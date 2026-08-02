extends Node3D
# Windowed capture of the four hull armor materials with their greeble fields.
const AG = preload("res://scripts/armor_greebles.gd")
const HMB = preload("res://scripts/hull_material_builder.gd")
var mats = ["hardened_steel","reactive_armor","ablative_ceramic","energy_shielding"]
var frame_count = 0
var shots = 0

func _ready():
	_build(0)

func _build(i: int):
	for c in get_children():
		if c.name not in ["Camera3D","DirectionalLight3D","FillLight","WorldEnvironment"]:
			c.queue_free()
	await get_tree().process_frame
	var hull = Node3D.new()
	hull.name = "Hull"
	add_child(hull)
	var size = Vector3(4.0, 1.4, 6.0)
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new(); bm.size = size
	mi.mesh = bm
	hull.add_child(mi)

	# A stand-in for a PLACED MODULE: a child of the hull carrying the
	# module_data meta, sitting proud of the roof. Greebles and decals must
	# treat it as a thing bolted TO the hull, not as hull surface - so nothing
	# should be scattered onto its faces and no decal should land on it.
	var turret = MeshInstance3D.new()
	turret.name = "MockTurret"
	var tb = BoxMesh.new(); tb.size = Vector3(1.2, 0.9, 1.6)
	turret.mesh = tb
	turret.position = Vector3(0, size.y * 0.5 + 0.45, -0.6)
	turret.set_meta("module_data", {})
	hull.add_child(turret)

	HMB.apply_hull_materials(mi, mats[i], "industrialists")
	AG.apply(hull, mats[i], size)
	var cam = get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.global_position = Vector3(5.0, 4.2, 6.5)
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	print("[CAPTURE] %d: %s" % [i, mats[i]])

func _process(_d):
	frame_count += 1
	if frame_count % 14 == 0 and shots < mats.size():
		get_viewport().get_texture().get_image().save_png("res://scratch/armor_%d_%s.png" % [shots, mats[shots]])
		shots += 1
		if shots < mats.size(): _build(shots)
		else:
			print("[CAPTURE] done")
			get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
