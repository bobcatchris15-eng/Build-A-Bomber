extends SceneTree
# Sweeps every bundled map for the "sits still and circles" navigation
# deadlock at the current DEFAULT_WORLD_SCALE, since the agent_max_climb fix
# was only verified against open_plains (flat, noise-only terrain) and the
# 2026-08-08 playtest still reproduced the bug after that fix landed -
# heightmap-backed maps (highland_chokepoint, scattered_peaks, twin_summits)
# are a genuinely different elevation code path and untested by that fix.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_nav_scale_all_maps.gd

const UnitScript = preload("res://scripts/battle/units/unit.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const OrderScript = preload("res://scripts/battle/orders/order.gd")
const MapCatalogScript = preload("res://scripts/map_catalog.gd")

const MAPS := [
	"open_plains", "lake_crossing", "highland_chokepoint", "coastal_strand",
	"twin_bridges", "twin_summits", "urban_sprawl", "scattered_peaks",
	"ore_basin", "close_quarters",
]


func _find_ground_design(battle) -> Dictionary:
	for design in battle.roster:
		if battle.is_defence_design(design):
			continue
		for module in design.get("modules", []):
			if str(module.get("type_id", "")) == "resource_harvester":
				return design
	return {}


func _test_map(map_id: String) -> void:
	var packed = load("res://scenes/Battle.tscn")
	var battle = packed.instantiate()
	battle.map_id = map_id
	root.add_child(battle)

	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	if not battle.world_is_ready:
		print(map_id, ": [FAIL] Battle never finished building")
		battle.queue_free()
		return
	for _i in range(30):
		await process_frame

	var bp_manager = BlueprintManagerScript.new()
	root.add_child(bp_manager)
	var unit = UnitScript.new()
	root.add_child(unit)
	var blueprint := _find_ground_design(battle)
	if blueprint.is_empty():
		print(map_id, ": [SKIP] no ground/harvester design in roster")
		bp_manager.queue_free()
		unit.queue_free()
		battle.queue_free()
		return
	var ok: bool = unit.setup(blueprint, 0, bp_manager, battle)
	if not ok or not is_instance_valid(unit.nav_agent):
		print(map_id, ": [SKIP] unit setup failed or no nav_agent")
		bp_manager.queue_free()
		unit.queue_free()
		battle.queue_free()
		return

	# Two spawn HQs as start/destination - always legal, always far apart,
	# no map-specific coordinate guessing needed.
	var map_def = MapCatalogScript.get_map(map_id)
	var player_spawn = MapCatalogScript.get_spawn(map_def, "player")
	var enemy_spawn = MapCatalogScript.get_spawn(map_def, "enemy")
	var start: Vector3 = player_spawn.harvester
	var destination: Vector3 = enemy_spawn.harvester
	unit.global_position = start
	for _i in range(10):
		await process_frame
	unit.current_order = OrderScript.move(destination)

	var initial_distance := Vector3(start.x, 0, start.z).distance_to(Vector3(destination.x, 0, destination.z))
	var closest := initial_distance
	for i in range(1800): # 30s
		await physics_frame
		var d := Vector3(unit.global_position.x, 0, unit.global_position.z).distance_to(Vector3(destination.x, 0, destination.z))
		closest = minf(closest, d)
		if d < 8.0:
			break

	var progress := initial_distance - closest
	var verdict := "PASS" if progress > initial_distance * 0.5 else "FAIL"
	print(map_id, ": [", verdict, "] progress=", progress, " / ", initial_distance,
		" (", int(100.0 * progress / initial_distance) if initial_distance > 0 else 0, "%)")

	bp_manager.queue_free()
	unit.queue_free()
	battle.queue_free()
	await process_frame


func _init():
	for map_id in MAPS:
		await _test_map(map_id)
	quit(0)
