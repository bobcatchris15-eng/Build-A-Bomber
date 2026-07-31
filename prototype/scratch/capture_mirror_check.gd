extends SceneTree
# Scratch: render a real saved design that uses tracked locomotion, so the
# "left-hand locomotion renders inverted" report can be checked against a
# picture instead of against reasoning about cull modes.
#
# Reconstructs through blueprint_manager.reconstruct_vehicle(), which is the
# path that applies the mirror, and shoots it from a three-quarter angle
# where both sides are visible at once - the whole point is comparing the
# mirrored side against the unmirrored one in a single frame.
#
# Run WITHOUT --headless: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_mirror_check.gd

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const OUT_DIR = "res://progress_captures/2026-07-30/mirror_check"

# Designs known to carry tracked/wheeled locomotion.
const WANTED = ["TrackedHeavyTank", "TrackedLightTank", "FlakTrak"]

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1200, 800))
	await process_frame

	var mgr = Node.new()
	mgr.set_script(BlueprintManagerScript)
	root.add_child(mgr)

	var entries: Array = mgr.list_blueprints(false)
	for entry in entries:
		if str(entry.get("name", "")) not in WANTED:
			continue
		await _shoot(mgr, entry)
	print("done -> ", OUT_DIR)
	quit(0)

func _shoot(mgr: Node, entry: Dictionary) -> void:
	var data: Dictionary = mgr.load_blueprint(str(entry["path"]))
	if data.is_empty():
		print("  skip (unreadable): ", entry.get("name", ""))
		return

	var world = Node3D.new()
	root.add_child(world)
	current_scene = world

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -38, 0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	world.add_child(light)

	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Flat mid grey: a gradient sky makes it hard to tell "I can see through
	# this surface" from "this surface is lit differently".
	env.background_color = Color(0.42, 0.44, 0.46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_energy = 0.85
	env_node.environment = env
	world.add_child(env_node)

	# is_designer = true: matches the Design Lab, where the report came from.
	var hull = mgr.reconstruct_vehicle(data, world, true)
	if not hull:
		print("  skip (reconstruct failed): ", entry.get("name", ""))
		world.queue_free()
		await process_frame
		return

	var cam = Camera3D.new()
	world.add_child(cam)
	# Low three-quarter front so both flanks and the underside chassis are in
	# frame - inverted geometry reads most obviously along the tread run.
	cam.look_at_from_position(Vector3(7.5, 3.4, 8.5), Vector3(0, 0.4, 0), Vector3.UP)
	cam.fov = 45

	for i in range(8):
		await process_frame
	var img = root.get_texture().get_image()
	var fname = "%s.png" % str(entry["name"]).to_lower()
	img.save_png("%s/%s" % [OUT_DIR, fname])
	print("  wrote ", fname)

	world.queue_free()
	await process_frame
