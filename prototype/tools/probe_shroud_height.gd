extends SceneTree
# Does the fog shroud plane clear the terrain on every bundled map? Ground
# above the plane renders straight through the fog, which is what produced
# the elevation-shaped "already revealed" patches.
const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

func _init():
	for id in MapCatalogScript.get_map_ids():
		var map_def = MapCatalogScript.get_map(id)
		var bound = TerrainBuilderScript.max_height(map_def)
		var half = map_def.get("map_half_extents", 80.0)
		# Sample the real terrain to confirm the bound is genuinely a bound.
		var peak := -1e9
		for i in range(40):
			for j in range(40):
				var x = -half + (i / 39.0) * half * 2.0
				var z = -half + (j / 39.0) * half * 2.0
				peak = max(peak, TerrainBuilderScript.height_at(map_def, x, z))
		var plane = bound + 0.4
		print(id, " half=", half, " bound=", bound, " sampled_peak=", peak,
			" shroud_plane=", plane,
			("  <<< TERRAIN THROUGH SHROUD" if peak > plane else "  ok"))
	quit(0)
