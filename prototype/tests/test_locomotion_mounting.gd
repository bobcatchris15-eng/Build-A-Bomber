extends "res://tests/suite_base.gd"
# Locomotion mounting suites. Registration order lives in run_tests.gd's
# SUITE_ORDER, not here.
#
# These replace GOLDEN_LOCOMOTION_LAYOUT, the frozen table of exact station
# coordinates that used to live in suite_base.gd. See the note left in its place
# for why it went: it had no live consumer, and what it froze - positions derived
# from the hull's fitted collision BOX - is exactly the behaviour this pass
# removed, so pinning those numbers would have pinned the bug.
#
# What is asserted here instead are PROPERTIES of the mount, which is both what
# actually matters and what a coordinate table could never express:
#
#   - the mount point lies on the hull's real mesh, not near it
#   - it is at the turn of the bilge, not up the flank or under the keel
#   - a continuous belt clears the hull's belly and flank instead
#   - running gear stands clear of the hull body rather than tucking into it
#   - only ground-contact and hovering types get seated; airborne ones do not
#   - a hull carries exactly one locomotion chassis
#
# They are hull-shape-independent, so they keep holding when a hull is rebaked -
# which the coordinate fixture explicitly did not.

const HullChineScript = preload("res://scripts/hull_chine.gd")
const LocomotionMountScript = preload("res://scripts/locomotion_mount.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")

## Hulls chosen to span the shapes that broke the old box-based placement:
## a slab-sided box (the control), a tumblehome flank, a tapered keel, and a
## foundation, which is vertical-walled and much taller than it is wide.
const SHAPE_SAMPLE := [
	"brenntal_medium_a",
	"orrin_medium_a",
	"halvorsen_medium_a",
	"bunker_main_meridian",
]

## Types that must seat to the chine, one per mounting convention:
## build_wheel_mount (wheels), the track frame (tracked_treads), the authored
## hip (legs) and the generic kit (hover_engine).
const SEATED_SAMPLE := ["wheels", "tracked_treads", "legs", "hover_engine"]

## Types that must NOT be dragged down to the chine - they mount above or around
## the hull, and seating them would bury a rotor in the deck.
const UNSEATED_SAMPLE := ["helicopter_rotors", "fixed_wing_engine", "buoyant_envelope"]

const ON_SKIN_FRAC := 0.02


func _make_lab() -> Node3D:
	var placer := Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm := Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	return placer


func _locomotion_children(hull: Node3D) -> Array:
	var out: Array = []
	for c in hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").category == "locomotion":
			out.append(c)
	return out


## Every seated locomotion station sits on the hull's actual mesh.
##
## This is the whole point of the pass, stated as directly as it can be. Before
## chine seating, a station was the bounding box's lower corner, which across the
## roster sat a mean of 0.335 units - max 2.09 - from the hull's real lower edge.
## That distance was the visible gap.
func test_seated_stations_lie_on_the_hull_mesh() -> bool:
	print("Running Test Suite: Locomotion stations are seated on the hull mesh...")
	var ok := true
	var placer := _make_lab()
	await tree.process_frame

	for hull_id in SHAPE_SAMPLE:
		for type_id in SEATED_SAMPLE:
			placer._place_hull_from_ui(hull_id)
			await tree.process_frame
			placer.update_locomotion(type_id,
				placer.default_locomotion_settings[type_id].duplicate())
			await tree.process_frame

			var hull: Node3D = placer.hull
			var mesh_inst := hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
			if mesh_inst == null or mesh_inst.mesh == null:
				print("  [FAIL] %s has no hull mesh to seat against." % hull_id)
				ok = false
				continue
			var profile: Dictionary = HullChineScript.build(mesh_inst)
			var diag: float = (profile["aabb"] as AABB).size.length()

			var parts := _locomotion_children(hull)
			if parts.is_empty():
				print("  [FAIL] %s / %s placed no locomotion at all." % [hull_id, type_id])
				ok = false
				continue

			for part in parts:
				if absf(part.position.x) <= LocomotionMountScript.CENTRELINE_EPS:
					continue  # centreline mount, no flank to seat against
				if not bool(part.get_meta("chine_seated", false)):
					print("  [FAIL] %s / %s: station at %.2f was never seated."
						% [hull_id, type_id, part.position.x])
					ok = false
					continue
				var frame: Dictionary = HullChineScript.mount_frame(
					profile, part.position.z, signf(part.position.x))
				var chine: Vector3 = frame["position"]

				if type_id in LocomotionMountScript.BELT_TYPES:
					# A belt is deliberately NOT on the chine - it has to clear the
					# belly to reach the ground and the flank to keep its sprockets
					# out of the hull side. What it must do is sit strictly outboard
					# of the hull's widest point and strictly below its lowest, and
					# that is what is checked instead of proximity.
					var lowest: float = chine.y - float(frame["belly_drop"])
					if absf(part.position.x) <= float(frame["half_width"]):
						print("  [FAIL] %s / %s: belt at x=%.3f is inside half-width %.3f."
							% [hull_id, type_id, absf(part.position.x), frame["half_width"]])
						ok = false
					if part.position.y >= lowest:
						print("  [FAIL] %s / %s: belt at y=%.3f is not below hull bottom %.3f."
							% [hull_id, type_id, part.position.y, lowest])
						ok = false
					continue

				var drift: float = Vector2(
					part.position.x - chine.x, part.position.y - chine.y).length()
				if drift > diag * ON_SKIN_FRAC:
					print("  [FAIL] %s / %s: station %.3f off the solved chine."
						% [hull_id, type_id, drift])
					ok = false
	placer.queue_free()
	if ok:
		print("  [PASS] Every seated station across %d hulls x %d types lands on the mesh."
			% [SHAPE_SAMPLE.size(), SEATED_SAMPLE.size()])
	return ok


## Running gear stands clear of the hull body.
##
## Chris, 2026-08-12: "The wheels are too close to the hull body." Seating removed
## the accidental clearance the old bounding-box placement had been providing -
## the box corner sat outboard of the mesh, so the error itself was holding the
## wheels off the body. Clearance is now requested explicitly via
## chine_standoff(), and this pins it so it cannot silently collapse again.
func test_running_gear_stands_clear_of_the_hull() -> bool:
	print("Running Test Suite: Running gear stands off the hull body...")
	var ok := true
	var placer := _make_lab()
	await tree.process_frame
	var checked := 0

	for hull_id in SHAPE_SAMPLE:
		placer._place_hull_from_ui(hull_id)
		await tree.process_frame
		placer.update_locomotion("wheels",
			placer.default_locomotion_settings["wheels"].duplicate())
		await tree.process_frame

		var hull: Node3D = placer.hull
		var mesh_inst := hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh_inst == null or mesh_inst.mesh == null:
			continue
		var profile: Dictionary = HullChineScript.build(mesh_inst)

		for part in _locomotion_children(hull):
			var side: float = signf(part.position.x)
			if is_zero_approx(side):
				continue
			var pivot := part.get_node_or_null("WheelSpin") as Node3D
			if pivot == null:
				continue
			checked += 1
			# The wheel's own outboard offset, in hull space, has to clear the
			# widest the hull gets at this station - otherwise the tyre is
			# intersecting or grazing the body.
			var wheel_x: float = absf((hull.global_transform.affine_inverse()
				* pivot.global_transform).origin.x)
			var frame: Dictionary = HullChineScript.mount_frame(
				profile, part.position.z, side)
			var hull_half: float = frame["half_width"]
			if wheel_x <= hull_half:
				print("  [FAIL] %s: wheel at %.3f is inside the hull's %.3f half-width."
					% [hull_id, wheel_x, hull_half])
				ok = false
	placer.queue_free()
	if checked == 0:
		print("  [FAIL] No wheel pivots found - cannot verify standoff.")
		return false
	if ok:
		print("  [PASS] %d wheels all sit outboard of their hull's widest point." % checked)
	return ok


## Ground and hovering types seat; airborne types are left where the layout put
## them.
##
## The split is trait-derived (ModuleCatalog.locomotion_touches_ground), not a
## hand-kept list, so this guards the predicate rather than an enumeration -
## a new locomotion type gets the right behaviour from its traits, and this
## catches it if the traits say something the mounting does not honour.
func test_only_ground_and_hovering_types_seat_to_the_chine() -> bool:
	print("Running Test Suite: Only weight-bearing locomotion seats to the chine...")
	var ok := true
	var placer := _make_lab()
	await tree.process_frame

	for type_id in SEATED_SAMPLE + UNSEATED_SAMPLE:
		var should_seat: bool = ModuleCatalogScript.locomotion_touches_ground(type_id)
		placer._place_hull_from_ui("brenntal_medium_a")
		await tree.process_frame
		placer.update_locomotion(type_id,
			placer.default_locomotion_settings[type_id].duplicate())
		await tree.process_frame

		var any_seated := false
		for part in _locomotion_children(placer.hull):
			if bool(part.get_meta("chine_seated", false)):
				any_seated = true
		if should_seat and not any_seated:
			print("  [FAIL] %s bears weight but no station seated." % type_id)
			ok = false
		elif not should_seat and any_seated:
			print("  [FAIL] %s mounts above the hull but was dragged to the chine."
				% type_id)
			ok = false
	placer.queue_free()
	if ok:
		print("  [PASS] %d types seat or abstain exactly as their traits require."
			% (SEATED_SAMPLE.size() + UNSEATED_SAMPLE.size()))
	return ok


## A hull carries exactly one locomotion chassis.
##
## Chris, 2026-08-12: "The only enforcement should be one main locomotion chassis
## per hull." This used to be an unnamed side effect of update_locomotion()'s
## teardown loop, which meant nothing tested it and nothing stated it. It is now
## LocomotionMount.clear(), and this pins it.
func test_hull_carries_exactly_one_locomotion_chassis() -> bool:
	print("Running Test Suite: One locomotion chassis per hull...")
	var placer := _make_lab()
	await tree.process_frame
	placer._place_hull_from_ui("brenntal_medium_a")
	await tree.process_frame

	var seen: Array[String] = []
	for type_id in ["wheels", "tracked_treads", "legs", "wheels"]:
		placer.update_locomotion(type_id,
			placer.default_locomotion_settings[type_id].duplicate())
		await tree.process_frame
		var types := {}
		for part in _locomotion_children(placer.hull):
			types[part.get_meta("module_data").type_id] = true
		if types.size() != 1:
			print("  [FAIL] After choosing %s the hull carries %d locomotion types: %s"
				% [type_id, types.size(), str(types.keys())])
			placer.queue_free()
			return false
		if not types.has(type_id):
			print("  [FAIL] After choosing %s the hull carries %s instead."
				% [type_id, str(types.keys())])
			placer.queue_free()
			return false
		seen.append(type_id)
	placer.queue_free()
	print("  [PASS] Across %d successive choices the hull never carried two chassis."
		% seen.size())
	return true


## The chine solver itself, over the whole shipped roster.
##
## tools/verify_hull_chine.gd is the full harness (94 hulls x 10 stations, with a
## drift report); this is the regression guard that runs in CI. It asserts the
## two properties that must never break: the solver finds a real section on every
## hull rather than falling back to the bounding box, and every mount frame it
## returns points outboard and rises.
func test_chine_solver_holds_across_the_hull_roster() -> bool:
	print("Running Test Suite: Chine solver holds across every shipped hull...")
	var dir := DirAccess.open("res://assets/models/hulls")
	if dir == null:
		print("  [FAIL] Hull directory missing.")
		return false
	var checked := 0
	var fell_back := 0
	var bad := 0
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".glb"):
			var res := load("res://assets/models/hulls/%s" % f)
			if res is PackedScene:
				var inst = (res as PackedScene).instantiate()
				if inst is Node3D:
					var profile: Dictionary = HullChineScript.build(inst)
					if HullChineScript.is_valid(profile):
						var aabb: AABB = profile["aabb"]
						for frac in [0.3, 0.5, 0.7]:
							for side in [-1.0, 1.0]:
								checked += 1
								var z: float = aabb.position.z + aabb.size.z * frac
								var fr: Dictionary = HullChineScript.mount_frame(
									profile, z, side)
								if not fr["found"]:
									fell_back += 1
								var n: Vector3 = fr["normal"]
								var up: Vector3 = fr["flank_up"]
								if n.x * side <= 0.0 or n.y >= 0.0 or up.y <= 0.0:
									bad += 1
				inst.free()
		f = dir.get_next()
	dir.list_dir_end()

	if checked == 0:
		print("  [FAIL] No hulls were checked.")
		return false
	if fell_back > 0 or bad > 0:
		print("  [FAIL] %d/%d stations fell back to the box, %d had an unusable frame."
			% [fell_back, checked, bad])
		return false
	print("  [PASS] %d stations across the roster all solved to a usable chine frame."
		% checked)
	return true
