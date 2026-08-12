# Reads a .glb through Godot's REAL glTF importer (GLTFDocument, so no
# .godot import cache is needed) and reports, per surface:
#   - where the surface landed in Godot space (AABB centre)
#   - whether its triangle WINDING faces outward (the thing backface culling
#     actually keys off) and whether the stored normals agree with it.
#
# Run:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script ../scratch/hull_probe/probe_read.gd -- <abs_path.glb>

extends SceneTree


func _init() -> void:
	var target := ""
	for a in OS.get_cmdline_user_args():
		if a.to_lower().ends_with(".glb"):
			target = a
	if target == "":
		print("PROBE-READ: no .glb argument")
		quit(1)
		return

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(target, state)
	if err != OK:
		print("PROBE-READ: append_from_file failed err=%d for %s" % [err, target])
		quit(1)
		return
	var scene := doc.generate_scene(state)
	if scene == null:
		print("PROBE-READ: generate_scene returned null")
		quit(1)
		return

	print("PROBE-READ file: %s" % target)
	_walk(scene, scene)
	quit(0)


func _walk(node: Node, root: Node) -> void:
	if node is MeshInstance3D:
		_report(node as MeshInstance3D, root)
	for c in node.get_children():
		_walk(c, root)


func _report(mi: MeshInstance3D, root: Node) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	var xform := _global_xform(mi, root)
	print("--- MeshInstance3D '%s'  node_xform_origin=%s  surfaces=%d" % [
		mi.name, xform.origin, mesh.get_surface_count()])
	print("    whole-mesh AABB: pos=%s size=%s" % [mesh.get_aabb().position, mesh.get_aabb().size])

	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()

		var mat := mesh.surface_get_material(s)
		var mat_name := "<null>" if mat == null else mat.resource_name

		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var centroid := Vector3.ZERO
		for v in verts:
			var w: Vector3 = xform * v
			lo = lo.min(w)
			hi = hi.max(w)
			centroid += w
		if verts.size() > 0:
			centroid /= float(verts.size())

		# Winding test. glTF/Godot are right-handed and CCW-front-facing, so
		# cross(v1-v0, v2-v0) points out of a correctly-wound closed surface.
		# Compare against (triangle centre - surface centroid): agreement means
		# the visible side is the outside; disagreement means inside out.
		var wind_out := 0
		var wind_in := 0
		var normal_out := 0
		var normal_in := 0
		var tri_count := indices.size() / 3
		for t in tri_count:
			var i0 := indices[t * 3]
			var i1 := indices[t * 3 + 1]
			var i2 := indices[t * 3 + 2]
			var p0: Vector3 = xform * verts[i0]
			var p1: Vector3 = xform * verts[i1]
			var p2: Vector3 = xform * verts[i2]
			var geo := (p1 - p0).cross(p2 - p0)
			if geo.length() < 1e-9:
				continue
			var tri_c := (p0 + p1 + p2) / 3.0
			var outward := tri_c - centroid
			if outward.length() < 1e-6:
				continue
			if geo.normalized().dot(outward.normalized()) > 0.0:
				wind_out += 1
			else:
				wind_in += 1
			if normals.size() > i0:
				var n: Vector3 = (xform.basis * normals[i0])
				if n.length() > 1e-9 and n.normalized().dot(outward.normalized()) > 0.0:
					normal_out += 1
				else:
					normal_in += 1

		var verdict := "OUTWARD-OK" if wind_in == 0 else ("INSIDE-OUT" if wind_out == 0 else "MIXED")
		print("    surf %d  mat=%-24s centre=(%7.3f,%7.3f,%7.3f) size=(%6.3f,%6.3f,%6.3f)" % [
			s, mat_name, (lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5,
			hi.x - lo.x, hi.y - lo.y, hi.z - lo.z])
		print("             winding: out=%d in=%d -> %s   |  normals: out=%d in=%d" % [
			wind_out, wind_in, verdict, normal_out, normal_in])


func _global_xform(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root.get_parent():
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
