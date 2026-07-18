extends SceneTree
# FABLE review chunk D verification captures:
# 1) Sidebar shows the new "Hull HP: X (modules +Y)" combat-true stats
# 2) Cost visibly jumps when switching to energy_shielding + thickness 3.0
# 3) Hull scale drag path resizes the AUTHORED mesh live (gizmo fix) - shown
#    via before/after silhouette at 1x vs 2x footprint

func _init():
	var out_dir = "res://progress_captures/2026-07-18_fable_fixes"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(10): await process_frame

	var cam = root.get_camera_3d()
	if cam and "_distance" in cam:
		cam._distance = 12.0
		cam.position.z = 12.0
		cam.get_parent().rotation.y = deg_to_rad(-30.0)
		cam.get_parent().rotation.x = deg_to_rad(-18.0)

	scene.clear_hull()
	await process_frame
	scene._place_hull_from_ui("medium_hull")
	scene.update_hull_appearance()
	for i in range(8): await process_frame

	var stat_ui = scene.get_node_or_null("UI_StatBlock")
	if stat_ui:
		stat_ui.update_stats(scene.hull)
	for i in range(4): await process_frame

	print("[CAPTURE] baseline hull + sidebar...")
	root.get_texture().get_image().save_png("%s/sidebar_baseline_steel_t1.png" % out_dir)

	# Fortress config: energy_shielding, thickness 3.0 - the cost line should
	# jump visibly (this combination used to be free).
	scene.hull.set_meta("armor_material", "energy_shielding")
	scene.hull.set_meta("armor_thickness", 3.0)
	scene.update_hull_appearance()
	if stat_ui:
		stat_ui.update_stats(scene.hull)
		stat_ui.sync_hull_ui(scene.hull)
	for i in range(6): await process_frame
	print("[CAPTURE] fortress config sidebar...")
	root.get_texture().get_image().save_png("%s/sidebar_shield_t3_costs_real.png" % out_dir)

	# Hull scale via the real gizmo drag path (_apply_scale_to_node) - the
	# authored mesh must resize live, and the scale must clamp at 2.0.
	scene.hull.set_meta("armor_material", "hardened_steel")
	scene.hull.set_meta("armor_thickness", 1.0)
	scene.update_hull_appearance()
	var gizmo = load("res://scenes/Gizmo3D.tscn").instantiate()
	scene.hull.add_child(gizmo)
	await process_frame
	gizmo._apply_scale_to_node(scene.hull, Vector3(9.0, 1.0, 9.0)) # asks for 9x, must clamp to 2x
	if stat_ui:
		stat_ui.update_stats(scene.hull)
	for i in range(6): await process_frame
	print("[CAPTURE] scaled hull (clamped to 2x) with live authored-mesh resize...")
	root.get_texture().get_image().save_png("%s/hull_scaled_2x_live_mesh.png" % out_dir)
	print("[CAPTURE] hull_scale meta after clamp: ", scene.hull.get_meta("hull_scale"))

	quit(0)
