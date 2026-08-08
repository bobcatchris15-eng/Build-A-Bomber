extends SceneTree
# Checks terrain height/slope/blocked-state directly around a compacted
# spawn cluster (post building-spacing fix) vs. open ground, to test
# whether the navigation deadlock near real bases is a slope/elevation
# problem specifically.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_spawn_terrain.gd

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")


func _init():
	var map_def = MapCatalogScript.get_map("open_plains")
	var player_spawn = MapCatalogScript.get_spawn(map_def, "player")
	print("Compacted spawn positions: hq=", player_spawn.hq, " factory=", player_spawn.factory,
		" refinery=", player_spawn.refinery, " harvester=", player_spawn.harvester)

	var points = {
		"hq": player_spawn.hq,
		"factory": player_spawn.factory,
		"refinery": player_spawn.refinery,
		"harvester": player_spawn.harvester,
		"midpoint_hq_harvester": (player_spawn.hq + player_spawn.harvester) / 2.0,
		"open_ground_far": Vector3(0, 0, 0),
	}
	for label in points:
		var p: Vector3 = points[label]
		var h = TerrainBuilderScript.height_at(map_def, p.x, p.z)
		var slope = TerrainBuilderScript._slope_at(map_def, p.x, p.z)
		var blocked = TerrainBuilderScript.is_position_blocked(map_def, Vector3(p.x, 0, p.z))
		print(label, " @ ", p, " -> height=", h, " slope=", slope,
			" MAX_WALKABLE_SLOPE=", TerrainBuilderScript.MAX_WALKABLE_SLOPE, " blocked=", blocked)

	# Sample a fine grid around the harvester spawn to see if it's a genuine
	# local hole or just this one point.
	print("--- fine grid around harvester spawn ---")
	var centre: Vector3 = player_spawn.harvester
	for dz in range(-6, 7, 2):
		var row := ""
		for dx in range(-6, 7, 2):
			var p = Vector3(centre.x + dx, 0, centre.z + dz)
			var blocked = TerrainBuilderScript.is_position_blocked(map_def, p)
			row += ("#" if blocked else ".")
		print(row)

	quit(0)
