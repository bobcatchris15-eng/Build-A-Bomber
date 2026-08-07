extends SceneTree
# REGENERATE THE GOLDEN LOCOMOTION FIXTURE, and say exactly what moved.
#
# Chris, 2026-08-07: "The golden fixture can be set to say it's passing in the
# current state. I'll get round to making sure it's more cohesive soon."
#
# The suite bails on its FIRST mismatch, so all it ever reported was
# small/legs. That is a report about the test's control flow, not about the
# drift - there may be one entry wrong or thirty, and re-pointing the fixture
# without knowing which would be exactly the silent-baseline-move the fixture
# exists to prevent.
#
# So this does two things, and the first is the important one:
#
#   1. DIFFS every entry against the committed fixture and prints what moved,
#      by how much. That list is what goes in the commit message, because a
#      golden-fixture change whose justification is "the test passes now" is
#      not a justification.
#
#   2. Emits the full replacement literal in source order, ready to paste.
#
# Mirrors test_locomotion.gd's harness exactly - same hull construction, same
# sort, same fields. If the two ever drift the fixture is meaningless, so this
# deliberately duplicates rather than sharing a helper that could be changed
# on one side only.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/regen_locomotion_fixture.gd

const SuiteBase = preload("res://tests/suite_base.gd")

const TOL := 0.001


func _init():
	await process_frame

	var golden: Dictionary = SuiteBase.GOLDEN_LOCOMOTION_LAYOUT
	var sizes: Dictionary = SuiteBase.GOLDEN_HULL_SIZES

	var drift: Array = []
	var fresh: Dictionary = {}

	for size_name in sizes:
		var hull_size: Vector3 = sizes[size_name]
		var expected_for_size: Dictionary = golden[size_name]
		fresh[size_name] = {}
		for type_id in expected_for_size:
			var measured := await _measure(hull_size, type_id)
			fresh[size_name][type_id] = measured
			_compare(size_name, type_id, expected_for_size[type_id], measured, drift)

	print("=== DRIFT vs COMMITTED FIXTURE ===")
	if drift.is_empty():
		print("  none - the fixture already matches. Nothing to regenerate.")
	else:
		for d in drift:
			print("  " + d)
	print("")
	print("  %d entr%s moved." % [drift.size(), "y" if drift.size() == 1 else "ies"])

	print("")
	print("=== REPLACEMENT LITERAL ===")
	print("const GOLDEN_LOCOMOTION_LAYOUT := {")
	for size_name in sizes:
		print("\t\"%s\": {" % size_name)
		for type_id in golden[size_name]:
			var e: Dictionary = fresh[size_name][type_id]
			var parts: Array = []
			for st in e["stations"]:
				parts.append("[%s, %s]" % [_v(st[0]), _v(st[1])])
			print("\t\t\"%s\": {\"hull_y\": %.4f, \"stations\": [%s]},"
				% [type_id, e["hull_y"], ", ".join(parts)])
		print("\t},")
	print("}")

	quit(0)


func _measure(hull_size: Vector3, type_id: String) -> Dictionary:
	var hull := StaticBody3D.new()
	hull.name = "Hull"
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = hull_size
	shape.shape = box
	hull.add_child(shape)
	root.add_child(hull)
	var placer := Node3D.new()
	placer.set_script(load("res://scripts/module_placer.gd"))
	placer.hull = hull
	root.add_child(placer)
	await process_frame

	placer.update_locomotion(type_id, {})
	await process_frame

	var rows := []
	for child in hull.get_children():
		if not child.has_meta("module_data"):
			continue
		var m = child.get_meta("module_data")
		if m == null or m.category != "locomotion":
			continue
		rows.append({"pos": child.position, "scale": child.scale})
	rows.sort_custom(func(a, b):
		if not is_equal_approx(a["pos"].x, b["pos"].x):
			return a["pos"].x < b["pos"].x
		if not is_equal_approx(a["pos"].y, b["pos"].y):
			return a["pos"].y < b["pos"].y
		return a["pos"].z < b["pos"].z)

	var hull_y: float = hull.position.y
	var stations: Array = []
	for r in rows:
		stations.append([r["pos"], r["scale"]])

	placer.free()
	hull.free()
	await process_frame
	return {"hull_y": hull_y, "stations": stations}


func _compare(size_name: String, type_id: String, want: Dictionary,
		got: Dictionary, drift: Array) -> void:
	var label := "%s/%s" % [size_name, type_id]
	var want_stations: Array = want["stations"]
	var got_stations: Array = got["stations"]

	if want_stations.size() != got_stations.size():
		drift.append("%-28s station COUNT %d -> %d"
			% [label, want_stations.size(), got_stations.size()])
		return

	var hull_dy: float = absf(float(want["hull_y"]) - got["hull_y"])
	if hull_dy > TOL:
		drift.append("%-28s hull_y %.4f -> %.4f  (%+.4f)"
			% [label, want["hull_y"], got["hull_y"], got["hull_y"] - float(want["hull_y"])])

	for i in range(got_stations.size()):
		var dp: float = (want_stations[i][0] as Vector3).distance_to(got_stations[i][0])
		var ds: float = (want_stations[i][1] as Vector3).distance_to(got_stations[i][1])
		if dp > TOL:
			drift.append("%-28s station %d pos %s -> %s  (moved %.4f)"
				% [label, i, _v(want_stations[i][0]), _v(got_stations[i][0]), dp])
		if ds > TOL:
			drift.append("%-28s station %d scale %s -> %s"
				% [label, i, _v(want_stations[i][1]), _v(got_stations[i][1])])


func _v(v: Vector3) -> String:
	return "Vector3(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]
