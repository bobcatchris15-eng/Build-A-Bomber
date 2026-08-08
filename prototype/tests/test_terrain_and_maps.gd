extends "res://tests/suite_base.gd"
# terrain and maps suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

func test_balance_report_covers_every_catalog_entry() -> bool:
	print("Running Test Suite: Balance Report Tool - Scores Every Catalog Entry Without Erroring...")
	# Not a balance-correctness check (balance is subjective, tuned by
	# playtest feel) - a regression guard that tools/balance_report.gd's
	# scoring function stays callable and well-behaved (finite, non-
	# negative) as the catalog grows, so it doesn't silently rot into an
	# unusable tool nobody notices is broken.
	var BalanceReportScript = load("res://tools/balance_report.gd")
	var catalog = ModuleCatalog.get_catalog()
	var checked = 0
	for type_id in catalog.keys():
		var data = catalog[type_id]
		var score = BalanceReportScript.compute_score(data)
		if not (score.has("value") and score.has("cost") and score.has("ratio")):
			print("  [FAIL] compute_score() should return value/cost/ratio for ", type_id)
			return false
		if is_nan(score.value) or is_nan(score.cost) or is_nan(score.ratio):
			print("  [FAIL] compute_score() produced NaN for ", type_id, ": ", score)
			return false
		if score.value < 0.0 or score.cost < 0.0:
			print("  [FAIL] compute_score() produced a negative value/cost for ", type_id, ": ", score)
			return false
		checked += 1

	if checked != catalog.size():
		print("  [FAIL] Expected to score all ", catalog.size(), " catalog entries, only checked ", checked)
		return false

	print("  [PASS] Balance report scores all ", checked, " catalog entries with finite, non-negative value/cost/ratio.")
	return true

func test_terrain_builder_pure_functions() -> bool:
	print("Running Test Suite: Multi-Map Terrain - terrain_height_at()/is_position_blocked() (pure functions)...")
	var TerrainBuilder = preload("res://scripts/terrain_builder.gd")
	var map_def = {
		"map_half_extents": 80.0,
		"water_areas": [{"center": Vector3(18, 0, 0), "half_extents": Vector2(7, 7)}],
		"obstacles": [{"center": Vector3(-20, 0, 20), "half_extents": Vector2(5, 5)}],
	}

	# Skirmish refinement pass: "flat" ground carries real low-amplitude
	# rolling noise (height_at()'s baseline contribution) instead of being
	# hardcoded to exactly 0.0 - a small tolerance replaces exact equality.
	var flat_h = TerrainBuilder.terrain_height_at(map_def, Vector3(40, 0, 40))
	if abs(flat_h) > 1.0:
		print("  [FAIL] Flat ground should report a height near 0.0 (noise only), got ", flat_h)
		return false
	if not TerrainBuilder.is_position_blocked(map_def, Vector3(18, 0, 0)):
		print("  [FAIL] A position inside a water_area should be blocked")
		return false
	if not TerrainBuilder.is_position_blocked(map_def, Vector3(-20, 0, 20)):
		print("  [FAIL] A position inside an obstacle should be blocked")
		return false
	if TerrainBuilder.is_position_blocked(map_def, Vector3(40, 0, 40)):
		print("  [FAIL] Ordinary flat ground should not be blocked")
		return false

	print("  [PASS] terrain_height_at()/is_position_blocked() correctly classify water, obstacles, and flat ground.")
	return true

func test_b6_heightmap_plateau_approachable_from_any_side() -> bool:
	print("Running Test Suite: Heightmap Plateau - Approachable From Any Side, Not Just An Authored Ramp Direction (RTS_CORE_ROADMAP.md B6)...")
	# RTS_CORE_ROADMAP.md B6 retired elevation_zones' "one ramp on ONE
	# authored side" system - a heightmap plateau has a real continuous
	# slope on every side (see build_terrain.py's _plateau()), so unlike
	# the old test_terrain_builder_navmesh_ramp_connects() (which had to
	# exercise all 4 ramp directions because only ONE was ever authored),
	# this proves a SINGLE plateau feature is reachable from all 4
	# cardinal directions with no per-side authoring at all.
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	TerrainBuilderScript.reset_heightmap_cache_for_tests()

	var file = FileAccess.open("res://data/test_fixtures/terrain/test_terrain.json", FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var map_def: Dictionary = json.get_data()
	# Read raw from disk, bypassing MapCatalog's _apply_world_scale - see
	# test_b4_heightmap_terrain_pure_functions' identical comment for why
	# this fixture needs an explicit world_scale=1.0 now that Chunk 19
	# moved the global default off 1.0.
	map_def["world_scale"] = 1.0

	var nav = TerrainBuilderScript.build_navmeshes(map_def)
	await _await_nav_map(nav.ground_map)

	# The fixture's plateau: center [-40, 20], half_extents [6, 6], height
	# 3, falloff 5 (walkable: slope 3/5=0.6 < MAX_WALKABLE_SLOPE 0.7) - so
	# its slope zone extends roughly x=[-51,-29], z=[9,31]. Approach points
	# chosen clear of the fixture's other features (hill/basin share the
	# plateau's x=-40 column further south; ridge/ravine sit at x=-10/10)
	# and inside the map's 60-unit half-extent.
	var approaches = [
		{"side": "north", "start": Vector3(-40, 0, 45)},
		{"side": "south", "start": Vector3(-25, 0, 0)},
		{"side": "east", "start": Vector3(-20, 0, 20)},
		{"side": "west", "start": Vector3(-55, 0, 20)},
	]
	var top = Vector3(-40, 3, 20)
	for a in approaches:
		var path = NavigationServer3D.map_get_path(nav.ground_map, a.start, top, true)
		var max_y = 0.0
		for p in path:
			max_y = max(max_y, p.y)
		if path.is_empty() or max_y < 2.5:
			print("  [FAIL] Approaching the plateau from the ", a.side, " should reach its top (Y>=2.5), got ", path.size(), " points, max_y=", max_y)
			return false

	print("  [PASS] A single plateau feature (no per-side ramp authoring) is reachable from all 4 cardinal directions.")
	return true

func test_b7_open_plains_surfacemap_covers_all_7_surface_types() -> bool:
	print("Running Test Suite: Open Plains - Real Surfacemap Covers All 7 Surface Types (RTS_CORE_ROADMAP.md B7)...")
	# RTS_CORE_ROADMAP.md B7: "with B4's surface map this becomes paint-not-
	# rects" - open_plains now resolves get_surface_type_at() through a real
	# baked surfacemap PNG (terrain.surfacemap) instead of a live rect-
	# overlap test, proving the raster path works for an actual bundled map,
	# not just the B4 test fixture.
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	MapCatalogScript.reset_cache_for_tests()
	TerrainBuilderScript.reset_heightmap_cache_for_tests()

	var map_def = MapCatalogScript.get_map("open_plains")
	if TerrainBuilderScript._get_surfacemap_image(map_def) == null:
		print("  [FAIL] open_plains should have a real surfacemap image loaded.")
		return false

	# Every authored surface_zones center should resolve to its own type
	# via the raster - the exact center point of each zone.
	for zone in map_def.get("surface_zones", []):
		var pos = zone.center
		var got = TerrainBuilderScript.get_surface_type_at(map_def, Vector3(pos.x, 0, pos.z))
		if got != zone.surface_type:
			print("  [FAIL] Zone center ", pos, " should resolve to '", zone.surface_type, "', got '", got, "'")
			return false

	# All 7 types are actually represented somewhere on this map.
	var found_types: Dictionary = {}
	for zone in map_def.get("surface_zones", []):
		found_types[zone.surface_type] = true
	for t in ["marsh", "rocky", "snow_mud", "sand", "gravel", "forest", "ice"]:
		if not found_types.has(t):
			print("  [FAIL] open_plains should include a '", t, "' surface zone.")
			return false

	# Flat ground far from every zone still resolves to plain ("").
	if TerrainBuilderScript.get_surface_type_at(map_def, Vector3(0, 0, 0)) != "":
		print("  [FAIL] Open ground away from every zone should resolve to plain (\"\").")
		return false

	print("  [PASS] open_plains' surfacemap correctly resolves all 7 surface types at their authored centers, plus plain ground elsewhere - a real raster, not rects.")
	return true

func test_bridges_carve_a_real_ground_crossing_through_water() -> bool:
	print("Running Test Suite: Bridges - Ground Units Cross Via The Bridge, Blocked Without One (Map Variety Batch)...")
	var TerrainBuilder = preload("res://scripts/terrain_builder.gd")
	var half = 40.0
	# Water spans the map's ENTIRE x-range (edge to edge) - with no bridge
	# there is literally zero room to go around, so any successful crossing
	# can only be explained by the bridge carve-out, not a lucky detour.
	var water = [{"center": Vector3(0, 0, 0), "half_extents": Vector2(half, 6)}]
	var map_no_bridge = {"map_half_extents": half, "water_areas": water, "obstacles": []}
	var map_with_bridge = {
		"map_half_extents": half, "water_areas": water, "obstacles": [],
		"bridges": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(4, 6)}],
	}
	var start = Vector3(0, 0, -30)
	var end = Vector3(0, 0, 30)

	var nav_no_bridge = TerrainBuilder.build_navmeshes(map_no_bridge)
	await _await_nav_map(nav_no_bridge.ground_map)
	var path_no_bridge = NavigationServer3D.map_get_path(nav_no_bridge.ground_map, start, end, true)
	var reached_no_bridge = path_no_bridge.size() >= 2 and path_no_bridge[path_no_bridge.size() - 1].distance_to(end) <= 3.0
	for k in ["ground_region", "water_region", "amphibious_region", "deep_water_region"]:
		if nav_no_bridge[k].is_valid(): NavigationServer3D.free_rid(nav_no_bridge[k])
	for k in ["ground_map", "water_map", "amphibious_map", "deep_water_map"]:
		NavigationServer3D.free_rid(nav_no_bridge[k])

	var nav_with_bridge = TerrainBuilder.build_navmeshes(map_with_bridge)
	await _await_nav_map(nav_with_bridge.ground_map)
	var path_with_bridge = NavigationServer3D.map_get_path(nav_with_bridge.ground_map, start, end, true)
	var reached_with_bridge = path_with_bridge.size() >= 2 and path_with_bridge[path_with_bridge.size() - 1].distance_to(end) <= 3.0
	var crosses_via_bridge_strip = true
	for p in path_with_bridge:
		if p.z > -6.0 and p.z < 6.0 and abs(p.x) > 5.0: # outside the bridge's x=[-4,4] footprint (+1 slack)
			crosses_via_bridge_strip = false
	for k in ["ground_region", "water_region", "amphibious_region", "deep_water_region"]:
		if nav_with_bridge[k].is_valid(): NavigationServer3D.free_rid(nav_with_bridge[k])
	for k in ["ground_map", "water_map", "amphibious_map", "deep_water_map"]:
		NavigationServer3D.free_rid(nav_with_bridge[k])

	if reached_no_bridge:
		print("  [FAIL] Without a bridge, a full-width water band should completely block ground crossing")
		return false
	if not reached_with_bridge:
		print("  [FAIL] With a bridge carved through the water, ground crossing should succeed")
		return false
	if not crosses_via_bridge_strip:
		print("  [FAIL] The crossing path should stay within the bridge's own x-footprint while passing through the water band, not some other route")
		return false
	if TerrainBuilder.terrain_height_at(map_with_bridge, Vector3(0, 0, 0)) <= 0.0:
		print("  [FAIL] terrain_height_at() should report a real positive deck height on the bridge, not ground level 0.0")
		return false

	print("  [PASS] A bridge carves a genuine, narrow ground crossing through an otherwise fully-blocking water band, and reports a real deck height.")
	return true

func test_building_obstacle_spawns_taller_real_cover_than_rock_cluster() -> bool:
	print("Running Test Suite: Urban Obstacles - 'building' Type Spawns Real, Taller Cover Distinct From Rock Clusters (Map Variety Batch)...")
	var TerrainBuilder = preload("res://scripts/terrain_builder.gd")
	var parent = Node3D.new()
	root.add_child(parent)
	var map_def = {
		"map_half_extents": 80.0,
		"obstacles": [
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(4, 4), "type": "rock"},
			{"center": Vector3(30, 0, 0), "half_extents": Vector2(4, 4), "type": "building", "building_height": 7.0},
		],
	}
	TerrainBuilder.spawn_visuals(map_def, parent)
	await tree.process_frame

	var rock_body = null
	var building_body = null
	for child in parent.get_children():
		if child is StaticBody3D:
			if child.global_position.x < 15:
				rock_body = child
			else:
				building_body = child
	if not rock_body or not building_body:
		print("  [FAIL] Expected one real StaticBody3D collider per obstacle, got rock=", rock_body, " building=", building_body)
		parent.queue_free()
		return false
	# Code-generated nodes get anonymous engine names (e.g. "@CollisionShape3D@N")
	# unless force_readable_name is passed to add_child(), so find the
	# CollisionShape3D child by type rather than by name.
	var rock_shape: BoxShape3D = null
	for child in rock_body.get_children():
		if child is CollisionShape3D: rock_shape = child.shape
	var building_shape: BoxShape3D = null
	for child in building_body.get_children():
		if child is CollisionShape3D: building_shape = child.shape
	if not is_equal_approx(rock_shape.size.y, 3.0):
		print("  [FAIL] rock obstacle collider height should stay 3.0 (unchanged behavior), got ", rock_shape.size.y)
		parent.queue_free()
		return false
	if building_shape.size.y < 6.9 or building_shape.size.y > 7.1:
		print("  [FAIL] building obstacle collider height should honor building_height=7.0, got ", building_shape.size.y)
		parent.queue_free()
		return false

	parent.queue_free()
	await tree.process_frame
	print("  [PASS] 'building' obstacles spawn a real, taller StaticBody3D collider honoring building_height, distinct from 'rock' obstacles' fixed height.")
	return true

func test_amphibious_navmesh_crosses_water() -> bool:
	print("Running Test Suite: Amphibious Navmesh - screw_drive Crosses Water In One Continuous Path...")
	var map_def = {
		"map_half_extents": 80.0,
		"water_areas": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(15, 40)}],
		"obstacles": [],
	}
	var nav = TerrainBuilder.build_navmeshes(map_def)
	await _await_nav_map(nav.ground_map)

	var start = Vector3(-30, 0, 0)
	var goal = Vector3(30, 0, 0)
	var ground_path = NavigationServer3D.map_get_path(nav.ground_map, start, goal, true)
	var amphibious_path = NavigationServer3D.map_get_path(nav.amphibious_map, start, goal, true)

	NavigationServer3D.free_rid(nav.ground_region)
	if nav.water_region.is_valid():
		NavigationServer3D.free_rid(nav.water_region)
	NavigationServer3D.free_rid(nav.amphibious_region)
	if nav.deep_water_region.is_valid():
		NavigationServer3D.free_rid(nav.deep_water_region)
	NavigationServer3D.free_rid(nav.ground_map)
	NavigationServer3D.free_rid(nav.water_map)
	NavigationServer3D.free_rid(nav.amphibious_map)
	NavigationServer3D.free_rid(nav.deep_water_map)

	# On ground_map (the water area is a hole), a straight line through the
	# 30-unit-wide lake isn't available - any real path has to detour a long
	# way around, or navigation may not even find a full route depending on
	# map bounds. On amphibious_map (water is walkable), the direct route
	# straight across is available - proof this is a genuinely different,
	# wider-terrain map, not a copy of ground_map.
	var ground_dist = 0.0
	for i in range(1, ground_path.size()):
		ground_dist += ground_path[i - 1].distance_to(ground_path[i])
	var amphibious_dist = 0.0
	for i in range(1, amphibious_path.size()):
		amphibious_dist += amphibious_path[i - 1].distance_to(amphibious_path[i])
	var direct_dist = start.distance_to(goal)

	if amphibious_path.size() < 2 or amphibious_dist > direct_dist * 1.1:
		print("  [FAIL] Amphibious path should go essentially straight across the water (direct=", direct_dist, "), got ", amphibious_dist, " over ", amphibious_path.size(), " points.")
		return false
	if ground_path.size() >= 2 and ground_dist < amphibious_dist * 1.5:
		print("  [FAIL] Ground-only path should detour meaningfully around the water instead of cutting through it like the amphibious path did. ground_dist=", ground_dist, " amphibious_dist=", amphibious_dist)
		return false

	print("  [PASS] Amphibious navmesh lets a screw_drive unit cross water directly (", amphibious_dist, " units), while the ground-only map can't take the same shortcut.")
	return true

func test_deep_water_navmesh_blocks_shallow_draught_hulls() -> bool:
	print("Running Test Suite: Hull Draught - Shallow Water Genuinely Blocks Deep-Draught Naval Hulls...")
	# A shallow_water_areas strip spans the FULL width of the lake, splitting
	# it into north/south halves - a deep-draught hull has no way around it
	# (this IS the entire body of water), so deep_water_map should have NO
	# connection between the two halves at all, while water_map (which
	# still includes shallow water as walkable) connects them fine.
	var map_def = {
		"map_half_extents": 80.0,
		"water_areas": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(15, 40)}],
		"shallow_water_areas": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(15, 3)}],
		"obstacles": [],
	}
	var nav = TerrainBuilder.build_navmeshes(map_def)
	await _await_nav_map(nav.ground_map)

	var north = Vector3(0, 0, 20)
	var south = Vector3(0, 0, -20)
	var shallow_capable_path = NavigationServer3D.map_get_path(nav.water_map, north, south, true)
	var deep_draught_path = NavigationServer3D.map_get_path(nav.deep_water_map, north, south, true)

	NavigationServer3D.free_rid(nav.ground_region)
	if nav.water_region.is_valid():
		NavigationServer3D.free_rid(nav.water_region)
	NavigationServer3D.free_rid(nav.amphibious_region)
	if nav.deep_water_region.is_valid():
		NavigationServer3D.free_rid(nav.deep_water_region)
	NavigationServer3D.free_rid(nav.ground_map)
	NavigationServer3D.free_rid(nav.water_map)
	NavigationServer3D.free_rid(nav.amphibious_map)
	NavigationServer3D.free_rid(nav.deep_water_map)

	var shallow_dist = 0.0
	for i in range(1, shallow_capable_path.size()):
		shallow_dist += shallow_capable_path[i - 1].distance_to(shallow_capable_path[i])
	var direct_dist = north.distance_to(south)
	if shallow_capable_path.size() < 2 or shallow_dist > direct_dist * 1.2:
		print("  [FAIL] A shallow-draught-capable path (water_map) should connect the two halves almost directly. size=", shallow_capable_path.size(), " dist=", shallow_dist, " direct=", direct_dist)
		return false

	# NavigationServer3D.map_get_path() on a disconnected map returns
	# either an empty/degenerate path or one that doesn't actually reach
	# the goal - either way, it must NOT be a real corridor answer close to
	# the direct distance.
	var deep_dist = 0.0
	for i in range(1, deep_draught_path.size()):
		deep_dist += deep_draught_path[i - 1].distance_to(deep_draught_path[i])
	var deep_reaches_goal = deep_draught_path.size() > 0 and deep_draught_path[deep_draught_path.size() - 1].distance_to(south) < 2.0
	if deep_reaches_goal and deep_dist < direct_dist * 1.2:
		print("  [FAIL] A deep-draught hull (deep_water_map) should NOT be able to cross the shallow strip splitting the lake - it's the only water there, no way around. got a path of dist=", deep_dist)
		return false

	print("  [PASS] A deep-draught hull's navmesh has no route across the shallow-water strip splitting the lake (genuinely blocked, not just slowed), while a shallow-draught-capable path crosses it directly.")
	return true

func test_map_open_plains_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Open Plains (start points legal, resources reachable, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("open_plains")
	if ok:
		print("  [PASS] Open Plains: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_lake_crossing_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Lake Crossing (same generic smoke test, run against the refactored default map)...")
	var ok = await _smoke_test_map("lake_crossing")
	if ok:
		print("  [PASS] Lake Crossing: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_highland_chokepoint_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Highland Chokepoint (start points legal, resources reachable, HQs mutually reachable through the flanking lanes, economy loop works)...")
	var ok = await _smoke_test_map("highland_chokepoint")
	if ok:
		print("  [PASS] Highland Chokepoint: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_coastal_strand_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Coastal Strand (start points legal, resources reachable, HQs mutually reachable around inland obstacles, economy loop works)...")
	var ok = await _smoke_test_map("coastal_strand")
	if ok:
		print("  [PASS] Coastal Strand: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_twin_bridges_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Twin Bridges (start points legal, resources reachable, HQs mutually reachable via a real bridge crossing, economy loop works)...")
	var ok = await _smoke_test_map("twin_bridges")
	if ok:
		print("  [PASS] Twin Bridges: legal start points, all resources reachable, HQs mutually reachable across the river via a bridge, factory production works.")
	return ok

func test_map_twin_summits_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Twin Summits (start points legal, resources reachable, both hills reachable, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("twin_summits")
	if ok:
		print("  [PASS] Twin Summits: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_close_quarters_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Close Quarters (start points legal, resources reachable through the 3 lanes, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("close_quarters")
	if ok:
		print("  [PASS] Close Quarters: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_urban_sprawl_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Urban Sprawl (start points legal, resources reachable through the street grid, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("urban_sprawl")
	if ok:
		print("  [PASS] Urban Sprawl: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_scattered_peaks_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Scattered Peaks (RTS_CORE_ROADMAP.md B8, ~550 half-extent, 4 heightmap plateaus, start points legal, resources reachable, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("scattered_peaks")
	if ok:
		print("  [PASS] Scattered Peaks: legal start points, all resources reachable, HQs mutually reachable, factory production works.")
	return ok

func test_map_ore_basin_smoke() -> bool:
	print("Running Test Suite: Map Smoke Test - Ore Basin (Chris's own C&C-crib resource redesign: 3 clustered fields - player-side, enemy-side, contested center - instead of scattered singleton nodes; start points legal, resources reachable, HQs mutually reachable, economy loop works)...")
	var ok = await _smoke_test_map("ore_basin")
	if ok:
		print("  [PASS] Ore Basin: legal start points, all 15 resource nodes (3 clustered fields) reachable, HQs mutually reachable, factory production works.")
	return ok

func test_b8_large_map_navmesh_bake_does_not_crash_recast() -> bool:
	print("Running Test Suite: Large Map (Scattered Peaks) Navmesh Bake Doesn't Crash Recast (RTS_CORE_ROADMAP.md B8)...")
	# Real bug found authoring this map: at 550 half-extent, Godot's own
	# NavigationMesh.cell_size DEFAULT (0.25) sizes Recast's internal voxel
	# heightfield to ~4400x4400 - not just slow, an outright SEGFAULT
	# (confirmed empirically, reproduced with a minimal isolated repro
	# before this fix). _nav_cell_size() widens the cell for anything
	# bigger than the ~300 half-extent every original map already used
	# safely - this test is the standing regression guard for that crash
	# class, not just a "does the map load" check.
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	MapCatalogScript.reset_cache_for_tests()
	TerrainBuilderScript.reset_heightmap_cache_for_tests()

	# Every original (<=300 half-extent) map keeps EXACTLY Godot's own
	# default cell_size - zero behavior change for maps that already worked.
	var small_map = {"map_half_extents": 300.0}
	if TerrainBuilderScript._nav_cell_size(small_map) != 0.25:
		print("  [FAIL] A map at or under 300 half-extent should keep Godot's own default cell_size (0.25), got ", TerrainBuilderScript._nav_cell_size(small_map))
		return false

	var map_def = MapCatalogScript.get_map("scattered_peaks")
	if TerrainBuilderScript._nav_cell_size(map_def) <= 0.25:
		print("  [FAIL] scattered_peaks (550 half-extent) should get a widened cell_size, got ", TerrainBuilderScript._nav_cell_size(map_def))
		return false

	# The actual bake - this is what used to segfault the whole process.
	var nav = TerrainBuilderScript.build_navmeshes(map_def)
	await _await_nav_map(nav.ground_map)

	# A region-map association check alone isn't enough here - a second
	# real bug found via the actual Skirmish scene (not this isolated
	# test): NavigationServer3D MAPS have their OWN cell_size/cell_height,
	# independent of the NavigationMesh resource assigned to one of their
	# regions, and region_set_navigation_mesh() silently REJECTS a
	# mismatched mesh while leaving the region-map association itself
	# "valid" - a real path query is the only way to prove the mesh was
	# genuinely accepted, not just that a region RID exists.
	var path = NavigationServer3D.map_get_path(nav.ground_map, Vector3(0, 0, 480), Vector3(0, 0, -480), true)
	if path.size() < 2:
		print("  [FAIL] scattered_peaks' ground navmesh should support a real HQ-to-HQ path query, got ", path.size(), " points - the navmesh may have been silently rejected (mismatched map/mesh cell_size).")
		return false

	NavigationServer3D.free_rid(nav.ground_region)
	NavigationServer3D.free_rid(nav.amphibious_region)
	NavigationServer3D.free_rid(nav.ground_map)
	NavigationServer3D.free_rid(nav.water_map)
	NavigationServer3D.free_rid(nav.amphibious_map)
	NavigationServer3D.free_rid(nav.deep_water_map)

	print("  [PASS] A 550-half-extent map's navmesh bakes successfully (this specific crash is what killed the whole test process before the fix) with widened cell_size, while smaller maps keep Godot's own default.")
	return true

func test_b10_spawn_assignment_picks_explicit_then_maximizes_separation() -> bool:
	print("Running Test Suite: B10 Spawn Assignment - Explicit Pick > Max Squared Distance > Random (RTS_CORE_ROADMAP.md B10)...")
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")

	# Three spawns on a line: a=0, b=100, c=200. Slot 0 explicitly picks
	# "a"; slot 1 has no explicit pick, so with team_separation on it should
	# maximize squared distance to what's already claimed (a) - c (dist 200)
	# beats b (dist 100), so it must pick "c", never b.
	var spawns = [
		{"id": "a", "hq": Vector3(0, 0, 0)},
		{"id": "b", "hq": Vector3(100, 0, 0)},
		{"id": "c", "hq": Vector3(200, 0, 0)},
	]
	var assignment = MapCatalogScript.assign_spawns(spawns, [0, 1], {0: "a"}, true)
	if assignment.get(0) != "a":
		print("  [FAIL] Slot 0's explicit pick 'a' should be honored, got ", assignment.get(0))
		return false
	if assignment.get(1) != "c":
		print("  [FAIL] Slot 1 (team_separation on, 'a' already claimed) should maximize squared distance and pick 'c' (dist 200) over 'b' (dist 100), got ", assignment.get(1))
		return false

	# An explicit pick wins even when it's NOT the distance-maximizing choice.
	var explicit_assignment = MapCatalogScript.assign_spawns(spawns, [0, 1], {0: "a", 1: "b"}, true)
	if explicit_assignment.get(1) != "b":
		print("  [FAIL] An explicit pick should win even over the distance-maximizing candidate, got ", explicit_assignment.get(1))
		return false

	# With team_separation OFF, slot 1's pick among the 2 remaining
	# candidates ('b'/'c') should be genuinely random, not always the
	# distance-maximizing 'c' - run enough seeded trials that landing on
	# 'b' at least once is a near-certainty if (and only if) the flag is
	# actually respected rather than ignored.
	var saw_b = false
	for seed_val in range(30):
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_val
		var no_sep_assignment = MapCatalogScript.assign_spawns(spawns, [0, 1], {0: "a"}, false, rng)
		if no_sep_assignment.get(1) == "b":
			saw_b = true
			break
	if not saw_b:
		print("  [FAIL] With team_separation off, slot 1 should sometimes land on 'b' (genuine randomness), not always 'c' (distance-maximizing) - the flag may be ignored")
		return false

	print("  [PASS] Spawn assignment honors explicit picks first, maximizes squared distance to claimed spawns when team_separation is on, and falls back to real randomness when it's off.")
	return true

func test_b10_spawn_fairness_lint_passes_real_maps_and_catches_bad_ones() -> bool:
	print("Running Test Suite: B10 Spawn Fairness Lint - Clears Every Bundled Map, Catches Synthetic Bad Ones (RTS_CORE_ROADMAP.md B10)...")
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	MapCatalogScript.reset_cache_for_tests()
	TerrainBuilderScript.reset_heightmap_cache_for_tests()

	# Every bundled map should already clear the lint - it's meant to
	# generalize the checks _smoke_test_map already proves per-map, not
	# introduce a new bar the existing roster hasn't cleared.
	for map_id in MapCatalogScript.get_map_ids():
		var map_def = MapCatalogScript.get_map(map_id)
		var nav = TerrainBuilderScript.build_navmeshes(map_def)
		await _await_nav_map(nav.ground_map)
		var errors = MapCatalogScript.lint_spawn_fairness(map_def, nav.ground_map)
		NavigationServer3D.free_rid(nav.ground_region)
		NavigationServer3D.free_rid(nav.amphibious_region)
		NavigationServer3D.free_rid(nav.ground_map)
		NavigationServer3D.free_rid(nav.water_map)
		NavigationServer3D.free_rid(nav.amphibious_map)
		NavigationServer3D.free_rid(nav.deep_water_map)
		if not errors.is_empty():
			print("  [FAIL] Bundled map '", map_id, "' should clear the fairness lint cleanly, got: ", errors)
			return false

	# Synthetic bad map #1: spawn 'a's HQ sits inside a water rect, and
	# there are no resource nodes at all - should trip both the blocked-
	# terrain check and the minimum-nearby-resources check.
	var blocked_map_def = {
		"map_half_extents": 100.0,
		"water_areas": [{"center": Vector3(0, 0, 0), "half_extents": Vector2(10, 10)}],
		"obstacles": [],
		"resource_nodes": [],
		"spawns": [
			{"id": "a", "hq": Vector3(0, 0, 0)},
			{"id": "b", "hq": Vector3(90, 0, 90)},
		],
	}
	var blocked_nav = TerrainBuilderScript.build_navmeshes(blocked_map_def)
	await _await_nav_map(blocked_nav.ground_map)
	var blocked_errors = MapCatalogScript.lint_spawn_fairness(blocked_map_def, blocked_nav.ground_map)
	NavigationServer3D.free_rid(blocked_nav.ground_region)
	NavigationServer3D.free_rid(blocked_nav.amphibious_region)
	NavigationServer3D.free_rid(blocked_nav.ground_map)
	NavigationServer3D.free_rid(blocked_nav.water_map)
	NavigationServer3D.free_rid(blocked_nav.amphibious_map)
	NavigationServer3D.free_rid(blocked_nav.deep_water_map)
	var found_blocked = false
	var found_resource = false
	for e in blocked_errors:
		if "blocked terrain" in e:
			found_blocked = true
		if "resource node" in e:
			found_resource = true
	if not found_blocked or not found_resource:
		print("  [FAIL] A spawn HQ on water with zero resource nodes should trip both the blocked-terrain and minimum-resources checks, got: ", blocked_errors)
		return false

	# Synthetic bad map #2: 3 spawns where one pair sits much closer than
	# the others (10 units vs. ~500-510) - should trip the pairwise
	# distance-variance check. Plenty of resources near every spawn and no
	# obstacles, so only the variance check is exercised.
	var lopsided_resources = []
	for hq_x in [0, 10, 510]:
		lopsided_resources.append({"position": Vector3(hq_x - 20, 0, 0), "type": "metal", "amount": 500})
		lopsided_resources.append({"position": Vector3(hq_x + 20, 0, 0), "type": "metal", "amount": 500})
	var lopsided_map_def = {
		"map_half_extents": 600.0,
		"water_areas": [],
		"obstacles": [],
		"resource_nodes": lopsided_resources,
		"spawns": [
			{"id": "a", "hq": Vector3(0, 0, 0)},
			{"id": "b", "hq": Vector3(10, 0, 0)},
			{"id": "c", "hq": Vector3(510, 0, 0)},
		],
	}
	var lopsided_nav = TerrainBuilderScript.build_navmeshes(lopsided_map_def)
	await _await_nav_map(lopsided_nav.ground_map)
	var lopsided_errors = MapCatalogScript.lint_spawn_fairness(lopsided_map_def, lopsided_nav.ground_map)
	NavigationServer3D.free_rid(lopsided_nav.ground_region)
	NavigationServer3D.free_rid(lopsided_nav.amphibious_region)
	NavigationServer3D.free_rid(lopsided_nav.ground_map)
	NavigationServer3D.free_rid(lopsided_nav.water_map)
	NavigationServer3D.free_rid(lopsided_nav.amphibious_map)
	NavigationServer3D.free_rid(lopsided_nav.deep_water_map)
	var found_variance = false
	for e in lopsided_errors:
		if "vary too much" in e:
			found_variance = true
	if not found_variance:
		print("  [FAIL] 3 spawns with one pair 10 units apart and the others ~500+ apart should trip the distance-variance check, got: ", lopsided_errors)
		return false

	print("  [PASS] Every bundled map clears the fairness lint cleanly; a spawn on blocked terrain with no nearby resources, and a lopsided 3-spawn distance spread, both get caught.")
	return true

func test_part_material_roles_differentiate_surfaces() -> bool:
	print("Running Test Suite: Part Materials - Roles Give Parts Different Substances, Not Just Different Paint...")
	var PartMaterials = preload("res://scripts/part_materials.gd")
	var VisualBuilder = preload("res://scripts/visual_builder.gd")
	var ok = true

	# Roles are resolved from the authored filename, which is what lets ~190
	# existing parts pick one up without editing their call sites.
	var expectations = {
		"hmg_barrel": "gunmetal",
		"basic_cannon": "steel",
		"heavy_laser_lens": "optics",
		"tread_belt_loop": "rubber",
		"hmg_ammo_drum": "brass",
		"muzzle_brake": "scorched",
		"coilgun_coil": "energized",
		"missile_pod_housing": "painted",
	}
	for part_name in expectations:
		var got = PartMaterials.role_for_part(part_name)
		if got != expectations[part_name]:
			print("  [FAIL] role_for_part('%s') = '%s', expected '%s'" % [part_name, got, expectations[part_name]])
			ok = false
	# Anything unrecognised must degrade to the default role, never to "".
	if PartMaterials.role_for_part("totally_unknown_modded_thing") != PartMaterials.DEFAULT_ROLE:
		print("  [FAIL] An unrecognised part name must fall back to DEFAULT_ROLE")
		ok = false

	# The actual defect being fixed: every part used to get a bare
	# StandardMaterial3D with only albedo_color set, i.e. Godot's default
	# metallic 0.0 / roughness 1.0 - matte plastic for a barrel, a lens and a
	# tyre alike. Assert they now differ in SURFACE, not just in colour.
	var tint = Color(0.4, 0.4, 0.4)
	var barrel = PartMaterials.get_material("gunmetal", tint)
	var lens = PartMaterials.get_material("optics", tint)
	var tyre = PartMaterials.get_material("rubber", tint)
	if is_equal_approx(barrel.metallic, tyre.metallic) or is_equal_approx(barrel.roughness, lens.roughness):
		print("  [FAIL] Roles are not actually differentiated (barrel/tyre metallic, barrel/lens roughness)")
		ok = false
	if barrel.metallic <= 0.0 or barrel.roughness >= 1.0:
		print("  [FAIL] gunmetal is still at Godot's matte-plastic defaults: metallic=%.2f roughness=%.2f" % [
			barrel.metallic, barrel.roughness])
		ok = false
	if tyre.metallic != 0.0:
		print("  [FAIL] rubber must not be metallic, got %.2f" % tyre.metallic)
		ok = false

	# Triplanar procedural texture, so the authored meshes need no UVs.
	if not barrel.uv1_triplanar or barrel.roughness_texture == null:
		print("  [FAIL] No triplanar roughness texture on a worn role")
		ok = false

	# Identity sharing is load-bearing: bake_module_visual() merges a battle
	# module's meshes grouped by material identity, so two parts of the same
	# role+tint must hand back the SAME resource, not equal copies.
	if PartMaterials.get_material("gunmetal", tint) != barrel:
		print("  [FAIL] Materials are not shared - the battle-side mesh merge would be defeated")
		ok = false

	# A high-tint role takes the caller's colour; a low-tint one stays its own
	# substance. This is what stops a barrel turning bright red just because
	# the weapon's catalog colour is.
	var red = Color(1.0, 0.0, 0.0)
	var painted_red = PartMaterials.get_material("painted", red)
	var barrel_red = PartMaterials.get_material("gunmetal", red)
	if painted_red.albedo_color.r < 0.8:
		print("  [FAIL] A painted part should take the requested colour, got ", painted_red.albedo_color)
		ok = false
	if barrel_red.albedo_color.r > 0.35:
		print("  [FAIL] A gunmetal barrel should stay gunmetal on a red weapon, got ", barrel_red.albedo_color)
		ok = false

	# And it has to actually reach a built weapon, not just the palette.
	var holder = Node3D.new()
	root.add_child(holder)
	var cd = ModuleCatalog.get_module_data("heavy_machine_gun")
	VisualBuilder.build_visual("heavy_machine_gun", holder, cd.size, cd.color, {})
	var distinct := {}
	for m in holder.find_children("*", "MeshInstance3D", true, false):
		if m.material_override != null:
			distinct[m.material_override.get_instance_id()] = true
	if distinct.size() < 2:
		print("  [FAIL] A built HMG uses only %d distinct material(s) - parts are not differentiated" % distinct.size())
		ok = false
	holder.free()

	if not ok:
		return false
	print("  [PASS] Parts resolve real material roles from their names, roles differ in surface response, materials are shared for the batch merge, and a built weapon carries several.")
	return true

func test_map_schema_validator() -> bool:
	print("Running Test Suite: Map Schema Validator (RTS_CORE_ROADMAP.md B1)...")

	var MapCatalogScript = preload("res://scripts/map_catalog.gd")

	# All 8 bundled maps should validate clean - zero errors, no exceptions,
	# same coverage a hand-written per-map assert would give but derived
	# entirely from FIELD_SPEC.
	var ids = MapCatalogScript.get_map_ids()
	if ids.size() < 8:
		print("  [FAIL] Expected at least 8 bundled maps, found ", ids.size())
		return false
	for id in ids:
		var errors = MapCatalogScript.validate_map(id)
		if not errors.is_empty():
			print("  [FAIL] Map '%s' failed validation: %s" % [id, errors])
			return false

	# Unknown map id.
	var unknown_errors = MapCatalogScript.validate_map("this_map_does_not_exist")
	if unknown_errors.is_empty():
		print("  [FAIL] validate_map() should report an error for an unknown map id.")
		return false

	# Three deliberately corrupted IN-MEMORY copies (validate_map_def()
	# takes a raw Dictionary, so none of this touches the real MAPS const),
	# kept as separate copies rather than stacked on one - a wrong-typed
	# map_half_extents would otherwise also suppress the bounds check below
	# (it needs a real number to compare against), which would silently
	# hide a real defect class instead of proving it's caught.
	var base_map = MapCatalogScript.get_map(MapCatalogScript.DEFAULT_MAP_ID)

	var bad_type_map = base_map.duplicate(true)
	bad_type_map["map_half_extents"] = "240" # was a number, now a String
	var bad_type_errors: Array = MapCatalogScript.validate_map_def(bad_type_map)
	var caught_bad_type = false
	for e in bad_type_errors:
		if "map_half_extents" in e and "number" in e:
			caught_bad_type = true
	if not caught_bad_type:
		print("  [FAIL] A String map_half_extents should be caught as a type error. Got: ", bad_type_errors)
		return false

	var typo_map = base_map.duplicate(true)
	typo_map["watre_blobs"] = typo_map["water_blobs"] # misspelled - "water_blobs" itself stays present, so this is a genuine extra unknown key
	var typo_errors: Array = MapCatalogScript.validate_map_def(typo_map)
	var caught_unknown_key = false
	for e in typo_errors:
		if "watre_blobs" in e:
			caught_unknown_key = true
	if not caught_unknown_key:
		print("  [FAIL] A misspelled field name should be caught as an unknown-key error. Got: ", typo_errors)
		return false

	var oob_map = base_map.duplicate(true)
	oob_map["resource_nodes"] = oob_map["resource_nodes"].duplicate(true)
	oob_map["resource_nodes"].append({"position": Vector3(99999, 0, 0), "type": "metal", "amount": 500})
	var oob_errors: Array = MapCatalogScript.validate_map_def(oob_map)
	var caught_out_of_bounds = false
	for e in oob_errors:
		if "resource_nodes" in e and "outside map_half_extents" in e:
			caught_out_of_bounds = true
	if not caught_out_of_bounds:
		print("  [FAIL] A resource node placed outside map_half_extents should be caught. Got: ", oob_errors)
		return false

	print("  [PASS] All 8 bundled maps validate clean via FIELD_SPEC; unknown map id, wrong-typed scalar, misspelled field, and out-of-bounds resource node are all caught.")
	return true

func test_b3_maps_are_json_and_byte_identical_to_the_old_const() -> bool:
	print("Running Test Suite: Maps Are JSON - Byte-Identical Deep-Equal vs. The Old Const (RTS_CORE_ROADMAP.md B3)...")

	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	MapCatalogScript.reset_cache_for_tests()

	# Checked-in snapshot of lake_crossing's values EXACTLY as they were
	# hardcoded in map_catalog.gd's old MAPS const, before the B3 JSON
	# migration - transcribed by hand from that commit, not derived from
	# the new loader, so this is a real independent check against a
	# transcription error in the generator script that produced the JSON.
	# All bare numeric leaves are float literals (not int) because JSON
	# round-trips every number as a float, and Godot's Dictionary/Array
	# deep-equality is NOT numerically coercive between int and float the
	# way scalar `==` is - confirmed empirically before writing this test.
	var expected_lake_crossing = {
		"schema_version": 1.0,
		"name": "Lake Crossing",
		"description": "A single lake splits the map roughly in two - ground units detour around it, naval units are confined to it. No high ground.",
		"map_half_extents": 240.0,
		"ground_color": Color(0.2, 0.26, 0.21),
		"water_blobs": [
			{"center": Vector3(54, 0, 0), "radius": 22.0, "irregularity": 0.3, "depth": 1.3, "shore_blend": 8.0},
		],
		"obstacles": [],
		"resource_nodes": [
			{"position": Vector3(-66, 0, 54), "type": "metal", "amount": 1200.0},
			{"position": Vector3(-84, 0, 36), "type": "metal", "amount": 1000.0},
			{"position": Vector3(66, 0, -54), "type": "metal", "amount": 1200.0},
			{"position": Vector3(84, 0, -36), "type": "metal", "amount": 1000.0},
			{"position": Vector3(0, 0, 0), "type": "crystal", "amount": 800.0},
			{"position": Vector3(-90, 0, -75), "type": "crystal", "amount": 700.0},
			{"position": Vector3(90, 0, 75), "type": "crystal", "amount": 700.0},
			{"position": Vector3(-15, 0, -24), "type": "metal", "amount": 900.0},
			{"position": Vector3(15, 0, 24), "type": "metal", "amount": 900.0},
		],
		"spawns": [
			{"id": "player", "hq": Vector3(0, 0, 102), "factory": Vector3(-30, 0, 90), "refinery": Vector3(27, 0, 84), "harvester": Vector3(18, 1.5, 72)},
			{"id": "enemy", "hq": Vector3(0, 0, -102), "factory": Vector3(30, 0, -90), "refinery": Vector3(-27, 0, -84), "harvester": Vector3(-18, 1.5, -72)},
		],
	}

	var WorldScaleScript = preload("res://scripts/world_scale.gd")
	# Chunk 19: get_map() now returns values multiplied by the map's
	# resolved world_scale (DEFAULT_WORLD_SCALE=4.0, and lake_crossing
	# declares no override). This test's whole purpose is checking raw JSON
	# transcription against historical values, which is orthogonal to that
	# multiplier - so it's reversed here via the SAME FIELD_SPEC-driven walk
	# _apply_world_scale() itself uses, just with the reciprocal factor,
	# rather than hand-converting every expected coordinate to a 4x world.
	var scaled = MapCatalogScript.get_map("lake_crossing")
	var loaded = MapCatalogScript._scale_dict(scaled, MapCatalogScript.FIELD_SPEC, 1.0 / WorldScaleScript.for_map(scaled))

	# spawns[].factory/refinery/harvester are NOT a simple multiplication
	# (the building-spacing fix after Chunk 19's playtest made them
	# hq-relative-offset-preserving instead - see FIELD_SPEC's own comment
	# on "spawns"), so the generic per-leaf reversal above leaves them as
	# their SCALED/compacted values, not the raw ones. Reversed by hand
	# here using the same relationship _compact_spawns() applied forward:
	# compacted = scaled_hq + (raw - raw_hq), so raw = reversed_hq +
	# (compacted - scaled_hq). loaded.spawns[].hq is already the correctly-
	# reversed raw_hq from the generic walk above; scaled.spawns[] still
	# holds the original compacted values to diff against.
	var reversed_spawns: Array = []
	for i in range(loaded.get("spawns", []).size()):
		var spawn: Dictionary = loaded.spawns[i].duplicate(true)
		var scaled_spawn: Dictionary = scaled.spawns[i]
		var reversed_hq: Vector3 = spawn.hq
		var scaled_hq: Vector3 = scaled_spawn.hq
		for key in ["factory", "refinery", "harvester"]:
			spawn[key] = reversed_hq + ((scaled_spawn[key] as Vector3) - scaled_hq)
		reversed_spawns.append(spawn)
	loaded["spawns"] = reversed_spawns

	# EVERY FIELD EXCEPT resource_nodes IS STILL A STRICT DEEP-EQUAL. That is what
	# this test is for: proving the const -> JSON migration did not corrupt a
	# value in transcription.
	#
	# resource_nodes is checked as a SUPERSET instead, because a map file is
	# content and content is supposed to grow - the 2026-08-07 resource rework
	# added lumber stands and oil wells to all ten maps. A strict equality here
	# would mean "no map may ever gain a deposit again", which is not a property
	# worth defending; "the nine originals are still exactly where they were" is.
	var loaded_nodes: Array = loaded.get("resource_nodes", [])
	var expected_nodes: Array = expected_lake_crossing["resource_nodes"]
	var loaded_rest: Dictionary = loaded.duplicate(true)
	var expected_rest: Dictionary = expected_lake_crossing.duplicate(true)
	loaded_rest.erase("resource_nodes")
	expected_rest.erase("resource_nodes")

	if loaded_rest != expected_rest:
		print("  [FAIL] JSON-loaded lake_crossing does not deep-equal the checked-in snapshot of the old const's values.")
		print("    Loaded:   ", loaded_rest)
		print("    Expected: ", expected_rest)
		return false

	for node_data in expected_nodes:
		if not loaded_nodes.has(node_data):
			print("  [FAIL] An original lake_crossing resource node is missing or altered: ", node_data)
			print("    Loaded nodes: ", loaded_nodes)
			return false

	# All 8 original bundled maps still present (the const had exactly 8) -
	# "at least 8" rather than "exactly 8" since B8 has since added more
	# (scattered_peaks) on top of the original migrated set.
	var ids = MapCatalogScript.get_map_ids()
	if ids.size() < 8:
		print("  [FAIL] Expected at least the 8 original maps loaded from res://data/maps/*.json, got ", ids.size(), ": ", ids)
		return false

	# Every map must validate clean through the exact same validator B1 built.
	for id in ids:
		var errors = MapCatalogScript.validate_map(id)
		if not errors.is_empty():
			print("  [FAIL] Map '", id, "' failed validation after loading from JSON: ", errors)
			return false

	print("  [PASS] lake_crossing deep-equals the old const's exact values (all %d original resource nodes intact, %d total now); every bundled map loads from JSON and validates clean."
		% [expected_nodes.size(), loaded_nodes.size()])
	return true

func test_b3_hand_broken_json_map_hard_fails_with_a_useful_message() -> bool:
	print("Running Test Suite: Hand-Broken Map JSON Hard-Fails With A Useful Message (RTS_CORE_ROADMAP.md B3)...")

	var MapCatalogScript = preload("res://scripts/map_catalog.gd")

	# A deliberately broken map file dropped into the REAL res://data/maps/
	# directory (D1: shipped content, hard-fail territory) - missing its
	# required "spawns" field entirely and has an unknown key, so both
	# defect classes get exercised by one broken file.
	var bad_path = "res://data/maps/__test_broken_map__.json"
	var bad_json = {
		"schema_version": 1,
		"name": "Broken Test Map",
		"description": "deliberately invalid",
		"map_half_extents": 100,
		"ground_color": [0.1, 0.1, 0.1],
		"this_key_does_not_exist_in_the_schema": true,
		# "spawns" deliberately omitted - required field missing
	}
	var f = FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(bad_json, "\t"))
	f.close()

	MapCatalogScript.reset_cache_for_tests()
	var ids = MapCatalogScript.get_map_ids()
	var err = MapCatalogScript.get_last_load_error() # read BEFORE the cleanup rescan below clears it
	DirAccess.remove_absolute(bad_path)
	MapCatalogScript.reset_cache_for_tests() # rescan again with the broken file gone, restoring normal state for every test after this one

	if "__test_broken_map__" in ids:
		print("  [FAIL] A map missing its required 'spawns' field should never enter the usable catalog.")
		return false

	if not ("__test_broken_map__" in err and "spawns" in err):
		print("  [FAIL] The hard-fail error should specifically name the broken file and the missing 'spawns' field. Got: '", err, "'")
		return false

	print("  [PASS] A hand-broken map JSON (missing a required field, plus an unknown key) is rejected - never enters the catalog - with a specific, useful error naming the file and the missing field.")
	return true

func test_b4_heightmap_terrain_pure_functions() -> bool:
	print("Running Test Suite: Heightmap-Backed Terrain - Pure Functions (RTS_CORE_ROADMAP.md B4)...")

	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	TerrainBuilderScript.reset_heightmap_cache_for_tests()

	var file = FileAccess.open("res://data/test_fixtures/terrain/test_terrain.json", FileAccess.READ)
	if not file:
		print("  [FAIL] Could not open the B4 test fixture map.")
		return false
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		print("  [FAIL] B4 test fixture map failed to parse as JSON.")
		return false
	file.close()
	# The fixture's terrain.features (hill/basin/plateau/ridge/ravine/
	# escarpment/cliff, laid out with clean spatial separation so no two
	# features' falloff zones overlap and stack) was generated via:
	#   python tools/terrain/build_terrain.py data/test_fixtures/terrain/test_terrain.json
	var map_def: Dictionary = json.get_data()
	# This fixture is read raw from disk, bypassing MapCatalog's decode/
	# _apply_world_scale entirely - so it carries no "world_scale" key, and
	# since Chunk 19 moved DEFAULT_WORLD_SCALE off 1.0, height_at()'s
	# WorldScaleScript.for_map(map_def) would otherwise silently treat this
	# genuinely-1x fixture as 4x, dividing its coordinates by 4 before
	# sampling the heightmap PNG. Explicit key keeps this fixture's
	# hand-authored feature coordinates meaning what they say.
	map_def["world_scale"] = 1.0

	# A known ravine (center [10,-35], width 4, depth 8) samples lower at
	# its center than at its rim (just past the half-width, still inside
	# the falloff transition) and near-flat well outside it.
	var ravine_center = TerrainBuilderScript.height_at(map_def, 10.0, -35.0)
	var ravine_rim = TerrainBuilderScript.height_at(map_def, 13.0, -35.0)
	var ravine_far = TerrainBuilderScript.height_at(map_def, 30.0, -35.0)
	if not (ravine_center < ravine_rim and ravine_rim < ravine_far + 0.5):
		print("  [FAIL] Ravine should sample lowest at its center, less low at its rim, near-flat outside it. Got center=", ravine_center, " rim=", ravine_rim, " far=", ravine_far)
		return false

	# A known escarpment (line at x=40, height 18, falloff 4, high side
	# x>40) has its steepest slope AT the transition (x=40) - should
	# exceed MAX_WALKABLE_SLOPE and therefore be blocked.
	if not TerrainBuilderScript.is_position_blocked(map_def, Vector3(40.0, 0.0, 0.0)):
		print("  [FAIL] The escarpment's steep transition should exceed MAX_WALKABLE_SLOPE and be blocked.")
		return false
	# Well clear of any feature, flat ground should NOT be blocked by slope.
	if TerrainBuilderScript.is_position_blocked(map_def, Vector3(-55.0, 0.0, 55.0)):
		print("  [FAIL] Flat ground far from every feature should not be slope-blocked.")
		return false

	# Bilinear sampling AT a pixel center (an exact integer world
	# coordinate, since the generator uses 1 pixel/world-unit) must match
	# the source PNG's own stored value exactly - not just approximately,
	# since tx=tz=0 there and the lerp is mathematically a no-op.
	var height_img = Image.load_from_file("res://data/test_fixtures/terrain/test_terrain_height.png")
	if not height_img:
		print("  [FAIL] Could not load the B4 test fixture heightmap PNG directly.")
		return false
	var half = map_def.map_half_extents
	var height_scale = map_def.terrain.height_scale
	for test_point in [Vector2(-40, -40), Vector2(-10, -35), Vector2(40, 0), Vector2(0, 0)]:
		var px = int(round(test_point.x + half))
		var pz = int(round(test_point.y + half))
		var direct_pixel_height = TerrainBuilderScript._decode_heightmap_pixel(height_img.get_pixel(px, pz)) * height_scale
		var via_height_at = TerrainBuilderScript.height_at(map_def, test_point.x, test_point.y)
		if abs(direct_pixel_height - via_height_at) > 0.0001:
			print("  [FAIL] Bilinear sample at pixel-exact coordinate ", test_point, " should match the source PNG's own pixel exactly. Direct=", direct_pixel_height, " via height_at()=", via_height_at)
			return false

	print("  [PASS] Ravine samples lowest at center; escarpment transition is slope-blocked while flat ground isn't; bilinear sampling at pixel centers matches the source PNG exactly.")
	return true

func test_b4_heightmap_leaves_unmigrated_maps_untouched() -> bool:
	print("Running Test Suite: Heightmap-Backed Terrain - Flag-Gated Per-Map (RTS_CORE_ROADMAP.md B4/B6)...")

	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	TerrainBuilderScript.reset_heightmap_cache_for_tests()

	# RTS_CORE_ROADMAP.md B6 migrated highland_chokepoint/twin_summits (the
	# only 2 of the original 8 bundled maps that used elevation_zones) onto
	# real heightmaps; B8's scattered_peaks was authored with a heightmap
	# from the start. Every other map still takes the analytic
	# noise+hills+water_blobs path. Confirm the flag gate reflects exactly
	# that split, not "on for everything" or "on for nothing."
	var has_heightmap_maps = ["highland_chokepoint", "twin_summits", "scattered_peaks"]
	for map_id in MapCatalogScript.get_map_ids():
		var map_def = MapCatalogScript.get_map(map_id)
		var has_heightmap = TerrainBuilderScript._get_heightmap_image(map_def) != null
		var should_have = map_id in has_heightmap_maps
		if has_heightmap != should_have:
			print("  [FAIL] Map '", map_id, "' heightmap presence should be ", should_have, ", got ", has_heightmap)
			return false

	print("  [PASS] Exactly the maps that author terrain.heightmap have a real heightmap loaded; every other map still takes the analytic path.")
	return true

func test_b5_heightmap_navmesh_rejects_steep_slope() -> bool:
	print("Running Test Suite: Heightmap-Backed Navmesh - Steep Slope Is A Real Hole (RTS_CORE_ROADMAP.md B5)...")

	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	TerrainBuilderScript.reset_heightmap_cache_for_tests()

	var file = FileAccess.open("res://data/test_fixtures/terrain/test_terrain.json", FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var map_def: Dictionary = json.get_data()
	# Read raw from disk, bypassing MapCatalog's _apply_world_scale - see
	# test_b4_heightmap_terrain_pure_functions' identical comment for why
	# this fixture needs an explicit world_scale=1.0 now that Chunk 19
	# moved the global default off 1.0.
	map_def["world_scale"] = 1.0

	var maps = TerrainBuilderScript.build_navmeshes(map_def)
	await _await_nav_map(maps.ground_map)

	# The fixture's cliff (line at x=52, height 18, hard near-zero
	# transition) makes a genuine navmesh hole - a point just before it and
	# a point just after it must NOT be connected.
	var before_cliff = Vector3(45, 0, 0)
	var after_cliff = Vector3(58, 0, 0)
	var path = NavigationServer3D.map_get_path(maps.ground_map, before_cliff, after_cliff, true)
	var reached_other_side = not path.is_empty() and path[path.size() - 1].distance_to(after_cliff) < 3.0
	if reached_other_side:
		print("  [FAIL] A point past the cliff should NOT be reachable from a point before it - the cliff should be a real navmesh hole, not just a Y-snap visual. Path: ", path)
		return false

	# Meanwhile, two points on the SAME flat side (well clear of every
	# feature's falloff) must still be normally connected - slope-rejection
	# shouldn't have turned the whole map into holes.
	var flat_a = Vector3(-55, 0, 55)
	var flat_b = Vector3(-55, 0, -55)
	var flat_path = NavigationServer3D.map_get_path(maps.ground_map, flat_a, flat_b, true)
	if flat_path.is_empty() or flat_path[flat_path.size() - 1].distance_to(flat_b) > 3.0:
		print("  [FAIL] Two points on flat ground, clear of every feature, should still be normally reachable. Path: ", flat_path)
		return false

	print("  [PASS] A heightmap-backed cliff is a genuine navmesh hole (unreachable across it), while flat ground elsewhere still paths normally.")
	return true

func test_world_scale_default_and_per_map_override() -> bool:
	print("Running Test Suite: WorldScale - Default Factor and Per-Map Override...")
	var WorldScaleScript = preload("res://scripts/world_scale.gd")

	# No map context (null, {}, or a map_def that never declared the key)
	# always falls back to DEFAULT_WORLD_SCALE - this is the "inert until
	# a later commit flips it" contract every other chunk in this pass
	# depends on.
	if WorldScaleScript.for_map(null) != WorldScaleScript.DEFAULT_WORLD_SCALE:
		print("  [FAIL] for_map(null) should return DEFAULT_WORLD_SCALE, got ", WorldScaleScript.for_map(null))
		return false
	if WorldScaleScript.for_map({}) != WorldScaleScript.DEFAULT_WORLD_SCALE:
		print("  [FAIL] for_map({}) should return DEFAULT_WORLD_SCALE, got ", WorldScaleScript.for_map({}))
		return false
	var undeclared_map := {"name": "Some Map", "map_half_extents": 210.0}
	if WorldScaleScript.for_map(undeclared_map) != WorldScaleScript.DEFAULT_WORLD_SCALE:
		print("  [FAIL] A map_def without a world_scale key should fall back to the default.")
		return false

	# A map that DOES declare world_scale overrides the default - the
	# per-map escape hatch for outlier maps (scattered_peaks etc). Uses a
	# value distinct from DEFAULT_WORLD_SCALE (4.0 as of Chunk 19) so the
	# override-vs-default distinction stays meaningful regardless of what
	# the default itself currently is.
	var overridden_map := {"name": "Huge Map", "world_scale": 8.0}
	if WorldScaleScript.for_map(overridden_map) != 8.0:
		print("  [FAIL] A map_def with world_scale=8.0 should override the default, got ", WorldScaleScript.for_map(overridden_map))
		return false

	# A malformed override (wrong type, zero, negative) must not poison
	# every downstream multiplication - fall back to the default instead
	# of propagating a zero/negative scale into the whole map.
	var bad_type_map := {"world_scale": "sixteen"}
	if WorldScaleScript.for_map(bad_type_map) != WorldScaleScript.DEFAULT_WORLD_SCALE:
		print("  [FAIL] A non-numeric world_scale should fall back to the default, got ", WorldScaleScript.for_map(bad_type_map))
		return false
	var zero_map := {"world_scale": 0.0}
	if WorldScaleScript.for_map(zero_map) != WorldScaleScript.DEFAULT_WORLD_SCALE:
		print("  [FAIL] world_scale=0.0 should fall back to the default, got ", WorldScaleScript.for_map(zero_map))
		return false
	var negative_map := {"world_scale": -2.0}
	if WorldScaleScript.for_map(negative_map) != WorldScaleScript.DEFAULT_WORLD_SCALE:
		print("  [FAIL] A negative world_scale should fall back to the default, got ", WorldScaleScript.for_map(negative_map))
		return false

	# The scaled_* helpers multiply by the resolved factor.
	if WorldScaleScript.scaled_f(6.0, overridden_map) != 48.0:
		print("  [FAIL] scaled_f(6.0) at world_scale=8.0 should be 48.0, got ", WorldScaleScript.scaled_f(6.0, overridden_map))
		return false
	if WorldScaleScript.scaled_v2(Vector2(1.0, 2.0), overridden_map) != Vector2(8.0, 16.0):
		print("  [FAIL] scaled_v2 did not scale both axes by the resolved factor.")
		return false
	if WorldScaleScript.scaled_v3(Vector3(1.0, 2.0, 3.0), overridden_map) != Vector3(8.0, 16.0, 24.0):
		print("  [FAIL] scaled_v3 did not scale all three axes by the resolved factor.")
		return false

	# Chunk 19: DEFAULT_WORLD_SCALE flipped from the Phase-1 inert 1.0 to
	# 4.0, the Phase-2 proving-ground value (16.0, the real target, is
	# Chunk 25). Pinned here rather than left as an assumption, since every
	# real bundled map (none declare an explicit world_scale override)
	# depends on this being the actual current default.
	if WorldScaleScript.DEFAULT_WORLD_SCALE != 4.0:
		print("  [FAIL] DEFAULT_WORLD_SCALE should be 4.0 (Chunk 19's proving-ground value), got ", WorldScaleScript.DEFAULT_WORLD_SCALE)
		return false
	if WorldScaleScript.scaled_f(6.0, null) != 24.0:
		print("  [FAIL] scaled_f with no map context should apply the current default (4.0), got ", WorldScaleScript.scaled_f(6.0, null))
		return false

	print("  [PASS] WorldScale defaults to 4.0 (Chunk 19), honours a valid per-map override, rejects malformed overrides, and its scaled_* helpers multiply correctly.")
	return true

# Deterministic per-zone RNG (_seeded_rng() hashes zone.center) means two
# scatter() calls against the SAME zone dict produce the exact same sequence
# of randf_range() draws regardless of prop_scale - so comparing prop sizes
# index-by-index between a prop_scale=1.0 run and a prop_scale=2.0 run is a
# real doubling check, not just "both non-empty."
func _greeble_box_sizes(parent: Node3D) -> Array:
	var sizes: Array = []
	for child in parent.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			sizes.append(child.mesh.size)
	return sizes

func test_greeble_prop_scale_is_inert_at_1_and_doubles_at_2() -> bool:
	print("Running Test Suite: TerrainGreebles - prop_scale Is Inert At 1.0, Exactly Doubles Geometry At 2.0...")
	var TerrainGreeblesScript = preload("res://scripts/terrain_greebles.gd")
	var zone = {"center": Vector3(40, 0, -30), "half_extents": Vector2(15, 15)}

	# Baseline: what today's (pre-Chunk-5) hardcoded literals would have
	# produced. scatter_shallow_water()/_scatter_tide_pool_rocks is
	# deliberately the subject here, not any of scatter()'s surface types:
	# it is the ONLY function in this file with a single loop and nothing
	# else - every surface_type in scatter() runs at least two passes
	# through the SAME shared RandomNumberGenerator, and Chunk 6 makes each
	# pass's iteration COUNT depend on prop_scale. A pass earlier in the
	# function consuming a different number of rng.randf_range() draws at
	# 1.0 vs 2.0 desyncs the rng stream for every pass after it - not just
	# across passes (which broke an earlier version of this test using
	# "rocky"), but even within what looked like a single BoxMesh pass
	# (which broke a second version using "snow_mud", where the earlier
	# SphereMesh mound pass silently desynced the later rut pass). A
	# function with exactly one loop and no earlier pass has nothing to
	# desync against.
	var parent_default = Node3D.new()
	root.add_child(parent_default)
	TerrainGreeblesScript.scatter_shallow_water(zone, parent_default) # prop_scale defaults to 1.0
	var default_sizes = _greeble_box_sizes(parent_default)

	var parent_explicit_1 = Node3D.new()
	root.add_child(parent_explicit_1)
	TerrainGreeblesScript.scatter_shallow_water(zone, parent_explicit_1, 1.0)
	var explicit_1_sizes = _greeble_box_sizes(parent_explicit_1)

	if default_sizes.size() != explicit_1_sizes.size() or default_sizes.size() == 0:
		print("  [FAIL] Expected the same non-zero number of BoxMesh props at the default and explicit prop_scale=1.0, got ", default_sizes.size(), " vs ", explicit_1_sizes.size())
		parent_default.queue_free()
		parent_explicit_1.queue_free()
		return false
	for i in range(default_sizes.size()):
		if not default_sizes[i].is_equal_approx(explicit_1_sizes[i]):
			print("  [FAIL] prop_scale=1.0 must be visually IDENTICAL to the old hardcoded sizes - prop ", i, ": ", default_sizes[i], " vs ", explicit_1_sizes[i])
			parent_default.queue_free()
			parent_explicit_1.queue_free()
			return false

	# NOTE: this compares per-prop SIZE only, not prop COUNT - Chunk 6 (see
	# test_greeble_density_holds_coverage_fraction_as_prop_scale_rises)
	# makes prop_scale also divide the scatter count by prop_scale^2, so at
	# 2.0 fewer props are placed than at 1.0. Both passes' loop counts are
	# read off in the exact same rng-draw ORDER regardless of how many
	# iterations run, so the props that DO survive at 2.0 still line up
	# index-for-index with the first N props at 1.0.
	var parent_2x = Node3D.new()
	root.add_child(parent_2x)
	TerrainGreeblesScript.scatter_shallow_water(zone, parent_2x, 2.0)
	var sizes_2x = _greeble_box_sizes(parent_2x)

	var ok = true
	if sizes_2x.is_empty():
		print("  [FAIL] Expected at least one surviving prop at prop_scale=2.0 to compare sizes against.")
		ok = false
	elif sizes_2x.size() > default_sizes.size():
		print("  [FAIL] prop_scale=2.0 should never place MORE props than prop_scale=1.0, got ", sizes_2x.size(), " vs ", default_sizes.size())
		ok = false
	else:
		for i in range(sizes_2x.size()):
			if not sizes_2x[i].is_equal_approx(default_sizes[i] * 2.0):
				print("  [FAIL] prop_scale=2.0 should exactly double every box dimension - prop ", i, ": expected ", default_sizes[i] * 2.0, ", got ", sizes_2x[i])
				ok = false
				break

	parent_default.queue_free()
	parent_explicit_1.queue_free()
	parent_2x.queue_free()
	if not ok:
		return false

	print("  [PASS] prop_scale=1.0 reproduces today's exact prop sizes, and prop_scale=2.0 doubles every dimension for every prop that survives Chunk 6's density scaling.")
	return true

func test_greeble_density_holds_coverage_fraction_as_prop_scale_rises() -> bool:
	print("Running Test Suite: TerrainGreebles - Scatter Density Divides By prop_scale^2 So Coverage Fraction Holds...")
	var TerrainGreeblesScript = preload("res://scripts/terrain_greebles.gd")

	# _scaled_count() itself is a pure function - test it directly rather
	# than through node counting, since it's the actual thing Chunk 6 adds
	# and a direct test pins its exact contract (inert at 1.0, divides by
	# scale^2, never negative, no divide-by-zero).
	if TerrainGreeblesScript._scaled_count(7, 1.0) != 7:
		print("  [FAIL] _scaled_count must be inert at prop_scale=1.0 - base count should pass through unchanged, got ", TerrainGreeblesScript._scaled_count(7, 1.0))
		return false
	if TerrainGreeblesScript._scaled_count(16, 4.0) != 1:
		print("  [FAIL] _scaled_count(16, 4.0) should divide by 4.0^2=16, got ", TerrainGreeblesScript._scaled_count(16, 4.0))
		return false
	if TerrainGreeblesScript._scaled_count(10, 0.0) < 0:
		print("  [FAIL] _scaled_count must not crash or go negative on a degenerate prop_scale of 0.0, got ", TerrainGreeblesScript._scaled_count(10, 0.0))
		return false

	# End-to-end through scatter(): a rocky zone (3 boulders + 10 small
	# rocks = 13 BoxMesh props at prop_scale=1.0) should place roughly
	# 13/16 props at prop_scale=4.0 - "roughly" because each of the two
	# passes rounds independently (3/16 rounds to 0, 10/16 rounds to 1).
	var zone = {"center": Vector3(-20, 0, 55), "half_extents": Vector2(15, 15), "surface_type": "rocky"}

	var parent_1x = Node3D.new()
	root.add_child(parent_1x)
	TerrainGreeblesScript.scatter(zone, parent_1x, 1.0)
	var count_1x = _greeble_box_sizes(parent_1x).size()

	var parent_4x = Node3D.new()
	root.add_child(parent_4x)
	TerrainGreeblesScript.scatter(zone, parent_4x, 4.0)
	var count_4x = _greeble_box_sizes(parent_4x).size()

	parent_1x.queue_free()
	parent_4x.queue_free()

	if count_1x != 13:
		print("  [FAIL] Test setup: expected the rocky zone's known base count of 13 props at prop_scale=1.0, got ", count_1x)
		return false
	# _scaled_count(3, 4.0) rounds to 0, _scaled_count(10, 4.0) rounds to 1 -
	# exactly 1 prop total survives at 4x, matching the per-pass rounding
	# the direct _scaled_count() calls above already pinned.
	var expected_4x = TerrainGreeblesScript._scaled_count(3, 4.0) + TerrainGreeblesScript._scaled_count(10, 4.0)
	if count_4x != expected_4x:
		print("  [FAIL] Expected ", expected_4x, " props at prop_scale=4.0 (sum of each pass's independently-rounded _scaled_count), got ", count_4x)
		return false

	print("  [PASS] _scaled_count is inert at 1.0 and divides by prop_scale^2, and scatter() end-to-end shrinks prop count accordingly without changing per-prop size logic.")
	return true

func test_spawn_visuals_threads_world_scale_into_every_greeble_call() -> bool:
	print("Running Test Suite: TerrainBuilder.spawn_visuals() - Resolved World Scale Reaches Every Greeble Call Site (Chunk 7)...")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

	# Two otherwise-identical maps, one EXPLICITLY at world_scale=1.0 (Chunk
	# 19 moved the global default off 1.0, so "no key" no longer means
	# "1.0" - an explicit key is required to keep testing a genuine
	# baseline) and one that opts into 2.0 via map_catalog.gd's Chunk-1
	# per-map override key. surface_zones' "rocky" boulder pass is the
	# subject - same reasoning as the direct TerrainGreebles tests above,
	# it's a real BoxMesh, and this only needs to prove the multiplier
	# ARRIVED at the greeble call, not re-litigate exact size math (that's
	# already covered directly against TerrainGreebles itself).
	var base_map = {
		"map_half_extents": 80.0,
		"world_scale": 1.0,
		"surface_zones": [
			{"center": Vector3(0, 0, 0), "half_extents": Vector2(15, 15), "surface_type": "rocky"},
		],
	}
	var scaled_map = base_map.duplicate(true)
	scaled_map["world_scale"] = 2.0

	var parent_default = Node3D.new()
	root.add_child(parent_default)
	TerrainBuilderScript.spawn_visuals(base_map, parent_default)
	await tree.process_frame

	var parent_scaled = Node3D.new()
	root.add_child(parent_scaled)
	TerrainBuilderScript.spawn_visuals(scaled_map, parent_scaled)
	await tree.process_frame

	# Both zones share the same zone dict (only the map's world_scale key
	# differs), so the boulder pass's FIRST prop is the same rng draw in
	# both - same alignment reasoning as the TerrainGreebles tests, and
	# valid here for the same reason (rocky's boulder pass runs before
	# anything else consumes the shared rng in this zone's scatter() call).
	var sizes_default: Array = []
	var sizes_scaled: Array = []
	for child in parent_default.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			sizes_default.append(child.mesh.size)
	for child in parent_scaled.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			sizes_scaled.append(child.mesh.size)

	parent_default.queue_free()
	parent_scaled.queue_free()

	if sizes_default.is_empty() or sizes_scaled.is_empty():
		print("  [FAIL] Test setup: expected at least one BoxMesh prop from the rocky zone in both maps, got ", sizes_default.size(), " vs ", sizes_scaled.size())
		return false
	if not sizes_scaled[0].is_equal_approx(sizes_default[0] * 2.0):
		print("  [FAIL] A map declaring world_scale=2.0 should produce greeble props exactly 2x the size of the same map at the default scale - expected ", sizes_default[0] * 2.0, ", got ", sizes_scaled[0])
		return false

	print("  [PASS] spawn_visuals() resolves the map's world_scale and threads it into the greeble call, so prop size actually tracks the map's declared scale.")
	return true

func test_tall_grassland_clutter_never_lands_on_the_navigable_interior() -> bool:
	print("Running Test Suite: Tall Grassland Clutter Stays Off The Navigable Interior (Chunk 8, CORE_DESIGN_LANGUAGE.md §2.1/§7.1)...")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

	# Flat, obstacle-free map: the ONLY non-navigable area is the outer edge
	# margin beyond half*0.94 (no hills means is_position_blocked() never
	# trips on slope here) - so any tall prop found strictly inside that
	# margin would be a real gate failure, not an artifact of this fixture.
	var map_def = {
		"map_half_extents": 100.0,
	}
	var parent = Node3D.new()
	root.add_child(parent)
	TerrainBuilderScript._spawn_grassland_clutter(map_def, parent)
	await tree.process_frame

	var half = 100.0
	var interior_bound = half * 0.94
	# _place_tall_brush() jitters each individual blade up to 0.4*prop_scale
	# off its clump's gate-checked center position - the GATE is checked
	# against the clump center, not each blade's final jittered position, so
	# a blade whose clump sits right at the boundary can render up to ~0.4m
	# on the interior side of interior_bound without that being a real gate
	# failure. Padding the interior check by that same jitter magnitude
	# (plus a hair of slack) tells a genuine violation (a clump placed deep
	# in the interior, which would be off by metres, not centimetres) apart
	# from this boundary rounding.
	const BLADE_JITTER_MAGNITUDE = 0.4
	var interior_bound_padded = interior_bound - BLADE_JITTER_MAGNITUDE - 0.1
	# Grass tufts (the only interior CylinderMesh producer) top out at
	# 0.42m; tall brush starts at 1.0m - comfortably separated, so a
	# threshold check is unambiguous rather than needing to inspect which
	# function placed a given node.
	const TALL_HEIGHT_THRESHOLD = 1.0
	var tall_seen = false
	var ok = true
	for child in parent.get_children():
		if not (child is MeshInstance3D and child.mesh is CylinderMesh):
			continue
		var height = child.mesh.height
		var on_interior = absf(child.global_position.x) <= interior_bound_padded and absf(child.global_position.z) <= interior_bound_padded
		if height >= TALL_HEIGHT_THRESHOLD:
			tall_seen = true
			if on_interior:
				print("  [FAIL] A tall-brush-height prop (height ", height, ") was placed on the navigable interior at ", child.global_position, " - it should only ever land in the edge margin or on a steep slope.")
				ok = false
				break

	parent.queue_free()
	if not ok:
		return false
	if not tall_seen:
		print("  [FAIL] Test setup: expected at least one tall-brush prop in the edge margin, found none - the tall pass may not be running.")
		return false

	print("  [PASS] Tall grassland clutter only ever appears in the edge margin/off-slope, never on the navigable interior where it would hide a unit mid-fight.")
	return true

func test_ground_noise_stretches_with_world_scale_not_just_amplifies() -> bool:
	print("Running Test Suite: Ground Noise Wavelength And Amplitude Both Track World Scale (Chunk 9)...")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

	# No hills/water_blobs/heightmap - isolates height_at() to the pure
	# noise term (GROUND_NOISE_AMPLITUDE * noise(freq * xz)), so the
	# relationship below is exact rather than muddied by other contributors.
	# map_base is EXPLICITLY world_scale=1.0 - Chunk 19 moved the global
	# default off 1.0, so omitting the key here would no longer test the
	# actual 1.0 baseline the "scale * height_at(base, xz/scale)" relation
	# below assumes.
	var map_base = {"name": "chunk9_noise_test", "map_half_extents": 200.0, "world_scale": 1.0}
	var map_scaled = {"name": "chunk9_noise_test", "map_half_extents": 200.0, "world_scale": 3.0}

	# height_at(scaled_map, x, z) should equal
	# scale * height_at(base_map, x/scale, z/scale) - the SAME underlying
	# noise field, just stretched (longer wavelength) and taller (bigger
	# amplitude) by the same factor, so a hill that was N units wide and 1
	# unit tall at scale=1 is 3N units wide and 3 units tall at scale=3,
	# preserving its shape rather than just its height.
	var scale = 3.0
	var sample_points = [Vector2(12.0, -7.0), Vector2(-40.0, 55.0), Vector2(0.5, 0.5)]
	for p in sample_points:
		var scaled_height = TerrainBuilderScript.height_at(map_scaled, p.x, p.y)
		var base_height = TerrainBuilderScript.height_at(map_base, p.x / scale, p.y / scale)
		var expected = base_height * scale
		if absf(scaled_height - expected) > 0.001:
			print("  [FAIL] At (", p.x, ",", p.y, "): expected height_at(scaled) == scale * height_at(base, xz/scale) == ", expected, ", got ", scaled_height)
			return false

	# Inert at the (current, default) scale of 1.0 - the exact behavior
	# every other test in this file that calls height_at()/is_position_
	# blocked() on a map without a world_scale key already depends on.
	var map_no_scale = {"name": "chunk9_noise_test_inert", "map_half_extents": 200.0}
	var height_a = TerrainBuilderScript.height_at(map_no_scale, 30.0, -18.0)
	var height_b = TerrainBuilderScript.height_at(map_no_scale, 30.0, -18.0)
	if not is_equal_approx(height_a, height_b):
		print("  [FAIL] height_at() should be deterministic for the same map/position, got ", height_a, " vs ", height_b)
		return false

	print("  [PASS] Ground noise wavelength and amplitude both scale with world_scale (a stretched/taller version of the same field, not just an amplified one), and stay exact at the default scale.")
	return true

func test_terrain_tile_density_scales_with_world_scale() -> bool:
	print("Running Test Suite: Terrain Texture Tile Density Tracks World Scale (Chunk 9)...")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	var footprint = Vector2(60.0, 60.0)

	var mat_default = TerrainBuilderScript._build_terrain_material("rocky", footprint)
	var mat_2x = TerrainBuilderScript._build_terrain_material("rocky", footprint, Color.WHITE, "", 2.0)

	# uv1_scale.xy = footprint / (TERRAIN_TILE_WORLD_SIZE * tile_scale) - a
	# LARGER tile_scale means the SAME baked texture tile now represents
	# more world-space, so fewer repeats fit across the same footprint: the
	# xy repeat count should be exactly HALF at tile_scale=2.0. .z is
	# deliberately excluded from this comparison - it's always a fixed 1.0
	# (there's no third UV axis for a flat terrain plane), never multiplied
	# by tile_scale, so halving it would be checking the wrong thing.
	var expected_xy = Vector2(mat_default.uv1_scale.x, mat_default.uv1_scale.y) * 0.5
	var got_xy = Vector2(mat_2x.uv1_scale.x, mat_2x.uv1_scale.y)
	if not got_xy.is_equal_approx(expected_xy):
		print("  [FAIL] tile_scale=2.0 should halve uv1_scale.xy (fewer texture repeats over the same footprint), expected ", expected_xy, ", got ", got_xy)
		return false
	if not is_equal_approx(mat_2x.uv1_scale.z, 1.0):
		print("  [FAIL] uv1_scale.z should stay a fixed 1.0 regardless of tile_scale - there's no third UV axis, got ", mat_2x.uv1_scale.z)
		return false

	var mat_explicit_1 = TerrainBuilderScript._build_terrain_material("rocky", footprint, Color.WHITE, "", 1.0)
	if not mat_explicit_1.uv1_scale.is_equal_approx(mat_default.uv1_scale):
		print("  [FAIL] tile_scale=1.0 should be identical to the default (no tile_scale argument), expected ", mat_default.uv1_scale, ", got ", mat_explicit_1.uv1_scale)
		return false

	print("  [PASS] tile_scale=1.0 is inert (matches the no-argument default), and tile_scale=2.0 halves texture repeat density as expected.")
	return true

# Explicit exceptions to "every vector3/vector2 field must carry scale:true".
# spawns[].factory/refinery/harvester are deliberately unflagged as of the
# building-spacing fix that followed Chunk 19's playtest: a base is unit-
# scale, not environment-scale, so _apply_world_scale()'s dedicated
# _compact_spawns() step repositions them at their ORIGINAL offset from the
# (still-scaled) hq anchor instead of scaling each one independently - see
# FIELD_SPEC's own comment on "spawns". Exists so a genuinely non-spatial
# vector field has somewhere to be named ON PURPOSE rather than the test
# below just being weakened to pass.
const CHUNK11_NON_SPATIAL_VECTOR_FIELDS: Array = [
	"spawns.factory", "spawns.refinery", "spawns.harvester",
]

func _walk_field_spec_for_unflagged_vectors(spec: Dictionary, path: String, violations: Array) -> void:
	for key in spec.keys():
		var leaf: Dictionary = spec[key]
		var full_path = path + key
		var t: String = leaf.get("type", "")
		if (t == "vector3" or t == "vector2") and not leaf.get("scale", false):
			if not (full_path in CHUNK11_NON_SPATIAL_VECTOR_FIELDS):
				violations.append(full_path)
		if leaf.has("item"):
			_walk_field_spec_for_unflagged_vectors(leaf["item"], full_path + ".", violations)

func test_every_spatial_field_in_field_spec_is_flagged_for_scaling() -> bool:
	print("Running Test Suite: map_catalog.FIELD_SPEC - Every vector3/vector2 Field Carries scale:true Or Is An Explicit Exception (Chunk 11)...")
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")

	var violations: Array = []
	_walk_field_spec_for_unflagged_vectors(MapCatalogScript.FIELD_SPEC, "", violations)
	if not violations.is_empty():
		print("  [FAIL] These vector3/vector2 fields have no scale:true flag and aren't in CHUNK11_NON_SPATIAL_VECTOR_FIELDS - either flag them or name them as a deliberate exception: ", violations)
		return false

	# Direct spot-check that the flag itself is actually readable off a few
	# known fields, not just "the walker found nothing wrong" (which would
	# also be true of a walker with a bug that visits nothing).
	if not MapCatalogScript.FIELD_SPEC["map_half_extents"].get("scale", false):
		print("  [FAIL] map_half_extents should carry scale:true.")
		return false
	if not MapCatalogScript.FIELD_SPEC["spawns"]["item"]["hq"].get("scale", false):
		print("  [FAIL] spawns[].hq should carry scale:true.")
		return false
	if MapCatalogScript.FIELD_SPEC["resource_nodes"]["item"]["amount"].get("scale", false):
		print("  [FAIL] resource_nodes[].amount is a balance number, not a distance - it should NOT carry scale:true.")
		return false

	print("  [PASS] Every vector3/vector2 field in FIELD_SPEC is flagged for scaling (or named as a deliberate exception), and non-spatial fields like resource amount stay unflagged.")
	return true

func test_apply_world_scale_is_inert_at_1_and_scales_flagged_fields_at_2() -> bool:
	print("Running Test Suite: map_catalog._apply_world_scale() - Hard No-Op At 1.0, Scales Flagged Fields Only At 2.0 (Chunk 12)...")
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")

	# Explicit world_scale:1.0 - Chunk 19 moved DEFAULT_WORLD_SCALE off 1.0,
	# so "no key" no longer means "world_scale=1.0" the way it did when this
	# test was first written. An explicit 1.0 keeps testing the genuine
	# no-op path regardless of what the global default currently is.
	var map_def = {
		"name": "chunk12_test",
		"map_half_extents": 100.0,
		"schema_version": 2.0,
		"world_scale": 1.0,
		"resource_nodes": [
			{"position": Vector3(10, 0, -5), "type": "metal", "amount": 500},
		],
		"spawns": [
			{"id": "player", "hq": Vector3(20, 0, 20), "factory": Vector3(25, 0, 20),
				"refinery": Vector3(15, 0, 20), "harvester": Vector3(20, 0, 15)},
		],
	}

	# At world_scale=1.0, this must be a hard no-op - not "multiplied by 1.0
	# and happens to compare equal," but literally the SAME Dictionary
	# instance returned unchanged, so no int->float widening or duplication
	# can sneak in.
	var same_ref = MapCatalogScript._apply_world_scale(map_def)
	if not is_same(same_ref, map_def):
		print("  [FAIL] At world_scale=1.0, _apply_world_scale() should return the SAME Dictionary instance, not a scaled/duplicated copy.")
		return false

	# A map with NO world_scale key at all now picks up the current global
	# default (4.0 as of Chunk 19), not 1.0 - the behavior
	# test_b3_maps_are_json_and_byte_identical_to_the_old_const's reversal
	# trick (1.0 / WorldScale.for_map(...)) depends on.
	var WorldScaleScript = preload("res://scripts/world_scale.gd")
	var no_key_map = map_def.duplicate(true)
	no_key_map.erase("world_scale")
	var no_key_result = MapCatalogScript._apply_world_scale(no_key_map)
	if is_same(no_key_result, no_key_map):
		print("  [FAIL] A map with no world_scale key should pick up the non-1.0 global default, not take the no-op path.")
		return false
	if no_key_result.map_half_extents != 100.0 * WorldScaleScript.DEFAULT_WORLD_SCALE:
		print("  [FAIL] A map with no world_scale key should scale by DEFAULT_WORLD_SCALE, expected ", 100.0 * WorldScaleScript.DEFAULT_WORLD_SCALE, ", got ", no_key_result.map_half_extents)
		return false

	# A map that opts into world_scale=2.0 gets every FLAGGED field doubled...
	var scaled_map = map_def.duplicate(true)
	scaled_map["world_scale"] = 2.0
	var result = MapCatalogScript._apply_world_scale(scaled_map)

	if result.map_half_extents != 200.0:
		print("  [FAIL] map_half_extents should double at world_scale=2.0, got ", result.map_half_extents)
		return false
	if not (result.resource_nodes[0].position as Vector3).is_equal_approx(Vector3(20, 0, -10)):
		print("  [FAIL] resource_nodes[].position should double, got ", result.resource_nodes[0].position)
		return false
	if not (result.spawns[0].hq as Vector3).is_equal_approx(Vector3(40, 0, 40)):
		print("  [FAIL] spawns[].hq should double, got ", result.spawns[0].hq)
		return false

	# ...but factory/refinery/harvester are COMPACTED, not independently
	# scaled: each keeps its ORIGINAL offset from hq (factory was +5 on x,
	# refinery -5 on x, harvester -5 on z), now measured from hq's NEW
	# doubled position - not doubled themselves. A base stays the same
	# physical size regardless of world_scale.
	if not (result.spawns[0].factory as Vector3).is_equal_approx(Vector3(45, 0, 40)):
		print("  [FAIL] spawns[].factory should keep its original +5x offset from the scaled hq (45,0,40), not double to (50,0,40) - got ", result.spawns[0].factory)
		return false
	if not (result.spawns[0].refinery as Vector3).is_equal_approx(Vector3(35, 0, 40)):
		print("  [FAIL] spawns[].refinery should keep its original -5x offset from the scaled hq (35,0,40), got ", result.spawns[0].refinery)
		return false
	if not (result.spawns[0].harvester as Vector3).is_equal_approx(Vector3(40, 0, 35)):
		print("  [FAIL] spawns[].harvester should keep its original -5z offset from the scaled hq (40,0,35), got ", result.spawns[0].harvester)
		return false

	# ...and every UNFLAGGED field stays exactly as authored - the whole
	# point of Chunk 11's flag list existing at all.
	if result.resource_nodes[0].amount != 500:
		print("  [FAIL] resource_nodes[].amount is a balance number, not a distance - it must NOT scale, got ", result.resource_nodes[0].amount)
		return false
	if result.schema_version != 2.0:
		print("  [FAIL] schema_version must NOT scale, got ", result.schema_version)
		return false
	if result.name != "chunk12_test":
		print("  [FAIL] name (a string field) must be untouched, got ", result.name)
		return false

	print("  [PASS] _apply_world_scale() is a true no-op at world_scale=1.0, picks up the non-1.0 global default when no key is present, and at 2.0 scales only FIELD_SPEC-flagged fields, leaving balance numbers and strings exactly as authored.")
	return true

func test_spawn_fairness_lint_passes_a_real_map_scaled_up_4x() -> bool:
	print("Running Test Suite: Spawn Fairness Lint Clears A Real Map At world_scale=4.0 (Chunk 13)...")
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	MapCatalogScript.reset_cache_for_tests()
	TerrainBuilderScript.reset_heightmap_cache_for_tests()

	# open_plains at world_scale=1.0 already clears the lint (see the B10
	# suite above) - the real question this test answers is whether it
	# STILL clears once every position/extent has been quadrupled by
	# Chunk 12's _apply_world_scale(). Without Chunk 13's fix,
	# FAIRNESS_HQ_REACHABLE_MARGIN stays a fixed 12.0 world units while the
	# navmesh's own quantization slop (terrain_builder.gd's GRID_CELL,
	# which scales with world_scale) grows - eventually reading two
	# perfectly fine spawns as "not mutually reachable" purely from grid
	# slop, not a real fairness problem.
	#
	# get_map() now applies DEFAULT_WORLD_SCALE (4.0 as of Chunk 19)
	# automatically, so it's reversed back to the raw 1x values first (same
	# trick as test_b3_maps_are_json_and_byte_identical_to_the_old_const)
	# before applying the explicit 4.0 this test actually wants to isolate -
	# otherwise this would silently test 16x (4.0 default * 4.0 override)
	# instead of the 4x its own name promises.
	var WorldScaleScript = preload("res://scripts/world_scale.gd")
	var default_scaled_map = MapCatalogScript.get_map("open_plains")
	var base_map = MapCatalogScript._scale_dict(default_scaled_map, MapCatalogScript.FIELD_SPEC, 1.0 / WorldScaleScript.for_map(default_scaled_map))
	var scaled_map = base_map.duplicate(true)
	scaled_map["world_scale"] = 4.0
	scaled_map = MapCatalogScript._apply_world_scale(scaled_map)

	var nav = TerrainBuilderScript.build_navmeshes(scaled_map)
	await _await_nav_map(nav.ground_map)
	var errors = MapCatalogScript.lint_spawn_fairness(scaled_map, nav.ground_map)
	NavigationServer3D.free_rid(nav.ground_region)
	NavigationServer3D.free_rid(nav.amphibious_region)
	NavigationServer3D.free_rid(nav.ground_map)
	NavigationServer3D.free_rid(nav.water_map)
	NavigationServer3D.free_rid(nav.amphibious_map)
	NavigationServer3D.free_rid(nav.deep_water_map)

	if not errors.is_empty():
		print("  [FAIL] open_plains at world_scale=4.0 should still clear the fairness lint (scale-relative margin), got: ", errors)
		return false

	print("  [PASS] A real map scaled 4x still clears spawn fairness - the reachability margin grew with it instead of staying a fixed absolute value.")
	return true

func test_scattered_peaks_navmesh_bakes_cleanly_at_world_scale_4() -> bool:
	print("Running Test Suite: scattered_peaks Navmesh Still Bakes Cleanly At world_scale=4.0 (Chunk 14)...")
	# scattered_peaks (550 half-extent) is the map that ORIGINALLY segfaulted
	# Recast at its native size (see test_b8 above) - the standing regression
	# guard for that crash class. This is the same guard at 4x the size, to
	# confirm _nav_grid_cell()/_nav_cell_size() are self-bounding (a pure
	# function of map_half_extents, which now grows with world_scale) rather
	# than needing their own re-tuned constants for a scaled-up map.
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	MapCatalogScript.reset_cache_for_tests()
	TerrainBuilderScript.reset_heightmap_cache_for_tests()

	# Same reversal as test_spawn_fairness_lint_passes_a_real_map_scaled_up_4x
	# above: get_map() already applies DEFAULT_WORLD_SCALE (4.0), so it's
	# undone first or this would test 16x instead of the 4x this test name
	# promises.
	var WorldScaleScript = preload("res://scripts/world_scale.gd")
	var default_scaled_map = MapCatalogScript.get_map("scattered_peaks")
	var base_map = MapCatalogScript._scale_dict(default_scaled_map, MapCatalogScript.FIELD_SPEC, 1.0 / WorldScaleScript.for_map(default_scaled_map))
	var scaled_map = base_map.duplicate(true)
	scaled_map["world_scale"] = 4.0
	scaled_map = MapCatalogScript._apply_world_scale(scaled_map)

	var scaled_half: float = scaled_map.get("map_half_extents", 0.0)
	if absf(scaled_half - base_map.get("map_half_extents", 0.0) * 4.0) > 0.01:
		print("  [FAIL] Test setup: expected map_half_extents to be exactly 4x the base map's, got ", scaled_half, " vs base ", base_map.get("map_half_extents", 0.0))
		return false

	# The actual bake - this is what would segfault without the self-
	# bounding property _nav_cell_size()/_nav_grid_cell() document.
	var nav = TerrainBuilderScript.build_navmeshes(scaled_map)
	await _await_nav_map(nav.ground_map)

	# Real path query, same reasoning as test_b8 above: a region-map
	# association check alone can't prove the mesh was genuinely accepted
	# (region_set_navigation_mesh() silently rejects a cell_size mismatch
	# while leaving the association looking "valid").
	var far = scaled_half * 0.87 # inside the map, well clear of the edge
	var path = NavigationServer3D.map_get_path(nav.ground_map, Vector3(0, 0, far), Vector3(0, 0, -far), true)

	NavigationServer3D.free_rid(nav.ground_region)
	NavigationServer3D.free_rid(nav.amphibious_region)
	NavigationServer3D.free_rid(nav.ground_map)
	NavigationServer3D.free_rid(nav.water_map)
	NavigationServer3D.free_rid(nav.amphibious_map)
	NavigationServer3D.free_rid(nav.deep_water_map)

	if path.size() < 2:
		print("  [FAIL] scattered_peaks at world_scale=4.0 should still support a real long-distance path query, got ", path.size(), " points.")
		return false

	print("  [PASS] scattered_peaks bakes cleanly and supports real pathing at 4x its native size - the grid-cell formulas are self-bounding, not tuned to a fixed map size.")
	return true

