extends SceneTree
# Scratch: boots MainLab, places locomotion, then piles on weight and prints
# what the TELEMETRY rail actually SAYS at each step. The headless suite can
# assert the drivetrain maths; this is here to confirm the readout is wired to
# it, sits in the right place in the rail, and changes when the design does.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_weight_ui.gd --path .

const ModuleDataScript = preload("res://scripts/module_data.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

var stats = null
var hull: Node3D = null

func _dump(tag: String) -> void:
	stats.update_stats(hull)
	print("--- %s" % tag)
	print("    weight : %s" % stats.weight_label.text)
	print("    speed  : %s" % (stats._speed_label.text if stats._speed_label else "<none>"))
	print("    load   : %s  (visible=%s)" % [
		stats._load_label.text if stats._load_label else "<none>",
		stats._load_label.visible if stats._load_label else "n/a"])
	print("    bar    : %.1f / %.1f" % [stats._load_bar.value, stats._load_bar.max_value] if stats._load_bar else "<none>")
	print("    WARN   : visible=%s" % (stats._overweight_panel.visible if stats._overweight_panel else "n/a"))
	if stats._overweight_panel and stats._overweight_panel.visible:
		print("             %s" % stats._overweight_title.text)
		print("             %s" % stats._overweight_detail.text)

# Mounts `n` copies of a real catalog part, the way a player piling on armour
# and guns would.
func _add_modules(type_id: String, n: int) -> void:
	for _i in range(n):
		var node := Node3D.new()
		var d = ModuleDataScript.new()
		d.type_id = type_id
		var cat := ModuleCatalog.get_module_data(type_id)
		d.category = cat.get("category", "module")
		d.base_weight = cat.get("weight", 50.0)
		d.base_hp = cat.get("hp", 10.0)
		node.set_meta("module_data", d)
		hull.add_child(node)

func _init():
	root.size = Vector2i(1280, 800)
	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	for _i in range(8):
		await process_frame

	stats = scene.get_node_or_null("UI_StatBlock")
	hull = scene.get_node_or_null("Hull")
	if stats == null or hull == null:
		print("FAIL: stats=", stats, " hull=", hull)
		quit(1)
		return

	_dump("bare hull, NO locomotion (expect: no speed/load rows)")

	# Real placement path, so station counts are whatever the game would build.
	if scene.has_method("update_locomotion"):
		scene.update_locomotion("wheels", {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 1})
		for _i in range(4):
			await process_frame
	_dump("wheels, 4 axles, empty")

	_add_modules("heavy_armor_plate", 4)
	_dump("+4 heavy armor plates")

	_add_modules("artillery", 4)
	_dump("+4 artillery (expect OVERWEIGHT)")

	# The fix the warning panel tells the player about: more axles.
	if scene.has_method("update_locomotion"):
		scene.update_locomotion("wheels", {"wheel_size": 1.0, "num_axles": 8, "wheels_per_axle": 2})
		for _i in range(4):
			await process_frame
	_dump("same load, 8 axles x 2 wheels (expect back under capacity)")

	# Rail ordering: the readout must sit with the weight row it explains.
	print("")
	print("=== RAIL ORDER around the weight row ===")
	var vb = stats._rail_vbox
	for i in range(vb.get_child_count()):
		var c = vb.get_child(i)
		var mark := ""
		if c == stats.weight_label: mark = "  <- weight"
		elif c == stats._speed_label: mark = "  <- speed"
		elif c == stats._load_label: mark = "  <- load"
		elif c == stats._load_bar: mark = "  <- bar"
		elif c == stats._overweight_panel: mark = "  <- WARNING"
		if mark != "":
			print("  %2d  %-22s%s" % [i, c.get_class(), mark])
	quit(0)
