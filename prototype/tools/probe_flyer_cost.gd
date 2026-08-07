extends SceneTree
# What one flying unit costs, in physics milliseconds.
#
# THE REGRESSION THIS MEASURES. The rebuilt unit.gd's _apply_vertical() zeroed a
# flyer's vertical velocity and returned without ever setting an altitude, so a
# flyer held whatever Y it spawned at - a factory exit, which is ground level.
# A flyer inside the terrain collides with the ground and with every building
# standing on it (collision_mask is TERRAIN | BUILDINGS), and move_and_slide()
# then depenetrates it every frame for the rest of the match.
#
# The old runtime hit exactly this and measured it: 2.38 ms -> 15.57 ms of
# physics from a SINGLE flyer. It is worth measuring rather than eyeballing,
# because the symptom - "the game got slow" - is the same for a dozen causes and
# because the fix is invisible in a screenshot.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_flyer_cost.gd

const ModuleCatalog = preload("res://scripts/module_catalog.gd")

const SETTLE := 120
const SAMPLE := 600

# A flyer wedged in the ground drove physics 6.5x in the old runtime. Anything
# near that ratio means the altitude hold is not working again.
const MAX_RATIO := 2.5


func _init():
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	for _i in range(8):
		await process_frame

	# --- Baseline: the match as it starts, no flyer -------------------------
	var baseline := await _measure()
	print("  baseline physics: %.3f ms/frame (%d units)"
		% [baseline, battle.get_tree().get_nodes_in_group("units").size()])

	# --- Add one flyer -------------------------------------------------------
	var flyer_bp := _flyer_blueprint(battle)
	if flyer_bp.is_empty():
		print("[FAIL] no airborne design in the roster to test with")
		_cleanup(battle)
		quit(1)
		return
	print("  flyer design: %s" % flyer_bp.get("name", "?"))

	var home: Vector3 = battle._team_home(0)
	var flyer = battle.spawn_unit(flyer_bp, 0, home + Vector3(6, 0, 6))
	for _i in range(SETTLE):
		await physics_frame

	if not is_instance_valid(flyer):
		print("[FAIL] the flyer did not survive spawning")
		_cleanup(battle)
		quit(1)
		return
	if not flyer.is_flying:
		print("[FAIL] the design chosen is not actually airborne")
		_cleanup(battle)
		quit(1)
		return

	var ground_y: float = battle.terrain_height_at(flyer.global_position)
	var altitude: float = flyer.global_position.y - ground_y
	print("  flyer altitude above ground after settling: %.2f m (target %.2f)"
		% [altitude, flyer.target_altitude])

	var with_flyer := await _measure()
	var ratio: float = with_flyer / maxf(baseline, 0.001)
	print("  with one flyer:   %.3f ms/frame  (%.2fx baseline)" % [with_flyer, ratio])

	var failures: Array = []

	# THE REAL ASSERTION. A flyer must hold its cruise height above the ground,
	# not sit in it. Half the target is generous and still unambiguous - a wedged
	# flyer reads at roughly zero.
	if altitude < flyer.target_altitude * 0.5:
		failures.append("the flyer is at %.2f m above ground, not its %.2f m cruise altitude - it is in the terrain"
			% [altitude, flyer.target_altitude])

	if ratio > MAX_RATIO:
		failures.append("one flyer multiplied physics cost by %.2fx (%.3f -> %.3f ms)"
			% [ratio, baseline, with_flyer])

	_cleanup(battle)
	await process_frame
	if failures.is_empty():
		print("[PASS] one flyer costs %.2fx baseline and holds %.2f m" % [ratio, altitude])
		quit(0)
	else:
		for f in failures:
			print("  [FAIL] %s" % f)
		quit(1)


# Mean physics frame time over SAMPLE frames, after letting it settle.
func _measure() -> float:
	for _i in range(SETTLE):
		await physics_frame
	var total := 0.0
	for _i in range(SAMPLE):
		await physics_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return 1000.0 * total / float(SAMPLE)


# A design that actually flies.
#
# "airborne" is a trait of the LOCOMOTION module, not a field on the blueprint,
# so it is resolved through ModuleCatalog rather than read off the design - the
# first version of this probe looked for a `traits` key on the blueprint, found
# none, and reported "no airborne design in the roster" against a roster whose
# designs simply do not carry that key.
#
# The player's OWN saved designs are searched first, because the bundled roster
# contains no flyer at all and the report that started this was a real match
# flown with a saved one (RidgeBailiff-8H, a buoyant_envelope).
func _flyer_blueprint(battle) -> Dictionary:
	var pools: Array = [_saved_designs(battle), battle.roster]
	for pool in pools:
		for design in pool:
			if _is_airborne(design):
				return design
	return {}


func _is_airborne(design: Dictionary) -> bool:
	var loco: String = design.get("locomotion", {}).get("type_id", "")
	if loco == "" or not ModuleCatalog.module_exists(loco):
		return false
	return "airborne" in ModuleCatalog.get_module_data(loco).get("traits", [])


func _saved_designs(battle) -> Array:
	var out: Array = []
	var dir := DirAccess.open("user://blueprints")
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var bp: Dictionary = battle.bp_manager.load_blueprint("user://blueprints/" + file)
		if not bp.is_empty():
			out.append(bp)
	return out


func _cleanup(battle: Node) -> void:
	battle.queue_free()
