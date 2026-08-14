extends SceneTree

# What does the sync/async agent_radius split actually cost?
#
# terrain_builder.gd bakes the SAME surfaces at NAV_AGENT_RADIUS (1.0) from the
# synchronous path and at 0.1 from both async paths. The async paths are the
# ones production uses - initial load AND mid-match rebake - so the shipping
# game has been pathing on a navmesh the test suite never bakes.
#
# Recast quantises the radius to whole cell_size voxels, so the two only differ
# where cell_size < 1.0 (there 1.0 becomes 2 voxels and 0.1 stays 1). This
# reports, per map and surface, whether that is a real difference or a no-op.
#
# Run:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script tools/probe_agent_radius_effect.gd --quit

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TB = preload("res://scripts/terrain_builder.gd")


func _bake(verts: PackedVector3Array, cell_size: float, agent_radius: float) -> NavigationMesh:
	var nm := NavigationMesh.new()
	TB._configure_nav_mesh(nm, cell_size, agent_radius)
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(verts, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	return nm


# Polygon COUNT is too coarse to answer this: eroding the walkable outline
# inward by a voxel shrinks the mesh without necessarily adding or removing a
# single polygon. Summed triangle area is what actually captures erosion.
func _walkable_area(nm: NavigationMesh) -> float:
	var verts: PackedVector3Array = nm.get_vertices()
	var area := 0.0
	for i in range(nm.get_polygon_count()):
		var poly: PackedInt32Array = nm.get_polygon(i)
		for k in range(1, poly.size() - 1):
			var a: Vector3 = verts[poly[0]]
			var b: Vector3 = verts[poly[k]]
			var c: Vector3 = verts[poly[k + 1]]
			area += (b - a).cross(c - a).length() * 0.5
	return area


func _init() -> void:
	var differing := 0
	var total := 0
	print("%-32s %-9s %-6s %-6s %-11s %-9s %s" % ["map/surface", "cell_sz", "vox1.0", "vox0.1", "polys", "area@1.0", "verdict"])
	for id in MapCatalogScript.get_map_ids():
		var m: Dictionary = MapCatalogScript.get_map(id)
		if m.is_empty():
			continue
		var tile_cs: float = TB._nav_tile_cell_size(m)
		for entry in [["ground", TB._build_ground_faces(m, []), tile_cs],
					  ["amphibious", TB._build_amphibious_faces(m, []), tile_cs]]:
			var verts: PackedVector3Array = entry[1]
			if verts.is_empty():
				continue
			var cs: float = entry[2]
			var a := _bake(verts, cs, TB.NAV_AGENT_RADIUS)
			var b := _bake(verts, cs, 0.1)
			var vox_a: int = int(ceil(TB.NAV_AGENT_RADIUS / cs))
			var vox_b: int = int(ceil(0.1 / cs))
			var area_a := _walkable_area(a)
			var area_b := _walkable_area(b)
			var delta_pct: float = 0.0 if area_b == 0.0 else (area_a - area_b) / area_b * 100.0
			var same: bool = absf(delta_pct) < 0.01
			total += 1
			if not same:
				differing += 1
			print("%-32s %-9.3f %-6d %-6d %-11s %-9.1f %s" % [
				"%s %s" % [id, entry[0]], cs, vox_a, vox_b,
				"%d/%d" % [a.get_polygon_count(), b.get_polygon_count()],
				area_a, "same" if same else "area %+.2f%%" % delta_pct])
	print("")
	print("%d of %d surfaces change when the async paths are corrected to NAV_AGENT_RADIUS" % [differing, total])
	quit()
