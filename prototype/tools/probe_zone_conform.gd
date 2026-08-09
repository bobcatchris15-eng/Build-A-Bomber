extends SceneTree
# Verifies surface-zone dressing meshes now FOLLOW the terrain instead of
# sitting on one flat plane at y=0.03 (playtest item #7a). The check that
# matters: every zone mesh vertex should sit ZONE_Y_LIFT above the real
# height_at() at its own (x, z) - which also means the mesh has real Y spread
# wherever the terrain does.

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")


func _init():
	MapCatalogScript.reset_cache_for_tests()
	for map_id in ["open_plains", "lake_crossing"]:
		var map_def: Dictionary = MapCatalogScript.get_map(map_id)
		var zones: Array = map_def.get("surface_zones", [])
		print("--- ", map_id, " (", zones.size(), " surface zones) ---")
		for zone in zones:
			var mesh := TerrainBuilderScript._build_conforming_zone_mesh(
				map_def, zone.center, zone.half_extents,
				TerrainBuilderScript.ZONE_Y_LIFT, 1.0)
			var arrays: Array = mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var min_y := INF
			var max_y := -INF
			var worst := 0.0
			# Edge fade (#7b): a vertex ON the footprint boundary must be fully
			# transparent, and the zone's interior must still be fully opaque -
			# a fade that never reaches either end is not a fade.
			var edge_alpha := -1.0
			var center_alpha := -1.0
			for i in range(verts.size()):
				var v: Vector3 = verts[i]
				min_y = minf(min_y, v.y)
				max_y = maxf(max_y, v.y)
				var want: float = TerrainBuilderScript.height_at(map_def, v.x, v.z) + TerrainBuilderScript.ZONE_Y_LIFT
				worst = maxf(worst, absf(v.y - want))
				var dx: float = absf(v.x - zone.center.x) / zone.half_extents.x
				var dz: float = absf(v.z - zone.center.z) / zone.half_extents.y
				var a: float = colors[i].a if i < colors.size() else -1.0
				if maxf(dx, dz) > 0.999:
					edge_alpha = maxf(edge_alpha, a)
				if maxf(dx, dz) < 0.5:
					center_alpha = maxf(center_alpha, a) if center_alpha < 0.0 else minf(center_alpha, a)
			print("  ", zone.get("surface_type", "?"), " verts=", verts.size(),
				" y_range=", "%.2f..%.2f" % [min_y, max_y],
				" (spread %.2f)" % (max_y - min_y),
				" max_deviation=", "%.6f" % worst,
				" | alpha at edge=%.3f interior=%.3f" % [edge_alpha, center_alpha])
	quit(0)
