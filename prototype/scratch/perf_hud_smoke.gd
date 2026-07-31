extends SceneTree
# Smoke test for scripts/perf_hud.gd: instantiates a real Skirmish, toggles
# the overlay through the same _toggle_perf_hud() path F3 uses, spawns units so
# the counters have something to report, and prints the overlay's rendered text
# so it can be verified without a human watching the window.
#
# Must run WITHOUT --headless (the overlay reads render monitors).
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/perf_hud_smoke.gd --path .

func _init():
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(10): await process_frame

	var mid = (skirmish.player_hq.global_position + skirmish.enemy_hq.global_position) * 0.5
	skirmish.camera.global_position.x = mid.x
	skirmish.camera.global_position.z = mid.z

	var bp = {
		"version": 2.0, "hull_type": "medium_hull", "faction": "industrialists",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "wheels", "settings": {}},
		"modules": [
			{"type_id": "wheels", "name": "wheels", "position": {"x": 0.0, "y": -1.0, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}},
			{"type_id": "rotary_cannon", "name": "rotary_cannon", "position": {"x": 0.0, "y": 1.0, "z": 1.2}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}},
		]
	}
	for i in range(3):
		skirmish.spawn_unit(bp, skirmish.PLAYER_TEAM, mid + Vector3(i * 4.0 - 4.0, 0, -4.0))
		skirmish.spawn_unit(bp, skirmish.ENEMY_TEAM, mid + Vector3(i * 4.0 - 4.0, 0, 4.0))

	skirmish._toggle_perf_hud()
	var hud = skirmish.get_node_or_null("PerfHUD")
	if not hud:
		print("FAIL: overlay was not created")
		quit(1)
		return
	print("PASS: overlay created, layer=", hud.layer)

	# The overlay rebuilds its text once per second, so wait past that.
	for i in range(130): await process_frame

	var label = _find_label(hud)
	if not label:
		print("FAIL: no Label found under overlay")
		quit(1)
		return
	if label.text.strip_edges() == "":
		print("FAIL: overlay text never populated")
		quit(1)
		return
	print("--- overlay contents ---")
	print(label.text)
	print("--- end ---")

	# Toggling again must remove it (F3 pressed twice).
	skirmish._toggle_perf_hud()
	for i in range(3): await process_frame
	if skirmish.get_node_or_null("PerfHUD"):
		print("FAIL: overlay was not removed on second toggle")
		quit(1)
		return
	print("PASS: overlay removed on second toggle")
	quit(0)

func _find_label(n: Node) -> Label:
	if n is Label:
		return n
	for c in n.get_children():
		var found := _find_label(c)
		if found:
			return found
	return null
