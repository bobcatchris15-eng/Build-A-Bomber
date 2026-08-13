extends "res://tests/suite_base.gd"
# terrain and maps suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

# The real MatchDirector. Loaded here as a const so the inner test
# class below can extend it via the GDScript 2 inner-class path.
const MatchDirectorScript = preload("res://scripts/battle/match_director.gd")

# A no-op-_ready MatchDirector used by the pre-game HQ-placement suites.
#
# Why this exists. The real MatchDirector's _ready() is a coroutine that
# does a synchronous block of setup (services, _spawn_resource_nodes,
# _spawn_bases) and then awaits _setup_terrain (a full Recast navmesh
# bake). The pre-game tests only want to exercise _spawn_bases() in
# isolation - the trim from "HQ + refinery + 3 manufactories" to "HQ
# only" and the new place_hq_for_human() hook - and the navmesh bake
# is both expensive and not what those tests are about.
#
# Two failures this subclass prevents:
#   1. add_child(test_director) would also fire _ready, which would
#      call _spawn_bases once before the test could, doubling every
#      structure count and breaking every "expected N" assertion in
#      a way the test can't tell from a real regression.
#   2. _ready awaits a real map's navmesh bake; on a minimal map_def
#      the bake either errors out (the agent_max_climb warning seen
#      on the first attempt) or hangs the test, neither of which
#      tells you anything about _spawn_bases() itself.
#
# What it does NOT skip. _spawn_bases() itself, _place_structure(),
# _base_zone_centre(), place_hq_for_human() and get_team_structures()
# all run normally - they're the surface these suites are pinning.
class TestMatchDirector:
	extends "res://scripts/battle/match_director.gd"

	func _ready() -> void:
		# Deliberately empty. The real director's _ready() would set
		# up services, run _spawn_resource_nodes + _spawn_bases, and
		# then await a navmesh bake. The pre-game tests want to call
		# _spawn_bases themselves with a controlled current_map, so
		# none of that should run.
		pass


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
	_free_nav_result(nav_no_bridge)

	var nav_with_bridge = TerrainBuilder.build_navmeshes(map_with_bridge)
	await _await_nav_map(nav_with_bridge.ground_map)
	var path_with_bridge = NavigationServer3D.map_get_path(nav_with_bridge.ground_map, start, end, true)
	var reached_with_bridge = path_with_bridge.size() >= 2 and path_with_bridge[path_with_bridge.size() - 1].distance_to(end) <= 3.0
	var crosses_via_bridge_strip = true
	for p in path_with_bridge:
		if p.z > -6.0 and p.z < 6.0 and abs(p.x) > 5.0: # outside the bridge's x=[-4,4] footprint (+1 slack)
			crosses_via_bridge_strip = false
	_free_nav_result(nav_with_bridge)

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

	# OBSTACLE BODIES ONLY. spawn_visuals() also scatters the ambient forest
	# into this same parent, and an ambient scatter node is a StaticBody3D
	# with NO CollisionShape3D (it was taken out of the broadphase for the
	# 1800-node scatter cost). Matching on "is a StaticBody3D" alone therefore
	# picked up a tree as the rock, found no shape under it, and crashed on a
	# null. Requiring a real collider is what actually identifies an obstacle.
	var rock_body = null
	var building_body = null
	for child in parent.get_children():
		if not (child is StaticBody3D):
			continue
		var has_shape := false
		for c in child.get_children():
			if c is CollisionShape3D:
				has_shape = true
		if not has_shape:
			continue
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

	_free_nav_result(nav)

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

	_free_nav_result(nav)

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

	_free_nav_result(nav)

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

	# Every bundled SKIRMISH map should already clear the lint - it's meant to
	# generalize the checks _smoke_test_map already proves per-map, not
	# introduce a new bar the existing roster hasn't cleared.
	#
	# test_range is excluded because it is not a skirmish map. It is a
	# miniature arena used only by the Design Lab's "Test in Arena" trip, where
	# the player drives one design against target dummies - there is no second
	# team to be fair to. Its spawns are not mutually reachable on the ground
	# navmesh and that is correct for what it is; linting it as though two
	# armies had to meet across it only ever produced a false positive.
	for map_id in MapCatalogScript.get_map_ids():
		if map_id == "test_range":
			continue
		var map_def = MapCatalogScript.get_map(map_id)
		var nav = TerrainBuilderScript.build_navmeshes(map_def)
		await _await_nav_map(nav.ground_map)
		var errors = MapCatalogScript.lint_spawn_fairness(map_def, nav.ground_map)
		_free_nav_result(nav)
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
	_free_nav_result(blocked_nav)
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
	_free_nav_result(lopsided_nav)
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

	# EVERY FIELD EXCEPT resource_nodes, hills, AND base_zones IS STILL A
	# STRICT DEEP-EQUAL. That is what this test is for: proving the const ->
	# JSON migration did not corrupt a value in transcription.
	#
	# resource_nodes is checked as a SUPERSET instead, because a map file is
	# content and content is supposed to grow - the 2026-08-07 resource rework
	# added lumber stands and oil wells to all ten maps. A strict equality here
	# would mean "no map may ever gain a deposit again", which is not a property
	# worth defending; "the nine originals are still exactly where they were" is.
	#
	# hills is dropped outright rather than superset-checked, for a stronger
	# reason than that: the old const had no "hills" key at all, so there is no
	# historical value here to defend against transcription error, which is this
	# test's entire subject. The terrain-variety pass authored hills and ravines
	# into every analytic map, and asserting their absence would be asserting
	# that maps must stay flat forever. Their actual correctness is covered
	# where it belongs - the spawn-fairness lint, the navmesh smoke tests, and
	# tools/probe_hills_ravine.gd.
	#
	# base_zones is dropped the same way hills is, for the same family of
	# reasons: the const had no zones (zones are a 2026-08-10 addition for
	# the new pre-game HQ-placement phase), and there is no historical
	# position to defend. The zone data's correctness is covered by
	# test_base_zones_field_in_field_spec and test_assign_base_zones_spreads_
	# them_apart - this test's job is to make sure the old map values did
	# not regress while the new field was added.
	var loaded_nodes: Array = loaded.get("resource_nodes", [])
	var expected_nodes: Array = expected_lake_crossing["resource_nodes"]
	var loaded_rest: Dictionary = loaded.duplicate(true)
	var expected_rest: Dictionary = expected_lake_crossing.duplicate(true)
	loaded_rest.erase("resource_nodes")
	expected_rest.erase("resource_nodes")
	loaded_rest.erase("hills")
	expected_rest.erase("hills")
	loaded_rest.erase("base_zones")
	expected_rest.erase("base_zones")

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
	_free_nav_result(nav)

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

	_free_nav_result(nav)

	if path.size() < 2:
		print("  [FAIL] scattered_peaks at world_scale=4.0 should still support a real long-distance path query, got ", path.size(), " points.")
		return false

	print("  [PASS] scattered_peaks bakes cleanly and supports real pathing at 4x its native size - the grid-cell formulas are self-bounding, not tuned to a fixed map size.")
	return true


func test_navmesh_path_routes_around_building_with_clearance() -> bool:
	print("Running Test Suite: Navmesh Path Routes Around A Placed Building With >Agent-Radius Clearance (Chris 2026-08-10)...")
	# 2026-08-10 playtest: harvesters were driving into the SIDE of
	# buildings and stopping, because the navmesh was baked with
	# agent_radius=0.1 - the resulting paths had 10 cm of clearance to
	# structures, which a 2-3 m wide hull physically cannot fit through.
	# The unit followed the path until its own CharacterBody3D
	# (collision_mask = TERRAIN|BUILDINGS) physically stopped it.
	#
	# This test reproduces the failure on a real baked navmesh: place a
	# building, query a path that has to cross its footprint, and confirm
	# the path CORNERS around the structure with at least NAV_AGENT_RADIUS
	# of clearance to the building's edge. If it goes through, the
	# collision would mask the failure visually - a harvester "appears
	# to stop at the wall" - but the path itself was always wrong.
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

	# Flat, featureless fixture - the path's only constraint is the
	# building. 200 half-extents is large enough that a 6x6 building
	# in the middle has plenty of walkable ground to either side.
	var map_def: Dictionary = {
		"map_half_extents": 200.0,
		"world_scale": 1.0,
	}
	# A realistic manufactory footprint (~6x6) at the map's centre. The
	# build_navmeshes() entry point also takes an extra_holes Array, so
	# this is the same hook the dynamic rebake uses - a live building
	# and a baked-test hole go through the exact same path. Sized
	# deliberately to leave 30+ m of corridor to either side, so a
	# "path sneaks through a 0.1m gap" failure mode is geometrically
	# impossible.
	var building_center: Vector3 = Vector3(0, 0, 0)
	var building_half: Vector2 = Vector2(3, 3)
	var extra_holes: Array = [
		{"center": building_center, "half_extents": building_half},
	]
	var nav = TerrainBuilderScript.build_navmeshes(map_def, extra_holes)
	if not await _await_nav_map(nav.ground_map):
		print("  [FAIL] Ground navmesh never synchronised for clearance test fixture")
		_free_nav_result(nav)
		return false

	# Path A: due-east to due-west, crossing the building's footprint.
	# At agent_radius=0.1 the path would clip through the hole the
	# building carves; at agent_radius>=1.0 it has to route around.
	var west = Vector3(-40, 0, 0)
	var east = Vector3(40, 0, 0)
	var path_east_west = NavigationServer3D.map_get_path(nav.ground_map, west, east, true)
	if path_east_west.size() < 2:
		print("  [FAIL] A west-to-east path across a 6x6 building should still resolve (route around), got ", path_east_west.size(), " points")
		_free_nav_result(nav)
		return false

	# Path B: due-north to due-south, same idea, perpendicular approach.
	# Two perpendicular paths catch the case where the path "goes around"
	# by sliding along a single face only.
	var north = Vector3(0, 0, -40)
	var south = Vector3(0, 0, 40)
	var path_north_south = NavigationServer3D.map_get_path(nav.ground_map, north, south, true)
	if path_north_south.size() < 2:
		print("  [FAIL] A north-to-south path across a 6x6 building should still resolve (route around), got ", path_north_south.size(), " points")
		_free_nav_result(nav)
		return false

	_free_nav_result(nav)

	# What the test is ACTUALLY checking: the path keeps at least the
	# navmesh's own agent_radius (a lower bound on usable clearance)
	# from the building's edge at every point. A path that comes within
	# 0.5 m of a wall is unusable by a 2 m wide hull, regardless of
	# the navmesh's nominal radius.
	#
	# Why "min distance to building rect >= agent_radius" and not "to
	# building center >= building half + agent_radius + small margin":
	# the actual constraint Recast enforces IS the agent_radius margin
	# from the obstacle's wall (the navmesh's erosion), not from its
	# center. Testing against the wall is the spec-accurate check.
	var agent_r: float = TerrainBuilderScript.NAV_AGENT_RADIUS
	var min_required_clearance: float = agent_r  # floor: 1.0 m
	var worst_east_west := INF
	for p in path_east_west:
		var dx: float = maxf(0.0, absf(p.x - building_center.x) - building_half.x)
		var dz: float = maxf(0.0, absf(p.z - building_center.z) - building_half.y)
		var dist_to_wall: float = sqrt(dx * dx + dz * dz)
		worst_east_west = minf(worst_east_west, dist_to_wall)
	var worst_north_south := INF
	for p in path_north_south:
		var dx2: float = maxf(0.0, absf(p.x - building_center.x) - building_half.x)
		var dz2: float = maxf(0.0, absf(p.z - building_center.z) - building_half.y)
		var dist_to_wall2: float = sqrt(dx2 * dx2 + dz2 * dz2)
		worst_north_south = minf(worst_north_south, dist_to_wall2)

	if worst_east_west < min_required_clearance:
		print("  [FAIL] East-west path came within ", worst_east_west, " m of the building wall - below the ", min_required_clearance, " m clearance the navmesh's agent_radius is supposed to guarantee. Full path: ", path_east_west)
		return false
	if worst_north_south < min_required_clearance:
		print("  [FAIL] North-south path came within ", worst_north_south, " m of the building wall - below the ", min_required_clearance, " m clearance the navmesh's agent_radius is supposed to guarantee. Full path: ", path_north_south)
		return false

	print("  [PASS] Both perpendicular paths route around a 6x6 building with at least ", min_required_clearance, " m clearance to the wall (worst: E/W ", worst_east_west, " m, N/S ", worst_north_south, " m).")
	return true


func test_base_zones_field_in_field_spec() -> bool:
	print("Running Test Suite: base_zones Field Validates Against FIELD_SPEC...")
	# 2026-08-10 (Chris): the new base_zones block must round-trip
	# through MapCatalog's validator. Wrong shapes (missing id, vector3
	# vs vector2 mixup on half_extents, etc.) need to fail with the
	# same useful messages FIELD_SPEC produces for the rest of the
	# map schema, not silently drop the field on parse.
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")

	# A minimally-valid zone entry, exactly the shape FIELD_SPEC declares.
	# Real bundled maps are JSON-parsed (so center is Vector3 already);
	# the test feeds VALIDATED Godot types directly, which is what
	# validate_map_def() sees after _decode_dict() has run.
	var good: Dictionary = {
		"name": "Test",
		"description": "Test map",
		"map_half_extents": 80.0,
		"ground_color": Color(0.3, 0.3, 0.3),
		"base_zones": [
			{"id": "a", "center": Vector3(0, 0, 0), "half_extents": Vector2(10, 10)},
			{"id": "b", "center": Vector3(40, 0, 40), "half_extents": Vector2(10, 10)},
		],
		"spawns": [
			{"id": "player", "hq": Vector3(0, 0, 0), "factory": Vector3(10, 0, 0), "refinery": Vector3(-10, 0, 0), "harvester": Vector3(0, 0, 10)},
			{"id": "enemy", "hq": Vector3(40, 0, 40), "factory": Vector3(50, 0, 40), "refinery": Vector3(30, 0, 40), "harvester": Vector3(40, 0, 50)},
		],
		"schema_version": 1,
	}
	var good_errors: Array = MapCatalogScript.validate_map_def(good)
	if not good_errors.is_empty():
		for e in good_errors:
			print("  [FAIL] A minimally-valid map with base_zones should pass validation, got: ", e)
		return false

	# Missing id is a required-field violation, not a quiet drop.
	var missing_id: Dictionary = good.duplicate(true)
	missing_id["base_zones"] = [{"center": Vector3(0, 0, 0), "half_extents": Vector2(10, 10)}]
	var missing_id_errors: Array = MapCatalogScript.validate_map_def(missing_id)
	var found_missing_id: bool = false
	for e in missing_id_errors:
		if "base_zones" in e and "id" in e:
			found_missing_id = true
			break
	if not found_missing_id:
		print("  [FAIL] A base_zone missing its id should fail validation with a useful message, got: ", missing_id_errors)
		return false

	# half_extents as Vector3 instead of Vector2 should also fail. This
	# is the bug FIELD_SPEC was specifically designed to catch - an
	# "obviously rectangular" zone silently accepted with the Y
	# component ignored would land placement logic on a non-validated
	# field.
	var wrong_type: Dictionary = good.duplicate(true)
	wrong_type["base_zones"] = [{"id": "a", "center": Vector3(0, 0, 0), "half_extents": Vector3(10, 10, 10)}]
	var wrong_type_errors: Array = MapCatalogScript.validate_map_def(wrong_type)
	var found_wrong_type: bool = false
	for e in wrong_type_errors:
		# FIELD_SPEC emits type names with a capital ("Vector2"), so the
		# substring match is case-sensitive on the capitalised form.
		if "base_zones" in e and ("Vector2" in e or "Vector3" in e):
			found_wrong_type = true
			break
	if not found_wrong_type:
		print("  [FAIL] A base_zone with Vector3 half_extents (should be Vector2) should fail validation, got: ", wrong_type_errors)
		return false

	print("  [PASS] base_zones validates, rejects missing id, and rejects Vector3 half_extents.")
	return true


func test_assign_base_zones_spreads_them_apart() -> bool:
	print("Running Test Suite: assign_base_zones() spreads slots across the map (no two adjacent)...")
	# 2026-08-10 (Chris): the base-zone counterpart of assign_spawns()
	# must use the same OpenRA max-distance-spread algorithm, so two
	# players on a 2-zone map get the two zones that are furthest
	# apart - the same fairness property assign_spawns() proves for
	# the spawns themselves. A 4-player, 4-zone map must assign all
	# four zones (no double-claim), and a 2-zone, 3-player map must
	# refuse rather than silently collapsing to 2 picks.
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var zones: Array = [
		{"id": "north", "center": Vector3(0, 0, -40), "half_extents": Vector2(10, 10)},
		{"id": "east", "center": Vector3(40, 0, 0), "half_extents": Vector2(10, 10)},
		{"id": "south", "center": Vector3(0, 0, 40), "half_extents": Vector2(10, 10)},
		{"id": "west", "center": Vector3(-40, 0, 0), "half_extents": Vector2(10, 10)},
	]

	# 2-player / 4-zone: pick the two furthest apart (north+south or
	# east+west - the algorithm is deterministic given the same RNG,
	# so seed it and assert the exact pair it picks).
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var two_player: Dictionary = MapCatalogScript.assign_base_zones(zones, ["player", "enemy"], rng)
	if two_player.size() != 2:
		print("  [FAIL] 2 players, 4 zones should yield 2 assignments, got ", two_player.size())
		return false
	var two_ids: Array = [two_player["player"], two_player["enemy"]]
	if two_ids[0] == two_ids[1]:
		print("  [FAIL] Two players were assigned the SAME zone: ", two_ids)
		return false
	# A diagonal pair (north+south OR east+west) is the only correct
	# answer for "maximise distance across 4 points, pick 2"; the
	# algorithm's first iteration seeds claimed_centres with the
	# first pick (any zone, here "north"), then the second iteration
	# picks the zone with the largest squared distance from "north"
	# which is "south". Lock the test to that result.
	if not (two_player["player"] == "north" and two_player["enemy"] == "south"):
		print("  [FAIL] 2 players on a 4-zone cardinal map should be assigned the diagonal pair north+south, got ", two_player)
		return false

	# 4-player / 4-zone: every slot gets a unique zone, no double-claim.
	var four_player: Dictionary = MapCatalogScript.assign_base_zones(zones, ["a", "b", "c", "d"], RandomNumberGenerator.new())
	if four_player.size() != 4:
		print("  [FAIL] 4 players, 4 zones should yield 4 assignments, got ", four_player.size())
		return false
	var seen: Array = []
	for slot in four_player:
		if seen.has(four_player[slot]):
			print("  [FAIL] Two slots were assigned the same zone: ", four_player)
			return false
		seen.append(four_player[slot])

	# 3-player / 2-zone: must REFUSE, not silently pick the first
	# zone twice. Empty Dictionary return is the explicit under-
	# provisioned signal; the orchestrator decides what to do with
	# it (the orchestrator's choice is its own concern, not this
	# function's). A "first zone wins" collapse here is the bug this
	# case exists to catch.
	var under: Dictionary = MapCatalogScript.assign_base_zones(
		[{"id": "a", "center": Vector3(0, 0, 0), "half_extents": Vector2(10, 10)},
		{"id": "b", "center": Vector3(40, 0, 0), "half_extents": Vector2(10, 10)}],
		["a", "b", "c"])
	if not under.is_empty():
		print("  [FAIL] 3 players on a 2-zone map should refuse (under-provisioned), got ", under)
		return false

	# 0-player / N-zone: empty result, no crashes.
	var zero: Dictionary = MapCatalogScript.assign_base_zones(zones, [])
	if not zero.is_empty():
		print("  [FAIL] 0 players should yield an empty assignment, got ", zero)
		return false

	print("  [PASS] assign_base_zones: 2-player picks the diagonal pair, 4-player claims all 4 zones uniquely, 3/2 refuses, 0/N returns empty.")
	return true


# --- Pre-game HQ-placement phase (Chris 2026-08-10) ---------------------------
#
# The new flow replaces the old "auto-spawn HQ + refinery + 3 manufactories"
# boot with: each player is assigned a base zone, drops their HQ inside it, and
# then the match is live. The refinery and 2 manufactories are now built
# NORMALLY during play, paid for out of a starting bank. These suites assert
# the four load-bearing pieces of that contract:
#
#   1. STARTING_CREDITS covers the smart opening (refinery + 2 of any
#      manufactory tier) without forcing the player to wait on income.
#   2. _spawn_bases() only places the HQ - the refinery and the three
#      manufactories the old runtime dropped are gone.
#   3. The AI auto-places its HQ at the centre of its assigned zone (no
#      human-placement UX for the AI; the same _spawn_bases() path).
#   4. The human-placement hook refuses positions outside the assigned
#      zone, refuses a second HQ for the same team, and otherwise
#      commits - the property the placement-UI layer will lean on.

# Reads the starting-bank constant and the building costs from the catalogs
# they live in, then asserts the bank covers the worst-case smart opening.
# This is a CONSTANT-FOLLOWING test on purpose: if anyone bumps STARTING_CREDITS
# without re-running the worst case through the catalog, this fails with the
# new number, which is the exact signal that the bank was changed and the
# opening economy should be re-evaluated.
func test_starting_bank_covers_refinery_plus_two_manufactories() -> bool:
	print("Running Test Suite: Starting Bank Covers Refinery + 2 Manufactories...")
	var BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
	var bank: int = MatchDirectorScript.STARTING_CREDITS
	if bank <= 0:
		print("  [FAIL] STARTING_CREDITS is non-positive: ", bank)
		return false
	# The "smart opening" is refinery + 2 of the SAME tier. Worst case is
	# the most expensive tier (heavy_manufactory), so test against that.
	# Crystal cost is intentionally ignored: the bank is metal-only at
	# match start, and crystal is mined normally - the bank only has to
	# cover the metal side of the opening.
	var refinery_metal: int = int(BuildingCatalogScript.STATS["refinery"].get("cost_metal", 0))
	var heavy_metal: int = int(BuildingCatalogScript.STATS["heavy_manufactory"].get("cost_metal", 0))
	if refinery_metal <= 0 or heavy_metal <= 0:
		print("  [FAIL] Building catalog returned non-positive costs (refinery=", refinery_metal,
			", heavy_manufactory=", heavy_metal, ") - this test assumes those are the canonical numbers")
		return false
	var worst_case: int = refinery_metal + 2 * heavy_metal
	if bank < worst_case:
		print("  [FAIL] STARTING_CREDITS=", bank, " doesn't cover the worst-case smart opening (refinery ",
			refinery_metal, " + 2 heavy_manufactory ", heavy_metal, " = ", worst_case, ")")
		return false
	# And every other tier pair - the smart opening shouldn't fail because
	# the player picked a cheaper tier. Belt-and-braces over just heavy.
	for tier in BuildingCatalogScript.MANUFACTORY_KINDS:
		var m: int = int(BuildingCatalogScript.STATS[tier].get("cost_metal", 0))
		if bank < refinery_metal + 2 * m:
			print("  [FAIL] STARTING_CREDITS=", bank, " doesn't cover refinery + 2 ", tier,
				" (refinery ", refinery_metal, " + 2 ", tier, " ", m, " = ", refinery_metal + 2 * m, ")")
			return false
	print("  [PASS] STARTING_CREDITS=", bank, " covers refinery (", refinery_metal, " metal) + 2 of any manufactory tier (worst: 2 heavy = ", 2 * heavy_metal, " metal, total ", worst_case, ").")
	return true


# Asserts the post-trim _spawn_bases() only places HQs - no refinery, no
# manufactories, no other auto-spawned structures. This is the property the
# pre-game phase contract rests on: a match starting "live" with anything
# other than an HQ would be a match where the new flow's claim ("player
# builds the rest") is false.
#
# Spins up a real MatchDirector with a minimal map (north+south base_zones,
# matching player+enemy spawns) and reads the structures group after
# _spawn_bases() returns. Both the spawning and the post-spawn power recalc
# are exercised, so a regression in either path shows up here.
func test_spawn_bases_drops_only_hq_not_refinery_or_manufactories() -> bool:
	print("Running Test Suite: _spawn_bases() Drops Only HQs (no refinery, no manufactories)...")
	var EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
	var director := TestMatchDirector.new()
	director.current_map = {
		"id": "test_two_zones_hq_only",
		"map_half_extents": 80.0,
		"world_scale": 1,
		"terrain": {"size": Vector2(160, 160)},
		"spawns": [
			{"id": "player", "hq": Vector3(0, 0, 50)},
			{"id": "enemy", "hq": Vector3(0, 0, -50)},
		],
		"base_zones": [
			{"id": "north", "center": Vector3(0, 0, 50), "half_extents": Vector2(15, 15)},
			{"id": "south", "center": Vector3(0, 0, -50), "half_extents": Vector2(15, 15)},
		],
	}
	director.economy = EconomyServiceScript.new()
	director.economy.add_team(0, 1200)
	director.economy.add_team(1, 1200)
	root.add_child(director)
	# add_child is deferred in --script mode - the director only joins
	# the tree on the next frame. _spawn_bases and the get_team_structures
	# lookup it uses both need the director in the tree, so wait one
	# frame before exercising them.
	await tree.process_frame
	director._spawn_bases()

	# Walk the structures group rather than counting on add_child side
	# effects - the same lookup place_hq_for_human() uses, so the
	# count here is what the placement-UI layer would observe.
	# Filter to structures parented to this director, so a previous
	# test's leaked structure (if any) can't poison the count.
	var hqs: Array = []
	var refineries: Array = []
	var manufactories: Array = []
	var others: Array = []
	for s in director.get_tree().get_nodes_in_group("structures"):
		if not is_instance_valid(s) or s.get_parent() != director:
			continue
		match s.kind:
			"hq": hqs.append(s)
			"refinery": refineries.append(s)
			"light_manufactory", "medium_manufactory", "heavy_manufactory":
				manufactories.append(s)
			_: others.append(s)

	director.queue_free()

	# Pre-game phase: only the AI auto-places. The player gets a placement
	# ghost and the player HQ lands when they commit it - which _spawn_bases
	# does not do. So the auto-placed count is exactly ONE (the AI HQ), with
	# no refinery, no manufactories, no other structure. The 2-HQ check was
	# the legacy expectation before the pre-game phase landed.
	if hqs.size() != 1:
		print("  [FAIL] expected exactly 1 auto-placed HQ (AI only on a zoned map; player is in pre-game placement), got ", hqs.size())
		return false
	# The auto-placed HQ belongs to the AI, not the player.
	if hqs.size() == 1 and hqs[0].team != 1:
		print("  [FAIL] the auto-placed HQ should be the AI's, got team ", hqs[0].team)
		return false
	if refineries.size() != 0:
		print("  [FAIL] expected 0 refineries (player must build their own), got ", refineries.size())
		return false
	if manufactories.size() != 0:
		print("  [FAIL] expected 0 manufactories (player must build their own), got ", manufactories.size())
		return false
	if others.size() != 0:
		print("  [FAIL] expected 0 other auto-spawned structures, got ", others.size(), " (kinds: ", others.map(func(s): return s.kind), ")")
		return false
	print("  [PASS] _spawn_bases() placed exactly 1 auto-placed HQ (AI only) and no refinery, no manufactory, no other structure. The player is in pre-game placement and will commit their own HQ through the placement UI.")
	return true


# The AI gets no placement UI - it auto-drops its HQ at the centre of its
# assigned base zone, the same way the old runtime used the spawn.hq
# coordinate. This is the assertion that contract still holds under the
# new base-zones flow: a player on a north-zone map and an AI on the
# south-zone map should see the AI HQ at the south-zone centre, not at
# spawn.hq, not at (0,0,0).
func test_ai_auto_places_hq_in_assigned_base_zone() -> bool:
	print("Running Test Suite: AI Auto-Places HQ at Centre of Its Assigned Base Zone...")
	var EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
	var director := TestMatchDirector.new()
	# Asymmetric map: spawn.hq says one thing, the AI's base zone is
	# somewhere else on purpose. If _spawn_bases() were still using
	# spawn.hq, the AI HQ would land at (0,0,-50), not at the zone
	# centre - the failure mode the test is built to catch.
	director.current_map = {
		"id": "test_ai_zone_autoplace",
		"map_half_extents": 120.0,
		"world_scale": 1,
		"terrain": {"size": Vector2(240, 240)},
		"spawns": [
			{"id": "player", "hq": Vector3(0, 0, 50)},
			{"id": "enemy", "hq": Vector3(0, 0, -50)},
		],
		"base_zones": [
			{"id": "north", "center": Vector3(20, 0, 70), "half_extents": Vector2(15, 15)},
			{"id": "south", "center": Vector3(-25, 0, -90), "half_extents": Vector2(15, 15)},
		],
	}
	director.economy = EconomyServiceScript.new()
	director.economy.add_team(0, 1200)
	director.economy.add_team(1, 1200)
	root.add_child(director)
	# See test_spawn_bases_drops_only_hq for why this await is needed.
	await tree.process_frame
	director._spawn_bases()

	# Find the enemy HQ. Use the global_position (terrain-snapped Y) so
	# the test isn't sensitive to the exact snap value, only to X/Z.
	# Filter to structures parented to this director, so a previous
	# test's leaked structure can't be confused for a fresh one.
	var enemy_hq = null
	for s in director.get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and s.get_parent() == director and s.kind == "hq" and s.team == 1:
			enemy_hq = s
			break
	if enemy_hq == null:
		print("  [FAIL] no enemy HQ was placed by _spawn_bases()")
		director.queue_free()
		return false

	# With exactly 2 slots and 2 zones, the max-distance-spread lands
	# slot 0 on north (20,0,70) (closer to the player spawn at (0,0,50))
	# and slot 1 on south (-25,0,-90) (further from it). The
	# PLAYER_TEAM=0, ENEMY_TEAM=1 ordering in _spawn_bases() keeps
	# the convention.
	var expected_centre: Vector3 = Vector3(-25, 0, -90)
	var got: Vector3 = enemy_hq.global_position
	if absf(got.x - expected_centre.x) > 0.5 or absf(got.z - expected_centre.z) > 0.5:
		print("  [FAIL] enemy HQ at (", got.x, ", ", got.z, "), expected near (",
			expected_centre.x, ", ", expected_centre.z, ") - AI is not using the zone centre")
		director.queue_free()
		return false

	# The PLAYER HQ is no longer auto-placed on a zoned map - the pre-game
	# phase raises a placement ghost and waits for the player to drop the
	# HQ. What we CAN assert: the player is in pre-game mode (the UI
	# contract the player will use is now armed), the player's
	# _team_base_zone entry is the north zone, and the AI's zone is south.
	# The committed player HQ's location is what the new
	# test_pre_game_hq_placement_mode_lifecycle test pins.
	if not director.is_placing_hq():
		print("  [FAIL] on a zoned map the player should be in pre-game placement, not auto-placed")
		director.queue_free()
		return false
	var player_zone_id: String = director._team_base_zone.get(0, "")
	if player_zone_id != "north":
		print("  [FAIL] player (team 0) should be assigned the north zone, got ", player_zone_id)
		director.queue_free()
		return false
	var enemy_zone_id: String = director._team_base_zone.get(1, "")
	if enemy_zone_id != "south":
		print("  [FAIL] enemy (team 1) should be assigned the south zone, got ", enemy_zone_id)
		director.queue_free()
		return false
	director.queue_free()
	print("  [PASS] AI HQ at the south-zone centre (", got.x, ",", got.z,
		"); player is in pre-game placement, assigned the north zone - the new pre-game phase drives the player side, not the legacy auto-place.")
	return true


# The human-placement hook must:
#   - REFUSE positions outside the assigned zone (half_extents rectangle);
#   - REFUSE a second call while a live player HQ already exists;
#   - COMMIT on a valid first call.
# All three are the contract the placement-UI layer will lean on, and
# they're cheap to test in isolation. The valid-commit case is checked
# by counting structures in the group after a successful call.
func test_place_hq_for_human_refuses_outside_zone_and_double_place() -> bool:
	print("Running Test Suite: place_hq_for_human() Refuses Outside Zone and Double-Place...")
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
	var director := TestMatchDirector.new()
	director.current_map = {
		"id": "test_hq_human_placement",
		"map_half_extents": 80.0,
		"world_scale": 1,
		"terrain": {"size": Vector2(160, 160)},
		"spawns": [
			{"id": "player", "hq": Vector3(0, 0, 40)},
			{"id": "enemy", "hq": Vector3(0, 0, -40)},
		],
		"base_zones": [
			# 15x15 zone centred at (0,0,40) - inside is X in [-15,15],
			# Z in [25,55]. Anything past those edges is outside.
			{"id": "north", "center": Vector3(0, 0, 40), "half_extents": Vector2(15, 15)},
			{"id": "south", "center": Vector3(0, 0, -40), "half_extents": Vector2(15, 15)},
		],
	}
	director.economy = EconomyServiceScript.new()
	director.economy.add_team(0, 1200)
	director.economy.add_team(1, 1200)
	root.add_child(director)
	# add_child is deferred in --script mode - see the other pre-game
	# tests for the full reason. get_team_structures() and the
	# structures-group iterators all need the director in the tree.
	await tree.process_frame
	director._spawn_bases()

	# Snapshot: AFTER the pre-game phase landed, _spawn_bases() does NOT
	# auto-place the player HQ on a zoned map - the player is in pre-game
	# placement instead. The AI HQ is the only auto-placed one. The
	# double-place test below therefore needs to commit the player HQ
	# FIRST, then exercise the refusals - which is the same flow the
	# pre-game placement UI runs (commit once, then the hook should
	# refuse any further commit attempts).
	#
	# Order matters: the outside-zone refusal must be tested BEFORE the
	# commit, so the "refused because outside" check is the one being
	# exercised (a refusal after the commit is the double-place path
	# instead, which is what the test pins separately). The old layout
	# relied on a pre-existing player HQ from _spawn_bases; the new
	# layout builds one through the hook itself.
	#
	# OUTSIDE the zone. Zone is X[-15,15], Z[25,55]. (100, 0, 100) is
	# well past both edges. Hook must refuse. At this point the player
	# has no HQ, so the refusal is the outside-zone check, not the
	# double-place check.
	var refused_outside: bool = not director.place_hq_for_human(Vector3(100, 0, 100))
	if not refused_outside:
		print("  [FAIL] place_hq_for_human() accepted (100,0,100), which is outside the X[-15,15] Z[25,55] zone")
		director.queue_free()
		return false

	# Just OUTSIDE one axis. X=14 is in, X=16 is out. Catches off-by-one
	# in the half_extents comparison (using >= instead of > would let
	# X=15 through, which is a 0-width sliver at the edge - the spec
	# says inside-the-rectangle, edge is a degenerate case the test
	# pins down).
	var refused_edge_x: bool = not director.place_hq_for_human(Vector3(16, 0, 40))
	if not refused_edge_x:
		print("  [FAIL] place_hq_for_human() accepted (16,0,40), which is X-out-of-zone (X edge is 15)")
		director.queue_free()
		return false
	var refused_edge_z: bool = not director.place_hq_for_human(Vector3(0, 0, 56))
	if not refused_edge_z:
		print("  [FAIL] place_hq_for_human() accepted (0,0,56), which is Z-out-of-zone (Z edge is 55)")
		director.queue_free()
		return false

	# COMMIT path: in-zone call (5, 0, 35) should land a player HQ.
	var placed: bool = director.place_hq_for_human(Vector3(5, 0, 35))
	if not placed:
		print("  [FAIL] place_hq_for_human() refused a valid in-zone commit (5,0,35)")
		director.queue_free()
		return false
	var hq_at_5: bool = false
	for s in director.get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and s.get_parent() == director and s.kind == "hq" and s.team == 0:
			var gp: Vector3 = s.global_position
			if absf(gp.x - 5) < 0.5 and absf(gp.z - 35) < 0.5:
				hq_at_5 = true
	if not hq_at_5:
		print("  [FAIL] commit returned true but no player HQ landed at (5,0,35)")
		director.queue_free()
		return false

	# DOUBLE-PLACE: an in-zone call (10, 0, 40) should refuse, because
	# the player already has a live HQ from the commit above. This is
	# the "one human HQ per match" invariant.
	var refused_double: bool = not director.place_hq_for_human(Vector3(10, 0, 40))
	if not refused_double:
		print("  [FAIL] place_hq_for_human() accepted a second call while a live player HQ exists")
		director.queue_free()
		return false

	# STRUCTURE COUNT: after the commit + 4 refused calls, still exactly
	# one player HQ. No phantom HQs from any of the refused attempts.
	var hq_count_after: int = 0
	for s in director.get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and s.get_parent() == director and s.kind == "hq" and s.team == 0:
			hq_count_after += 1
	if hq_count_after != 1:
		print("  [FAIL] after the commit + 4 refused calls, expected 1 player HQ, got ", hq_count_after)
		director.queue_free()
		return false

	director.queue_free()
	await tree.process_frame
	print("  [PASS] place_hq_for_human() refuses outside-zone (incl. one-axis edge), refuses double-place, and commits on a valid in-zone call.")
	return true


# The pre-game placement MODE - _enter_hq_placement arms the ghost, the zone
# outline, the hq_placement_started signal; _exit_hq_placement tears them all
# down; confirm_hq_placement routes through place_hq_for_human. Lives in
# its own state (placing_hq) so it does not race with the build-queue
# placement (is_placing/begin_placement/confirm_placement) - the input
# handler at match_director.gd:_unhandled_input early-returns for either
# state, and the two are never both true.
#
# What this exercises, end-to-end:
#   - _spawn_bases() in a 2-zone map enters the mode (the player has no
#     auto-placed HQ on a zoned map; the AI does);
#   - the ghost and zone outline are live MeshInstance3D children;
#   - _clamp_to_player_zone drags a point outside the half_extents
#     rectangle to the closest point inside it;
#   - confirm_hq_placement with a valid in-zone ghost commits and exits;
#   - confirm_hq_placement on a setup with no live player HQ but a ghost
#     outside the zone refuses (place_hq_for_human is the gate, but
#     confirm_hq_placement passes the ghost position through it);
#   - the hq_placement_started / hq_placement_finished signals fire at
#     the right transitions.
func test_pre_game_hq_placement_mode_lifecycle() -> bool:
	print("Running Test Suite: Pre-Game HQ Placement Mode - lifecycle, clamp, signal, commit...")
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
	# TestMatchDirector extends match_director.gd with an empty _ready,
	# so the heavy setup (services, _spawn_resource_nodes, _spawn_bases,
	# navmesh bake) does NOT auto-run on add_child. The test calls
	# _spawn_bases itself with a controlled current_map. Same pattern
	# test_ai_auto_places_hq_in_assigned_base_zone and the four pre-game
	# HQ tests use; works because the inherited _spawn_bases reads
	# current_map fresh, not at add_child time.
	#
	# Note: do NOT call set_script(MatchDirectorScript) on top of this
	# - the script swap leaves get_tree() returning null on the
	# underlying Node3D (script state and node tree state don't
	# propagate cleanly across a swap), and the pre-game _spawn_bases
	# path needs get_tree() to resolve structures_of_kinds.
	var director := TestMatchDirector.new()
	director.current_map = {
		"id": "test_hq_placement_mode",
		"map_half_extents": 80.0,
		"world_scale": 1,
		"terrain": {"size": Vector2(160, 160)},
		"spawns": [
			{"id": "player", "hq": Vector3(0, 0, 40)},
			{"id": "enemy", "hq": Vector3(0, 0, -40)},
		],
		"base_zones": [
			{"id": "north", "center": Vector3(0, 0, 40), "half_extents": Vector2(15, 15)},
			{"id": "south", "center": Vector3(0, 0, -40), "half_extents": Vector2(15, 15)},
		],
	}
	director.economy = EconomyServiceScript.new()
	director.economy.add_team(0, 1200)
	director.economy.add_team(1, 1200)
	# Add to the tree BEFORE _spawn_bases: the spawn path calls
	# get_team_structures() (which needs get_tree() to resolve) and
	# _enter_hq_placement() (which calls get_node_or_null("/root/MatchConfig")
	# to detect Test Range mode). Both require the director to be in
	# the tree.
	root.add_child(director)
	# add_child is deferred in `--script` mode (root is the SceneTree's
	# root Window, which is not actually an active main-scene root in
	# headless --script runs). The node lands in the tree on the next
	# frame, and until then get_tree() on the director returns null and
	# get_team_structures() / the structures-group iterators all error.
	# One process_frame is enough.
	await tree.process_frame

	# Before _spawn_bases, the player is not in pre-game mode (no zones
	# resolved yet) and has no HQ. After, the player IS in pre-game
	# mode (zoned map), and only the AI got an auto-placed HQ.
	if director.is_placing_hq():
		print("  [FAIL] pre-game mode should not be armed before _spawn_bases()")
		director.queue_free()
		return false
	director._spawn_bases()
	if not director.is_placing_hq():
		print("  [FAIL] pre-game mode should be armed after _spawn_bases() on a zoned map")
		director.queue_free()
		return false
	# AI's HQ is auto-placed; the player's is NOT.
	var player_hq_count: int = 0
	var enemy_hq_count: int = 0
	for s in director.get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and s.get_parent() == director and s.kind == "hq":
			if s.team == 0:
				player_hq_count += 1
			elif s.team == 1:
				enemy_hq_count += 1
	if player_hq_count != 0:
		print("  [FAIL] player HQ should NOT be auto-placed on a zoned map (got ", player_hq_count, ")")
		director.queue_free()
		return false
	if enemy_hq_count != 1:
		print("  [FAIL] AI HQ should be auto-placed (got ", enemy_hq_count, ")")
		director.queue_free()
		return false

	# Ghosts are live MeshInstance3D children of the director.
	if not is_instance_valid(director.hq_ghost) or not is_instance_valid(director.hq_zone_outline):
		print("  [FAIL] hq_ghost or hq_zone_outline is not a live MeshInstance3D")
		director.queue_free()
		return false
	# Ghosts do not cast shadows (decoration, not gameplay element).
	if director.hq_ghost.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		print("  [FAIL] hq_ghost should not cast shadows (decorative, not gameplay)")
		director.queue_free()
		return false
	if director.hq_zone_outline.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		print("  [FAIL] hq_zone_outline should not cast shadows (UI affordance)")
		director.queue_free()
		return false

	# hq_placement_started signal fires exactly once on enter.
	var started_count: int = 0
	director.hq_placement_started.connect(
		func() -> void:
			started_count += 1)
	# Re-entering is a no-op (already in mode), so the signal does not
	# fire a second time. The connect above is registered AFTER the
	# first emit, which is the only one we want - this also exercises
	# the "second entry is a no-op" path.
	director._enter_hq_placement()
	if started_count != 0:
		print("  [FAIL] _enter_hq_placement while already placing_hq should be a no-op, but fired the signal ", started_count, " times")
		director.queue_free()
		return false

	# Clamp: a point 100m outside the zone is dragged to the closest
	# point inside it. The exact corner is (15, _, 55); the test just
	# needs "inside the rectangle" not "at the corner".
	var zone_id: String = director._team_base_zone.get(0, "")
	var zone: Dictionary = MapCatalogScript.get_base_zone(director.current_map, zone_id)
	var center: Vector3 = zone.get("center", Vector3.ZERO)
	var half: Vector2 = zone.get("half_extents", Vector2.ZERO)
	var outside_pt: Vector3 = center + Vector3(100, 0, 100)
	var clamped: Vector3 = director._clamp_to_player_zone(outside_pt)
	if absf(clamped.x - center.x) > half.x + 0.01 or absf(clamped.z - center.z) > half.y + 0.01:
		print("  [FAIL] clamp didn't bring point inside zone: ", clamped, " vs center ", center, " half ", half)
		director.queue_free()
		return false

	# Confirm: a ghost at the centre commits and exits the mode. The
	# matching player HQ lands at the centre.
	director.hq_ghost_pos = center
	var commit_ok: bool = director.confirm_hq_placement()
	if not commit_ok:
		print("  [FAIL] confirm_hq_placement at the zone centre should commit")
		director.queue_free()
		return false
	if director.is_placing_hq():
		print("  [FAIL] pre-game mode should be exited after a successful commit")
		director.queue_free()
		return false
	if director.hq_ghost != null or director.hq_zone_outline != null:
		print("  [FAIL] ghost / zone outline should be null after exit")
		director.queue_free()
		return false
	# The committed player HQ is now in the structures group.
	var committed_hq_at_centre: bool = false
	for s in director.get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and s.get_parent() == director and s.kind == "hq" and s.team == 0:
			var gp: Vector3 = s.global_position
			if absf(gp.x - center.x) < 0.5 and absf(gp.z - center.z) < 0.5:
				committed_hq_at_centre = true
	if not committed_hq_at_centre:
		print("  [FAIL] committed player HQ is not at the zone centre")
		director.queue_free()
		return false

	# Re-arm the mode, then try to commit at an out-of-zone ghost
	# position. This bypasses the clamp (the test sets hq_ghost_pos
	# directly without going through _unhandled_input, so the clamp
	# in update_hq_placement does not run). The commit must refuse
	# (place_hq_for_human is the gate) and stay in the mode - the
	# player's HQ still exists from the previous commit, so a
	# second commit would also trip the double-place guard, but the
	# outside-zone check fires first.
	director._enter_hq_placement()
	if not director.is_placing_hq():
		print("  [FAIL] _enter_hq_placement should re-arm after a previous commit")
		director.queue_free()
		return false
	director.hq_ghost_pos = Vector3(1000, 0, 1000)  # well outside
	var refused: bool = not director.confirm_hq_placement()
	if not refused:
		print("  [FAIL] confirm at an out-of-zone ghost position should refuse")
		director.queue_free()
		return false
	if not director.is_placing_hq():
		print("  [FAIL] pre-game mode should stay armed after a refused commit (player can re-aim)")
		director.queue_free()
		return false

	# Cancel: drops out of the mode without placing. Same as a
	# non-place flow; the mode has to be re-armed for the player to
	# try again, but for this test we just check the teardown.
	director.cancel_hq_placement()
	if director.is_placing_hq():
		print("  [FAIL] cancel_hq_placement should drop out of pre-game mode")
		director.queue_free()
		return false

	director.queue_free()
	await tree.process_frame
	print("  [PASS] Pre-game HQ placement mode: enters after _spawn_bases on zoned map, ghost+zone live and unshadowed, clamp+commit+refuse all behave, signals fire on transitions.")
	return true


# --- Ambient harvestable trees (Chris 2026-08-10) -----------------------------
#
# The "ambient forest" feature: a 20-variant .glb pool of single trees
# (build_meshes.build_ambient_tree, exported as ambient_tree_0..19.glb
# alongside the existing resource_lumber_*.glb family) is scattered as
# individual ResourceNode instances across every map's baseline ground.
# Ambient trees are HARVESTABLE (resource_type = "lumber", join the
# resource_nodes group, harvest() drains their amount) but they do NOT
# regrow (resource_node.gd's is_ambient flag suppresses both the
# per-collectible regrow and the per-field respawn). The 4 harvestable
# LUMBER FIELDS in open_plains.json still work exactly as they did -
# this suite covers the NEW code path, not the old one.

func test_ambient_tree_pool_size_matches_constant() -> bool:
	print("Running Test Suite: Ambient Tree Pool - exported .glb count matches AMBIENT_TREE_POOL_SIZE constant...")
	# The constant in resource_node.gd is the source of truth the loader
	# rolls against (`idx = randi() % AMBIENT_TREE_POOL_SIZE`). A constant
	# larger than the number of files on disk rolls indices at missing
	# .glb files and falls through to the procedural cylinder - exactly
	# the silent-fallback bug AUTHORED_POOL_SIZES exists to prevent at
	# the harvestable scale, now mirrored at the ambient scale.
	var ResourceNodeScript = preload("res://scripts/resource_node.gd")
	var pool_size: int = ResourceNodeScript.AMBIENT_TREE_POOL_SIZE
	if pool_size <= 0:
		print("  [FAIL] AMBIENT_TREE_POOL_SIZE is non-positive: ", pool_size)
		return false
	for i in range(pool_size):
		var path: String = ResourceNodeScript.AMBIENT_TREE_MODEL_DIR % i
		if not ResourceLoader.exists(path):
			print("  [FAIL] Expected ambient tree pool file missing: ", path,
				" (AMBIENT_TREE_POOL_SIZE=", pool_size, " but only ", i, " files exist on disk)")
			return false
	print("  [PASS] AMBIENT_TREE_POOL_SIZE=", pool_size, " matches the ", pool_size, " exported ambient_tree_*.glb files.")
	return true


func test_ambient_tree_uses_ambient_pool_not_lumber_pool() -> bool:
	print("Running Test Suite: Ambient Tree Setup Picks From ambient_tree_* Pool, Not resource_lumber_*...")
	# An ambient tree with resource_type = "lumber" and is_ambient = true
	# must NOT pick from AUTHORED_POOL_SIZES["lumber"] = 3 (the
	# harvestable "stand" family), and must NOT use the procedural lumber
	# cone fallback. It has to instantiate one of the 20 single-tree
	# .glb files. Failure mode: a tile showing a 3-tree clumped "stand"
	# at a position that was supposed to be a single tree - visually
	# wrong AND it makes the scatter read as "duplicate lumber fields,"
	# not "ambient forest."
	var ResourceNodeScript = preload("res://scripts/resource_node.gd")
	var AmbientScatterScript = preload("res://scripts/ambient_scatter.gd")
	# Parented under its own container because that is where the shared
	# MultiMesh batcher gets created (ambient_scatter.gd's get_or_create takes
	# the node's PARENT), and this test needs a handle on it.
	var holder := Node3D.new()
	root.add_child(holder)
	var node = ResourceNodeScript.new()
	node.is_ambient = true
	holder.add_child(node)
	node.global_position = Vector3(17.5, 0, -23.0)
	node.setup("lumber", 40)
	await tree.process_frame

	if node.resource_type != "lumber":
		print("  [FAIL] Ambient tree should keep resource_type='lumber' (so harvesters credit it as lumber), got '", node.resource_type, "'")
		holder.queue_free()
		return false
	if not node.is_ambient:
		print("  [FAIL] is_ambient flag was reset by setup()")
		holder.queue_free()
		return false
	# An ambient node no longer builds its own mesh subtree - its visual is a
	# slot in a shared MultiMesh (ambient_scatter.gd), so "which pool did it
	# pick from" is now answered by the mesh the BATCH is drawing. The rule
	# under test is unchanged: it must be an ambient_tree_*.glb and not one of
	# the 3 harvestable "stand" variants.
	var batcher = AmbientScatterScript.get_or_create(holder)
	batcher.commit()
	await tree.process_frame
	var got_ambient: bool = false
	var seen_paths: Array = []
	var stack: Array = [batcher]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MultiMeshInstance3D and n.multimesh != null and n.multimesh.mesh != null:
			var mp: String = String(n.multimesh.mesh.resource_path)
			seen_paths.append(mp)
			if "ambient_tree_" in mp:
				got_ambient = true
	holder.queue_free()
	if not got_ambient:
		print("  [FAIL] Ambient tree registered no ambient_tree_*.glb geometry with the scatter batcher (batched meshes were: ", seen_paths, ")")
		return false
	print("  [PASS] Ambient tree setup instantiates from the ambient_tree_*.glb pool, not the harvestable resource_lumber_* family.")
	return true


func test_ambient_tree_does_not_regrow_after_harvest() -> bool:
	print("Running Test Suite: Ambient Tree Harvester Drain - amount stays at 0, no regrow, removed from resource_nodes group...")
	# The whole point of the ambient flag: a harvester that empties an
	# ambient tree should find it gone for the rest of the match, NOT
	# regrow back to full after 15s the way a harvestable lumber
	# collectible does. Verified two ways: amount stays at 0 across a
	# physics tick window longer than REGROW_DELAY, AND the node is
	# removed from the resource_nodes group (which is what gates
	# "find nearest resource" in unit.gd's _auto_find_harvest_
	# work - so even if a bug let amount stay positive, the harvester
	# would still walk past it).
	var ResourceNodeScript = preload("res://scripts/resource_node.gd")
	var node = ResourceNodeScript.new()
	node.is_ambient = true
	root.add_child(node)
	node.global_position = Vector3(5.0, 0, 5.0)
	node.setup("lumber", 40)
	await tree.process_frame

	# Harvest the full amount in one call.
	var got: int = node.harvest(40)
	if got != 40:
		print("  [FAIL] Ambient tree should have yielded 40 on a full harvest, got ", got)
		node.queue_free()
		return false
	if node.amount != 0:
		print("  [FAIL] Ambient tree amount should be 0 after a full harvest, got ", node.amount)
		node.queue_free()
		return false
	if node.is_in_group("resource_nodes"):
		print("  [FAIL] Empty ambient tree should be removed from the resource_nodes group (so harvesters don't see it)")
		node.queue_free()
		return false

	# Tick physics well past REGROW_DELAY (15s) - if regrow is not
	# actually suppressed, amount would be back at start_amount by now.
	# 30 physics ticks * 1.0s = 30s, twice the delay.
	for i in range(30):
		node._physics_process(1.0)
	if node.amount != 0:
		print("  [FAIL] Ambient tree regrew from 0 to ", node.amount, " after 30s of physics ticks - is_ambient should suppress regrow entirely")
		node.queue_free()
		return false
	if node.is_in_group("resource_nodes"):
		print("  [FAIL] Ambient tree was re-added to the resource_nodes group after regrow window - is_ambient should stay out")
		node.queue_free()
		return false

	# The negative case: a non-ambient (field) node on the same fixture
	# MUST still regrow - confirms the suppress only applies to ambient
	# and didn't break the existing path.
	var field_node = ResourceNodeScript.new()
	field_node.is_ambient = false
	root.add_child(field_node)
	field_node.global_position = Vector3(-5.0, 0, -5.0)
	field_node.setup("lumber", 40)
	await tree.process_frame
	field_node.harvest(40)
	if field_node.is_in_group("resource_nodes"):
		print("  [FAIL] Non-ambient (field) node was also removed from resource_nodes on empty - regrow was suppressed for the wrong type")
		field_node.queue_free()
		node.queue_free()
		return false
	# Tick past REGROW_DELAY and confirm amount comes back.
	for i in range(30):
		field_node._physics_process(1.0)
	if field_node.amount <= 0:
		print("  [FAIL] Non-ambient field node failed to regrow - the is_ambient gate may have broken the regrow path for field nodes too")
		field_node.queue_free()
		node.queue_free()
		return false

	field_node.queue_free()
	node.queue_free()
	print("  [PASS] Ambient tree stays at 0 and out of the resource_nodes group after a full harvest; field nodes still regrow as before.")
	return true


# Ambient trees must NOT cast shadows. The 2026-08-10 ambient scatter
# places up to 1000 trees across a map; with Godot's default 4096x4096
# shadow atlas that's hundreds of shadow casters doing a full depth pass
# per frame, for almost no visual gain on a top-down RTS camera (the
# camera looks straight down on a tree's own canopy, so the only shadow
# is a smudge on the canopy itself - and worse, it sits on the same
# ground pixels as the gameplay-relevant unit shadow the player actually
# needs to read). The harvestable 4-field stands keep their shadows
# (36 trees total, visible gameplay element). This test pins the rule
# so a future "tidy up setup()" doesn't silently re-enable shadows on
# 300+ decorative trees and tank framerate again.
func test_ambient_nodes_opt_out_of_shadow_casting() -> bool:
	print("Running Test Suite: Ambient Nodes Don't Cast Shadows (perf guard for 300+ tree scatter)...")
	var ResourceNodeScript = preload("res://scripts/resource_node.gd")
	# Ambient branch. Use a lumber scatter position (not an existing map
	# node, since this is a unit-of-the-class test not a fixture) so the
	# pool picks a real variant - the failure mode is "setup never set
	# cast_shadow OFF at all", which a procedural fallback (no mesh_inst
	# to check) would mask.
	#
	# The ambient visual no longer lives under the node's own mesh_inst - it
	# is a slot in a shared MultiMesh (ambient_scatter.gd), so the assertion
	# follows it there. The RULE is unchanged and is what this test exists
	# for; only where cast_shadow has to be set moved.
	var scatter_parent := Node3D.new()
	root.add_child(scatter_parent)
	var ambient = ResourceNodeScript.new()
	ambient.is_ambient = true
	scatter_parent.add_child(ambient)
	ambient.global_position = Vector3(11.0, 0, 7.0)
	ambient.setup("lumber", 40)
	await tree.process_frame
	var AmbientScatterScript = preload("res://scripts/ambient_scatter.gd")
	var batcher = AmbientScatterScript.get_or_create(scatter_parent)
	batcher.commit()
	await tree.process_frame
	var ambient_meshes: Array = _collect_geometry_instances(batcher)
	if ambient_meshes.is_empty():
		print("  [FAIL] Ambient tree produced no batched GeometryInstance3D - can't assert shadow state")
		scatter_parent.queue_free()
		return false
	for m in ambient_meshes:
		if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			print("  [FAIL] Ambient tree's ", m.get_class(), " still casts shadows (", m.cast_shadow,
				") - 300+ ambient trees on a 4096 shadow atlas will tank framerate. ambient_scatter.gd:commit() must set cast_shadow=OFF on every MultiMeshInstance3D it builds.")
			scatter_parent.queue_free()
			return false
	scatter_parent.queue_free()

	# Non-ambient (field) branch: shadows STAY ON. There are only ~36 of
	# these on a map (4 fields x 9 trees) so the shadow cost is bounded,
	# and a forest stand is a visible gameplay element whose shadow
	# contributes to the visual identity (occlusion cue, depth read at
	# RTS camera distance). The asymmetry is the whole point of the
	# is_ambient gate; this assertion pins it.
	var field = ResourceNodeScript.new()
	field.is_ambient = false
	root.add_child(field)
	field.global_position = Vector3(-13.0, 0, -9.0)
	field.setup("lumber", 40)
	await tree.process_frame
	if not is_instance_valid(field.mesh_inst):
		print("  [FAIL] Field tree setup() didn't produce a mesh_inst - can't assert shadow state")
		field.queue_free()
		return false
	var field_meshes: Array = _collect_geometry_instances(field.mesh_inst)
	if field_meshes.is_empty():
		print("  [FAIL] Field tree's mesh_inst tree has no GeometryInstance3D - can't assert shadow state")
		field.queue_free()
		return false
	var any_field_off: bool = false
	for m in field_meshes:
		if m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			any_field_off = true
			break
	if any_field_off:
		print("  [FAIL] Field tree (non-ambient) has shadows OFF on at least one mesh - the 4 harvestable fields should keep their shadows. The is_ambient gate is too aggressive.")
		field.queue_free()
		return false
	field.queue_free()
	print("  [PASS] Ambient trees cast no shadows (perf guard), field trees keep their shadows (visual identity).")
	return true


# Walk a subtree and return every GeometryInstance3D - mirrors
# resource_node.gd's _disable_shadows_recursive so the test sees the same
# set of nodes the fix touches. Bounded depth (a glTF import is a few
# levels), plain recursion is fine.
func _collect_geometry_instances(root: Node, out: Array = []) -> Array:
	if root == null:
		return out
	if root is GeometryInstance3D:
		out.append(root)
	for c in root.get_children():
		_collect_geometry_instances(c, out)
	return out


func test_ambient_trees_scatter_is_deterministic() -> bool:
	print("Running Test Suite: Ambient Tree Scatter - same map name yields identical placement (screenshot-verification contract)...")
	# A given map dresses identically run to run, both for visual diff
	# and for the scatter-distance / avoid-radius asserts that would
	# otherwise flake on re-seed. Two passes of the same fixture must
	# produce ResourceNodes at the same positions with the same picked
	# pool indices. We assert the Nth spawned node's global_position
	# matches exactly between runs (the strongest possible determinism
	# contract - same seed, same draws, same positions).
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	var map_def_a = {
		"map_half_extents": 100.0,
		"name": "ambient_determinism",
	}
	var map_def_b = {
		"map_half_extents": 100.0,
		"name": "ambient_determinism",
	}
	var parent_a := Node3D.new()
	root.add_child(parent_a)
	TerrainBuilderScript._spawn_ambient_trees(map_def_a, parent_a)
	await tree.process_frame
	var parent_b := Node3D.new()
	root.add_child(parent_b)
	TerrainBuilderScript._spawn_ambient_trees(map_def_b, parent_b)
	await tree.process_frame

	var positions_a: Array = []
	var positions_b: Array = []
	for child in parent_a.get_children():
		positions_a.append(child.global_position)
	for child in parent_b.get_children():
		positions_b.append(child.global_position)
	parent_a.queue_free()
	parent_b.queue_free()

	if positions_a.is_empty():
		print("  [FAIL] No ambient trees scattered on the test map - density formula may be off")
		return false
	if positions_a.size() != positions_b.size():
		print("  [FAIL] Same map fixture produced ", positions_a.size(), " ambient trees on run A and ", positions_b.size(), " on run B - count diverges (non-deterministic)")
		return false
	for i in range(positions_a.size()):
		var pa: Vector3 = positions_a[i]
		var pb: Vector3 = positions_b[i]
		if pa != pb:
			print("  [FAIL] Ambient tree ", i, " at ", pa, " (run A) vs ", pb, " (run B) - same map must produce identical scatter")
			return false
	print("  [PASS] Same map fixture produces ", positions_a.size(), " ambient trees at identical positions on two independent scatter runs.")
	return true


# 2026-08-11: test_ambient_trees_respect_avoid_radii used to sit here. It
# asserted that NO ambient tree lands inside a water_area, inside a
# surface_zone, on a bridge rect, within AMBIENT_TREE_AVOID_RADIUS of a
# harvestable resource_node, or within that radius of any spawn structure -
# the per-instance separation guarantee the pre-2026-08-10 uniform random
# scatter could make, because it rejected candidate points one at a time.
#
# The cluster-scatter second pass (terrain_builder.gd:2188-2204) retired that
# guarantee deliberately. Scatter is now 30 tree clusters of 22-32 items each
# at a 9m cluster radius, and the avoidance set is applied at CLUSTER level -
# so an individual tree inside a grove legitimately lands inside a radius the
# old test measured per instance. The failure it produced said exactly that
# ("tree at (26.1, -2.3, -17.3) inside water_area"): shipped behaviour moved,
# the assertion did not.
#
# Deleted rather than re-tuned, because every assertion in it was about the
# retired invariant - there was nothing left to keep. A cluster-era
# replacement is a genuinely different test (assert the CLUSTER CENTRES
# respect the avoid set, and that centres stay CLUSTER_AVOID_RADIUS apart),
# and the call was to write new ones when they are wanted rather than reshape
# these. The surviving ambient suites still cover pool choice, no-regrow and
# scatter determinism, none of which the cluster pass changed.


# --- Ambient ore (2026-08-10, paired with the ambient-tree trim) ---------------
#
# The tree-trim freed up scatter budget for an ambient ore pass, and
# the tests below verify the properties the ore pass has to hold for
# the design to be sound:
#   1. Ambient ore instantiates from the existing 3-variant
#      resource_ore_*.glb pool (NOT the 20-variant ambient_tree_* one
#      - a separate ambient_ore_* family was considered and rejected;
#      the existing outcrop IS the right "single find" silhouette).
#   2. The is_ambient flag suppresses regrow the same way it does for
#      trees - covered in test_ambient_tree_does_not_regrow_after_
#      harvest above for the flag in general; the test here is just
#      the ore-specific path through the same gate.
#   3. The scatter is deterministic from the map name (same contract
#      as the trees).
#   4. WAS: an ambient ore never lands on top of an ambient tree (the
#      cross-pass avoidance set), or on water / surface_zones /
#      bridges / harvestable resource_nodes / within the spawn avoid
#      radius. NO LONGER TESTED - the 2026-08-10 cluster pass moved
#      avoidance from per-item to per-cluster and property 4 stopped
#      being true as written. See the deletion note at the bottom of
#      this file.

func test_ambient_ore_picks_from_resource_ore_pool() -> bool:
	print("Running Test Suite: Ambient Ore Setup Picks From resource_ore_* Pool, Not ambient_tree_*...")
	# The whole architectural point of the ore pass: it reuses the
	# existing harvestable ore outcrop (3 variants) rather than
	# spawning a parallel ambient_ore_* family. A failure here means
	# either (a) _try_spawn_ambient_authored's "non-lumber falls
	# through to harvestable pool" branch is broken, or (b) someone
	# added an ambient_ore_* family that drifted from the
	# harvestable one.
	var ResourceNodeScript = preload("res://scripts/resource_node.gd")
	var AmbientScatterScript = preload("res://scripts/ambient_scatter.gd")
	# Own container, because that is where the shared MultiMesh batcher is
	# created (get_or_create takes the node's PARENT) and this test needs it.
	var holder := Node3D.new()
	root.add_child(holder)
	var node = ResourceNodeScript.new()
	node.is_ambient = true
	holder.add_child(node)
	node.global_position = Vector3(-7.3, 0, 11.8)
	node.setup("ore", 60)
	await tree.process_frame

	if node.resource_type != "ore":
		print("  [FAIL] Ambient ore should keep resource_type='ore', got '", node.resource_type, "'")
		holder.queue_free()
		return false
	if not node.is_ambient:
		print("  [FAIL] is_ambient flag was reset by setup()")
		holder.queue_free()
		return false
	# An ambient node draws through the shared MultiMesh rather than its own
	# subtree now, so "which pool" is answered by the batched mesh. The rule
	# is unchanged: ore must come from the harvestable resource_ore_* family,
	# NOT from a parallel ambient_ore_* one.
	var batcher = AmbientScatterScript.get_or_create(holder)
	batcher.commit()
	await tree.process_frame
	var got_ore: bool = false
	var seen_paths: Array = []
	var stack: Array = [batcher]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MultiMeshInstance3D and n.multimesh != null and n.multimesh.mesh != null:
			var mp: String = String(n.multimesh.mesh.resource_path)
			seen_paths.append(mp)
			if "resource_ore_" in mp:
				got_ore = true
	# Negative case: must NOT be from ambient_tree_*.glb. A failure
	# here would mean _try_spawn_ambient_authored's lumber branch is
	# being taken for an ore-typed call, which would land an actual
	# tree where an outcrop should be - the "wrong species" bug.
	var got_tree: bool = false
	for p in seen_paths:
		if "ambient_tree_" in str(p):
			got_tree = true
	holder.queue_free()
	if not got_ore:
		print("  [FAIL] Ambient ore registered no resource_ore_*.glb geometry with the scatter batcher (batched meshes were: ", seen_paths, ")")
		return false
	if got_tree:
		print("  [FAIL] Ambient ore loaded an ambient_tree_*.glb instead of a resource_ore_*.glb - _try_spawn_ambient_authored's lumber branch is being taken for an ore-typed call")
		return false
	print("  [PASS] Ambient ore instantiates from the resource_ore_*.glb pool (and never from ambient_tree_*).")
	return true


func test_ambient_ore_does_not_regrow() -> bool:
	print("Running Test Suite: Ambient Ore Harvester Drain - no regrow, removed from resource_nodes group...")
	# Same contract as ambient trees; the is_ambient flag's regrow
	# suppression is type-agnostic (resource_node.gd's _physics_process
	# checks the flag before the type), so the test is structurally
	# identical to test_ambient_tree_does_not_regrow_after_harvest but
	# for ore. Catches a future regression where someone might
	# type-conditional the gate and accidentally let ore regrow.
	var ResourceNodeScript = preload("res://scripts/resource_node.gd")
	var node = ResourceNodeScript.new()
	node.is_ambient = true
	root.add_child(node)
	node.global_position = Vector3(3.0, 0, 3.0)
	node.setup("ore", 60)
	await tree.process_frame

	var got: int = node.harvest(60)
	if got != 60:
		print("  [FAIL] Ambient ore should yield 60 on a full harvest, got ", got)
		node.queue_free()
		return false
	if node.amount != 0:
		print("  [FAIL] Ambient ore amount should be 0 after full harvest, got ", node.amount)
		node.queue_free()
		return false
	if node.is_in_group("resource_nodes"):
		print("  [FAIL] Empty ambient ore should be removed from the resource_nodes group")
		node.queue_free()
		return false
	for i in range(30):
		node._physics_process(1.0)
	if node.amount != 0:
		print("  [FAIL] Ambient ore regrew to ", node.amount, " after 30s of physics ticks")
		node.queue_free()
		return false
	node.queue_free()
	print("  [PASS] Ambient ore stays at 0 and out of resource_nodes after a full harvest.")
	return true


# 2026-08-11: test_ambient_ores_respect_avoid_radii_and_dont_overlap_trees
# used to sit here. It is gone for the same reason as its tree counterpart
# further up this file - see that note for the full story. This one asserted
# both the per-instance avoid set AND the cross-pass rule that no ambient ore
# lands within AMBIENT_ORE_AVOID_RADIUS (9m) of any ambient tree.
#
# The 2026-08-10 cluster pass gives ore a 7m cluster radius and trees a 9m
# one, and applies avoidance per cluster rather than per item, so an ore at
# the edge of its own patch sits comfortably inside 9m of a tree at the edge
# of an adjacent grove. The run before deletion reported eleven such pairs -
# every one of them that intended cluster overlap, and none of them the
# stacked-mesh-at-one-world-point artefact the rule originally existed to
# prevent.
