extends Node

func save_blueprint() -> bool:
	var root = get_node("/root/MainLab")
	if root and root.get("clipping_detected") == true:
		var ui = get_tree().get_first_node_in_group("stat_ui")
		if ui and ui.has_node("ScrollContainer/VBoxContainer/Title"):
			ui.get_node("ScrollContainer/VBoxContainer/Title").text = "SAVE FAILED: Clipping!"
			get_tree().create_timer(2.5).timeout.connect(func():
				if is_instance_valid(ui) and ui.has_node("ScrollContainer/VBoxContainer/Title"):
					ui.get_node("ScrollContainer/VBoxContainer/Title").text = "Blueprint Stats"
			)
		return false
		
	var hull = root.get_node_or_null("Hull")
	if not hull:
		print("No hull found to save.")
		return false
		
	var hull_size = Vector3(4.0, 1.0, 6.0)
	if hull.has_meta("base_hull_size") and hull.has_meta("hull_scale"):
		hull_size = hull.get_meta("base_hull_size") * hull.get_meta("hull_scale")

	var locomotion_type = hull.get_meta("locomotion_type") if hull.has_meta("locomotion_type") else ""
	var locomotion_settings = hull.get_meta("locomotion_settings") if hull.has_meta("locomotion_settings") else {}

	var blueprint = {
		"version": 1.0,
		"hull_type": hull.get_meta("type_id") if hull.has_meta("type_id") else "medium_hull",
		"hull_scale": {"x": hull.get_meta("hull_scale").x, "y": hull.get_meta("hull_scale").y, "z": hull.get_meta("hull_scale").z} if hull.has_meta("hull_scale") else {"x": 1.0, "y": 1.0, "z": 1.0},
		"hull_size": {"x": hull_size.x, "y": hull_size.y, "z": hull_size.z},
		"armor_material": hull.get_meta("armor_material") if hull.has_meta("armor_material") else "hardened_steel",
		"armor_thickness": hull.get_meta("armor_thickness") if hull.has_meta("armor_thickness") else 1.0,
		"faction": hull.get_meta("faction") if hull.has_meta("faction") else "industrialists",
		"locomotion": {
			"type_id": locomotion_type,
			"settings": locomotion_settings
		},
		"modules": []
	}
	
	for child in hull.get_children():
		if child is StaticBody3D: continue # Hull's own collider
		if child is MeshInstance3D: continue # Hull's own mesh
		
		# Assume this is a module Node3D
		if child.has_meta("module_data"):
			var data = child.get_meta("module_data")
			var mod_dict = {
				"type_id": data.type_id if "type_id" in data else "",
				"name": data.module_name,
				"position": {"x": child.position.x, "y": child.position.y, "z": child.position.z},
				"rotation": {"x": child.rotation.x, "y": child.rotation.y, "z": child.rotation.z},
				"scale": {"x": child.scale.x, "y": child.scale.y, "z": child.scale.z},
				"yaw_offset": child.get_meta("yaw_offset", 0.0),
				"tweaks": data.tweaks if "tweaks" in data else {},
				"stats": {
					"hp": data.get_hp(),
					"weight": data.get_weight(),
					"cost_metal": data.get_cost().x,
					"cost_crystal": data.get_cost().y,
					"dps": data.get_dps()
				}
			}
			blueprint["modules"].append(mod_dict)
			
	var bp_id = ""
	if hull.has_meta("blueprint_id"):
		bp_id = hull.get_meta("blueprint_id")
	if bp_id == "":
		bp_id = _generate_blueprint_id()
	var bp_name = "Untitled Design"
	if hull.has_meta("blueprint_name") and hull.get_meta("blueprint_name") != "":
		bp_name = hull.get_meta("blueprint_name")

	blueprint["id"] = bp_id
	blueprint["name"] = bp_name
	blueprint["modified_unix"] = Time.get_unix_time_from_system()

	hull.set_meta("blueprint_id", bp_id)
	hull.set_meta("blueprint_name", bp_name)

	var json_string = JSON.stringify(blueprint, "\t")

	DirAccess.make_dir_recursive_absolute("user://blueprints")
	var file = FileAccess.open("user://blueprints/%s.json" % bp_id, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Blueprint '%s' saved (id=%s)" % [bp_name, bp_id])

	# Legacy single-slot pointer, kept in sync so the existing single-unit
	# weapon test range (Battlefield.tscn / "Test in Arena") keeps working unchanged.
	var legacy_file = FileAccess.open("user://blueprint.json", FileAccess.WRITE)
	if legacy_file:
		legacy_file.store_string(json_string)
		legacy_file.close()

	var ui = get_tree().get_first_node_in_group("stat_ui")
	if ui and ui.has_node("ScrollContainer/VBoxContainer/Title"):
		ui.get_node("ScrollContainer/VBoxContainer/Title").text = "Saved '%s'!" % bp_name
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(ui) and ui.has_node("ScrollContainer/VBoxContainer/Title"):
				ui.get_node("ScrollContainer/VBoxContainer/Title").text = "Blueprint Stats"
		)
	return true

func _generate_blueprint_id() -> String:
	return "bp_%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]

func list_blueprints() -> Array:
	var results = []
	DirAccess.make_dir_recursive_absolute("user://blueprints")
	var dir = DirAccess.open("user://blueprints")
	if not dir:
		return results
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data = load_blueprint("user://blueprints/" + file_name)
			if not data.is_empty():
				results.append({
					"id": data.get("id", file_name.get_basename()),
					"name": data.get("name", "Untitled Design"),
					"hull_type": data.get("hull_type", "medium_hull"),
					"faction": data.get("faction", "industrialists"),
					"modified_unix": data.get("modified_unix", 0),
					"path": "user://blueprints/" + file_name
				})
		file_name = dir.get_next()
	dir.list_dir_end()
	results.sort_custom(func(a, b): return a["modified_unix"] > b["modified_unix"])
	return results

func delete_blueprint(id: String) -> void:
	var path = "user://blueprints/%s.json" % id
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("Deleted blueprint: ", id)

func duplicate_blueprint(id: String) -> String:
	var path = "user://blueprints/%s.json" % id
	var data = load_blueprint(path)
	if data.is_empty():
		return ""
	var new_id = _generate_blueprint_id()
	data["id"] = new_id
	data["name"] = str(data.get("name", "Untitled Design")) + " (Copy)"
	data["modified_unix"] = Time.get_unix_time_from_system()
	var json_string = JSON.stringify(data, "\t")
	var file = FileAccess.open("user://blueprints/%s.json" % new_id, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	return new_id

func load_blueprint_into_designer(id: String) -> bool:
	var path = "user://blueprints/%s.json" % id
	var data = load_blueprint(path)
	if data.is_empty():
		print("Could not load blueprint for designer: ", id)
		return false

	var root = get_node("/root/MainLab")
	if not root:
		return false

	if root.has_method("clear_hull"):
		root.clear_hull()

	var new_hull = reconstruct_vehicle(data, root, true)
	root.hull = new_hull

	get_tree().call_group("stat_ui", "update_stats", new_hull)
	get_tree().call_group("stat_ui", "sync_hull_ui", new_hull)
	return true

func load_blueprint(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		print("Blueprint file not found: ", file_path)
		return {}
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
		
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error == OK:
		var data = json.get_data()
		if typeof(data) == TYPE_DICTIONARY:
			return data
	else:
		print("JSON Parse Error: ", json.get_error_message(), " in ", json_string, " at line ", json.get_error_line())
	return {}

func reconstruct_vehicle(blueprint_data: Dictionary, parent_node: Node3D, is_designer: bool = false) -> Node3D:
	if blueprint_data.is_empty():
		return null
		
	var ModuleCatalog = preload("res://scripts/module_catalog.gd")
	var ModuleData = preload("res://scripts/module_data.gd")
	
	var hull_type = blueprint_data.get("hull_type", "medium_hull")
	var catalog_data = ModuleCatalog.get_module_data(hull_type)
	
	var hull
	if is_designer:
		hull = StaticBody3D.new()
		hull.collision_layer = 1
		hull.collision_mask = 0
	else:
		hull = Node3D.new()
	hull.name = "Hull"
	
	# Set metadata
	hull.set_meta("base_hull_size", catalog_data.size)
	var hull_scale_dict = blueprint_data.get("hull_scale", {"x": 1.0, "y": 1.0, "z": 1.0})
	var hull_scale = Vector3(hull_scale_dict.x, hull_scale_dict.y, hull_scale_dict.z)
	hull.set_meta("hull_scale", hull_scale)
	hull.set_meta("type_id", hull_type)
	
	var armor_thick = blueprint_data.get("armor_thickness", 1.0)
	var armor_mat_name = blueprint_data.get("armor_material", "hardened_steel")
	var faction_name = blueprint_data.get("faction", "industrialists")
	hull.set_meta("armor_thickness", armor_thick)
	hull.set_meta("armor_material", armor_mat_name)
	hull.set_meta("faction", faction_name)
	hull.set_meta("blueprint_id", blueprint_data.get("id", ""))
	hull.set_meta("blueprint_name", blueprint_data.get("name", "Untitled Design"))
	
	# Bulk size based on thickness
	var armor_bulk = Vector3(1.0 + (armor_thick - 1.0) * 0.15, 1.0 + (armor_thick - 1.0) * 0.15, 1.0)
	
	# Re-create Hull's MeshInstance3D
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var box = BoxMesh.new()
	box.size = catalog_data.size * hull_scale * armor_bulk
	mesh_inst.mesh = box
	
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
	hull.add_child(mesh_inst)
	
	# Re-create Hull's CollisionShape3D (only in designer)
	if is_designer:
		var col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var col_box = BoxShape3D.new()
		col_box.size = catalog_data.size * hull_scale * armor_bulk
		col.shape = col_box
		hull.add_child(col)
	
	parent_node.add_child(hull)
	
	# Raise hull height if wheels are present so they touch the ground (Y=0)
	var wheels_offset = 0.0
	var locomotion = blueprint_data.get("locomotion", {})
	var loc_type = locomotion.get("type_id", "")
	var settings = locomotion.get("settings", {})
	if loc_type == "wheels":
		var wheel_size = settings.get("size", 1.0)
		wheels_offset = 0.8 * wheel_size
	elif loc_type == "legs":
		wheels_offset = 1.6 * settings.get("size", 1.0)
	elif loc_type == "anti_grav":
		wheels_offset = 0.4 * settings.get("size", 1.0)
		
	hull.position = Vector3(0, (catalog_data.size.y * hull_scale.y) / 2.0 + wheels_offset, 0)
	
	# Spawn modules
	var modules = blueprint_data.get("modules", [])
	for mod in modules:
		var type_id = mod.get("type_id", "")
		if type_id == "": continue
		
		var mod_catalog_data = ModuleCatalog.get_module_data(type_id)
		var category = mod_catalog_data.get("category", "module")
		
		var new_module = Node3D.new()
		
		var VisualBuilder = preload("res://scripts/visual_builder.gd")
		VisualBuilder.build_visual(type_id, new_module, mod_catalog_data.size, mod_catalog_data.color, mod.get("tweaks", {}))
		
		if is_designer:
			var static_body = StaticBody3D.new()
			static_body.collision_layer = 2 # Modules layer
			static_body.collision_mask = 0
			static_body.position = Vector3(0, mod_catalog_data.size.y / 2.0, 0)
			var collision_shape = CollisionShape3D.new()
			var col_box_mod = BoxShape3D.new()
			col_box_mod.size = mod_catalog_data.size
			collision_shape.shape = col_box_mod
			static_body.add_child(collision_shape)
			new_module.add_child(static_body)
		
		var m_data = ModuleData.new()
		m_data.type_id = type_id
		m_data.module_name = mod_catalog_data.name
		m_data.category = category
		m_data.base_hp = mod_catalog_data.hp
		m_data.base_weight = mod_catalog_data.weight
		m_data.cost_metal = mod_catalog_data.metal
		m_data.cost_crystal = mod_catalog_data.crystal
		m_data.base_dps = mod_catalog_data.dps
		if mod.has("tweaks"):
			m_data.tweaks = mod["tweaks"]
		
		# Set scale
		var sc_dict = mod.get("scale", {"x": 1.0, "y": 1.0, "z": 1.0})
		var mod_scale = Vector3(sc_dict.x, sc_dict.y, sc_dict.z)
		new_module.scale = mod_scale
		m_data.scale_multiplier = mod_scale
		new_module.set_meta("module_data", m_data)
		
		# Add module to hull
		hull.add_child(new_module)
		
		# Set local position and rotation
		var pos_dict = mod.get("position", {"x": 0.0, "y": 0.0, "z": 0.0})
		new_module.position = Vector3(pos_dict.x, pos_dict.y, pos_dict.z)
		
		var rot_dict = mod.get("rotation", {"x": 0.0, "y": 0.0, "z": 0.0})
		new_module.rotation = Vector3(rot_dict.x, rot_dict.y, rot_dict.z)
		
		new_module.set_meta("yaw_offset", mod.get("yaw_offset", 0.0))
		# Force mesh deformation rebuild
		VisualBuilder.rebuild_visual(new_module)
		
	return hull
