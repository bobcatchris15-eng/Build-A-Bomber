extends SceneTree
# Scratch: is the lift floor RIGHT for the case that moved the golden fixture, or
# is it masking a placement problem?
#
# test_locomotion_layout_matches_golden_fixture now reports
#   small/tracked_treads: hull sits at y=0.9000, golden fixture says 0.4886
# which is my maxf(-lowest, default_lift) in module_placer.gd. 0.9 is only the
# right answer if the hull's own underside really does hang BELOW the tread
# geometry - i.e. if the old 0.4886 was sinking the hull through the ground.
# This prints both numbers per hull so that is a measurement, not a guess.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/probe_lift_floor.gd --path .

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")

const HULLS := ["scout_hull", "light_hull", "medium_hull", "heavy_hull"]
const LOCOS := ["wheels", "tracked_treads", "legs", "half_track", "screw_drive"]

func _init():
	var lab = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in range(12):
		await process_frame

	print("hull / locomotion            hull_h  half   -lowest  applied  tread_btm  hull_btm  verdict")
	for hull_id in HULLS:
		for loco_id in LOCOS:
			# Fresh hull each time so nothing carries over.
			var existing = lab.get_node_or_null("Hull")
			if existing:
				existing.free()
				await process_frame
			lab._place_hull_from_ui(hull_id)
			for _i in range(6):
				await process_frame
			lab.update_locomotion(loco_id, {})
			for _i in range(8):
				await process_frame
			var hull = lab.get_node_or_null("Hull")
			if hull == null:
				continue

			var hull_h: float = ModuleCatalog.get_module_data(hull_id).get("size", Vector3.ONE).y
			var scale: Vector3 = hull.get_meta("hull_scale", Vector3.ONE)
			var half: float = hull_h * scale.y / 2.0

			var lowest := INF
			for child in hull.get_children():
				if not child.has_meta("module_data"):
					continue
				var d = child.get_meta("module_data")
				if d == null or d.category != "locomotion":
					continue
				var wb: AABB = VisualBuilder.measure_visual_bounds(child)
				if wb.size.length_squared() <= 0.0:
					continue
				lowest = minf(lowest, child.position.y + wb.position.y * child.scale.y)
			if lowest == INF:
				continue

			var applied: float = hull.position.y
			# Where each thing ends up in world space with the applied lift.
			var tread_btm: float = applied + lowest
			var hull_btm: float = applied - half
			var verdict := "ok"
			if hull_btm < -0.005:
				verdict = "HULL THROUGH GROUND %.3f" % hull_btm
			elif tread_btm > 0.02:
				verdict = "gear floats %.3f" % tread_btm
			print("  %-14s %-14s %5.2f  %5.3f  %7.4f  %7.4f  %8.3f  %8.3f  %s" % [
				hull_id, loco_id, hull_h, half, -lowest, applied, tread_btm, hull_btm, verdict])
	quit(0)
