extends SceneTree
# End-to-end: spawn a unit exactly the way a completed production job does
# (factory exit_position, through match_director), give it a real move order,
# and check it actually converges. This is the "built unit circles forever"
# report reduced to something headless.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_built_unit_moves.gd

const MapCatalogScript = preload("res://scripts/map_catalog.gd")


func _init():
	var packed = load("res://scenes/Battle.tscn")
	var battle = packed.instantiate()
	battle.map_id = "open_plains"
	root.add_child(battle)

	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	for _i in range(30):
		await process_frame

	# A ground design, the way production would hand one over.
	var blueprint: Dictionary = _ground_blueprint(battle)
	if blueprint.is_empty():
		print("NO GROUND BLUEPRINT FOUND")
		quit(1)
		return

	var factory = null
	for s in get_nodes_in_group("structures"):
		if is_instance_valid(s) and s.team == 0 and s.kind == "light_manufactory":
			factory = s
			break
	if factory == null:
		# The default skirmish boot no longer guarantees a player manufactory
		# on every map, so place one the same way production completion does.
		# Without this the probe could not run at all (NO FACTORY bail).
		print("no player manufactory at boot - placing one via _place_structure")
		var site: Vector3 = battle.snap_to_navmesh(Vector3(0, 0, 0))
		factory = battle._place_structure("light_manufactory", 0, site)
		for _i in range(10):
			await process_frame
	if factory == null:
		print("NO FACTORY")
		quit(1)
		return

	var raw_exit: Vector3 = factory.exit_position()
	var snapped: Vector3 = battle.snap_to_navmesh(raw_exit)
	print("raw_exit=", raw_exit, " snapped=", snapped,
		" moved=", Vector3(raw_exit.x, 0, raw_exit.z).distance_to(Vector3(snapped.x, 0, snapped.z)))

	var unit = battle.spawn_unit(blueprint, 0, snapped)
	print("move_speed=", unit.move_speed)
	if unit == null:
		print("SPAWN FAILED")
		quit(1)
		return
	for _i in range(5):
		await process_frame

	# Destination: a navmesh-snapped point ~100 m out from wherever the unit
	# actually spawned. The old hardcoded (0,0,0) sat 9 m from the factory
	# exit once maps got world_scale'd, leaving the probe nothing to measure.
	var destination: Vector3 = battle.snap_to_navmesh(
		unit.global_position + Vector3(100.0, 0.0, 40.0))
	if is_instance_valid(unit.nav_agent):
		var m: RID = unit.nav_agent.get_navigation_map()
		print("unit nav_map=", m, " ground=", battle.get_ground_nav_map(),
			" amphibious=", (battle.get_amphibious_nav_map() if battle.has_method("get_amphibious_nav_map") else RID()),
			" water=", battle.get_water_nav_map())
		print("is_amphibious=", unit.is_amphibious, " is_naval=", ("is_naval" in unit and unit.is_naval))
		var pth = NavigationServer3D.map_get_path(m, unit.global_position, destination, true)
		print("path on unit map: size=", pth.size(), " first=", (pth[0] if pth.size() > 0 else Vector3.ZERO),
			" last=", (pth[-1] if pth.size() > 0 else Vector3.ZERO))
		var gp = NavigationServer3D.map_get_path(battle.get_ground_nav_map(), unit.global_position, destination, true)
		print("path on GROUND map: size=", gp.size())
	battle.orders.move([unit], destination)

	# Horizontal distance only. On world_scale'd maps the ground plane sits
	# tens of metres below y=0, so a 3D distance_to() never converges even for
	# a unit parked exactly on the destination (the false FAIL this probe used
	# to report).
	var flat_dist := func(p: Vector3) -> float:
		return Vector2(p.x - destination.x, p.z - destination.z).length()
	var start_dist: float = flat_dist.call(unit.global_position)
	var best: float = start_dist
	for tick in range(3000):
		await process_frame
		var d: float = flat_dist.call(unit.global_position)
		best = min(best, d)
		if tick % 500 == 0:
			var st = -1
			if unit.harvester != null:
				st = unit.harvester.state
			var nc = Vector3.ZERO
			if is_instance_valid(unit.nav_agent):
				nc = unit.nav_agent.get_next_path_position()
			print("  tick ", tick, " pos=", unit.global_position, " dist=", d,
				" order=", (unit.current_order.type if unit.current_order != null else -1),
				" fsm_state=", st, " internal_dest=", unit._has_internal_destination,
				" vel=", unit.velocity, " next_corner=", nc,
				" is_harv=", unit.is_harvester)
		if d < 12.0:
			break

	var progress: float = (start_dist - best) / max(start_dist, 0.001) * 100.0
	print("start_dist=", start_dist, " best=", best, " progress=", progress, "%")
	print("RESULT: ", ("PASS" if progress > 60.0 else "FAIL - unit did not converge"))
	quit(0)


func _ground_blueprint(_battle) -> Dictionary:
	var dir := DirAccess.open("res://data/loadout")
	if dir == null:
		return {}
	# Preferred: an ore hauler (the original probe subject). The roster has
	# renamed/re-balanced these more than once, so fall back to ANY ground
	# wheels design rather than failing the probe on naming drift. NOT a
	# harvester though - the harvester FSM overrides move orders, which makes
	# the convergence test meaningless (magpie_ore_hauler taught us that).
	var fallback := {}
	var harvester_fallback := {}
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("res://data/loadout/" + file)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var loco = parsed.get("locomotion", {})
		var type_id: String = str(loco.get("type_id", "")) if typeof(loco) == TYPE_DICTIONARY else str(loco)
		if type_id != "wheels":
			continue
		var is_harvester := false
		var modules = parsed.get("modules", [])
		if modules is Array:
			for m in modules:
				if m is Dictionary and str(m.get("type_id", "")) == "resource_harvester":
					is_harvester = true
					break
		if file.begins_with("ore_"):
			print("using blueprint ", file, " locomotion=", type_id)
			return parsed
		if fallback.is_empty() and not is_harvester:
			fallback = parsed
			print("fallback blueprint candidate ", file, " locomotion=", type_id)
		if harvester_fallback.is_empty() and is_harvester:
			harvester_fallback = parsed
	return fallback if not fallback.is_empty() else harvester_fallback
