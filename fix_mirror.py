import sys

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'r') as f:
    content = f.read()

# Fix 1: Add mirror_enabled toggle to update_locomotion
old_func = '''func update_locomotion(type_id: String, settings: Dictionary):
	if not hull: return
	
	# Save settings on hull metadata
	hull.set_meta("locomotion_type", type_id)
	hull.set_meta("locomotion_settings", settings)'''

new_func = '''func update_locomotion(type_id: String, settings: Dictionary):
	if not hull: return
	
	# Save settings on hull metadata
	hull.set_meta("locomotion_type", type_id)
	hull.set_meta("locomotion_settings", settings)
	
	# Temporarily disable mirroring so we don't spawn 4x locomotion components
	var old_mirror = mirror_enabled
	mirror_enabled = false'''
content = content.replace(old_func, new_func)

# Fix 2: Restore mirror_enabled at the end of update_locomotion
old_end = '''	var hull_catalog_data = ModuleCatalog.get_module_data(hull_type)
	if hull_catalog_data:
		var visual_yaw = ModuleCatalog.get_hull_visual_yaw_offset_deg(hull_type)
		hull.set_meta("visual_yaw_offset_deg", visual_yaw)'''

new_end = '''	var hull_catalog_data = ModuleCatalog.get_module_data(hull_type)
	if hull_catalog_data:
		var visual_yaw = ModuleCatalog.get_hull_visual_yaw_offset_deg(hull_type)
		hull.set_meta("visual_yaw_offset_deg", visual_yaw)
		
	mirror_enabled = old_mirror'''
content = content.replace(old_end, new_end)

# Fix 3: Use catalog size for hull_size instead of broken mesh.get_aabb() + rot_y swapping
old_size = '''	# Get actual hull size
	var hull_size = Vector3(4.0, 1.0, 6.0)
	var hull_bottom_y = -0.5
	var hull_scale = Vector3(1.0, 1.0, 1.0)
	if hull.has_meta("hull_scale"):
		hull_scale = hull.get_meta("hull_scale")
	var hull_shape = hull.get_node_or_null("CollisionShape3D")
	if hull_shape and hull_shape.shape is BoxShape3D:
		hull_size = hull_shape.shape.size
		hull_bottom_y = hull_bottom_y
	else:
		var mesh_inst = hull.get_node_or_null("MeshInstance3D")
		if mesh_inst and mesh_inst.mesh:
			# Use mesh_inst.scale instead of hull_scale because mesh_inst.scale includes the dynamic fit_scale!
			var aabb = mesh_inst.mesh.get_aabb()
			var size = aabb.size * mesh_inst.scale
			var rot_y = fmod(abs(rad_to_deg(mesh_inst.rotation.y)), 180.0)
			if rot_y > 45.0 and rot_y < 135.0:
				hull_size = Vector3(size.z, size.y, size.x)
			else:
				hull_size = size
			hull_bottom_y = aabb.position.y * mesh_inst.scale.y'''

new_size = '''	# Get actual hull size
	var hull_size = Vector3(4.0, 1.0, 6.0)
	var hull_bottom_y = -0.5
	var hull_scale = Vector3(1.0, 1.0, 1.0)
	if hull.has_meta("hull_scale"):
		hull_scale = hull.get_meta("hull_scale")
		
	var h_type = hull.get_meta("type_id") if hull.has_meta("type_id") else ""
	if h_type != "":
		var h_data = ModuleCatalog.get_module_data(h_type)
		hull_size = h_data.size * hull_scale
		
	var mesh_inst = hull.get_node_or_null("MeshInstance3D")
	if mesh_inst and mesh_inst.mesh:
		hull_bottom_y = mesh_inst.mesh.get_aabb().position.y * mesh_inst.scale.y
	else:
		hull_bottom_y = -hull_size.y / 2.0'''
content = content.replace(old_size, new_size)

# Fix 4: Also replace -hull_size.y / 4.0 with hull_bottom_y / 2.0 (for treads)
content = content.replace("var y_offset = -hull_size.y / 4.0", "var y_offset = hull_bottom_y / 2.0")

# Fix 5: Apply _apply_mirror_flip to the LEFT side wheels/treads
old_append_wheel = '''					wheel.get_meta("module_data").scale_multiplier = wheel.scale
					spawned_wheels.append(wheel)'''

new_append_wheel = '''					wheel.get_meta("module_data").scale_multiplier = wheel.scale
					if side < 0:
						wheel.set_meta("scale_flip_x", true)
						_apply_mirror_flip(wheel)
					spawned_wheels.append(wheel)'''
content = content.replace(old_append_wheel, new_append_wheel)

old_append_tread = '''				if tread.has_meta("module_data"):
					tread.get_meta("module_data").scale_multiplier = tread.scale
				spawned_wheels.append(tread)'''

new_append_tread = '''				if tread.has_meta("module_data"):
					tread.get_meta("module_data").scale_multiplier = tread.scale
				if side < 0:
					tread.set_meta("scale_flip_x", true)
					_apply_mirror_flip(tread)
				spawned_wheels.append(tread)'''
content = content.replace(old_append_tread, new_append_tread)

old_append_loop = '''				if loop.has_meta("module_data"):
					loop.get_meta("module_data").scale_multiplier = loop.scale
				spawned_wheels.append(loop)'''

new_append_loop = '''				if loop.has_meta("module_data"):
					loop.get_meta("module_data").scale_multiplier = loop.scale
				if side < 0:
					loop.set_meta("scale_flip_x", true)
					_apply_mirror_flip(loop)
				spawned_wheels.append(loop)'''
content = content.replace(old_append_loop, new_append_loop)

old_append_drum = '''				if drum.has_meta("module_data"):
					drum.get_meta("module_data").scale_multiplier = drum.scale
				spawned_wheels.append(drum)'''

new_append_drum = '''				if drum.has_meta("module_data"):
					drum.get_meta("module_data").scale_multiplier = drum.scale
				if side < 0:
					drum.set_meta("scale_flip_x", true)
					_apply_mirror_flip(drum)
				spawned_wheels.append(drum)'''
content = content.replace(old_append_drum, new_append_drum)

with open('e:/Build-A-Bomber/prototype/scripts/module_placer.gd', 'w') as f:
    f.write(content)
print("Updated module_placer.gd")
