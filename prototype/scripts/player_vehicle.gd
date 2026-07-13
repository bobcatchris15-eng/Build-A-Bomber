extends CharacterBody3D

const DamageResolverScript = preload("res://scripts/damage_resolver.gd")

var max_hp: float = 400.0
var hp: float = 400.0
var is_dead: bool = false
# Energy resource (ENERGY_AND_BALANCE_SPEC.md #1) - state lives here same as
# hp/max_hp, but computation/regen-ticking is driven by battlefield.gd
# (recalculate_energy()/_physics_process()), mirroring how max_hp itself is
# computed there rather than in this script.
var max_energy: float = 0.0
var current_energy: float = 0.0
var energy_regen_rate: float = 0.0

func _ready():
	add_to_group("player_vehicle")

func get_active_modules() -> Array:
	var list = []
	var hull = get_node_or_null("Hull")
	if hull:
		for child in hull.get_children():
			if child.has_meta("module_data") and not child.is_queued_for_deletion():
				list.append(child)
	return list

func _find_meshes_recursive(node: Node, result: Array):
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_meshes_recursive(child, result)

func _spawn_module_explosion(pos: Vector3):
	for i in range(5):
		var particle = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.15, 0.15, 0.15)
		particle.mesh = box
		var p_mat = StandardMaterial3D.new()
		p_mat.albedo_color = Color.ORANGE
		p_mat.emission_enabled = true
		p_mat.emission = Color.ORANGE
		var scene = get_tree().current_scene
		if not scene:
			scene = get_parent()
		if scene:
			scene.add_child(particle)
		particle.global_position = pos
		
		var dir = Vector3(randf_range(-1, 1), randf_range(1, 3), randf_range(-1, 1)).normalized()
		var tween_p = create_tween()
		tween_p.tween_property(particle, "global_position", pos + dir * 3.0, 0.5)
		tween_p.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.5)
		tween_p.finished.connect(func(): particle.queue_free())

func take_damage(amount: float, damage_type: String = "kinetic", hit_origin = null):
	if is_dead: return

	# Fetch armor properties from hull metadata if present
	var hull = get_node_or_null("Hull")
	var active_modules = get_active_modules()
	var resolved = DamageResolverScript.resolve(hull, active_modules, damage_type, self, hit_origin)
	var threshold = resolved.x
	var reduction = resolved.y

	# 35% chance to hit a random exposed module (subsystem stripping)
	if not active_modules.is_empty() and randf() < 0.35:
		var target_module = active_modules.pick_random()
		var m_data = target_module.get_meta("module_data")
		
		# Retrieve current health or initialize it
		var m_hp = target_module.get_meta("current_hp") if target_module.has_meta("current_hp") else m_data.get_hp()
		
		# Modules don't have heavy hull armor, but apply a default minor threshold (say 5)
		var minor_threshold = 5.0
		var final_mod_damage = max(0.0, amount - minor_threshold)
		
		m_hp = max(0.0, m_hp - final_mod_damage)
		target_module.set_meta("current_hp", m_hp)
		
		# Flash module red briefly
		var meshes = []
		_find_meshes_recursive(target_module, meshes)
		for mesh in meshes:
			if is_instance_valid(mesh):
				var mat_over = mesh.material_override as StandardMaterial3D
				if mat_over:
					var prev_color = mat_over.albedo_color
					mat_over.albedo_color = Color.RED
					get_tree().create_timer(0.12).timeout.connect(func():
						if is_instance_valid(mat_over):
							mat_over.albedo_color = prev_color
					)
					
		print("[SUB-SYSTEM HIT] Hit module: ", m_data.module_name, " HP: ", m_hp, "/", m_data.get_hp())
		
		if m_hp <= 0.0:
			print("[STRIPPED] Module destroyed: ", m_data.module_name)
			_spawn_module_explosion(target_module.global_position)
			
			# Check symmetrical counterpart or group connections
			if target_module.has_meta("mirrored_counterpart"):
				var mirror = target_module.get_meta("mirrored_counterpart")
				if is_instance_valid(mirror):
					mirror.remove_meta("mirrored_counterpart") # delink
					
			target_module.queue_free()
			
			# Recalculate battlefield speed on the next frame (after queue_free takes effect)
			var battlefield = get_parent()
			if battlefield and battlefield.has_method("recalculate_move_speed"):
				battlefield.call_deferred("recalculate_move_speed")
		return

	# The Threshold Rule: If incoming attack is below threshold, it's negated!
	if amount < threshold:
		# Negated! Play shield flash
		var exp = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.8
		sphere.height = 1.6
		exp.mesh = sphere
		var flash_mat = StandardMaterial3D.new()
		flash_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.4)
		flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(0.2, 0.6, 1.0)
		exp.material_override = flash_mat
		add_child(exp)
		exp.position = Vector3(0, 0.5, 0)
		var tween = create_tween()
		tween.tween_property(exp, "scale", Vector3.ZERO, 0.1)
		tween.finished.connect(func(): exp.queue_free())
		return
		
	# Apply reduction multiplier to main hull
	var final_damage = amount * reduction
	hp = max(0.0, hp - final_damage)
	
	# Red camera flash or flash color on vehicle - hull materials are now
	# the shared faction ShaderMaterial (hull_material_builder.gd), so this
	# flashes via its flash_amount uniform instead of albedo_color (which
	# never existed on a ShaderMaterial), same fix as battle_unit.gd's
	# _flash_hull().
	if hull:
		var mesh_inst = hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh_inst and mesh_inst.material_override:
			var mat_over = mesh_inst.material_override
			if mat_over is ShaderMaterial:
				mat_over.set_shader_parameter("flash_amount", 1.0)
				get_tree().create_timer(0.12).timeout.connect(func():
					if is_instance_valid(mat_over):
						mat_over.set_shader_parameter("flash_amount", 0.0)
				)
			elif mat_over is StandardMaterial3D:
				var prev_color = mat_over.albedo_color
				mat_over.albedo_color = Color.RED
				get_tree().create_timer(0.12).timeout.connect(func():
					if is_instance_valid(mat_over):
						mat_over.albedo_color = prev_color
				)
			
	# Update battlefield UI
	var battlefield = get_parent()
	if battlefield and battlefield.has_method("update_player_hp_ui"):
		battlefield.update_player_hp_ui()
		
	if hp <= 0.0:
		die()

func spend_energy(amount: float) -> bool:
	if is_dead or current_energy < amount:
		return false
	current_energy -= amount
	return true

func drain_energy(amount: float):
	if is_dead: return
	current_energy = max(0.0, current_energy - amount)

func repair_hp(amount: float):
	if is_dead or hp >= max_hp: return
	hp = min(max_hp, hp + amount)
	var battlefield = get_parent()
	if battlefield and battlefield.has_method("update_player_hp_ui"):
		battlefield.update_player_hp_ui()

func die():
	is_dead = true
	
	# Spawn massive explosion particle simulation
	for i in range(12):
		var particle = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.3, 0.3, 0.3)
		particle.mesh = box
		var p_mat = StandardMaterial3D.new()
		p_mat.albedo_color = Color.RED.lerp(Color.YELLOW, randf())
		p_mat.emission_enabled = true
		p_mat.emission = p_mat.albedo_color
		var scene = get_tree().current_scene
		if not scene:
			scene = get_parent()
		if scene:
			scene.add_child(particle)
		particle.global_position = global_position
		
		var dir = Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-2, 2)).normalized()
		var tween_p = create_tween()
		tween_p.tween_property(particle, "global_position", global_position + dir * 6.0, 0.8)
		tween_p.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.8)
		tween_p.finished.connect(func(): particle.queue_free())
		
	# Scale down and hide
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
	
	# Restart battle scene after a short delay
	get_tree().create_timer(2.0).timeout.connect(func():
		get_tree().reload_current_scene()
	)
