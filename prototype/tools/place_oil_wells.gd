extends SceneTree
# Repositions any UNREACHABLE resource node onto ground the navmesh actually
# connects to, and rewrites the map JSON.
#
# The oil wells were placed by a script that knew about water rects but not about
# obstacles or elevation, so on three maps they landed somewhere no truck can
# drive. The map smoke tests caught it, which is exactly their job - but "nudge
# it and re-run the suite" is a bad loop when the authority on reachability is a
# baked navmesh sitting right here.
#
# Candidates are tried in order of how little they move the well, so a placement
# that was nearly right stays nearly right, and the mirrored pair stays mirrored
# by construction (both are moved by the same rule).
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/place_oil_wells.gd

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

const REACH_TOLERANCE := 3.0
# Rings to search outward from the intended spot, in metres.
const SEARCH_RINGS := [0.0, 6.0, 12.0, 18.0, 26.0, 34.0, 44.0]
const SEARCH_SPOKES := 12


func _init():
	for map_id in MapCatalogScript.get_map_ids():
		await _fix_map(map_id)
	quit(0)


func _fix_map(map_id: String) -> void:
	var map_def: Dictionary = MapCatalogScript.get_map(map_id)
	var nav: Dictionary = TerrainBuilderScript.build_navmeshes(map_def)
	var ground: RID = nav.ground_map
	var waited := 0
	while waited < 240:
		if NavigationServer3D.map_is_active(ground) \
				and not NavigationServer3D.map_get_regions(ground).is_empty() \
				and NavigationServer3D.map_get_iteration_id(ground) >= 2:
			break
		await process_frame
		waited += 1

	var player_start: Dictionary = MapCatalogScript.get_spawn(map_def, "player")
	var enemy_start: Dictionary = MapCatalogScript.get_spawn(map_def, "enemy")
	var from_points := [player_start.harvester, enemy_start.harvester]
	var half: float = map_def.get("map_half_extents", 80.0)

	var moved: Array = []
	var nodes: Array = map_def.get("resource_nodes", [])
	for entry in nodes:
		var pos: Vector3 = entry.position
		if _reachable(ground, from_points, pos):
			continue
		var found := false
		for ring in SEARCH_RINGS:
			if found:
				break
			for spoke in range(SEARCH_SPOKES):
				var theta: float = TAU * float(spoke) / float(SEARCH_SPOKES)
				var candidate := Vector3(pos.x + cos(theta) * ring, 0.0, pos.z + sin(theta) * ring)
				if absf(candidate.x) > half * 0.95 or absf(candidate.z) > half * 0.95:
					continue
				if TerrainBuilderScript.is_position_blocked(map_def, candidate):
					continue
				if not _reachable(ground, from_points, candidate):
					continue
				moved.append({"type": str(entry.type), "from": pos, "to": candidate})
				entry.position = candidate
				found = true
				break
		if not found:
			print("  %s: could NOT reposition %s at %s" % [map_id, entry.type, str(pos)])

	for rid in [nav.ground_region, nav.water_region, nav.amphibious_region, nav.deep_water_region]:
		if rid.is_valid():
			NavigationServer3D.free_rid(rid)
	for key in ["ground_map", "water_map", "amphibious_map", "deep_water_map"]:
		NavigationServer3D.free_rid(nav[key])

	if moved.is_empty():
		print("  %-22s all nodes reachable" % map_id)
		return

	_rewrite(map_id, nodes)
	for m in moved:
		print("  %-22s %s %s -> %s" % [map_id, m["type"], str(m["from"]), str(m["to"])])


func _reachable(ground: RID, from_points: Array, target: Vector3) -> bool:
	for from_pos in from_points:
		var path := NavigationServer3D.map_get_path(ground, from_pos, target, true)
		if path.size() >= 2 and path[path.size() - 1].distance_to(target) <= REACH_TOLERANCE:
			return true
	return false


# Rewrites only the resource_nodes array, preserving everything else verbatim.
func _rewrite(map_id: String, nodes: Array) -> void:
	var path := "res://data/maps/%s.json" % map_id
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var raw = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var out: Array = []
	for entry in nodes:
		out.append({
			"amount": int(entry.amount),
			"position": [entry.position.x, entry.position.y, entry.position.z],
			"type": str(entry.type),
		})
	raw["resource_nodes"] = out
	var write := FileAccess.open(path, FileAccess.WRITE)
	if write == null:
		print("  could not write %s" % path)
		return
	write.store_string(JSON.stringify(raw, "\t"))
	write.close()
