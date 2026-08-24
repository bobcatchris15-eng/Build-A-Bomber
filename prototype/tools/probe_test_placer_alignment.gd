extends SceneTree

const LocomotionMountScript = preload("res://scripts/locomotion_mount.gd")
const MountReachScript = preload("res://scripts/mount_reach.gd")
const HullChineScript = preload("res://scripts/hull_chine.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const ModulePlacer = preload("res://scripts/module_placer.gd")

func _init():
	print("--- Testing Final Placed Sprocket Corner Alignment ---")
	
	var hull_path = "res://assets/models/hulls/brenntal_medium_a.glb"
	var glb: PackedScene = load(hull_path)
	var hull = glb.instantiate()
	
	var mesh_inst = MountReachScript._find_mesh_instance(hull)
	var aabb = mesh_inst.get_aabb()
	print("Visible hull mesh AABB: position=", aabb.position, " size=", aabb.size)
	print("Expected front corner Z: %.3f, expected rear corner Z: %.3f" % [aabb.position.z, aabb.position.z + aabb.size.z])
	
	# Mock placer
	var placer = Node3D.new()
	placer.set_script(ModulePlacer)
	placer.hull = hull
	hull.add_child(mesh_inst.duplicate())
	
	var parts = LocomotionMountScript.rebuild(placer, "tracked_treads", {})
	print("Rebuild returned %d parts." % parts.size())
	
	for part in parts:
		print("Part global_pos: %s, scale: %s" % [part.position, part.scale])
		# Find sp_front_axle and sp_rear_axle
		for child in part.get_children():
			if child.name == VisualBuilder.SPIN_PIVOT_TREAD:
				var world_z = part.position.z + child.position.z * part.scale.z
				print("  Sprocket/Wheel Pivot local_z: %.3f -> world_z: %.3f" % [child.position.z, world_z])
				
	placer.free()
	hull.free()
	quit(0)
