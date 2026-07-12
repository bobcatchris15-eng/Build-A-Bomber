extends CharacterBody3D
# Generic team-aware combat unit for Skirmish mode.
# Built from a blueprint dictionary via BlueprintManager.reconstruct_vehicle().
# Handles: armor/threshold damage model, subsystem stripping, movement orders,
# flying locomotion, and (if a resource_harvester module is present) an
# automatic harvest -> refinery dropoff economy loop.

signal died(unit)
signal resources_delivered(team, metal, crystal)

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")

var team: int = 0
var max_hp: float = 400.0
var hp: float = 400.0
var is_dead: bool = false

var hull_node: Node3D = null
var locomotion_type: String = ""
var locomotion_settings: Dictionary = {}
var move_speed: float = 5.0
var rotate_speed: float = 4.0
var target_altitude: float = 0.0
var is_flying: bool = false

# Orders
enum OrderType { IDLE, MOVE, ATTACK, HARVEST }
var order: OrderType = OrderType.IDLE
var move_target: Vector3 = Vector3.ZERO
var attack_target: Node3D = null

# Harvester state
var is_harvester: bool = false
var harvest_node: Node3D = null
var cargo_metal: int = 0
var cargo_crystal: int = 0
var cargo_capacity: int = 50
var harvest_timer: float = 0.0
const HARVEST_TIME: float = 3.0

var selection_ring: MeshInstance3D = null
var attack_range: float = 12.0

func _ready():
	add_to_group("units")
	add_to_group("damageable")

func setup(blueprint_data: Dictionary, unit_team: int, bp_manager: Node) -> void:
	team = unit_team
	set_meta("team", team)
	collision_layer = 4
	collision_mask = 1 # Ground only; units pass through each other in the prototype

	var locomotion = blueprint_data.get("locomotion", {})
	locomotion_type = locomotion.get("type_id", "")
	locomotion_settings = locomotion.get("settings", {})
	is_flying = (locomotion_type == "helicopter_rotors")
	if is_flying:
		target_altitude = 4.0

	hull_node = bp_manager.reconstruct_vehicle(blueprint_data, self)
	if not hull_node:
		return

	# HP model matches the test range: hull base HP * thickness * material multiplier
	var hull_type = hull_node.get_meta("type_id") if hull_node.has_meta("type_id") else "medium_hull"
	var catalog_data = ModuleCatalog.get_module_data(hull_type)
	var thick = hull_node.get_meta("armor_thickness") if hull_node.has_meta("armor_thickness") else 1.0
	var mat = hull_node.get_meta("armor_material") if hull_node.has_meta("armor_material") else "hardened_steel"
	var mat_mult = 1.0
	if mat == "reactive_armor": mat_mult = 1.3
	elif mat == "ablative_ceramic": mat_mult = 1.6
	elif mat == "energy_shielding": mat_mult = 2.0
	max_hp = catalog_data.hp * thick * mat_mult
	hp = max_hp

	# Collision shape matching the hull
	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	var base_size = catalog_data.size
	if hull_node.has_meta("base_hull_size") and hull_node.has_meta("hull_scale"):
		base_size = hull_node.get_meta("base_hull_size") * hull_node.get_meta("hull_scale")
	var bulk = Vector3(1.0 + (thick - 1.0) * 0.15, 1.0 + (thick - 1.0) * 0.15, 1.0)
	box.size = base_size * bulk
	col_shape.shape = box
	col_shape.position = Vector3(0, box.size.y / 2.0, 0)
	add_child(col_shape)

	_setup_weapons()
	_detect_harvester()
	_recalculate_move_speed()
	_create_selection_ring(base_size)
	_create_hp_bar()

func _setup_weapons():
	for child in hull_node.get_children():
		if child.has_meta("module_data"):
			var data = child.get_meta("module_data")
			if data.category == "weapon":
				var weapon_script = load("res://scripts/auto_weapon.gd")
				child.set_script(weapon_script)
				child.set_physics_process(true)
				child._ready()
				# Track the longest-ranged weapon for attack-order standoff distance
				if "fire_range" in child:
					attack_range = max(attack_range, child.fire_range * 0.85)

func _detect_harvester():
	for child in hull_node.get_children():
		if child.has_meta("module_data"):
			var data = child.get_meta("module_data")
			if data.type_id == "resource_harvester":
				is_harvester = true
				var extractor = data.tweaks.get("extractor_size", 1.0)
				cargo_capacity = int(50 * extractor)
				break

func _recalculate_move_speed():
	if not is_instance_valid(hull_node):
		return
	var total_weight = 0.0
	var motor_thrust = 100.0
	var has_locomotion = false
	for child in hull_node.get_children():
		if child.has_meta("module_data") and not child.is_queued_for_deletion():
			var data = child.get_meta("module_data")
			total_weight += data.get_weight()
			if data.category == "locomotion":
				has_locomotion = true
				var count_contrib = 1.0
				if locomotion_type == "wheels" or locomotion_type == "helicopter_rotors":
					count_contrib = float(locomotion_settings.get("count", 4)) / 4.0
				elif locomotion_type == "tracked_treads":
					count_contrib = locomotion_settings.get("width", 1.0)
				motor_thrust += 150.0 * child.scale.x * child.scale.z * count_contrib
	if not has_locomotion:
		move_speed = 0.0
		return
	if total_weight > 0.0:
		move_speed = clamp((motor_thrust / total_weight) * 5.0, 2.0, 15.0)
	# Faction passive: Technocrats +5% speed
	var faction = hull_node.get_meta("faction") if hull_node.has_meta("faction") else "industrialists"
	if faction == "technocrats":
		move_speed *= 1.05

func _create_selection_ring(base_size: Vector3):
	selection_ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	var radius = max(base_size.x, base_size.z) * 0.65
	torus.inner_radius = radius - 0.12
	torus.outer_radius = radius
	selection_ring.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_ring.material_override = mat
	selection_ring.position = Vector3(0, 0.08, 0)
	selection_ring.visible = false
	add_child(selection_ring)

var hp_bar: Label3D = null
func _create_hp_bar():
	hp_bar = Label3D.new()
	hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_bar.font_size = 22
	hp_bar.outline_size = 5
	hp_bar.position = Vector3(0, 2.6, 0)
	add_child(hp_bar)
	_update_hp_bar()

func _update_hp_bar():
	if not is_instance_valid(hp_bar): return
	var pct = clamp(hp / max_hp, 0.0, 1.0)
	var filled = int(pct * 8.0)
	var bar = ""
	for i in range(filled): bar += "■"
	for i in range(8 - filled): bar += "□"
	if is_harvester and (cargo_metal > 0 or cargo_crystal > 0):
		bar += " ⛏"
	hp_bar.text = bar
	hp_bar.modulate = (Color.GREEN if team == 0 else Color.ORANGE_RED).lerp(Color.RED, 1.0 - pct)

func set_selected(selected: bool):
	if is_instance_valid(selection_ring):
		selection_ring.visible = selected

func order_move(dest: Vector3):
	order = OrderType.MOVE
	move_target = dest
	attack_target = null

func order_attack(node: Node3D):
	order = OrderType.ATTACK
	attack_target = node

func order_harvest(node: Node3D):
	if not is_harvester: return
	order = OrderType.HARVEST
	harvest_node = node
	harvest_timer = 0.0

func _physics_process(delta):
	if is_dead: return

	# Altitude / gravity
	if is_flying:
		velocity.y = 0.0
		global_position.y = lerp(global_position.y, target_altitude, 3.0 * delta)
	else:
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		else:
			velocity.y = -1.0

	match order:
		OrderType.MOVE:
			if _steer_towards(move_target, delta, 0.6):
				order = OrderType.IDLE
		OrderType.ATTACK:
			if not is_instance_valid(attack_target) or ("is_dead" in attack_target and attack_target.is_dead):
				attack_target = null
				order = OrderType.IDLE
			else:
				var dist = global_position.distance_to(attack_target.global_position)
				if dist > attack_range:
					# Armor phase 5: approach the target's weakest facet
					# instead of walking straight at it, so a player's
					# directional armor design decisions actually matter in
					# Skirmish (previously only a human in Test Range could
					# exploit facing; the AI never tried). Applies to both
					# teams equally - same steering code runs for player and
					# enemy units, no AI-only special case.
					var approach_point = _compute_flank_point(attack_target)
					_steer_towards(approach_point, delta, attack_range * 0.9)
				else:
					velocity.x = 0.0
					velocity.z = 0.0
		OrderType.HARVEST:
			_process_harvest(delta)
		_:
			velocity.x = 0.0
			velocity.z = 0.0
			if is_harvester:
				_auto_find_harvest_work()

	move_and_slide()

	# Spin rotors
	if is_flying and is_instance_valid(hull_node):
		for child in hull_node.get_children():
			if child.has_meta("module_data") and child.get_meta("module_data").type_id == "helicopter_rotors":
				if child.get_child_count() > 0 and is_instance_valid(child.get_child(0)):
					child.get_child(0).rotate_y(15.0 * delta)

# Returns true when arrived
func _steer_towards(dest: Vector3, delta: float, arrive_dist: float) -> bool:
	var pos_diff = dest - global_position
	pos_diff.y = 0.0
	if pos_diff.length() < arrive_dist:
		velocity.x = 0.0
		velocity.z = 0.0
		return true
	if move_speed <= 0.0:
		return false
	var target_basis = Basis.looking_at(pos_diff, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, rotate_speed * delta).orthonormalized()
	var forward_dir = -global_transform.basis.z.normalized()
	velocity.x = forward_dir.x * move_speed
	velocity.z = forward_dir.z * move_speed
	return false

# --- Harvest loop ---

func _auto_find_harvest_work():
	if cargo_metal + cargo_crystal >= cargo_capacity:
		order = OrderType.HARVEST
		return
	var nodes = get_tree().get_nodes_in_group("resource_nodes")
	var best: Node3D = null
	var best_dist := INF
	for n in nodes:
		if is_instance_valid(n) and n.amount > 0:
			var d = global_position.distance_to(n.global_position)
			if d < best_dist:
				best = n
				best_dist = d
	if best:
		order_harvest(best)

func _process_harvest(delta):
	# Full? Head to nearest friendly refinery.
	if cargo_metal + cargo_crystal >= cargo_capacity or (not is_instance_valid(harvest_node)) or (is_instance_valid(harvest_node) and harvest_node.amount <= 0 and cargo_metal + cargo_crystal > 0):
		var refinery = _find_nearest_refinery()
		if not refinery:
			velocity.x = 0.0
			velocity.z = 0.0
			return
		if _steer_towards(refinery.global_position, delta, 4.5):
			emit_signal("resources_delivered", team, cargo_metal, cargo_crystal)
			cargo_metal = 0
			cargo_crystal = 0
			_update_hp_bar()
			order = OrderType.IDLE
		return

	if not is_instance_valid(harvest_node) or harvest_node.amount <= 0:
		order = OrderType.IDLE
		return

	# Drive to the node, then extract over time
	if _steer_towards(harvest_node.global_position, delta, 3.0):
		harvest_timer += delta
		if harvest_timer >= HARVEST_TIME:
			harvest_timer = 0.0
			var want = cargo_capacity - (cargo_metal + cargo_crystal)
			var got = harvest_node.harvest(min(25, want))
			if harvest_node.resource_type == "crystal":
				cargo_crystal += got
			else:
				cargo_metal += got
			_update_hp_bar()

func _find_nearest_refinery() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.is_dead and b.team == team and b.kind in ["refinery", "hq"]:
			var d = global_position.distance_to(b.global_position)
			if d < best_dist:
				best = b
				best_dist = d
	return best

# --- Damage model (mirrors player_vehicle.gd) ---

func get_active_modules() -> Array:
	var list = []
	if is_instance_valid(hull_node):
		for child in hull_node.get_children():
			if child.has_meta("module_data") and not child.is_queued_for_deletion():
				list.append(child)
	return list

# --- Flanking (Armor phase 5) ---

const FACET_NORMALS = {
	"front": Vector3(0, 0, -1),
	"back": Vector3(0, 0, 1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
}

# Duck-typed: works for both battle_unit.gd (hull_node) and building.gd
# (defense_hull) targets, whichever the attack_target happens to be.
func _get_target_hull(target: Node3D) -> Node3D:
	if "hull_node" in target and is_instance_valid(target.hull_node):
		return target.hull_node
	if "defense_hull" in target and is_instance_valid(target.defense_hull):
		return target.defense_hull
	return null

# Estimates each of the 4 horizontal facets' effective kinetic threshold
# (hull baseline, or a covering plate's own material+HP bonus if one
# exists - same resolution DamageResolver would use for a real hit) and
# returns the WORLD-space direction of the weakest one. Top/bottom are
# deliberately excluded - not meaningful to "approach from above" with
# ground-based steering.
func _weakest_facet_normal(target: Node3D) -> Vector3:
	var hull = _get_target_hull(target)
	if not hull:
		return Vector3.ZERO

	var hull_mat = hull.get_meta("armor_material") if hull.has_meta("armor_material") else "hardened_steel"
	var hull_thick = hull.get_meta("armor_thickness") if hull.has_meta("armor_thickness") else 1.0
	var baseline = DamageResolverScript.get_material_threshold(hull_mat, "kinetic", hull_thick).x

	var target_modules = []
	if target.has_method("get_active_modules"):
		target_modules = target.get_active_modules()

	var best_facet = "front"
	var best_threshold = INF
	for facet in FACET_NORMALS.keys():
		var t = baseline
		for m in target_modules:
			if not m.has_meta("module_data"): continue
			var m_data = m.get_meta("module_data")
			if m_data.category == "armor" and m.get_meta("facet", "") == facet:
				var plate_mat = m_data.tweaks.get("material", "") if "tweaks" in m_data else ""
				if plate_mat != "":
					t = DamageResolverScript.get_material_threshold(plate_mat, "kinetic", 1.0).x
				t += m_data.get_hp() * 0.1
				break
		if t < best_threshold:
			best_threshold = t
			best_facet = facet

	return FACET_NORMALS[best_facet]

func _compute_flank_point(target: Node3D) -> Vector3:
	var weak_normal_local = _weakest_facet_normal(target)
	if weak_normal_local == Vector3.ZERO:
		return target.global_position
	var world_normal = (target.global_transform.basis * weak_normal_local).normalized()
	return target.global_position + world_normal * (attack_range * 0.8)

func take_damage(amount: float, damage_type: String = "kinetic", hit_origin = null):
	if is_dead: return

	var active_modules = get_active_modules()
	var resolved = DamageResolverScript.resolve(hull_node, active_modules, damage_type, self, hit_origin)
	var threshold = resolved.x
	var reduction = resolved.y

	# Subsystem stripping: 35% of hits land on an exposed module
	if not active_modules.is_empty() and randf() < 0.35:
		var target_module = active_modules.pick_random()
		var m_data = target_module.get_meta("module_data")
		var m_hp = target_module.get_meta("current_hp") if target_module.has_meta("current_hp") else m_data.get_hp()
		var final_mod_damage = max(0.0, amount - 5.0)
		m_hp = max(0.0, m_hp - final_mod_damage)
		target_module.set_meta("current_hp", m_hp)
		if m_hp <= 0.0:
			_spawn_explosion(target_module.global_position, 0.5)
			if target_module.has_meta("mirrored_counterpart"):
				var mirror = target_module.get_meta("mirrored_counterpart")
				if is_instance_valid(mirror):
					mirror.remove_meta("mirrored_counterpart")
			var was_locomotion = m_data.category == "locomotion"
			target_module.queue_free()
			if was_locomotion:
				call_deferred("_recalculate_move_speed")
		return

	if amount < threshold:
		_flash_shield()
		return

	hp = max(0.0, hp - amount * reduction)
	_update_hp_bar()
	_flash_hull()
	if hp <= 0.0:
		die()

func _flash_shield():
	var exp_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	exp_mesh.mesh = sphere
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.4)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(0.2, 0.6, 1.0)
	exp_mesh.material_override = flash_mat
	add_child(exp_mesh)
	exp_mesh.position = Vector3(0, 0.5, 0)
	var tween = create_tween()
	tween.tween_property(exp_mesh, "scale", Vector3.ZERO, 0.1)
	tween.finished.connect(func(): exp_mesh.queue_free())

func _flash_hull():
	if not is_instance_valid(hull_node): return
	var mesh_inst = hull_node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_inst and mesh_inst.material_override:
		var mat_over = mesh_inst.material_override as StandardMaterial3D
		var prev_color = mat_over.albedo_color
		mat_over.albedo_color = Color.RED
		get_tree().create_timer(0.12).timeout.connect(func():
			if is_instance_valid(mat_over):
				mat_over.albedo_color = prev_color
		)

func _spawn_explosion(pos: Vector3, size: float):
	var scene = get_tree().current_scene
	if not scene: scene = get_parent()
	if not scene: return
	for i in range(6):
		var particle = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.2, 0.2, 0.2) * size
		particle.mesh = box
		var p_mat = StandardMaterial3D.new()
		p_mat.albedo_color = Color.RED.lerp(Color.YELLOW, randf())
		p_mat.emission_enabled = true
		p_mat.emission = p_mat.albedo_color
		particle.material_override = p_mat
		scene.add_child(particle)
		particle.global_position = pos
		var dir = Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-2, 2)).normalized()
		var tween_p = create_tween()
		tween_p.tween_property(particle, "global_position", pos + dir * 4.0 * size, 0.6)
		tween_p.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.6)
		tween_p.finished.connect(func(): particle.queue_free())

func die():
	if is_dead: return
	is_dead = true
	remove_from_group("damageable")
	collision_layer = 0
	_spawn_explosion(global_position, 1.5)
	emit_signal("died", self)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	tween.finished.connect(func(): queue_free())
