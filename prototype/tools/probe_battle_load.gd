extends SceneTree
# Smoke test: load Battle.tscn, instantiate it, run a few seconds of physics,
# confirm it doesn't crash. Catches PR1.3 errors (Environment resource parse)
# and PR1.4 (unit.gd compile/runtime errors) without running the full test
# suite.
# Run: Godot --headless --script tools/probe_battle_load.gd

func _init():
	var packed := load("res://scenes/Battle.tscn") as PackedScene
	if packed == null:
		print("[FAIL] could not load Battle.tscn")
		quit(1)
		return
	var scene := packed.instantiate()
	if scene == null:
		print("[FAIL] could not instantiate Battle.tscn")
		quit(1)
		return
	# Need a WorldEnvironment? Battle.tscn provides it. Need a window?
	# Headless mode skips the visual server.
	root.add_child(scene)
	# Wait for world_ready, then run 30 physics frames.
	var frames := 0
	for i in range(30):
		await physics_frame
		frames += 1
		if scene.world_is_ready:
			break
	if not scene.world_is_ready:
		print("[WARN] world never became ready; running anyway")
	print("[OK] Battle.tscn loaded, ran %d physics frames, world_is_ready=%s"
		% [frames, str(scene.world_is_ready)])
	# Check that Environment resource is sane.
	var env: Environment = null
	for child in scene.get_children():
		if child is WorldEnvironment:
			env = child.environment
			break
	if env == null:
		print("[FAIL] no WorldEnvironment / Environment in Battle.tscn")
		quit(1)
		return
	print("tonemap_mode=%d sdfgi_enabled=%s ssil_enabled=%s volumetric_fog_enabled=%s"
		% [env.tonemap_mode, str(env.sdfgi_enabled), str(env.ssil_enabled),
			str(env.volumetric_fog_enabled)])
	scene.queue_free()
	quit(0)
