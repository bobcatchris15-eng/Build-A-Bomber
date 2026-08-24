extends SceneTree
# Measures the post-rebake agent re-path storm that the 02:31 skirmish log
# implicates in its 2.2 s unit.steer_nav frames. The match data shows every
# AI power-plant placement carves a navmesh hole; when the bake lands,
# _on_navmesh_rebaked walks every unit through request_repath(), and every
# agent's next get_next_path_position() re-runs A* - apparently expensively.
#
# The probe boots a real battle on lake_crossing (the log's map), spawns a
# small army with live paths, times each agent's path query BEFORE a
# structure placement and again AFTER the rebake lands, and prints both
# distributions. Two shapes to distinguish:
#
#   - agent 0 eats seconds and the rest are cheap -> the first querier is
#     paying the navigation-server map sync/merge inside its query;
#     budgeting queries barely helps, cutting SYNC COUNT does.
#   - every agent pays tens of ms -> distributed A*; a per-frame query
#     budget spreads it flat.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script res://tools/probe_navmesh_repath_storm.gd

const MapCatalog = preload("res://scripts/map_catalog.gd")

const ARMY := 30

func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

func _init():
	var packed = load("res://scenes/Battle.tscn")
	var battle = packed.instantiate()
	battle.map_id = "lake_crossing"
	root.add_child(battle)

	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	print("[OK] battle ready after %d frames" % guard)
	for _i in range(20):
		await process_frame

	var text := FileAccess.get_file_as_string("res://data/loadout/rattler_scout.json")
	var blueprint: Dictionary = JSON.parse_string(text)
	if typeof(blueprint) != TYPE_DICTIONARY or blueprint.is_empty():
		print("[FAIL] no scout blueprint")
		quit(1)
		return

	var anchor: Vector3 = battle.snap_to_navmesh(Vector3(0, 0, 0))
	var units: Array = []
	for i in range(ARMY):
		var ring := float(i / 12)
		var ang := TAU * float(i % 12) / 12.0
		var spot := anchor + Vector3(cos(ang) * (6.0 + ring * 6.0), 0.0, sin(ang) * (6.0 + ring * 6.0))
		var u = battle.spawn_unit(blueprint, 0, battle.snap_to_navmesh(spot))
		if is_instance_valid(u):
			units.append(u)
	print("[OK] spawned %d units" % units.size())
	for _i in range(10):
		await process_frame

	var destination: Vector3 = battle.snap_to_navmesh(anchor + Vector3(220.0, 0.0, -140.0))
	battle.orders.move(units, destination)
	for _i in range(30):
		await process_frame

	var sample := func(label: String) -> void:
		var times: Array[float] = []
		for u in units:
			if not is_instance_valid(u) or u.is_dead or not is_instance_valid(u.nav_agent):
				continue
			var t0 := Time.get_ticks_usec()
			u.nav_agent.get_next_path_position()
			times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		if times.is_empty():
			print("%s: no agents" % label)
			return
		times.sort()
		var total := 0.0
		for t in times: total += t
		print("%s: n=%d first=%.2fms median=%.2fms p90=%.2fms max=%.2fms total=%.1fms" % [
			label, times.size(), times[0], times[times.size() / 2], times[int(times.size() * 0.9)],
			times[-1], total])

	await sample.call("BASELINE query")

	# Place structures the way the AI does - a few, spaced past the debounce.
	var site := anchor + Vector3(40.0, 0.0, 10.0)
	for k in range(3):
		battle._place_structure("power_plant", 0, battle.snap_to_navmesh(site + Vector3(18.0 * k, 0.0, 0.0)))
		for _i in range(5):
			await process_frame
	# The lazy rebake debounce lands within NAV_LAZY_REBAKE_DELAY; give it room.
	for _i in range(120):
		await process_frame
	print("[OK] structures placed, rebake settled")

	await sample.call("POST-REBAKE query")

	# --- Catch a REAL field build through the game's own path -----------------
	# One group move for >=FIELD_MIN_UNITS over >=MIN_TRIP_DISTANCE forces
	# field_for() to build. Watch per-frame wall time and the field cache so
	# the build lands visibly.
	var big_squad: Array = []
	for u in units:
		if is_instance_valid(u) and not u.is_dead:
			big_squad.append(u)
	battle.flow_fields.invalidate()
	var far_dest: Vector3 = battle.snap_to_navmesh(anchor + Vector3(-320.0, 0.0, 240.0))
	battle.orders.move(big_squad, far_dest)
	print("[OK] group move issued for %d units (trip ~%.0f m)" % [
		big_squad.size(), 400.0])
	for i in range(180):
		var t0 := Time.get_ticks_usec()
		await process_frame
		var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var nf: int = battle.flow_fields._fields.size()
		if dt_ms > 250.0 or i == 0 or (nf > 0 and i < 2):
			print("  frame %3d: %.0f ms, cached fields=%d" % [i, dt_ms, nf])
		if nf > 0 and i > 3:
			break

	# --- Storm without fields --------------------------------------------------
	# Individual orders (one unit per group -> field_for bails on size<8) plus
	# AI-cadence structure placement. Any multi-second frame here CANNOT be a
	# field build; it must be the nav-sync / agent-repath side.
	print("[STORM] placing structures every 60 frames while units re-steer")
	for k in range(10):
		var spot: Vector3 = battle.snap_to_navmesh(
			anchor + Vector3(40.0 + 18.0 * (k % 6), 0.0, 10.0 + 14.0 * (k / 6)))
		battle._place_structure("power_plant", 0, spot)
		for j in range(60):
			var t1 := Time.get_ticks_usec()
			await process_frame
			var dt1 := float(Time.get_ticks_usec() - t1) / 1000.0
			if dt1 > 250.0:
				print("  storm frame (plant %d, +%d): %.0f ms" % [k, j, dt1])
	print("[STORM] done")

	# --- Where does a flow-field rebuild actually spend its time? -------------
	var FlowFieldScript = load("res://scripts/battle/movement/flow_field.gd")
	var map_def := MapCatalog.get_map("lake_crossing")
	var half: float = map_def.get("map_half_extents", 960.0)
	var ws: float = 4.0
	var cell: float = 4.0 * ws
	var side := int(ceil((half * 2.0) / cell))
	var ff = FlowFieldScript.new()
	ff.destination = destination
	ff.cell_size = cell
	ff.passable_tolerance = cell * 0.75
	ff.origin = Vector3(-half, 0.0, -half)
	ff.dims = Vector2i(side, side)
	var ground_map: RID = battle.get_ground_nav_map()
	var t0 := Time.get_ticks_usec()
	ff._sample_passability(ground_map)
	var sample_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	ff._integrate()
	var integrate_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	ff._derive_flow()
	var derive_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("FLOWFIELD build: cells=%d sample=%.1fms integrate=%.1fms derive=%.1fms total=%.1fms" % [
		side * side, sample_ms, integrate_ms, derive_ms, sample_ms + integrate_ms + derive_ms])

	quit(0)
