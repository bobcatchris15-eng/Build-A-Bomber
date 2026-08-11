extends Node3D
const ModuleDataResource = preload("res://scripts/module_data.gd")


const Gizmo3D = preload("res://scenes/Gizmo3D.tscn")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const ModuleMirrorScript = preload("res://scripts/module_mirror.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")
const VisualBuilderScript = preload("res://scripts/visual_builder.gd")
# Only for the shared elevation/depression tolerances the firing-arc envelope
# has to match - see _build_firing_arc().
const AutoWeaponScript = preload("res://scripts/auto_weapon.gd")
const HullGreeblesScript = preload("res://scripts/hull_greebles.gd")
const UITokens = preload("res://scripts/ui_tokens.gd")
const ArmorGreeblesScript = preload("res://scripts/armor_greebles.gd")
# hull_decals.gd is deliberately NOT preloaded any more - the Lab draws no
# faction insignia. Battle spawns still get theirs via blueprint_manager.
const LiveryScript = preload("res://scripts/livery.gd")
const HullSurfaceScript = preload("res://scripts/hull_surface.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")
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
	call_deferred("_check_first_time_instructions")

func _restore_test_session() -> void:
	var bp_manager = get_node_or_null("BlueprintManager")
	if bp_manager and bp_manager.has_pending_lab_restore():
		bp_manager.restore_scratch_into_designer()
		
func _process(delta: float):
	# Live idle spin for helicopter_rotors blades while designing - the
	# Design Lab canvas never had this at all (unit.gd in combat now,
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
				# Chris: the innermost ring should turn about a horizontal axis
				# as well. One axis alone reads as a flat spin like the outer
				# rings; a second, slower one about Z makes it tumble, which is
				# what sells the gimbal.
				inner_ring.rotate_z(7.0 * delta)

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
		# Actions, not keycodes - see InputService's header for why this file's
		# raw comparisons had to go. REDO IS TESTED BEFORE UNDO: its Ctrl+Shift+Z
		# form also satisfies a permissively-matched Ctrl+Z, so checking undo
		# first would swallow every redo. InputService._descriptors_equal()
		# compares modifiers exactly for the same reason.
		if event.is_action_pressed("lab_mirror"):
			mirror_enabled = not mirror_enabled
			_log("Mirror toggled: " + str(mirror_enabled))
			var tree = get_tree()
			if tree: tree.call_group("stat_ui", "set_mirror_toggle", mirror_enabled)
		elif event.is_action_pressed("lab_delete"):
			delete_selected_module()
		elif event.is_action_pressed("lab_rotate"):
			rotate_selected_module()
		elif event.is_action_pressed("lab_redo"):
			redo()
		elif event.is_action_pressed("lab_undo"):
			undo()
		elif event.is_action_pressed("ui_cancel"):
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
					# We clicked a Module or sub-node!
					var module: Node = result.collider
					var curr: Node = module
					while curr != null and curr != hull and curr != get_tree().root:
						if curr.has_meta("module_data"):
							module = curr
							break
						curr = curr.get_parent()
					_select_module(module if (module != null and module.has_meta("module_data")) else result.collider)
					
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
					# Same refusal the build bar applies, so a lobbing weapon
					# cannot be dragged onto a wall it was not allowed to be
					# placed on. Enforced HERE rather than inside
					# _update_module_placement() so the rule lives on the one
					# interactive path and direct callers (tests, scripted
					# setup) keep working unchanged. The module simply stops
					# following the cursor over a face it cannot occupy, which
					# reads as "it won't go there" without a toast firing every
					# frame of the drag.
					var drag_data = selected_module.get_meta("module_data", null)
					var drag_refused = false
					if drag_data != null:
						drag_refused = _placement_refusal_reason(
							drag_data.type_id, drag_data.category, result.normal) != ""
					if not drag_refused:
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
	# A sponson blister is welded to the hull face, not to the gun spinning on
	# it, so its counter-rotation has to be re-applied whenever yaw changes
	# outside of a full rebuild.
	VisualBuilderScript.refresh_sponson_blister(selected_module)

	if selected_module.has_meta("mirrored_counterpart"):
		var mirror = selected_module.get_meta("mirrored_counterpart")
		if mirror and is_instance_valid(mirror):
			mirror.set_meta("yaw_offset", -yaw)
			mirror.rotate_object_local(Vector3.UP, -PI / 2.0)
			VisualBuilderScript.refresh_sponson_blister(mirror)

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
			elif cat == "hull":
				# Hull scales in all 3 directions; whole-vehicle orientation
				# isn't a placement tweak, so no rotation ring.
				if hrot: hrot.queue_free()
				
		# Firing Arc Visualization ("Radar Sweep", Design_Lab_UI_UX.md): a
		# horizontal wedge spanning the weapon's actual traverse_limit_angle
		# (shared with combat via ModuleCatalog.get_traverse_limit_angle),
		# raycast per-segment against the hull/other modules so blocked
		# angles read alert-red and clear angles read hazard-orange - not a
		# fixed decorative cone. Kept live via _refresh_firing_arc(), called
		# from check_all_clipping() so it updates after drags/tweaks/rotation.
		if show_firing_arc and selected_module.has_meta("module_data"):
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
	# Legs had no entry here at all, so a freshly-dragged set arrived with an
	# empty settings dict and every default had to be re-derived downstream.
	# leg_type in particular has to be present from the first placement, because
	# it decides whether the stations go under the hull or on its flank.
	"legs": {"leg_length": 1.0, "leg_width": 1.0, "count": 4, "leg_type": "stryker"},
	"hover_engine": {},
	"helicopter_rotors": {"size": 1.0, "count": 4},
	"fixed_wing_engine": {"size": 1.0, "count": 2},
	"ornithopter_wing": {"size": 1.0, "count": 2},
	"buoyant_envelope": {"prop_count": 2, "blade_count": 3, "blade_pitch": 1.0},
	"screw_drive": {"drum_diameter": 1.0, "helix_depth": 1.0}
}

func _place_weapon_from_ui(type_id: String, pos: Vector3, normal: Vector3):
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var category = catalog_data.get("category", "module")

	# Refused BEFORE push_undo_snapshot(), so a rejected click does not leave a
	# do-nothing entry on the undo stack for the player to step back through.
	var refusal = _placement_refusal_reason(type_id, category, normal)
	if refusal != "":
		var bm_toast = get_node_or_null("BlueprintManager")
		if bm_toast and bm_toast.has_method("_show_toast"):
			bm_toast._show_toast(refusal, true)
		_log("Placement refused: " + refusal)
		return

	push_undo_snapshot()

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
			var local_n = hull.global_transform.basis.inverse() * normal if hull else normal
			var abs_n = local_n.abs()
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

## Slides each leg inboard until its origin lands on the hull's VISIBLE skin.
##
## Chris: the legs should "mount directly to the VISIBLE hull mesh" - no plate,
## no standoff. That is a different surface from the one the layout works in.
## LocomotionLayout positions every station against hull_size, which is the
## COLLISION BOX; since the hull roster moved to the SDF/marching-cubes bake, a
## hull is routinely narrower or more tapered than its declared box, so a station
## on the box plane can hang in clear air beside the model it is supposed to be
## bolted to.
##
## Raycast inward along the mount axis and take the first triangle: that is where
## the hull actually is. A miss leaves the leg exactly where the layout put it,
## which is the current behaviour and a safe answer for a hull with no visible
## mesh (a bare test rig, a primitive-shape hull mid-load).
##
## HullProjection rather than a physics query on purpose - it is pure
## Moller-Trumbore over Mesh.get_faces(), so it works headless and needs no
## physics step to have run, which matters because this runs during
## construction. Same reasoning hull_decals.gd documents for using it.
func _seat_legs_on_hull_skin(legs: Array, hull_size: Vector3) -> void:
	if legs.is_empty() or not is_instance_valid(hull):
		return
	var mesh_inst := hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_inst == null or mesh_inst.mesh == null:
		return
	var surface: Dictionary = HullProjectionScript.build_surface(mesh_inst)
	if surface.get("tris", PackedVector3Array()).size() < 3:
		return

	for leg in legs:
		if not is_instance_valid(leg):
			continue
		var side: float = signf(leg.position.x)
		if is_zero_approx(side):
			continue

		# SAMPLED UP THE FLANK, not fired once at the station's own height.
		#
		# A leg station sits on the belly line, and a hull with any curve at all
		# is pinching in by the time it reaches its lowest point - so a single
		# horizontal ray at exactly that y passes UNDER the geometry and misses.
		# Measured: medium_hull and heavy_hull hit, scout_hull and
		# flying_wing_hull missed at every station, which would have left the
		# legs on those two floating at the bounding box exactly as before.
		#
		# Sampling a short ladder up into the body of the hull and keeping the
		# OUTERMOST hit finds the widest point the leg can bolt to, which is what
		# a real hardpoint would use.
		var best_x: float = INF * side
		for frac in [0.06, 0.18, 0.32, 0.50]:
			# Start outside the widest point the hull could possibly reach, so the
			# first triangle is the OUTER skin rather than a far wall hit from
			# inside.
			var from := Vector3(side * hull_size.x,
				leg.position.y + hull_size.y * frac, leg.position.z)
			var hit: Dictionary = HullProjectionScript.raycast(
				surface, from, Vector3(-side, 0.0, 0.0))
			if not hit.get("hit", false):
				continue
			var x: float = hit["position"].x
			if absf(x) > absf(best_x) or is_inf(best_x):
				best_x = x
		if is_inf(best_x):
			continue
		# x only. The layout owns y (belly line or flank height) and z (the
		# fore/aft spread), and both are load-bearing elsewhere - y feeds the
		# ride-height solve and z keeps the legs evenly spaced along the hull.
		leg.position.x = best_x


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

	# NO RUNNING-GEAR SLAB, AND NO SUBFRAME. Chris, 2026-08-02: "Drop the
	# running gear / subframe (from everything actually)."
	#
	# It was introduced to solve "the vehicle slides on its belly" by putting a
	# procedural chassis under the hull for the gear to sit on. Ground contact
	# is now MEASURED from where the locomotion geometry actually ends (see the
	# lift block further down), which solves that properly and for every type,
	# so the slab was doing nothing but adding a second structure under every
	# vehicle - the same two-structures mistake the subframe made, and the
	# reason parts kept reading as mounted to a box rather than to the hull.
	#
	# running_gear_size stays as a zero Vector3 rather than being deleted: it is
	# still read as a layout input by several patterns, and zeroing it is what
	# tells them there is nothing under the hull.
	var running_gear_size := Vector3.ZERO

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

	if type_id == "legs":
		_seat_legs_on_hull_skin(spawned_wheels, hull_size)

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
		# OUTBOARD extent, not |x|. absf() counted a part reaching INBOARD -
		# toward the vehicle's centreline - as if it stuck out sideways, and
		# build_wheel_mount()'s whole job is to reach inboard into the hull. On
		# screw_drive that inboard driveshaft measured further from the module
		# origin than the drum did, so the clamp fired on it and shrank the
		# entire assembly UNIFORMLY - which is why the drum kept coming out
		# short of the hull's ends and tucked up high (Chris, three times)
		# despite the layout handing the builder the hull's full length. The
		# side sign comes from which side of the hull the station sits on.
		var mount_reach := 0.0
		var local_extent := 0.0
		for w in spawned_wheels:
			var wb := _visual_bounds(w)
			if wb.size.length_squared() <= 0.0:
				continue
			var out_sign: float = signf(w.position.x)
			if out_sign == 0.0:
				out_sign = 1.0
			mount_reach = maxf(mount_reach, absf(w.position.x))
			local_extent = maxf(local_extent, out_sign * wb.position.x * w.scale.x)
			local_extent = maxf(local_extent, out_sign * (wb.position.x + wb.size.x) * w.scale.x)
		local_extent = maxf(local_extent, 0.0)
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
		if lowest < INF:
			# Floored at the hull's own half-height for the reason spelled out
			# in blueprint_manager.gd's matching block: locomotion that does not
			# reach past the hull's underside would otherwise sink the hull
			# itself through the ground plane. Kept identical to that copy so a
			# design sits at the same height in the lab and in a match.
			#
			# Measured from hull_size - the hull's OWN collision box, the same
			# source every station position above is derived from - and NOT from
			# default_lift. default_lift comes off the CATALOG entry for
			# hull.get_meta("type_id"), which falls back to medium_hull when
			# there is no such meta: that made the floor 0.9 for a hull actually
			# 0.6 tall, and moved the layout golden fixture's small/tracked_
			# treads row from 0.4886 to 0.9 - a hull hoisted a third of a metre
			# into the air on a floor that had no business binding at all.
			hull.position.y = maxf(-lowest, hull_size.y / 2.0)
				
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
# Moved to visual_builder.gd's measure_visual_bounds() so the battle spawner can
# measure ride height with the identical code - see that function's header. Kept
# as a thin alias because this file calls it from four places.
static func _visual_bounds(module: Node3D) -> AABB:
	return VisualBuilderScript.measure_visual_bounds(module)

# Re-fits a module's click collider to whatever geometry it currently has.
#
# Needed because a module can BECOME (or stop being) a sponson by being dragged
# between facets, and the collider is otherwise only ever sized once at initial
# placement. A weapon dragged onto a wall keeps its catalog-sized box, which is
# then buried in the hull and unclickable; one dragged back off keeps an
# oversized box measured around a blister it no longer has.
static func _refit_module_collider(module: Node3D) -> void:
	if module == null or not is_instance_valid(module):
		return
	# Found BY TYPE, not by name. The click body is added unnamed, so Godot
	# names it after its class - but only while that name is free; on a
	# collision it silently becomes "@StaticBody3D@N" instead, the same trap
	# VisualBuilder._hardware() documents. A get_node_or_null("StaticBody3D")
	# here would then no-op without a word and the collider would never re-fit.
	var bodies: Array = module.find_children("*", "StaticBody3D", false, false)
	if bodies.is_empty():
		return
	var body := bodies[0] as StaticBody3D
	var shapes: Array = body.find_children("*", "CollisionShape3D", false, false)
	if shapes.is_empty():
		return
	var shape := shapes[0] as CollisionShape3D
	if not (shape.shape is BoxShape3D):
		return
	var bounds := _visual_bounds(module)
	if bounds.size.length_squared() <= 0.0:
		return
	var fit_size = bounds.size
	var min_dim = 0.35
	fit_size.x = maxf(fit_size.x, min_dim)
	fit_size.y = maxf(fit_size.y, min_dim)
	fit_size.z = maxf(fit_size.z, min_dim)
	(shape.shape as BoxShape3D).size = fit_size
	body.position = bounds.get_center()

func _place_weapon(type_id: String, pos: Vector3, normal: Vector3, is_mirror: bool = false, tweaks: Dictionary = {}) -> Node3D:
	var catalog_data = ModuleCatalog.get_module_data(type_id)
	var category = catalog_data.get("category", "module")
	
	var new_weapon = Node3D.new()

	# Mount classification is hoisted ABOVE build_visual() deliberately. The
	# sponson blister is built inside build_visual() off the "sponson" meta
	# (it has to be - build_visual clears every non-StaticBody3D child on
	# entry, so anything attached afterwards is destroyed by the next rebuild),
	# which means the meta must already exist by the time it runs. The rest of
	# the mount metas are set here too rather than left at the bottom of this
	# function, so there is one place that decides them instead of two.
	#
	# Only the NORMAL is needed this early; the grid snap below moves the
	# position but cannot change which facet was hit.
	var hull_type_for_mount = hull.get_meta("type_id", "") if hull else ""
	var early_local_normal = normal
	if hull:
		early_local_normal = hull.global_transform.basis.inverse() * normal
	var mount_style = ""
	var wall_mount = false
	var sponson = false
	if category == "weapon":
		mount_style = ModuleCatalog.get_mount_style(type_id, hull_type_for_mount)
		wall_mount = _is_wall_mount(category, mount_style, type_id, early_local_normal)
		sponson = wall_mount and ModuleCatalog.is_sponson_capable(type_id)
		new_weapon.set_meta("mount_style", mount_style)
		new_weapon.set_meta("mount_normal", normal)
		new_weapon.set_meta("facet", ModuleCatalog.classify_facet(early_local_normal))
		new_weapon.set_meta("sponson", sponson)

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
	#
	# WEAPONS need it for the same reason, and this is a PRE-EXISTING bug that
	# has nothing to do with sponsons - Chris hit it on ordinary top-deck
	# pintle mounts too ("difficult to select in the normal pintle mount as
	# well"). Two compounding causes:
	#
	#  1. Every monolithic authored mesh is yawed 90 degrees about Y at
	#     visual_builder.gd:441 (the TripoSG orientation offset), which swings
	#     the barrel from Z onto X. The catalog `size` it is NOT rotated with -
	#     heavy_machine_gun is (0.3, 0.3, 1.0), so the click box is a thin
	#     sliver lying ACROSS the gun rather than along it.
	#  2. The mesh is then uniformly fit-scaled to the largest catalog axis, so
	#     the other two axes rarely match the box either.
	#
	# Measuring solves both at once, because measure_visual_bounds() walks the
	# child transforms and so accounts for that yaw and that scale. Same
	# argument as the locomotion case above, which is where this was first
	# found and fixed for one category only.
	#
	# Armor and structural are deliberately excluded: armor is auto-scaled to
	# its facet right after this and structural colliders are separately kept
	# in step with struct_scale (see blueprint_manager and gizmo_3d), so both
	# have their own sizing story that this must not fight.
	if category != "armor":
		var visual_aabb := _visual_bounds(new_weapon)
		if visual_aabb.size.length_squared() > 0.0:
			col_size = visual_aabb.size
			col_center = visual_aabb.get_center()
	var min_dim = 0.35
	col_size.x = maxf(col_size.x, min_dim)
	col_size.y = maxf(col_size.y, min_dim)
	col_size.z = maxf(col_size.z, min_dim)
	static_body.position = col_center
	var collision_shape = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = col_size
	collision_shape.shape = col_box
	static_body.add_child(collision_shape)
	new_weapon.add_child(static_body)
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
	data.base_power_output = catalog_data.get("power_output", 0.0)
	data.base_vision_bonus = catalog_data.get("vision_bonus", 0.0)
	data.tweaks = tweaks.duplicate()
	new_weapon.set_meta("module_data", data)
	
	hull.add_child(new_weapon)

	# Snap to 0.25m grid relative to hull local space
	var local_pos = Vector3.ZERO
	var local_normal = early_local_normal
	if hull:
		local_pos = hull.to_local(pos)

		var snap_interval = 0.25
		if abs(local_normal.x) < 0.9:
			local_pos.x = round(local_pos.x / snap_interval) * snap_interval
		if abs(local_normal.y) < 0.9:
			local_pos.y = round(local_pos.y / snap_interval) * snap_interval
		if abs(local_normal.z) < 0.9:
			local_pos.z = round(local_pos.z / snap_interval) * snap_interval

	# Weapon meshes are authored with their own mounting post/base baked in
	# (bottom of the mesh sits at local Y=0 - see build_visual()'s
	# monolithic-mesh placement above). For a flush mount, rotating local-up to
	# the surface normal puts that baked-in post against whatever facet it
	# landed on - flat deck, sloped glacis, or underside alike - replacing the
	# old column-extrusion + procedurally-drawn hardware model (abandoned; see
	# MOUNTING_AND_ARMOR_SPEC.md addendum, 2026-07-21).
	#
	# For a sponson the module is instead pushed INBOARD along the outboard
	# axis so its post and body end up inside the hull and only the barrel
	# protrudes - which is why position and basis are decided together by
	# _mount_transform() rather than separately. See _is_sponson_mount().
	#
	# Every category goes through this, not just weapons: a radar mast, armor
	# plate or fuel tank dropped on the underside has the same "base against
	# the hull, body projecting outward" requirement a gun does (non-weapons
	# never sponson, so they always take the flush branch). See _align_up_to()
	# for the antiparallel bug this fixes.
	# build_visual() ran above and, for a sponson, measured the real geometry
	# to pick an embed that still leaves barrel showing. Use that exact number
	# so the weapon and its housing agree on where the hull skin is.
	var mount_xf := _mount_transform(local_pos, local_normal, type_id, wall_mount, sponson,
		new_weapon.get_meta("sponson_embed", -1.0))
	if hull:
		new_weapon.position = mount_xf.origin
	else:
		new_weapon.global_position = pos
	new_weapon.transform.basis = mount_xf.basis

	# Auto-scale armor to fit facet
	if category == "armor":
		if hull:
			var facet_meas = _measure_hull_facet(hull, new_weapon.position, local_normal, new_weapon.transform.basis)
			var target_x = 1.0
			var target_z = 1.0
			var armor_pos = new_weapon.position

			if facet_meas["valid"]:
				target_x = facet_meas["size"].x
				target_z = facet_meas["size"].z
				armor_pos = facet_meas["center"]
			else:
				var hull_size = Vector3(4.0, 1.0, 6.0)
				var hull_shape = hull.get_node_or_null("CollisionShape3D")
				if hull_shape and hull_shape.shape is BoxShape3D:
					hull_size = hull_shape.shape.size

				var local_x = new_weapon.transform.basis.x.abs()
				var local_z = new_weapon.transform.basis.z.abs()

				if local_x.x > 0.5: target_x = hull_size.x
				elif local_x.y > 0.5: target_x = hull_size.y
				elif local_x.z > 0.5: target_x = hull_size.z

				if local_z.x > 0.5: target_z = hull_size.x
				elif local_z.y > 0.5: target_z = hull_size.y
				elif local_z.z > 0.5: target_z = hull_size.z

				var armor_facet = ModuleCatalog.classify_facet(local_normal)
				match armor_facet:
					"left", "right":
						var x_off = sign(local_normal.x) * hull_size.x / 2.0 if hull_shape else armor_pos.x
						armor_pos = Vector3(x_off, 0, 0)
					"front", "back":
						var z_off = sign(local_normal.z) * hull_size.z / 2.0 if hull_shape else armor_pos.z
						armor_pos = Vector3(0, 0, z_off)
					_:
						var y_off = sign(local_normal.y) * hull_size.y / 2.0 if hull_shape else armor_pos.y
						armor_pos = Vector3(0, y_off, 0)

			var cat_size = catalog_data.get("size", Vector3.ONE)
			if type_id == "energy_barrier_projector":
				new_weapon.scale = Vector3.ONE
				new_weapon.position = armor_pos
			else:
				new_weapon.scale.x = target_x / cat_size.x
				new_weapon.scale.z = target_z / cat_size.z
				new_weapon.position = armor_pos

			var mod_data = new_weapon.get_meta("module_data", null) as ModuleData
			if mod_data:
				mod_data.scale_multiplier = Vector3(new_weapon.scale.x, 1.0, new_weapon.scale.z)

			new_weapon.set_meta("facet", ModuleCatalog.classify_facet(local_normal))
			if type_id == "energy_barrier_projector":
				VisualBuilder.build_visual(type_id, new_weapon, catalog_data.size, catalog_data.color, tweaks)

	# The weapon mount metas (mount_style, mount_normal, facet, sponson) are
	# set at the TOP of this function, not here: build_visual() needs the
	# sponson flag before it runs, and having one place decide them is what
	# keeps the four placement paths from drifting apart again.

	# Notify the UI that a module was added
	if get_tree():
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

	# UNPAINTED, DELIBERATELY. The Lab used to render the hull in a faction's
	# full livery via apply_hull_materials(), plus that faction's greeble tint
	# and its insignia decals. All three are gone from this screen.
	#
	# Faction is chosen at match setup, and reconstruct_vehicle()'s
	# match_faction_override has always had the last word at spawn - so the
	# livery shown here was a preview of a paint job the match would overwrite,
	# picked from a dropdown whose only other effect (passives on the stat rail)
	# was also wrong for nine factions out of ten. Showing a design in one
	# faction's colours while it is being built implies a commitment the design
	# does not actually carry.
	#
	# What replaces it is the finish the main menu turntable and the Blueprint
	# Library previews already use - flat grey-green injection-moulded plastic,
	# the kit before it is painted. That is the honest read for a screen whose
	# whole subject is the SHAPE you are building, and it is the same call, so
	# the Lab and the previews cannot drift apart.
	#
	# apply_greebles() is still CALLED with NO_FACTION rather than skipped, and
	# the distinction matters: its first act is to delete any existing
	# HullGreebles container, so calling it is what CLEARS the scrap, nets and
	# pennants off a hull that was built under a faction before this change.
	# Skipping the call would have left them attached forever. Under an unknown
	# id its match statement falls to `_: pass`, so what it rebuilds is an empty
	# container - faction greebles are identity, not silhouette, and there is no
	# neutral version of a jury-rigged scrap antenna.
	#
	# The repaint pass below still walks that container, because
	# apply_scale_model_finish() skips a node named "HullGreebles" by design
	# (the right call on a battle mesh, where flattening the greebling costs the
	# silhouette its read). It is a no-op today and stops being one the moment
	# any faction-independent greeble is added.
	var body_size: Vector3 = catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk
	HullGreeblesScript.apply_greebles(hull, LiveryScript.NO_LIVERY, body_size)
	ArmorGreeblesScript.apply(hull, "", body_size)

	var kit_mat := HullMaterialBuilderScript.build_scale_model_material()
	HullMaterialBuilderScript.apply_scale_model_finish(mesh_inst, kit_mat)
	var greebles := hull.get_node_or_null("HullGreebles")
	if greebles:
		for child in greebles.get_children():
			HullMaterialBuilderScript.apply_scale_model_finish(child, kit_mat)

	# No HullDecals call at all. Decals are faction insignia - there is no
	# neutral version of a unit marking, so the answer is not to draw one. Any
	# decal node left over from a hull that was built before this change is
	# removed rather than hidden, so a rebuild cannot resurrect it.
	var stale_decals := hull.get_node_or_null("HullDecals")
	if stale_decals:
		stale_decals.queue_free()

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
# How far outside the hull's own bounding radius the envelope is drawn.
const ARC_HULL_CLEARANCE := 3.2
const ARC_RADIUS_MIN := 6.0

# --- TRAVERSE ENVELOPE MODEL ------------------------------------------------
#
# Deliberately isolated in one place, because Chris intends to make traverse
# genuinely meaningful later - traverse SPEED as a real cost, and hard vertical
# limits on most weapons. Everything the visualiser knows about "can this
# weapon point here, and how far out of its way is it" goes through
# _traverse_intensity(); adding per-weapon yaw/pitch caps or a speed-weighted
# falloff means editing that one function and the constants below, not the mesh
# builder.
#
# Elevation limits are now per-weapon and live in
# ModuleCatalog.ELEVATION_LIMITS, read through get_elevation_up/down() - the
# same accessors auto_weapon.gd gates real acquisition on, so the envelope drawn
# here and the set of targets the weapon will actually accept cannot drift
# apart.
#
# This replaces a single hardcoded pair (88 degrees up AND down, for every
# weapon in the roster) that was left here as an explicit placeholder for
# exactly this work - "a gun that cannot shoot straight up is the common case
# and this is where that will be expressed". Chris, 2026-08-03: "we need to
# differentiate the elevation available to each different weapon."

# How dim the envelope gets at the far edge of the weapon's traverse. The point
# is to make "this is where the gun already points" instantly separable from
# "this is reachable, but the turret has to swing all the way round for it" -
# which becomes a real cost once traverse speed matters.
const ARC_FALLOFF_MIN := 0.14

func _build_firing_arc(module: Node3D, data) -> Node3D:
	var container = Node3D.new()
	container.name = "ArcCone"

	var arc_facet = module.get_meta("facet", "")
	if arc_facet == "" and module.has_meta("mount_normal") and hull:
		var local_mount_normal = hull.global_transform.basis.inverse() * module.get_meta("mount_normal")
		arc_facet = ModuleCatalog.classify_facet(local_mount_normal)
	var arc_hull_type = hull.get_meta("type_id", "") if hull else ""
	# Same "sponson" meta auto_weapon._ready() reads, so the drawn envelope and
	# the arc combat actually enforces come from one source.
	var limit = ModuleCatalog.get_traverse_limit_angle(data.type_id, arc_facet, arc_hull_type,
		module.get_meta("sponson", false))
	# Read from the instance's own tweaks, not the bare type - the `elevation`
	# tweak raises the ceiling, and the envelope has to show the weapon the
	# player actually built rather than the catalog default.
	var arc_tweaks: Dictionary = data.tweaks if "tweaks" in data else {}
	var pitch_up: float = ModuleCatalog.get_elevation_up(data.type_id, arc_tweaks)
	# Same permissive depression floor combat applies - see
	# auto_weapon.gd's MIN_DEPRESSION_TOLERANCE for why depression is not
	# enforced strictly. Drawing the strict authored value here while combat
	# honours the floor would show the player an envelope narrower than the
	# weapon they actually have.
	var pitch_down: float = maxf(
		ModuleCatalog.get_elevation_down(data.type_id, arc_tweaks),
		AutoWeaponScript.MIN_DEPRESSION_TOLERANCE)

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

	# Two representations per state, and both matter:
	#   *_fill  translucent triangles, so the covered VOLUME reads at a glance
	#   *_grid  line segments along every cell boundary, so the player can
	#           actually judge WHERE the boundary falls
	#
	# The fill alone (which is all this used to draw) is a soft translucent blob
	# whose edge is impossible to locate - fine for "roughly forward", useless
	# for "can this actually cover the left flank". The grid is what makes it a
	# readable instrument, and it is why the mesh is built as a projected
	# lat/long lattice rather than a smooth shell.
	var radius = _arc_radius_for(module)
	# Per-vertex colour carries the traverse falloff, so one draw call covers
	# the whole gradient. Requires vertex_color_use_as_albedo on the material.
	var fill_v = []
	var fill_c = []
	var grid_v = []
	var grid_c = []

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
			var u_mid = (u0 + u1) * 0.5
			var phi_mid = (phi0 + phi1) * 0.5

			# ONLY DRAW WHERE THE WEAPON CAN ACTUALLY TARGET (Chris, 2026-08-02).
			#
			# Two separate reasons a direction can be unavailable, and both now
			# result in nothing being drawn rather than in a red cell:
			#   * MECHANICAL - outside the mount's traverse envelope.
			#   * OBSTRUCTED - the vehicle's own hull or another module is in
			#     the way.
			# Drawing obstructed cells in red made the envelope a full sphere
			# with a red patch, which reads as "the gun covers everything" at a
			# glance - the opposite of the truth. An envelope that simply is not
			# there where the gun cannot shoot needs no reading at all.
			var intensity = _traverse_intensity(u_mid, phi_mid, limit, pitch_up, pitch_down)
			if intensity <= 0.0:
				continue

			var mid = _sphere_point(phi_mid, u_mid, 1.0)
			var world_dir = (module.global_transform.basis * mid).normalized()

			var query = PhysicsRayQueryParameters3D.create(origin, origin + world_dir * radius)
			query.collision_mask = 3 # Layer 1 (Hull) + Layer 2 (Modules)
			query.exclude = exclude_list
			if not space_state.intersect_ray(query).is_empty():
				continue

			var a = _sphere_point(phi0, u0, radius)
			var b = _sphere_point(phi0, u1, radius)
			var c = _sphere_point(phi1, u1, radius)
			var d = _sphere_point(phi1, u0, radius)

			# Low, because the material is CULL_DISABLED: every fragment is
			# painted twice, once by the near face and once by the far one, so
			# the on-screen alpha is roughly double this. At 0.10 the envelope
			# went milky and swallowed the model inside it.
			var fill_col = Color(UITokens.SIGNAL_HAZARD, 0.045 * intensity)
			for v in [a, b, c, a, c, d]:
				fill_v.append(v)
				fill_c.append(fill_col)

			# All four edges per cell. Shared edges get drawn twice, which is
			# cheaper than de-duplicating them and visually identical.
			var grid_col = Color(UITokens.SIGNAL_HAZARD, 0.90 * intensity)
			for pair in [[a, b], [b, c], [c, d], [d, a]]:
				grid_v.append(pair[0])
				grid_c.append(grid_col)
				grid_v.append(pair[1])
				grid_c.append(grid_col)

	if not fill_v.is_empty():
		container.add_child(_arc_surface("ArcFill", fill_v,
			UITokens.SIGNAL_HAZARD * 0.5, fill_c))
	if not grid_v.is_empty():
		container.add_child(_arc_surface("ArcGrid", grid_v,
			UITokens.SIGNAL_HAZARD, grid_c, Mesh.PRIMITIVE_LINES))

	return container


# Envelope radius for a module: outside the hull by a clear margin, so the grid
# reads as a field of fire AROUND the vehicle rather than as a bubble stuck to
# the turret. Sized from the hull rather than fixed, so it stays correct across
# a 70kg roadster and an 800kg heavy.
func _arc_radius_for(_module: Node3D) -> float:
	var hull_radius := 0.0
	if hull and hull.has_meta("type_id"):
		var hsize: Vector3 = ModuleCatalog.get_module_data(
			hull.get_meta("type_id")).get("size", Vector3.ONE)
		hull_radius = hsize.length() * 0.5
	return maxf(ARC_RADIUS_MIN, hull_radius + ARC_HULL_CLEARANCE)


# How strongly the envelope draws in a given direction, in the module's own
# frame. Returns 0 for "cannot point here at all", otherwise 0..1 where 1 is
# the weapon's default heading.
#
# THIS IS THE EXTENSION POINT for the traverse work Chris has planned. Today it
# models a yaw limit, fixed pitch stops, and a falloff with angular distance
# from the default heading. When traverse becomes a real per-weapon stat, this
# is where per-weapon yaw/pitch caps and a speed-weighted cost go; nothing in
# the mesh builder needs to change, because it already just asks for a number.
#
# `azimuth` is measured the same way _sphere_point() measures it (0 = the
# barrel's forward, -Z). `phi` is polar from +Y.
func _traverse_intensity(azimuth: float, phi: float, yaw_limit: float,
						 pitch_up: float = PI * 0.5, pitch_down: float = PI * 0.5) -> float:
	# Yaw: how far the turret must swing from its default heading.
	var yaw = absf(wrapf(azimuth, -PI, PI))
	if yaw > yaw_limit + 0.001:
		return 0.0

	# Pitch: elevation above / depression below the weapon's own horizon.
	# Per-weapon now (see the ARC_PITCH comment block above). The defaults are
	# a full hemisphere so any caller that does not pass limits gets the old
	# unrestricted behaviour rather than a silently clipped envelope.
	var pitch = PI * 0.5 - phi
	if pitch > pitch_up + 0.001 or -pitch > pitch_down + 0.001:
		return 0.0

	# Falloff with total angular distance off the default heading. Normalised
	# against the actual yaw limit so a 60-degree mount fades across its own
	# 60 degrees rather than across a notional 180.
	var span = maxf(yaw_limit, 0.001)
	var t = clampf(yaw / span, 0.0, 1.0)
	# Squared, so the bright region genuinely reads as "where it already
	# points" instead of as a slow linear wash across the whole envelope.
	return lerpf(1.0, ARC_FALLOFF_MIN, t * t)

# Point on a sphere in the module's local frame. phi is measured from +Y so
# phi=0 is straight up and phi=PI straight down; azimuth 0 faces -Z, matching
# the barrel-forward convention used everywhere else.
static func _sphere_point(phi: float, azimuth: float, radius: float) -> Vector3:
	var sin_phi = sin(phi)
	return Vector3(sin_phi * sin(azimuth), cos(phi), -sin_phi * cos(azimuth)) * radius

# `colors` is a per-vertex array parallel to `vertices`, carrying the traverse
# falloff. Passing it per-vertex rather than baking several meshes at different
# alphas keeps the whole gradient in one draw call and lets the falloff be
# continuous instead of banded.
func _arc_surface(surface_name: String, vertices: Array, emission: Color,
		colors: Array = [], primitive: int = Mesh.PRIMITIVE_TRIANGLES) -> MeshInstance3D:
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(primitive)
	for i in vertices.size():
		if i < colors.size():
			mesh.surface_set_color(colors[i])
		mesh.surface_add_vertex(vertices[i])
	mesh.surface_end()

	var mi = MeshInstance3D.new()
	mi.name = surface_name
	mi.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	# White albedo so the per-vertex colours come through unmultiplied - the
	# falloff lives entirely in vertex alpha.
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
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
	var reach = _arc_radius_for(module)
	var world_dir = -module.global_transform.basis.z.normalized()
	var query = PhysicsRayQueryParameters3D.create(origin, origin + world_dir * reach)
	query.collision_mask = 3
	query.exclude = exclude_list
	var blocked = not space_state.intersect_ray(query).is_empty()

	# Two crossed triangles, so the spike reads from any camera angle. Stays
	# PRIMITIVE_TRIANGLES - it is a solid marker, not a lattice like the
	# envelope, and drawing these six verts as lines would give three
	# disconnected segments.
	var half = 0.08
	var tip = Vector3(0, 0, -reach)
	var verts = [
		Vector3(-half, 0, 0), Vector3(half, 0, 0), tip,
		Vector3(0, -half, 0), Vector3(0, half, 0), tip,
	]
	# A frame-built gun with its ONE line of fire obstructed is worth saying
	# out loud, so this is the only place alert-red survives in the arc
	# visualiser - there is no envelope here to simply omit.
	var col = UITokens.SIGNAL_ALERT if blocked else UITokens.SIGNAL_HAZARD
	var cols = []
	for i in verts.size():
		cols.append(Color(col, 0.85))
	return _arc_surface("BlockedArc" if blocked else "ClearArc", verts, col, cols)

# Whether the firing envelope is drawn. Toggled from the radial menu's Arc
# wedge. Persisted across selections because it is a VIEW preference - a player
# comparing coverage across several turrets should not have to re-enable it on
# every part they click.
var show_firing_arc: bool = true


func toggle_firing_arc() -> void:
	show_firing_arc = not show_firing_arc
	if not show_firing_arc:
		if is_instance_valid(selected_module):
			var existing = selected_module.get_node_or_null("ArcCone")
			if existing:
				selected_module.remove_child(existing)
				existing.free()
	else:
		_refresh_firing_arc()


func _refresh_firing_arc():
	if not show_firing_arc: return
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

static func _measure_hull_facet(hull: Node3D, local_pos: Vector3, local_normal: Vector3, module_basis: Basis) -> Dictionary:
	var result = {
		"size": Vector3.ZERO,
		"center": local_pos,
		"valid": false
	}
	if not hull or not is_instance_valid(hull):
		return result

	var mesh_inst = hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_inst:
		mesh_inst = hull.get_node_or_null("PhysicsMesh") as MeshInstance3D
	if not mesh_inst or not mesh_inst.mesh:
		return result

	var xform = mesh_inst.transform

	var faces: PackedVector3Array = mesh_inst.mesh.get_faces()
	if faces.is_empty() or faces.size() % 3 != 0:
		return result

	var norm = local_normal.normalized()
	var bx = module_basis.x.normalized()
	var bz = module_basis.z.normalized()

	var num_tris = faces.size() / 3
	var matching_tris = []
	var tri_centers = []
	var tri_verts_hull = []

	for i in range(num_tris):
		var v0 = xform * faces[i * 3 + 0]
		var v1 = xform * faces[i * 3 + 1]
		var v2 = xform * faces[i * 3 + 2]
		var tri_n = (v1 - v0).cross(v2 - v0)
		if tri_n.length_squared() < 1e-8:
			continue
		tri_n = tri_n.normalized()

		if abs(tri_n.dot(norm)) > 0.90:
			var center = (v0 + v1 + v2) / 3.0
			var plane_dist = abs((center - local_pos).dot(norm))
			if plane_dist < 0.20:
				matching_tris.append(i)
				tri_centers.append(center)
				tri_verts_hull.append([v0, v1, v2])

	if matching_tris.is_empty():
		return result

	# Find closest matching triangle to clicked local_pos
	var start_idx = 0
	var best_d = 1e9
	for i in range(matching_tris.size()):
		var d = (tri_centers[i] - local_pos).length_squared()
		if d < best_d:
			best_d = d
			start_idx = i

	# Flood-fill connected coplanar triangles from start_idx
	var visited = {}
	var queue = [start_idx]
	visited[start_idx] = true
	var facet_verts = []

	while not queue.is_empty():
		var curr = queue.pop_back()
		var tv = tri_verts_hull[curr]
		facet_verts.append(tv[0])
		facet_verts.append(tv[1])
		facet_verts.append(tv[2])

		for n in range(matching_tris.size()):
			if visited.has(n):
				continue
			var nv = tri_verts_hull[n]
			var shares = false
			for v_a in tv:
				for v_b in nv:
					if (v_a - v_b).length_squared() < 0.005:
						shares = true
						break
				if shares:
					break
			if shares:
				visited[n] = true
				queue.append(n)

	if facet_verts.is_empty():
		return result

	var min_x = 1e9
	var max_x = -1e9
	var min_z = 1e9
	var max_z = -1e9

	for v in facet_verts:
		var rel = v - local_pos
		var px = rel.dot(bx)
		var pz = rel.dot(bz)
		min_x = min(min_x, px)
		max_x = max(max_x, px)
		min_z = min(min_z, pz)
		max_z = max(max_z, pz)

	var size_x = max_x - min_x
	var size_z = max_z - min_z
	if size_x > 0.1 and size_z > 0.1:
		var mid_x = (min_x + max_x) * 0.5
		var mid_z = (min_z + max_z) * 0.5
		result["size"] = Vector3(size_x, 0, size_z)
		result["center"] = local_pos + bx * mid_x + bz * mid_z
		result["valid"] = true

	return result

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

# --- Wall and sponson mounting ---------------------------------------------
# TWO decisions, deliberately separate, because conflating them got artillery
# boxed into a housing it cannot shoot out of.
#
#   _is_wall_mount()    - should this module be LEVELLED, muzzle outboard?
#   _is_sponson_mount() - should it additionally be EMBEDDED IN A HOUSING with
#                         a narrowed arc?
#
# The first is a geometry fix and applies to every weapon. _align_up_to() puts
# local +Y on the surface normal, which is right for a deck, a slope or a
# belly but incoherent on a near-VERTICAL face, where "up" is horizontal.
# Measured directly, that put a front-facet weapon's muzzle straight into the
# ground, a rear-facet one straight at the sky, and rolled the side-facet ones
# 90 degrees so their elevation cone opened sideways
# (auto_weapon._within_elevation reads basis.y as "up").
#
# The second is a capability question, and for a mortar the answer is no - a
# housing and a 60-degree arc deny exactly the open sky a lobbing weapon needs.
# See ModuleCatalog.is_sponson_capable(). So an artillery piece on a wall is
# levelled and aimed outboard on an open mount, keeping its full elevation and
# full traverse; a machine gun in the same spot gets the blister.
#
# Deliberately narrow:
#   * non-weapons never wall-mount. An armor plate MUST stay flush to the
#     facet it auto-fits, and a fuel tank in a gun housing is nonsense.
#   * absf(), so the BELLY stays a flush inverted pintle. That is spec'd
#     behaviour (spec #3 "bottom"), not an accident of the old code.
#
# EVERY mount style wall-mounts, including "turret" and "frame_built". A first
# pass admitted only "pintle", reading MOUNTING_AND_ARMOR_SPEC.md:25's "the
# existing tank-cannon (enclosed turret) is already handled correctly - leave
# it as-is" as covering all facets. It does not: that line is about the TOP
# DECK, where a turret genuinely was already right. On a vertical face
# basic_cannon was broken in exactly the same way as everything else - its
# muzzle went into the ground on the front facet - and excluding it just left
# the reported bug in place. A tank cannon buried in a hull side firing through
# a housing is a casemate, which is a real thing and the correct read here.
#
# frame_built is admitted for the same reason: a railgun in the front glacis
# should aim out of it, not at the dirt. Its traverse stays zero regardless,
# because get_traverse_limit_angle() tests frame_built BEFORE the sponson flag.
# `_mount_style` is kept in the signature (and unused) because every caller
# already has it to hand and a future rule may well need it again - the four
# call sites should not have to change shape for that.
static func _is_wall_mount(category: String, _mount_style: String,
						   type_id: String, local_normal: Vector3) -> bool:
	if category != "weapon":
		return false
	if local_normal.length_squared() < 0.5:
		return false
	var n := local_normal.normalized()
	if Vector3(n.x, 0.0, n.z).length_squared() < 0.000001:
		return false
	return absf(n.y) < ModuleCatalog.get_sponson_up_alignment(type_id)

static func _is_sponson_mount(category: String, mount_style: String,
							  type_id: String, local_normal: Vector3) -> bool:
	return _is_wall_mount(category, mount_style, type_id, local_normal) \
		and ModuleCatalog.is_sponson_capable(type_id)

# Why a placement is refused, or "" to allow it.
#
# A DELIBERATE EXCEPTION to the no-hard-blocking rule
# (MOUNTING_AND_ARMOR_SPEC.md:58, "traits compose and drive simulation
# behavior - whatever that produces, including janky/suboptimal outcomes -
# never validation logic that prevents 'weird' combinations"). Chris called
# this one explicitly on 2026-08-04: an artillery piece or mortar on a vertical
# hull face is not an interestingly-janky outcome, it is a nonsense one, and
# there is no orientation that makes a lobbing weapon work off a wall. An
# earlier pass tried levelling them on an open mount instead of blocking; the
# call was that they should simply not go there.
#
# Kept as narrow as possible so it does not become a precedent: it refuses
# exactly one combination - a weapon whose catalog says it cannot be sponsoned,
# on a face steep enough to require one. Everything else, including every
# genuinely weird trait combination the spec is protecting, still goes through.
func _placement_refusal_reason(type_id: String, category: String, normal: Vector3) -> String:
	if category != "weapon" or hull == null:
		return ""
	if ModuleCatalog.is_sponson_capable(type_id):
		return ""
	var local_normal = hull.global_transform.basis.inverse() * normal
	var hull_type_for_mount = hull.get_meta("type_id", "")
	var mount_style = ModuleCatalog.get_mount_style(type_id, hull_type_for_mount)
	if not _is_wall_mount(category, mount_style, type_id, local_normal):
		return ""
	var display_name = ModuleCatalog.get_module_data(type_id).get("name", type_id)
	return "%s can't mount on a vertical face - it needs to fire upward." % display_name

# Orientation AND position for one placed module, in hull-local space.
#
# The single place this is decided. All four placement paths call it -
# _place_weapon(), _update_module_placement(), that function's mirror block,
# and _reclassify_module_after_drag() - because four hand-synchronised copies
# of the rule is exactly how two facets ended up broken without anyone
# noticing.
#
# `local_pos` must be the RAW snapped surface point, never an already-offset
# one: the embed offset is applied HERE, and the mirror path derives its
# position by negating X on the raw point, so passing a pre-offset position
# would double the offset on one side only.
#
# `wall` levels the module and aims it outboard. `housed` additionally sinks it
# inboard so its body sits inside the hull behind a blister. A wall mount that
# is NOT housed stays at the clicked surface point: with no housing to cover
# an aperture, embedding it would just look like the gun melting into the hull.
#
# `embed_override` is the depth VisualBuilder actually used when it built the
# housing, measured off the real geometry (see sponson_geometry_for). Passing
# it through rather than re-deriving is what keeps the weapon and its housing
# on the same hole - a stubby barrel gets a shallower embed than the catalog
# default so the muzzle still clears the hull, and the module has to move by
# that same reduced amount. Negative means "no measurement available, use the
# catalog default".
static func _mount_transform(local_pos: Vector3, local_normal: Vector3,
							 type_id: String, wall: bool, housed: bool,
							 embed_override: float = -1.0) -> Transform3D:
	if not wall:
		return Transform3D(_align_up_to(local_normal), local_pos)
	# Outboard is the surface normal with its vertical component dropped: on a
	# truly vertical wall that IS the normal, and on one raked a few degrees it
	# is the horizontal heading the housing is welded to face.
	var outboard := Vector3(local_normal.x, 0.0, local_normal.z)
	if outboard.length_squared() < 0.000001:
		# No horizontal component at all means a deck or a belly, not a wall.
		# Unreachable through _is_wall_mount()'s own guard; kept so this
		# function is total for any caller.
		return Transform3D(_align_up_to(local_normal), local_pos)
	outboard = outboard.normalized()
	# -Z is the muzzle axis everywhere in this project and +Y is hull-up, so
	# the gun sits level, traverses about hull-up and elevates about its own X.
	# This is the same Basis.looking_at idiom auto_weapon._looking_at_safe()
	# uses to build its TRACKING basis - which is why resting and tracking now
	# agree, instead of the weapon visibly snapping upright on acquisition.
	var depth := 0.0
	if housed:
		depth = embed_override if embed_override >= 0.0 \
			else ModuleCatalog.get_sponson_embed_depth(type_id)
	return Transform3D(Basis.looking_at(outboard, Vector3.UP),
					   local_pos - outboard * depth)

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
			# Armor is a skin, not an obstruction. Armor modules do not affect
			# clipping of other modules or other armor modules.
			if my_data.category == "armor" or other_data_early.category == "armor":
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
		lbl.text = "CENTRE OF GRAVITY"
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
	var wall_mount = false
	var sponson = false
	if category == "weapon":
		mount_style = ModuleCatalog.get_mount_style(data.type_id, hull_type_for_mount)
		wall_mount = _is_wall_mount(category, mount_style, data.type_id, local_normal)
		sponson = wall_mount and ModuleCatalog.is_sponson_capable(data.type_id)
		module.set_meta("mount_style", mount_style)
		module.set_meta("mount_normal", normal)
		# Weapons get a facet now too, not just armor. auto_weapon.gd reads
		# this and has always received "" - it is what lets combat and the
		# Design Lab arc agree on a sponson's narrowed traverse.
		module.set_meta("facet", ModuleCatalog.classify_facet(local_normal))
		# Must be set BEFORE rebuild_visual() below, which is what builds the
		# blister off this meta.
		module.set_meta("sponson", sponson)

	# Non-weapons used to get an extra `normal * size.y / 2` push-off here,
	# which _place_weapon() never applies. Module meshes are built with their
	# base at local Y=0 (build_visual() offsets the mesh up by half its height
	# so the BOTTOM lands on the origin), so the origin belongs exactly on the
	# surface - that extra half-height left every non-weapon module hovering
	# off the hull the moment it was dragged, at a different height than where
	# it was originally dropped.
	#
	# Position and basis both come from _mount_transform() now: a sponson
	# weapon is pushed INBOARD of the clicked point, so the two cannot be
	# decided separately. Assigning .origin and .basis rather than the whole
	# Transform3D, because the whole-transform form would drop node scale that
	# the armor fit re-applies afterwards.
	var mount_xf := _mount_transform(local_pos, local_normal, data.type_id, wall_mount, sponson,
		module.get_meta("sponson_embed", -1.0))
	module.position = mount_xf.origin
	module.transform.basis = mount_xf.basis

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
			var mirrored_normal = Vector3(-normal.x, normal.y, normal.z)
			var local_mirrored_normal = hull.global_transform.basis.inverse() * mirrored_normal
			# Classified independently rather than copying the primary's flag:
			# mirroring is X-only, so outboard.x negates while outboard.z
			# survives, and a right-side sponson becomes a genuine left-side
			# one aiming outboard-left. Note this branch takes the RAW mirrored
			# surface point - _mount_transform() applies the embed offset, and
			# passing the primary's already-offset position would put the twin
			# at the wrong depth.
			var mirror_wall = _is_wall_mount(category, mount_style, data.type_id,
				local_mirrored_normal)
			var mirror_sponson = mirror_wall and ModuleCatalog.is_sponson_capable(data.type_id)
			if category == "weapon":
				mirror.set_meta("mount_style", mount_style)
				mirror.set_meta("mount_normal", mirrored_normal)
				mirror.set_meta("facet", ModuleCatalog.classify_facet(local_mirrored_normal))
				mirror.set_meta("sponson", mirror_sponson)

			var mirror_xf := _mount_transform(mirrored_local_pos, local_mirrored_normal,
				data.type_id, mirror_wall, mirror_sponson,
				mirror.get_meta("sponson_embed", -1.0))
			mirror.position = mirror_xf.origin
			mirror.transform.basis = mirror_xf.basis

			mirror.rotate_object_local(Vector3.UP, -yaw_offset)
			if category == "weapon":
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
		var facet_meas = _measure_hull_facet(hull, module.position, local_normal, module.transform.basis)
		var target_x = 1.0
		var target_z = 1.0
		var armor_pos = module.position

		if facet_meas["valid"]:
			target_x = facet_meas["size"].x
			target_z = facet_meas["size"].z
			armor_pos = facet_meas["center"]
		else:
			var hull_x = module.transform.basis.x.abs()
			var hull_z = module.transform.basis.z.abs()
			if hull_x.x > 0.5: target_x = hull_size.x
			elif hull_x.y > 0.5: target_x = hull_size.y
			elif hull_x.z > 0.5: target_x = hull_size.z

			if hull_z.x > 0.5: target_z = hull_size.x
			elif hull_z.y > 0.5: target_z = hull_size.y
			elif hull_z.z > 0.5: target_z = hull_size.z

			var armor_facet_fb = ModuleCatalog.classify_facet(local_normal)
			match armor_facet_fb:
				"left", "right":
					var x_off = sign(local_normal.x) * hull_size.x / 2.0 if hull_shape else armor_pos.x
					armor_pos = Vector3(x_off, 0, 0)
				"front", "back":
					var z_off = sign(local_normal.z) * hull_size.z / 2.0 if hull_shape else armor_pos.z
					armor_pos = Vector3(0, 0, z_off)
				_:
					var y_off = sign(local_normal.y) * hull_size.y / 2.0 if hull_shape else armor_pos.y
					armor_pos = Vector3(0, y_off, 0)

		module.scale.x = target_x / catalog_data.get("size", Vector3.ONE).x
		module.scale.z = target_z / catalog_data.get("size", Vector3.ONE).z
		module.position = armor_pos

		var mod_data = module.get_meta("module_data", null) as ModuleData
		if mod_data:
			mod_data.scale_multiplier = Vector3(module.scale.x, 1.0, module.scale.z)

		module.set_meta("facet", ModuleCatalog.classify_facet(local_normal))

	elif category == "weapon":
		var hull_type_for_mount = hull.get_meta("type_id", "") if hull else ""
		var mount_style = ModuleCatalog.get_mount_style(data.type_id, hull_type_for_mount)
		module.set_meta("mount_style", mount_style)
		module.set_meta("mount_normal", normal)
		module.set_meta("facet", ModuleCatalog.classify_facet(local_normal))
		# Recomputed, and set BEFORE rebuild_visual() below - a weapon dragged
		# from the deck onto a wall has to grow a blister here, and one dragged
		# the other way has to lose it. rebuild_visual() reads this meta.
		module.set_meta("sponson",
			_is_sponson_mount(category, mount_style, data.type_id, local_normal))
		# Position/rotation are already mounted to the new facet by the last
		# _update_module_placement() call during the drag - this just finalizes
		# the classification and rebuilds the visual for the new facet's mesh
		# (e.g. tweak deformations, and the blister).
		var VisualBuilder = preload("res://scripts/visual_builder.gd")
		VisualBuilder.rebuild_visual(module)
		# AFTER the rebuild, so the collider is fitted to the geometry the
		# module actually has now - with a blister if it just landed on a wall,
		# without one if it just left. Otherwise a weapon dragged onto a facet
		# becomes unclickable, which is the same bug initial placement has.
		_refit_module_collider(module)
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

# --- First-Time Instructions Modal & Persistent Help ---
var instructions_canvas_layer: CanvasLayer = null

func _setup_instructions_ui() -> void:
	var ui_layer = CanvasLayer.new()
	ui_layer.name = "InstructionsUILayer"
	ui_layer.layer = 90
	add_child(ui_layer)

	var btn = Button.new()
	btn.name = "InstructionsButton"
	btn.text = "Instructions"
	btn.position = Vector2(16, 16)
	btn.custom_minimum_size = Vector2(120, 32)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = UITokens.BASE_700
	style_normal.border_width_left = 1
	style_normal.border_width_top = 1
	style_normal.border_width_right = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = UITokens.BASE_500
	style_normal.set_corner_radius_all(4)

	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = UITokens.BASE_600
	style_hover.border_width_left = 1
	style_hover.border_width_top = 1
	style_hover.border_width_right = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = UITokens.SIGNAL_HAZARD
	style_hover.set_corner_radius_all(4)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_color_override("font_color", UITokens.TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.pressed.connect(func(): show_instructions_dialog(true))
	ui_layer.add_child(btn)

# On a first visit the player is now OFFERED THE TUTORIAL rather than shown the
# manual. The manual is not gone - _setup_instructions_ui() still builds its
# button, and it works better as a reference you reach for than as a wall of text
# that greets you before you have seen the thing it describes.
#
# TutorialManager owns the "have they been offered this" flag, so there is one
# first-run gate rather than two that can disagree. It no-ops when a run is
# already active, which is the case when the player arrived here by pressing
# TUTORIAL on the main menu.
func _check_first_time_instructions() -> void:
	_setup_instructions_ui()
	var tutorial = get_node_or_null("/root/TutorialManager")
	if tutorial == null:
		return
	tutorial.offer_first_run()

func show_instructions_dialog(is_manual_reopen: bool = false) -> void:
	if is_instance_valid(instructions_canvas_layer):
		instructions_canvas_layer.queue_free()

	instructions_canvas_layer = CanvasLayer.new()
	instructions_canvas_layer.name = "InstructionsModalLayer"
	instructions_canvas_layer.layer = 100
	add_child(instructions_canvas_layer)

	var scrim = ColorRect.new()
	scrim.name = "Scrim"
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.04, 0.04, 0.04, 0.78)
	instructions_canvas_layer.add_child(scrim)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 520)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = UITokens.BASE_800
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = UITokens.SIGNAL_HAZARD
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 28
	panel_style.content_margin_top = 24
	panel_style.content_margin_right = 28
	panel_style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "DESIGN LAB MANUAL & CONTROLS"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", UITokens.SIGNAL_HAZARD)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "Quick-start reference for constructing, customizing, and testing vehicles."
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", UITokens.TEXT_SECONDARY)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub_lbl)

	var div = ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = UITokens.BASE_500
	vbox.add_child(div)

	var grid = HBoxContainer.new()
	grid.add_theme_constant_override("separation", 24)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	var col1 = VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col1.add_theme_constant_override("separation", 12)
	grid.add_child(col1)

	_add_section_header(col1, "🎥 CAMERA & NAVIGATION")
	_add_bullet_item(col1, "Right Mouse (RMB)", "Hold & drag to orbit camera around vehicle")
	_add_bullet_item(col1, "Middle Mouse / Shift+RMB", "Hold & drag to pan camera view")
	_add_bullet_item(col1, "Scroll Wheel", "Zoom in & out on your vehicle")
	_add_bullet_item(col1, "Focus Key (F)", "Focus camera on selected part or hull")

	_add_section_header(col1, "🧱 BUILDING & ATTACHING")
	_add_bullet_item(col1, "Drag & Drop Parts", "Drag components from left menu onto hull facets")
	_add_bullet_item(col1, "Facet Auto-Snapping", "Modules & armor automatically align to hull faces")
	_add_bullet_item(col1, "Mirror Mode (M)", "Toggle symmetry to mirror parts on opposite side")

	var col2 = VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2.add_theme_constant_override("separation", 12)
	grid.add_child(col2)

	_add_section_header(col2, "🔄 MANIPULATION & EDITING")
	_add_bullet_item(col2, "Select Part", "Click any attached module to highlight & edit")
	_add_bullet_item(col2, "Rotate Part", "Drag 3D gizmo rings or press R / E / Q")
	_add_bullet_item(col2, "Remove Part", "Press Delete / Backspace or click Delete Part")

	_add_section_header(col2, "⚡ STATS & FIELD TESTING")
	_add_bullet_item(col2, "Live Vehicle Stats", "Monitor DPS, Armor, HP, Mass & Speed on right panel")
	_add_bullet_item(col2, "Test Range / Combat", "Click Test Range to test-drive & fight in combat")

	var div2 = ColorRect.new()
	div2.custom_minimum_size = Vector2(0, 1)
	div2.color = UITokens.BASE_500
	vbox.add_child(div2)

	var btn_center = CenterContainer.new()
	vbox.add_child(btn_center)

	var close_btn = Button.new()
	close_btn.text = "GOT IT! START BUILDING"
	close_btn.custom_minimum_size = Vector2(260, 44)

	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = UITokens.SIGNAL_GO
	btn_style.set_corner_radius_all(6)

	var btn_hover = StyleBoxFlat.new()
	btn_hover.bg_color = UITokens.SIGNAL_GO.lightened(0.15)
	btn_hover.set_corner_radius_all(6)

	close_btn.add_theme_stylebox_override("normal", btn_style)
	close_btn.add_theme_stylebox_override("hover", btn_hover)
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.add_theme_color_override("font_color", Color.WHITE)

	close_btn.pressed.connect(func():
		var f = FileAccess.open("user://lab_instructions_seen.cfg", FileAccess.WRITE)
		if f:
			f.store_line("seen=true")
			f.close()
		instructions_canvas_layer.queue_free()
		instructions_canvas_layer = null
	)
	btn_center.add_child(close_btn)

func _add_section_header(parent: Control, title: String) -> void:
	var lbl = Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", UITokens.SIGNAL_HAZARD)
	parent.add_child(lbl)

func _add_bullet_item(parent: Control, key_name: String, desc: String) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	var k_lbl = Label.new()
	k_lbl.text = "• " + key_name + ":"
	k_lbl.add_theme_font_size_override("font_size", 12)
	k_lbl.add_theme_color_override("font_color", UITokens.TEXT_PRIMARY)
	hbox.add_child(k_lbl)

	var d_lbl = Label.new()
	d_lbl.text = desc
	d_lbl.add_theme_font_size_override("font_size", 12)
	d_lbl.add_theme_color_override("font_color", UITokens.TEXT_SECONDARY)
	d_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(d_lbl)

	parent.add_child(hbox)
