extends Control

var ghost_mesh: MeshInstance3D = null

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "module_part":
		var type_id = data["id"]
		var ModuleCatalog = preload("res://scripts/module_catalog.gd")
		var catalog_data = ModuleCatalog.get_module_data(type_id)
		var category = catalog_data.get("category", "module")
		
		var root = get_node("/root/MainLab")
		if category == "hull":
			if root and root.get_node_or_null("Hull") != null:
				# Cannot drop hull if hull already exists
				_destroy_ghost_mesh()
				return false
			_update_ghost_mesh_hull(type_id)
			return true
			
		# Normal modules require a hull to exist first!
		if not root or root.get_node_or_null("Hull") == null:
			_destroy_ghost_mesh()
			return false
			
		# Normal modules require raycast
		_update_ghost_mesh(at_position, type_id)
		return true
		
	_destroy_ghost_mesh()
	return false

func _drop_data(at_position: Vector2, data: Variant):
	_destroy_ghost_mesh()
	
	if typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "module_part":
		var type_id = data["id"]
		var ModuleCatalog = preload("res://scripts/module_catalog.gd")
		var catalog_data = ModuleCatalog.get_module_data(type_id)
		var category = catalog_data.get("category", "module")
		
		var root = get_node("/root/MainLab")
		if category == "hull":
			if root and root.has_method("_place_hull_from_ui"):
				root._place_hull_from_ui(type_id)
		else:
			if root and root.has_method("_place_weapon_from_ui"):
				var result = _raycast_from_screen(at_position)
				if result:
					root._place_weapon_from_ui(type_id, result.position, result.normal)

func _update_ghost_mesh_hull(type_id: String):
	if not ghost_mesh:
		ghost_mesh = MeshInstance3D.new()
		get_node("/root/MainLab").add_child(ghost_mesh)
		
		# Setup ghost material
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.4)
		ghost_mesh.material_override = mat
		
	ghost_mesh.visible = true
	var ModuleCatalog = preload("res://scripts/module_catalog.gd")
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	
	if not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != catalog_data.size):
		var box = BoxMesh.new()
		box.size = catalog_data.size
		ghost_mesh.mesh = box
		
	ghost_mesh.position = Vector3(0, catalog_data.size.y / 2.0, 0)

# Helper to create/update the ghost mesh preview
func _update_ghost_mesh(screen_pos: Vector2, type_id: String):
	var result = _raycast_from_screen(screen_pos)
	if not result:
		if ghost_mesh: ghost_mesh.visible = false
		return
		
	if not ghost_mesh:
		ghost_mesh = MeshInstance3D.new()
		get_node("/root/MainLab").add_child(ghost_mesh)
		
		# Setup ghost material
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.4)
		ghost_mesh.material_override = mat
		
	ghost_mesh.visible = true
	
	# Update shape from catalog
	var ModuleCatalog = preload("res://scripts/module_catalog.gd")
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	
	if not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != catalog_data.size):
		var box = BoxMesh.new()
		box.size = catalog_data.size
		ghost_mesh.mesh = box
		
	# Offset height properly
	ghost_mesh.position = result.position + Vector3(0, catalog_data.size.y / 2.0, 0)
	
func _destroy_ghost_mesh():
	if ghost_mesh:
		ghost_mesh.queue_free()
		ghost_mesh = null

func _raycast_from_screen(screen_pos: Vector2):
	var camera = get_viewport().get_camera_3d()
	if not camera: return null
	
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_end = ray_origin + camera.project_ray_normal(screen_pos) * 1000.0
	
	var space_state = get_node("/root/MainLab").get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 3 # Hits Hull (1) and Modules (2)
	return space_state.intersect_ray(query)
