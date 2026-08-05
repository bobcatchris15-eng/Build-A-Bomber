extends SceneTree
# Phase 0 acceptance for the rebuilt battle layer: does a match assemble, and do
# its units actually move when ordered?
#
# Not a test suite - suites live in tests/ and run under run_tests.gd. This is
# the throwaway-shaped probe that answers "is the skeleton alive" while the
# skeleton is being built, in the same spirit as probe_scene_loads.gd. It gets
# replaced by real suites in tests/battle/ once Phase 1 gives the layer an API
# worth pinning.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_battle_phase0.gd

const OrderScript = preload("res://scripts/battle/orders/order.gd")

# Physics ticks to let a unit travel. At 60 Hz this is ~4 seconds of sim, which
# is comfortably enough for the slowest bundled design to cover 25 m.
const TICKS := 240
const MOVE_DISTANCE := 25.0

func _init():
	var failures: Array = []

	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return

	var battle = packed.instantiate()
	root.add_child(battle)
	# _ready() awaits nothing in headless (build_navmeshes() is the blocking
	# branch), but the spawn loop still needs a tick to settle transforms.
	for _i in range(4):
		await process_frame

	# --- Assembly -----------------------------------------------------------
	var units: Array = battle.get_team_units(0)
	print("  units spawned: %d" % units.size())
	if units.is_empty():
		failures.append("no units spawned - check data/loadout/ and the spawn id")
		_finish(battle, failures)
		return

	for u in units:
		if not is_instance_valid(u.hull_node):
			failures.append("%s has no hull_node" % u.name)
		if u.max_hp <= 0.0:
			failures.append("%s has max_hp %.1f" % [u.name, u.max_hp])
		if u.get_node_or_null("SelectionProxy") == null:
			failures.append("%s has no SelectionProxy - frustum selection will not see it" % u.name)

	# --- Navigation ---------------------------------------------------------
	# A ground unit inside a real match must have picked up an agent off the
	# controller's duck-typed nav map getters. If this is null, every unit is
	# silently falling back to direct-line steering and will drive into lakes.
	var ground_units := 0
	for u in units:
		if u.is_flying or u.is_fixed_wing:
			continue
		ground_units += 1
		if u.nav_agent == null:
			failures.append("%s got no NavigationAgent3D" % u.name)
	print("  ground units: %d" % ground_units)

	# --- Movement -----------------------------------------------------------
	# The real question Phase 0 exists to answer. Order every unit somewhere and
	# check it closed most of the distance - not that it arrived, because arrival
	# radius and terrain both vary, but that it genuinely travelled.
	var mover = units[0]
	if mover.move_speed <= 0.0:
		# Not a failure on its own: a design with no locomotion legitimately
		# cannot move. Pick one that can, or say why none could.
		mover = null
		for u in units:
			if u.move_speed > 0.0:
				mover = u
				break
	if mover == null:
		failures.append("no spawned unit has a non-zero move_speed")
		_finish(battle, failures)
		return

	var start: Vector3 = mover.global_position
	var destination := start + Vector3(0, 0, -MOVE_DISTANCE)
	destination.y = battle.terrain_height_at(destination)
	mover.current_order = OrderScript.move(destination)

	for _i in range(TICKS):
		await physics_frame

	var travelled := Vector3(mover.global_position.x - start.x, 0.0, mover.global_position.z - start.z).length()
	var remaining := Vector3(mover.global_position.x - destination.x, 0.0, mover.global_position.z - destination.z).length()
	print("  %s (speed %.1f): travelled %.1f m, %.1f m short" % [mover.name, mover.move_speed, travelled, remaining])
	if travelled < 1.0:
		failures.append("ordered unit did not move at all (%.2f m)" % travelled)
	elif remaining > MOVE_DISTANCE * 0.5:
		failures.append("ordered unit covered less than half the distance (%.1f m short)" % remaining)

	_finish(battle, failures)


func _finish(battle: Node, failures: Array) -> void:
	battle.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] battle phase 0")
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		print("[FAIL] battle phase 0: %d problem(s)" % failures.size())
		quit(1)
