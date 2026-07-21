import sys

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'r') as f:
    content = f.read()

# Add ghost_mesh_mirror property
if "var ghost_mesh_mirror: MeshInstance3D = null" not in content:
    content = content.replace("var ghost_mesh: MeshInstance3D = null", "var ghost_mesh: MeshInstance3D = null\nvar ghost_mesh_mirror: MeshInstance3D = null")

# Destroy ghost_mesh_mirror
old_destroy = '''func _destroy_ghost_mesh():
	if ghost_mesh:
		ghost_mesh.queue_free()
		ghost_mesh = null'''

new_destroy = '''func _destroy_ghost_mesh():
	if ghost_mesh:
		ghost_mesh.queue_free()
		ghost_mesh = null
	if ghost_mesh_mirror:
		ghost_mesh_mirror.queue_free()
		ghost_mesh_mirror = null'''
content = content.replace(old_destroy, new_destroy)

# We want to replace the update block ONLY in _update_ghost_mesh
# The easiest way is to split the file at unc _update_ghost_mesh(
parts = content.split("func _update_ghost_mesh(screen_pos: Vector2, type_id: String):")

old_update = '''	if not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != catalog_data.size):
		var box = BoxMesh.new()
		box.size = catalog_data.size
		ghost_mesh.mesh = box
		
	# Offset height properly
	ghost_mesh.position = result.position + Vector3(0, catalog_data.size.y / 2.0, 0)'''

new_update = '''	if not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != catalog_data.size):
		var box = BoxMesh.new()
		box.size = catalog_data.size
		ghost_mesh.mesh = box
		
	# Offset height properly
	ghost_mesh.position = result.position + Vector3(0, catalog_data.size.y / 2.0, 0)
	
	var root = get_node("/root/MainLab")
	if root and root.mirror_enabled and category != "hull":
		var local_x = root.hull.to_local(result.position).x if root.hull else 0.0
		if abs(local_x) > 0.15:
			if not ghost_mesh_mirror:
				ghost_mesh_mirror = MeshInstance3D.new()
				root.add_child(ghost_mesh_mirror)
				var mat_mirror = StandardMaterial3D.new()
				mat_mirror.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat_mirror.albedo_color = Color(1, 1, 1, 0.4)
				ghost_mesh_mirror.material_override = mat_mirror
			
			ghost_mesh_mirror.visible = true
			ghost_mesh_mirror.mesh = ghost_mesh.mesh
			var mirror_pos = Vector3(-result.position.x, result.position.y, result.position.z)
			ghost_mesh_mirror.position = mirror_pos + Vector3(0, catalog_data.size.y / 2.0, 0)
		elif ghost_mesh_mirror:
			ghost_mesh_mirror.visible = false
	elif ghost_mesh_mirror:
		ghost_mesh_mirror.visible = false'''

parts[1] = parts[1].replace(old_update, new_update)

old_hide = '''	if not result:
		if ghost_mesh: ghost_mesh.visible = false
		return'''
new_hide = '''	if not result:
		if ghost_mesh: ghost_mesh.visible = false
		if ghost_mesh_mirror: ghost_mesh_mirror.visible = false
		return'''
parts[1] = parts[1].replace(old_hide, new_hide)

content = "func _update_ghost_mesh(screen_pos: Vector2, type_id: String):".join(parts)

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'w') as f:
    f.write(content)
print("Updated drag_drop_manager.gd")
