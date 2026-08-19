extends SceneTree
# Minimal smoke test: does NavigationServer3D actually carve a hole when
# build_navmeshes() is given an extra_holes list? No placement, no battle
# scene, no match_director wiring - just the terrain builder and the
# server, in isolation. If this works, the bug is in the urgent rebake
# wiring. If this doesn't work, the bug is in build_navmeshes() itself
# (probably in _bake_nav_mesh, _build_ground_faces, or Recast config).

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")


func _init():
	# 200x200 half-extents so a 6x6 hole in the middle has plenty of
	# walkable ground to either side.
	var map_def: Dictionary = {
		"map_half_extents": 200.0,
		"world_scale": 1.0,
	}
	var hole: Dictionary = {
		"center": Vector3.ZERO,
		"half_extents": Vector2(3, 3),
	}
	var nav: Dictionary = TerrainBuilder.build_navmeshes(map_def, [hole])
	if not await _await_nav_map(nav.ground_map):
		print("[FAIL] ground navmesh never synchronised")
		quit(1)
		return

	# Query the closest navmesh point to the centre (which is inside the hole).
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav.ground_map, Vector3.ZERO)
	var dist: float = Vector2(closest.x, closest.z).length()
	print("[INFO] closest nav point to origin: %s, XZ dist = %.3f m" % [closest, dist])
	if dist < 1.0:
		print("[FAIL] origin is still walkable - the hole was not carved (Recast kept walkable, or write to wrong region)")
		# Continue so we can also test the path.
	else:
		print("[PASS] origin hole carved (closest XZ dist = %.2f m, expected >= 1 m for a 3x3 hole)" % dist)
	# Also test a path that goes through the hole.
	var west := Vector3(-40, 0, 0)
	var east := Vector3(40, 0, 0)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav.ground_map, west, east, true)
	var worst: float = INF
	for p in path:
		var d: float = Vector2(p.x, p.z).length()
		worst = minf(worst, d)
	print("[INFO] west-to-east path: %d points, closest approach to hole centre: %.2f m" % [path.size(), worst])
	if worst < 1.0:
		print("[FAIL] west-to-east path came within %.2f m of hole centre - hole not carved for path queries" % worst)
	else:
		print("[PASS] path routes around the hole (closest approach %.2f m)" % worst)

	# Sample many points INSIDE the hole to characterise the navmesh there.
	# If a unit could spawn at any of these and the path query would still
	# route around, the player sees a refinery that has no walkable area
	# under it - that IS the bug, just hidden by path-finding cleverness.
	print("[INFO] sampling navmesh at points inside the hole:")
	for r in [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
		var pt := Vector3(r, 0, 0)
		var c := NavigationServer3D.map_get_closest_point(nav.ground_map, pt)
		var d2 := Vector2(c.x, c.z).length()
		print("       x=+%.1f: closest = (%.2f, %.2f), dist = %.3f" % [r, c.x, c.z, d2])

	# Free the RIDs.
	_free_nav_result(nav)
	quit(0)


func _await_nav_map(map_rid: RID) -> bool:
	for _i in range(60):
		if NavigationServer3D.map_get_iteration_id(map_rid) > 0:
			return true
		await physics_frame
	return false


func _free_nav_result(nav: Dictionary) -> void:
	for rid in nav["ground_regions"] + nav["amphibious_regions"] + [
			nav["water_region"], nav["deep_water_nav_region"],
			nav["ground_map"], nav["water_map"],
			nav["amphibious_map"], nav["deep_water_map"]]:
		if rid != null and rid.is_valid():
			NavigationServer3D.free_rid(rid)