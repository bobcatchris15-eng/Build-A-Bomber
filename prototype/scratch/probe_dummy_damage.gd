extends SceneTree
# Scratch: test_target_dummies_actually_take_damage_in_test_range has now
# failed three runs in a row, where before my auto_weapon.gd changes it
# alternated. That pattern says "regression", not "flaky", and it has to be
# checked rather than assumed.
#
# The prime suspect is my own edit: _deal_aoe_damage() now calls
# _maybe_crater() as its FIRST statement. If that call errors for any reason
# in the Battlefield/Test Range context (no real Skirmish parent, no
# terrain_height_at, a null effects parent), the rest of _deal_aoe_damage -
# including all the actual damage - never runs, which would look exactly
# like "dummies took no damage".
#
# Replicates the test's core (spawn Battlefield, find the weapon, watch total
# dummy health) over several trials so a pass/fail rate is visible rather
# than a single sample.
#
# Usage: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_dummy_damage.gd --path .

const TRIALS := 3
const TICKS := 400

func _init():
	var results := []
	for t in range(TRIALS):
		results.append(await _trial())
	print("")
	print("=== dummy damage over %d trials ===" % TRIALS)
	for r in results:
		print("  weapon=%-22s target_locked=%-5s  health %8.1f -> %8.1f   %s"
			% [r["weapon"], str(r["had_target"]), r["before"], r["after"],
				"DAMAGE" if r["after"] < r["before"] else "NONE"])
	quit(0)

func _trial() -> Dictionary:
	var bf = preload("res://scenes/Battlefield.tscn").instantiate()
	root.add_child(bf)
	current_scene = bf
	for i in range(10):
		await process_frame

	var out := {"weapon": "?", "before": 0.0, "after": 0.0, "had_target": false}
	var hull = bf.vehicle_hull
	if not hull:
		out["weapon"] = "NO HULL"
		bf.queue_free()
		await process_frame
		return out

	var weapon = null
	for child in hull.get_children():
		if child.has_method("_find_nearest_target"):
			weapon = child
			break
	if weapon == null:
		out["weapon"] = "NO WEAPON"
		bf.queue_free()
		await process_frame
		return out
	out["weapon"] = str(weapon.type_id)

	var dummies := []
	for d in bf.get_children():
		if d.is_in_group("targets") or ("health" in d and d.has_method("take_damage")):
			dummies.append(d)
	for d in dummies:
		out["before"] += d.health

	for i in range(TICKS):
		await physics_frame
		if weapon.target != null:
			out["had_target"] = true
	for d in dummies:
		if is_instance_valid(d):
			out["after"] += d.health

	bf.queue_free()
	await process_frame
	return out
