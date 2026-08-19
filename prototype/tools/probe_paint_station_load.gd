extends SceneTree
# Smoke test: load the ArmorBay scene and verify the paint station
# environment instantiates without the Transform3D constructor error.
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_paint_station_load.gd

func _init():
	var packed = load("res://scenes/ArmorBay.tscn")
	if packed == null:
		print("[FAIL] ArmorBay.tscn did not load")
		quit(1)
		return
	var bay = packed.instantiate()
	if bay == null:
		print("[FAIL] ArmorBay.tscn did not instantiate")
		quit(1)
		return
	root.add_child(bay)
	# Force a couple of frames so _ready runs and the paint station
	# environment is built.
	for _i in range(5):
		await process_frame
	# Find the paint station environment in the tree (it's a child of
	# the SubViewport's _preview_root).
	var paint_stations: Array = []
	_collect_nodes_of_script(bay, "res://scripts/paint_station_environment.gd", paint_stations)
	if paint_stations.is_empty():
		print("[FAIL] no paint_station_environment node in the ArmorBay scene")
		quit(1)
		return
	var ps: Node = paint_stations[0]
	print("[OK]   paint_station_environment instantiated with %d children" % ps.get_child_count())
	# The desktop (WoodDesktop) is the first child added in _ready.
	var desktop_count := 0
	var paint_bottle_count := 0
	for child in ps.get_children():
		if child.name == "WoodDesktop":
			desktop_count += 1
		if child.name == "PaintBottle":
			paint_bottle_count += 1
	print("[OK]   %d WoodDesktop, %d PaintBottle children" % [desktop_count, paint_bottle_count])
	if desktop_count == 0:
		print("[FAIL] no WoodDesktop node - environment build failed")
		quit(1)
		return
	if paint_bottle_count == 0:
		print("[FAIL] no PaintBottle nodes - bottle build failed")
		quit(1)
		return

	print("[PASS] ArmorBay scene loads, paint_station_environment instantiates, all expected children present.")
	quit(0)


func _collect_nodes_of_script(node: Node, script_path: String, out: Array) -> void:
	if node.get_script() != null and node.get_script().resource_path == script_path:
		out.append(node)
	for child in node.get_children():
		_collect_nodes_of_script(child, script_path, out)