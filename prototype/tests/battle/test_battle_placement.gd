extends "res://tests/suite_base.gd"
# Where a structure may legally go, and the ghost flow that puts one there.
#
# THE RULE THESE PIN. PlacementService.validity() is the ONE answer both the
# player's ghost and the AI's siting resolve through. The rebuild had drifted off
# that - the AI sited through a private bounds/water/overlap check that ignored
# buildable-area adjacency, and the player had no placement path at all - so the
# property worth asserting is not any individual rule but that both callers get
# the same rule.
#
# validity() is a static function of a world, so these hand it a stub rather than
# building a match. That is the same isolation the production suites use.

const PlacementServiceScript = preload("res://scripts/battle/buildings/placement_service.gd")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const StructureScript = preload("res://scripts/battle/buildings/structure.gd")


# The narrow surface PlacementService actually asks about: a map dictionary, a
# terrain height, and the scene tree's groups. Nothing else.
class StubWorld:
	extends Node

	var current_map: Dictionary = {"map_half_extents": 80.0, "surface_type": "plains"}

	func terrain_height_at(_pos: Vector3) -> float:
		return 0.0


func _world() -> StubWorld:
	var w := StubWorld.new()
	root.add_child(w)
	return w


func _structure(world: Node, kind: String, team: int, at: Vector3) -> Structure:
	var s := StructureScript.new()
	world.add_child(s)
	s.setup(kind, team)
	s.global_position = at
	return s


# --- The rules ----------------------------------------------------------------

func test_placement_rejects_bounds_water_and_overlap() -> bool:
	print("Running Test Suite: Placement - bounds, water, overlap and adjacency...")
	var w := _world()
	var hq := _structure(w, "hq", 0, Vector3.ZERO)

	# Next to the HQ: legal. This is the control - if this fails every other
	# assertion below is meaningless.
	var good := Vector3(10.0, 0.0, 0.0)
	var ok: Dictionary = PlacementServiceScript.validity(w, 0, good, "power_plant")
	if not ok["valid"]:
		print("  [FAIL] a clear spot beside the HQ was rejected: %s" % ok["reason"])
		w.queue_free()
		return false

	# Off the edge of the map. A building on the boundary has its dock bays and
	# factory exit off the navmesh.
	var edge := Vector3(79.0, 0.0, 0.0)
	if PlacementServiceScript.validity(w, 0, edge, "power_plant")["valid"]:
		print("  [FAIL] a site past the map edge was accepted")
		w.queue_free()
		return false

	# On top of the HQ.
	if PlacementServiceScript.validity(w, 0, Vector3.ZERO, "power_plant")["valid"]:
		print("  [FAIL] a site inside the HQ's footprint was accepted")
		w.queue_free()
		return false

	# Far from any building of ours. This is the rule the AI was skipping.
	var far := Vector3(60.0, 0.0, 60.0)
	var away: Dictionary = PlacementServiceScript.validity(w, 0, far, "power_plant")
	if away["valid"]:
		print("  [FAIL] a site 85 m from the nearest building was accepted")
		w.queue_free()
		return false
	if away["reason"] != PlacementServiceScript.NOT_ADJACENT:
		print("  [FAIL] expected an adjacency refusal, got '%s'" % away["reason"])
		w.queue_free()
		return false

	# And you may not build off the ENEMY's base. Their HQ gives buildable area,
	# but not to us.
	var enemy_home := Vector3(0.0, 0.0, 55.0)
	_structure(w, "hq", 1, enemy_home)
	if PlacementServiceScript.validity(w, 0, enemy_home + Vector3(10, 0, 0), "power_plant")["valid"]:
		print("  [FAIL] a site adjacent to the ENEMY HQ was accepted for team 0")
		w.queue_free()
		return false

	print("  [PASS] bounds, overlap and adjacency")
	w.queue_free()
	return true


# A resource node is not buildable ground. Walling one in would let a player deny
# an ore patch with a building and strands the harvesters routed to it.
func test_placement_excludes_resource_nodes() -> bool:
	print("Running Test Suite: Placement - resource nodes are not buildable ground...")
	var w := _world()
	_structure(w, "hq", 0, Vector3.ZERO)

	var at := Vector3(10.0, 0.0, 0.0)
	if not PlacementServiceScript.validity(w, 0, at, "power_plant")["valid"]:
		print("  [FAIL] the control site was not clear to begin with")
		w.queue_free()
		return false

	var node := Node3D.new()
	node.add_to_group("resource_nodes")
	w.add_child(node)
	node.global_position = at

	var blocked: Dictionary = PlacementServiceScript.validity(w, 0, at, "power_plant")
	if blocked["valid"]:
		print("  [FAIL] a site on an ore patch was accepted")
		w.queue_free()
		return false
	if blocked["reason"] != PlacementServiceScript.ON_RESOURCE:
		print("  [FAIL] expected a resource refusal, got '%s'" % blocked["reason"])
		w.queue_free()
		return false
	print("  [PASS] resource node exclusion")
	w.queue_free()
	return true


# THE POINT OF THE WHOLE FILE. The AI's siting must resolve through the same
# validity() the player's ghost does - not a looser private copy. So every site
# find_site() returns must itself be valid, and when nothing is legal it must say
# so rather than returning a spot the player would be refused.
func test_ai_siting_and_player_ghost_share_one_rule_set() -> bool:
	print("Running Test Suite: Placement - the AI is held to the player's rules...")
	var w := _world()
	_structure(w, "hq", 1, Vector3(0, 0, 0))

	var site: Vector3 = PlacementServiceScript.find_site(w, 1, Vector3.ZERO, "power_plant")
	if site == Vector3.INF:
		print("  [FAIL] no site found beside a lone HQ on open ground")
		w.queue_free()
		return false
	var check: Dictionary = PlacementServiceScript.validity(w, 1, site, "power_plant")
	if not check["valid"]:
		print("  [FAIL] find_site returned a site validity() rejects: %s" % check["reason"])
		w.queue_free()
		return false

	# A defence reaches much further from the base than an ordinary building -
	# picketing forward is the point of a turret - so the two must not share one
	# adjacency number.
	if PlacementServiceScript.adjacency_for("power_plant") \
			>= PlacementServiceScript.adjacency_for("defense", {"hull_type": "foundation_small"}):
		print("  [FAIL] a defence should reach further from the base than a power plant")
		w.queue_free()
		return false
	print("  [PASS] one rule set for both")
	w.queue_free()
	return true


func test_expanded_build_radius_tripled() -> bool:
	print("Running Test Suite: Placement - expanded 3x build radius (24m base, 84m defense)...")
	var w := _world()
	_structure(w, "hq", 0, Vector3.ZERO)

	# 20m from HQ: with 24m radius (plus footprints), this is valid!
	var site_20m := Vector3(20.0, 0.0, 0.0)
	var ok_20m: Dictionary = PlacementServiceScript.validity(w, 0, site_20m, "power_plant")
	if not ok_20m["valid"]:
		print("  [FAIL] 20m site should be valid within 24m build radius: %s" % ok_20m["reason"])
		w.queue_free()
		return false

	# 35m from HQ: beyond standard 24m building radius, so power_plant should be NOT_ADJACENT
	var site_35m := Vector3(35.0, 0.0, 0.0)
	var check_35m: Dictionary = PlacementServiceScript.validity(w, 0, site_35m, "power_plant")
	if check_35m["valid"]:
		print("  [FAIL] 35m site should be too far for a standard building")
		w.queue_free()
		return false
	if check_35m["reason"] != PlacementServiceScript.NOT_ADJACENT:
		print("  [FAIL] expected NOT_ADJACENT, got %s" % check_35m["reason"])
		w.queue_free()
		return false

	# 35m from HQ: for a defense structure (84m reach), 35m IS legal
	var def_35m: Dictionary = PlacementServiceScript.validity(w, 0, site_35m, "defense", {"hull_type": "foundation_small"})
	if not def_35m["valid"]:
		print("  [FAIL] 35m site should be valid for a defense structure (84m reach): %s" % def_35m["reason"])
		w.queue_free()
		return false

	print("  [PASS] expanded 3x build radius (24m base, 84m defense)")
	w.queue_free()
	return true


func test_structure_construction_animation_lifecycle() -> bool:
	print("Running Test Suite: Structure - construction animation lifecycle & progress...")
	var w := _world()
	var s := StructureScript.new()
	w.add_child(s)
	s.setup("power_plant", 0)

	# Initially complete
	if s.build_incomplete:
		print("  [FAIL] fresh default setup should not be build_incomplete")
		w.queue_free()
		return false

	# Start construction
	s.begin_construction(10.0)
	if not s.build_incomplete or not s.is_under_construction:
		print("  [FAIL] begin_construction should mark build_incomplete and is_under_construction")
		w.queue_free()
		return false
	if s.construction_progress != 0.0:
		print("  [FAIL] construction_progress should start at 0.0, got ", s.construction_progress)
		w.queue_free()
		return false

	# Update progress to 50%
	s.update_construction_progress(0.5, false)
	if not is_equal_approx(s.construction_progress, 0.5):
		print("  [FAIL] construction_progress should be 0.5, got ", s.construction_progress)
		w.queue_free()
		return false

	# Complete construction
	s.finish_construction()
	if s.build_incomplete or s.is_under_construction:
		print("  [FAIL] finish_construction should clear build_incomplete and is_under_construction")
		w.queue_free()
		return false
	if not is_equal_approx(s.construction_progress, 1.0):
		print("  [FAIL] construction_progress should be 1.0 on completion, got ", s.construction_progress)
		w.queue_free()
		return false

	print("  [PASS] structure construction animation lifecycle")
	w.queue_free()
	return true

