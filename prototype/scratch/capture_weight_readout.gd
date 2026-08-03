extends SceneTree
# Visual capture for the weight/top-speed work: the TELEMETRY rail at three
# load states, because the load bar's colour, the warning panel's contrast, and
# whether any of it overflows the 320px dock are all things the headless suite
# cannot see. Six defects in the previous UI pass were caught only by reading
# screenshots, so this exists before the work is called done.
#
# Must run WITHOUT --headless: it reads back the rendered framebuffer.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_weight_readout.gd

const OUT_DIR = "res://progress_captures/2026-08-03-weight-system"
const ModuleDataScript = preload("res://scripts/module_data.gd")

var stats = null
var hull: Node3D = null

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.content_scale_size = Vector2i(1600, 900)
	await process_frame

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for _i in range(12):
		await process_frame

	stats = scene.get_node_or_null("UI_StatBlock")
	hull = scene.get_node_or_null("Hull")
	if stats == null or hull == null:
		print("[CAPTURE] FAIL stats=", stats, " hull=", hull)
		quit(1)
		return

	# The rail must be open for any of this to be judgeable - it defaults to
	# railed now (UI pass item 7).
	#
	# persist_key is cleared FIRST: set_dock_state() unconditionally calls
	# _save_state(), and its second argument is `animate`, not `persist`. Without
	# this, running a capture silently rewrites user://ui_layout.cfg and leaves
	# Chris's Design Lab with both docks expanded on next launch - which this
	# script did do once before the guard was added.
	var UIDockScript = load("res://scripts/ui_dock.gd")
	if stats.stats_dock:
		stats.stats_dock.persist_key = ""
		stats.stats_dock.set_dock_state(UIDockScript.State.EXPANDED, false)
	for _i in range(6):
		await process_frame

	scene.update_locomotion("wheels", {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 1})
	for _i in range(6):
		await process_frame
	stats.update_stats(hull)
	await _shot("01_within_capacity")

	# ~95%: the HAZARD band, which exists so the warning arrives BEFORE the
	# cliff rather than at it.
	_load_to(stats.drivetrain["capacity"] * 0.95)
	await _shot("02_near_capacity_hazard")

	_load_to(stats.drivetrain["capacity"] * 1.30)
	await _shot("03_overweight_warning")

	# Well past the bar's 125% pin, to confirm the panel still reads correctly
	# when the bar itself has nothing left to say.
	_load_to(stats.drivetrain["capacity"] * 2.2)
	await _shot("04_grossly_overweight")

	scene.queue_free()
	print("[CAPTURE] done -> %s" % OUT_DIR)
	quit()

# Adds ballast until the design's total weight reaches `target_kg`. Ballast is a
# real catalog part so nothing downstream sees a synthetic module.
#
# Coarse-then-fine, because the first version stepped in flat 120kg lumps and
# overshot a 95%-of-capacity target to 100.4% - which put the "near capacity"
# shot into the overloaded state instead, and in doing so exposed a real display
# bug (a 0.4% overload rendered as "Top Speed: 5.0 (was 5.0)"). Worth keeping
# precise: the hazard band between 90% and 100% is its own state and needs its
# own shot.
func _load_to(target_kg: float) -> void:
	for step in [120.0, 20.0, 4.0]:
		for _i in range(300):
			stats.update_stats(hull)
			if stats.drivetrain["weight"] + step > target_kg:
				break
			var node := Node3D.new()
			var d = ModuleDataScript.new()
			d.type_id = "artillery"
			d.category = "weapon"
			d.base_weight = step
			node.set_meta("module_data", d)
			hull.add_child(node)
	stats.update_stats(hull)

func _shot(name: String) -> void:
	for _i in range(4):
		await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[CAPTURE] %s  (%s | %s)" % [name, stats._load_label.text, stats._speed_label.text])
