extends "res://tests/suite_base.gd"
# Phase 1 command layer: formations, flow fields, selection geometry.
#
# Same rule as test_battle_movement.gd - these assert PURE functions, because
# headless Godot cannot drive a real drag-select or a held mouse button. The
# behaviours that genuinely need a live match (a squad crossing real terrain
# without stacking) are covered by tools/probe_battle_phase1.gd instead.

const FormationScript = preload("res://scripts/battle/orders/formation_service.gd")
const FlowFieldScript = preload("res://scripts/battle/movement/flow_field.gd")
const FlowFieldServiceScript = preload("res://scripts/battle/movement/flow_field_service.gd")
const SelectionServiceScript = preload("res://scripts/battle/orders/selection_service.gd")
const SteeringScript = preload("res://scripts/battle/movement/steering.gd")
const StanceScript = preload("res://scripts/battle/orders/stance.gd")


# THE CORE GUARANTEE. A group order must give every unit its OWN destination.
# The old runtime handed the same Vector3 to all of them, so twenty units
# converged on one point, all landed inside each other's arrival radius, and
# shoved each other off it forever. Any duplicate slot reintroduces that.
func test_formation_gives_every_unit_a_distinct_slot() -> bool:
	print("Running Test Suite: Formation - distinct slots, sane shapes, no overshoot...")
	var destination := Vector3(40, 0, -25)

	for count in [1, 2, 3, 4, 5, 9, 12, 13, 30]:
		var positions: Array = []
		for i in range(count):
			# A loose blob well away from the destination, so the formation has a
			# real direction of travel to orient against.
			positions.append(Vector3(float(i % 5) * 3.0, 0.0, 60.0 + float(i / 5) * 3.0))
		var slots: Array = FormationScript.destinations_for(positions, destination)

		if slots.size() != count:
			print("  [FAIL] %d units produced %d slots" % [count, slots.size()])
			return false
		for i in range(count):
			for j in range(i + 1, count):
				if slots[i].distance_to(slots[j]) < 0.5:
					print("  [FAIL] %d-unit formation gave units %d and %d the same slot" % [count, i, j])
					return false

	# A LONE unit goes exactly where it was clicked. Offsetting it would make the
	# game look like it ignored the order.
	var single: Array = FormationScript.destinations_for([Vector3(0, 0, 50)], destination)
	if single[0].distance_to(destination) > 0.001:
		print("  [FAIL] A single unit should go exactly to the clicked point, got ", single[0])
		return false

	# NO OVERSHOOT. The front rank sits ON the destination and the rest trail
	# back toward where the group came from. Building the formation forward of
	# the click would march the leaders past the point the player chose.
	var approach: Array = []
	for i in range(9):
		approach.append(Vector3(float(i) * 2.0, 0.0, 80.0))
	var ranked: Array = FormationScript.destinations_for(approach, destination)
	var closest := 1.0e9
	for s in ranked:
		closest = minf(closest, Vector3(s.x - destination.x, 0.0, s.z - destination.z).length())
		# Nothing should end up further from the group than the destination is.
		if s.z < destination.z - 1.0:
			print("  [FAIL] A slot overshot past the destination: ", s)
			return false
	if closest > 1.0:
		print("  [FAIL] No slot lands on the destination itself (closest %.2f m)" % closest)
		return false
	print("  [PASS] Formation slotting")
	return true


# Slots are paired to units without crossings. The naive greedy pass - each unit
# takes its nearest free slot - produces crossed paths whenever two units are
# each closer to the other's slot, and crossing paths inside a group move is
# exactly the shoving formations exist to prevent.
func test_formation_assignment_does_not_cross() -> bool:
	print("Running Test Suite: Formation - assignment preserves left/right order...")
	# Four units abreast, travelling along -Z. Their left-to-right order is by X.
	var positions := [
		Vector3(-9, 0, 40), Vector3(-3, 0, 40), Vector3(3, 0, 40), Vector3(9, 0, 40),
	]
	var destination := Vector3(0, 0, -40)
	var slots: Array = FormationScript.destinations_for(positions, destination)

	# Travelling along -Z, "right" is -X, so a unit further left (smaller X)
	# must not be given a slot to the right of a unit that started to its right.
	for i in range(positions.size() - 1):
		if slots[i].x > slots[i + 1].x:
			print("  [FAIL] Units %d and %d swapped sides: %s then %s"
				% [i, i + 1, slots[i], slots[i + 1]])
			return false

	# And the pairing must be a permutation - no slot used twice, none skipped.
	var seen: Array = []
	for s in slots:
		for t in seen:
			if s.distance_to(t) < 0.001:
				print("  [FAIL] A slot was assigned twice: ", s)
				return false
		seen.append(s)
	print("  [PASS] Formation assignment")
	return true


func test_flow_field_integrates_and_points_home() -> bool:
	print("Running Test Suite: FlowField - Dijkstra integration and descent...")
	# An invalid RID means "no navmesh", which the field treats as all-passable.
	# That is the branch worth testing directly: it isolates the integration and
	# descent maths from Recast, which is the flakiest thing in this codebase.
	var half := 60.0
	var destination := Vector3(20, 0, -20)
	var field: FlowField = FlowFieldScript.build(RID(), half, destination)

	if field.dims.x <= 0 or field.dims.x != field.dims.y:
		print("  [FAIL] Field dimensions look wrong: ", field.dims)
		return false

	# Cell/world round trip: the centre of the cell containing a point must be
	# within half a diagonal of that point.
	var probe := Vector3(-13.0, 0.0, 41.0)
	var centre: Vector3 = field.centre_of(field.cell_at(probe))
	if Vector2(centre.x - probe.x, centre.z - probe.z).length() > FlowFieldScript.BASE_CELL_SIZE:
		print("  [FAIL] cell_at/centre_of round trip drifted: ", probe, " -> ", centre)
		return false

	# Everywhere on an open field is reachable, and following the flow must
	# strictly reduce the distance to the destination. That is the property that
	# makes the field usable at all: descend it and you arrive.
	var starts := [Vector3(-50, 0, 50), Vector3(50, 0, 50), Vector3(-50, 0, -50), Vector3(0, 0, 0)]
	for start in starts:
		if not field.has_route(start):
			print("  [FAIL] No route from ", start)
			return false
		var dir: Vector3 = field.direction_at(start)
		if dir == Vector3.ZERO:
			print("  [FAIL] No flow direction at ", start)
			return false
		var start_pos: Vector3 = start
		var toward := destination - start_pos
		toward.y = 0.0
		if dir.normalized().dot(toward.normalized()) < 0.5:
			print("  [FAIL] Flow at %s points at %s, away from the destination" % [start, dir])
			return false

	# Walking the field must actually terminate at the destination rather than
	# looping - the failure mode a badly derived descent produces.
	var walker := Vector3(-50, 0, 50)
	var steps := 0
	while walker.distance_to(destination) > FlowFieldScript.BASE_CELL_SIZE * 1.5 and steps < 500:
		var d: Vector3 = field.direction_at(walker)
		if d == Vector3.ZERO:
			break
		walker += d * FlowFieldScript.BASE_CELL_SIZE
		steps += 1
	if walker.distance_to(destination) > FlowFieldScript.BASE_CELL_SIZE * 2.0:
		print("  [FAIL] Descending the field stalled %.1f m from the destination after %d steps"
			% [walker.distance_to(destination), steps])
		return false

	# The gate: a field is one search shared by many units, so below a handful of
	# units it is strictly more expensive than letting each one path for itself.
	if FlowFieldServiceScript.should_use_field(2):
		print("  [FAIL] A 2-unit group should not build a flow field")
		return false
	if not FlowFieldServiceScript.should_use_field(FlowFieldServiceScript.FIELD_MIN_UNITS):
		print("  [FAIL] A group at the threshold should build a flow field")
		return false
	print("  [PASS] FlowField integration")
	return true


func test_flow_field_cell_size_scales_with_world_scale() -> bool:
	print("Running Test Suite: FlowField - cell_size Scales With world_scale, Keeping Cell Count Bounded...")
	# CORE_DESIGN_LANGUAGE.md §3.2: without this, a map that grows 16x under
	# world_scale would grow a field's cell COUNT 256x (dims scale with
	# half^2) - the "19M cells per field" the plan's own cost table warns
	# about. Scaling cell_size alongside map_half_extents keeps dims roughly
	# constant regardless of world_scale.
	var half := 60.0
	var destination := Vector3(20, 0, -20)

	var field_default: FlowField = FlowFieldScript.build(RID(), half, destination)
	if not is_equal_approx(field_default.cell_size, FlowFieldScript.BASE_CELL_SIZE):
		print("  [FAIL] Default (no world_scale arg) should keep BASE_CELL_SIZE, got ", field_default.cell_size)
		return false

	var field_explicit_1: FlowField = FlowFieldScript.build(RID(), half, destination, 1.0)
	if not is_equal_approx(field_explicit_1.cell_size, FlowFieldScript.BASE_CELL_SIZE):
		print("  [FAIL] world_scale=1.0 should be identical to the default, got ", field_explicit_1.cell_size)
		return false
	if field_explicit_1.dims != field_default.dims:
		print("  [FAIL] world_scale=1.0 should produce identical dims to the default, got ", field_explicit_1.dims, " vs ", field_default.dims)
		return false

	# At world_scale=4.0, BOTH map_half_extents (Chunk 12, not exercised
	# directly here) and cell_size grow by the same factor - so dims (which
	# depend on the RATIO of the two) should come out roughly the same as
	# the unscaled field's, not 4x or 16x larger.
	var scaled_half := half * 4.0
	var field_scaled: FlowField = FlowFieldScript.build(RID(), scaled_half, destination, 4.0)
	if not is_equal_approx(field_scaled.cell_size, FlowFieldScript.BASE_CELL_SIZE * 4.0):
		print("  [FAIL] world_scale=4.0 should quadruple cell_size, expected ", FlowFieldScript.BASE_CELL_SIZE * 4.0, ", got ", field_scaled.cell_size)
		return false
	if field_scaled.dims != field_default.dims:
		print("  [FAIL] Scaling both map_half_extents and world_scale by the same factor should hold dims roughly constant, expected ", field_default.dims, ", got ", field_scaled.dims)
		return false

	print("  [PASS] FlowField.cell_size is inert at world_scale=1.0 and scales proportionally at 4.0, keeping cell count bounded as the map grows.")
	return true


# The frustum is the piece of selection most likely to be subtly wrong and the
# piece that never needs a scene to check. The old runtime had no frustum at all
# - it projected each unit's origin to the screen and tested a Rect2, which
# selects units behind the camera and misses units whose origin is a pixel
# outside a box they mostly fill.
func test_selection_frustum_geometry() -> bool:
	print("Running Test Suite: SelectionService - drag frustum geometry...")
	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 500.0
	root.add_child(camera)
	camera.global_position = Vector3(0, 40, 40)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await tree.process_frame

	var rect := Rect2(Vector2(200, 150), Vector2(400, 300))
	var points := SelectionServiceScript.frustum_points(camera, rect)

	if points.size() != 8:
		print("  [FAIL] Expected 8 frustum corners, got ", points.size())
		camera.queue_free()
		return false

	# Alternating near/far per corner, by construction. Every near point must be
	# nearer the camera than every far point - an inverted or collapsed frustum
	# is the failure that would silently select nothing.
	var origin := camera.global_position
	var near_max := 0.0
	var far_min := 1.0e9
	for i in range(8):
		var d: float = origin.distance_to(points[i])
		if i % 2 == 0:
			near_max = maxf(near_max, d)
		else:
			far_min = minf(far_min, d)
	if near_max >= far_min:
		print("  [FAIL] Near plane (max %.2f) is not in front of the far plane (min %.2f)"
			% [near_max, far_min])
		camera.queue_free()
		return false

	# A frustum DIVERGES: the far quad must be wider than the near quad. Equal
	# widths would mean an orthographic box, which for a perspective camera means
	# the projection was not applied.
	var near_width := points[0].distance_to(points[2])
	var far_width := points[1].distance_to(points[3])
	if far_width <= near_width:
		print("  [FAIL] Far quad (%.2f) is not wider than the near quad (%.2f)" % [far_width, near_width])
		camera.queue_free()
		return false

	# A bigger drag box must sweep a bigger volume - the sanity check that the
	# rect is actually being read.
	var wide := SelectionServiceScript.frustum_points(camera, Rect2(Vector2(100, 100), Vector2(700, 500)))
	if wide[1].distance_to(wide[3]) <= far_width:
		print("  [FAIL] A larger drag rect did not produce a larger frustum")
		camera.queue_free()
		return false

	camera.queue_free()
	print("  [PASS] Selection frustum")
	return true


func test_separation_and_stance_policy() -> bool:
	print("Running Test Suite: Steering separation + stance policy...")

	# Separation pushes AWAY from a crowding neighbour, and not at all from one
	# outside the radius.
	var push: Vector3 = SteeringScript.separation(Vector3.ZERO, [Vector3(2, 0, 0)], 5.0)
	if push.x >= 0.0:
		print("  [FAIL] A neighbour to the right should push left, got ", push)
		return false
	if SteeringScript.separation(Vector3.ZERO, [Vector3(50, 0, 0)], 5.0) != Vector3.ZERO:
		print("  [FAIL] A distant neighbour should not push at all")
		return false

	# Closer must push harder, or a unit in contact is treated the same as one
	# barely in range and overlap never resolves.
	var near_push: float = SteeringScript.separation(Vector3.ZERO, [Vector3(1, 0, 0)], 5.0).length()
	var far_push: float = SteeringScript.separation(Vector3.ZERO, [Vector3(4, 0, 0)], 5.0).length()
	if near_push <= far_push:
		print("  [FAIL] Separation should fall off with distance (near %.3f, far %.3f)" % [near_push, far_push])
		return false

	# Exactly coincident units must not produce NaN, and must not pick a random
	# direction - two stacked units would vibrate forever instead of separating.
	var coincident: Vector3 = SteeringScript.separation(Vector3.ZERO, [Vector3.ZERO], 5.0)
	if is_nan(coincident.x) or is_nan(coincident.z):
		print("  [FAIL] Coincident units produced NaN")
		return false
	if coincident != SteeringScript.separation(Vector3.ZERO, [Vector3.ZERO], 5.0):
		print("  [FAIL] Coincident separation is not deterministic")
		return false

	# Stance is a POLICY, and the policy has to differ or the stances are
	# decoration. HOLD_POSITION in particular must never pursue.
	if StanceScript.pursuit_range_multiplier(StanceScript.Kind.HOLD_POSITION) != 0.0:
		print("  [FAIL] HOLD_POSITION must not pursue at all")
		return false
	if StanceScript.pursuit_range_multiplier(StanceScript.Kind.AGGRESSIVE) \
			<= StanceScript.pursuit_range_multiplier(StanceScript.Kind.RETURN_FIRE):
		print("  [FAIL] AGGRESSIVE should pursue further than RETURN_FIRE")
		return false
	if StanceScript.seeks_targets(StanceScript.Kind.RETURN_FIRE):
		print("  [FAIL] RETURN_FIRE should not go looking for targets")
		return false
	if not StanceScript.seeks_targets(StanceScript.Kind.AGGRESSIVE):
		print("  [FAIL] AGGRESSIVE should go looking for targets")
		return false
	# The default matters: the old runtime's one hardcoded policy was effectively
	# AGGRESSIVE, and every bug report about it was "my units wandered off".
	if StanceScript.DEFAULT != StanceScript.Kind.RETURN_FIRE:
		print("  [FAIL] The default stance should be RETURN_FIRE")
		return false
	print("  [PASS] Separation and stance policy")
	return true
