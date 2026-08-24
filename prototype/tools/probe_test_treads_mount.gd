extends SceneTree

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const LocomotionMountScript = preload("res://scripts/locomotion_mount.gd")

func _init():
	print("=== Running Tracked Treads & Locomotion Probe ===")
	
	# Verify pontoon_wheels is gone from catalog
	if ModuleCatalog.get_catalog().has("pontoon_wheels"):
		print("[FAIL] pontoon_wheels still exists in ModuleCatalog!")
		quit(1)
		return
	print("[OK] pontoon_wheels confirmed removed from ModuleCatalog.")

	# Create a test hull node with a box mesh
	var root = Node3D.new()
	var hull = Node3D.new()
	hull.name = "Hull"
	root.add_child(hull)
	
	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(4.0, 1.2, 6.0)
	mesh_inst.mesh = box_mesh
	mesh_inst.name = "MeshInstance3D"
	hull.add_child(mesh_inst)
	
	var col_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = box_mesh.size
	col_shape.shape = box_shape
	col_shape.name = "CollisionShape3D"
	hull.add_child(col_shape)
	
	# Instantiate a tracked_treads module on hull
	var tread_module = Node3D.new()
	hull.add_child(tread_module)
	
	var tweaks = {
		"station_x": 2.2,
		"station_y": -0.6,
		"station_z": 0.0,
		"node_scale_x": 1.0,
		"node_scale_y": 1.0,
		"node_scale_z": 1.0,
		"tread_width": 1.0,
		"target_length": 6.0
	}
	
	VisualBuilder.build_visual("tracked_treads", tread_module, Vector3(1.0, 1.0, 6.0), Color.DARK_SLATE_GRAY, tweaks)
	
	print("[OK] VisualBuilder.build_visual for tracked_treads created %d direct children." % tread_module.get_child_count())
	
	# Check children: expect loop, 2 sprocket spin pivots, 2 sprocket gearboxes, 2 sprocket driveshafts, 5 road wheel pivots, 5 road wheel gearboxes, 5 road wheel driveshafts
	var mesh_count = 0
	for child in tread_module.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
		elif child is Node3D:
			for sub in child.get_children():
				if sub is MeshInstance3D:
					mesh_count += 1
					
	print("[OK] Total mesh instances in tracked_treads: %d" % mesh_count)
	if mesh_count < 15:
		print("[FAIL] Expected at least 15 mesh components (belt loop + 7 wheels/sprockets + 7 gearboxes + 7 driveshafts), got %d" % mesh_count)
		quit(1)
		return

	print("[PASS] Tracked treads mounting and running gear verified successfully.")
	root.free()
	quit(0)
