extends StaticBody3D
# Harvestable map resource node. resource_type: "metal" | "crystal"

var resource_type: String = "metal"
var amount: int = 1000
var start_amount: int = 1000

var mesh_inst: MeshInstance3D = null
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

func setup(res_type: String, res_amount: int):
	resource_type = res_type
	amount = res_amount
	start_amount = res_amount
	add_to_group("resource_nodes")
	collision_layer = 16
	collision_mask = 0

	mesh_inst = MeshInstance3D.new()
	var mat = StandardMaterial3D.new()
	if resource_type == "crystal":
		var prism = PrismMesh.new()
		prism.size = Vector3(1.6, 2.2, 1.6)
		mesh_inst.mesh = prism
		mat.albedo_color = Color(0.5, 0.85, 1.0, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.6, 1.0)
		mat.emission_energy_multiplier = 0.7
		mesh_inst.position = Vector3(0, 1.1, 0)
	else:
		var sphere = SphereMesh.new()
		sphere.radius = 1.2
		sphere.height = 1.6
		mesh_inst.mesh = sphere
		mat.albedo_color = Color(0.55, 0.42, 0.28)
		mat.roughness = 0.9
		mesh_inst.position = Vector3(0, 0.6, 0)
	mesh_inst.material_override = mat
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
		label.text = "%s: %d" % ["CRYSTAL" if resource_type == "crystal" else "METAL", amount]
		label.modulate = Color(0.5, 0.85, 1.0) if resource_type == "crystal" else Color(0.9, 0.75, 0.5)

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
