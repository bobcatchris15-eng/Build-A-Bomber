extends SceneTree
# Dumps where every locomotion type puts its instances, for every hull size in
# HULL_SIZES, as a GDScript literal ready to paste into run_tests.gd.
#
# This exists to make the placement factoring safe. update_locomotion() is a
# 540-line elif chain whose branches encode a long tail of hand-tuned visual
# fixes; the only way to refactor it without silently undoing one of those is
# to freeze its current output first and require the new code to reproduce it
# exactly. Run this BEFORE touching module_placer.gd - afterward it is a
# verification tool, not a capture tool.

const ModuleCatalog = preload("res://scripts/module_catalog.gd")

const HULL_SIZES := {
	"small": Vector3(2.0, 0.6, 3.0),
	"reference": Vector3(4.0, 1.0, 6.0),
	"large": Vector3(7.0, 2.2, 11.0),
}

const TYPES := [
	"wheels", "tracked_treads", "legs", "hover_engine", "helicopter_rotors",
	"fixed_wing_engine", "ornithopter_wing", "naval_propeller",
	"buoyant_envelope", "screw_drive",
]

func _fmt(v: Vector3) -> String:
	return "Vector3(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]

func _init() -> void:
	await process_frame
	var out := PackedStringArray()
	out.append("const GOLDEN_LOCOMOTION_LAYOUT := {")
	for size_name in HULL_SIZES:
		var hull_size: Vector3 = HULL_SIZES[size_name]
		out.append("\t\"%s\": {" % size_name)
		for type_id in TYPES:
			var hull := StaticBody3D.new()
			hull.name = "Hull"
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = hull_size
			shape.shape = box
			shape.name = "CollisionShape3D"
			hull.add_child(shape)
			root.add_child(hull)

			var placer := Node3D.new()
			placer.set_script(load("res://scripts/module_placer.gd"))
			placer.hull = hull
			root.add_child(placer)
			await process_frame

			placer.update_locomotion(type_id, {})
			await process_frame

			# Sorted so the fixture is stable regardless of child ordering.
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

			var parts := PackedStringArray()
			for r in rows:
				parts.append("[%s, %s]" % [_fmt(r["pos"]), _fmt(r["scale"])])
			out.append("\t\t\"%s\": {\"hull_y\": %.4f, \"stations\": [%s]}," % [
				type_id, hull.position.y, ", ".join(parts)])

			placer.free()
			hull.free()
			await process_frame
		out.append("\t},")
	out.append("}")
	print("\n".join(out))
	quit()
