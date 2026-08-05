extends SceneTree

func _init():
	print("Generating default roster...")
	var BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
	var ModulePlacerScript = preload("res://scripts/module_placer.gd")
	var ModuleCatalog = preload("res://scripts/module_catalog.gd")
	
	var bm = BlueprintManagerScript.new()
	var placer = ModulePlacerScript.new()
	
	var units = [
		{
			"id": "bp_default_scout",
			"name": "M41 Jackrabbit Scout Buggy",
			"hull": "scout_hull",
			"loc_type": "wheels",
			"loc_settings": {"num_axles": 2, "wheel_size": 1.0, "wheels_per_axle": 2},
			"weapons": [
				{"type": "machine_gun", "pos": Vector3(0, 0, 0)}
			]
		},
		{
			"id": "bp_default_light_tank",
			"name": "M22 Poodle Light Tank",
			"hull": "light_hull",
			"loc_type": "tracked_treads",
			"loc_settings": {"tread_width": 1.0},
			"weapons": [
				{"type": "basic_cannon", "pos": Vector3(0, 0, 0)}
			]
		},
		{
			"id": "bp_default_medium_tank",
			"name": "M4 Sherman-Rex Medium Tank",
			"hull": "medium_hull",
			"loc_type": "tracked_treads",
			"loc_settings": {"tread_width": 1.2},
			"weapons": [
				{"type": "heavy_cannon", "pos": Vector3(0, 0, -0.5)}
			]
		},
		{
			"id": "bp_default_main_battle_tank",
			"name": "M100 Thunder-Toad MBT",
			"hull": "heavy_hull",
			"loc_type": "tracked_treads",
			"loc_settings": {"tread_width": 1.5},
			"weapons": [
				{"type": "heavy_cannon", "pos": Vector3(0, 0, -1.0)},
				{"type": "machine_gun", "pos": Vector3(0, 0, 1.0)}
			]
		},
		{
			"id": "bp_default_heavy_brawler",
			"name": "M33 Rhino-Puncher",
			"hull": "assault_hull",
			"loc_type": "tracked_treads",
			"loc_settings": {"tread_width": 1.8},
			"weapons": [
				{"type": "rotary_cannon", "pos": Vector3(0, 0, -0.5)}
			]
		},
		{
			"id": "bp_default_anti_air",
			"name": "ZSU-44 Sky-Swatter",
			"hull": "medium_hull",
			"loc_type": "wheels",
			"loc_settings": {"num_axles": 4, "wheel_size": 1.2, "wheels_per_axle": 2},
			"weapons": [
				{"type": "anti_air_missile", "pos": Vector3(0, 0, 0.5)}
			]
		},
		{
			"id": "bp_default_artillery",
			"name": "M88 Boom-Lobber",
			"hull": "medium_hull",
			"loc_type": "tracked_treads",
			"loc_settings": {"tread_width": 1.2},
			"weapons": [
				{"type": "artillery_cannon", "pos": Vector3(0, 0, -1.0)}
			]
		},
		{
			"id": "bp_default_siege",
			"name": "M120 Crater-Maker",
			"hull": "heavy_hull",
			"loc_type": "tracked_treads",
			"loc_settings": {"tread_width": 1.5},
			"weapons": [
				{"type": "heavy_cannon", "pos": Vector3(-1.0, 0, -1.0)},
				{"type": "heavy_cannon", "pos": Vector3(1.0, 0, -1.0)}
			]
		},
		{
			"id": "bp_default_attack_chopper",
			"name": "AH-66 Whirly-Dirge",
			"hull": "medium_hull",
			"loc_type": "helicopter_rotors",
			"loc_settings": {"size": 1.5, "count": 4},
			"weapons": [
				{"type": "rocket_artillery", "pos": Vector3(0, 0, 0)},
				{"type": "rotary_cannon", "pos": Vector3(0, -1.5, 2.0)} 
			]
		},
		{
			"id": "bp_default_drone_carrier",
			"name": "CV-99 Hive-Mind",
			"hull": "assault_hull",
			"loc_type": "hover_engine",
			"loc_settings": {},
			"weapons": [
				{"type": "radar_dish", "pos": Vector3(0, 0, 0)}
			]
		},
		{
			"id": "bp_default_ew_radar",
			"name": "M195 Batfrog EW",
			"hull": "scout_hull",
			"loc_type": "wheels",
			"loc_settings": {"num_axles": 2, "wheel_size": 1.1, "wheels_per_axle": 2},
			"weapons": [
				{"type": "radar_dish", "pos": Vector3(0, 0, -0.5)}
			]
		},
		{
			"id": "bp_default_heavy_bomber",
			"name": "B-52 Carpet-Bagger",
			"hull": "assault_hull",
			"loc_type": "fixed_wing_engine",
			"loc_settings": {"size": 2.0, "count": 4},
			"weapons": [
				{"type": "rocket_artillery", "pos": Vector3(-1.5, 0, 0)},
				{"type": "rocket_artillery", "pos": Vector3(1.5, 0, 0)}
			]
		}
	]
	
	for unit in units:
		print("Building ", unit["id"], "...")
		
		# We need a dummy root to attach things to
		var my_root = Node3D.new()
		root.add_child(my_root)
		
		# Reset placer
		placer.clear_hull()
		
		# Force place hull manually to bypass UI-specific things
		var hull_data = ModuleCatalog.get_module_data(unit["hull"])
		
		var hull = StaticBody3D.new()
		hull.name = "Hull"
		hull.set_meta("base_hull_size", hull_data.get("size", Vector3.ONE))
		hull.set_meta("hull_scale", Vector3(1, 1, 1))
		hull.set_meta("type_id", unit["hull"])
		hull.set_meta("blueprint_id", unit["id"])
		hull.set_meta("blueprint_name", unit["name"])
		hull.set_meta("faction", "industrialists")
		hull.set_meta("armor_material", "hardened_steel")
		hull.set_meta("armor_thickness", 1.0)
		
		var col = CollisionShape3D.new()
		var col_box = BoxShape3D.new()
		col_box.size = hull_data.get("size", Vector3.ONE)
		col.shape = col_box
		hull.add_child(col)
		
		my_root.add_child(hull)
		placer.hull = hull
		
		# Place locomotion
		placer.update_locomotion(unit["loc_type"], unit["loc_settings"])
		
		# Place weapons on top face
		for w in unit["weapons"]:
			var y_pos = col_box.size.y / 2.0
			# Just snap to top face (normal = UP)
			var w_node = placer._place_weapon(w["type"], hull.global_position + Vector3(w["pos"].x, y_pos, w["pos"].z), Vector3.UP)
			if w_node:
				w_node.position.y = y_pos
				# Special case for rotary cannon on the chopper's underside
				if unit["id"] == "bp_default_attack_chopper" and w["type"] == "rotary_cannon":
					w_node.position = Vector3(0, -y_pos, w["pos"].z)
					w_node.set_meta("facet", "bottom")
					w_node.set_meta("mount_normal", Vector3.DOWN)
					# Adjust yaw so it faces forward
					w_node.set_meta("yaw_offset", PI)
					w_node.rotation.y = PI
			
		var data = bm.serialize_hull(hull)
		
		var f = FileAccess.open("res://assets/blueprints/default_roster/" + unit["id"] + ".json", FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(data, "\t"))
			f.close()
			print("Saved to ", unit["id"])
		else:
			print("Failed to save ", unit["id"])
			
		my_root.queue_free()
			
	quit()
