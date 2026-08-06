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
