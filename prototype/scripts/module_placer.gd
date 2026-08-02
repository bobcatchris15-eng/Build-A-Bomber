extends Node3D
const ModuleDataResource = preload("res://scripts/module_data.gd")


const Gizmo3D = preload("res://scenes/Gizmo3D.tscn")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const HullDeformScript = preload("res://scripts/hull_deform.gd")
const ModuleMirrorScript = preload("res://scripts/module_mirror.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")
const VisualBuilderScript = preload("res://scripts/visual_builder.gd")
const HullGreeblesScript = preload("res://scripts/hull_greebles.gd")
const ArmorGreeblesScript = preload("res://scripts/armor_greebles.gd")
const HullDecalsScript = preload("res://scripts/hull_decals.gd")
const HullSurfaceScript = preload("res://scripts/hull_surface.gd")
const LocomotionLayoutScript = preload("res://scripts/locomotion_layout.gd")

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
	# Spawn some scale reference boxes (1x1x1 meters)
	for x in [-8, 8]:
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1, 1, 1)
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.4, 0.2)
		mesh_inst.material_override = mat
		mesh_inst.position = Vector3(x, 0.5, -4)
		add_child(mesh_inst)
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

	# Coming back from the Test Range: rebuild whatever the player was
	# working on instead of dropping them onto the default bare hull.
	#
	# Deferred because the restore runs reconstruct_vehicle() against this
	# node and calls into the stat sidebar via the "stat_ui" group - during
	# _ready() the sidebar's own _ready() may not have run yet, so its
	# @onready references would still be null.
	call_deferred("_restore_test_session")

func _restore_test_session() -> void:
	var bp_manager = get_node_or_null("BlueprintManager")
	if bp_manager and bp_manager.has_pending_lab_restore():
		bp_manager.restore_scratch_into_designer()
		
func _process(delta: float):
	# Live idle spin for helicopter_rotors blades while designing - the
	# Design Lab canvas never had this at all (battle_unit.gd/battlefield.gd
	# spin them in combat/Test Range, but nothing did it here), which read
	# as "the animation is broken" when the actual issue was that it never
	# existed on this screen. Same rotate_y(15/sec) on the "RotorBlades"
	# pivot as the combat paths, so it looks consistent everywhere.
	if not is_instance_valid(hull): return
	for child in hull.get_children():
		if not child.has_meta("module_data"): continue
		var type_id = child.get_meta("module_data").type_id
		if type_id == "helicopter_rotors":
			var rotor = child.get_node_or_null("RotorBlades")
			if rotor:
				rotor.rotate_y(15.0 * delta)
		elif type_id == "hover_engine":
			# Same idle spin as helicopter_rotors' blades - outer ring stays
			# fixed/horizontal, middle ring spins around X, inner ring
			# around Y (Chris's ask).
			var mid_ring = child.get_node_or_null("HoverRingMid")
			if mid_ring:
				mid_ring.rotate_x(12.0 * delta)
			var inner_ring = child.get_node_or_null("HoverRingInner")
			if inner_ring:
				inner_ring.rotate_y(18.0 * delta)

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
				elif result.collider == hull or (result.collider.get_parent() == hull and not result.collider.has_meta("module_data") and not (result.collider.get_parent() and result.collider.get_parent().has_meta("module_data"))):
					# Hit the Hull itself
					_select_module(hull)
				else:
					# We clicked a Module!
					var module = result.collider
					if not module.has_meta("module_data") and module.get_parent() != null and module.get_parent().has_meta("module_data"):
						module = module.get_parent()
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
				if selected_module and is_instance_valid(selected_module):
					var final_normal = selected_module.get_meta("_last_drag_normal", Vector3.UP)
					_reclassify_module_after_drag(selected_module, final_normal)
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
				_free_gizmo(selected_module)
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
						
				# Precise hull surface first, bounding box only as a fallback -
				# same rule initial placement uses, so a dragged module tracks
				# the visible hull instead of jumping onto its bounding shell.
				var result = surface_raycast(ray_origin, camera.project_ray_normal(mouse_pos), 1000.0, exclude_list)
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
	if selected_module and is_instance_valid(selected_module):
		_deselect_module()
		_free_gizmo(selected_module)

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
			elif cat == "structural":
				# Structural pieces resize freely in all 3 axes (X/Y/Z) so
				# the player can stretch a block, lengthen a girder, or
				# flatten a slab. No rotation ring — they should stay flush
				# against the surface normal they were mounted on.
				if hrot: hrot.queue_free()
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
				hull.position.y = (hull_catalog_data.get("size", Vector3.ONE).y * hull_scale.y) / 2.0
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
	hull.position = Vector3(0, catalog_data.get("size", Vector3.ONE).y / 2.0, 0)
	
	hull.set_meta("base_hull_size", catalog_data.get("size", Vector3.ONE))
	hull.set_meta("hull_scale", Vector3(1, 1, 1))
	hull.set_meta("type_id", type_id)
	
	var phys_mesh = MeshInstance3D.new()
	phys_mesh.name = "PhysicsMesh"
	var authored_mesh = MeshAssetLoader.get_hull_mesh(type_id)
	if authored_mesh:
		phys_mesh.mesh = authored_mesh
		var fit = ModuleCatalog.get_hull_mesh_fit(type_id, authored_mesh)
		phys_mesh.rotation = fit["rotation"]
		phys_mesh.scale = fit["scale"]
		phys_mesh.position = fit["position"]
	else:
		var box = BoxMesh.new()
		box.size = catalog_data.get("size", Vector3.ONE)
		phys_mesh.mesh = box

	# Never drawn: it carries the same mesh at the same transform as the
	# visual MeshInstance3D below, so rendering both just z-fights (and this
	# one has no material, so the fight is against untextured white). It
	# exists as the hull's physical-shape reference for code that wants the
	# mesh independent of whatever the visual copy is currently showing.
	phys_mesh.visible = false
	hull.add_child(phys_mesh)

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	mesh_inst.mesh = phys_mesh.mesh
	mesh_inst.rotation = phys_mesh.rotation
	mesh_inst.scale = phys_mesh.scale
	mesh_inst.position = phys_mesh.position
	hull.add_child(mesh_inst)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = catalog_data.color
	mesh_inst.material_override = mat

	_rebuild_surface_body(hull, phys_mesh)

	# Axis-aligned in hull-local space, and NOT rotated to match the mesh:
	# col_box.size is already expressed in the hull-local convention
	# (x = width, z = length along the -Z front), and get_hull_mesh_fit() has
	# just scaled the visual mesh to occupy exactly that box. Applying the
	# mesh's orientation correction here as well used to rotate the collider
	# 90 degrees away from the hull you can see - medium_hull rendered 3.0
	# wide by 5.5 long while colliding as 5.5 wide by 3.0 long, which threw
	# off click-to-select raycasts, locomotion mounting and armor auto-fit
	# (all of which read this shape's size).
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var col_box = BoxShape3D.new()
	col_box.size = catalog_data.get("size", Vector3.ONE)
	col.shape = col_box
	hull.add_child(col)

	add_child(hull)
	update_hull_appearance()
	_log("New hull spawned: " + type_id)
	get_tree().call_group("stat_ui", "update_stats", hull)

var default_locomotion_settings = {
	"wheels": {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 1},
	"tracked_treads": {"tread_width": 1.0},
	"hover_engine": {},
	"helicopter_rotors": {"size": 1.0, "count": 4},
	"fixed_wing_engine": {"size": 1.0, "count": 2},
	"ornithopter_wing": {"size": 1.0, "count": 2},
	"naval_propeller": {"prop_count": 2, "blade_count": 3, "blade_pitch": 1.0},
	"buoyant_envelope": {"prop_count": 2, "blade_count": 3, "blade_pitch": 1.0},
	"screw_drive": {"drum_diameter": 1.0, "helix_depth": 1.0}
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

## Lightweight per-instance geometry update for locomotion tweaks that DON'T
## change how many module instances exist (wheel_size, wheels_per_axle,
## tread_width, blade_length, etc. - anything that isn't a "count" tweak).
## Unlike update_locomotion(), this never destroys/recreates any node: it
## just updates each existing instance's own data.tweaks and rebuilds its
## mesh in place, exactly like a weapon's tweak slider does via
## VisualBuilder.rebuild_visual(). That means it's cheap enough to call on
## EVERY value_changed tick during a drag (no debounce needed) and never
## disturbs the current selection or the floating tweak popup's position -
## unlike a full update_locomotion() respawn, which reselects an arbitrary
## instance and visibly jumps the popup around mid-drag (confirmed via a
## real simulated-mouse-drag test - this was the actual cause of the wheels
## size slider feeling "laggy"/unresponsive compared to weapon tweaks).
## Re-fits a placed module's click target to whatever it currently renders.
## Shared by initial placement and by live tweak drags so the two cannot drift.
static func _resize_collider_to_visual(module: Node3D) -> void:
	var bounds := _visual_bounds(module)
	if bounds.size.length_squared() <= 0.0:
		return
	for child in module.get_children():
		if not (child is StaticBody3D):
			continue
		child.position = bounds.get_center()
		for shape_node in child.get_children():
			if shape_node is CollisionShape3D and shape_node.shape is BoxShape3D:
				# Shapes are shared resources by default; resizing one in place
				# would silently resize every other module using the same box.
				if not shape_node.shape.resource_local_to_scene:
					shape_node.shape = shape_node.shape.duplicate()
				shape_node.shape.size = bounds.size
				shape_node.position = Vector3.ZERO
		return

func update_locomotion_geometry_tweak(type_id: String, tweak_key: String, value) -> void:
	if not hull: return
	var VisualBuilder = load("res://scripts/visual_builder.gd")
	var settings: Dictionary = hull.get_meta("locomotion_settings", {}).duplicate() if hull.has_meta("locomotion_settings") else {}
	settings[tweak_key] = value
	hull.set_meta("locomotion_settings", settings)
	for child in hull.get_children():
		if child.has_meta("module_data"):
			var m_data = child.get_meta("module_data")
			if m_data and m_data.type_id == type_id:
				m_data.tweaks[tweak_key] = value
				VisualBuilder.rebuild_visual(child)
				# _apply_mirror_flip() (called once at initial placement for
				# the mirrored side) doesn't scale the module itself - it
				# individually mirrors each of the module's CHILDREN's own
				# transforms and marks them "_mirrored", one time. rebuild_
				# visual() just destroyed those mirrored children and built
				# fresh, un-mirrored ones, and nothing re-applied the mirror
				# afterward - the mirrored-side wheel's driveshaft/gearbox
				# would silently un-mirror (render on the wrong side) on the
				# very first live wheel_size/wheels_per_axle drag. Redo it
				# here since this is the only path that rebuilds children
				# after initial placement.
				if child.get_meta("scale_flip_x", false):
					_apply_mirror_flip(child)
					# rebuild_visual()/build_visual() deliberately skip
					# StaticBody3D children when clearing/rebuilding a module's
					# mesh (so the click-target collider survives visual
					# rebuilds), which means it is never resized on its own -
					# and a tweak that just reshaped the mesh has, by
					# definition, moved the thing the player is trying to click.
					# Re-measured from the geometry that was just rebuilt, the
					# same way _place_weapon() sizes it initially, so the two
					# paths cannot disagree.
					_resize_collider_to_visual(child)
	get_tree().call_group("stat_ui", "update_stats", hull)

## Re-runs the current locomotion layout against the hull as it is NOW.
##
## Every station position is derived from hull_size (x_offset, z_limit, the
## ellipse radii, the drum span), but update_locomotion() only ever ran at
## initial placement and on a count tweak - nothing re-ran it when the hull
## itself changed. Dragging a hull scale handle after choosing locomotion left
## the wheels spaced for the hull you used to have, getting worse the further
## you dragged. gizmo_3d.gd's rescale handler calls this now.
##
## No-ops when the hull has no locomotion, so it is safe to call unconditionally.
func refresh_locomotion() -> void:
	if not hull or not hull.has_meta("locomotion_type"):
		return
	var type_id: String = str(hull.get_meta("locomotion_type"))
	if type_id == "":
		return
	var settings: Dictionary = hull.get_meta("locomotion_settings", {})
	update_locomotion(type_id, settings.duplicate())

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

	# Same class of cleanup for the running-gear chassis slab: if a previous
	# locomotion type created one and the new type either doesn't want one
	# (hover_engine/anti_grav) or wants it freshly sized (the new hull might
	# be a different size), tear it down before deciding whether to rebuild.
	# ModuleDataResource is already preloaded at the top of this file.
	var existing_gear = hull.get_node_or_null("RunningGear")
	if existing_gear:
		existing_gear.queue_free()

	var catalog_data = ModuleCatalog.get_module_data(type_id)

	# Get actual hull size
	var hull_size = Vector3(4.0, 1.0, 6.0)
	var hull_scale = Vector3(1.0, 1.0, 1.0)
	if hull.has_meta("hull_scale"):
		hull_scale = hull.get_meta("hull_scale")
	var hull_shape = hull.get_node_or_null("CollisionShape3D")
	if hull_shape and hull_shape.shape is BoxShape3D:
		hull_size = hull_shape.shape.size

	# Locomotion grounding fix (test arena "vehicle slides on its belly"):
	# every ground-contact locomotion archetype now has a procedurally-
	# generated chassis slab (the "running gear") that sits BELOW the hull's
	# underside, with the wheels/treads/legs/screws mounting to its sides
	# rather than to the bare hull skin. Two real effects:
	#
	# 1. The unit's CharacterBody3D collider (battle_unit.gd) extends down
	#    to the chassis bottom, so the unit rests on the chassis (not the
	#    hull's belly) - a real "vehicle on its running gear" pose.
	# 2. Side-mount parts now have a real chassis surface to mount to, not
	#    a hull-skin interface that left them floating below the authored
	#    mesh on hulls whose underside sits above the catalog bottom
	#    (per the underside_y_bias hack).
	#
	# Hover_engine / anti_grav / winged / naval / buoyant types don't get
	# a chassis - they project from the underside / above / stern and a
	# slab underneath them would be visual noise.
	var running_gear_size := Vector3.ZERO
	if ModuleCatalog.needs_running_gear(type_id):
		running_gear_size = ModuleCatalog.get_running_gear_size(hull_size)
		var VisualBuilder = load("res://scripts/visual_builder.gd")
		var gear_body: StaticBody3D = VisualBuilder.build_running_gear(hull, running_gear_size, catalog_data.color, 1, type_id)
		# Flush the chassis's top against the hull's underside: hull's origin
		# is at its center, so chassis center sits at -hull_size.y/2 - gear_y/2.
		gear_body.position = Vector3(0, -hull_size.y / 2.0 - running_gear_size.y / 2.0, 0)

	# Visual bug pass finding: several hulls' visual mesh doesn't fill its
	# collision box symmetrically (ship hulls' tapered keel, airship_hull's
	# curved envelope) - underside-mounted locomotion (wheels/legs/
	# hover_engine/anti_grav) computed purely from -hull_size.y/2.0 floated
	# visibly below the actual hull on those. Raises the underside mount
	# point by however much that specific hull needs (0.0 for every
	# box-ish hull, unaffected).
	var underside_y_bias = 0.0
	if hull.has_meta("type_id"):
		underside_y_bias = ModuleCatalog.get_underside_y_bias(hull.get_meta("type_id"))

	# Locomotion visuals were previously built at a fixed absolute size (each
	# _build_X() in visual_builder.gd only ever sees the LOCOMOTION module's
	# own catalog size field, never the hull's) - giant legs on a paper-thin
	# wing, tiny rotors on a huge cruiser, etc. Two hull-relative factors,
	# benchmarked against medium_hull (the size everything was originally
	# eyeballed against, so this is a no-op there): a HEIGHT factor for parts
	# whose scale should track hull height/ground-clearance (wheels radius,
	# leg length), and a FOOTPRINT factor (sqrt of plan-view area) for parts
	# whose scale should track overall hull bulk (rotor span, hover/anti-grav
	# pad size, engine pod size, prop size). Clamped so an extreme hull
	# (tiny drone / huge cruiser) still gets a legible part instead of a
	# vanishing sliver or a comically oversized blob.
	var hull_height_factor = clamp(hull_size.y / ModuleCatalog.REFERENCE_HULL_SIZE.y, 0.45, 2.25)
	var hull_footprint_factor = clamp(sqrt((hull_size.x * hull_size.z) / (ModuleCatalog.REFERENCE_HULL_SIZE.x * ModuleCatalog.REFERENCE_HULL_SIZE.z)), 0.45, 2.25)

	var spawned_wheels = []
	
	# One generic placement loop, replacing the ten hand-written branches this
	# used to be. Every branch did the same six things - resolve tweaks, compute
	# a mount pattern, build a geo_tweaks dict, place, reset the transform,
	# mirror - and only the pattern was ever per-type. The patterns now live in
	# locomotion_layout.gd as data, so adding a locomotion type is a table entry
	# rather than another elif and another copy of the other five steps.
	var layout_ctx := {
		"hull_size": hull_size,
		"running_gear_size": running_gear_size,
		"underside_y_bias": underside_y_bias,
		"catalog_size": catalog_data.get("size", Vector3.ONE),
	}
	var node_scale := LocomotionLayoutScript.node_scale_for(type_id, hull_height_factor)
	var scale_mult := LocomotionLayoutScript.scale_multiplier_for(type_id)
	for station in LocomotionLayoutScript.stations(type_id, settings, layout_ctx):
		var station_pos: Vector3 = station["position"]
		var part := _place_weapon(type_id, hull.global_position + station_pos,
			station["normal"], false, station["geo"])
		if part == null:
			continue
		# _place_weapon() aligns the node to the mount normal and snaps it to a
		# 0.25m grid; locomotion wants neither - it is laid out analytically and
		# its meshes are authored already-oriented.
		part.scale = node_scale
		part.rotation = Vector3.ZERO
		if station["has_final_position"]:
			part.position = station["final_position"]
		if part.has_meta("module_data"):
			part.get_meta("module_data").scale_multiplier = scale_mult
		for meta_key in station["meta"]:
			part.set_meta(meta_key, station["meta"][meta_key])
		if station["mirror"]:
			part.set_meta("scale_flip_x", true)
			_apply_mirror_flip(part)
			# The mirror reflects each child's own transform in module space, so
			# geometry that sat off-centre (a wheel's hub offset, a leg's splayed
			# stance, a wing's shoulder) lands somewhere new. The collider was
			# measured before that happened, so the port-side instance of every
			# asymmetric type had a click target sitting where the starboard one's
			# geometry would have been - mirrored parts were the hardest of all to
			# click, on top of the per-type drift this pass already removed.
			_resize_collider_to_visual(part)
		spawned_wheels.append(part)


	# WIDTH CLAMP. Locomotion is laid out from hull dimensions, but each type's
	# own parts are authored at a fixed size, so on a small hull an assembly can
	# end up wider than the vehicle it is carrying. Measured against the
	# reference hull: ornithopter_wing came out 4.25x the hull's width and legs
	# 2.69x, against ~1.1-1.2x for the tracked and wheeled types. That is not a
	# style difference, it is the same part failing to scale with its hull.
	#
	# Clamped by scaling the instances rather than moving them: scale shrinks
	# each assembly about its own station, so the mount stays exactly where the
	# layout put it and only the outboard reach comes in. Limits are per type
	# because a rotor disc SHOULD overhang and a road wheel should not.
	var width_limit := LocomotionLayoutScript.max_width_factor(type_id)
	if width_limit > 0.0 and not spawned_wheels.is_empty():
		# Solve for the scale directly rather than applying a ratio. An
		# instance's outboard reach is |station.x| + scale.x * local_extent, and
		# only the second term shrinks - the station is where the layout put the
		# mount and must not move. Scaling by allowed/reach ignores that and
		# under-corrects badly on exactly the types that need it most: the first
		# attempt took ornithopter_wing from 4.25x to 4.14x. It also has to read
		# the CURRENT scale, since ornithopter_wing already carries a deliberate
		# 2x and legs a hull-height factor.
		var mount_reach := 0.0
		var local_extent := 0.0
		for w in spawned_wheels:
			var wb := _visual_bounds(w)
			if wb.size.length_squared() <= 0.0:
				continue
			mount_reach = maxf(mount_reach, absf(w.position.x))
			local_extent = maxf(local_extent, absf(wb.position.x) * w.scale.x)
			local_extent = maxf(local_extent, absf(wb.position.x + wb.size.x) * w.scale.x)
		var allowed: float = hull_size.x * 0.5 * width_limit
		if mount_reach + local_extent > allowed and local_extent > 0.001:
			# Never invert or vanish the part, even if the mount alone already
			# exceeds the budget - a sliver reads worse than a slight overhang.
			var shrink: float = clampf((allowed - mount_reach) / local_extent, 0.35, 1.0)
			for w in spawned_wheels:
				w.scale *= shrink
				if w.has_meta("module_data"):
					w.get_meta("module_data").scale_multiplier *= shrink
				_resize_collider_to_visual(w)

	# GROUND CONTACT. The hull lift used to be computed from the chassis height
	# (or, before that, a per-type hand-tuned constant), which is only right if
	# every part happens to end exactly at the chassis bottom - and none of them
	# did. Measured against the reference hull, wheels floated 0.13 above the
	# ground, half_track 0.30, pontoon_wheels 0.28, while legs sank 0.31 through
	# it. Measuring where the geometry ACTUALLY ends and lifting the hull by that
	# is both simpler and correct for every type, including the seven new ones
	# that never had a constant of their own.
	var hull_type = hull.get_meta("type_id") if hull.has_meta("type_id") else "medium_hull"
	var hull_catalog_data = ModuleCatalog.get_module_data(hull_type)
	var default_lift: float = (hull_catalog_data.get("size", Vector3.ONE).y * hull_scale.y) / 2.0 + running_gear_size.y
	hull.position.y = default_lift
	if ModuleCatalog.locomotion_touches_ground(type_id):
		var lowest := INF
		for w in spawned_wheels:
			var wb := _visual_bounds(w)
			if wb.size.length_squared() <= 0.0:
				continue
			lowest = minf(lowest, w.position.y + wb.position.y * w.scale.y)
		# The chassis slab is ground contact too when nothing hangs below it.
		if running_gear_size.y > 0.0:
			lowest = minf(lowest, -hull_size.y / 2.0 - running_gear_size.y)
		if lowest < INF:
			hull.position.y = -lowest
				
	# Link them in a group
	for w in spawned_wheels:
		w.set_meta("locomotion_group", spawned_wheels)

	# Each _place_weapon() call above already ran check_all_clipping() as
	# part of placing that single instance, but at that point locomotion_group
	# wasn't set on ANY of the spawned instances yet (it's only assigned in
	# the loop just above, after every instance already exists as a hull
	# child) - so multi-instance types (wheels/legs/rotors/etc, count/width
	# tweaks especially) could get a same-group pair flagged as clipping-red
	# by that stale mid-placement check and never get re-evaluated, since
	# nothing else here calls check_all_clipping() again. Surfaced by the
	# Batch E hull-relative scaling fix - larger locomotion instances on
	# large hulls made transient same-group overlaps during placement much
	# more likely to actually happen. Re-checking now (with the group
	# exemption finally in place) clears any false positive immediately
	# instead of leaving it stuck red until the player's next click/drag.
	check_all_clipping()

	get_tree().call_group("stat_ui", "update_stats", hull)
	
## The bounds of everything a module actually renders, in the module's own
## local space. Empty AABB if it has no meshes yet.
##
## Deliberately walks MeshInstance3D children rather than trusting the catalog
## size: a locomotion assembly's parts are positioned and scaled by its builder
## from tweaks the catalog knows nothing about, so the catalog box and the thing
## on screen routinely disagree by a factor of several.
static func _visual_bounds(module: Node3D) -> AABB:
	var bounds := AABB()
	var seen := false
	for mesh_inst in module.find_children("*", "MeshInstance3D", true, false):
		if mesh_inst.mesh == null:
			continue
		# Each mesh's own AABB, carried up through every intermediate pivot's
		# transform into the module's space. Locomotion builders nest parts
		# under named pivots (rotor hubs, leg knees) that carry real offsets.
		var xf := Transform3D.IDENTITY
		var walker: Node = mesh_inst
		while walker != null and walker != module:
			if walker is Node3D:
				xf = walker.transform * xf
			walker = walker.get_parent()
		var part = xf * mesh_inst.mesh.get_aabb()
		bounds = part if not seen else bounds.merge(part)
		seen = true
	return bounds if seen else AABB()

func _place_weapon(type_id: String, pos: Vector3, normal: Vector3, is_mirror: bool = false, tweaks: Dictionary = {}) -> Node3D:
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var category = catalog_data.get("category", "module")
	
	var new_weapon = Node3D.new()
	
	var VisualBuilder = preload("res://scripts/visual_builder.gd")
	VisualBuilder.build_visual(type_id, new_weapon, catalog_data.get("size", Vector3.ONE), catalog_data.color, tweaks)
	
	var static_body = StaticBody3D.new()
	static_body.collision_layer = 2 # Modules layer
	static_body.collision_mask = 0
	var col_size = catalog_data.get("size", Vector3.ONE)
	var col_center = Vector3(0, col_size.y / 2.0, 0)
	# Locomotion click targets are measured from the geometry that was just
	# built, not re-derived from the tweaks.
	#
	# This used to be a per-type override block: wheels, tracked_treads and legs
	# each had a hand-written box here that restated, in the placer, whatever
	# _build_wheels()/_build_tracked_treads()/_build_legs() had done to the
	# mesh. The same formulas also existed a THIRD time in
	# update_locomotion_geometry_tweak(), to keep the collider in sync during a
	# live slider drag. Three copies of one formula, synchronised by hand, drifted
	# exactly as often as you would expect - "needing to be clicked very close to
	# dead center" once wheel_size moved the wheel away from the box, and a tread
	# collider that stayed a ~2.5-unit stub while the rendered loop spanned the
	# whole hull. Both were fixed by copying the builder's math across again.
	#
	# The builder already knows where it put things, so ask it. The other seven
	# locomotion types never got an override at all and had been silently wrong
	# in the same way; they are fixed by the same change.
	if category == "locomotion":
		var visual_aabb := _visual_bounds(new_weapon)
		if visual_aabb.size.length_squared() > 0.0:
			col_size = visual_aabb.size
			col_center = visual_aabb.get_center()
	static_body.position = col_center
	var collision_shape = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = col_size
	collision_shape.shape = col_box
	static_body.add_child(collision_shape)
	new_weapon.add_child(static_body)

	# Structural pieces get a surface collision body on layer 16
	# (SURFACE_COLLISION_LAYER) so subsequent modules can be placed onto
	# their surfaces via surface_raycast() — same mechanism the hull's
	# own HullSurface body uses, but a simple box collider matching the
	# module's own size rather than a trimesh of the visual geometry.
	if category == "structural":
		var surf_body = StaticBody3D.new()
		surf_body.name = "StructuralSurface"
		surf_body.collision_layer = SURFACE_COLLISION_LAYER
		surf_body.collision_mask = 0
		var surf_col = CollisionShape3D.new()
		var surf_box = BoxShape3D.new()
		surf_box.size = catalog_data.get("size", Vector3.ONE)
		surf_col.shape = surf_box
		surf_col.position = col_center
		surf_body.add_child(surf_col)
		new_weapon.add_child(surf_body)

		# Override the StandardMaterial3D meshes created by VisualBuilder
		# with the hull shader (faction textures, wear, grime, ink border)
		# so structural pieces inherit the faction's visual identity —
		# same as the main hull. This is applied after build_visual so the
		# geometry is correct but the material is the faction shader.
		# Argument order is (armor_material, faction) - these were passed
		# swapped until 2026-07-29, which silently forced every weapon's
		# structural pieces to DEFAULT_FACTION textures instead of the hull's
		# own faction. See building.gd's copy of this note for the mechanism.
		var hull_faction = hull.get_meta("faction") if hull.has_meta("faction") else "industrialists"
		#
		# The authored hardware (bolt pads, brackets, splice collars, hatches
		# - anything named with VisualBuilder.HARDWARE_PREFIX) is deliberately
		# EXEMPT. Painting a bolt head in the same faction livery as the plate
		# it's driven into flattens the piece back into one undifferentiated
		# shader and throws away the detail the authored meshes exist to
		# provide; leaving the hardware as bare dark steel is what makes the
		# faction-painted structure read as painted structure.
		var hull_mat = HullMaterialBuilderScript.build_hull_material("hardened_steel", hull_faction)
		for child in new_weapon.find_children("*", "MeshInstance3D", true, false):
			if child.name.begins_with(VisualBuilderScript.HARDWARE_PREFIX):
				continue
			child.material_override = hull_mat

	var data = ModuleDataResource.new()
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
	data.tweaks = tweaks.duplicate()
	new_weapon.set_meta("module_data", data)
	
	hull.add_child(new_weapon)

	var hull_type_for_mount = hull.get_meta("type_id", "") if hull else ""
	var mount_style = ""
	if category == "weapon":
		mount_style = ModuleCatalog.get_mount_style(type_id, hull_type_for_mount)

	# Snap to 0.25m grid relative to hull local space
	var final_pos = pos
	var local_pos = Vector3.ZERO
	var local_normal = Vector3.UP
	if hull:
		local_pos = hull.to_local(pos)
		local_normal = hull.global_transform.basis.inverse() * normal

		var snap_interval = 0.25
		if abs(local_normal.x) < 0.9:
			local_pos.x = round(local_pos.x / snap_interval) * snap_interval
		if abs(local_normal.y) < 0.9:
			local_pos.y = round(local_pos.y / snap_interval) * snap_interval
		if abs(local_normal.z) < 0.9:
			local_pos.z = round(local_pos.z / snap_interval) * snap_interval

		final_pos = hull.to_global(local_pos)

	new_weapon.global_position = final_pos

	# Weapon meshes are authored with their own mounting post/base baked in
	# (bottom of the mesh sits at local Y=0 - see build_visual()'s
	# monolithic-mesh placement above). Rotating local-up to the surface
	# normal puts that baked-in post flush against whatever facet it landed
	# on - flat deck, sloped glacis, or underside alike - replacing the old
	# column-extrusion + procedurally-drawn hardware model (abandoned; see
	# MOUNTING_AND_ARMOR_SPEC.md addendum, 2026-07-21). Applies uniformly
	# across mount styles now - mount_style only still matters for combat
	# traverse (get_traverse_limit_angle), not visual placement.
	#
	# Every category goes through _align_up_to() now, not just weapons: a
	# radar mast, armor plate or fuel tank dropped on the underside has the
	# same "base against the hull, body projecting outward" requirement a gun
	# does. See _align_up_to() for the antiparallel bug this fixes.
	new_weapon.transform.basis = _align_up_to(local_normal)

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
			
			# The module's base size is catalog_data.get("size", Vector3.ONE), so we scale by ratio
			new_weapon.scale.x = target_x / catalog_data.get("size", Vector3.ONE).x
			new_weapon.scale.z = target_z / catalog_data.get("size", Vector3.ONE).z

			# Center on the facet rather than leaving it at the clicked
			# point: a plate that auto-fits the WHOLE face but stays
			# positioned wherever the player happened to click would poke
			# out past the hull edge on one side. Snap the two in-plane
			# axes to hull-center (0) and keep only the surface-normal axis.
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

	# Face-based weapon mounting: mount_style still drives combat traverse
	# (see get_traverse_limit_angle) but no longer changes how the weapon is
	# placed - every style flush-mounts against the clicked facet now (see
	# the rotation block above).
	if category == "weapon":
		new_weapon.set_meta("mount_style", mount_style)
		new_weapon.set_meta("mount_normal", normal)

	# Notify the UI that a module was added
	get_tree().call_group("stat_ui", "update_stats", hull)
	check_all_clipping()
	return new_weapon

func update_hull_appearance():
	if not hull: return
	var mesh_inst = hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_inst: return
	# MainLab.tscn's hand-authored startup Hull node predates the
	# PhysicsMesh/MeshInstance3D split and only ships the visual one. Bailing
	# out when PhysicsMesh was missing meant the hull the player actually
	# opens the Design Lab looking at never got its authored mesh, faction
	# material, greebles, decals, front arrow or correctly-sized collider -
	# and every later call (armor thickness, faction, scale) silently no-oped
	# for the same reason. Create the node instead of giving up.
	var phys_mesh = hull.get_node_or_null("PhysicsMesh") as MeshInstance3D
	if not phys_mesh:
		phys_mesh = MeshInstance3D.new()
		phys_mesh.name = "PhysicsMesh"
		phys_mesh.visible = false
		hull.add_child(phys_mesh)

	var type_id = hull.get_meta("type_id") if hull.has_meta("type_id") else "medium_hull"
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	
	var hull_scale = hull.get_meta("hull_scale") if hull.has_meta("hull_scale") else Vector3(1,1,1)
	var armor_thick = hull.get_meta("armor_thickness") if hull.has_meta("armor_thickness") else 1.0
	var armor_mat_name = hull.get_meta("armor_material") if hull.has_meta("armor_material") else "hardened_steel"
	var faction_name = hull.get_meta("faction") if hull.has_meta("faction") else "industrialists"
	
	# Bulk size based on thickness
	var armor_bulk = Vector3(1.0 + (armor_thick - 1.0) * 0.15, 1.0 + (armor_thick - 1.0) * 0.15, 1.0)
	var authored_mesh = MeshAssetLoader.get_hull_mesh(type_id)
	if authored_mesh:
		# Per-hull-type custom deform (MOUNTING_AND_ARMOR_SPEC.md #4),
		# proof-of-concept for interceptor_hull only. Genuine regional
		# reshaping of the actual authored mesh via MeshDataTool, not a mesh
		# swap - apply_nose_taper() returns a fresh ArrayMesh each time, so
		# this never mutates MeshAssetLoader's cached shared resource.
			# nose_taper removed with interceptor_hull - hook point for future per-hull mesh deform
		phys_mesh.mesh = authored_mesh
		var fit = ModuleCatalog.get_hull_mesh_fit(type_id, authored_mesh, hull_scale * armor_bulk)
		phys_mesh.rotation = fit["rotation"]
		phys_mesh.scale = fit["scale"]
		phys_mesh.position = fit["position"]
	else:
		var box = BoxMesh.new()
		box.size = catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk
		phys_mesh.mesh = box
		phys_mesh.scale = Vector3.ONE
		phys_mesh.position = Vector3.ZERO

	mesh_inst.mesh = phys_mesh.mesh
	mesh_inst.scale = phys_mesh.scale
	mesh_inst.rotation = phys_mesh.rotation
	mesh_inst.position = phys_mesh.position

	# Precise placement surface has to track every change to the visual mesh
	# (hull swap, rescale, armor bulk, nose taper) or modules would snap to a
	# stale silhouette.
	_rebuild_surface_body(hull, mesh_inst)

	# Apply materials - shared faction+armor shader (see hull_material_builder.gd)
	HullMaterialBuilderScript.apply_hull_materials(mesh_inst, armor_mat_name, faction_name)
	HullGreeblesScript.apply_greebles(hull, faction_name, catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk)
	# Armour-MATERIAL greebles, alongside the faction ones. Same call site and
	# same size argument, because both want the hull's real post-scale extent;
	# they land in separate containers ("HullGreebles" / "ArmorGreebles") so
	# neither can clobber the other's rebuild.
	ArmorGreeblesScript.apply(hull, armor_mat_name, catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk)
	HullDecalsScript.apply_decals(hull, faction_name, catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk)
	
	# Also update collision shape size in the designer
	var col = hull.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.scale = Vector3.ONE
		var col_box = BoxShape3D.new()
		col_box.size = catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk
		col.shape = col_box
		# Deliberately left unrotated - see _place_hull_from_ui() for why
		# inheriting the mesh's orientation correction here is wrong.
		col.rotation = Vector3.ZERO
			
	# Manage Front Arrow Indicator (Green triangle pointing along -Z)
	var arrow = hull.get_node_or_null("FrontArrow")
	if not arrow:
		arrow = Node3D.new()
		arrow.name = "FrontArrow"
		
		# Tip: a cone pointing forward (-Z)
		var tip = MeshInstance3D.new()
		tip.name = "Tip"
		var cone = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.18
		cone.height = 0.35
		tip.mesh = cone
		tip.rotation.x = -PI / 2.0
		tip.position = Vector3(0, 0, -0.175)
		arrow.add_child(tip)
		
		# Shaft: a cylinder behind the tip
		var shaft = MeshInstance3D.new()
		shaft.name = "Shaft"
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 0.35
		shaft.mesh = cyl
		shaft.rotation.x = -PI / 2.0
		shaft.position = Vector3(0, 0, 0.175)
		arrow.add_child(shaft)
		
		# Vibrant green material
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.9, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.7, 0.1)
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		tip.material_override = mat
		shaft.material_override = mat
		
		hull.add_child(arrow)
		
	var vis_size = catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk
	# Position at the front-center of the deck, slightly raised
	arrow.position = Vector3(0, vis_size.y / 2.0 + 0.3, -vis_size.z / 2.0 - 0.5)
	
	# Recalculate stats
	get_tree().call_group("stat_ui", "update_stats", hull)
	check_all_clipping()

# Immediate free (not queue_free) for exactly the same reason _deselect_module()
# frees the "ArcCone" immediately: a gizmo is routinely torn down and rebuilt
# within a SINGLE frame - _select_module(m) is called with m already selected
# on every drag release, and the drag-start handler drops the gizmo just before
# the drag begins. queue_free()'s deferred removal leaves the old node in the
# tree long enough that Godot renames the incoming "Gizmo3D" to "Gizmo3D2" to
# avoid the sibling name collision, after which this by-name lookup can never
# find it again - so the gizmo is orphaned from cleanup and a fresh one stacks
# on top of it on every subsequent drag.
func _free_gizmo(module: Node3D):
	if not module or not is_instance_valid(module):
		return
	# Loop rather than a single lookup so any gizmos already orphaned under a
	# generated name by the old code get cleaned up too.
	for child in module.get_children():
		if child.name.begins_with("Gizmo3D"):
			module.remove_child(child)
			child.free()

func _deselect_module():
	# is_instance_valid guard (2026-07-23 locomotion-tweak fix): a
	# count-changing locomotion tweak (num_axles etc.) calls
	# update_locomotion() synchronously, which queue_free()s every existing
	# instance of that type INCLUDING the currently-selected one, then
	# _apply_tweaks() call_deferred()s a reselect of one of the freshly
	# respawned instances. By the time that deferred _select_module() runs
	# (and reaches here via _deselect_module()), `selected_module` still
	# points at the OLD, by-then-actually-freed instance - selected_module
	# alone is a stale Object reference, not null, so the old `if
	# selected_module:` check passed and get_children() below threw on a
	# freed instance. With the debugger attached (the normal editor Play
	# session) an uncaught script error like that pauses/freezes the running
	# game - exactly the "game locks up" symptom reported when adjusting
	# axle/wheel count.
	if selected_module and is_instance_valid(selected_module):
		# Immediate free (not queue_free) - same reasoning as
		# _refresh_firing_arc()'s own old-arc cleanup: _select_module()
		# calls this and then immediately adds a fresh "ArcCone" (e.g. the
		# reselect-after-drag path in _unhandled_input's mouse-release
		# handler, in the SAME frame). queue_free()'s deferred removal
		# would leave the stale node around long enough for Godot to
		# auto-rename the new one to "ArcCone2" to avoid the name
		# collision - after that, this exact by-name lookup can never find
		# it again, and the firing arc is permanently orphaned from
		# cleanup (visible forever, even after later real deselects).
		for child in selected_module.get_children():
			if child.name == "ArcCone":
				selected_module.remove_child(child)
				child.free()

# Firing envelope preview.
#
# Rewritten 2026-07-21 (Chris: pintle mounts fire in a full sphere, and line
# of sight against the hull/other modules is what limits them). This used to
# draw a flat horizontal wedge at the weapon's own height, which said nothing
# about elevation or depression and so could not express either half of that:
# a pintle's envelope is a SPHERE, minus whatever its own vehicle occludes.
#
# Samples directions over a sphere and raycasts each one against the hull
# (layer 1) and sibling modules (layer 2) - the same two layers auto_weapon.gd
# checks before it fires - so a blocked patch here is a shot combat will
# genuinely refuse to take. Clear directions read blue, occluded ones red.
const ARC_AZIMUTH_SEGMENTS := 24
const ARC_ELEVATION_SEGMENTS := 12
const ARC_RADIUS := 3.0

func _build_firing_arc(module: Node3D, data) -> Node3D:
	var container = Node3D.new()
	container.name = "ArcCone"

	var arc_facet = module.get_meta("facet", "")
	if arc_facet == "" and module.has_meta("mount_normal") and hull:
		var local_mount_normal = hull.global_transform.basis.inverse() * module.get_meta("mount_normal")
		arc_facet = ModuleCatalog.classify_facet(local_mount_normal)
	var arc_hull_type = hull.get_meta("type_id", "") if hull else ""
	var limit = ModuleCatalog.get_traverse_limit_angle(data.type_id, arc_facet, arc_hull_type)

	var exclude_list = []
	_get_colliders_recursive(module, exclude_list)
	var space_state = get_world_3d().direct_space_state
	# Trace from just off the weapon's own mounting face, along ITS up axis -
	# world-up would start a side- or belly-mounted weapon's rays inside the
	# hull it is bolted to and report everything as blocked.
	var origin = module.global_position + module.global_transform.basis.y.normalized() * 0.35

	# frame_built: no independent traverse at all, the whole vehicle aims.
	# A sphere would be a lie, so draw a single forward spike instead.
	if limit <= 0.001:
		container.add_child(_build_fixed_forward_indicator(module, origin, exclude_list, space_state))
		return container

	var clear_vertices = []
	var blocked_vertices = []

	for ei in range(ARC_ELEVATION_SEGMENTS):
		# Polar angle from +Y (0 = straight up, PI = straight down), so the
		# band genuinely covers full elevation AND full depression.
		var t0 = float(ei) / ARC_ELEVATION_SEGMENTS
		var t1 = float(ei + 1) / ARC_ELEVATION_SEGMENTS
		var phi0 = t0 * PI
		var phi1 = t1 * PI
		for ai in range(ARC_AZIMUTH_SEGMENTS):
			var u0 = float(ai) / ARC_AZIMUTH_SEGMENTS * TAU
			var u1 = float(ai + 1) / ARC_AZIMUTH_SEGMENTS * TAU
			var mid = _sphere_point((phi0 + phi1) * 0.5, (u0 + u1) * 0.5, 1.0)
			var world_dir = (module.global_transform.basis * mid).normalized()

			var query = PhysicsRayQueryParameters3D.create(origin, origin + world_dir * ARC_RADIUS)
			query.collision_mask = 3 # Layer 1 (Hull) + Layer 2 (Modules)
			query.exclude = exclude_list
			var blocked = not space_state.intersect_ray(query).is_empty()

			var a = _sphere_point(phi0, u0, ARC_RADIUS)
			var b = _sphere_point(phi0, u1, ARC_RADIUS)
			var c = _sphere_point(phi1, u1, ARC_RADIUS)
			var d = _sphere_point(phi1, u0, ARC_RADIUS)
			var bucket = blocked_vertices if blocked else clear_vertices
			for v in [a, b, c, a, c, d]:
				bucket.append(v)

	if not clear_vertices.is_empty():
		container.add_child(_arc_surface("ClearArc", clear_vertices, Color(0.2, 0.6, 1.0, 0.12), Color(0.2, 0.6, 1.0)))
	if not blocked_vertices.is_empty():
		container.add_child(_arc_surface("BlockedArc", blocked_vertices, Color(1.0, 0.15, 0.15, 0.3), Color(1.0, 0.15, 0.15)))

	return container

# Point on a sphere in the module's local frame. phi is measured from +Y so
# phi=0 is straight up and phi=PI straight down; azimuth 0 faces -Z, matching
# the barrel-forward convention used everywhere else.
static func _sphere_point(phi: float, azimuth: float, radius: float) -> Vector3:
	var sin_phi = sin(phi)
	return Vector3(sin_phi * sin(azimuth), cos(phi), -sin_phi * cos(azimuth)) * radius

func _arc_surface(surface_name: String, vertices: Array, albedo: Color, emission: Color) -> MeshInstance3D:
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in vertices:
		mesh.surface_add_vertex(v)
	mesh.surface_end()

	var mi = MeshInstance3D.new()
	mi.name = surface_name
	mi.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.albedo_color = albedo
	mat.emission = emission
	mat.emission_energy_multiplier = 0.5
	# The envelope wraps the weapon, so without this it z-fights its own far
	# side and the module inside it.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = mat
	return mi

# A frame_built weapon aims by turning the whole vehicle, so its "arc" is one
# fixed direction - drawn as a short spike, coloured by whether that single
# line of fire is clear.
func _build_fixed_forward_indicator(module: Node3D, origin: Vector3, exclude_list: Array, space_state) -> MeshInstance3D:
	var world_dir = -module.global_transform.basis.z.normalized()
	var query = PhysicsRayQueryParameters3D.create(origin, origin + world_dir * ARC_RADIUS)
	query.collision_mask = 3
	query.exclude = exclude_list
	var blocked = not space_state.intersect_ray(query).is_empty()

	var half = 0.08
	var tip = Vector3(0, 0, -ARC_RADIUS)
	var verts = [
		Vector3(-half, 0, 0), Vector3(half, 0, 0), tip,
		Vector3(0, -half, 0), Vector3(0, half, 0), tip,
	]
	if blocked:
		return _arc_surface("BlockedArc", verts, Color(1.0, 0.15, 0.15, 0.5), Color(1.0, 0.15, 0.15))
	return _arc_surface("ClearArc", verts, Color(0.2, 0.6, 1.0, 0.5), Color(0.2, 0.6, 1.0))

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

# --- Precise placement surface ---------------------------------------------
#
# The hull's CollisionShape3D is an axis-aligned BOX of the catalog size,
# because that is what every dimension-reading caller needs (locomotion
# mounting, armor facet fitting, clipping). But a hull mesh only touches that
# box where it is widest: everywhere it curves, tapers or slopes, the visible
# surface sits well inside its own bounding box. Placement raycasts hit the
# box, so modules landed on an invisible shell and floated off the hull -
# worst on the tapered ship keels and the airship's curved envelope.
#
# HullSurface is a second StaticBody3D carrying a trimesh of the ACTUAL hull
# mesh, on its own collision layer so placement can query it alone. Layer 5
# (bit value 16) is unused by the hull(1)/modules(2)/gizmos(4)/buildings(8)
# assignments already in play. Placement prefers a HullSurface hit and falls
# back to the box when there is no authored mesh to trace against.
const SURFACE_COLLISION_LAYER := HullSurfaceScript.SURFACE_COLLISION_LAYER

# Delegates to scripts/hull_surface.gd so blueprint_manager.gd's designer
# reconstruction can build an identical surface body for a loaded blueprint.
func _rebuild_surface_body(target_hull: Node3D, source_mesh_inst: MeshInstance3D):
	HullSurfaceScript.rebuild(target_hull, source_mesh_inst)

# Raycast used by every placement path. Traces the precise hull surface first
# and only falls back to the bounding box if that misses, so a dropped module
# sits on the hull you can see rather than on its bounding shell.
func surface_raycast(ray_origin: Vector3, ray_dir: Vector3, length: float = 1000.0, exclude: Array = []):
	var space_state = get_world_3d().direct_space_state
	var to = ray_origin + ray_dir * length
	var precise = PhysicsRayQueryParameters3D.create(ray_origin, to)
	precise.collision_mask = SURFACE_COLLISION_LAYER
	precise.exclude = exclude
	var hit = space_state.intersect_ray(precise)
	if hit:
		return hit
	var fallback = PhysicsRayQueryParameters3D.create(ray_origin, to)
	fallback.collision_mask = 1
	fallback.exclude = exclude
	return space_state.intersect_ray(fallback)

# Basis that rotates the module's local +Y (its "up", i.e. the direction the
# body projects away from its baked-in mounting base) onto `n`, the surface
# normal of the facet it was dropped on. Every category uses this now, so a
# module's base always sits flush against the hull and its body always
# projects outward - including straight down off the underside.
#
# Two bugs this replaces:
#
# 1. Godot's Quaternion(from, to) constructor special-cases ANTIPARALLEL
#    inputs to the quaternion (0,1,0,0) - a 180-degree spin about Y - which
#    maps UP straight back to UP. So Basis(Quaternion(UP, DOWN)) is not a
#    flip at all, and anything mounted on the hull's underside kept pointing
#    UP, burying its body inside the hull instead of hanging below it.
# 2. Non-weapon categories additionally guarded the whole rotation behind
#    `abs(normal.dot(UP)) < 0.999`, which skips the top and bottom faces
#    entirely - the two facets most likely to need it.
static func _align_up_to(n: Vector3) -> Basis:
	var target = n.normalized()
	if target.length_squared() < 0.5:
		return Basis.IDENTITY
	var d = Vector3.UP.dot(target)
	if d > 1.0 - 0.000001:
		return Basis.IDENTITY
	if d < -1.0 + 0.000001:
		# Genuine flip: rotate a half turn about a HORIZONTAL axis, so +Y
		# really does end up pointing at -Y.
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, target))

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
		# Structural pieces keep node.scale at ONE and carry their resize in
		# the struct_scale meta instead (scale isolation - see gizmo_3d.gd), so
		# reading .scale alone would AABB every stretched structural piece at
		# its original catalog size and miss real overlaps.
		var my_size = my_catalog.size * my_module.get_meta("struct_scale", my_module.scale)
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

			var other_data_early = other_module.get_meta("module_data")
			# Armor is a skin, not an obstruction. MOUNTING_AND_ARMOR_SPEC.md
			# #2 has an armor plate "auto-scale to exactly fit the facet it's
			# deployed on", and #3 has weapons/devices mounting onto those same
			# facets - so armouring the deck and then mounting a deck gun is a
			# completely ordinary design, yet every module on an armoured facet
			# used to overlap the plate's AABB and flag the whole vehicle
			# clipping-red. Exempt armor-vs-anything-else while still catching
			# armor-vs-armor, which is a genuine conflict (two plates fighting
			# over the same facet).
			var one_is_armor = (my_data.category == "armor") != (other_data_early.category == "armor")
			if one_is_armor:
				continue

			var other_data = other_data_early
			var other_catalog = ModuleCatalog.get_module_data(other_data.type_id)
			var other_size = other_catalog.size * other_module.get_meta("struct_scale", other_module.scale)
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

		# SWAP the override, never MUTATE it. Two separate reasons, both real:
		#
		# 1. Materials are now shared per role+tint (part_materials.gd), for
		#    the sake of bake_module_visual()'s identity-keyed merge. Writing
		#    albedo_color on one part's material here would repaint every
		#    other part in the scene that happens to share that role - one
		#    clipping module would turn the entire vehicle red.
		#
		# 2. Even before sharing, the "not clipping" branch flattened EVERY
		#    mesh in the module to the catalog colour on every single pass -
		#    and this runs on every placement, drag, rotation and tweak. So
		#    the per-part colours the builders carefully assign (dark barrel,
		#    pale lens, warm brass) survived only until the first clipping
		#    check, which is to say never. Remembering the original override
		#    and restoring THAT is what lets per-part material roles actually
		#    reach the screen in the Design Lab.
		for mesh in meshes:
			if not mesh.has_meta("base_material"):
				mesh.set_meta("base_material", mesh.material_override)
			if is_clipping:
				mesh.material_override = _clipping_material()
			else:
				mesh.material_override = mesh.get_meta("base_material")

	_refresh_firing_arc()
	_update_cog_crosshair()

var _cog_node: Node3D = null

func _update_cog_crosshair():
	if not hull:
		if _cog_node: _cog_node.visible = false
		return

	var total_mass: float = 250.0 # base hull mass
	if hull.has_meta("weight"):
		total_mass = float(hull.get_meta("weight"))

	var weighted_pos = hull.global_position * total_mass

	for child in hull.get_children():
		if child.has_meta("module_data") and not child.is_queued_for_deletion():
			var mdata = child.get_meta("module_data")
			var m_weight = 20.0
			if "weight" in mdata:
				m_weight = float(mdata.weight)
			total_mass += m_weight
			weighted_pos += child.global_position * m_weight

	var cog_pos = weighted_pos / max(1.0, total_mass)

	if not _cog_node:
		_cog_node = Node3D.new()
		add_child(_cog_node)

		# Build 3D crosshair lines
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			var line_inst = MeshInstance3D.new()
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = 0.02
			cylinder.bottom_radius = 0.02
			cylinder.height = 1.6
			line_inst.mesh = cylinder
			if axis == Vector3.RIGHT:
				line_inst.rotation.z = PI / 2.0
			elif axis == Vector3.BACK:
				line_inst.rotation.x = PI / 2.0

			var mat = StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.0, 0.95, 1.0, 0.9) # Bright CAD cyan
			mat.no_depth_test = true
			mat.render_priority = 8
			line_inst.material_override = mat
			_cog_node.add_child(line_inst)

		var lbl = Label3D.new()
		lbl.text = "⊕ COG TELEMETRY"
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.render_priority = 9
		lbl.font_size = 15
		lbl.modulate = Color(0.0, 0.95, 1.0)
		lbl.position = Vector3(0, 0.9, 0)
		_cog_node.add_child(lbl)

	_cog_node.visible = true
	_cog_node.global_position = cog_pos

# Collects the module's own body meshes for clipping recolouring. Skips the
# editor-overlay subtrees entirely: "ArcCone" (firing-arc wedges, which carry
# their own deliberate blue/red materials) and "Gizmo3D" (the manipulator
# handles). The gizmo was previously walked into and had material_override
# assigned on every clipping pass, so selecting a module repainted its own
# transform handles in the module's catalog colour - and turned them solid red
# whenever the module was clipping, which is precisely when you need to see
# the handles to drag it back out.
# One shared "this part is clipping" material for the whole scene. Built once
# rather than per mesh so swapping it in is free, and so it can never be
# confused with a part's own material by the base_material bookkeeping above.
static var _clipping_mat: StandardMaterial3D = null

static func _clipping_material() -> StandardMaterial3D:
	if _clipping_mat == null:
		_clipping_mat = StandardMaterial3D.new()
		_clipping_mat.albedo_color = Color(1.0, 0.0, 0.0)
		_clipping_mat.emission_enabled = true
		_clipping_mat.emission = Color(1.0, 0.0, 0.0)
		_clipping_mat.emission_energy_multiplier = 1.0
		_clipping_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _clipping_mat

func _find_meshes_recursive(node: Node, result: Array):
	if node.name == "ArcCone" or node.name.begins_with("Gizmo3D"):
		return
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_meshes_recursive(child, result)

func _update_module_placement(module: Node3D, world_pos: Vector3, normal: Vector3):
	if not module or not is_instance_valid(module): return

	var data = module.get_meta("module_data")
	var catalog_data = ModuleCatalog.get_module_data(data.type_id)
	var category = data.category

	# Remembered so drag-end can re-run the same facet/mount classification
	module.set_meta("_last_drag_normal", normal)

	var local_pos = hull.to_local(world_pos)
	var local_normal = hull.global_transform.basis.inverse() * normal
	
	var snap_interval = 0.25
	if abs(local_normal.x) < 0.9:
		local_pos.x = round(local_pos.x / snap_interval) * snap_interval
	if abs(local_normal.y) < 0.9:
		local_pos.y = round(local_pos.y / snap_interval) * snap_interval
	if abs(local_normal.z) < 0.9:
		local_pos.z = round(local_pos.z / snap_interval) * snap_interval

	var hull_type_for_mount = hull.get_meta("type_id", "") if hull else ""
	var mount_style = ""
	if category == "weapon":
		mount_style = ModuleCatalog.get_mount_style(data.type_id, hull_type_for_mount)
		module.set_meta("mount_style", mount_style)
		module.set_meta("mount_normal", normal)

	# Non-weapons used to get an extra `normal * size.y / 2` push-off here,
	# which _place_weapon() never applies. Module meshes are built with their
	# base at local Y=0 (build_visual() offsets the mesh up by half its height
	# so the BOTTOM lands on the origin), so the origin belongs exactly on the
	# surface - that extra half-height left every non-weapon module hovering
	# off the hull the moment it was dragged, at a different height than where
	# it was originally dropped.
	module.position = local_pos

	# Same alignment as initial placement, for every category - see
	# _place_weapon() and _align_up_to().
	module.transform.basis = _align_up_to(local_normal)

	var yaw_offset = module.get_meta("yaw_offset", 0.0)
	module.rotate_object_local(Vector3.UP, yaw_offset)
	
	if category == "weapon":
		var VisualBuilder = preload("res://scripts/visual_builder.gd")
		VisualBuilder.rebuild_visual(module)
		if module.get_meta("is_mirror", false):
			_apply_mirror_flip(module)
		
	if module.has_meta("mirrored_counterpart"):
		var mirror = module.get_meta("mirrored_counterpart")
		if mirror and is_instance_valid(mirror):
			var mirrored_local_pos = Vector3(-local_pos.x, local_pos.y, local_pos.z)
			mirror.position = mirrored_local_pos

			var mirrored_normal = Vector3(-normal.x, normal.y, normal.z)
			var local_mirrored_normal = hull.global_transform.basis.inverse() * mirrored_normal
			mirror.transform.basis = _align_up_to(local_mirrored_normal)

			mirror.rotate_object_local(Vector3.UP, -yaw_offset)
			if category == "weapon":
				mirror.set_meta("mount_style", mount_style)
				mirror.set_meta("mount_normal", mirrored_normal)
				var VisualBuilder = preload("res://scripts/visual_builder.gd")
				VisualBuilder.rebuild_visual(mirror)
			_apply_mirror_flip(mirror)

# Re-runs the same facet/mount classification _place_weapon() does at initial placement.
func _reclassify_module_after_drag(module: Node3D, normal: Vector3, is_mirror: bool = false):
	if not module or not is_instance_valid(module) or not module.has_meta("module_data"):
		return
	var data = module.get_meta("module_data")
	var category = data.category
	if category != "armor" and category != "weapon":
		return
	if not hull:
		return
	var catalog_data = ModuleCatalog.get_module_data(data.type_id)

	var hull_size = Vector3(4.0, 1.0, 6.0)
	var hull_shape = hull.get_node_or_null("CollisionShape3D")
	if hull_shape and hull_shape.shape is BoxShape3D:
		hull_size = hull_shape.shape.size
	var local_normal = hull.global_transform.basis.inverse() * normal

	if category == "armor":
		var local_x = module.global_transform.basis.x.abs()
		var local_z = module.global_transform.basis.z.abs()
		var target_x = 1.0
		var target_z = 1.0
		if local_x.x > 0.5: target_x = hull_size.x
		elif local_x.y > 0.5: target_x = hull_size.y
		elif local_x.z > 0.5: target_x = hull_size.z
		if local_z.x > 0.5: target_z = hull_size.x
		elif local_z.y > 0.5: target_z = hull_size.y
		elif local_z.z > 0.5: target_z = hull_size.z
		module.scale.x = target_x / catalog_data.get("size", Vector3.ONE).x
		module.scale.z = target_z / catalog_data.get("size", Vector3.ONE).z

		var armor_facet = ModuleCatalog.classify_facet(local_normal)
		var centered_local = Vector3.ZERO
		match armor_facet:
			"left", "right":
				centered_local = Vector3(sign(local_normal.x) * hull_size.x / 2.0, 0, 0)
			"front", "back":
				centered_local = Vector3(0, 0, sign(local_normal.z) * hull_size.z / 2.0)
			_:
				centered_local = Vector3(0, sign(local_normal.y) * hull_size.y / 2.0, 0)
		module.global_position = hull.to_global(centered_local)
		module.set_meta("facet", armor_facet)

	elif category == "weapon":
		var hull_type_for_mount = hull.get_meta("type_id", "") if hull else ""
		var mount_style = ModuleCatalog.get_mount_style(data.type_id, hull_type_for_mount)
		module.set_meta("mount_style", mount_style)
		module.set_meta("mount_normal", normal)
		# Position/rotation are already flush-mounted to the new facet by
		# the last _update_module_placement() call during the drag - this
		# just finalizes the mount_style classification and rebuilds the
		# visual for the new facet's mesh (e.g. tweak deformations).
		var VisualBuilder = preload("res://scripts/visual_builder.gd")
		VisualBuilder.rebuild_visual(module)
		if module.get_meta("is_mirror", false):
			_apply_mirror_flip(module)

	if not is_mirror and module.has_meta("mirrored_counterpart"):
		var mirror = module.get_meta("mirrored_counterpart")
		if mirror and is_instance_valid(mirror):
			var mirrored_normal = Vector3(-normal.x, normal.y, normal.z)
			_reclassify_module_after_drag(mirror, mirrored_normal, true)

func _get_colliders_recursive(node: Node, list: Array):
	if node is CollisionObject3D:
		list.append(node.get_rid())
	for child in node.get_children():
		_get_colliders_recursive(child, list)

# Mirrors a module's visuals across the module's own YZ plane, so a left-side
# instance is the true reflection of the right-side one rather than a second
# copy of it. Applied to the module's DIRECT visual children (nested geometry
# inherits it) - never to the module node's own scale, which would put a
# negative factor into collision shapes and into module_data.scale_multiplier,
# where the stat maths reads it.
#
# Rewritten 2026-07-21. The old version walked the whole subtree flipping each
# MeshInstance3D's LOCAL scale.z, which only mirrors across module-X for a
# mesh that happens to carry the authored parts' 90-degree yaw offset - the
# procedural-fallback meshes have no such offset, so it mirrored them along
# the wrong axis. Reflecting the child's whole transform in module space is
# correct whatever orientation the child is in.
#
# The "_mirrored" marker keeps this idempotent: a reflection is its own
# inverse, so calling it twice on the same node would silently undo it, and
# it IS called repeatedly - once per mouse-motion frame while dragging a
# mirrored module. rebuild_visual() destroys and recreates these children, so
# fresh geometry is correctly unmarked and gets mirrored again.
# The reflection itself, and the cull-mode compensation it requires, now live
# in ModuleMirror - blueprint_manager.gd's reconstruct path needs the exact
# same behaviour, and when these were two separate copies that copy silently
# lost the compensation.
func _apply_mirror_flip(module: Node3D):
	if not module or not is_instance_valid(module): return
	if not module.get_meta("scale_flip_x", false): return
	ModuleMirrorScript.apply(module)
