extends "res://tests/suite_base.gd"
# The tech tree: three lab buildings (tech_lab, physics_lab, exotics_lab) that
# feed no production queue and exist purely to be OWNED - ModuleCatalog names
# them as required_building on individual hulls/armour/modules/ammo,
# DesignCosting unions a design's gates into the list a player actually reads,
# and ProductionService refuses to queue a design against a gate the team
# hasn't built.
#
# Reconstructed after the git mishap (see 8932d27) took the original feature
# with it - only the SUITE_ORDER entries and this file's name survived.

const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
const DesignCostingScript = preload("res://scripts/battle/economy/design_costing.gd")
const EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
const ProductionServiceScript = preload("res://scripts/battle/economy/production_service.gd")

const MODEL_DIR := "res://assets/models/buildings/%s.glb"


# A world stub carrying only what ProductionService's gate asks of it: which
# building kinds a team currently owns a live copy of. Same isolation
# test_battle_placement.gd's StubWorld and test_battle_economy.gd's null-world
# service use - the queue/gate maths is asserted without a match, a navmesh or
# an actual Structure node.
class StubWorld:
	extends Node
	var owned: Dictionary = {}  # team -> Array[String] of kinds it has built

	func give(team: int, kind: String) -> void:
		if not owned.has(team):
			owned[team] = []
		owned[team].append(kind)

	func structures_of_kinds(team: int, kinds: Array) -> Array:
		var have: Array = owned.get(team, [])
		var out: Array = []
		for kind in have:
			if kind in kinds:
				out.append(kind)
		return out


func _service(world) -> ProductionService:
	var economy = EconomyServiceScript.new()
	economy.add_team(0, 30000)
	var production = ProductionServiceScript.new()
	production.setup(economy, world)
	production.add_team(0)
	return production


func test_building_catalog_prerequisites() -> bool:
	print("Running Test Suite: BuildingCatalog knows the three tech-tree labs...")
	var ok = true
	for kind in BuildingCatalogScript.TECH_LAB_KINDS:
		if not BuildingCatalogScript.has_kind(kind):
			print("  [FAIL] BuildingCatalog is missing '%s'" % kind)
			ok = false
			continue
		if not BuildingCatalogScript.is_tech_lab(kind):
			print("  [FAIL] is_tech_lab('%s') should be true" % kind)
			ok = false
		# A lab feeds no production queue - it exists to be owned, not to speed
		# up a line. CONTRIBUTORS deliberately has no entry for any of them.
		if BuildingCatalogScript.queue_for_kind(kind) != "":
			print("  [FAIL] '%s' should feed no queue, got '%s'" % [
				kind, BuildingCatalogScript.queue_for_kind(kind)])
			ok = false
		if not kind in BuildingCatalogScript.buildable_kinds():
			print("  [FAIL] '%s' should be orderable off the Building queue" % kind)
			ok = false
		var stats: Dictionary = BuildingCatalogScript.get_stats(kind)
		if stats.get("cost_metal", 0) <= 0 or stats.get("build_time", 0.0) <= 0.0:
			print("  [FAIL] '%s' should cost real metal and real time" % kind)
			ok = false

	if BuildingCatalogScript.is_tech_lab("hq"):
		print("  [FAIL] the HQ is not a tech lab")
		ok = false
	if BuildingCatalogScript.TECH_LAB_KINDS.size() != 3:
		print("  [FAIL] expected exactly 3 tech-tree kinds, got %d" % BuildingCatalogScript.TECH_LAB_KINDS.size())
		ok = false

	if ok:
		print("  [PASS] BuildingCatalog tech-tree entries")
	return ok


func test_module_catalog_building_requirements() -> bool:
	print("Running Test Suite: ModuleCatalog.get_required_building resolves every gate source...")
	var ok = true

	# A hull-level gate (HULL_REQUIREMENTS).
	if ModuleCatalogScript.get_required_building("dreadnought_hull") != "physics_lab":
		print("  [FAIL] dreadnought_hull should require physics_lab")
		ok = false
	if ModuleCatalogScript.get_required_building("medium_hull") != "":
		print("  [FAIL] medium_hull should require nothing")
		ok = false

	# An armour-material gate (ARMOR_MATERIAL_REQUIREMENTS).
	if ModuleCatalogScript.get_required_building("energy_shielding") != "exotics_lab":
		print("  [FAIL] energy_shielding should require exotics_lab")
		ok = false
	if ModuleCatalogScript.get_required_building("hardened_steel") != "":
		print("  [FAIL] hardened_steel should require nothing")
		ok = false

	# An unknown id gates nothing rather than erroring - same forgiving contract
	# get_module_data() has for a type_id the catalog does not know.
	if ModuleCatalogScript.get_required_building("not_a_real_thing") != "":
		print("  [FAIL] an unknown id should require nothing, not error")
		ok = false

	if ok:
		print("  [PASS] ModuleCatalog building-requirement tables")
	return ok


func test_design_costing_building_requirements() -> bool:
	print("Running Test Suite: DesignCosting unions every gate a design carries...")
	var ok = true

	# A bare, ungated design requires nothing.
	var bare: Array = DesignCostingScript.blueprint_required_buildings(
		{"hull_type": "medium_hull", "armor_material": "hardened_steel"})
	if not bare.is_empty():
		print("  [FAIL] a bare medium/hardened-steel design should require nothing, got ", bare)
		ok = false

	# Hull and armour gates union and come back in tier order regardless of
	# which is the "bigger" gate - dreadnought_hull is physics_lab,
	# reactive_armor is tech_lab, and tech_lab sorts first.
	var both: Array = DesignCostingScript.blueprint_required_buildings(
		{"hull_type": "dreadnought_hull", "armor_material": "reactive_armor"})
	if both != ["tech_lab", "physics_lab"]:
		print("  [FAIL] expected [tech_lab, physics_lab] in tier order, got ", both)
		ok = false

	# A single gate repeated across hull AND armour de-dupes to one entry.
	var deduped: Array = DesignCostingScript.blueprint_required_buildings(
		{"hull_type": "heavy_hull", "armor_material": "ablative_ceramic"})
	if deduped != ["tech_lab"]:
		print("  [FAIL] a repeated tech_lab gate should collapse to one entry, got ", deduped)
		ok = false

	# An unknown module type_id is skipped, same as blueprint_materials() skips
	# it - reconstruct_vehicle() never builds it, so it cannot gate anything.
	var with_unknown: Array = DesignCostingScript.blueprint_required_buildings({
		"hull_type": "airship_hull", "armor_material": "hardened_steel",
		"modules": [{"type_id": "not_a_real_module"}],
	})
	if with_unknown != ["exotics_lab"]:
		print("  [FAIL] airship_hull alone should require exotics_lab, got ", with_unknown)
		ok = false

	# An empty dictionary (falls back to medium_hull/hardened_steel) requires
	# nothing rather than erroring on missing keys.
	if not DesignCostingScript.blueprint_required_buildings({}).is_empty():
		print("  [FAIL] an empty blueprint dict should require nothing")
		ok = false

	if ok:
		print("  [PASS] DesignCosting.blueprint_required_buildings")
	return ok


func test_production_service_prerequisite_gating() -> bool:
	print("Running Test Suite: ProductionService refuses a design its team can't yet build...")
	var ok = true
	var gated_design := {"hull_type": "dreadnought_hull", "armor_material": "hardened_steel"}

	# No world (the queue-maths isolation every other production suite relies
	# on): nothing to check ownership against, so the gate does not apply.
	var isolated := _service(null)
	var isolated_job: Dictionary = isolated.enqueue_unit(
		0, gated_design, 100, 20.0, BuildingCatalogScript.QUEUE_HEAVY)
	if isolated_job.is_empty():
		print("  [FAIL] with no world behind it, the gate should not apply")
		ok = false

	# A real world, lab not yet built: refused. Give team 0 the manufactory and
	# HQ contributors up front, so every check below is isolated to the
	# tech-tree gate and not tangled up with ProductionService's separate
	# "does anything even feed this queue" contributor gate.
	var world := StubWorld.new()
	root.add_child(world)
	world.give(0, "heavy_manufactory")
	world.give(0, "hq")
	var production := _service(world)
	var blocked: Dictionary = production.enqueue_unit(
		0, gated_design, 100, 20.0, BuildingCatalogScript.QUEUE_HEAVY)
	if not blocked.is_empty():
		print("  [FAIL] a dreadnought hull should be refused without a physics_lab")
		ok = false
	if production.missing_required_buildings(0, gated_design) != ["physics_lab"]:
		print("  [FAIL] missing_required_buildings should report physics_lab, got ",
			production.missing_required_buildings(0, gated_design))
		ok = false

	# Build the lab: the same design now queues.
	world.give(0, "physics_lab")
	var allowed: Dictionary = production.enqueue_unit(
		0, gated_design, 100, 20.0, BuildingCatalogScript.QUEUE_HEAVY)
	if allowed.is_empty():
		print("  [FAIL] the design should queue once physics_lab is owned")
		ok = false
	if not production.missing_required_buildings(0, gated_design).is_empty():
		print("  [FAIL] nothing should be missing once physics_lab is owned")
		ok = false

	# The same gate applies to a blueprint-built defence off the Defense queue,
	# not just the unit tiers. Team 0 owns an hq (a Defense contributor) but no
	# exotics_lab, so this is refused by the tech-tree gate specifically, not
	# by having no contributor at all.
	var defence_design := {
		"hull_type": "pillbox_foundation", "armor_material": "energy_shielding"}
	var def_blocked: Dictionary = production.enqueue_structure(
		0, BuildingCatalogScript.QUEUE_DEFENSE, "defense", 50, 10.0, defence_design)
	if not def_blocked.is_empty():
		print("  [FAIL] a defence needing exotics_lab should be refused without one")
		ok = false

	# A prefab structure kind (empty blueprint) is never gated on itself - a
	# team must be able to order its very first lab.
	var first_lab: Dictionary = production.enqueue_structure(
		0, BuildingCatalogScript.QUEUE_BUILDING, "tech_lab", 200, 18.0, {})
	if first_lab.is_empty():
		print("  [FAIL] ordering a lab itself should never be gated by the tech tree")
		ok = false

	if ok:
		print("  [PASS] ProductionService tech-tree gate")
	return ok


func test_building_glb_meshes_exist() -> bool:
	print("Running Test Suite: the three tech-tree labs have authored GLB meshes...")
	var ok = true
	for kind in BuildingCatalogScript.TECH_LAB_KINDS:
		var path := MODEL_DIR % kind
		if not ResourceLoader.exists(path):
			print("  [FAIL] missing mesh for '%s' at %s" % [kind, path])
			ok = false
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			print("  [FAIL] %s did not load as a PackedScene" % path)
			ok = false
			continue
		var inst := packed.instantiate()
		if inst == null:
			print("  [FAIL] %s failed to instantiate" % path)
			ok = false
		else:
			inst.queue_free()
	if ok:
		print("  [PASS] tech-tree lab meshes")
	return ok
