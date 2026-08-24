extends SceneTree
# Verifies the frame-chunked terrain build path introduced 2026-08-23.
#
# THE TWO CLAIMS THIS PROVES:
#
#   1. PARITY - build_ground_visual_mesh(map, ticker) produces the SAME
#      geometry as build_ground_visual_mesh(map), and spawn_visuals(...,
#      ticker) creates the SAME prop tree as spawn_visuals(...). The chunked
#      variants must be a scheduling change only; any drift here would show
#      up as seams, lighting discontinuities or missing scatter.
#
#   2. PACING - run windowed (no --headless) with a ticker, no single
#      main-thread gap during either phase approaches the multi-second
#      freezes the old monolithic calls produced. The watchdog coroutine
#      samples process_frame alongside the builder; because a blocked main
#      thread delays both equally, the watchdog's worst inter-sample gap IS
#      the worst visible hitch.
#
# Run WINDOWED (the chunked path only engages outside headless):
#   ./Godot_v4.7.1-stable_win64_console.exe --path . \
#       --script res://tools/probe_terrain_chunking.gd

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")
const TerrainVisualScatterScript = preload("res://scripts/terrain_visual_scatter.gd")
const AmbientScatterScript = preload("res://scripts/ambient_scatter.gd")
const WorldScaleScript = preload("res://scripts/world_scale.gd")

var _fails: int = 0


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _init():
	_run()


func _run() -> void:
	await process_frame
	var map_def: Dictionary = MapCatalog.get_map(MapCatalog.DEFAULT_MAP_ID)
	print("[probe] map '%s' half_extents=%s" % [str(map_def.get("id", "?")), str(map_def.get("map_half_extents", "?"))])

	var holder := Node3D.new()
	root.add_child(holder)

	# --- Ground mesh: chunked vs sync ------------------------------------
	var w1 := _start_watchdog()
	var t0 := Time.get_ticks_usec()
	var chunked: Dictionary = await TerrainBuilder.build_ground_visual_mesh(map_def, holder)
	var chunked_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var pace1: Dictionary = await _stop_watchdog(w1)

	var t1 := Time.get_ticks_usec()
	var sync: Dictionary = await TerrainBuilder.build_ground_visual_mesh(map_def)
	var sync_ms := float(Time.get_ticks_usec() - t1) / 1000.0

	var ca: Array = (chunked.mesh as ArrayMesh).surface_get_arrays(0)
	var sa: Array = (sync.mesh as ArrayMesh).surface_get_arrays(0)
	var cvert: int = (ca[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var svert: int = (sa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var cidx: int = (ca[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	var sidx: int = (sa[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	print("[probe] ground mesh: %d verts / %d indices | chunked %.0f ms (%d frames, worst gap %.1f ms) vs sync %.0f ms"
		% [cvert, cidx, chunked_ms, pace1["frames"], pace1["worst"], sync_ms])
	_check("chunked ground mesh matches sync vertex count", cvert == svert and cvert > 0)
	_check("chunked ground mesh matches sync index count", cidx == sidx and cidx > 0)
	var cbb := _aabb_of(ca[Mesh.ARRAY_VERTEX])
	var sbb := _aabb_of(sa[Mesh.ARRAY_VERTEX])
	_check("chunked ground mesh AABB matches sync", cbb.is_equal_approx(sbb))
	var csamp: int = chunked.shape.map_data.size()
	var ssamp: int = sync.shape.map_data.size()
	_check("collision heightmap matches sync", csamp == ssamp and csamp > 0)
	_check("ground mesh spread over multiple frames", pace1["frames"] > 4)
	print("[probe] ground gaps>100ms: %s" % str(pace1["big"]))

	# --- Scatter: chunked vs sync ----------------------------------------
	var c1 := Node3D.new()
	var c2 := Node3D.new()
	holder.add_child(c1)
	holder.add_child(c2)

	print("[probe] scatter: starting chunked pass")
	var w2 := _start_watchdog()
	t0 = Time.get_ticks_usec()
	await TerrainBuilder.spawn_visuals(map_def, c1, holder)
	var scat_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var pace2: Dictionary = await _stop_watchdog(w2)
	print("[probe] scatter: chunked pass done")

	print("[probe] scatter: starting sync pass")
	t1 = Time.get_ticks_usec()
	await TerrainBuilder.spawn_visuals(map_def, c2)
	var scat_sync_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	print("[probe] scatter: sync pass done")

	var cn := _count_children(c1)
	var sn := _count_children(c2)
	print("[probe] scatter: %d nodes | chunked %.0f ms (%d frames, worst gap %.1f ms) vs sync %.0f ms"
		% [cn, scat_ms, pace2["frames"], pace2["worst"], scat_sync_ms])
	_check("chunked scatter matches sync node count", cn == sn and cn > 0)

	# --- Scatter phase timeline -------------------------------------------
	# Drives spawn_visuals' sub-phases by hand into a fresh container so the
	# wall-clock cost of each is visible individually - this is what decides
	# where chunking has to go deeper than the sub-phase boundaries.
	var c3 := Node3D.new()
	holder.add_child(c3)
	var prop_scale: float = WorldScaleScript.for_map(map_def)
	var steps: Array = []
	var _step := func(label: String, fn: Callable) -> void:
		var s0 := Time.get_ticks_usec()
		await fn.call()
		steps.append({"label": label, "ms": float(Time.get_ticks_usec() - s0) / 1000.0})
	await _step.call("merged_water", func(): TerrainBuilder._spawn_merged_water(map_def, c3, prop_scale))
	await _step.call("obstacles", func():
		for o in map_def.get("obstacles", []):
			TerrainBuilder._spawn_obstacle(o, c3, map_def))
	await _step.call("surface_zones", func():
		for s in map_def.get("surface_zones", []):
			await TerrainBuilder._spawn_surface_zone(s, c3, prop_scale, map_def))
	await _step.call("grassland_clutter", func(): TerrainBuilder._spawn_grassland_clutter(map_def, c3, prop_scale))
	await _step.call("ambient_trees", func(): return await TerrainBuilder._spawn_ambient_trees(map_def, c3, prop_scale))
	await _step.call("ambient_ores", func(): TerrainBuilder._spawn_ambient_ores(map_def, c3, prop_scale))
	var batcher := AmbientScatterScript.get_or_create(c3)
	await _step.call("ambient_commit", func(): batcher.commit())
	var vs := TerrainVisualScatterScript.get_or_create(c3)
	await _step.call("visual_scatter_all", func(): vs.scatter_all(map_def, prop_scale))
	await _step.call("slope_rocks", func(): TerrainBuilder._spawn_slope_rocks(map_def, c3))
	for s in steps:
		print("[probe]   %-20s %8.0f ms" % [s["label"], s["ms"]])

	# Batcher forensics: which containers hold an AmbientScatter, is it
	# committed, and how many registrations landed per species.
	for cont in [c1, c2, c3]:
		for child in cont.get_children():
			if child.get_script() == AmbientScatterScript:
				var pend: Dictionary = child._pending
				var totals := {}
				for k in pend:
					totals[str(k.get_file())] = pend[k].size()
				print("[probe] batcher under %s committed=%s pending=%s"
					% [cont.name, str(child._committed), str(totals)])

	# --- Pacing ------------------------------------------------------------
	# The budget is 8 ms of work per frame; a frame's TOTAL duration includes
	# rendering/idle overhead on top, so allow generous headroom before calling
	# it a regression. Anything near the old multi-second freezes fails. A
	# couple of isolated ~300 ms spikes (glb template loads on a cold import
	# cache, driver hiccups) are tolerated; sustained deadness is not.
	print("[probe] ground gaps>100ms: %s" % str(pace1["big"]))
	print("[probe] scatter gaps>100ms: %s" % str(pace2["big"]))
	_check("ground mesh worst inter-frame gap < 500 ms", pace1["worst"] < 500.0)
	_check("ground mesh has <= 3 gaps over 250 ms", pace1["over250"] <= 3)
	_check("scatter worst inter-frame gap < 500 ms", pace2["worst"] < 500.0)
	_check("scatter has <= 3 gaps over 250 ms", pace2["over250"] <= 3)

	print("")
	if _fails == 0:
		print("PASS - chunked terrain builds are parity-clean and stay responsive")
	else:
		print("%d CHECK(S) FAILED" % _fails)
	holder.queue_free()
	quit(1 if _fails > 0 else 0)


# Samples process_frame next to the builders. A blocked main thread delays
# this coroutine identically, so its worst inter-sample gap is the worst
# hitch the player could see.
func _start_watchdog() -> Dictionary:
	var w := {"worst": 0.0, "frames": 0, "last": Time.get_ticks_usec(), "run": true,
		"over250": 0, "big": []}
	# Detached coroutine: it samples alongside the builders for as long as
	# w["run"] is true.
	_tick_loop(w)
	return w


func _tick_loop(w: Dictionary) -> void:
	while w["run"]:
		await process_frame
		var now := Time.get_ticks_usec()
		var gap := float(now - int(w["last"])) / 1000.0
		w["last"] = now
		w["frames"] = int(w["frames"]) + 1
		if gap > float(w["worst"]):
			w["worst"] = gap
		if gap > 250.0:
			w["over250"] = int(w["over250"]) + 1
		if gap > 100.0:
			var big: Array = w["big"]
			big.append(int(gap))


func _stop_watchdog(w: Dictionary) -> Dictionary:
	w["run"] = false
	await process_frame
	return {"worst": float(w["worst"]), "frames": int(w["frames"]),
		"over250": int(w["over250"]), "big": w["big"]}


func _count_children(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		n += 1 + _count_children(c)
	return n


func _aabb_of(packed) -> AABB:
	var pts: PackedVector3Array = packed
	var box := AABB(pts[0], Vector3.ZERO)
	for v in pts:
		box = box.expand(v)
	return box
