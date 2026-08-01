extends SceneTree
# Scratch: visual check on the rebuilt base-building meshes
# (tools/blender/build_buildings.py). Must run WITHOUT --headless.
const BuildingScript = preload("res://scripts/building.gd")

func _init():
	var world = Node3D.new()
	root.add_child(world); current_scene = world
	var light = DirectionalLight3D.new(); world.add_child(light)
	light.rotation_degrees = Vector3(-48, -35, 0); light.light_energy = 1.3
	var en = WorldEnvironment.new(); var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.43, 0.47); env.ambient_light_energy = 0.9
	en.environment = env; world.add_child(en)
	var ground = MeshInstance3D.new(); var pl = BoxMesh.new()
	pl.size = Vector3(90, 0.4, 40); ground.mesh = pl
	var gm = StandardMaterial3D.new(); gm.albedo_color = Color(0.30, 0.31, 0.27)
	ground.material_override = gm; world.add_child(ground)
	ground.position = Vector3(0, -0.2, 0)

	var kinds = ["hq", "refinery", "power_plant", "light_manufactory", "medium_manufactory", "heavy_manufactory"]
	for i in range(kinds.size()):
		var b = BuildingScript.new()
		world.add_child(b)
		b.setup_prefab(kinds[i], 0, "industrialists")
		b.global_position = Vector3(-32.0 + i * 13.0, 0, 0)
	var cam = Camera3D.new(); world.add_child(cam)
	cam.position = Vector3(0, 14, 30); cam.look_at(Vector3(0, 2, 0), Vector3.UP)
	cam.fov = 62
	for i in range(45): await process_frame
	var dir = "res://progress_captures/2026-08-01-buildings"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	root.get_texture().get_image().save_png("%s/buildings.png" % dir)
	print("saved")
	quit(0)
