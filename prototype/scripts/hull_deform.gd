class_name HullDeform
# MOUNTING_AND_ARMOR_SPEC.md #4: per-hull-type custom deform. This is a
# proof-of-concept for interceptor_hull only (see DECISIONS_NEEDED.md for
# why the other 6 hulls are deferred, not attempted here). Uses
# MeshDataTool to reshape just the nose region of the ACTUAL authored mesh
# independently of the uniform hull-scale handles - genuine regional
# deformation (Spore-style: a handle reshapes one section differently),
# not a swap between preset shapes or a second mesh layered on top.

static func apply_nose_taper(source_mesh: Mesh, taper_amount: float) -> Mesh:
	if not source_mesh:
		return source_mesh
	if abs(taper_amount - 1.0) < 0.001:
		return source_mesh

	var working = _to_array_mesh(source_mesh)
	if not working or working.get_surface_count() == 0:
		return source_mesh

	var result = ArrayMesh.new()
	for surf in range(working.get_surface_count()):
		var mdt = MeshDataTool.new()
		var err = mdt.create_from_surface(working, surf)
		if err != OK:
			# MeshDataTool couldn't parse this surface (e.g. import format
			# it doesn't support) - fail safe to the undeformed mesh rather
			# than half-apply a taper to some surfaces and not others.
			return source_mesh

		var aabb = working.get_aabb()
		# Forward convention is local -Z: the nose is the most-negative-Z tip.
		var nose_tip_z = aabb.position.z
		var nose_region_z = aabb.position.z + aabb.size.z * 0.35

		for i in range(mdt.get_vertex_count()):
			var v = mdt.get_vertex(i)
			if v.z <= nose_region_z and nose_region_z != nose_tip_z:
				var t = inverse_lerp(nose_region_z, nose_tip_z, v.z)
				t = clamp(t, 0.0, 1.0)
				var factor = lerp(1.0, taper_amount, t)
				v.x *= factor
				v.y = lerp(v.y, v.y * factor, t * 0.5)
				mdt.set_vertex(i, v)

		var mat = working.surface_get_material(surf)
		mdt.commit_to_surface(result)
		if mat:
			result.surface_set_material(result.get_surface_count() - 1, mat)

	return result

static func _to_array_mesh(mesh: Mesh) -> ArrayMesh:
	if mesh is ArrayMesh:
		return mesh
	var result = ArrayMesh.new()
	for surf in range(mesh.get_surface_count()):
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surf))
		var mat = mesh.surface_get_material(surf)
		if mat:
			result.surface_set_material(result.get_surface_count() - 1, mat)
	return result
