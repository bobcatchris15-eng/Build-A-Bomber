extends SceneTree
# PERFORMANCE_PLAN.md verification: spawns many units per side in a real
# Skirmish and logs physics-frame time, to sanity-check P1a/b/c actually
# help at scale. Must run WITHOUT --headless (needs real physics/render).

func _init():
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(4): await process_frame

	var bp = {
		"version": 1.0, "hull_type": "medium_hull", "faction": "industrialists",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "wheels", "settings": {}},
		"modules": [
			{"type_id": "wheels", "name": "Wheels", "position": {"x": 0.0, "y": -1.0, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}},
			{"type_id": "basic_cannon", "name": "Cannon", "position": {"x": 0.0, "y": 1.0, "z": 1.5}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}},
		]
	}

	var n_per_side = 30
	for i in range(n_per_side):
		var px = skirmish.player_hq.global_position + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
		skirmish.spawn_unit(bp, skirmish.PLAYER_TEAM, px)
	for i in range(n_per_side):
		var ex = skirmish.enemy_hq.global_position + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
		skirmish.spawn_unit(bp, skirmish.ENEMY_TEAM, ex)

	print("Spawned ", n_per_side * 2, " units. Letting combat settle...")
	for i in range(120): await process_frame

	var samples: Array = []
	for i in range(60):
		await process_frame
		samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))

	samples.sort()
	var total = 0.0
	for s in samples: total += s
	print("Physics process time over 60 frames with ", n_per_side * 2, " units in active combat:")
	print("  avg: ", total / samples.size() * 1000.0, " ms")
	print("  median: ", samples[samples.size() / 2] * 1000.0, " ms")
	print("  max: ", samples[samples.size() - 1] * 1000.0, " ms")
	quit(0)
