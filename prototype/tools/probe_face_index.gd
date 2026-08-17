extends SceneTree
# Throwaway probe: does PhysicsDirectSpaceState3D.intersect_ray() return a
# `face_index` that indexes the SAME triangle order as Mesh.get_faces()?
#
# This gates the armor damage path. HullFacets bakes a per-triangle -> facet-id
# map against get_faces() order. If face_index agrees with that order, then
# damage_resolver can recover the exact facet a shot struck for free - it
# ALREADY fires one intersect_ray per hit in compute_slope_multiplier() and
# throws everything but the normal away. If it disagrees (or is always -1), the
# resolver has to fall back to blending a whole side's armor together.
#
# Two known hazards this probe exists to measure rather than assume:
#   1. face_index is -1 unless the struck shape is a ConcavePolygonShape3D. The
#      Design Lab hull also carries a BOX collider on layer 1, which sits
#      OUTSIDE the mesh skin and is therefore struck first - so a naive query
#      gets -1 every time. Masking to the HullSurface layer alone is required.
#   2. Godot may report a BVH-internal index rather than the original face.
#      Verified here geometrically: the barycentre of get_faces()[3*fi ..+2]
#      must land on the reported hit position.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script res://tools/probe_face_index.gd --quit

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const HullSurface = preload("res://scripts/hull_surface.gd")
const HullFacets = preload("res://scripts/hull_facets.gd")

const HULLS := [
	"brenntal_medium_a",   # 180 tris, 14 facets - the workhorse
	"kestrel_medium_a",    # 204 tris, 22 facets - steeply raked
	"orrin_transport_a",   # tumblehome, 12 facets
	"tower_main_meridian", # 886 tris, 39 facets - the busiest
]

# How close the reported hit must sit to the plane of the triangle face_index
# names. Generous: we are testing INDEX IDENTITY, not precision.
const TOLERANCE := 0.05


func _init() -> void:
	await process_frame

	var total_hits := 0
	var total_rays := 0
	var neg_index := 0
	var mismatches := 0
	var worst := 0.0

	for hull_id in HULLS:
		var mesh: Mesh = MeshAssetLoader.get_hull_mesh(hull_id)
		if mesh == null:
			print("[SKIP] %s: no mesh" % hull_id)
			continue

		var holder := Node3D.new()
		root.add_child(holder)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		holder.add_child(mi)
		HullSurface.rebuild(holder, mi)

		# Physics bodies only enter the space after a physics step.
		await physics_frame
		await physics_frame

		var faces := mesh.get_faces()
		var tri_count := faces.size() / 3
		var aabb := mesh.get_aabb()
		var centre := aabb.get_center()
		var radius: float = aabb.size.length()

		var space := holder.get_world_3d().direct_space_state
		var hits := 0
		var hull_mismatch := 0
		var hull_worst := 0.0
		var facet_seen := {}

		# A fibonacci sphere of directions, so the sampling does not privilege
		# the axis-aligned faces the way a six-direction probe would.
		var n_rays := 240
		for i in range(n_rays):
			var y := 1.0 - (float(i) / float(n_rays - 1)) * 2.0
			var r := sqrt(maxf(0.0, 1.0 - y * y))
			var theta := PI * (3.0 - sqrt(5.0)) * float(i)
			var dir := Vector3(cos(theta) * r, y, sin(theta) * r)
			var from: Vector3 = centre + dir * radius
			var q := PhysicsRayQueryParameters3D.create(from, centre)
			q.collision_mask = HullSurface.SURFACE_COLLISION_LAYER
			total_rays += 1
			var res := space.intersect_ray(q)
			if res.is_empty():
				continue
			hits += 1
			total_hits += 1

			if not res.has("face_index"):
				neg_index += 1
				continue
			var fi := int(res["face_index"])
			if fi < 0:
				neg_index += 1
				continue
			if fi >= tri_count:
				hull_mismatch += 1
				mismatches += 1
				continue

			# Distance from the reported hit point to the plane of the triangle
			# face_index names. If the index were BVH-internal or reordered,
			# this would be large for most rays.
			var v0 := faces[fi * 3]
			var v1 := faces[fi * 3 + 1]
			var v2 := faces[fi * 3 + 2]
			var nrm := (v1 - v0).cross(v2 - v0)
			var d := 0.0
			if nrm.length_squared() > 1e-16:
				d = absf((res["position"] as Vector3 - v0).dot(nrm.normalized()))
			hull_worst = maxf(hull_worst, d)
			worst = maxf(worst, d)
			if d > TOLERANCE:
				hull_mismatch += 1
				mismatches += 1

			var fmap := HullFacets.load_map(hull_id)
			if fmap.has("map"):
				var m: PackedInt32Array = fmap["map"]
				if fi < m.size():
					facet_seen[m[fi]] = true

		print("%-22s %3d/%3d rays hit | %d tris | off-plane worst %.4f | mismatches %d | distinct facets struck %d" % [
			hull_id, hits, n_rays, tri_count, hull_worst, hull_mismatch, facet_seen.size()])

		holder.queue_free()
		await process_frame

	print("")
	print("rays %d, hits %d, face_index missing/-1 %d, mismatches %d, worst off-plane %.4f" % [
		total_rays, total_hits, neg_index, mismatches, worst])
	if total_hits == 0:
		print("VERDICT: INCONCLUSIVE - nothing was hit at all.")
		quit(2)
		return
	if neg_index > 0:
		print("VERDICT: FAIL - face_index unavailable on %d hits. Use the side-summary fallback." % neg_index)
		quit(1)
		return
	if mismatches > 0:
		print("VERDICT: FAIL - face_index does not match get_faces() order. Use the side-summary fallback.")
		quit(1)
		return
	print("VERDICT: PASS - face_index indexes get_faces() order. The resolver can recover the exact facet struck.")
	quit(0)
