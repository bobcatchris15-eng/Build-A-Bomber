class_name VisualBuilder
# Assembles the visual mesh tree for a placed module. Prefers authored .glb
# "kit" parts (tools/blender/build_meshes.py) for a detailed/greebled look,
# falling back to the original procedural primitives when no authored asset
# exists yet. Authored cylindrical/dome/leg/mast/tank/wheel parts are built
# along local Y (matching Godot's own CylinderMesh default axis), so every
# existing runtime rotation/positioning call below applies identically to
# both the authored and procedural mesh - only the `.mesh` source differs.

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const GlobalConfigScript = preload("res://scripts/global_config.gd")
const PartMaterialsScript = preload("res://scripts/part_materials.gd")

# mesh instance-id -> PartMaterials role, populated by _part() as assets load.
#
# This exists so material ROLES can be applied to all ~190 authored parts
# without touching the several hundred `_mesh_inst(_part("x"), colour)` call
# sites in this file. _part() is the single chokepoint every authored asset
# passes through and it is the only place that still knows the part's NAME -
# by the time _mesh_inst() sees it, it's an anonymous Mesh. So the name's
# classification is recorded here on the way past, keyed by the mesh resource
# MeshAssetLoader already caches (identity is stable for the process, so one
# entry per part, not one per instance).
#
# A mesh that isn't in here - every procedural BoxMesh/CylinderMesh fallback
# in this file - resolves to PartMaterials.DEFAULT_ROLE, which is still a
# properly finished metal rather than the flat matte plastic everything used
# to get. Nothing degrades; unclassified things just stay generic.
static var _part_roles: Dictionary = {}

static func _part(part_name: String) -> Mesh:
	var mesh: Mesh = MeshAssetLoader.get_part_mesh(part_name)
	if mesh != null:
		var id := mesh.get_instance_id()
		if not _part_roles.has(id):
			_part_roles[id] = PartMaterialsScript.role_for_part(part_name)
	return mesh

# Procedural running-gear slab (locomotion grounding fix). A flat dark-metal
# chassis that sits under the hull, sized to the hull's XZ with a small
# inset, with the wheels/treads/legs/screws/hover-pads mounting to its
# sides instead of to the hull's bare underside. Two real jobs at once:
#
# 1. Visual chassis: previously, side-mount locomotion (wheels/treads/etc.)
#    were placed straight against the hull skin, with the hull's authored
#    mesh often leaving a visible gap between the part and the hull surface
#    on hulls whose underside doesn't sit at the catalog bottom (per the
#    underside_y_bias hack). A real chassis reads as a deliberate
#    intermediary between hull and running gear.
# 2. Physics grounding: the CharacterBody3D's collider in battle_unit.gd
#    was sized to the hull only, so a wheeled unit sat on the hull's
#    underside with wheels dangling in midair (test arena: "vehicle slides
#    on its belly"). The unit's collider now extends to include the
#    running-gear height (see battle_unit.gd), and the running gear's
#    StaticBody3D carries the matching physics shape so designer-mode ray
#    casts and click-to-select also see a flat bottom, not a hull-bottom.
#
# Returns the StaticBody3D so callers can re-position or query it.
# The body is returned at the parent's local origin - callers are
# responsible for translating it to the right hull-local Y (conventionally
# -hull_size.y/2 - dimensions.y/2, so the chassis's TOP sits flush with
# the hull's underside and the chassis hangs BELOW the hull).
#
# collision_layer defaults to 1 (matching the designer-mode hull's own
# StaticBody3D layer, for click/raycast selection) but MUST be 0 when built
# under a battle_unit.gd CharacterBody3D: that body's collision_mask is 1
# ("Ground only"), so a layer-1 RunningGear sitting right at its own feet
# reads as terrain and it perpetually pushes itself off its own chassis -
# the battle-arena "constantly bouncing" bug. battle_unit.gd's own
# CollisionShape3D already provides the real physics collider in that case;
# this body's collider is purely for the designer-raycast/dimension-lookup
# use, so it can safely be collision-free there.
static func build_running_gear(parent_node: Node3D, dimensions: Vector3, base_color: Color, collision_layer: int = 1, type_id: String = "", hardpoints: Array = []) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.name = "RunningGear"
	body.collision_layer = collision_layer
	body.collision_mask = 0

	# Collider: matching box for grounding and raycast selection.
	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = dimensions
	col.shape = col_box
	body.add_child(col)

	parent_node.add_child(body)
	# Ground and hover types ride a real subframe; naval and airborne ones do
	# not (see build_subframe). An empty hardpoint list still yields a frame -
	# just a plain two-bay one - so a type that has not published its stations
	# yet degrades to something sensible rather than to nothing.
	if LocomotionLayoutScript.uses_subframe(type_id):
		build_subframe(body, dimensions, base_color, hardpoints)
	return body

static func _mesh_inst(mesh: Mesh, color: Color, emission: Color = Color(0, 0, 0, 0), emission_energy: float = 0.0, role_override: String = "") -> MeshInstance3D:
	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	# This used to build a bare StandardMaterial3D with nothing set but
	# albedo_color, which is Godot's default metallic 0.0 / roughness 1.0 -
	# i.e. matte plastic - for every barrel, lens, tyre and brass fitting
	# alike. See part_materials.gd for the full reasoning; the short version
	# is that the parts were differentiated by geometry and by paint colour
	# but not by SUBSTANCE, and materials are shared per role+tint so the
	# battle-side mesh merge still collapses them.
	var role := role_override
	if role == "" and mesh != null:
		role = _part_roles.get(mesh.get_instance_id(), PartMaterialsScript.DEFAULT_ROLE)
	inst.material_override = PartMaterialsScript.get_material(role, color, emission, emission_energy)
	return inst

# Plain albedo material for a procedurally-built primitive. The roster
# expansion's fallback paths each needed the same four lines of
# StandardMaterial3D setup, which is a lot of noise repeated ~15 times in
# what is only ever the "authored mesh is missing" branch.
static func _flat_mat(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	return mat

# --- Structural piece helpers ----------------------------------------------
# See the `structural_` branch of build_visual() for the design: parametric
# body, fixed-size authored hardware bolted onto it.

# Every authored hardware instance is named with this prefix. module_placer.gd
# repaints a structural piece's meshes with the faction hull shader so the
# piece matches the vehicle it's bolted to; that pass skips anything named
# with this prefix, which is what keeps the fasteners reading as bare steel
# against faction-liveried plate instead of the whole thing turning into one
# flat shader.
const LocomotionLayoutScript = preload("res://scripts/locomotion_layout.gd")
const HARDWARE_PREFIX := "Hardware_"

# Names of the pivot nodes battle_unit.gd spins. Locomotion animation has always
# worked by looking a pivot up BY NAME, but the names were string literals
# duplicated across the builder and the animator, and three types
# (wheels, tracked_treads, fixed_wing_engine) simply never got a pivot - so a
# rolling tank's treads and road wheels sat frozen while the helicopter parked
# next to it span its rotor forever. Declared here so the two files agree.
#
# Godot uniquifies duplicate sibling names ("WheelSpin", "WheelSpin2", ...),
# which is why the animator matches these as a PREFIX rather than exactly.
const SPIN_PIVOT_WHEEL := "WheelSpin"
const SPIN_PIVOT_TREAD := "TreadSpin"
const SPIN_PIVOT_TURBINE := "TurbineFan"
const HARDWARE_COLOR := Color(0.27, 0.27, 0.30)

static var _hardware_mat_cache: StandardMaterial3D = null

static func _hardware_mat() -> StandardMaterial3D:
	if _hardware_mat_cache == null:
		_hardware_mat_cache = StandardMaterial3D.new()
		_hardware_mat_cache.albedo_color = HARDWARE_COLOR
		# Harder and shinier than the painted plate it sits on - the contrast
		# between bare fastener and liveried structure is the whole reason the
		# faction repaint skips these.
		_hardware_mat_cache.metallic = 0.85
		_hardware_mat_cache.roughness = 0.35
	return _hardware_mat_cache

static func _structural_body_mat(color: Color) -> StandardMaterial3D:
	# Routed through the shared role palette rather than a hand-rolled
	# StandardMaterial3D so structural plate gets the same triplanar wear
	# texture everything else now has. It matters most in BATTLE: the Design
	# Lab repaints these with the faction hull shader (module_placer), but
	# blueprint_manager's battle reconstruction doesn't, so on the field this
	# is the material a structural piece actually wears - and unpainted it
	# was a flat matte slab next to hulls carrying a full wear/grime shader.
	return PartMaterialsScript.get_material("painted", color)

# Instances one authored hardware part at its TRUE authored size. There is
# deliberately no scale argument: the whole point of the split is that this
# geometry never stretches with the body. Silently no-ops if the .glb is
# missing so a fresh checkout that hasn't run the Blender build yet still
# renders the bodies rather than erroring out mid-build.
#
# `uniform_scale` is the ONE scaling allowance, and it is uniform on purpose:
# stretching authored hardware anisotropically is the smearing this whole
# design exists to prevent, but scaling it evenly just makes a bigger version
# of the same object with every proportion intact. Used for the handful of
# details that are crew-scale references rather than fasteners - a dome hatch
# authored at fastener size reads as a coin on a 2.5-unit cupola.
static func _hardware(parent_node: Node3D, part_name: String, pos: Vector3, rot: Vector3, uniform_scale: float = 1.0) -> MeshInstance3D:
	var mesh = _part(part_name)
	if mesh == null:
		return null
	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	# ONE shared material across every hardware instance, not one per instance
	# like _mesh_inst() would make. A stretched block can carry 60 of these,
	# and bake_module_visual() groups its merge by material IDENTITY - 60
	# separate-but-identical StandardMaterial3Ds would defeat the merge
	# entirely and ship 60 draw calls per structural piece into a battle.
	inst.material_override = _hardware_mat()
	inst.position = pos
	inst.rotation = rot
	if not is_equal_approx(uniform_scale, 1.0):
		inst.scale = Vector3.ONE * uniform_scale
	parent_node.add_child(inst)
	# Named AFTER add_child, and with an explicit unique suffix. Setting a
	# colliding name on a not-yet-parented node makes Godot 4 throw the name
	# away entirely and fall back to a generated "@MeshInstance3D@7" - so with
	# the obvious ordering, only the FIRST of each hardware kind kept its name
	# and every other one silently lost the HARDWARE_PREFIX that the faction-
	# repaint exemption in module_placer keys off.
	inst.name = "%s%s_%d" % [HARDWARE_PREFIX, part_name, parent_node.get_child_count()]
	return inst

# How many fixed-size details fit along `span` at roughly `spacing` apart.
# This is the function that makes stretching work: it is the COUNT that grows
# with the body, never the size of the individual detail.
static func _hardware_count(span: float, spacing: float, lo: int = 1, hi: int = 20) -> int:
	return clampi(int(round(abs(span) / max(0.01, spacing))), lo, hi)

# Yaw that points a corner bracket's two arms inward along the faces meeting
# at corner (sx, sz). The bracket is authored with arms along +X and -Z.
static func _corner_yaw(sx: float, sz: float) -> float:
	if sx > 0.0 and sz > 0.0: return PI / 2.0
	if sx < 0.0 and sz > 0.0: return PI
	if sx < 0.0 and sz < 0.0: return -PI / 2.0
	return 0.0

# Tie-down grid across a deck surface at height `y`. Spacing is fixed, so a
# bigger deck gets more tie-downs rather than bigger ones.
static func _deck_tie_downs(parent_node: Node3D, base_size: Vector3, y: float, spacing: float = 0.95) -> void:
	var nx = _hardware_count(base_size.x, spacing, 1, 8)
	var nz = _hardware_count(base_size.z, spacing, 1, 8)
	for i in range(nx):
		for j in range(nz):
			var tx = (float(i) + 0.5) / float(nx) - 0.5
			var tz = (float(j) + 0.5) / float(nz) - 0.5
			_hardware(parent_node, "struct_tie_down",
				Vector3(tx * base_size.x * 0.82, y, tz * base_size.z * 0.82), Vector3.ZERO)

# Shared beam dressing for the girder and the I-beam: splice collars at fixed
# stations along the run, and a bolted end cap on each end. The collar's ring
# axis is authored along -Z (Blender +Y), which is already the beam's run, so
# no rotation is needed on those.
static func _beam_hardware(parent_node: Node3D, base_size: Vector3) -> void:
	var collars = _hardware_count(base_size.z, 1.05, 1, 8)
	for i in range(collars):
		var t = (float(i) + 0.5) / float(collars) - 0.5
		_hardware(parent_node, "struct_splice_collar",
			Vector3(0, base_size.y / 2.0, t * base_size.z * 0.86), Vector3.ZERO)
	for sz in [-1.0, 1.0]:
		# The cap is authored facing -Z; the +Z end needs a half turn.
		_hardware(parent_node, "struct_beam_end_cap",
			Vector3(0, base_size.y / 2.0, sz * base_size.z * 0.5),
			Vector3(0, 0.0 if sz < 0.0 else PI, 0))

# Scales a fixed-dimension authored part's Node3D to hit a target Godot-space
# (width, height, depth) size, given the part's own authored base dimensions.
static func _fit_scale(target: Vector3, authored_base: Vector3) -> Vector3:
	return Vector3(
		target.x / authored_base.x if authored_base.x > 0.0 else 1.0,
		target.y / authored_base.y if authored_base.y > 0.0 else 1.0,
		target.z / authored_base.z if authored_base.z > 0.0 else 1.0
	)

# Which monolithic authored parts get their mesh wrapped in a named animation
# pivot, and under what name - see the pivot block in build_visual() below.
#
# Only types where rotating the WHOLE module is the correct motion are listed.
# rotary_cannon is deliberately absent: its "BarrelCluster" pivot is meant to
# spin the barrel ring while the mount stays put, and the authored mesh fuses
# barrels and mount into one object - wrapping it would spin the entire gun on
# its side, which is worse than leaving it static. That one needs the barrels
# authored as a separate mesh before it can animate.
const MONOLITHIC_ANIMATION_PIVOTS := {
	"helicopter_rotors": "RotorBlades",
	"ornithopter_wing": "WingPivot",
	"naval_propeller": "PropBlades",
	"ship_screw": "PropBlades",
	"propeller_prop": "PropBlades",
	"pusher_prop": "PropBlades",
	"paddle_wheel": "PropBlades",
}

const LOCOMOTION_MODULAR_TYPES := {
	"wheels": true, "helicopter_rotors": true, "tracked_treads": true, "legs": true,
	"hover_engine": true, "fixed_wing_engine": true, "ornithopter_wing": true,
	"naval_propeller": true, "buoyant_envelope": true, "screw_drive": true,
	"half_track": true, "rocker_bogie": true, "air_cushion_skirt": true,
	"anti_grav_plate": true, "hydrofoil": true, "water_jet": true, "pontoon_wheels": true,
}

# Firing elevation applied as a PIVOT ROTATION for the two weapons whose barrels
# used to have their elevation baked into the mesh. Must match
# ASSEMBLY_ELEVATION_DEG in tools/blender/build_artillery.py / build_mortar.py -
# those scripts author the tube along -Z at zero elevation and record here the
# angle the mount is supposed to restore.
const ARTILLERY_ELEVATION_DEG := 35.0
const MORTAR_ELEVATION_DEG := 60.0
const NAPALM_ELEVATION_DEG := 55.0

# Anti-materiel rifle assembly stations, MEASURED from the authored .glb
# AABBs rather than estimated. amr_breech's front face sits at z = -0.168 and
# amr_barrel spans z = -1.040 .. 0.0 with its origin on its own rear face, so
# the barrel mounts exactly at the breech's face and the muzzle brake belongs
# one authored barrel-length beyond it. These were estimated at first and the
# barrel hung 0.11 units clear of the breech in mid-air; re-measure if the
# meshes change.
const AMR_BREECH_FRONT_Z := -0.168
const AMR_BARREL_LEN := 1.040
const AMR_BUFFER_Z := 0.42

# Same story for the two receivers that share the mk19/autocannon assembly
# branch - measured off their own meshes, not shared between them.
const MK19_RECEIVER_FRONT_Z := -0.16
const AUTOCANNON_RECEIVER_FRONT_Z := -0.102
const AUTOCANNON_DRUM_FLOOR := 0.262
const AUTOCANNON_DRUM_Z := 0.11

# Energy-bracket stations, measured from the exported AABBs.
const ARC_BODY_FRONT_Z := -0.040
const MICROWAVE_BODY_FRONT_Z := -0.080
const LANCE_BREECH_FRONT_Z := -0.130
const LANCE_BREECH_REAR_Z := 0.160

# Indirect-fire and missile stations, measured from the exported AABBs.
const SPIGOT_BREECH_FRONT_Z := -0.060
const ROCKET_CRADLE_FRONT_Z := -0.070
const AA_RECEIVER_FRONT_Z := -0.082

# The six guided launchers share a pedestal and an assembly path. Each entry
# names the body that gives the launcher its identity, the round it carries,
# how many it carries by default (1 = a single centreline round), the tweak
# that scales that round, the measured front face of its body, and how far
# the whole assembly is canted up. Kept as data rather than as six
# near-identical match arms.
const MISSILE_LAUNCHER_PARTS := {
	"hypervelocity_missile": {"body": "hvm_body", "round": "hvm_canister", "default_count": 2,
		"scale_tweak": "seeker_size", "front_z": -0.064, "cant_deg": 6.0, "tint": Color(0.24, 0.25, 0.22)},
	"sam_launcher": {"body": "sam_body", "round": "sam_missile", "default_count": 2,
		"scale_tweak": "radar_dish", "front_z": -0.035, "cant_deg": 34.0, "tint": Color(0.72, 0.72, 0.70)},
	"loitering_munition": {"body": "loiter_body", "round": "loiter_tube", "default_count": 2,
		"scale_tweak": "seeker_size", "front_z": -0.098, "cant_deg": 62.0, "tint": Color(0.25, 0.27, 0.23)},
	"anti_radiation_missile": {"body": "arm_body", "round": "arm_missile", "default_count": 2,
		"scale_tweak": "seeker_size", "front_z": -0.106, "cant_deg": 14.0, "tint": Color(0.34, 0.36, 0.33)},
	"bunker_buster": {"body": "bb_body", "round": "bb_penetrator", "default_count": 1,
		"scale_tweak": "warhead_size", "front_z": -0.080, "cant_deg": 46.0, "tint": Color(0.19, 0.20, 0.21)},
	"cruise_missile": {"body": "cruise_body", "round": "cruise_container", "default_count": 1,
		"scale_tweak": "warhead_size", "front_z": -0.035, "cant_deg": 26.0, "tint": Color(0.29, 0.31, 0.27)},
}

const MODULAR_ASSEMBLY_TYPES := {
	"basic_cannon": true, "heavy_machine_gun": true, "rotary_cannon": true, "gauss_railgun": true,
	"artillery": true, "mortar_array": true, "guided_missile": true, "missile_pod": true,
	"cluster_dispenser": true, "flamethrower": true, "tesla_coil": true, "ion_cannon": true,
	"heavy_laser": true, "plasma_lobber": true, "ciws": true, "pd_laser": true, "flak_cannon": true,
	"smoke_discharger": true,
	"mk19_grenade_launcher": true, "recoilless_rifle": true, "coil_gun": true,
	"autocannon": true, "napalm_mortar": true, "mine_layer": true, "ballista": true,
	"anti_materiel_rifle": true,
	"arc_projector": true, "microwave_emitter": true, "particle_lance": true,
	"spigot_mortar": true, "rocket_artillery": true,
	"hypervelocity_missile": true, "sam_launcher": true, "loitering_munition": true,
	"anti_radiation_missile": true, "bunker_buster": true, "cruise_missile": true,
	"chaff_dispenser": true, "laser_dazzler": true, "aps_interceptor": true,
	"aa_autocannon": true, "jammer_mast": true, "sentry_deployer": true,
	"sensor_beacon_launcher": true, "decoy_projector": true,
	"wheels": true, "helicopter_rotors": true, "tracked_treads": true, "legs": true,
	"hover_engine": true, "fixed_wing_engine": true, "ornithopter_wing": true,
	"naval_propeller": true, "buoyant_envelope": true, "screw_drive": true,
	"half_track": true, "rocker_bogie": true, "air_cushion_skirt": true,
	"anti_grav_plate": true, "hydrofoil": true, "water_jet": true, "pontoon_wheels": true,
	"structural_block": true, "structural_dome": true, "structural_slab": true,
	"structural_wedge": true, "structural_girder": true, "structural_i_beam": true
}

static func _repeat_along_axis(parent: Node3D, count: int, spacing: float, axis_vec: Vector3, builder_func: Callable):
	var start_pos = -axis_vec * ((count - 1) * spacing / 2.0)
	for i in range(count):
		var pos = start_pos + axis_vec * (i * spacing)
		builder_func.call(parent, pos, i)

static func _ring_of(parent: Node3D, count: int, radius: float, builder_func: Callable):
	for i in range(count):
		var angle = i * (TAU / max(1, count))
		var pos = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		builder_func.call(parent, pos, angle, i)

static func build_visual(type_id: String, parent_node: Node3D, base_size: Vector3, base_color: Color, tweaks: Dictionary = {}):
	# Clear any existing visual children. remove_child() BEFORE queue_free() -
	# queue_free() alone doesn't actually detach the node until end-of-frame,
	# so a caller that immediately calls build_visual() again on the same
	# parent (blueprint_manager.gd's reconstruct_vehicle() does exactly this:
	# build_visual() then rebuild_visual() back to back, same frame) would
	# have its freshly-created "RotorBlades"/"HoverRingMid"/"LegSwing" pivot
	# collide in name with the still-present old one and get silently
	# auto-renamed by add_child() - breaking every by-name animation lookup
	# for any vehicle reconstructed from a blueprint (Skirmish, Test Range,
	# defense buildings). remove_child() first frees the name immediately;
	# queue_free() still handles the actual node deletion safely.
	for child in parent_node.get_children():
		if child is StaticBody3D:
			continue
		parent_node.remove_child(child)
		child.queue_free()

	# Try to load a monolithic authored mesh for this entire module first (modular sub-part assemblies bypass this)
	var monolithic_mesh = _part(type_id) if not MODULAR_ASSEMBLY_TYPES.has(type_id) else null
	if monolithic_mesh:
		var inst = _mesh_inst(monolithic_mesh, base_color)
		if type_id == "basic_cannon":
			inst.rotation.y = 0.0
		else:
			inst.rotation.y = deg_to_rad(90.0) # TripoSG native orientation offset
		# We scale the mesh uniformly so its largest dimension matches the largest dimension
		# defined in base_size. This prevents squishing/stretching while ensuring it fits the scale curve.
		var aabb = monolithic_mesh.get_aabb()
		var max_target = max(base_size.x, max(base_size.y, base_size.z))
		var max_authored = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		var fit_scale = max_target / max_authored if max_authored > 0.0 else 1.0
		inst.scale = Vector3(fit_scale, fit_scale, fit_scale) * _monolithic_tweak_scale(type_id, tweaks, inst.rotation)

		# Mounting-gap fix: the old `Vector3(0, base_size.y / 2.0, 0)` assumed
		# every authored mesh was perfectly centered on its own origin AND
		# that its natural (post-scale) height exactly matched the catalog's
		# target height - true for almost none of them (checked via a
		# headless AABB dump across several parts: most are already
		# bottom-anchored near their own local origin already, e.g.
		# sensor_suite's aabb.position.y is -0.025 against a 1.32-unit tall
		# mesh, not -0.66; a few are height-centered but their largest
		# dimension - the one fit_scale actually matches - is a different
		# axis). That mismatch left the mesh's REAL bottom floating above
		# the module's local origin (where _place_weapon() flush-mounts it
		# against the hull surface) by anywhere from a few cm up to over a
		# meter for sensor_suite's mast - "noticeable gaps beneath most
		# modules." Using the mesh's own actual AABB minimum Y (scaled by
		# the same fit_scale) instead puts its real bottom exactly on the
		# module's origin regardless of how the source mesh happens to be
		# centered.
		inst.position = Vector3(0, -aabb.position.y * fit_scale, 0)

		# Animation pivot. battle_unit.gd and auto_weapon.gd animate moving
		# parts by looking up a child node BY NAME ("WingPivot", "RotorBlades",
		# "PropBlades") - names the procedural build creates. A monolithic
		# authored mesh has no such child, so those lookups came back null and
		# the motion silently stopped: ornithopter wings in particular never
		# flapped at all, since that arm isn't behind the
		# enable_animated_monolithic_parts flag the others sit behind.
		#
		# Wrap the mesh in a correctly-named pivot rather than bolting a second
		# procedural copy of the blades on top (what the flag does) - the
		# authored mesh already sculpts them, so a second copy would double the
		# geometry, which is exactly the caveat _attach_moving_parts() warns
		# about. A WRAPPER, not a rename: the animation writes whole rotations
		# onto the pivot (pivot.rotation.x = ...), which would otherwise
		# clobber the mesh's own orientation offset.
		var pivot_name = MONOLITHIC_ANIMATION_PIVOTS.get(type_id, "")
		if pivot_name != "":
			var pivot = Node3D.new()
			pivot.name = pivot_name
			pivot.add_child(inst)
			parent_node.add_child(pivot)
		else:
			parent_node.add_child(inst)
		# Feature-flagged (GlobalConfig.enable_animated_monolithic_parts,
		# default off): attach the same named moving-part pivots (barrels,
		# rotors) the procedural fallback below builds, so a detailed
		# monolithic body doesn't lose animation just because it replaced
		# the procedural base mesh. Off by default so this can be A/B tested
		# without changing today's shipped behavior.
		if GlobalConfigScript.enable_animated_monolithic_parts:
			_attach_moving_parts(type_id, parent_node, base_size, base_color, tweaks)
		return

	# Locomotion dispatch: handled BEFORE the weapon if/elif/else chain below,
	# not after it. Every locomotion type_id is in MODULAR_ASSEMBLY_TYPES (so
	# it skips the monolithic-mesh branch above), but none of them ever
	# matched any of the weapon-specific `if type_id == "..."` branches in
	# that chain either - so every locomotion instance fell through to the
	# chain's final `else: Fallback: Simple box mesh for armor and basic
	# parts`, which unconditionally added a plain uncolored BoxMesh sized to
	# the catalog's flat base_size (not scaled by any tweak) at the module's
	# mount point, BEFORE _build_wheels()/etc. below ever ran - a second,
	# unwanted, unchamfered box baked into every locomotion instance ("box
	# outboard of them and above, no chamfered edges" - visually indistinguishable
	# from a failed/fallback mount). The dispatch below also wasn't passing
	# `tweaks` through to most _build_X() calls, so wheel_size/blade_length/
	# etc. tweaks never reached the actual sub-part geometry at all. Returning
	# here after the real per-type build fixes both: no more stray fallback
	# box, and every per-instance tweak now actually reaches its _build_X().
	if LOCOMOTION_MODULAR_TYPES.has(type_id):
		match type_id:
			"wheels": _build_wheels(parent_node, base_size, base_color, tweaks)
			"tracked_treads": _build_tracked_treads(parent_node, base_size, base_color, tweaks)
			"helicopter_rotors": _build_helicopter_rotors(parent_node, base_size, base_color, tweaks)
			"hover_engine": _build_hover_engine(parent_node, base_size, base_color, tweaks)
			"legs": _build_legs(parent_node, base_size, base_color, tweaks)
			"fixed_wing_engine": _build_fixed_wing_engine(parent_node, base_size, base_color, tweaks)
			"ornithopter_wing": _build_ornithopter_wing(parent_node, base_size, base_color, tweaks)
			"naval_propeller": _build_naval_propeller(parent_node, base_size, base_color, tweaks)
			"buoyant_envelope": _build_buoyant_envelope(parent_node, base_size, base_color, tweaks)
			"screw_drive": _build_screw_drive(parent_node, base_size, base_color, tweaks)
			"half_track": _build_half_track(parent_node, base_size, base_color, tweaks)
			"rocker_bogie": _build_rocker_bogie(parent_node, base_size, base_color, tweaks)
			"air_cushion_skirt": _build_air_cushion_skirt(parent_node, base_size, base_color, tweaks)
			"anti_grav_plate": _build_anti_grav_plate(parent_node, base_size, base_color, tweaks)
			"hydrofoil": _build_hydrofoil(parent_node, base_size, base_color, tweaks)
			"water_jet": _build_water_jet(parent_node, base_size, base_color, tweaks)
			"pontoon_wheels": _build_pontoon_wheels(parent_node, base_size, base_color, tweaks)
		_apply_tweak_deformations(type_id, parent_node, tweaks, base_size)

		return


	if type_id == "basic_cannon":
		var b_count = int(tweaks.get("barrel_count", 1.0))
		b_count = clamp(b_count, 1, 4)
		var caliber = tweaks.get("caliber", 1.0)
		var length = tweaks.get("barrel_length", 1.0)

		# 1. MOUNT / PINTLE (m3_pintle_mount.glb)
		var base_w_scale = (1.0 + (b_count - 1) * 0.35) * caliber
		var pintle_mesh = _part("m3_pintle_mount")
		if not pintle_mesh:
			pintle_mesh = _part("pintle_mount")
		var pintle: MeshInstance3D
		var pintle_h = base_size.y * 0.45 * caliber
		if pintle_mesh:
			pintle = _mesh_inst(pintle_mesh, base_color.darkened(0.3))
			pintle.scale = Vector3(base_w_scale, caliber, caliber)
			pintle.position = Vector3(0, 0, 0)
		else:
			pintle = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(base_size.x * 1.2 * base_w_scale, pintle_h, base_size.x * 1.2 * caliber)
			pintle.mesh = p_box
			var p_mat = StandardMaterial3D.new()
			p_mat.albedo_color = base_color.darkened(0.3)
			pintle.material_override = p_mat
			pintle.position = Vector3(0, p_box.size.y / 2.0, 0)
		parent_node.add_child(pintle)

		# 2. ACTION / BREECH & BARREL (Per barrel count 1 to 4)
		var breech_mesh = _part("m3_action_breech")
		if not breech_mesh:
			breech_mesh = _part("howitzer_breech")
		var barrel_mesh = _part("m3_barrel")
		if not barrel_mesh:
			barrel_mesh = _part("barrel_standard")

		var x_spacing = 0.28 * caliber
		var start_x = -((b_count - 1) * x_spacing) / 2.0
		var trunnion_y = 0.26 * caliber

		for i in range(b_count):
			var cur_x = start_x + i * x_spacing

			# 2A. ACTION / BREECH
			var breech: MeshInstance3D
			if breech_mesh:
				breech = _mesh_inst(breech_mesh, Color(0.22, 0.24, 0.26))
				breech.scale = Vector3(caliber, caliber, caliber)
				breech.position = Vector3(cur_x, trunnion_y, 0.0)
			else:
				breech = MeshInstance3D.new()
				var b_box = BoxMesh.new()
				b_box.size = Vector3(0.22 * caliber, 0.26 * caliber, 0.38 * caliber)
				breech.mesh = b_box
				var b_mat = StandardMaterial3D.new()
				b_mat.albedo_color = Color(0.22, 0.24, 0.26)
				breech.material_override = b_mat
				breech.position = Vector3(cur_x, trunnion_y, 0.0)
			parent_node.add_child(breech)

			# 2B. BARREL (Mounted at breech muzzle port, scaling with caliber and barrel_length)
			var barrel: MeshInstance3D
			if barrel_mesh:
				barrel = _mesh_inst(barrel_mesh, Color(0.18, 0.19, 0.21))
				barrel.scale = Vector3(caliber, caliber, length * caliber)
				barrel.position = Vector3(cur_x, trunnion_y, -0.05 * caliber)
			else:
				barrel = MeshInstance3D.new()
				var b_cyl = CylinderMesh.new()
				b_cyl.top_radius = 0.045 * caliber
				b_cyl.bottom_radius = 0.065 * caliber
				b_cyl.height = 1.25 * length
				barrel.mesh = b_cyl
				var b_mat = StandardMaterial3D.new()
				b_mat.albedo_color = Color(0.18, 0.19, 0.21)
				barrel.material_override = b_mat
				barrel.position = Vector3(cur_x, trunnion_y, -(1.25 * length / 2.0) - 0.05 * caliber)
				barrel.rotation = Vector3(PI / 2, 0, 0)
			parent_node.add_child(barrel)

	elif type_id == "heavy_machine_gun":
		var multi_b = bool(tweaks.get("multi_barrel", false))
		var drum_scale = tweaks.get("drum_size", 1.0)
		var caliber = tweaks.get("caliber", 1.0)
		var length = tweaks.get("barrel_length", 1.0)
		var b_count = 2 if multi_b else 1

		# 1. PINTLE MOUNT (hmg_pintle_mount.glb)
		var pintle_mesh = _part("hmg_pintle_mount")
		if not pintle_mesh:
			pintle_mesh = _part("pintle_mount")
		var pintle: MeshInstance3D
		var base_w_scale = (1.4 if multi_b else 1.0) * caliber
		if pintle_mesh:
			pintle = _mesh_inst(pintle_mesh, base_color.darkened(0.2))
			pintle.scale = Vector3(base_w_scale, caliber, caliber)
			pintle.position = Vector3(0, 0, 0)
		else:
			pintle = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(0.28 * base_w_scale, 0.22 * caliber, 0.28 * caliber)
			pintle.mesh = p_box
			var p_mat = StandardMaterial3D.new()
			p_mat.albedo_color = base_color.darkened(0.2)
			pintle.material_override = p_mat
			pintle.position = Vector3(0, 0.11 * caliber, 0)
		parent_node.add_child(pintle)

		# 2. RECEIVER(S) & BARREL(S)
		var rec_mesh = _part("hmg_receiver")
		var barrel_mesh = _part("hmg_barrel")
		var trunnion_y = 0.22 * caliber
		var x_spacing = 0.22 * caliber
		var start_x = -((b_count - 1) * x_spacing) / 2.0

		for i in range(b_count):
			var cur_x = start_x + i * x_spacing

			# 2A. RECEIVER
			var receiver: MeshInstance3D
			if rec_mesh:
				receiver = _mesh_inst(rec_mesh, Color(0.20, 0.22, 0.24))
				receiver.scale = Vector3(caliber, caliber, caliber)
				receiver.position = Vector3(cur_x, trunnion_y, 0.0)
			else:
				receiver = MeshInstance3D.new()
				var r_box = BoxMesh.new()
				r_box.size = Vector3(0.14 * caliber, 0.16 * caliber, 0.34 * caliber)
				receiver.mesh = r_box
				var r_mat = StandardMaterial3D.new()
				r_mat.albedo_color = Color(0.20, 0.22, 0.24)
				receiver.material_override = r_mat
				receiver.position = Vector3(cur_x, trunnion_y, -0.06 * caliber)
			parent_node.add_child(receiver)

			# 2B. BARREL (Mounted at front of receiver socket, scaling with caliber and barrel_length)
			var barrel: MeshInstance3D
			if barrel_mesh:
				barrel = _mesh_inst(barrel_mesh, Color(0.15, 0.16, 0.18))
				barrel.scale = Vector3(caliber, caliber, length * caliber)
				barrel.position = Vector3(cur_x, trunnion_y, 0.0)
			else:
				barrel = MeshInstance3D.new()
				var b_cyl = CylinderMesh.new()
				b_cyl.top_radius = 0.03 * caliber
				b_cyl.bottom_radius = 0.04 * caliber
				b_cyl.height = 0.85 * length
				barrel.mesh = b_cyl
				var b_mat = StandardMaterial3D.new()
				b_mat.albedo_color = Color(0.15, 0.16, 0.18)
				barrel.material_override = b_mat
				barrel.position = Vector3(cur_x, trunnion_y, -0.425 * length)
				barrel.rotation = Vector3(PI / 2, 0, 0)
			parent_node.add_child(barrel)

		# 3. SIDE AMMO DRUM (hmg_ammo_drum.glb) - Deformed by drum_size slider!
		var drum_mesh = _part("hmg_ammo_drum")
		if not drum_mesh:
			drum_mesh = _part("ammo_drum")
		var drum: MeshInstance3D
		var drum_x = start_x - 0.07 * caliber
		var total_drum_s = drum_scale * caliber
		if drum_mesh:
			drum = _mesh_inst(drum_mesh, Color(0.25, 0.28, 0.25))
			drum.scale = Vector3(total_drum_s, total_drum_s, total_drum_s)
			drum.position = Vector3(drum_x, trunnion_y, -0.06 * caliber)
		else:
			drum = MeshInstance3D.new()
			var drum_cyl = CylinderMesh.new()
			drum_cyl.top_radius = 0.13 * total_drum_s
			drum_cyl.bottom_radius = 0.13 * total_drum_s
			drum_cyl.height = 0.14 * total_drum_s
			drum.mesh = drum_cyl
			var d_mat = StandardMaterial3D.new()
			d_mat.albedo_color = Color(0.25, 0.28, 0.25)
			drum.material_override = d_mat
			drum.position = Vector3(drum_x - 0.10 * caliber, trunnion_y, -0.06 * caliber)
			drum.rotation = Vector3(0, 0, PI / 2)
		parent_node.add_child(drum)

	elif type_id == "rotary_cannon":
		var caliber = tweaks.get("caliber", 1.0)
		var length = tweaks.get("barrel_length", 1.0)
		var b_count = int(tweaks.get("barrel_count", 6.0))
		b_count = clamp(b_count, 3, 9)
		var motor_s = tweaks.get("motor_size", 1.0)

		# 1. PINTLE MOUNT (rotary_pintle_mount.glb)
		var pintle_mesh = _part("rotary_pintle_mount")
		if not pintle_mesh:
			pintle_mesh = _part("pintle_mount")
		var pintle: MeshInstance3D
		if pintle_mesh:
			pintle = _mesh_inst(pintle_mesh, base_color.darkened(0.2))
			pintle.scale = Vector3(caliber, caliber, caliber)
			pintle.position = Vector3(0, 0, 0)
		else:
			pintle = MeshInstance3D.new()
			var p_box = BoxMesh.new()
			p_box.size = Vector3(0.36 * caliber, 0.24 * caliber, 0.36 * caliber)
			pintle.mesh = p_box
			var p_mat = StandardMaterial3D.new()
			p_mat.albedo_color = base_color.darkened(0.2)
			pintle.material_override = p_mat
			pintle.position = Vector3(0, 0.12 * caliber, 0)
		parent_node.add_child(pintle)

		# 2. ROTOR HOUSING & DRIVE MOTOR (rotary_housing.glb)
		var trunnion_y = 0.24 * caliber
		var housing_mesh = _part("rotary_housing")
		if not housing_mesh:
			housing_mesh = _part("rotary_jacket")
		var housing: MeshInstance3D
		if housing_mesh:
			housing = _mesh_inst(housing_mesh, Color(0.22, 0.24, 0.26))
			housing.scale = Vector3(caliber, caliber, motor_s * caliber)
			housing.position = Vector3(0, trunnion_y, 0)
		else:
			housing = MeshInstance3D.new()
			var h_cyl = CylinderMesh.new()
			h_cyl.top_radius = 0.20 * caliber
			h_cyl.bottom_radius = 0.20 * caliber
			h_cyl.height = 0.35 * motor_s * caliber
			housing.mesh = h_cyl
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.22, 0.24, 0.26)
			housing.material_override = h_mat
			housing.position = Vector3(0, trunnion_y, 0)
			housing.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(housing)

		# 3. SPINNING BARREL CLUSTER (under "BarrelCluster" pivot for spin animation)
		_attach_rotary_barrels(parent_node, base_size, tweaks)

	elif type_id == "gauss_railgun":
		var caliber = tweaks.get("caliber", 1.0)
		var length = tweaks.get("rail_length", 1.0)

		# 1. HEAVY CASEMATE HULL MOUNT (railgun_casemate_mount.glb) - Non-traversing hull citadel
		var mount_mesh = _part("railgun_casemate_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(caliber, caliber, caliber)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.58 * caliber, 0.26 * caliber, 0.68 * caliber)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.13 * caliber, 0)
		parent_node.add_child(mount)

		# 2. CAPACITOR / BREECH HOUSING (railgun_capacitor_housing.glb)
		var trunnion_y = 0.24 * caliber
		var cap_mesh = _part("railgun_capacitor_housing")
		var capacitor: MeshInstance3D
		if cap_mesh:
			capacitor = _mesh_inst(cap_mesh, Color(0.18, 0.20, 0.22))
			capacitor.scale = Vector3(caliber, caliber, caliber)
			capacitor.position = Vector3(0, trunnion_y, 0.0)
		else:
			capacitor = MeshInstance3D.new()
			var c_box = BoxMesh.new()
			c_box.size = Vector3(0.28 * caliber, 0.22 * caliber, 0.42 * caliber)
			capacitor.mesh = c_box
			var c_mat = StandardMaterial3D.new()
			c_mat.albedo_color = Color(0.18, 0.20, 0.22)
			capacitor.material_override = c_mat
			capacitor.position = Vector3(0, trunnion_y, -0.12 * caliber)
		parent_node.add_child(capacitor)

		# 3. ACCELERATOR RAILS (railgun_rails.glb) - Deformed ONLY by rail_length and caliber!
		var rail_mesh = _part("railgun_rails")
		var rails: MeshInstance3D
		if rail_mesh:
			rails = _mesh_inst(rail_mesh, Color(0.15, 0.16, 0.18), Color.BLUE_VIOLET, 1.2)
			rails.scale = Vector3(caliber, caliber, length * caliber)
			rails.position = Vector3(0, trunnion_y, 0.0)
		else:
			rails = MeshInstance3D.new()
			var r_box = BoxMesh.new()
			r_box.size = Vector3(0.16 * caliber, 0.20 * caliber, 1.40 * length)
			rails.mesh = r_box
			var r_mat = StandardMaterial3D.new()
			r_mat.albedo_color = Color(0.15, 0.16, 0.18)
			r_mat.emission_enabled = true
			r_mat.emission = Color.BLUE_VIOLET
			r_mat.emission_energy_multiplier = 1.2
			rails.material_override = r_mat
			rails.position = Vector3(0, trunnion_y, -(1.40 * length / 2.0))
		parent_node.add_child(rails)

	elif type_id == "artillery":
		var b_count = int(tweaks.get("barrel_count", 1.0))
		b_count = clamp(b_count, 1, 2)
		var caliber = tweaks.get("caliber", 1.0) * 2.0  # Doubled visual size per user request
		var length = tweaks.get("barrel_length", 1.0)

		# 1. HEAVY CASEMATE HULL MOUNT (artillery_casemate_mount.glb)
		var base_w_scale = (1.0 + (b_count - 1) * 0.45) * caliber
		var mount_mesh = _part("artillery_casemate_mount")
		if not mount_mesh:
			mount_mesh = _part("railgun_casemate_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(base_w_scale, caliber, caliber)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.64 * base_w_scale, 0.28 * caliber, 0.72 * caliber)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.14 * caliber, 0)
		parent_node.add_child(mount)

		# 2. BREECH & BARREL (1 or 2 heavy artillery barrels side-by-side)
		var breech_mesh = _part("artillery_breech")
		var barrel_mesh = _part("artillery_barrel")
		var trunnion_y = 0.26 * caliber
		var x_spacing = 0.36 * caliber
		var start_x = -((b_count - 1) * x_spacing) / 2.0

		for i in range(b_count):
			var cur_x = start_x + i * x_spacing

			# ELEVATION PIVOT. artillery_barrel.glb / artillery_breech.glb are now
			# authored along -Z at zero elevation (see build_artillery.py's
			# ELEV_ANGLE); the gun's 35-degree elevation is applied here instead.
			#
			# This is what makes the barrel_length tweak work: the barrel's own
			# local -Z is the tube axis, so scaling its Z lengthens the tube. When
			# the elevation was baked into the mesh, the long axis was a tilted
			# Y/Z diagonal and scaling Z sheared the gun sideways.
			var elev_pivot = Node3D.new()
			elev_pivot.name = "ElevationPivot" if i == 0 else "ElevationPivot%d" % i
			elev_pivot.position = Vector3(cur_x, trunnion_y, 0.0)
			elev_pivot.rotation = Vector3(deg_to_rad(ARTILLERY_ELEVATION_DEG), 0, 0)
			parent_node.add_child(elev_pivot)

			# 2A. BREECH BLOCK
			var breech: MeshInstance3D
			if breech_mesh:
				breech = _mesh_inst(breech_mesh, Color(0.20, 0.22, 0.24))
				breech.scale = Vector3(caliber, caliber, caliber)
				elev_pivot.add_child(breech)
			else:
				breech = MeshInstance3D.new()
				var b_box = BoxMesh.new()
				b_box.size = Vector3(0.30 * caliber, 0.28 * caliber, 0.45 * caliber)
				breech.mesh = b_box
				var b_mat = StandardMaterial3D.new()
				b_mat.albedo_color = Color(0.20, 0.22, 0.24)
				breech.material_override = b_mat
				breech.position = Vector3(0, 0, -0.12 * caliber)
				elev_pivot.add_child(breech)

			# 2B. BARREL. Authored along -Z, so scaling Z lengthens the tube.
			var barrel: MeshInstance3D
			if barrel_mesh:
				barrel = _mesh_inst(barrel_mesh, Color(0.16, 0.17, 0.19))
				barrel.scale = Vector3(caliber, caliber, length * caliber)
			else:
				barrel = MeshInstance3D.new()
				var b_cyl = CylinderMesh.new()
				b_cyl.top_radius = 0.05 * caliber
				b_cyl.bottom_radius = 0.08 * caliber
				b_cyl.height = 1.35 * length
				barrel.mesh = b_cyl
				var b_mat = StandardMaterial3D.new()
				b_mat.albedo_color = Color(0.16, 0.17, 0.19)
				barrel.material_override = b_mat
				barrel.position = Vector3(0, 0, -(1.35 * length / 2.0))
				barrel.rotation = Vector3(PI / 2, 0, 0)
			elev_pivot.add_child(barrel)

	elif type_id == "mortar_array":
		var t_count = int(tweaks.get("tube_count", 2.0))
		t_count = clamp(t_count, 1, 4)
		var caliber = tweaks.get("caliber", 1.0)
		var length = tweaks.get("barrel_length", 1.0)

		# 1. SWIVEL TURNTABLE MOUNT PLATE (mortar_swivel_mount.glb)
		var base_w_scale = (1.0 + (t_count - 1) * 0.18) * caliber
		var mount_mesh = _part("mortar_swivel_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.25))
			mount.scale = Vector3(base_w_scale, caliber, base_w_scale)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_cyl = CylinderMesh.new()
			m_cyl.top_radius = 0.32 * base_w_scale
			m_cyl.bottom_radius = 0.34 * base_w_scale
			m_cyl.height = 0.12 * caliber
			mount.mesh = m_cyl
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.25)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.06 * caliber, 0)
		parent_node.add_child(mount)

		# 2. CLUSTERED MORTAR TUBES WITH RECOIL COLLARS (mortar_tube_single.glb)
		var tube_mesh = _part("mortar_tube_single")
		var trunnion_y = 0.16 * caliber
		var r_off = 0.18 * caliber

		var tube_offsets = [Vector3(0, 0, 0)]
		if t_count == 2:
			tube_offsets = [Vector3(-r_off, 0, 0), Vector3(r_off, 0, 0)]
		elif t_count == 3:
			tube_offsets = [
				Vector3(0, 0, -r_off * 0.9),
				Vector3(-r_off * 0.866, 0, r_off * 0.5),
				Vector3(r_off * 0.866, 0, r_off * 0.5)
			]
		elif t_count >= 4:
			tube_offsets = [
				Vector3(-r_off * 0.85, 0, -r_off * 0.85),
				Vector3(r_off * 0.85, 0, -r_off * 0.85),
				Vector3(-r_off * 0.85, 0, r_off * 0.85),
				Vector3(r_off * 0.85, 0, r_off * 0.85)
			]

		for offset in tube_offsets:
			# ELEVATION PIVOT, same reasoning as artillery: mortar_tube_single.glb
			# is now authored along -Z at zero elevation (build_mortar.py's
			# ELEV_60_DEG), and the 60-degree firing elevation is a pivot rotation.
			# Scaling the tube's Z therefore lengthens the tube along its own axis
			# instead of shearing it, which is what barrel_length needs.
			var m_pivot = Node3D.new()
			m_pivot.name = "TubePivot"
			m_pivot.position = Vector3(offset.x, trunnion_y, offset.z)
			m_pivot.rotation = Vector3(deg_to_rad(MORTAR_ELEVATION_DEG), 0, 0)
			parent_node.add_child(m_pivot)

			var tube: MeshInstance3D
			if tube_mesh:
				tube = _mesh_inst(tube_mesh, Color(0.22, 0.25, 0.20))
				tube.scale = Vector3(caliber, caliber, length * caliber)
			else:
				tube = MeshInstance3D.new()
				var t_cyl = CylinderMesh.new()
				t_cyl.top_radius = 0.075 * caliber
				t_cyl.bottom_radius = 0.09 * caliber
				t_cyl.height = 1.10 * length
				tube.mesh = t_cyl
				var t_mat = StandardMaterial3D.new()
				t_mat.albedo_color = Color(0.22, 0.25, 0.20)
				tube.material_override = t_mat
				# Procedural fallback: CylinderMesh runs along Y, so a quarter turn
				# puts it along the pivot's -Z like the authored tube.
				tube.position = Vector3(0, 0, -(1.10 * length * 0.5))
				tube.rotation = Vector3(PI / 2, 0, 0)
			m_pivot.add_child(tube)


	elif type_id == "missile_pod":
		# missile_pod is in MODULAR_ASSEMBLY_TYPES, so build_visual() never tries
		# the monolithic _part(type_id) path for it - it comes straight here. There
		# was no branch, so it fell through to the generic box fallback at the end
		# of this function and the swarm pod rendered as a plain orange box, while
		# its three authored meshes (missile_pod_pintle_mount, missile_pod_housing,
		# missile_pod_missile) sat unused in assets/models/parts.
		var warhead = tweaks.get("warhead_size", 1.0)
		var motor = tweaks.get("motor_length", 1.0)
		var grid = int(clamp(tweaks.get("grid_size", 4.0), 2.0, 6.0))

		# 1. PINTLE MOUNT
		var pod_mount_mesh = _part("missile_pod_pintle_mount")
		if not pod_mount_mesh:
			pod_mount_mesh = _part("pintle_mount")
		var pod_mount: MeshInstance3D
		if pod_mount_mesh:
			pod_mount = _mesh_inst(pod_mount_mesh, base_color.darkened(0.25))
			pod_mount.scale = Vector3(warhead, warhead, warhead)
		else:
			pod_mount = MeshInstance3D.new()
			var pm_box = BoxMesh.new()
			pm_box.size = Vector3(base_size.x * 0.45, base_size.y * 0.25, base_size.z * 0.45)
			pod_mount.mesh = pm_box
			var pm_mat = StandardMaterial3D.new()
			pm_mat.albedo_color = base_color.darkened(0.25)
			pod_mount.material_override = pm_mat
			pod_mount.position = Vector3(0, pm_box.size.y * 0.5, 0)
		parent_node.add_child(pod_mount)

		# 2. LAUNCHER HOUSING - the boxy multi-tube pod body
		var pod_body_y: float = base_size.y * 0.55 * warhead
		var housing_mesh = _part("missile_pod_housing")
		var pod_housing: MeshInstance3D
		if housing_mesh:
			pod_housing = _mesh_inst(housing_mesh, base_color)
			pod_housing.scale = Vector3(warhead, warhead, motor * warhead)
			pod_housing.position = Vector3(0, pod_body_y, 0)
		else:
			pod_housing = MeshInstance3D.new()
			var ph_box = BoxMesh.new()
			ph_box.size = Vector3(base_size.x * 0.9 * warhead,
				base_size.y * 0.6 * warhead, base_size.z * 0.8 * motor)
			pod_housing.mesh = ph_box
			var ph_mat = StandardMaterial3D.new()
			ph_mat.albedo_color = base_color
			pod_housing.material_override = ph_mat
			pod_housing.position = Vector3(0, pod_body_y, 0)
		parent_node.add_child(pod_housing)

		# 3. ROCKET GRID - grid x rows of tube muzzles across the pod's front face
		var rocket_mesh = _part("missile_pod_missile")
		var rows: int = maxi(int(round(float(grid) * 0.66)), 2)
		var cell_w: float = (base_size.x * 0.72 * warhead) / float(grid)
		var cell_h: float = (base_size.y * 0.5 * warhead) / float(rows)
		var grid_z: float = -base_size.z * 0.4 * motor
		for gx in range(grid):
			for gy in range(rows):
				var rx: float = (float(gx) - float(grid - 1) * 0.5) * cell_w
				var ry: float = pod_body_y + (float(gy) - float(rows - 1) * 0.5) * cell_h
				var rocket: MeshInstance3D
				if rocket_mesh:
					rocket = _mesh_inst(rocket_mesh, Color(0.75, 0.72, 0.66))
					rocket.scale = Vector3(warhead, warhead, motor * warhead)
				else:
					rocket = MeshInstance3D.new()
					var r_cyl = CylinderMesh.new()
					r_cyl.top_radius = cell_w * 0.3
					r_cyl.bottom_radius = cell_w * 0.3
					r_cyl.height = cell_w * 0.5
					rocket.mesh = r_cyl
					rocket.rotation = Vector3(PI / 2.0, 0, 0)
					var r_mat = StandardMaterial3D.new()
					r_mat.albedo_color = Color(0.75, 0.72, 0.66)
					rocket.material_override = r_mat
				rocket.position = Vector3(rx, ry, grid_z)
				parent_node.add_child(rocket)

	elif type_id == "guided_missile":
		var b_count = int(tweaks.get("barrel_count", 1.0))
		b_count = clamp(b_count, 1, 4)
		var seeker = tweaks.get("seeker_size", 1.0)
		var engine = tweaks.get("engine_length", 1.0)

		# 1. PINTLE MOUNT & GUIDANCE OPTIC SIGHT (tow_pintle_mount.glb)
		var base_w_scale = (1.0 + (b_count - 1) * 0.35) * seeker
		var mount_mesh = _part("tow_pintle_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(base_w_scale, seeker, seeker)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.34 * base_w_scale, 0.22 * seeker, 0.34 * seeker)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.11 * seeker, 0)
		parent_node.add_child(mount)

		# 2. FIBERGLASS LAUNCH CANISTER TUBES & TOW MISSILES (1 to 4 tubes side-by-side)
		var tube_mesh = _part("tow_launch_tube")
		var missile_mesh = _part("tow_missile_warhead")
		var trunnion_y = 0.24 * seeker
		var x_spacing = 0.28 * seeker
		var start_x = -((b_count - 1) * x_spacing) / 2.0

		for i in range(b_count):
			var cur_x = start_x + i * x_spacing

			# 2A. LAUNCH TUBE CANISTER
			var tube: MeshInstance3D
			if tube_mesh:
				tube = _mesh_inst(tube_mesh, Color(0.24, 0.26, 0.22))
				tube.scale = Vector3(seeker, seeker, engine * seeker)
				tube.position = Vector3(cur_x, trunnion_y, 0.0)
			else:
				tube = MeshInstance3D.new()
				var t_box = BoxMesh.new()
				t_box.size = Vector3(0.20 * seeker, 0.20 * seeker, 1.20 * engine)
				tube.mesh = t_box
				var t_mat = StandardMaterial3D.new()
				t_mat.albedo_color = Color(0.24, 0.26, 0.22)
				tube.material_override = t_mat
				tube.position = Vector3(cur_x, trunnion_y, -(1.20 * engine / 2.0))
			parent_node.add_child(tube)

			# 2B. TOW MISSILE WARHEAD PROBE (Protruding out front of tube opening)
			var missile: MeshInstance3D
			if missile_mesh:
				missile = _mesh_inst(missile_mesh, Color(0.85, 0.85, 0.85))
				missile.scale = Vector3(seeker, seeker, seeker)
				missile.position = Vector3(cur_x, trunnion_y, -0.60 * engine * seeker)
			else:
				missile = MeshInstance3D.new()
				var m_cyl = CylinderMesh.new()
				m_cyl.top_radius = 0.01
				m_cyl.bottom_radius = 0.075 * seeker
				m_cyl.height = 0.30
				missile.mesh = m_cyl
				var m_mat = StandardMaterial3D.new()
				m_mat.albedo_color = Color.WHITE
				missile.material_override = m_mat
				missile.position = Vector3(cur_x, trunnion_y, -(1.20 * engine + 0.15))
				missile.rotation = Vector3(PI / 2, 0, 0)
			parent_node.add_child(missile)


	elif type_id == "drone_carrier":
		var hangar_size = int(tweaks.get("hangar_size", 2.0))
		hangar_size = clamp(hangar_size, 1, 5)
		var launch_catapult = tweaks.get("launch_catapult", 1.0)

		# 1. CATAPULT LAUNCH DECK MOUNT (drone_carrier_mount.glb)
		var mount_mesh = _part("drone_carrier_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		var mount_w = 0.8 + (hangar_size - 1) * 0.15
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(mount_w, 1.0, launch_catapult)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.50 * mount_w, 0.06, 0.80 * launch_catapult)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.03, 0)
		parent_node.add_child(mount)

		# 2. HANGAR BAY ENCLOSURE (drone_carrier_housing.glb)
		var housing_mesh = _part("drone_carrier_housing")
		var housing: MeshInstance3D
		if housing_mesh:
			housing = _mesh_inst(housing_mesh, Color(0.28, 0.30, 0.34))
			housing.scale = Vector3(mount_w, 1.0, 1.0)
			housing.position = Vector3(0, 0, 0)
		else:
			housing = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.46 * mount_w, 0.44, 0.22)
			housing.mesh = h_box
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.28, 0.30, 0.34)
			housing.material_override = h_mat
			housing.position = Vector3(0, 0.22, 0.15)
		parent_node.add_child(housing)

		# 3. SCOUT DRONES (drone_carrier_drone.glb) mounted on catapult launch rails
		var drone_mesh = _part("drone_carrier_drone")
		var front_z_start = -0.35 * launch_catapult
		for i in range(hangar_size):
			var drone: MeshInstance3D
			var dz = front_z_start + i * (0.15 * launch_catapult)
			if drone_mesh:
				drone = _mesh_inst(drone_mesh, Color(0.85, 0.85, 0.88))
				drone.scale = Vector3(1.0, 1.0, 1.0)
				drone.position = Vector3(0, 0.08, dz)
			else:
				drone = MeshInstance3D.new()
				var d_box = BoxMesh.new()
				d_box.size = Vector3(0.18, 0.04, 0.12)
				drone.mesh = d_box
				var d_mat = StandardMaterial3D.new()
				d_mat.albedo_color = Color(0.85, 0.85, 0.88)
				drone.material_override = d_mat
				drone.position = Vector3(0, 0.08, dz)
			parent_node.add_child(drone)

	elif type_id in ["cluster_dispenser", "cluster_launcher"]:
		var dispersion = tweaks.get("dispersion", 1.0)
		var payload_size = tweaks.get("payload_size", 1.0)
		var tube_count = int(tweaks.get("tube_count", 2.0))
		tube_count = clamp(tube_count, 1, 4)

		# 1. MOUNT (cluster_dispenser_mount.glb)
		var mount_mesh = _part("cluster_dispenser_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		var base_w_scale = (0.85 + (tube_count - 1) * 0.15) * dispersion
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(base_w_scale, payload_size, base_w_scale)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.42 * base_w_scale, 0.16 * payload_size, 0.42 * base_w_scale)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.08 * payload_size, 0)
		parent_node.add_child(mount)

		# 2. CONTAINER HOUSING (cluster_dispenser_housing.glb)
		var trunnion_y = 0.22 * payload_size
		var housing_mesh = _part("cluster_dispenser_housing")
		var housing: MeshInstance3D
		var house_w = (0.85 + (tube_count - 1) * 0.15) * dispersion
		if housing_mesh:
			housing = _mesh_inst(housing_mesh, Color(0.28, 0.22, 0.18))
			housing.scale = Vector3(house_w, payload_size, dispersion)
			housing.position = Vector3(0, trunnion_y, 0)
		else:
			housing = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.42 * house_w, 0.32 * payload_size, 0.70 * dispersion)
			housing.mesh = h_box
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.28, 0.22, 0.18)
			housing.material_override = h_mat
			housing.position = Vector3(0, trunnion_y, 0)
		parent_node.add_child(housing)

		# 3. SUBMUNITION CANISTERS / DEPTH CHARGES (cluster_dispenser_canister.glb)
		var canister_mesh = _part("cluster_dispenser_canister")
		var offsets: Array[Vector2] = []
		if tube_count == 1:
			offsets = [Vector2(0, 0)]
		elif tube_count == 2:
			offsets = [Vector2(-0.10 * dispersion, 0), Vector2(0.10 * dispersion, 0)]
		elif tube_count == 3:
			offsets = [Vector2(0, -0.12 * dispersion), Vector2(-0.11 * dispersion, 0.08 * dispersion), Vector2(0.11 * dispersion, 0.08 * dispersion)]
		else:
			offsets = [Vector2(-0.11 * dispersion, -0.11 * dispersion), Vector2(0.11 * dispersion, -0.11 * dispersion), Vector2(-0.11 * dispersion, 0.11 * dispersion), Vector2(0.11 * dispersion, 0.11 * dispersion)]

		for off in offsets:
			var can: MeshInstance3D
			var can_scale = payload_size
			if canister_mesh:
				can = _mesh_inst(canister_mesh, Color(0.70, 0.40, 0.20))
				can.scale = Vector3(can_scale, can_scale, can_scale)
				can.position = Vector3(off.x, trunnion_y, off.y)
			else:
				can = MeshInstance3D.new()
				var c_cyl = CylinderMesh.new()
				c_cyl.top_radius = 0.05 * can_scale
				c_cyl.bottom_radius = 0.05 * can_scale
				c_cyl.height = 0.18 * payload_size
				can.mesh = c_cyl
				var c_mat = StandardMaterial3D.new()
				c_mat.albedo_color = Color(0.70, 0.40, 0.20)
				can.material_override = c_mat
				can.position = Vector3(off.x, trunnion_y, off.y)
				can.rotation = Vector3(PI / 2, 0, 0)
			parent_node.add_child(can)

	elif type_id == "flamethrower":
		var nozzle_width = tweaks.get("nozzle_width", 1.0)
		var pressure_valve = tweaks.get("pressure_valve", 1.0)

		# 1. MOUNT (flamethrower_mount.glb)
		var mount_mesh = _part("flamethrower_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(1.0, 1.0, 1.0)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.32, 0.16, 0.32)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.08, 0)
		parent_node.add_child(mount)

		# 2. BODY & DUAL FUEL TANKS (flamethrower_body.glb) - pressure_valve deforms body only
		var trunnion_y = 0.20
		var body_mesh = _part("flamethrower_body")
		var body: MeshInstance3D
		if body_mesh:
			body = _mesh_inst(body_mesh, Color(0.35, 0.20, 0.12))
			body.scale = Vector3(pressure_valve, 1.0, pressure_valve)
			body.position = Vector3(0, trunnion_y, 0)
		else:
			body = MeshInstance3D.new()
			var b_box = BoxMesh.new()
			b_box.size = Vector3(0.22 * pressure_valve, 0.22, 0.45 * pressure_valve)
			body.mesh = b_box
			var b_mat = StandardMaterial3D.new()
			b_mat.albedo_color = Color(0.35, 0.20, 0.12)
			body.material_override = b_mat
			body.position = Vector3(0, trunnion_y, 0)
		parent_node.add_child(body)

		# 3. NOZZLE & IGNITER TIP (flamethrower_nozzle.glb) - nozzle_width deforms nozzle only
		var nozzle_mesh = _part("flamethrower_nozzle")
		var nozzle: MeshInstance3D
		var nozzle_z = 0.0
		if nozzle_mesh:
			nozzle = _mesh_inst(nozzle_mesh, Color(0.15, 0.15, 0.15))
			nozzle.scale = Vector3(nozzle_width, nozzle_width, 1.0)
			nozzle.position = Vector3(0, trunnion_y, nozzle_z)
		else:
			nozzle = MeshInstance3D.new()
			var n_cyl = CylinderMesh.new()
			n_cyl.top_radius = 0.08 * nozzle_width
			n_cyl.bottom_radius = 0.05 * nozzle_width
			n_cyl.height = 0.35
			nozzle.mesh = n_cyl
			var n_mat = StandardMaterial3D.new()
			n_mat.albedo_color = Color(0.15, 0.15, 0.15)
			nozzle.material_override = n_mat
			nozzle.position = Vector3(0, trunnion_y, -0.37)
			nozzle.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(nozzle)

	elif type_id == "tesla_coil":
		var caliber = tweaks.get("caliber", 1.0)
		var arc_freq = tweaks.get("arc_frequency", 1.0)
		var surge_cap = tweaks.get("surge_capacity", 1.0)

		# 1. MOUNT (tesla_coil_mount.glb)
		var mount_mesh = _part("tesla_coil_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(caliber, 1.0, caliber)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.48 * caliber, 0.16, 0.48 * caliber)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.08, 0)
		parent_node.add_child(mount)

		# 2. TRANSFORMER TOWER HOUSING (tesla_coil_housing.glb)
		var trunnion_y = 0.12
		var housing_mesh = _part("tesla_coil_housing")
		var housing: MeshInstance3D
		if housing_mesh:
			housing = _mesh_inst(housing_mesh, Color(0.70, 0.45, 0.20))
			housing.scale = Vector3(caliber, surge_cap, caliber)
			housing.position = Vector3(0, trunnion_y, 0)
		else:
			housing = MeshInstance3D.new()
			var h_cyl = CylinderMesh.new()
			h_cyl.top_radius = 0.16 * caliber
			h_cyl.bottom_radius = 0.16 * caliber
			h_cyl.height = 0.80 * surge_cap
			housing.mesh = h_cyl
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.70, 0.45, 0.20)
			housing.material_override = h_mat
			housing.position = Vector3(0, trunnion_y + 0.40 * surge_cap, 0)
		parent_node.add_child(housing)

		# 3. DISCHARGE TOROID DOME (tesla_coil_toroid.glb)
		var toroid_mesh = _part("tesla_coil_toroid")
		var toroid: MeshInstance3D
		var toroid_y = trunnion_y + 0.80 * surge_cap
		if toroid_mesh:
			toroid = _mesh_inst(toroid_mesh, Color(0.85, 0.90, 0.95))
			toroid.scale = Vector3(caliber * arc_freq, arc_freq, caliber * arc_freq)
			toroid.position = Vector3(0, toroid_y, 0)
		else:
			toroid = MeshInstance3D.new()
			var t_sph = SphereMesh.new()
			t_sph.radius = 0.24 * caliber * arc_freq
			t_sph.height = 0.32 * arc_freq
			toroid.mesh = t_sph
			var t_mat = StandardMaterial3D.new()
			t_mat.albedo_color = Color.LIGHT_SKY_BLUE
			toroid.material_override = t_mat
			toroid.position = Vector3(0, toroid_y, 0)
		parent_node.add_child(toroid)

	elif type_id == "ion_cannon":
		var beam_width = tweaks.get("beam_width", 1.0)
		var ion_density = tweaks.get("ion_density", 1.0)

		# 1. MOUNT (ion_cannon_mount.glb)
		var mount_mesh = _part("ion_cannon_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(beam_width, 1.0, beam_width)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.50 * beam_width, 0.16, 0.50 * beam_width)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.08, 0)
		parent_node.add_child(mount)

		# 2. ACCELERATOR HOUSING (ion_cannon_housing.glb)
		var trunnion_y = 0.26
		var housing_mesh = _part("ion_cannon_housing")
		var housing: MeshInstance3D
		if housing_mesh:
			housing = _mesh_inst(housing_mesh, Color(0.20, 0.24, 0.30))
			housing.scale = Vector3(beam_width, beam_width, ion_density)
			housing.position = Vector3(0, trunnion_y, 0)
		else:
			housing = MeshInstance3D.new()
			var h_cyl = CylinderMesh.new()
			h_cyl.top_radius = 0.14 * beam_width
			h_cyl.bottom_radius = 0.14 * beam_width
			h_cyl.height = 1.20 * ion_density
			housing.mesh = h_cyl
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.20, 0.24, 0.30)
			housing.material_override = h_mat
			housing.position = Vector3(0, trunnion_y, -0.60 * ion_density)
			housing.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(housing)

		# 3. FOCUSING LENS (ion_cannon_lens.glb)
		var lens_mesh = _part("ion_cannon_lens")
		var lens: MeshInstance3D
		var lens_z = -0.60 * ion_density
		if lens_mesh:
			lens = _mesh_inst(lens_mesh, Color(0.25, 0.60, 0.85))
			lens.scale = Vector3(beam_width, beam_width, beam_width)
			lens.position = Vector3(0, trunnion_y, lens_z)
		else:
			lens = MeshInstance3D.new()
			var l_cyl = CylinderMesh.new()
			l_cyl.top_radius = 0.08 * beam_width
			l_cyl.bottom_radius = 0.14 * beam_width
			l_cyl.height = 0.20
			lens.mesh = l_cyl
			var l_mat = StandardMaterial3D.new()
			l_mat.albedo_color = Color.CYAN
			lens.material_override = l_mat
			lens.position = Vector3(0, trunnion_y, lens_z - 0.10)
			lens.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(lens)

	elif type_id in ["heavy_laser", "laser_cannon"]:
		var lens_aperture = tweaks.get("lens_aperture", 1.0)
		var barrel_len = tweaks.get("barrel_length", tweaks.get("focal_length", 1.0))

		# 1. MOUNT (heavy_laser_mount.glb)
		var mount_mesh = _part("heavy_laser_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(1.0, 1.0, 1.0)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.44, 0.16, 0.44)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.08, 0)
		parent_node.add_child(mount)

		# 2. OPTICAL CAVITY BARREL HOUSING (heavy_laser_housing.glb)
		var trunnion_y = 0.25
		var housing_mesh = _part("heavy_laser_housing")
		var housing: MeshInstance3D
		if housing_mesh:
			housing = _mesh_inst(housing_mesh, Color(0.24, 0.28, 0.32))
			housing.scale = Vector3(lens_aperture, lens_aperture, 1.0)
			housing.position = Vector3(0, trunnion_y, 0)
		else:
			housing = MeshInstance3D.new()
			var h_cyl = CylinderMesh.new()
			h_cyl.top_radius = 0.12 * lens_aperture
			h_cyl.bottom_radius = 0.12 * lens_aperture
			h_cyl.height = 0.50
			housing.mesh = h_cyl
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.24, 0.28, 0.32)
			housing.material_override = h_mat
			housing.position = Vector3(0, trunnion_y, -0.25)
			housing.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(housing)

		# 3. LENS TELESCOPE BARREL (heavy_laser_lens.glb)
		var lens_mesh = _part("heavy_laser_lens")
		var lens: MeshInstance3D
		var lens_z = 0.0
		if lens_mesh:
			lens = _mesh_inst(lens_mesh, Color(0.15, 0.18, 0.22))
			lens.scale = Vector3(lens_aperture, lens_aperture, barrel_len)
			lens.position = Vector3(0, trunnion_y, lens_z)
		else:
			lens = MeshInstance3D.new()
			var l_cyl = CylinderMesh.new()
			l_cyl.top_radius = 0.14 * lens_aperture
			l_cyl.bottom_radius = 0.12 * lens_aperture
			l_cyl.height = 0.50 * barrel_len
			lens.mesh = l_cyl
			var l_mat = StandardMaterial3D.new()
			l_mat.albedo_color = Color(0.15, 0.18, 0.22)
			lens.material_override = l_mat
			lens.position = Vector3(0, trunnion_y, -(0.25 + 0.25 * barrel_len))
			lens.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(lens)

	elif type_id in ["plasma_lobber", "plasma_launcher"]:
		var containment = tweaks.get("containment", 1.0)
		var barrel_len = tweaks.get("barrel_length", tweaks.get("charge_rate", 1.0))

		# 1. MOUNT (plasma_lobber_mount.glb)
		var mount_mesh = _part("plasma_lobber_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(1.0, 1.0, 1.0)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.56, 0.16, 0.56)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.08, 0)
		parent_node.add_child(mount)

		var trunnion_y = 0.28
		var barrel_group = Node3D.new()
		barrel_group.position = Vector3(0, trunnion_y, 0)
		barrel_group.rotation.x = deg_to_rad(35.0)
		parent_node.add_child(barrel_group)

		# 2. CONTAINMENT VESSEL CHAMBER (plasma_lobber_chamber.glb)
		var chamber_mesh = _part("plasma_lobber_chamber")
		var chamber: MeshInstance3D
		if chamber_mesh:
			chamber = _mesh_inst(chamber_mesh, Color(0.30, 0.20, 0.35))
			chamber.scale = Vector3(containment, containment, containment)
			chamber.position = Vector3(0, 0, 0)
		else:
			chamber = MeshInstance3D.new()
			var h_cyl = CylinderMesh.new()
			h_cyl.top_radius = 0.24 * containment
			h_cyl.bottom_radius = 0.24 * containment
			h_cyl.height = 0.40 * containment
			chamber.mesh = h_cyl
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.30, 0.20, 0.35)
			chamber.material_override = h_mat
			chamber.position = Vector3(0, 0, -0.20 * containment)
			chamber.rotation = Vector3(PI / 2, 0, 0)
		barrel_group.add_child(chamber)

		# 3. ACCELERATOR BARREL (plasma_lobber_barrel.glb)
		var barrel_mesh = _part("plasma_lobber_barrel")
		var barrel: MeshInstance3D
		if barrel_mesh:
			barrel = _mesh_inst(barrel_mesh, Color(0.20, 0.18, 0.25))
			barrel.scale = Vector3(containment, containment, barrel_len)
			barrel.position = Vector3(0, 0, 0)
		else:
			barrel = MeshInstance3D.new()
			var n_cyl = CylinderMesh.new()
			n_cyl.top_radius = 0.13 * containment
			n_cyl.bottom_radius = 0.13 * containment
			n_cyl.height = 0.45 * barrel_len
			barrel.mesh = n_cyl
			var n_mat = StandardMaterial3D.new()
			n_mat.albedo_color = Color(0.20, 0.18, 0.25)
			barrel.material_override = n_mat
			barrel.position = Vector3(0, 0, -0.45 * barrel_len)
			barrel.rotation = Vector3(PI / 2, 0, 0)
		barrel_group.add_child(barrel)

	elif type_id == "ciws":
		var caliber = tweaks.get("caliber", 1.0)
		var barrel_len = tweaks.get("barrel_length", 1.0)
		var radar_dish = tweaks.get("radar_dish", 1.0)

		# 1. MOUNT (ciws_mount.glb)
		var mount_mesh = _part("ciws_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(caliber, 1.0, caliber)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.58 * caliber, 0.16, 0.58 * caliber)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.08, 0)
		parent_node.add_child(mount)

		# 2. RADOME & RECEIVER HOUSING (ciws_radar.glb)
		var trunnion_y = 0.32
		var radar_mesh = _part("ciws_radar")
		var radar: MeshInstance3D
		if radar_mesh:
			radar = _mesh_inst(radar_mesh, Color(0.90, 0.90, 0.90))
			radar.scale = Vector3(radar_dish, radar_dish, radar_dish)
			radar.position = Vector3(0, trunnion_y, 0)
		else:
			radar = MeshInstance3D.new()
			var h_cyl = CylinderMesh.new()
			h_cyl.top_radius = 0.24 * radar_dish
			h_cyl.bottom_radius = 0.24 * radar_dish
			h_cyl.height = 0.50 * radar_dish
			radar.mesh = h_cyl
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.90, 0.90, 0.90)
			radar.material_override = h_mat
			radar.position = Vector3(0, trunnion_y + 0.25 * radar_dish, 0)
		parent_node.add_child(radar)

		# 3. 6-BARREL ROTARY GATLING CLUSTER (ciws_barrel.glb)
		var barrel_mesh = _part("ciws_barrel")
		var barrel: MeshInstance3D
		if barrel_mesh:
			barrel = _mesh_inst(barrel_mesh, Color(0.20, 0.22, 0.25))
			barrel.scale = Vector3(caliber, caliber, barrel_len)
			barrel.position = Vector3(0, trunnion_y, 0)
		else:
			barrel = MeshInstance3D.new()
			var b_cyl = CylinderMesh.new()
			b_cyl.top_radius = 0.08 * caliber
			b_cyl.bottom_radius = 0.08 * caliber
			b_cyl.height = 0.85 * barrel_len
			barrel.mesh = b_cyl
			var b_mat = StandardMaterial3D.new()
			b_mat.albedo_color = Color(0.20, 0.22, 0.25)
			barrel.material_override = b_mat
			barrel.position = Vector3(0, trunnion_y, -0.42 * barrel_len)
			barrel.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(barrel)

	elif type_id in ["pd_laser", "point_defense_laser"]:
		var cooling_jacket = tweaks.get("cooling_jacket", 1.0)
		var barrel_len = tweaks.get("barrel_length", 1.0)

		# 1. GIMBAL MOUNT (pd_laser_mount.glb)
		var mount_mesh = _part("pd_laser_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(1.0, 1.0, 1.0)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.32, 0.14, 0.32)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.07, 0)
		parent_node.add_child(mount)

		# 2. DIODE RECEIVER HOUSING (pd_laser_housing.glb)
		var trunnion_y = 0.20
		var housing_mesh = _part("pd_laser_housing")
		var housing: MeshInstance3D
		if housing_mesh:
			housing = _mesh_inst(housing_mesh, Color(0.25, 0.30, 0.35))
			housing.scale = Vector3(cooling_jacket, cooling_jacket, 1.0)
			housing.position = Vector3(0, trunnion_y, 0)
		else:
			housing = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.18 * cooling_jacket, 0.18, 0.32)
			housing.mesh = h_box
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.25, 0.30, 0.35)
			housing.material_override = h_mat
			housing.position = Vector3(0, trunnion_y, -0.16)
		parent_node.add_child(housing)

		# 3. TWIN LENS EMITTERS (pd_laser_lens.glb)
		var lens_mesh = _part("pd_laser_lens")
		var lens: MeshInstance3D
		if lens_mesh:
			lens = _mesh_inst(lens_mesh, Color(0.15, 0.50, 0.75))
			lens.scale = Vector3(cooling_jacket, cooling_jacket, barrel_len)
			lens.position = Vector3(0, trunnion_y, 0)
		else:
			lens = MeshInstance3D.new()
			var l_cyl = CylinderMesh.new()
			l_cyl.top_radius = 0.04 * cooling_jacket
			l_cyl.bottom_radius = 0.04 * cooling_jacket
			l_cyl.height = 0.28 * barrel_len
			lens.mesh = l_cyl
			var l_mat = StandardMaterial3D.new()
			l_mat.albedo_color = Color(0.15, 0.50, 0.75)
			lens.material_override = l_mat
			lens.position = Vector3(0, trunnion_y, -0.14 * barrel_len)
			lens.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(lens)

	elif type_id in ["flak_cannon", "flak_battery"]:
		var caliber = tweaks.get("caliber", 1.0) * 0.75  # Cut flak scale to 0.75 per user request
		var barrel_len = tweaks.get("barrel_length", 1.0) * 0.75
		var barrel_count = int(tweaks.get("barrel_count", 2.0))
		barrel_count = clamp(barrel_count, 1, 4)

		# 1. MOUNT (flak_cannon_mount.glb)
		var mount_mesh = _part("flak_cannon_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		var mount_w = (1.0 + (barrel_count - 1) * 0.15) * caliber
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(mount_w, 1.0, caliber)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.52 * mount_w, 0.16, 0.52 * caliber)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.08, 0)
		parent_node.add_child(mount)

		var trunnion_y = 0.28
		var barrel_group = Node3D.new()
		barrel_group.position = Vector3(0, trunnion_y, 0)
		barrel_group.rotation.x = deg_to_rad(45.0)
		parent_node.add_child(barrel_group)

		# 2. BREECH BLOCK & RECUPERATOR (flak_cannon_breech.glb)
		var breech_mesh = _part("flak_cannon_breech")
		if not breech_mesh:
			breech_mesh = _part("flak_cannon_housing")
		var breech: MeshInstance3D
		if breech_mesh:
			breech = _mesh_inst(breech_mesh, Color(0.20, 0.22, 0.18))
			breech.scale = Vector3(mount_w, caliber, caliber)
			breech.position = Vector3(0, 0, 0)
		else:
			breech = MeshInstance3D.new()
			var h_box = BoxMesh.new()
			h_box.size = Vector3(0.34 * mount_w, 0.32 * caliber, 0.50 * caliber)
			breech.mesh = h_box
			var h_mat = StandardMaterial3D.new()
			h_mat.albedo_color = Color(0.20, 0.22, 0.18)
			breech.material_override = h_mat
			breech.position = Vector3(0, 0, -0.25 * caliber)
		barrel_group.add_child(breech)

		# 3. CLUSTERED FLAK BARRELS (flak_cannon_barrel.glb) - clustered formation, not line abreast
		var barrel_mesh = _part("flak_cannon_barrel")
		var offsets: Array[Vector2] = []
		if barrel_count == 1:
			offsets = [Vector2(0, 0)]
		elif barrel_count == 2:
			# Vertical stack cluster
			offsets = [Vector2(0, -0.06 * caliber), Vector2(0, 0.06 * caliber)]
		elif barrel_count == 3:
			# Delta triangle cluster
			offsets = [Vector2(0, 0.07 * caliber), Vector2(-0.06 * caliber, -0.05 * caliber), Vector2(0.06 * caliber, -0.05 * caliber)]
		else:
			# 2x2 Box cluster
			offsets = [Vector2(-0.06 * caliber, -0.06 * caliber), Vector2(0.06 * caliber, -0.06 * caliber), Vector2(-0.06 * caliber, 0.06 * caliber), Vector2(0.06 * caliber, 0.06 * caliber)]

		for off in offsets:
			var barrel: MeshInstance3D
			if barrel_mesh:
				barrel = _mesh_inst(barrel_mesh, Color(0.15, 0.16, 0.14))
				barrel.scale = Vector3(caliber, caliber, barrel_len)
				barrel.position = Vector3(off.x, off.y, 0.0)
				barrel_group.add_child(barrel)
			else:
				barrel = MeshInstance3D.new()
				var b_cyl = CylinderMesh.new()
				b_cyl.top_radius = 0.07 * caliber
				b_cyl.bottom_radius = 0.07 * caliber
				b_cyl.height = 1.10 * barrel_len
				barrel.mesh = b_cyl
				var b_mat = StandardMaterial3D.new()
				b_mat.albedo_color = Color(0.15, 0.16, 0.14)
				barrel.material_override = b_mat
				barrel.position = Vector3(off.x, off.y, -0.55 * barrel_len)
				barrel.rotation = Vector3(PI / 2, 0, 0)
				barrel_group.add_child(barrel)

	elif type_id == "repair_array":
		var arm_count = int(tweaks.get("welder_count", 2.0))
		arm_count = clamp(arm_count, 1, 4)

		# 1. MOUNT PEDESTAL BASE (repair_array_mount.glb)
		var mount_mesh = _part("repair_array_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(1.0, 1.0, 1.0)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.52, 0.12, 0.52)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.06, 0)
		parent_node.add_child(mount)

		# 2. ARTICULATED WELDER ARMS & TORCH TIPS (repair_array_arm.glb & repair_array_welder.glb)
		var arm_mesh = _part("repair_array_arm")
		var welder_mesh = _part("repair_array_welder")
		for a in range(arm_count):
			var angle = (float(a) / float(arm_count)) * TAU
			var ax = cos(angle) * 0.12
			var az = sin(angle) * 0.12
			var arm: MeshInstance3D
			if arm_mesh:
				arm = _mesh_inst(arm_mesh, Color(0.25, 0.28, 0.32))
				arm.scale = Vector3(1.0, 1.0, 1.0)
				arm.position = Vector3(ax, 0, az)
				arm.rotation.y = -angle
			else:
				arm = MeshInstance3D.new()
				var a_cyl = CylinderMesh.new()
				a_cyl.top_radius = 0.03
				a_cyl.bottom_radius = 0.04
				a_cyl.height = 0.40
				arm.mesh = a_cyl
				var a_mat = StandardMaterial3D.new()
				a_mat.albedo_color = Color(0.25, 0.28, 0.32)
				arm.material_override = a_mat
				arm.position = Vector3(ax, 0.20, az)
			parent_node.add_child(arm)

			var welder: MeshInstance3D
			if welder_mesh:
				welder = _mesh_inst(welder_mesh, Color(0.15, 0.65, 0.85))
				welder.scale = Vector3(1.0, 1.0, 1.0)
				welder.position = Vector3(ax, 0, az)
				welder.rotation.y = -angle
			else:
				welder = MeshInstance3D.new()
				var w_sph = SphereMesh.new()
				w_sph.radius = 0.05
				w_sph.height = 0.10
				welder.mesh = w_sph
				var w_mat = StandardMaterial3D.new()
				w_mat.albedo_color = Color.CYAN
				w_mat.emission_enabled = true
				w_mat.emission = Color.CYAN
				welder.material_override = w_mat
				welder.position = Vector3(ax, 0.38, az)
			parent_node.add_child(welder)

	elif type_id == "sensor_suite":
		var mast_h = tweaks.get("mast_height", 1.0)

		# 1. MAST PEDESTAL BASE (sensor_suite_mount.glb)
		var mount_mesh = _part("sensor_suite_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(1.0, 1.0, 1.0)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.44, 0.12, 0.44)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.06, 0)
		parent_node.add_child(mount)

		# 2. LATTICE MAST TOWER COLUMN (sensor_suite_mast.glb)
		var mast_mesh = _part("sensor_suite_mast")
		var mast: MeshInstance3D
		if mast_mesh:
			mast = _mesh_inst(mast_mesh, Color(0.25, 0.28, 0.32))
			mast.scale = Vector3(1.0, mast_h, 1.0)
			mast.position = Vector3(0, 0, 0)
		else:
			mast = MeshInstance3D.new()
			var m_cyl = CylinderMesh.new()
			m_cyl.top_radius = 0.04
			m_cyl.bottom_radius = 0.07
			m_cyl.height = 1.00 * mast_h
			mast.mesh = m_cyl
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = Color(0.25, 0.28, 0.32)
			mast.material_override = m_mat
			mast.position = Vector3(0, 0.50 * mast_h, 0)
		parent_node.add_child(mast)

		# 3. ROTATING PARABOLIC DISH (sensor_suite_dish.glb) riding top of mast
		var dish_mesh = _part("sensor_suite_dish")
		var dish: MeshInstance3D
		var dish_y = 1.00 * mast_h
		if dish_mesh:
			dish = _mesh_inst(dish_mesh, Color(0.85, 0.88, 0.90))
			dish.scale = Vector3(1.0, 1.0, 1.0)
			dish.position = Vector3(0, dish_y, 0)
		else:
			dish = MeshInstance3D.new()
			var d_sph = SphereMesh.new()
			d_sph.radius = 0.25
			d_sph.height = 0.20
			dish.mesh = d_sph
			var d_mat = StandardMaterial3D.new()
			d_mat.albedo_color = Color(0.85, 0.88, 0.90)
			dish.material_override = d_mat
			dish.position = Vector3(0, dish_y, 0)
		parent_node.add_child(dish)

	elif type_id == "resource_harvester":
		var ext_size = tweaks.get("extractor_size", 1.0)

		# 1. TURNTABLE MOUNT BASE (resource_harvester_mount.glb)
		var mount_mesh = _part("resource_harvester_mount")
		if not mount_mesh:
			mount_mesh = _part("pintle_mount")
		var mount: MeshInstance3D
		if mount_mesh:
			mount = _mesh_inst(mount_mesh, base_color.darkened(0.2))
			mount.scale = Vector3(1.0, 1.0, 1.0)
			mount.position = Vector3(0, 0, 0)
		else:
			mount = MeshInstance3D.new()
			var m_box = BoxMesh.new()
			m_box.size = Vector3(0.56, 0.16, 0.56)
			mount.mesh = m_box
			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = base_color.darkened(0.2)
			mount.material_override = m_mat
			mount.position = Vector3(0, 0.08, 0)
		parent_node.add_child(mount)

		# 2. EXTRACTOR BOOM ARM (resource_harvester_arm.glb)
		var arm_mesh = _part("resource_harvester_arm")
		var arm: MeshInstance3D
		if arm_mesh:
			arm = _mesh_inst(arm_mesh, Color(0.75, 0.50, 0.15))
			arm.scale = Vector3(1.0, 1.0, ext_size)
			arm.position = Vector3(0, 0, 0)
		else:
			arm = MeshInstance3D.new()
			var a_box = BoxMesh.new()
			a_box.size = Vector3(0.16, 0.40, 0.14 * ext_size)
			arm.mesh = a_box
			var a_mat = StandardMaterial3D.new()
			a_mat.albedo_color = Color(0.75, 0.50, 0.15)
			arm.material_override = a_mat
			arm.position = Vector3(0, 0.20, -0.20 * ext_size)
		parent_node.add_child(arm)

		# 3. ROTARY DRILL BIT (resource_harvester_drill.glb)
		var drill_mesh = _part("resource_harvester_drill")
		var drill: MeshInstance3D
		if drill_mesh:
			drill = _mesh_inst(drill_mesh, Color(0.35, 0.38, 0.42))
			drill.scale = Vector3(ext_size, ext_size, ext_size)
			drill.position = Vector3(0, 0, -0.28 * ext_size)
		else:
			drill = MeshInstance3D.new()
			var d_cyl = CylinderMesh.new()
			d_cyl.top_radius = 0.14 * ext_size
			d_cyl.bottom_radius = 0.02 * ext_size
			d_cyl.height = 0.28 * ext_size
			drill.mesh = d_cyl
			var d_mat = StandardMaterial3D.new()
			d_mat.albedo_color = Color(0.35, 0.38, 0.42)
			drill.material_override = d_mat
			drill.position = Vector3(0, 0.10, -0.45 * ext_size)
			drill.rotation = Vector3(PI / 2, 0, 0)
		parent_node.add_child(drill)

	elif type_id == "tesla_coil":
		# Chris explicitly invited some fun/silly weapons alongside the
		# grounded ones (ENERGY_AND_BALANCE_SPEC.md #4) - a literal wound
		# coil with a glowing discharge ball on top, distinct from the
		# generic box fallback every other unhandled type gets.
		var base = MeshInstance3D.new()
		var base_cyl = CylinderMesh.new()
		base_cyl.top_radius = base_size.x * 0.45
		base_cyl.bottom_radius = base_size.x * 0.55
		base_cyl.height = base_size.y * 0.15
		base.mesh = base_cyl
		var base_mat = StandardMaterial3D.new()
		base_mat.albedo_color = Color(0.2, 0.2, 0.22)
		base.material_override = base_mat
		base.position = Vector3(0, base_cyl.height / 2.0, 0)
		parent_node.add_child(base)

		var coil_segments = 8
		var coil_height = base_size.y * 0.75
		var coil_radius = base_size.x * 0.32
		for i in range(coil_segments):
			var ring = MeshInstance3D.new()
			var torus = TorusMesh.new()
			torus.inner_radius = coil_radius - 0.03
			torus.outer_radius = coil_radius
			ring.mesh = torus
			var ring_mat = StandardMaterial3D.new()
			ring_mat.albedo_color = base_color
			ring_mat.emission_enabled = true
			ring_mat.emission = base_color
			ring_mat.emission_energy_multiplier = 0.4
			ring.material_override = ring_mat
			ring.position = Vector3(0, base_size.y * 0.2 + (coil_height * i / float(coil_segments - 1)), 0)
			parent_node.add_child(ring)

		var orb = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = base_size.x * 0.4
		sphere.height = sphere.radius * 2.0
		orb.mesh = sphere
		var orb_mat = StandardMaterial3D.new()
		orb_mat.albedo_color = Color.WHITE
		orb_mat.emission_enabled = true
		orb_mat.emission = base_color
		orb_mat.emission_energy_multiplier = 1.5
		orb.material_override = orb_mat
		orb.position = Vector3(0, base_size.y * 0.2 + coil_height + sphere.radius * 0.6, 0)
		parent_node.add_child(orb)

	elif type_id.begins_with("structural_"):
		# --- Structural pieces (block, dome, slab, wedge, girder, i_beam) ----
		#
		# PARAMETRIC BODY + FIXED-SIZE AUTHORED HARDWARE.
		#
		# These six are the only modules the player can scale freely on all
		# three axes at once (module_placer.gd's gizmo-category switch gives
		# them X, Y and Z handles), and they are MEANT to be stretched hard -
		# a girder pulled to four times its length, a slab squashed into a
		# deck. That rules out the approach every other part family here uses,
		# where the whole part is one authored .glb that gets scaled: a bolt
		# head scaled 4x along Z is a smear, and the whole reason these read
		# as below the standard of the rest of the roster is that at anything
		# other than default size they were a stretched box with stretched
		# trim on it.
		#
		# So the body stays procedural (it is a box/wedge/hemisphere - trivial
		# geometry that WANTS to be parametric and to re-tessellate when
		# stretched), and all of the detail is authored hardware from
		# build_structural.py, instanced at its true authored size with NO
		# scaling applied. Stretch a girder and you get MORE splice collars,
		# not longer ones. Stretch a block and you get more tie-downs on the
		# deck, not bigger ones. That is how the real object would be built,
		# which is why it holds up at any size.
		#
		# Hardware instances are named with the HARDWARE_PREFIX. module_placer
		# repaints structural pieces with the faction hull shader so they
		# match the vehicle they're bolted to; that pass skips these, so the
		# painted plate reads as faction-liveried structure and the fasteners
		# read as bare steel hardware, instead of everything being one
		# undifferentiated shader.
		var s_body := _structural_body_mat(base_color)
		var s_trim := _structural_body_mat(base_color.lightened(0.12))
		var s_dark := _structural_body_mat(base_color.darkened(0.25))

		# --- BLOCK: a bolted armoured crate ---------------------------------
		if type_id == "structural_block":
			var core = MeshInstance3D.new()
			var box_mesh = BoxMesh.new()
			# The core sits slightly inside the nominal envelope so the corner
			# brackets and edge beads below can occupy the outermost skin
			# without poking past the collision box the placer snaps to.
			box_mesh.size = base_size * 0.96
			core.mesh = box_mesh
			core.material_override = s_body
			core.position = Vector3(0, base_size.y / 2.0, 0)
			parent_node.add_child(core)

			# Rolled edge beads down the four vertical corners - reads as a
			# welded box section rather than a cut cube.
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var bead = MeshInstance3D.new()
					var bead_cyl = CylinderMesh.new()
					bead_cyl.top_radius = 0.035
					bead_cyl.bottom_radius = 0.035
					bead_cyl.height = base_size.y
					bead.mesh = bead_cyl
					bead.material_override = s_trim
					bead.position = Vector3(sx * base_size.x * 0.48, base_size.y / 2.0, sz * base_size.z * 0.48)
					parent_node.add_child(bead)

			# Corner brackets wrapping each vertical edge, top and bottom.
			# The bracket is authored with its arms along +X and +Y (Godot
			# +X / -Z) and its plate rising in +Y, so each corner needs the
			# yaw that points both arms inward along the block's faces.
			for i in range(4):
				var sx = -1.0 if i in [0, 3] else 1.0
				var sz = -1.0 if i in [0, 1] else 1.0
				var yaw = _corner_yaw(sx, sz)
				for y in [0.02, max(0.02, base_size.y - 0.17)]:
					_hardware(parent_node, "struct_corner_bracket",
						Vector3(sx * base_size.x * 0.48, y, sz * base_size.z * 0.48),
						Vector3(0, yaw, 0))

			# Stiffener ribs standing off the two long faces. Count scales
			# with the face, spacing does not.
			var rib_rows = _hardware_count(base_size.z, 0.75)
			for sx in [-1.0, 1.0]:
				for i in range(rib_rows):
					var t = (float(i) + 0.5) / float(rib_rows) - 0.5
					# Sat flush at 0.48 originally, which buried all but a
					# sliver of the rib inside the core box - they read as
					# scratches rather than as structure. Stood proud of the
					# face instead, which is where a welded-on stiffener
					# actually sits.
					_hardware(parent_node, "struct_stiffener_rib",
						Vector3(sx * base_size.x * 0.50, base_size.y * 0.18, t * base_size.z * 0.86),
						Vector3(0, 0, sx * PI / 2.0))

			# Deck tie-downs on top, on a real grid.
			_deck_tie_downs(parent_node, base_size, base_size.y)

		# --- DOME: an armoured turret base ----------------------------------
		elif type_id == "structural_dome":
			var drum_h = base_size.y * 0.30
			var rx = base_size.x / 2.0
			var rz = base_size.z / 2.0

			# Base drum. Elliptical footprint via node scale on a unit
			# cylinder, so a stretched dome stays a stretched dome rather
			# than snapping to a circle.
			var drum = MeshInstance3D.new()
			var drum_cyl = CylinderMesh.new()
			drum_cyl.top_radius = 1.0
			drum_cyl.bottom_radius = 1.02
			drum_cyl.height = 1.0
			drum.mesh = drum_cyl
			drum.material_override = s_dark
			drum.scale = Vector3(rx, drum_h, rz)
			drum.position = Vector3(0, drum_h / 2.0, 0)
			parent_node.add_child(drum)

			# The cupola itself. SphereMesh with is_hemisphere so the flat cut
			# lands on the drum instead of half the sphere hiding inside it.
			# NOTE `height` is the hemisphere's FULL height above its base, not
			# the diameter of the sphere it was cut from (verified against
			# SphereMesh.get_aabb, which reports height 1.0 for radius 1.0) -
			# passing 2.0 here built a dome twice as tall as its own module,
			# a smooth egg that swallowed the hatch and every vision block
			# whole.
			var dome_h = max(0.05, base_size.y - drum_h)
			var dome = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 1.0
			sphere.is_hemisphere = true
			dome.mesh = sphere
			dome.material_override = s_body
			# Slightly narrower than the drum, so the drum's rim reads as a
			# real ledge for the bolt pads to sit on rather than the two
			# surfaces meeting flush and hiding the fasteners inside.
			dome.scale = Vector3(rx * 0.92, dome_h, rz * 0.92)
			dome.position = Vector3(0, drum_h, 0)
			parent_node.add_child(dome)

			# Bolt pads around the drum's top rim, on the ellipse - outboard of
			# the cupola so they stand on the ledge instead of inside it.
			var pad_count = _hardware_count(PI * (rx + rz), 0.62, 6, 24)
			for i in range(pad_count):
				var a = (float(i) / float(pad_count)) * TAU
				_hardware(parent_node, "struct_bolt_pad",
					Vector3(cos(a) * rx * 0.96, drum_h, sin(a) * rz * 0.96),
					Vector3.ZERO)

			# Vision blocks set into the dome's shoulder, facing outward.
			# Deliberately not a full ring - four is enough to give the dome a
			# front, and a full ring reads as decoration.
			# Radius follows the ellipse at that height (r * sqrt(1 - t^2)),
			# plus a little proud of it. Sitting at a flat fraction of rx put
			# them inside the dome's own skin at anything but the base.
			var shoulder_t = 0.42
			var shoulder_y = drum_h + dome_h * shoulder_t
			var shoulder_r = sqrt(max(0.0, 1.0 - shoulder_t * shoulder_t)) * 0.92
			for i in range(4):
				var a = (float(i) / 4.0) * TAU + PI / 4.0
				_hardware(parent_node, "struct_vision_block",
					Vector3(cos(a) * rx * shoulder_r, shoulder_y, sin(a) * rz * shoulder_r),
					Vector3(0, -a + PI / 2.0, 0), 2.0)

			# Crown hatch. This is the single detail that gives the dome a
			# human scale reference - without it a stretched hemisphere has
			# nothing in it to read size against.
			# Uniformly upscaled - see _hardware()'s uniform_scale note. At
			# authored fastener size the hatch read as a coin on the crown
			# instead of as the crew-scale reference that gives the dome its
			# sense of size.
			_hardware(parent_node, "struct_dome_hatch",
				Vector3(0, base_size.y * 0.97, 0), Vector3.ZERO, 2.6)

		# --- SLAB: a ribbed armour deck plate -------------------------------
		elif type_id == "structural_slab":
			var plate = MeshInstance3D.new()
			var slab_box = BoxMesh.new()
			slab_box.size = Vector3(base_size.x * 0.97, base_size.y, base_size.z * 0.97)
			plate.mesh = slab_box
			plate.material_override = s_body
			plate.position = Vector3(0, base_size.y / 2.0, 0)
			parent_node.add_child(plate)

			# Rolled beads down all four edges - the slab's whole silhouette
			# is its edge, so this is where the read is won or lost.
			for sx in [-1.0, 1.0]:
				var bx = MeshInstance3D.new()
				var bx_cyl = CylinderMesh.new()
				# Slimmer than the plate is thick, and tucked inboard. At 0.30
				# these read as two enormous rolled logs bolted to a thin
				# plate rather than as the plate's own rolled edge.
				bx_cyl.top_radius = base_size.y * 0.20
				bx_cyl.bottom_radius = base_size.y * 0.20
				bx_cyl.height = base_size.z
				bx.mesh = bx_cyl
				bx.material_override = s_trim
				bx.position = Vector3(sx * base_size.x * 0.470, base_size.y * 0.5, 0)
				bx.rotation = Vector3(PI / 2.0, 0, 0)
				parent_node.add_child(bx)
			for sz in [-1.0, 1.0]:
				var bz = MeshInstance3D.new()
				var bz_cyl = CylinderMesh.new()
				bz_cyl.top_radius = base_size.y * 0.20
				bz_cyl.bottom_radius = base_size.y * 0.20
				bz_cyl.height = base_size.x
				bz.mesh = bz_cyl
				bz.material_override = s_trim
				bz.position = Vector3(0, base_size.y * 0.5, sz * base_size.z * 0.470)
				bz.rotation = Vector3(0, 0, PI / 2.0)
				parent_node.add_child(bz)

			# Stiffener ribs on the UNDERSIDE, running across the short axis -
			# where they'd actually be on a real deck plate, and where they
			# don't fight the walkable top surface.
			var s_ribs = _hardware_count(base_size.x, 0.70)
			for i in range(s_ribs):
				var t = (float(i) + 0.5) / float(s_ribs) - 0.5
				_hardware(parent_node, "struct_stiffener_rib",
					Vector3(t * base_size.x * 0.88, 0.0, 0.0),
					Vector3(PI, 0, 0))

			# Non-slip step cleats along the top, plus corner brackets laid
			# flat at each corner.
			var cleats = _hardware_count(base_size.x, 0.85, 2, 10)
			for i in range(cleats):
				var t = (float(i) + 0.5) / float(cleats) - 0.5
				_hardware(parent_node, "struct_step_cleat",
					Vector3(t * base_size.x * 0.80, base_size.y, 0.0), Vector3.ZERO)
			_deck_tie_downs(parent_node, base_size, base_size.y, 1.15)

		# --- WEDGE: a sloped glacis breech ----------------------------------
		elif type_id == "structural_wedge":
			# The mesh already spans y 0..size.y from its own origin, so it
			# sits flush on the mount at position ZERO. The old +y/2 offset
			# floated the whole piece half its own height off the surface it
			# was bolted to.
			var wedge = MeshInstance3D.new()
			wedge.mesh = _build_wedge_mesh(base_size)
			wedge.material_override = s_body
			parent_node.add_child(wedge)

			# Gussets braced against both flanks at the base of the slope.
			var g_count = _hardware_count(base_size.z, 0.85, 2, 8)
			for sx in [-1.0, 1.0]:
				for i in range(g_count):
					var t = (float(i) + 0.5) / float(g_count) - 0.5
					_hardware(parent_node, "struct_gusset",
						Vector3(sx * base_size.x * 0.49, 0.0, t * base_size.z * 0.80),
						Vector3(0, 0.0 if sx > 0.0 else PI, 0))

			# Step cleats climbing the sloped face, so the slope reads as
			# something a crew would walk up rather than a bare ramp. Placed
			# ON the glacis via _wedge_slope_point() and pitched to lie flat
			# against it, rather than guessed at along a straight diagonal -
			# with a real wedge under them now, a guess visibly floats.
			var pitch = _wedge_slope_pitch(base_size)
			var steps = _hardware_count(base_size.z, 0.62, 2, 9)
			for i in range(steps):
				var t = (float(i) + 0.5) / float(steps)
				_hardware(parent_node, "struct_step_cleat",
					_wedge_slope_point(base_size, t), Vector3(pitch, PI / 2.0, 0))

			# Bolt pads along the base skirt.
			var pads = _hardware_count(base_size.z, 0.80, 2, 8)
			for sx in [-1.0, 1.0]:
				for i in range(pads):
					var t = (float(i) + 0.5) / float(pads) - 0.5
					_hardware(parent_node, "struct_bolt_pad",
						Vector3(sx * base_size.x * 0.44, 0.01, t * base_size.z * 0.82),
						Vector3.ZERO)

		# --- GIRDER: an open lattice truss ----------------------------------
		elif type_id == "structural_girder":
			var rail_w = max(0.05, base_size.x * 0.30)
			var rail_h = max(0.05, base_size.y * 0.30)
			var half_gap_x = (base_size.x - rail_w) / 2.0
			var half_gap_y = (base_size.y - rail_h) / 2.0

			# Four chords, one at each corner of the section - a real truss,
			# not the two-rail ladder this used to be.
			for sx in [-1.0, 1.0]:
				for sy in [0.0, 1.0]:
					var rail = MeshInstance3D.new()
					var rail_box = BoxMesh.new()
					rail_box.size = Vector3(rail_w, rail_h, base_size.z)
					rail.mesh = rail_box
					rail.material_override = s_trim
					rail.position = Vector3(sx * half_gap_x, rail_h / 2.0 + sy * half_gap_y * 2.0, 0)
					parent_node.add_child(rail)

			# Zigzag lattice web between the chords. Bay COUNT scales with
			# length, bay SIZE does not, so a long girder reads as a long
			# truss instead of a stretched one.
			var bays = _hardware_count(base_size.z, 0.55, 2, 32)
			var bay_len = base_size.z / float(bays)
			var diag_len = sqrt(bay_len * bay_len + base_size.y * base_size.y)
			var diag_thick = rail_h * 0.55
			for sx in [-1.0, 1.0]:
				for i in range(bays):
					var z0 = -base_size.z / 2.0 + (float(i) + 0.5) * bay_len
					var diag = MeshInstance3D.new()
					var diag_box = BoxMesh.new()
					diag_box.size = Vector3(diag_thick, diag_thick, diag_len)
					diag.mesh = diag_box
					diag.material_override = s_dark
					diag.position = Vector3(sx * half_gap_x, base_size.y / 2.0, z0)
					# Alternating tilt gives the classic W-truss web.
					var tilt = atan2(base_size.y, bay_len)
					diag.rotation = Vector3(tilt if i % 2 == 0 else -tilt, 0, 0)
					parent_node.add_child(diag)

			_beam_hardware(parent_node, base_size)

		# --- I-BEAM: a rolled section frame ---------------------------------
		elif type_id == "structural_i_beam":
			var flange_thick = max(0.03, base_size.y * 0.15)
			var flange_width = max(0.05, base_size.x * 0.85)
			var web_thick = max(0.03, base_size.x * 0.16)
			var web_height = max(0.01, base_size.y - 2.0 * flange_thick)

			for y in [flange_thick / 2.0, base_size.y - flange_thick / 2.0]:
				var fl = MeshInstance3D.new()
				var fl_box = BoxMesh.new()
				fl_box.size = Vector3(flange_width, flange_thick, base_size.z)
				fl.mesh = fl_box
				fl.material_override = s_trim
				fl.position = Vector3(0, y, 0)
				parent_node.add_child(fl)

			var web = MeshInstance3D.new()
			var web_box = BoxMesh.new()
			web_box.size = Vector3(web_thick, web_height, base_size.z)
			web.mesh = web_box
			web.material_override = s_body
			web.position = Vector3(0, flange_thick + web_height / 2.0, 0)
			parent_node.add_child(web)

			# Web gussets at fixed stations, braced into both flanges - the
			# detail that turns a plain extruded I into a fabricated beam.
			var stations = _hardware_count(base_size.z, 0.80, 2, 16)
			for i in range(stations):
				var t = (float(i) + 0.5) / float(stations) - 0.5
				for sx in [-1.0, 1.0]:
					_hardware(parent_node, "struct_gusset",
						Vector3(sx * web_thick * 0.6, flange_thick, t * base_size.z * 0.88),
						Vector3(0, 0.0 if sx > 0.0 else PI, 0))
				# Bolt pad on the top flange at the same station.
				_hardware(parent_node, "struct_bolt_pad",
					Vector3(0, base_size.y, t * base_size.z * 0.88), Vector3.ZERO)

			_beam_hardware(parent_node, base_size)

	elif type_id in ["mk19_grenade_launcher", "autocannon", "recoilless_rifle", "coil_gun",
					 "ballista", "napalm_mortar", "mine_layer", "smoke_discharger",
					 "anti_materiel_rifle", "arc_projector", "microwave_emitter",
					 "particle_lance", "spigot_mortar", "rocket_artillery",
					 "hypervelocity_missile", "sam_launcher", "loitering_munition",
					 "anti_radiation_missile", "bunker_buster", "cruise_missile",
					 "chaff_dispenser", "laser_dazzler", "aps_interceptor",
					 "aa_autocannon", "jammer_mast", "sentry_deployer",
					 "sensor_beacon_launcher", "decoy_projector"]:
		# --- Roster expansion ------------------------------------------------
		# Assembled from authored .glb sub-parts (tools/blender/
		# build_roster_expansion.py) exactly like basic_cannon and the HMG
		# above, each with a primitive fallback so a broken or missing import
		# degrades to a readable shape rather than to nothing.
		#
		# The sub-part SPLIT is load-bearing, not cosmetic: every part a tweak
		# has to resize is its own mesh with its own origin, so barrel_length
		# stretches only the tube (never the breech, sight or grips),
		# drum_size scales only the magazine, and repeated parts (coils,
		# mines, discharger tubes) can be instanced N times. That is why, for
		# example, recoilless_breech and recoilless_tube are two files.
		var caliber = tweaks.get("caliber", 1.0)
		var length = tweaks.get("barrel_length", 1.0)

		match type_id:
			"mk19_grenade_launcher", "autocannon":
				var is_mk19 = type_id == "mk19_grenade_launcher"
				var prefix = "mk19" if is_mk19 else "autocannon"
				var trunnion_y = 0.25 if is_mk19 else 0.24
				var drum_scale = tweaks.get("drum_size", 1.0)

				# 1. CRADLE MOUNT
				var mount_mesh = _part(prefix + "_mount")
				if not mount_mesh:
					mount_mesh = _part("hmg_pintle_mount")
				if mount_mesh:
					var mount = _mesh_inst(mount_mesh, base_color.darkened(0.25))
					mount.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(mount)
				else:
					var mount = MeshInstance3D.new()
					var m_box = BoxMesh.new()
					m_box.size = Vector3(0.34 * caliber, trunnion_y, 0.34 * caliber)
					mount.mesh = m_box
					mount.material_override = _flat_mat(base_color.darkened(0.25))
					mount.position = Vector3(0, trunnion_y / 2.0, 0)
					parent_node.add_child(mount)

				# 2. RECEIVER - scaled by caliber only, never by barrel length
				var rec_mesh = _part(prefix + "_receiver")
				if not rec_mesh:
					rec_mesh = _part("hmg_receiver")
				# MEASURED from each receiver's own .glb AABB, not shared and
				# not estimated: the MK19's front face sits at z = -0.16, the
				# remodelled M230's at -0.102. They used one shared -0.16,
				# which left the autocannon's barrel floating 0.058 clear of
				# its receiver - the same defect the anti-materiel rifle had.
				# Re-measure if either mesh changes.
				var rec_front_z = (MK19_RECEIVER_FRONT_Z if is_mk19 else AUTOCANNON_RECEIVER_FRONT_Z) * caliber
				if rec_mesh:
					var receiver = _mesh_inst(rec_mesh, Color(0.20, 0.22, 0.23))
					receiver.scale = Vector3(caliber, caliber, caliber)
					receiver.position = Vector3(0, trunnion_y, 0)
					parent_node.add_child(receiver)
				else:
					var receiver = MeshInstance3D.new()
					var r_box = BoxMesh.new()
					r_box.size = Vector3(0.17, 0.20, 0.42) * caliber
					receiver.mesh = r_box
					receiver.material_override = _flat_mat(Color(0.20, 0.22, 0.23))
					receiver.position = Vector3(0, trunnion_y, 0)
					parent_node.add_child(receiver)

				# 3. BARREL - the only part barrel_length touches
				var bar_mesh = _part(prefix + "_barrel")
				if not bar_mesh:
					bar_mesh = _part("hmg_barrel")
				if bar_mesh:
					var barrel = _mesh_inst(bar_mesh, Color(0.13, 0.14, 0.15))
					barrel.scale = Vector3(caliber, caliber, length * caliber)
					barrel.position = Vector3(0, trunnion_y, rec_front_z)
					parent_node.add_child(barrel)
				else:
					var barrel = MeshInstance3D.new()
					var b_cyl = CylinderMesh.new()
					b_cyl.top_radius = (0.075 if is_mk19 else 0.042) * caliber
					b_cyl.bottom_radius = (0.085 if is_mk19 else 0.055) * caliber
					b_cyl.height = (0.4 if is_mk19 else 0.85) * length
					barrel.mesh = b_cyl
					barrel.material_override = _flat_mat(Color(0.13, 0.14, 0.15))
					barrel.position = Vector3(0, trunnion_y, rec_front_z - b_cyl.height / 2.0)
					barrel.rotation = Vector3(PI / 2, 0, 0)
					parent_node.add_child(barrel)

				# 4. AMMO CAN - the only part drum_size touches
				var can_mesh = _part(prefix + ("_ammo_can" if is_mk19 else "_ammo_box"))
				if not can_mesh:
					can_mesh = _part("ammo_drum")
				if can_mesh:
					var can = _mesh_inst(can_mesh, Color(0.22, 0.26, 0.18))
					can.scale = Vector3.ONE * drum_scale * caliber
					# The M230's magazine is a linkless drum 0.28 units deep,
					# which simply does not fit under a receiver whose
					# trunnion sits 0.24 above the deck - so it mounts BEHIND
					# the gun and stands on the deck instead, which is also
					# where an ammunition drum that size would really go.
					# Its floor tracks drum_size so a big drum grows upward
					# rather than sinking through the deck.
					var can_y = trunnion_y * 0.85
					var can_z = 0.0
					if not is_mk19:
						can_y = AUTOCANNON_DRUM_FLOOR * drum_scale * caliber
						can_z = AUTOCANNON_DRUM_Z * caliber
					can.position = Vector3(0, can_y, can_z)
					parent_node.add_child(can)
				else:
					var can = MeshInstance3D.new()
					var c_box = BoxMesh.new()
					c_box.size = Vector3(0.19, 0.20, 0.24) * drum_scale * caliber
					can.mesh = c_box
					can.material_override = _flat_mat(Color(0.22, 0.26, 0.18))
					can.position = Vector3(-0.16 * drum_scale * caliber, trunnion_y * 0.85, 0)
					parent_node.add_child(can)

			"anti_materiel_rifle":
				# Long, thin, deliberate. The proportions are the point: the
				# breech runs back THROUGH the trunnions rather than hanging
				# off them, so the gun reads as balanced about its middle,
				# and the tube is long enough that the muzzle brake has to be
				# its own part or barrel_length would stretch the baffles.
				#
				# The Z constants below are MEASURED off the authored meshes'
				# own AABBs, not estimated. They were estimated originally,
				# and the barrel ended up mounted 0.11 units in front of the
				# breech's actual face - visibly floating in mid-air. Any
				# change to the .glb geometry has to re-measure them; a probe
				# that prints Mesh.get_aabb() for each part is the check.
				var amr_trunnion_y = 0.28
				var optic = tweaks.get("optic_power", 1.0)
				var bipod_down = tweaks.get("bipod_deploy", 0.0) >= 0.5

				# 1. TRUNNION CRADLE
				var amr_mount_mesh = _part("amr_mount")
				if not amr_mount_mesh:
					amr_mount_mesh = _part("pintle_mount")
				if amr_mount_mesh:
					var amr_mount = _mesh_inst(amr_mount_mesh, base_color.darkened(0.25))
					amr_mount.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(amr_mount)
				else:
					var amr_mount = MeshInstance3D.new()
					var am_cyl = CylinderMesh.new()
					am_cyl.top_radius = 0.13 * caliber
					am_cyl.bottom_radius = 0.20 * caliber
					am_cyl.height = amr_trunnion_y
					amr_mount.mesh = am_cyl
					amr_mount.material_override = _flat_mat(base_color.darkened(0.25))
					amr_mount.position = Vector3(0, amr_trunnion_y / 2.0, 0)
					parent_node.add_child(amr_mount)

				# 2. BREECH - scaled by caliber only. barrel_length must never
				#    touch it, or the sight rail and feed chutes stretch too.
				var amr_has_breech = _part("amr_breech") != null
				var amr_breech_front_z = (AMR_BREECH_FRONT_Z if amr_has_breech else -0.52) * caliber
				if amr_has_breech:
					var amr_breech = _mesh_inst(_part("amr_breech"), Color(0.20, 0.22, 0.21))
					amr_breech.scale = Vector3.ONE * caliber
					amr_breech.position = Vector3(0, amr_trunnion_y, 0)
					parent_node.add_child(amr_breech)
				else:
					var amr_breech = MeshInstance3D.new()
					var ab_box = BoxMesh.new()
					ab_box.size = Vector3(0.30, 0.33, 1.04) * caliber
					amr_breech.mesh = ab_box
					amr_breech.material_override = _flat_mat(Color(0.20, 0.22, 0.21))
					amr_breech.position = Vector3(0, amr_trunnion_y, 0.15 * caliber)
					parent_node.add_child(amr_breech)

				# 3. BARREL - the only part barrel_length touches.
				var amr_bar_mesh = _part("amr_barrel")
				if not amr_bar_mesh:
					amr_bar_mesh = _part("barrel_thin")
				var amr_barrel_len: float
				if amr_bar_mesh:
					amr_barrel_len = AMR_BARREL_LEN * length * caliber
					var amr_barrel = _mesh_inst(amr_bar_mesh, Color(0.13, 0.14, 0.15))
					amr_barrel.scale = Vector3(caliber, caliber, length * caliber)
					amr_barrel.position = Vector3(0, amr_trunnion_y, amr_breech_front_z)
					parent_node.add_child(amr_barrel)
				else:
					amr_barrel_len = 0.95 * length * caliber
					var amr_barrel = MeshInstance3D.new()
					var abr_cyl = CylinderMesh.new()
					abr_cyl.top_radius = 0.035 * caliber
					abr_cyl.bottom_radius = 0.048 * caliber
					abr_cyl.height = amr_barrel_len
					amr_barrel.mesh = abr_cyl
					amr_barrel.material_override = _flat_mat(Color(0.13, 0.14, 0.15))
					amr_barrel.position = Vector3(0, amr_trunnion_y, amr_breech_front_z - amr_barrel_len / 2.0)
					amr_barrel.rotation = Vector3(PI / 2, 0, 0)
					parent_node.add_child(amr_barrel)

				# 4. MUZZLE BRAKE - own part, positioned at the barrel's ACTUAL
				#    tip so a longer barrel moves it rather than stretching it.
				var amr_brake_mesh = _part("amr_muzzle_brake")
				if not amr_brake_mesh:
					amr_brake_mesh = _part("muzzle_brake")
				if amr_brake_mesh:
					var amr_brake = _mesh_inst(amr_brake_mesh, Color(0.115, 0.10, 0.095))
					amr_brake.scale = Vector3.ONE * caliber
					amr_brake.position = Vector3(0, amr_trunnion_y, amr_breech_front_z - amr_barrel_len)
					parent_node.add_child(amr_brake)

				# 5. SENSOR HEAD - camera + LIDAR, not a scope. optic_power is
				#    the only thing that scales it, and it scales UNIFORMLY: a
				#    better sensor head is a bigger one, not a stretched one.
				var amr_pod_mesh = _part("amr_sensor_pod")
				if not amr_pod_mesh:
					amr_pod_mesh = _part("sensor_dome")
				if amr_pod_mesh:
					var amr_pod = _mesh_inst(amr_pod_mesh, Color(0.17, 0.19, 0.18))
					amr_pod.scale = Vector3.ONE * caliber * optic
					amr_pod.position = Vector3(-0.20 * caliber, amr_trunnion_y + 0.12 * caliber, 0.02 * caliber)
					parent_node.add_child(amr_pod)

				# 6. RECOIL BUFFER + HYDRAULICS - deliberately oversized, out
				#    the back past the breech's rear face. Caliber only: this
				#    absorbs the shot, it has nothing to do with barrel length.
				var amr_buf_mesh = _part("amr_buffer")
				if amr_buf_mesh:
					var amr_buf = _mesh_inst(amr_buf_mesh, Color(0.19, 0.20, 0.21))
					amr_buf.scale = Vector3.ONE * caliber
					amr_buf.position = Vector3(0, amr_trunnion_y, AMR_BUFFER_Z * caliber)
					parent_node.add_child(amr_buf)

				# 7. BIPOD - present ONLY when deployed. The tweak has a real
				#    combat effect (auto_weapon._bipod_blocks_firing), so it
				#    has to be visible on the model or the player has no way
				#    to tell a deployed rifle from a stowed one at a glance.
				if bipod_down:
					var amr_bipod_mesh = _part("amr_bipod")
					if amr_bipod_mesh:
						var amr_bipod = _mesh_inst(amr_bipod_mesh, Color(0.18, 0.19, 0.20))
						amr_bipod.scale = Vector3.ONE * caliber
						amr_bipod.position = Vector3(0, 0.0, amr_breech_front_z * 1.4)
						parent_node.add_child(amr_bipod)

			"arc_projector":
				# Jacob's-ladder apparatus, not a gun. The transformer body
				# sits BEHIND the trunnion and is most of the module's mass -
				# it is both the counterweight the balance test wants and the
				# visible answer to "where does the charge come from".
				var arc_trunnion_y = 0.352
				var contain = tweaks.get("containment", 1.0)

				var arc_mount_mesh = _part("arc_projector_mount")
				if arc_mount_mesh:
					var am = _mesh_inst(arc_mount_mesh, base_color.darkened(0.25))
					am.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(am)

				var arc_body_mesh = _part("arc_projector_body")
				if arc_body_mesh:
					var ab = _mesh_inst(arc_body_mesh, Color(0.22, 0.24, 0.26))
					ab.scale = Vector3.ONE * caliber
					ab.position = Vector3(0, arc_trunnion_y, 0)
					parent_node.add_child(ab)

				# The ONLY part containment scales - the field emitter and its
				# electrodes. Measured: the body's front face is at z=-0.040.
				var arc_em_mesh = _part("arc_projector_emitter")
				if arc_em_mesh:
					var ae = _mesh_inst(arc_em_mesh, Color(0.30, 0.33, 0.36),
						Color(0.35, 0.85, 1.0), 0.7)
					ae.scale = Vector3.ONE * caliber * contain
					ae.position = Vector3(0, arc_trunnion_y, ARC_BODY_FRONT_Z * caliber)
					parent_node.add_child(ae)

			"microwave_emitter":
				# The dish IS the silhouette; nothing else in the roster has
				# one. The magnetron can behind the trunnion is the ballast
				# that stops a 2.0-aperture dish tipping the module forward.
				var mw_trunnion_y = 0.262
				var dish = tweaks.get("dish_aperture", 1.0)

				var mw_mount_mesh = _part("microwave_mount")
				if mw_mount_mesh:
					var mm = _mesh_inst(mw_mount_mesh, base_color.darkened(0.25))
					mm.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(mm)

				var mw_body_mesh = _part("microwave_body")
				if mw_body_mesh:
					var mb = _mesh_inst(mw_body_mesh, Color(0.24, 0.25, 0.27))
					mb.scale = Vector3.ONE * caliber
					mb.position = Vector3(0, mw_trunnion_y, 0)
					parent_node.add_child(mb)

				# The ONLY part dish_aperture scales, and uniformly - a bigger
				# dish is a bigger dish, not a stretched one.
				var mw_dish_mesh = _part("microwave_dish")
				if mw_dish_mesh:
					var md = _mesh_inst(mw_dish_mesh, Color(0.62, 0.62, 0.60))
					md.scale = Vector3.ONE * caliber * dish
					md.position = Vector3(0, mw_trunnion_y, MICROWAVE_BODY_FRONT_Z * caliber)
					parent_node.add_child(md)

			"particle_lance":
				# Charge-up heavy. The capacitor stack out the back is both
				# the counterweight and the thing charge_time scales, which is
				# the read the tweak needs: a longer wind-up is visibly more
				# stored charge bolted to the back of the gun.
				var pl_trunnion_y = 0.318
				var charge = tweaks.get("charge_time", 1.0)
				var focal = tweaks.get("focal_length", 1.0)

				var pl_mount_mesh = _part("lance_mount")
				if pl_mount_mesh:
					var pm = _mesh_inst(pl_mount_mesh, base_color.darkened(0.25))
					pm.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(pm)

				var pl_breech_mesh = _part("lance_breech")
				if pl_breech_mesh:
					var pb = _mesh_inst(pl_breech_mesh, Color(0.21, 0.23, 0.25))
					pb.scale = Vector3.ONE * caliber
					pb.position = Vector3(0, pl_trunnion_y, 0)
					parent_node.add_child(pb)

				# UNIFORM scale, and no emission. Scaling only Z stretched the
				# individual capacitor cans into long tubes - the exact
				# smearing the part-separation rule exists to prevent - and a
				# 0.35 emission on the whole part turned the stack into one
				# solid glowing slab that read as a lightsaber rather than as
				# stored charge. Uniform keeps every can's proportions, and
				# the glow belongs on the accelerator when it fires, not baked
				# into the battery.
				var pl_cap_mesh = _part("lance_capacitors")
				if pl_cap_mesh:
					var pc = _mesh_inst(pl_cap_mesh, Color(0.28, 0.30, 0.34))
					pc.scale = Vector3.ONE * caliber * charge
					pc.position = Vector3(0, pl_trunnion_y, LANCE_BREECH_REAR_Z * caliber)
					parent_node.add_child(pc)

				var pl_acc_mesh = _part("lance_accelerator")
				if pl_acc_mesh:
					var pa = _mesh_inst(pl_acc_mesh, Color(0.16, 0.18, 0.21))
					pa.scale = Vector3(caliber, caliber, focal * caliber)
					pa.position = Vector3(0, pl_trunnion_y, LANCE_BREECH_FRONT_Z * caliber)
					parent_node.add_child(pa)

			"spigot_mortar":
				# The bomb is bigger than the weapon. A spigot has no barrel:
				# the round slides OVER a rod, so rod_thickness and
				# payload_size scale two genuinely separate parts and the
				# silhouette changes shape rather than just size.
				var sp_trunnion_y = 0.250
				var sp_rod = tweaks.get("rod_thickness", 1.0)
				var sp_pay = tweaks.get("payload_size", 1.0)
				var sp_elev = deg_to_rad(50.0)

				var sp_mount_mesh = _part("spigot_mount")
				if sp_mount_mesh:
					var spm = _mesh_inst(sp_mount_mesh, base_color.darkened(0.25))
					spm.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(spm)

				var sp_pivot = Node3D.new()
				sp_pivot.name = "ElevationPivot"
				sp_pivot.position = Vector3(0, sp_trunnion_y, 0)
				sp_pivot.rotation = Vector3(sp_elev, 0, 0)
				parent_node.add_child(sp_pivot)

				var sp_breech_mesh = _part("spigot_breech")
				if sp_breech_mesh:
					var spb = _mesh_inst(sp_breech_mesh, Color(0.21, 0.22, 0.20))
					spb.scale = Vector3.ONE * caliber
					sp_pivot.add_child(spb)

				var sp_rod_mesh = _part("spigot_rod")
				if sp_rod_mesh:
					var spr = _mesh_inst(sp_rod_mesh, Color(0.14, 0.15, 0.16))
					spr.scale = Vector3(sp_rod * caliber, sp_rod * caliber, caliber)
					spr.position = Vector3(0, 0, SPIGOT_BREECH_FRONT_Z * caliber)
					sp_pivot.add_child(spr)

				var sp_bomb_mesh = _part("spigot_bomb")
				if sp_bomb_mesh:
					var spbomb = _mesh_inst(sp_bomb_mesh, Color(0.30, 0.32, 0.26))
					spbomb.scale = Vector3.ONE * sp_pay * caliber
					# Sits ON the rod, not at its tip - the rod runs up inside
					# the bomb, which is what a spigot mortar actually does.
					spbomb.position = Vector3(0, 0, (SPIGOT_BREECH_FRONT_Z - 0.20) * caliber)
					sp_pivot.add_child(spbomb)

			"rocket_artillery":
				# tube_count spawns more RAILS rather than scaling one, so the
				# rack visibly grows. Damage is split across the salvo (see
				# _fire_rocket_artillery), so this is a spread slider and not
				# a free upgrade.
				var ra_trunnion_y = 0.272
				var ra_rails = clampi(int(tweaks.get("tube_count", 4.0)), 2, 8)
				var ra_elev = deg_to_rad(32.0)

				var ra_mount_mesh = _part("rocket_arty_mount")
				if ra_mount_mesh:
					var ram = _mesh_inst(ra_mount_mesh, base_color.darkened(0.25))
					ram.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(ram)

				var ra_pivot = Node3D.new()
				ra_pivot.name = "ElevationPivot"
				ra_pivot.position = Vector3(0, ra_trunnion_y, 0)
				ra_pivot.rotation = Vector3(ra_elev, 0, 0)
				parent_node.add_child(ra_pivot)

				var ra_cradle_mesh = _part("rocket_arty_cradle")
				if ra_cradle_mesh:
					var rac = _mesh_inst(ra_cradle_mesh, Color(0.22, 0.24, 0.21))
					rac.scale = Vector3.ONE * caliber
					ra_pivot.add_child(rac)

				var ra_rail_mesh = _part("rocket_arty_rail")
				if ra_rail_mesh:
					# Two rows when there are more than four, so a big rack
					# reads as a rack rather than as a very wide comb.
					var rows = 2 if ra_rails > 4 else 1
					var per_row = int(ceil(float(ra_rails) / float(rows)))
					var placed = 0
					for row in range(rows):
						for i in range(per_row):
							if placed >= ra_rails:
								break
							placed += 1
							var t = 0.0 if per_row == 1 else (float(i) / float(per_row - 1) - 0.5)
							var rail = _mesh_inst(ra_rail_mesh, Color(0.26, 0.27, 0.24))
							rail.scale = Vector3.ONE * caliber
							rail.position = Vector3(t * 0.26 * caliber,
								row * 0.13 * caliber,
								ROCKET_CRADLE_FRONT_Z * caliber)
							ra_pivot.add_child(rail)

			"hypervelocity_missile", "sam_launcher", "loitering_munition", \
			"anti_radiation_missile", "bunker_buster", "cruise_missile":
				# The six guided launchers share one authored pedestal and one
				# assembly path, differing in the body that gives each its
				# identity and in what it carries. That is honest reuse - they
				# genuinely are the same class of bolt-on launcher - and it
				# keeps six near-identical pedestal .glbs out of the repo.
				var ml_trunnion_y = 0.242
				var ml_spec = MISSILE_LAUNCHER_PARTS[type_id]
				var ml_count = clampi(int(tweaks.get("tube_count", ml_spec["default_count"])), 1, 4)
				var ml_cant = deg_to_rad(ml_spec["cant_deg"])

				var ml_ped_mesh = _part("missile_pedestal")
				if ml_ped_mesh:
					var mlp = _mesh_inst(ml_ped_mesh, base_color.darkened(0.25))
					mlp.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(mlp)

				var ml_pivot = Node3D.new()
				ml_pivot.name = "ElevationPivot"
				ml_pivot.position = Vector3(0, ml_trunnion_y, 0)
				ml_pivot.rotation = Vector3(ml_cant, 0, 0)
				parent_node.add_child(ml_pivot)

				var ml_body_mesh = _part(ml_spec["body"])
				if ml_body_mesh:
					var mlb = _mesh_inst(ml_body_mesh, Color(0.21, 0.23, 0.25))
					mlb.scale = Vector3.ONE * caliber
					ml_pivot.add_child(mlb)

				var ml_round_mesh = _part(ml_spec["round"])
				if ml_round_mesh:
					# Single-round launchers (bunker buster, cruise) mount on
					# the centreline; multi-round ones spread across the body.
					var singles = ml_spec["default_count"] == 1
					var n = 1 if singles else ml_count
					for i in range(n):
						var t = 0.0 if n == 1 else (float(i) / float(n - 1) - 0.5)
						var rnd = _mesh_inst(ml_round_mesh, Color(ml_spec["tint"]))
						rnd.scale = Vector3.ONE * caliber * float(tweaks.get(ml_spec["scale_tweak"], 1.0))
						rnd.position = Vector3(t * 0.20 * caliber, 0.0,
							float(ml_spec["front_z"]) * caliber)
						ml_pivot.add_child(rnd)

			"chaff_dispenser":
				# Never points at anything, so no trunnion and no elevation
				# pivot - the tubes are fixed and splayed. Same family as the
				# smoke discharger, deliberately.
				var cd_tubes = clampi(int(tweaks.get("tube_count", 4.0)), 2, 8)
				var cd_body_mesh = _part("chaff_body")
				if cd_body_mesh:
					var cdb = _mesh_inst(cd_body_mesh, base_color.darkened(0.1))
					cdb.scale = Vector3.ONE * caliber
					parent_node.add_child(cdb)
				var cd_tube_mesh = _part("chaff_tube")
				if cd_tube_mesh:
					for i in range(cd_tubes):
						var t = 0.0 if cd_tubes == 1 else (float(i) / float(cd_tubes - 1) - 0.5)
						var tube = _mesh_inst(cd_tube_mesh, Color(0.30, 0.31, 0.27))
						tube.scale = Vector3.ONE * caliber
						tube.position = Vector3(t * 0.30 * caliber, 0.24 * caliber, -0.05 * caliber)
						# Splayed OUTWARD and canted up. Sign checked against
						# the smoke discharger's own splay bug: the leftmost
						# tube must yaw left, not inward.
						tube.rotation = Vector3(deg_to_rad(-55.0), lerp(0.30, -0.30, float(i) / maxf(1.0, float(cd_tubes - 1))), 0)
						parent_node.add_child(tube)

			"laser_dazzler":
				var dz_trunnion_y = 0.196
				var dz_mount_mesh = _part("dazzler_mount")
				if dz_mount_mesh:
					var dzm = _mesh_inst(dz_mount_mesh, base_color.darkened(0.25))
					dzm.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(dzm)
				var dz_head_mesh = _part("dazzler_head")
				if dz_head_mesh:
					var dzh = _mesh_inst(dz_head_mesh, Color(0.22, 0.24, 0.26),
						Color(0.35, 0.95, 0.5), 0.5)
					dzh.scale = Vector3.ONE * caliber * float(tweaks.get("lens_aperture", 1.0))
					dzh.position = Vector3(0, dz_trunnion_y, 0)
					parent_node.add_child(dzh)

			"aps_interceptor":
				# Covers the whole arc at once, so it does not traverse and
				# has no trunnion - the launcher ring IS the weapon.
				var aps_mesh = _part("aps_body")
				if aps_mesh:
					var apsb = _mesh_inst(aps_mesh, base_color.darkened(0.1),
						Color(1.0, 0.6, 0.25), 0.25)
					apsb.scale = Vector3.ONE * caliber
					parent_node.add_child(apsb)

			"aa_autocannon":
				var aa_trunnion_y = 0.268
				var aa_len = tweaks.get("barrel_length", 1.0)
				var aa_mount_mesh = _part("aa_mount")
				if aa_mount_mesh:
					var aam = _mesh_inst(aa_mount_mesh, base_color.darkened(0.25))
					aam.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(aam)
				# High fixed elevation - it is looking up, which is the point.
				var aa_pivot = Node3D.new()
				aa_pivot.name = "ElevationPivot"
				aa_pivot.position = Vector3(0, aa_trunnion_y, 0)
				aa_pivot.rotation = Vector3(deg_to_rad(38.0), 0, 0)
				parent_node.add_child(aa_pivot)
				var aa_rec_mesh = _part("aa_receiver")
				if aa_rec_mesh:
					var aar = _mesh_inst(aa_rec_mesh, Color(0.22, 0.24, 0.22))
					aar.scale = Vector3.ONE * caliber
					aa_pivot.add_child(aar)
				var aa_bar_mesh = _part("aa_barrel")
				if aa_bar_mesh:
					for side in [-1.0, 1.0]:
						var bar = _mesh_inst(aa_bar_mesh, Color(0.13, 0.14, 0.15))
						bar.scale = Vector3(caliber, caliber, aa_len * caliber)
						bar.position = Vector3(side * 0.055 * caliber, 0, AA_RECEIVER_FRONT_Z * caliber)
						aa_pivot.add_child(bar)

			"jammer_mast":
				# No barrel, no traverse, no shot. Reads as equipment.
				var jm_mesh = _part("jammer_body")
				if jm_mesh:
					var jmb = _mesh_inst(jm_mesh, base_color.darkened(0.1),
						Color(0.4, 0.8, 0.95), 0.30)
					jmb.scale = Vector3(caliber, float(tweaks.get("mast_height", 1.0)), caliber)
					parent_node.add_child(jmb)

			"sentry_deployer":
				var sd_rack_mesh = _part("sentry_rack")
				if sd_rack_mesh:
					var sdr = _mesh_inst(sd_rack_mesh, base_color.darkened(0.1))
					sdr.scale = Vector3.ONE * caliber
					parent_node.add_child(sdr)
				# Loaded sentries visible in the rack, using the SAME mesh the
				# deployed turret uses - what you see loaded is what you get.
				var sd_turret_mesh = _part("sentry_turret")
				if sd_turret_mesh:
					var loaded = clampi(int(tweaks.get("hangar_size", 2.0)), 1, 3)
					for i in range(loaded):
						var st = _mesh_inst(sd_turret_mesh, Color(0.27, 0.29, 0.24))
						st.scale = Vector3.ONE * caliber * 0.72
						st.position = Vector3(0, (0.10 + i * 0.115) * caliber, 0.02 * caliber)
						parent_node.add_child(st)

			"sensor_beacon_launcher":
				var sb_body_mesh = _part("beacon_body")
				if sb_body_mesh:
					var sbb = _mesh_inst(sb_body_mesh, base_color.darkened(0.1))
					sbb.scale = Vector3.ONE * caliber
					parent_node.add_child(sbb)
				var sb_tube_mesh = _part("beacon_tube")
				if sb_tube_mesh:
					var sbt = _mesh_inst(sb_tube_mesh, Color(0.26, 0.29, 0.25))
					sbt.scale = Vector3.ONE * caliber
					sbt.position = Vector3(0, 0.196 * caliber, -0.02 * caliber)
					sbt.rotation = Vector3(deg_to_rad(58.0), 0, 0)
					parent_node.add_child(sbt)

			"decoy_projector":
				var dp_mesh = _part("decoy_body")
				if dp_mesh:
					var dpb = _mesh_inst(dp_mesh, base_color.darkened(0.05))
					dpb.scale = Vector3.ONE * caliber
					parent_node.add_child(dpb)

			"recoilless_rifle":
				var trunnion_y = 0.27

				# 1. TRIPOD MOUNT
				var rr_mount_mesh = _part("recoilless_mount")
				if not rr_mount_mesh:
					rr_mount_mesh = _part("pintle_mount")
				if rr_mount_mesh:
					var mount = _mesh_inst(rr_mount_mesh, base_color.darkened(0.25))
					mount.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(mount)
				else:
					var mount = MeshInstance3D.new()
					var m_cyl = CylinderMesh.new()
					m_cyl.top_radius = 0.10 * caliber
					m_cyl.bottom_radius = 0.16 * caliber
					m_cyl.height = trunnion_y
					mount.mesh = m_cyl
					mount.material_override = _flat_mat(base_color.darkened(0.25))
					mount.position = Vector3(0, trunnion_y / 2.0, 0)
					parent_node.add_child(mount)

				# 2. BREECH + SIGHT + GRIP - fixed hardware, caliber only
				var breech_mesh = _part("recoilless_breech")
				if breech_mesh:
					var breech = _mesh_inst(breech_mesh, Color(0.24, 0.23, 0.20))
					breech.scale = Vector3(caliber, caliber, caliber)
					breech.position = Vector3(0, trunnion_y, 0)
					parent_node.add_child(breech)

				# 3. TUBE - grows forward with barrel_length, nothing else moves
				var rr_tube_mesh = _part("recoilless_tube")
				if not rr_tube_mesh:
					rr_tube_mesh = _part("barrel_standard")
				if rr_tube_mesh:
					var tube = _mesh_inst(rr_tube_mesh, Color(0.26, 0.25, 0.21))
					tube.scale = Vector3(caliber, caliber, length * caliber)
					tube.position = Vector3(0, trunnion_y, -0.045 * caliber)
					parent_node.add_child(tube)
				else:
					var tube = MeshInstance3D.new()
					var t_cyl = CylinderMesh.new()
					t_cyl.top_radius = 0.062 * caliber
					t_cyl.bottom_radius = 0.062 * caliber
					t_cyl.height = 0.8 * length
					tube.mesh = t_cyl
					tube.material_override = _flat_mat(Color(0.26, 0.25, 0.21))
					tube.position = Vector3(0, trunnion_y, -0.045 - t_cyl.height / 2.0)
					tube.rotation = Vector3(PI / 2, 0, 0)
					parent_node.add_child(tube)

				# 4. VENTURI - sits at the BREECH end, so it is deliberately
				# independent of barrel_length: the backblast nozzle points
				# where _fire_recoilless_rifle()'s damage cone goes, and that
				# must not drift when the tube is lengthened.
				var ven_mesh = _part("recoilless_venturi")
				if not ven_mesh:
					ven_mesh = _part("exhaust_cone")
				if ven_mesh:
					var venturi = _mesh_inst(ven_mesh, Color(0.12, 0.12, 0.12))
					venturi.scale = Vector3(caliber, caliber, caliber)
					venturi.position = Vector3(0, trunnion_y, 0.10 * caliber)
					parent_node.add_child(venturi)

			"coil_gun":
				var trunnion_y = 0.27
				# Stage count drives BOTH the coil instance count and the rail
				# length, so the tweak reads as "a longer accelerator with more
				# stages" rather than just a number changing.
				var stage_tweak = tweaks.get("rail_length", 1.0)
				var stages = clamp(int(round(stage_tweak * 5.0)), 3, 9)

				# 1. MOUNT
				var cg_mount_mesh = _part("coilgun_mount")
				if not cg_mount_mesh:
					cg_mount_mesh = _part("railgun_pintle_mount")
				if cg_mount_mesh:
					var mount = _mesh_inst(cg_mount_mesh, base_color.darkened(0.25))
					mount.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(mount)
				else:
					var mount = MeshInstance3D.new()
					var m_box = BoxMesh.new()
					m_box.size = Vector3(0.38 * caliber, trunnion_y, 0.38 * caliber)
					mount.mesh = m_box
					mount.material_override = _flat_mat(base_color.darkened(0.25))
					mount.position = Vector3(0, trunnion_y / 2.0, 0)
					parent_node.add_child(mount)

				# 2. BREECH - fixed, never stretched by the stage tweak
				var cg_breech_mesh = _part("coilgun_breech")
				if cg_breech_mesh:
					var breech = _mesh_inst(cg_breech_mesh, Color(0.22, 0.25, 0.28))
					breech.scale = Vector3(caliber, caliber, caliber)
					breech.position = Vector3(0, trunnion_y, 0)
					parent_node.add_child(breech)

				# 3. RAIL SPINE
				var rail_mesh = _part("coilgun_rail")
				if not rail_mesh:
					rail_mesh = _part("railgun_rails")
				var rail_z = -0.04 * caliber
				if rail_mesh:
					var rail = _mesh_inst(rail_mesh, Color(0.24, 0.27, 0.30))
					rail.scale = Vector3(caliber, caliber, stage_tweak * caliber)
					rail.position = Vector3(0, trunnion_y, rail_z)
					parent_node.add_child(rail)
				else:
					var rail = MeshInstance3D.new()
					var r_box = BoxMesh.new()
					r_box.size = Vector3(0.085 * caliber, 0.075 * caliber, 0.8 * stage_tweak)
					rail.mesh = r_box
					rail.material_override = _flat_mat(Color(0.24, 0.27, 0.30))
					rail.position = Vector3(0, trunnion_y, rail_z - r_box.size.z / 2.0)
					parent_node.add_child(rail)

				# 4. ACCELERATOR COILS - one instance per stage, spread along
				# the rail's actual (scaled) length so they always sit ON it.
				var coil_mesh = _part("coilgun_coil")
				var rail_span = 0.78 * stage_tweak * caliber
				for i in range(stages):
					var t = float(i) / float(max(1, stages - 1))
					var cz = rail_z - 0.06 * caliber - t * rail_span
					if coil_mesh:
						var coil = _mesh_inst(coil_mesh, Color(0.62, 0.36, 0.14))
						coil.scale = Vector3.ONE * caliber
						coil.position = Vector3(0, trunnion_y, cz)
						parent_node.add_child(coil)
					else:
						var coil = MeshInstance3D.new()
						var c_cyl = CylinderMesh.new()
						c_cyl.top_radius = 0.11 * caliber
						c_cyl.bottom_radius = 0.11 * caliber
						c_cyl.height = 0.05
						coil.mesh = c_cyl
						coil.material_override = _flat_mat(Color(0.62, 0.36, 0.14))
						coil.position = Vector3(0, trunnion_y, cz)
						coil.rotation = Vector3(PI / 2, 0, 0)
						parent_node.add_child(coil)

				# 5. CAPACITOR BANK
				var cap_mesh = _part("coilgun_capacitors")
				if not cap_mesh:
					cap_mesh = _part("railgun_capacitor_housing")
				if cap_mesh:
					var caps = _mesh_inst(cap_mesh, Color(0.30, 0.33, 0.36))
					caps.scale = Vector3.ONE * caliber
					caps.position = Vector3(0, trunnion_y * 0.45, 0.14 * caliber)
					parent_node.add_child(caps)

			"napalm_mortar":
				var trunnion_y = 0.18
				# Steep fixed elevation, applied as a pivot rotation on the
				# tube group rather than baked into the mesh - the same
				# approach ARTILLERY_ELEVATION_DEG/MORTAR_ELEVATION_DEG use.
				# SIGN: positive, same as ARTILLERY_/MORTAR_ELEVATION_DEG. The
				# parts are authored with the bore along -Z, and a POSITIVE X
				# rotation pitches -Z upward. This read -55.0, which pitched
				# the assembly nose-down through the deck - the flared muzzle
				# ended up below the breech, which is what made the barrel
				# look like it had been fitted upside down.
				var elev = deg_to_rad(NAPALM_ELEVATION_DEG)

				# 1. BASEPLATE
				var np_mount_mesh = _part("napalm_mount")
				if not np_mount_mesh:
					np_mount_mesh = _part("mortar_swivel_mount")
				if np_mount_mesh:
					var mount = _mesh_inst(np_mount_mesh, base_color.darkened(0.3))
					mount.scale = Vector3(caliber, 1.0, caliber)
					parent_node.add_child(mount)
				else:
					var mount = MeshInstance3D.new()
					var m_cyl = CylinderMesh.new()
					m_cyl.top_radius = 0.12 * caliber
					m_cyl.bottom_radius = 0.24 * caliber
					m_cyl.height = trunnion_y
					mount.mesh = m_cyl
					mount.material_override = _flat_mat(base_color.darkened(0.3))
					mount.position = Vector3(0, trunnion_y / 2.0, 0)
					parent_node.add_child(mount)

				# Elevation pivot carries breech + tube together so they stay
				# aligned at any barrel_length.
				var elev_pivot = Node3D.new()
				elev_pivot.name = "ElevationPivot"
				elev_pivot.position = Vector3(0, trunnion_y, 0)
				elev_pivot.rotation = Vector3(elev, 0, 0)
				parent_node.add_child(elev_pivot)

				# 2. BREECH CAP
				var np_breech_mesh = _part("napalm_breech")
				if np_breech_mesh:
					var breech = _mesh_inst(np_breech_mesh, Color(0.30, 0.28, 0.24))
					breech.scale = Vector3(caliber, caliber, caliber)
					elev_pivot.add_child(breech)

				# 3. TUBE
				var np_tube_mesh = _part("napalm_tube")
				if not np_tube_mesh:
					np_tube_mesh = _part("mortar_tube_single")
				if np_tube_mesh:
					var tube = _mesh_inst(np_tube_mesh, Color(0.32, 0.30, 0.26))
					tube.scale = Vector3(caliber, caliber, length * caliber)
					elev_pivot.add_child(tube)
				else:
					var tube = MeshInstance3D.new()
					var t_cyl = CylinderMesh.new()
					t_cyl.top_radius = 0.13 * caliber
					t_cyl.bottom_radius = 0.115 * caliber
					t_cyl.height = 0.55 * length
					tube.mesh = t_cyl
					tube.material_override = _flat_mat(Color(0.32, 0.30, 0.26))
					tube.position = Vector3(0, 0, -t_cyl.height / 2.0)
					tube.rotation = Vector3(PI / 2, 0, 0)
					elev_pivot.add_child(tube)

				# 4. FUEL DRUM - deliberately OUTSIDE the elevation pivot: the
				# drum is hull-mounted plumbing, it doesn't swing with the tube.
				var drum_mesh = _part("napalm_fuel_drum")
				if not drum_mesh:
					drum_mesh = _part("fuel_tank")
				if drum_mesh:
					var drum = _mesh_inst(drum_mesh, Color(0.52, 0.24, 0.09))
					drum.scale = Vector3.ONE * caliber
					drum.position = Vector3(-0.22 * caliber, 0, 0.10 * caliber)
					parent_node.add_child(drum)

			"mine_layer":
				# Mines-per-volley and charge size are both visible on the
				# rack: more mines means more canisters loaded, a bigger
				# charge means bigger canisters.
				var mine_rows = clamp(int(tweaks.get("tube_count", 1.0)), 1, 4)
				var pay = tweaks.get("payload_size", 1.0)

				# 1. RACK CHASSIS
				var rack_mesh = _part("mine_layer_rack")
				if rack_mesh:
					var rack = _mesh_inst(rack_mesh, base_color.darkened(0.15))
					parent_node.add_child(rack)
				else:
					var rack = MeshInstance3D.new()
					var rk_box = BoxMesh.new()
					rk_box.size = Vector3(0.46, 0.32, 0.56)
					rack.mesh = rk_box
					rack.material_override = _flat_mat(base_color.darkened(0.15))
					rack.position = Vector3(0, 0.16, 0)
					parent_node.add_child(rack)

				# 2. LOADED MINE CANISTERS - two per row, rows from the tweak
				var can2_mesh = _part("mine_canister")
				if not can2_mesh:
					can2_mesh = _part("canister_small")
				for row in range(mine_rows):
					for col in range(2):
						var cz = -0.18 + row * 0.13
						var cx = (col - 0.5) * 0.19
						if can2_mesh:
							var m = _mesh_inst(can2_mesh, Color(0.28, 0.30, 0.18))
							m.scale = Vector3.ONE * pay
							m.position = Vector3(cx, 0.31, cz)
							parent_node.add_child(m)
						else:
							var m = MeshInstance3D.new()
							var mc = CylinderMesh.new()
							mc.top_radius = 0.085 * pay
							mc.bottom_radius = 0.085 * pay
							mc.height = 0.07 * pay
							m.mesh = mc
							m.material_override = _flat_mat(Color(0.28, 0.30, 0.18))
							m.position = Vector3(cx, 0.34, cz)
							parent_node.add_child(m)

				# 3. DISPENSER CHUTE
				var chute_mesh = _part("mine_layer_chute")
				if chute_mesh:
					var chute = _mesh_inst(chute_mesh, Color(0.19, 0.20, 0.17))
					chute.position = Vector3(0, 0.08, 0.28)
					parent_node.add_child(chute)

			"ballista":
				# 1. TURNTABLE + TIMBER FRAME
				var frame_mesh = _part("ballista_frame")
				if frame_mesh:
					var frame = _mesh_inst(frame_mesh, base_color)
					frame.scale = Vector3(length, 1.0, 1.0)
					parent_node.add_child(frame)
				else:
					var frame = MeshInstance3D.new()
					var f_box = BoxMesh.new()
					f_box.size = Vector3(0.60 * length, 0.28, 0.63)
					frame.mesh = f_box
					frame.material_override = _flat_mat(base_color)
					frame.position = Vector3(0, 0.14, 0)
					parent_node.add_child(frame)

				var frame_top = 0.28

				# 2. STOCK + WINDLASS - draw length stretches the stock
				var stock_mesh = _part("ballista_stock")
				if stock_mesh:
					var stock = _mesh_inst(stock_mesh, base_color.lightened(0.05))
					stock.scale = Vector3(1.0, 1.0, length)
					stock.position = Vector3(0, frame_top, 0)
					parent_node.add_child(stock)

				# 3. TORSION BUNDLES + THROWING ARMS - mirrored pair. The
				# authored part is the LEFT arm; the right is the same mesh
				# with a negative X scale, which is why it is one file.
				var arm_mesh = _part("ballista_arm")
				for side in [-1.0, 1.0]:
					if arm_mesh:
						var arm = _mesh_inst(arm_mesh, base_color.darkened(0.08))
						arm.scale = Vector3(side * length, 1.0, 1.0)
						arm.position = Vector3(side * 0.17, frame_top - 0.02, -0.22 * length)
						parent_node.add_child(arm)
					else:
						var arm = MeshInstance3D.new()
						var a_box = BoxMesh.new()
						a_box.size = Vector3(0.05, 0.05, 0.30 * length)
						arm.mesh = a_box
						arm.material_override = _flat_mat(base_color.darkened(0.08))
						arm.position = Vector3(side * 0.20, frame_top + 0.08, -0.30 * length)
						arm.rotation = Vector3(0, side * 0.45, 0)
						parent_node.add_child(arm)

				# 4. LOADED BOLT - caliber is bolt thickness
				var bolt_mesh = _part("ballista_bolt")
				if bolt_mesh:
					var bolt = _mesh_inst(bolt_mesh, Color(0.24, 0.22, 0.19))
					bolt.scale = Vector3(caliber, caliber, length)
					bolt.position = Vector3(0, frame_top + 0.075, -0.10 * length)
					parent_node.add_child(bolt)

			"smoke_discharger":
				var tube_count = clamp(int(tweaks.get("tube_count", 4.0)), 2, 6)

				# 1. BRACKET
				var br_mesh = _part("smoke_discharger_bracket")
				if br_mesh:
					var bracket = _mesh_inst(br_mesh, base_color.darkened(0.2))
					parent_node.add_child(bracket)
				else:
					var bracket = MeshInstance3D.new()
					var br_box = BoxMesh.new()
					br_box.size = Vector3(0.36, 0.12, 0.24)
					bracket.mesh = br_box
					bracket.material_override = _flat_mat(base_color.darkened(0.2))
					bracket.position = Vector3(0, 0.06, 0)
					parent_node.add_child(bracket)

				# 2. LAUNCHER TUBES - one instance per tube, canted up and
				# splayed OUTWARD.
				#
				# The splay sign matters and is easy to get backwards (it was,
				# first time round - the bank converged into a point instead
				# of fanning out). Weapons face -Z, and a POSITIVE yaw about
				# +Y turns -Z toward -X. So the tube at the most negative X -
				# the leftmost, i == 0 - needs a POSITIVE yaw to lean further
				# left, i.e. outward. The lerp therefore runs from + down to
				# -, matching x running from - up to +.
				var tube_mesh = _part("smoke_discharger_tube")
				var spacing = 0.30 / max(1, tube_count - 1) if tube_count > 1 else 0.0
				var start_x = -0.15 if tube_count > 1 else 0.0
				for i in range(tube_count):
					var splay = 0.0
					if tube_count > 1:
						splay = lerp(0.25, -0.25, float(i) / float(tube_count - 1))
					var tx = start_x + i * spacing
					if tube_mesh:
						var tube = _mesh_inst(tube_mesh, Color(0.20, 0.21, 0.19))
						tube.position = Vector3(tx, 0.12, 0)
						tube.rotation = Vector3(deg_to_rad(35.0), splay, 0)
						parent_node.add_child(tube)
					else:
						var tube = MeshInstance3D.new()
						var t_cyl = CylinderMesh.new()
						t_cyl.top_radius = 0.048
						t_cyl.bottom_radius = 0.055
						t_cyl.height = 0.24
						tube.mesh = t_cyl
						tube.material_override = _flat_mat(Color(0.20, 0.21, 0.19))
						tube.position = Vector3(tx, 0.12, 0)
						tube.rotation = Vector3(deg_to_rad(-55.0), splay, 0)
						parent_node.add_child(tube)

	else:
		# Fallback: Simple box mesh for armor and basic parts
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = base_size
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color
		mesh_inst.material_override = mat
		mesh_inst.position = Vector3(0, base_size.y / 2.0, 0)
		parent_node.add_child(mesh_inst)

	# Apply deformations to the newly constructed meshes based on the tweaks
	_apply_tweak_deformations(type_id, parent_node, tweaks, base_size)

	var protectedness = tweaks.get("protectedness", 0.0)
	if protectedness > 0.0 and type_id not in LOCOMOTION_MODULAR_TYPES and type_id != "drone_carrier" and type_id != "resource_harvester" and type_id != "repair_array" and type_id != "sensor_suite" and not type_id.begins_with("structural_"):
		_build_weapon_armor(parent_node, int(protectedness), base_size, base_color, tweaks)



# Dispatcher for GlobalConfig.enable_animated_monolithic_parts: attaches the
# same named moving-part pivots the procedural fallback builds, on top of a
# monolithic authored body. No-op for any type_id without a moving-part
# helper - a monolithic body renders exactly as it did before this feature
# unless it's one of the types listed here.
#
# CAVEAT worth checking visually once this is toggled on: unlike a cannon
# barrel (which pokes out beyond its housing either way), a TripoSG-authored
# monolithic mesh for a rotor/propeller/dish/wing type may already sculpt
# the blades/dish/membrane INTO the single mesh. If so, attaching a second
# procedural copy on top will double the geometry rather than animate the
# existing one - inspect each type after enabling the flag and drop its
# _attach_moving_parts() case below if that's what's happening (the fix at
# that point is authoring the monolithic mesh WITHOUT the moving piece, not
# a code change here).
static func _attach_moving_parts(type_id: String, parent_node: Node3D, base_size: Vector3, base_color: Color, tweaks: Dictionary):
	match type_id:
		"rotary_cannon":
			_attach_rotary_barrels(parent_node, base_size, tweaks)
		"helicopter_rotors":
			_attach_rotor_blades(parent_node, base_size)
		"ornithopter_wing":
			_attach_ornithopter_pivot(parent_node, base_size, base_color)
		"sensor_suite":
			_attach_radar_dish(parent_node, base_size, base_color)
		"naval_propeller":
			_attach_naval_propeller_blades(parent_node, base_size)
		"ship_screw":
			_attach_ship_screw_blades(parent_node, base_size)
		"paddle_wheel":
			_attach_paddle_wheel_blades(parent_node, base_size, base_color)
		"propeller_prop":
			_attach_propeller_blades(parent_node, base_size, base_color, false)
		"pusher_prop":
			_attach_propeller_blades(parent_node, base_size, base_color, true)


# Barrel ring for rotary_cannon, wrapped under a "BarrelCluster" pivot so it
# can spin independently of the (static) base/mount - see auto_weapon.gd.
static func _attach_rotary_barrels(parent_node: Node3D, base_size: Vector3, tweaks: Dictionary):
	var pivot = Node3D.new()
	pivot.name = "BarrelCluster"
	parent_node.add_child(pivot)

	var b_count = int(tweaks.get("barrel_count", 6.0))
	b_count = clamp(b_count, 3, 9)
	var caliber = tweaks.get("caliber", 1.0)
	var length = tweaks.get("barrel_length", 1.0)

	var trunnion_y = 0.24 * caliber
	pivot.position = Vector3(0, trunnion_y, 0)

	var barrel_mesh = _part("rotary_barrel_single")
	var clamp_mesh = _part("rotary_clamp_ring")

	var ring_r = 0.12 * caliber

	for i in range(b_count):
		var angle = i * (2.0 * PI / b_count)
		var barrel: MeshInstance3D
		var offset_x = cos(angle) * ring_r
		var offset_y = sin(angle) * ring_r

		if barrel_mesh:
			barrel = _mesh_inst(barrel_mesh, Color(0.15, 0.16, 0.18))
			barrel.scale = Vector3(caliber, caliber, length * caliber)
			barrel.position = Vector3(offset_x, offset_y, 0)
		else:
			barrel = MeshInstance3D.new()
			var b_cyl = CylinderMesh.new()
			b_cyl.top_radius = 0.024 * caliber
			b_cyl.bottom_radius = 0.024 * caliber
			b_cyl.height = 1.10 * length
			barrel.mesh = b_cyl
			var b_mat = StandardMaterial3D.new()
			b_mat.albedo_color = Color(0.15, 0.16, 0.18)
			barrel.material_override = b_mat
			barrel.position = Vector3(offset_x, offset_y, -(1.10 * length / 2.0))
			barrel.rotation = Vector3(PI / 2, 0, 0)
		pivot.add_child(barrel)

	if clamp_mesh:
		var clamp_inst = _mesh_inst(clamp_mesh, Color(0.20, 0.22, 0.24))
		var clamp_scale_xy = (ring_r + 0.05 * caliber) / 0.18
		clamp_inst.scale = Vector3(clamp_scale_xy, clamp_scale_xy, caliber)
		clamp_inst.position = Vector3(0, 0, -0.60 * length * caliber)
		pivot.add_child(clamp_inst)


# Spinning radar grid dish for sensor_suite, named "RadarDish" (already spun
# directly by auto_weapon.gd - see get_node_or_null("RadarDish") there, no
# rename needed since it was never nested under another pivot).
static func _attach_radar_dish(parent_node: Node3D, base_size: Vector3, base_color: Color):
	var dish = MeshInstance3D.new()
	dish.name = "RadarDish"
	var dish_cyl = CylinderMesh.new()
	dish_cyl.top_radius = base_size.x * 0.6
	dish_cyl.bottom_radius = base_size.x * 0.6
	dish_cyl.height = 0.06
	dish.mesh = dish_cyl
	var dish_mat = StandardMaterial3D.new()
	dish_mat.albedo_color = base_color
	dish.material_override = dish_mat
	dish.position = Vector3(0, base_size.y, 0)
	dish.rotation = Vector3(PI / 2 - 0.2, 0, 0)
	parent_node.add_child(dish)

static func _attach_rotor_blades(parent_node: Node3D, base_size: Vector3):
	var pivot = Node3D.new()
	pivot.name = "RotorBlades"
	var shaft_h = base_size.y * 0.8
	pivot.position = Vector3(0, shaft_h, 0)
	parent_node.add_child(pivot)
	var blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.1, 0.1, 0.1)
	var blades = MeshInstance3D.new()
	var blade_mesh = BoxMesh.new()
	blade_mesh.size = Vector3(base_size.x, 0.03, 0.2)
	blades.mesh = blade_mesh
	blades.material_override = blade_mat
	pivot.add_child(blades)

static func _attach_ornithopter_pivot(parent_node: Node3D, base_size: Vector3, base_color: Color):
	var pivot = Node3D.new()
	pivot.name = "WingPivot"
	pivot.position = Vector3(base_size.x * 0.2, base_size.y * 0.15, 0)
	parent_node.add_child(pivot)

static func _attach_naval_propeller_blades(parent_node: Node3D, base_size: Vector3):
	var pivot = Node3D.new()
	pivot.name = "PropBlades"
	parent_node.add_child(pivot)
	for i in range(3):
		var blade = MeshInstance3D.new()
		var blade_box = BoxMesh.new()
		blade_box.size = Vector3(0.04, base_size.x * 0.7, 0.12)
		blade.mesh = blade_box
		var blade_mat = StandardMaterial3D.new()
		blade_mat.albedo_color = Color.SILVER
		blade.material_override = blade_mat
		blade.position = Vector3(0, 0, base_size.z * 0.4)
		blade.rotate_z(i * (TAU / 3.0))
		pivot.add_child(blade)


## The wheel mount: an angled driveshaft housing running up and inboard into a
## gearbox, with the hub hanging off the outboard end of it.
##
## Authored once, here, because Chris called the pontoon version "excellent" and
## asked for the same assembly on the screw drive and the legs. It works for the
## same reason the original wheel mounting did: the locomotion module's origin
## ALREADY SITS AT THE HULL'S UNDERSIDE (module_placer.gd puts it there), so a
## shaft angling up and inboard from a point just below that origin arrives
## inside the hull's solid volume by construction - no hull measurement, no
## reach solving, no subframe to bridge a gap that was never open. That
## invariant is the whole trick, and it is why four types can share one mount.
##
## `s` scales the whole assembly, `z` slides it fore/aft, `span` is its
## thickness along Z (a dually cluster or a wide drum wants a fatter housing).
## Returns the outboard hub position in the parent's local space so the caller
## can hang a wheel, a drum end or a leg on it without redoing the arithmetic.
## `hub_drop` overrides how far the hub hangs below the origin. A wheel wants
## the default (the mount is as deep as the wheel is big); a screw drum wants to
## hang well clear so the hull rides high over terrain, WITHOUT inflating the
## gearbox to get there. The driveshaft lengthens to match, so it still arrives
## inside the hull however deep the hub goes.
static func build_wheel_mount(parent_node: Node3D, base_color: Color,
		s: float = 1.0, z: float = 0.0, span: float = 0.3,
		hub_drop: float = -1.0) -> Vector3:
	var hub_y: float = -0.2 * s if hub_drop < 0.0 else -hub_drop
	var gearbox_x := -0.24 * s
	var ds_mesh := _part("wheel_driveshaft")
	var gb_mesh := _part("wheel_gearbox")
	if ds_mesh:
		# wheel_driveshaft is authored spanning Y=0 (top/pivot) to Y=-1
		# (bottom), so its bottom end after scale+rotation is
		# `position + Rz(angle)*(0,-len,0)`. Anchor the BOTTOM at the gearbox
		# and solve the pivot backward from it: the fixed end is the one that
		# has to meet the hub, and the free end is the one that should be
		# allowed to run as deep into the hull as the angle takes it.
		var shaft := _mesh_inst(ds_mesh, base_color.darkened(0.25).lightened(0.35))
		# Default depth keeps the original 55 degrees and length verbatim - the
		# wheels' look is settled and must not drift.
		#
		# A DEEP hub is a different structural problem: holding 55 degrees just
		# makes the strut longer, and at a full drum-diameter drop the two
		# struts ran so far inboard they crossed past each other under the hull
		# centreline. A deep leg should get STEEPER, not longer. So the angle is
		# solved from the drop instead: rise is whatever it takes to clear the
		# hull's underside, run is a bounded step inboard.
		var shaft_angle := deg_to_rad(55.0)
		var shaft_len: float = 1.0 * s
		if hub_drop >= 0.0:
			var rise: float = absf(hub_y) + 0.25 * s
			var run: float = 0.55 * s
			shaft_angle = atan2(run, rise)
			shaft_len = sqrt(run * run + rise * rise)
		var bottom_target := Vector3(gearbox_x + 0.05 * s, hub_y, z)
		var drop := Vector3(sin(shaft_angle), -cos(shaft_angle), 0.0) * shaft_len
		shaft.scale = Vector3(0.32 * s, shaft_len, span)
		shaft.position = bottom_target - drop
		shaft.rotation = Vector3(0, 0, shaft_angle)
		parent_node.add_child(shaft)
	if gb_mesh:
		var gearbox := _mesh_inst(gb_mesh, base_color.darkened(0.1).lightened(0.3))
		var gb := 0.46 * s
		gearbox.scale = Vector3(gb, gb, span)
		gearbox.position = Vector3(gearbox_x, hub_y, z)
		parent_node.add_child(gearbox)
	# Pulled slightly INBOARD of the module origin, not outboard: the hub and
	# the gearbox should visibly overlap rather than sit adjacent (Chris's ask,
	# twice, on the original wheels).
	#
	# Chris reported the wheels "angling inward rather than outward from the
	# hull" and this offset was the obvious suspect, but it was not the cause -
	# the stations themselves had collapsed onto the centreline (see the
	# missing `else` in locomotion_layout.gd's x_offset block). This value is
	# left where it was rather than "fixed" alongside the real bug.
	return Vector3(-0.05 * s, hub_y, z)


static func _build_wheels(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.BLACK, tweaks: Dictionary = {}):
	var wheel_size = float(tweaks.get("wheel_size", tweaks.get("size", 1.0)))
	var w_per_axle = int(tweaks.get("wheels_per_axle", 1.0))

	# Strict GLB part mesh loading - fails with assertion if asset is missing
	var wheel_mesh = _part("wheel_hub")

	var cluster_width = 0.3 * wheel_size * float(w_per_axle)

	# Lateral layout along local X. X=0 is the module's own local origin, i.e.
	# the hull mount point. build_wheel_mount() puts the gearbox inboard of it
	# and returns the hub point just outboard, keeping the whole cluster inside
	# the vehicle's footprint instead of hanging past its silhouette.
	var hub := build_wheel_mount(parent_node, base_color, wheel_size, 0.0, cluster_width)
	var hub_x_offset := hub.x
	var wheel_y := hub.y

	var spacing = 0.38 * wheel_size
	_repeat_along_axis(parent_node, w_per_axle, spacing, Vector3.RIGHT, func(p, pos, _idx):
		# Each wheel hangs under its own spin pivot rather than being parented
		# straight to the module. A wheel has to rotate about its OWN axle, and
		# the axle is offset from the module origin - spinning the module node
		# would swing the whole cluster around the mount point instead. Named
		# so battle_unit.gd can find it: same by-name pivot convention as
		# "RotorBlades", "PropBlades", "LegSwing" and "ScrewSpin".
		var axle = Node3D.new()
		axle.name = SPIN_PIVOT_WHEEL
		axle.position = pos + Vector3(hub_x_offset, wheel_y, 0)
		p.add_child(axle)
		var wheel = _mesh_inst(wheel_mesh, Color(0.1, 0.1, 0.12))
		wheel.scale = Vector3(wheel_size, wheel_size, wheel_size)
		# wheel_hub.glb's hub-cap/lug-bolt detail is authored at its +Y end
		# (the "outward-facing" side of the tire, per build_wheel() in
		# build_meshes.py) - rotation.z = -PI/2 (not +PI/2) maps that +Y face
		# to +X, i.e. outboard/away from the mount column above, so the
		# visible hub face points away from the vehicle instead of backwards
		# into the gearbox.
		wheel.rotation = Vector3(0, 0, -PI / 2.0)
		axle.add_child(wheel)
	)


# The numbers tread_belt_loop.glb was authored with (see _track_path in
# tools/blender/build_locomotion_rework.py). EVERY placement below derives from
# these, so the mesh and the runtime cannot disagree about where the sprocket
# centreline, the road-wheel line or the belt path are. When the mesh changes,
# these change in the same commit.
const BELT_HALF_SPAN := 2.6     # sprocket centre to idler centre, halved
const BELT_DRIVE_RADIUS := 0.46 # sprocket / idler radius
const BELT_ROAD_DROP := 0.38    # road-wheel centre below the sprocket centreline
const BELT_ROAD_RADIUS := 0.22  # road-wheel radius

static func _build_tracked_treads(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DARK_SLATE_GRAY, tweaks: Dictionary = {}):
	var width = tweaks.get("tread_width", tweaks.get("width", tweaks.get("size", 1.0)))
	# Fixed at 3 - Chris's ask, no longer a user tweak (was road_wheel_count,
	# 3-8 via a dedicated slider; removed along with the slider/catalog entry
	# in stat_calculator.gd/module_catalog.gd/module_placer.gd/module_data.gd).
	var road_wheels = 5
	var sprocket = tweaks.get("drive_sprocket", true)

	var loop_mesh = _part("tread_belt_loop")
	var sprocket_mesh = _part("drive_sprocket")
	var wheel_mesh = _part("wheel_hub")
	var gearbox_mesh = _part("wheel_gearbox")
	var driveshaft_mesh = _part("wheel_driveshaft")

	# Snap the tread's overall length to the actual hull it's mounted on
	# (target_length, passed in from module_placer.gd's update_locomotion() -
	# the tread's own catalog base_size.z is just a small placeholder with
	# no relationship to any specific hull, which is why the loop rendered
	# as a small oval regardless of hull size before this). Height scales up
	# PROPORTIONATELY from that same length ratio so the tread keeps its
	# authored shape instead of stretching into a thin snake on a long hull
	# or a squat blob on a short one. Sprockets end up centered at the
	# hull's own front/rear ends this way (extending past the hull is fine,
	# per Chris).
	#
	# actual_size.x deliberately does NOT fold in the tread_width tweak
	# (`width`) - it used to, which meant every X-axis size/position derived
	# from it (outboard_x, and via that sprocket_scale/wheel_scale/
	# belt_center_x) drifted with tread_width too, so dragging the Tread
	# Track Width slider visibly resized and repositioned the sprockets and
	# road wheels right along with the belt (Chris: only the belt loop
	# itself should widen). `width` is applied ONLY to the loop's own
	# lateral scale below now - everything else here is sized purely off
	# the hull.
	var target_length = tweaks.get("target_length", base_size.z)
	var length_scale = target_length / base_size.z
	var actual_size = Vector3(base_size.x * length_scale, base_size.y * length_scale, target_length)

	# Real rework, not a layout tweak: the belt is now a genuine closed
	# LOOP (tread_belt_loop, authored via bmesh.ops.spin in build_meshes.py)
	# that wraps all the way around the road-wheel/sprocket row, shaped as
	# an "inverted trapezoid" like a real modern track - Chris's ask - not a
	# plain symmetric oval: the top run is a simple straight line tangent to
	# both sprockets, but the bottom run dips DOWN by authored_drop between
	# two diagonal transitions, so the road wheels ride notably lower than
	# the sprocket axle line. Because the authored mesh is asymmetric
	# (top = +radius, bottom = -(radius+drop)), the loop's local origin is
	# NOT its vertical center - placement below has to account for that,
	# unlike the old symmetric-stadium math.
	# 0.48, up from 0.42. Chris, calibrating the roster against this type: the
	# treads are the one that is close to the right size, "if a bit too small
	# still". Since tracked_treads is now the sizing REFERENCE every other
	# ground type is judged against, it wants to be right first.
	var target_radius = actual_size.y * 0.48
	var target_half_span = actual_size.z * 0.5 - target_radius
	var authored_radius = 0.45
	var authored_drop = 0.4
	var authored_half_span = 1.0
	var y_scale = target_radius / authored_radius
	var target_drop = authored_drop * y_scale
	# Vertical offset from the loop's own local origin down to its lowest
	# point (the bottom of the trapezoid dip) - placing the loop/sprockets
	# at this height puts that lowest point at world Y=0 (ground), matching
	# where the road wheels also sit.
	var ground_offset = target_radius + target_drop

	# Drop the WHOLE assembly further down (Chris: "road wheels below the
	# hull altogether" - they were still clipping into the hull's
	# underside) - a uniform Y shift applied to every element below, purely
	# visual (the actual ground-contact collider is the separate invisible
	# running-gear StaticBody3D sized by ModuleCatalog.get_running_gear_size(),
	# untouched by this).
	var y_shift = -target_radius * 0.9

	# Move the WHOLE assembly (loop, sprockets, wheels, gearbox/driveshaft)
	# outboard along local X - originally 35% of the tread's own width, then
	# pulled back inboard by half that (Chris: "so the sprockets and
	# driveshafts intersect with the hull"), netting 17.5% outboard.
	# "Extending past the hull is fine" applies to length (Z); this is the
	# separate width (X) axis.
	var outboard_x = actual_size.x * 0.175

	# Both drive_sprocket and tread_belt_loop are authored with the same
	# 0.3 width along their own local Y/X (build_drive_sprocket's `width` and
	# build_tread_belt_loop's `belt_width` in build_meshes.py) - the sprocket
	# is a cylinder spanning local Y=[0, 0.3] that gets rotated so that span
	# maps to world X=[position.x - 0.3*sprocket_scale, position.x], i.e.
	# entirely INBOARD of its own position (see the wheel/sprocket rotation
	# comments below). The loop, unrotated, is symmetric about its own
	# position.x instead - so scaling it by the same sprocket_scale factor
	# alone still leaves half the loop hanging past the sprocket's outboard
	# face and the other half short of its inboard face. Deliberately NOT
	# multiplied by `width` (tread_width) - sprocket_scale also sizes the
	# actual sprockets/feeds belt_center_x below, and Chris's ask is for
	# tread_width to widen only the belt loop itself, not resize or reposition
	# the sprockets/wheels. Computed here (before the loop is built) so both
	# the loop and the sprockets below share one value.
	# ONE SCALE FOR THE WHOLE TRACK GROUP.
	#
	# The belt was scaled non-uniformly - y_scale on height, a separate
	# (half_span + radius) ratio on length - while the sprockets were scaled
	# uniformly by target_radius/0.4. Two different mappings cannot line up, so
	# the belt's end arcs were never the sprocket's radius and the track cut
	# THROUGH the sprockets instead of wrapping them (Chris's report). The belt
	# mesh is authored with the sprockets, road wheels and belt path all
	# coincident; scaling that one assembly uniformly keeps them coincident, and
	# is the only way they stay aligned at every hull size.
	#
	# tread_width still widens the belt alone, on top of this.
	var belt_scale: float = target_length / (BELT_HALF_SPAN * 2.0 + BELT_DRIVE_RADIUS * 2.0)
	var sprocket_scale = (BELT_DRIVE_RADIUS * belt_scale) / 0.4
	var sprocket_width_authored = 0.3
	# Center of the sprocket's own footprint (which sits entirely inboard of
	# outboard_x, its outer edge) - the loop anchors to THIS instead of
	# outboard_x directly, so it's centered over the sprocket's actual
	# footprint rather than straddling empty space past its outboard face.
	# BELT_OUTBOARD_NUDGE. The station moved INBOARD (locomotion_layout.gd's
	# x_inset_frac) so the mount struts bite into the hull; without this the
	# belt would have gone in with it and buried itself in the hull's side.
	# Chris asked for both at once: "they need to move in further, so their
	# struts actually intersect the hull, BUT the tread itself needs to move
	# outboard some, so that it sits on the sprockets and wheels, not embedded
	# in the hull." So the belt is pushed back out by the same amount the
	# station came in, and now rides just PROUD of the sprocket's outer face
	# rather than centred half a sprocket-width inboard of it.
	const BELT_OUTBOARD_NUDGE := 0.16
	var belt_center_x = outboard_x - sprocket_width_authored * 0.5 * sprocket_scale 		+ actual_size.x * BELT_OUTBOARD_NUDGE

	var loop: MeshInstance3D
	if loop_mesh:
		loop = _mesh_inst(loop_mesh, base_color)
		# `width` (tread_width tweak) applied ONLY here, on top of the
		# sprocket-covering baseline above - this is the one place tread_width
		# is allowed to affect the tracked_treads assembly (Chris: "just the
		# tread loop should get wider, the sprockets and wheels should stay
		# as is"). The loop grows/shrinks symmetrically around belt_center_x
		# (fixed, width-independent) rather than shifting it.
		# Uniform on height and length; width is the one axis tread_width owns.
		loop.scale = Vector3(sprocket_scale * width, belt_scale, belt_scale)
	else:
		loop = MeshInstance3D.new()
		var loop_box = BoxMesh.new()
		loop_box.size = Vector3(actual_size.x * width, actual_size.y, actual_size.z)
		loop.mesh = loop_box
		var loop_mat = StandardMaterial3D.new()
		loop_mat.albedo_color = base_color
		loop.material_override = loop_mat
	loop.position = Vector3(belt_center_x, ground_offset + y_shift, 0)
	parent_node.add_child(loop)

	# Sprockets at the true forward/rear corners, at the loop's own wrap-
	# circle height (ground_offset, matching the loop's local Z=0 - NOT
	# ground level itself, the sprocket axle sits above the road wheels),
	# sized to the loop's own wrap radius (authored drive_sprocket radius =
	# 0.4) so the belt visibly hugs them instead of floating around an
	# unrelated-sized wheel.
	if sprocket and sprocket_mesh:
		# Drive sprockets turn on their own axles, so each gets a named spin
		# pivot at its own station - rotating the module node would swing the
		# whole track assembly about the mount point instead.
		var sp_front_axle = Node3D.new()
		sp_front_axle.name = SPIN_PIVOT_TREAD
		sp_front_axle.position = Vector3(outboard_x, ground_offset + y_shift, -BELT_HALF_SPAN * belt_scale)
		parent_node.add_child(sp_front_axle)
		var sp_front = _mesh_inst(sprocket_mesh, Color(0.18, 0.18, 0.2))
		sp_front.scale = Vector3(sprocket_scale, sprocket_scale, sprocket_scale)
		sp_front.rotation = Vector3(0, 0, PI / 2.0)
		sp_front_axle.add_child(sp_front)

		var sp_rear_axle = Node3D.new()
		sp_rear_axle.name = SPIN_PIVOT_TREAD
		sp_rear_axle.position = Vector3(outboard_x, ground_offset + y_shift, BELT_HALF_SPAN * belt_scale)
		parent_node.add_child(sp_rear_axle)
		var sp_rear = _mesh_inst(sprocket_mesh, Color(0.18, 0.18, 0.2))
		sp_rear.scale = Vector3(sprocket_scale, sprocket_scale, sprocket_scale)
		sp_rear.rotation = Vector3(0, 0, PI / 2.0)
		sp_rear_axle.add_child(sp_rear)

	# Road wheels: smaller than the sprockets, riding low at true ground
	# level (Y=0, same as the loop's own lowest point - see ground_offset
	# above), evenly spaced strictly BETWEEN the two sprockets. Wheel radius
	# is derived from the resulting spacing (not a fixed constant) rather
	# than hardcoded, even though road_wheels is now fixed at 3, so it stays
	# consistent with how every other size here scales off the hull.
	# wheel_span keyed directly to the hull's own actual length (actual_size.z
	# == target_length) rather than target_half_span/sprocket spacing - Chris
	# wants all 3 road wheels clustered in the middle, spaced regularly
	# across the center 50% of the hull's length, not spread out toward the
	# sprockets. Outer wheels would land at +-wheel_span/2 (see
	# _repeat_along_axis), so half of actual_size.z puts them at +-25% of
	# hull length, i.e. the center 50% - sized off THIS span first so
	# wheel_radius_target doesn't shrink from the inward pull below.
	var wheel_span = BELT_HALF_SPAN * 2.0 * belt_scale * 0.62
	var spacing = wheel_span / float(max(1, road_wheels - 1)) if road_wheels > 1 else target_radius
	# Sized and seated from the AUTHORED belt profile, not independently.
	# tread_belt_loop is now a real track trapezoid (see _track_path in
	# tools/blender/build_locomotion_rework.py): sprockets on the centreline,
	# road wheels a fixed drop below it, belt bottom another road-radius below
	# that. Choosing the road wheel radius by its own rule left the wheels
	# hanging BELOW the belt instead of riding inside it - Chris's report - so
	# both radius and seat now come from the same constants the mesh was built
	# with, and the two cannot disagree.

	var wheel_radius_target = BELT_ROAD_RADIUS * belt_scale
	# Not multiplied by `width` (tread_width) - same reasoning as
	# sprocket_scale above, road wheels stay fixed size when the belt widens.
	var wheel_scale = wheel_radius_target / 0.45

	# Pull the outer wheels further in by half their own diameter (Chris's
	# ask, on top of the center-50%-of-hull-length span above) - shrinks the
	# span used for POSITIONING only, not the span used to size the wheels
	# above, so this doesn't shrink the wheels themselves, just tucks them in
	# closer together.
	wheel_span = max(0.0, wheel_span - wheel_radius_target * 2.0)
	spacing = wheel_span / float(max(1, road_wheels - 1)) if road_wheels > 1 else target_radius

	# Gearbox + driveshaft behind each road wheel, angled and sized to
	# actually intersect the wheel - Chris's ask. The earlier attempt
	# offset the gearbox by a fraction of the TREAD's overall width
	# (actual_size.x, which after hull-length scaling could be a couple of
	# units) instead of the wheel's own (much smaller) radius, so it
	# rendered nowhere near the wheel; fixed by basing every offset here on
	# wheel_radius_target instead. The driveshaft is anchored at its BOTTOM
	# (a fixed point inside the wheel/gearbox, guaranteeing the overlap)
	# with its TOP computed backward from length+angle, same trick used for
	# the wheels locomotion type's own driveshaft.
	# Where the hull's underside sits in this module's own local space, so the
	# suspension arms below can be solved to reach it rather than guessed.
	var hull_line_y: float = float(tweaks.get("kit_reach", 0.0))

	_repeat_along_axis(parent_node, road_wheels, spacing, Vector3.FORWARD, func(p, pos, _idx):
		var roller: MeshInstance3D
		if wheel_mesh:
			roller = _mesh_inst(wheel_mesh, Color.DARK_SLATE_GRAY)
			roller.scale = Vector3(wheel_scale, wheel_scale, wheel_scale)
		else:
			roller = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = wheel_radius_target
			cyl.bottom_radius = wheel_radius_target
			cyl.height = actual_size.x * 1.05
			roller.mesh = cyl
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.DARK_SLATE_GRAY
			roller.material_override = mat
		# Road wheels spin with the belt, same as the sprockets.
		var roller_axle = Node3D.new()
		roller_axle.name = SPIN_PIVOT_TREAD
		# Seated on the belt's own road-wheel line rather than on its own radius,
		# so the wheel sits INSIDE the loop with the bottom run passing under it.
		roller_axle.position = Vector3(outboard_x,
			ground_offset + y_shift - BELT_ROAD_DROP * belt_scale, pos.z)
		p.add_child(roller_axle)
		roller.rotation = Vector3(0, 0, PI / 2.0)
		roller_axle.add_child(roller)

		# Gearbox and driveshaft behind each road wheel - the original, restored.
		# It is anchored to the ROLLER's own axle rather than to a separately
		# computed height, which is what stranded it on the bottom run before.
		if gearbox_mesh:
			var gearbox = _mesh_inst(gearbox_mesh, base_color.darkened(0.15).lightened(0.25))
			var gb_size: float = wheel_radius_target * 1.2
			gearbox.scale = Vector3(gb_size, gb_size, gb_size)
			gearbox.position = Vector3(outboard_x - wheel_radius_target * 0.85,
				roller_axle.position.y, pos.z)
			p.add_child(gearbox)
		if driveshaft_mesh:
			var shaft = _mesh_inst(driveshaft_mesh, base_color.darkened(0.3).lightened(0.3))
			var gb_size2: float = wheel_radius_target * 1.2
			var shaft_len: float = wheel_radius_target * 2.4
			var shaft_angle := deg_to_rad(25.0)
			var bottom_target: Vector3 = Vector3(outboard_x - wheel_radius_target * 0.34,
				roller_axle.position.y + wheel_radius_target * 0.35, pos.z)
			var shaft_drop := Vector3(sin(shaft_angle), -cos(shaft_angle), 0.0) * shaft_len
			shaft.scale = Vector3(gb_size2 * 0.55, shaft_len, gb_size2 * 0.55)
			shaft.position = bottom_target - shaft_drop
			shaft.rotation = Vector3(0, 0, shaft_angle)
			p.add_child(shaft)
	)


static func _build_helicopter_rotors(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DARK_GRAY, tweaks: Dictionary = {}):
	build_mount_kit(parent_node, "helicopter_rotors", base_color, 1.0, float(tweaks.get("blade_length", 1.0)), float(tweaks.get("kit_reach", 0.0)), Vector3(float(tweaks.get("kit_anchor_x", 0.0)), float(tweaks.get("kit_anchor_y", 0.0)), float(tweaks.get("kit_anchor_z", 0.0))))
	var blade_count = int(tweaks.get("blade_count", 4.0))
	var blade_length = tweaks.get("blade_length", tweaks.get("size", 1.0))
	var duct = tweaks.get("duct", false)

	var mast_mesh = _part("rotor_mast")
	var hub_mesh = _part("rotor_hub")
	var blade_mesh = _part("rotor_blade")
	var duct_mesh = _part("rotor_duct_ring")
	var strut_mesh = _part("mount_strut_tapered")
	var mount_mesh = _part("rg_mount_box")

	# Structural mounting pylon down to the hull's physical center - NOT just
	# to its near edge. module_placer.gd places this whole module at
	# hull_size/2 + a fixed clearance (1.2 outboard, 0.3 above the hull top)
	# and passes the FULL resulting distances through as mount_reach_x/y
	# (mirrored by mount_side for whichever side this instance is on -
	# rotors are never mirror-flipped like wheels/tracked_treads are, since
	# the mast+blade ring alone is rotationally symmetric, so this is the
	# first rotor geometry that needs to know its own side). The strut
	# travels the FULL mount_reach_x/y, guaranteeing it plunges into the
	# hull body regardless of hull size or shape.
	var mount_side = tweaks.get("mount_side", 1.0)
	var mount_reach_x = tweaks.get("mount_reach_x", 1.2)
	var mount_reach_y = tweaks.get("mount_reach_y", 0.3)
	var hull_center = Vector3(-mount_reach_x * mount_side, -mount_reach_y, 0)
	var strut_len = hull_center.length()
	var strut_dir = hull_center / strut_len
	# rg_mount_box/mount_strut_tapered are both authored spanning local
	# Y=[0, authored_len] - rotating by strut_angle about Z maps that Y span
	# to world direction (-sin(angle), cos(angle), 0), so solving
	# strut_dir = that gives the angle needed to point the strut's long axis
	# at the hull center.
	var strut_angle = atan2(-strut_dir.x, strut_dir.y)
	if strut_mesh:
		# mount_strut_tapered (build_meshes.py) is authored as a genuine
		# taper - thin (near_half=0.12) at local Y=0, 3x-per-edge thicker
		# (far_half=0.36) at local Y=1.0 (Chris's ask: the pylon should read
		# as load-bearing, thickening as it nears the hull, not a uniform
		# rod) - one continuous mesh, no separate flared "anchor" block
		# needed anymore.
		var strut = _mesh_inst(strut_mesh, base_color.darkened(0.3))
		strut.scale = Vector3(1.0, strut_len, 1.0)
		strut.position = Vector3.ZERO
		strut.rotation = Vector3(0, 0, strut_angle)
		parent_node.add_child(strut)
	elif mount_mesh:
		# Fallback (mount_strut_tapered not yet reimported): the old
		# two-piece uniform-strut + larger-block-at-the-end approximation.
		var strut = _mesh_inst(mount_mesh, base_color.darkened(0.3))
		strut.scale = Vector3(0.3, strut_len / 0.4, 0.3)
		strut.position = Vector3.ZERO
		strut.rotation = Vector3(0, 0, strut_angle)
		parent_node.add_child(strut)

		var anchor = _mesh_inst(mount_mesh, base_color.darkened(0.3))
		anchor.scale = Vector3(0.85, 0.7, 0.85)
		anchor.position = hull_center
		anchor.rotation = Vector3(0, 0, strut_angle)
		parent_node.add_child(anchor)

	var shaft_h = base_size.y * 0.8
	if mast_mesh:
		var mast = _mesh_inst(mast_mesh, Color.DARK_GRAY)
		mast.scale = Vector3(1.0, shaft_h / 0.6, 1.0)
		mast.position = Vector3(0, 0, 0)
		parent_node.add_child(mast)
	else:
		var shaft = MeshInstance3D.new()
		var shaft_cyl = CylinderMesh.new()
		shaft_cyl.top_radius = 0.05
		shaft_cyl.bottom_radius = 0.05
		shaft_cyl.height = shaft_h
		shaft.mesh = shaft_cyl
		var shaft_mat = StandardMaterial3D.new()
		shaft_mat.albedo_color = Color.DARK_GRAY
		shaft.material_override = shaft_mat
		shaft.position = Vector3(0, shaft_h / 2.0, 0)
		parent_node.add_child(shaft)

	if hub_mesh:
		var hub = _mesh_inst(hub_mesh, Color(0.2, 0.2, 0.22))
		hub.position = Vector3(0, shaft_h, 0)
		parent_node.add_child(hub)

	var pivot = Node3D.new()
	pivot.name = "RotorBlades"
	pivot.position = Vector3(0, shaft_h + 0.05, 0)
	parent_node.add_child(pivot)

	_ring_of(pivot, blade_count, 0.0, func(p, _pos, angle, _idx):
		var blade: MeshInstance3D
		if blade_mesh:
			blade = _mesh_inst(blade_mesh, Color(0.1, 0.1, 0.1))
			blade.scale = Vector3(1.0, 1.0, blade_length)
			blade.rotation.y = angle
		else:
			blade = MeshInstance3D.new()
			var b_box = BoxMesh.new()
			b_box.size = Vector3(0.1, 0.03, base_size.x * blade_length)
			blade.mesh = b_box
			var b_mat = StandardMaterial3D.new()
			b_mat.albedo_color = Color(0.1, 0.1, 0.1)
			blade.material_override = b_mat
			blade.position = Vector3(0, 0, base_size.x * blade_length * 0.5)
			blade.rotation.y = angle
		p.add_child(blade)
	)

	if duct and duct_mesh:
		var shroud = _mesh_inst(duct_mesh, base_color.darkened(0.2))
		shroud.scale = Vector3(blade_length, 1.0, blade_length)
		shroud.position = Vector3(0, shaft_h, 0)
		parent_node.add_child(shroud)


static func _build_hover_engine(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DEEP_SKY_BLUE, tweaks: Dictionary = {}):
	build_mount_kit(parent_node, "hover_engine", Color(0.32, 0.34, 0.37).lerp(base_color, 0.12), 1.0, float(tweaks.get("emv_level", 1.0)), float(tweaks.get("kit_reach", 0.0)), Vector3(float(tweaks.get("kit_anchor_x", 0.0)), float(tweaks.get("kit_anchor_y", 0.0)), float(tweaks.get("kit_anchor_z", 0.0))))
	# Scifi hover pad, per Chris's redesign: three concentric rings instead
	# of the old fan+skirt+single-ring combo. The outer ring stays fixed/
	# horizontal; the middle ring spins continuously around local X and the
	# inner ring around local Y (battle_unit.gd/battlefield.gd/
	# module_placer.gd all spin "HoverRingMid"/"HoverRingInner" by name,
	# same by-name-pivot pattern as helicopter_rotors' "RotorBlades"). No
	# pad_size/skirt tweaks anymore - footprint is fixed off the hull
	# (module_placer.gd), and emv_level (Electron Megavoltage) instead
	# fattens the rings' tube thickness without changing their diameter, so
	# it reads as "denser hardware", not "bigger pad".
	var emv = tweaks.get("emv_level", 1.0)
	var ring_mesh = _part("hover_ring")
	# The MOUNTING is steel, not team paint. hover_engine's catalog colour is
	# DEEP_SKY_BLUE, and everything structural was being tinted with it - so
	# the pylon and mount came out as bright cyan girders, which is most of why
	# this module "looked terrible" (Chris). The field colour belongs to the
	# field; the hardware holding it out there is metal with a hint of team
	# tint, the same as every other locomotor's mount.
	var struct_color := Color(0.32, 0.34, 0.37).lerp(base_color, 0.12)

	# hover_ring is authored with major_radius=0.5, i.e. diameter=1.0 (see
	# build_hover_ring in build_meshes.py) - ring_scale converts that to the
	# catalog's actual footprint (base_size.x), and ring_radii nests three
	# rings inside it (outer/mid/inner) at decreasing diameter.
	var authored_diameter = 1.0
	# Same prominence pass as anti_grav_plate: the rings ARE the module, and
	# at 1.0 they read as a detail on the end of a strut rather than the
	# working end of one (Chris).
	const HEAD_SCALE := 2.1
	var ring_scale = (base_size.x / authored_diameter) * HEAD_SCALE
	var ring_radii = [1.0, 0.65, 0.35]
	var ring_names = ["HoverRingOuter", "HoverRingMid", "HoverRingInner"]
	var ring_y = base_size.y * 0.5

	for idx in range(3):
		var ring: MeshInstance3D
		if ring_mesh:
			# Only the INNERMOST ring glows - the other two are dark polished
			# alloy, same as the anti-grav pad body. Chris: "the hover pad
			# looks similar, still all sky blue." Emission is applied over any
			# material, so glowing all three was what kept the whole assembly
			# blue however exotic the substrate was. One lit hoop inside two
			# dark ones reads as a machine with something running in it;
			# three lit hoops read as a plastic toy.
			if idx == 2:
				ring = _mesh_inst(ring_mesh, Color(0.26, 0.30, 0.34),
					Color(0.35, 0.72, 1.0), 0.55)
			else:
				ring = _mesh_inst(ring_mesh, Color(0.30, 0.32, 0.35))
			ring.scale = Vector3(ring_scale * ring_radii[idx], emv, ring_scale * ring_radii[idx])
		else:
			ring = MeshInstance3D.new()
			var torus = TorusMesh.new()
			torus.outer_radius = ring_scale * ring_radii[idx] * 0.5
			torus.inner_radius = torus.outer_radius * 0.8
			ring.mesh = torus
			var mat = StandardMaterial3D.new()
			mat.albedo_color = base_color
			mat.emission_enabled = true
			mat.emission = base_color
			mat.emission_energy_multiplier = 1.0
			ring.material_override = mat
			ring.scale = Vector3(1.0, emv, 1.0)
		ring.name = ring_names[idx]
		ring.position = Vector3(0, ring_y, 0)
		parent_node.add_child(ring)

	# Structural mounting pylon back to the hull's physical center - same
	# "extend all the way to the center, not just the near edge" fix
	# helicopter_rotors' pylon got, but flattened (mount_strut_flat, ~3x as
	# wide as it is thick, per Chris's ask) rather than square, and general
	# 3D (module_placer.gd distributes pads radially around the hull, so
	# the reach direction has both an X and a Z component, unlike the
	# rotor pylon which only ever needed to reach inboard along X).
	var mount_reach = Vector3(tweaks.get("mount_reach_x", 0.6), tweaks.get("mount_reach_y", 0.15), tweaks.get("mount_reach_z", 0.0))
	if mount_reach.length() > 0.001:
		var strut_mesh = _part("mount_strut_flat")
		var strut_len = mount_reach.length()
		var dir = mount_reach / strut_len
		# Gram-Schmidt: build an orthonormal basis with local Y along `dir`
		# (the strut's authored long axis) - `reference` just needs to be
		# any vector not parallel to dir, picked per-instance since dir
		# varies with each pad's own angle around the hull.
		var reference = Vector3(0, 0, 1)
		if abs(dir.dot(reference)) > 0.95:
			reference = Vector3(1, 0, 0)
		var right = dir.cross(reference).normalized()
		var forward = right.cross(dir).normalized()
		if strut_mesh:
			var strut = _mesh_inst(strut_mesh, struct_color)
			# Basis columns pre-scaled directly (right/forward stay unit-
			# length - the flattened 3-to-1 cross-section is already baked
			# into the authored mesh - dir scaled to strut_len) rather than
			# setting .scale separately afterward, which risks desyncing
			# from a directly-assigned .transform.basis.
			strut.transform = Transform3D(Basis(right, dir * strut_len, forward), Vector3.ZERO)
			parent_node.add_child(strut)
		else:
			# Fallback (mount_strut_flat not yet reimported): a plain
			# flattened box, no taper.
			var mount_mesh = _part("rg_mount_box")
			if mount_mesh:
				var strut = _mesh_inst(mount_mesh, struct_color)
				strut.transform = Transform3D(Basis(right * 0.6, dir * strut_len, forward * 0.2), Vector3.ZERO)
				parent_node.add_child(strut)


static func _build_legs(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.GRAY, tweaks: Dictionary = {}):
	var leg_length = tweaks.get("leg_length", tweaks.get("size", 1.0))
	var foot_size = tweaks.get("foot_size", 1.0)
	# Chris's ask: legs about 2x thicker all the way through (cross-section
	# only - length/reach are untouched), except the knee joint block,
	# which is 2.5x bigger all around instead.
	# Slimmer than the old mammalian build: an insect leg is a thin spar under
	# tension, and at 2.0 the segments read as stocky pistons (Chris) once the
	# leg stopped being hull-length.
	var thickness_mult = 1.15
	var knee_mult = 2.0

	var thigh_mesh = _part("leg_thigh")
	var shin_mesh = _part("leg_shin")
	var foot_mesh = _part("leg_foot")
	var joint_mesh = _part("leg_joint")

	# The hip is build_wheel_mount() - the same angled driveshaft and inboard
	# gearbox the wheels and pontoons hang from, with a leg tacked on the
	# outboard end instead of a wheel (Chris's ask: "just take those gearbox and
	# strut assemblies, they are already positioned perfectly on the pontoon
	# wheels"). A walking machine's hip actuator is a gearbox on the end of a
	# drive housing, so the part reads correctly here without being restyled.
	#
	# hip_y comes back from the mount rather than being computed against
	# base_size, and everything below is already expressed RELATIVE to hip_y
	# (knee_y and foot_y both subtract it), so the foot still lands on the
	# ground plane at y=0.03 no matter where the mount puts the hip.
	var mount_s: float = float(leg_length) * 1.4
	var hip := build_wheel_mount(parent_node, base_color, mount_s, 0.0, 0.42 * mount_s)
	var hip_y: float = hip.y

	# Everything below (thigh/shin/foot/ankle joint) hangs off a "LegSwing"
	# pivot, itself nested inside a static "leg_root" anchor rooted at the
	# hip - NOT a single pivot directly under parent_node. module_placer.gd's
	# _apply_mirror_flip() reflects every DIRECT child of the leg module
	# once at placement time by rewriting its whole Transform3D; Godot then
	# decomposes that reflected Transform3D back into .rotation/.scale, and
	# for a pure X-mirror it's free to pick EITHER (rotation=0, scale=
	# (-1,1,1)) OR (rotation=(PI,0,0), scale=(-1,-1,-1)) - both represent
	# the identical transform, but confirmed via a headless test
	# (scratch/debug_leg_mirror_swing.gd) that Godot 4.3 actually picks the
	# second one here. The walk animation used to write swing.rotation.x
	# directly onto that SAME node - which, on the mirrored side, means
	# overwriting the baked-in PI (the mirror's own encoding) with the
	# swing angle instead of adding to it, destroying the mirror and
	# rendering the leg inside-out ("upside down," Chris's report). leg_root
	# now carries the mirror and is never touched again after placement;
	# the animation instead rotates the NESTED "LegSwing" pivot, which is
	# always freshly created at identity and never mirrored itself (mirror-
	# flip only walks parent_node's DIRECT children) - it just inherits
	# leg_root's already-correct mirrored frame normally, the same way any
	# child node does.
	#
	# The femur and tibia each SPAN from their own start point out to where
	# they need to land - the same "compute a direction and length, orient a
	# stretchable mesh along it" technique the rotor/hover pylons use - rather
	# than translating a fixed assembly sideways, which left a gap between the
	# fixed hip and a floating thigh instead of a real angled leg. leg_root
	# itself stays at the hip, flush against the mount; only the segments below
	# splay out from it. Authored assuming the canonical +X = outboard
	# direction (unmirrored build); side<0 legs get mirrored for free via
	# module_placer.gd's whole-subtree mirror-flip.
	#
	# leg_stance_reach is no longer read here. It arrives as a fraction of the
	# HULL'S WIDTH (~2.5 on a medium hull), and anything keyed to a hull
	# dimension sets the leg's scale rather than influencing its pose - the
	# repeated cause of both the giant-spider and the splayed-flat legs. The
	# stance now comes out of knee_out/foot_out below, which are fractions of
	# the leg's own drop.
	var leg_root = Node3D.new()
	# Named (not left auto-generated) so the animation code can reach the
	# nested "LegSwing" pivot via the fixed path "LegRoot/LegSwing".
	leg_root.name = "LegRoot"
	leg_root.position = Vector3(hip.x, hip_y, 0)
	parent_node.add_child(leg_root)

	var swing = Node3D.new()
	swing.name = "LegSwing"
	swing.position = Vector3.ZERO
	leg_root.add_child(swing)

	# INSECTILE STANCE. Chris: the legs "should resemble the insectile legs,
	# carrying the body low between them."
	#
	# That is a specific arrangement, not just a longer leg: the FEMUR RISES
	# from the hip out to a knee ABOVE the hull line, and the tibia drops from
	# that knee back down and inward to the foot. The body then hangs low
	# BETWEEN the knees rather than being propped up on top of the legs. A
	# mammalian leg - knee below the hip, which is what the previous pass
	# built - cannot do that at any length; it just gets stockier.
	#
	# Proportions are still keyed to the mount rather than to the hull (that
	# was what produced the enormous spider legs two passes ago, when the knee
	# tracked the hull's centreline and the stance tracked its width). DROP is
	# the ride height from the module origin down to the sole.
	var drop: float = 1.35 * float(leg_length)
	# The knee is the outermost AND highest point of the limb; the foot tucks
	# back inboard under the load. Both are fractions of the drop, so the leg
	# keeps its shape at any scale.
	var knee_out: float = 0.80 * drop
	var foot_out: float = 0.60 * drop

	# knee_height keeps its cosmetic job (Chris: "doesn't really make a stat
	# difference, just looking cool") - it now sets how far the knee rises
	# above the hip, which is the single most visible thing about an insect
	# leg, instead of parking the knee at an absolute hull height.
	var knee_height = tweaks.get("knee_height", 0.375)
	var knee_rise: float = drop * clampf(0.30 + 0.30 * float(knee_height), 0.10, 0.90)
	var knee_y: float = knee_rise - hip_y
	var foot_y: float = -drop - hip_y

	var thigh_target = Vector3(knee_out, knee_y, 0)
	var thigh_len = thigh_target.length()
	var thigh_dir = thigh_target / thigh_len
	var thigh_angle = atan2(-thigh_dir.x, thigh_dir.y)
	var thigh: MeshInstance3D
	if thigh_mesh:
		thigh = _mesh_inst(thigh_mesh, base_color)
		thigh.scale = Vector3(leg_length * thickness_mult, thigh_len / 0.55, leg_length * thickness_mult)
	else:
		thigh = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.12 * leg_length * thickness_mult
		cyl.bottom_radius = 0.08 * leg_length * thickness_mult
		cyl.height = thigh_len
		thigh.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color
		thigh.material_override = mat
	thigh.position = Vector3.ZERO
	thigh.rotation = Vector3(0, 0, thigh_angle)
	swing.add_child(thigh)

	var knee_pos = thigh_target
	# Negative X: the tibia comes back INBOARD from the knee down to the sole,
	# which is what makes the knee the outermost point of the leg.
	var shin_target = Vector3(foot_out - knee_out, foot_y - knee_y, 0)
	var shin_len = shin_target.length()
	var shin_dir = shin_target / shin_len
	var shin_angle = atan2(-shin_dir.x, shin_dir.y)
	var shin: MeshInstance3D
	if shin_mesh:
		shin = _mesh_inst(shin_mesh, Color(0.15, 0.15, 0.15))
		shin.scale = Vector3(leg_length * thickness_mult, shin_len / 0.5, leg_length * thickness_mult)
	else:
		shin = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.08 * leg_length * thickness_mult
		cyl.bottom_radius = 0.05 * leg_length * thickness_mult
		cyl.height = shin_len
		shin.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.15, 0.15)
		shin.material_override = mat
	shin.position = knee_pos
	shin.rotation = Vector3(0, 0, shin_angle)
	swing.add_child(shin)

	# Bulkier faceted knee joint (Chris's ask) - the raised knee bends the
	# thigh and shin at a much sharper, more visible angle than the old
	# straight-ish hang did, so unlike the hip/ankle joints this one is
	# scaled generously specifically to bury that intersection rather than
	# just decorate a joint that was already reading fine. Oriented halfway
	# between the thigh's and shin's own angles so it doesn't visibly favor
	# either segment's direction.
	if joint_mesh:
		var knee = _mesh_inst(joint_mesh, base_color.darkened(0.1))
		# Non-uniform this time (Chris's ask) - scaled back on the mesh's
		# own local Z (leg_joint is authored as a vertical drum, so local Z
		# is its "depth"/thickness axis) and extended on local Y (its
		# height axis) instead of the flat uniform 2.5x from before, so it
		# reads as a taller, thinner joint rather than a chunky ball.
		# Re-scaled against the leg's own thickness, not its old hull-driven
		# length: at 0.75 the joint drum was wider than the 0.95 ride height
		# once the leg shrank, and read as a boulder with limbs attached.
		var knee_base = 0.26 * leg_length * knee_mult
		knee.scale = Vector3(knee_base, knee_base * 1.4, knee_base * 0.55)
		knee.position = knee_pos
		knee.rotation = Vector3(0, 0, (thigh_angle + shin_angle) * 0.5)
		swing.add_child(knee)

	var ankle_pos = knee_pos + shin_target
	var foot: MeshInstance3D
	if foot_mesh:
		foot = _mesh_inst(foot_mesh, Color(0.18, 0.18, 0.2))
		foot.scale = Vector3(foot_size, foot_size, foot_size)
	else:
		foot = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(base_size.x * 0.7 * foot_size, 0.06 * foot_size, base_size.z * 0.7 * foot_size)
		foot.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.15, 0.15)
		foot.material_override = mat
	foot.position = ankle_pos
	swing.add_child(foot)

	# Bulkier faceted ankle joint where the shin meets the foot ("toe
	# sections meet", Chris's ask) - previously a bare junction with
	# nothing there at all. Piggybacks on foot.position (already tuned to
	# sit at the shin/foot contact point) rather than re-deriving it from
	# shin's own rotated end, offset up slightly so it reads as sitting
	# above the foot pad, not buried inside it.
	if joint_mesh:
		var ankle = _mesh_inst(joint_mesh, Color(0.18, 0.18, 0.2))
		ankle.scale = Vector3(1.0, 1.0, 1.0) * (0.20 * leg_length * foot_size * thickness_mult)
		ankle.position = foot.position + Vector3(0, 0.09 * leg_length, 0)
		ankle.rotation = Vector3(0, 0, shin_angle)
		swing.add_child(ankle)


static func _build_fixed_wing_engine(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.SLATE_GRAY, tweaks: Dictionary = {}):
	build_mount_kit(parent_node, "fixed_wing_engine", base_color, 1.0, float(tweaks.get("turbine_compression", 1.0)), float(tweaks.get("kit_reach", 0.0)), Vector3(float(tweaks.get("kit_anchor_x", 0.0)), float(tweaks.get("kit_anchor_y", 0.0)), float(tweaks.get("kit_anchor_z", 0.0))))
	# Redesign (Chris's ask): mounted out from the hull on a pylon like the
	# rotors/hover pads, radially/elliptically distributed around the Y
	# axis (module_placer.gd, engine_count 2-6) instead of a fixed pair.
	# nacelle_size is no longer user-tweakable - turbine_compression takes
	# over that "Size" slider slot, and unlike hover's purely cosmetic
	# knee_height, IS wired into weight/cost (module_data.gd) since a
	# physically longer turbine core is a real size change, not just a
	# look.
	var nacelle_size = tweaks.get("nacelle_size", 1.0)
	var turbine_compression = tweaks.get("turbine_compression", 1.0)
	var afterburner = tweaks.get("afterburner", false)

	var nacelle_mesh = _part("engine_nacelle")
	var fan_mesh = _part("engine_fan")
	var exhaust_mesh = _part("exhaust_cone")
	var core_mesh = _part("engine_core")
	var strut_mesh = _part("mount_strut_aerofoil")

	var actual_size = Vector3(base_size.x * nacelle_size, base_size.y * nacelle_size, base_size.z * nacelle_size)
	if nacelle_mesh:
		var nac = _mesh_inst(nacelle_mesh, base_color)
		nac.scale = Vector3(nacelle_size, nacelle_size, nacelle_size)
		# engine_nacelle is authored along local Z (build_engine_nacelle,
		# add_cyl_axis(..., 'z')) - matching this function's own placement
		# convention (rotation=Vector3.ZERO at the module_placer call site) -
		# so it needs NO runtime rotation. The stray 90deg-about-Y rotation
		# this used to carry pointed the nacelle/core sideways along world X
		# instead of forward along Z, which is why turbine_compression read
		# as "wider" instead of "longer" and the core appeared to drift off
		# to the side instead of extending straight out the back.
		nac.position = Vector3(0, 0, 0)
		parent_node.add_child(nac)
	else:
		var nac = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = actual_size.y * 0.55
		cyl.bottom_radius = actual_size.y * 0.4
		cyl.height = actual_size.z
		nac.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color
		mat.metallic = 0.6
		mat.roughness = 0.3
		nac.material_override = mat
		nac.rotation = Vector3(PI / 2.0, 0, 0)
		parent_node.add_child(nac)

	if fan_mesh:
		# The intake fan is the one moving part of a jet the eye can actually
		# read, and it was static - a fixed-wing unit in flight had nothing at
		# all in motion, unlike every other airborne type. Spun about local Z
		# (the engine's own thrust axis, which is what this whole part family
		# is authored along) via a named pivot, so the nacelle around it stays
		# put.
		var fan_pivot = Node3D.new()
		fan_pivot.name = SPIN_PIVOT_TURBINE
		fan_pivot.position = Vector3(0, 0, -actual_size.z * 0.48)
		parent_node.add_child(fan_pivot)
		var fan = _mesh_inst(fan_mesh, Color(0.2, 0.2, 0.22))
		fan.scale = Vector3(nacelle_size, nacelle_size, nacelle_size)
		fan_pivot.add_child(fan)

	# Turbine core: a distinct segment behind the main nacelle whose own
	# length is what turbine_compression physically stretches/compresses
	# ("a central part of the engine housing longer or shorter... out the
	# back", Chris's ask) - engine_core is authored along local Z like the
	# rest of this engine's part family (build_engine_nacelle/_fan/
	# _exhaust_cone), matching this function's own no-rotation convention
	# (see the nacelle comment above - no runtime rotation needed).
	# core_rear_z is fixed (independent of core_len), and the node's
	# position is core_rear_z + half its own scaled length, so the FRONT
	# face (position.z - core_len/2 == core_rear_z) never moves as
	# turbine_compression changes - only the rear face (core_rear_z +
	# core_len) extends further out, anchoring growth at the nacelle joint.
	var core_len = actual_size.z * 0.7 * turbine_compression
	var core_rear_z = actual_size.z * 0.48
	if core_mesh:
		var core = _mesh_inst(core_mesh, base_color.darkened(0.15))
		core.scale = Vector3(nacelle_size, nacelle_size, core_len / 0.6)
		core.position = Vector3(0, 0, core_rear_z + core_len * 0.5)
		parent_node.add_child(core)
	else:
		var core = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = actual_size.y * 0.42
		cyl.bottom_radius = actual_size.y * 0.42
		cyl.height = core_len
		core.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color.darkened(0.15)
		mat.metallic = 0.7
		mat.roughness = 0.3
		core.material_override = mat
		core.rotation = Vector3(PI / 2.0, 0, 0)
		core.position = Vector3(0, 0, core_rear_z + core_len * 0.5)
		parent_node.add_child(core)

	if afterburner:
		if exhaust_mesh:
			var ex = _mesh_inst(exhaust_mesh, Color(1.0, 0.4, 0.1), Color(1.0, 0.5, 0.1), 1.5)
			ex.scale = Vector3(nacelle_size, nacelle_size, nacelle_size)
			# Pushed back past the turbine core (which the old fixed
			# actual_size.z*0.48 position didn't account for) so the
			# exhaust sits at the engine's TRUE rear now that the core can
			# stretch it further back.
			ex.position = Vector3(0, 0, core_rear_z + core_len)
			parent_node.add_child(ex)

	# Structural mounting pylon back to the hull's physical center - same
	# reach-vector technique as helicopter_rotors'/hover_engine's pylons,
	# generalized to full 3D (module_placer.gd distributes engines
	# radially/elliptically, so the reach direction has both an X and a Z
	# component, same as hover's). Aerofoil cross-section (mount_strut_
	# aerofoil, "vaguely aerofoil shaped... pretend that gives enough
	# lift", Chris's ask) and noticeably thicker than hover's flat pylon.
	var mount_reach = Vector3(tweaks.get("mount_reach_x", 1.0), tweaks.get("mount_reach_y", 0.0), tweaks.get("mount_reach_z", 0.0))
	if mount_reach.length() > 0.001:
		var reach_len = mount_reach.length()
		var dir = mount_reach / reach_len
		var reference = Vector3(0, 1, 0)
		if abs(dir.dot(reference)) > 0.95:
			reference = Vector3(1, 0, 0)
		var right = dir.cross(reference).normalized()
		var forward = right.cross(dir).normalized()
		if strut_mesh:
			var strut = _mesh_inst(strut_mesh, base_color.darkened(0.2))
			strut.transform = Transform3D(Basis(right * 1.8, dir * reach_len, forward * 1.8), Vector3.ZERO)
			parent_node.add_child(strut)
		else:
			var mount_mesh = _part("rg_mount_box")
			if mount_mesh:
				var strut = _mesh_inst(mount_mesh, base_color.darkened(0.2))
				strut.transform = Transform3D(Basis(right * 1.4, dir * reach_len, forward * 0.7), Vector3.ZERO)
				parent_node.add_child(strut)


static func _build_ornithopter_wing(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.BROWN, tweaks: Dictionary = {}):
	# Dragonfly-style rebuild (Chris's ask, 2026-07-24): TWO independent
	# wing pairs per mount node (fore + hind, like a dragonfly's wing
	# root) instead of one wing on one pivot, each on its own named pivot
	# ("WingPivotFore"/"WingPivotHind") so battle_unit.gd can flap them in
	# opposition to each other - real dragonflies beat their fore and hind
	# wing pairs roughly 180 degrees out of phase. The wings themselves are
	# also now authored substantially longer and narrower (see
	# build_wing_membrane's rebuilt defaults in build_meshes.py) - a real
	# slender dragonfly silhouette, not the old short stubby panel.
	#
	# wing_sweep was declared in TWEAK_SPECS but never read anywhere -
	# wired in here now (scales the same leading-edge sweep angle the old
	# single wing used a fixed 12deg for).
	var wingspan = tweaks.get("wingspan", tweaks.get("size", 1.0))
	var sweep = tweaks.get("wing_sweep", 1.0)

	var shoulder_mesh = _part("wing_shoulder")
	if shoulder_mesh:
		var sh = _mesh_inst(shoulder_mesh, Color(0.3, 0.28, 0.25))
		parent_node.add_child(sh)
	else:
		var shoulder = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(base_size.x * 0.35, base_size.y * 0.7, base_size.z * 0.5)
		shoulder.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.28, 0.25)
		shoulder.material_override = mat
		parent_node.add_child(shoulder)

	# Fore/hind wing roots sit close together fore-and-aft on the thorax
	# (a real dragonfly's two wing bases are close but distinct), not
	# spread across the whole hull like the old single-wing rib fan was.
	# Hind wing reads slightly broader than fore (size_mult 1.15), matching
	# a real dragonfly's hindwing being the bigger of the pair.
	var root_gap = base_size.z * 0.22
	_build_ornithopter_wing_unit(parent_node, base_size, base_color, wingspan, sweep, "WingPivotFore", root_gap, 1.0)
	_build_ornithopter_wing_unit(parent_node, base_size, base_color, wingspan, sweep, "WingPivotHind", -root_gap, 1.15)


# One wing (membrane + a single main spar) of an ornithopter_wing's fore/
# hind pair, on its own named flap pivot. size_mult lets the hind wing read
# as the broader of the two. Split out of _build_ornithopter_wing() so the
# fore and hind units share identical construction logic.
#
# Rebuilt (Chris's ask, 2026-07-24): "each wing should have a single
# wing-rib that connects to the gearbox/mount, and extends about 2/3rds of
# the total length of the wing membrane" - the old rib_count-driven fan of
# 2-6 parallel ribs (rib_count was never actually wired to any UI control,
# so it silently always defaulted to 3) read as a loose bundle of sticks
# radiating from the mount rather than a single readable wing spar,
# especially once the wing got much longer earlier in this rebuild. One
# spar, root-anchored at the same point as the membrane, 2/3 of the
# membrane's own rendered length, replaces it - rib_count is gone
# entirely, not just defaulted differently (see the matching removals in
# module_catalog.gd's LOCOMOTION_TWEAK_SPECS, module_placer.gd, and
# module_data.gd's weight/cost tweak tables).
static func _build_ornithopter_wing_unit(parent_node: Node3D, base_size: Vector3, base_color: Color, wingspan: float, sweep: float, pivot_name: String, z_offset: float, size_mult: float):
	var mem_mesh = _part("wing_membrane")
	var rib_mesh = _part("wing_rib")
	var span = wingspan * size_mult
	var sweep_angle = deg_to_rad(12.0) * sweep

	var pivot = Node3D.new()
	pivot.name = pivot_name
	pivot.position = Vector3(base_size.x * 0.2, base_size.y * 0.15, z_offset)
	parent_node.add_child(pivot)

	# root_x/mem_len track the membrane's actual root position and
	# rendered length so the single spar below can be anchored and sized
	# to match, whichever branch (authored vs procedural fallback) built it.
	# root_x is 0 (not base_size.x*0.2 again) because the pivot ABOVE
	# already carries that same offset out from the gearbox - doubling it
	# here used to put the wing's actual root a further 0.2*base_size.x
	# past the pivot, floating well clear of the gearbox mesh instead of
	# meeting it (Chris's report, 2026-07-24).
	var root_x = 0.0
	var mem_len: float

	if mem_mesh:
		var mem = _mesh_inst(mem_mesh, base_color)
		mem.scale = Vector3(span, 1.0, 1.0)
		mem.position = Vector3(root_x, 0, 0)
		mem.rotation = Vector3(0, 0, sweep_angle)
		pivot.add_child(mem)
		mem_len = 2.4 * span # 2.4 = build_wing_membrane's authored "length" default

		# Inner connector panel (Chris's ask, 2026-07-24): a mirrored
		# duplicate of the very same tapered membrane mesh, rotated 180deg
		# so its NARROW end now points inward and reaches back past the
		# pivot to intersect the gearbox, while its WIDE end sits at
		# exactly the same point as the outer panel's own wide root above
		# (both positioned at pivot-local x=0) - so the two meet seamlessly
		# at full root width, with no visible gap or step. This also gives
		# the wing the fast inside taper Chris asked for: the widest point
		# of the whole wing is now out at this root/hinge, not smeared
		# uniformly from the gearbox itself, since the connector pinches
		# back down to the membrane's narrow-tip width as it nears the hull.
		# scale.x is deliberately NOT `span` - wingspan only stretches the
		# OUTER panel's reach; the connector only needs to be exactly long
		# enough to bridge the gearbox gap (pivot.position.x) plus a 40%
		# overshoot so it visibly overlaps/intersects the gearbox mesh
		# rather than just grazing its surface.
		var connector_len = pivot.position.x * 1.4
		var connector = _mesh_inst(mem_mesh, base_color)
		connector.scale = Vector3(connector_len / 2.4, 1.0, 1.0)
		connector.rotation = Vector3(0, PI, sweep_angle)
		pivot.add_child(connector)
	else:
		var mem = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(base_size.x * 0.75 * span, base_size.y * 0.15, base_size.z * 0.85)
		mem.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color
		mem.material_override = mat
		# BoxMesh is centered on its own origin (unlike the authored
		# membrane's root-at-zero convex hull), so root_x here is HALF the
		# box's own length - that puts its near edge (the root) at
		# pivot-local x=0, matching the authored branch's convention above.
		root_x = box.size.x * 0.5
		mem.position = Vector3(root_x, 0, 0)
		mem.rotation = Vector3(0, 0, sweep_angle)
		pivot.add_child(mem)
		mem_len = base_size.x * 0.75 * span

	var rib_len = mem_len * (2.0 / 3.0)
	var rib: MeshInstance3D
	if rib_mesh:
		rib = _mesh_inst(rib_mesh, Color(0.22, 0.17, 0.12))
		rib.scale = Vector3(rib_len / 2.3, 1.0, 1.0) # 2.3 = build_wing_rib's authored "length" default
	else:
		rib = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(rib_len, base_size.y * 0.04, base_size.z * 0.06)
		rib.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.17, 0.12)
		rib.material_override = mat
	rib.position = Vector3(root_x, base_size.y * 0.08, 0)
	rib.rotation = Vector3(0, 0, sweep_angle)
	pivot.add_child(rib)


# Shared by naval_propeller and buoyant_envelope (Chris's ask, 2026-07-24):
# both used to spawn entirely inside the hull mesh with no visible
# structure reaching them clear of it - a fixed offset (hull_size.z*0.42
# for naval, side-mounted for buoyant) that landed well within the hull's
# own collision box on most hull shapes. Rebuilt to reuse the exact stern/
# reach-vector pylon technique already established for helicopter_rotors/
# hover_engine/fixed_wing_engine: module_placer.gd now places the propeller
# itself well aft of the hull's own mesh and passes a mount_reach vector
# pointing back to the hull's geometric center, and this function builds a
# mount_strut_aerofoil pylon along that vector, with the propeller hub+
# blades at the far (outboard) end. hub_scale differentiates the two
# "deformed" reuses of the same prop_housing/rotor_blade GLBs (buoyant_
# envelope's smaller cruise motor vs naval_propeller's full-size boat
# screw) without needing separate authored assets. Both types now share
# the exact same tweak set (blade_count, blade_pitch, prop_count) - the old
# prop_size/kort_nozzle/motor_size/tail_fins tweaks are gone entirely, not
# just defaulted differently.
static func _build_pylon_mounted_propeller(parent_node: Node3D, base_size: Vector3, base_color: Color, tweaks: Dictionary, hub_scale: float, blade_scale: float = 1.0):
	var blade_count = int(tweaks.get("blade_count", 3.0))
	var blade_pitch = tweaks.get("blade_pitch", 1.0)

	var housing_mesh = _part("prop_housing")
	var blade_mesh = _part("rotor_blade")
	var strut_mesh = _part("mount_strut_aerofoil")

	var actual_size = base_size * hub_scale
	if housing_mesh:
		var house = _mesh_inst(housing_mesh, base_color.darkened(0.2))
		house.scale = Vector3(hub_scale, hub_scale, hub_scale)
		parent_node.add_child(house)
	else:
		var house = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = actual_size.x * 0.4
		cyl.bottom_radius = actual_size.x * 0.5
		cyl.height = actual_size.z * 0.7
		house.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color.darkened(0.2)
		house.material_override = mat
		house.rotation = Vector3(PI / 2.0, 0, 0)
		parent_node.add_child(house)

	var pivot = Node3D.new()
	pivot.name = "PropBlades"
	pivot.position = Vector3(0, 0, actual_size.z * 0.35)
	parent_node.add_child(pivot)

	_ring_of(pivot, blade_count, 0.0, func(p, _pos, angle, _idx):
		var blade: MeshInstance3D
		if blade_mesh:
			# rotor_blade is authored with its span along LOCAL Z (root at
			# z=0, tip at z=length - see build_rotor_blade) - correct as-is
			# for helicopter_rotors, which spins its blades around Y (a
			# Z-reaching blade sweeps properly through the horizontal
			# plane there). This hub spins around Z instead (PropBlades
			# rotates_z in battle_unit.gd, matching a boat/aircraft
			# propeller shaft), and rotating a Z-REACHING blade around Z
			# does nothing - Z-axis rotation leaves the Z component
			# unchanged, which is exactly why every blade used to end up
			# overlapping at the same spot regardless of `angle` (Chris's
			# report, 2026-07-24). Fix: reorient the blade's span from Z
			# onto X first (a fixed -90deg turn around Y), then pitch it
			# around its own new (X) spanwise axis, THEN fan each blade out
			# by its own angle around Z - now that the blade actually has
			# an X/Y component, the Z fan-out rotation genuinely spreads
			# them around the hub. Built as a pure-rotation quaternion
			# (not Euler) so it composes correctly and doesn't disturb the
			# scale set right after.
			var reorient = Basis(Vector3(0, 1, 0), -PI / 2.0)
			var pitch_rot = Basis(Vector3(1, 0, 0), 0.3 * blade_pitch)
			var fan_rot = Basis(Vector3(0, 0, 1), angle)
			blade = _mesh_inst(blade_mesh, Color.SILVER)
			blade.quaternion = (fan_rot * pitch_rot * reorient).get_rotation_quaternion()
			blade.scale = Vector3(0.5 * blade_scale, 1.0, actual_size.x * 0.4 * blade_scale)
		else:
			# The procedural fallback box is built fresh here with its long
			# dimension already along Y (box.size.y), perpendicular to the
			# Z fan-out axis - correctly spreads with a plain rotate_z(),
			# no reorientation needed (unlike the authored branch above).
			blade = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.04 * blade_scale, actual_size.x * 0.7 * blade_scale, 0.12 * blade_scale)
			blade.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.SILVER
			blade.material_override = mat
			blade.rotate_z(angle)
			blade.rotate_y(0.3 * blade_pitch)
		p.add_child(blade)
	)

	# Pylon reaching back to the hull's geometric center - same reach-
	# vector technique as _build_fixed_wing_engine's pylon (see that
	# function's comment for the full explanation). module_placer.gd
	# computes mount_reach as the offset from THIS propeller's placed
	# position back to the hull's own local origin (0,0,0), so the far end
	# of this strut always lands exactly at the hull's geometric center
	# regardless of where the propeller itself was placed.
	var mount_reach = Vector3(tweaks.get("mount_reach_x", 0.0), tweaks.get("mount_reach_y", 0.0), tweaks.get("mount_reach_z", 1.0))
	if mount_reach.length() > 0.001:
		var reach_len = mount_reach.length()
		var dir = mount_reach / reach_len
		var reference = Vector3(0, 1, 0)
		if abs(dir.dot(reference)) > 0.95:
			reference = Vector3(1, 0, 0)
		var right = dir.cross(reference).normalized()
		var forward = right.cross(dir).normalized()
		if strut_mesh:
			var strut = _mesh_inst(strut_mesh, base_color.darkened(0.2))
			strut.transform = Transform3D(Basis(right * 1.4, dir * reach_len, forward * 1.4), Vector3.ZERO)
			parent_node.add_child(strut)
		else:
			var mount_mesh = _part("rg_mount_box")
			if mount_mesh:
				var strut = _mesh_inst(mount_mesh, base_color.darkened(0.2))
				strut.transform = Transform3D(Basis(right * 1.2, dir * reach_len, forward * 0.6), Vector3.ZERO)
				parent_node.add_child(strut)


static func _build_naval_propeller(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DARK_SLATE_GRAY, tweaks: Dictionary = {}):
	build_mount_kit(parent_node, "naval_propeller", base_color, 1.0, float(tweaks.get("blade_pitch", 1.0)), float(tweaks.get("kit_reach", 0.0)), Vector3(float(tweaks.get("kit_anchor_x", 0.0)), float(tweaks.get("kit_anchor_y", 0.0)), float(tweaks.get("kit_anchor_z", 0.0))))
	_build_pylon_mounted_propeller(parent_node, base_size, base_color, tweaks, 1.0)


static func _build_buoyant_envelope(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.TAN, tweaks: Dictionary = {}):
	build_mount_kit(parent_node, "buoyant_envelope", base_color, 1.0, float(tweaks.get("blade_pitch", 1.0)), float(tweaks.get("kit_reach", 0.0)), Vector3(float(tweaks.get("kit_anchor_x", 0.0)), float(tweaks.get("kit_anchor_y", 0.0)), float(tweaks.get("kit_anchor_z", 0.0))))
	# Zeppelin-style cruise prop (Chris's ask, 2026-07-24): a small engine
	# nacelle (hub_scale 0.75, unchanged) turning a disproportionately
	# large, slow prop - real airships mount big low-RPM propellers since
	# they're only providing gentle cruise/steering thrust, not fighting
	# gravity like a plane's. blade_scale 1.8 makes the blades noticeably
	# bigger than naval_propeller's own (which stays at the neutral 1.0);
	# the slow turn rate itself lives in battle_unit.gd's PropBlades spin.
	_build_pylon_mounted_propeller(parent_node, base_size, base_color, tweaks, 0.75, 1.8)


static func _build_screw_drive(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DARK_GOLDENROD, tweaks: Dictionary = {}):
	# Rebuilt (Chris's ask, 2026-07-24, two passes): drum_width/drum_count
	# are gone - just two tweaks now (drum_diameter, helix_depth). Each end
	# now terminates in an explicit gearbox housing, corner-mounted:
	# The reach-solved diagonal braces are gone. Each end now carries the
	# SAME assembly the wheels and pontoons use - build_wheel_mount()'s
	# angled driveshaft into an inboard gearbox - pinned at the hull corner
	# and descending from there, with the drum slung between the two
	# gearboxes (Chris's ask: "give the amphibious screw drive those same
	# gearboxes and struts... then the drum and helix between the
	# gearboxes"). That mount needs no mount_reach_* channel at all, because
	# it reaches into the hull by construction rather than by measurement -
	# see build_wheel_mount()'s own comment.
	# drum_length (internal) is the corner-to-corner span - the
	# gearboxes sit at exactly +-drum_length/2 (the corners' own Z), and
	# the drum's authored tapered tip (which lands at 0.65x whatever length
	# _fit_scale targets, not the full span - see fit_length below) is
	# scaled to land at that exact same point, so the cone visually plugs
	# straight into the gearbox face instead of floating short of or past
	# it ("pin the ends of the cones to the gearbox faces... stretch the
	# drum between the cones", Chris's ask).
	#
	# helix_depth can't continuously re-deform a single baked mesh at
	# runtime, so it picks among 3 discrete authored variants (shallow/
	# standard/deep flighting) rather than a smooth scale, the same way
	# blade_count picks a literal blade count instead of stretching one
	# blade.
	var diameter = tweaks.get("drum_diameter", tweaks.get("drum_width", tweaks.get("size", 1.0)))
	var depth = tweaks.get("helix_depth", 1.0)
	var span = tweaks.get("drum_length", base_size.z) # corner-to-corner distance
	var fit_length = span

	var drum_variant = "screw_drum"
	if depth < 0.85:
		drum_variant = "screw_drum_shallow"
	elif depth > 1.15:
		drum_variant = "screw_drum_deep"
	var drum_mesh = _part(drum_variant)
	if not drum_mesh:
		drum_mesh = _part("screw_drum")

	# Diameter comes off the HULL, not the catalog base_size. A screw drive is
	# the thing the vehicle rides on, so its drum has to be sized against the
	# vehicle - the catalog number is a fixed placeholder that came out as a
	# thin rod under anything bigger than a scout ("the screw is too small",
	# Chris). drum_bore is the hull's own height, from locomotion_layout.gd.
	var bore: float = float(tweaks.get("drum_bore", base_size.y))
	# GIRTH is the drum's own business. mount_ref, NOT drum_d, sizes the
	# gearboxes and sets how deep the hub hangs - fattening the auger 3x
	# (Chris) should not also triple the housings and shove the hull into the
	# sky. The drum thickens about a centreline that stays put.
	var mount_ref: float = bore * 0.46 * float(diameter)
	# 2.1, down 30% from 3.0 (Chris) - at 3x the drums read as the vehicle and
	# the hull as cargo.
	var drum_d: float = mount_ref * 2.1
	var actual_size = Vector3(drum_d, drum_d, fit_length)

	var spin = Node3D.new()
	spin.name = "ScrewSpin"
	parent_node.add_child(spin)

	var drum: MeshInstance3D
	if drum_mesh:
		drum = _mesh_inst(drum_mesh, base_color)
		# Scale solved against the mesh's OWN measured AABB, not against
		# hardcoded authored constants. Those constants said 0.29 across by
		# 1.6 long; the re-authored drum is 0.66 by 1.895, and the three
		# helix-depth variants differ in diameter from each other. So the
		# drum came out ~2x too fat and ~10% short of the gearboxes, and no
		# amount of adjusting the length target fixed it because the divisor
		# was wrong. A measured fit cannot go stale the next time the mesh is
		# re-authored, which is the actual lesson.
		var da: AABB = drum_mesh.get_aabb()
		drum.scale = Vector3(
			actual_size.y / maxf(da.size.x, 0.001),
			actual_size.y / maxf(da.size.y, 0.001),
			# 1.04: the drum runs THROUGH each bearing housing rather than
			# stopping on its centre, so the two read as assembled.
			(span * 1.04) / maxf(da.size.z, 0.001))
	else:
		drum = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = actual_size.y * 0.4
		cyl.bottom_radius = actual_size.y * 0.4
		cyl.height = span
		drum.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color
		drum.material_override = mat
		drum.rotation = Vector3(PI / 2.0, 0, 0)
	spin.add_child(drum)

	# One shared mount per end. `mount_s` sizes it so the gearbox housing
	# (0.46 * mount_s across) comes out visibly LARGER than the drum it
	# carries (0.85 * actual_size.y across) - a bearing block smaller than
	# its own shaft reads as a part that could not possibly hold it.
	# 1.5, not 2.2: at 2.2 the housing came out as wide as the drum itself and
	# the strut as thick as a leg, so the mounting read as the main object and
	# the auger as an accessory hung off it.
	var mount_s: float = mount_ref * 1.5
	# Hung a full drum-diameter below the hull rather than at the mount's own
	# default depth: Chris wants the drums "spread out and low to hold the hull
	# up above terrain", which is a longer strut, not a bigger gearbox.
	# STRUT_INSET pulls the mounts in from the hull's very ends (Chris) - a
	# bearing hung off the extreme corner reads as an afterthought bolted on,
	# and the drum's tapered nose wants to overhang it anyway. The drum still
	# spans the full length, so the ends now cantilever past the bearings the
	# way a real auger does.
	const STRUT_INSET := 0.86
	var hub_y := 0.0
	for z_end in [span * 0.5 * STRUT_INSET, -span * 0.5 * STRUT_INSET]:
		var hub := build_wheel_mount(parent_node, base_color, mount_s, z_end,
			mount_ref * 0.7, mount_ref * 1.0)
		hub_y = hub.y

	# The drum hangs at the mounts' own hub line, not at the module origin,
	# so its axis passes through both bearing bores instead of floating
	# above them.
	spin.position = Vector3(0, hub_y, 0)


static func _build_wing(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Flat swept panel - no aerodynamic simulation, purely a weight_capacity
	# attachment (see module_catalog.gd's "weight_capacity_bonus").
	var panel = MeshInstance3D.new()
	var panel_box = BoxMesh.new()
	panel_box.size = Vector3(base_size.x, base_size.y * 0.6, base_size.z)
	panel.mesh = panel_box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.metallic = 0.5
	mat.roughness = 0.4
	panel.material_override = mat
	parent_node.add_child(panel)

	# Swept tip - a smaller box fused near the outer edge to break up the
	# plain rectangle silhouette.
	var tip = MeshInstance3D.new()
	var tip_box = BoxMesh.new()
	tip_box.size = Vector3(base_size.x * 0.25, base_size.y * 0.45, base_size.z * 0.6)
	tip.mesh = tip_box
	tip.material_override = mat
	tip.position = Vector3(base_size.x * 0.45, 0, -base_size.z * 0.15)
	parent_node.add_child(tip)


static func _build_thruster(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Jet/rocket nacelle - no visible blades (reads as reaction thrust, not
	# a propeller), distinct from propeller_prop/pusher_prop/ship_screw.
	var nacelle = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = base_size.y * 0.5
	cyl.bottom_radius = base_size.y * 0.45
	cyl.height = base_size.z * 0.75
	nacelle.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.metallic = 0.75
	mat.roughness = 0.3
	nacelle.material_override = mat
	nacelle.rotation = Vector3(PI / 2.0, 0, 0)
	parent_node.add_child(nacelle)

	var exhaust = MeshInstance3D.new()
	var exhaust_cyl = CylinderMesh.new()
	exhaust_cyl.top_radius = base_size.y * 0.5
	exhaust_cyl.bottom_radius = base_size.y * 0.35
	exhaust_cyl.height = base_size.z * 0.3
	exhaust.mesh = exhaust_cyl
	var exhaust_mat = StandardMaterial3D.new()
	exhaust_mat.albedo_color = Color(1.0, 0.5, 0.1)
	exhaust_mat.emission_enabled = true
	exhaust_mat.emission = Color(1.0, 0.4, 0.05)
	exhaust_mat.emission_energy_multiplier = 1.2
	exhaust.material_override = exhaust_mat
	exhaust.rotation = Vector3(PI / 2.0, 0, 0)
	exhaust.position = Vector3(0, 0, base_size.z * 0.55)
	parent_node.add_child(exhaust)


## Geometric Polish Pass (Section 3): a real thinning taper for
## propeller/screw blades - thick chord at the hub, narrow at the tip -
## instead of a constant-cross-section BoxMesh. Spans along local Y
## (0=root, span=tip); tapers chord along local Z; thickness (local X)
## stays constant along the span, matching how a real blade is built.
static func _build_tapered_blade_mesh(thickness: float, root_chord: float, tip_chord: float, span: float) -> ArrayMesh:
	var hx = thickness * 0.5
	var hz0 = root_chord * 0.5
	var hz1 = tip_chord * 0.5
	var root_pts = [
		Vector3(-hx, 0.0, -hz0), Vector3(hx, 0.0, -hz0),
		Vector3(hx, 0.0, hz0), Vector3(-hx, 0.0, hz0),
	]
	var tip_pts = [
		Vector3(-hx, span, -hz1), Vector3(hx, span, -hz1),
		Vector3(hx, span, hz1), Vector3(-hx, span, hz1),
	]
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(4):
		var a = root_pts[i]
		var b = root_pts[(i + 1) % 4]
		var c = tip_pts[(i + 1) % 4]
		var d = tip_pts[i]
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
	st.add_vertex(root_pts[0]); st.add_vertex(root_pts[2]); st.add_vertex(root_pts[1])
	st.add_vertex(root_pts[0]); st.add_vertex(root_pts[3]); st.add_vertex(root_pts[2])
	st.add_vertex(tip_pts[0]); st.add_vertex(tip_pts[1]); st.add_vertex(tip_pts[2])
	st.add_vertex(tip_pts[0]); st.add_vertex(tip_pts[2]); st.add_vertex(tip_pts[3])
	st.generate_normals()
	return st.commit()


static func _build_propeller(parent_node: Node3D, base_size: Vector3, base_color: Color, pusher: bool):
	# Flat 3-blade fan on a hub, forward-facing (tractor) by default -
	# pusher_prop passes pusher=true to flip which end the blades sit on,
	# the "visually distinct placement/orientation" the task asked for,
	# with zero extra mount-system code (purely which local Z the blades
	# and hub are authored toward).
	var facing = 1.0 if pusher else -1.0
	var hub = MeshInstance3D.new()
	var hub_cyl = CylinderMesh.new()
	hub_cyl.top_radius = base_size.x * 0.25
	hub_cyl.bottom_radius = base_size.x * 0.22
	hub_cyl.height = base_size.z * 0.5
	hub.mesh = hub_cyl
	var hub_mat = StandardMaterial3D.new()
	hub_mat.albedo_color = base_color.darkened(0.3)
	hub_mat.metallic = 0.7
	hub.material_override = hub_mat
	hub.rotation = Vector3(PI / 2.0, 0, 0)
	hub.position = Vector3(0, 0, facing * base_size.z * 0.3)
	parent_node.add_child(hub)

	_attach_propeller_blades(parent_node, base_size, base_color, pusher)


# 3-blade tractor/pusher fan, wrapped under a "PropBlades" pivot so it can
# spin (about local Z, matching the rotate_z fan arrangement below)
# independently of the (static) hub.
static func _attach_propeller_blades(parent_node: Node3D, base_size: Vector3, base_color: Color, pusher: bool):
	var facing = 1.0 if pusher else -1.0
	var pivot = Node3D.new()
	pivot.name = "PropBlades"
	pivot.position = Vector3(0, 0, facing * base_size.z * 0.55)
	parent_node.add_child(pivot)

	var blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color.SILVER
	var blade_mesh = _build_tapered_blade_mesh(0.03, 0.14, 0.045, base_size.x * 0.9)
	for i in range(3):
		var blade = MeshInstance3D.new()
		blade.mesh = blade_mesh
		blade.material_override = blade_mat
		blade.rotate_z(i * (TAU / 3.0))
		pivot.add_child(blade)


static func _build_paddle_wheel(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Steamship-style side paddle wheel: a disc whose face points sideways
	# (matching a side hull mount) with flat paddle blades radiating from
	# the rim - distinct from ship_screw's twisted blades or
	# naval_propeller's stern fan.
	var disc = MeshInstance3D.new()
	var disc_cyl = CylinderMesh.new()
	disc_cyl.top_radius = base_size.x * 0.45
	disc_cyl.bottom_radius = base_size.x * 0.45
	disc_cyl.height = base_size.y * 0.2
	disc.mesh = disc_cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color.darkened(0.1)
	mat.metallic = 0.5
	mat.roughness = 0.6
	disc.material_override = mat
	disc.rotation = Vector3(0, 0, PI / 2.0)
	parent_node.add_child(disc)

	_attach_paddle_wheel_blades(parent_node, base_size, base_color)


# 6 radial paddle blades, wrapped under a "PropBlades" pivot so they can spin
# (about local X, matching the rotate_x fan arrangement below) independently
# of the (static) disc.
static func _attach_paddle_wheel_blades(parent_node: Node3D, base_size: Vector3, base_color: Color):
	var pivot = Node3D.new()
	pivot.name = "PropBlades"
	parent_node.add_child(pivot)

	var paddle_mat = StandardMaterial3D.new()
	paddle_mat.albedo_color = base_color.darkened(0.35)
	for i in range(6):
		var paddle = MeshInstance3D.new()
		var paddle_box = BoxMesh.new()
		paddle_box.size = Vector3(base_size.y * 0.18, base_size.x * 0.35, base_size.z * 0.85)
		paddle.mesh = paddle_box
		paddle.material_override = paddle_mat
		paddle.rotation = Vector3(0, 0, PI / 2.0)
		paddle.rotate_x(i * (TAU / 6.0))
		pivot.add_child(paddle)


static func _build_ship_screw(parent_node: Node3D, base_size: Vector3, base_color: Color):
	# Twisted (pitched) blade screw propeller - the real distinguishing
	# "screw" look vs. paddle_wheel's flat radial paddles or
	# naval_propeller's flat 3-blade fan.
	var hub = MeshInstance3D.new()
	var hub_cyl = CylinderMesh.new()
	hub_cyl.top_radius = base_size.x * 0.15
	hub_cyl.bottom_radius = base_size.x * 0.15
	hub_cyl.height = base_size.z * 0.7
	hub.mesh = hub_cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.metallic = 0.75
	mat.roughness = 0.3
	hub.material_override = mat
	hub.rotation = Vector3(PI / 2.0, 0, 0)
	parent_node.add_child(hub)

	_attach_ship_screw_blades(parent_node, base_size)


# 4 twisted (pitched) blades, wrapped under a "PropBlades" pivot so they can
# spin (about local Z, matching the rotate_z fan arrangement below)
# independently of the (static) hub.
static func _attach_ship_screw_blades(parent_node: Node3D, base_size: Vector3):
	var pivot = Node3D.new()
	pivot.name = "PropBlades"
	parent_node.add_child(pivot)

	var blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color.SILVER
	var blade_mesh = _build_tapered_blade_mesh(0.025, base_size.x * 0.38, base_size.x * 0.12, base_size.x * 0.55)
	for i in range(4):
		var blade = MeshInstance3D.new()
		blade.mesh = blade_mesh
		blade.material_override = blade_mat
		blade.rotation.x = 0.5
		blade.rotate_z(i * (TAU / 4.0))
		pivot.add_child(blade)


# Procedural mount hardware (post + bolted base plate) was removed
# 2026-07-21: authored module meshes now bring their own baked-in mounting
# post/base (see build_visual()'s monolithic-mesh path), and
# module_placer.gd flush-rotates the whole module to the surface normal
# instead of extruding it outward along a separate column axis - see
# MOUNTING_AND_ARMOR_SPEC.md addendum. A weapon type still on the
# procedural-primitive fallback path (no authored .glb yet) simply has no
# extra mount geometry drawn until it gets one.

static func rebuild_visual(module: Node3D):
	if not module or not module.has_meta("module_data"): return
	var data = module.get_meta("module_data")
	var catalog_data = preload("res://scripts/module_catalog.gd").get_module_data(data.type_id)
	if catalog_data:
		var size: Vector3 = catalog_data.get("size", Vector3.ONE)
		# Structural pieces use SCALE ISOLATION, the same trick the hull uses
		# (gizmo_3d.gd's _apply_scale_to_node): their resize is carried as a
		# meta multiplier on the BASE SIZE and rebuilt here, rather than
		# written to the node's own `scale`. Scaling the node would drag the
		# fixed-size authored hardware along with it and smear every bolt
		# head, which is exactly what the parametric-body split exists to
		# avoid - the body has to be rebuilt at the new size so the detail
		# count can change instead.
		if module.has_meta("struct_scale"):
			var ss: Vector3 = module.get_meta("struct_scale")
			size = Vector3(size.x * ss.x, size.y * ss.y, size.z * ss.z)
		build_visual(data.type_id, module, size, catalog_data.color, data.tweaks)

# PERFORMANCE_PLAN.md P4: MODULAR_ASSEMBLY_TYPES modules (every weapon,
# every locomotion type, and the structural hull-extenders) build_visual()
# as many individually-instanced MeshInstance3Ds - up to ~9 for a 4-barrel
# cannon, more for multi-axle wheels - each with its own freshly-allocated
# StandardMaterial3D, none of it batchable. That's real in a battle instance
# (draw calls, per-node culling/AABB overhead) and pointless in the Design
# Lab, where those same nodes ARE the editable representation (gizmo drag
# handles, per-part tweak deformation all target them by name/index).
#
# Call this ONLY on a battle-spawned module (never a Design-Lab one - see
# blueprint_manager.gd's reconstruct_vehicle(), which gates this on
# `not is_designer`), after rebuild_visual() has built the module's real
# geometry. Merges this module's direct-child MeshInstance3D siblings into
# one baked MeshInstance3D per distinct material (SurfaceTool, grouped so a
# module with e.g. a metal pintle + a darker barrel still ends up as 2 draw
# calls, not 1 with the wrong color) - typically collapses 3-9 nodes down to
# 1-3. Named animation pivots (MONOLITHIC_ANIMATION_PIVOTS' values, plus the
# procedural equivalents the modular-assembly branches build under the same
# names - BarrelCluster, RotorBlades, WingPivot, PropBlades) are left
# untouched: those rotate independently every frame (auto_weapon.gd's
# rotary-cannon spin-up, battle_unit.gd's rotor/prop animation) and merging
# them into a static mesh would freeze that motion.
const _ANIMATED_PART_NAMES := ["BarrelCluster", "RotorBlades", "WingPivot", "PropBlades"]

static func bake_module_visual(module: Node3D) -> void:
	if not module:
		return
	# material_override -> Array[MeshInstance3D] sharing that exact material
	# resource. null is a valid dictionary key here (an unmaterialed part) and
	# groups correctly with other unmaterialed parts.
	var groups: Dictionary = {}
	var to_remove: Array = []
	for child in module.get_children():
		if not (child is MeshInstance3D):
			continue
		if child.name in _ANIMATED_PART_NAMES:
			continue
		if child.mesh == null:
			continue
		var mat = child.material_override
		if not groups.has(mat):
			groups[mat] = []
		groups[mat].append(child)
		to_remove.append(child)

	# Nothing to gain merging a single part (most monolithic-mesh modules hit
	# this - they're already one node) or an empty module.
	if to_remove.size() <= 1:
		return

	for mat in groups.keys():
		var parts: Array = groups[mat]
		var surface_tool = SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in parts:
			# Iterate every surface, not just 0 - _mesh_inst() overrides the
			# WHOLE MeshInstance3D's material regardless of how many surfaces
			# its source mesh has, so a multi-surface authored part would
			# silently lose geometry merging only surface 0.
			for s in range(part.mesh.get_surface_count()):
				surface_tool.append_from(part.mesh, s, part.transform)
		surface_tool.generate_normals()
		var baked_inst = MeshInstance3D.new()
		baked_inst.name = "BakedVisual"
		baked_inst.mesh = _with_lods(surface_tool.commit())
		baked_inst.material_override = mat
		module.add_child(baked_inst)

	for part in to_remove:
		module.remove_child(part)
		part.queue_free()


# Regenerates level-of-detail data on a runtime-merged mesh.
#
# Every authored .glb imports with meshes/generate_lods=true, so a part drawn
# straight from the asset already sheds triangles at distance. SurfaceTool
# merging throws that away: commit() returns a plain ArrayMesh with a single
# LOD level, so a BAKED module - which is most of them, since a weapon is an
# assembly of six to ten parts - rendered its full density at every zoom. An
# autocannon is ~9k triangles across its parts, and an RTS draws a dozen
# vehicles carrying several modules each.
#
# ImporterMesh is the same simplifier the import pipeline uses, exposed at
# runtime. It is wrapped defensively because it is editor-adjacent API: if it
# is unavailable or throws, the un-LODded mesh is still perfectly correct,
# just as expensive as it was before.
static func _with_lods(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var im := ImporterMesh.new()
	for s in range(mesh.get_surface_count()):
		im.add_surface(mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s),
			[], {}, mesh.surface_get_material(s), "", mesh.surface_get_format(s))
	# 25 deg merge / 60 deg split are the import defaults - the angles below
	# which the simplifier may weld normals, and above which it must keep a
	# hard edge. These meshes are hard-surface greebles, so preserving the
	# hard edges is what keeps a decimated breech from turning to mush.
	im.generate_lods(25.0, 60.0, [])
	var out := im.get_mesh()
	return out if out != null else mesh


# --- Tweak deformation for monolithic authored meshes ----------------------
#
# _apply_tweak_deformations() below reshapes a module by scaling individual
# sub-meshes of the procedural build (children[1] is the barrel, children[2]
# is the drum, and so on). A monolithic authored .glb has no sub-meshes - the
# whole module is one MeshInstance3D - and build_visual()'s monolithic branch
# returns before ever reaching that function. Since every module now ships an
# authored .glb, that made EVERY tweak slider in the Design Lab, and the
# gizmo's drag-to-tweak handles, visually inert: the stat readout moved (stats
# come from stat_calculator.gd, which was never affected) while the model on
# screen never changed.
#
# A single mesh can still express its tweaks by scaling along the axis the
# tweak is about, which is what this table encodes: which of the module's own
# axes each tweak stretches. Vector3 components are flags, not magnitudes -
# (1,1,0) means "this tweak fattens the cross-section", (0,0,1) means "this
# tweak extends it forward", (1,1,1) means "this tweak grows the whole part".
# The axis each tweak maps to matches what the procedural path already did to
# the corresponding sub-mesh, and what gizmo_3d.gd's get_tweak_for_axis()
# binds to the X and Z drag handles.
const MONOLITHIC_TWEAK_AXES := {
	"basic_cannon": {"caliber": Vector3(1, 1, 0), "barrel_length": Vector3(0, 0, 1)},
	"heavy_machine_gun": {"caliber": Vector3(1, 1, 0), "drum_size": Vector3(1, 1, 1)},
	"rotary_cannon": {"caliber": Vector3(1, 1, 0), "motor_size": Vector3(1, 1, 1)},
	"artillery": {"caliber": Vector3(1, 1, 0), "barrel_length": Vector3(0, 0, 1)},
	"guided_missile": {"seeker_size": Vector3(1, 1, 0), "engine_length": Vector3(0, 0, 1)},
	"flamethrower": {"nozzle_width": Vector3(1, 1, 0), "pressure_valve": Vector3(1, 1, 1)},
	"heavy_laser": {"lens_aperture": Vector3(1, 1, 0), "barrel_length": Vector3(0, 0, 1), "focal_length": Vector3(0, 0, 1)},
	"plasma_lobber": {"containment": Vector3(1, 1, 1), "caliber": Vector3(1, 1, 0), "barrel_length": Vector3(0, 0, 1), "charge_rate": Vector3(0, 0, 1)},
	"ciws": {"caliber": Vector3(1, 1, 0), "barrel_length": Vector3(0, 0, 1), "radar_dish": Vector3(1, 1, 1), "burst_length": Vector3(0, 0, 1)},
	"pd_laser": {"cooling_jacket": Vector3(1, 1, 1), "barrel_length": Vector3(0, 0, 1), "tracking_speed": Vector3(1, 0, 0)},
	"flak_cannon": {"caliber": Vector3(1, 1, 0), "barrel_length": Vector3(0, 0, 1), "barrel_count": Vector3(1, 0, 0), "fuse_setting": Vector3(1, 1, 1), "burst_size": Vector3(0, 0, 1)},
	"drone_carrier": {"hangar_size": Vector3(1, 0, 0), "launch_catapult": Vector3(0, 0, 1)},
	"resource_harvester": {"extractor_size": Vector3(1, 1, 1)},
	"sensor_suite": {"mast_height": Vector3(0, 1, 0)},
	"cluster_dispenser": {"dispersion": Vector3(1, 0, 1), "payload_size": Vector3(1, 1, 1), "tube_count": Vector3(1, 0, 0)},
	"mortar_array": {"tube_count": Vector3(1, 0, 1)},
	"missile_pod": {"grid_size": Vector3(1, 0, 1), "warhead_size": Vector3(1, 1, 0), "motor_length": Vector3(0, 0, 1), "seeker_size": Vector3(1, 1, 0), "engine_length": Vector3(0, 0, 1)},
	"tesla_coil": {"caliber": Vector3(1, 1, 1), "arc_frequency": Vector3(0, 0, 1), "surge_capacity": Vector3(0, 1, 1)},
	"ion_cannon": {"beam_width": Vector3(1, 1, 0), "ion_density": Vector3(0, 0, 1)},
}

# Per-axis multiplier for a monolithic mesh, expressed in MESH-local axes.
#
# The table above is written in the module's own frame (x = width,
# y = height, z = forward), but the authored mesh is mounted with a yaw offset
# to correct TripoSG's native orientation, and Godot composes a node's basis
# as rotation * scale - so a scale assigned to the node is applied along mesh
# axes and only then rotated. The multiplier therefore has to be permuted back
# through that rotation, otherwise "lengthen the barrel" would fatten the gun
# sideways instead.
static func _monolithic_tweak_scale(type_id: String, tweaks: Dictionary, mesh_rotation: Vector3) -> Vector3:
	if tweaks.is_empty() or not MONOLITHIC_TWEAK_AXES.has(type_id):
		return Vector3.ONE
	var module_space = Vector3.ONE
	for tweak_name in MONOLITHIC_TWEAK_AXES[type_id]:
		if not tweaks.has(tweak_name):
			continue
		var value = float(tweaks[tweak_name])
		if value <= 0.0:
			continue
		var axes: Vector3 = MONOLITHIC_TWEAK_AXES[type_id][tweak_name]
		# Flag set -> this tweak scales that axis; flag clear -> leave it be.
		module_space *= Vector3(
			value if axes.x > 0.5 else 1.0,
			value if axes.y > 0.5 else 1.0,
			value if axes.z > 0.5 else 1.0)
	return (Basis.from_euler(mesh_rotation).transposed() * module_space).abs()

static func _apply_tweak_deformations(type_id: String, parent: Node3D, tweaks: Dictionary, base_size: Vector3):
	var children = parent.get_children().filter(func(c): return c is MeshInstance3D)
	if children.is_empty(): return

	match type_id:
		"basic_cannon", "heavy_machine_gun", "rotary_cannon", "gauss_railgun", "artillery", "mortar_array", "guided_missile", "missile_pod", "cluster_dispenser", "flamethrower", "tesla_coil", "ion_cannon", "heavy_laser", "laser_cannon", "plasma_lobber", "plasma_launcher", "ciws", "pd_laser", "point_defense_laser", "flak_cannon", "flak_battery", "drone_carrier", "resource_harvester", "repair_array", "sensor_suite", "smoke_discharger", "mk19_grenade_launcher", "recoilless_rifle", "coil_gun", "autocannon", "napalm_mortar", "mine_layer", "ballista", "anti_materiel_rifle", "arc_projector", "microwave_emitter", "particle_lance", "spigot_mortar", "rocket_artillery", "hypervelocity_missile", "sam_launcher", "loitering_munition", "anti_radiation_missile", "bunker_buster", "cruise_missile", "chaff_dispenser", "laser_dazzler", "aps_interceptor", "aa_autocannon", "jammer_mast", "sentry_deployer", "sensor_beacon_launcher", "decoy_projector":
			return

# Builds a wedge (triangular prism) mesh from a base_size Vector3.
# The wedge has a flat base (full width X and depth Z) that tapers to a
# ridge along the top centerline (Y-direction apex). This is a simple
# ArrayMesh with 5 faces: base, back, and two sloped sides, + 2 end caps.
# Fraction of the piece's depth taken up by the flat top deck at the back.
# The rest is the sloped glacis. Zero here would give a knife edge, which is
# not a thing anyone fabricates out of armour plate.
const WEDGE_DECK_FRACTION := 0.30

static func _build_wedge_mesh(size: Vector3) -> ArrayMesh:
	# A REAL wedge. What was here before declared eight vertices and then put
	# the top four at the full size on all axes - i.e. it built a plain box,
	# with comments describing an "apex" and a "top ridge" that the geometry
	# never had. "Wedge Breech" has therefore always rendered as a rectangular
	# block indistinguishable from Structure Block.
	#
	# Shape: bottom rectangle, a glacis rising from the FRONT edge (-Z, which
	# is forward everywhere in this codebase) to a knuckle, then a flat deck
	# running back from the knuckle to the rear face.
	#
	# Flat-shaded, not smooth-normal averaged: this is folded plate, and
	# averaging normals across the knuckle rounded the fold into a soft blob
	# and darkened the deck (which is what made the old box look hollow).
	var hw = size.x / 2.0
	var h = size.y
	var hd = size.z / 2.0
	var zk = -hd + size.z * (1.0 - WEDGE_DECK_FRACTION)

	var p_bfl = Vector3(-hw, 0, -hd)  # bottom front left
	var p_bfr = Vector3( hw, 0, -hd)
	var p_brl = Vector3(-hw, 0,  hd)  # bottom rear left
	var p_brr = Vector3( hw, 0,  hd)
	var p_kl  = Vector3(-hw, h, zk)   # knuckle (top of the glacis)
	var p_kr  = Vector3( hw, h, zk)
	var p_trl = Vector3(-hw, h,  hd)  # top rear
	var p_trr = Vector3( hw, h,  hd)

	var verts = PackedVector3Array()
	var normals = PackedVector3Array()

	# Each quad emitted as two triangles with one shared face normal.
	var quads = [
		[p_bfl, p_brl, p_brr, p_bfr],  # bottom
		[p_bfl, p_bfr, p_kr,  p_kl],   # glacis
		[p_kl,  p_kr,  p_trr, p_trl],  # top deck
		[p_brl, p_trl, p_trr, p_brr],  # rear face
		[p_bfl, p_kl,  p_trl, p_brl],  # left flank
		[p_bfr, p_brr, p_trr, p_kr],   # right flank
	]
	for q in quads:
		var n = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for idx in tri:
				verts.append(q[idx])
				normals.append(n)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# Where the glacis surface sits at depth fraction `t` (0 = front edge, 1 =
# knuckle). Used to lay step cleats onto the actual slope instead of guessing
# at a diagonal, and to pitch them to match it.
static func _wedge_slope_point(size: Vector3, t: float) -> Vector3:
	var hd = size.z / 2.0
	var zk = -hd + size.z * (1.0 - WEDGE_DECK_FRACTION)
	return Vector3(0, size.y * t, lerp(-hd, zk, t))

static func _wedge_slope_pitch(size: Vector3) -> float:
	var run = size.z * (1.0 - WEDGE_DECK_FRACTION)
	return atan2(size.y, max(0.001, run))

# Compute smooth vertex normals for an indexed triangle mesh.
static func _compute_smooth_normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals = PackedVector3Array()
	normals.resize(verts.size())
	for i in verts.size():
		normals[i] = Vector3.ZERO

	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i+1]
		var i2 = indices[i+2]
		var e1 = verts[i1] - verts[i0]
		var e2 = verts[i2] - verts[i0]
		var n = e1.cross(e2).normalized()
		normals[i0] += n
		normals[i1] += n
		normals[i2] += n

	for i in normals.size():
		normals[i] = normals[i].normalized()

	return normals




static func _build_weapon_armor(parent_node: Node3D, stage: int, base_size: Vector3, base_color: Color, tweaks: Dictionary = {}):
	if stage <= 0:
		return

	# Armour tracks the weapon's own tweaks: a bigger calibre grows the whole
	# casemate, and extra barrels/tubes widen it to cover them. Without this the
	# enclosure stayed at the catalog size while the gun inside it grew, so the
	# barrels pushed straight through the plates.
	var girth: float = _weapon_armor_girth(tweaks)   # overall size multiplier
	var spread: float = _weapon_armor_spread(tweaks) # extra WIDTH for more barrels

	# ── Adaptive sizing ──────────────────────────────────────────────────
	# The enclosure is fitted to the weapon's HOUSING, measured from the
	# geometry that has already been built, not to the catalog's base_size.
	#
	# base_size is the module's overall footprint, and for a gun most of it is
	# BARREL: basic_cannon is (0.6, 0.6, 2.0), where z = 2.0 is almost entirely
	# barrel length. The old code took w_base = x * 1.3 and d_base = z * 0.6,
	# i.e. 0.78 wide by 1.2 deep - a box sized off the barrel, which is why the
	# armour only ever landed "roughly" on the gun instead of wrapping its
	# breech and mount. Measuring the built housing makes the same code fit
	# every weapon in the roster, whatever its proportions.
	var housing := _weapon_housing_bounds(parent_node, base_size, girth, spread)

	var a_mat = StandardMaterial3D.new()
	a_mat.albedo_color = base_color.darkened(0.2)
	a_mat.metallic = 0.5
	a_mat.roughness = 0.5
	# Armour plates render double-sided.
	#
	# The geometry below is a closed solid with verified-outward winding (every
	# face is emitted through _add_tri, which derives winding from an explicit
	# outward direction), and an isolated ray test finds zero camera-visible back
	# faces. Yet the plates still read as hollow in the scene, which means
	# something in the live transform chain is inverting them - a mirrored module
	# contributes a determinant-(-1) basis, and turret_armor.gd overwrites the
	# holder's basis every frame on top of whatever the parent chain carries.
	# Rather than keep chasing which combination flips it, disable culling: for a
	# thin plate the back face is a legitimate surface to see anyway (you can look
	# into an open-topped turret), and it makes the plates impossible to lose to
	# a winding or handedness bug from any source.
	a_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var centre_x: float = housing.position.x + housing.size.x * 0.5
	var centre_z: float = housing.position.z + housing.size.z * 0.5
	# Never start below the module's mounting plane. Authored part meshes are not
	# all modelled sitting on y=0 - heavy_machine_gun's pintle mesh straddles the
	# origin - so an unclamped housing floor put the whole enclosure underneath
	# the weapon, which is the "tiny capsule below the gun" symptom.
	var floor_y: float = max(housing.position.y, 0.0)

	# SIZE comes from the module's own cross-section; PLACEMENT comes from the
	# measured housing above.
	#
	# Splitting it this way is deliberate. Deriving the size from measured
	# geometry sounds better but cannot be made reliable, because a breech is
	# long and thin in exactly the way a barrel is: on basic_cannon the breech
	# (0.27 x 0.30 x 0.97) and the barrel (0.15 x 0.15 x 1.51) are the same shape
	# to any aspect-ratio test, so excluding barrels also excluded the breech and
	# the enclosure shrank to just the pintle; while on artillery the elevation
	# assembly (0.39 x 2.56 x 3.46) is squat enough to pass as housing and gave a
	# casemate 3.79 tall on a module only 1.8 high.
	#
	# base_size.x/y are the weapon's calibre-ish cross-section and scale sensibly
	# across the whole roster; only base_size.z is barrel-dominated, so it is not
	# used. The measured housing still decides WHERE the enclosure sits, which is
	# the part that has to adapt per weapon and is robust to measure (a centre is
	# far less sensitive to a stray mesh than an extent).
	# All three dimensions come from the measured action volume, each clamped to a
	# sane band around the module's declared size (scaled by the same tweak
	# multipliers, so the bands move with the weapon).
	#
	# Measuring rather than using a flat ratio is what stops the casemate
	# swallowing the muzzle on compact weapons: a flat depth of 1.7 x base_size.x
	# put the armour's front face 0.52 beyond the end of mortar_array's tubes and
	# 0.42 beyond missile_pod's rocket grid, so the very thing that should
	# protrude was enclosed.
	var w_base: float = clampf(housing.size.x * 1.45,
		base_size.x * 1.15 * girth * spread, base_size.x * 2.0 * girth * spread)
	var d_base: float = clampf(housing.size.z * 1.45,
		base_size.x * 1.05 * girth, base_size.x * 1.9 * girth)

	# The casemate never reaches past the weapon's own frontmost geometry. This is
	# "let the barrel protrude" stated generally, and it is what keeps the armour
	# off the business end of weapons whose body is short: mortar_array's tubes,
	# rotary_cannon's barrel cluster and missile_pod's rocket grid all sat INSIDE
	# the plates before this, because a depth derived from the body alone happened
	# to exceed the distance to the muzzle. For a long gun the barrel tip is far
	# forward and this never binds.
	var front_z: float = _weapon_front_z(parent_node)
	# 0.95 leaves a slight recess rather than landing exactly flush, so the plate
	# and the muzzle face are never coplanar (which would z-fight).
	var max_depth: float = 2.0 * max(centre_z - front_z, 0.0) * 0.95
	if max_depth > 0.0:
		d_base = min(d_base, max(max_depth, base_size.x * 0.6 * girth))

	# heavy_machine_gun needs the measured height (base_size.y is 0.30, well under
	# its built receiver, so a purely declared height gave a stubby box below the
	# gun); artillery needs the clamp.
	var measured_h: float = max(housing.position.y + housing.size.y - floor_y, 0.01)
	var h_plate: float = clampf(measured_h * 1.05,
		base_size.y * 0.8 * girth, base_size.y * 1.8 * girth)

	# Corner cut, always non-zero at BOTH base and top so the silhouette is a
	# true octagon all the way up.
	#
	# The old code left c_base = 0 below stage 4, which made vertex pairs
	# 0/1, 2/3, 4/5 and 6/7 land on the same position. Coincident-but-distinct
	# vertices got different averaged normals, so the inner surface was offset
	# two different ways at every corner and the plates did not close up - the
	# "plates don't meet reliably" symptom - and the corner faces degenerated to
	# zero-width triangles.
	var c_base: float = min(w_base, d_base) * 0.22
	var thick: float = max(min(w_base, d_base) * 0.06, 0.02)

	# Inward slope of the walls, in the classic faceted-turret style.
	var inset: float = h_plate * 0.30
	var w_top: float = max(w_base - 2.0 * inset, min(w_base, d_base) * 0.35)
	var d_top: float = max(d_base - 2.0 * inset, min(w_base, d_base) * 0.35)
	var c_top: float = min(c_base, min(w_top, d_top) * 0.4)

	# Inner rings are the outer rings pulled in by the wall thickness. The
	# chamfer is reduced by thick*(sqrt(2)-1) so the 45-degree corner plates end
	# up the same thickness as the axis-aligned ones.
	var c_shrink: float = thick * 0.41421356
	var ib_c: float = max(c_base - c_shrink, 0.01)
	var it_c: float = max(c_top - c_shrink, 0.01)

	# Geometry is built around the LOCAL origin and the holder is positioned at
	# the housing centre instead. turret_armor.gd/mantlet_armor.gd overwrite the
	# holder's basis every frame to keep the enclosure level with the hull, and a
	# basis rotates about the node's own origin - so if the geometry carried the
	# centre offset internally, the enclosure would swing around the module's
	# origin instead of spinning about its own axis.
	var origin := Vector3.ZERO
	var ring_ob := _octagon_ring(w_base, d_base, c_base, 0.0, origin)
	var ring_ot := _octagon_ring(w_top, d_top, c_top, h_plate, origin)
	var ring_ib := _octagon_ring(max(w_base - 2.0 * thick, 0.02),
		max(d_base - 2.0 * thick, 0.02), ib_c, 0.0, origin)
	var ring_it := _octagon_ring(max(w_top - 2.0 * thick, 0.02),
		max(d_top - 2.0 * thick, 0.02), it_c, h_plate, origin)

	# ── Which of the 8 segments exist at this stage ───────────────────────
	# _octagon_ring's ordering puts segment i between ring[i] and ring[i+1]:
	#   0 front-right corner   1 FRONT           2 front-left corner
	#   3 LEFT                 4 back-left cnr   5 BACK
	#   6 back-right corner    7 RIGHT
	var segments: Array = []
	match stage:
		1:
			segments = [1]                      # mantlet: front plate only
		2:
			segments = [0, 1, 2, 3, 7]          # front, its corners, both sides
		_:
			segments = [0, 1, 2, 3, 4, 5, 6, 7] # closed ring
	var present := {}
	for s in segments:
		present[s] = true

	var verts := PackedVector3Array()
	var indices := PackedInt32Array()

	for s in segments:
		var i: int = s
		var j: int = (s + 1) % 8
		var ob: Vector3 = ring_ob[i]
		var ob2: Vector3 = ring_ob[j]
		var ot: Vector3 = ring_ot[i]
		var ot2: Vector3 = ring_ot[j]
		var ib: Vector3 = ring_ib[i]
		var ib2: Vector3 = ring_ib[j]
		var it: Vector3 = ring_it[i]
		var it2: Vector3 = ring_it[j]

		# Horizontal outward direction of this segment, used to orient faces.
		var along: Vector3 = ob2 - ob
		var outward := Vector3(along.z, 0.0, -along.x)
		if outward.length_squared() < 1e-9:
			outward = Vector3(0, 0, -1)
		outward = outward.normalized()
		if outward.dot((ob + ob2) * 0.5 - origin) < 0.0:
			outward = -outward

		_add_quad(verts, indices, ob, ob2, ot2, ot, outward)          # outer skin
		_add_quad(verts, indices, ib, ib2, it2, it, -outward)         # inner skin
		_add_quad(verts, indices, ob, ob2, ib2, ib, Vector3.DOWN)     # bottom rim
		# The top rim is needed at EVERY stage, including with a roof. The roof
		# slab only fills the INNER top octagon, so without this the annulus
		# between the outer and inner top rings is an open slot right around the
		# roof's edge - rays from above pass through it into the interior.
		_add_quad(verts, indices, ot, ot2, it2, it, Vector3.UP)       # top rim

		# Cap the open ends of a partial ring so it stays a closed solid.
		var prev: int = (s + 7) % 8
		if not present.has(prev):
			_add_quad(verts, indices, ob, ot, it, ib, -along.normalized())
		if not present.has(j):
			_add_quad(verts, indices, ob2, ot2, it2, ib2, along.normalized())

	# ── Roof ─────────────────────────────────────────────────────────────
	# A slab filling the inner top octagon, so it never touches the OUTER ring
	# and therefore cannot change the top-down silhouette. The old roof was a
	# triangle fan wound the wrong way round (its normals pointed at -Y), so it
	# was backface-culled - you saw straight into the turret - and because
	# _solidify() averaged face normals per vertex, that inverted fan also
	# dragged the top ring's inward offset off true, deforming the octagon at
	# exactly the corners where the plates meet.
	if stage >= 4:
		var roof_t: float = thick
		var under: Array = []
		for k in range(8):
			under.append(ring_it[k] - Vector3(0, roof_t, 0))
		# Top surface and underside, as fans from vertex 0.
		for k in range(1, 7):
			_add_tri(verts, indices, ring_it[0], ring_it[k], ring_it[k + 1], Vector3.UP)
			_add_tri(verts, indices, under[0], under[k], under[k + 1], Vector3.DOWN)
		# Rim between them, so the slab is closed.
		for k in range(8):
			var k2: int = (k + 1) % 8
			var a: Vector3 = ring_it[k]
			var b: Vector3 = ring_it[k2]
			var seg: Vector3 = b - a
			var out_h := Vector3(seg.z, 0.0, -seg.x)
			if out_h.length_squared() < 1e-9:
				out_h = Vector3(0, 0, -1)
			out_h = out_h.normalized()
			if out_h.dot((a + b) * 0.5 - origin) < 0.0:
				out_h = -out_h
			_add_quad(verts, indices, a, b, under[k2], under[k], out_h)

	if indices.is_empty():
		return

	var flat_mesh = _create_flat_shaded_mesh(verts, indices)

	# Stage 1 tilts with the gun (mantlet_armor.gd); stages 2+ stay level with
	# the hull and only yaw with the turret (turret_armor.gd).
	var holder = Node3D.new()
	if stage == 1:
		holder.name = "MantletPivot"
		holder.set_script(load("res://scripts/mantlet_armor.gd"))
	else:
		holder.name = "ArmorEnclosure"
		holder.set_script(load("res://scripts/turret_armor.gd"))
	holder.position = Vector3(centre_x, floor_y, centre_z)
	parent_node.add_child(holder)

	var shell = MeshInstance3D.new()
	shell.name = "ArmorShell"
	shell.mesh = flat_mesh
	shell.material_override = a_mat
	holder.add_child(shell)


# Overall armour size multiplier from whichever "how big is this weapon" tweak
# the module happens to expose. Different weapon families name it differently -
# guns have calibre, guided missiles a seeker, rocket pods a warhead, cluster
# weapons a payload - so take whichever is present rather than special-casing
# type_id, which would silently miss any weapon added later.
static func _weapon_armor_girth(tweaks: Dictionary) -> float:
	for key in ["caliber", "seeker_size", "warhead_size", "payload_size", "drum_size"]:
		if tweaks.has(key):
			return clampf(float(tweaks[key]), 0.4, 3.0)
	return 1.0


# Extra WIDTH only, for weapons that mount several barrels/tubes side by side.
# Mirrors the same (1 + (n-1)*0.35) spacing the weapon builders themselves use to
# lay those barrels out, so the plates widen exactly as fast as the guns do.
static func _weapon_armor_spread(tweaks: Dictionary) -> float:
	if bool(tweaks.get("multi_barrel", false)):
		return 1.4
	for key in ["barrel_count", "tube_count", "grid_size"]:
		if tweaks.has(key):
			var n: float = clampf(float(tweaks[key]), 1.0, 8.0)
			return 1.0 + (n - 1.0) * 0.35
	return 1.0


# One ring of the octagon, ordered so segment i spans ring[i] -> ring[i+1].
# `c` is the corner cut; a positive c on every ring is what keeps the silhouette
# a real octagon and stops corner vertices collapsing onto each other.
static func _octagon_ring(width: float, depth: float, c: float, y: float, origin: Vector3) -> Array:
	var hw: float = width * 0.5
	var hd: float = depth * 0.5
	var cc: float = clampf(c, 0.0, min(hw, hd) - 0.005)
	if cc < 0.0:
		cc = 0.0
	var o := origin + Vector3(0, y, 0)
	return [
		o + Vector3( hw, 0, -hd + cc),
		o + Vector3( hw - cc, 0, -hd),
		o + Vector3(-hw + cc, 0, -hd),
		o + Vector3(-hw, 0, -hd + cc),
		o + Vector3(-hw, 0,  hd - cc),
		o + Vector3(-hw + cc, 0,  hd),
		o + Vector3( hw - cc, 0,  hd),
		o + Vector3( hw, 0,  hd - cc),
	]


# Appends a triangle wound so its normal agrees with `outward`.
#
# Every face in the enclosure is emitted through this (or _add_quad), which is
# why winding cannot go wrong here: the caller states the direction the face
# should look, geometrically, and the winding is derived from that rather than
# from hand-ordered index lists. The old builder hand-wrote index lists and got
# the roof fan backwards.
static func _add_tri(verts: PackedVector3Array, indices: PackedInt32Array,
		a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	var base: int = verts.size()
	verts.append(a)
	if n.dot(outward) < 0.0:
		verts.append(c)
		verts.append(b)
	else:
		verts.append(b)
		verts.append(c)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)


static func _add_quad(verts: PackedVector3Array, indices: PackedInt32Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_add_tri(verts, indices, a, b, c, outward)
	_add_tri(verts, indices, a, c, d, outward)


# The weapon's ACTION volume: the mount and breech clustered around the pintle,
# which is what a casemate armours. Barrels are meant to protrude through it.
#
# Measurement is CLIPPED to a box around the mount rather than trying to
# classify whole meshes as barrel-or-not:
#   * horizontally +/- base_size.x * 0.9 on BOTH axes - never base_size.z, which
#     is barrel-dominated (basic_cannon's z is 2.0 against a 0.6 body),
#   * vertically base_size.y * 1.15 up from the mounting plane.
#
# Clipping is what makes this robust where classification could not be. Every
# per-mesh test failed on real data: basic_cannon's breech (0.27 x 0.30 x 0.97)
# is the same shape as its barrel (0.15 x 0.15 x 1.51) to any aspect-ratio rule,
# and artillery models its barrel TOGETHER with the elevation cradle as a single
# 0.39 x 2.56 x 3.46 mesh, so there is no mesh to exclude at all - that one mesh
# is both action and barrel. Clipping simply keeps whichever part of each mesh
# lies inside the action volume, so the artillery casemate now wraps the breech
# and carriage and lets the tube run out through it, instead of growing to 3.06
# tall to swallow the whole elevating mass.
# Frontmost point (most negative Z, the firing direction) of everything the
# weapon has built so far. Unclipped, unlike _weapon_housing_bounds - the whole
# point is to find the muzzle.
static func _weapon_front_z(parent_node: Node3D) -> float:
	var front: float = 0.0
	var found := false
	for child in parent_node.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi: MeshInstance3D = child
		if mi.mesh == null:
			continue
		var local: AABB = mi.mesh.get_aabb()
		for sx in [0.0, 1.0]:
			for sy in [0.0, 1.0]:
				for sz in [0.0, 1.0]:
					var p: Vector3 = mi.transform * (local.position + Vector3(
						local.size.x * sx, local.size.y * sy, local.size.z * sz))
					if not found or p.z < front:
						front = p.z
						found = true
	return front


# girth/spread scale the clip box with the weapon's own tweaks, so a bigger
# calibre or a wider multi-barrel cluster is still measured in full rather than
# being cut off by a box sized for the default configuration.
static func _weapon_housing_bounds(parent_node: Node3D, base_size: Vector3,
		girth: float = 1.0, spread: float = 1.0) -> AABB:
	var rx: float = max(base_size.x, 0.05) * 0.9 * girth * spread
	var rz: float = max(base_size.x, 0.05) * 0.9 * girth
	var lift: float = max(base_size.y, 0.05) * 1.15 * girth
	var clip := AABB(Vector3(-rx, 0.0, -rz), Vector3(rx * 2.0, lift, rz * 2.0))

	var found := false
	var acc := AABB()
	for child in parent_node.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi: MeshInstance3D = child
		if mi.mesh == null:
			continue
		var local := mi.mesh.get_aabb()
		var ext: Vector3 = local.size
		# Enclosing box of the mesh in the module's own space.
		var box := AABB()
		var first := true
		for sx in [0.0, 1.0]:
			for sy in [0.0, 1.0]:
				for sz in [0.0, 1.0]:
					var corner: Vector3 = mi.transform * (local.position + Vector3(
						ext.x * sx, ext.y * sy, ext.z * sz))
					if first:
						box = AABB(corner, Vector3.ZERO)
						first = false
					else:
						box = box.expand(corner)
		if not clip.intersects(box):
			continue
		var kept := clip.intersection(box)
		if kept.size.x <= 0.0001 or kept.size.z <= 0.0001:
			continue
		if not found:
			acc = kept
			found = true
		else:
			acc = acc.merge(kept)

	if not found:
		return AABB(Vector3(-base_size.x * 0.5, 0.0, -base_size.x * 0.5),
			Vector3(base_size.x, base_size.y, base_size.x))
	# A housing with no measurable height would give a zero-height enclosure.
	if acc.size.y < 0.01:
		acc.size.y = max(base_size.y * 0.5, 0.05)
	return acc


static func _create_flat_shaded_mesh(verts: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var flat_verts = PackedVector3Array()
	var flat_indices = PackedInt32Array()
	var flat_normals = PackedVector3Array()
	
	for i in range(0, indices.size(), 3):
		var v0 = verts[indices[i]]
		var v1 = verts[indices[i+1]]
		var v2 = verts[indices[i+2]]
		var n = (v1 - v0).cross(v2 - v0).normalized()
		
		var start_idx = flat_verts.size()
		flat_verts.append(v0)
		flat_verts.append(v1)
		flat_verts.append(v2)
		flat_normals.append(n)
		flat_normals.append(n)
		flat_normals.append(n)
		
		flat_indices.append(start_idx)
		flat_indices.append(start_idx + 1)
		flat_indices.append(start_idx + 2)
		
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = flat_verts
	arrays[Mesh.ARRAY_NORMAL] = flat_normals
	arrays[Mesh.ARRAY_INDEX] = flat_indices
	
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ===========================================================================
# LOCOMOTION EXPANSION BUILDERS (LOCOMOTION_EXPANSION_PLAN.md 4)
#
# Each is a straight assembly of authored parts. Placement of the module as a
# whole is locomotion_layout.gd's job - these only decide where a type's own
# sub-parts sit relative to its mount point, and which of them a tweak scales.
#
# The rule the rest of the roster follows and these keep: a tweak scales the
# PART it is about and nothing else, so a slider can never smear a bolt head.
# ===========================================================================

## Half-track: steered wheels forward, a short track bogie aft. The two ends
## are separate parts because bogie_count and front_axle_size move
## independently - the whole pitch of the type is that its two halves are
## different machines bolted to one frame.
static func _build_half_track(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DARK_OLIVE_GREEN, tweaks: Dictionary = {}):
	var bogies := int(tweaks.get("bogie_count", 3.0))
	var front_size := float(tweaks.get("front_axle_size", 1.0))
	var width := float(tweaks.get("tread_width", 1.0))
	# The assembly spans the hull it is mounted on, like tracked_treads.
	var target_length := float(tweaks.get("target_length", base_size.z))
	var half := target_length * 0.5

	# VERTICAL SIZE. Both parts are authored at a fixed depth (the belt loop
	# spans ~0.43 in Blender Z, the tyre is 0.245 in radius), which against a
	# real hull read as a paper ribbon with bicycle wheels (Chris: "the track
	# and the wheel are too small vertically"). Depth is now a fraction of the
	# assembly's own length, the same way tracked_treads derives everything
	# from its belt span, so it stays in proportion on any hull.
	const AUTHORED_LOOP_DEPTH := 0.43
	var depth: float = target_length * 0.22
	var v_scale: float = depth / AUTHORED_LOOP_DEPTH

	var axle_mesh := _part("ht_front_axle")
	if axle_mesh:
		# The steered wheel is a wheel, so it rolls - under its own named pivot
		# like every other ground-contact drive element in the roster.
		var axle_pivot := Node3D.new()
		axle_pivot.name = SPIN_PIVOT_WHEEL
		axle_pivot.position = Vector3(0, 0, -half + 0.30 * front_size * v_scale)
		parent_node.add_child(axle_pivot)
		var axle := _mesh_inst(axle_mesh, base_color.lightened(0.05))
		# The steered wheel grows with the track it shares an axle line with -
		# a half-track whose front wheel is half the height of its bogie looks
		# like two vehicles spliced together.
		axle.scale = Vector3(width * v_scale * 0.55, front_size * v_scale, front_size * v_scale)
		axle_pivot.add_child(axle)

	var bogie_mesh := _part("ht_track_bogie")
	if bogie_mesh:
		# ONE track, not one per bogie. This used to instance the authored
		# bogie `bogies` times down the run, so what read as "the track" was
		# actually three short closed loops parked nose to tail - every join
		# between them showed two belt ends meeting, which is what made the
		# front and back of the track portion look wrong (Chris). A half-track
		# has a single belt; bogie_count now sets how LONG that belt is, which
		# is the stat it was always standing in for.
		var run: float = target_length * 0.42 * (1.0 + 0.16 * float(bogies - 3))
		var bogie_pivot := Node3D.new()
		bogie_pivot.name = SPIN_PIVOT_TREAD
		bogie_pivot.position = Vector3(0, 0, half - run * 0.5)
		parent_node.add_child(bogie_pivot)
		var bogie := _mesh_inst(bogie_mesh, base_color)
		# Z is the fore/aft axis here, not Y: the parts are authored with
		# Blender +Y forward, which imports as Godot -Z. Scaling Y instead
		# squashed the assembly flat and left the track a paper ribbon.
		# 0.9 is the authored frame length end to end.
		bogie.scale = Vector3(width * v_scale * 0.55, v_scale, run / 0.9)
		bogie_pivot.add_child(bogie)

		# SUSPENSION STRUTS. Chris: "add a series of the struts on the inside
		# attaching to the underside of the hull." The bogie carries its own
		# mounting spine, but nothing visibly tied that spine to the vehicle -
		# the track just floated alongside the hull edge.
		#
		# The module origin sits AT the hull's underside (that invariant again -
		# see build_wheel_mount), so a strut running up and INBOARD from the
		# track's top rail arrives inside the hull by construction; no reach
		# solving, no hull measurement. mount_strut_tapered is authored along
		# local +Y spanning 0..1, thin at the root and flaring at the far end,
		# so it is oriented here by building a basis around the span vector -
		# the same technique the rotor and hover pylons use.
		var strut_mesh := _part("mount_strut_tapered")
		if strut_mesh:
			# One per bogie: the count that used to spawn a whole extra track
			# now spawns the suspension station it always meant.
			var n: int = maxi(2, bogies)
			# Start at the top of the track's own frame and run a SHORT way up
			# and inboard. First pass used a span of (-0.42, 0.30) * v_scale
			# with a 0.14 * v_scale cross-section, which on a real hull came
			# out as two great blades reaching most of the way to the
			# centreline. A suspension strut is a short thick link between two
			# things that are already almost touching.
			var rail_y: float = 0.02 * v_scale
			var strut_w: float = 0.10
			for i in range(n):
				var t: float = (float(i) + 0.5) / float(n)
				var z: float = half - run * t
				# Up and inboard, from the top of the track into the hull.
				var span := Vector3(-0.16 * v_scale, 0.26 * v_scale, 0.0)
				var len_s: float = span.length()
				var dir: Vector3 = span / len_s
				var right: Vector3 = dir.cross(Vector3.FORWARD).normalized()
				var fwd: Vector3 = right.cross(dir).normalized()
				var strut := _mesh_inst(strut_mesh, base_color.darkened(0.2))
				strut.transform = Transform3D(
					Basis(right * strut_w, dir * len_s, fwd * strut_w),
					Vector3(0.0, rail_y, z))
				parent_node.add_child(strut)


## Rocker-bogie: a free-pivoting arm chain. Built as a real linkage - primary
## rocker, secondary bogie, wheels at the knuckles - because the articulation
## IS the silhouette, and a rigid axle would read as a normal wheeled chassis.
static func _build_rocker_bogie(parent_node: Node3D, base_size: Vector3, base_color: Color = Color(0.42, 0.38, 0.30), tweaks: Dictionary = {}):
	var pairs := int(tweaks.get("bogie_pairs", 3.0))
	var arm_len := float(tweaks.get("arm_length", 1.0))
	var wheel_size := float(tweaks.get("wheel_size", 1.0))
	var target_length := float(tweaks.get("target_length", base_size.z))
	var span := target_length * 0.42

	# SIZE. Every part here was used at its authored scale, which has no
	# relationship to any hull - against a real one the whole linkage came out
	# as a handful of pebbles under the belly, which is what made it read as
	# both floating and flimsy (Chris). Scale is now derived from the span the
	# assembly actually has to cover, the same way half_track and
	# tracked_treads derive theirs, so it stays in proportion on any hull.
	# AUTHORED_SPAN is rb_rocker_arm's MEASURED fore/aft extent (0.83 along Z),
	# not a guessed round number - the first pass assumed 1.30 and the arms
	# came out well short of the wheels they were meant to reach. Same mistake
	# as the screw drum's stale _fit_scale divisors, so it is measured here
	# too: `span` is a half-extent, hence the doubling.
	const AUTHORED_ARM_Z := 0.83
	# Two factors, not one. z_s stretches the linkage fore/aft to cover the
	# span; p_s sizes the parts themselves - cross-sections, the drop to the
	# axle line, and the wheels. Driving all of it off z_s made the wheels grow
	# with the hull's LENGTH and lifted the body to 3.5 units on a medium hull.
	# How long a suspension is and how big its wheels are are separate
	# questions, and conflating them is the same error as scaling the legs by
	# the hull's height.
	var z_s: float = maxf(0.4, (span * 2.0) / AUTHORED_ARM_Z)
	var p_s: float = clampf(z_s * 0.42, 0.85, 1.7)
	var v_scale: float = p_s

	var rocker_mesh := _part("rb_rocker_arm")
	var bogie_mesh := _part("rb_bogie_arm")
	var wheel_mesh := _part("rb_wheel")

	# THE ATTACHMENT. A rocker-bogie hangs the whole linkage off ONE pivot per
	# side - that differential pivot is the only thing joining it to the body,
	# and it had nothing at all here ("the lack of running gear of any kind
	# attaching it to the hull"). build_wheel_mount() is that pivot: the
	# gearbox reads as the bearing housing and the driveshaft as the trunnion
	# arm running up into the hull. Same mount as the wheels and pontoons, for
	# the same reason it works there - the module origin is already at the
	# hull's underside.
	const WHEEL_GROWTH := 2.2
	var pivot_s: float = 0.55 * v_scale
	var hub := build_wheel_mount(parent_node, base_color, pivot_s, 0.0, 0.45 * pivot_s)

	var chain := Node3D.new()
	chain.position = hub
	parent_node.add_child(chain)

	if rocker_mesh:
		var rocker := _mesh_inst(rocker_mesh, base_color)
		rocker.scale = Vector3(p_s * 0.9, arm_len * p_s, z_s)
		chain.add_child(rocker)

	for i in range(pairs):
		var t: float = 0.5 if pairs <= 1 else float(i) / float(pairs - 1)
		var z: float = (-span + 2.0 * span * t)
		if bogie_mesh and i > 0:
			var bogie := _mesh_inst(bogie_mesh, base_color.darkened(0.08))
			bogie.scale = Vector3(p_s * 0.9, arm_len * p_s, z_s * 0.42)
			bogie.position = Vector3(0, -0.10 * arm_len * v_scale, z)
			chain.add_child(bogie)
		if wheel_mesh:
			var wheel_pivot := Node3D.new()
			wheel_pivot.name = SPIN_PIVOT_WHEEL
			# COLLAPSED UP. The linkage was spread over a drop of 0.30 * arm
			# length with wheels sized at p_s, which left daylight between
			# every pair of parts and read as a set of loose components rather
			# than one suspension (Chris: "it mostly just all needs to collapse
			# upwards, so the pieces actually connect"). The drop is more than
			# halved and the wheels are scaled up to close the rest of the gap
			# themselves - rb_wheel's authored radius is 0.211, so WHEEL_GROWTH
			# takes it to roughly twice what it was.
			# Outboard by half a wheel width (Chris) - rb_wheel is authored
			# 0.20 across, so half of that times the rendered scale. Keeps the
			# tyre clear of the arm it hangs on instead of straddling it.
			var wheel_scale: float = wheel_size * p_s * WHEEL_GROWTH
			wheel_pivot.position = Vector3(
				0.14 * wheel_size * p_s + 0.10 * wheel_scale,
				-0.12 * arm_len * p_s, z)
			chain.add_child(wheel_pivot)
			var wheel := _mesh_inst(wheel_mesh, Color(0.20, 0.20, 0.22))
			wheel.scale = Vector3.ONE * wheel_scale
			wheel_pivot.add_child(wheel)
			# HUB CARRIER. Stepping the wheel outboard by half its width opens
			# a gap between the arm's outer face and the tyre's inner one -
			# measured as 4 islands where there had been 1. A real suspension
			# has a carrier spanning exactly that gap, so this is the part the
			# geometry was asking for rather than a fudge to close a number.
			# Static (a sibling of the spin pivot, not a child) - the carrier
			# does not turn with the wheel.
			var carrier_mesh := _part("wheel_gearbox")
			if carrier_mesh:
				var carrier := _mesh_inst(carrier_mesh, base_color.lightened(0.2))
				# Sized to SPAN the gap, not to fill the space: a 0.34 cube
				# closed the islands but took the module to 0.996 bulk, i.e.
				# the suspension weighed as much as the vehicle. Long on X
				# (the axis the gap is on), slim on the other two.
				carrier.scale = Vector3(0.26, 0.15, 0.15) * wheel_scale
				carrier.position = Vector3(
					0.16 * wheel_size * p_s,
					-0.12 * arm_len * p_s, z)
				chain.add_child(carrier)


## Air-cushion skirt: one continuous bag around the module's footprint, with
## the lift fans set into the plenum deck above it.
static func _build_air_cushion_skirt(parent_node: Node3D, base_size: Vector3, base_color: Color = Color(0.55, 0.52, 0.42), tweaks: Dictionary = {}):
	var diameter := float(tweaks.get("skirt_diameter", 1.0))
	var fans := int(tweaks.get("lift_fan_count", 3.0))
	var plenum := float(tweaks.get("plenum_pressure", 1.0))
	# The hull's own plan dimensions, from locomotion_layout.gd's FOOTPRINT
	# pattern. Internal geometry channel, not a player tweak.
	var fx := float(tweaks.get("footprint_x", base_size.x))
	var fz := float(tweaks.get("footprint_z", base_size.z))

	# ONE skirt, wrapping the whole hull. acs_skirt is authored as a swept
	# wedge around a UNIT rounded rectangle (half-extent 0.5), so scaling X and
	# Z by the hull's own length and width lands the bag exactly on its bottom
	# edge - see build_acs_skirt() in tools/blender/build_locomotion_rework.py.
	# skirt_diameter now inflates it slightly PROUD of that edge rather than
	# setting an absolute size, which is what it means on a part that has to
	# match the hull it is fitted to.
	var skirt_mesh := _part("acs_skirt")
	if skirt_mesh:
		var skirt := _mesh_inst(skirt_mesh, base_color.darkened(0.35))
		# SKIRT_INNER_UNIT is the authored half-extent of the bag's INNER
		# wall - the face that laps the hull's sides - and build_acs_skirt()
		# in tools/blender/build_locomotion_rework.py authors it at exactly
		# this value. The two must change together. Scaling by the hull's own
		# width and length therefore lands that wall flush on the hull's sides,
		# with the outer bulge extending past it, which is correct: the bag is
		# wider than the vehicle.
		#
		# Deliberately NOT fitted to the mesh's AABB, unlike the screw drum and
		# the rocker arm. The AABB is the OUTER extent, and fitting that to the
		# hull would tuck the bag under the floor - the exact "bottom-to-top"
		# arrangement Chris asked to get away from.
		const SKIRT_INNER_UNIT := 0.5
		const AUTHORED_SECTION_HEIGHT := 0.52
		var proud: float = 1.0 + 0.10 * (diameter - 1.0)
		# Plenum pressure inflates the bag vertically rather than widening it -
		# a separate axis from skirt_diameter, so both sliders read distinctly.
		# Depth is its own number: tying it to the footprint made the bag
		# deeper on longer hulls, which is not what a skirt does.
		var depth: float = 0.86 * (0.85 + 0.30 * plenum)
		skirt.scale = Vector3(
			(fx * proud) / (SKIRT_INNER_UNIT * 2.0),
			depth / AUTHORED_SECTION_HEIGHT,
			(fz * proud) / (SKIRT_INNER_UNIT * 2.0))
		parent_node.add_child(skirt)

	var fan_mesh := _part("acs_lift_fan")
	if fan_mesh:
		for i in range(fans):
			var fan_pivot := Node3D.new()
			# Named so _animate_locomotion() spins it: a hovercraft with still
			# fans is the same "is this broken?" read the frozen road wheels had.
			fan_pivot.name = SPIN_PIVOT_TURBINE
			# Spread down the vehicle's LENGTH inside the bag, which is where a
			# hovercraft's lift fans actually sit - a ring of them made sense
			# when each was its own module, but there is one plenum now.
			var t: float = 0.0 if fans <= 1 else (float(i) / float(fans - 1)) - 0.5
			fan_pivot.position = Vector3(0.0, 0.16, t * fz * 0.55)
			fan_pivot.rotation = Vector3(PI / 2.0, 0, 0)
			parent_node.add_child(fan_pivot)
			var fan := _mesh_inst(fan_mesh, Color(0.30, 0.32, 0.34))
			fan.scale = Vector3.ONE * (0.75 + 0.25 * diameter) * maxf(1.0, fx * 0.35)
			fan_pivot.add_child(fan)


## Anti-grav plate: emitter plates in a cluster under an optional stabiliser
## toroid. The only locomotor with no moving contact surface at all, so its
## motion cue is the ring - which is exactly why dropping the ring for speed
## is a visible trade and not just a number.
static func _build_anti_grav_plate(parent_node: Node3D, base_size: Vector3, base_color: Color = Color(0.35, 0.65, 0.85), tweaks: Dictionary = {}):
	build_mount_kit(parent_node, "anti_grav_plate", Color(0.32, 0.34, 0.37).lerp(base_color, 0.12), 1.0, float(tweaks.get("field_strength", 1.0)), float(tweaks.get("kit_reach", 0.0)), Vector3(float(tweaks.get("kit_anchor_x", 0.0)), float(tweaks.get("kit_anchor_y", 0.0)), float(tweaks.get("kit_anchor_z", 0.0))))
	var plates := int(tweaks.get("plate_count", 4.0))
	var field := float(tweaks.get("field_strength", 1.0))
	var has_ring: bool = bool(tweaks.get("stabilizer_ring", true))

	# PROMINENCE. Chris: both this and the hover pad "need to be larger and
	# more prominent on the ends of their pylons". The emitter is the point of
	# the module - the pylon is just what holds it out there - so the head
	# grows and the mount does not.
	const HEAD_SCALE := 2.3
	var plate_mesh := _part("agp_plate")
	if plate_mesh:
		for i in range(plates):
			var a: float = float(i) / float(maxi(1, plates)) * TAU
			var r: float = 0.0 if plates <= 1 else 0.22 * HEAD_SCALE
			# NO EMISSION on the pad body. Chris: "that hoop in the middle
			# can stay, the rest of the pad part should be the dark metal."
			# The exotic role was already doing its job - emission is applied
			# on top of ANY material, so a blue glow across the whole plate
			# was what kept it reading as sky-blue plastic no matter what the
			# substrate said. The tint is neutral too, so the team colour
			# cannot leak back in through the role's own tint weight.
			var plate := _mesh_inst(plate_mesh, Color(0.30, 0.32, 0.35))
			plate.scale = Vector3(0.8 + 0.3 * field, 1.0, 0.8 + 0.3 * field) * HEAD_SCALE
			plate.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
			parent_node.add_child(plate)

	if has_ring:
		var ring_mesh := _part("agp_ring")
		if ring_mesh:
			var ring_pivot := Node3D.new()
			ring_pivot.name = SPIN_PIVOT_TURBINE
			ring_pivot.position = Vector3(0, -0.10 * HEAD_SCALE, 0)
			ring_pivot.rotation = Vector3(PI / 2.0, 0, 0)
			parent_node.add_child(ring_pivot)
			var ring := _mesh_inst(ring_mesh, base_color.darkened(0.45),
				Color(0.35, 0.75, 1.0), 0.45 * field)
			ring.scale = Vector3.ONE * (0.9 + 0.25 * field) * HEAD_SCALE
			ring_pivot.add_child(ring)

	# THE FIELD ITSELF, in two parts: light cast onto the ground, and the
	# ground seen through a lens. Chris asked for both - "a glow under them,
	# and an effect that it looks like its bending light under them as well" -
	# and they are genuinely different phenomena, so neither one fakes the
	# other.
	var head_r: float = 0.42 * HEAD_SCALE * (0.8 + 0.3 * field)

	# 1. The glow. A real OmniLight3D, so it lights the actual terrain under
	# the vehicle and moves with it, rather than a painted blob that would sit
	# flat on whatever it is over.
	var glow := OmniLight3D.new()
	glow.name = "GravGlow"
	glow.position = Vector3(0, -0.55 * HEAD_SCALE, 0)
	glow.light_color = Color(0.34, 0.68, 1.0)
	# 1.2, not 2.2: at the higher value the light washed the hull's whole
	# underside flat blue and the hardware stopped reading as metal at all.
	glow.light_energy = 1.2 * field
	glow.omni_range = 3.4 * HEAD_SCALE * (0.7 + 0.3 * field)
	glow.omni_attenuation = 1.6
	glow.shadow_enabled = false
	parent_node.add_child(glow)

	# 2. The lens. A disc lying flat under the plates carrying
	# gravitic_lens.gdshader, which displaces its screen sample radially - so
	# what warps is whatever is really behind it. See that shader for why it
	# is unshaded and never writes depth.
	var lens_shader: Shader = load("res://shaders/gravitic_lens.gdshader")
	if lens_shader:
		var lens := MeshInstance3D.new()
		lens.name = "GravLens"
		var quad := QuadMesh.new()
		quad.size = Vector2(head_r * 5.2, head_r * 5.2)
		lens.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = lens_shader
		mat.set_shader_parameter("strength", 0.028 + 0.022 * field)
		mat.set_shader_parameter("tint", Color(0.30, 0.62, 0.95))
		lens.material_override = mat
		# Flat, facing down at the ground it is bending.
		lens.rotation = Vector3(PI / 2.0, 0, 0)
		lens.position = Vector3(0, -0.62 * HEAD_SCALE, 0)
		# The lens must not be culled when the plates themselves are on screen
		# but its own small quad is not.
		lens.extra_cull_margin = 4.0
		parent_node.add_child(lens)


## Hydrofoil: struts down from the hull corners carrying lifting foils. The
## strut is what makes it fragile and the foil is what makes it fast, so they
## are separate parts scaled by separate tweaks.
static func _build_hydrofoil(parent_node: Node3D, base_size: Vector3, base_color: Color = Color(0.28, 0.40, 0.45), tweaks: Dictionary = {}):
	build_mount_kit(parent_node, "hydrofoil", base_color, 1.0, float(tweaks.get("strut_height", 1.0)), float(tweaks.get("kit_reach", 0.0)), Vector3(float(tweaks.get("kit_anchor_x", 0.0)), float(tweaks.get("kit_anchor_y", 0.0)), float(tweaks.get("kit_anchor_z", 0.0))))
	var span := float(tweaks.get("foil_span", 1.0))
	var strut_h := float(tweaks.get("strut_height", 1.0))
	var foils := int(tweaks.get("foil_count", 2.0))
	var length := float(tweaks.get("drum_length", base_size.z))
	var half := length * 0.5

	var strut_mesh := _part("hf_strut")
	var foil_mesh := _part("hf_foil")
	for i in range(foils):
		var t: float = 0.5 if foils <= 1 else float(i) / float(foils - 1)
		var z: float = -half * 0.8 + 1.6 * half * 0.8 * t
		if strut_mesh:
			var strut := _mesh_inst(strut_mesh, base_color)
			strut.scale = Vector3(1.0, strut_h, 1.0)
			strut.position = Vector3(0, 0, z)
			parent_node.add_child(strut)
		if foil_mesh:
			var foil := _mesh_inst(foil_mesh, base_color.darkened(0.12))
			foil.scale = Vector3(span, 1.0, 1.0)
			# Seated at the bottom of the strut, which is where strut_height
			# put it - the foil must not float when the strut lengthens.
			foil.position = Vector3(0, -0.86 * strut_h, z)
			parent_node.add_child(foil)


## Water jet: a through-hull pump feeding a steerable nozzle. The reverser
## bucket is part of the nozzle, so it appears and disappears with the toggle
## rather than being a permanently visible lump.
static func _build_water_jet(parent_node: Node3D, base_size: Vector3, base_color: Color = Color(0.30, 0.45, 0.48), tweaks: Dictionary = {}):
	build_mount_kit(parent_node, "water_jet", base_color, 1.0, float(tweaks.get("intake_size", 1.0)), float(tweaks.get("kit_reach", 0.0)), Vector3(float(tweaks.get("kit_anchor_x", 0.0)), float(tweaks.get("kit_anchor_y", 0.0)), float(tweaks.get("kit_anchor_z", 0.0))))
	var intake := float(tweaks.get("intake_size", 1.0))
	var has_reverser: bool = bool(tweaks.get("reverser", false))

	var pump_mesh := _part("wj_pump")
	if pump_mesh:
		# The impeller is inside the duct, so the pump body itself is the only
		# thing that can carry the motion cue. Turning it slowly reads as a
		# running pump rather than a dead casting - and keeps water_jet from
		# being the one naval type with nothing moving.
		var impeller := Node3D.new()
		impeller.name = SPIN_PIVOT_TURBINE
		parent_node.add_child(impeller)
		var pump := _mesh_inst(pump_mesh, base_color)
		pump.scale = Vector3.ONE * intake
		impeller.add_child(pump)

	var nozzle_mesh := _part("wj_nozzle")
	if nozzle_mesh:
		var nozzle := _mesh_inst(nozzle_mesh, base_color.lightened(0.10))
		nozzle.scale = Vector3(intake, intake, 1.0 if has_reverser else 0.72)
		nozzle.position = Vector3(0, 0, 0.24 * intake)
		parent_node.add_child(nozzle)


## Pontoon wheels: sealed buoyant drums that are simultaneously the wheel and
## the float. One part doing both jobs is the point of the type.
static func _build_pontoon_wheels(parent_node: Node3D, base_size: Vector3, base_color: Color = Color(0.36, 0.34, 0.30), tweaks: Dictionary = {}):
	var psize := float(tweaks.get("pontoon_size", 1.0))
	var vanes: bool = bool(tweaks.get("paddle_vanes", true))

	# Mounting copied wholesale from _build_wheels (Chris's instruction): the
	# same angled driveshaft and inboard gearbox, sized off pontoon_size the way
	# wheels size off wheel_size. A pontoon drum is a wheel that floats, so it
	# should hang off the hull the same way one does.
	#
	# DRUM_SCALE oversizes the drum against the mount that carries it (Chris:
	# the mounting is right, "the wheels themselves are too small"). It applies
	# to the drum only - scaling `psize` instead would grow the gearbox and
	# driveshaft in lockstep and leave the proportions exactly where they were.
	const DRUM_SCALE := 1.5
	var hub := build_wheel_mount(parent_node, base_color, psize, 0.0, 0.3 * psize)

	var pontoon_mesh := _part("pw_pontoon")
	if pontoon_mesh:
		var axle := Node3D.new()
		axle.name = SPIN_PIVOT_WHEEL
		axle.position = hub
		parent_node.add_child(axle)
		var drum := _mesh_inst(pontoon_mesh, base_color)
		# Dropping the vanes narrows the drum: a plain float rather than a
		# paddle, which is what the thrust penalty is describing.
		var d := psize * DRUM_SCALE
		drum.scale = Vector3(d * (1.0 if vanes else 0.82), d, d)
		axle.add_child(drum)


# ===========================================================================
# MOUNT KIT ASSEMBLY
#
# One function, five archetypes, every locomotion type. See
# locomotion_layout.gd's Kit enum for why this exists rather than a generic
# chassis: locomotion had no mounting CONVENTION, so each type improvised one,
# and anything generic added underneath fought them.
#
# Kit parts are authored with their ORIGIN AT THE ATTACHMENT POINT, -Z toward
# the running gear and +X outboard (tools/blender/build_mount_kits.py), so a kit
# is positioned by putting its origin on the mount station and nothing else.
# Everything below is placed in the MODULE's local space, which is exactly that
# station - so the kit needs no per-type fudge factors, which is the whole point.
# ===========================================================================

## Builds the structural mount for one locomotion instance, under a child node
## named "MountKit" so it can be found, hidden or restyled as a unit.
##
## `outboard` is +1 for the starboard side and -1 for port; the kit is authored
## once and mirrored here rather than authored twice.
static func build_mount_kit(parent_node: Node3D, type_id: String,
		base_color: Color, outboard: float = 1.0, scale_hint: float = 1.0,
		kit_reach: float = 0.0, anchor: Vector3 = Vector3.ZERO) -> Node3D:
	var spec: Dictionary = LocomotionLayoutScript.mount_kit(type_id)
	var kit: int = int(spec.get("kit", 0))
	if kit == LocomotionLayoutScript.Kit.NONE:
		return null

	var root := Node3D.new()
	root.name = "MountKit"
	parent_node.add_child(root)
	var drop: float = float(spec.get("drop", 0.0)) * scale_hint
	var stations: int = int(spec.get("stations", 1))
	var frame_col := base_color.darkened(0.30)
	var hw_col := base_color.darkened(0.10)
	var side: float = signf(outboard) if not is_zero_approx(outboard) else 1.0

	# THE SPANNING MEMBER. This is the generalisation of the one thing that
	# already worked: the OLD wheels' driveshaft was solved to bridge the actual
	# distance from the wheel back into the hull, angling inboard and up, rather
	# than being a fixed lump sitting at the mount point. Everything else
	# improvised, and a fixed kit plus a vertical riser could never close the
	# gaps, because the gap differs per type, per hull and per station.
	#
	# `anchor` is the vector from this kit's origin to its hull attachment, in
	# module space. The member is built one unit long on -Z, then scaled to the
	# vector's length and rotated onto it - so it spans exactly, at any size, for
	# any type, with no per-type numbers at all.
	if anchor.length() > 0.05:
		var span_len := anchor.length()
		var arm := Node3D.new()
		arm.name = "MountArm"
		root.add_child(arm)
		arm.look_at_from_position(Vector3.ZERO, anchor, Vector3.UP)

		# Scaled off the SPAN it carries, not off a tweak. A 1.2-unit arm holding
		# a road wheel needs real section; the first pass used a flat 0.14 and the
		# structural probe promptly flagged half the roster FRAGILE at 0.02-0.05
		# thinnest section. Floored so a short arm is still a fabrication rather
		# than a wire.
		var thickness: float = clampf(0.12 * span_len + 0.06 * scale_hint, 0.10, 0.32)
		var beam := BoxMesh.new()
		beam.size = Vector3(thickness, thickness * 1.25, 1.0)
		var beam_inst := _mesh_inst(beam, frame_col, Color(0, 0, 0, 0), 0.0, "steel")
		beam_inst.name = "MountArmBeam"
		# look_at aims -Z at the target, so the beam runs from 0 to -span_len.
		beam_inst.position = Vector3(0, 0, -span_len * 0.5)
		beam_inst.scale = Vector3(1, 1, span_len)
		arm.add_child(beam_inst)

		# A web down one side turns a bar into a fabricated arm.
		var web := BoxMesh.new()
		web.size = Vector3(thickness * 0.35, thickness * 2.1, 0.82)
		var web_inst := _mesh_inst(web, frame_col.darkened(0.08), Color(0, 0, 0, 0), 0.0, "steel")
		web_inst.name = "MountArmWeb"
		web_inst.position = Vector3(0, -thickness * 0.35, -span_len * 0.5)
		web_inst.scale = Vector3(1, 1, span_len)
		arm.add_child(web_inst)

		# Bracket where it lands on the hull, and a pivot boss at the gear end,
		# so both ends read as joined rather than butted.
		var pad := BoxMesh.new()
		pad.size = Vector3(thickness * 2.4, thickness * 0.6, thickness * 2.4)
		var pad_inst := _mesh_inst(pad, hw_col, Color(0, 0, 0, 0), 0.0, "steel")
		pad_inst.name = "MountArmPad"
		pad_inst.position = Vector3(0, 0, -span_len)
		arm.add_child(pad_inst)

		var boss := CylinderMesh.new()
		boss.top_radius = thickness * 0.85
		boss.bottom_radius = thickness * 0.85
		boss.height = thickness * 2.0
		var boss_inst := _mesh_inst(boss, hw_col, Color(0, 0, 0, 0), 0.0, "steel")
		boss_inst.name = "MountArmBoss"
		boss_inst.rotation = Vector3(0, 0, PI / 2.0)
		arm.add_child(boss_inst)

	match kit:
		LocomotionLayoutScript.Kit.SUSPENSION_ARM:
			_kit_part(root, "mk_susp_anchor", frame_col, Vector3.ZERO, Vector3.ONE * scale_hint, side)
			_kit_part(root, "mk_susp_arm", hw_col, Vector3(0, -drop * 0.35, 0),
				Vector3.ONE * scale_hint, side)
			_kit_part(root, "mk_susp_spring", base_color.lightened(0.05),
				Vector3(side * 0.20 * scale_hint, -drop * 0.30, 0), Vector3.ONE * scale_hint, side)
			# One hub per station, spread fore/aft - a rocker-bogie carries two
			# on the same arm, a road wheel one.
			for i in range(maxi(1, stations)):
				var t: float = 0.0 if stations <= 1 else (float(i) / float(stations - 1)) - 0.5
				_kit_part(root, "mk_susp_hub", hw_col,
					Vector3(side * 0.34 * scale_hint, -drop, t * 0.55 * scale_hint),
					Vector3.ONE * scale_hint, side)

		LocomotionLayoutScript.Kit.TRACK_FRAME:
			# The frame is authored one unit long on its own fore/aft axis so
			# the runtime stretches only it, never the bearings bolted to it.
			var frame := _kit_part(root, "mk_track_frame", frame_col,
				Vector3(0, -drop * 0.5, 0), Vector3(scale_hint, scale_hint, 1.0), side)
			if frame:
				frame.scale = Vector3(scale_hint, scale_hint, maxf(0.2, scale_hint))
			for i in range(maxi(1, stations)):
				var t2: float = 0.0 if stations <= 1 else (float(i) / float(stations - 1)) - 0.5
				_kit_part(root, "mk_track_bearing", hw_col,
					Vector3(0, -drop * 0.5, t2 * 0.86 * scale_hint),
					Vector3.ONE * scale_hint, side)
			for zz in [-1.0, 1.0]:
				_kit_part(root, "mk_track_finaldrive", hw_col.lightened(0.06),
					Vector3(0, -drop * 0.4, zz * 0.46 * scale_hint),
					Vector3.ONE * scale_hint, side)

		LocomotionLayoutScript.Kit.STRUT_LEG:
			_kit_part(root, "mk_strut_flange", frame_col, Vector3.ZERO,
				Vector3.ONE * scale_hint, side)
			var blade := _kit_part(root, "mk_strut_blade", hw_col,
				Vector3(0, -drop * 0.5, 0), Vector3.ONE * scale_hint, side)
			if blade:
				# Authored one unit tall, so the drop stretches the blade alone.
				blade.scale = Vector3(scale_hint, maxf(0.2, drop), scale_hint)
			_kit_part(root, "mk_strut_actuator", base_color.lightened(0.04),
				Vector3(side * 0.16 * scale_hint, -drop * 0.25, -0.12 * scale_hint),
				Vector3.ONE * scale_hint, side)

		LocomotionLayoutScript.Kit.PYLON:
			_kit_part(root, "mk_pylon_root", frame_col, Vector3.ZERO,
				Vector3.ONE * scale_hint, side)
			var strut := _kit_part(root, "mk_pylon_strut", hw_col, Vector3.ZERO,
				Vector3.ONE * scale_hint, side)
			if strut:
				strut.scale = Vector3(scale_hint, maxf(0.2, scale_hint), scale_hint)
			_kit_part(root, "mk_pylon_collar", hw_col.lightened(0.05),
				Vector3(0, -0.92 * scale_hint, 0), Vector3.ONE * scale_hint, side)

		LocomotionLayoutScript.Kit.HARDPOINT_PAD:
			_kit_part(root, "mk_pad_plate", frame_col, Vector3.ZERO,
				Vector3.ONE * scale_hint, side)
			for i in range(maxi(1, stations)):
				var a: float = float(i) / float(maxi(1, stations)) * TAU
				_kit_part(root, "mk_pad_standoff", hw_col,
					Vector3(cos(a) * 0.24 * scale_hint, -drop * 0.5, sin(a) * 0.24 * scale_hint),
					Vector3.ONE * scale_hint, side)
			_kit_part(root, "mk_pad_conduit", base_color.lightened(0.03),
				Vector3(side * 0.20 * scale_hint, -drop * 0.2, 0.16 * scale_hint),
				Vector3.ONE * scale_hint, side)

	return root


## One kit part. Returns null (quietly) when the asset is missing, so a kit is
## degraded rather than fatal if a part fails to import.
static func _kit_part(root: Node3D, part_name: String, colour: Color,
		pos: Vector3, part_scale: Vector3, side: float) -> MeshInstance3D:
	var mesh := _part(part_name)
	if mesh == null:
		return null
	var inst := _mesh_inst(mesh, colour, Color(0, 0, 0, 0), 0.0, "steel")
	inst.name = part_name
	# Mirroring on X rather than authoring a port-side variant. Negative scale
	# flips winding, so cull mode is switched to match - the same compensation
	# module_mirror.gd applies to mirrored weapon modules.
	inst.scale = Vector3(part_scale.x * side, part_scale.y, part_scale.z)
	inst.position = pos
	if side < 0.0:
		var mat := inst.material_override
		if mat is BaseMaterial3D:
			var flipped: BaseMaterial3D = mat.duplicate()
			flipped.cull_mode = BaseMaterial3D.CULL_FRONT
			inst.material_override = flipped
	root.add_child(inst)
	return inst


# ===========================================================================
# SUBFRAME - the chassis every ground and hover locomotor bolts to.
#
# Chris's design, and the answer the per-type improvising kept failing to be:
# a space-frame of tubes and beams that DYNAMICALLY grows attachment points
# wherever the fitted locomotor needs them, with the locomotors lining up on
# those points, and the whole thing slung under the hull as the running gear.
#
# This is how a real modular chassis works, and it is why it fixes the class of
# bug rather than an instance of it. Previously each type invented its own way
# of reaching the hull, so a hardpoint was wherever that type's author put it,
# and nothing could line up with anything. Now the frame publishes the
# hardpoints and the locomotor consumes them - one contract, ten types.
#
# Naval and airborne types deliberately do NOT use this: a propeller on a stern
# pylon and a rotor on a mast are not carried by a chassis under the hull, and
# forcing them onto one is what made the first generic frame collide with
# everything. They keep their own structure until they get a system of their own.
# ===========================================================================

## Builds the subframe into `body`, with a mounting pad at each hardpoint.
##
## `hardpoints` are in the running gear's own local space (X outboard, Y up,
## Z fore/aft). The frame is generated around them, so a four-wheeled chassis
## gets four bays and a five-road-wheel track gets five - the geometry follows
## the fitment rather than being a fixed prop the parts sit near.
static func build_subframe(body: StaticBody3D, dimensions: Vector3,
		base_color: Color, hardpoints: Array) -> void:
	var half := dimensions * 0.5
	var beam_col := base_color.darkened(0.34)
	var tube_col := base_color.darkened(0.20)
	var pad_col := base_color.darkened(0.06)
	# Section scales with the chassis so a big hull gets a frame that looks like
	# it could hold one, without a per-hull constant.
	var tube_r: float = clampf(dimensions.y * 0.16, 0.035, 0.085)
	var rail_x: float = half.x - tube_r * 1.6

	var tube := func(a: Vector3, b: Vector3, r: float, colour: Color, nm: String) -> void:
		var d := b - a
		if d.length() < 0.02:
			return
		var mesh := CylinderMesh.new()
		mesh.top_radius = r
		mesh.bottom_radius = r
		mesh.height = d.length()
		mesh.radial_segments = 10
		var inst := _mesh_inst(mesh, colour, Color(0, 0, 0, 0), 0.0, "steel")
		inst.name = nm
		inst.position = (a + b) * 0.5
		# CylinderMesh runs along local Y; aim that at the span.
		var up := Vector3.UP
		if absf(d.normalized().dot(up)) > 0.99:
			up = Vector3.FORWARD
		inst.basis = Basis.looking_at(d.normalized(), up) * Basis(Vector3.RIGHT, PI / 2.0)
		body.add_child(inst)

	var beam := func(centre: Vector3, size: Vector3, colour: Color, nm: String) -> void:
		var mesh := BoxMesh.new()
		mesh.size = size
		var inst := _mesh_inst(mesh, colour, Color(0, 0, 0, 0), 0.0, "steel")
		inst.name = nm
		inst.position = centre
		body.add_child(inst)

	# Longitudinal main rails - the frame's backbone, one per side.
	for side in [-1.0, 1.0]:
		beam.call(Vector3(side * rail_x, 0.0, 0.0),
			Vector3(tube_r * 2.2, dimensions.y * 0.62, dimensions.z * 0.98),
			beam_col, "SubframeRail")
		# Top and bottom chords, so the rail reads as fabricated section.
		for sy in [-1.0, 1.0]:
			beam.call(Vector3(side * rail_x, sy * dimensions.y * 0.30, 0.0),
				Vector3(tube_r * 3.0, dimensions.y * 0.13, dimensions.z * 0.98),
				tube_col, "SubframeChord")

	# Sort the hardpoints fore-to-aft so cross members and bracing run between
	# NEIGHBOURS rather than criss-crossing the frame.
	var stations: Array = []
	for hp in hardpoints:
		var v: Vector3 = hp
		if not stations.has(v.z):
			stations.append(v.z)
	stations.sort()
	if stations.is_empty():
		stations = [-half.z * 0.5, half.z * 0.5]

	var y_top: float = dimensions.y * 0.26
	var y_bot: float = -dimensions.y * 0.26

	for i in range(stations.size()):
		var z: float = stations[i]
		# Cross member at every station - this is what makes it a frame.
		tube.call(Vector3(-rail_x, y_bot, z), Vector3(rail_x, y_bot, z),
			tube_r, tube_col, "SubframeCross")
		tube.call(Vector3(-rail_x * 0.72, y_top, z), Vector3(rail_x * 0.72, y_top, z),
			tube_r * 0.82, tube_col, "SubframeCrossUpper")
		# Vertical posts tying the two chords together at the rail.
		for side in [-1.0, 1.0]:
			tube.call(Vector3(side * rail_x, y_bot, z), Vector3(side * rail_x, y_top, z),
				tube_r * 0.8, tube_col, "SubframePost")
		# Diagonal bracing into the next bay - a ladder without diagonals is a
		# ladder, not a frame, and reads as flimsy from every angle.
		if i + 1 < stations.size():
			var z2: float = stations[i + 1]
			for side in [-1.0, 1.0]:
				tube.call(Vector3(side * rail_x, y_bot, z), Vector3(side * rail_x * 0.55, y_top, z2),
					tube_r * 0.62, tube_col, "SubframeBrace")

	# Belly skids rather than one full tray. A solid plate closed the frame off
	# completely and hid the tubes and bracing behind it, which defeats the point
	# of building a space-frame - two narrow skid rails give it a floor to read
	# against while leaving the structure visible from below.
	for side in [-0.55, 0.55]:
		beam.call(Vector3(rail_x * side, -dimensions.y * 0.40, 0.0),
			Vector3(tube_r * 3.2, dimensions.y * 0.12, dimensions.z * 0.86),
			beam_col, "SubframeSkid")

	# HARDPOINTS. A machined pad and a boss at every attachment the fitted
	# locomotor asked for - this is the contract the locomotors line up on.
	for hp in hardpoints:
		var p: Vector3 = hp
		var pad_x: float = signf(p.x) * rail_x if not is_zero_approx(p.x) else 0.0
		beam.call(Vector3(pad_x, p.y, p.z),
			Vector3(tube_r * 3.4, tube_r * 2.6, tube_r * 4.2), pad_col, "SubframeHardpoint")
		var boss := CylinderMesh.new()
		boss.top_radius = tube_r * 1.15
		boss.bottom_radius = tube_r * 1.15
		boss.height = tube_r * 3.2
		boss.radial_segments = 10
		var boss_inst := _mesh_inst(boss, pad_col, Color(0, 0, 0, 0), 0.0, "steel")
		boss_inst.name = "SubframeBoss"
		boss_inst.rotation = Vector3(0, 0, PI / 2.0)
		boss_inst.position = Vector3(pad_x + signf(pad_x) * tube_r * 1.4, p.y, p.z)
		body.add_child(boss_inst)
