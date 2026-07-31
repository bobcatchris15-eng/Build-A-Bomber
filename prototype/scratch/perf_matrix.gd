extends SceneTree
# Ablation harness for the ~26ms/frame floor that scratch/perf_probe.gd found
# sits under EVERY configuration - including an empty map with zero units.
#
# WHY THIS EXISTS RATHER THAN MORE perf_probe RUNS. perf_probe measures one
# configuration per process, so comparing configurations means comparing
# separate processes run at different times. On this machine (Radeon 860M
# iGPU) that is fatal: identical code measured 6.9, 20, 40 and 120ms across
# four consecutive runs, and within any batch the later runs were reliably
# slower - so whichever configuration happened to run last looked worst. An
# earlier conclusion ("munition churn costs 5x idle") turned out to be
# entirely an artifact of churn always running last.
#
# The fix is structural, not statistical: every scenario is measured in ONE
# process, ROUND-ROBIN, across several passes. Thermal/background drift then
# hits all scenarios equally instead of loading onto the last one, and
# per-pass output makes the drift visible instead of hiding it in a mean.
# Compare scenarios WITHIN a pass; compare passes only to judge drift.
#
# VSYNC. perf_probe never disabled it, and project.godot does not set it, so
# it defaulted to ON - meaning every frame time it reported was quantised to
# the display's refresh cadence and a "floor" was guaranteed regardless of
# workload. This harness disables vsync outright (and measures it both ways,
# scenario 'empty_vsync_on', to quantify how much that alone distorted the
# earlier numbers).
#
# THE ABLATION LADDER, each isolating one candidate for the floor:
#   empty            - map, terrain, HQs, harvesters; no player units
#   empty_vsync_on   - same, vsync re-enabled (what perf_probe was measuring)
#   empty_no_shadow  - directional shadow map off
#   empty_msaa_off   - project.godot ships msaa_3d=2 (4x MSAA) at 1920x1080,
#                      which is a lot of fill rate for an iGPU
#   empty_scale_50   - 3D render scale 0.5 (quarter the pixels). If the floor
#                      is fill-rate/shader bound this collapses; if it is CPU
#                      or present-bound it does not move. This is the single
#                      most diagnostic scenario in the list.
#   empty_hide_world - every world Node3D hidden: sky/environment only. If
#                      the floor survives THIS, no amount of mesh baking,
#                      LOD or draw-call work can help it.
#   units_idle       - 8 units, no combat
#   units_churn      - 8 units, flamethrower + rotary, sustained fire
#
# Units are made immortal so attrition cannot silently turn "8 units
# fighting" into "however many survived, idling" - the other confound that
# invalidated the first measurement pass.
#
# Must run WITHOUT --headless.
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/perf_matrix.gd --path .

const PASSES := 3
const SETTLE_FRAMES := 30
const SAMPLE_FRAMES := 60
const IMMORTAL_HP := 1.0e9

var _skirmish: Node = null
var _mid: Vector3 = Vector3.ZERO
var _spawned: Array = []
var _unit_kind: String = "none"
var _light: DirectionalLight3D = null
var _results: Dictionary = {} # scenario -> Array of per-pass medians

func _init():
	_skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(_skirmish)
	current_scene = _skirmish
	for i in range(10): await process_frame

	_mid = (_skirmish.player_hq.global_position + _skirmish.enemy_hq.global_position) * 0.5
	_skirmish.camera.global_position.x = _mid.x
	_skirmish.camera.global_position.z = _mid.z
	_light = _skirmish.get_node_or_null("DirectionalLight3D")

	# Pin the window to a fixed, modest, always-visible size. Three reasons:
	#  1. Comparability - an earlier run of this harness rendered at 2669x1080
	#     because the window inherited a resize from the UI work, so its frame
	#     times were not comparable to any other run. Pixel count is the single
	#     biggest lever on this scene's cost (render scale 0.5 cut frame time
	#     37%), so it must be identical across runs, not whatever the window
	#     happened to be.
	#  2. Always-on-top keeps the window presenting even while other work
	#     continues on the desktop. Godot stops doing real per-frame work for
	#     an occluded window, which silently invalidates the whole run (see the
	#     validity gate below).
	#  3. A smaller window leaves more iGPU headroom for the rest of the
	#     desktop, which reduces - but does NOT eliminate - contention drift.
	#     For trustworthy absolute numbers the machine still needs to be quiet.
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_position(Vector2i(40, 40))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	for i in range(4): await process_frame

	var vp := root.get_viewport()
	print("viewport size: ", vp.get_visible_rect().size, "   msaa_3d: ", vp.msaa_3d,
		"   refresh: ", DisplayServer.screen_get_refresh_rate(), " Hz")
	print("scenarios measured round-robin over %d passes, %d frames each\n" % [PASSES, SAMPLE_FRAMES])

	var scenarios := [
		"empty", "empty_vsync_on", "empty_no_shadow", "empty_msaa_off",
		"empty_scale_50", "empty_hide_world", "units_idle", "units_churn",
		# Added after the perf_hud smoke test showed 41.8ms mean and 24
		# hitches/sec over 33ms with only 6 firing units and vsync ON, against
		# 15.4ms for units_churn with vsync OFF. If the baseline sits just
		# under the 16.7ms vblank deadline, then combat pushing it barely over
		# doesn't cost the overshoot - it costs a whole extra vblank (33.3ms),
		# and jitter takes some frames to 50ms. These two scenarios test that
		# amplification directly, and whether dropping MSAA buys back enough
		# headroom to stay under the deadline.
		"units_churn_vsync_on", "units_churn_msaa_off", "units_churn_both",
	]
	for s in scenarios:
		_results[s] = []

	for p in range(PASSES):
		for s in scenarios:
			var med := await _measure(s)
			_results[s].append(med)
			print("  pass %d  %-17s median %7.2f ms" % [p + 1, s, med])
		print("")

	# --- VALIDITY GATE -----------------------------------------------------
	#
	# A run of this harness is only meaningful if the window is actually
	# rendering and presenting. It sometimes is not: on a busy desktop the
	# window can end up occluded or unfocused, at which point Godot stops
	# doing the real per-frame work and EVERY scenario collapses to the same
	# few milliseconds - including ones that are physically impossible, like
	# vsync-on measuring faster than the refresh period.
	#
	# That happened twice during this investigation (one run reported all 11
	# scenarios between 6.2 and 7.5ms, vsync-on included) and it is dangerous
	# precisely because it looks like GREAT performance rather than like a
	# broken measurement. The check: with vsync ON, frame time cannot be
	# meaningfully below the display's refresh period. If it is, the numbers
	# describe a window that isn't drawing, and must be thrown away.
	var vsync_floor := _median(_results["empty_vsync_on"])
	var refresh := DisplayServer.screen_get_refresh_rate()
	var expected := 1000.0 / (refresh if refresh > 0.0 else 60.0)
	var valid := vsync_floor > expected * 0.8
	if not valid:
		print("*** INVALID RUN - DISCARD THESE NUMBERS ***")
		print("    empty_vsync_on measured %.2f ms but the display refresh period" % vsync_floor)
		print("    is %.2f ms. Frame time cannot beat vblank while vsync is on, so" % expected)
		print("    this window was not presenting (occluded, minimised, or the")
		print("    compositor dropped it). Bring the Godot window to the")
		print("    foreground, keep it visible for the whole run, and re-run.")
		print("")

	print("=== summary (median of per-pass medians) ===")
	var rows: Array = []
	for s in scenarios:
		rows.append({"name": s, "med": _median(_results[s]), "all": _results[s]})
	for r in rows:
		var per_pass := ""
		for v in r["all"]:
			per_pass += "%7.2f" % v
		print("  %-17s %7.2f ms   fps %6.1f   per-pass:%s" % [
			r["name"], r["med"], 1000.0 / r["med"], per_pass])
	if not valid:
		print("\n*** REMINDER: the validity gate above FAILED. These numbers are not usable. ***")
	# Pass 1 is routinely an outlier (shader/pipeline warm-up on first draw of
	# each scenario), which is why the per-pass column is printed rather than
	# just a mean - judge from the agreement of passes 2..N.
	quit(0 if valid else 1)

func _measure(scenario: String) -> float:
	await _apply(scenario)
	for i in range(SETTLE_FRAMES): await process_frame
	var samples: Array = []
	var last := Time.get_ticks_usec()
	for i in range(SAMPLE_FRAMES):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - last) / 1000.0)
		last = now
	return _median(samples)

# Every scenario re-asserts the FULL viewport/light state rather than only the
# one knob it cares about, so scenarios cannot leak settings into whichever
# one happens to run next.
func _apply(scenario: String) -> void:
	var vp := root.get_viewport()

	var vsync_on := scenario in ["empty_vsync_on", "units_churn_vsync_on", "units_churn_both"]
	var msaa_off := scenario in ["empty_msaa_off", "units_churn_msaa_off", "units_churn_both"]
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED)
	vp.msaa_3d = Viewport.MSAA_DISABLED if msaa_off else Viewport.MSAA_4X
	vp.scaling_3d_scale = 0.5 if scenario == "empty_scale_50" else 1.0
	if _light:
		_light.shadow_enabled = scenario != "empty_no_shadow"

	var want_units := "none"
	if scenario == "units_idle": want_units = "idle"
	elif scenario.begins_with("units_churn"): want_units = "churn"
	await _ensure_units(want_units)

	# Hide/show the world last, so newly spawned units inherit the right state.
	var hide_world := scenario == "empty_hide_world"
	for child in _skirmish.get_children():
		if child is Node3D and not (child is Camera3D):
			child.visible = not hide_world

func _ensure_units(kind: String) -> void:
	if kind == _unit_kind:
		return
	for u in _spawned:
		if is_instance_valid(u):
			u.free()
	_spawned.clear()
	_unit_kind = kind
	if kind == "none":
		for i in range(4): await process_frame
		return

	var bp := _blueprint([{"id": "basic_cannon", "pos": Vector3(0.0, 1.0, 1.5)}]) if kind == "idle" \
		else _blueprint([
			{"id": "flamethrower", "pos": Vector3(-0.8, 1.0, 1.2)},
			{"id": "rotary_cannon", "pos": Vector3(0.8, 1.0, 1.2)},
		])

	if kind == "idle":
		# One team only: no enemy in range, so nothing acquires or fires.
		for i in range(8):
			_spawned.append(_skirmish.spawn_unit(bp, _skirmish.PLAYER_TEAM,
				_mid + Vector3(i * 4.0 - 16.0, 0, -4.0)))
	else:
		for i in range(4):
			_spawned.append(_skirmish.spawn_unit(bp, _skirmish.PLAYER_TEAM,
				_mid + Vector3(i * 4.0 - 8.0, 0, -4.0)))
		for i in range(4):
			_spawned.append(_skirmish.spawn_unit(bp, _skirmish.ENEMY_TEAM,
				_mid + Vector3(i * 4.0 - 8.0, 0, 4.0)))

	for u in _spawned:
		if is_instance_valid(u):
			u.max_hp = IMMORTAL_HP
			u.hp = IMMORTAL_HP
	for i in range(4): await process_frame

func _blueprint(weapons: Array) -> Dictionary:
	var modules: Array = [_module("wheels", Vector3(0.0, -1.0, 0.0))]
	for w in weapons:
		modules.append(_module(w["id"], w["pos"]))
	return {
		"version": 2.0, "hull_type": "medium_hull", "faction": "industrialists",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "wheels", "settings": {}},
		"modules": modules,
	}

func _module(type_id: String, pos: Vector3) -> Dictionary:
	return {
		"type_id": type_id, "name": type_id,
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"rotation": {"x": 0.0, "y": 0.0, "z": 0.0},
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"yaw_offset": 0.0, "tweaks": {},
	}

func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return s[int(s.size() * 0.5)]
