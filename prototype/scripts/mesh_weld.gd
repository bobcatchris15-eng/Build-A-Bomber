# MeshWeld: position-only vertex welding, for collision generation.
#
# No class_name / no `extends` - same convention as hull_surface.gd,
# mesh_asset_loader.gd and sdf_mesh_baker.gd. Preload it.
#
# WHY THIS EXISTS. sdf_mesh_baker's _build_faceted_mesh() emits pure TRIANGLE
# SOUP: three fresh vertices per triangle, each carrying that triangle's own
# flat face normal. That is not a defect - the hard faceting IS the art
# direction (see HULL_MASSING_SPEC.md and _snap_constructed_normal), and the
# positions it writes are the dual-contouring cell vertices, shared exactly
# between adjacent triangles. Only the normals differ.
#
# SurfaceTool.index() cannot weld it, and this is the trap worth writing down:
# index() dedupes on the WHOLE vertex tuple, so two coincident corners belonging
# to differently-angled faces are correctly kept apart. Run it on a faceted hull
# and you get an indexed mesh with essentially the same vertex count you
# started with.
#
# Convex decomposition needs real shared topology - it works from vertex
# adjacency, and with none to find it degenerates. unit_assembly.gd's collider
# comment recorded the symptom: decomposition "never returned on the smallest
# hull in the roster at max_convex_hulls as low as 4", and named welding as the
# prerequisite for revisiting it. This is that prerequisite.
#
# The result is deliberately POSITION-ONLY. It is never rendered - it exists to
# be handed to Mesh.convex_decompose() and thrown away - so normals, UVs and
# tangents would be weight the decomposer ignores, and carrying the normals is
# the very thing that would stop it welding.

# 1e-5 against a voxel size of ~0.3-0.6. The positions are already bit-identical
# between adjacent triangles (see above), so this is guarding float noise from a
# future baker change rather than doing real merging work. A LARGE tolerance
# here would be actively harmful: it would collapse genuinely distinct corners
# on any hull detail finer than the tolerance and punch holes in the shell.
const DEFAULT_TOLERANCE := 0.00001


## An indexed, position-only ArrayMesh of `mesh`, with coincident vertices
## merged and any triangle the merge collapsed dropped. Null if there is
## nothing to weld.
static func weld(mesh: Mesh, tolerance: float = DEFAULT_TOLERANCE) -> ArrayMesh:
	if mesh == null:
		return null
	# get_faces() flattens every surface into one triangle list, which is what
	# we want: a hull's collision shell does not care which material a face
	# belonged to, and a multi-surface mesh would otherwise weld per surface and
	# leave the seams between them unwelded - exactly the topology break this is
	# trying to remove.
	var faces: PackedVector3Array = mesh.get_faces()
	if faces.size() < 3:
		return null

	var inv := 1.0 / maxf(tolerance, 0.000000001)
	var lookup := {}
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var collapsed := 0

	for i in range(0, faces.size() - 2, 3):
		var tri := [0, 0, 0]
		for k in range(3):
			var p: Vector3 = faces[i + k]
			# Quantised to a lattice rather than compared pairwise. Pairwise is
			# O(n^2) and these meshes run to tens of thousands of triangles.
			var key := "%d|%d|%d" % [
				roundi(p.x * inv), roundi(p.y * inv), roundi(p.z * inv)]
			if lookup.has(key):
				tri[k] = lookup[key]
			else:
				tri[k] = verts.size()
				lookup[key] = tri[k]
				verts.append(p)
		# A triangle whose corners merged onto each other has no area left.
		# Feeding a degenerate to the decomposer is how you get NaN normals.
		if tri[0] == tri[1] or tri[1] == tri[2] or tri[0] == tri[2]:
			collapsed += 1
			continue
		indices.append(tri[0])
		indices.append(tri[1])
		indices.append(tri[2])

	if indices.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.set_meta("weld_collapsed_triangles", collapsed)
	out.set_meta("weld_source_vertices", faces.size())
	return out


## Fraction of the source vertices that survived the weld. 1.0 means nothing
## merged - i.e. the mesh was already indexed, or the tolerance was too tight to
## do anything, and a decomposition run on it will behave exactly as badly as it
## did before. The baker reports this so a regression is visible rather than
## silently producing a hull that hangs the next person to try.
static func weld_ratio(welded: ArrayMesh) -> float:
	if welded == null or not welded.has_meta("weld_source_vertices"):
		return 1.0
	var source: int = welded.get_meta("weld_source_vertices")
	if source <= 0:
		return 1.0
	var arrays := welded.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return float(verts.size()) / float(source)
