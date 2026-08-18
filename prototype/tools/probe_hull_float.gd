extends SceneTree
# Renders a single hull in isolation to inspect the "4 posts on a beam" floating
# pattern from the screenshot. Outputs a PNG; pass --hull=<id> on the command line
# (default: tallow_medium_b).
#
# Run WINDOWED. headless Godot's dummy renderer does not rasterize:
#   Godot_v4.7.1-stable_win64_console.exe --path . --script tools/probe_hull_float.gd -- --hull=tallow_medium_b

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const ModulePlacer = preload("res://scripts/module_placer.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

const OUT_DIR := "user://hull_float"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var hull_id: String = "tallow_medium_b"
	for a in args:
		if a.begins_with("--hull="):
			hull_id = a.substr("--hull=".length())
	root.size = Vector2i(1100, 700)

	var placer := Node3D.new()
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await process_frame
	await process_frame

	placer._place_hull_from_ui(hull_id)
	var hull: Node3D = placer.hull
	if hull == null:
		print("[FAIL] no hull for id=%s" % hull_id); quit(1); return
	await process_frame

	# Drop the camera and light far enough that the whole hull fits.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	light.light_energy = 1.5
	root.add_child(light)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(7.0, 4.0, -8.0)
	cam.look_at(Vector3(0, 0.4, 0), Vector3.UP)
	cam.current = true

	await process_frame
	var img: Image = root.get_texture().get_image()
	var out_path := "%s/%s.png" % [OUT_DIR, hull_id]
	img.save_png(out_path)
	print("saved ", out_path, "  hull=", hull_id)
	quit(0)
