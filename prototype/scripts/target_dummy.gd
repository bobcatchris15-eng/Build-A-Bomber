extends StaticBody3D

const DamageResolver = preload("res://scripts/damage_resolver.gd")
const WorldHPBarScript = preload("res://scripts/world_hp_bar.gd")

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
var hp_bar: MeshInstance3D = null
var _last_health_for_flash: float = -1.0

@onready var mesh_inst = $MeshInstance3D

func _ready():
	health = max_health
	add_to_group("targets")
	add_to_group("damageable")
	if not has_meta("team"):
		set_meta("team", 1)

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
	
	# Real graphical bar (VISUAL_AND_UX_POLISH_PLAN.md A4) + a compact text
	# label for the numeric HP/type - the ASCII `■□` bar itself is what's
	# being replaced, the actual numbers are still worth keeping legible.
	hp_bar = WorldHPBarScript.create_bar(self, Vector3(0, 1.4, 0), get_meta("team", 1), 1.2, 0.16)
	label = Label3D.new()
	label.position = Vector3(0, 1.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 20
	label.outline_size = 4
	add_child(label)
	_update_health_label()

func _update_health_label():
	var hp_pct = clamp(health / max_health, 0.0, 1.0)
	WorldHPBarScript.update_bar(hp_bar, hp_pct)
	if _last_health_for_flash >= 0.0 and health < _last_health_for_flash:
		WorldHPBarScript.flash_damage(hp_bar)
	_last_health_for_flash = health
	if is_instance_valid(label):
		var type_str = "HOSTILE" if is_combat_dummy else "DUMMY"
		label.text = "%s\n%d/%d HP" % [type_str, int(health), int(max_health)]
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
		(get_tree().current_scene if get_tree().current_scene != null else get_tree().root).add_child(missile)
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
	remove_from_group("damageable")
	
	if is_instance_valid(label):
		label.visible = false
		label.queue_free()
	WorldHPBarScript.free_bar(hp_bar)
	
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
		(get_tree().current_scene if get_tree().current_scene != null else get_tree().root).add_child(particle)
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
