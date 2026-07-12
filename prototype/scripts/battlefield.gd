extends Node3D

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

@onready var vehicle_spawn_point = $VehicleSpawnPoint
@onready var camera = $Camera3D

var vehicle: CharacterBody3D
var vehicle_hull: Node3D
var target_dummies: Array[Node] = []
var target_destination: Vector3 = Vector3.ZERO
var is_moving: bool = false
var target_altitude: float = 0.0
var locomotion_type: String = "wheels"

# Movement parameters (derived from vehicle stats or defaults)
var move_speed: float = 5.0
var rotate_speed: float = 4.0

func _ready():
	_spawn_vehicle()
	_spawn_target_dummies()
	
	# Connect UI buttons
	var return_btn = get_node_or_null("UI/ReturnButton")
	if return_btn:
		return_btn.pressed.connect(_on_return_pressed)
		
	var reset_dummies_btn = get_node_or_null("UI/ResetDummiesButton")
	if reset_dummies_btn:
		reset_dummies_btn.pressed.connect(_on_reset_dummies_pressed)
		
	# Instantiate live tuning overlay
	var tuning_panel_script = load("res://scripts/debug_tuning_panel.gd")
	if tuning_panel_script:
		var tuning_panel = Control.new()
		tuning_panel.set_script(tuning_panel_script)
		tuning_panel.name = "DebugTuningPanel"
		add_child(tuning_panel)

func _spawn_vehicle():
	# Create CharacterBody3D container with player_vehicle script for physics movement
	vehicle = CharacterBody3D.new()
	vehicle.name = "PlayerVehicle"
	vehicle.collision_layer = 4 # Vehicle layer
	vehicle.collision_mask = 9 # Hits ground (1) and targets (8)
	vehicle.set_script(load("res://scripts/player_vehicle.gd"))
	vehicle._ready()
	add_child(vehicle)
	
	# Spawn ground vehicles slightly above the floor so they drop down safely without clipping
	var spawn_pos = vehicle_spawn_point.global_position
	if locomotion_type != "helicopter_rotors":
		spawn_pos.y += 1.0
	vehicle.global_position = spawn_pos
	
	# Instantiate a temporary BlueprintManager instance to access helpers
	var bp_manager = BlueprintManager.new()
	add_child(bp_manager)
	
	var blueprint_data = bp_manager.load_blueprint("user://blueprint.json")
	if blueprint_data.is_empty():
		blueprint_data = {
			"version": 1.0,
			"hull_type": "medium_hull",
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"modules": []
		}
		
	var locomotion = blueprint_data.get("locomotion", {})
	locomotion_type = locomotion.get("type_id", "wheels")
	var settings = locomotion.get("settings", {})
	
	if locomotion_type == "helicopter_rotors":
		target_altitude = 4.0
	else:
		target_altitude = 0.0
		
	vehicle_hull = bp_manager.reconstruct_vehicle(blueprint_data, vehicle)
	remove_child(bp_manager) # Clean up
	bp_manager.queue_free()
	
	if vehicle_hull:
		var hull_type = vehicle_hull.get_meta("type_id") if vehicle_hull.has_meta("type_id") else "medium_hull"
		var catalog_data = ModuleCatalog.get_module_data(hull_type)
		var base_hp = catalog_data.hp
		var thick = vehicle_hull.get_meta("armor_thickness") if vehicle_hull.has_meta("armor_thickness") else 1.0
		var mat = vehicle_hull.get_meta("armor_material") if vehicle_hull.has_meta("armor_material") else "hardened_steel"
		var mat_mult = 1.0
		if mat == "reactive_armor": mat_mult = 1.3
		elif mat == "ablative_ceramic": mat_mult = 1.6
		elif mat == "energy_shielding": mat_mult = 2.0
		
		var final_max_hp = base_hp * thick * mat_mult
		vehicle.max_hp = final_max_hp
		vehicle.hp = final_max_hp
		
		# Dynamic creation of Player HP Label in Battlefield UI
		var ui_node = get_node_or_null("UI")
		if ui_node:
			var hp_label = Label.new()
			hp_label.name = "PlayerHPLabel"
			hp_label.position = Vector2(20, 20)
			hp_label.add_theme_font_size_override("font_size", 24)
			ui_node.add_child(hp_label)
			update_player_hp_ui()
			
		_setup_weapons()
		
		# Set up vehicle collision shape
		var col_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		
		# Set size matching the hull's size
		var base_size = Vector3(4.0, 1.0, 6.0)
		if vehicle_hull.has_meta("base_hull_size") and vehicle_hull.has_meta("hull_scale"):
			var raw_size = vehicle_hull.get_meta("base_hull_size") * vehicle_hull.get_meta("hull_scale")
			var armor_thick = vehicle_hull.get_meta("armor_thickness") if vehicle_hull.has_meta("armor_thickness") else 1.0
			var bulk = Vector3(1.0 + (armor_thick - 1.0) * 0.15, 1.0 + (armor_thick - 1.0) * 0.15, 1.0)
			base_size = raw_size * bulk
		box.size = base_size
		col_shape.shape = box
		col_shape.position = Vector3(0, base_size.y / 2.0, 0)
		vehicle.add_child(col_shape)
		
		recalculate_move_speed()

func _setup_weapons():
	# Attach auto-tracking weapon scripts to all weapon modules
	for child in vehicle_hull.get_children():
		if child.has_meta("module_data"):
			var data = child.get_meta("module_data")
			if data.category == "weapon":
				var weapon_script = load("res://scripts/auto_weapon.gd")
				if weapon_script:
					child.set_script(weapon_script)
					child.set_physics_process(true)
					child._ready() # Re-initialize with script

func _spawn_target_dummies():
	# Clear old dummies
	for dummy in target_dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	target_dummies.clear()
	
	var points = [
		Vector3(-10, 0.5, -10),
		Vector3(10, 0.5, -15),
		Vector3(0, 0.5, -20),
		Vector3(-15, 0.5, -5),
		Vector3(15, 0.5, -5)
	]
	
	for pos in points:
		var dummy_scene = load("res://scenes/TargetDummy.tscn")
		if dummy_scene:
			var dummy = dummy_scene.instantiate()
			add_child(dummy)
			dummy.global_position = pos
			target_dummies.append(dummy)

func _unhandled_input(event):
	# Click to move vehicle (Right click or Left click on ground)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and not event.shift_pressed):
			var space_state = get_world_3d().direct_space_state
			var mouse_pos = event.position
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0
			
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			query.collision_mask = 1 # Ground layer
			var result = space_state.intersect_ray(query)
			
			if result:
				target_destination = result.position
				is_moving = true
				
				# Spawn a brief destination marker
				_create_move_marker(target_destination)

func _create_move_marker(pos: Vector3):
	var marker = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	marker.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.GREEN
	mat.emission_enabled = true
	mat.emission = Color.GREEN
	marker.material_override = mat
	add_child(marker)
	marker.global_position = pos
	
	var timer = get_tree().create_timer(0.5)
	timer.timeout.connect(func(): marker.queue_free())

func _physics_process(delta):
	# Altitude / Gravity control
	if is_instance_valid(vehicle):
		if locomotion_type == "helicopter_rotors":
			# Flying rotors manually lerp altitude, no gravity
			vehicle.velocity.y = 0.0
			var target_y = target_altitude
			vehicle.global_position.y = lerp(vehicle.global_position.y, target_y, 3.0 * delta)
		else:
			# Ground vehicles use gravity and snap to ground via physics
			if not vehicle.is_on_floor():
				vehicle.velocity.y -= 9.8 * delta
			else:
				vehicle.velocity.y = -1.0 # Press down slightly to keep grounded

	if is_moving and is_instance_valid(vehicle):
		var pos_diff = target_destination - vehicle.global_position
		pos_diff.y = 0.0 # Keep movement horizontal
		
		if pos_diff.length() < 0.5:
			is_moving = false
			vehicle.velocity.x = 0.0
			vehicle.velocity.z = 0.0
		else:
			var target_basis = Basis.looking_at(pos_diff, Vector3.UP)
			vehicle.global_transform.basis = vehicle.global_transform.basis.slerp(target_basis, rotate_speed * delta)
			
			var forward_dir = -vehicle.global_transform.basis.z.normalized()
			vehicle.velocity.x = forward_dir.x * move_speed
			vehicle.velocity.z = forward_dir.z * move_speed
	else:
		if is_instance_valid(vehicle):
			vehicle.velocity.x = 0.0
			vehicle.velocity.z = 0.0
			
	if is_instance_valid(vehicle):
		vehicle.move_and_slide()
			
	# Spin helicopter rotors if present
	if is_instance_valid(vehicle_hull):
		for child in vehicle_hull.get_children():
			if child.has_meta("module_data"):
				var data = child.get_meta("module_data")
				if data.type_id == "helicopter_rotors":
					# Find the MeshInstance3D inside and spin it on Y
					if child.get_child_count() > 0:
						var mesh = child.get_child(0)
						if is_instance_valid(mesh):
							mesh.rotate_y(15.0 * delta)
			
	# Update Camera to follow vehicle
	if is_instance_valid(vehicle):
		var target_cam_pos = vehicle.global_position + Vector3(0, 12, 12)
		camera.global_position = camera.global_position.lerp(target_cam_pos, 5.0 * delta)
		camera.look_at(vehicle.global_position + Vector3(0, 0.5, 0), Vector3.UP)

func _on_return_pressed():
	get_tree().change_scene_to_file("res://scenes/MainLab.tscn")

func _on_reset_dummies_pressed():
	_spawn_target_dummies()

func update_player_hp_ui():
	var hp_label = get_node_or_null("UI/PlayerHPLabel") as Label
	if hp_label and is_instance_valid(vehicle):
		var hp_pct = clamp(vehicle.hp / vehicle.max_hp, 0.0, 1.0)
		var bar_length = 15
		var filled = int(hp_pct * bar_length)
		var bar_str = ""
		for i in range(filled):
			bar_str += "■"
		for i in range(bar_length - filled):
			bar_str += "□"
			
		var faction_str = "Industrialists"
		if is_instance_valid(vehicle_hull) and vehicle_hull.has_meta("faction"):
			var fac = vehicle_hull.get_meta("faction")
			if fac == "industrialists": faction_str = "Heavy Industrialists"
			elif fac == "technocrats": faction_str = "Technocrats"
			elif fac == "expansionists": faction_str = "Expansionists"
			
		hp_label.text = "Player HP: %d/%d [%s] (%s)" % [int(vehicle.hp), int(vehicle.max_hp), bar_str, faction_str]
		hp_label.modulate = Color.GREEN.lerp(Color.RED, 1.0 - hp_pct)

func recalculate_move_speed():
	if not is_instance_valid(vehicle_hull) or not is_instance_valid(vehicle):
		return
		
	var total_weight = 0.0
	var motor_thrust = 100.0 # Default base
	var has_locomotion = false
	
	# Fetch settings from hull meta
	var settings = {}
	if vehicle_hull.has_meta("locomotion_settings"):
		settings = vehicle_hull.get_meta("locomotion_settings")
		
	for child in vehicle_hull.get_children():
		if child.has_meta("module_data") and not child.is_queued_for_deletion():
			var data = child.get_meta("module_data")
			total_weight += data.get_weight()
			if data.category == "locomotion":
				has_locomotion = true
				var count_contrib = 1.0
				if locomotion_type == "wheels":
					var count = settings.get("count", 4)
					count_contrib = float(count) / 4.0
				elif locomotion_type == "tracked_treads":
					var width = settings.get("width", 1.0)
					count_contrib = width
				elif locomotion_type == "helicopter_rotors":
					var count = settings.get("count", 4)
					count_contrib = float(count) / 4.0
				motor_thrust += 150.0 * child.scale.x * child.scale.z * count_contrib
				
	if not has_locomotion:
		move_speed = 0.0
		print("Player vehicle immobilized! All locomotion parts destroyed.")
		return
		
	if total_weight > 0.0:
		move_speed = clamp((motor_thrust / total_weight) * 5.0, 2.0, 15.0)
		
	# Faction Passive Bonus: Technocrats get a 5% Speed Boost
	var faction = vehicle_hull.get_meta("faction") if vehicle_hull.has_meta("faction") else "industrialists"
	if faction == "technocrats":
		move_speed *= 1.05
		
	print("Recalculated speed: ", move_speed)
