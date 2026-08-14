extends SceneTree

# A/B test for the agent_radius / agent_max_climb voxel-warning fix.
#
# For every bundled map, bakes the SAME source geometry twice:
#   RAW     - the pre-fix parameters, set verbatim (warns every bake)
#   SNAPPED - through TerrainBuilder._configure_nav_mesh() (the fix)
# and compares polygon and vertex counts.
#
# The fix's whole claim is that passing the already-quantised value changes
# nothing, because Recast quantises to the same integer voxel counts itself.
# Equal counts on every surface of every map is that claim checked rather
# than asserted. Any inequality means the snap moved a voxel and the
# clearance argument in _configure_nav_mesh()'s comment is wrong.
#
# Run:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script tools/probe_nav_warning_silence.gd --quit

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TB = preload("res://scripts/terrain_builder.gd")


func _bake_raw(verts: PackedVector3Array, cell_size: float, agent_radius: float) -> NavigationMesh:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = cell_size
	nav_mesh.cell_height = TB.NAV_CELL_HEIGHT
	nav_mesh.agent_max_climb = cell_size * TB.AGENT_MAX_CLIMB_CELLS
	nav_mesh.agent_radius = agent_radius
	var source := NavigationMeshSourceGeometryData3D.new()
	source.add_faces(verts, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	return nav_mesh


func _bake_snapped(verts: PackedVector3Array, cell_size: float, agent_radius: float) -> NavigationMesh:
	var nav_mesh := NavigationMesh.new()
	TB._configure_nav_mesh(nav_mesh, cell_size, agent_radius)
	var source := NavigationMeshSourceGeometryData3D.new()
	source.add_faces(verts, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	return nav_mesh


func _compare(label: String, verts: PackedVector3Array, cell_size: float, agent_radius: float) -> bool:
	# Most maps author no deep water at all. Baking an empty face array is a
	# no-op that still trips the engine's own "Condition p_faces.is_empty()"
	# error, which would read as a probe failure rather than "this map has no
	# deep water" - so skip it rather than print two ERRORs per surface.
	if verts.is_empty():
		print("%-46s cs=%-7.4f r=%-5.2f (no source geometry - skipped)" % [label, cell_size, agent_radius])
		return true
	var raw := _bake_raw(verts, cell_size, agent_radius)
	var snapped := _bake_snapped(verts, cell_size, agent_radius)
	var same: bool = (raw.get_polygon_count() == snapped.get_polygon_count()
		and raw.get_vertices().size() == snapped.get_vertices().size())
	print("%-46s cs=%-7.4f r=%-5.2f raw=%d/%d snapped=%d/%d  %s" % [
		label, cell_size, agent_radius,
		raw.get_polygon_count(), raw.get_vertices().size(),
		snapped.get_polygon_count(), snapped.get_vertices().size(),
		"same" if same else "*** DIFFERS ***"])
	return same


func _init() -> void:
	var all_same := true
	var checked := 0
	for id in MapCatalogScript.get_map_ids():
		var map_def: Dictionary = MapCatalogScript.get_map(id)
		if map_def.is_empty():
			print("%s SKIPPED (failed to load)" % id)
			continue
		var tile_cs: float = TB._nav_tile_cell_size(map_def)
		var open_cs: float = TB._nav_cell_size(map_def)
		# The sync path bakes at NAV_AGENT_RADIUS; both async paths at 0.1.
		# Cover both, since they quantise differently.
		for r in [TB.NAV_AGENT_RADIUS, 0.1]:
			all_same = _compare("%s ground" % id, TB._build_ground_faces(map_def, []), tile_cs, r) and all_same
			all_same = _compare("%s amphibious" % id, TB._build_amphibious_faces(map_def, []), tile_cs, r) and all_same
			all_same = _compare("%s deep_water" % id, TB._build_deep_water_faces(map_def), open_cs, r) and all_same
			checked += 3

	print("")
	print("%d bakes compared -> %s" % [checked, "ALL IDENTICAL" if all_same else "*** GEOMETRY CHANGED ***"])
	quit(0 if all_same else 1)
