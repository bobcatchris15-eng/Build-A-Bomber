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

	var destination := Vector3(0, 0, 0)
	battle.orders.move([unit], destination)

	var start_dist: float = unit.global_position.distance_to(destination)
	var best: float = start_dist
	for tick in range(3000):
		await process_frame
		var d: float = unit.global_position.distance_to(destination)
		best = min(best, d)
		if tick % 1000 == 0:
			print("  tick ", tick, " pos=", unit.global_position, " dist=", d)
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
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("res://data/loadout/" + file)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var loco = parsed.get("locomotion", {})
		var type_id: String = str(loco.get("type_id", "")) if typeof(loco) == TYPE_DICTIONARY else str(loco)
		if type_id in ["wheels", "tracked_treads", "half_track", "hover_engine"]:
			print("using blueprint ", file, " locomotion=", type_id)
			return parsed
	return {}
