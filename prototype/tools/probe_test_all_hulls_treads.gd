extends SceneTree

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const MountReachScript = preload("res://scripts/mount_reach.gd")
const HullChineScript = preload("res://scripts/hull_chine.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")
const LocomotionMountScript = preload("res://scripts/locomotion_mount.gd")

const HULLS_DIR := "res://assets/models/hulls"

func _init():
	print("=== Testing Tracked Treads Across All Hulls ===")
	
	var dir = DirAccess.open(HULLS_DIR)
	if not dir:
		print("[FAIL] could not open ", HULLS_DIR)
		quit(1)
		return
		
	var files: Array[String] = []
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".glb") and not fname.ends_with("_collision.glb"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	
	print("Found %d hulls to test." % files.size())
	
	var total_hulls = 0
	var clean_hulls = 0
	var total_shafts_spawned = 0
	var total_shafts_skipped_no_hit = 0
	
	for glb_name in files:
		total_hulls += 1
		var path = "%s/%s" % [HULLS_DIR, glb_name]
		var glb: PackedScene = load(path)
		if not glb:
			continue
		var hull = glb.instantiate()
		var mesh_inst = MountReachScript._find_mesh_instance(hull)
		if not mesh_inst:
			hull.free()
			continue
			
		MountReachScript.clear_cache()
		MountReachScript.cache_hull(hull)
		
		var aabb = mesh_inst.get_aabb()
		var profile = HullChineScript.build(mesh_inst)
		var frame = HullChineScript.mount_frame(profile, 0.0, 1.0)
		
		var station_x = float(frame["half_width"]) + 0.04 * aabb.size.x
		var station_y = float(frame["position"].y)
		var tweaks = {
			"station_x": station_x,
			"station_y": station_y,
			"station_z": 0.0,
			"node_scale_x": 1.0,
			"node_scale_y": 1.0,
			"node_scale_z": 1.0,
			"target_length": aabb.size.z
		}
		
		var tread_node = Node3D.new()
		hull.add_child(tread_node)
		
		VisualBuilder.build_visual("tracked_treads", tread_node, Vector3(1.0, 1.0, aabb.size.z), Color.DARK_SLATE_GRAY, tweaks)
		
		clean_hulls += 1
		hull.free()
		
	print("Summary: %d/%d hulls processed cleanly." % [clean_hulls, total_hulls])
	quit(0)
