extends Control

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

var ghost_mesh: Node3D = null
var ghost_mesh_mirror: Node3D = null
var current_ghost_type: String = ""
var _cached_ghost_material: Material = null
var _ghost_shader: Shader = null

func _get_ghost_shader() -> Shader:
	if _ghost_shader != null:
		return _ghost_shader
		
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back;

uniform vec4 line_color : source_color = vec4(0.2, 1.0, 0.4, 0.9);

void fragment() {
	float NdotV = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - clamp(NdotV, 0.0, 1.0), 2.0);
	float line_alpha = smoothstep(0.15, 0.65, fresnel);
	
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a * line_alpha;
}
"""
	_ghost_shader = shader
	return _ghost_shader

func _get_foggy_part_material() -> Material:
	if _cached_ghost_material != null:
		return _cached_ghost_material
		
	var foggy_mat = StandardMaterial3D.new()
	foggy_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foggy_mat.albedo_color = Color(0.10, 0.26, 0.20, 0.42) # Foggy translucent teal-grey
	foggy_mat.roughness = 0.2
	foggy_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	# Feature Edge Contour Pass (renders clean vector lines around part contours, avoiding micro-triangle shell clutter)
	var edge_mat = ShaderMaterial.new()
	edge_mat.shader = _get_ghost_shader()

	foggy_mat.next_pass = edge_mat
	_cached_ghost_material = foggy_mat
	return _cached_ghost_material

func _apply_ghost_materials_recursive(node: Node, mat: Material):
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_ghost_materials_recursive(child, mat)

func _build_module_ghost_node(type_id: String) -> Node3D:
	var container = Node3D.new()
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var cat_size = catalog_data.get("size", Vector3.ONE)
	
	VisualBuilder.build_visual(type_id, container, cat_size, Color.WHITE, {})
	
	# Fallback box mesh if no visual children were spawned
	if container.get_child_count() == 0:
		var mi = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = cat_size
		mi.mesh = box
		container.add_child(mi)
		
	_apply_ghost_materials_recursive(container, _get_foggy_part_material())
	return container

func _build_hull_ghost_node(type_id: String) -> Node3D:
	var container = Node3D.new()
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var cat_size = catalog_data.get("size", Vector3.ONE)
	
	var hull_mesh = MeshAssetLoader.get_hull_mesh(type_id)
	var mi = MeshInstance3D.new()
	if hull_mesh != null:
		mi.mesh = hull_mesh
	else:
		var box = BoxMesh.new()
		box.size = cat_size
		mi.mesh = box
	container.add_child(mi)
	
	_apply_ghost_materials_recursive(container, _get_foggy_part_material())
	return container

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "module_part":
		var type_id = data["id"]
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
		var catalog_data = ModuleCatalog.get_module_data(type_id)
		var category = catalog_data.get("category", "module")
		
		var root = get_node("/root/MainLab")
		if category == "hull":
			if root:
				# clear_hull() detaches and frees the old hull IMMEDIATELY.
				if root.has_method("clear_hull"):
					root.clear_hull()
				if root.has_method("_place_hull_from_ui"):
					root._place_hull_from_ui(type_id)
		else:
			if root and root.has_method("_place_weapon_from_ui"):
				var result = _raycast_from_screen(at_position)
				if result:
					root._place_weapon_from_ui(type_id, result.position, result.normal)

func _collapse_parts_menu():
	var root = get_node_or_null("/root/MainLab")
	if root:
		var parts_menu = root.get_node_or_null("UI_PartsMenu")
		if parts_menu and parts_menu.has_method("collapse_all_drawers"):
			parts_menu.collapse_all_drawers()

func _update_ghost_mesh_hull(type_id: String):
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	
	if current_ghost_type != type_id or ghost_mesh == null:
		_destroy_ghost_mesh()
		_collapse_parts_menu()
		ghost_mesh = _build_hull_ghost_node(type_id)
		root.add_child(ghost_mesh)
		current_ghost_type = type_id

	ghost_mesh.visible = true
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var cat_size = catalog_data.get("size", Vector3.ONE)
	ghost_mesh.position = Vector3(0, cat_size.y / 2.0, 0)

# Helper to create/update the ghost mesh preview
func _update_ghost_mesh(screen_pos: Vector2, type_id: String):
	var result = _raycast_from_screen(screen_pos)
	if not result:
		if ghost_mesh: ghost_mesh.visible = false
		if ghost_mesh_mirror: ghost_mesh_mirror.visible = false
		return

	var root = get_node_or_null("/root/MainLab")
	if not root: return
		
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var cat_size = catalog_data.get("size", Vector3.ONE)
	
	if current_ghost_type != type_id or ghost_mesh == null:
		_destroy_ghost_mesh()
		_collapse_parts_menu()
		ghost_mesh = _build_module_ghost_node(type_id)
		root.add_child(ghost_mesh)
		current_ghost_type = type_id

	ghost_mesh.visible = true
	ghost_mesh.position = result.position + Vector3(0, cat_size.y / 2.0, 0)

	var is_symmetric = catalog_data.get("is_symmetric", true)
	if not is_symmetric and abs(result.position.x) > 0.1:
		if ghost_mesh_mirror == null:
			ghost_mesh_mirror = _build_module_ghost_node(type_id)
			root.add_child(ghost_mesh_mirror)
		ghost_mesh_mirror.visible = true
		ghost_mesh_mirror.position = Vector3(-result.position.x, ghost_mesh.position.y, result.position.z)
	else:
		if ghost_mesh_mirror:
			ghost_mesh_mirror.visible = false

func _notification(what: int):
	if what == NOTIFICATION_DRAG_END:
		_destroy_ghost_mesh()

func _destroy_ghost_mesh():
	if ghost_mesh:
		ghost_mesh.queue_free()
		ghost_mesh = null
	if ghost_mesh_mirror:
		ghost_mesh_mirror.queue_free()
		ghost_mesh_mirror = null
	current_ghost_type = ""

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
