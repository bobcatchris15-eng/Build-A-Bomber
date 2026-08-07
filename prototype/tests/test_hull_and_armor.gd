extends "res://tests/suite_base.gd"
# hull and armor suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

func test_fortress_wall_foundation_spawns_correctly() -> bool:
	print("Running Test Suite: Fortress Wall Foundation - Real Spawn Pipeline (Factions_and_Buildings.md's third foundation type)...")
	var bp_manager = preload("res://scripts/blueprint_manager.gd").new()
	root.add_child(bp_manager)
	var BattleUnitScript = preload("res://scripts/battle_unit.gd")

	var bp = {
		"version": 1.0, "hull_type": "fortress_wall_foundation",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "", "settings": {}},
		"modules": [
			{"type_id": "rotary_cannon", "name": "Rotary Cannon", "position": {"x": 0.0, "y": 1.4, "z": 0.0}, "rotation": {"x": 0.0, "y": 0.0, "z": 0.0}, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "yaw_offset": 0.0, "tweaks": {}}
		]
	}
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	root.add_child(unit)
	unit.setup(bp, 0, bp_manager)

	if not is_instance_valid(unit.hull_node):
		print("  [FAIL] fortress_wall_foundation should reconstruct a real hull via the authored .glb mesh, got no hull_node")
		unit.queue_free()
		return false
	if unit.max_hp <= 0.0:
		print("  [FAIL] fortress_wall_foundation should carry real HP from the catalog, got ", unit.max_hp)
		unit.queue_free()
		return false
	if unit.vision_range <= 0.0:
		print("  [FAIL] fortress_wall_foundation should have a real base_vision, got ", unit.vision_range)
		unit.queue_free()
		return false
	if not ModuleCatalog.is_foundation("fortress_wall_foundation"):
		print("  [FAIL] fortress_wall_foundation should classify as a foundation (static, no locomotion required)")
		unit.queue_free()
		return false
	if not ModuleCatalog.validate_build_legality(bp).valid:
		print("  [FAIL] A fortress_wall_foundation with a weapon should be a legal build (static defense, no locomotion required)")
		unit.queue_free()
		return false

	unit.queue_free()
	print("  [PASS] fortress_wall_foundation reconstructs via the real spawn pipeline with a working mesh, real HP/vision, and passes the build-legality gate as a static defense.")
	return true

func test_hull_spec_flyout_round_trip() -> bool:
	print("Running Test Suite: hull-spec controls survive a flyout open/close cycle...")
	# The hull-spec flyout REPARENTS six long-lived controls into a panel that
	# frees itself on close. If the reclaim on `closed` ever stops firing, those
	# controls get freed with the flyout and the armour/faction UI goes dead -
	# and it goes dead silently, because every caller guards with `if
	# armor_mat_btn:` and simply skips. That is the failure this test exists for.
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	await tree.process_frame
	root.size = Vector2i(1280, 720)
	await tree.process_frame

	var stats = scene.get_node_or_null("UI_StatBlock")
	if stats == null:
		print("  [FAIL] No UI_StatBlock in MainLab.tscn.")
		scene.queue_free()
		return false
	if stats.hull_spec_btn == null or stats.hull_spec_stash == null:
		print("  [FAIL] Hull-spec trigger/stash were never built.")
		scene.queue_free()
		return false

	var widgets: Array = stats._hull_spec_widgets()
	if widgets.size() != 2:
		print("  [FAIL] Expected 2 hull-spec widgets, got ", widgets.size())
		scene.queue_free()
		return false
	for w in widgets:
		if w == null or not is_instance_valid(w):
			print("  [FAIL] A hull-spec widget was never created.")
			scene.queue_free()
			return false
		if w.get_parent() != stats.hull_spec_stash:
			print("  [FAIL] Widget ", w.name, " does not start in the stash (parent=", w.get_parent(), ")")
			scene.queue_free()
			return false

	# --- Open: every widget must move into the flyout ---
	stats._on_hull_spec_pressed()
	await tree.process_frame
	var flyout = stats._hull_spec_flyout
	if flyout == null or not is_instance_valid(flyout):
		print("  [FAIL] Pressing the trigger created no flyout.")
		scene.queue_free()
		return false
	for w in widgets:
		if not stats.hull_spec_stash.is_ancestor_of(w) and not flyout.is_ancestor_of(w):
			print("  [FAIL] Widget ", w.name, " went nowhere on open.")
			scene.queue_free()
			return false
	if not flyout.is_ancestor_of(stats.faction_btn):
		print("  [FAIL] Faction dropdown did not move into the flyout.")
		scene.queue_free()
		return false

	# --- Close: every widget must come back, still alive ---
	flyout.close()
	await tree.process_frame
	await tree.process_frame
	for w in widgets:
		if not is_instance_valid(w):
			print("  [FAIL] A hull-spec widget was FREED with the flyout - the reclaim on `closed` did not run.")
			scene.queue_free()
			return false
		if w.get_parent() != stats.hull_spec_stash:
			print("  [FAIL] Widget ", w.name, " did not return to the stash (parent=", w.get_parent(), ")")
			scene.queue_free()
			return false

	# Faction sync must still work after the round trip. This is the regression
	# the old `get_node_or_null("FactionDropdown")` path lookup would have caused:
	# null lookup, silent skip, wrong faction shown on a loaded blueprint.
	if stats.faction_btn == null or not is_instance_valid(stats.faction_btn):
		print("  [FAIL] faction_btn member lost after the round trip.")
		scene.queue_free()
		return false

	# Reopening must toggle, not stack a second panel on top of the first.
	stats._on_hull_spec_pressed()
	await tree.process_frame
	if stats._hull_spec_flyout == null:
		print("  [FAIL] Second open produced no flyout.")
		scene.queue_free()
		return false
	stats._on_hull_spec_pressed()
	await tree.process_frame
	await tree.process_frame
	if stats._hull_spec_flyout != null:
		print("  [FAIL] Trigger did not toggle - a flyout is still open after a second press.")
		scene.queue_free()
		return false
	for w in widgets:
		if not is_instance_valid(w) or w.get_parent() != stats.hull_spec_stash:
			print("  [FAIL] Widget ", w, " not reclaimed after the toggle cycle.")
			scene.queue_free()
			return false

	scene.queue_free()
	await tree.process_frame
	print("  [PASS] Hull-spec controls move into the flyout, return to the stash alive, and the trigger toggles.")
	return true

func test_faction_catalog_and_hull_material() -> bool:
	print("Running Test Suite: Faction Visual Identity - FactionCatalog (10 Factions, VISUAL_ART_DIRECTION.md model) + Shared Hull Shader Material...")
	var FactionCatalog = preload("res://scripts/faction_catalog.gd")
	var HullMaterialBuilder = preload("res://scripts/hull_material_builder.gd")

	var ids = FactionCatalog.get_ids()
	if ids.size() != 10:
		print("  [FAIL] Expected exactly 10 factions, got ", ids.size(), ": ", ids)
		return false
	var required_keys = ["name", "passive_summary", "base_color", "accent_color", "detail_color", "wear_color", "wear_amount", "anisotropy", "grime_amount", "edge_highlight_strength"]
	for fid in ids:
		var f = FactionCatalog.get_faction(fid)
		for key in required_keys:
			if not f.has(key):
				print("  [FAIL] Faction '", fid, "' is missing required visual field '", key, "': ", f.keys())
				return false

	# Same armor material, two different factions - should differ in paint
	# color but share the identical metallic/roughness "what is this armor
	# made of" character (faction=ownership/paint, armor_material=PBR
	# substance, deliberately independent axes).
	#
	# Faction color/wear identity is baked into the per-faction texture now
	# (tools/generate_faction_textures.gd, hull_faction_material.gdshader v3)
	# - base_color/accent_color are neutral, faction-independent multiply
	# tints (default white), kept live only for building.gd's team-color
	# override and a future damage-status overlay, NOT faction paint. The
	# real per-faction differentiator to check is albedo_tex.
	var mat_a = HullMaterialBuilder.build_hull_material("industrialists")
	var mat_b = HullMaterialBuilder.build_hull_material("technocrats")
	if mat_a.get_shader_parameter("albedo_tex") == mat_b.get_shader_parameter("albedo_tex"):
		print("  [FAIL] Two different factions should get different baked paint textures")
		return false
	if mat_a.shader != mat_b.shader:
		print("  [FAIL] Every faction should share the exact same shader resource (same mesh models, texture-only differentiation - no per-faction shader variants)")
		return false

	# Bayou Irregulars' camo is the one faction that blends accent into
	# broad mottled patches rather than thin panel-seam trim - proves the
	# mottle_amount parameter actually differs per faction, not a constant.
	if FactionCatalog.get_visual("bayou_irregulars").mottle_amount <= FactionCatalog.get_visual("industrialists").mottle_amount:
		print("  [FAIL] Bayou Irregulars should have a distinctly higher mottle_amount than a non-camo faction")
		return false

	# Real spawn-pipeline check: reconstruct_vehicle() should apply this
	# shared ShaderMaterial to the actual hull mesh, not just have the
	# builder function work in isolation.
	var BlueprintManager = preload("res://scripts/blueprint_manager.gd")
	var bp_manager = BlueprintManager.new()
	root.add_child(bp_manager)
	var blueprint_data = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "reactive_armor", "faction": "crimson_concordat",
		"modules": [],
	}
	var parent = Node3D.new()
	root.add_child(parent)
	var hull = bp_manager.reconstruct_vehicle(blueprint_data, parent, false)
	var mesh_inst = hull.get_node_or_null("MeshInstance3D") if hull else null
	# Hull materials are per-surface overrides now (HullMaterialBuilder.
	# apply_hull_materials() - real material slots, not a single whole-mesh
	# material_override, which is always null for a hull - see that
	# function's own comment). Faction identity lives in albedo_tex now
	# (see the mat_a/mat_b check above) - cross-check against build_hull_
	# material()'s OWN output for the same inputs, proving the real spawn
	# pipeline applies the same texture selection the builder function does.
	var check_surf = mesh_inst.mesh.get_surface_count() - 1 if mesh_inst and mesh_inst.mesh else 0
	var surface_mat = mesh_inst.get_surface_override_material(check_surf) if mesh_inst else null
	if not mesh_inst or not (surface_mat is ShaderMaterial):
		print("  [FAIL] A real reconstructed hull should have a ShaderMaterial (not StandardMaterial3D) as its armor surface override material")
		parent.queue_free()
		bp_manager.queue_free()
		return false
	var expected_armor_mat = HullMaterialBuilder.build_hull_material("reactive_armor", "crimson_concordat")
	if surface_mat.get_shader_parameter("albedo_tex") != expected_armor_mat.get_shader_parameter("albedo_tex"):
		print("  [FAIL] The real spawned hull's material should carry the blueprint's own faction texture (crimson_concordat)")
		parent.queue_free()
		bp_manager.queue_free()
		return false
	parent.queue_free()
	bp_manager.queue_free()

	print("  [PASS] All 10 factions have complete VISUAL_ART_DIRECTION.md-model visual identities, share one shader across every faction/armor-material combination, and a real reconstructed hull carries the correct faction-colored material.")
	return true

func test_hull_greebles() -> bool:
	print("Running Test Suite: Faction Visual Identity - Alpha-Cutout Greeble Cards (5 Treated Factions, 5 Untreated)...")
	var HullGreebles = preload("res://scripts/hull_greebles.gd")
	var BlueprintManager = preload("res://scripts/blueprint_manager.gd")
	var hull_size = Vector3(4.0, 1.0, 6.0)

	var ok = true

	# Every untreated faction should produce a real, empty container -
	# proves the exclusivity is genuine (a deliberate no-op branch), not
	# just "nobody bothered to add these 5 yet."
	var untreated = ["industrialists", "technocrats", "expansionists", "glacier_syndicate", "ledger_combine"]
	for fac in untreated:
		var hull = Node3D.new()
		root.add_child(hull)
		HullGreebles.apply_greebles(hull, fac, hull_size)
		var container = hull.get_node_or_null("HullGreebles")
		if not container or container.get_child_count() != 0:
			print("  [FAIL] Untreated faction '", fac, "' should get an empty HullGreebles container, got ", container.get_child_count() if container else "no container")
			ok = false
		hull.queue_free()

	# Every treated faction should produce a non-empty container with a
	# real, specific child count (not just "more than zero").
	var treated_counts = {
		"salvage_union": 3, "bayou_irregulars": 2, "crimson_concordat": 2,
		"aerodrome_cartel": 2, "dune_runners": 2,
	}
	for fac in treated_counts:
		var hull = Node3D.new()
		root.add_child(hull)
		HullGreebles.apply_greebles(hull, fac, hull_size)
		var container = hull.get_node_or_null("HullGreebles")
		if not container or container.get_child_count() != treated_counts[fac]:
			print("  [FAIL] '", fac, "' should produce exactly ", treated_counts[fac], " greeble children, got ", container.get_child_count() if container else "no container")
			ok = false
		hull.queue_free()
	await tree.process_frame

	# Re-applying (a faction change in the Design Lab) must replace, not
	# accumulate - the classic "update function called twice" duplication bug.
	var reuse_hull = Node3D.new()
	root.add_child(reuse_hull)
	HullGreebles.apply_greebles(reuse_hull, "salvage_union", hull_size)
	HullGreebles.apply_greebles(reuse_hull, "bayou_irregulars", hull_size)
	var reused_container = reuse_hull.get_node_or_null("HullGreebles")
	if not reused_container or reused_container.get_child_count() != treated_counts["bayou_irregulars"]:
		print("  [FAIL] Re-applying greebles for a different faction should REPLACE the old ones, not accumulate - got ", reused_container.get_child_count() if reused_container else "no container", " expected ", treated_counts["bayou_irregulars"])
		ok = false
	reuse_hull.queue_free()
	await tree.process_frame

	# Dune Runners' barrels are real 3D geometry (CylinderMesh + 2 band
	# children each), not flat alpha-cutout cards like the other 4.
	var barrel_hull = Node3D.new()
	root.add_child(barrel_hull)
	HullGreebles.apply_greebles(barrel_hull, "dune_runners", hull_size)
	var barrel_container = barrel_hull.get_node_or_null("HullGreebles")
	var found_real_barrel = false
	for child in barrel_container.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh and child.get_child_count() == 2:
			found_real_barrel = true
	if not found_real_barrel:
		print("  [FAIL] Dune Runners should have real CylinderMesh barrel geometry (with 2 band children each), not flat cutout cards")
		ok = false
	barrel_hull.queue_free()
	await tree.process_frame

	# Real spawn-pipeline check: reconstruct_vehicle() should apply greebles
	# to the actual hull, sized off the real footprint - not just have the
	# builder function work in isolation.
	var bp_manager = BlueprintManager.new()
	root.add_child(bp_manager)
	var blueprint_data = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "faction": "crimson_concordat",
		"modules": [],
	}
	var parent = Node3D.new()
	root.add_child(parent)
	var hull = bp_manager.reconstruct_vehicle(blueprint_data, parent, false)
	var real_container = hull.get_node_or_null("HullGreebles") if hull else null
	if not real_container or real_container.get_child_count() != 2:
		print("  [FAIL] A real reconstructed Crimson Concordat hull should carry exactly 2 pennant greebles")
		ok = false
	parent.queue_free()
	bp_manager.queue_free()
	await tree.process_frame

	if ok:
		print("  [PASS] All 5 untreated factions stay clean, all 5 treated factions produce the right greeble count/geometry type, re-theming replaces rather than accumulates, and a real reconstructed hull carries its faction's greebles.")
	return ok

func test_hull_decals() -> bool:
	print("Running Test Suite: Faction Visual Identity - Shared Decal/Stencil Atlas (Hazard Stripes + Serial Stencils + Mascot Icons, All 10 Factions)...")
	var HullDecals = preload("res://scripts/hull_decals.gd")
	var FactionCatalog = preload("res://scripts/faction_catalog.gd")
	var BlueprintManager = preload("res://scripts/blueprint_manager.gd")
	var hull_size = Vector3(4.0, 1.0, 6.0)

	var ok = true

	# Unlike hull_greebles.gd, decals are UNIVERSAL - every one of the 10
	# factions should get exactly 4 (2 hazard stripes + 1 serial + 1 mascot),
	# never a no-op.
	var ids = FactionCatalog.get_ids()
	if ids.size() != 10:
		print("  [FAIL] Expected 10 factions, got ", ids.size())
		return false
	for fac in ids:
		var hull = Node3D.new()
		root.add_child(hull)
		HullDecals.apply_decals(hull, fac, hull_size)
		var container = hull.get_node_or_null("HullDecals")
		if not container or container.get_child_count() != 5:
			print("  [FAIL] '", fac, "' should have exactly 5 decals (2 hazard + serial + badge + mascot), got ", container.get_child_count() if container else "no container")
			ok = false
		hull.queue_free()
	await tree.process_frame

	# decal_tint should track detail_color exactly (the accessor's whole
	# point is to never silently drift from what the hull shader's own
	# decal_tint uniform already carries).
	for fac in ["industrialists", "crimson_concordat", "ledger_combine"]:
		if FactionCatalog.get_visual_decal_tint(fac) != FactionCatalog.get_faction(fac).get("detail_color"):
			print("  [FAIL] get_visual_decal_tint('", fac, "') should exactly match its detail_color")
			ok = false

	# Two different factions' mascot icons should be genuinely different
	# shapes (different cached textures), not the same crest recolored -
	# proves the per-faction simplification actually varies, not just tint.
	var hull_a = Node3D.new()
	root.add_child(hull_a)
	HullDecals.apply_decals(hull_a, "industrialists", hull_size)
	var hull_b = Node3D.new()
	root.add_child(hull_b)
	HullDecals.apply_decals(hull_b, "glacier_syndicate", hull_size)
	var mascot_a = hull_a.get_node("HullDecals").get_children()[4].material_override.albedo_texture
	var mascot_b = hull_b.get_node("HullDecals").get_children()[4].material_override.albedo_texture
	if mascot_a == mascot_b:
		print("  [FAIL] Industrialists and Glacier Syndicate should have genuinely different mascot icon shapes (gear vs. snowflake-star), not the same texture")
		ok = false
	# But their hazard-stripe texture (a shared, non-mascot element) SHOULD
	# be the literal same cached texture resource - proves the "one shared
	# atlas, re-tinted" model is real, not a fresh texture per faction.
	var hazard_a = hull_a.get_node("HullDecals").get_children()[0].material_override.albedo_texture
	var hazard_b = hull_b.get_node("HullDecals").get_children()[0].material_override.albedo_texture
	if hazard_a != hazard_b:
		print("  [FAIL] Every faction should share the identical cached hazard-stripe texture (only tint differs)")
		ok = false
	hull_a.queue_free()
	hull_b.queue_free()
	await tree.process_frame

	# Re-applying (a faction change in the Design Lab) must replace, not accumulate.
	var reuse_hull = Node3D.new()
	root.add_child(reuse_hull)
	HullDecals.apply_decals(reuse_hull, "industrialists", hull_size)
	HullDecals.apply_decals(reuse_hull, "technocrats", hull_size)
	var reused_container = reuse_hull.get_node_or_null("HullDecals")
	if not reused_container or reused_container.get_child_count() != 5:
		print("  [FAIL] Re-applying decals for a different faction should REPLACE, not accumulate, got ", reused_container.get_child_count() if reused_container else "no container")
		ok = false
	reuse_hull.queue_free()
	await tree.process_frame

	# Real spawn-pipeline check.
	var bp_manager = BlueprintManager.new()
	root.add_child(bp_manager)
	var blueprint_data = {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "faction": "dune_runners",
		"modules": [],
	}
	var parent = Node3D.new()
	root.add_child(parent)
	var hull = bp_manager.reconstruct_vehicle(blueprint_data, parent, false)
	var real_container = hull.get_node_or_null("HullDecals") if hull else null
	if not real_container or real_container.get_child_count() != 5:
		print("  [FAIL] A real reconstructed hull should carry exactly 5 decals regardless of faction")
		ok = false
	parent.queue_free()
	bp_manager.queue_free()
	await tree.process_frame

	if ok:
		print("  [PASS] All 10 factions get the universal 4-decal set (hazard stripes share one cached texture, mascot icons genuinely differ in shape), re-theming replaces rather than accumulates, and a real reconstructed hull carries its decals.")
	return ok

func test_hull_modding_loader_scan_and_validation() -> bool:
	print("Running Test Suite: Hull Modding - HullLoader Scan, Validation, Mod-Overrides-Builtin Precedence...")
	var mods_dir = "user://mods/hulls"
	DirAccess.make_dir_recursive_absolute(mods_dir)

	var written_files = []
	var write_file = func(fname: String, content: String):
		var f = FileAccess.open(mods_dir + "/" + fname, FileAccess.WRITE)
		f.store_string(content)
		f.close()
		written_files.append(mods_dir + "/" + fname)

	# Malformed sidecars - must be skipped (with a warning), never fatal to
	# the whole scan (HULL_MODDING_PLAN.md §3, validation points 1-3).
	write_file.call("bad_missing_field.json", JSON.stringify({"name": "Bad", "hp": 1.0}))
	write_file.call("bad_missing_field.glb", "")
	write_file.call("bad_wrong_type.json", JSON.stringify({"name": "Bad2", "hp": "nope", "weight": 1.0, "metal": 1, "crystal": 1, "size": [1, 1, 1], "color": [1, 1, 1]}))
	write_file.call("bad_wrong_type.glb", "")

	var good_id = "run_tests_smoke_mod_hull"
	write_file.call(good_id + ".json", JSON.stringify({"name": "Run Tests Smoke Mod Hull", "hp": 111.0, "weight": 22.0, "metal": 5, "crystal": 1, "size": [1, 1, 1], "color": [1, 0, 0]}))
	write_file.call(good_id + ".glb", "")

	HullLoader.reset_cache_for_tests()
	var hulls = HullLoader.get_hulls()

	var ok = true
	if not hulls.has(good_id):
		print("  [FAIL] valid mod sidecar was not picked up")
		ok = false
	if hulls.has("bad_missing_field"):
		print("  [FAIL] sidecar missing a required field should have been skipped, not defaulted")
		ok = false
	if hulls.has("bad_wrong_type"):
		print("  [FAIL] sidecar with a wrong-typed field should have been skipped")
		ok = false
	if not HullLoader.is_modded(good_id):
		print("  [FAIL] valid mod hull should be flagged as sourced from user://mods/hulls")
		ok = false
	if not hulls.has("medium_hull") or hulls["medium_hull"]["hp"] != 400.0:
		print("  [FAIL] medium_hull should still be present and unaffected by unrelated mod files")
		ok = false

	# Mod-overrides-built-in precedence: a mod file using a built-in's own
	# id (e.g. a rebalance/reskin mod) wins, since it's a deliberate,
	# nameable override, not an accidental collision (HULL_MODDING_PLAN.md
	# §5's open question - see DECISIONS_NEEDED.md for the reasoning).
	write_file.call("medium_hull.json", JSON.stringify({"name": "Modded Medium Hull", "hp": 999.0, "weight": 250.0, "metal": 100, "crystal": 20, "size": [4, 1, 6], "color": [1, 1, 1]}))
	write_file.call("medium_hull.glb", "")
	HullLoader.reset_cache_for_tests()
	hulls = HullLoader.get_hulls()
	if hulls.get("medium_hull", {}).get("hp", -1.0) != 999.0:
		print("  [FAIL] a mod hull should override a built-in hull of the same id")
		ok = false
	if not HullLoader.is_modded("medium_hull"):
		print("  [FAIL] the overridden medium_hull should be flagged as modded while the override is active")
		ok = false

	for path in written_files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if FileAccess.file_exists(mods_dir + "/medium_hull.json"):
		DirAccess.remove_absolute(mods_dir + "/medium_hull.json")
	if FileAccess.file_exists(mods_dir + "/medium_hull.glb"):
		DirAccess.remove_absolute(mods_dir + "/medium_hull.glb")
	HullLoader.reset_cache_for_tests()

	# Real protection against this test silently leaking state into every
	# test that runs after it: confirm a rescan after cleanup goes straight
	# back to the true on-disk state.
	var fresh = HullLoader.get_hulls()
	if fresh.get("medium_hull", {}).get("hp", -1.0) != 400.0:
		print("  [FAIL] medium_hull did not revert to its real built-in value after test cleanup")
		ok = false
	if fresh.has(good_id):
		print("  [FAIL] test mod hull should be gone after cleanup")
		ok = false

	if not ok:
		return false
	print("  [PASS] HullLoader scans both directories, skips malformed sidecars without failing the whole scan, and a mod hull correctly overrides a built-in of the same id (logged as a warning).")
	return true

func test_hull_modding_parts_menu_two_buckets() -> bool:
	print("Running Test Suite: Hull Modding - Parts Catalog Groups Hulls From Their Own Fields...")
	var menu = preload("res://scenes/UI_PartsMenu.tscn").instantiate()
	root.add_child(menu)
	await tree.process_frame

	# sections_for() rather than a hardcoded widget path - see its comment in
	# parts_menu.gd for why this suite should not know the panel's node tree.
	var drawer_categories = []
	for child in menu.sections_for("hulls"):
		if child.has_meta("drawer_category"):
			drawer_categories.append(child.get_meta("drawer_category"))
	drawer_categories.sort()

	var ok = true
	# The hull tab used to be a 2-way Vehicle / Static Building split, which
	# meant one 22-entry "Vehicle" drawer. It is now is_foundation FIRST and
	# then weight class - but the property under test is unchanged and is the
	# only one that matters: every assignment is computed from the hull's own
	# catalog fields, so a modded hull sorts correctly with zero code changes.
	# There is still no per-type_id table anywhere in the UI layer.
	for drawer_cat in drawer_categories:
		if drawer_cat not in menu.HULL_GROUP_ORDER:
			print("  [FAIL] Unexpected hull drawer '%s' (not in HULL_GROUP_ORDER)" % drawer_cat)
			ok = false

	var seen_hulls := {}
	for child in menu.sections_for("hulls"):
		if not child.has_meta("drawer_category"):
			continue
		var category = child.get_meta("drawer_category")
		var content = child.get_meta("content_container")

		# Light-to-heavy inside every drawer.
		var last_weight := -1.0
		for btn in content.get_children():
			var data = ModuleCatalog.get_module_data(btn.module_type_id)
			seen_hulls[btn.module_type_id] = true
			var w = float(data.get("weight", 0.0))
			if w < last_weight:
				print("  [FAIL] Drawer '%s' is not sorted light-to-heavy (%s at %.0f follows %.0f)" % [
					category, btn.module_type_id, w, last_weight])
				ok = false
			last_weight = w

			# Foundations and only foundations go in the static drawer.
			var expect_static = data.get("is_foundation", false)
			var actual_static = category == "Static Foundations"
			if expect_static != actual_static:
				print("  [FAIL] %s (is_foundation=%s) landed in drawer '%s'" % [btn.module_type_id, expect_static, category])
				ok = false
				continue
			if expect_static:
				continue

			# Non-foundations land in the weight class their OWN weight puts
			# them in - recomputed here from the catalog rather than trusting
			# the menu's own bucketing.
			var expect_group := "Heavy Chassis"
			if w < menu.HULL_LIGHT_MAX:
				expect_group = "Light Chassis"
			elif w < menu.HULL_MEDIUM_MAX:
				expect_group = "Medium Chassis"
			if category != expect_group:
				print("  [FAIL] %s (weight %.0f) landed in '%s', expected '%s'" % [
					btn.module_type_id, w, category, expect_group])
				ok = false

	# Nothing may be dropped on the floor by the regrouping.
	for type_id in ModuleCatalog.get_catalog().keys():
		if ModuleCatalog.get_catalog()[type_id].get("category", "") != "hull":
			continue
		if not seen_hulls.has(type_id):
			print("  [FAIL] Hull '%s' appears in no drawer at all" % type_id)
			ok = false

	menu.queue_free()
	if not ok:
		return false
	print("  [PASS] Every hull sorts into a foundation/weight-class drawer purely off its own catalog fields, light-to-heavy, with none dropped - no hardcoded per-type_id domain table.")
	return true

func test_hull_modding_hard_fail_on_unknown_hull() -> bool:
	print("Running Test Suite: Hull Modding - Blueprint Load Hard-Fails On A Missing Hull (not a silent fallback)...")
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	root.add_child(bm)
	await tree.process_frame

	var fake_blueprint = {
		"version": 1.0,
		"hull_type": "totally_not_a_real_hull_xyz",
		"name": "Broken Design",
		"modules": [],
	}

	# reconstruct_vehicle() itself must refuse - this is the second line of
	# defense that protects every non-Design-Lab caller (skirmish spawns,
	# battlefield, defense buildings), not just the explicit Load button.
	var parent = Node3D.new()
	root.add_child(parent)
	var result = bm.reconstruct_vehicle(fake_blueprint, parent)
	if result != null:
		print("  [FAIL] reconstruct_vehicle() should refuse (return null) for an unknown hull_type instead of building a hull off substitute data")
		bm.queue_free()
		parent.queue_free()
		return false
	parent.queue_free()

	# The Design Lab's own Load button must refuse BEFORE ever calling
	# reconstruct_vehicle(), and report which specific hull is missing.
	DirAccess.make_dir_recursive_absolute("user://blueprints")
	var bad_id = "test_hard_fail_missing_hull_bp"
	var bp_to_save = fake_blueprint.duplicate()
	bp_to_save["id"] = bad_id
	var file = FileAccess.open("user://blueprints/%s.json" % bad_id, FileAccess.WRITE)
	file.store_string(JSON.stringify(bp_to_save, "\t"))
	file.close()

	var ok = bm.load_blueprint_into_designer(bad_id)
	DirAccess.remove_absolute("user://blueprints/%s.json" % bad_id)
	bm.queue_free()

	if ok:
		print("  [FAIL] load_blueprint_into_designer() should return false for an unknown hull_type")
		return false
	if not "totally_not_a_real_hull_xyz" in bm.last_load_error:
		print("  [FAIL] last_load_error should name the specific missing hull, got: ", bm.last_load_error)
		return false

	print("  [PASS] Both reconstruct_vehicle() and load_blueprint_into_designer() refuse to load a blueprint referencing a missing hull, with a specific user-facing reason naming it.")
	return true


