extends StaticBody3D
# One harvestable collectible: a rock, a crystal cluster, a tree, a well.
#
# WHAT CHANGED, 2026-08-07. These used to BE the deposit - one node at one
# coordinate holding the whole 1,100 units of ore, which made a "field" a single
# point four trucks queued at and shoved over. They are now the scattered
# children of resource_field.gd, which spawns them around a centre and replaces
# them as they are worked out.
#
# resource_type is a ResourceCatalog id: "ore" (alias "metal"), "crystal",
# "lumber" or "oil". Appearance and colour come from the catalog rather than from
# an if/else chain here, so adding a fifth resource does not mean editing this
# file.

const ResourceCatalogScript = preload("res://scripts/battle/economy/resource_catalog.gd")

var resource_type: String = "metal"
var amount: int = 1000
var start_amount: int = 1000

# Node3D, not MeshInstance3D: an authored pool asset (see AUTHORED_POOL_SIZE
# below) is instantiated whole, and its root may carry its own child
# MeshInstance3D(s) with two real material slots (e.g. a tree's trunk vs.
# canopy) rather than being a single flat mesh. Only .position/.scale are
# ever read on this from outside setup() (the depletion shrink at
# update_amount() below), which both surfaces (procedural and authored)
# equally support as Node3D members.
var mesh_inst: Node3D = null
var label: Label3D = null

# Crib from C&C/Tiberium fields (Chris's own call, 2026-07-27): a node left
# alone for a while gradually regrows, whether it's merely been picked at
# or fully depleted - a contested field rewards holding it even after the
# obvious harvest, and a fully-mined field isn't gone forever. Adapted from
# OpenRA's own SeedsResource (a per-cell regrowth tick with a density cap)
# to this game's discrete nodes rather than a cell/density grid - see
# RTS_CORE_ROADMAP.md's own "explicitly out of scope... but worth having
# eventually" note for this exact feature. Deliberately self-contained in
# this script (own _physics_process, no external ticking from skirmish.gd
# needed) rather than a second timer skirmish.gd has to remember to drive.
const REGROW_DELAY: float = 15.0 # seconds since the last successful harvest before regrowth starts
const REGROW_RATE_FRACTION: float = 0.01 # fraction of start_amount regenerated per second, once active
var _time_since_harvest: float = REGROW_DELAY # a freshly-spawned full node has nothing to regrow anyway
var _regrow_accum: float = 0.0

# Authored pool (tools/blender/build_terrain_props.py), one family per
# resource type, N variants each so a field reads as real variety rather
# than one asset stamped at every node. Picked deterministically from this
# node's own spawn position, same convention _spawn_rock_obstacle() in
# terrain_builder.gd already uses for boulders.
#
# PER-FAMILY, not one global count. build_meshes.generate_terrain_props()
# exports three ore, three crystal and three lumber variants but only TWO oil
# derricks, so a flat pool size of 3 rolled index 2 for roughly a third of all
# oil wells, failed to load resource_oil_2.glb, and quietly fell through to the
# procedural derrick box - with a resource-load error on the way past. It never
# looked broken because the fallback is a plausible-looking derrick, which is
# exactly what made it worth pinning here.
#
# A family absent from this dict falls back to 1, so adding a new resource type
# without an entry renders its variant 0 everywhere rather than erroring - the
# same "degrade to something" contract as the procedural fallback itself.
const AUTHORED_POOL_SIZES := {
	"ore": 3,
	"crystal": 3,
	"lumber": 3,
	"oil": 2,
}
const AUTHORED_MODEL_DIR := "res://assets/models/terrain/resource_%s_%d.glb"
# The lookup uses the CANONICAL type, which is why the asset family is named
# resource_ore_N.glb and not resource_metal_N.glb: ResourceCatalog.ALIASES is
# {"metal": "ore"}, so canonical("metal") returns "ore", not the reverse. No
# separate alias table is needed here - but the naming only works in that one
# direction, so an asset family added under a non-canonical id would silently
# never load and every node of that type would sit on the procedural fallback
# with nothing logged.

func _try_spawn_authored(res_type: String) -> Node3D:
	if not ResourceLoader.exists(AUTHORED_MODEL_DIR % [res_type, 0]):
		return null
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var pool: int = maxi(1, int(AUTHORED_POOL_SIZES.get(res_type, 1)))
	var idx: int = rng.randi() % pool
	var packed := load(AUTHORED_MODEL_DIR % [res_type, idx]) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


func setup(res_type: String, res_amount: int):
	resource_type = ResourceCatalogScript.canonical(res_type)
	amount = res_amount
	start_amount = res_amount
	add_to_group("resource_nodes")
	collision_layer = 16
	collision_mask = 0

	# Authored art first, procedural primitive second - same "degrade to the
	# placeholder rather than to nothing" contract as building_mesh.gd's own
	# build(). The authored asset keeps its own baked-in glTF materials (a
	# tree's trunk vs. canopy, an outcrop's rock vs. ore vein), so it is
	# NEVER given a flat material_override the way the procedural fallback
	# below is.
	mesh_inst = _try_spawn_authored(resource_type)
	if mesh_inst == null:
		var fallback := MeshInstance3D.new()
		var mat = StandardMaterial3D.new()
		mat.albedo_color = ResourceCatalogScript.color(resource_type)
		match resource_type:
			"crystal":
				var prism = PrismMesh.new()
				prism.size = Vector3(1.6, 2.2, 1.6)
				fallback.mesh = prism
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.85
				mat.emission_enabled = true
				mat.emission = Color(0.3, 0.6, 1.0)
				mat.emission_energy_multiplier = 0.7
				fallback.position = Vector3(0, 1.1, 0)
			"lumber":
				# A seedling cone, per Chris: a forest stand is "really just a group
				# of tree seedlings" - the field spawns nine of these, so one of them
				# is a tree, not a wood.
				var tree = CylinderMesh.new()
				tree.top_radius = 0.0
				tree.bottom_radius = 1.0
				tree.height = 3.0
				fallback.mesh = tree
				mat.roughness = 1.0
				fallback.position = Vector3(0, 1.5, 0)
			"oil":
				# A squat derrick block. Deliberately dark and low - a well reads as
				# infrastructure sitting on the ground, not as a mineral growing out
				# of it, which is what says "neutral, and worth taking".
				var derrick = BoxMesh.new()
				derrick.size = Vector3(1.8, 2.6, 1.8)
				fallback.mesh = derrick
				mat.metallic = 0.6
				mat.roughness = 0.4
				fallback.position = Vector3(0, 1.3, 0)
			_:
				var sphere = SphereMesh.new()
				sphere.radius = 1.2
				sphere.height = 1.6
				fallback.mesh = sphere
				mat.roughness = 0.9
				fallback.position = Vector3(0, 0.6, 0)
		fallback.material_override = mat
		mesh_inst = fallback
	add_child(mesh_inst)

	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(2.4, 2.4, 2.4)
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	add_child(col)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 20
	label.outline_size = 4
	label.position = Vector3(0, 3.0, 0)
	add_child(label)
	_update_label()

func _update_label():
	if not is_instance_valid(label): return
	if amount <= 0:
		label.text = "DEPLETED"
		label.modulate = Color(0.5, 0.5, 0.5)
	else:
		label.text = "%s: %d" % [ResourceCatalogScript.label(resource_type), amount]
		label.modulate = ResourceCatalogScript.color(resource_type)

func _update_visual_scale():
	if is_instance_valid(mesh_inst) and start_amount > 0:
		var pct = clamp(float(amount) / float(start_amount), 0.15, 1.0) if amount > 0 else 0.15
		mesh_inst.scale = Vector3(pct, pct, pct)

func harvest(want: int) -> int:
	var got = min(want, amount)
	amount -= got
	if got > 0:
		_time_since_harvest = 0.0
	_update_label()
	_update_visual_scale() # Shrink visually as it depletes
	if amount <= 0:
		remove_from_group("resource_nodes")
	return got

func _physics_process(delta: float) -> void:
	if amount >= start_amount:
		return
	_time_since_harvest += delta
	if _time_since_harvest < REGROW_DELAY:
		return
	_regrow_accum += start_amount * REGROW_RATE_FRACTION * delta
	if _regrow_accum < 1.0:
		return
	var whole = int(_regrow_accum)
	_regrow_accum -= whole
	var was_depleted = amount <= 0
	amount = min(start_amount, amount + whole)
	if was_depleted and amount > 0 and not is_in_group("resource_nodes"):
		add_to_group("resource_nodes")
	_update_label()
	_update_visual_scale()
