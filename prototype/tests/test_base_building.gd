extends "res://tests/suite_base.gd"
# base building suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

func test_centerline_placement_does_not_self_mirror() -> bool:
	print("Running Test Suite: Centerline Placement Doesn't Mirror Onto Itself (found while visually verifying face-based mounting)...")
	# A module placed dead-center (local x ~= 0) - e.g. a frame_built railgun
	# mounted on the front/back centerline, a very natural placement for
	# that weapon type - would previously mirror onto its own position,
	# producing a fully-overlapping duplicate that read as a clipping-red
	# bug. Not mount-style-specific: any module placed on the centerline
	# hit this.
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await tree.process_frame

	placer._place_hull_from_ui("heavy_hull")
	await tree.process_frame
	placer._place_weapon_from_ui("gauss_railgun", Vector3(0, 0.75, 2.0), Vector3.UP)
	await tree.process_frame

	var railguns = []
	for c in placer.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "gauss_railgun":
			railguns.append(c)

	if railguns.size() != 1:
		print("  [FAIL] Centerline placement should produce exactly 1 module, not mirror onto itself, got ", railguns.size())
		placer.queue_free()
		return false
	if railguns[0].has_meta("mirrored_counterpart"):
		print("  [FAIL] Centerline-placed module should not have a mirrored_counterpart at all")
		placer.queue_free()
		return false

	placer.check_all_clipping()
	if placer.clipping_detected:
		print("  [FAIL] Centerline placement should not trigger a false-positive clipping flag")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Centerline-placed modules no longer mirror onto their own position.")
	return true


func test_ui_flyout_placement() -> bool:
	print("Running Test Suite: UIFlyout edge flipping + viewport clamping...")
	# The flyout primitive's whole job is landing somewhere sensible relative to
	# the control that opened it. Placement is also the part most likely to
	# silently regress, because a mispositioned flyout still renders - it is just
	# in the wrong place, or half off the screen, which no smoke test notices.
	#
	# screen_bounds_override exists precisely so this can be asserted: headless
	# Godot's viewport is whatever project settings imply, not what a test set up,
	# so without an injectable rect every assertion here would measure the wrong
	# rectangle. See the property's comment in ui_flyout.gd.
	var UIFlyoutScript = preload("res://scripts/ui_flyout.gd")
	var BOUNDS := Rect2(Vector2.ZERO, Vector2(1280, 720))

	var host = Control.new()
	host.size = BOUNDS.size
	root.add_child(host)

	# A source button hard against the BOTTOM edge. Asking for BELOW there must
	# flip ABOVE rather than hang off the screen.
	var low_btn = Button.new()
	low_btn.text = "SPEC"
	low_btn.position = Vector2(80, 700)
	low_btn.size = Vector2(120, 20)
	host.add_child(low_btn)

	var f = UIFlyoutScript.create(host, "Hull Specification")
	f.screen_bounds_override = BOUNDS
	for i in range(6):
		var pad = Label.new()
		pad.text = "ARMOR MATERIAL ROW %d" % i
		f.body().add_child(pad)
	f.open_from(low_btn, UIFlyoutScript.Align.BELOW)
	# open_from defers placement by two frames on purpose (a container has no real
	# size until it has computed its minimum), so this must wait longer than that.
	for i in range(6):
		await tree.process_frame

	var r: Rect2 = f.get_rect()
	if r.size.y < 4.0:
		print("  [FAIL] Flyout never laid out (size=", r.size, ") - placement assertions would be meaningless.")
		host.queue_free()
		return false
	if not BOUNDS.encloses(r):
		print("  [FAIL] Flyout near the bottom edge left the viewport: rect=", r, " bounds=", BOUNDS)
		host.queue_free()
		return false
	# Flipped ABOVE means it must not cover the button that opened it.
	if r.intersects(low_btn.get_global_rect()):
		print("  [FAIL] Flyout overlaps its own trigger: flyout=", r, " trigger=", low_btn.get_global_rect())
		host.queue_free()
		return false

	# A source hard against the RIGHT edge, asked to open RIGHT_OF: same contract
	# on the other axis, which is a genuinely separate branch in _rect_for_source.
	var right_btn = Button.new()
	right_btn.text = "SPEC"
	right_btn.position = Vector2(1200, 300)
	right_btn.size = Vector2(70, 20)
	host.add_child(right_btn)

	var f2 = UIFlyoutScript.create(host, "Faction")
	f2.screen_bounds_override = BOUNDS
	for i in range(4):
		var pad2 = Label.new()
		pad2.text = "THE AERODROME CARTEL"
		f2.body().add_child(pad2)
	f2.open_from(right_btn, UIFlyoutScript.Align.RIGHT_OF)
	for i in range(6):
		await tree.process_frame

	var r2: Rect2 = f2.get_rect()
	if not BOUNDS.encloses(r2):
		print("  [FAIL] Flyout near the right edge left the viewport: rect=", r2, " bounds=", BOUNDS)
		host.queue_free()
		return false

	host.queue_free()
	await tree.process_frame
	print("  [PASS] Flyouts flip off both the bottom and right edges, stay inside the viewport, and never cover their own trigger.")
	return true

func test_build_legality_gate() -> bool:
	print("Running Test Suite: Build-Legality Gate (hull + weapon-or-support + locomotion-or-static)...")

	var no_hull = {"hull_type": "", "modules": []}
	if ModuleCatalog.validate_build_legality(no_hull).valid:
		print("  [FAIL] A blueprint with no hull should be invalid")
		return false

	var brick = {"hull_type": "medium_hull", "modules": []}
	if ModuleCatalog.validate_build_legality(brick).valid:
		print("  [FAIL] A hull with no weapon/support and no locomotion should be invalid (accidental brick)")
		return false

	var weapon_no_loco = {"hull_type": "medium_hull", "modules": [{"type_id": "basic_cannon"}]}
	var weapon_no_loco_result = ModuleCatalog.validate_build_legality(weapon_no_loco)
	if weapon_no_loco_result.valid:
		print("  [FAIL] A weapon alone doesn't excuse missing locomotion on a non-foundation hull")
		return false
	if "locomotion" not in weapon_no_loco_result.reason.to_lower():
		print("  [FAIL] The rejection reason should mention locomotion, got: ", weapon_no_loco_result.reason)
		return false

	var full_mobile = {"hull_type": "medium_hull", "modules": [{"type_id": "basic_cannon"}, {"type_id": "tracked_treads"}]}
	if not ModuleCatalog.validate_build_legality(full_mobile).valid:
		print("  [FAIL] Hull + weapon + locomotion should be a valid mobile design")
		return false

	# Support-only (no weapon) on a foundation - a static sensor tower or
	# generator outpost - is a legitimate intentional build, not a brick.
	var static_support = {"hull_type": "pillbox_foundation", "modules": [{"type_id": "sensor_suite"}]}
	if not ModuleCatalog.validate_build_legality(static_support).valid:
		print("  [FAIL] A foundation with a support module (no weapon) should be a valid intentional static build")
		return false

	# Support-only on a MOBILE hull with no locomotion is still a brick -
	# support doesn't excuse missing locomotion any more than a weapon does.
	var mobile_support_no_loco = {"hull_type": "medium_hull", "modules": [{"type_id": "sensor_suite"}]}
	if ModuleCatalog.validate_build_legality(mobile_support_no_loco).valid:
		print("  [FAIL] A non-foundation hull with only a support module and no locomotion should still be invalid")
		return false

	# drone_carrier alone (no "weapon"-category module) counts as a real
	# combat purpose, not an accidental brick.
	var drone_only = {"hull_type": "light_hull", "modules": [{"type_id": "drone_carrier"}, {"type_id": "wheels"}]}
	if not ModuleCatalog.validate_build_legality(drone_only).valid:
		print("  [FAIL] A drone_carrier-only combat design should be valid")
		return false

	# --- Integration: the match-queue gate actually rejects, and never spends resources ---
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var metal_before = skirmish.economy[skirmish.PLAYER_TEAM].metal
	var illegal_entry = {
		"blueprint": {"hull_type": "medium_hull", "modules": []},
		"name": "Accidental Brick",
		"cost_metal": 50,
		"cost_crystal": 0,
	}
	skirmish._queue_player_unit(illegal_entry)
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before:
		print("  [FAIL] Queuing an illegal design should never spend resources")
		skirmish.queue_free()
		return false
	var factory = skirmish.get_team_factory(skirmish.PLAYER_TEAM)
	if factory and not factory.production_queue.is_empty():
		print("  [FAIL] An illegal design should never enter the production queue")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] validate_build_legality() correctly gates hull/weapon-or-support/locomotion-or-static, and the match-queue path rejects illegal designs without spending resources.")
	return true

func test_c2_placement_rejects_a_footprint_corner_overhang() -> bool:
	print("Running Test Suite: C2 - Placement Rejects a Footprint CORNER Overhang, Not Just Center-Point (RTS_CORE_ROADMAP.md C2)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# heavy_manufactory footprint is (7.5, 3.8, 10), half-extents (3.75, 5).
	# Center at (27, 95) is clear ground, well within the refinery's (27, 84)
	# own buildable-area reach (RTS_CORE_ROADMAP.md C3: 8.0m footprint-to-
	# footprint gap, not the old flat 28m-from-center rule) - a center-only
	# terrain check passes this regardless. The synthetic obstacle below
	# sits clear of the CENTER point but overlaps the footprint's own +x
	# edge - exactly the case a lattice walk over the whole footprint
	# catches and a single point-check can't.
	#
	# MapCatalog.get_map() hands back the SAME cached Dictionary to every
	# Skirmish instance for a given map_id (no copy) - mutating
	# current_map.obstacles here would otherwise permanently leak this
	# synthetic obstacle into every later test that loads lake_crossing.
	# Must pop it back off before returning, on every exit path.
	skirmish.current_map.obstacles.append({"center": Vector3(31.75, 0, 95), "half_extents": Vector2(2, 2), "type": "rock"})

	skirmish.placing = {"kind": "heavy_manufactory", "cost_metal": 320, "cost_crystal": 85}
	var metal_before = skirmish.economy[skirmish.PLAYER_TEAM].metal
	var center_pos = Vector3(27, 0, 95)
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	if TerrainBuilderScript.is_position_blocked(skirmish.current_map, center_pos):
		print("  [FAIL] Test setup bug: the building's own CENTER point should read as clear ground (only a corner should overlap the obstacle)")
		skirmish.current_map.obstacles.pop_back()
		skirmish.queue_free()
		return false

	skirmish._try_place_building(center_pos)
	var placement_rejected = skirmish.economy[skirmish.PLAYER_TEAM].metal == metal_before
	skirmish.current_map.obstacles.pop_back()
	if not placement_rejected:
		print("  [FAIL] A footprint corner overhanging an obstacle should reject placement before spending any resources (center point alone is clear, so a center-only check would have wrongly allowed this)")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Placement correctly rejects a footprint corner overhanging an obstacle, even though the footprint's own center point is clear.")
	return true

func test_c2_placement_rejects_building_on_resource_node() -> bool:
	print("Running Test Suite: C2 - Placement Rejects Building On Top Of A Resource Node (RTS_CORE_ROADMAP.md C2)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var node_pos: Vector3 = skirmish.current_map.resource_nodes[0].position
	skirmish.placing = {"kind": "refinery", "cost_metal": 150, "cost_crystal": 0}
	var metal_before = skirmish.economy[skirmish.PLAYER_TEAM].metal
	skirmish._try_place_building(node_pos)

	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before:
		print("  [FAIL] Placing a building directly on a resource node should be rejected before spending any resources")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Placement is rejected when it would sit directly on top of a resource node.")
	return true

func test_c2_placement_shoves_own_units_clear_instead_of_failing() -> bool:
	print("Running Test Suite: C2 - Placement Shoves Own Units Clear Instead Of Failing (RTS_CORE_ROADMAP.md C2, OpenRA's ClearBlockersOrders)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	# Clear ground within the refinery's (27, 84) own 8.0m buildable-area
	# reach (RTS_CORE_ROADMAP.md C3) - footprint-to-footprint, not center-
	# to-center, so this has to sit close now, not just "within 28".
	var build_pos = Vector3(27, 0, 93)
	var blocker = CharacterBody3D.new()
	blocker.set_script(BattleUnitScript)
	skirmish.add_child(blocker)
	blocker.team = skirmish.PLAYER_TEAM
	blocker.set_meta("team", skirmish.PLAYER_TEAM)
	blocker.add_to_group("units")
	blocker.add_to_group("damageable")
	blocker.global_position = build_pos # sitting exactly where the building is about to go

	# RTS_CORE_ROADMAP.md D4: _try_place_building() no longer spends -
	# cost is already fully paid by production.enqueue_structure()'s
	# drip-feed by the time a placement actually runs. Directly driving
	# _try_place_building() here (skipping the queue) is still the right
	# way to test the SHOVE mechanic in isolation; whether placement
	# succeeded is proven by the refinery actually existing below.
	skirmish.placing = {"kind": "refinery", "cost_metal": 150, "cost_crystal": 0}
	skirmish._try_place_building(build_pos)

	var refinery = null
	for b in skirmish.get_team_buildings(skirmish.PLAYER_TEAM):
		if b.kind == "refinery" and b.global_position.distance_to(build_pos) < 1.0:
			refinery = b
			break
	if not refinery:
		print("  [FAIL] The refinery should have actually spawned at the placement position")
		skirmish.queue_free()
		return false

	var half_x = refinery.footprint.x / 2.0
	var half_z = refinery.footprint.z / 2.0
	var dx = abs(blocker.global_position.x - refinery.global_position.x)
	var dz = abs(blocker.global_position.z - refinery.global_position.z)
	if dx < half_x and dz < half_z:
		print("  [FAIL] The blocking unit should have been shoved clear of the new building's footprint, still at ", blocker.global_position, " vs building at ", refinery.global_position)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A friendly unit standing where a building is placed gets shoved clear instead of blocking the placement.")
	return true

func test_c3_buildable_area_reach_is_per_kind_not_flat_28m() -> bool:
	print("Running Test Suite: C3 - Buildable-Area Reach Is Per-KIND (defense's 28m vs. a regular building's 8m default), Not a Flat 28m (RTS_CORE_ROADMAP.md C3)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	var refinery = null
	for b in skirmish.get_team_buildings(skirmish.PLAYER_TEAM):
		if b.kind == "refinery":
			refinery = b
			break
	if not refinery:
		print("  [FAIL] No starting player refinery found.")
		skirmish.queue_free()
		return false

	# A defense's own leash (BuildingScript.DEFENSE_ADJACENT_M, 28m) is what
	# lets IT be placed far from the base - it's a property of the thing
	# being placed, not a bigger zone radiated by existing buildings (a
	# defense doesn't even give_buildable_area, so nothing anchors off IT).
	skirmish.placing = {"kind": "defense", "blueprint": {"hull_type": "pillbox_foundation"}, "cost_metal": 0, "cost_crystal": 0}
	var defense_fp = skirmish._placing_footprint()
	var gap_20_z = refinery.global_position.z + 20.0 + refinery.footprint.z / 2.0 + defense_fp.z / 2.0
	var test_pos = Vector3(refinery.global_position.x, 0, gap_20_z)

	var defense_validity = skirmish._placement_validity(test_pos)
	if not defense_validity.valid:
		print("  [FAIL] A defense should be placeable ~20m (footprint gap) from the refinery - within its own 28m leash - got rejected: ", defense_validity.reason)
		skirmish.queue_free()
		return false

	# The SAME position, but for a regular building (default 8.0m reach) -
	# should now be rejected, proving the reach really is per-kind and not
	# secretly still a flat 28m for everything.
	skirmish.placing = {"kind": "power_plant", "cost_metal": 180, "cost_crystal": 40}
	var plant_validity = skirmish._placement_validity(test_pos)
	if plant_validity.valid:
		print("  [FAIL] A power_plant (default 8.0m reach) at the same ~20m gap from the refinery should be rejected as too far from base, but was accepted")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A defense can be placed ~20m from the base (within its own 28m leash) while a regular building at the same distance (default 8.0m reach) is correctly rejected.")
	return true

func test_c4_manufactory_rally_point_is_settable_via_right_click() -> bool:
	print("Running Test Suite: C4 - Manufactory Rally Point Is Settable (Select + Right-Click Ground) (RTS_CORE_ROADMAP.md C4)...")
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

	var old_rally = factory.rally_point
	var new_rally = factory.global_position + Vector3(25, 0, 0)
	skirmish._set_selection([factory])
	if skirmish._selected_manufactories().size() != 1:
		print("  [FAIL] A selected manufactory should show up in _selected_manufactories()")
		skirmish.queue_free()
		return false

	# Real production authority - queue a unit and confirm it actually walks
	# toward the NEW rally point, not the old default.
	factory.rally_point = new_rally # same effect _issue_order()'s ground-click branch has; skips the screen-space raycast a real click needs
	if factory.rally_point.distance_to(old_rally) < 1.0:
		print("  [FAIL] Test setup bug: new_rally should differ meaningfully from the old default")
		skirmish.queue_free()
		return false

	var units_before = skirmish.get_team_units(skirmish.PLAYER_TEAM).size()
	factory.queue_unit({}, 0.05)
	var new_unit = null
	for i in range(60):
		await tree.process_frame
		if skirmish.get_team_units(skirmish.PLAYER_TEAM).size() > units_before:
			for u in skirmish.get_team_units(skirmish.PLAYER_TEAM):
				if u.order == u.OrderType.MOVE and u.move_target.distance_to(new_rally) < 0.5:
					new_unit = u
					break
			break

	if not new_unit:
		print("  [FAIL] The newly-produced unit should be moving toward the manufactory's own (newly-set) rally_point, not the old default")
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A manufactory's rally_point is settable and a freshly-produced unit actually orders toward it.")
	return true

func test_d4_clicking_a_structure_queues_it_instead_of_placing_immediately() -> bool:
	print("Running Test Suite: D4 - Clicking A Structure Queues It (Real Build Time), Ghost Placement Only Begins Once Done (RTS_CORE_ROADMAP.md D4)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	skirmish._queue_structure_build({"kind": "power_plant", "cost_metal": 180, "cost_crystal": 40})
	var q = skirmish.production.get_queue(skirmish.PLAYER_TEAM, "structures")
	if q.size() != 1:
		print("  [FAIL] Clicking a Structures button should queue a real structures-tier job, got queue size ", q.size())
		skirmish.queue_free()
		return false
	if not skirmish.placing.is_empty():
		print("  [FAIL] Placement should NOT begin immediately on click - buildings never auto-exit, it has to actually finish building first")
		skirmish.queue_free()
		return false

	# Tick the job all the way through - RTS_CORE_ROADMAP.md D4's own
	# "buildings never auto-exit" means tick() deliberately does NOT pop a
	# done structures job on its own (unlike unit tiers) - it just sits at
	# time_left <= 0 until skirmish.gd's _physics_process() polls
	# pop_ready_structure() and starts real ghost placement.
	for i in range(2000):
		skirmish.production.tick(1.0 / 60.0)
		if not q.is_empty() and q[0].time_left <= 0.0:
			break
	if q.is_empty() or q[0].time_left > 0.0:
		print("  [FAIL] The structures job should have finished ticking down by now, queue=", q)
		skirmish.queue_free()
		return false

	skirmish._physics_process(1.0 / 60.0) # the same poll _physics_process() itself does every real tick
	if skirmish.placing.get("kind", "") != "power_plant":
		print("  [FAIL] Ghost placement should have started automatically for the completed power_plant build, placing=", skirmish.placing)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Clicking a structure queues a real drip-fed build; ghost placement only begins once production.pop_ready_structure() confirms it's actually done.")
	return true

func test_d4_abandoning_ghost_placement_refunds_but_successful_placement_does_not() -> bool:
	print("Running Test Suite: D4 - Abandoning A Structure's Ghost Placement Refunds The Fully-Paid Cost; A Successful Placement Does Not (RTS_CORE_ROADMAP.md D4 gap)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# --- Abandon path: Escape (or right-click) should refund the full cost ---
	skirmish._queue_structure_build({"kind": "power_plant", "cost_metal": 180, "cost_crystal": 40})
	var q = skirmish.production.get_queue(skirmish.PLAYER_TEAM, "structures")
	for i in range(2000):
		skirmish.production.tick(1.0 / 60.0)
		if not q.is_empty() and q[0].time_left <= 0.0:
			break
	skirmish._physics_process(1.0 / 60.0) # pops the ready job, starts ghost placement
	if skirmish.placing.get("kind", "") != "power_plant":
		print("  [FAIL] Test setup: ghost placement should have started for the completed power_plant build, placing=", skirmish.placing)
		skirmish.queue_free()
		return false

	var metal_before_abandon = skirmish.economy[skirmish.PLAYER_TEAM].metal
	var crystal_before_abandon = skirmish.economy[skirmish.PLAYER_TEAM].crystal
	skirmish._abandon_placement()
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before_abandon + 180:
		print("  [FAIL] Abandoning the ghost should refund the full 180 metal actually paid, got ", skirmish.economy[skirmish.PLAYER_TEAM].metal - metal_before_abandon)
		skirmish.queue_free()
		return false
	if skirmish.economy[skirmish.PLAYER_TEAM].crystal != crystal_before_abandon + 40:
		print("  [FAIL] Abandoning the ghost should refund the full 40 crystal actually paid, got ", skirmish.economy[skirmish.PLAYER_TEAM].crystal - crystal_before_abandon)
		skirmish.queue_free()
		return false
	if not skirmish.placing.is_empty():
		print("  [FAIL] placing should be cleared after abandoning.")
		skirmish.queue_free()
		return false

	# --- Success path: an actual placement must NOT also refund ---
	skirmish._queue_structure_build({"kind": "power_plant", "cost_metal": 180, "cost_crystal": 40})
	q = skirmish.production.get_queue(skirmish.PLAYER_TEAM, "structures")
	for i in range(2000):
		skirmish.production.tick(1.0 / 60.0)
		if not q.is_empty() and q[0].time_left <= 0.0:
			break
	skirmish._physics_process(1.0 / 60.0)
	if skirmish.placing.get("kind", "") != "power_plant":
		print("  [FAIL] Test setup: second ghost placement should have started, placing=", skirmish.placing)
		skirmish.queue_free()
		return false

	var metal_before_place = skirmish.economy[skirmish.PLAYER_TEAM].metal
	var crystal_before_place = skirmish.economy[skirmish.PLAYER_TEAM].crystal
	# Same offset the D4 build-incomplete test above already verified is a
	# clear, in-adjacency-range spot next to the starting light_manufactory.
	var place_pos = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light").global_position + Vector3(0, 0, 14)
	skirmish._try_place_building(place_pos)
	if not skirmish.placing.is_empty():
		print("  [FAIL] Test setup: placement should have succeeded (placing should be cleared), placing=", skirmish.placing)
		skirmish.queue_free()
		return false
	if skirmish.economy[skirmish.PLAYER_TEAM].metal != metal_before_place or skirmish.economy[skirmish.PLAYER_TEAM].crystal != crystal_before_place:
		print("  [FAIL] A SUCCESSFUL placement must not also refund the cost - metal ", metal_before_place, " -> ", skirmish.economy[skirmish.PLAYER_TEAM].metal, ", crystal ", crystal_before_place, " -> ", skirmish.economy[skirmish.PLAYER_TEAM].crystal)
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] Abandoning a structure's ghost placement refunds the full amount already drawn; a successful placement leaves the spend alone.")
	return true

func test_d4_freshly_placed_building_is_build_incomplete_until_its_grace_period_clears() -> bool:
	print("Running Test Suite: D4 - A Freshly-Placed Building Is build_incomplete (No Weapons/Production/Energy) Until Its Grace Period Clears (RTS_CORE_ROADMAP.md D4)...")
	await tree.process_frame
	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	await tree.process_frame
	await tree.process_frame

	# A second light_manufactory, placed the same way _try_place_building()
	# places anything live (not via _spawn_bases(), which never sets
	# build_incomplete - the starting base spawns complete).
	var first_light = skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light")
	var second_light = skirmish._spawn_prefab("light_manufactory", skirmish.PLAYER_TEAM, first_light.global_position + Vector3(0, 0, 14), skirmish.player_faction)
	second_light.start_construction_animation()

	if not second_light.build_incomplete:
		print("  [FAIL] A freshly-placed building should be build_incomplete immediately after start_construction_animation()")
		skirmish.queue_free()
		return false
	# Energy: an incomplete building's own energy_capacity/generators must
	# NOT count yet - light_manufactory carries no energy_capacity itself,
	# so just prove the gate exists via count_factories_of_tier(), which
	# every other tier-aware check (get_team_factory, D3's speed bonus)
	# shares the same underlying build_incomplete filter with.
	if skirmish.count_factories_of_tier(skirmish.PLAYER_TEAM, "light") != 1:
		print("  [FAIL] An incomplete second light manufactory should NOT count toward count_factories_of_tier() yet, got ", skirmish.count_factories_of_tier(skirmish.PLAYER_TEAM, "light"))
		skirmish.queue_free()
		return false
	if skirmish.get_team_factory(skirmish.PLAYER_TEAM, "light") != first_light:
		print("  [FAIL] get_team_factory() should still resolve to the ALREADY-complete first manufactory, not the incomplete second one")
		skirmish.queue_free()
		return false

	# Clear the flag directly (bypassing the real 2s tween - this test is
	# about the GATING logic, not the tween's own timing) and confirm it
	# now counts.
	second_light.build_incomplete = false
	if skirmish.count_factories_of_tier(skirmish.PLAYER_TEAM, "light") != 2:
		print("  [FAIL] Once build_incomplete clears, the second manufactory should count toward count_factories_of_tier(), got ", skirmish.count_factories_of_tier(skirmish.PLAYER_TEAM, "light"))
		skirmish.queue_free()
		return false

	skirmish.queue_free()
	await tree.process_frame
	print("  [PASS] A freshly-placed building is build_incomplete (excluded from factory-tier counts) until its grace period clears, then counts normally.")
	return true

func test_d4_build_incomplete_weapon_does_not_fire() -> bool:
	print("Running Test Suite: D4 - A build_incomplete Defense's Weapon Does Not Target Or Fire (RTS_CORE_ROADMAP.md D4)...")
	await tree.process_frame

	var building = StaticBody3D.new()
	building.set_script(preload("res://scripts/building.gd"))
	root.add_child(building)
	building.team = 0
	building.set_meta("team", 0) # auto_weapon.gd's get_team() reads the META, not the property directly
	building.build_incomplete = true

	var weapon = Node3D.new()
	weapon.set_script(preload("res://scripts/auto_weapon.gd"))
	building.add_child(weapon)
	var ModuleDataScript = preload("res://scripts/module_data.gd")
	var w_data = ModuleDataScript.new()
	w_data.type_id = "basic_cannon"
	w_data.base_weight = 80.0
	w_data.base_dps = 40.0
	weapon.set_meta("module_data", w_data)
	weapon._ready()

	# A plain hostile battle_unit (not target_dummy.gd, which expects a
	# real $MeshInstance3D child from its own .tscn - not present when
	# constructed bare like this) - same minimal-target pattern already
	# used by this suite's other weapon-targeting tests.
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var target = CharacterBody3D.new()
	target.set_script(BattleUnitScript)
	root.add_child(target)
	target.team = 1
	target.set_meta("team", 1)
	target.add_to_group("damageable")
	target.global_position = weapon.global_position + Vector3(3, 0, 0)
	await tree.process_frame

	weapon._physics_process(1.0 / 60.0) # exercises the real gate, which lives at the top of _physics_process()
	if weapon.target != null:
		print("  [FAIL] A build_incomplete defense's weapon should not acquire a target at all")
		building.queue_free()
		target.queue_free()
		return false

	building.build_incomplete = false
	weapon._find_nearest_target()
	if weapon.target == null:
		print("  [FAIL] Once build_incomplete clears, the SAME weapon should be able to acquire a target normally")
		building.queue_free()
		target.queue_free()
		return false

	building.queue_free()
	target.queue_free()
	await tree.process_frame
	print("  [PASS] A build_incomplete defense's weapon is fully inert (no targeting) and works normally again once the flag clears.")
	return true

