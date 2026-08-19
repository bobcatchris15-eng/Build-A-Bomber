extends SceneTree
# Localises the "navmesh not updating on placement" regression.
#
# What this probes, in order, so the failure message tells you exactly
# which link in the chain broke:
#
#   1. After boot, the ground navmesh has WALKABLE surface everywhere
#      a building could go (the boot bake carved the starting HQs but
#      otherwise left the map open).
#   2. Place a building at a known open point. Confirm the structure
#      is added to the "structures" group.
#   3. Read the ground navmesh region BEFORE _mark_navmesh_dirty. The
#      walkable surface at the building's centre should still be there
#      (no hole yet, because we haven't rebaked).
#   4. Call _mark_navmesh_dirty(urgent=true) directly.
#   5. Read the ground navmesh region AFTER. The walkable surface at
#      the building's centre should now be MISSING (the hole is carved).
#   6. A NavigationServer3D.map_get_path() that crosses the building
#      should route around it (path corners, doesn't go through).
#
# If steps 1-3 pass but 4-5 fail: the urgent rebake is silently doing
# nothing (early-exit, wrong region, empty bake, etc.). If 5 passes
# but 6 fails: the navmesh data is updated but NavigationServer3D
# isn't seeing it (region RID wrong, sync timing, etc.).
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_navmesh_after_placement.gd

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")

const PLAYER := 0


func _init():
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)

	# Wait for the boot to complete so the navmesh is in place.
	var guard := 0
	while not ("world_is_ready" in battle) or not battle.world_is_ready:
		if guard > 600:
			print("[FAIL] battle never became ready (waited %d frames)" % guard)
			quit(1)
			return
		await physics_frame
		guard += 1
	print("[OK]   battle ready after %d frames" % guard)

	# --- 1. Pick a flat, open spot for the test ------------------------------
	# We want a building placed close to the player HQ so the boot bake
	# definitely left this area walkable, and at low slope. The player
	# HQ is at approximately (0, 0, 80) on lake_crossing. (10, 0, 70)
	# is in the player's buildable area, next to the HQ, and the spot
	# the player would naturally pick for a power plant. The map is
	# flat near the HQ by design (the player needs flat ground to build
	# in, and the editor picked a flat tile).
	var site := Vector3(10, 0, 70)
	var site_y: float = battle.terrain_height_at(site)
	site.y = site_y
	print("[OK]   terrain at site is y=%.2f" % site_y)

	# --- 2. Place a building -----------------------------------------------
	var placed = battle._place_structure("power_plant", PLAYER, site)
	if placed == null or not is_instance_valid(placed):
		print("[FAIL] _place_structure returned null/invalid")
		quit(1)
		return
	print("[OK]   placed %s at %s, footprint %s" % [placed.kind, placed.global_position, placed.footprint])

	# Confirm it's in the structures group (the urgent path keys off this).
	var in_group := false
	for s in get_nodes_in_group("structures"):
		if s == placed:
			in_group = true
			break
	if not in_group:
		print("[FAIL] newly placed structure is NOT in the 'structures' group - urgent rebake would carve no hole")
		quit(1)
		return
	print("[OK]   structure is in 'structures' group")

	# --- 3. Navmesh region BEFORE rebake ------------------------------------
	var ground_map = battle.ground_nav_map
	if ground_map == null or not ground_map.is_valid():
		print("[FAIL] battle.ground_nav_map is null/invalid")
		quit(1)
		return

	# The navmesh SOURCE GEOMETRY is deliberately flat at y=0.5 (see
	# _build_ground_faces()'s header - the navmesh's flat Y is not
	# terrain_height_at). So when we query "closest navmesh point to
	# the building's centre", the 3D distance is dominated by Y. We
	# want the XZ distance only - the building's footprint is a 2D
	# rect and what matters is whether the rect is carved.
	#
	# Sample walkability by querying the closest polygon. map_get_closest_point
	# returns the closest navmesh point to the query. If the building
	# is NOT yet carved, that point's XZ is the query's XZ (within a
	# polygon). If carved, it's on the edge of the hole, XZ-offset.
	var closest_before: Vector3 = NavigationServer3D.map_get_closest_point(ground_map, site)
	var dist_before_xz: float = Vector2(closest_before.x - site.x, closest_before.z - site.z).length()
	print("[INFO] before rebake: closest nav point = %s, XZ dist = %.3f m" % [closest_before, dist_before_xz])
	if dist_before_xz > 1.5:
		print("[FAIL] before rebake, the navmesh's closest XZ point to the building is %.2f m away - the boot bake didn't make this XZ walkable, so we can't test placement carving" % dist_before_xz)
		quit(1)
		return

	# --- 4. Trigger the urgent rebake ---------------------------------------
	# Capture the state of the urgent-path control flags BEFORE the call
	# so we can tell whether _mark_navmesh_dirty did anything, took an
	# early exit, or actually rebaked.
	var regions_before: int = battle._ground_nav_regions.size()
	var rebake_pending_before: bool = battle._nav_rebake_pending
	var holes_before: int = 0
	for s in get_nodes_in_group("structures"):
		if is_instance_valid(s) and not s.is_dead and s.is_inside_tree():
			holes_before += 1
	print("[INFO] before call: regions=%d, _nav_rebake_pending=%s, live structures=%d" % [regions_before, rebake_pending_before, holes_before])
	if regions_before == 0:
		print("[FAIL] _ground_nav_regions is empty before the rebake call - the urgent path would defer, and the deferred path returns early when regions are empty (regression risk)")
		quit(1)
		return

	battle._mark_navmesh_dirty(true)
	print("[OK]   _mark_navmesh_dirty(true) returned without error")

	# Direct call to _building_holes() to confirm the new building is
	# present in the data the rebake used.
	var new_holes = battle._building_holes()
	print("[INFO] _building_holes() returned %d holes" % new_holes.size())
	for h in new_holes:
		print("       hole: center=%s half_extents=%s" % [h["center"], h["half_extents"]])
	var new_building_hole: Dictionary = {}
	for h in new_holes:
		if absf(h["center"].x - site.x) < 0.5 and absf(h["center"].z - site.z) < 0.5:
			new_building_hole = h
			break
	if new_building_hole.is_empty():
		print("[FAIL] the new building's hole is not in _building_holes() - the urgent rebake's data source is missing the new structure")
		quit(1)
		return
	var tile_indices = TerrainBuilder.tiles_overlapping_hole(battle.current_map, new_building_hole)
	print("[INFO] tiles_overlapping_hole() returned %d tile(s) for the new building: %s" % [tile_indices.size(), str(tile_indices)])

	# Direct call to the rebake function, with the same arguments _mark_navmesh_dirty
	# uses, but BEFORE the urgent call ran. This gives us a "what the rebake SHOULD
	# have produced" baseline to compare against the post-_mark_navmesh_dirty state.
	#
	# If this direct call DOES carve the hole but the urgent _mark_navmesh_dirty
	# call did NOT, then the bug is in _mark_navmesh_dirty's path - probably a
	# wrong map_def, wrong regions array, or wrong tile_rects.
	#
	# If this direct call also fails to carve, the bug is in the rebake itself
	# (or its inputs).
	var direct_ground_buckets = []
	var direct_tile_rects = battle._nav_tile_rects
	if direct_tile_rects.is_empty():
		print("[FAIL] battle._nav_tile_rects is empty - the rebake would iterate zero tiles")
		quit(1)
		return
	# Manually run rebake for tile 78 (the one overlapping our building).
	TerrainBuilder.rebake_ground_amphibious_tiles_sync(
		battle.current_map, new_holes, battle._ground_nav_regions, battle._amphibious_nav_regions,
		direct_tile_rects, [78])
	await physics_frame
	await physics_frame
	var closest_after_direct: Vector3 = NavigationServer3D.map_get_closest_point(ground_map, site)
	var dist_after_direct_xz: float = Vector2(closest_after_direct.x - site.x, closest_after_direct.z - site.z).length()
	print("[INFO] after DIRECT rebake of tile 78: closest nav = %s, XZ dist = %.3f m" % [closest_after_direct, dist_after_direct_xz])
	if dist_after_direct_xz >= 3.5:
		print("[INFO] direct rebake DID carve the hole. Bug is in _mark_navmesh_dirty's wiring (wrong args, early exit, etc.)")
	else:
		print("[INFO] direct rebake ALSO did not carve. Bug is in rebake_ground_amphibious_tiles_sync itself (Recast kept walkable, or write to wrong region).")
		# Dig deeper: check whether the bucket for tile 78 actually has a hole in it
		# by counting faces inside vs outside the new building's footprint rect.
		var tile_rects_dbg = battle._nav_tile_rects
		var t78: Dictionary = tile_rects_dbg[78]
		print("[INFO] tile 78 rect: x0=%.1f x1=%.1f z0=%.1f z1=%.1f" % [t78["x0"], t78["x1"], t78["z0"], t78["z1"]])
		print("[INFO] building rect: x0=%.1f x1=%.1f z0=%.1f z1=%.1f" % [new_building_hole["center"].x - new_building_hole["half_extents"].x, new_building_hole["center"].x + new_building_hole["half_extents"].x, new_building_hole["center"].z - new_building_hole["half_extents"].y, new_building_hole["center"].z + new_building_hole["half_extents"].y])
		# Run _build_ground_faces and _bucket_verts_by_tile ourselves to see the bucket.
		var ground_verts = TerrainBuilder._build_ground_faces(battle.current_map, new_holes)
		var buckets = TerrainBuilder._bucket_verts_by_tile(ground_verts, battle.current_map, tile_rects_dbg)
		var bucket78_vert_count: int = buckets[78].size()
		var faces_in_bucket: int = bucket78_vert_count / 3
		print("[INFO] tile 78 bucket: %d verts = %d triangles" % [bucket78_vert_count, faces_in_bucket])
		# Count triangles whose centroid is inside the building rect.
		var tris_inside: int = 0
		var i := 0
		while i + 2 < bucket78_vert_count:
			var v0: Vector3 = buckets[78][i]
			var v1: Vector3 = buckets[78][i + 1]
			var v2: Vector3 = buckets[78][i + 2]
			var cx: float = (v0.x + v1.x + v2.x) / 3.0
			var cz: float = (v0.z + v1.z + v2.z) / 3.0
			if absf(cx - site.x) < new_building_hole["half_extents"].x and absf(cz - site.z) < new_building_hole["half_extents"].y:
				tris_inside += 1
			i += 3
		print("[INFO] tile 78 bucket: %d triangle(s) inside the building rect (expected 0 - the hole should have excluded them)" % tris_inside)

		# Compare the bucket the probe computed against the bucket the rebake
		# actually computed. The rebake is the live call we just made; the
		# probe's is a re-derivation. They should match exactly. If they
		# differ, the inputs to the live call (map_def, extra_holes, tile_rects)
		# differ from the probe's view.
		var direct_rebake_verts = TerrainBuilder._build_ground_faces(battle.current_map, new_holes)
		var direct_rebake_buckets = TerrainBuilder._bucket_verts_by_tile(direct_rebake_verts, battle.current_map, battle._nav_tile_rects)
		var direct_bucket_size: int = direct_rebake_buckets[78].size()
		print("[INFO] bucket the live rebake produced (re-derived): %d verts (matches probe: %s)" % [direct_bucket_size, direct_bucket_size == bucket78_vert_count])
		# Now compute the bucket WITHOUT the new building's hole - the "before" state.
		var holes_minus_new: Array = []
		for h in new_holes:
			if absf(h["center"].x - site.x) > 0.5 or absf(h["center"].z - site.z) > 0.5:
				holes_minus_new.append(h)
		var before_verts = TerrainBuilder._build_ground_faces(battle.current_map, holes_minus_new)
		var before_buckets = TerrainBuilder._bucket_verts_by_tile(before_verts, battle.current_map, battle._nav_tile_rects)
		var before_bucket_size: int = before_buckets[78].size()
		print("[INFO] bucket without the new building's hole: %d verts (expected: more than with the hole, since the hole removes triangles)" % before_bucket_size)
		# If the bucket is the SAME size with vs without the hole, _build_ground_faces
		# is not respecting the hole for this tile.
		if before_bucket_size == direct_bucket_size:
			print("[FAIL] bucket for tile 78 has the same vert count with and without the new building's hole.")
			print("       _build_ground_faces() is NOT respecting the new building's hole for this tile.")
			print("       This is the bug - the source geometry is not being carved.")

		# Compare the actual navmesh meshes stored in the regions. _ground_nav_regions
		# has the regions, but there might be OTHER regions on the same map (water,
		# amphibious) that also cover this XZ. Count how many regions in the map
		# cover the building's XZ.
		var all_region_rids = NavigationServer3D.map_get_regions(ground_map)
		print("[INFO] total regions on ground map: %d (expected 144, one per tile)" % all_region_rids.size())

		# Simpler check: the boot bake created tile 78 and didn't carve the new
		# building's hole (because the building wasn't placed at boot time). The
		# urgent rebake is supposed to overwrite tile 78 with a carved version.
		# If map_get_closest_point still returns a walkable point, the rebake
		# didn't actually overwrite. To verify, check the map iteration ID: if
		# the rebake ran, the iteration ID should have changed.
		var iter_id_before: int = NavigationServer3D.map_get_iteration_id(ground_map)
		# Trigger a no-op rebake to see if iteration ID changes.
		battle._mark_navmesh_dirty(true)
		await physics_frame
		await physics_frame
		var iter_id_after: int = NavigationServer3D.map_get_iteration_id(ground_map)
		print("[INFO] map iteration id before=%d, after second urgent rebake=%d (should differ if rebake did real work)" % [iter_id_before, iter_id_after])

		# The bucket looks correct. So the problem is downstream of the bucket.
		# Sample the navmesh at many points around the building to characterise
		# the shape of the missing region. This tells us whether the hole is
		# actually carved (and we're sampling the wrong spot) or whether the
		# whole tile's navmesh is unchanged.
		var sample_offsets: Array = [
			Vector3(0, 0, 0),       # centre
			Vector3(2, 0, 0),       # 2m east
			Vector3(-2, 0, 0),      # 2m west
			Vector3(0, 0, 2),       # 2m north
			Vector3(0, 0, -2),      # 2m south
			Vector3(4, 0, 0),       # 4m east
			Vector3(-4, 0, 0),      # 4m west
			Vector3(0, 0, 4),       # 4m north
			Vector3(0, 0, -4),      # 4m south
			Vector3(8, 0, 0),       # 8m east (should be walkable - outside hole)
		]
		for off in sample_offsets:
			var sample_pt: Vector3 = site + off
			var closest: Vector3 = NavigationServer3D.map_get_closest_point(ground_map, sample_pt)
			var dist: float = Vector2(closest.x - sample_pt.x, closest.z - sample_pt.z).length()
			print("[INFO]   sample %s: closest = %s, XZ dist = %.2f m" % [off, closest, dist])

	# Even before placing the new building, the boot bake should have carved
	# the player HQ at (0, 0.96, -408). Check that. If THAT hole isn't there
	# either, the boot bake itself is broken - and the urgent rebake can't
	# be expected to fix what was already broken at boot.
	var hq_hole: Dictionary = new_holes[0]
	var hq_site: Vector3 = hq_hole["center"]
	var hq_closest: Vector3 = NavigationServer3D.map_get_closest_point(ground_map, hq_site)
	var hq_dist_xz: float = Vector2(hq_closest.x - hq_site.x, hq_closest.z - hq_site.z).length()
	print("[INFO] player HQ at %s: closest nav point XZ dist = %.3f m (expected >= 4 m if carved)" % [hq_site, hq_dist_xz])
	if hq_dist_xz < 3.5:
		print("[INFO] player HQ hole is ALSO not carved. The boot bake did not include the starting HQ as a hole.")
		# Find which tile(s) the HQ is in.
		var hq_tiles = TerrainBuilder.tiles_overlapping_hole(battle.current_map, hq_hole)
		print("[INFO] player HQ hole's tile(s): %s" % str(hq_tiles))
	else:
		print("[INFO] player HQ hole IS carved correctly - bug is specific to the new building's tile.")

	quit(1)

	# Wait one frame so the NavigationServer3D sidecar fully syncs.
	# The sync rebake is synchronous (match_director.gd comment at 1651:
	# "the main thread blocks on the result, not on the work") but the
	# region's internal sync still takes a tick.
	await physics_frame
	await physics_frame

	# --- 5. Navmesh region AFTER rebake -------------------------------------
	var closest_after: Vector3 = NavigationServer3D.map_get_closest_point(ground_map, site)
	var dist_after_xz: float = Vector2(closest_after.x - site.x, closest_after.z - site.z).length()
	print("[INFO] after rebake:  closest nav point = %s, XZ dist = %.3f m" % [closest_after, dist_after_xz])
	# With BUILDING_CLEARANCE=2.5 plus the power_plant footprint (4.5x4.5),
	# the closest XZ navmesh point at the building's centre should now be
	# AT LEAST half(footprint) + clearance - agent_radius away (~4.2 m).
	# Anything less means the rebake did not carve the hole.
	if dist_after_xz < 3.5:
		print("[FAIL] after urgent rebake, the closest XZ navmesh point to the building is only %.2f m away - the navmesh was NOT carved for this structure" % dist_after_xz)
		print("       (expected ~4-5 m: footprint half-extent + BUILDING_CLEARANCE - agent_radius)")
		print("       the structure IS in the 'structures' group, so the urgent path SHOULD have rebaked.")
		print("       this is the bug: either _mark_navmesh_dirty's urgent branch took an early exit, or the sync rebake wrote to the wrong region / produced an empty mesh.")
		quit(1)
		return

	# --- 6. Path query routes around the new building ------------------------
	# Query a path that goes straight through the new building. If the
	# navmesh was carved correctly, the path routes around the hole.
	# If not, the path goes straight through.
	var west := Vector3(site.x - 30, 0, site.z)
	var east := Vector3(site.x + 30, 0, site.z)
	west.y = battle.terrain_height_at(west)
	east.y = battle.terrain_height_at(east)
	var path_we: PackedVector3Array = NavigationServer3D.map_get_path(ground_map, west, east, true)
	if path_we.size() < 2:
		print("[FAIL] west-to-east path query returned %d points (expected >= 2, routing around the new building)" % path_we.size())
		quit(1)
		return
	# Path should NOT pass within 4 m of the building's XZ centre.
	var worst_dist := INF
	for p in path_we:
		var d: float = Vector2(p.x - site.x, p.z - site.z).length()
		worst_dist = minf(worst_dist, d)
	print("[INFO] west-to-east path: %d points, closest XZ approach to building centre: %.2f m" % [path_we.size(), worst_dist])
	if worst_dist < 3.5:
		print("[FAIL] west-to-east path came within %.2f m of the building centre (XZ) - navmesh is not actually carving this structure" % worst_dist)
		quit(1)
		return

	print("[PASS] urgent rebake carved the building's footprint into the navmesh (closest XZ approach %.2f m). Steps 1-6 all pass." % worst_dist)
	quit(0)