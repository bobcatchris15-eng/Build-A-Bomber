extends SceneTree
# Scratch: what the Design Lab range rows actually SAY, for three designs -
# a self-sufficient brawler, one that reaches slightly past its own eyes, and
# a spotter-only artillery piece.
#
# Reads the label text rather than screenshotting, because the thing being
# checked here is the wording and the arithmetic in it (six UI defects in the
# weight work were caught only by reading the rendered strings).
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_range_ui.gd --path .

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")
const WeaponRange = preload("res://scripts/weapon_range.gd")

func _mount(hull: Node3D, type_id: String, tweaks: Dictionary = {}) -> void:
	var m := Node3D.new()
	var d = ModuleDataScript.new()
	var cat = ModuleCatalog.get_module_data(type_id)
	d.type_id = type_id
	d.category = cat.get("category", "weapon")
	d.base_weight = cat.get("weight", 100.0)
	d.base_dps = cat.get("dps", 50.0)
	d.base_vision_bonus = cat.get("vision_bonus", 0.0)
	d.tweaks = tweaks
	m.set_meta("module_data", d)
	hull.add_child(m)

func _hull(hull_type: String) -> Node3D:
	var h := Node3D.new()
	h.set_meta("type_id", hull_type)
	root.add_child(h)
	return h

func _report(label: String, h: Node3D) -> void:
	var wr = WeaponRange.analyze(h)
	print("")
	print("--- %s ---" % label)
	if not wr["has_weapons"]:
		print("  Range: - (no weapons)")
		return
	var shortest: float = wr["shortest"]
	var longest: float = wr["longest"]
	var vision: float = wr["vision"]
	if absf(longest - shortest) >= 0.5:
		print("  Range: %.0f - %.0f  (%s)" % [shortest, longest, wr["tier_label"]])
	else:
		print("  Range: %.0f  (%s)" % [longest, wr["tier_label"]])
	print("  Vision: %.0f" % vision)
	var required: Array = wr["spotter_required"]
	var assisted: Array = wr["spotter_assisted"]
	if required.is_empty() and assisted.is_empty():
		print("  (no spotter warning)")
		return
	var names: Array = []
	if not required.is_empty():
		for w in required:
			names.append("%s (%.0f)" % [w["name"], w["reach"]])
		print("  [!] NEEDS A SPOTTER")
		print("      %s %s far past this design's own %.0f vision. Without another unit of yours watching the target, it can only shoot as far as it can see - roughly %.0f%% of its reach. Pair it with a scout or a radar mast and it works at full range." % [
			", ".join(names), "reaches" if names.size() == 1 else "reach",
			vision, (vision / longest) * 100.0])
	else:
		for w in assisted:
			names.append("%s (%.0f)" % [w["name"], w["reach"]])
		print("  [!] OUT-REACHES ITS OWN VISION")
		print("      %s can shoot further than this design can see (%.0f). Usable as-is, but a spotting unit or a radar mast is what unlocks the last %.0f units of that reach." % [
			", ".join(names), vision, longest - vision])

func _init():
	var brawler := _hull("assault_hull")
	_mount(brawler, "heavy_machine_gun")
	_mount(brawler, "flamethrower")
	_report("brawler: HMG + flamethrower on an assault hull", brawler)

	var mixed := _hull("medium_hull")
	_mount(mixed, "basic_cannon")
	_mount(mixed, "gauss_railgun")
	_report("overwatch: cannon + railgun on a medium hull", mixed)

	var arty := _hull("heavy_hull")
	_mount(arty, "artillery")
	_report("artillery: bare howitzer on a heavy hull", arty)

	var arty_spot := _hull("heavy_hull")
	_mount(arty_spot, "artillery")
	_mount(arty_spot, "sensor_suite")
	_report("artillery + its own radar mast", arty_spot)

	var barrel := _hull("medium_hull")
	_mount(barrel, "basic_cannon", {"barrel_length": 2.5})
	_report("cannon with a 2.5x barrel (tier jump)", barrel)

	var unarmed := _hull("medium_hull")
	_mount(unarmed, "smoke_discharger")
	_report("smoke only (zero-dps utility must not count as a weapon)", unarmed)

	quit(0)
