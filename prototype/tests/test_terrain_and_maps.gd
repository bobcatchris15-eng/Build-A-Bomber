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

func test_vision_blocked_by_real_obstacle_cover() -> bool:
	print("Running Test Suite: Fog-of-War - Buildings/Obstacles Are Real Cover, Not Just Movement Blockers (Map Variety Batch)...")
	await tree.process_frame

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var enemy = CharacterBody3D.new()
	enemy.set_script(BattleUnitScript)
	skirmish.add_child(enemy)
	enemy.team = skirmish.ENEMY_TEAM
	enemy.set_meta("team", skirmish.ENEMY_TEAM)
	enemy.add_to_group("units")
	enemy.add_to_group("damageable")
	enemy.vision_range = 5.0
	enemy.global_position = Vector3(300, 0, 0) # far from the default map's lake/bases/obstacles

	var viewer = CharacterBody3D.new()
	viewer.set_script(BattleUnitScript)
	skirmish.add_child(viewer)
	viewer.team = skirmish.PLAYER_TEAM
	viewer.set_meta("team", skirmish.PLAYER_TEAM)
	viewer.add_to_group("units")
	viewer.add_to_group("damageable")
	viewer.vision_range = 30.0
	viewer.global_position = Vector3(280, 0, 0)

	skirmish._recalc_fog_of_war()
	if enemy.fog_hidden or not enemy.visible:
		print("  [FAIL] Sanity check failed: with clear line of sight and no obstacle, the enemy should already be visible")
		skirmish.queue_free()
		return false

	# Real cover, built the exact same way TerrainBuilder's rock/building
	# obstacles are (a StaticBody3D on collision layer 1), placed squarely
	# between viewer and enemy - proves _has_line_of_sight() genuinely
	# raycasts against that layer rather than the fog check being pure
	# distance math with an obstacle just coincidentally nearby.
	var cover = StaticBody3D.new()
	cover.collision_layer = 1
	cover.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(6.0, 6.0, 6.0)
	shape.shape = box_shape
	cover.add_child(shape)
	skirmish.add_child(cover)
	cover.global_position = Vector3(290, 3.0, 0)
	await tree.process_frame # let the physics server register the new collider before raycasting against it

	skirmish._recalc_fog_of_war()
	if not enemy.fog_hidden or enemy.visible:
		print("  [FAIL] A real obstacle directly between viewer and enemy should block vision (fog_hidden should flip true) even though the enemy is still within vision_range")
		skirmish.queue_free()
		return false

	cover.queue_free()
	await tree.process_frame
	skirmish._recalc_fog_of_war()
	if enemy.fog_hidden or not enemy.visible:
		print("  [FAIL] Removing the obstacle should restore line of sight and reveal the enemy again")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Obstacles on the terrain collision layer genuinely block vision (a real LOS raycast, not just distance), and stop blocking once removed.")
	return true

func test_navmesh_routes_around_the_lake() -> bool:
	print("Running Test Suite: Real Pathfinding - Navmesh Routes Around The Lake...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	if not skirmish.ground_nav_map.is_valid() or not skirmish.water_nav_map.is_valid():
		print("  [FAIL] Skirmish should bake valid ground/water navigation maps at _ready()")
		skirmish.queue_free()
		return false

	# Read the lake's real position/extent from the live map instead of a
	# hardcoded literal (Skirmish refinement pass: lake_crossing's lake is
	# now an organic water_blob, not a fixed rect, and map scale itself can
	# change independently of this test) - is_position_blocked() is the
	# actual ground-truth query every other system already trusts, so using
	# it here instead of re-deriving bounds keeps this test honest no
	# matter how the map's water is authored.
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	var lake_center: Vector3 = Vector3(27, 0, 0)
	var lake_span: float = 15.0
	if not skirmish.current_map.get("water_blobs", []).is_empty():
		var blob = skirmish.current_map.water_blobs[0]
		lake_center = blob.center
		lake_span = blob.get("radius", 10.0)
	elif not skirmish.current_map.get("water_areas", []).is_empty():
		var w = skirmish.current_map.water_areas[0]
		lake_center = w.center
		lake_span = max(w.half_extents.x, w.half_extents.y)

	# Query straight across the lake - a real ground path must detour
	# around it, not cut straight through.
	var start = Vector3(lake_center.x - lake_span * 2.5, 0, lake_center.z)
	var end = Vector3(lake_center.x + lake_span * 2.5, 0, lake_center.z)
	var path = NavigationServer3D.map_get_path(skirmish.ground_nav_map, start, end, true)
	if path.size() < 2:
		print("  [FAIL] Expected a real multi-point path across the map, got ", path.size(), " points")
		skirmish.queue_free()
		return false
	var crosses_lake = false
	for p in path:
		if TerrainBuilderScript.is_position_blocked(skirmish.current_map, p):
			crosses_lake = true
	if crosses_lake:
		print("  [FAIL] Ground navmesh path should detour around the lake, not cross through its bounds")
		skirmish.queue_free()
		return false

	# The water navmesh, conversely, should ONLY have geometry inside the
	# lake bounds - a path query from land to land on the water map
	# should be empty/degenerate (there's simply no connected water there).
	var water_path = NavigationServer3D.map_get_path(skirmish.water_nav_map, lake_center, lake_center + Vector3(0, 0, 3), true)
	if water_path.size() < 2:
		print("  [FAIL] A short path fully inside the lake should resolve on the water navmesh, got ", water_path.size(), " points")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Ground navmesh correctly detours around the lake; water navmesh correctly covers the lake interior.")
	return true

func test_ground_and_naval_units_use_different_nav_maps() -> bool:
	print("Running Test Suite: Real Pathfinding - Ground/Naval Units Get The Correct Nav Map, Flying Units Skip It...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var bp_manager = skirmish.bp_manager
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var ground_bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": []
	}
	var ground_unit = CharacterBody3D.new()
	ground_unit.set_script(BattleUnitScript)
	skirmish.add_child(ground_unit)
	ground_unit.setup(ground_bp, 0, bp_manager)
	if not is_instance_valid(ground_unit.nav_agent):
		print("  [FAIL] A ground unit spawned in a real Skirmish match should get a nav_agent")
		skirmish.queue_free()
		return false
	if ground_unit.nav_agent.get_navigation_map() != skirmish.ground_nav_map:
		print("  [FAIL] A ground unit's nav_agent should be assigned to the ground nav map")
		skirmish.queue_free()
		return false

	var naval_bp = {
		"version": 1.0, "hull_type": "heavy_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "naval_propeller", "settings": {"size": 1.0, "count": 2}},
		"modules": []
	}
	var naval_unit = CharacterBody3D.new()
	naval_unit.set_script(BattleUnitScript)
	skirmish.add_child(naval_unit)
	naval_unit.setup(naval_bp, 0, bp_manager)
	if not is_instance_valid(naval_unit.nav_agent):
		print("  [FAIL] A naval unit spawned in a real Skirmish match should get a nav_agent")
		skirmish.queue_free()
		return false
	if naval_unit.nav_agent.get_navigation_map() != skirmish.water_nav_map:
		print("  [FAIL] A naval unit's nav_agent should be assigned to the water nav map, not the ground one")
		skirmish.queue_free()
		return false

	var flying_bp = {
		"version": 1.0, "hull_type": "light_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "helicopter_rotors", "settings": {}},
		"modules": []
	}
	var flying_unit = CharacterBody3D.new()
	flying_unit.set_script(BattleUnitScript)
	skirmish.add_child(flying_unit)
	flying_unit.setup(flying_bp, 0, bp_manager)
	if is_instance_valid(flying_unit.nav_agent):
		print("  [FAIL] A flying unit should skip navigation entirely (open air, nothing to route around)")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Ground units path on the ground map, naval units path on the water map, flying units skip navigation entirely.")
	return true


# End-to-end check that a unit given a real order_move() actually translates
# and actually detours around the lake, not just that the underlying navmesh
# query and nav_agent assignment are individually correct in isolation. This
# test exists because an earlier debug session found that a battle_unit's
# move_speed depends on the hull having an actual locomotion MODULE child
# (category "locomotion", added to "modules") - the top-level "locomotion"
# field alone (type_id/settings) is not enough on its own, it's only used to
# pick movement traits/count_contrib. Real saved blueprints always carry both
# (serialize_hull() emits every hull child with module_data, which includes
# the locomotion part placed via update_locomotion()) - this test's blueprint
# mirrors that real shape rather than the top-level-field-only shorthand used
# by nav_agent-assignment-only tests above.
func test_unit_order_move_actually_navigates_around_the_lake() -> bool:
	print("Running Test Suite: Real Pathfinding - order_move() Actually Moves A Unit Around The Lake...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "tracked_treads", "name": "Tracked Treads", "position": {"x": 0.0, "y": -0.4, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	skirmish.add_child(unit)
	unit.global_position = Vector3(0, 0.5, 0)
	unit.setup(bp, 0, skirmish.bp_manager)

	if unit.move_speed <= 0.0:
		print("  [FAIL] Unit with a real locomotion module should have nonzero move_speed, got ", unit.move_speed)
		skirmish.queue_free()
		return false

	# Same live-map-derived lake bounds as test_navmesh_routes_around_the_lake()
	# - see that test's comment for why a hardcoded literal doesn't hold up
	# across map scale/shape changes.
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	var lake_center: Vector3 = Vector3(27, 0, 0)
	var lake_span: float = 15.0
	if not skirmish.current_map.get("water_blobs", []).is_empty():
		var blob = skirmish.current_map.water_blobs[0]
		lake_center = blob.center
		lake_span = blob.get("radius", 10.0)
	elif not skirmish.current_map.get("water_areas", []).is_empty():
		var w = skirmish.current_map.water_areas[0]
		lake_center = w.center
		lake_span = max(w.half_extents.x, w.half_extents.y)

	var start_pos = unit.global_position
	unit.order_move(Vector3(lake_center.x + lake_span * 2.5, 0.5, lake_center.z))

	var crossed_lake = false
	for i in range(140):
		unit._physics_process(1.0 / 60.0)
		unit.move_and_slide()
		if TerrainBuilderScript.is_position_blocked(skirmish.current_map, unit.global_position):
			crossed_lake = true

	var moved_dist = start_pos.distance_to(unit.global_position)
	if moved_dist < 5.0:
		print("  [FAIL] Unit given order_move() across the map barely moved (", moved_dist, " units) - pathfinding/steering integration is not producing real movement")
		skirmish.queue_free()
		return false
	if crossed_lake:
		print("  [FAIL] Unit's real movement path cut through the lake bounds instead of detouring around it")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A real order_move() across the map produces real movement (", moved_dist, " units) that detours around the lake.")
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

	var nav = TerrainBuilderScript.build_navmeshes(map_def)
	await tree.process_frame
	await tree.process_frame

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
	await tree.process_frame
	await tree.process_frame
	var path_no_bridge = NavigationServer3D.map_get_path(nav_no_bridge.ground_map, start, end, true)
	var reached_no_bridge = path_no_bridge.size() >= 2 and path_no_bridge[path_no_bridge.size() - 1].distance_to(end) <= 3.0
	for k in ["ground_region", "water_region", "amphibious_region", "deep_water_region"]:
		if nav_no_bridge[k].is_valid(): NavigationServer3D.free_rid(nav_no_bridge[k])
	for k in ["ground_map", "water_map", "amphibious_map", "deep_water_map"]:
		NavigationServer3D.free_rid(nav_no_bridge[k])

	var nav_with_bridge = TerrainBuilder.build_navmeshes(map_with_bridge)
	await tree.process_frame
	await tree.process_frame
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
	await tree.process_frame
	await tree.process_frame

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
	await tree.process_frame
	await tree.process_frame

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

func test_build_placement_rejects_water_and_obstacles() -> bool:
	print("Running Test Suite: Multi-Map Terrain - Build Placement Rejects Water/Obstacles (previously nothing stopped this)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	skirmish.placing = {"kind": "refinery", "cost_metal": 150, "cost_crystal": 0}
	var metal_before = skirmish.economy[skirmish.PLAYER_TEAM].metal
	# lake_crossing's real lake is at (27,0,0) with half-extents (10.5,10.5)
	# (scaled 1.5x from the map's original size in the Skirmish refinement
	# pass) - the placement should be rejected as water regardless of base
	# proximity, which is all this test actually asserts.
	skirmish._try_place_building(Vector3(27, 0, 0))
	var buildings_after = skirmish.get_team_buildings(skirmish.PLAYER_TEAM).size()

	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before:
		print("  [FAIL] Placing a building inside the lake should be rejected before spending any resources")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Attempting to place a building inside water is rejected without spending resources.")
	return true

func test_c4_exit_point_is_height_snapped_to_real_terrain() -> bool:
	print("Running Test Suite: C4 - Exit Point Is Height-Snapped To Real Terrain, Not A Flat Offset (RTS_CORE_ROADMAP.md C4)...")
	await tree.process_frame
	# highland_chokepoint has a real heightmap plateau right at map center -
	# terrain_height_at() is genuinely non-flat here, unlike lake_crossing.
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	skirmish.map_id = "highland_chokepoint"
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	var factory = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light")
	if not factory:
		print("  [FAIL] No starting light manufactory found.")
		skirmish.queue_free()
		return false

	var exit_pos = factory.get_exit_position()
	var real_terrain_y = skirmish.terrain_height_at(exit_pos)
	if abs(exit_pos.y - (real_terrain_y + 0.5)) > 0.05:
		print("  [FAIL] Exit position Y should be snapped to real terrain height + 0.5, got exit.y=", exit_pos.y, " terrain_height_at=", real_terrain_y)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] The factory's exit point snaps to real terrain height instead of a flat, unsnapped offset.")
	return true

func test_c4_blocked_exit_holds_job_done_nudges_blockers_then_spawns() -> bool:
	print("Running Test Suite: C4 - Blocked Exit Holds The Job 'done', Nudges Blockers, Then Spawns (RTS_CORE_ROADMAP.md C4)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var factory = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light")
	if not factory:
		print("  [FAIL] No starting light manufactory found.")
		skirmish.queue_free()
		return false

	# 4 real, moveable units parked right on the exit (small spread so their
	# post-nudge moves don't all collapse onto the exact same point).
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "tracked_treads", "name": "Tracked Treads", "position": {"x": 0.0, "y": -0.4, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var exit_pos = factory.get_exit_position()
	var blockers = []
	# Spread with a deliberate +z bias (away from the whole manufactory
	# cluster) rather than +/-x - lake_crossing's 3 manufactories sit close
	# together in x (light/medium/heavy offset +/-8 from one shared factory
	# spawn), so a purely -x nudge can walk a unit toward a NEIGHBORING
	# manufactory's own footprint instead of into open ground, needing a
	# real navmesh detour around it (a real, if narrow, edge case notify_
	# blocker's straight-line nudge doesn't itself guard against - found by
	# watching one of 4 blockers get stuck oscillating a few meters short
	# of clearing, exactly at a neighboring manufactory's footprint edge).
	for spread in [Vector3(0, 0, 1.8), Vector3(0.5, 0, 1.8), Vector3(-0.5, 0, 1.8), Vector3(0, 0, 2.2)]:
		var u = CharacterBody3D.new()
		u.set_script(BattleUnitScript)
		skirmish.add_child(u)
		u.global_position = exit_pos + spread
		u.setup(bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)
		blockers.append(u)

	var units_before = skirmish.get_team_units(skirmish.PLAYER_TEAM).size()
	factory.queue_unit({}, 0.05) # near-instant build_time - the exit is the actual bottleneck here
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	# The build timer has long since expired, but a real production authority
	# holds the job `done` (never popped) instead of spawning on top of the
	# blockers.
	if skirmish.get_team_units(skirmish.PLAYER_TEAM).size() > units_before:
		print("  [FAIL] A unit spawned despite 4 real units parked on the exit - blocked-exit detection did not hold the job")
		skirmish.queue_free()
		return false

	var any_nudged = false
	for u in blockers:
		if u.order == u.OrderType.MOVE:
			any_nudged = true
	if not any_nudged:
		print("  [FAIL] None of the 4 blocking units were nudged (notify_blocker) - they should have each received a real move order off the exit")
		skirmish.queue_free()
		return false

	# Let the nudged units actually walk clear and the job finally spawn.
	var spawned = false
	for i in range(300):
		await tree.process_frame
		if skirmish.get_team_units(skirmish.PLAYER_TEAM).size() > units_before:
			spawned = true
			break
	if not spawned:
		print("  [FAIL] The blocked job never spawned once the blockers had time to clear the exit")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A blocked exit holds the finished job, nudges the blocking units clear, and spawns once the exit is actually free.")
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
	await tree.process_frame

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

func test_b9_minimap_samples_water_and_hides_reveals_enemy_blips() -> bool:
	print("Running Test Suite: Minimap - Real Water Sample + Fog-Gated Enemy Blips (RTS_CORE_ROADMAP.md B9)...")
	# Deliberately tests the real Image (skirmish._minimap_static_image /
	# _minimap_image) directly, not a render-to-texture screenshot -
	# headless never rasterizes a Viewport, which is exactly why B9 is
	# specified as a real Image bake in the first place (see skirmish.gd's
	# _setup_minimap() comment).
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var FactionCatalogScript = preload("res://scripts/faction_catalog.gd")

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# lake_crossing (the default map) has a real water_blob centered at
	# (54, 0, 0), radius 22 - well inside it, away from any surface_zones.
	# _minimap_static_image is FORMAT_RGB8, so an exact float compare
	# against the raw MINIMAP_WATER_COLOR constant would fail on harmless
	# 8-bit quantization rounding (confirmed empirically) - _color_close()
	# tolerates that, same reasoning as this suite's screenshot-diff test.
	var water_cell = skirmish._minimap_world_to_cell(54.0, 0.0)
	var water_sample = skirmish._minimap_static_image.get_pixel(water_cell.x, water_cell.y)
	if not _color_close(water_sample, skirmish.MINIMAP_WATER_COLOR):
		print("  [FAIL] A known water region should bake to MINIMAP_WATER_COLOR on the static minimap, got ", water_sample)
		skirmish.queue_free()
		return false

	# Ground far from the lake shouldn't get the water tint.
	var land_cell = skirmish._minimap_world_to_cell(-200.0, -200.0)
	var land_sample = skirmish._minimap_static_image.get_pixel(land_cell.x, land_cell.y)
	if _color_close(land_sample, skirmish.MINIMAP_WATER_COLOR):
		print("  [FAIL] Open ground far from the lake should NOT sample as water on the minimap")
		skirmish.queue_free()
		return false

	var enemy = CharacterBody3D.new()
	enemy.set_script(BattleUnitScript)
	skirmish.add_child(enemy)
	enemy.team = skirmish.ENEMY_TEAM
	enemy.set_meta("team", skirmish.ENEMY_TEAM)
	enemy.add_to_group("units")
	enemy.add_to_group("damageable")
	enemy.vision_range = 5.0
	enemy.global_position = Vector3(200, 0, 200) # far from any existing base/unit, same spot the fog test uses

	skirmish._recalc_fog_of_war() # also runs _update_minimap()
	var enemy_cell = skirmish._minimap_world_to_cell(200.0, 200.0)
	var hidden_sample = skirmish._minimap_image.get_pixel(enemy_cell.x, enemy_cell.y)
	var background_sample = skirmish._minimap_static_image.get_pixel(enemy_cell.x, enemy_cell.y)
	if hidden_sample != background_sample:
		print("  [FAIL] A fog-hidden enemy should NOT get a minimap blip - expected the plain background color ", background_sample, ", got ", hidden_sample)
		skirmish.queue_free()
		return false

	var near_player = CharacterBody3D.new()
	near_player.set_script(BattleUnitScript)
	skirmish.add_child(near_player)
	near_player.team = skirmish.PLAYER_TEAM
	near_player.set_meta("team", skirmish.PLAYER_TEAM)
	near_player.add_to_group("units")
	near_player.add_to_group("damageable")
	near_player.vision_range = 20.0
	near_player.global_position = Vector3(205, 0, 200) # within 20 units of the enemy

	skirmish._recalc_fog_of_war()
	var revealed_sample = skirmish._minimap_image.get_pixel(enemy_cell.x, enemy_cell.y)
	var expected_color = FactionCatalogScript.get_visual_color(FactionCatalogScript.DEFAULT_FACTION)
	if not _color_close(revealed_sample, expected_color):
		print("  [FAIL] A scouted enemy should get a minimap blip in its faction's visual color, expected ", expected_color, " got ", revealed_sample)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Minimap correctly samples a known water region, and only shows an enemy blip once that enemy is actually scouted (not while fog_hidden).")
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
		await tree.process_frame
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
	await tree.process_frame
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
	await tree.process_frame
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

func test_c1_building_placed_after_unit_is_moving_forces_a_repath() -> bool:
	print("Running Test Suite: C1 - A Building Placed Mid-Flight Forces a Live Repath (RTS_CORE_ROADMAP.md C1)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var bp = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "tracked_treads", "name": "Tracked Treads", "position": {"x": 0.0, "y": -0.4, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	skirmish.add_child(unit)
	unit.global_position = Vector3(-40, 0.5, 200)
	unit.setup(bp, skirmish.PLAYER_TEAM, skirmish.bp_manager)

	var block_pos = Vector3(0, 0, 200)
	unit.order_move(Vector3(40, 0.5, 200))
	# A few ticks of real straight-line travel BEFORE the building exists -
	# the whole point of this test is that the building lands in a path the
	# unit already committed to, not one it planned around from the start.
	# Real frames here too - the unit has to be genuinely under way, with a
	# live path corridor, before the building lands in front of it. Hand-
	# cranked ticks would leave it "moving" with a corridor the navigation
	# server never actually issued.
	for i in range(20):
		await tree.physics_frame

	var building = skirmish._spawn_prefab("heavy_manufactory", skirmish.ENEMY_TEAM, block_pos, skirmish.enemy_faction)
	var half_x = building.footprint.x / 2.0
	var half_z = building.footprint.z / 2.0
	# Same debounce wait as the test above, but now with the unit already
	# mid-flight - this is what actually exercises request_repath()/
	# _repath_live_units(), not just a fresh nav_agent picking up the
	# hole from a standing start.
	for i in range(5):
		await tree.process_frame

	# Same move_speed-budget reasoning as the test above (~7.2 u/s) - a bit
	# more headroom here since a mid-flight repath costs some extra time
	# re-planning around the new obstacle versus knowing about it from the
	# start.
	# DRIVEN ON REAL PHYSICS FRAMES, not by calling _physics_process() in a
	# tight loop.
	#
	# Both C1 movement tests used to advance the unit by calling
	# unit._physics_process(1/60) + move_and_slide() N times WITHOUT awaiting
	# anything, which made them the two flakiest tests in the suite - a
	# different one of the pair failed on each full run for no reason.
	#
	# The cause is that NavigationServer3D syncs its maps on real physics
	# steps. Inside a no-await loop the agent can never RECEIVE an updated
	# path, so every iteration steers on whichever corridor happened to be
	# cached when the loop started - and whether that corridor already knew
	# about the building was pure timing luck.
	#
	# Measured with scratch/probe_c1_repath_flake.gd, same scenario 6x each:
	#   manual ticks : 3/6 passed, final x = -23.5, 12.7, 8.2, 38.1, -9.8, 11.8
	#   real frames  : 6/6 passed, final x = 38.0, 38.1, 38.1, 38.1, 38.1, 38.1
	#
	# So the GAME was never flaky here - units route around a building
	# reliably, arriving within 0.1 units of the same spot every time. Only
	# the harness was. Awaiting physics_frame also means the unit's own
	# _physics_process runs the way it does in a match, rather than being
	# hand-cranked out of step with the servers it depends on.
	var entered_footprint = false
	for i in range(900):
		await tree.physics_frame
		if abs(unit.global_position.x - block_pos.x) < half_x and abs(unit.global_position.z - block_pos.z) < half_z:
			entered_footprint = true

	if entered_footprint:
		print("  [FAIL] A unit already mid-flight should repath around a building that appears in its way, not drive through its footprint AABB")
		skirmish.queue_free()
		return false
	if unit.global_position.x < 10.0:
		print("  [FAIL] Unit should have made it past the building to the far side (x >= 10) after the repath, got x=", unit.global_position.x)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A building placed directly in an already-moving unit's path triggers a real repath - it detours instead of driving through.")
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

func test_weapon_los_blocked_by_cover_and_skirmish_bug_fixes() -> bool:
	print("Running Test Suite: FABLE review fixes - weapon LOS cover, factory load-balancing, building overlap, defense faction...")

	# --- Part 1: weapon fire LOS is genuinely blocked by world geometry ---
	# (FABLE_REVIEW.md 3.1: the old check only blocked on own-vehicle hits, so
	# units fired straight through rocks/buildings.)
	var weapon_rig = Node3D.new()
	root.add_child(weapon_rig)
	var weapon = Node3D.new()
	weapon.set_script(load("res://scripts/auto_weapon.gd"))
	var w_data = ModuleData.new()
	w_data.type_id = "basic_cannon"
	weapon.set_meta("module_data", w_data)
	weapon_rig.add_child(weapon)
	# The LOS check is called directly below; per-tick targeting would crash
	# against this synthetic rig (no vehicle root), so switch it off.
	weapon.set_physics_process(false)
	weapon.global_position = Vector3(0, 1.0, 0)

	var los_target = StaticBody3D.new()
	los_target.collision_layer = 8
	los_target.collision_mask = 0
	var t_col = CollisionShape3D.new()
	var t_box = BoxShape3D.new()
	t_box.size = Vector3(2, 2, 2)
	t_col.shape = t_box
	los_target.add_child(t_col)
	root.add_child(los_target)
	los_target.global_position = Vector3(0, 1.0, -14.0)
	weapon.target = los_target
	# Aim the weapon at the target so the muzzle-forward ray offset points the right way
	weapon.look_at(los_target.global_position, Vector3.UP)

	await tree.process_frame

	var clear_result = weapon._is_line_of_sight_blocked()

	# Insert a wall (world-geometry layer 1) squarely between them
	var wall = StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var w_col = CollisionShape3D.new()
	var w_box = BoxShape3D.new()
	w_box.size = Vector3(6, 6, 1)
	w_col.shape = w_box
	wall.add_child(w_col)
	root.add_child(wall)
	wall.global_position = Vector3(0, 1.0, -7.0)

	await tree.process_frame

	var blocked_result = weapon._is_line_of_sight_blocked()

	weapon_rig.queue_free()
	los_target.queue_free()
	wall.queue_free()

	if clear_result != false:
		print("  [FAIL] LOS reported blocked with a clear line to the target (the target's own collider must not block the shot at itself).")
		return false
	if blocked_result != true:
		print("  [FAIL] LOS reported clear with a wall between weapon and target - cover does not block weapon fire.")
		return false

	# --- Part 2: Skirmish-level fixes need a real match instance ---
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# Shared per-tier production queue (RTS_CORE_ROADMAP.md A1, replacing
	# FABLE_REVIEW.md 2.4's old least-busy-factory routing): two manufactories
	# of the SAME tier now alias the exact same queue Array (OpenRA's
	# ClassicProductionQueue model - one line per team+tier, not per
	# building), so queuing via one is immediately visible through the other.
	var first_light = skirmish.get_team_factory(0, "light")
	if not first_light:
		print("  [FAIL] No starting light manufactory found.")
		skirmish.queue_free()
		return false
	var second_light = skirmish._spawn_prefab("light_manufactory", 0, first_light.global_position + Vector3(0, 0, 14), skirmish.player_faction)
	await tree.process_frame
	first_light.queue_unit({}, 60.0)
	if second_light.production_queue.size() != 1 or second_light.production_queue[0] != first_light.production_queue[0]:
		print("  [FAIL] A second manufactory of the same tier should share the exact same production queue as the first, not an independent one.")
		skirmish.queue_free()
		return false
	first_light.production_queue.clear()

	# Building overlap rejection (FABLE_REVIEW.md 3.3): placing a refinery on
	# top of an existing building must be invalid; a clear nearby spot valid.
	skirmish.placing = {"kind": "refinery", "cost_metal": 150, "cost_crystal": 0}
	var stacked = skirmish._placement_validity(first_light.global_position)
	var hq_pos = skirmish.player_hq.global_position
	# RTS_CORE_ROADMAP.md C3: buildable-area reach is a real per-building
	# adjacent_m now (HQ's default 8.0m, footprint-to-footprint), not a flat
	# 28m from any friendly building's center - -16 cleared the OLD rule
	# comfortably but sits outside HQ's own zone under the new one. -9
	# leaves only a ~3m gap past HQ's own footprint, safely inside 8.0m.
	var clear_spot = hq_pos + Vector3(0, 0, -9)
	var clear = skirmish._placement_validity(clear_spot)
	skirmish.placing = {}
	if stacked.valid:
		print("  [FAIL] Placement on top of an existing building was accepted - buildings can still be stacked.")
		skirmish.queue_free()
		return false
	if not clear.valid:
		print("  [FAIL] A clear spot near the base was rejected (%s) - overlap check is too aggressive." % clear.reason)
		skirmish.queue_free()
		return false

	# Defense buildings carry a real faction field (FABLE_REVIEW.md 3.7) -
	# updated by the later 1.7 fix to be the MATCH faction, not the
	# blueprint's own saved tag (see
	# test_match_faction_overrides_blueprint_faction_stats_and_looks for the
	# full stats+looks proof). Blueprint deliberately tagged a DIFFERENT
	# faction than the match here to prove it's really overridden, not just
	# carried through by coincidence.
	skirmish.player_faction = "bayou_irregulars"
	var defense_bp = {
		"hull_type": "pillbox_foundation",
		"faction": "industrialists",
		"armor_material": "hardened_steel",
		"armor_thickness": 1.0,
		"locomotion": {"type_id": "", "settings": {}},
		"modules": [{"type_id": "heavy_machine_gun", "position": {"x": 0, "y": 1.2, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}}]
	}
	var defense = skirmish.spawn_defense(defense_bp, 0, hq_pos + Vector3(16, 0, 0))
	await tree.process_frame
	if defense.faction != "bayou_irregulars":
		print("  [FAIL] Defense building faction field is '%s', expected the match faction 'bayou_irregulars' (not the blueprint's own 'industrialists' tag)." % defense.faction)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Weapon fire is blocked by real cover, same-tier factories share one production queue, buildings can't stack, and defenses carry their faction.")
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

	var loaded = MapCatalogScript.get_map("lake_crossing")
	if loaded != expected_lake_crossing:
		print("  [FAIL] JSON-loaded lake_crossing does not deep-equal the checked-in snapshot of the old const's values.")
		print("    Loaded:   ", loaded)
		print("    Expected: ", expected_lake_crossing)
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

	print("  [PASS] lake_crossing deep-equals the old const's exact values; every bundled map loads from JSON and validates clean.")
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

	var maps = TerrainBuilderScript.build_navmeshes(map_def)
	await tree.process_frame # let NavigationServer3D finish baking before querying

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

