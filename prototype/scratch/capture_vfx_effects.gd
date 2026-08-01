extends SceneTree
# Scratch: visual proof for scripts/vfx_effects.gd - the GPU-particle flame,
# the flame's smoke, a one-shot smoke puff, and a Decal-projected ground
# scorch, all rendered against a sloped surface so the decal's terrain
# conforming is actually visible (a flat floor would prove nothing - a plain
# quad looks identical there, which is the whole reason the old approach's
# problem was invisible until maps had real elevation).
#
# Must run WITHOUT --headless (dummy renderer doesn't rasterize).
# Run: ./godot.exe --script scratch/capture_vfx_effects.gd --path .

const VFXEffects = preload("res://scripts/vfx_effects.gd")

func _init():
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world

	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.1

	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.30, 0.33)
	env.ambient_light_energy = 0.8
	env_node.environment = env
	world.add_child(env_node)

	# Ground: a wide flat slab plus a ramp, so the scorch decal has both a
	# flat and a sloped surface to project onto.
	_slab(world, Vector3(0, 0, 0), Vector3(40, 0.5, 40), Vector3.ZERO, Color(0.30, 0.31, 0.26))
	_slab(world, Vector3(7, 1.4, 0), Vector3(10, 0.5, 12), Vector3(0, 0, -22), Color(0.34, 0.32, 0.27))

	var cam = Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 7.5, 16)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)

	# Flame jet, aimed along -Z like a real barrel.
	var nozzle = Node3D.new()
	world.add_child(nozzle)
	nozzle.position = Vector3(-8, 1.6, 6)
	nozzle.rotation_degrees = Vector3(0, 35, 0)
	var jet = VFXEffects.make_flame_emitter(nozzle, 9.0, 1.0)
	var jet_smoke = VFXEffects.make_flame_smoke_emitter(nozzle, 9.0)
	jet.emitting = true
	jet_smoke.emitting = true

	# Ground scorch: one cold mark on the flat, one BURNING pool on the ramp.
	VFXEffects.scorch(world, Vector3(-2, 0.3, -2), 3.0, 0.0, 600.0)
	VFXEffects.scorch(world, Vector3(7, 1.9, 0), 3.5, 600.0, 600.0)

	# A smoke puff needs to be re-triggered because it is one_shot and would
	# be over before the screenshot; fire it and wait a beat.
	VFXEffects.smoke_puff(world, Vector3(4, 0.5, 6), 1.8, 14)

	# Let particles fill in and the flipbook reach a representative frame.
	for i in range(70):
		await process_frame

	var dir = "res://progress_captures/2026-07-31-vfx"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var img = root.get_texture().get_image()
	img.save_png("%s/vfx_effects.png" % dir)
	print("saved %s/vfx_effects.png" % dir)

	# Close-up on the flame alone, to judge the flipbook itself.
	cam.position = Vector3(-6.5, 2.6, 3.0)
	cam.look_at(Vector3(-10.5, 1.6, 0.5), Vector3.UP)
	for i in range(20):
		await process_frame
	root.get_texture().get_image().save_png("%s/vfx_flame_closeup.png" % dir)
	print("saved %s/vfx_flame_closeup.png" % dir)
	quit(0)

func _slab(world: Node3D, pos: Vector3, size: Vector3, rot_deg: Vector3, col: Color) -> void:
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	mi.material_override = mat
	world.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot_deg
