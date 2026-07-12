extends Node3D

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const GlobalConfig = preload("res://scripts/global_config.gd")

var target: Node3D = null
var fire_range: float = 12.0
var fire_rate: float = 1.0 # Shot interval
var time_since_last_shot: float = 0.0

var dps: float = 10.0
var laser_color: Color = Color.RED
var type_id: String = ""

var damage_class: String = "kinetic"
var traverse_limit_angle: float = PI / 4.0
var traverse_speed: float = 4.0
var resting_transform: Transform3D
var spin_up_timer: float = 0.0

# Helper to find all colliders recursively
func _get_colliders_recursive(node: Node, list: Array):
	if node is CollisionObject3D:
		list.append(node.get_rid())
	for child in node.get_children():
		_get_colliders_recursive(child, list)

# Helper to find vehicle root
func get_vehicle_root() -> Node3D:
	var p = get_parent()
	while p:
		if p.is_in_group("player_vehicle") or p.is_in_group("targets") or p.is_in_group("damageable"):
			return p
		p = p.get_parent()
	return null

# Team of the construct this weapon is mounted on (-1 = legacy test range, no team)
func get_team() -> int:
	var root_vehicle = get_vehicle_root()
	if root_vehicle and root_vehicle.has_meta("team"):
		return root_vehicle.get_meta("team")
	return -1

# Line of sight raycast check
func _is_line_of_sight_blocked() -> bool:
	if not target or not is_instance_valid(target): return true
	
	var space_state = get_world_3d().direct_space_state
	# Weapons face forward along negative Z relative to their own local space
	var muzzle_forward = -global_transform.basis.z.normalized()
	
	# Offset ray start to weapon barrel height to avoid clipping own hull/neighbors
	var height_offset = 0.5
	if type_id != "":
		var catalog = ModuleCatalog.get_module_data(type_id)
		if catalog:
			height_offset = catalog.size.y * 0.7
			
	var ray_start = global_position + Vector3(0, height_offset, 0) + muzzle_forward * 0.8 # start in front of barrel
	var ray_end = target.global_position + Vector3(0, 0.5, 0) # target center
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1 + 2 + 4 + 8 # Ground (1), Modules (2), Vehicles (4), Targets (8)
	query.collide_with_areas = true
	
	# Exclude own weapon static body, main vehicle body, and the Hull static body
	var own_colliders = []
	_get_colliders_recursive(self, own_colliders)
	var vehicle = get_vehicle_root()
	if vehicle:
		if vehicle is CollisionObject3D:
			own_colliders.append(vehicle.get_rid())
		var hull = vehicle.get_node_or_null("Hull")
		if hull and hull is CollisionObject3D:
			own_colliders.append(hull.get_rid())
	query.exclude = own_colliders
	
	var result = space_state.intersect_ray(query)
	if result:
		var hit_collider = result.collider
		var is_own = vehicle and (hit_collider == vehicle or vehicle.is_ancestor_of(hit_collider))
		if is_own:
			return true
	return false

func _ready():
	resting_transform = transform
	if has_meta("module_data"):
		var data = get_meta("module_data")
		type_id = data.type_id
		dps = data.get_dps()
		
		# Calculate traverse speed based on weight
		var weight = data.get_weight()
		traverse_speed = clamp(200.0 / weight, 0.6, 6.0)
		
		# Traverse limit angle: shared with the Design Lab's firing-arc
		# visualization via ModuleCatalog.get_traverse_limit_angle() so the
		# two can never drift apart.
		var mount_facet = get_meta("facet", "")
		var mount_hull_type = ""
		var mount_parent = get_parent()
		if mount_parent and mount_parent.has_meta("type_id"):
			mount_hull_type = mount_parent.get_meta("type_id")
		traverse_limit_angle = ModuleCatalog.get_traverse_limit_angle(type_id, mount_facet, mount_hull_type)
			
		if type_id in ["basic_cannon", "heavy_machine_gun", "rotary_cannon", "gauss_railgun", "ciws"]:
			damage_class = "kinetic"
		elif type_id in ["heavy_howitzer", "mortar_array", "spigot_mortar", "guided_missile", "dual_stage_missile", "missile_pod", "cluster_dispenser", "flak_cannon"]:
			damage_class = "explosive"
		else:
			damage_class = "thermal"
			
		# Configure stats and colors by type_id
		if type_id == "basic_cannon":
			fire_range = 25.0
			fire_rate = 1.8
			laser_color = Color.ORANGE
		elif type_id == "heavy_machine_gun":
			fire_range = 15.0
			fire_rate = 0.22
			laser_color = Color.GOLD
		elif type_id == "rotary_cannon":
			fire_range = 20.0
			fire_rate = 0.05
			laser_color = Color.GOLD
		elif type_id == "gauss_railgun":
			fire_range = 45.0
			fire_rate = 3.5
			laser_color = Color.BLUE_VIOLET
		elif type_id == "heavy_howitzer":
			fire_range = 50.0
			fire_rate = 4.5
			laser_color = Color.SADDLE_BROWN
		elif type_id == "mortar_array":
			fire_range = 28.0
			fire_rate = 2.0
			laser_color = Color.OLIVE
		elif type_id == "spigot_mortar":
			fire_range = 10.0
			fire_rate = 4.0
			laser_color = Color.CRIMSON
		elif type_id == "guided_missile":
			fire_range = 35.0
			fire_rate = 3.0
			laser_color = Color.YELLOW
		elif type_id == "dual_stage_missile":
			fire_range = 38.0
			fire_rate = 4.0
			laser_color = Color.YELLOW_GREEN
		elif type_id == "missile_pod":
			fire_range = 30.0
			fire_rate = 2.8
			laser_color = Color.DARK_ORANGE
		elif type_id == "drone_carrier":
			fire_range = 30.0
			fire_rate = 5.0
			laser_color = Color.NAVY_BLUE
		elif type_id == "cluster_dispenser":
			fire_range = 24.0
			fire_rate = 3.0
			laser_color = Color.CHOCOLATE
		elif type_id == "flamethrower":
			fire_range = 9.0
			fire_rate = 0.05
			laser_color = Color.CRIMSON
		elif type_id == "heavy_laser":
			fire_range = 22.0
			fire_rate = 0.05
			laser_color = Color.DARK_RED
		elif type_id == "plasma_lobber":
			fire_range = 24.0
			fire_rate = 2.2
			laser_color = Color.MEDIUM_SPRING_GREEN
		elif type_id == "ciws":
			fire_range = 14.0
			fire_rate = 0.06
			laser_color = Color.WHITE_SMOKE
		elif type_id == "pd_laser":
			fire_range = 16.0
			fire_rate = 0.1
			laser_color = Color.LIGHT_CORAL
		elif type_id == "flak_cannon":
			fire_range = 22.0
			fire_rate = 1.2
			laser_color = Color.DARK_GOLDENROD
		elif type_id == "resource_harvester":
			fire_range = 15.0
			fire_rate = 0.1
			laser_color = Color.GOLD
		elif type_id == "repair_array":
			fire_range = 12.0
			fire_rate = 0.15
			laser_color = Color.CYAN
		else:
			fire_range = 15.0
			fire_rate = 1.0
			laser_color = Color.WHITE
			
		# Apply Range & Traverse Speed Tweak Modifiers
		if data.tweaks.has("barrel_length"):
			fire_range *= data.tweaks["barrel_length"]
		if data.tweaks.has("elevation"):
			fire_range *= data.tweaks["elevation"]
		if data.tweaks.has("rod_thickness") and data.tweaks["rod_thickness"] > 0.0:
			fire_range /= data.tweaks["rod_thickness"]
		if data.tweaks.has("engine_length"):
			fire_range *= data.tweaks["engine_length"]
		if data.tweaks.has("payload_size") and data.tweaks["payload_size"] > 0.0:
			fire_range /= data.tweaks["payload_size"]
		if data.tweaks.has("nozzle_width") and data.tweaks["nozzle_width"] > 0.0:
			fire_range /= data.tweaks["nozzle_width"]
		if data.tweaks.has("lens_aperture") and data.tweaks["lens_aperture"] > 0.0:
			fire_range /= data.tweaks["lens_aperture"]
		if data.tweaks.has("containment") and data.tweaks["containment"] > 0.0:
			fire_range /= data.tweaks["containment"]
		if data.tweaks.has("radar_dish"):
			fire_range *= data.tweaks["radar_dish"]
			
		if data.tweaks.has("barrel_length") and data.tweaks["barrel_length"] > 0.0:
			traverse_speed /= data.tweaks["barrel_length"]
		if data.tweaks.has("elevation") and data.tweaks["elevation"] > 0.0:
			traverse_speed /= data.tweaks["elevation"]
			
		# Apply Fire Rate Tweak Modifiers (Shot Intervals)
		if data.tweaks.has("caliber"):
			fire_rate *= data.tweaks["caliber"]
		if data.tweaks.has("multi_barrel") and data.tweaks["multi_barrel"] == true:
			fire_rate /= 2.0
		if data.tweaks.has("tube_count") and data.tweaks["tube_count"] > 0.0:
			fire_rate *= (data.tweaks["tube_count"] / 2.0)
		if data.tweaks.has("grid_size") and data.tweaks["grid_size"] > 0.0:
			fire_rate *= (data.tweaks["grid_size"] / 4.0)
		if data.tweaks.has("pressure_valve") and data.tweaks["pressure_valve"] > 0.0:
			fire_rate /= data.tweaks["pressure_valve"]
			
	# Desynchronize initial reload timers
	time_since_last_shot = randf_range(0.0, fire_rate)

func _physics_process(delta):
	# Spin radar mast dish
	if type_id == "sensor_suite":
		var dish = get_node_or_null("RadarDish")
		if dish:
			dish.rotate_y(delta * 2.5)
		return
		
	# Ignore support modules in tracking (except harvester and repair welder)
	if type_id in ["logistics_tank"]:
		return

	time_since_last_shot += delta
	_find_nearest_target()
	
	if target and is_instance_valid(target):
		var target_pos = target.global_position
		# Target center height
		if target.is_in_group("targets") or target.is_in_group("player_vehicle"):
			target_pos += Vector3(0, 0.5, 0)
			
		var dir_to_target = (target_pos - global_position).normalized()

		# frame_built (traverse_limit_angle == 0): the barrel is fixed
		# relative to the hull by definition - skip the independent-aim
		# slerp entirely and stay at resting_transform. The whole vehicle
		# has to turn to bring it to bear (battle_unit.gd's
		# _has_frame_built_weapon/whole-vehicle-aim handles that), and the
		# angle_to_target check just below naturally reflects that since
		# global_transform now tracks the hull's own facing 1:1.
		if traverse_limit_angle > 0.001:
			# Target local direction relative to weapon parent (the Hull)
			var target_local_pos = get_parent().to_local(target_pos)
			var local_dir = target_local_pos.normalized()
			var target_local_basis = Basis.looking_at(local_dir, Vector3.UP)

			# Gradually rotate local basis towards target using Quaternions
			var q_current = transform.basis.get_rotation_quaternion()
			var q_target = target_local_basis.get_rotation_quaternion()
			var q_next = q_current.slerp(q_target, traverse_speed * delta)
			var local_scale = transform.basis.get_scale()
			transform.basis = Basis(q_next).scaled(local_scale)

		# Check if pointing close enough to fire
		var current_dir = -global_transform.basis.z.normalized()
		var angle_to_target = current_dir.angle_to(dir_to_target)
		
		# Only fire if pointing within 10 degrees (0.17 rad) and not blocked
		if angle_to_target < 0.17 and not _is_line_of_sight_blocked():
			# Spin up check for Rotary Cannon
			if type_id == "rotary_cannon":
				var spin_needed = 0.8
				if has_meta("module_data"):
					var m_data = get_meta("module_data")
					var motor_size = m_data.tweaks.get("motor_size", 1.0)
					if motor_size > 0.0:
						spin_needed /= motor_size
				
				# Visually rotate barrels if spun up or spinning
				rotate_object_local(Vector3.FORWARD, delta * (spin_up_timer / spin_needed) * 30.0)
				
				if spin_up_timer < spin_needed:
					spin_up_timer += delta
					return # still spinning up!
					
			if time_since_last_shot >= fire_rate:
				time_since_last_shot = 0.0
				_fire_at_target()
		else:
			# Not pointing at target, spin down
			if type_id == "rotary_cannon":
				spin_up_timer = max(0.0, spin_up_timer - delta * 2.0)
	else:
		# Return to resting transform in local space using Quaternions
		var q_current = transform.basis.get_rotation_quaternion()
		var q_target = resting_transform.basis.get_rotation_quaternion()
		var q_next = q_current.slerp(q_target, traverse_speed * delta)
		var local_scale = transform.basis.get_scale()
		transform.basis = Basis(q_next).scaled(local_scale)
		
		# Spin down Gatling
		if type_id == "rotary_cannon":
			spin_up_timer = max(0.0, spin_up_timer - delta * 2.0)

func _find_nearest_target():
	var resting_forward = get_parent().global_transform.basis * resting_transform.basis * Vector3.FORWARD

	# --- TEAM MODE (Skirmish): target any hostile "damageable" construct ---
	var my_team = get_team()
	if my_team >= 0:
		# Point defense still prioritizes missiles aimed at friendlies
		if type_id in ["ciws", "pd_laser", "flak_cannon"]:
			var missiles = get_tree().get_nodes_in_group("missiles")
			var closest_m: Node3D = null
			var closest_m_dist: float = fire_range
			for m in missiles:
				if not is_instance_valid(m): continue
				var m_team = m.get_meta("team") if m.has_meta("team") else -1
				if m_team == my_team: continue
				var dist_m = global_position.distance_to(m.global_position)
				if dist_m < closest_m_dist:
					var dir_m = (m.global_position - global_position).normalized()
					if resting_forward.angle_to(dir_m) <= traverse_limit_angle:
						closest_m = m
						closest_m_dist = dist_m
			if closest_m:
				target = closest_m
				return
		var candidates = get_tree().get_nodes_in_group("damageable")
		var closest_c: Node3D = null
		var closest_c_dist: float = fire_range
		for c in candidates:
			if not is_instance_valid(c) or not c.has_method("take_damage"): continue
			var c_team = c.get_meta("team") if c.has_meta("team") else -1
			if c_team == my_team: continue
			if "is_dead" in c and c.is_dead: continue
			var dist = global_position.distance_to(c.global_position)
			if dist < closest_c_dist:
				var dir = (c.global_position - global_position).normalized()
				if resting_forward.angle_to(dir) <= traverse_limit_angle:
					closest_c = c
					closest_c_dist = dist
		target = closest_c
		return

	# Point Defenses prioritize incoming missiles
	if type_id in ["ciws", "pd_laser", "flak_cannon"]:
		var missiles = get_tree().get_nodes_in_group("missiles")
		var closest: Node3D = null
		var closest_dist: float = fire_range
		for m in missiles:
			if is_instance_valid(m):
				var dist = global_position.distance_to(m.global_position)
				if dist < closest_dist:
					var dir = (m.global_position - global_position).normalized()
					if resting_forward.angle_to(dir) <= traverse_limit_angle:
						closest = m
						closest_dist = dist
		target = closest
		if target: return

	# Standard target dummies
	var targets = get_tree().get_nodes_in_group("targets")
	
	# If this weapon is on target dummy, target the player instead!
	var root_vehicle = get_vehicle_root()
	if root_vehicle and root_vehicle.is_in_group("targets"):
		var player = get_tree().get_first_node_in_group("player_vehicle")
		if player and is_instance_valid(player) and not player.is_dead:
			var dist = global_position.distance_to(player.global_position)
			if dist < fire_range:
				var dir = (player.global_position - global_position).normalized()
				if resting_forward.angle_to(dir) <= traverse_limit_angle:
					target = player
					return
		target = null
		return

	# Player targeting dummies
	var closest: Node3D = null
	var closest_dist: float = fire_range
	for t in targets:
		if is_instance_valid(t) and t.has_method("take_damage"):
			if "health" in t and t.health <= 0.0:
				continue
			var dist = global_position.distance_to(t.global_position)
			if dist < closest_dist:
				var dir = (t.global_position - global_position).normalized()
				if resting_forward.angle_to(dir) <= traverse_limit_angle:
					closest = t
					closest_dist = dist
	target = closest

func _fire_at_target():
	if not target or not is_instance_valid(target): return
	
	# Point Defense intercepting a missile
	if target.is_in_group("missiles"):
		_fire_pd_at_missile()
		return
		
	# Spawn a nice muzzle flash (except for silent lasers/beams/harvester/welder)
	if not type_id in ["heavy_laser", "pd_laser", "resource_harvester", "repair_array"]:
		var flash = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.2
		sphere_mesh.height = 0.4
		flash.mesh = sphere_mesh
		var flash_mat = StandardMaterial3D.new()
		flash_mat.albedo_color = laser_color
		flash_mat.emission_enabled = true
		flash_mat.emission = laser_color
		flash.material_override = flash_mat
		add_child(flash)
		flash.position = Vector3(0, 0.4, -0.6)
		var flash_tween = create_tween()
		flash_tween.tween_property(flash, "scale", Vector3.ZERO, 0.08)
		flash_tween.finished.connect(func(): flash.queue_free())
	
	# Call unique visual functions
	match type_id:
		"basic_cannon":
			_fire_kinetic_projectile(0.05, 0.5, 0.18, laser_color, true)
		"heavy_machine_gun":
			_fire_kinetic_projectile(0.015, 0.25, 0.08, laser_color, false)
		"rotary_cannon":
			_fire_kinetic_projectile(0.012, 0.2, 0.06, laser_color, false)
		"gauss_railgun":
			_fire_railgun_beam()
		"heavy_howitzer":
			_fire_heavy_howitzer()
		"mortar_array":
			_fire_mortar_salvo()
		"spigot_mortar":
			_fire_spigot_mortar()
		"guided_missile":
			_fire_missile_projectile(false)
		"dual_stage_missile":
			_fire_missile_projectile(true)
		"missile_pod":
			_fire_swarm_missiles()
		"drone_carrier":
			_fire_drone_swarm()
		"cluster_dispenser":
			_fire_cluster_dispenser()
		"flamethrower":
			_fire_flame_spray()
		"heavy_laser":
			_fire_continuous_beam()
		"plasma_lobber":
			_fire_plasma_lobber()
		"ciws":
			_fire_kinetic_projectile(0.01, 0.18, 0.06, laser_color, false)
		"pd_laser":
			_fire_continuous_beam()
		"flak_cannon":
			_fire_flak_cannon()
		"resource_harvester":
			_fire_resource_harvester_tether()
		"repair_array":
			_fire_repair_array_beam()
		_:
			_fire_standard_laser()

func _fire_pd_at_missile():
	if type_id == "pd_laser":
		var beam = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		cyl.height = global_position.distance_to(target.global_position)
		beam.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.LIGHT_CORAL
		mat.emission_enabled = true
		mat.emission = Color.RED
		beam.material_override = mat
		get_tree().current_scene.add_child(beam)
		beam.global_position = global_position.lerp(target.global_position, 0.5)
		beam.look_at(target.global_position, Vector3.UP)
		beam.rotate_object_local(Vector3.RIGHT, PI/2)
		var timer = get_tree().create_timer(0.08)
		timer.timeout.connect(func(): if is_instance_valid(beam): beam.queue_free())
		
	if target.has_method("destroy_missile"):
		target.destroy_missile(true)

func _fire_kinetic_projectile(radius: float, length: float, duration: float, color: Color, explode_on_hit: bool):
	var tracer = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	tracer.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	tracer.material_override = mat
	get_tree().current_scene.add_child(tracer)
	
	var start = global_position + Vector3(0, 0.4, 0)
	tracer.global_position = start
	tracer.look_at(target.global_position, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, PI/2)
	
	var tween = create_tween()
	var end = target.global_position
	tween.tween_property(tracer, "global_position", end, duration)
	tween.finished.connect(func():
		if is_instance_valid(tracer): tracer.queue_free()
		if is_instance_valid(target):
			target.take_damage(dps * fire_rate, damage_class, global_position)
			if explode_on_hit:
				_spawn_explosion_visual(end, 0.4, color)
	)

func _fire_railgun_beam():
	var beam = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	var dist = global_position.distance_to(target.global_position)
	cyl.height = dist
	beam.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.BLUE_VIOLET
	mat.emission_enabled = true
	mat.emission = Color.BLUE_VIOLET
	beam.material_override = mat
	get_tree().current_scene.add_child(beam)
	
	beam.global_position = global_position.lerp(target.global_position, 0.5)
	beam.look_at(target.global_position, Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, PI/2)
	
	for i in range(4):
		var spark = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.15
		sphere.height = 0.3
		spark.mesh = sphere
		var smat = StandardMaterial3D.new()
		smat.albedo_color = Color.CYAN
		smat.emission_enabled = true
		smat.emission = Color.CYAN
		spark.material_override = smat
		get_tree().current_scene.add_child(spark)
		
		var pct = randf()
		spark.global_position = global_position.lerp(target.global_position, pct) + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
		
		var stween = create_tween()
		stween.tween_property(spark, "scale", Vector3.ZERO, 0.1)
		stween.finished.connect(func(): spark.queue_free())
		
	if is_instance_valid(target):
		target.take_damage(dps * fire_rate, damage_class, global_position)
		_spawn_explosion_visual(target.global_position, 0.6, Color.BLUE_VIOLET)
		
	var tween = create_tween()
	tween.tween_property(beam, "scale", Vector3(0.0, 1.0, 0.0), 0.15)
	tween.finished.connect(func(): beam.queue_free())

func _fire_heavy_howitzer():
	var shell = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	shell.mesh = sphere
	shell.scale = Vector3(0.4, 0.4, 0.4)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.SADDLE_BROWN
	mat.emission_enabled = true
	mat.emission = Color.ORANGE
	shell.material_override = mat
	get_tree().current_scene.add_child(shell)
	
	var start = global_position
	var end = target.global_position
	var tween = create_tween()
	var callable = func(val: float):
		if not is_instance_valid(shell): return
		var current_target = end
		if is_instance_valid(target):
			current_target = target.global_position
		var pos = start.lerp(current_target, val)
		pos.y += sin(val * PI) * 12.0
		shell.global_position = pos
		
	tween.tween_method(callable, 0.0, 1.0, 0.8)
	tween.finished.connect(func():
		if is_instance_valid(shell): shell.queue_free()
		if is_instance_valid(target):
			target.take_damage(dps * fire_rate, damage_class, global_position)
			_spawn_explosion_visual(end, 1.2, Color.ORANGE)
	)

func _fire_mortar_salvo():
	var count = 3
	if has_meta("module_data"):
		var data = get_meta("module_data")
		count = int(data.tweaks.get("tube_count", 2.0))
		
	for i in range(count):
		get_tree().create_timer(i * 0.18).timeout.connect(func():
			if not is_instance_valid(target): return
			var shell = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			shell.mesh = sphere
			shell.scale = Vector3(0.2, 0.2, 0.2)
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.OLIVE
			mat.emission_enabled = true
			mat.emission = Color.YELLOW
			shell.material_override = mat
			get_tree().current_scene.add_child(shell)
			
			var start = global_position
			var end = target.global_position + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
			var tween = create_tween()
			var height = 6.0
			var callable = func(val: float):
				if not is_instance_valid(shell): return
				var pos = start.lerp(end, val)
				pos.y += sin(val * PI) * height
				shell.global_position = pos
				
			tween.tween_method(callable, 0.0, 1.0, 0.6)
			tween.finished.connect(func():
				if is_instance_valid(shell): shell.queue_free()
				if is_instance_valid(target):
					target.take_damage((dps * fire_rate) / count, damage_class, global_position)
					_spawn_explosion_visual(end, 0.5, Color.YELLOW)
			)
		)

func _fire_spigot_mortar():
	var bomb = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.25
	cyl.height = 0.5
	bomb.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.DARK_KHAKI
	mat.emission_enabled = true
	mat.emission = Color.CRIMSON
	bomb.material_override = mat
	get_tree().current_scene.add_child(bomb)
	
	var start = global_position
	var end = target.global_position
	var tween = create_tween()
	var callable = func(val: float):
		if not is_instance_valid(bomb): return
		var pos = start.lerp(end, val)
		pos.y += sin(val * PI) * 5.0
		bomb.global_position = pos
		bomb.rotate_x(0.1)
		bomb.rotate_y(0.05)
		
	tween.tween_method(callable, 0.0, 1.0, 0.7)
	tween.finished.connect(func():
		if is_instance_valid(bomb): bomb.queue_free()
		if is_instance_valid(target):
			target.take_damage(dps * fire_rate, damage_class, global_position)
			_spawn_explosion_visual(end, 1.8, Color.CRIMSON)
	)

func _fire_missile_projectile(is_top_attack: bool):
	var missile = Node3D.new()
	var body = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 0.35
	body.mesh = cyl
	
	var bmat = StandardMaterial3D.new()
	bmat.albedo_color = Color.DARK_SLATE_GRAY
	body.material_override = bmat
	missile.add_child(body)
	body.rotate_x(PI/2)
	
	var nose = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.12
	nose.mesh = cone
	var nmat = StandardMaterial3D.new()
	nmat.albedo_color = Color.RED
	nmat.emission_enabled = true
	nmat.emission = Color.RED
	nose.material_override = nmat
	missile.add_child(nose)
	nose.position = Vector3(0, 0, -0.23)
	nose.rotate_x(-PI/2)
	
	get_tree().current_scene.add_child(missile)
	var start = global_position + Vector3(0, 0.5, 0)
	missile.global_position = start
	
	var end = target.global_position
	
	var trail_timer = Timer.new()
	trail_timer.wait_time = 0.04
	trail_timer.autostart = true
	missile.add_child(trail_timer)
	trail_timer.timeout.connect(func():
		if not is_instance_valid(missile): return
		var smoke = MeshInstance3D.new()
		var sph = SphereMesh.new()
		sph.radius = 0.08
		sph.height = 0.16
		smoke.mesh = sph
		var smat = StandardMaterial3D.new()
		smat.albedo_color = Color(0.6, 0.6, 0.6, 0.5)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke.material_override = smat
		get_tree().current_scene.add_child(smoke)
		smoke.global_position = missile.global_position - missile.global_transform.basis.z * 0.2
		var st = create_tween()
		st.tween_property(smoke, "scale", Vector3.ZERO, 0.25)
		st.finished.connect(func(): smoke.queue_free())
	)
	
	var tween = create_tween()
	if is_top_attack:
		var peak = start + Vector3(0, 9.0, 0)
		missile.look_at(peak, Vector3.UP)
		tween.tween_property(missile, "global_position", peak, 0.35)
		tween.finished.connect(func():
			if not is_instance_valid(missile): return
			if is_instance_valid(target):
				missile.look_at(target.global_position, Vector3.UP)
				var move_t = create_tween()
				move_t.tween_property(missile, "global_position", target.global_position, 0.35)
				move_t.finished.connect(func():
					if is_instance_valid(missile): missile.queue_free()
					if is_instance_valid(target):
						target.take_damage(dps * fire_rate, damage_class, global_position)
						_spawn_explosion_visual(target.global_position, 0.8, Color.YELLOW_GREEN)
				)
			else:
				missile.queue_free()
		)
	else:
		missile.look_at(end, Vector3.UP)
		tween.tween_property(missile, "global_position", end, 0.45)
		tween.finished.connect(func():
			if is_instance_valid(missile): missile.queue_free()
			if is_instance_valid(target):
				target.take_damage(dps * fire_rate, damage_class, global_position)
				_spawn_explosion_visual(end, 0.7, Color.YELLOW)
		)

func _fire_swarm_missiles():
	var count = 4
	if has_meta("module_data"):
		var data = get_meta("module_data")
		count = int(data.tweaks.get("grid_size", 4.0))
		
	for i in range(count):
		get_tree().create_timer(i * 0.08).timeout.connect(func():
			if not is_instance_valid(target): return
			
			var missile = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.06, 0.06, 0.2)
			missile.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.DARK_ORANGE
			mat.emission_enabled = true
			mat.emission = Color.ORANGE
			missile.material_override = mat
			get_tree().current_scene.add_child(missile)
			
			var start = global_position
			var end = target.global_position
			missile.global_position = start
			
			var dev_dir = Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 1.5), randf_range(-1.5, 1.5))
			var mid = start.lerp(end, 0.5) + dev_dir
			
			var tween = create_tween()
			var callable = func(val: float):
				if not is_instance_valid(missile): return
				var q0 = start.lerp(mid, val)
				var mid_pos = mid.lerp(end, val)
				var pos = q0.lerp(mid_pos, val)
				
				var next_val = val + 0.05
				if next_val <= 1.0:
					var next_q0 = start.lerp(mid, next_val)
					var next_mid = mid.lerp(end, next_val)
					var next_pos = next_q0.lerp(next_mid, next_val)
					missile.look_at(next_pos, Vector3.UP)
				
				missile.global_position = pos
				
			tween.tween_method(callable, 0.0, 1.0, 0.5)
			tween.finished.connect(func():
				if is_instance_valid(missile): missile.queue_free()
				if is_instance_valid(target):
					target.take_damage((dps * fire_rate) / count, damage_class, global_position)
					_spawn_explosion_visual(end, 0.3, Color.DARK_ORANGE)
			)
		)

func _fire_drone_swarm():
	for i in range(2):
		var drone = MeshInstance3D.new()
		var prism = PrismMesh.new()
		prism.size = Vector3(0.18, 0.08, 0.18)
		drone.mesh = prism
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.NAVY_BLUE
		mat.emission_enabled = true
		mat.emission = Color.CYAN
		drone.material_override = mat
		get_tree().current_scene.add_child(drone)
		
		var start = global_position + Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5))
		drone.global_position = start
		
		var end = target.global_position
		var tween = create_tween()
		
		var offset_angle = randf_range(0, 2*PI)
		var orbit_center = end + Vector3(0, 1.5, 0)
		var orbit_pos = orbit_center + Vector3(cos(offset_angle) * 1.5, 0, sin(offset_angle) * 1.5)
		
		tween.tween_property(drone, "global_position", orbit_pos, 0.3)
		tween.finished.connect(func():
			if not is_instance_valid(drone): return
			if is_instance_valid(target):
				var laser = MeshInstance3D.new()
				var cyl = CylinderMesh.new()
				cyl.top_radius = 0.01
				cyl.bottom_radius = 0.01
				cyl.height = drone.global_position.distance_to(target.global_position)
				laser.mesh = cyl
				var lmat = StandardMaterial3D.new()
				lmat.albedo_color = Color.CYAN
				lmat.emission_enabled = true
				lmat.emission = Color.CYAN
				laser.material_override = lmat
				get_tree().current_scene.add_child(laser)
				laser.global_position = drone.global_position.lerp(target.global_position, 0.5)
				laser.look_at(target.global_position, Vector3.UP)
				laser.rotate_object_local(Vector3.RIGHT, PI/2)
				
				var lt = create_tween()
				lt.tween_interval(0.08)
				lt.finished.connect(func(): laser.queue_free())
				
				target.take_damage((dps * fire_rate) / 2.0, damage_class, global_position)
				
				var return_t = create_tween()
				return_t.tween_property(drone, "global_position", global_position, 0.3)
				return_t.finished.connect(func(): drone.queue_free())
			else:
				drone.queue_free()
		)

func _fire_cluster_dispenser():
	var canister = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.2, 0.2, 0.4)
	canister.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.CHOCOLATE
	mat.emission_enabled = true
	mat.emission = Color.ORANGE_RED
	canister.material_override = mat
	get_tree().current_scene.add_child(canister)
	
	var start = global_position
	var end = target.global_position
	canister.global_position = start
	canister.look_at(end, Vector3.UP)
	
	var mid = start.lerp(end, 0.4)
	var tween = create_tween()
	tween.tween_property(canister, "global_position", mid, 0.25)
	tween.finished.connect(func():
		if is_instance_valid(canister): canister.queue_free()
		
		for i in range(5):
			var sub = MeshInstance3D.new()
			var sph = SphereMesh.new()
			sph.radius = 0.08
			sph.height = 0.16
			sub.mesh = sph
			var smat = StandardMaterial3D.new()
			smat.albedo_color = Color.CHOCOLATE
			smat.emission_enabled = true
			smat.emission = Color.ORANGE
			sub.material_override = smat
			get_tree().current_scene.add_child(sub)
			sub.global_position = mid
			
			var scatter_dest = end + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			var st = create_tween()
			st.tween_property(sub, "global_position", scatter_dest, 0.2)
			st.finished.connect(func():
				if is_instance_valid(sub): sub.queue_free()
				if is_instance_valid(target):
					target.take_damage((dps * fire_rate) / 5.0, damage_class, global_position)
					_spawn_explosion_visual(scatter_dest, 0.3, Color.CHOCOLATE)
			)
	)

func _fire_flame_spray():
	for i in range(6):
		var flame = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		flame.mesh = sphere
		flame.scale = Vector3(0.15, 0.15, 0.15)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(randf_range(0.8, 1.0), randf_range(0.2, 0.5), 0.0)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		flame.material_override = mat
		get_tree().current_scene.add_child(flame)
		
		flame.global_position = global_position + Vector3(randf_range(-0.1, 0.1), 0.4, randf_range(-0.1, 0.1))
		var spread = Vector3(randf_range(-1.2, 1.2), randf_range(-0.2, 0.5), randf_range(-1.2, 1.2))
		var dest = target.global_position + spread
		
		var tween = create_tween()
		tween.tween_property(flame, "global_position", dest, 0.35)
		tween.parallel().tween_property(flame, "scale", Vector3(0.4, 0.4, 0.4), 0.15)
		tween.chain().tween_property(flame, "scale", Vector3.ZERO, 0.2)
		tween.finished.connect(func():
			flame.queue_free()
			if is_instance_valid(target) and i == 0:
				target.take_damage(dps * fire_rate, damage_class, global_position)
		)

func _fire_continuous_beam():
	var beam = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = global_position.distance_to(target.global_position)
	beam.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = laser_color
	mat.emission_enabled = true
	mat.emission = laser_color
	beam.material_override = mat
	get_tree().current_scene.add_child(beam)
	
	beam.global_position = global_position.lerp(target.global_position, 0.5)
	beam.look_at(target.global_position, Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, PI/2)
	
	if is_instance_valid(target):
		target.take_damage(dps * fire_rate, damage_class, global_position)
		
	var timer = get_tree().create_timer(0.06)
	timer.timeout.connect(func(): if is_instance_valid(beam): beam.queue_free())

func _fire_plasma_lobber():
	var plasma = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	plasma.mesh = sphere
	plasma.scale = Vector3(0.35, 0.35, 0.35)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.MEDIUM_SPRING_GREEN
	mat.emission_enabled = true
	mat.emission = Color.MEDIUM_SPRING_GREEN
	plasma.material_override = mat
	get_tree().current_scene.add_child(plasma)
	
	var start = global_position
	var end = target.global_position
	var tween = create_tween()
	var callable = func(val: float):
		if not is_instance_valid(plasma): return
		var pos = start.lerp(end, val)
		pos.y += sin(val * PI) * 4.0
		plasma.global_position = pos
		
	tween.tween_method(callable, 0.0, 1.0, 0.6)
	tween.finished.connect(func():
		if is_instance_valid(plasma): plasma.queue_free()
		if is_instance_valid(target):
			target.take_damage(dps * fire_rate, damage_class, global_position)
			_spawn_explosion_visual(end, 0.8, Color.MEDIUM_SPRING_GREEN)
			
			var puddle = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = 1.0
			cyl.bottom_radius = 1.0
			cyl.height = 0.05
			puddle.mesh = cyl
			var pmat = StandardMaterial3D.new()
			pmat.albedo_color = Color(0.1, 0.8, 0.2, 0.4)
			pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			pmat.emission_enabled = true
			pmat.emission = Color.MEDIUM_SPRING_GREEN
			puddle.material_override = pmat
			get_tree().current_scene.add_child(puddle)
			puddle.global_position = end
			
			var pt = create_tween()
			pt.tween_property(puddle, "scale", Vector3.ZERO, 1.5)
			pt.finished.connect(func(): puddle.queue_free())
	)

func _fire_flak_cannon():
	var shell = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	shell.mesh = sphere
	shell.scale = Vector3(0.18, 0.18, 0.18)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.DARK_GOLDENROD
	mat.emission_enabled = true
	mat.emission = Color.GOLD
	shell.material_override = mat
	get_tree().current_scene.add_child(shell)
	
	var start = global_position
	var end = target.global_position
	var detonate_pos = start.lerp(end, 0.85)
	
	var tween = create_tween()
	tween.tween_property(shell, "global_position", detonate_pos, 0.22)
	tween.finished.connect(func():
		if is_instance_valid(shell): shell.queue_free()
		
		var smoke = MeshInstance3D.new()
		var sph = SphereMesh.new()
		sph.radius = 0.8
		sph.height = 1.6
		smoke.mesh = sph
		var smat = StandardMaterial3D.new()
		smat.albedo_color = Color(0.15, 0.15, 0.15, 0.7)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke.material_override = smat
		get_tree().current_scene.add_child(smoke)
		smoke.global_position = detonate_pos
		
		var st = create_tween()
		st.tween_property(smoke, "scale", Vector3.ZERO, 0.4)
		st.finished.connect(func(): smoke.queue_free())
		
		if is_instance_valid(target):
			target.take_damage(dps * fire_rate, damage_class, global_position)
	)

func _fire_resource_harvester_tether():
	var tether = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = global_position.distance_to(target.global_position)
	tether.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.GOLD
	mat.emission_enabled = true
	mat.emission = Color.GOLD
	tether.material_override = mat
	get_tree().current_scene.add_child(tether)
	
	tether.global_position = global_position.lerp(target.global_position, 0.5)
	tether.look_at(target.global_position, Vector3.UP)
	tether.rotate_object_local(Vector3.RIGHT, PI/2)
	
	if is_instance_valid(target):
		target.take_damage(dps * fire_rate, damage_class, global_position)
		
	var tween = create_tween()
	tween.tween_property(tether, "scale", Vector3(0, 1, 0), 0.08)
	tween.finished.connect(func(): tether.queue_free())

func _fire_repair_array_beam():
	var beam = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = global_position.distance_to(target.global_position)
	beam.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.CYAN
	mat.emission_enabled = true
	mat.emission = Color.CYAN
	beam.material_override = mat
	get_tree().current_scene.add_child(beam)
	
	beam.global_position = global_position.lerp(target.global_position, 0.5)
	beam.look_at(target.global_position, Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, PI/2)
	
	var spark = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	spark.mesh = sphere
	var smat = StandardMaterial3D.new()
	smat.albedo_color = Color.WHITE
	smat.emission_enabled = true
	smat.emission = Color.CYAN
	spark.material_override = smat
	get_tree().current_scene.add_child(spark)
	spark.global_position = target.global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.8), randf_range(-0.3, 0.3))
	var st = create_tween()
	st.tween_property(spark, "scale", Vector3.ZERO, 0.1)
	st.finished.connect(func(): spark.queue_free())
	
	if is_instance_valid(target):
		target.take_damage(dps * fire_rate, damage_class, global_position)
		
	var timer = get_tree().create_timer(0.08)
	timer.timeout.connect(func(): if is_instance_valid(beam): beam.queue_free())

func _spawn_explosion_visual(pos: Vector3, custom_scale: float = 0.6, color: Color = Color.ORANGE):
	var exp = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = custom_scale
	sphere.height = custom_scale * 2.0
	exp.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	exp.material_override = mat
	get_tree().current_scene.add_child(exp)
	exp.global_position = pos
	
	var tween = create_tween()
	tween.tween_property(exp, "scale", Vector3.ZERO, 0.15)
	tween.finished.connect(func(): exp.queue_free())

func _fire_standard_laser():
	var laser = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.05
	cylinder.height = global_position.distance_to(target.global_position)
	laser.mesh = cylinder
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = laser_color
	mat.emission_enabled = true
	mat.emission = laser_color
	laser.material_override = mat
	get_tree().current_scene.add_child(laser)
	
	laser.global_position = global_position.lerp(target.global_position, 0.5)
	laser.look_at(target.global_position, Vector3.UP)
	laser.rotate_object_local(Vector3.RIGHT, PI/2)
	
	if is_instance_valid(target):
		target.take_damage(dps * fire_rate, damage_class, global_position)
	
	var timer = get_tree().create_timer(0.08)
	timer.timeout.connect(func(): if is_instance_valid(laser): laser.queue_free())
