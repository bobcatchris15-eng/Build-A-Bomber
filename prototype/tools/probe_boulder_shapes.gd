extends SceneTree
# Playtest item #3: boulders should be rugged and rocklike, not lumpy balls.
# The rework replaced radial-noise-on-a-sphere with real planar fracture cuts
# plus flat shading, across three silhouette families. This checks the three
# things that could silently go wrong in a headless Blender pipeline:
#   - every pool index actually exists and carries real geometry (a fracture
#     that cut too deep, or a hole-fill that failed, would export an empty or
#     near-empty mesh - the "slab" family's files are much smaller than the
#     others by design, so file size alone proves nothing)
#   - normals are FLAT, i.e. adjacent faces genuinely disagree. Smooth shading
#     averaging the fracture faces away is exactly what made the old boulders
#     read as lumpy, so it is the regression worth pinning.
#   - the families have visibly different proportions, rather than one shape
#     with randomized parameters.

const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")


func _init():
	print("pool size declared in terrain_builder.gd = ", TerrainBuilderScript.BOULDER_POOL_SIZE)
	for i in range(TerrainBuilderScript.BOULDER_POOL_SIZE):
		var path: String = TerrainBuilderScript.BOULDER_MODEL_DIR % i
		if not ResourceLoader.exists(path):
			print("  boulder_%d MISSING at %s" % [i, path])
			continue
		var packed := load(path) as PackedScene
		var inst := packed.instantiate() as Node3D
		var mi := _first_mesh(inst)
		if mi == null or mi.mesh == null:
			print("  boulder_%d has no mesh" % i)
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var aabb: AABB = mi.mesh.get_aabb()

		# Distinct normal directions. A smooth-shaded sphere has one normal per
		# vertex all pointing outward and nearly all unique-but-continuous; a
		# faceted mesh has normals that cluster into a small number of exactly
		# repeated values, one per flat face. The count of DISTINCT normals
		# being far below the vertex count is the signature of flat shading.
		var distinct := {}
		for n in normals:
			distinct[Vector3(snappedf(n.x, 0.01), snappedf(n.y, 0.01), snappedf(n.z, 0.01))] = true
		var faceted: bool = normals.size() > 0 and float(distinct.size()) / float(normals.size()) < 0.5
		print("  boulder_%d: verts=%-5d distinct_normals=%-4d %s | size=%.2f x %.2f x %.2f (h/w=%.2f)" % [
			i, verts.size(), distinct.size(),
			("FLAT-SHADED" if faceted else "smooth - REGRESSION"),
			aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.size.y / maxf(aabb.size.x, 0.001)])
		inst.queue_free()
	quit(0)


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null
