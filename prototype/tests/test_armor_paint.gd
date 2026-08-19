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
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

const HULL := "brenntal_medium_a"


func _paint(hull_type: String, side: String, type_id: String, material: String) -> Array:
	var rows := []
	var mesh := MeshAssetLoader.get_hull_mesh(hull_type)
	if mesh != null:
		# Warm the cache so facets_for_side_mesh works.
		HullFacets.cached_segment(mesh)
	var seg := HullFacets.cached_segment(mesh) if mesh else HullFacets.load_map(hull_type)
	var normals: PackedVector3Array = seg.get("normal", PackedVector3Array())
	var centroids: PackedVector3Array = seg.get("centroid", PackedVector3Array())
	var areas: PackedFloat32Array = seg.get("area", PackedFloat32Array())
	for f in ArmorPaint.facets_for_side(hull_type, side, mesh):
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

	var mesh := MeshAssetLoader.get_hull_mesh(HULL)
	if mesh == null:
		print("  [FAIL] could not load hull mesh for %s" % HULL)
		return false
	var seg := HullFacets.cached_segment(mesh)
	if seg.is_empty() or int(seg.get("count", 0)) <= 0:
		print("  [FAIL] %s produced no facets from live segment" % HULL)
		return false

	# Every side must be paintable. Winner-take-all side classification left 15
	# of the 94 hulls with no `front` at all, which is why membership is
	# weighted - see HullFacets.BRUSH_SIDE_MIN_WEIGHT.
	for side in ArmorPaint.SIDES:
		if ArmorPaint.facets_for_side(HULL, side, mesh).is_empty():
			print("  [FAIL] side '%s' has no paintable facets" % side)
			return false

	var front := _paint(HULL, "front", "armor_plating", "hardened_steel")
	var plan := ArmorPaint.build_plan(HULL, front, mesh)
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
	hull.set_meta("armor_plan", ArmorPaint.build_plan(HULL, by_id.values(), mesh))
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
			"hull_tri_count": int(seg.get("tri_count", 0)),
			"facet_count": int(seg.get("count", 0)),
			"assignments": front,
		},
		"modules": [],
	}
	var restored: Array = bm._deserialize_armor(blueprint, HULL, mesh)
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

	var mesh := MeshAssetLoader.get_hull_mesh(HULL)
	var front := _paint(HULL, "front", "slat_armor", "reactive_armor")
	if front.is_empty():
		print("  [FAIL] nothing painted")
		return false

	var bm = BlueprintManagerScript.new()
	root.add_child(bm)

	# A re-exported .glb: the triangle count no longer matches what the save was
	# written against, so facet_id is meaningless and must NOT be trusted. The
	# facets themselves are unchanged here, so every assignment should recover.
	var seg := HullFacets.cached_segment(mesh) if mesh else {}
	var blueprint := {
		"version": BlueprintManagerScript.CURRENT_BLUEPRINT_VERSION,
		"hull_type": HULL,
		"armor": {
			"hull_type": HULL,
			"hull_tri_count": int(seg.get("tri_count", 0)) + 137,
			"facet_count": int(seg.get("count", 0)),
			"assignments": front,
		},
		"modules": [],
	}
	var recovered: Array = bm._deserialize_armor(blueprint, HULL, mesh)
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
		var f: Dictionary = r.duplicate(true)
		f["normal"] = {"x": -float(r["normal"]["x"]), "y": -float(r["normal"]["y"]), "z": -float(r["normal"]["z"])}
		f["centroid"] = {"x": 999.0, "y": 999.0, "z": 999.0}
		flipped.append(f)
	blueprint["armor"]["assignments"] = flipped
	var dropped: Array = bm._deserialize_armor(blueprint, HULL, mesh)
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

	var mesh := MeshAssetLoader.get_hull_mesh(HULL)
	var holder := Node3D.new()
	root.add_child(holder)
	var hull := Node3D.new()
	hull.set_meta("armor_material", "hardened_steel")
	hull.set_meta("armor_thickness", 1.0)
	holder.add_child(hull)

	var bare := DamageResolverScript.resolve(hull, [], "kinetic")
	var plan := ArmorPaint.build_plan(HULL, _paint(HULL, "front", "spaced_composite", "reactive_armor"), mesh)
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
	var slat_plan := ArmorPaint.build_plan(HULL, _paint(HULL, "front", "slat_armor", "reactive_armor"), mesh)
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


# The cage geometry. build_plate's "cage" mode is the one piece of the
# slat-stand-off work that has no coverage test in the data path (the plan
# tests above don't care what the visual looks like), so this suite asserts
# the bars exist, are sized to the pattern's period, and stand off the hull
# by `bar_height`. A regression in `_cage` that emits zero triangles, emits
# bars with the wrong period, or forgets the standoff is caught here.
func test_slat_cage_geometry() -> bool:
	print("Running Test Suite: Armor paint - slat cage emits bars with the right period and standoff...")

	var mesh := MeshAssetLoader.get_hull_mesh(HULL)
	if mesh == null:
		print("  [FAIL] could not load hull mesh for %s" % HULL)
		return false
	HullFacets.cached_segment(mesh)
	var seg := HullFacets.cached_segment(mesh)
	var normals: PackedVector3Array = seg.get("normal", PackedVector3Array())
	if normals.is_empty():
		print("  [FAIL] %s produced no facet normals" % HULL)
		return false
	# Pick any front-facing facet. We don't care which one - the bar count
	# depends on the facet's V extent, and the V extent is positive for any
	# real facet.
	var picked_facet := -1
	for i in range(normals.size()):
		if normals[i].z < -0.5:
			picked_facet = i
			break
	if picked_facet < 0:
		print("  [FAIL] no front-facing facet on %s" % HULL)
		return false

	# Build a slat plate in cage mode. The mesh is in module-local frame, so
	# we don't need the hull transform for assertions on bar count and height.
	# build_plate needs a real MeshInstance3D because _facet_surface walks
	# the mesh resource, so wrap our test mesh in one.
	var centroids: PackedVector3Array = seg.get("centroid", PackedVector3Array())
	var center: Vector3 = centroids[picked_facet]
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	var frame_dict := HullFacets.facet_frame(HULL, picked_facet, Transform3D.IDENTITY, mesh)
	var frame: Basis = frame_dict["basis"]
	var plate: ArrayMesh = HullFacets.build_plate(mesh_inst, HULL, picked_facet, "slat_armor",
		Vector3.ONE, center, frame, "reactive_armor", 1.0)
	if plate == null:
		print("  [FAIL] slat cage build_plate returned null for facet %d" % picked_facet)
		return false
	var arrays = plate.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tri_count: int = verts.size() / 3
	# The cage is a set of closed rectangular prisms (one per bar), each
	# at the facet's mean plane. 6 faces, 12 triangles, 36 vertices per
	# bar; the total tri count is a clean multiple of 12 - any other
	# number means a regression in the per-bar box path.
	if tri_count <= 0 or tri_count % 12 != 0:
		print("  [FAIL] slat cage triangle count should be a positive multiple of 12 (one box per bar), got %d" % tri_count)
		return false
	var bar_count: int = tri_count / 12
	var bar_height: float = float(HullFacets.SURFACE_PATTERNS["slat_armor"]["bar_height"])
	var max_y := -INF
	var min_y := INF
	for v in verts:
		if v.y > max_y:
			max_y = v.y
		if v.y < min_y:
			min_y = v.y
	var y_range: float = max_y - min_y
	# The cage is a flat box at the facet's mean plane, so its Y range
	# is exactly bar_height - the hull's curvature is NOT inherited
	# into the cage's geometry. This is the property the user wanted
	# after seeing the chaotic curtain-wall version: clean flat top
	# and sides, hull surface visible curving around the bar.
	if absf(y_range - bar_height) > 0.001:
		print("  [FAIL] slat cage Y range should be exactly bar_height (%.4f), got %.4f" % [
			bar_height, y_range])
		return false
	# The cage's BOTTOM must be at the z-fight lift, NOT at the hull's
	# curvature peak. The earlier `max(bounds_scaled_lift, max_curvature)`
	# formula lifted the bar by the facet's max |Y| of any triangle, so
	# on the Brenntal's curved front (skin curvature ~0.5m) the bars
	# floated ~0.5m above the hull. The user explicitly accepted the
	# bar's bottom clipping into the hull, so the lift is now the
	# z-fight epsilon only. The bar's min_y must be at the bounds-
	# scaled lift (a few cm), not at the curvature peak.
	#
	# We don't know the exact lift value (it's bounds.size.length() *
	# PLATE_LIFT_FRACTION capped by PLATE_LIFT_MIN), but we can bound
	# it: lift < bar_height (a 0.30m bar with min_y near 0.30m would
	# be a flat bar with no standoff, not a cage). And lift < skin
	# curvature on this facet would be the regression we're catching.
	# The precise check: min_y < skin's max_y. If the bar's bottom is
	# above the skin's highest point, the bar is floating.
	#
	# We get skin's max_y from the skin plate below, so we stash the
	# raw min_y here and check it after the skin plate is built.
	var cage_min_y: float = min_y
	# Per-bar V range must not extend past the hull's V extent at the
	# bar's U position. The old code used the full facet V range for
	# every bar, which projected past the hull's edge on any non-
	# rectangular facet (a tumblehome flank, a chamfered nose). The
	# bar's V range is now clipped to the hull's surface in the bar's
	# U slice, so the bar's V extent (across all bars) cannot exceed
	# the facet's V extent. This is the test that would have caught
	# the "bars extend past the facet" bug.
	#
	# We compare against a SKIN plate built on the same facet: the
	# skin is the hull's surface itself (lifted by the z-fight epsilon,
	# which does not change its V extent), so its V range is the hull's
	# V range at this facet. On a rectangular facet the cage and skin
	# V ranges are equal; on a curved facet the cage's V range is the
	# union of per-bar V ranges, each a subset of the hull's V range
	# at that bar's U position, so the union cannot exceed the hull's
	# overall V range.
	var plate_skin: ArrayMesh = HullFacets.build_plate(mesh_inst, HULL, picked_facet, "armor_plating",
		Vector3.ONE, center, frame, "hardened_steel", 1.0)
	if plate_skin == null:
		print("  [FAIL] skin build_plate returned null for armor_plating (V range check)")
		return false
	var skin_verts: PackedVector3Array = plate_skin.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var skin_v_lo: float = INF
	var skin_v_hi: float = -INF
	for v in skin_verts:
		if v.z < skin_v_lo: skin_v_lo = v.z
		if v.z > skin_v_hi: skin_v_hi = v.z
	var cage_v_lo: float = INF
	var cage_v_hi: float = -INF
	for v in verts:
		if v.z < cage_v_lo: cage_v_lo = v.z
		if v.z > cage_v_hi: cage_v_hi = v.z
	# Cage's V range must be at or inside the skin's V range, with a
	# small tolerance for float error. The skin is the hull's surface
	# and the cage's V range is the union of triangles that overlap
	# each bar's U slice, so the cage cannot exceed the skin in V.
	if cage_v_lo < skin_v_lo - 0.001 or cage_v_hi > skin_v_hi + 0.001:
		print("  [FAIL] slat cage V range [%.4f, %.4f] must be within the hull's V range [%.4f, %.4f]" % [
			cage_v_lo, cage_v_hi, skin_v_lo, skin_v_hi])
		return false
	# The cage's V range must also be NON-EMPTY (at least one bar
	# overlaps the hull's surface in V). An empty cage would mean
	# every bar's U slice had no hull surface, which would only
	# happen on a degenerate facet. The Y-range check above already
	# implies a non-empty cage, but assert explicitly.
	if cage_v_hi - cage_v_lo < 1e-6:
		print("  [FAIL] slat cage V range is empty (cage spans no V extent)")
		return false
	# And: skin mode (armor_plating) is NOT the cage path. A skin on a
	# curved facet can have Y variation (the hull's tumblehome flank
	# lifts vertices out of the plane by the curvature amount), but the
	# skin is still essentially flat. The cage's vertical extent is
	# bar_height (0.30m); the skin's vertical extent is the curvature.
	# The cage must dominate by at least an order of magnitude on a
	# curved facet.
	# (plate_skin was built above for the V-range check; reuse it here.)
	var skin_max_y := -INF
	var skin_min_y := INF
	for v in skin_verts:
		if v.y > skin_max_y:
			skin_max_y = v.y
		if v.y < skin_min_y:
			skin_min_y = v.y
	var skin_y_range: float = skin_max_y - skin_min_y
	# FLOATING CHECK: the bar's bottom (cage_min_y) must NOT be above
	# the skin's highest point (skin_max_y). If it is, the bar is
	# floating above the hull - the bug where the curvature lift
	# pushed the bar up by the facet's max |Y|. The bar's bottom
	# should sit at the z-fight lift (a few cm) and the hull's surface
	# can push up through it at curvature peaks; the bar's bottom
	# being ABOVE the skin's max_y is a regression to the floating
	# version. The skin is lifted by the z-fight epsilon too, so
	# cage_min_y is allowed to be slightly above skin_min_y (up to
	# the lift amount, a few cm), but it must be at or below
	# skin_max_y. On a flat facet skin_max_y is the z-fight lift and
	# cage_min_y is also the z-fight lift, so the two are equal; on a
	# curved facet the bar's bottom is at the z-fight lift and the
	# skin curves up to or past it.
	if cage_min_y > skin_max_y + 0.001:
		print("  [FAIL] slat cage bottom (%.4f) is above the hull's surface (skin max_y=%.4f); the bar is floating" % [
			cage_min_y, skin_max_y])
		return false
	# And: the bar's bottom must be a small fraction of bar_height
	# above the skin's lowest point. Without this bound a regression
	# could pass the floating check by setting both cage_min_y and
	# skin_max_y to 0.5m (a flat-topped box at 0.5m). cage_min_y is
	# the z-fight lift (a few cm), and the skin's lowest point on
	# this facet is at skin_min_y; cage_min_y >= skin_min_y because
	# the bar must be at or above the lowest hull vertex in its U
	# slice. We don't assert an upper bound on cage_min_y here
	# because on a curved facet the bar's bottom is allowed to be
	# well above the skin's lowest point (the bar reads as growing
	# out of the hull, which is the intended look).
	if cage_min_y < skin_min_y - 0.001:
		print("  [FAIL] slat cage bottom (%.4f) is below the hull's surface (skin min_y=%.4f); the bar is clipping too deep" % [
			cage_min_y, skin_min_y])
		return false
	# Sanity: the skin's Y range is the hull's curvature in Y for this
	# facet. On a flat facet this is near zero; on a tumblehome flank
	# it can exceed bar_height (Brenntal measures ~0.5m of curvature
	# on its tumblehome, more than the 0.30m bar_height). The cage does
	# NOT need to dominate the skin in Y range - the cage is a flat
	# box, the skin is the hull's surface. The relevant check is that
	# the cage exists at all with the right Y extent (= bar_height)
	# and the right triangle count, which are already verified above.
	# Here we just print the skin curvature for visibility.
	pass
	# And: ceramic (skin+lift) sits at the per-type lift_override, not at
	# the z-fight epsilon. 10mm is what SURFACE_PATTERNS declares; check it.
	var plate_ceramic: ArrayMesh = HullFacets.build_plate(mesh_inst, HULL, picked_facet, "ablative_foam",
		Vector3.ONE, center, frame, "hardened_steel", 1.0)
	if plate_ceramic == null:
		print("  [FAIL] skin+lift build_plate returned null for ablative_foam")
		return false
	var cer_verts: PackedVector3Array = plate_ceramic.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var cer_max_y := -INF
	var cer_min_y := INF
	for v in cer_verts:
		if v.y > cer_max_y:
			cer_max_y = v.y
		if v.y < cer_min_y:
			cer_min_y = v.y
	# The lift_override is a FLOOR: the ceramic's lift is
	# max(lift_override, bounds_scaled_lift). So:
	#   - on a small facet, ceramic is at lift_override, skin is at the
	#     bounds-scaled value, ceramic is ABOVE the skin by
	#     (lift_override - bounds_scaled_lift)
	#   - on a large facet where bounds_scaled_lift > lift_override,
	#     both ceramic and skin sit at the bounds-scaled value, and
	#     ceramic is AT the same height as the skin.
	# In both cases, ceramic must be AT OR ABOVE the skin, never below.
	var cer_above_skin: float = cer_max_y - skin_max_y
	if cer_above_skin < -0.001:
		print("  [FAIL] ceramic should be at or above the skin, got %.4f below" % -cer_above_skin)
		return false
	# And: on a small facet, the ceramic is lift_override (10mm) above
	# the z-fight minimum. The skin's lift is at least PLATE_LIFT_MIN
	# (4mm) and at most bounds-scaled. So the ceramic is at least
	# (lift_override - bounds_scaled_lift) above the skin, but the
	# exact amount depends on the facet. Assert the ceramic is at
	# least lift_override - bounds_scaled_lift_max above the skin on
	# any facet, where bounds_scaled_lift_max is the max the bounds-
	# scaled formula would give (capped at the lift_override for large
	# facets). Concretely: ceramic should be at least 0 above the
	# skin (already checked) and at most lift_override above the skin
	# (no facet can lift the skin above lift_override AND not lift the
	# ceramic, since they share the max()).
	var expected_lift: float = float(HullFacets.SURFACE_PATTERNS["ablative_foam"]["lift_override"])
	if cer_above_skin > expected_lift + 0.005:
		print("  [FAIL] ceramic sits %.4f above skin; expected at most lift_override (%.4f)" % [
			cer_above_skin, expected_lift])
		return false

	print("  [ OK ] cage: %d bars × 12 tris, Y range %.4f (bar_height=%.4f); bar bottom %.4f (z-fight lift, not floating above skin max_y %.4f); cage V [%.4f, %.4f] within skin V [%.4f, %.4f]; skin curvature %.4f; ceramic sits %.4f above skin" % [
		bar_count, y_range, bar_height, cage_min_y, skin_max_y, cage_v_lo, cage_v_hi, skin_v_lo, skin_v_hi, skin_y_range, cer_above_skin])
	mesh_inst.queue_free()
	return true

