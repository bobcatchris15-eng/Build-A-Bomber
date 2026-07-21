extends Control

var ghost_mesh: MeshInstance3D = null
var ghost_mesh_mirror: MeshInstance3D = null

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "module_part":
		var type_id = data["id"]
		var ModuleCatalog = preload("res://scripts/module_catalog.gd")
		var catalog_data = ModuleCatalog.get_module_data(type_id)
		var category = catalog_data.get("category", "module")
		
		var root = get_node("/root/MainLab")
		if category == "hull":
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
			if root:
				# clear_hull() detaches and frees the old hull IMMEDIATELY.
				# queue_free() only marks it, so it was still sitting in the
				# tree under the name "Hull" when _place_hull_from_ui() added
				# the replacement - Godot then auto-renamed the new node
				# (to "@StaticBody3D@200"), after which get_node("Hull")
				# returned null forever: _can_drop_data() refused every
				# subsequent module drop, and gizmo_3d.gd's
				# "/root/MainLab/Hull" lookups broke. It also clears the
				# selection and clipping state that pointed at the old hull.
				if root.has_method("clear_hull"):
					root.clear_hull()
				if root.has_method("_place_hull_from_ui"):
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
	
	var cat_size = catalog_data.get("size", Vector3.ONE)
	if not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != cat_size):
		var box = BoxMesh.new()
		box.size = cat_size
		ghost_mesh.mesh = box
		
	ghost_mesh.position = Vector3(0, catalog_data.get("size", Vector3.ONE).y / 2.0, 0)

# Helper to create/update the ghost mesh preview
func _update_ghost_mesh(screen_pos: Vector2, type_id: String):
	var result = _raycast_from_screen(screen_pos)
	if not result:
		if ghost_mesh: ghost_mesh.visible = false
		if ghost_mesh_mirror: ghost_mesh_mirror.visible = false
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
	
	var cat_size = catalog_data.get("size", Vector3.ONE)
	if not ghost_mesh.mesh or (ghost_mesh.mesh is BoxMesh and ghost_mesh.mesh.size != cat_size):
		var box = BoxMesh.new()
		box.size = cat_size
		ghost_mesh.mesh = box
		
	# Offset height properly
	ghost_mesh.position = result.position + Vector3(0, cat_size.y / 2.0, 0)
	if not ghost_mesh_mirror:
		ghost_mesh_mirror = MeshInstance3D.new()
		get_node("/root/MainLab").add_child(ghost_mesh_mirror)
		ghost_mesh_mirror.material_override = ghost_mesh.material_override

	var is_symmetric = catalog_data.get("is_symmetric", true)
	if not is_symmetric and abs(result.position.x) > 0.1:
		ghost_mesh_mirror.visible = true
		if not ghost_mesh_mirror.mesh or (ghost_mesh_mirror.mesh is BoxMesh and ghost_mesh_mirror.mesh.size != cat_size):
			var box2 = BoxMesh.new()
			box2.size = cat_size
			ghost_mesh_mirror.mesh = box2
		ghost_mesh_mirror.position = Vector3(-result.position.x, ghost_mesh.position.y, result.position.z)
	else:
		ghost_mesh_mirror.visible = false
	
func _notification(what: int):
	# A drag that ends anywhere other than a successful drop on this overlay
	# (released over the parts list, over empty UI, or cancelled with Escape)
	# never calls _drop_data(), so the translucent preview box used to be left
	# parented to MainLab forever - one stale ghost per abandoned drag.
	if what == NOTIFICATION_DRAG_END:
		_destroy_ghost_mesh()

func _destroy_ghost_mesh():
	if ghost_mesh:
		ghost_mesh.queue_free()
		ghost_mesh = null
	if ghost_mesh_mirror:
		ghost_mesh_mirror.queue_free()
		ghost_mesh_mirror = null

func _raycast_from_screen(screen_pos: Vector2):
	var camera = get_viewport().get_camera_3d()
	if not camera: return null

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var root = get_node_or_null("/root/MainLab")

	# Prefer module_placer's precise-surface raycast so a dropped part lands on
	# the hull's visible skin. Hitting only the hull's bounding box (which is
	# what a plain layer-1 query returns) left parts floating wherever the mesh
	# curves away from that box.
	if root and root.has_method("surface_raycast"):
		var precise = root.surface_raycast(ray_origin, ray_dir)
		if precise:
			return precise

	var space_state = get_node("/root/MainLab").get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.collision_mask = 3 # Hits Hull (1) and Modules (2)
	return space_state.intersect_ray(query)
