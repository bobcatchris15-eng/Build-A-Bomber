extends Node3D
# Windowed visual verification harness: places a hull with a spread of
# weapon/locomotion modules, frames it with a camera, waits a couple of
# rendered frames, then saves a screenshot and quits. Run with:
#   Godot_v4.3-stable_win64_console.exe res://scratch/VisualVerify.tscn

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

var frame_count = 0
var shots_taken = 0

# Each entry: [hull_type_id, list of (type_id, local_offset)]
var scenes = [
	["medium_hull", [
		["basic_cannon", Vector3(0, 0.5, -0.5)],
		["heavy_machine_gun", Vector3(1.2, 0.5, 1.0)],
		["rotary_cannon", Vector3(-1.2, 0.5, 1.0)],
		["gauss_railgun", Vector3(0, 0.5, 2.0)],
		["sensor_suite", Vector3(1.5, 0.5, -1.5)],
		["missile_pod", Vector3(-1.5, 0.5, -1.5)],
	]],
	["heavy_hull", [
		["heavy_howitzer", Vector3(0, 0.75, -1.0)],
		["ciws", Vector3(2.0, 0.75, 2.0)],
		["flak_cannon", Vector3(-2.0, 0.75, 2.0)],
	]],
	["pillbox_foundation", [
		["rotary_cannon", Vector3(0.75, 0.6, 0.0)],
		["rotary_cannon", Vector3(-0.75, 0.6, 0.0)],
	]],
	["tower_foundation", []],
	["interceptor_hull", [
		["heavy_laser", Vector3(0, 0.4, -0.5)],
	]],
]

func _ready():
	get_viewport().transparent_bg = false
	_build_scene(0)

func _build_scene(index: int):
	for child in get_children():
		if child.name != "Camera3D" and child.name != "DirectionalLight3D" and child.name != "WorldEnvironment":
			child.queue_free()
	await get_tree().process_frame

	var hull_type = scenes[index][0]
	var modules = scenes[index][1]
	var catalog_data = ModuleCatalog.get_module_data(hull_type)

	var hull = Node3D.new()
	hull.name = "Hull"
	add_child(hull)

	var mesh_inst = MeshInstance3D.new()
	var authored = MeshAssetLoader.get_hull_mesh(hull_type)
	if authored:
		mesh_inst.mesh = authored
	else:
		var box = BoxMesh.new()
		box.size = catalog_data.size
		mesh_inst.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = catalog_data.color
	mesh_inst.material_override = mat
	hull.add_child(mesh_inst)
	hull.position = Vector3(0, catalog_data.size.y / 2.0, 0)

	for m in modules:
		var type_id = m[0]
		var offset = m[1]
		var mod_catalog = ModuleCatalog.get_module_data(type_id)
		var mod_node = Node3D.new()
		VisualBuilder.build_visual(type_id, mod_node, mod_catalog.size, mod_catalog.color)
		hull.add_child(mod_node)
		mod_node.position = offset

	var cam = get_node_or_null("Camera3D") as Camera3D
	if cam:
		var reach = max(catalog_data.size.x, catalog_data.size.z, catalog_data.size.y) * 0.85 + 1.0
		cam.global_position = Vector3(reach * 0.85, reach * 0.65, reach)
		cam.look_at(Vector3(0, catalog_data.size.y * 0.4, 0), Vector3.UP)

	print("[VISUAL-VERIFY] Built scene %d: %s" % [index, hull_type])

func _process(delta):
	frame_count += 1
	if frame_count % 12 == 0 and shots_taken < scenes.size():
		var img = get_viewport().get_texture().get_image()
		var path = "res://scratch/verify_shot_%d.png" % shots_taken
		img.save_png(path)
		print("[VISUAL-VERIFY] Saved: ", path)
		shots_taken += 1
		if shots_taken < scenes.size():
			_build_scene(shots_taken)
		else:
			print("[VISUAL-VERIFY] All screenshots captured.")
			get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
