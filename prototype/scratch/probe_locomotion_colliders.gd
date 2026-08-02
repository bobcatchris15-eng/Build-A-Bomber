extends SceneTree
# Measures how well each locomotion type's CLICK TARGET covers what it actually
# renders. Reports the fraction of the visual bounding box the collider box
# contains, plus the offset between their centres.
#
# 1.00 / 0.00 offset is a perfect fit. The historical failure mode here was a
# collider left at the module's bare catalog size while the builder scaled and
# offset the real geometry somewhere else entirely - which reads as "this part
# is very hard to click".

const TYPES := [
	"wheels", "tracked_treads", "legs", "hover_engine", "helicopter_rotors",
	"fixed_wing_engine", "ornithopter_wing", "naval_propeller",
	"buoyant_envelope", "screw_drive",
]

# Tweak sets chosen to push each builder away from its defaults, since a
# collider that only fits at default settings is the bug, not the fix.
const STRESS := {
	"wheels": {"wheel_size": 2.5, "wheels_per_axle": 3.0},
	"tracked_treads": {"tread_width": 2.5},
	"legs": {"leg_length": 2.0, "foot_size": 2.0},
	"helicopter_rotors": {"blade_length": 2.0, "duct": true},
	"hover_engine": {"emv_level": 2.5},
	"fixed_wing_engine": {"turbine_compression": 2.0, "afterburner": true},
	"ornithopter_wing": {"wingspan": 2.5},
	"naval_propeller": {"blade_pitch": 1.5, "blade_count": 6.0},
	"buoyant_envelope": {"blade_pitch": 1.5, "blade_count": 6.0},
	"screw_drive": {"drum_diameter": 2.0, "helix_depth": 1.5},
}

func _visual_bounds(module: Node3D) -> AABB:
	var bounds := AABB()
	var seen := false
	for mi in module.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var walker: Node = mi
		while walker != null and walker != module:
			if walker is Node3D:
				xf = walker.transform * xf
			walker = walker.get_parent()
		var part: AABB = xf * mi.mesh.get_aabb()
		bounds = part if not seen else bounds.merge(part)
		seen = true
	return bounds if seen else AABB()

func _init() -> void:
	await process_frame
	print("type                  fit   centre-offset   collider / visual")
	for type_id in TYPES:
		for label in ["default", "stressed"]:
			var hull := StaticBody3D.new()
			hull.name = "Hull"
			root.add_child(hull)
			var placer := Node3D.new()
			placer.set_script(load("res://scripts/module_placer.gd"))
			placer.hull = hull
			root.add_child(placer)
			await process_frame
			var settings: Dictionary = {} if label == "default" else STRESS.get(type_id, {})
			placer.update_locomotion(type_id, settings)
			await process_frame

			for child in hull.get_children():
				if not child.has_meta("module_data"):
					continue
				var m = child.get_meta("module_data")
				if m == null or m.category != "locomotion":
					continue
				var vis := _visual_bounds(child)
				var col_size := Vector3.ZERO
				var col_centre := Vector3.ZERO
				for sb in child.get_children():
					if not (sb is StaticBody3D):
						continue
					for cs in sb.get_children():
						if cs is CollisionShape3D and cs.shape is BoxShape3D:
							col_size = cs.shape.size
							col_centre = sb.position + cs.position
				var vol_v: float = max(vis.size.x * vis.size.y * vis.size.z, 0.0001)
				var vol_c: float = col_size.x * col_size.y * col_size.z
				print("%-20s %-8s ratio=%.2f  offset=%.3f  col=%.2fx%.2fx%.2f vis=%.2fx%.2fx%.2f" % [
					type_id, label, vol_c / vol_v,
					col_centre.distance_to(vis.get_center()),
					col_size.x, col_size.y, col_size.z,
					vis.size.x, vis.size.y, vis.size.z])
				break
			placer.free()
			hull.free()
			await process_frame
	quit()
