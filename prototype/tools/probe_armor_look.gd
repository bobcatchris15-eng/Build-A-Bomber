extends SceneTree
# Renders a hull with armor on its FRONT facet and saves a PNG, because
# "does this read as armor on the surface" is not a number and every headless
# assertion in this pass has agreed with itself while being visibly wrong.
#
# Run WINDOWED (headless Godot's dummy renderer does not rasterize):
#   Godot_v4.7.1-stable_win64_console.exe --path . --script tools/probe_armor_look.gd

const ModulePlacer = preload("res://scripts/module_placer.gd")

const OUT_DIR := "user://armor_look"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	root.size = Vector2i(900, 700)

	var placer := Node3D.new()
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await process_frame
	await process_frame

	placer._place_hull_from_ui("brenntal_medium_a")
	var hull: Node3D = placer.hull
	if hull == null:
		print("[FAIL] no hull"); quit(1); return
	await process_frame

	# Light + camera looking at the nose from front-left-above.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	light.light_energy = 1.5
	root.add_child(light)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(4.6, 2.6, -6.4)
	cam.look_at(Vector3(0, 0.2, -2.6), Vector3.UP)
	cam.current = true

	var shots := [["bare", ""], ["slat", "slat_armor"], ["plating", "armor_plating"],
		["foam", "ablative_foam"]]
	for shot in shots:
		var name: String = shot[0]
		var type_id: String = shot[1]
		var placed: Node3D = null
		if type_id != "":
			# Front facet: click the nose.
			placed = placer._place_weapon(type_id,
				hull.to_global(Vector3(0.0, 0.1, -2.95)), Vector3(0, 0, -1))
			if placed == null:
				print("[WARN] could not place ", type_id)
		for _i in range(12):
			await process_frame
		var img: Image = root.get_texture().get_image()
		img.save_png("%s/%s.png" % [OUT_DIR, name])
		print("saved ", name, "  placed=", placed != null)
		if placed != null and is_instance_valid(placed):
			placed.free()
			await process_frame

	print("output dir: ", ProjectSettings.globalize_path(OUT_DIR))
	quit(0)
