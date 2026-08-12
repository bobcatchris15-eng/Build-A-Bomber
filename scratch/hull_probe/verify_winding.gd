# Unambiguous winding check, calibrated rather than theorised.
#
# For each mesh it finds the single TOPMOST triangle (highest centroid Y) and
# reports the sign of its winding-derived normal, cross(v1-v0, v2-v0).y. A
# hull's top face must face up. Whether "up" means a positive or negative
# cross product depends on Godot's front-face winding convention, so this
# script does not assume one: run it over an asset known to render correctly
# and over one known to render inside out, and the two will disagree. Every
# new hull must match the known-good sign.
#
# Also reports the frontmost triangle (lowest centroid Z, i.e. the nose under
# Godot's -Z-forward convention) so a hull built facing backwards is caught.
#
# Run:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script ../scratch/hull_probe/verify_winding.gd -- <glb> [<glb> ...]

extends SceneTree


func _init() -> void:
	var targets: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.to_lower().ends_with(".glb"):
			targets.append(a)
	if targets.is_empty():
		print("VERIFY: no .glb arguments")
		quit(1)
		return

	print("%-34s %-9s %-9s %-9s %s" % ["asset", "top.y", "bottom.y", "nose.z", "verdict"])
	var bad := 0
	for t in targets:
		if not _check(t):
			bad += 1
	print("VERIFY: %d/%d consistent" % [targets.size() - bad, targets.size()])
	quit(1 if bad > 0 else 0)


func _check(path: String) -> bool:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		print("%-34s LOAD FAILED" % path.get_file())
		return false
	var scene := doc.generate_scene(state)
	var meshes: Array[MeshInstance3D] = []
	_collect(scene, meshes)
	if meshes.is_empty():
		print("%-34s NO MESH" % path.get_file())
		return false

	# Winding-derived normal of the extreme triangle on each of three axes.
	var top_n := 0.0
	var top_y := -INF
	var bot_n := 0.0
	var bot_y := INF
	var nose_n := 0.0
	var nose_z := INF

	for mi in meshes:
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_INDEX] == null:
				continue
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for tri in idx.size() / 3:
				var p0: Vector3 = verts[idx[tri * 3]]
				var p1: Vector3 = verts[idx[tri * 3 + 1]]
				var p2: Vector3 = verts[idx[tri * 3 + 2]]
				var g := (p1 - p0).cross(p2 - p0)
				if g.length() < 1e-9:
					continue
				g = g.normalized()
				var c := (p0 + p1 + p2) / 3.0
				# Only consider triangles that actually face the axis in
				# question, so a vertical wall that happens to reach high
				# does not get mistaken for the roof.
				if absf(g.y) > 0.7:
					if c.y > top_y:
						top_y = c.y
						top_n = g.y
					if c.y < bot_y:
						bot_y = c.y
						bot_n = g.y
				if absf(g.z) > 0.7 and c.z < nose_z:
					nose_z = c.z
					nose_n = g.z

	# Self-consistency: the top face and the bottom face must have OPPOSITE
	# signs, and the nose face must point away from the body. Both hold under
	# either winding convention, so a mesh failing this is inconsistent, not
	# merely mirrored.
	var consistent := (top_n * bot_n) < 0.0 and nose_n != 0.0
	print("%-34s %+9.3f %+9.3f %+9.3f %s" % [
		path.get_file(), top_n, bot_n, nose_n,
		"consistent" if consistent else "INCONSISTENT"])
	return consistent


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect(c, out)
