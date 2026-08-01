extends Node3D
# Windowed capture of the rebuilt structural pieces + material-role check, one close-up per
# weapon, so the authored sub-part detail can actually be eyeballed rather
# than inferred from vertex counts. Run with:
#   Godot_v4.3-stable_win64_console.exe res://scratch/CaptureRosterExpansion.tscn

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")

var frame_count = 0
var shots_taken = 0

# Each entry: [type_id, tweaks]. A couple are captured twice at different
# tweak settings so the per-part scaling is visible in the images too.
var subjects = [
	["spigot_mortar", {}],
	["rocket_artillery", {"tube_count": 6.0}],
	["hypervelocity_missile", {}],
	["sam_launcher", {}],
	["loitering_munition", {}],
	["anti_radiation_missile", {}],
	["bunker_buster", {}],
	["cruise_missile", {}],
]

func _ready():
	get_viewport().transparent_bg = false
	_build(0)

func _build(index: int):
	for child in get_children():
		if child.name not in ["Camera3D", "DirectionalLight3D", "FillLight", "WorldEnvironment"]:
			child.queue_free()
	await get_tree().process_frame

	var type_id = subjects[index][0]
	var tweaks = subjects[index][1]
	var data = ModuleCatalog.get_module_data(type_id)

	# A neutral deck plate so each weapon reads as mounted on something,
	# the way it will actually be seen.
	var bounds_hint = ModuleCatalog.get_module_data(type_id).get("size", Vector3.ONE).length()
	var deck = MeshInstance3D.new()
	var plate = BoxMesh.new()
	plate.size = Vector3(max(1.2, bounds_hint), 0.08, max(1.2, bounds_hint))
	deck.mesh = plate
	var dm = StandardMaterial3D.new()
	dm.albedo_color = Color(0.30, 0.31, 0.33)
	deck.material_override = dm
	deck.position = Vector3(0, -0.06, 0)
	add_child(deck)

	var holder = Node3D.new()
	holder.name = "Subject"
	add_child(holder)
	VisualBuilder.build_visual(type_id, holder, data.size, data.color, tweaks)

	# Frame the assembly on its real bounds so every weapon fills the shot
	# regardless of how big it actually is.
	var bounds := AABB()
	var first := true
	var stack: Array = [holder]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is MeshInstance3D and c.mesh:
				var a = c.mesh.get_aabb()
				a.position *= c.scale
				a.size *= c.scale
				a.position += c.position
				if first:
					bounds = a
					first = false
				else:
					bounds = bounds.merge(a)
	var centre = bounds.position + bounds.size * 0.5
	var reach = max(bounds.size.x, max(bounds.size.y, bounds.size.z)) * 0.80 + 0.25

	var cam = get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.global_position = centre + Vector3(reach * 0.85, reach * 0.60, reach * 1.0)
		cam.look_at(centre, Vector3.UP)

	print("[CAPTURE] %d: %s %s  bounds=%.2f x %.2f x %.2f" % [
		index, type_id, tweaks, bounds.size.x, bounds.size.y, bounds.size.z])

func _process(_delta):
	frame_count += 1
	if frame_count % 10 == 0 and shots_taken < subjects.size():
		var img = get_viewport().get_texture().get_image()
		var label = subjects[shots_taken][0]
		if not subjects[shots_taken][1].is_empty():
			label += "_tweaked"
		img.save_png("res://scratch/nw_%02d_%s.png" % [shots_taken, label])
		shots_taken += 1
		if shots_taken < subjects.size():
			_build(shots_taken)
		else:
			print("[CAPTURE] done")
			get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
