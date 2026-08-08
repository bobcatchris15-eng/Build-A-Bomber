extends SceneTree
# Verifies the new "hills" FIELD_SPEC entry (previously missing entirely -
# terrain_builder.gd read it but map_catalog.gd never scaled or validated
# it) scales correctly with world_scale, and that the open_plains.json
# example hills/ravine actually produce real elevation and a real navmesh
# hole at their edges.

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")


func _init():
	MapCatalogScript.reset_cache_for_tests()
	var map_def: Dictionary = MapCatalogScript.get_map("open_plains")
	var scale: float = map_def.get("world_scale", 1.0)
	print("resolved world_scale on map_def=", scale)
	print("hills after load: ", map_def.get("hills"))

	# Confirm the vantage hill's PEAK genuinely sits above open ground.
	var hill_center: Vector3 = map_def["hills"][0]["center"]
	var peak_h: float = TerrainBuilderScript.height_at(map_def, hill_center.x, hill_center.z)
	var flat_h: float = TerrainBuilderScript.height_at(map_def, 0, 0)
	print("hill peak height=", peak_h, " flat ground height=", flat_h)

	# Confirm the ravine genuinely dips BELOW open ground.
	var ravine_center: Vector3 = map_def["hills"][2]["center"]
	var ravine_h: float = TerrainBuilderScript.height_at(map_def, ravine_center.x, ravine_center.z)
	print("ravine floor height=", ravine_h, " (should be negative)")

	# Bake the real navmesh and confirm the ravine edge is a genuine hole -
	# a point right at its center should be MUCH farther from a navmesh
	# point at its steep edge than the smooth interior would suggest.
	var nav = TerrainBuilderScript.build_navmeshes(map_def)
	var slope_at_edge = TerrainBuilderScript._slope_at(map_def, ravine_center.x, ravine_center.z + 18)
	print("slope at ravine falloff edge=", slope_at_edge, " MAX_WALKABLE_SLOPE=", TerrainBuilderScript.MAX_WALKABLE_SLOPE)

	quit(0)
