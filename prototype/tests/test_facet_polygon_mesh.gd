extends SceneTree
# One-shot smoke test for module_placer._build_facet_polygon_mesh, added
# because the new facet-conforming armor visual was the first place the
# project called SurfaceTool.set_uv() and the first draft shipped with
# add_uv() (which does not exist in Godot 4.x). A missed test cost a
# live-editor crash; this file makes that mistake impossible to ship
# again.
#
# USAGE
#   godot --headless --path prototype --script tests/test_facet_polygon_mesh.gd
#
# Returns 0 on PASS, 1 on FAIL. Not registered with run_tests.gd because
# the rest of the suite's "_ready" lifecycle does not suit a raw
# SceneTree check; this script is its own complete runner.

const ModulePlacerScript = preload("res://scripts/module_placer.gd")


func _init() -> void:
	var ok := _run()
	if ok:
		print("PASS facet_polygon_mesh: all assertions held.")
		quit(0)
	else:
		print("FAIL facet_polygon_mesh: see assertions above.")
		quit(1)


func _run() -> bool:
	# Synthetic hexagon outline in the (bx, bz) tangent plane, centred at
	# the bounding-box midpoint (which is the frame the placer passes in).
	var outline := PackedVector2Array([
		Vector2( 0.50,  0.00),
		Vector2( 0.25,  0.43),
		Vector2(-0.25,  0.43),
		Vector2(-0.50,  0.00),
		Vector2(-0.25, -0.43),
		Vector2( 0.25, -0.43),
	])

	var mesh: ArrayMesh = ModulePlacerScript._build_facet_polygon_mesh(outline, 0.20)
	if mesh == null:
		print("  [FAIL] hexagon outline returned null mesh")
		return false

	# Surface count: 1 (the whole plate is one Surface).
	if mesh.get_surface_count() != 1:
		print("  [FAIL] expected 1 surface, got ", mesh.get_surface_count())
		return false

	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	# Mesh is non-indexed (SurfaceTool defaults to vertex soup; only
	# `surface_set_arrays_from_arrays()` or an explicit `st.index()` would
	# give us an index buffer). The check is "not null and not empty" on
	# the vertex array, not on indices.
	var indices_raw = arrays[Mesh.ARRAY_INDEX]
	var has_index_buffer := indices_raw != null and (indices_raw as PackedInt32Array).size() > 0

	# Vertex count expectation, with or without index buffer:
	#   24 triangles total: 6 top fan + 6 bottom fan + 12 side (2 per edge).
	#   Non-indexed: 24 * 3 = 72.
	#   Indexed: 24 * 3 = 72 distinct verts still possible if we never
	#     shared; SurfaceTool does not share by default, so the number is
	#     72 either way for this implementation.
	if verts.size() != 72:
		print("  [FAIL] expected 72 verts, got ", verts.size())
		return false
	# Sanity: 72 verts / 3 = 24 triangles, regardless of indexing.
	if (verts.size() / 3) != 24:
		print("  [FAIL] expected 24 triangles worth of verts, got ", verts.size() / 3)
		return false
	# Either an index buffer exists with positive size, or no index buffer
	# (raw vertex soup) - both are valid; reject only the broken third case
	# where the slot exists but is empty.
	if arrays[Mesh.ARRAY_INDEX] != null and not has_index_buffer:
		print("  [FAIL] index buffer slot exists but is empty")
		return false

	# UV expectation: every vertex carries an explicit UV. The top fan's
	# 18 verts use the bbox-relative UV (the read that matters visually).
	# The remaining 54 verts (bottom fan + sides) get an explicit (0,0)
	# rather than inheriting the last top-fan UV, because SurfaceTool's
	# set_uv() binding persists across add_vertex() calls and silently
	# pins everything after the top fan to the last bound texel otherwise.
	if uvs.size() != 72:
		print("  [FAIL] expected 72 explicit UVs, got ", uvs.size())
		return false
	# Top fan is the first 18 verts. The centroid's UV should be near the
	# centre of the bbox (0.5, 0.5), since the hexagon outline is centred.
	var centroid_uv: Vector2 = uvs[0]
	if centroid_uv.length() < 0.1 or centroid_uv.length() > 1.0:
		print("  [FAIL] centroid UV out of range (expected near (0.5,0.5)): ", centroid_uv)
		return false
	# Bottom + side UVs (indices 18..71) must be the explicit (0,0) clear.
	for i in range(18, 72):
		if uvs[i] != Vector2.ZERO:
			print("  [FAIL] UV at index ", i, " should be (0,0), got ", uvs[i])
			return false

	# Bounding box of the mesh: must span ±0.5 in X and Z, and exactly the
	# thickness 0..0.20 in Y. (Hex vertices are at radius 0.5.)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	if absf(lo.x - -0.5) > 0.01 or absf(hi.x - 0.5) > 0.01:
		print("  [FAIL] X extent out of range: ", lo, " to ", hi)
		return false
	if absf(lo.z - -0.43) > 0.01 or absf(hi.z - 0.43) > 0.01:
		print("  [FAIL] Z extent out of range: ", lo, " to ", hi)
		return false
	if absf(lo.y - 0.0) > 0.001 or absf(hi.y - 0.20) > 0.001:
		print("  [FAIL] Y extent out of range (expected 0..0.20): ", lo, " to ", hi)
		return false

	# Degenerate cases - these should be rejected, not crash.
	if ModulePlacerScript._build_facet_polygon_mesh(PackedVector2Array(), 0.2) != null:
		print("  [FAIL] empty outline should return null, didn't")
		return false
	if ModulePlacerScript._build_facet_polygon_mesh(outline, 0.0) != null:
		print("  [FAIL] zero thickness should return null, didn't")
		return false
	if ModulePlacerScript._build_facet_polygon_mesh(PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 0.0001)
	]), 0.2) != null:
		print("  [FAIL] degenerate (near-collinear) outline should return null, didn't")
		return false

	return true
