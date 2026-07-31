extends SceneTree
# PERFORMANCE_PLAN.md measurement pass (2026-07-31), written to test Chris's
# hypothesis that the remaining in-battle slowdown at 6-8 engaged units comes
# from weapon-module animation and per-shot munition object churn rather than
# from unit mesh/draw-call count.
#
# METHODOLOGY NOTE - the first version of this probe sampled
# Performance.get_monitor(TIME_PROCESS / TIME_PHYSICS_PROCESS) once per frame
# and produced nonsense (81ms of _process alongside 35fps, and
# median == p95 == max to the same 2 decimals across 120 samples). Godot's
# Performance monitors refresh on their own ~1Hz cadence, so per-frame reads
# return the same stale value repeatedly. Ground truth here is instead the
# real wall-clock frame interval measured by a probe Node's own _process
# delta, which is what the player actually feels. Monitors are still printed,
# but only as once-per-run scalars (draw calls, node count) where staleness
# doesn't matter.
#
# The second confound the first version had: the camera never moved, so the
# midfield combat units were partly outside the frustum while the idle units
# sat directly in front of it - the configs weren't rendering comparable
# scenes. All configs now spawn at the same midfield spot with the camera
# explicitly centered on it.
#
# Three configurations, all 8 units, same place, same camera - the only
# variable is what the units are DOING:
#
#   idle    - 8 units, all one team. No enemy, so no targeting, no traverse,
#             no fire. The standing cost of 8 built vehicles on screen.
#   cannon  - 4v4 basic_cannon (fire_rate 1.8s, one tracer mesh per shot).
#             Real targeting + traverse, minimal munition allocation.
#   churn   - 4v4 flamethrower + rotary_cannon (fire_rate 0.06s x6 spheres,
#             and 0.05s) - the highest per-shot allocation rate in the
#             arsenal, ~100+ fresh MeshInstance3D + Mesh + Material per
#             second per weapon.
#
# idle -> cannon isolates combat logic and module animation.
# cannon -> churn isolates munition allocation rate.
#
# Must run WITHOUT --headless (the headless rasterizer reports no render
# cost and would flatten exactly what we're trying to measure).
#
# Usage:
#   ./Godot_v4.3-stable_win64_console.exe --script scratch/perf_probe.gd --path . -- idle
#   ...                                                                        -- cannon
#   ...                                                                        -- churn

const SETTLE_FRAMES := 90
const SAMPLE_FRAMES := 240

# Units are made effectively immortal after spawn. WHY THIS IS ESSENTIAL, the
# hard way: the first version of this probe let a 4v4 fight resolve during a
# 150-frame settle, so by the time sampling began one side was usually wiped
# and the survivors had no target and fired nothing. That silently turned
# "8 units in sustained combat" into "however many units happened to survive,
# idling" - which is why the same unmodified `cannon` config measured 6.9ms,
# 20ms, 40ms and 120ms across four consecutive runs, and why a PerfTally pass
# recorded ZERO shots inside the sampling window. Any A/B conclusion drawn
# from that spread was noise. With attrition removed, every config holds a
# fixed 8 units firing continuously for the whole window.
const IMMORTAL_HP := 1.0e9

func _init():
	var config := "cannon"
	for arg in OS.get_cmdline_user_args():
		if arg in ["empty", "idle", "cannon", "churn"]:
			config = arg

	print("=== perf_probe: config '%s' ===" % config)

	var skirmish = preload("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(skirmish)
	current_scene = skirmish
	for i in range(8): await process_frame

	var bp_cannon := _blueprint([
		{"id": "basic_cannon", "pos": Vector3(0.0, 1.0, 1.5)},
	])
	var bp_churn := _blueprint([
		{"id": "flamethrower", "pos": Vector3(-0.8, 1.0, 1.2)},
		{"id": "rotary_cannon", "pos": Vector3(0.8, 1.0, 1.2)},
	])

	var mid = (skirmish.player_hq.global_position + skirmish.enemy_hq.global_position) * 0.5

	match config:
		"empty":
			# The control this investigation was missing: the map, terrain,
			# HQs, harvesters and hull shader with ZERO player units spawned.
			# Without it there is no way to tell whether the ~26ms floor that
			# 'idle' and 'churn' both sit at belongs to the units or to the
			# scene they stand in.
			pass
		"idle":
			# One team only: no valid enemy anywhere in range, so no
			# reacquisition, no traverse, no fire. Same footprint as the
			# combat configs so the render load matches.
			for i in range(8):
				skirmish.spawn_unit(bp_cannon, skirmish.PLAYER_TEAM,
					mid + Vector3(i * 4.0 - 8.0, 0, -4.0))
		"cannon":
			_spawn_engaged(skirmish, bp_cannon, 4, mid)
		"churn":
			# Flamethrower reaches only 9m, so the lines start close enough
			# that this measures sustained firing, not an approach march.
			_spawn_engaged(skirmish, bp_churn, 4, mid)

	# Put the action on screen, identically for every config.
	skirmish.camera.global_position.x = mid.x
	skirmish.camera.global_position.z = mid.z

	# Remove attrition as a variable (see IMMORTAL_HP above).
	for u in skirmish.get_tree().get_nodes_in_group("units"):
		u.max_hp = IMMORTAL_HP
		u.hp = IMMORTAL_HP

	print("Spawned. Settling for %d frames..." % SETTLE_FRAMES)
	for i in range(SETTLE_FRAMES): await process_frame

	# Ground truth: wall-clock interval between rendered frames.
	var frame_ms: Array = []
	var last := Time.get_ticks_usec()
	for i in range(SAMPLE_FRAMES):
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now

	print("\n--- config '%s' over %d frames ---" % [config, SAMPLE_FRAMES])
	_report("frame time (ms)", frame_ms)
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for s in sorted: total += s
	print("  implied fps: %.1f (from mean frame time)" % (1000.0 / (total / sorted.size())))
	print("  draw calls:  ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("  live nodes:  ", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("  munition nodes under effects parent: ", _count_effects(skirmish))
	# Proves the config actually held its unit count for the whole window - if
	# this is not 8, the run measured attrition and must be discarded.
	print("  units alive at end: ", _count_units(skirmish))
	print("  static memory (MB): %.1f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	quit(0)

# Two facing lines, close enough that the shortest-ranged weapon in either
# blueprint is already in range at spawn.
func _spawn_engaged(skirmish, bp: Dictionary, per_side: int, mid: Vector3) -> void:
	for i in range(per_side):
		skirmish.spawn_unit(bp, skirmish.PLAYER_TEAM,
			mid + Vector3(i * 4.0 - per_side * 2.0, 0, -4.0))
	for i in range(per_side):
		skirmish.spawn_unit(bp, skirmish.ENEMY_TEAM,
			mid + Vector3(i * 4.0 - per_side * 2.0, 0, 4.0))

# auto_weapon.gd parents its tracers/flames/explosions to _effects_parent();
# counting them shows how much transient geometry is alive at any instant.
func _count_effects(skirmish) -> int:
	var n := 0
	for child in skirmish.get_children():
		if child is MeshInstance3D:
			n += 1
	return n

func _count_units(skirmish) -> int:
	var n := 0
	for u in skirmish.get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not ("is_dead" in u and u.is_dead):
			n += 1
	return n

func _blueprint(weapons: Array) -> Dictionary:
	var modules: Array = [_module("wheels", Vector3(0.0, -1.0, 0.0))]
	for w in weapons:
		modules.append(_module(w["id"], w["pos"]))
	return {
		"version": 2.0, "hull_type": "medium_hull", "faction": "industrialists",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"locomotion": {"type_id": "wheels", "settings": {}},
		"modules": modules,
	}

func _module(type_id: String, pos: Vector3) -> Dictionary:
	return {
		"type_id": type_id, "name": type_id,
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"rotation": {"x": 0.0, "y": 0.0, "z": 0.0},
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"yaw_offset": 0.0, "tweaks": {},
	}

func _report(label: String, samples: Array) -> void:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in sorted: total += s
	print("  %s  mean %7.2f   median %7.2f   p95 %7.2f   max %7.2f" % [
		label,
		total / sorted.size(),
		sorted[int(sorted.size() * 0.5)],
		sorted[int(sorted.size() * 0.95)],
		sorted[sorted.size() - 1],
	])
