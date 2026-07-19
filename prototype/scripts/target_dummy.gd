extends StaticBody3D

const DamageResolver = preload("res://scripts/damage_resolver.gd")

@export var max_health: float = 100.0
var health: float = 100.0
var is_dead: bool = false

# Patrol movement parameters
@export var patrol_speed: float = 3.0
@export var patrol_range: float = 6.0
var start_pos: Vector3
var patrol_dir: float = 1.0
var is_patrolling: bool = false

# Combat dummy parameters
var is_combat_dummy: bool = false
var time_since_last_missile: float = 0.0

var label: Label3D

@onready var mesh_inst = $MeshInstance3D

func _ready():
	health = max_health
	add_to_group("targets")
	
	start_pos = global_position
	is_patrolling = (randf() > 0.5)
	is_combat_dummy = (randf() > 0.6) # 40% chance to be hostile
	
	# Unique material so flashing doesn't affect other instances
	var mat = StandardMaterial3D.new()
	if is_combat_dummy:
		mat.albedo_color = Color(1.0, 0.4, 0.4) # Red tint for hostiles
	else:
		mat.albedo_color = Color.WHITE
	mesh_inst.material_override = mat
	
	# Instantiate floating 3D health label
	label = Label3D.new()
	label.position = Vector3(0, 1.3, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.outline_size = 6
	add_child(label)
	_update_health_label()

func _update_health_label():
	if is_instance_valid(label):
		var hp_pct = clamp(health / max_health, 0.0, 1.0)
		var bar_length = 8
		var filled = int(hp_pct * bar_length)
		var bar_str = ""
		for i in range(filled):
			bar_str += "■"
		for i in range(bar_length - filled):
			bar_str += "□"
		
		var type_str = "HOSTILE" if is_combat_dummy else "DUMMY"
		label.text = "%s (%s)\n%d/%d HP" % [bar_str, type_str, int(health), int(max_health)]
		label.modulate = Color.GREEN.lerp(Color.RED, 1.0 - hp_pct)

func _physics_process(delta):
	if is_dead: return
	
	if is_patrolling:
		# Move left/right on X-axis relative to start position
		global_position.x += patrol_dir * patrol_speed * delta
		if abs(global_position.x - start_pos.x) >= patrol_range:
			patrol_dir *= -1.0
			global_position.x = start_pos.x + patrol_dir * patrol_range
			
	if is_combat_dummy:
		time_since_last_missile += delta
		if time_since_last_missile >= 3.5:
			time_since_last_missile = 0.0
			_fire_missile_at_player()

func _fire_missile_at_player():
	var player = get_tree().get_first_node_in_group("player_vehicle")
	if not player or not is_instance_valid(player): return
	
	# Only fire if player is within 30 meters
	if global_position.distance_to(player.global_position) > 30.0:
		return
		
	var missile_scene = load("res://scripts/incoming_missile.gd")
	if missile_scene:
		var missile = Node3D.new()
		missile.set_script(missile_scene)
		get_tree().current_scene.add_child(missile)
		missile.global_position = global_position + Vector3(0, 1.0, 0)
		missile.target_node = player

func take_damage(amount: float, damage_type: String = "kinetic", _hit_origin = null):
	if is_dead: return

	# Same shared chip-through/brute-force armor model every real combatant
	# uses (battle_unit.gd/player_vehicle.gd/building.gd) - a light hardened
	# steel armor at thickness 0.5, roughly matching this dummy's old hand
	# -rolled thresholds. The old inline version hard-negated any hit below
	# its flat threshold instead of chip-through, so rapid-fire weapons
	# (dps*fire_rate per shot, often single digits) dealt literal zero
	# damage to test dummies forever.
	var pair = DamageResolver.get_material_threshold("hardened_steel", damage_type, 0.5)
	var final_damage = DamageResolver.compute_hull_damage(amount, pair.x, pair.y)
	if final_damage <= 0.0:
		return
	health = max(0.0, health - final_damage)
	_update_health_label()
	
	# Flash red
	var mat = mesh_inst.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color.RED
		mat.emission_enabled = true
		mat.emission = Color.RED
		
		get_tree().create_timer(0.15).timeout.connect(func():
			if is_instance_valid(mat) and not is_dead:
				mat.emission_enabled = false
				var health_pct = health / max_health
				mat.albedo_color = Color.WHITE.lerp(Color(0.8, 0.2, 0.2), 1.0 - health_pct)
		)
		
	if health <= 0.0:
		die()

func die():
	is_dead = true
	remove_from_group("targets")
	
	if is_instance_valid(label):
		label.visible = false
		label.queue_free()
	
	# Disable collisions immediately
	collision_layer = 0
	collision_mask = 0
	
	var mat = mesh_inst.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color.DARK_SLATE_GRAY
		mat.emission_enabled = false
		
	# Simple explosion particle simulation (creating small cubes fly off)
	for i in range(5):
		var particle = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.2, 0.2, 0.2)
		particle.mesh = box
		var p_mat = StandardMaterial3D.new()
		p_mat.albedo_color = Color.ORANGE
		particle.material_override = p_mat
		get_tree().current_scene.add_child(particle)
		particle.global_position = global_position
		
		# Move particle
		var dir = Vector3(randf_range(-1, 1), randf_range(0.5, 2), randf_range(-1, 1)).normalized()
		var tween_p = create_tween()
		tween_p.tween_property(particle, "global_position", global_position + dir * 3.0, 0.4)
		tween_p.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.4)
		tween_p.finished.connect(func(): particle.queue_free())
		
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
	tween.finished.connect(func(): queue_free())
