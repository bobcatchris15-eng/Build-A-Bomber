extends SceneTree
# Phase 3.5 acceptance: does anything actually shoot?
#
# Until this phase the battle layer could select, order, formation, path, harvest
# and produce - and could not fire a shot. auto_weapon.gd was listed as "reused
# as-is" but was never attached to anything, so stances and ATTACK orders were
# vocabulary over a runtime where nothing was lethal.
#
# The questions that need a real match rather than a suite:
#
#   * do weapons get attached to a spawned unit at all
#   * does the three-argument take_damage contract actually hold when a weapon
#     calls it - a one-argument version is a runtime error on every hit, which a
#     unit test of take_damage() alone would never catch
#   * do two hostile groups left alone kill each other
#   * can a unit destroy a STRUCTURE, which is the win condition's prerequisite
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_battle_combat.gd

const TICKS := 2400

# One armed design, used for both sides so any asymmetry in the result is the
# systems' doing rather than a matchup.
const COMBAT_BLUEPRINT := "res://data/loadout/bulwark_mbt.json"


func _init():
	var failures: Array = []

	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(6):
		await process_frame

	var blueprint: Dictionary = battle.bp_manager.load_blueprint(COMBAT_BLUEPRINT)
	if blueprint.is_empty():
		_finish(battle, ["could not load %s" % COMBAT_BLUEPRINT])
		return

	# --- Weapons are attached -----------------------------------------------
	var probe = battle.spawn_unit(blueprint, 0, Vector3(0, 0, 0))
	for _i in range(4):
		await process_frame
	if probe == null:
		_finish(battle, ["spawn_unit returned null for the combat blueprint"])
		return

	var weapons := 0
	for child in probe.hull_node.get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("auto_weapon.gd"):
			weapons += 1
	print("  weapons attached: %d" % weapons)
	print("  attack_range: %.1f m   vision_range: %.1f m" % [probe.attack_range, probe.vision_range])
	if weapons == 0:
		failures.append("no auto_weapon script was attached to an armed design")
	if probe.attack_range <= 0.0:
		failures.append("attack_range is zero on an armed design - weapons cannot be ranged")

	# --- The damage contract -------------------------------------------------
	# Called exactly the way auto_weapon.gd calls it (auto_weapon.gd:331). If the
	# signature is wrong this is a hard runtime error, not a wrong number.
	var before: float = probe.hp
	probe.take_damage(40.0, "kinetic", Vector3(0, 0, -30))
	print("  hp %.0f -> %.0f after a 40-damage kinetic hit from the front" % [before, probe.hp])
	if probe.hp == before:
		# Not necessarily a bug - the hit may have been absorbed or have stripped a
		# module instead - but worth surfacing, because a take_damage that never
		# does anything looks identical to a working one from outside.
		print("    (no hull loss - absorbed, or it stripped a module)")

	# --- Energy --------------------------------------------------------------
	print("  energy: %.0f / %.0f  (+%.1f/s)"
		% [probe.current_energy, probe.max_energy, probe.energy_regen_rate])
	if probe.max_energy > 0.0:
		var spent: bool = probe.spend_energy(probe.max_energy + 1.0)
		if spent:
			failures.append("spend_energy allowed an overdraw")
	probe.queue_free()
	await process_frame

	# --- Two sides, left alone ----------------------------------------------
	# Deliberately no orders issued. Weapons acquire on their own, so if the
	# attachment worked these groups fight without being told to.
	var red: Array = []
	var blue: Array = []
	for i in range(4):
		var r = battle.spawn_unit(blueprint, 0, Vector3(-12.0 + i * 8.0, 0, 14.0))
		var b = battle.spawn_unit(blueprint, 1, Vector3(-12.0 + i * 8.0, 0, -14.0))
		if r != null:
			red.append(r)
		if b != null:
			blue.append(b)
	for _i in range(4):
		await process_frame
	print("  engagement: %d vs %d at 28 m" % [red.size(), blue.size()])

	var red_hp_before := _total_hp(red)
	var blue_hp_before := _total_hp(blue)
	for _i in range(TICKS):
		await physics_frame

	var red_alive := _alive(red)
	var blue_alive := _alive(blue)
	print("  after %d ticks: team0 %d/%d alive (%.0f -> %.0f hp), team1 %d/%d alive (%.0f -> %.0f hp)"
		% [TICKS, red_alive, red.size(), red_hp_before, _total_hp(red),
			blue_alive, blue.size(), blue_hp_before, _total_hp(blue)])

	var damage_done: float = (red_hp_before - _total_hp(red)) + (blue_hp_before - _total_hp(blue))
	if damage_done <= 0.0:
		failures.append("two hostile groups at 28 m did no damage to each other in %d ticks" % TICKS)
	if red_alive == red.size() and blue_alive == blue.size() and damage_done < 1.0:
		failures.append("nothing was killed and nothing was hurt - weapons are not firing")

	# --- Structures are destructible ----------------------------------------
	# The win condition is "destroy the HQ", so a unit that cannot hurt a building
	# makes the whole mode unwinnable - and it fails silently, because units
	# killing units looks like combat working.
	var target_structure = null
	for s in battle.get_team_structures(1):
		target_structure = s
		break
	if target_structure == null:
		# No enemy base in this scene yet; damage a friendly one instead, since the
		# question is whether Structure.take_damage honours the weapon contract at
		# all, not whose building it is.
		for s in battle.get_team_structures(0):
			target_structure = s
			break
	if target_structure == null:
		failures.append("no structure available to test building damage")
	else:
		var s_before: float = target_structure.hp
		target_structure.take_damage(250.0, "explosive", target_structure.global_position + Vector3(0, 0, 20))
		print("  structure '%s' hp %.0f -> %.0f after a 250 explosive hit"
			% [target_structure.kind, s_before, target_structure.hp])
		if target_structure.hp >= s_before:
			failures.append("a structure took no damage from an explosive hit")

	_finish(battle, failures)


func _alive(units: Array) -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and not u.is_dead:
			n += 1
	return n


func _total_hp(units: Array) -> float:
	var total := 0.0
	for u in units:
		if is_instance_valid(u) and not u.is_dead:
			total += u.hp
	return total


func _finish(battle: Node, failures: Array) -> void:
	battle.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] battle phase 3.5 - combat")
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		print("[FAIL] battle phase 3.5: %d problem(s)" % failures.size())
		quit(1)
