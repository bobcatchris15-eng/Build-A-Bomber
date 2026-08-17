extends SceneTree
# Standalone test that exercises the full _measure_hull_facet +
# _build_facet_polygon_mesh pipeline against a synthetic box hull with
# a known geometry. The previous run of the polygon mesh showed the
# plate "much too large, rotated 90 degrees" in the live editor; this
# script checks the math directly so we can see whether the issue is
# in the measurement, the basis convention, or the mesh construction.
#
# USAGE
#   godot --headless --path prototype --script tests/test_facet_polygon_visual.gd

const ModulePlacerScript = preload("res://scripts/module_placer.gd")


func _init() -> void:
	var ok := _run()
	if ok:
		print("PASS facet_polygon_visual: all assertions held.")
		quit(0)
	else:
		print("FAIL facet_polygon_visual: see assertions above.")
		quit(1)


func _run() -> bool:
	# Build a simple 4m x 1.4m x 2.5m box hull. The top facet is the
	# 4m (X) by 2.5m (Z) face; a click at the centre of the top should
	# produce a polygon mesh that lies flat, 4m wide and 2.5m deep, with
	# 0.2m of thickness in Y.
	var hull := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 1.4, 2.5)
	mi.mesh = box
	hull.add_child(mi)
	# hull's MeshInstance3D is at hull-local origin, so mesh verts are
	# already in hull-local space.

	# Simulate a click at the centre of the TOP facet.
	var click_pos := Vector3(0, 0.7, 0)  # top face centre (hull-local)
	var click_normal := Vector3(0, 1, 0)  # UP
	var basis_for_top := Basis.IDENTITY   # what _align_up_to(UP) returns

	# Measure
	var meas: Dictionary = ModulePlacerScript._measure_hull_facet(
		hull, click_pos, click_normal, basis_for_top)

	print("  size   = ", meas.get("size"))
	print("  center = ", meas.get("center"))
	print("  valid  = ", meas.get("valid"))
	print("  outline verts = ", (meas.get("outline", PackedVector2Array()) as PackedVector2Array).size())

	# Debug: dump triangle normals to see whether the BoxMesh winding
	# is CCW (outward normals) or CW (inward). The existing code matches
	# triangles whose normal has abs(dot(norm)) > 0.90, so the winding
	# matters.
	var faces_debug: PackedVector3Array = mi.mesh.get_faces()
	print("  total faces = ", faces_debug.size() / 3)
	var matched_count := 0
	for i in range(faces_debug.size() / 3):
		var v0d = faces_debug[i * 3 + 0]
		var v1d = faces_debug[i * 3 + 1]
		var v2d = faces_debug[i * 3 + 2]
		var tri_nd: Vector3 = (v1d - v0d).cross(v2d - v0d)
		if tri_nd.length_squared() < 1e-8:
			continue
		tri_nd = tri_nd.normalized()
		var d: float = tri_nd.dot(click_normal)
		if i < 12:
			print("  tri ", i, " normal=", tri_nd, " dot=", d)
		if absf(d) > 0.90:
			matched_count += 1
	print("  matched ", matched_count, " tris")

	# Hard checks
	if not meas.get("valid", false):
		print("  [FAIL] measurement not valid for top-facet click")
		return false
	# Expected bbox: 4m x 2.5m (with the 0.1 / 0.1 chamfer margin from the
	# matching code's `< 0.20` plane-distance check pulling in some side
	# triangles if the box has any, but a pure BoxMesh has no such
	# triangles - so the size should be exactly the top facet).
	var size: Vector3 = meas.get("size", Vector3.ZERO)
	if absf(size.x - 4.0) > 0.05 or absf(size.z - 2.5) > 0.05:
		print("  [FAIL] expected size (~4.0, 0, ~2.5), got ", size)
		return false

	# Build polygon mesh and inspect AABB
	var outline: PackedVector2Array = meas.get("outline", PackedVector2Array())
	if outline.size() < 3:
		print("  [FAIL] outline has ", outline.size(), " verts; need >= 3")
		return false
	var thickness: float = 0.2
	var mesh: ArrayMesh = ModulePlacerScript._build_facet_polygon_mesh(outline, thickness)
	if mesh == null:
		print("  [FAIL] polygon mesh build returned null")
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	print("  mesh AABB: lo=", lo, " hi=", hi)
	print("  mesh size: ", hi - lo)
	# Mesh is built in the new_weapon's LOCAL frame. For a top facet the
	# local frame IS world / hull-local, so the mesh AABB should be:
	#   X: -2.0 .. +2.0   (4m wide along the facet's "bx" / world X)
	#   Y:  0.0 .. +0.2   (thickness along the normal / world Y)
	#   Z: -1.25 .. +1.25 (2.5m deep along the facet's "bz" / world Z)
	if absf(lo.x - -2.0) > 0.05 or absf(hi.x - 2.0) > 0.05:
		print("  [FAIL] mesh X extent unexpected")
		return false
	if absf(lo.y - 0.0) > 0.001 or absf(hi.y - 0.2) > 0.001:
		print("  [FAIL] mesh Y extent (thickness) unexpected: ", lo.y, " .. ", hi.y)
		return false
	if absf(lo.z - -1.25) > 0.05 or absf(hi.z - 1.25) > 0.05:
		print("  [FAIL] mesh Z extent unexpected")
		return false

	# Now place the new_weapon and verify the WORLD transform of the mesh
	# ends up flat on the top of the box hull.
	var new_weapon := Node3D.new()
	new_weapon.transform.basis = basis_for_top
	new_weapon.position = meas.get("center", click_pos)
	new_weapon.scale = Vector3.ONE
	var mi2 := MeshInstance3D.new()
	mi2.mesh = mesh
	new_weapon.add_child(mi2)
	hull.add_child(new_weapon)

	# Compute the world AABB of the mesh.
	var world_lo := Vector3(INF, INF, INF)
	var world_hi := Vector3(-INF, -INF, -INF)
	var xform: Transform3D = mi2.global_transform
	for v in verts:
		var w := xform * v
		world_lo = world_lo.min(w)
		world_hi = world_hi.max(w)
	print("  world AABB: lo=", world_lo, " hi=", world_hi)
	# For the top facet, expected world AABB (since basis is IDENTITY):
	#   X: -2.0 .. +2.0
	#   Y:  0.7 ..  0.9   (click_pos.y + 0 .. +thickness)
	#   Z: -1.25 .. +1.25
	if absf(world_lo.y - 0.7) > 0.05 or absf(world_hi.y - 0.9) > 0.05:
		print("  [FAIL] world Y extent not flat-on-top: ", world_lo.y, " .. ", world_hi.y)
		return false
	if absf(world_lo.x - -2.0) > 0.05 or absf(world_hi.x - 2.0) > 0.05:
		print("  [FAIL] world X extent not 4m")
		return false
	if absf(world_lo.z - -1.25) > 0.05 or absf(world_hi.z - 1.25) > 0.05:
		print("  [FAIL] world Z extent not 2.5m")
		return false

	hull.queue_free()
	return true
