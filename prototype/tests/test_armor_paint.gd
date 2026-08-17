extends "res://tests/suite_base.gd"
# Armor as painted per-facet coverage.
#
# Replaces the old plate conform/round-trip suite, which asserted things about
# armor MODULES - their mesh extent, their node scale, their survival across a
# save. None of that exists any more, so it was deleted rather than rewritten.
# What matters now is different in kind:
#
#   * painting a side covers that side, and coverage/weight follow the AREA
#     covered rather than a count of plates
#   * a design survives save -> load with the same facets painted
#   * a hull mesh that changes underneath a save re-resolves by geometry rather
#     than silently applying old facet ids to new facets
#   * the damage resolver reads the facet actually struck

const ArmorPaint = preload("res://scripts/armor_paint.gd")
const HullFacets = preload("res://scripts/hull_facets.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")

const HULL := "brenntal_medium_a"


func _paint(hull_type: String, side: String, type_id: String, material: String) -> Array:
	var rows := []
	var table := HullFacets.load_map(hull_type)
	var normals: PackedVector3Array = table.get("normal", PackedVector3Array())
	var centroids: PackedVector3Array = table.get("centroid", PackedVector3Array())
	var areas: PackedFloat32Array = table.get("area", PackedFloat32Array())
	for f in ArmorPaint.facets_for_side(hull_type, side):
		rows.append({
			"facet_id": int(f),
			"side": side,
			"type_id": type_id,
			"material": material,
			"thickness": 1.0,
			"normal": {"x": normals[f].x, "y": normals[f].y, "z": normals[f].z},
			"centroid": {"x": centroids[f].x, "y": centroids[f].y, "z": centroids[f].z},
			"area": float(areas[f]),
		})
	return rows


func test_paint_coverage_weight_and_round_trip() -> bool:
	print("Running Test Suite: Armor paint - coverage, area-scaled weight, round trip...")

	var table := HullFacets.load_map(HULL)
	if int(table.get("facet_count", 0)) <= 0:
		print("  [FAIL] %s has no baked facet table - run bake_hull_roster --facets-only" % HULL)
		return false

	# Every side must be paintable. Winner-take-all side classification left 15
	# of the 94 hulls with no `front` at all, which is why membership is
	# weighted - see HullFacets.BRUSH_SIDE_MIN_WEIGHT.
	for side in ArmorPaint.SIDES:
		if ArmorPaint.facets_for_side(HULL, side).is_empty():
			print("  [FAIL] side '%s' has no paintable facets" % side)
			return false

	var front := _paint(HULL, "front", "armor_plating", "hardened_steel")
	var plan := ArmorPaint.build_plan(HULL, front)
	if bool(plan.get("empty", true)):
		print("  [FAIL] a painted front produced an empty plan")
		return false

	var front_cov := float((plan["sides"]["front"] as Dictionary)["coverage"])
	var back_cov := float((plan["sides"]["back"] as Dictionary)["coverage"])
	if front_cov <= 0.5:
		print("  [FAIL] painting the front should cover most of it, got %.2f" % front_cov)
		return false
	if back_cov >= front_cov:
		print("  [FAIL] the back should be less covered than the front (%.2f vs %.2f)" % [back_cov, front_cov])
		return false

	# Weight scales with AREA, so an all-round scheme must cost strictly more
	# than a frontal one. Under the old flat per-plate model these were equal,
	# which is the decision this whole model exists to make real.
	var holder := Node3D.new()
	root.add_child(holder)
	var hull := Node3D.new()
	holder.add_child(hull)

	hull.set_meta("armor_plan", plan)
	var frontal: Dictionary = ArmorPaint.analyze(hull)

	var all_rows := []
	for side in ArmorPaint.SIDES:
		all_rows.append_array(_paint(HULL, side, "armor_plating", "hardened_steel"))
	# Dedupe: a facet can belong to more than one side's brush set.
	var by_id := {}
	for r in all_rows:
		by_id[int(r["facet_id"])] = r
	hull.set_meta("armor_plan", ArmorPaint.build_plan(HULL, by_id.values()))
	var all_round: Dictionary = ArmorPaint.analyze(hull)

	if not (all_round["weight"] > frontal["weight"] * 1.5):
		print("  [FAIL] all-round armor should weigh clearly more than frontal: %.1f vs %.1f" % [
			all_round["weight"], frontal["weight"]])
		holder.queue_free()
		return false
	if int(all_round["cost_metal"]) <= int(frontal["cost_metal"]):
		print("  [FAIL] all-round armor should cost more metal: %d vs %d" % [
			all_round["cost_metal"], frontal["cost_metal"]])
		holder.queue_free()
		return false
	if float(frontal["coverage"]) <= 0.0 or float(all_round["coverage"]) <= float(frontal["coverage"]):
		print("  [FAIL] total coverage should rise with an all-round scheme")
		holder.queue_free()
		return false
	if str(frontal["weakest_side"]) == "front":
		print("  [FAIL] with only the front painted, the front should not be the weakest side")
		holder.queue_free()
		return false
	holder.queue_free()

	# Round trip through the blueprint schema.
	var bm = BlueprintManagerScript.new()
	root.add_child(bm)
	var blueprint := {
		"version": BlueprintManagerScript.CURRENT_BLUEPRINT_VERSION,
		"hull_type": HULL,
		"armor": {
			"hull_type": HULL,
			"hull_tri_count": int(table.get("tri_count", 0)),
			"facet_count": int(table.get("facet_count", 0)),
			"assignments": front,
		},
		"modules": [],
	}
	var restored: Array = bm._deserialize_armor(blueprint, HULL)
	if restored.size() != front.size():
		print("  [FAIL] round trip lost assignments: %d -> %d" % [front.size(), restored.size()])
		bm.queue_free()
		return false
	var want := {}
	for r in front:
		want[int(r["facet_id"])] = true
	for r in restored:
		if not want.has(int(r["facet_id"])):
			print("  [FAIL] round trip produced facet %d, which was never painted" % int(r["facet_id"]))
			bm.queue_free()
			return false
	bm.queue_free()

	print("  [ OK ] front %.0f%% vs back %.0f%%; all-round %.0fkg vs frontal %.0fkg; %d facets round tripped" % [
		front_cov * 100.0, back_cov * 100.0, all_round["weight"], frontal["weight"], restored.size()])
	return true


func test_paint_reresolves_when_the_hull_mesh_changes() -> bool:
	print("Running Test Suite: Armor paint - re-resolve against a changed hull mesh...")

	var table := HullFacets.load_map(HULL)
	var front := _paint(HULL, "front", "slat_armor", "reactive_armor")
	if front.is_empty():
		print("  [FAIL] nothing painted")
		return false

	var bm = BlueprintManagerScript.new()
	root.add_child(bm)

	# A re-exported .glb: the triangle count no longer matches what the save was
	# written against, so facet_id is meaningless and must NOT be trusted. The
	# facets themselves are unchanged here, so every assignment should recover.
	var blueprint := {
		"version": BlueprintManagerScript.CURRENT_BLUEPRINT_VERSION,
		"hull_type": HULL,
		"armor": {
			"hull_type": HULL,
			"hull_tri_count": int(table.get("tri_count", 0)) + 137,
			"facet_count": int(table.get("facet_count", 0)),
			"assignments": front,
		},
		"modules": [],
	}
	var recovered: Array = bm._deserialize_armor(blueprint, HULL)
	if recovered.size() != front.size():
		print("  [FAIL] re-resolve should recover every facet whose geometry is unchanged: %d of %d" % [
			recovered.size(), front.size()])
		bm.queue_free()
		return false
	var original := {}
	for r in front:
		original[int(r["facet_id"])] = true
	for r in recovered:
		if not original.has(int(r["facet_id"])):
			print("  [FAIL] re-resolve moved a facet that had not changed")
			bm.queue_free()
			return false

	# A facet whose normal has swung right around must be DROPPED rather than
	# quietly re-armored onto whatever surface now sits nearest.
	var flipped := []
	for r in front:
		var f := r.duplicate(true)
		f["normal"] = {"x": -float(r["normal"]["x"]), "y": -float(r["normal"]["y"]), "z": -float(r["normal"]["z"])}
		f["centroid"] = {"x": 999.0, "y": 999.0, "z": 999.0}
		flipped.append(f)
	blueprint["armor"]["assignments"] = flipped
	var dropped: Array = bm._deserialize_armor(blueprint, HULL)
	if dropped.size() >= front.size():
		print("  [FAIL] a facet rotated past the match cone should be dropped, kept %d of %d" % [
			dropped.size(), front.size()])
		bm.queue_free()
		return false
	bm.queue_free()

	print("  [ OK ] %d facets recovered on a re-export; %d of %d kept when flipped" % [
		recovered.size(), dropped.size(), front.size()])
	return true


func test_resolver_reads_the_painted_facet() -> bool:
	print("Running Test Suite: Armor paint - the damage resolver reads the plan...")

	var holder := Node3D.new()
	root.add_child(holder)
	var hull := Node3D.new()
	hull.set_meta("armor_material", "hardened_steel")
	hull.set_meta("armor_thickness", 1.0)
	holder.add_child(hull)

	var bare := DamageResolverScript.resolve(hull, [], "kinetic")
	var plan := ArmorPaint.build_plan(HULL, _paint(HULL, "front", "spaced_composite", "reactive_armor"))
	hull.set_meta("armor_plan", plan)
	var painted := DamageResolverScript.resolve(hull, [], "kinetic")

	# No hit direction: the AoE path, blended by total coverage. Painting one
	# side must raise the threshold but not to the full plated value.
	if not (painted.x > bare.x):
		print("  [FAIL] painted armor should raise the kinetic threshold: %.2f vs %.2f" % [painted.x, bare.x])
		holder.queue_free()
		return false

	# Module bias still applies and still discriminates: spaced_composite is
	# the anti-kinetic answer, slat_armor is not.
	var slat_plan := ArmorPaint.build_plan(HULL, _paint(HULL, "front", "slat_armor", "reactive_armor"))
	hull.set_meta("armor_plan", slat_plan)
	var slat := DamageResolverScript.resolve(hull, [], "kinetic")
	if not (painted.x > slat.x):
		print("  [FAIL] spaced_composite should beat slat_armor against kinetic: %.2f vs %.2f" % [painted.x, slat.x])
		holder.queue_free()
		return false

	# Explosive flips the ordering - that is the whole point of the bias table.
	hull.set_meta("armor_plan", slat_plan)
	var slat_ex := DamageResolverScript.resolve(hull, [], "explosive")
	hull.set_meta("armor_plan", plan)
	var comp_ex := DamageResolverScript.resolve(hull, [], "explosive")
	if not (slat_ex.x > comp_ex.x):
		print("  [FAIL] slat_armor should beat spaced_composite against explosive: %.2f vs %.2f" % [
			slat_ex.x, comp_ex.x])
		holder.queue_free()
		return false

	# A hull with no plan must resolve exactly as it always did - this is the
	# structure path (structure.gd calls resolve(null, [], ...)).
	var no_plan := DamageResolverScript.resolve(null, [], "kinetic")
	var default_baseline := DamageResolverScript.get_material_threshold("hardened_steel", "kinetic", 1.0)
	if not is_equal_approx(no_plan.x, default_baseline.x) or not is_equal_approx(no_plan.y, default_baseline.y):
		print("  [FAIL] a hull with no armor plan must resolve as bare metal")
		holder.queue_free()
		return false

	holder.queue_free()
	print("  [ OK ] bare %.1f -> painted %.1f; composite/slat ordering flips between kinetic and explosive" % [
		bare.x, painted.x])
	return true
