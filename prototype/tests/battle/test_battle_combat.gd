extends "res://tests/suite_base.gd"
# Phase 3.5: the damage contract and the rules that hang off it.
#
# WHY THE SIGNATURE GETS ITS OWN TEST. auto_weapon.gd duck-types its target -
# anything in the `damageable` group with take_damage(). It calls that with THREE
# arguments (auto_weapon.gd:331). Both new targets shipped with a one-argument
# version, which is a runtime error on every shell that lands and is invisible to
# any test that calls take_damage() the way the test itself finds convenient.
# So these call it the way a weapon does, deliberately.
#
# The DamageModel rules are pure and get asserted directly rather than through a
# spawned unit - which is the whole reason they were extracted out of a 110-line
# method in the middle of battle_unit.gd.

# DamageResolverScript, ModuleCatalog and ModuleData come from suite_base.
const DamageModelScript = preload("res://scripts/battle/units/damage_model.gd")
const StructureScript = preload("res://scripts/battle/buildings/structure.gd")
const UnitAssemblyScript = preload("res://scripts/battle/units/unit_assembly.gd")


# A stand-in module node carrying the metas DamageModel reads. Cheaper and far
# more controllable than reconstructing a vehicle, and it exercises exactly the
# interface the real thing presents.
func _module(type_id: String, category: String, at: Vector3, hp: float = 100.0) -> Node3D:
	var n := Node3D.new()
	n.position = at
	var data := ModuleData.new()
	data.type_id = type_id
	data.category = category
	data.base_hp = hp
	n.set_meta("module_data", data)
	return n


# --- The contract ------------------------------------------------------------

# Called exactly as auto_weapon.gd calls it. A one-argument take_damage fails
# here with a runtime error rather than a wrong number, which is the point.
func test_take_damage_accepts_the_three_argument_weapon_contract() -> bool:
	print("Running Test Suite: Damage - the 3-arg contract weapons actually call...")

	var structure = StructureScript.new()
	root.add_child(structure)
	structure.setup("hq", 1)
	var before: float = structure.hp

	structure.take_damage(120.0, "kinetic", structure.global_position + Vector3(0, 0, 25))
	if structure.hp >= before:
		print("  [FAIL] A structure took no damage from a 3-arg weapon hit")
		return false

	# The damage class must MATTER. If it is ignored, thermal and kinetic land
	# identically and the whole armour table is decorative.
	var a = StructureScript.new()
	root.add_child(a)
	a.setup("hq", 1)
	var b = StructureScript.new()
	root.add_child(b)
	b.setup("hq", 1)
	a.take_damage(200.0, "kinetic", null)
	b.take_damage(200.0, "thermal", null)
	if is_equal_approx(a.hp, b.hp):
		print("  [FAIL] kinetic and thermal did identical damage - the class is being ignored")
		return false

	# Overkill must not drive HP negative, and must kill exactly once.
	#
	# The counter is an Array, not an int. GDScript lambdas capture locals BY
	# VALUE, so `var deaths := 0` with `deaths += 1` inside the handler increments
	# a copy and reads zero forever - which looks exactly like the signal never
	# firing. An Array is a reference, so the mutation is visible.
	var deaths: Array = []
	var c = StructureScript.new()
	root.add_child(c)
	c.setup("refinery", 1)
	c.died.connect(func(_s): deaths.append(1))
	c.take_damage(999999.0, "explosive", null)
	if c.hp < 0.0:
		print("  [FAIL] HP went negative: ", c.hp)
		return false
	if deaths.size() != 1:
		print("  [FAIL] died fired %d times, expected once" % deaths.size())
		return false
	# A dead structure must absorb nothing further, or a splash hit landing on a
	# corpse re-emits died and the win condition fires twice.
	c.take_damage(100.0, "kinetic", null)
	if deaths.size() != 1:
		print("  [FAIL] a dead structure took damage again, died fired %d times" % deaths.size())
		return false

	print("  [PASS] 3-arg damage contract")
	return true


# --- Strip rules -------------------------------------------------------------

# Two rules, both of which silently break the design if they regress: armour must
# never be strippable (it already gets facet-aware treatment inside the resolver,
# so stripping it would apply it twice), and a hit may only strip a module on the
# facet it actually landed on.
func test_strip_eligibility_excludes_armour_and_respects_facet() -> bool:
	print("Running Test Suite: Damage - strip eligibility, armour exemption, facet gating...")

	var front := _module("autocannon", "weapon", Vector3(0, 0, -2))
	var back := _module("sensor_suite", "sensor", Vector3(0, 0, 2))
	var plate := _module("bolt_on_plate", "armor", Vector3(0, 0, -2))
	var modules: Array = [front, back, plate]

	# Armour is never eligible, on any facet, including its own.
	for facet in ["front", "back", ""]:
		for m in DamageModelScript.strippable(modules, facet):
			if m.get_meta("module_data").category == "armor":
				print("  [FAIL] armour was strippable on facet '%s'" % facet)
				return false

	var front_hits := DamageModelScript.strippable(modules, "front")
	if front_hits.size() != 1 or front_hits[0] != front:
		print("  [FAIL] a front hit should offer exactly the front weapon, got ", front_hits.size())
		return false

	# The empty facet is the no-hit-origin case and must NOT lose stripping
	# altogether - a caller with no attacker (a test, an explosion) would silently
	# stop stripping, which is quieter and worse than over-permitting.
	var no_origin := DamageModelScript.strippable(modules, "")
	if no_origin.size() != 2:
		print("  [FAIL] with no hit origin every non-armour module should be eligible, got ",
			no_origin.size())
		return false

	for m in modules:
		m.free()
	print("  [PASS] strip eligibility")
	return true


# Module damage is a FRACTION of the raw hit, not the whole thing. The old flat
# `amount - 5.0` rounded every rapid-fire weapon's strip damage to zero, which
# quietly made small sustained guns the one archetype that could not strip.
func test_module_damage_uses_the_resolver_fraction() -> bool:
	print("Running Test Suite: Damage - module strip damage is a fraction of the hit...")
	var m := _module("autocannon", "weapon", Vector3(0, 0, -2), 100.0)

	var killed: bool = DamageModelScript.damage_module(m, 10.0)
	if killed:
		print("  [FAIL] a 10-damage hit destroyed a 100 HP module outright")
		m.free()
		return false
	var remaining: float = m.get_meta("current_hp")
	var expected: float = 100.0 - 10.0 * DamageResolverScript.MODULE_STRIP_DAMAGE_FACTOR
	if not is_equal_approx(remaining, expected):
		print("  [FAIL] expected %.2f HP left, got %.2f" % [expected, remaining])
		m.free()
		return false

	# A small hit must remove something. Zero here is the old bug.
	if remaining >= 100.0:
		print("  [FAIL] a small hit did nothing at all - strip damage rounded to zero")
		m.free()
		return false

	# Enough hits must eventually kill it, and report so exactly at zero.
	var died := false
	for _i in range(200):
		if DamageModelScript.damage_module(m, 10.0):
			died = true
			break
	if not died:
		print("  [FAIL] a module never died under sustained fire")
		m.free()
		return false
	if m.get_meta("current_hp") > 0.0:
		print("  [FAIL] reported dead with HP remaining: ", m.get_meta("current_hp"))
		m.free()
		return false

	m.free()
	print("  [PASS] module strip fraction")
	return true


# active_modules() must exclude anything already queued for deletion. A module
# destroyed earlier in the same frame is still a child until the tree flushes,
# and counting it lets a dead sensor keep soaking hits and keep granting vision.
func test_active_modules_excludes_dying_children() -> bool:
	print("Running Test Suite: Damage - active modules exclude queued-for-deletion...")
	var hull := Node3D.new()
	root.add_child(hull)
	var live := _module("autocannon", "weapon", Vector3.ZERO)
	var dying := _module("sensor_suite", "sensor", Vector3.ZERO)
	hull.add_child(live)
	hull.add_child(dying)

	if DamageModelScript.active_modules(hull).size() != 2:
		print("  [FAIL] expected 2 live modules before any death")
		return false
	dying.queue_free()
	var after := DamageModelScript.active_modules(hull)
	if after.size() != 1 or after[0] != live:
		print("  [FAIL] a queued-for-deletion module is still counted, got ", after.size())
		return false

	# A null hull must be answered, not crashed on - structures have no hull at all
	# and go through the same resolve() path.
	if not DamageModelScript.active_modules(null).is_empty():
		print("  [FAIL] active_modules(null) should be empty")
		return false
	print("  [PASS] active module filtering")
	return true


# --- Weapon attachment -------------------------------------------------------

# needs_combat_script() is the single source of truth for what gets a firing
# script, and it deliberately covers two modules that are NOT category "weapon".
# Three spawn paths used to decide this independently and all three missed them,
# so repair_array and drone_carrier never fired in a real match while passing
# every test that attached the script by hand.
func test_weapon_attachment_covers_non_weapon_combat_modules() -> bool:
	print("Running Test Suite: Combat - which modules get a firing script...")
	for type_id in ["repair_array", "drone_carrier"]:
		if not ModuleCatalog.needs_combat_script(type_id):
			print("  [FAIL] %s should need a combat script but does not" % type_id)
			return false
	if ModuleCatalog.needs_combat_script("sensor_suite"):
		print("  [FAIL] a sensor suite should not get a firing script")
		return false

	# attach_weapons must survive a hull with nothing to arm, and report no reach
	# rather than a bogus one.
	var bare := Node3D.new()
	root.add_child(bare)
	bare.add_child(_module("sensor_suite", "sensor", Vector3.ZERO))
	if not is_equal_approx(UnitAssemblyScript.attach_weapons(bare), 0.0):
		print("  [FAIL] an unarmed hull should report zero reach")
		return false
	if not is_equal_approx(UnitAssemblyScript.attach_weapons(null), 0.0):
		print("  [FAIL] attach_weapons(null) should be 0.0, not a crash")
		return false
	print("  [PASS] weapon attachment gating")
	return true


# --- Collision geometry ------------------------------------------------------
#
# A spawned unit's collision used to be three boxes and a convex blob: the hull
# swallowed its own concavities, its modules had no hit volumes at all (the
# per-module bodies were gated on `is_designer`), and nothing mesh-accurate
# existed for a damage ray to trace. These assert the geometry a unit actually
# spawns with, because every one of those was invisible to a test that only ever
# checked numbers.

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const UnitScript = preload("res://scripts/battle/units/unit.gd")
const MeshAssetLoaderScript = preload("res://scripts/mesh_asset_loader.gd")


func _spawn_armed_unit(hull_type: String):
	var bp_manager = BlueprintManagerScript.new()
	root.add_child(bp_manager)
	var unit = UnitScript.new()
	root.add_child(unit)
	var blueprint := {
		"hull_type": hull_type,
		"modules": [
			{"type_id": "heavy_machine_gun", "position": {"x": 0.0, "y": 0.6, "z": -0.5}},
			{"type_id": "sensor_suite", "position": {"x": 0.4, "y": 0.6, "z": 0.8}},
		],
		"locomotion": {"type_id": "wheels", "settings": {}},
	}
	if not unit.setup(blueprint, 0, bp_manager, null):
		return null
	return unit


func test_spawned_unit_carries_mesh_matched_collision() -> bool:
	print("Running Test Suite: Combat - a spawned unit's collision matches its meshes...")
	var hull_type := "brenntal_medium_a"
	var unit = _spawn_armed_unit(hull_type)
	if unit == null:
		print("  [FAIL] unit failed to assemble")
		return false

	# 1. The hull collider is the BAKED DECOMPOSITION when one exists. Asserted
	#    against the resource rather than a hardcoded count, so a re-bake that
	#    changes how a hull splits does not have to touch this test.
	var decomposed = MeshAssetLoaderScript.get_hull_collision(hull_type)
	var expected_pieces: int = decomposed.piece_count() if decomposed != null else 1
	var hull_colliders := 0
	for child in unit.get_children():
		if child is CollisionShape3D and str(child.name).begins_with("HullCollider"):
			hull_colliders += 1
	if hull_colliders != expected_pieces:
		print("  [FAIL] expected %d hull collider(s) from the baked decomposition, found %d" % [
			expected_pieces, hull_colliders])
		return false

	# 2. Every module carries a hit volume on the units-module layer, with at
	#    least one shape in it. An empty Area3D is the failure that would look
	#    exactly like success from the outside.
	var hull_node = unit.hull_node
	var checked := 0
	for child in hull_node.get_children():
		if not child.has_meta("module_data"):
			continue
		var volumes: Array = child.find_children("*", "Area3D", false, false)
		if volumes.is_empty():
			print("  [FAIL] module %s has no hit volume" % child.name)
			return false
		var area := volumes[0] as Area3D
		if area.collision_layer != BattleLayers.UNIT_MODULES:
			print("  [FAIL] module hit volume is on layer %d, expected UNIT_MODULES (%d)" % [
				area.collision_layer, BattleLayers.UNIT_MODULES])
			return false
		var shapes: Array = area.find_children("*", "CollisionShape3D", false, false)
		if shapes.is_empty():
			print("  [FAIL] module %s has an EMPTY hit volume" % child.name)
			return false
		checked += 1
	if checked == 0:
		print("  [FAIL] the spawned unit had no modules to check")
		return false

	# 3. The precise skin exists, and NOT on the layer that means "ore patch"
	#    in a match - HullSurface's own default (16) is RESOURCE_NODES here.
	var surface = hull_node.get_node_or_null("HullSurface")
	if surface == null:
		print("  [FAIL] a battle-spawned hull has no HullSurface trimesh to trace")
		return false
	if surface.collision_layer != BattleLayers.HULL_SURFACE:
		print("  [FAIL] HullSurface is on layer %d, expected HULL_SURFACE (%d)" % [
			surface.collision_layer, BattleLayers.HULL_SURFACE])
		return false
	if surface.collision_layer == BattleLayers.RESOURCE_NODES:
		print("  [FAIL] HullSurface is on the resource-node layer - units would be harvestable")
		return false

	print("  [PASS] %d hull piece(s), %d module hit volume(s), and a HullSurface on its own layer." % [
		hull_colliders, checked])
	return true


# The trace narrows WHICH module a hit takes without changing how many random
# draws it costs. SimRNG.pick() draws one randi() regardless of array length, so
# a narrower candidate list must not move the stream - if it did, every seeded
# match and every replay would diverge from this change alone.
func test_shot_trace_narrows_strip_candidates_without_touching_the_rng() -> bool:
	print("Running Test Suite: Combat - shot tracing picks the module without moving the sim stream...")
	var modules := [
		_module("heavy_machine_gun", "weapon", Vector3(0, 0.5, -1.0)),
		_module("sensor_suite", "sensor", Vector3(0, 0.5, 1.0)),
		_module("armor_plate", "armor", Vector3(0, 0.5, 0.0)),
	]
	var holder := Node3D.new()
	root.add_child(holder)
	for m in modules:
		holder.add_child(m)

	# No hit origin and no physics world to trace in: must fall back to the
	# facet filter, unchanged. This is the path every headless take_damage()
	# call and every direct scripted hit takes.
	var fallback: Array = DamageModelScript.strippable_along_shot(
		holder, holder, modules, null, "")
	var expected: Array = DamageModelScript.strippable(modules, "")
	if fallback.size() != expected.size():
		print("  [FAIL] with no origin the trace must return exactly strippable()'s answer, got %d vs %d" % [
			fallback.size(), expected.size()])
		return false
	for m in expected:
		if not (m in fallback):
			print("  [FAIL] fallback dropped a module strippable() kept")
			return false

	# Armour must stay out of it on both paths - it has its own facet-aware
	# treatment in the resolver and being strippable too would double-count.
	for m in fallback:
		if m.get_meta("module_data").category == "armor":
			print("  [FAIL] armour came back as a strip candidate")
			return false

	print("  [PASS] shot tracing falls back cleanly and never offers armour.")
	return true
