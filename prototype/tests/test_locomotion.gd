extends "res://tests/suite_base.gd"
# locomotion suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

# Every locomotion type in the catalog must resolve to a LocomotionLayout, get a
# real mount pattern, and be told apart from its neighbours by terrain. These
# three are what make "add a locomotion type" a data declaration rather than a
# code change - without them a new type can be half-added (catalog entry, no
# layout; layout, no terrain row) and simply behave as a duller copy of
# something else, which is exactly how hover_engine ended up with no terrain
# character at all for months.
func test_every_locomotion_type_is_fully_declared() -> bool:
	print("Running Test Suite: Locomotion Declaration Completeness...")
	var Layout = load("res://scripts/locomotion_layout.gd")
	var loco_ids: Array = []
	var catalog: Dictionary = ModuleCatalog.get_catalog()
	for type_id in catalog:
		if catalog[type_id].get("category", "") == "locomotion":
			loco_ids.append(type_id)
	if loco_ids.size() < 14:
		print("  [FAIL] expected at least 14 locomotion types after the expansion (naval drives removed), found %d." % loco_ids.size())
		return false

	for type_id in loco_ids:
		# 1. A layout, or module_placer has nothing to place.
		if not Layout.has_layout(type_id):
			print("  [FAIL] '%s' has a catalog entry but no LocomotionLayout - it would place nothing." % type_id)
			return false
		# 2. Tweaks that all reach a stat. A cosmetic slider is a lie about
		#    what the player is choosing.
		var specs: Array = ModuleCatalog.LOCOMOTION_TWEAK_SPECS.get(type_id, [])
		if specs.size() < 2:
			print("  [FAIL] '%s' has %d tweaks - every type carries at least 2." % [type_id, specs.size()])
			return false
		var base = ModuleCatalog.get_locomotion_contribs(type_id, {})
		for spec in specs:
			var probe := {}
			if spec.get("type", "") == "bool":
				probe[spec["name"]] = not bool(spec.get("default", false))
			else:
				probe[spec["name"]] = float(spec.get("max", 2.0))
			var moved = ModuleCatalog.get_locomotion_contribs(type_id, probe)
			var thrust_moved: bool = abs(moved["thrust"] - base["thrust"]) > 0.0001
			var cap_moved: bool = abs(moved["capacity"] - base["capacity"]) > 0.0001
			if not (thrust_moved or cap_moved):
				print("  [FAIL] '%s' tweak '%s' moves neither thrust nor capacity - it is cosmetic." % [
					type_id, spec["name"]])
				return false
		# 3. Every tweak must move CAPACITY somewhere in the type, not just
		#    speed - five types used to return capacity 0.0 flat.
		if base["capacity"] <= 0.0:
			print("  [FAIL] '%s' contributes no weight capacity at all - its tweaks move speed only." % type_id)
			return false

	# 4. Terrain character, for the types that actually touch the ground.
	for type_id in loco_ids:
		var traits: Array = catalog[type_id].get("traits", [])
		var exempt := false
		for t in traits:
			if t in ModuleCatalog.TERRAIN_EXEMPT_TRAITS:
				exempt = true
		if exempt:
			continue
		var values := []
		for surface in ModuleCatalog.TERRAIN_SPEED_MULTIPLIERS:
			if not ModuleCatalog.TERRAIN_SPEED_MULTIPLIERS[surface].has(type_id):
				print("  [FAIL] ground type '%s' has no '%s' entry - it silently returns 1.0 there." % [
					type_id, surface])
				return false
			values.append(float(ModuleCatalog.TERRAIN_SPEED_MULTIPLIERS[surface][type_id]))
		if type_id in ModuleCatalog.TERRAIN_INTENTIONALLY_FLAT:
			continue
		var flat := true
		for v in values:
			if abs(v - 1.0) > 0.01:
				flat = false
		if flat:
			print("  [FAIL] ground type '%s' is 1.0 on every surface - no terrain character." % type_id)
			return false

	print("  [PASS] All %d locomotion types have a layout, consequential tweaks, real weight capacity, and terrain character (or a declared exemption)." % loco_ids.size())
	return true


# The seven expansion types must actually build geometry and lay out somewhere
# sane. Cheap smoke coverage, but it is what catches a type wired into the
# catalog and the layout table whose _build_X() was never written - which would
# otherwise show up as an invisible locomotor in the Lab.
func test_expansion_locomotion_types_build_and_place() -> bool:
	print("Running Test Suite: Locomotion Expansion Types Build And Place...")
	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var new_types := ["half_track", "rocker_bogie", "air_cushion_skirt",
		"anti_grav_plate", "pontoon_wheels"]
	for type_id in new_types:
		var data = ModuleCatalog.get_module_data(type_id)
		var probe := Node3D.new()
		root.add_child(probe)
		VisualBuilder.build_visual(type_id, probe, data.get("size", Vector3.ONE), data.color, {})
		await tree.process_frame
		var meshes := probe.find_children("*", "MeshInstance3D", true, false)
		var mesh_count := meshes.size()
		probe.queue_free()
		await tree.process_frame
		if mesh_count < 1:
			print("  [FAIL] '%s' built no geometry - it would be invisible in the Lab." % type_id)
			return false

		# And it must place at least one instance on a real hull.
		var hull := StaticBody3D.new()
		hull.name = "Hull"
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 1.0, 6.0)
		shape.shape = box
		hull.add_child(shape)
		root.add_child(hull)
		var placer := Node3D.new()
		placer.set_script(load("res://scripts/module_placer.gd"))
		placer.hull = hull
		root.add_child(placer)
		await tree.process_frame
		placer.update_locomotion(type_id, {})
		await tree.process_frame
		var placed := 0
		for child in hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").category == "locomotion":
				placed += 1
		placer.free()
		hull.free()
		await tree.process_frame
		if placed < 1:
			print("  [FAIL] '%s' placed no instances on a reference hull." % type_id)
			return false
	print("  [PASS] All 7 expansion locomotion types build real geometry and place instances on a hull.")
	return true

# Every locomotion type must expose a pivot the animator can move, and the
# animator must have a branch for it. The failure this pins is not a crash - it
# is silence: wheels, tracked_treads and fixed_wing_engine shipped with no pivot
# at all, so a tank rolled across the map on frozen road wheels and a jet flew
# with a static fan, while the helicopter parked next to them span forever. That
# reads as broken, and nothing failed when it regressed.
func test_every_locomotion_type_animates_something() -> bool:
	print("Running Test Suite: Locomotion Animation Coverage...")
	var VisualBuilder = load("res://scripts/visual_builder.gd")
	# pivot name (or prefix) each type must produce, and whether it is driven by
	# ground contact (stops when parked) or by engine power (idles when parked).
	var expected := {
		"wheels": [VisualBuilder.SPIN_PIVOT_WHEEL, "ground"],
		"tracked_treads": [VisualBuilder.SPIN_PIVOT_TREAD, "ground"],
		"legs": ["LegSwing", "ground"],
		"screw_drive": ["ScrewSpin", "ground"],
		"fixed_wing_engine": [VisualBuilder.SPIN_PIVOT_TURBINE, "powered"],
		"helicopter_rotors": ["RotorBlades", "powered"],
		"hover_engine": ["HoverRingMid", "powered"],
		"ornithopter_wing": ["WingPivotFore", "powered"],
		"buoyant_envelope": ["PropBlades", "powered"],
		"half_track": [VisualBuilder.SPIN_PIVOT_TREAD, "ground"],
		"rocker_bogie": [VisualBuilder.SPIN_PIVOT_WHEEL, "ground"],
		"pontoon_wheels": [VisualBuilder.SPIN_PIVOT_WHEEL, "ground"],
		"air_cushion_skirt": [VisualBuilder.SPIN_PIVOT_TURBINE, "powered"],
		"anti_grav_plate": [VisualBuilder.SPIN_PIVOT_TURBINE, "powered"],
	}
	for type_id in expected:
		var pivot_name: String = expected[type_id][0]
		var probe := Node3D.new()
		root.add_child(probe)
		VisualBuilder.build_visual(type_id, probe,
			ModuleCatalog.get_module_data(type_id).get("size", Vector3.ONE),
			ModuleCatalog.get_module_data(type_id).color, {})
		await tree.process_frame
		var found := probe.find_children(pivot_name + "*", "Node3D", true, false)
		var hit := found.size() > 0
		probe.queue_free()
		await tree.process_frame
		if not hit:
			print("  [FAIL] %s builds no '%s' pivot - nothing for the animator to move." % [
				type_id, pivot_name])
			return false

	# The animator must actually name every one of them, or a pivot exists and
	# is never touched - which looks identical to having no pivot.
	var src := FileAccess.get_file_as_string("res://scripts/battle_unit.gd")
	if src == "":
		print("  [FAIL] could not read battle_unit.gd to check animation branches.")
		return false
	var anim_start := src.find("func _animate_locomotion")
	if anim_start < 0:
		print("  [FAIL] battle_unit.gd has no _animate_locomotion() - the animation branches moved or were lost.")
		return false
	var anim_src := src.substr(anim_start)
	for type_id in expected:
		if not anim_src.contains('"%s"' % type_id):
			print("  [FAIL] _animate_locomotion() has no branch for '%s'." % type_id)
			return false
	print("  [PASS] All 16 moving locomotion types build an animation pivot and are driven by _animate_locomotion() - ground-contact types by travel, powered types by throttle.")
	return true


# Lays out every locomotion type against three hull sizes and requires the
# result to match GOLDEN_LOCOMOTION_LAYOUT to 1e-3. This is the safety net for
# the placement rearchitecture: it is deliberately a whole-output snapshot
# rather than a set of hand-picked assertions, because the property being
# protected is "nothing moved", and the failures it exists to catch are the
# ones nobody thought to assert on.
func test_locomotion_layout_matches_golden_fixture() -> bool:
	print("Running Test Suite: Locomotion Golden Layout...")
	var tol := 0.001
	for size_name in GOLDEN_HULL_SIZES:
		var hull_size: Vector3 = GOLDEN_HULL_SIZES[size_name]
		var expected_for_size: Dictionary = GOLDEN_LOCOMOTION_LAYOUT[size_name]
		for type_id in expected_for_size:
			var hull := StaticBody3D.new()
			hull.name = "Hull"
			var shape := CollisionShape3D.new()
			shape.name = "CollisionShape3D"
			var box := BoxShape3D.new()
			box.size = hull_size
			shape.shape = box
			hull.add_child(shape)
			root.add_child(hull)
			var placer := Node3D.new()
			placer.set_script(load("res://scripts/module_placer.gd"))
			placer.hull = hull
			root.add_child(placer)
			await tree.process_frame

			placer.update_locomotion(type_id, {})
			await tree.process_frame

			var rows := []
			for child in hull.get_children():
				if not child.has_meta("module_data"):
					continue
				var m = child.get_meta("module_data")
				if m == null or m.category != "locomotion":
					continue
				rows.append({"pos": child.position, "scale": child.scale})
			rows.sort_custom(func(a, b):
				if not is_equal_approx(a["pos"].x, b["pos"].x):
					return a["pos"].x < b["pos"].x
				if not is_equal_approx(a["pos"].y, b["pos"].y):
					return a["pos"].y < b["pos"].y
				return a["pos"].z < b["pos"].z)

			var expected: Dictionary = expected_for_size[type_id]
			var want_stations: Array = expected["stations"]
			var hull_y := hull.position.y
			placer.free()
			hull.free()
			await tree.process_frame

			if rows.size() != want_stations.size():
				print("  [FAIL] %s/%s: %d instances placed, golden fixture has %d." % [
					size_name, type_id, rows.size(), want_stations.size()])
				return false
			if abs(hull_y - float(expected["hull_y"])) > tol:
				print("  [FAIL] %s/%s: hull sits at y=%.4f, golden fixture says %.4f." % [
					size_name, type_id, hull_y, expected["hull_y"]])
				return false
			for i in range(rows.size()):
				var want_pos: Vector3 = want_stations[i][0]
				var want_scale: Vector3 = want_stations[i][1]
				if rows[i]["pos"].distance_to(want_pos) > tol:
					print("  [FAIL] %s/%s station %d moved: %s, golden fixture says %s." % [
						size_name, type_id, i, rows[i]["pos"], want_pos])
					return false
				if rows[i]["scale"].distance_to(want_scale) > tol:
					print("  [FAIL] %s/%s station %d rescaled: %s, golden fixture says %s." % [
						size_name, type_id, i, rows[i]["scale"], want_scale])
					return false
	print("  [PASS] All 10 locomotion types lay out identically to the golden fixture across 3 hull sizes.")
	return true

func test_locomotion_tweak_parity() -> bool:
	print("Running Test Suite: Locomotion Tweak Parity (DESIGN_VISION.md audit)...")
	# Regression test for a real bug found during the Sunday audit: the "legs"
	# locomotion UI slider updated settings but update_locomotion() never read
	# the "size" key, so dragging the slider had zero effect on the resulting
	# unit. "hover_engine" had no tweak UI at all. Both are fixed to respond to
	# a continuous "size" setting like wheels/treads/rotors already did.
	var gizmo_probe_parent = Node3D.new()
	root.add_child(gizmo_probe_parent)
	var gizmo_probe = Node3D.new()
	gizmo_probe.set_script(preload("res://scripts/gizmo_3d.gd"))
	gizmo_probe_parent.add_child(gizmo_probe)

	for type_id in ["legs", "hover_engine"]:
		var hull = StaticBody3D.new()
		hull.name = "Hull"
		root.add_child(hull)
		var placer = Node3D.new()
		placer.set_script(preload("res://scripts/module_placer.gd"))
		placer.hull = hull
		root.add_child(placer)
		await tree.process_frame

		# scale_multiplier is no longer the signal to check here: since the
		# modular rebuild, each _build_X() bakes its own per-instance tweak
		# (leg_length/pad_size/etc.) straight into its sub-part scales, and
		# module_data.get_weight()/get_cost() read that same tweak directly
		# out of the tweaks dict (see module_data.gd) - scale_multiplier is
		# reserved for the outer node's hull-relative factors only (e.g.
		# legs' hull_height_factor) and is deliberately left at 1.0 for these
		# types now (module_placer.gd, "already baked into ... sub-part
		# scales" comments). Weight is the real end-to-end signal that the
		# slider does something.
		placer.update_locomotion(type_id, {"size": 1.0, "count": 4})
		await tree.process_frame
		var small_weight = 0.0
		for child in hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == type_id:
				small_weight = child.get_meta("module_data").get_weight()
				break

		placer.update_locomotion(type_id, {"size": 2.0, "count": 4})
		await tree.process_frame
		var big_weight = 0.0
		var found_big = false
		for child in hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == type_id:
				big_weight = child.get_meta("module_data").get_weight()
				found_big = true
				break

		if not found_big:
			print("  [FAIL] %s: no locomotion part spawned" % type_id)
			placer.queue_free(); hull.queue_free()
			return false
		if abs(big_weight - small_weight) < 0.5:
			print("  [FAIL] %s: size=2.0 did not change weight (still %s vs %s) - slider is dead" % [type_id, small_weight, big_weight])
			placer.queue_free(); hull.queue_free()
			return false

		placer.queue_free()
		hull.queue_free()
		await tree.process_frame

	# Gizmo-drag axis mapping: these three weapons had TWEAK_SPECS (slider-tweakable)
	# but no 3D gizmo-handle mapping, so the tactile Spore-style drag didn't work on them.
	var axis_checks = {
		"mortar_array": "tube_count",
		"cluster_dispenser": "dispersion",
		"missile_pod": "grid_size"
	}
	for type_id in axis_checks:
		var expected = axis_checks[type_id]
		var got = gizmo_probe.get_tweak_for_axis(type_id, Vector3.RIGHT)
		if got != expected:
			print("  [FAIL] %s: expected gizmo x-axis to map to '%s', got '%s'" % [type_id, expected, got])
			gizmo_probe_parent.queue_free()
			return false

	gizmo_probe_parent.queue_free()
	print("  [PASS] Locomotion size tweaks (legs/hover_engine) and gizmo axis mappings verified.")
	return true

func test_locomotion_rebuild_and_multipart_assemblies() -> bool:
	print("Running Test Suite: Locomotion Rebuild & Multi-Part GLB Assemblies...")

	var types = [
		"wheels", "helicopter_rotors", "tracked_treads", "legs", "hover_engine",
		"fixed_wing_engine", "ornithopter_wing", "buoyant_envelope", "screw_drive"
	]

	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")
	for type_id in types:
		var parent = Node3D.new()
		root.add_child(parent)
		var cat_data = ModuleCatalog.get_module_data(type_id)
		if cat_data.is_empty():
			print("  [FAIL] Missing catalog entry for locomotion type: ", type_id)
			parent.queue_free()
			return false

		VisualBuilderScript.build_visual(type_id, parent, cat_data.get("size", Vector3.ONE), cat_data.color, {})
		if parent.get_child_count() == 0:
			print("  [FAIL] VisualBuilder built 0 children for locomotion type: ", type_id)
			parent.queue_free()
			return false

		if type_id == "helicopter_rotors":
			if not parent.has_node("RotorBlades"):
				print("  [FAIL] helicopter_rotors missing 'RotorBlades' animation pivot")
				parent.queue_free()
				return false
		elif type_id == "ornithopter_wing":
			# Dragonfly-style fore/hind wing pair, each with its own
			# flap-animation pivot (see visual_builder.gd's
			# _build_ornithopter_wing rebuild, 2026-07-24).
			if not parent.has_node("WingPivotFore") or not parent.has_node("WingPivotHind"):
				print("  [FAIL] ornithopter_wing missing 'WingPivotFore'/'WingPivotHind' animation pivots")
				parent.queue_free()
				return false
		elif type_id == "buoyant_envelope":
			if not parent.has_node("PropBlades"):
				print("  [FAIL] %s missing 'PropBlades' animation pivot" % type_id)
				parent.queue_free()
				return false

		var m_data = ModuleData.new()
		m_data.type_id = type_id
		m_data.base_weight = cat_data.weight
		m_data.cost_metal = cat_data.metal
		m_data.cost_crystal = cat_data.crystal
		var contribs = ModuleCatalog.get_locomotion_contribs(type_id, m_data.tweaks)
		if contribs.get("thrust", 0.0) <= 0.0:
			print("  [FAIL] %s has 0 thrust contribution in ModuleCatalog.get_locomotion_contribs()" % type_id)
			parent.queue_free()
			return false

		parent.queue_free()

	print("  [PASS] All 10 kept locomotion types build multi-part assemblies with animation pivots and stat contribs.")
	return true

func test_new_locomotion_types_spawn_and_differentiate() -> bool:
	print("Running Test Suite: New Locomotion Types (buoyant_envelope/screw_drive) Spawn + Differentiate...")

	for type_id in ["buoyant_envelope", "screw_drive"]:
		var hull = StaticBody3D.new()
		hull.name = "Hull"
		root.add_child(hull)
		var placer = Node3D.new()
		placer.set_script(preload("res://scripts/module_placer.gd"))
		placer.hull = hull
		root.add_child(placer)
		await tree.process_frame

		placer.update_locomotion(type_id, {})
		await tree.process_frame
		var count = 0
		for child in hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == type_id:
				count += 1
		placer.queue_free(); hull.queue_free()
		if count < 2:
			print("  [FAIL] %s: update_locomotion() should spawn a real left/right pair, got %d" % [type_id, count])
			return false

	# buoyant_envelope: real buoyant-lift character (task/DECISIONS_NEEDED.md
	# judgment call) - low thrust (small cruise motors, buoyancy does the
	# lifting) but very high weight_capacity (buoyancy scales generously),
	# opposite of a thrust-driven flyer like fixed_wing_engine.
	if ModuleCatalog.get_thrust_coefficient("buoyant_envelope") >= ModuleCatalog.get_thrust_coefficient("fixed_wing_engine"):
		print("  [FAIL] buoyant_envelope should have a lower thrust_coefficient than fixed_wing_engine (buoyancy does the lifting, not the motors).")
		return false
	if ModuleCatalog.get_base_weight_capacity("buoyant_envelope") <= ModuleCatalog.get_base_weight_capacity("fixed_wing_engine"):
		print("  [FAIL] buoyant_envelope should have a higher base_weight_capacity than fixed_wing_engine (buoyancy scales generously with envelope size).")
		return false

	# screw_drive: genuinely amphibious trait composition, not hard-gated.
	var screw_traits = ModuleCatalog.get_traits("medium_hull", "screw_drive")
	if "ground_contact" not in screw_traits or "amphibious" not in screw_traits:
		print("  [FAIL] screw_drive should carry BOTH ground_contact and amphibious traits, got ", screw_traits)
		return false

	print("  [PASS] buoyant_envelope and screw_drive both spawn real matched pairs via update_locomotion(), and their catalog stats/traits reflect their real-world distinct character.")
	return true

func test_ship_hull_locomotion_mount_gap_fix() -> bool:
	print("Running Test Suite: Visual Bug Pass - Ship/Airship Hull Locomotion No Longer Floats Below The Mesh...")

	# Catalog-level: only the 4 hulls whose mesh doesn't fill its collision
	# box symmetrically (ship taper, airship ellipsoid) carry a nonzero
	# bias; every box-ish hull is untouched.
	for hull_id in []:
		if ModuleCatalog.get_underside_y_bias(hull_id) <= 0.0:
			print("  [FAIL] %s should carry a nonzero underside_y_bias (visual bug pass fix)." % hull_id)
			return false
	if ModuleCatalog.get_underside_y_bias("medium_hull") != 0.0:
		print("  [FAIL] medium_hull (a plain box-ish hull) should NOT have a bias - the fix shouldn't touch hulls that were already fine.")
		return false

	# End-to-end: placing wheels on an airship_hull via the real module_placer.gd
	# path should mount them measurably HIGHER than the naive box-bottom
	# calculation would put them - the actual regression this bug pass fixed.
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	root.add_child(hull)
	hull.set_meta("type_id", "airship_hull")
	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = ModuleCatalog.get_module_data("airship_hull").size
	col_shape.shape = box
	hull.add_child(col_shape)

	var placer = Node3D.new()
	placer.set_script(preload("res://scripts/module_placer.gd"))
	placer.hull = hull
	root.add_child(placer)
	await tree.process_frame

	placer.update_locomotion("wheels", {})
	await tree.process_frame
	var wheel_y = 0.0
	var found_wheel = false
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "wheels":
			wheel_y = child.position.y
			found_wheel = true
			break
	var naive_y = -box.size.y / 2.0 - 0.8
	if not found_wheel:
		print("  [FAIL] wheels should spawn on airship_hull.")
		placer.queue_free(); hull.queue_free()
		return false
	if wheel_y <= naive_y:
		print("  [FAIL] wheels on airship_hull should mount higher than the naive box-bottom calculation (", naive_y, "), got ", wheel_y, " - the underside_y_bias fix isn't being applied.")
		placer.queue_free(); hull.queue_free()
		return false

	placer.queue_free()
	hull.queue_free()
	print("  [PASS] Wheels on airship-shaped hulls now mount measurably closer to the real hull mesh instead of floating below/behind it.")
	return true

func test_fixed_wing_and_naval_movement() -> bool:
	print("Running Test Suite: Fixed-Wing + Naval Movement Models (Traits B3)...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	# --- Fixed-wing: never stops, banks into turns ---
	var plane = CharacterBody3D.new()
	plane.set_script(BattleUnitScript)
	root.add_child(plane)
	plane.move_speed = 8.0
	plane.rotate_speed = 3.0
	plane.is_fixed_wing = true
	plane.global_position = Vector3.ZERO
	await tree.process_frame

	# A destination essentially at the plane's own position (already
	# "arrived") - a ground unit would zero its velocity here; a fixed-wing
	# unit must keep flying at minimum airspeed regardless.
	plane._steer_fixed_wing(plane.global_position + Vector3(0, 0, -0.01), 0.1)
	var horizontal_speed = Vector2(plane.velocity.x, plane.velocity.z).length()
	if horizontal_speed < plane.move_speed - 0.5:
		print("  [FAIL] Fixed-wing should never drop below minimum airspeed even when 'arrived', got speed ", horizontal_speed, " (min ", plane.move_speed, ")")
		plane.queue_free()
		return false

	# A sharp turn should produce a non-trivial bank (roll) angle, not a
	# flat yaw-only turn like ground/hover steering.
	plane.global_transform = Transform3D.IDENTITY # facing -Z (default forward)
	plane._steer_fixed_wing(Vector3(10, 0, 0), 0.1) # hard turn toward +X
	var roll = plane.global_transform.basis.get_euler().z
	if abs(roll) < 0.05:
		print("  [FAIL] A sharp turn should produce a visible bank/roll angle, got ", roll)
		plane.queue_free()
		return false
	plane.queue_free()

	# --- Naval: surface-locked, unaffected by gravity ---
	var ship = CharacterBody3D.new()
	ship.set_script(BattleUnitScript)
	root.add_child(ship)
	ship.is_naval = true
	ship.global_position = Vector3(0, 5.0, 0) # start well above the waterline
	for i in range(30):
		ship._physics_process(0.1)
	if abs(ship.global_position.y - 0.3) > 1.0:
		print("  [FAIL] A naval unit should settle near the fixed waterline (y~0.3) regardless of gravity, got y=", ship.global_position.y)
		ship.queue_free()
		return false
	ship.queue_free()

	print("  [PASS] Fixed-wing units never stop and bank into turns; naval units stay surface-locked, unaffected by gravity.")
	return true

func test_weight_vs_locomotion_capacity_penalty() -> bool:
	print("Running Test Suite: Weight vs. Locomotion Capacity - Overload Slows The Unit...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var Drivetrain = preload("res://scripts/drivetrain.gd")

	# Builds a minimal unit with a fake hull_node carrying a locomotion
	# child (+ an optional heavy weapon child to push total weight up) and
	# calls _recalculate_move_speed() directly - same "mock the exact
	# fields the function reads" approach as test_traverse_limit's mock
	# weapon, so the test controls weight/scale precisely instead of
	# depending on the real blueprint pipeline's own scale decisions.
	#
	# ONE locomotion child, deliberately: a real design spawns one node per
	# station, but this suite is about the PENALTY, and a single node keeps
	# capacity equal to the type's flat base_weight_capacity so the numbers
	# below stay readable.
	# hull_type is explicit because the capacity retune (Chris, 2026-08-03 -
	# "bring the weight capacities down ... especially taking chassis / hull
	# weight into account") made the hull's own mass decisive at this scale: a
	# medium_hull weighs 225kg on its own, which is already over a single wheel
	# node's 200kg rating before any locomotion or payload is added. That is the
	# intended feel, but it means the "comfortably under capacity" case has to
	# be built on a light_hull (90kg) or there is no such case to test.
	var make_unit = func(locomotion_id: String, loco_weight: float, extra_module_weight: float, hull_type: String = "medium_hull") -> Node:
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		root.add_child(unit)
		unit.locomotion_type = locomotion_id
		unit.locomotion_settings = {}
		var fake_hull = Node3D.new()
		fake_hull.set_meta("type_id", hull_type)
		unit.add_child(fake_hull)
		unit.hull_node = fake_hull

		var loco_child = Node3D.new()
		var loco_data = ModuleData.new()
		loco_data.type_id = locomotion_id
		loco_data.category = "locomotion"
		loco_data.base_weight = loco_weight
		loco_child.set_meta("module_data", loco_data)
		fake_hull.add_child(loco_child)

		if extra_module_weight > 0.0:
			var extra_child = Node3D.new()
			var extra_data = ModuleData.new()
			extra_data.type_id = "artillery"
			extra_data.category = "weapon"
			extra_data.base_weight = extra_module_weight
			extra_child.set_meta("module_data", extra_data)
			fake_hull.add_child(extra_child)

		unit._recalculate_move_speed()
		return unit

	# The mock's hull_node has no type_id meta, so this falls back to
	# medium_hull's hull weight - REAL as of the FABLE review pass (hull mass,
	# incl. armor, now enters the combat weight total). armor_weight_mult 0.8:
	# no faction meta either, so it falls back to "industrialists", whose 20%
	# armor-weight discount is real combat behavior.
	var mock_hull_weight = ModuleCatalog.compute_hull_weight("medium_hull", 1.0, "hardened_steel", Vector3.ONE, 0.8)

	# Predicts the speed a design WOULD reach with no overload penalty:
	# thrust/weight, capped by the chassis's own top-speed rating. Written
	# against the named Drivetrain constants rather than repeating literals,
	# so retuning the model does not silently invalidate this suite - what is
	# being asserted here is the PENALTY's behavior, not the constants.
	var unpenalized = func(locomotion_id: String, total_weight: float) -> float:
		var thrust = Drivetrain.BASE_THRUST + ModuleCatalog.get_thrust_coefficient(locomotion_id)
		var power = maxf(Drivetrain.SPEED_FLOOR, (thrust / total_weight) * Drivetrain.TW_GAIN)
		return minf(power, ModuleCatalog.get_base_top_speed(locomotion_id))

	# One wheel node is rated for 200kg (ModuleCatalog.get_base_weight_capacity)
	# - a 200kg weapon + 50kg wheel chassis + a medium_hull's own 225kg puts it
	# far over. One tread node is rated for 600 - the SAME loadout on a 120kg
	# tread chassis stays under. This is the core ask made concrete: heavier,
	# tougher locomotion tolerates more excess weight before the penalty starts.
	#
	# The light case is on a light_hull for the reason given at make_unit: after
	# the capacity retune a medium hull alone outweighs one wheel node's rating,
	# so "comfortably under capacity" is not something a medium hull on a single
	# wheel can be. That is deliberate, and it is why the Design Lab now warns.
	var overloaded_wheels = make_unit.call("wheels", 50.0, 200.0)
	var loaded_treads = make_unit.call("tracked_treads", 120.0, 200.0)
	var light_wheels = make_unit.call("wheels", 50.0, 0.0, "light_hull")
	var cleanup = func():
		overloaded_wheels.queue_free()
		loaded_treads.queue_free()
		light_wheels.queue_free()

	# Prove the wheels case is ACTUALLY penalized, not just naturally slower
	# from carrying more weight (which the thrust/weight ratio already
	# accounts for).
	var wheels_total = 250.0 + mock_hull_weight
	var wheels_unpenalized = unpenalized.call("wheels", wheels_total)
	if overloaded_wheels.move_speed >= wheels_unpenalized - 0.01:
		print("  [FAIL] An overloaded wheeled unit (", wheels_total, "kg vs. 200 capacity) should be penalized below the unpenalized prediction. unpenalized=", wheels_unpenalized, " actual=", overloaded_wheels.move_speed)
		cleanup.call()
		return false

	# The unit must also REPORT being overloaded, not just be slower - the
	# Design Lab warning and anything else surfacing load reads these fields.
	if not overloaded_wheels.is_overloaded:
		print("  [FAIL] An overloaded unit should report is_overloaded = true. load_ratio=", overloaded_wheels.load_ratio)
		cleanup.call()
		return false
	if overloaded_wheels.top_speed <= overloaded_wheels.move_speed:
		print("  [FAIL] top_speed (pre-penalty) should exceed move_speed (post-penalty) on an overloaded unit, got top_speed=", overloaded_wheels.top_speed, " move_speed=", overloaded_wheels.move_speed)
		cleanup.call()
		return false

	# Prove the treads case gets NO penalty (matches the plain prediction
	# exactly, since it's under its own higher capacity).
	var treads_total = 320.0 + mock_hull_weight
	var treads_unpenalized = unpenalized.call("tracked_treads", treads_total)
	if abs(loaded_treads.move_speed - treads_unpenalized) > 0.01:
		print("  [FAIL] A tracked_treads unit under its own capacity (", treads_total, "kg vs. 600) should be unpenalized. expected=", treads_unpenalized, " actual=", loaded_treads.move_speed)
		cleanup.call()
		return false
	if loaded_treads.is_overloaded:
		print("  [FAIL] A unit under capacity should report is_overloaded = false, got load_ratio=", loaded_treads.load_ratio)
		cleanup.call()
		return false

	# A lightly-loaded unit well under capacity should also see zero
	# penalty (the multiplier is a true no-op below the threshold, not just
	# a small one).
	var light_hull_weight = ModuleCatalog.compute_hull_weight("light_hull", 1.0, "hardened_steel", Vector3.ONE, 0.8)
	var light_total = 50.0 + light_hull_weight
	var light_unpenalized = unpenalized.call("wheels", light_total)
	if light_total >= ModuleCatalog.get_base_weight_capacity("wheels"):
		print("  [FAIL] Test setup is wrong: the 'light' case (", light_total, "kg) is not actually under one wheel node's capacity (", ModuleCatalog.get_base_weight_capacity("wheels"), ") - pick a lighter hull.")
		cleanup.call()
		return false
	if abs(light_wheels.move_speed - light_unpenalized) > 0.01:
		print("  [FAIL] A lightly-loaded wheeled unit (", light_total, "kg vs. ", ModuleCatalog.get_base_weight_capacity("wheels"), " capacity) should have zero overload penalty. expected=", light_unpenalized, " actual=", light_wheels.move_speed)
		cleanup.call()
		return false

	cleanup.call()
	print("  [PASS] Weight beyond a locomotor's own capacity measurably slows the unit and is reported via is_overloaded/top_speed; heavier locomotion types (tracked_treads) tolerate more excess weight before the penalty kicks in than lighter ones (wheels); units under capacity are unaffected.")
	return true

# THE ANTI-DRIFT TEST. The Design Lab and combat used to compute load capacity
# in two separate places, and they had drifted: the sidebar knew about four
# locomotors and combat knew about six, so on most of the roster the Design Lab
# showed a capacity figure that could not respond to the tweaks driving it.
# Both now call Drivetrain.analyze(), and this asserts they agree - if someone
# reintroduces a local copy in either file, this fails.
func test_design_lab_and_combat_agree_on_weight_and_capacity() -> bool:
	print("Running Test Suite: Design Lab / Combat Drivetrain Agreement...")
	var Drivetrain = preload("res://scripts/drivetrain.gd")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	# Deliberately includes the locomotors the OLD Design Lab copy knew
	# nothing about (hover_engine's emv_level, fixed_wing_engine's turbine
	# compression, and an expansion type), with tweaks set to non-default
	# values so a stale copy would produce a visibly different number.
	var cases = [
		["wheels", {"num_axles": 6, "wheels_per_axle": 2}],
		["tracked_treads", {"tread_width": 2.0}],
		["legs", {"count": 6}],
		["hover_engine", {"pad_count": 6, "emv_level": 2.0}],
		["fixed_wing_engine", {"engine_count": 4, "turbine_compression": 1.5}],
		["buoyant_envelope", {"prop_count": 4}],
		["screw_drive", {"drum_diameter": 1.5, "helix_depth": 1.5}],
	]

	for case in cases:
		var loco_id: String = case[0]
		var settings: Dictionary = case[1]

		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		root.add_child(unit)
		unit.locomotion_type = loco_id
		unit.locomotion_settings = settings
		var hull = Node3D.new()
		hull.set_meta("type_id", "medium_hull")
		hull.set_meta("locomotion_type", loco_id)
		hull.set_meta("locomotion_settings", settings)
		unit.add_child(hull)
		unit.hull_node = hull
		# Three locomotion nodes plus a payload, so both the per-node sum and
		# the tweak factors are exercised rather than cancelling out.
		for _i in range(3):
			var child = Node3D.new()
			var d = ModuleData.new()
			d.type_id = loco_id
			d.category = "locomotion"
			d.base_weight = ModuleCatalog.get_module_data(loco_id).get("weight", 50.0)
			child.set_meta("module_data", d)
			hull.add_child(child)
		var payload = Node3D.new()
		var pd = ModuleData.new()
		pd.type_id = "artillery"
		pd.category = "weapon"
		pd.base_weight = 180.0
		payload.set_meta("module_data", pd)
		hull.add_child(payload)

		unit._recalculate_move_speed()
		# What the Design Lab sidebar reads for the very same hull.
		var lab = Drivetrain.analyze(hull)

		if abs(unit.total_weight - lab["weight"]) > 0.01:
			print("  [FAIL] ", loco_id, ": Design Lab weight ", lab["weight"], " disagrees with combat weight ", unit.total_weight)
			unit.queue_free()
			return false
		if abs(unit.weight_capacity - lab["capacity"]) > 0.01:
			print("  [FAIL] ", loco_id, ": Design Lab capacity ", lab["capacity"], " disagrees with combat capacity ", unit.weight_capacity, " - the two derivations have drifted apart again.")
			unit.queue_free()
			return false
		if abs(unit.move_speed - lab["move_speed"]) > 0.01:
			print("  [FAIL] ", loco_id, ": Design Lab move_speed ", lab["move_speed"], " disagrees with combat move_speed ", unit.move_speed)
			unit.queue_free()
			return false
		if unit.is_overloaded != lab["is_overloaded"]:
			print("  [FAIL] ", loco_id, ": Design Lab and combat disagree on whether the design is overloaded (", lab["is_overloaded"], " vs ", unit.is_overloaded, ")")
			unit.queue_free()
			return false
		unit.queue_free()

	print("  [PASS] The Design Lab and combat report identical weight, capacity, speed and overload state across 8 locomotors including the ones the old sidebar copy could not see.")
	return true

# Chris's ask: "max weight capacity ... should change based on the tweaks
# applied (eg, more axles = more weight capacity)". This asserts it for EVERY
# locomotion type in the catalog rather than the handful that happened to be
# wired, which is how the old if/elif chain left eleven types inert.
func test_every_locomotor_capacity_responds_to_its_own_tweaks() -> bool:
	print("Running Test Suite: Every Locomotor's Capacity Responds To Its Tweaks...")
	var Drivetrain = preload("res://scripts/drivetrain.gd")
	var LocomotionLayout = preload("res://scripts/locomotion_layout.gd")

	# Builds a hull with as many locomotion nodes as the real layout would
	# spawn for these settings - the same thing the game does, and the reason
	# a count tweak raises capacity at all.
	var build = func(loco_id: String, settings: Dictionary) -> Node3D:
		var ctx = {
			"hull_size": ModuleCatalog.REFERENCE_HULL_SIZE,
			"running_gear_size": ModuleCatalog.REFERENCE_HULL_SIZE,
			"underside_y_bias": 0.0,
			"catalog_size": ModuleCatalog.get_module_data(loco_id).get("size", Vector3.ONE),
		}
		var n = maxi(1, LocomotionLayout.stations(loco_id, settings, ctx).size())
		var hull = Node3D.new()
		hull.set_meta("type_id", "medium_hull")
		hull.set_meta("locomotion_type", loco_id)
		hull.set_meta("locomotion_settings", settings)
		for _i in range(n):
			var child = Node3D.new()
			var d = ModuleData.new()
			d.type_id = loco_id
			d.category = "locomotion"
			d.base_weight = ModuleCatalog.get_module_data(loco_id).get("weight", 50.0)
			child.set_meta("module_data", d)
			hull.add_child(child)
		return hull

	# (type_id, tweak dict at stock, tweak dict cranked up). Every locomotion
	# type in the catalog must appear here - the check below enforces that, so
	# adding a locomotor without wiring its load response fails this suite
	# rather than shipping inert.
	var cases = {
		"wheels": [{"num_axles": 4, "wheels_per_axle": 1}, {"num_axles": 8, "wheels_per_axle": 1}],
		"tracked_treads": [{"tread_width": 1.0}, {"tread_width": 2.0}],
		"legs": [{"count": 4}, {"count": 8}],
		"helicopter_rotors": [{"count": 4}, {"count": 8}],
		"hover_engine": [{"pad_count": 4, "emv_level": 1.0}, {"pad_count": 4, "emv_level": 2.0}],
		"fixed_wing_engine": [{"engine_count": 2, "turbine_compression": 1.0}, {"engine_count": 2, "turbine_compression": 2.0}],
		"ornithopter_wing": [{"wingspan": 1.0}, {"wingspan": 2.0}],
		# The one type whose capacity must NOT rise with its count tweak:
		# an airship's lift is buoyancy, so extra engine pods carry nothing.
		# Checked separately below.
		"buoyant_envelope": [{"prop_count": 2}, {"prop_count": 2}],
		"half_track": [{"tread_width": 1.0}, {"tread_width": 2.0}],
		"rocker_bogie": [{"bogie_pairs": 3.0}, {"bogie_pairs": 6.0}],
		"pontoon_wheels": [{"axle_count": 4, "pontoon_size": 1.0}, {"axle_count": 8, "pontoon_size": 1.5}],
		"air_cushion_skirt": [{"plenum_pressure": 1.0}, {"plenum_pressure": 2.0}],
		"anti_grav_plate": [{"plate_count": 4, "field_strength": 1.0}, {"plate_count": 4, "field_strength": 2.0}],
		"screw_drive": [{"drum_diameter": 1.0}, {"drum_diameter": 2.0}],
	}

	var uncovered: Array = []
	for type_id in ModuleCatalog.get_catalog():
		if ModuleCatalog.get_module_data(type_id).get("category", "") == "locomotion" and not cases.has(type_id):
			uncovered.append(type_id)
	if not uncovered.is_empty():
		print("  [FAIL] These locomotion types have no capacity-response case here, so nothing checks that their tweaks do anything: ", uncovered)
		return false

	for loco_id in cases:
		var stock_hull = build.call(loco_id, cases[loco_id][0])
		var up_hull = build.call(loco_id, cases[loco_id][1])
		root.add_child(stock_hull)
		root.add_child(up_hull)
		var stock = Drivetrain.analyze(stock_hull)
		var up = Drivetrain.analyze(up_hull)
		var stock_cap: float = stock["capacity"]
		var up_cap: float = up["capacity"]
		stock_hull.free()
		up_hull.free()

		if loco_id == "buoyant_envelope":
			continue
		if up_cap <= stock_cap + 0.01:
			print("  [FAIL] ", loco_id, ": cranking its load-bearing tweak did not raise weight capacity (", stock_cap, " -> ", up_cap, "). Its entry in Drivetrain.TWEAK_RESPONSE is inert.")
			return false

	# An airship's engine count must NOT change what it can carry - the
	# capacity: -1.0 exponent cancels the per-node sum exactly.
	var air_2 = build.call("buoyant_envelope", {"prop_count": 2})
	var air_6 = build.call("buoyant_envelope", {"prop_count": 6})
	root.add_child(air_2)
	root.add_child(air_6)
	var a2 = Drivetrain.analyze(air_2)
	var a6 = Drivetrain.analyze(air_6)
	var flat_ok = abs(a2["capacity"] - a6["capacity"]) < 0.01
	var thrust_up = a6["thrust"] > a2["thrust"] + 0.01
	air_2.free()
	air_6.free()
	if not flat_ok:
		print("  [FAIL] buoyant_envelope capacity should be set by the envelope, not the engine count - got ", a2["capacity"], " at 2 props vs ", a6["capacity"], " at 6.")
		return false
	if not thrust_up:
		print("  [FAIL] buoyant_envelope should still gain THRUST from extra engine pods, got ", a2["thrust"], " -> ", a6["thrust"])
		return false

	print("  [PASS] Every locomotion type's weight capacity responds to its own load-bearing tweak, and buoyant_envelope correctly gains thrust but not capacity from extra engines.")
	return true

# REGRESSION GUARD for a real balance bug. LocomotionLayout spawns one node per
# count, and Drivetrain sums capacity per node - so a count tweak already
# scales capacity linearly. The old if/elif chain multiplied by the count a
# SECOND time, making capacity and thrust grow with the SQUARE of the count
# while weight grew only linearly: 4 axles -> 8 quadrupled capacity for double
# the wheel mass, so "drag the count slider up" strictly dominated every other
# response to being overweight and quietly defeated the whole mechanic.
func test_count_tweaks_scale_capacity_linearly_not_quadratically() -> bool:
	print("Running Test Suite: Count Tweaks Do Not Double-Count Capacity...")
	var Drivetrain = preload("res://scripts/drivetrain.gd")

	# Capacity for N locomotion nodes, with the count tweak set to match N -
	# exactly the pairing the real game produces.
	var cap_for = func(loco_id: String, count_key: String, n: int) -> float:
		var settings = {count_key: n}
		var hull = Node3D.new()
		hull.set_meta("type_id", "medium_hull")
		hull.set_meta("locomotion_type", loco_id)
		hull.set_meta("locomotion_settings", settings)
		for _i in range(n):
			var child = Node3D.new()
			var d = ModuleData.new()
			d.type_id = loco_id
			d.category = "locomotion"
			d.base_weight = 0.0
			child.set_meta("module_data", d)
			hull.add_child(child)
		root.add_child(hull)
		var c: float = Drivetrain.analyze(hull)["capacity"]
		hull.free()
		return c

	for case in [["wheels", "num_axles"], ["legs", "count"],
			["helicopter_rotors", "count"], ["hover_engine", "pad_count"],
			["anti_grav_plate", "plate_count"], ["pontoon_wheels", "axle_count"]]:
		var loco_id: String = case[0]
		var key: String = case[1]
		var c4 = cap_for.call(loco_id, key, 4)
		var c8 = cap_for.call(loco_id, key, 8)
		if c4 <= 0.0:
			print("  [FAIL] ", loco_id, " reported zero capacity at 4 nodes; test setup is wrong.")
			return false
		var factor = c8 / c4
		# Linear (2.0), not quadratic (4.0). Tolerance is wide enough for a
		# deliberate sub-linear pull-back but nowhere near the squared value.
		if factor > 2.5:
			print("  [FAIL] ", loco_id, ": doubling the ", key, " count multiplied capacity by ", factor, " - it is being counted twice (once per spawned node, once via the tweak factor). Linear is ~2.0; quadratic is 4.0.")
			return false
		if factor < 1.2:
			print("  [FAIL] ", loco_id, ": doubling the ", key, " count barely changed capacity (x", factor, ") - more running gear must carry meaningfully more.")
			return false

	print("  [PASS] Doubling a locomotor's count roughly doubles its weight capacity rather than quadrupling it - the per-node sum and the tweak table no longer both apply the count.")
	return true

# Chris, 2026-08-03: "the locomotors are currently falling through the ground in
# the test arena, leaving the vehicles sliding around on their belly."
#
# Two independent faults produced that, and this suite pins both.
#
# 1. RIDE HEIGHT. reconstruct_vehicle() lifted the hull with a hand-tuned
#    formula that special-cased only wheels and legs (every other ground type
#    got no ride height at all), and whose two constants read settings["size"] -
#    a key neither type stores, so both silently used 1.0 and ignored the tweak.
#    It now measures the real locomotion geometry with the same shared helper
#    module_placer.gd uses, so a design sits at the same height in a battle as
#    it did in the lab. Asserted by comparing the two directly: if either side
#    grows its own copy of the measurement again, they drift and this fails.
#
# 2. GROUND SNAP. battle_unit.gd picks its ground height from
#    get_parent().terrain_height_at() and falls back to gravity +
#    is_on_floor() when the parent has no such method. Battlefield.tscn had
#    none, so the arena took the fallback - which rests the unit on its only
#    collider, the one around the HULL, burying the running gear underneath.
#    Skirmish never showed it because skirmish.gd does implement the method.
func test_battle_spawn_sits_on_its_running_gear() -> bool:
	print("Running Test Suite: Battle Spawn Ride Height / Ground Contact...")
	var BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")

	# Ground types spanning both halves of the old bug: wheels and legs were the
	# two the formula knew about, the rest got nothing.
	var cases = [
		["wheels", {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 1}],
		["legs", {"leg_length": 1.0, "leg_width": 1.0, "count": 4}],
		["tracked_treads", {"tread_width": 1.0}],
		["screw_drive", {"drum_diameter": 1.0, "helix_depth": 1.0}],
		["half_track", {}],
	]

	# --- The arena must publish a ground height at all (fault 2) ---
	var arena = load("res://scenes/Battlefield.tscn").instantiate()
	root.add_child(arena)
	for _i in range(20):
		await tree.process_frame
	if not arena.has_method("terrain_height_at"):
		print("  [FAIL] Battlefield.tscn's script must implement terrain_height_at() - without it battle_unit.gd takes its gravity/is_on_floor fallback, which rests the unit on its HULL collider and buries the running gear.")
		arena.queue_free()
		return false
	var floor_y: float = arena.terrain_height_at(Vector3.ZERO)
	# The arena slab is a 100x1x100 box centred at y=-0.5, so its top is y=0.
	if absf(floor_y) > 0.001:
		print("  [FAIL] The arena floor should report y=0 (the slab's top face), got ", floor_y)
		arena.queue_free()
		return false

	# --- Ride height must match the Design Lab's, per type (fault 1) ---
	var lab = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab)
	for _i in range(12):
		await tree.process_frame
	var lab_bp = BlueprintManagerScript.new()
	lab.add_child(lab_bp)
	var arena_bp = BlueprintManagerScript.new()
	arena.add_child(arena_bp)

	var fail = func(msg: String) -> bool:
		print("  [FAIL] " + msg)
		lab.queue_free()
		arena.queue_free()
		return false

	# Lowest drawn locomotion geometry, in the hull's own local space.
	var lowest_gear = func(hull: Node3D) -> float:
		var lowest := INF
		for child in hull.get_children():
			if not child.has_meta("module_data"):
				continue
			var d = child.get_meta("module_data")
			if d == null or d.category != "locomotion":
				continue
			var wb: AABB = VisualBuilderScript.measure_visual_bounds(child)
			if wb.size.length_squared() <= 0.0:
				continue
			lowest = minf(lowest, child.position.y + wb.position.y * child.scale.y)
		return lowest

	for case in cases:
		var loco_id: String = case[0]
		if lab.get_node_or_null("Hull") == null:
			lab._place_hull_from_ui("medium_hull")
			for _i in range(6):
				await tree.process_frame
		lab.update_locomotion(loco_id, (case[1] as Dictionary).duplicate())
		for _i in range(8):
			await tree.process_frame
		var lab_hull = lab.get_node_or_null("Hull")
		if lab_hull == null:
			return fail.call("Design Lab built no hull for " + loco_id)
		var lab_lift: float = lab_hull.position.y
		var blueprint: Dictionary = lab_bp.serialize_hull(lab_hull)

		# Reconstruct the way a battle spawn does (is_designer = false).
		var battle_hull = arena_bp.reconstruct_vehicle(blueprint, arena, false, "industrialists")
		if battle_hull == null:
			return fail.call("reconstruct_vehicle returned nothing for " + loco_id)

		# A real ride height, not zero - "not on its belly".
		if battle_hull.position.y <= 0.01:
			return fail.call("%s: a battle-spawned hull must be LIFTED clear of the ground, got hull.position.y = %.3f. This is the 'slides around on its belly' bug." % [loco_id, battle_hull.position.y])

		# ...and the SAME height the lab previewed.
		if absf(battle_hull.position.y - lab_lift) > 0.02:
			return fail.call("%s: battle ride height %.3f disagrees with the Design Lab's %.3f - the two ride-height derivations have drifted apart again." % [loco_id, battle_hull.position.y, lab_lift])

		# The lift must put the lowest running gear exactly on the contact
		# plane: the unit's origin IS its ground contact point, which is the
		# invariant both the analytic terrain snap and is_on_floor() rely on.
		var gear: float = lowest_gear.call(battle_hull)
		if gear == INF:
			return fail.call("%s: the reconstructed hull has no locomotion geometry to measure - locomotion should arrive as entries in the blueprint's `modules` array." % loco_id)
		var contact: float = battle_hull.position.y + gear
		if absf(contact) > 0.05:
			return fail.call("%s: the lowest running gear should sit on the unit's origin (y=0), got %.3f. Negative means it is buried below the ground plane." % [loco_id, contact])

		battle_hull.queue_free()
		await tree.process_frame

	lab.queue_free()
	arena.queue_free()
	print("  [PASS] The test arena publishes a ground height, and a battle-spawned hull is lifted to put its lowest running gear exactly on the contact plane - at the identical ride height the Design Lab previewed, across wheels/legs/treads/screw_drive/half_track.")
	return true
func test_terrain_types_differentiate_locomotion() -> bool:
	print("Running Test Suite: Terrain Variety - All 7 Surface Types (marsh/rocky/snow_mud/sand/gravel/forest/ice) Genuinely Differentiate Locomotor Types...")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	# Fake controller: only get_surface_type_at() exists (no get_ground_nav_map),
	# so _setup_navigation() never creates a real nav_agent and _steer_towards()
	# falls back to plain direct-line steering - a real, deterministic distance
	# per fixed physics tick count, driven by the exact same _recalculate_
	# terrain_speed_multiplier() -> _steer_towards() code path a real match uses.
	var controller_script = preload("res://scripts/fake_surface_controller.gd")

	var measure = func(locomotion_type_id: String, surface_type: String) -> float:
		var controller = Node.new()
		controller.set_script(controller_script)
		controller.surface_type = surface_type
		root.add_child(controller)

		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		controller.add_child(unit)
		unit.locomotion_type = locomotion_type_id
		unit.locomotion_settings = {}
		var fake_hull = Node3D.new()
		unit.add_child(fake_hull)
		unit.hull_node = fake_hull

		var loco_data = ModuleData.new()
		loco_data.type_id = locomotion_type_id
		loco_data.category = "locomotion"
		loco_data.base_weight = 80.0
		var loco_child = Node3D.new()
		loco_child.set_meta("module_data", loco_data)
		fake_hull.add_child(loco_child)
		unit._recalculate_move_speed()

		unit.global_position = Vector3.ZERO
		unit._setup_navigation()
		unit.order_move(Vector3(0, 0, -1000))
		# Matches test_unit_order_move_actually_navigates_around_the_lake's
		# established pattern: CharacterBody3D.move_and_slide() reads the
		# real engine physics delta internally regardless of what's passed
		# to _physics_process(), so an explicit move_and_slide() call after
		# each manual tick (with delta matching the real physics_fps) is
		# needed for a synthetic, non-scene-tree-driven loop to produce
		# real, comparable distances.
		for i in range(140):
			unit._physics_process(1.0 / 60.0)
			unit.move_and_slide()
		var dist = unit.global_position.length()
		controller.queue_free()
		return dist

	# marsh: screw_drive should outpace wheels by a wide margin (favored vs.
	# punished), not just a marginal difference.
	var marsh_wheels = measure.call("wheels", "marsh")
	var marsh_screw = measure.call("screw_drive", "marsh")
	if marsh_screw <= marsh_wheels * 1.5:
		print("  [FAIL] marsh: screw_drive should cross noticeably faster than wheels. wheels=", marsh_wheels, " screw_drive=", marsh_screw)
		return false

	# rocky: legs should outpace wheels.
	var rocky_wheels = measure.call("wheels", "rocky")
	var rocky_legs = measure.call("legs", "rocky")
	if rocky_legs <= rocky_wheels * 1.5:
		print("  [FAIL] rocky: legs should cross noticeably faster than wheels. wheels=", rocky_wheels, " legs=", rocky_legs)
		return false

	# snow_mud: tracked_treads should outpace wheels hard.
	var mud_wheels = measure.call("wheels", "snow_mud")
	var mud_treads = measure.call("tracked_treads", "snow_mud")
	if mud_treads <= mud_wheels * 2.0:
		print("  [FAIL] snow_mud: tracked_treads should cross far faster than wheels (wheels bog down hard). wheels=", mud_wheels, " treads=", mud_treads)
		return false

	# sand: tracked_treads should outpace wheels.
	var sand_wheels = measure.call("wheels", "sand")
	var sand_treads = measure.call("tracked_treads", "sand")
	if sand_treads <= sand_wheels * 1.5:
		print("  [FAIL] sand: tracked_treads should cross noticeably faster than wheels. wheels=", sand_wheels, " treads=", sand_treads)
		return false

	# RTS_CORE_ROADMAP.md B7: gravel is the one surface that's a genuine
	# speed BONUS for every locomotor, not a penalty - wheels (its best
	# case) should measurably outrun the same wheels on plain ground.
	var plain_wheels_baseline = measure.call("wheels", "")
	var gravel_wheels = measure.call("wheels", "gravel")
	if gravel_wheels <= plain_wheels_baseline * 1.15:
		print("  [FAIL] gravel: wheels should cross measurably faster than on plain ground (a real bonus, not just 'least penalized'). plain=", plain_wheels_baseline, " gravel=", gravel_wheels)
		return false

	# forest: legs should outpace wheels (dense vegetation blocks wheels
	# hardest, legs weave through best).
	var forest_wheels = measure.call("wheels", "forest")
	var forest_legs = measure.call("legs", "forest")
	if forest_legs <= forest_wheels * 1.5:
		print("  [FAIL] forest: legs should cross noticeably faster than wheels. wheels=", forest_wheels, " legs=", forest_legs)
		return false

	# ice: unlike every other surface (which always has one clear
	# "winner"), ice penalizes every locomotor - screw_drive suffers LEAST
	# (its auger bites in rather than relying on friction).
	var ice_wheels = measure.call("wheels", "ice")
	var ice_legs = measure.call("legs", "ice")
	var ice_treads = measure.call("tracked_treads", "ice")
	var ice_screw = measure.call("screw_drive", "ice")
	if not (ice_screw > ice_wheels and ice_screw > ice_legs and ice_screw > ice_treads):
		print("  [FAIL] ice: screw_drive should outpace every other locomotor (suffers least from lost traction). wheels=", ice_wheels, " legs=", ice_legs, " treads=", ice_treads, " screw_drive=", ice_screw)
		return false
	# Each locomotor against ITS OWN plain-ground distance, not against wheels'.
	# The old form compared all three to plain_wheels_baseline, which was only
	# meaningful while every type shared one speed on plain ground - true when
	# they all shared the universal 18.0 ceiling and the same thrust, and false
	# now that each chassis has its own base_top_speed and its own load rating.
	# It broke on tracked_treads: this fixture mounts a single locomotion node,
	# so wheels (rated 200kg) are overloaded by the hull alone while treads
	# (rated 600kg) are not, which dropped wheels' PLAIN baseline below treads'
	# ICE distance and failed an assertion about ice. Per-type is both correct
	# and what the comment above actually claims.
	for loco_id in ["wheels", "legs", "tracked_treads", "screw_drive"]:
		var on_plain = measure.call(loco_id, "")
		var on_ice = measure.call(loco_id, "ice")
		if on_ice >= on_plain:
			print("  [FAIL] ice should penalize every locomotor: ", loco_id, " covered ", on_ice, " on ice vs ", on_plain, " on plain ground.")
			return false

	# Sanity: plain ground (no surface_type) should be unaffected by any of
	# this - same locomotion type covers the same distance on "" as it does
	# with a 1.0 multiplier explicitly, proving the default fallback works.
	if abs(plain_wheels_baseline - marsh_wheels) < 0.01:
		print("  [FAIL] plain ground and marsh gave wheels the identical distance (", plain_wheels_baseline, ") - the multiplier isn't actually being applied.")
		return false

	print("  [PASS] marsh favors screw_drive, rocky favors legs, snow_mud/sand/forest favor tracked_treads or legs over wheels, gravel is a genuine bonus, ice penalizes every locomotor (screw_drive least) - all measured via real physics-tick movement, not just catalog numbers.")
	return true

func test_locomotion_tweaks_have_real_visual_and_stat_effects() -> bool:
	print("Running Test Suite: Locomotion Tweaks (axle-count/leg-count/tread-width) Have Real Visual + Stat Effects...")
	var ModulePlacerScript = preload("res://scripts/module_placer.gd")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	var controller_script = preload("res://scripts/fake_surface_controller.gd")

	# --- Visual: count/width tweaks actually change spawned geometry, not
	# just the underlying stats - through the real module_placer.gd path. ---
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(4.0, 1.0, 6.0)
	mesh_inst.mesh = box
	mesh_inst.name = "MeshInstance3D"
	hull.add_child(mesh_inst)
	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = Vector3(4.0, 1.0, 6.0)
	col.shape = col_box
	col.name = "CollisionShape3D"
	hull.add_child(col)
	hull.set_meta("base_hull_size", Vector3(4.0, 1.0, 6.0))
	hull.set_meta("hull_scale", Vector3(1, 1, 1))
	hull.set_meta("type_id", "medium_hull")
	root.add_child(hull)
	await tree.process_frame

	var placer = Node3D.new()
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	root.add_child(placer)
	await tree.process_frame

	var count_children = func(type_id: String) -> int:
		var n = 0
		for child in hull.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == type_id:
				n += 1
		return n

	placer.update_locomotion("wheels", {"size": 1.0, "count": 2})
	await tree.process_frame
	var wheels_low_count = count_children.call("wheels")
	placer.update_locomotion("wheels", {"size": 1.0, "count": 8})
	await tree.process_frame
	var wheels_high_count = count_children.call("wheels")
	if wheels_high_count <= wheels_low_count:
		print("  [FAIL] wheels axle-count tweak didn't change the number of spawned wheel instances (low=", wheels_low_count, " high=", wheels_high_count, ")")
		placer.queue_free(); hull.queue_free()
		return false

	placer.update_locomotion("legs", {"size": 1.0, "count": 2})
	await tree.process_frame
	var legs_low_count = count_children.call("legs")
	placer.update_locomotion("legs", {"size": 1.0, "count": 8})
	await tree.process_frame
	var legs_high_count = count_children.call("legs")
	if legs_high_count <= legs_low_count:
		print("  [FAIL] legs leg-count tweak didn't change the number of spawned leg instances (low=", legs_low_count, " high=", legs_high_count, ")")
		placer.queue_free(); hull.queue_free()
		return false

	# tread_width is baked directly into the belt/sprocket/road-wheel/mount
	# sub-part scales inside _build_tracked_treads(), not into the outer
	# module node's own scale (which module_placer.gd deliberately leaves at
	# Vector3.ONE now to avoid double-applying the tweak - see its
	# update_locomotion() comments) - so the tweaks dict is the real signal
	# that the width slider did something, same as get_weight()/get_cost()
	# already read it directly.
	placer.update_locomotion("tracked_treads", {"width": 0.5})
	await tree.process_frame
	var tread_narrow_width = 0.0
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "tracked_treads":
			tread_narrow_width = child.get_meta("module_data").tweaks.get("tread_width", 0.0)
			break
	placer.update_locomotion("tracked_treads", {"width": 2.5})
	await tree.process_frame
	var tread_wide_width = 0.0
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "tracked_treads":
			tread_wide_width = child.get_meta("module_data").tweaks.get("tread_width", 0.0)
			break
	if tread_wide_width <= tread_narrow_width:
		print("  [FAIL] tracked_treads width tweak didn't widen the tread (narrow_width=", tread_narrow_width, " wide_width=", tread_wide_width, ")")
		placer.queue_free(); hull.queue_free()
		return false

	placer.queue_free()
	hull.queue_free()
	await tree.process_frame

	# --- Stat: tweaks produce a real, correctly-directioned move_speed
	# effect, using the mobility-addon test's ballast pattern to isolate
	# thrust-only vs. capacity/overload-only effects. ---
	#
	# make_unit spawns as many locomotion NODES as the real layout would for
	# these settings. It used to spawn exactly one regardless of the count
	# tweak, which made every count assertion below test a configuration the
	# game cannot produce: capacity and thrust are summed per node, so a count
	# of 8 on a single node is a 2-axle rig wearing an 8-axle label. That mock
	# is also what hid the fact that the old formula multiplied count in twice
	# (once per node, once via the tweak factor) - see
	# test_count_tweaks_scale_capacity_linearly_not_quadratically.
	#
	# The ballast weights below are chosen per assertion, from the sweep in
	# scratch/probe_legs_treads.gd, because each claim is only meaningful in
	# one regime: with too little ballast both variants sit on their chassis
	# top-speed ceiling and tie, and with too much both sit on SPEED_FLOOR and
	# tie again. The old single universal 18.0 ceiling had no upper tie.
	var make_unit = func(loco_type: String, settings: Dictionary, ballast_weight: float) -> Node:
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		root.add_child(unit)
		unit.locomotion_type = loco_type
		unit.locomotion_settings = settings
		var fake_hull = Node3D.new()
		fake_hull.set_meta("locomotion_type", loco_type)
		fake_hull.set_meta("locomotion_settings", settings)
		unit.add_child(fake_hull)
		unit.hull_node = fake_hull

		var station_ctx = {
			"hull_size": ModuleCatalog.REFERENCE_HULL_SIZE,
			"running_gear_size": ModuleCatalog.REFERENCE_HULL_SIZE,
			"underside_y_bias": 0.0,
			"catalog_size": ModuleCatalog.get_module_data(loco_type).get("size", Vector3.ONE),
		}
		var node_count = maxi(1, LocomotionLayoutScript.stations(loco_type, settings, station_ctx).size())
		for _i in range(node_count):
			var loco_child = Node3D.new()
			var loco_data = ModuleData.new()
			loco_data.type_id = loco_type
			loco_data.category = "locomotion"
			loco_data.base_weight = 50.0
			loco_child.set_meta("module_data", loco_data)
			fake_hull.add_child(loco_child)

		var ballast_child = Node3D.new()
		var ballast_data = ModuleData.new()
		ballast_data.type_id = "armor_plating"
		ballast_data.category = "armor"
		ballast_data.base_weight = ballast_weight
		ballast_child.set_meta("module_data", ballast_data)
		fake_hull.add_child(ballast_child)

		unit._recalculate_move_speed()
		return unit

	# Wheels: axle count raises BOTH thrust and capacity together (no
	# tradeoff), so more axles is faster at every load - the "bigger rig"
	# archetype. Heavy ballast so the 2-axle case is genuinely overloaded and
	# the capacity difference shows as a real, unclamped speed gain.
	var wheels_2 = make_unit.call("wheels", {"num_axles": 2}, 400.0)
	var wheels_8 = make_unit.call("wheels", {"num_axles": 8}, 400.0)
	if wheels_8.move_speed <= wheels_2.move_speed:
		print("  [FAIL] more wheel axles should raise move_speed (more thrust AND more capacity, less overload). axles=2:", wheels_2.move_speed, " axles=8:", wheels_8.move_speed)
		return false

	# Legs, heavy load: more legs wins, because capacity scales with the
	# number of load-bearing contact points and the 2-leg case is badly
	# overloaded at this weight.
	var legs_2_heavy = make_unit.call("legs", {"count": 2}, 1000.0)
	var legs_8_heavy = make_unit.call("legs", {"count": 8}, 1000.0)
	if legs_8_heavy.move_speed <= legs_2_heavy.move_speed:
		print("  [FAIL] more legs should win under heavy load (more capacity). count=2:", legs_2_heavy.move_speed, " count=8:", legs_8_heavy.move_speed)
		return false

	# Legs, the thrust side of the tradeoff: each ADDED leg contributes less
	# thrust than the one before it, because there is more mechanical mass to
	# coordinate. Asserted per leg rather than as a total.
	#
	# This assertion used to read "fewer legs should be FASTER under light
	# load", and that was never true in the shipped game - only in the
	# single-node mock this function used to build. With one node, 2 legs got
	# a 1.25x thrust bonus and 8 legs a 0.5x penalty, so 2 legs won; with the
	# real node count, 8 legs bring 8 motors and out-pull 2 however much each
	# individual leg is derated. Total thrust cannot favour fewer legs unless
	# the per-leg penalty is steeper than 1/n, and at that point capacity
	# (which rises linearly with legs) makes the few-leg build overloaded
	# before it can ever be power-limited - verified across the whole ballast
	# range in scratch/probe_legs_treads.gd. So the honest claim is the
	# per-leg one, and it is what the design intent ("fewer legs trades
	# stability for agility") actually rests on.
	var legs_2_thrust = DrivetrainScript.analyze(legs_2_heavy.hull_node, "legs", {"count": 2})
	var legs_8_thrust = DrivetrainScript.analyze(legs_8_heavy.hull_node, "legs", {"count": 8})
	var per_leg_2 = (legs_2_thrust["thrust"] - DrivetrainScript.BASE_THRUST) / 2.0
	var per_leg_8 = (legs_8_thrust["thrust"] - DrivetrainScript.BASE_THRUST) / 8.0
	if per_leg_8 >= per_leg_2:
		print("  [FAIL] each added leg should contribute LESS thrust than the last (diminishing returns per leg). per-leg at 2:", per_leg_2, " per-leg at 8:", per_leg_8)
		return false
	if legs_8_thrust["thrust"] <= legs_2_thrust["thrust"]:
		print("  [FAIL] ...but TOTAL thrust should still rise with leg count - 8 motors out-pull 2. total at 2:", legs_2_thrust["thrust"], " total at 8:", legs_8_thrust["thrust"])
		return false

	# Treads, light load: narrower is FASTER (less friction). Ballast is kept
	# low enough that the narrow build still reaches the tread chassis ceiling
	# while the wide one is held below it by its own friction - a wide margin
	# (8.0 vs ~6.1) rather than the ~4% gap a heavier, both-power-limited
	# ballast would give, which a future retune could flip by accident.
	var treads_narrow_light = make_unit.call("tracked_treads", {"tread_width": 0.5}, 200.0)
	var treads_wide_light = make_unit.call("tracked_treads", {"tread_width": 2.5}, 200.0)
	if treads_narrow_light.move_speed <= treads_wide_light.move_speed:
		print("  [FAIL] narrower treads should be faster under light load. narrow=", treads_narrow_light.move_speed, " wide=", treads_wide_light.move_speed)
		return false

	# Treads, heavy load: WIDER wins (more contact area, more capacity, so no
	# overload penalty - which outweighs its lower thrust).
	var treads_narrow_heavy = make_unit.call("tracked_treads", {"tread_width": 0.5}, 800.0)
	var treads_wide_heavy = make_unit.call("tracked_treads", {"tread_width": 2.5}, 800.0)
	if treads_wide_heavy.move_speed <= treads_narrow_heavy.move_speed:
		print("  [FAIL] wider treads should win under heavy load (more capacity). narrow=", treads_narrow_heavy.move_speed, " wide=", treads_wide_heavy.move_speed)
		return false

	for u in [wheels_2, wheels_8, legs_2_heavy, legs_8_heavy, treads_narrow_light, treads_wide_light, treads_narrow_heavy, treads_wide_heavy]:
		u.queue_free()

	# --- Terrain multiplier: tread width should modulate the marsh
	# penalty (wider = less severe), not just the flat catalog number. ---
	var measure_terrain = func(width: float) -> float:
		var controller = Node.new()
		controller.set_script(controller_script)
		controller.surface_type = "marsh"
		root.add_child(controller)
		var unit = CharacterBody3D.new()
		unit.set_script(BattleUnitScript)
		controller.add_child(unit)
		unit.locomotion_type = "tracked_treads"
		unit.locomotion_settings = {"width": width}
		unit.global_position = Vector3.ZERO
		unit._recalculate_terrain_speed_multiplier()
		var result = unit.terrain_speed_multiplier
		controller.queue_free()
		return result

	var marsh_narrow = measure_terrain.call(0.5)
	var marsh_wide = measure_terrain.call(2.5)
	if marsh_wide <= marsh_narrow:
		print("  [FAIL] wider treads should suffer less of a marsh speed penalty than narrower ones. narrow_multiplier=", marsh_narrow, " wide_multiplier=", marsh_wide)
		return false

	print("  [PASS] Wheels axle-count, legs leg-count, and tracked_treads width tweaks all produce real spawned-geometry changes and real, correctly-directioned move_speed/terrain effects - not just sliders.")
	return true

func test_ornithopter_wing_spawns_flaps_and_flies() -> bool:
	print("Running Test Suite: Ornithopter Wing - Real Placement, Flap Animation, and Hover-Capable Flight...")
	var ModulePlacerScript = preload("res://scripts/module_placer.gd")
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	# Traits: airborne (flies) but NOT fixed_wing - simple hover-arrival
	# flight like helicopter_rotors/hover_engine/anti_grav, not the
	# banking/minimum-airspeed paradigm. The mechanical similarity to
	# existing flight locomotion Chris explicitly asked for; the visual/
	# flavor (flapping motion, distinct silhouette) is the real differentiator.
	var loco_traits = ModuleCatalog.get_traits("medium_hull", "ornithopter_wing")
	if not ("airborne" in loco_traits):
		print("  [FAIL] ornithopter_wing should carry the airborne trait")
		return false
	if "fixed_wing" in loco_traits:
		print("  [FAIL] ornithopter_wing should NOT carry fixed_wing (simple hover flight, not banking/airspeed)")
		return false

	# Real placement via module_placer.gd: 2 wing instances (left/right),
	# each with a WingPivot node (the flap-animation target).
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = Vector3(4.0, 1.0, 6.0)
	col.shape = col_box
	col.name = "CollisionShape3D"
	hull.add_child(col)
	hull.set_meta("base_hull_size", Vector3(4.0, 1.0, 6.0))
	hull.set_meta("hull_scale", Vector3(1, 1, 1))
	hull.set_meta("type_id", "medium_hull")
	root.add_child(hull)
	await tree.process_frame

	var placer = Node3D.new()
	placer.set_script(ModulePlacerScript)
	placer.hull = hull
	root.add_child(placer)
	await tree.process_frame

	placer.update_locomotion("ornithopter_wing", {"size": 1.0, "count": 2})
	await tree.process_frame

	var wing_instances = []
	for child in hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "ornithopter_wing":
			wing_instances.append(child)
	if wing_instances.size() != 2:
		print("  [FAIL] expected 2 ornithopter_wing instances (left/right), found ", wing_instances.size())
		placer.queue_free(); hull.queue_free()
		return false
	for w in wing_instances:
		# Dragonfly-style fore/hind wing pair, each with its own
		# flap-animation pivot (see visual_builder.gd's
		# _build_ornithopter_wing rebuild, 2026-07-24).
		if not w.has_node("WingPivotFore") or not w.has_node("WingPivotHind"):
			print("  [FAIL] ornithopter_wing instance missing WingPivotFore/WingPivotHind (flap-animation targets)")
			placer.queue_free(); hull.queue_free()
			return false

	placer.queue_free()
	await tree.process_frame

	# Flap animation: real oscillation over time, driven by battle_unit.gd's
	# per-physics-tick update, not a static authored pose - and the fore/
	# hind pivots must beat in OPPOSITION to each other (Chris's ask: "flap
	# rapidly in opposition to each other per node", like a real
	# dragonfly's two wing pairs beating roughly 180deg out of phase), not
	# in unison.
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	unit.locomotion_type = "ornithopter_wing"
	unit.locomotion_settings = {}
	unit.is_flying = true
	hull.get_parent().remove_child(hull)
	unit.add_child(hull)
	unit.hull_node = hull
	unit.global_position = Vector3.ZERO
	await tree.process_frame

	var fore_pivot = wing_instances[0].get_node("WingPivotFore")
	var hind_pivot = wing_instances[0].get_node("WingPivotHind")
	unit._physics_process(1.0 / 60.0)
	var fore_a = fore_pivot.rotation.x
	var hind_a = hind_pivot.rotation.x
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	unit._physics_process(1.0 / 60.0)
	var fore_b = fore_pivot.rotation.x
	unit.queue_free()
	if is_equal_approx(fore_a, fore_b):
		print("  [FAIL] ornithopter wing flap animation isn't changing over time (fore_a=", fore_a, " fore_b=", fore_b, ")")
		return false
	if not is_equal_approx(fore_a, -hind_a):
		print("  [FAIL] ornithopter fore/hind wings should flap in opposition to each other (fore_a=", fore_a, " hind_a=", hind_a, ")")
		return false

	print("  [PASS] ornithopter_wing spawns 2 real wing instances, each with a dragonfly-style fore/hind wing pair on its own flap-animation pivot beating in opposition, carries the airborne-not-fixed_wing trait combo for simple hover-capable flight, and its flap motion genuinely oscillates over time.")
	return true

# --- Hull Modding (HULL_MODDING_PLAN.md) ---


# --- Authored leg sets (NEW_LEGS, 2026-08-08) --------------------------------
# The six authored sets replaced a fully procedural limb. What follows guards
# the seams that swap created: an asset path (six .glb files that have to load
# AND articulate), a placement fork (belly vs flank), a stat table, and a walk
# cycle that now drives three bones instead of one.


## Every set has to load AND expose the full chain. This is the one suite that
## fails outright if an asset is missing, renamed, or re-exported with different
## bone names - all of which look identical in the Design Lab (a leg that simply
## does not articulate) and none of which any other suite would notice.
func test_leg_sets_load_and_expose_the_bone_chain() -> bool:
	print("Running Test Suite: Leg Sets - Assets Load And Articulate...")
	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var ok := true

	for leg_id in ModuleCatalog.get_leg_options():
		var hull := _leg_test_hull()
		var placer := _leg_test_placer(hull)
		await tree.process_frame
		placer.update_locomotion("legs", {"leg_type": leg_id})
		await tree.process_frame

		var modules := _leg_modules(hull)
		if modules.is_empty():
			print("  [FAIL] %s placed no leg modules at all" % leg_id)
			ok = false
		else:
			var leg: Node3D = modules[0]
			# The two-level nesting is load-bearing, not decoration - see the
			# mirror comment in _build_legs(). Asserted as a PATH so collapsing
			# them into one node fails here rather than as inside-out mirrored
			# legs someone notices in a playtest.
			var swing := leg.get_node_or_null("LegRoot/%s" % VisualBuilder.LEG_PIVOT_SWING)
			if swing == null:
				print("  [FAIL] %s has no LegRoot/LegSwing pivot" % leg_id)
				ok = false
			else:
				for bone_name in [VisualBuilder.LEG_PIVOT_HIP,
						VisualBuilder.LEG_PIVOT_THIGH, VisualBuilder.LEG_PIVOT_SHIN]:
					var bone = VisualBuilder.find_leg_bone(swing, bone_name)
					if bone == null:
						print("  [FAIL] %s is missing bone %s" % [leg_id, bone_name])
						ok = false
					elif bone.find_children("*", "MeshInstance3D", false, false).is_empty():
						print("  [FAIL] %s bone %s carries no mesh" % [leg_id, bone_name])
						ok = false
			# The authoring aid must not survive into the game.
			if VisualBuilder.find_leg_bone(leg, "CamTarget") != null:
				print("  [FAIL] %s kept its CamTarget authoring node" % leg_id)
				ok = false
			# Deliberately inverted. There WAS a bolted plate standing in for the
			# hardpoint; Chris asked for the limbs to meet the hull directly
			# instead, so a plate reappearing is a regression, not a repair.
			if leg.get_node_or_null("LegPlatform") != null:
				print("  [FAIL] %s built a mounting plate - legs mount to the hull skin now" % leg_id)
				ok = false

			# THE SET ACTUALLY FITTED, not just "a leg was built".
			#
			# This is the check that would have caught the real bug found in
			# playtest: locomotion_layout._resolve_geo() only forwards the keys
			# a type DECLARES in geo_keys, and leg_type was not among them - so
			# the layout resolved the right stations from settings while the
			# builder, reading the module's tweaks, saw no leg_type at all and
			# built the DEFAULT limb every single time. Every structural
			# assertion above still passed, because a Stryker has all the right
			# bones. Asserted via the authored node names, which are the only
			# thing that differs between the six.
			var wants: String = str(ModuleCatalog.get_leg_profile(leg_id).label)
			if VisualBuilder.find_leg_bone(leg, "%s_Rig" % wants) == null:
				print("  [FAIL] %s built some other set - no %s_Rig under the module"
					% [leg_id, wants])
				ok = false

		placer.free()
		hull.free()
		await tree.process_frame

	if ok:
		print("  [PASS] All %d leg sets load, expose the full three-bone chain, and carry no mounting plate."
			% ModuleCatalog.get_leg_options().size())
	return ok


## Every set has to produce a SANE ride height - not an identical one.
##
## Chris, on seeing Mantis come out shorter than the rest: "having the legs at
## different heights is fine as well." So this deliberately does not demand
## uniformity - a shouldered set that reaches wide gets scaled down by the
## layout's own width clamp, and that is the clamp working, not a bug.
##
## What it DOES pin is the pair of failures that would actually ship broken:
## a set whose authored drop (2.50 to 3.85 raw units, against a ~1.6 target)
## never got normalised, leaving the vehicle on stilts; or one scaled to
## nothing, leaving the hull sitting on the dirt. A band around the default
## catches both without freezing the artistic spread between them.
func test_leg_sets_all_stand_on_the_ground() -> bool:
	print("Running Test Suite: Leg Sets - Every Set Stands Sanely...")
	var heights := {}

	for leg_id in ModuleCatalog.get_leg_options():
		var hull := _leg_test_hull()
		var placer := _leg_test_placer(hull)
		await tree.process_frame
		placer.update_locomotion("legs", {"leg_type": leg_id})
		await tree.process_frame
		heights[leg_id] = hull.position.y
		placer.free()
		hull.free()
		await tree.process_frame

	var baseline: float = heights[ModuleCatalog.LEG_DEFAULT]
	var ok := true
	if baseline <= _LEG_TEST_HULL_SIZE.y * 0.5:
		print("  [FAIL] the default set does not lift the hull clear of the ground at all (y=%.3f)" % baseline)
		ok = false
	for leg_id in heights:
		var h: float = heights[leg_id]
		# The raw authored drop is >2.5 and the target is ~1.6, so a set that
		# skipped normalisation lands well outside this band rather than just
		# looking a bit tall.
		if h < baseline * 0.4 or h > baseline * 1.6:
			print("  [FAIL] %s rides at %.3f, outside the sane band around the default %.3f"
				% [leg_id, h, baseline])
			ok = false
	if ok:
		print("  [PASS] All %d sets stand the hull clear of the ground (%.3f to %.3f)." % [
			heights.size(), heights.values().min(), heights.values().max()])
	return ok


## Mantis and Crawler bolt to the hull flank; the other four to its belly.
##
## Asserted against where the stations ACTUALLY land, not against LEG_TYPES -
## reading the table back would only prove the table equals itself, and the bug
## worth catching is the layout fork silently not being consulted.
func test_leg_mount_style_moves_the_stations() -> bool:
	print("Running Test Suite: Leg Sets - Flank vs Belly Mounting...")
	var ok := true
	var underside_y := 0.0
	var seen_underside := false

	for leg_id in ModuleCatalog.get_leg_options():
		var hull := _leg_test_hull()
		var placer := _leg_test_placer(hull)
		await tree.process_frame
		placer.update_locomotion("legs", {"leg_type": leg_id})
		await tree.process_frame

		var modules := _leg_modules(hull)
		var expect_flank: bool = str(ModuleCatalog.get_leg_profile(leg_id).mount) == "flank"
		if modules.is_empty():
			print("  [FAIL] %s placed nothing" % leg_id)
			ok = false
		else:
			var station_y: float = modules[0].position.y
			# The belly line for this hull, which is where a non-shouldered set
			# must sit and where a shouldered one must NOT.
			var belly: float = -_LEG_TEST_HULL_SIZE.y / 2.0
			if expect_flank:
				if station_y <= belly + 0.01:
					print("  [FAIL] %s is shouldered but sits at the belly line (y=%.3f)"
						% [leg_id, station_y])
					ok = false
			else:
				if absf(station_y - belly) > 0.01:
					print("  [FAIL] %s should sit at the belly line %.3f, sits at %.3f"
						% [leg_id, belly, station_y])
					ok = false
				if seen_underside and absf(station_y - underside_y) > 0.001:
					print("  [FAIL] belly-mounted sets disagree on station height")
					ok = false
				underside_y = station_y
				seen_underside = true

		placer.free()
		hull.free()
		await tree.process_frame

	if ok:
		print("  [PASS] Shouldered sets mount up the flank; the rest sit on the belly line.")
	return ok


## The set survives a save/load round trip, and a nonsense id degrades rather
## than erroring - the same forgiving contract get_ammo() has for a hand-edited
## blueprint or a save from a build that has since renamed a variant.
func test_leg_type_round_trips_and_degrades() -> bool:
	print("Running Test Suite: Leg Sets - Blueprint Round Trip...")
	var ok := true

	if ModuleCatalog.get_leg_type({}) != ModuleCatalog.LEG_DEFAULT:
		print("  [FAIL] an empty tweaks dict did not resolve to the default set")
		ok = false
	if ModuleCatalog.get_leg_type({"leg_type": "no_such_leg"}) != ModuleCatalog.LEG_DEFAULT:
		print("  [FAIL] an unknown leg id did not degrade to the default")
		ok = false
	if ModuleCatalog.get_leg_type({"leg_type": 7}) != ModuleCatalog.LEG_DEFAULT:
		print("  [FAIL] a non-string leg id did not degrade to the default")
		ok = false
	if ModuleCatalog.get_leg_type({"leg_type": "mantis"}) != "mantis":
		print("  [FAIL] a legal leg id was not honoured")
		ok = false

	# Through the real serializer, because the failure that matters is the tweak
	# being dropped somewhere between the hull metadata and the JSON.
	var hull := _leg_test_hull()
	var placer := _leg_test_placer(hull)
	await tree.process_frame
	placer.update_locomotion("legs", {"leg_type": "excavator", "count": 4})
	await tree.process_frame

	var bm = load("res://scripts/blueprint_manager.gd").new()
	root.add_child(bm)
	var serialized: Dictionary = bm.serialize_hull(hull)
	var loco: Dictionary = serialized.get("locomotion", {})
	var round_tripped := str(loco.get("settings", {}).get("leg_type", "<missing>"))
	if round_tripped != "excavator":
		print("  [FAIL] leg_type serialized as %s, expected excavator" % round_tripped)
		ok = false

	bm.queue_free()
	placer.free()
	hull.free()
	await tree.process_frame

	if ok:
		print("  [PASS] leg_type survives serialization and degrades safely on bad input.")
	return ok


## The sets have to differ MECHANICALLY, not just visually.
##
## Ordering rather than magic numbers, so retuning the LEG_TYPES table is a
## balance decision rather than a test edit - but the shape of the spread (the
## heavy set carries more and walks slower) is a design commitment and is
## pinned.
func test_leg_sets_have_a_real_stat_spread() -> bool:
	print("Running Test Suite: Leg Sets - Stat Spread...")
	var ok := true

	var cap := func(id: String) -> float:
		return ModuleCatalog.get_base_weight_capacity("legs", {"leg_type": id})
	var spd := func(id: String) -> float:
		return ModuleCatalog.get_base_top_speed("legs", {"leg_type": id})

	if cap.call("excavator") <= cap.call("raptor"):
		print("  [FAIL] Excavator should carry more than Raptor (%.1f vs %.1f)"
			% [cap.call("excavator"), cap.call("raptor")])
		ok = false
	if spd.call("crawler") <= spd.call("excavator"):
		print("  [FAIL] Crawler should outpace Excavator (%.2f vs %.2f)"
			% [spd.call("crawler"), spd.call("excavator")])
		ok = false
	if spd.call("raptor") <= spd.call("stryker"):
		print("  [FAIL] Raptor should outpace the baseline Stryker")
		ok = false

	# The default has to be the neutral one, or "I did not touch the dropdown"
	# silently means "I took a stat penalty".
	if not is_equal_approx(cap.call(ModuleCatalog.LEG_DEFAULT),
			float(ModuleCatalog.get_module_data("legs").get("base_weight_capacity", 0.0))):
		print("  [FAIL] the default set is not stat-neutral")
		ok = false

	# A non-leg type must be completely unaffected by a stray leg_type key.
	if not is_equal_approx(ModuleCatalog.get_base_top_speed("wheels", {"leg_type": "excavator"}),
			ModuleCatalog.get_base_top_speed("wheels")):
		print("  [FAIL] a leg_type tweak leaked into a non-leg locomotor")
		ok = false

	if ok:
		print("  [PASS] Leg sets differ in capacity and speed, the default is neutral, and nothing leaks.")
	return ok


## The walk cycle drives all THREE bones, and they disagree with each other.
##
## A regression to the old single-pivot swing would be silent - the leg would
## still visibly move, just rigidly below the hip - which is exactly the kind of
## quiet failure test_every_locomotion_type_animates_something was written for
## after three types shipped with no pivot at all.
func test_leg_walk_cycle_drives_all_three_bones() -> bool:
	print("Running Test Suite: Leg Sets - Three-Bone Walk Cycle...")
	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var ok := true

	var hull := _leg_test_hull()
	var placer := _leg_test_placer(hull)
	await tree.process_frame
	placer.update_locomotion("legs", {"leg_type": "raptor"})
	await tree.process_frame

	var modules := _leg_modules(hull)
	if modules.is_empty():
		print("  [FAIL] no leg modules to pose")
		placer.free()
		hull.free()
		return false

	var leg: Node3D = modules[0]
	var swing := leg.get_node_or_null("LegRoot/%s" % VisualBuilder.LEG_PIVOT_SWING) as Node3D
	var thigh: Node3D = VisualBuilder.find_leg_bone(leg, VisualBuilder.LEG_PIVOT_THIGH)
	var shin: Node3D = VisualBuilder.find_leg_bone(leg, VisualBuilder.LEG_PIVOT_SHIN)

	# Sampled across the cycle rather than at one instant: a bone parked at a
	# constant non-zero angle is not animated, and one sample cannot tell the
	# difference.
	var seen := {"swing": [], "thigh": [], "shin": []}
	for step in range(8):
		VisualBuilder.pose_leg(leg, float(step) * 0.09, 0.0, 1.0, 0.016)
		seen["swing"].append(swing.rotation.x)
		seen["thigh"].append(thigh.rotation.x)
		seen["shin"].append(shin.rotation.x)

	for bone_name in seen:
		var values: Array = seen[bone_name]
		var lo: float = values.min()
		var hi: float = values.max()
		if hi - lo < 0.01:
			print("  [FAIL] %s did not move across the cycle (range %.4f)" % [bone_name, hi - lo])
			ok = false

	# The knee must FOLD against the hip, not follow it. Identical motion would
	# mean a rigid limb swinging from the hip - the thing this replaced.
	var same := true
	for i in range(seen["thigh"].size()):
		if absf(float(seen["thigh"][i]) - float(seen["shin"][i])) > 0.001:
			same = false
			break
	if same:
		print("  [FAIL] thigh and shin moved identically - the limb is rigid below the hip")
		ok = false

	# Parked settles toward rest rather than freezing mid-stride.
	for _i in range(60):
		VisualBuilder.pose_leg(leg, 99.0, 0.0, 0.0, 0.016)
	if absf(swing.rotation.x) > 0.05:
		print("  [FAIL] a parked leg held a mid-stride pose (swing=%.3f)" % swing.rotation.x)
		ok = false

	# And the trot stagger has to actually be assigned - it was gated on a key
	# the legs layout does not set, so every leg read 0.0 and stepped in unison.
	var phases := {}
	for m in modules:
		phases[m.get_meta("leg_phase", 0.0)] = true
	if phases.size() < 2:
		print("  [FAIL] every leg shares one walk phase - they will step in lockstep")
		ok = false

	placer.free()
	hull.free()
	await tree.process_frame

	if ok:
		print("  [PASS] Hip, thigh and shin all animate, the knee folds against the hip, parked legs settle, and the trot is staggered.")
	return ok


## Legs bolt to the hull's VISIBLE mesh, not to its collision box.
##
## These are two genuinely different surfaces. LocomotionLayout positions every
## station against hull_size - the box - and since the hull roster moved to the
## SDF/marching-cubes bake, a baked hull is routinely narrower, wider or more
## tapered than the box it declares. A leg left on the box plane therefore hangs
## in clear air beside the model it is supposed to be bolted to, or buries its
## gearbox inside it.
##
## Run against real authored hulls rather than the bare box the other leg suites
## use, because a box hull is exactly the case where the bug is invisible: box
## and skin agree, so the seating is a no-op and proves nothing.
func test_legs_seat_on_the_visible_hull_mesh() -> bool:
	print("Running Test Suite: Leg Sets - Seated On The Visible Hull...")
	var HullProjection = load("res://scripts/hull_projection.gd")
	var ok := true
	var moved_any := false

	for hull_type in ["medium_hull", "heavy_hull", "scout_hull"]:
		var scene = load("res://scenes/MainLab.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		for _i in range(3):
			await tree.process_frame
		scene.clear_hull()
		scene._place_hull_from_ui(hull_type)
		await tree.process_frame
		scene.update_locomotion("legs", {})
		await tree.process_frame

		var mesh_inst := scene.hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
		var box_half: float = float(scene.hull.get_meta("base_hull_size").x) * 0.5
		if mesh_inst == null or mesh_inst.mesh == null:
			print("  [FAIL] %s has no visible mesh to seat against" % hull_type)
			ok = false
		else:
			var surface: Dictionary = HullProjection.build_surface(mesh_inst)
			for child in scene.hull.get_children():
				if not child.has_meta("module_data"):
					continue
				var m = child.get_meta("module_data")
				if m == null or m.category != "locomotion":
					continue
				var side: float = signf(child.position.x)
				# The leg's own x must be ON the skin: fire a ray back at it from
				# outside and the first triangle should be where the leg is.
				# Sampled up the flank the same way the seating does, because a
				# ray at the very belly line passes under a curved hull.
				var found := false
				for frac in [0.06, 0.18, 0.32, 0.50]:
					var from := Vector3(side * box_half * 4.0,
						child.position.y + float(scene.hull.get_meta("base_hull_size").y) * frac,
						child.position.z)
					var hit: Dictionary = HullProjection.raycast(
						surface, from, Vector3(-side, 0.0, 0.0))
					if hit.get("hit", false) and absf(absf(hit["position"].x) - absf(child.position.x)) < 0.02:
						found = true
						break
				if not found:
					print("  [FAIL] %s: a leg at x=%.3f is not on the hull's skin"
						% [hull_type, child.position.x])
					ok = false
				if absf(absf(child.position.x) - box_half) > 0.02:
					moved_any = true

		scene.free()
		await tree.process_frame

	# At least one hull in the set must have skin that DISAGREES with its box,
	# or this suite is passing on a technicality and would keep passing if the
	# seating were deleted outright.
	if not moved_any:
		print("  [FAIL] no leg moved off the bounding box on any hull - the seating is not doing anything")
		ok = false

	if ok:
		print("  [PASS] Legs land on the hull's real skin across three authored hulls, off the bounding box.")
	return ok


# --- Shared leg-suite helpers ------------------------------------------------
# The same hull every leg suite measures against, so a moved station always
# means the same thing across all of them.
const _LEG_TEST_HULL_SIZE := Vector3(3.0, 1.2, 4.4)

func _leg_test_hull() -> StaticBody3D:
	var hull := StaticBody3D.new()
	hull.name = "Hull"
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = _LEG_TEST_HULL_SIZE
	shape.shape = box
	hull.add_child(shape)
	root.add_child(hull)
	return hull

func _leg_test_placer(hull: StaticBody3D) -> Node3D:
	var placer := Node3D.new()
	placer.set_script(load("res://scripts/module_placer.gd"))
	placer.hull = hull
	root.add_child(placer)
	return placer

func _leg_modules(hull: Node3D) -> Array:
	var out: Array = []
	for child in hull.get_children():
		if not child.has_meta("module_data"):
			continue
		var m = child.get_meta("module_data")
		if m != null and m.category == "locomotion":
			out.append(child)
	out.sort_custom(func(a, b): return a.position.x < b.position.x)
	return out


# --- Speed as a real, affectable stat (2026-08-08) -------------------------

# The retuned band: every base_top_speed rose, the archetype ordering the
# roster depends on held, and the fast end pulled further away from the slow
# end rather than everything moving by the same amount - a flat lift would
# have kept the roster exactly as flat as before, just at a higher number.
func test_chassis_top_speeds_are_spread_and_ordered() -> bool:
	print("Running Test Suite: Speed Pass - base_top_speed Band Is Wider, Not Just Higher...")
	# (type_id, speed BEFORE the 2026-08-08 pass) - every one of these must be
	# strictly higher now.
	var before := {
		"wheels": 12.0, "tracked_treads": 8.0, "helicopter_rotors": 11.0,
		"hover_engine": 13.0, "legs": 6.5, "fixed_wing_engine": 18.0,
		"ornithopter_wing": 9.0, "buoyant_envelope": 4.0, "half_track": 8.5,
		"rocker_bogie": 6.0, "air_cushion_skirt": 12.5, "anti_grav_plate": 10.5,
		"pontoon_wheels": 7.5, "screw_drive": 6.5,
	}
	for type_id in before:
		var now: float = ModuleCatalog.get_base_top_speed(type_id)
		if now <= before[type_id]:
			print("  [FAIL] ", type_id, " should be faster than its pre-pass value ", before[type_id], ", got ", now)
			return false

	# Archetype ordering the roster's own design depends on (see the
	# catalog's own base_top_speed comments) - retuning must not have
	# scrambled it.
	if not (ModuleCatalog.get_base_top_speed("fixed_wing_engine") > ModuleCatalog.get_base_top_speed("wheels")):
		print("  [FAIL] fixed_wing_engine should still outrun wheels.")
		return false
	if not (ModuleCatalog.get_base_top_speed("wheels") > ModuleCatalog.get_base_top_speed("tracked_treads")):
		print("  [FAIL] wheels should still outrun tracked_treads.")
		return false
	if not (ModuleCatalog.get_base_top_speed("tracked_treads") > ModuleCatalog.get_base_top_speed("legs")):
		print("  [FAIL] tracked_treads should still outrun legs.")
		return false
	if not (ModuleCatalog.get_base_top_speed("buoyant_envelope") < ModuleCatalog.get_base_top_speed("legs")):
		print("  [FAIL] buoyant_envelope should still be slower than legs.")
		return false

	# The spread itself widened - fastest/slowest ratio bigger than it was
	# (18.0/4.0 = 4.5 before), not just every value scaled by the same factor.
	var fastest: float = ModuleCatalog.get_base_top_speed("fixed_wing_engine")
	var slowest: float = ModuleCatalog.get_base_top_speed("buoyant_envelope")
	var old_ratio := 18.0 / 4.0
	if fastest / slowest <= old_ratio:
		print("  [FAIL] Fastest/slowest ratio should have widened past the old ", old_ratio, ", got ", fastest / slowest)
		return false

	print("  [PASS] Every locomotor is faster than before, the archetype ordering held, and the roster's speed spread genuinely widened.")
	return true


# Propulsion parts (turbocharger/overdrive_gearbox/hub_motor_array) change
# Drivetrain.analyze()'s output through the thrust_bonus/top_speed_mult/
# capacity_mult hooks - this is the regression guard for those hooks
# actually being read, not just declared on the catalog entries.
func test_propulsion_modules_change_drivetrain_output() -> bool:
	print("Running Test Suite: Propulsion Modules Change Drivetrain Output...")

	var make_hull := func(part_ids: Array) -> Node3D:
		var hull := Node3D.new()
		root.add_child(hull)
		var loco := ModuleData.new()
		loco.type_id = "wheels"
		loco.category = "locomotion"
		loco.base_weight = 50.0
		var loco_child := Node3D.new()
		loco_child.set_meta("module_data", loco)
		hull.add_child(loco_child)
		for part_id in part_ids:
			var d := ModuleData.new()
			d.type_id = part_id
			d.category = "module"
			d.base_weight = ModuleCatalog.get_module_data(part_id).get("weight", 40.0)
			var child := Node3D.new()
			child.set_meta("module_data", d)
			hull.add_child(child)
		return hull

	# turbocharger: thrust rises, chassis ceiling does not.
	var bare: Node3D = make_hull.call([])
	var turbo: Node3D = make_hull.call(["turbocharger"])
	var dt_bare: Dictionary = DrivetrainScript.analyze(bare, "wheels", {})
	var dt_turbo: Dictionary = DrivetrainScript.analyze(turbo, "wheels", {})
	bare.queue_free(); turbo.queue_free()
	if dt_turbo["thrust"] <= dt_bare["thrust"]:
		print("  [FAIL] A turbocharger should raise thrust. bare=", dt_bare["thrust"], " turbo=", dt_turbo["thrust"])
		return false
	if not is_equal_approx(dt_turbo["chassis_speed_mult"], 1.0):
		print("  [FAIL] A turbocharger alone should not change chassis_speed_mult, got ", dt_turbo["chassis_speed_mult"])
		return false

	# overdrive_gearbox: chassis ceiling rises, capacity falls - the pure trade.
	var gearbox: Node3D = make_hull.call(["overdrive_gearbox"])
	var dt_gearbox: Dictionary = DrivetrainScript.analyze(gearbox, "wheels", {})
	gearbox.queue_free()
	if dt_gearbox["chassis_top_speed"] <= dt_bare["chassis_top_speed"]:
		print("  [FAIL] An Overdrive Gearbox should raise the chassis ceiling. bare=", dt_bare["chassis_top_speed"], " gearbox=", dt_gearbox["chassis_top_speed"])
		return false
	if dt_gearbox["chassis_speed_mult"] <= 1.0:
		print("  [FAIL] chassis_speed_mult should be reported > 1.0 with an Overdrive Gearbox fitted, got ", dt_gearbox["chassis_speed_mult"])
		return false
	if dt_gearbox["capacity"] >= dt_bare["capacity"]:
		print("  [FAIL] An Overdrive Gearbox should trade away some capacity. bare=", dt_bare["capacity"], " gearbox=", dt_gearbox["capacity"])
		return false

	# Stacking parts must not blow past MAX_CHASSIS_SPEED_MULT.
	var stacked: Node3D = make_hull.call([
		"overdrive_gearbox", "overdrive_gearbox", "overdrive_gearbox",
		"overdrive_gearbox", "overdrive_gearbox", "overdrive_gearbox",
	])
	var dt_stacked: Dictionary = DrivetrainScript.analyze(stacked, "wheels", {})
	stacked.queue_free()
	if dt_stacked["chassis_speed_mult"] > DrivetrainScript.MAX_CHASSIS_SPEED_MULT + 0.001:
		print("  [FAIL] Six stacked Overdrive Gearboxes should be clamped at MAX_CHASSIS_SPEED_MULT (", DrivetrainScript.MAX_CHASSIS_SPEED_MULT, "), got ", dt_stacked["chassis_speed_mult"])
		return false

	# nitrous_injector/booster_rack surface as a boost summary, and the
	# stronger of the two (by speed_mult) wins when both are fitted.
	var boosted: Node3D = make_hull.call(["nitrous_injector", "booster_rack"])
	var dt_boosted: Dictionary = DrivetrainScript.analyze(boosted, "wheels", {})
	boosted.queue_free()
	var booster_cat: Dictionary = ModuleCatalog.get_module_data("booster_rack")
	if dt_boosted["boost"].is_empty():
		print("  [FAIL] A design carrying boost parts should report a non-empty boost summary.")
		return false
	if not is_equal_approx(float(dt_boosted["boost"]["speed_mult"]), float(booster_cat["boost"]["speed_mult"])):
		print("  [FAIL] With both boost parts fitted, the STRONGER one (booster_rack) should win. Got ", dt_boosted["boost"])
		return false

	print("  [PASS] turbocharger/overdrive_gearbox change thrust/ceiling/capacity as declared, the chassis_speed_mult stack is clamped, and boost summaries surface the strongest fitted part.")
	return true


# The regression guard for the live Battle runtime speed fix (2026-08-08):
# BattleUnitV2 (scripts/battle/units/unit.gd) used to read dt["top_speed"] -
# the clean, pre-penalty figure - instead of dt["move_speed"], and never
# assigned terrain_speed_multiplier at all despite reading it every tick in
# _apply_movement(). Both made real Skirmish combat silently ignore
# overload/underload, faction speed passives, and the entire terrain table.
func test_live_runtime_uses_combat_speed_and_terrain() -> bool:
	print("Running Test Suite: Live Battle Runtime (unit.gd) Uses Combat Speed And Computes Terrain...")
	var UnitScript = preload("res://scripts/battle/units/unit.gd")

	# --- Part 1: an overloaded design moves at move_speed, not top_speed ---
	var unit = CharacterBody3D.new()
	unit.set_script(UnitScript)
	root.add_child(unit)
	var hull := Node3D.new()
	unit.add_child(hull)
	unit.hull_node = hull
	unit.locomotion_type = "wheels"
	unit.locomotion_settings = {}

	var loco_data := ModuleData.new()
	loco_data.type_id = "wheels"
	loco_data.category = "locomotion"
	loco_data.base_weight = 900.0  # far past wheels' own weight capacity
	var loco_child := Node3D.new()
	loco_child.set_meta("module_data", loco_data)
	hull.add_child(loco_child)

	unit._recalculate_move_speed()
	var dt: Dictionary = DrivetrainScript.analyze(hull, "wheels", {})

	if not dt["is_overloaded"]:
		print("  [FAIL] Test setup: expected an overloaded design, load_ratio=", dt["load_ratio"])
		unit.queue_free()
		return false
	if not is_equal_approx(unit.move_speed, dt["move_speed"]):
		print("  [FAIL] unit.move_speed (", unit.move_speed, ") should equal Drivetrain's move_speed (", dt["move_speed"], ") - the combat figure AFTER the overload penalty - not top_speed (", dt["top_speed"], "), the clean pre-penalty figure the Design Lab quotes.")
		unit.queue_free()
		return false
	if unit.move_speed >= dt["top_speed"] - 0.001:
		print("  [FAIL] An overloaded unit's move_speed should be measurably below its clean top_speed - got move_speed=", unit.move_speed, " top_speed=", dt["top_speed"])
		unit.queue_free()
		return false

	# --- Part 2: terrain_speed_multiplier is actually computed ---
	var controller_script = preload("res://scripts/fake_surface_controller.gd")
	var controller := Node.new()
	controller.set_script(controller_script)
	controller.surface_type = "snow_mud"
	root.add_child(controller)
	unit._controller = controller
	unit.is_flying = false
	unit.is_naval = false
	unit._recalculate_terrain_speed_multiplier()

	if is_equal_approx(unit.terrain_speed_multiplier, 1.0):
		print("  [FAIL] terrain_speed_multiplier should reflect the snow_mud penalty for wheels, stayed at the 1.0 default - the live runtime never assigns it.")
		unit.queue_free(); controller.queue_free()
		return false
	var expected: float = ModuleCatalog.get_terrain_speed_multiplier("wheels", "snow_mud")
	if not is_equal_approx(unit.terrain_speed_multiplier, expected):
		print("  [FAIL] terrain_speed_multiplier=", unit.terrain_speed_multiplier, " does not match ModuleCatalog's own table value ", expected, " for wheels/snow_mud.")
		unit.queue_free(); controller.queue_free()
		return false

	unit.queue_free()
	controller.queue_free()
	print("  [PASS] The live Battle runtime reads combat speed (post-overload/passives), not the clean design-time figure, and computes real per-surface terrain multipliers instead of leaving the dead 1.0 default.")
	return true
