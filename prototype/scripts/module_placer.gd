extends Node3D

const ModuleData = preload("res://scripts/module_data.gd")
const Gizmo3D = preload("res://scenes/Gizmo3D.tscn")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const HullDeformScript = preload("res://scripts/hull_deform.gd")

@export var hull_path: NodePath
var hull: Node3D

var mirror_enabled: bool = true
var selected_module: Node3D = null
var clipping_detected: bool = false
var log_mutex: Mutex = Mutex.new()

var drag_pending: bool = false
var is_dragging_module: bool = false
var drag_start_mouse_pos: Vector2
var drag_start_module: Node3D = null
var drag_original_transform: Transform3D
var drag_original_mirror_transform: Transform3D
var drag_has_mirror: bool = false

# --- Undo/Redo (Design_Lab_UI_UX.md top-bar spec) ---
# Snapshot-based: each entry is a full serialized-hull dictionary (same shape
# blueprint_manager.gd saves to disk), captured just before a mutation. Undo
# restores the previous snapshot by tearing down and reconstructing the hull.
const MAX_UNDO_HISTORY = 50
var undo_stack: Array = []
var redo_stack: Array = []

func push_undo_snapshot():
	if not hull:
		return
	var bm = get_node_or_null("BlueprintManager")
	if not bm:
		return
	var snapshot = bm.serialize_hull(hull)
	if snapshot.is_empty():
		return
	undo_stack.append(snapshot.duplicate(true))
	if undo_stack.size() > MAX_UNDO_HISTORY:
		undo_stack.pop_front()
	redo_stack.clear()

func can_undo() -> bool:
	return undo_stack.size() > 0

func can_redo() -> bool:
	return redo_stack.size() > 0

func undo():
	if undo_stack.is_empty():
		return
	var bm = get_node_or_null("BlueprintManager")
	if not bm:
		return
	var current = bm.serialize_hull(hull) if hull else {}
	if not current.is_empty():
		redo_stack.append(current.duplicate(true))
	var snapshot = undo_stack.pop_back()
	_reconstruct_from_snapshot(snapshot)
	_log("Undo applied. History remaining: " + str(undo_stack.size()))

func redo():
	if redo_stack.is_empty():
		return
	var bm = get_node_or_null("BlueprintManager")
	if not bm:
		return
	var current = bm.serialize_hull(hull) if hull else {}
	if not current.is_empty():
		undo_stack.append(current.duplicate(true))
	var snapshot = redo_stack.pop_back()
	_reconstruct_from_snapshot(snapshot)
	_log("Redo applied. Redo remaining: " + str(redo_stack.size()))

func _reconstruct_from_snapshot(snapshot: Dictionary):
	var bm = get_node_or_null("BlueprintManager")
	if not bm:
		return
	if selected_module:
		_select_module(null)
	if hull and is_instance_valid(hull):
		var parent = hull.get_parent()
		if parent:
			parent.remove_child(hull)
		hull.free()
	hull = null
	clipping_detected = false
	hull = bm.reconstruct_vehicle(snapshot, self, true)
	get_tree().call_group("stat_ui", "update_stats", hull)
	get_tree().call_group("stat_ui", "sync_hull_ui", hull)
	check_all_clipping()

func _ready():
	if has_node("Hull"):
		hull = get_node("Hull")
		if hull:
			if not hull.has_meta("base_hull_size"):
				hull.set_meta("base_hull_size", Vector3(4.0, 1.0, 6.0))
			if not hull.has_meta("hull_scale"):
				hull.set_meta("hull_scale", Vector3(1.0, 1.0, 1.0))
			if not hull.has_meta("type_id"):
				hull.set_meta("type_id", "medium_hull")
			if not hull.has_meta("armor_material"):
				hull.set_meta("armor_material", "hardened_steel")
			if not hull.has_meta("armor_thickness"):
				hull.set_meta("armor_thickness", 1.0)
			update_hull_appearance()
		
func set_mirror_enabled(enabled: bool):
	mirror_enabled = enabled
	_log("Mirror toggled via UI: " + str(mirror_enabled))
		
func _log(msg: String):
	print(msg)
	WorkerThreadPool.add_task(Callable(self, "_async_write_log").bind(msg))

func _async_write_log(msg: String):
	log_mutex.lock()
	var file = FileAccess.open("user://game_log.txt", FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open("user://game_log.txt", FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(msg)
		file.close()
	log_mutex.unlock()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			mirror_enabled = not mirror_enabled
			_log("Mirror toggled: " + str(mirror_enabled))
			var tree = get_tree()
			if tree: tree.call_group("stat_ui", "set_mirror_toggle", mirror_enabled)
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			delete_selected_module()
		elif event.keycode == KEY_R:
			rotate_selected_module()
		elif event.keycode == KEY_Z and event.ctrl_pressed and not event.shift_pressed:
			undo()
		elif (event.keycode == KEY_Y and event.ctrl_pressed) or (event.keycode == KEY_Z and event.ctrl_pressed and event.shift_pressed):
			redo()
		elif event.keycode == KEY_ESCAPE:
			if is_dragging_module:
				is_dragging_module = false
				selected_module.transform = drag_original_transform
				if drag_has_mirror:
					var mirror = selected_module.get_meta("mirrored_counterpart")
					if mirror and is_instance_valid(mirror):
						mirror.transform = drag_original_mirror_transform
				_select_module(selected_module)
				check_all_clipping()
				_log("Module dragging cancelled.")

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_log("Left click detected in module_placer.gd!")
			
			if not hull:
				_log("ERROR: Hull is null! Cannot proceed.")
				return
				
			var camera = get_viewport().get_camera_3d()
			if not camera: 
				_log("ERROR: Camera is null! Cannot raycast.")
				return
			
			var space_state = get_world_3d().direct_space_state
			
			var mouse_pos = event.position
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0
			
			_log("Casting ray from " + str(ray_origin) + " to " + str(ray_end))
			
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			query.collision_mask = 7 # Layer 1 (Hull), Layer 2 (Modules), Layer 3 (Gizmos)
			query.collide_with_areas = true
			var result = space_state.intersect_ray(query)
			
			if result:
				_log("Raycast hit! Collider: " + str(result.collider.name))
				if result.collider.has_method("start_drag"):
					# We clicked a Gizmo Handle!
					result.collider.start_drag(event, result.position)
				elif result.collider.collision_layer & 1:
					# Hit the Hull
					_select_module(result.collider)
				else:
					# We clicked a Module!
					var module = result.collider.get_parent()
					_select_module(module)
					
					# Initialize drag movement if not locomotion
					if module and module.has_meta("module_data"):
						var data = module.get_meta("module_data")
						if data.category != "locomotion":
							drag_pending = true
							drag_start_mouse_pos = event.position
							drag_start_module = module
							drag_original_transform = module.transform
							drag_has_mirror = module.has_meta("mirrored_counterpart")
							if drag_has_mirror:
								var mirror = module.get_meta("mirrored_counterpart")
								if mirror and is_instance_valid(mirror):
									drag_original_mirror_transform = mirror.transform
			else:
				_log("Raycast missed. Deselecting.")
				_select_module(null)
		else:
			# Left click released
			if is_dragging_module:
				is_dragging_module = false
				_select_module(selected_module)
				get_tree().call_group("stat_ui", "update_stats", hull)
				check_all_clipping()
				_log("Module dragging finished.")
			drag_pending = false
			drag_start_module = null

	if event is InputEventMouseMotion:
		if drag_pending and drag_start_module and is_instance_valid(drag_start_module):
			if event.position.distance_to(drag_start_mouse_pos) > 8:
				push_undo_snapshot()
				is_dragging_module = true
				drag_pending = false
				var old_gizmo = selected_module.get_node_or_null("Gizmo3D")
				if old_gizmo:
					old_gizmo.queue_free()
				_log("Module dragging started.")
				
		if is_dragging_module and selected_module and is_instance_valid(selected_module):
			var camera = get_viewport().get_camera_3d()
			if camera:
				var space_state = get_world_3d().direct_space_state
				var mouse_pos = event.position
				var ray_origin = camera.project_ray_origin(mouse_pos)
				var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0
				
				var exclude_list = []
				_get_colliders_recursive(selected_module, exclude_list)
				if selected_module.has_meta("mirrored_counterpart"):
					var mirror = selected_module.get_meta("mirrored_counterpart")
					if mirror and is_instance_valid(mirror):
						_get_colliders_recursive(mirror, exclude_list)
						
				var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
				query.collision_mask = 1 # Only hit the Hull
				query.exclude = exclude_list
				
				var result = space_state.intersect_ray(query)
				if result:
					_update_module_placement(selected_module, result.position, result.normal)
					check_all_clipping()

func rotate_selected_module():
	if not selected_module or selected_module == hull: return
	push_undo_snapshot()

	var yaw = selected_module.get_meta("yaw_offset", 0.0)
	yaw += PI / 2.0
	if yaw >= 2.0 * PI - 0.01:
		yaw = 0.0
	selected_module.set_meta("yaw_offset", yaw)
	
	selected_module.rotate_object_local(Vector3.UP, PI / 2.0)
	
	if selected_module.has_meta("mirrored_counterpart"):
		var mirror = selected_module.get_meta("mirrored_counterpart")
		if mirror and is_instance_valid(mirror):
			mirror.set_meta("yaw_offset", -yaw)
			mirror.rotate_object_local(Vector3.UP, -PI / 2.0)
			
	check_all_clipping()
	_log("Rotated module to yaw_offset: " + str(yaw))
	
	# Trigger UI updates
	get_tree().call_group("stat_ui", "on_module_selected", selected_module)
	get_tree().call_group("stat_ui", "update_stats", hull)

func _select_module(module: Node3D):
	if selected_module:
		_deselect_module()
		# Deselect old
		var old_gizmo = selected_module.get_node_or_null("Gizmo3D")
		if old_gizmo:
			old_gizmo.queue_free()
		
	selected_module = module
	get_tree().call_group("stat_ui", "on_module_selected", selected_module)
	
	if selected_module:
		var new_gizmo = Gizmo3D.instantiate()
		new_gizmo.name = "Gizmo3D"
		selected_module.add_child(new_gizmo)
		
		# Show/hide handles based on module category
		if selected_module.has_meta("module_data") or selected_module == hull:
			var cat = "module"
			if selected_module == hull:
				cat = "hull"
			elif selected_module.has_meta("module_data"):
				var data = selected_module.get_meta("module_data")
				cat = data.get("category") if "category" in data else "module"
			
			var hx = new_gizmo.get_node_or_null("HandleX")
			var hy = new_gizmo.get_node_or_null("HandleY")
			var hz = new_gizmo.get_node_or_null("HandleZ")
			var hrot = new_gizmo.get_node_or_null("HandleRotate")

			if cat == "locomotion":
				if hx: hx.queue_free()
				if hy: hy.queue_free()
				if hz: hz.queue_free()
				if hrot: hrot.queue_free()
			elif cat == "armor":
				# Armor only scales in thickness (Y axis); facet-fitted, not
				# freely rotatable (see MOUNTING_AND_ARMOR_SPEC.md #2).
				if hx: hx.queue_free()
				if hz: hz.queue_free()
				if hrot: hrot.queue_free()
			elif cat == "weapon" or cat == "module":
				# Weapons/Modules scale in X and Z, but not thickness (Y).
				# Free-form yaw rotation ring (MOUNTING_AND_ARMOR_SPEC.md #3)
				# replaces the old fixed-90-degree-only rotation for these.
				if hy: hy.queue_free()
			elif cat == "hull":
				# Hull scales in all 3 directions; whole-vehicle orientation
				# isn't a placement tweak, so no rotation ring.
				if hrot: hrot.queue_free()
				
		# Firing Arc Visualization ("Radar Sweep", Design_Lab_UI_UX.md): a
		# horizontal wedge spanning the weapon's actual traverse_limit_angle
		# (shared with combat via ModuleCatalog.get_traverse_limit_angle),
		# raycast per-segment against the hull/other modules so blocked
		# angles read red and clear angles read blue - not a fixed decorative
		# cone. Kept live via _refresh_firing_arc(), called from
		# check_all_clipping() so it updates after drags/tweaks/rotation.
		if selected_module.has_meta("module_data"):
			var m_data = selected_module.get_meta("module_data")
			if m_data and m_data.category == "weapon":
				selected_module.add_child(_build_firing_arc(selected_module, m_data))

func delete_selected_module():
	if selected_module:
		# Deleting the hull itself would leave nothing to snapshot; only guard
		# undo history for module deletions (the common case).
		if selected_module != hull:
			push_undo_snapshot()
		_log("Deleting selected module")
		_deselect_module()
		var is_hull = (selected_module == hull)
		
		# Symmetrical Deletion
		if selected_module.has_meta("mirrored_counterpart"):
			var mirror = selected_module.get_meta("mirrored_counterpart")
			if is_instance_valid(mirror):
				_log("Deleting mirrored counterpart as well")
				mirror.queue_free()
				
		# Locomotion Group Symmetrical Deletion
		if selected_module.has_meta("locomotion_group"):
			var group = selected_module.get_meta("locomotion_group")
			for wheel in group:
				if is_instance_valid(wheel) and wheel != selected_module:
					_log("Deleting locomotion group member")
					wheel.queue_free()
					
			if hull:
				var hull_scale = Vector3(1, 1, 1)
				if hull.has_meta("hull_scale"):
					hull_scale = hull.get_meta("hull_scale")
				var hull_catalog_data = ModuleCatalog.get_module_data(hull.get_meta("type_id") if hull.has_meta("type_id") else "medium_hull")
				hull.position.y = (hull_catalog_data.size.y * hull_scale.y) / 2.0
				hull.remove_meta("locomotion_type")
				hull.remove_meta("locomotion_settings")
		
		if is_hull:
			hull = null
		selected_module.queue_free()
		selected_module = null
		get_tree().call_group("stat_ui", "update_stats", hull)
		check_all_clipping()
	
func clear_hull():
	# Used by the Blueprint Library to swap the active design out entirely.
	if selected_module:
		_select_module(null)
	if hull and is_instance_valid(hull):
		var parent = hull.get_parent()
		if parent:
			parent.remove_child(hull)
		hull.free()
	hull = null
	clipping_detected = false
	get_tree().call_group("stat_ui", "update_stats", null)

func _place_hull_from_ui(type_id: String):
	if hull:
		_log("Hull already exists, cannot place another until deleted.")
		return
		
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	
	hull = StaticBody3D.new()
	hull.name = "Hull"
	hull.collision_layer = 1
	hull.collision_mask = 0
	hull.position = Vector3(0, catalog_data.size.y / 2.0, 0)
	
	hull.set_meta("base_hull_size", catalog_data.size)
	hull.set_meta("hull_scale", Vector3(1, 1, 1))
	hull.set_meta("type_id", type_id)
	
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var authored_mesh = MeshAssetLoader.get_hull_mesh(type_id)
	if authored_mesh:
		mesh_inst.mesh = authored_mesh
	else:
		var box = BoxMesh.new()
		box.size = catalog_data.size
		mesh_inst.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = catalog_data.color
	mesh_inst.material_override = mat
	
	hull.add_child(mesh_inst)
	
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var col_box = BoxShape3D.new()
	col_box.size = catalog_data.size
	col.shape = col_box
	hull.add_child(col)
	
	add_child(hull)
	_log("New hull spawned: " + type_id)
	get_tree().call_group("stat_ui", "update_stats", hull)

var default_locomotion_settings = {
	"wheels": {"size": 1.0, "count": 4},
	"tracked_treads": {"width": 1.0},
	"hover_engine": {},
	"helicopter_rotors": {"size": 1.0, "count": 4},
	"fixed_wing_engine": {"size": 1.0, "count": 2},
	"naval_propeller": {"size": 1.0, "count": 2}
}

func _place_weapon_from_ui(type_id: String, pos: Vector3, normal: Vector3):
	push_undo_snapshot()
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var category = catalog_data.get("category", "module")

	if category == "locomotion":
		# Foundations CAN take locomotion now - per Chris's explicit
		# no-hard-blocking constraint (MOUNTING_AND_ARMOR_SPEC.md addendum),
		# this pre-existing validation gate was removed rather than kept as
		# an exception. A mobile pillbox is exactly the kind of "janky or
		# suboptimal" emergent outcome that's acceptable by design now -
		# see DECISIONS_NEEDED.md.
		var settings = default_locomotion_settings.get(type_id, {}).duplicate()
		update_locomotion(type_id, settings)
	else:
		# Standard weapon/armor placement
		var primary = _place_weapon(type_id, pos, normal)
		var should_mirror = mirror_enabled
		if category == "armor":
			# Armor auto-fits and centers on its whole facet (see
			# _place_weapon's "Auto-scale armor to fit facet" block, below).
			# Only left/right facets have a distinct mirror position -
			# top/bottom/front/back are already centered on the symmetry
			# plane, so mirroring them would stack an identical duplicate
			# plate directly on top of the original (MOUNTING_AND_ARMOR_SPEC.md #2).
			var abs_n = normal.abs()
			should_mirror = mirror_enabled and abs_n.x > abs_n.y and abs_n.x > abs_n.z
		elif should_mirror and hull:
			# Same class of bug, general case: placing ANY module dead-center
			# (local x ~= 0, e.g. a railgun/howitzer mounted on the front/
			# back centerline - a very natural placement for "frame_built"
			# weapons specifically) would otherwise mirror it onto its own
			# position, producing a fully-overlapping duplicate that reads
			# as a clipping-red bug. Surfaced by testing frame_built weapons
			# for MOUNTING_AND_ARMOR_SPEC.md #3, but the underlying issue
			# isn't mount-style-specific - skip mirroring for ANY module
			# placed on the centerline.
			var local_x = hull.to_local(pos).x
			should_mirror = abs(local_x) > 0.15
		if should_mirror:
			var mirrored_pos = Vector3(-pos.x, pos.y, pos.z)
			var mirrored_normal = Vector3(-normal.x, normal.y, normal.z)
			var mirror = _place_weapon(type_id, mirrored_pos, mirrored_normal)
			if primary and mirror:
				primary.set_meta("mirrored_counterpart", mirror)
				mirror.set_meta("mirrored_counterpart", primary)

func _classify_hull_facet(normal: Vector3) -> String:
	# Now a thin wrapper - the actual classification moved to
	# ModuleCatalog.classify_facet() so combat (damage_resolver.gd) can
	# share the exact same facet convention as placement.
	return ModuleCatalog.classify_facet(normal)

func update_locomotion(type_id: String, settings: Dictionary):
	if not hull: return
	
	# Save settings on hull metadata
	hull.set_meta("locomotion_type", type_id)
	hull.set_meta("locomotion_settings", settings)
	
	# Delete any existing locomotion parts first
	for child in hull.get_children():
		if child.has_meta("module_data"):
			var m_data = child.get_meta("module_data")
			if m_data and m_data.category == "locomotion":
				child.queue_free()
				
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	
	# Get actual hull size
	var hull_size = Vector3(4.0, 1.0, 6.0)
	var hull_scale = Vector3(1.0, 1.0, 1.0)
	if hull.has_meta("hull_scale"):
		hull_scale = hull.get_meta("hull_scale")
	var hull_shape = hull.get_node_or_null("CollisionShape3D")
	if hull_shape and hull_shape.shape is BoxShape3D:
		hull_size = hull_shape.shape.size
		
	var spawned_wheels = []
	
	if type_id == "wheels":
		var size = settings.get("size", 1.0)
		var count = settings.get("count", 4)
		if count < 2: count = 2
		if count % 2 != 0: count += 1
		var half_count = int(count / 2)
		
		# Tucked slightly underneath the hull side
		var x_offset = hull_size.x / 2.0 - (0.4 * size)
		var z_limit = hull_size.z * 0.35
		
		for side in [-1.0, 1.0]:
			var side_normal = Vector3.LEFT if side < 0 else Vector3.RIGHT
			for i in range(half_count):
				var z_pos = 0.0
				if half_count > 1:
					z_pos = -z_limit + (2.0 * z_limit * i) / (half_count - 1)
				
				# Place using Vector3.DOWN normal, then override position and rotation to point forward
				var pos = hull.global_position + Vector3(x_offset * side, -hull_size.y / 2.0, z_pos)
				var wheel = _place_weapon(type_id, pos, Vector3.DOWN)
				if wheel:
					wheel.scale = Vector3(size, size, size)
					# Override position to be underneath (bottom Y) and rotation to be forward (0)
					wheel.position = Vector3(x_offset * side, -hull_size.y / 2.0 - (0.8 * size), z_pos)
					wheel.rotation = Vector3.ZERO
					if wheel.has_meta("module_data"):
						wheel.get_meta("module_data").scale_multiplier = wheel.scale
					spawned_wheels.append(wheel)
					
	elif type_id == "tracked_treads":
		var width = settings.get("width", 1.0)
		
		# Always 2 treads
		var x_offset = hull_size.x / 2.0
		var y_offset = -hull_size.y / 4.0
		var tread_length = hull_size.z
		
		for side in [-1.0, 1.0]:
			var side_normal = Vector3.LEFT if side < 0 else Vector3.RIGHT
			var pos = hull.global_position + Vector3((x_offset + (catalog_data.size.x * width / 2.0) - 0.2) * side, y_offset, 0.0)
			var tread = _place_weapon(type_id, pos, side_normal)
			if tread:
				tread.scale = Vector3(width, 1.0, tread_length / catalog_data.size.z)
				tread.rotation = Vector3.ZERO
				if tread.has_meta("module_data"):
					tread.get_meta("module_data").scale_multiplier = tread.scale
				spawned_wheels.append(tread)
				
	elif type_id == "helicopter_rotors":
		var size = settings.get("size", 1.0)
		var count = settings.get("count", 4)
		if count < 2: count = 2
		if count % 2 != 0: count += 1
		var half_count = int(count / 2)
		
		var x_offset = hull_size.x / 2.0 + 1.2
		var y_offset = hull_size.y / 2.0 + 0.3
		var z_limit = hull_size.z * 0.35
		
		for side in [-1.0, 1.0]:
			var side_normal = Vector3.UP
			for i in range(half_count):
				var z_pos = 0.0
				if half_count > 1:
					z_pos = -z_limit + (2.0 * z_limit * i) / (half_count - 1)
					
				var pos = hull.global_position + Vector3(x_offset * side, y_offset, z_pos)
				var rotor = _place_weapon(type_id, pos, side_normal)
				if rotor:
					rotor.scale = Vector3(size, 1.0, size)
					rotor.rotation = Vector3.ZERO
					if rotor.has_meta("module_data"):
						rotor.get_meta("module_data").scale_multiplier = rotor.scale
					spawned_wheels.append(rotor)
					
	elif type_id == "hover_engine":
		var size = settings.get("size", 1.0)
		var x_offset = (hull_size.x / 2.0) * size
		var y_offset = -hull_size.y / 2.0
		var z_offset = (hull_size.z * 0.35) * size
		var points = [
			Vector3(-x_offset, y_offset, z_offset),
			Vector3(x_offset, y_offset, z_offset),
			Vector3(-x_offset, y_offset, -z_offset),
			Vector3(x_offset, y_offset, -z_offset)
		]
		for p in points:
			var hover = _place_weapon(type_id, hull.global_position + p, Vector3.DOWN)
			if hover:
				hover.scale = Vector3(size, 1.0, size)
				if hover.has_meta("module_data"):
					hover.get_meta("module_data").scale_multiplier = hover.scale
				spawned_wheels.append(hover)

	elif type_id == "legs":
		var size = settings.get("size", 1.0)
		var count = settings.get("count", 4)
		if count < 2: count = 2
		if count % 2 != 0: count += 1
		var half_count = int(count / 2)

		var x_offset = hull_size.x / 2.0
		var z_limit = hull_size.z * 0.35

		for side in [-1.0, 1.0]:
			var side_normal = Vector3.LEFT if side < 0 else Vector3.RIGHT
			for i in range(half_count):
				var z_pos = 0.0
				if half_count > 1:
					z_pos = -z_limit + (2.0 * z_limit * i) / (half_count - 1)

				var pos = hull.global_position + Vector3(x_offset * side, -hull_size.y / 2.0, z_pos)
				var leg = _place_weapon(type_id, pos, side_normal)
				if leg:
					leg.rotation = Vector3.ZERO
					leg.scale = Vector3(1.0, size, 1.0)
					if leg.has_meta("module_data"):
						leg.get_meta("module_data").scale_multiplier = leg.scale
					spawned_wheels.append(leg)

	elif type_id == "anti_grav":
		var size = settings.get("size", 1.0)
		var x_offset = (hull_size.x / 2.2) * size
		var y_offset = -hull_size.y / 2.0
		var z_offset = (hull_size.z * 0.35) * size
		var points = [
			Vector3(-x_offset, y_offset, z_offset),
			Vector3(x_offset, y_offset, z_offset),
			Vector3(-x_offset, y_offset, -z_offset),
			Vector3(x_offset, y_offset, -z_offset)
		]
		for p in points:
			var ag = _place_weapon(type_id, hull.global_position + p, Vector3.DOWN)
			if ag:
				ag.scale = Vector3(size, 1.0, size)
				if ag.has_meta("module_data"):
					ag.get_meta("module_data").scale_multiplier = ag.scale
				spawned_wheels.append(ag)

	elif type_id == "fixed_wing_engine":
		# Wing-mounted engine pods, left/right - new movement paradigm
		# (Traits B3, MOUNTING_AND_ARMOR_SPEC.md addendum): banking,
		# minimum airspeed, no-hover flight, handled in battle_unit.gd.
		var size = settings.get("size", 1.0)
		var x_offset = (hull_size.x / 2.0 + 0.4 * size)
		var y_offset = 0.0
		for side in [-1.0, 1.0]:
			var side_normal = Vector3.LEFT if side < 0 else Vector3.RIGHT
			var pos = hull.global_position + Vector3(x_offset * side, y_offset, hull_size.z * 0.1)
			var engine = _place_weapon(type_id, pos, side_normal)
			if engine:
				engine.scale = Vector3(1.0, size, size)
				engine.rotation = Vector3.ZERO
				if engine.has_meta("module_data"):
					engine.get_meta("module_data").scale_multiplier = engine.scale
				spawned_wheels.append(engine)

	elif type_id == "naval_propeller":
		# Stern-mounted propeller(s) - new movement paradigm (Traits B3):
		# surface-locked, no gravity/altitude falling, handled in
		# battle_unit.gd via the "buoyant" trait.
		var size = settings.get("size", 1.0)
		var count = settings.get("count", 2)
		if count < 1: count = 1
		var half_count = max(1, int(count / 2)) if count > 1 else 1
		var x_limit = hull_size.x * 0.3
		for i in range(count):
			var x_pos = 0.0
			if count > 1:
				x_pos = -x_limit + (2.0 * x_limit * i) / (count - 1)
			var pos = hull.global_position + Vector3(x_pos, -hull_size.y * 0.2, hull_size.z / 2.0)
			var prop = _place_weapon(type_id, pos, Vector3.BACK)
			if prop:
				prop.scale = Vector3(size, size, size)
				if prop.has_meta("module_data"):
					prop.get_meta("module_data").scale_multiplier = prop.scale
				spawned_wheels.append(prop)

	# Adjust hull Y position in the editor to make wheels rest on floor
	var wheels_offset = 0.0
	if type_id == "wheels":
		var size = settings.get("size", 1.0)
		wheels_offset = 0.8 * size
	elif type_id == "legs":
		wheels_offset = 1.6 * settings.get("size", 1.0)
	elif type_id == "anti_grav":
		wheels_offset = 0.4 * settings.get("size", 1.0)
		
	var hull_type = hull.get_meta("type_id") if hull.has_meta("type_id") else "medium_hull"
	var hull_catalog_data = ModuleCatalog.get_module_data(hull_type)
	hull.position.y = (hull_catalog_data.size.y * hull_scale.y) / 2.0 + wheels_offset
				
	# Link them in a group
	for w in spawned_wheels:
		w.set_meta("locomotion_group", spawned_wheels)
		
	get_tree().call_group("stat_ui", "update_stats", hull)
	
func _place_weapon(type_id: String, pos: Vector3, normal: Vector3) -> Node3D:
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var category = catalog_data.get("category", "module")
	
	var new_weapon = Node3D.new()
	
	var VisualBuilder = preload("res://scripts/visual_builder.gd")
	VisualBuilder.build_visual(type_id, new_weapon, catalog_data.size, catalog_data.color)
	
	var static_body = StaticBody3D.new()
	static_body.collision_layer = 2 # Modules layer
	static_body.collision_mask = 0
	static_body.position = Vector3(0, catalog_data.size.y / 2.0, 0)
	var collision_shape = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = catalog_data.size
	collision_shape.shape = col_box
	static_body.add_child(collision_shape)
	new_weapon.add_child(static_body)
	
	var data = ModuleData.new()
	data.type_id = type_id
	data.module_name = catalog_data.name
	data.category = category
	data.base_hp = catalog_data.hp
	data.base_weight = catalog_data.weight
	data.cost_metal = catalog_data.metal
	data.cost_crystal = catalog_data.crystal
	data.base_dps = catalog_data.dps
	data.base_heal_rate = catalog_data.get("heal_rate", 0.0)
	data.base_energy_capacity = catalog_data.get("energy_capacity", 0.0)
	data.base_energy_regen = catalog_data.get("energy_regen", 0.0)
	data.base_vision_bonus = catalog_data.get("vision_bonus", 0.0)
	new_weapon.set_meta("module_data", data)
	
	hull.add_child(new_weapon)
	
	# Snap to 0.25m grid relative to hull local space
	var final_pos = pos
	if hull:
		var local_pos = hull.to_local(pos)
		var local_normal = hull.global_transform.basis.inverse() * normal
		
		var snap_interval = 0.25
		if abs(local_normal.x) < 0.9:
			local_pos.x = round(local_pos.x / snap_interval) * snap_interval
		if abs(local_normal.y) < 0.9:
			local_pos.y = round(local_pos.y / snap_interval) * snap_interval
		if abs(local_normal.z) < 0.9:
			local_pos.z = round(local_pos.z / snap_interval) * snap_interval
			
		final_pos = hull.to_global(local_pos)
		
	new_weapon.global_position = final_pos
	
	# Align to surface normal if not perfectly up/down
	if abs(normal.dot(Vector3.UP)) < 0.999:
		new_weapon.look_at(final_pos + normal, Vector3.UP)
		new_weapon.rotate_object_local(Vector3.RIGHT, -PI/2)
		
	# Auto-scale armor to fit facet
	if category == "armor":
		if hull:
			var hull_size = Vector3(4.0, 1.0, 6.0)
			var hull_shape = hull.get_node_or_null("CollisionShape3D")
			if hull_shape and hull_shape.shape is BoxShape3D:
				hull_size = hull_shape.shape.size
				
			# Determine which axis of the hull aligns with local X and Z of the module
			var local_x = new_weapon.global_transform.basis.x.abs()
			var local_z = new_weapon.global_transform.basis.z.abs()
			
			var target_x = 1.0
			var target_z = 1.0
			
			if local_x.x > 0.5: target_x = hull_size.x
			elif local_x.y > 0.5: target_x = hull_size.y
			elif local_x.z > 0.5: target_x = hull_size.z
			
			if local_z.x > 0.5: target_z = hull_size.x
			elif local_z.y > 0.5: target_z = hull_size.y
			elif local_z.z > 0.5: target_z = hull_size.z
			
			# The module's base size is catalog_data.size, so we scale by ratio
			new_weapon.scale.x = target_x / catalog_data.size.x
			new_weapon.scale.z = target_z / catalog_data.size.z

			# Center on the facet rather than leaving it at the clicked
			# point: a plate that auto-fits the WHOLE face but stays
			# positioned wherever the player happened to click would poke
			# out past the hull edge on one side. Snap the two in-plane
			# axes to hull-center (0) and keep only the surface-normal axis.
			var local_normal = hull.global_transform.basis.inverse() * normal
			var armor_facet = ModuleCatalog.classify_facet(local_normal)
			var centered_local = Vector3.ZERO
			match armor_facet:
				"left", "right":
					centered_local = Vector3(sign(local_normal.x) * hull_size.x / 2.0, 0, 0)
				"front", "back":
					centered_local = Vector3(0, 0, sign(local_normal.z) * hull_size.z / 2.0)
				_:
					centered_local = Vector3(0, sign(local_normal.y) * hull_size.y / 2.0, 0)
			new_weapon.global_position = hull.to_global(centered_local)
			# Stored so combat (damage_resolver.gd) can resolve which
			# specific armor module covers a given hit's facet, instead of
			# treating all placed armor as one undifferentiated pool.
			new_weapon.set_meta("facet", armor_facet)

	# Face-based weapon mounting (MOUNTING_AND_ARMOR_SPEC.md #3): sponson-
	# embed on side/front/back faces, pintle stand on top/bottom, except
	# railgun/howitzer (frame-built) and basic_cannon (existing enclosed
	# turret, left unchanged - handled by get_mount_style() returning "turret").
	if category == "weapon":
		var facet = _classify_hull_facet(normal)
		var hull_type_for_mount = hull.get_meta("type_id", "") if hull else ""
		var mount_style = ModuleCatalog.get_mount_style(type_id, facet, hull_type_for_mount)
		# Stored as meta (not just applied once) so rebuild_visual() - called
		# on every gizmo tweak-drag frame, which clears and rebuilds all
		# MeshInstance3D children - knows to re-add the mount hardware
		# instead of silently losing it on the first tweak.
		new_weapon.set_meta("mount_style", mount_style)
		if mount_style == "sponson" or mount_style == "frame_built":
			var embed_depth = catalog_data.size.y * (0.75 if mount_style == "frame_built" else 0.45)
			new_weapon.global_position -= normal * embed_depth
		VisualBuilder.add_mount_hardware(new_weapon, mount_style, catalog_data.size)

	# Notify the UI that a module was added
	get_tree().call_group("stat_ui", "update_stats", hull)
	check_all_clipping()
	return new_weapon

func update_hull_appearance():
	if not hull: return
	var mesh_inst = hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_inst: return
	
	var type_id = hull.get_meta("type_id") if hull.has_meta("type_id") else "medium_hull"
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	
	var hull_scale = hull.get_meta("hull_scale") if hull.has_meta("hull_scale") else Vector3(1,1,1)
	var armor_thick = hull.get_meta("armor_thickness") if hull.has_meta("armor_thickness") else 1.0
	var armor_mat_name = hull.get_meta("armor_material") if hull.has_meta("armor_material") else "hardened_steel"
	
	# Bulk size based on thickness
	var armor_bulk = Vector3(1.0 + (armor_thick - 1.0) * 0.15, 1.0 + (armor_thick - 1.0) * 0.15, 1.0)
	var authored_mesh = MeshAssetLoader.get_hull_mesh(type_id)
	if authored_mesh:
		# Per-hull-type custom deform (MOUNTING_AND_ARMOR_SPEC.md #4),
		# proof-of-concept for interceptor_hull only. Genuine regional
		# reshaping of the actual authored mesh via MeshDataTool, not a mesh
		# swap - apply_nose_taper() returns a fresh ArrayMesh each time, so
		# this never mutates MeshAssetLoader's cached shared resource.
		if type_id == "interceptor_hull" and hull.has_meta("nose_taper"):
			var taper = hull.get_meta("nose_taper")
			if abs(taper - 1.0) > 0.001:
				authored_mesh = HullDeformScript.apply_nose_taper(authored_mesh, taper)
		mesh_inst.mesh = authored_mesh
		mesh_inst.scale = hull_scale * armor_bulk
	else:
		var box = BoxMesh.new()
		box.size = catalog_data.size * hull_scale * armor_bulk
		mesh_inst.mesh = box
		mesh_inst.scale = Vector3.ONE
	
	# Apply material
	var mat = StandardMaterial3D.new()
	if armor_mat_name == "hardened_steel":
		mat.albedo_color = Color.GRAY
		mat.roughness = 0.2
		mat.metallic = 0.8
	elif armor_mat_name == "reactive_armor":
		mat.albedo_color = Color(0.18, 0.24, 0.18)
		mat.roughness = 0.7
		mat.metallic = 0.1
	elif armor_mat_name == "ablative_ceramic":
		mat.albedo_color = Color(0.85, 0.8, 0.7)
		mat.roughness = 0.5
		mat.metallic = 0.0
	elif armor_mat_name == "energy_shielding":
		mat.albedo_color = Color(0.3, 0.6, 1.0, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.1
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.6, 1.0)
		mat.emission_energy_multiplier = 0.5
	mesh_inst.material_override = mat
	
	# Also update collision shape size in the designer
	var col = hull.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		var col_box = BoxShape3D.new()
		col_box.size = catalog_data.size * hull_scale * armor_bulk
		col.shape = col_box
	# Recalculate stats
	get_tree().call_group("stat_ui", "update_stats", hull)
	check_all_clipping()

func _deselect_module():
	if selected_module:
		for child in selected_module.get_children():
			if child.name == "ArcCone":
				child.queue_free()

func _build_firing_arc(module: Node3D, data) -> Node3D:
	var container = Node3D.new()
	container.name = "ArcCone"
	container.position = Vector3(0, 0.35, 0)

	var arc_facet = module.get_meta("facet", "")
	var arc_hull_type = hull.get_meta("type_id", "") if hull else ""
	var limit = ModuleCatalog.get_traverse_limit_angle(data.type_id, arc_facet, arc_hull_type)
	var full_circle = limit >= PI - 0.01
	var angle_span = 2.0 * PI if full_circle else limit * 2.0
	var segments = 32 if full_circle else max(6, int(32.0 * angle_span / (2.0 * PI)))
	var angle_start = -angle_span / 2.0
	var step = angle_span / segments
	var radius = 3.0

	var exclude_list = []
	_get_colliders_recursive(module, exclude_list)
	var space_state = get_world_3d().direct_space_state
	var origin = module.global_position + Vector3(0, 0.35, 0)

	for i in range(segments):
		var a0 = angle_start + i * step
		var a1 = a0 + step
		var mid_angle = (a0 + a1) / 2.0
		var local_dir = Vector3(sin(mid_angle), 0, -cos(mid_angle))
		var world_dir = (module.global_transform.basis * local_dir).normalized()

		var query = PhysicsRayQueryParameters3D.create(origin, origin + world_dir * radius)
		query.collision_mask = 3 # Layer 1 (Hull) + Layer 2 (Modules)
		query.exclude = exclude_list
		var result = space_state.intersect_ray(query)
		var blocked = not result.is_empty()

		var seg = MeshInstance3D.new()
		seg.name = "ArcSeg%d" % i
		seg.mesh = _build_wedge_mesh(a0, a1, radius)
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		if blocked:
			mat.albedo_color = Color(1.0, 0.15, 0.15, 0.4)
			mat.emission = Color(1.0, 0.15, 0.15)
		else:
			mat.albedo_color = Color(0.2, 0.6, 1.0, 0.25)
			mat.emission = Color(0.2, 0.6, 1.0)
		mat.emission_energy_multiplier = 0.5
		seg.material_override = mat
		container.add_child(seg)

	return container

static func _build_wedge_mesh(angle_start: float, angle_end: float, radius: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p0 = Vector3.ZERO
	var p1 = Vector3(sin(angle_start) * radius, 0, -cos(angle_start) * radius)
	var p2 = Vector3(sin(angle_end) * radius, 0, -cos(angle_end) * radius)
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)
	return st.commit()

func _refresh_firing_arc():
	if not selected_module or not is_instance_valid(selected_module): return
	if not selected_module.has_meta("module_data"): return
	var data = selected_module.get_meta("module_data")
	if data.category != "weapon": return
	var old = selected_module.get_node_or_null("ArcCone")
	if old:
		# Immediate free (not queue_free): this can be called multiple times
		# within the same frame during a drag, and queue_free's deferred
		# removal would leave a stale same-named node around long enough to
		# cause the new one to be auto-renamed "ArcCone2", breaking the
		# name-based lookup/cleanup used everywhere else in this file.
		selected_module.remove_child(old)
		old.free()
	selected_module.add_child(_build_firing_arc(selected_module, data))

func _get_parent_space_aabb(module: Node3D, size: Vector3) -> AABB:
	var extents = size / 2.0
	var local_corners = [
		Vector3(-extents.x, -extents.y, -extents.z),
		Vector3(-extents.x, -extents.y, extents.z),
		Vector3(-extents.x, extents.y, -extents.z),
		Vector3(-extents.x, extents.y, extents.z),
		Vector3(extents.x, -extents.y, -extents.z),
		Vector3(extents.x, -extents.y, extents.z),
		Vector3(extents.x, extents.y, -extents.z),
		Vector3(extents.x, extents.y, extents.z)
	]
	
	var t = module.transform
	var first = t * local_corners[0]
	var min_p = first
	var max_p = first
	
	for i in range(1, 8):
		var p = t * local_corners[i]
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		min_p.z = min(min_p.z, p.z)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
		max_p.z = max(max_p.z, p.z)
		
	return AABB(min_p, max_p - min_p)

func check_all_clipping():
	clipping_detected = false
	if not hull:
		return
		
	var modules = []
	for child in hull.get_children():
		if child.has_meta("module_data") and not child.is_queued_for_deletion():
			modules.append(child)
			
	var clipping_set = {}
	for m in modules:
		clipping_set[m] = false
		
	for i in range(modules.size()):
		var my_module = modules[i]
		var my_data = my_module.get_meta("module_data")
		var my_catalog = ModuleCatalog.get_module_data(my_data.type_id)
		var my_size = my_catalog.size * my_module.scale
		var aabb_a = _get_parent_space_aabb(my_module, my_size)
		
		for j in range(i + 1, modules.size()):
			var other_module = modules[j]
			
			if my_module == other_module:
				continue
			if my_module.is_ancestor_of(other_module) or other_module.is_ancestor_of(my_module):
				continue
			if my_module.has_meta("mirrored_counterpart") and my_module.get_meta("mirrored_counterpart") == other_module:
				continue
			if my_module.has_meta("locomotion_group") and other_module in my_module.get_meta("locomotion_group"):
				continue
				
			var other_data = other_module.get_meta("module_data")
			var other_catalog = ModuleCatalog.get_module_data(other_data.type_id)
			var other_size = other_catalog.size * other_module.scale
			var aabb_b = _get_parent_space_aabb(other_module, other_size)
			
			# Shrink AABB slightly to allow touching/adjacent modules
			if aabb_a.grow(-0.05).intersects(aabb_b.grow(-0.05)):
				clipping_set[my_module] = true
				clipping_set[other_module] = true
				clipping_detected = true
				
	# Apply visual changes to each module
	for m in modules:
		var is_clipping = clipping_set[m]
		var my_data = m.get_meta("module_data")
		var my_catalog = ModuleCatalog.get_module_data(my_data.type_id)
		
		var meshes = []
		_find_meshes_recursive(m, meshes)
		
		for mesh in meshes:
			if mesh.name == "ArcCone":
				continue
			var mesh_parent = mesh.get_parent()
			if mesh_parent and mesh_parent.name == "ArcCone":
				continue # per-segment wedge meshes nested under the ArcCone container
			var mat = mesh.material_override as StandardMaterial3D
			if not mat:
				mat = StandardMaterial3D.new()
				mesh.material_override = mat
			if is_clipping:
				mat.albedo_color = Color(1.0, 0.0, 0.0) # bright RED
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.0, 0.0)
				mat.emission_energy_multiplier = 1.0
			else:
				mat.albedo_color = my_catalog.color
				if my_data.type_id == "hover_engine":
					mat.emission_enabled = true
					mat.emission = my_catalog.color
					mat.emission_energy_multiplier = 1.0
				else:
					mat.emission_enabled = false

	# Keep the firing-arc visualization live: placement/rotation/drag/tweak
	# changes all route through check_all_clipping(), so refreshing here
	# covers all of them without needing a call at every individual mutation
	# site.
	_refresh_firing_arc()

func _find_meshes_recursive(node: Node, result: Array):
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_meshes_recursive(child, result)

func _update_module_placement(module: Node3D, world_pos: Vector3, normal: Vector3):
	if not module or not is_instance_valid(module): return
	
	var data = module.get_meta("module_data")
	var catalog_data = ModuleCatalog.get_module_data(data.type_id)
	
	var offset = normal * (catalog_data.size.y / 2.0)
	var local_pos = hull.to_local(world_pos) + offset
	
	var snap_interval = 0.25
	var local_normal = hull.global_transform.basis.inverse() * normal
	
	if abs(local_normal.x) < 0.9:
		local_pos.x = round(local_pos.x / snap_interval) * snap_interval
	if abs(local_normal.y) < 0.9:
		local_pos.y = round(local_pos.y / snap_interval) * snap_interval
	if abs(local_normal.z) < 0.9:
		local_pos.z = round(local_pos.z / snap_interval) * snap_interval
		
	module.position = local_pos
	
	module.rotation = Vector3.ZERO
	if abs(normal.dot(Vector3.UP)) < 0.999:
		module.look_at(module.global_position + normal, Vector3.UP)
		module.rotate_object_local(Vector3.RIGHT, -PI/2.0)
		
	var yaw_offset = module.get_meta("yaw_offset", 0.0)
	module.rotate_object_local(Vector3.UP, yaw_offset)
		
	if module.has_meta("mirrored_counterpart"):
		var mirror = module.get_meta("mirrored_counterpart")
		if mirror and is_instance_valid(mirror):
			var mirrored_local_pos = Vector3(-local_pos.x, local_pos.y, local_pos.z)
			mirror.position = mirrored_local_pos
			
			var mirrored_normal = Vector3(-normal.x, normal.y, normal.z)
			mirror.rotation = Vector3.ZERO
			if abs(mirrored_normal.dot(Vector3.UP)) < 0.999:
				mirror.look_at(mirror.global_position + mirrored_normal, Vector3.UP)
				mirror.rotate_object_local(Vector3.RIGHT, -PI/2.0)
			
			mirror.rotate_object_local(Vector3.UP, -yaw_offset)

func _get_colliders_recursive(node: Node, list: Array):
	if node is CollisionObject3D:
		list.append(node.get_rid())
	for child in node.get_children():
		_get_colliders_recursive(child, list)
