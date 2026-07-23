extends SceneTree
# Isolated view of the raw tread_belt_loop.glb part (just the swept loop
# mesh itself, no wheels/sprockets/mount) to verify the geometry is actually
# a correct closed stadium loop before wiring it into _build_tracked_treads().
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_tread_loop_part.gd --path .

func _init():
	var out_dir = "res://progress_captures/2026-07-23/tracked_treads"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var world = Node3D.new()
	root.add_child(world)
	root.size = Vector2i(1100, 800)

	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.55, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.65, 0.7)
	env.ambient_light_energy = 1.3
	env_node.environment = env
	world.add_child(env_node)
	var sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(30.0), 0)
	sun.light_energy = 1.4
	world.add_child(sun)
	var fill = DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(-130.0), 0)
	fill.light_energy = 0.7
	world.add_child(fill)

	var MeshAssetLoader = load("res://scripts/mesh_asset_loader.gd")
	var mesh = MeshAssetLoader.get_part_mesh("tread_belt_loop")
	if not mesh:
		print("[FAIL] tread_belt_loop part failed to load")
		quit(1)
		return

	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.15, 0.15)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	inst.material_override = mat
	world.add_child(inst)
	for i in range(4): await process_frame

	var aabb = mesh.get_aabb()
	print("[INFO] tread_belt_loop AABB: pos=", aabb.position, " size=", aabb.size)

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.position = Vector3(0.0, 1.2, 3.5)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/tread_loop_part_side.png" % out_dir)
	print("[CAPTURE] tread_loop_part_side saved")

	cam.position = Vector3(2.0, 1.0, 2.0)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/tread_loop_part_34.png" % out_dir)
	print("[CAPTURE] tread_loop_part_34 saved")

	cam.position = Vector3(3.0, 0.0, 0.0)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	for i in range(4): await process_frame
	root.get_texture().get_image().save_png("%s/tread_loop_part_end.png" % out_dir)
	print("[CAPTURE] tread_loop_part_end saved")

	quit(0)
