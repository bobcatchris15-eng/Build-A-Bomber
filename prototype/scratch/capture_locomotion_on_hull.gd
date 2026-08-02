extends Node3D
# Chris's ask: load a blank hull, attach each locomotion type to it, and capture
# the WHOLE VEHICLE from a middle distance on each axis.
#
# This is a different question from the per-part captures. Those framed each
# assembly on its own bounds, which flatters everything: a part that is the
# wrong SIZE for a hull, or that leaves a structurally nonsensical gap between
# itself and the chassis, looks perfectly fine when it fills the frame alone.
# Mounted on a real hull at a fixed distance, scale errors and floating running
# gear are immediately obvious - which is the point.
#
# Run with:
#   Godot_v4.3-stable_win64.exe res://scratch/CaptureLocoOnHull.tscn

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

var frame_count := 0
var shot := 0

# Every locomotion type in the catalog, so nothing is reviewed by proxy.
var subjects: Array = []
# side / front / top-three-quarter. Named so the filenames sort into a
# comparable contact sheet per type.
# Chris's ask: directly behind, directly below, and a dead side profile. All
# three are ORTHOGONAL rather than three-quarter, because the questions being
# asked are alignment questions - is the gear square to the hull, does it sit at
# the right height, is it the right length - and a three-quarter view hides
# exactly those. The from-below view is the one that catches running gear
# floating off its mount, which no other angle shows.
# Third element is the camera UP vector. The from-below shot needs its own:
# look_at() degenerates when the view direction is parallel to the up vector, so
# a straight-down-the-Y-axis camera with Vector3.UP produced a tilted near-side
# view instead of a plan view of the underside.
const VIEWS := [
	["rear", Vector3(0.0, 0.0, 1.0), Vector3.UP],
	["below", Vector3(0.0, -1.0, 0.0), Vector3.FORWARD],
	["side", Vector3(1.0, 0.0, 0.0), Vector3.UP],
]

var placer: Node3D
var hull: StaticBody3D


func _ready() -> void:
	for type_id in ModuleCatalog.get_catalog():
		if ModuleCatalog.get_catalog()[type_id].get("category", "") == "locomotion":
			subjects.append(type_id)
	subjects.sort()
	var only := OS.get_environment("LOCO_ONLY")
	if only != "":
		subjects = subjects.filter(func(t): return t in only.split(","))
	print("[CAPTURE] %d locomotion types" % subjects.size())
	_build(0)


var HULL_ID := OS.get_environment("LOCO_HULL") if OS.get_environment("LOCO_HULL") != "" else "medium_hull"


func _build(index: int) -> void:
	if placer and is_instance_valid(placer):
		placer.queue_free()
	if hull and is_instance_valid(hull):
		hull.queue_free()
	await get_tree().process_frame

	# The REAL medium_hull mesh, not a stand-in box (Chris's ask). A box flatters
	# the running gear: its sides are vertical and its belly is flat, so
	# anything mounted to it lines up by accident. The authored hull has a
	# tapered nose and a belly that is not where the collision box says it is,
	# which is precisely where mounting goes wrong.
	hull = StaticBody3D.new()
	hull.name = "Hull"
	hull.set_meta("type_id", HULL_ID)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var authored: Mesh = MeshAssetLoader.get_hull_mesh(HULL_ID)
	if authored != null:
		mesh_inst.mesh = authored
		var fit: Dictionary = ModuleCatalog.get_hull_mesh_fit(HULL_ID, authored, Vector3.ONE)
		mesh_inst.rotation = fit["rotation"]
		mesh_inst.scale = fit["scale"]
		mesh_inst.position = fit["position"]
	else:
		var box := BoxMesh.new()
		box.size = ModuleCatalog.REFERENCE_HULL_SIZE
		mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.46)
	mat.roughness = 0.75
	mesh_inst.material_override = mat
	hull.add_child(mesh_inst)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var col := BoxShape3D.new()
	# The hull's OWN catalog size, not the reference box - hardcoding the
	# reference meant LOCO_HULL changed the mesh but not the size every
	# locomotion station is derived from, so every hull captured identically.
	var cat: Dictionary = ModuleCatalog.get_catalog().get(HULL_ID, {})
	col.size = cat.get("size", ModuleCatalog.REFERENCE_HULL_SIZE)
	shape.shape = col
	hull.add_child(shape)
	add_child(hull)

	placer = Node3D.new()
	placer.set_script(load("res://scripts/module_placer.gd"))
	placer.hull = hull
	add_child(placer)
	await get_tree().process_frame

	placer.update_locomotion(subjects[index], {})
	await get_tree().process_frame

	var b := _vehicle_bounds()
	print("[CAPTURE] %s  hull_y=%.2f  bounds=%.2f x %.2f x %.2f  low_y=%.2f" % [
		subjects[index], hull.position.y, b.size.x, b.size.y, b.size.z, b.position.y])


func _vehicle_bounds() -> AABB:
	var bounds := AABB()
	var seen := false
	for m in hull.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var a: AABB = m.mesh.get_aabb()
		var xf: Transform3D = m.global_transform
		var part: AABB = xf * a
		bounds = part if not seen else bounds.merge(part)
		seen = true
	return bounds


func _process(_delta: float) -> void:
	frame_count += 1
	if frame_count % 8 != 0:
		return
	var total := subjects.size() * VIEWS.size()
	if shot >= total:
		return
	var type_index := shot / VIEWS.size()
	var view_index := shot % VIEWS.size()

	# Frame on the WHOLE vehicle, from a fixed multiple of its own size, so
	# every type is judged at a comparable apparent scale.
	var b := _vehicle_bounds()
	var centre := b.position + b.size * 0.5
	var reach: float = maxf(b.size.x, maxf(b.size.y, b.size.z)) * 1.15 + 1.2
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam:
		var dir: Vector3 = (VIEWS[view_index][1] as Vector3).normalized()
		cam.global_position = centre + dir * reach
		cam.look_at(centre, VIEWS[view_index][2] as Vector3)

	var img := get_viewport().get_texture().get_image()
	img.save_png("res://scratch/hull_%s_%s.png" % [
		subjects[type_index], VIEWS[view_index][0]])
	shot += 1

	if shot >= total:
		print("[CAPTURE] done")
		get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
	elif shot % VIEWS.size() == 0:
		_build(shot / VIEWS.size())
