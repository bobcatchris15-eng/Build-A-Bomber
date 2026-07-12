extends StaticBody3D
# Harvestable map resource node. resource_type: "metal" | "crystal"

var resource_type: String = "metal"
var amount: int = 1000
var start_amount: int = 1000

var mesh_inst: MeshInstance3D = null
var label: Label3D = null

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
	label.text = "%s: %d" % ["CRYSTAL" if resource_type == "crystal" else "METAL", amount]
	label.modulate = Color(0.5, 0.85, 1.0) if resource_type == "crystal" else Color(0.9, 0.75, 0.5)

func harvest(want: int) -> int:
	var got = min(want, amount)
	amount -= got
	_update_label()
	# Shrink visually as it depletes
	if is_instance_valid(mesh_inst) and start_amount > 0:
		var pct = clamp(float(amount) / float(start_amount), 0.15, 1.0)
		mesh_inst.scale = Vector3(pct, pct, pct)
	if amount <= 0:
		remove_from_group("resource_nodes")
		if is_instance_valid(label):
			label.text = "DEPLETED"
			label.modulate = Color(0.5, 0.5, 0.5)
	return got
