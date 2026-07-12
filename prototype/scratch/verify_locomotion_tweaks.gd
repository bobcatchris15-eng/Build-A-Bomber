extends Node3D
# Windowed visual verification for the Sunday locomotion-tweak-parity fix:
# legs/anti_grav/hover_engine now actually respond to their size slider.
# Builds a medium_hull with each locomotion type at size=1.0, then size=2.0,
# screenshotting both so the visual difference is checkable by eye.
# Run with: ./Godot_v4.3-stable_win64_console.exe res://scratch/VerifyLocomotionTweaks.tscn

const ModulePlacerScript = preload("res://scripts/module_placer.gd")

var frame_count = 0
var shots_taken = 0
var cases = [
	["legs", {"size": 1.0, "count": 4}],
	["legs", {"size": 2.0, "count": 4}],
	["anti_grav", {"size": 1.0}],
	["anti_grav", {"size": 2.0}],
	["hover_engine", {"size": 1.0}],
	["hover_engine", {"size": 2.0}],
]

var hull: StaticBody3D
var placer: Node3D

func _ready():
	get_viewport().transparent_bg = false
	_build_case(0)

func _build_case(index: int):
	for child in get_children():
		if child.name != "Camera3D" and child.name != "DirectionalLight3D" and child.name != "WorldEnvironment":
			child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	hull = StaticBody3D.new()
	hull.name = "Hull"
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(4.0, 1.0, 6.0)
	mesh_inst.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.GRAY
	mesh_inst.material_override = mat
	mesh_inst.name = "MeshInstance3D"
	hull.add_child(mesh_inst)
	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = Vector3(4.0, 1.0, 6.0)
	col.shape = col_box
	col.name = "CollisionShape3D"
	hull.add_child(col)
	hull.position = Vector3(0, 0.5, 0)
	add_child(hull)

	placer = Node3D.new()
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	add_child(placer)
	await get_tree().process_frame

	var type_id = cases[index][0]
	var settings = cases[index][1]
	placer.update_locomotion(type_id, settings)
	await get_tree().process_frame

	var cam = get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.global_position = Vector3(7, 5, 9)
		cam.look_at(Vector3(0, 0, 0), Vector3.UP)

	print("[VERIFY-LOCO] Built case %d: %s %s" % [index, type_id, settings])

func _process(delta):
	frame_count += 1
	if frame_count % 15 == 0 and shots_taken < cases.size():
		var img = get_viewport().get_texture().get_image()
		var path = "res://scratch/loco_shot_%d.png" % shots_taken
		img.save_png(path)
		print("[VERIFY-LOCO] Saved: ", path)
		shots_taken += 1
		if shots_taken < cases.size():
			_build_case(shots_taken)
		else:
			print("[VERIFY-LOCO] All screenshots captured.")
			get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
