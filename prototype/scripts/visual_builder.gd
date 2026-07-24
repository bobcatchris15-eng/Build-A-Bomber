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

static func _part(part_name: String) -> Mesh:
	var m = MeshAssetLoader.get_part_mesh(part_name)
	if m == null:
		push_error("VisualBuilder CRITICAL ERROR: Failed to load part mesh '%s' from library!" % part_name)
		assert(m != null, "VisualBuilder CRITICAL ERROR: Failed to load part mesh '%s' from library!" % part_name)
	return m

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
static func build_running_gear(parent_node: Node3D, dimensions: Vector3, base_color: Color, collision_layer: int = 1, type_id: String = "") -> StaticBody3D:
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
	return body

static func _mesh_inst(mesh: Mesh, color: Color, emission: Color = Color(0, 0, 0, 0), emission_energy: float = 0.0) -> MeshInstance3D:
	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	inst.material_override = mat
	return inst

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
	"naval_propeller": true, "buoyant_envelope": true, "screw_drive": true
}

const MODULAR_ASSEMBLY_TYPES := {
	"basic_cannon": true, "heavy_machine_gun": true, "rotary_cannon": true, "gauss_railgun": true,
	"artillery": true, "mortar_array": true, "guided_missile": true, "missile_pod": true,
	"cluster_dispenser": true, "flamethrower": true, "tesla_coil": true, "ion_cannon": true,
	"heavy_laser": true, "plasma_lobber": true, "ciws": true, "pd_laser": true, "flak_cannon": true,
	"wheels": true, "helicopter_rotors": true, "tracked_treads": true, "legs": true,
	"hover_engine": true, "fixed_wing_engine": true, "ornithopter_wing": true,
	"naval_propeller": true, "buoyant_envelope": true, "screw_drive": true
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

			# 2A. BREECH BLOCK
			var breech: MeshInstance3D
			if breech_mesh:
				breech = _mesh_inst(breech_mesh, Color(0.20, 0.22, 0.24))
				breech.scale = Vector3(caliber, caliber, caliber)
				breech.position = Vector3(cur_x, trunnion_y, 0.0)
			else:
				breech = MeshInstance3D.new()
				var b_box = BoxMesh.new()
				b_box.size = Vector3(0.30 * caliber, 0.28 * caliber, 0.45 * caliber)
				breech.mesh = b_box
				var b_mat = StandardMaterial3D.new()
				b_mat.albedo_color = Color(0.20, 0.22, 0.24)
				breech.material_override = b_mat
				breech.position = Vector3(cur_x, trunnion_y, -0.12 * caliber)
			parent_node.add_child(breech)

			# 2B. BARREL (Mounted at front of breech socket, scaling with caliber and barrel_length)
			var barrel: MeshInstance3D
			if barrel_mesh:
				barrel = _mesh_inst(barrel_mesh, Color(0.16, 0.17, 0.19))
				barrel.scale = Vector3(caliber, caliber, length * caliber)
				barrel.position = Vector3(cur_x, trunnion_y, 0.0)
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
				barrel.position = Vector3(cur_x, trunnion_y, -(1.35 * length / 2.0))
				barrel.rotation = Vector3(PI / 2, 0, 0)
			parent_node.add_child(barrel)

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
			var tube: MeshInstance3D
			if tube_mesh:
				tube = _mesh_inst(tube_mesh, Color(0.22, 0.25, 0.20))
				tube.scale = Vector3(caliber, caliber, length * caliber)
				tube.position = Vector3(offset.x, trunnion_y, offset.z)
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
				tube.position = Vector3(offset.x, trunnion_y + (1.10 * length * 0.4), offset.z)
				tube.rotation = Vector3(PI / 3, 0, 0)
			parent_node.add_child(tube)


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


static func _build_wheels(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.BLACK, tweaks: Dictionary = {}):
	var wheel_size = float(tweaks.get("wheel_size", tweaks.get("size", 1.0)))
	var w_per_axle = int(tweaks.get("wheels_per_axle", 1.0))

	# Strict GLB part mesh loading - fails with assertion if asset is missing
	var wheel_mesh = _part("wheel_hub")
	var driveshaft_mesh = _part("wheel_driveshaft")
	var gearbox_mesh = _part("wheel_gearbox")

	var wheel_y = -0.2 * wheel_size
	var cluster_width = 0.3 * wheel_size * float(w_per_axle)

	# Lateral layout along local X. X=0 is the module's own local origin,
	# i.e. the hull mount point. Keep the WHOLE cluster close to that mount
	# point instead of pushing it past the hull's silhouette: the gearbox
	# sits INBOARD (negative X, tucked toward the hull), the wheel only a
	# small step further OUTBOARD from the mount point than before, and the
	# driveshaft spans the gap between them. This still keeps the wheel
	# clear of the gearbox/driveshaft's own local-X slab (the wheel is an
	# opaque disc of radius ~0.45*wheel_size lying in the local Y-Z plane -
	# without SOME separation the gearbox/driveshaft render entirely inside
	# it, invisible, confirmed via an isolated single-module capture) while
	# no longer leaving the wheel floating outside the vehicle's footprint.
	# hub_x_offset is negative (pulled inboard, toward the gearbox/mount
	# column) rather than outboard - Chris's ask, twice now: the wheel and
	# gearbox should visibly intersect/overlap, not just sit adjacent.
	var hub_x_offset = -0.05 * wheel_size
	var gearbox_x = -0.24 * wheel_size

	# Enclosed driveshaft housing: anchored at its BOTTOM near the gearbox/
	# wheel (a fixed connection point) with its TOP computed backward from
	# length + angle, so a longer, shallower shaft naturally reaches further
	# inboard toward the hull's longitudinal centerline before it pierces
	# the hull mesh - a short, steep shaft barely inside the mount edge
	# doesn't reliably intersect real hull geometry on hulls whose belly
	# tapers/narrows away from the outer edge, which read as a floating,
	# disconnected strut. wheel_driveshaft is authored spanning Y=0 (top/
	# pivot) to Y=-1 (bottom) - see build_meshes.py - so its bottom end
	# after scale+rotation is `position + Rz(angle)*(0,-shaft_len,0)`;
	# solving that backward from the desired bottom point gives the pivot
	# position placed here. Lightened relative to the near-black tire so it
	# actually reads as a distinct part instead of blending into the tire/
	# hull shadow.
	if driveshaft_mesh:
		var shaft = _mesh_inst(driveshaft_mesh, base_color.darkened(0.25).lightened(0.35))
		var shaft_len = 1.0 * wheel_size
		var shaft_angle = deg_to_rad(55.0)
		var bottom_target = Vector3(gearbox_x + 0.05 * wheel_size, wheel_y, 0.0)
		var drop = Vector3(sin(shaft_angle), -cos(shaft_angle), 0.0) * shaft_len
		shaft.scale = Vector3(0.32 * wheel_size, shaft_len, cluster_width)
		shaft.position = bottom_target - drop
		shaft.rotation = Vector3(0, 0, shaft_angle)
		parent_node.add_child(shaft)

	# Gearbox: large housing tucked inboard at the mount column, fed by the
	# driveshaft above it and facing the wheel cluster - the "attaches to
	# the driveshaft" piece.
	if gearbox_mesh:
		var gearbox = _mesh_inst(gearbox_mesh, base_color.darkened(0.1).lightened(0.3))
		var gb_size = 0.46 * wheel_size
		gearbox.scale = Vector3(gb_size, gb_size, cluster_width)
		gearbox.position = Vector3(gearbox_x, wheel_y, 0.0)
		parent_node.add_child(gearbox)

	var spacing = 0.38 * wheel_size
	_repeat_along_axis(parent_node, w_per_axle, spacing, Vector3.RIGHT, func(p, pos, _idx):
		var wheel = _mesh_inst(wheel_mesh, Color(0.1, 0.1, 0.12))
		wheel.scale = Vector3(wheel_size, wheel_size, wheel_size)
		wheel.position = pos + Vector3(hub_x_offset, wheel_y, 0)
		# wheel_hub.glb's hub-cap/lug-bolt detail is authored at its +Y end
		# (the "outward-facing" side of the tire, per build_wheel() in
		# build_meshes.py) - rotation.z = -PI/2 (not +PI/2) maps that +Y face
		# to +X, i.e. outboard/away from the mount column above, so the
		# visible hub face points away from the vehicle instead of backwards
		# into the gearbox.
		wheel.rotation = Vector3(0, 0, -PI / 2.0)
		p.add_child(wheel)
	)


static func _build_tracked_treads(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DARK_SLATE_GRAY, tweaks: Dictionary = {}):
	var width = tweaks.get("tread_width", tweaks.get("width", tweaks.get("size", 1.0)))
	# Fixed at 3 - Chris's ask, no longer a user tweak (was road_wheel_count,
	# 3-8 via a dedicated slider; removed along with the slider/catalog entry
	# in stat_calculator.gd/module_catalog.gd/module_placer.gd/module_data.gd).
	var road_wheels = 3
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
	var target_radius = actual_size.y * 0.42
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
	var sprocket_scale = target_radius / 0.4
	var sprocket_width_authored = 0.3
	# Center of the sprocket's own footprint (which sits entirely inboard of
	# outboard_x, its outer edge) - the loop anchors to THIS instead of
	# outboard_x directly, so it's centered over the sprocket's actual
	# footprint rather than straddling empty space past its outboard face.
	var belt_center_x = outboard_x - sprocket_width_authored * 0.5 * sprocket_scale

	var loop: MeshInstance3D
	if loop_mesh:
		loop = _mesh_inst(loop_mesh, base_color)
		# `width` (tread_width tweak) applied ONLY here, on top of the
		# sprocket-covering baseline above - this is the one place tread_width
		# is allowed to affect the tracked_treads assembly (Chris: "just the
		# tread loop should get wider, the sprockets and wheels should stay
		# as is"). The loop grows/shrinks symmetrically around belt_center_x
		# (fixed, width-independent) rather than shifting it.
		loop.scale = Vector3(sprocket_scale * width, y_scale, (target_half_span + target_radius) / (authored_half_span + authored_radius))
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
		var sp_front = _mesh_inst(sprocket_mesh, Color(0.18, 0.18, 0.2))
		sp_front.scale = Vector3(sprocket_scale, sprocket_scale, sprocket_scale)
		sp_front.position = Vector3(outboard_x, ground_offset + y_shift, -target_half_span)
		sp_front.rotation = Vector3(0, 0, PI / 2.0)
		parent_node.add_child(sp_front)

		var sp_rear = _mesh_inst(sprocket_mesh, Color(0.18, 0.18, 0.2))
		sp_rear.scale = Vector3(sprocket_scale, sprocket_scale, sprocket_scale)
		sp_rear.position = Vector3(outboard_x, ground_offset + y_shift, target_half_span)
		sp_rear.rotation = Vector3(0, 0, PI / 2.0)
		parent_node.add_child(sp_rear)

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
	var wheel_span = actual_size.z * 0.5
	var spacing = wheel_span / float(max(1, road_wheels - 1)) if road_wheels > 1 else target_radius
	var wheel_radius_target = clamp(spacing * 0.42, target_radius * 0.25, target_radius * 0.65)
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
	var gb_x_offset = -wheel_radius_target * 0.85
	var gb_size = wheel_radius_target * 1.2

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
		roller.position = Vector3(outboard_x, wheel_radius_target + y_shift, pos.z)
		roller.rotation = Vector3(0, 0, PI / 2.0)
		p.add_child(roller)

		if gearbox_mesh:
			var gearbox = _mesh_inst(gearbox_mesh, base_color.darkened(0.15).lightened(0.25))
			gearbox.scale = Vector3(gb_size, gb_size, gb_size)
			gearbox.position = Vector3(outboard_x + gb_x_offset, wheel_radius_target + y_shift, pos.z)
			p.add_child(gearbox)

		if driveshaft_mesh:
			var shaft = _mesh_inst(driveshaft_mesh, base_color.darkened(0.3).lightened(0.3))
			var shaft_len = wheel_radius_target * 2.4
			var shaft_angle = deg_to_rad(25.0)
			var bottom_target = Vector3(outboard_x + gb_x_offset * 0.4, wheel_radius_target * 0.9 + y_shift, pos.z)
			var shaft_drop = Vector3(sin(shaft_angle), -cos(shaft_angle), 0.0) * shaft_len
			shaft.scale = Vector3(gb_size * 0.55, shaft_len, gb_size * 0.55)
			shaft.position = bottom_target - shaft_drop
			shaft.rotation = Vector3(0, 0, shaft_angle)
			p.add_child(shaft)
	)


static func _build_helicopter_rotors(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DARK_GRAY, tweaks: Dictionary = {}):
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

	# hover_ring is authored with major_radius=0.5, i.e. diameter=1.0 (see
	# build_hover_ring in build_meshes.py) - ring_scale converts that to the
	# catalog's actual footprint (base_size.x), and ring_radii nests three
	# rings inside it (outer/mid/inner) at decreasing diameter.
	var authored_diameter = 1.0
	var ring_scale = base_size.x / authored_diameter
	var ring_radii = [1.0, 0.65, 0.35]
	var ring_names = ["HoverRingOuter", "HoverRingMid", "HoverRingInner"]
	var ring_y = base_size.y * 0.5

	for idx in range(3):
		var ring: MeshInstance3D
		if ring_mesh:
			ring = _mesh_inst(ring_mesh, base_color, base_color, 1.0)
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
			var strut = _mesh_inst(strut_mesh, base_color.darkened(0.3))
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
				var strut = _mesh_inst(mount_mesh, base_color.darkened(0.3))
				strut.transform = Transform3D(Basis(right * 0.6, dir * strut_len, forward * 0.2), Vector3.ZERO)
				parent_node.add_child(strut)


static func _build_legs(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.GRAY, tweaks: Dictionary = {}):
	var leg_length = tweaks.get("leg_length", tweaks.get("size", 1.0))
	var foot_size = tweaks.get("foot_size", 1.0)
	# Chris's ask: legs about 2x thicker all the way through (cross-section
	# only - length/reach are untouched), except the knee joint block,
	# which is 2.5x bigger all around instead.
	var thickness_mult = 2.0
	var knee_mult = 2.5

	var thigh_mesh = _part("leg_thigh")
	var shin_mesh = _part("leg_shin")
	var foot_mesh = _part("leg_foot")
	var joint_mesh = _part("leg_joint")
	var mount_mesh = _part("rg_mount_box")

	# Bulkier faceted hip joint at the hull interface (Chris's ask) -
	# leg_joint (build_meshes.py) replaces the old plain rg_mount_box here;
	# low segment count keeps it reading as flat riveted panels rather than
	# a smooth drum. Falls back to the old generic mount box if leg_joint
	# hasn't been reimported yet. Stays a direct child of parent_node
	# (fixed to the hull), NOT the swing pivot below - a real hip mount
	# doesn't swing with the leg.
	var hip_y = base_size.y * 0.8 * leg_length
	if joint_mesh:
		var hip = _mesh_inst(joint_mesh, base_color.darkened(0.2))
		hip.scale = Vector3(1.0, 1.0, 1.0) * (0.7 * leg_length * thickness_mult)
		hip.position = Vector3(0, hip_y, 0)
		hip.rotation = Vector3(deg_to_rad(-15.0), 0, 0)
		parent_node.add_child(hip)
	elif mount_mesh:
		var mount = _mesh_inst(mount_mesh, base_color.darkened(0.3))
		mount.scale = Vector3(0.4 * leg_length, 0.4 * leg_length, 0.4 * leg_length) * thickness_mult
		mount.position = Vector3(0, hip_y, 0)
		mount.rotation = Vector3(deg_to_rad(-15.0), 0, 0)
		parent_node.add_child(mount)

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
	# leg_stance_reach (Chris's ask, "wider stance") is carried by the
	# thigh+shin themselves (40%/60% split), each reoriented to actually
	# SPAN from its own start point out to where it needs to land - same
	# "compute a direction and length, orient a stretchable mesh along it"
	# technique the rotor/hover mounting pylons use - rather than just
	# translating the whole assembly sideways, which left a gap between
	# the fixed hip and a floating thigh instead of a real angled leg.
	# leg_root itself stays at X=0 (still rooted at the hip, flush against
	# the hull) - only the segments below splay outward from it. Authored
	# assuming the canonical +X = outboard direction (unmirrored build);
	# side<0 legs get this mirrored correctly for free via
	# module_placer.gd's existing whole-subtree mirror-flip.
	var stance_reach = tweaks.get("leg_stance_reach", 0.0)
	var leg_root = Node3D.new()
	# Named (not left auto-generated) so the animation code can reach the
	# nested "LegSwing" pivot via the fixed path "LegRoot/LegSwing".
	leg_root.name = "LegRoot"
	leg_root.position = Vector3(0, hip_y, 0)
	parent_node.add_child(leg_root)

	var swing = Node3D.new()
	swing.name = "LegSwing"
	swing.position = Vector3.ZERO
	leg_root.add_child(swing)

	# Knee height is a pure cosmetic tweak now (Chris's ask - "doesn't
	# really make a stat difference, just looking cool"), replacing the old
	# fixed-margin-above-centerline formula: knee_height is the margin
	# above the hull's own vertical centerline directly, slider-controlled
	# in stat_calculator.gd (repurposing what used to be the Leg Length
	# slider - leg_length itself is no longer user-tweakable, just a fixed
	# 1.0 internally). leg_hull_centerline_y (module_placer.gd) is the
	# reach from THIS module's own local origin up to the hull's
	# centerline; both thigh and shin below are expressed relative to the
	# swing pivot (which sits at world-ish Y=hip_y), so it needs the same
	# -hip_y conversion foot/ankle already used. Default (0.375) matches
	# the original fixed-margin look before this became tweakable.
	var hull_centerline_y = tweaks.get("leg_hull_centerline_y", hip_y)
	var knee_height = tweaks.get("knee_height", base_size.y * 0.25)
	var knee_y = (hull_centerline_y + knee_height) - hip_y

	var thigh_target = Vector3(stance_reach * 0.4, knee_y, 0)
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
	var foot_y = 0.03 - hip_y
	var shin_target = Vector3(stance_reach * 0.6, foot_y - knee_y, 0)
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
		var knee_base = 0.75 * leg_length * knee_mult
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
		ankle.scale = Vector3(1.0, 1.0, 1.0) * (0.5 * leg_length * foot_size * thickness_mult)
		ankle.position = foot.position + Vector3(0, 0.09 * leg_length, 0)
		ankle.rotation = Vector3(0, 0, shin_angle)
		swing.add_child(ankle)


static func _build_fixed_wing_engine(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.SLATE_GRAY, tweaks: Dictionary = {}):
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
		nac.rotation = Vector3(0, deg_to_rad(90.0), 0)
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
		var fan = _mesh_inst(fan_mesh, Color(0.2, 0.2, 0.22))
		fan.scale = Vector3(nacelle_size, nacelle_size, nacelle_size)
		fan.position = Vector3(0, 0, -actual_size.z * 0.48)
		parent_node.add_child(fan)

	# Turbine core: a distinct segment behind the main nacelle whose own
	# length is what turbine_compression physically stretches/compresses
	# ("a central part of the engine housing longer or shorter... out the
	# back", Chris's ask) - engine_core is authored along local Z like the
	# rest of this engine's part family (build_engine_nacelle/_fan/
	# _exhaust_cone), same rotation convention as the nacelle above.
	var core_len = actual_size.z * 0.7 * turbine_compression
	var core_rear_z = actual_size.z * 0.48
	if core_mesh:
		var core = _mesh_inst(core_mesh, base_color.darkened(0.15))
		core.scale = Vector3(nacelle_size, nacelle_size, core_len / 0.6)
		core.rotation = Vector3(0, deg_to_rad(90.0), 0)
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
	var wingspan = tweaks.get("wingspan", tweaks.get("size", 1.0))
	var rib_count = int(tweaks.get("rib_count", 3.0))

	var shoulder_mesh = _part("wing_shoulder")
	var mem_mesh = _part("wing_membrane")
	var rib_mesh = _part("wing_rib")

	if shoulder_mesh:
		var sh = _mesh_inst(shoulder_mesh, Color(0.3, 0.28, 0.25))
		sh.scale = Vector3(1.0, 1.0, 1.0)
		parent_node.add_child(sh)
	else:
		var shoulder = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(base_size.x * 0.35, base_size.y * 0.7, base_size.z * 0.35)
		shoulder.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.28, 0.25)
		shoulder.material_override = mat
		parent_node.add_child(shoulder)

	var pivot = Node3D.new()
	pivot.name = "WingPivot"
	pivot.position = Vector3(base_size.x * 0.2, base_size.y * 0.15, 0)
	parent_node.add_child(pivot)

	if mem_mesh:
		var mem = _mesh_inst(mem_mesh, base_color)
		mem.scale = Vector3(wingspan, 1.0, 1.0)
		mem.position = Vector3(base_size.x * 0.2, 0, 0)
		mem.rotation = Vector3(0, 0, deg_to_rad(12.0))
		pivot.add_child(mem)
	else:
		var mem = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(base_size.x * 0.75 * wingspan, base_size.y * 0.15, base_size.z * 0.85)
		mem.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color
		mem.material_override = mat
		mem.position = Vector3(base_size.x * 0.42 * wingspan, 0, 0)
		mem.rotation = Vector3(0, 0, deg_to_rad(12.0))
		pivot.add_child(mem)

	var spacing = base_size.z * 0.6 / float(max(1, rib_count - 1))
	_repeat_along_axis(pivot, rib_count, spacing, Vector3.FORWARD, func(p, pos, _idx):
		var rib: MeshInstance3D
		if rib_mesh:
			rib = _mesh_inst(rib_mesh, Color(0.22, 0.17, 0.12))
			rib.scale = Vector3(wingspan, 1.0, 1.0)
		else:
			rib = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(base_size.x * 0.7 * wingspan, base_size.y * 0.04, base_size.z * 0.06)
			rib.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.22, 0.17, 0.12)
			rib.material_override = mat
		rib.position = Vector3(base_size.x * 0.42 * wingspan, base_size.y * 0.08, pos.z)
		rib.rotation = Vector3(0, 0, deg_to_rad(12.0))
		p.add_child(rib)
	)


static func _build_naval_propeller(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DARK_SLATE_GRAY, tweaks: Dictionary = {}):
	var prop_size = tweaks.get("prop_size", tweaks.get("size", 1.0))
	var blade_count = int(tweaks.get("blade_count", 3.0))
	var kort = tweaks.get("kort_nozzle", false)

	var housing_mesh = _part("prop_housing")
	var blade_mesh = _part("rotor_blade")
	var kort_mesh = _part("kort_nozzle")

	var actual_size = Vector3(base_size.x * prop_size, base_size.y * prop_size, base_size.z * prop_size)
	if housing_mesh:
		var house = _mesh_inst(housing_mesh, base_color.darkened(0.2))
		house.scale = Vector3(prop_size, prop_size, prop_size)
		house.position = Vector3(0, 0, 0)
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
			blade = _mesh_inst(blade_mesh, Color.SILVER)
			blade.scale = Vector3(0.5, 1.0, actual_size.x * 0.4)
			blade.rotation = Vector3(0.3, 0, angle)
		else:
			blade = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.04, actual_size.x * 0.7, 0.12)
			blade.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.SILVER
			blade.material_override = mat
			blade.rotate_z(angle)
		p.add_child(blade)
	)

	if kort and kort_mesh:
		var nozzle = _mesh_inst(kort_mesh, Color(0.25, 0.25, 0.28))
		nozzle.scale = Vector3(prop_size, prop_size, prop_size)
		nozzle.position = Vector3(0, 0, actual_size.z * 0.35)
		parent_node.add_child(nozzle)


static func _build_buoyant_envelope(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.TAN, tweaks: Dictionary = {}):
	var motor_size = tweaks.get("motor_size", tweaks.get("size", 1.0))
	var blades = int(tweaks.get("prop_blades", 2.0))
	var tail_fins = tweaks.get("tail_fins", true)

	var strut_mesh = _part("outrigger_strut")
	var nacelle_mesh = _part("cruise_nacelle")
	var blade_mesh = _part("rotor_blade")
	var fin_mesh = _part("tail_fin")

	var actual_size = Vector3(base_size.x * motor_size, base_size.y * motor_size, base_size.z * motor_size)

	if strut_mesh:
		var strut = _mesh_inst(strut_mesh, base_color.darkened(0.3))
		strut.scale = Vector3(motor_size, 1.0, 1.0)
		strut.position = Vector3(actual_size.x * 0.25, 0, 0)
		parent_node.add_child(strut)

	if nacelle_mesh:
		var nacelle = _mesh_inst(nacelle_mesh, base_color.darkened(0.15))
		nacelle.scale = Vector3(motor_size, motor_size, motor_size)
		nacelle.position = Vector3(actual_size.x * 0.5, 0, 0)
		parent_node.add_child(nacelle)

	var pivot = Node3D.new()
	pivot.name = "PropBlades"
	pivot.position = Vector3(actual_size.x * 0.5, 0, -actual_size.z * 0.35)
	parent_node.add_child(pivot)

	_ring_of(pivot, blades, 0.0, func(p, _pos, angle, _idx):
		var blade: MeshInstance3D
		if blade_mesh:
			blade = _mesh_inst(blade_mesh, Color.SILVER)
			blade.scale = Vector3(0.4, 1.0, actual_size.y * 0.4)
			blade.rotation = Vector3(0.2, 0, angle)
		else:
			blade = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.02, actual_size.y * 0.55, 0.08)
			blade.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.SILVER
			blade.material_override = mat
			blade.rotate_z(angle)
		p.add_child(blade)
	)

	if tail_fins and fin_mesh:
		var fin = _mesh_inst(fin_mesh, Color(0.3, 0.3, 0.35))
		fin.scale = Vector3(1.0, motor_size, motor_size)
		fin.position = Vector3(actual_size.x * 0.5, actual_size.y * 0.3, actual_size.z * 0.3)
		parent_node.add_child(fin)


static func _build_screw_drive(parent_node: Node3D, base_size: Vector3, base_color: Color = Color.DARK_GOLDENROD, tweaks: Dictionary = {}):
	var drum_width = tweaks.get("drum_width", tweaks.get("size", 1.0))
	var drum_mesh = _part("screw_drum")
	var drum: MeshInstance3D
	var actual_size = Vector3(base_size.x * drum_width, base_size.y * drum_width, base_size.z * drum_width)
	if drum_mesh:
		drum = _mesh_inst(drum_mesh, base_color)
		drum.scale = _fit_scale(Vector3(actual_size.y * 0.85, actual_size.y * 0.85, actual_size.z), Vector3(0.29, 0.29, 1.6))
	else:
		drum = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = actual_size.y * 0.4
		cyl.bottom_radius = actual_size.y * 0.4
		cyl.height = actual_size.z
		drum.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = base_color
		drum.material_override = mat
		drum.rotation = Vector3(PI / 2.0, 0, 0)
	parent_node.add_child(drum)


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
		build_visual(data.type_id, module, catalog_data.get("size", Vector3.ONE), catalog_data.color, data.tweaks)

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
		"basic_cannon", "heavy_machine_gun", "rotary_cannon", "gauss_railgun", "artillery", "mortar_array", "guided_missile", "missile_pod", "cluster_dispenser", "flamethrower", "tesla_coil", "ion_cannon", "heavy_laser", "laser_cannon", "plasma_lobber", "plasma_launcher", "ciws", "pd_laser", "point_defense_laser", "flak_cannon", "flak_battery", "drone_carrier", "resource_harvester", "repair_array", "sensor_suite":
			return
