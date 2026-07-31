extends SceneTree
# Follow-up to scratch/perf_matrix.gd, which found that hiding ALL world
# geometry took the frame from 45.5ms to 3.57ms - i.e. ~42ms of a 45ms frame
# is world rendering, while 8 units in sustained combat add only 2.8ms. This
# breaks that 42ms down per top-level world node so the next optimisation
# targets the actual offender instead of the whole scene.
#
# Method: same round-robin-in-one-process discipline as perf_matrix (never
# compare across processes on this machine - identical code has measured
# 7ms to 168ms depending on desktop load), and the same pinned 1280x720
# always-on-top window so pixel count is constant and the window keeps
# presenting.
#
# Reports, for each direct Node3D child of the Skirmish scene, the frame time
# with ONLY that node hidden (everything else visible). A node whose removal
# recovers a large share of the 42ms is the thing to optimise.
#
# Must run WITHOUT --headless.
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/probe_world_cost.gd --path .

const PASSES := 4
const SETTLE_FRAMES := 25
const SAMPLE_FRAMES := 50

func _init():
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(10): await process_frame

	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_position(Vector2i(40, 40))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	# MUST disable vsync. The first version of this probe left it at the
	# project default (on), which pins every frame to the 16.7ms vblank on a
	# 60Hz display - so baseline and "everything hidden" both measured 16.7ms
	# and every per-node delta was noise within +/-0.12ms. With vsync on there
	# is simply no measurement resolution below the refresh period.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in range(4): await process_frame

	var mid = (skirmish.player_hq.global_position + skirmish.enemy_hq.global_position) * 0.5
	skirmish.camera.global_position.x = mid.x
	skirmish.camera.global_position.z = mid.z
	for i in range(10): await process_frame

	# Ablating one node at a time was the wrong granularity: the scene has 145
	# top-level world nodes, ~120 of which are individual terrain-clutter
	# MeshInstance3Ds costing well under 0.1ms each - individually lost in
	# noise, collectively possibly dominant. Grouping by role answers "what
	# should I optimise" directly.
	var targets: Array = []
	for child in skirmish.get_children():
		if child is Node3D and not (child is Camera3D):
			targets.append(child)

	var groups: Dictionary = {
		"light": [], "ground": [], "buildings": [], "vehicles": [],
		"clutter": [], "fog": [],
	}
	for t in targets:
		if t is DirectionalLight3D: groups["light"].append(t)
		elif str(t.name) == "Ground": groups["ground"].append(t)
		elif str(t.name) == "FogShroud": groups["fog"].append(t)
		elif t is StaticBody3D: groups["buildings"].append(t)
		elif t is CharacterBody3D: groups["vehicles"].append(t)
		else: groups["clutter"].append(t)

	print("viewport: ", root.get_viewport().get_visible_rect().size, "   vsync: OFF")
	for g in groups.keys():
		var vis := 0
		for t in groups[g]: vis += _count_visuals(t)
		print("   %-11s nodes=%-4d visual instances=%d" % [g, groups[g].size(), vis])
	print("")

	var labels: Array = ["baseline_all_visible", "hide_everything"]
	for g in groups.keys():
		labels.append("hide_" + str(g))
	var results: Dictionary = {}
	for l in labels:
		results[l] = []

	for p in range(PASSES):
		for l in labels:
			# Reset to fully visible, then apply just this label's ablation.
			for t in targets:
				t.visible = true
			if l == "hide_everything":
				for t in targets:
					t.visible = false
			elif l.begins_with("hide_"):
				var want: String = str(l).substr(5)
				for t in groups.get(want, []):
					t.visible = false
			var med := await _measure()
			results[l].append(med)
		print("  pass %d done" % (p + 1))

	var base := _median(results["baseline_all_visible"])
	var floor_ms := _median(results["hide_everything"])
	print("\n=== per-group cost ===")
	# Per-pass baselines are printed because this scene warms up steeply: an
	# earlier run drifted from 36.6ms to 5.0ms for the SAME ablation across
	# three passes, which makes a median across passes meaningless and can even
	# make an ablation look cheaper than the baseline. Compare each ablation
	# against the baseline FROM THE SAME PASS (rightmost pass is the settled
	# one); ignore the medians if the passes disagree.
	var base_pp := ""
	for v in results["baseline_all_visible"]:
		base_pp += "%7.2f" % v
	var floor_pp := ""
	for v in results["hide_everything"]:
		floor_pp += "%7.2f" % v
	print("  baseline (all visible)   %7.2f ms   per-pass:%s" % [base, base_pp])
	print("  everything hidden        %7.2f ms   per-pass:%s" % [floor_ms, floor_pp])
	print("  => total world cost      %7.2f ms (median basis)" % (base - floor_ms))
	# If hiding the entire world barely moves the frame, there is no resolution
	# to attribute anything within it - report that instead of ranking noise.
	if base - floor_ms < 1.0:
		print("\n  *** NO RESOLUTION: hiding the whole world changed the frame by")
		print("      only %.2f ms, so the per-group numbers below are noise." % (base - floor_ms))
		print("      Either the frame is bound by something other than world")
		print("      rendering, or vsync/occlusion is capping it. Discard.")
	print("")
	var rows: Array = []
	for l in labels:
		if l in ["baseline_all_visible", "hide_everything"]:
			continue
		rows.append({"name": l, "med": _median(results[l]), "all": results[l]})
	rows.sort_custom(func(a, b): return a["med"] < b["med"])
	for r in rows:
		var per_pass := ""
		for v in r["all"]:
			per_pass += "%7.2f" % v
		print("  %-20s %7.2f ms   recovers %6.2f ms (%5.1f%% of frame)   per-pass:%s" % [
			r["name"], r["med"], base - r["med"],
			(base - r["med"]) / base * 100.0, per_pass])
	quit(0)

func _measure() -> float:
	for i in range(SETTLE_FRAMES): await process_frame
	var samples: Array = []
	var last := Time.get_ticks_usec()
	for i in range(SAMPLE_FRAMES):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - last) / 1000.0)
		last = now
	return _median(samples)

func _count_visuals(n: Node) -> int:
	var c := 1 if (n is VisualInstance3D) else 0
	for child in n.get_children():
		c += _count_visuals(child)
	return c

func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return s[int(s.size() * 0.5)]
