extends SceneTree
# Scratch: _bake_nav_mesh() costs ~1.5s per surface (probe_navmesh_cost.gd),
# and rebake_ground_and_amphibious() runs TWO of them on every building
# placement - a 3.2s main-thread freeze.
#
# The cause is resolution, not geometry: _nav_cell_size() returns 0.25 for
# any map with half_extents <= 300, so lake_crossing (480m across) bakes a
# ~1920 x 1920 Recast grid. Recast cost is O(cells), i.e. quadratic in
# 1/cell_size.
#
# This sweeps cell_size to find what the bake actually costs at each
# resolution, and reports the resulting polygon count as a proxy for whether
# pathing detail survives. RTS ground units here are metres wide, so 0.25m
# cells resolve detail no unit can use.
#
# Usage: ./godot.exe --script scratch/probe_nav_cell_size.gd --path .

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")

func _init():
	for map_id in ["lake_crossing", "highland_chokepoint"]:
		var map = MapCatalog.get_map(map_id)
		var half: float = map.get("map_half_extents", 80.0)
		print("=== %s (%.0fm across, current cell_size %.2f) ==="
			% [map_id, half * 2.0, TerrainBuilder._nav_cell_size(map)])
		var holes = [{"center": Vector3(0, 0, 0), "half_extents": Vector2(3, 3)}]
		var verts = TerrainBuilder._build_ground_faces(map, holes)
		print("  %-10s %10s %12s %10s" % ["cell_size", "grid", "bake ms", "nav polys"])
		for cs in [0.25, 0.5, 1.0, 1.5, 2.0]:
			var t = Time.get_ticks_usec()
			var nm = TerrainBuilder._bake_nav_mesh(verts, cs)
			var ms: float = (Time.get_ticks_usec() - t) / 1000.0
			var cells: int = int(half * 2.0 / cs)
			print("  %-10.2f %10s %9.1f ms %10d" % [cs, "%dx%d" % [cells, cells], ms, nm.get_polygon_count()])
		print("")
	quit(0)
