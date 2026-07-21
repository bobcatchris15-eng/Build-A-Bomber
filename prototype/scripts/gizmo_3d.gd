extends Node3D

const StatCalculatorScript = preload("res://scripts/stat_calculator.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")

var target_module: Node3D
var start_scale: Vector3
var child_start_positions: Dictionary = {}
var start_tweaks: Dictionary = {}

const HANDLE_COLORS := {
	"HandleX": Color(0.95, 0.26, 0.30),
	"HandleY": Color(0.42, 0.85, 0.32),
	"HandleZ": Color(0.30, 0.55, 0.95),
	"HandleRotate": Color(0.95, 0.80, 0.25),
}

# The handle meshes ship with no material at all in Gizmo3D.tscn, so they used
# to render flat white - and module_placer.gd's clipping pass then walked into
# the gizmo and overwrote them with the module's own colour (or red). With that
# pass no longer touching the gizmo, give the handles the conventional
# red/green/blue per-axis colours so it reads as a manipulator rather than as
# part of the model. Unshaded and drawn on top so it stays legible against a
# dark hull or from inside a large module.
func _paint_handles():
	for handle_name in HANDLE_COLORS:
		var handle = get_node_or_null(handle_name)
		if not handle:
			continue
		var mesh_inst = handle.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if not mesh_inst:
			continue
		var mat = StandardMaterial3D.new()
		mat.albedo_color = HANDLE_COLORS[handle_name]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 1
		mesh_inst.material_override = mat

func _ready():
	target_module = get_parent()
	_paint_handles()

	# Connect to the 3 linear handles (X/Y/Z scale/tweak drag)
	for child in get_children():
		if child.name == "HandleRotate":
			continue # wired separately below - no .axis, different signal shape
		if child.has_signal("drag_started"):
			child.drag_started.connect(_on_drag_started)
			child.dragged.connect(_on_dragged.bind(child.axis))
			child.drag_ended.connect(_on_drag_ended)

	# Free-form rotation ring (Spore/KSP style, MOUNTING_AND_ARMOR_SPEC.md #3)
	var ring = get_node_or_null("HandleRotate")
	if ring:
		ring.drag_started.connect(_on_drag_started)
		ring.rotated.connect(_on_rotated)
		ring.drag_ended.connect(_on_drag_ended)

func _on_rotated(delta_angle: float):
	# Free-form yaw rotation from the ring handle - continuous, not snapped
	# to 90 degrees like the old Rotate button/R-key (still available as a
	# quick-align convenience, this doesn't replace it).
	if not target_module or target_module.name == "Hull": return

	target_module.rotate_object_local(Vector3.UP, delta_angle)
	var yaw = wrapf(target_module.get_meta("yaw_offset", 0.0) + delta_angle, 0.0, 2.0 * PI)
	target_module.set_meta("yaw_offset", yaw)

	if target_module.has_meta("mirrored_counterpart"):
		var mirror = target_module.get_meta("mirrored_counterpart")
		if mirror and is_instance_valid(mirror):
			mirror.rotate_object_local(Vector3.UP, -delta_angle)
			var mirror_yaw = wrapf(mirror.get_meta("yaw_offset", 0.0) - delta_angle, 0.0, 2.0 * PI)
			mirror.set_meta("yaw_offset", mirror_yaw)

	var root = get_node_or_null("/root/MainLab")
	if root and root.has_method("check_all_clipping"):
		root.check_all_clipping()

func _on_drag_started():
	var root = get_node_or_null("/root/MainLab")
	if root and root.has_method("push_undo_snapshot"):
		root.push_undo_snapshot()
	if target_module:
		if target_module.name == "Hull" and target_module.has_meta("hull_scale"):
			start_scale = target_module.get_meta("hull_scale")
			# Store initial positions of all child modules at the start of drag
			child_start_positions.clear()
			for child in target_module.get_children():
				if child.has_meta("module_data"):
					child_start_positions[child] = child.position
		else:
			start_scale = target_module.scale
			if target_module.has_meta("module_data"):
				var data = target_module.get_meta("module_data")
				start_tweaks = data.tweaks.duplicate()

func _on_dragged(offset_3d: Vector3, axis: Vector3):
	if not target_module: return
	
	# If this is a standard module with tweaks, map dragging to tweaks!
	if target_module.name != "Hull" and target_module.has_meta("module_data"):
		var data = target_module.get_meta("module_data")
		var type_id = data.type_id
		var tweak_name = get_tweak_for_axis(type_id, axis)
		if tweak_name != "":
			var specs = StatCalculatorScript.TWEAK_SPECS
			var spec = null
			if type_id in specs:
				for s in specs[type_id]:
					if s.name == tweak_name:
						spec = s
						break
			
			if spec:
				var start_val = start_tweaks.get(tweak_name, spec.default)
				var local_offset = offset_3d.dot(axis)
				# 1.0 world offset translates to 1.0 change in tweak value
				var change = local_offset * 1.5
				var new_val = start_val + change
				new_val = clamp(new_val, spec.min, spec.max)
				if spec.step > 0:
					new_val = round(new_val / spec.step) * spec.step
					
				data.tweaks[tweak_name] = new_val
				
				# Rebuild primary and mirror visuals
				VisualBuilder.rebuild_visual(target_module)
				if target_module.has_meta("mirrored_counterpart"):
					var mirror = target_module.get_meta("mirrored_counterpart")
					if mirror and is_instance_valid(mirror):
						var mirror_data = mirror.get_meta("module_data")
						if mirror_data:
							mirror_data.tweaks[tweak_name] = new_val
						VisualBuilder.rebuild_visual(mirror)
						
				# Update the UI
				get_tree().call_group("stat_ui", "on_module_selected", target_module)
				var root = get_node_or_null("/root/MainLab")
				var hull = root.get_node_or_null("Hull") if root else null
				if hull:
					get_tree().call_group("stat_ui", "update_stats", hull)
				if root and root.has_method("check_all_clipping"):
					root.check_all_clipping()
				return

	# Fallback: original scale behavior
	var local_offset = offset_3d.dot(axis)
	var scale_change = local_offset * 1.0
	var new_scale = start_scale
	if axis.x != 0: new_scale.x = max(0.1, start_scale.x + scale_change)
	elif axis.y != 0: new_scale.y = max(0.1, start_scale.y + scale_change)
	elif axis.z != 0: new_scale.z = max(0.1, start_scale.z + scale_change)
	
	_apply_scale_to_node(target_module, new_scale)
	
	# Mirror scaling propagation
	if target_module.has_meta("mirrored_counterpart"):
		var mirror = target_module.get_meta("mirrored_counterpart")
		if is_instance_valid(mirror):
			_apply_scale_to_node(mirror, new_scale)
			# Chirality is no longer carried by a negative scale on the
			# mirror's own node - module_placer.gd's _apply_mirror_flip()
			# reflects the module's VISUAL CHILDREN in module space instead,
			# which survives this scale write untouched and keeps the negative
			# factor out of both the collision shape and
			# module_data.scale_multiplier (which the stat maths reads).
			# Re-asserting scale.x = -abs(scale.x) here would now double up
			# with that child-level reflection and un-mirror the part.
		
	# Notify UI
	get_tree().call_group("stat_ui", "update_stats", get_node("/root/MainLab/Hull"))
	
	var main_lab = get_node_or_null("/root/MainLab")
	if main_lab and main_lab.has_method("check_all_clipping"):
		main_lab.check_all_clipping()

func _apply_scale_to_node(node: Node3D, new_scale: Vector3):
	if node.name == "Hull":
		# Bounded scaling (FABLE_REVIEW.md 1.3): the concept doc always
		# specced size-class bounds; the old code only clamped the low end,
		# and since hull scale now drives real HP/weight/cost this needs a
		# real ceiling too.
		new_scale = new_scale.clamp(
			Vector3.ONE * ModuleCatalogScript.HULL_SCALE_MIN,
			Vector3.ONE * ModuleCatalogScript.HULL_SCALE_MAX)
		# Scale Isolation: scale only the MeshInstance3D and CollisionShape3D directly.
		# This keeps the parent Hull node scale at (1, 1, 1), avoiding module deformation.
		node.set_meta("hull_scale", new_scale)
		var base_size = Vector3(4.0, 1.0, 6.0)
		if node.has_meta("base_hull_size"):
			base_size = node.get_meta("base_hull_size")

		var target_size = base_size * new_scale

		# Resize MeshInstance3D. Authored .glb hulls are ArrayMeshes - they
		# scale via mesh_inst.scale (same as update_hull_appearance() /
		# reconstruct_vehicle() do), not via BoxMesh.size; previously the
		# non-BoxMesh path was simply missing, so dragging a scale handle on
		# any authored hull moved the collision box and the stats but not
		# the visible mesh until some later full rebuild (FABLE_REVIEW.md 3.8).
		var armor_thick = node.get_meta("armor_thickness") if node.has_meta("armor_thickness") else 1.0
		var armor_bulk = Vector3(1.0 + (armor_thick - 1.0) * 0.15, 1.0 + (armor_thick - 1.0) * 0.15, 1.0)
		var hull_type = node.get_meta("type_id") if node.has_meta("type_id") else "medium_hull"
		var mesh_inst = node.get_node_or_null("MeshInstance3D")
		var phys_mesh = node.get_node_or_null("PhysicsMesh")
		if mesh_inst and mesh_inst.mesh is BoxMesh:
			if not mesh_inst.mesh.resource_local_to_scene:
				mesh_inst.mesh = mesh_inst.mesh.duplicate()
			mesh_inst.mesh.size = target_size
			if phys_mesh:
				phys_mesh.mesh = mesh_inst.mesh
		elif mesh_inst:
			# An authored .glb needs the orientation + per-axis fit that maps
			# it onto its catalog box folded in, exactly as
			# update_hull_appearance() does. Assigning the raw hull_scale here
			# dropped that factor entirely, so the hull's visible size jumped
			# the instant a scale handle was grabbed and then tracked a
			# different curve than the collider for the rest of the drag.
			var fit = ModuleCatalogScript.get_hull_mesh_fit(hull_type, mesh_inst.mesh, new_scale * armor_bulk)
			mesh_inst.rotation = fit["rotation"]
			mesh_inst.scale = fit["scale"]
			mesh_inst.position = fit["position"]
			# The physics copy is never drawn but other code reads its
			# transform, so it must not drift away from the visual one.
			if phys_mesh:
				phys_mesh.rotation = fit["rotation"]
				phys_mesh.scale = fit["scale"]
				phys_mesh.position = fit["position"]

		# Resize CollisionShape3D. Stays axis-aligned in hull-local space -
		# see module_placer.gd's _place_hull_from_ui() for why it must not
		# inherit the mesh's orientation correction.
		var col_shape = node.get_node_or_null("CollisionShape3D")
		if col_shape and col_shape.shape is BoxShape3D:
			if not col_shape.shape.resource_local_to_scene:
				col_shape.shape = col_shape.shape.duplicate()
			col_shape.shape.size = target_size
			
		# Shift child modules based on the scaling factor
		var scale_factor = Vector3(
			new_scale.x / start_scale.x if start_scale.x != 0.0 else 1.0,
			new_scale.y / start_scale.y if start_scale.y != 0.0 else 1.0,
			new_scale.z / start_scale.z if start_scale.z != 0.0 else 1.0
		)
		
		for child in child_start_positions.keys():
			if is_instance_valid(child):
				var start_pos = child_start_positions[child]
				child.position = start_pos * scale_factor
	else:
		# Standard module scaling
		node.scale = new_scale
		if node.has_meta("module_data"):
			var data = node.get_meta("module_data")
			data.scale_multiplier = new_scale

func _on_drag_ended():
	var main_lab = get_node_or_null("/root/MainLab")
	if main_lab and main_lab.has_method("check_all_clipping"):
		main_lab.check_all_clipping()

func get_tweak_for_axis(type_id: String, axis: Vector3) -> String:
	var abs_axis = axis.abs()
	if abs_axis.x > 0.9:
		match type_id:
			"basic_cannon", "heavy_machine_gun", "rotary_cannon":
				return "caliber"
			"gauss_railgun":
				return "rail_length"
			"heavy_howitzer":
				return "elevation"
			"spigot_mortar":
				return "rod_thickness"
			"guided_missile":
				return "seeker_size"
			"dual_stage_missile":
				return "payload_size"
			"flamethrower":
				return "nozzle_width"
			"heavy_laser":
				return "lens_aperture"
			"plasma_lobber":
				return "containment"
			"ciws":
				return "radar_dish"
			"pd_laser":
				return "cooling_jacket"
			"flak_cannon":
				return "fuse_setting"
			"resource_harvester":
				return "extractor_size"
			"sensor_suite":
				return "mast_height"
			"logistics_tank":
				return "tank_capacity"
			"mortar_array":
				return "tube_count"
			"cluster_dispenser":
				return "dispersion"
			"missile_pod":
				return "grid_size"
	elif abs_axis.z > 0.9:
		match type_id:
			"basic_cannon":
				return "barrel_length"
			"guided_missile":
				return "engine_length"
			"dual_stage_missile":
				return "ascent_thruster"
			"flamethrower":
				return "pressure_valve"
			"resource_harvester":
				return "extractor_size"
	return ""
