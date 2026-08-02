extends SceneTree
# Dumps the resolved tweaks dict of every placed locomotion instance. Companion
# to probe_locomotion_layout.gd: that one proves nothing MOVED, this one proves
# nothing the mesh builders read CHANGED. Between them they cover both halves of
# what update_locomotion() produces.

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

func _init() -> void:
	await process_frame
	var out := PackedStringArray()
	for size_name in HULL_SIZES:
		var hull_size: Vector3 = HULL_SIZES[size_name]
		for type_id in TYPES:
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
				var keys: Array = m.tweaks.keys()
				keys.sort()
				var pairs := PackedStringArray()
				for k in keys:
					var v = m.tweaks[k]
					if v is float:
						pairs.append("%s=%.4f" % [k, v])
					else:
						pairs.append("%s=%s" % [k, v])
				rows.append("      {%s} phase=%s flip=%s" % [
					", ".join(pairs),
					child.get_meta("leg_phase", "-"),
					child.get_meta("scale_flip_x", false)])
			rows.sort()
			out.append("%s/%s:" % [size_name, type_id])
			for r in rows:
				out.append(r)
			placer.free()
			hull.free()
			await process_frame
	print("\n".join(out))
	quit()
