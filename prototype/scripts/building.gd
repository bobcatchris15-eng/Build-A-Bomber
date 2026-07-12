extends StaticBody3D
# Prefab base structures (C&C style) plus custom-designed defensive structures.
# kind: "hq" | "refinery" | "factory" | "defense"

signal died(building)
signal unit_produced(unit)

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")

const PREFAB_STATS = {
	"hq":       {"hp": 3000.0, "size": Vector3(7, 4, 7),  "color": Color(0.75, 0.72, 0.55), "cost_metal": 0,   "cost_crystal": 0},
	"refinery": {"hp": 1200.0, "size": Vector3(5, 3, 5),  "color": Color(0.55, 0.62, 0.75), "cost_metal": 150, "cost_crystal": 0},
	"factory":  {"hp": 1800.0, "size": Vector3(6, 3, 8),  "color": Color(0.72, 0.55, 0.42), "cost_metal": 200, "cost_crystal": 50},
}

var kind: String = "hq"
var team: int = 0
var max_hp: float = 1000.0
var hp: float = 1000.0
var is_dead: bool = false
var faction: String = "industrialists"

# Defense-specific
var defense_hull: Node3D = null
var armor_material: String = "hardened_steel"
var armor_thickness: float = 1.0
# Energy resource (ENERGY_AND_BALANCE_SPEC.md #1) - only meaningful for
# "defense" kind buildings, which are the only kind that can mount weapon
# or generator modules (hq/refinery/factory are fixed prefabs).
var max_energy: float = 0.0
var current_energy: float = 0.0
var energy_regen_rate: float = 0.0

# Factory production queue: array of {blueprint: Dictionary, time_left: float, total_time: float}
var production_queue: Array = []
var rally_point: Vector3 = Vector3.ZERO
var bp_manager: Node = null

var hp_bar: Label3D = null
var selection_ring: MeshInstance3D = null
var footprint: Vector3 = Vector3(5, 3, 5)

func _ready():
	add_to_group("buildings")
	add_to_group("damageable")

func setup_prefab(building_kind: String, building_team: int, building_faction: String = "industrialists"):
	kind = building_kind
	team = building_team
	faction = building_faction
	set_meta("team", team)
	collision_layer = 8
	collision_mask = 0

	var stats = PREFAB_STATS.get(kind, PREFAB_STATS["hq"])
	max_hp = stats.hp
	hp = max_hp
	footprint = stats.size

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var box = BoxMesh.new()
	box.size = stats.size
	mesh_inst.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = stats.color if team == 0 else stats.color.lerp(Color(0.7, 0.2, 0.2), 0.45)
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(0, stats.size.y / 2.0, 0)
	add_child(mesh_inst)

	# Simple identifying rooftop detail so prefabs read differently at a glance
	var detail = MeshInstance3D.new()
	var dmat = StandardMaterial3D.new()
	dmat.albedo_color = Color(0.2, 0.9, 0.9) if team == 0 else Color(1.0, 0.35, 0.2)
	dmat.emission_enabled = true
	dmat.emission = dmat.albedo_color
	detail.material_override = dmat
	match kind:
		"hq":
			var antenna = CylinderMesh.new()
			antenna.top_radius = 0.08
			antenna.bottom_radius = 0.08
			antenna.height = 3.0
			detail.mesh = antenna
			detail.position = Vector3(0, stats.size.y + 1.5, 0)
		"refinery":
			var silo = CylinderMesh.new()
			silo.top_radius = 1.0
			silo.bottom_radius = 1.0
			silo.height = 1.5
			detail.mesh = silo
			detail.position = Vector3(1.2, stats.size.y + 0.75, 1.2)
		"factory":
			var vent = BoxMesh.new()
			vent.size = Vector3(4.0, 0.6, 1.2)
			detail.mesh = vent
			detail.position = Vector3(0, stats.size.y + 0.3, 0)
	add_child(detail)

	var col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = stats.size
	col.shape = col_box
	col.position = Vector3(0, stats.size.y / 2.0, 0)
	add_child(col)

	_create_hp_bar(stats.size.y + 2.2)
	_create_selection_ring(max(stats.size.x, stats.size.z) * 0.72)
	rally_point = global_position + Vector3(0, 0, 10 if team == 0 else -10)

func setup_defense(blueprint_data: Dictionary, building_team: int, manager: Node):
	kind = "defense"
	team = building_team
	set_meta("team", team)
	collision_layer = 8
	collision_mask = 0
	bp_manager = manager

	defense_hull = manager.reconstruct_vehicle(blueprint_data, self)
	if defense_hull:
		armor_material = defense_hull.get_meta("armor_material") if defense_hull.has_meta("armor_material") else "hardened_steel"
		armor_thickness = defense_hull.get_meta("armor_thickness") if defense_hull.has_meta("armor_thickness") else 1.0
		var hull_type = defense_hull.get_meta("type_id") if defense_hull.has_meta("type_id") else "pillbox_foundation"
		var catalog_data = ModuleCatalog.get_module_data(hull_type)
		var mat_mult = 1.0
		if armor_material == "reactive_armor": mat_mult = 1.3
		elif armor_material == "ablative_ceramic": mat_mult = 1.6
		elif armor_material == "energy_shielding": mat_mult = 2.0
		max_hp = catalog_data.hp * armor_thickness * mat_mult
		hp = max_hp
		footprint = catalog_data.size

		var col = CollisionShape3D.new()
		var col_box = BoxShape3D.new()
		var base_size = catalog_data.size
		if defense_hull.has_meta("base_hull_size") and defense_hull.has_meta("hull_scale"):
			base_size = defense_hull.get_meta("base_hull_size") * defense_hull.get_meta("hull_scale")
		col_box.size = base_size
		col.shape = col_box
		col.position = Vector3(0, base_size.y / 2.0, 0)
		add_child(col)

		# Arm the weapons
		for child in defense_hull.get_children():
			if child.has_meta("module_data"):
				var data = child.get_meta("module_data")
				if data.category == "weapon":
					var weapon_script = load("res://scripts/auto_weapon.gd")
					child.set_script(weapon_script)
					child.set_physics_process(true)
					child._ready()

		var bonus_capacity = 0.0
		var bonus_regen = 0.0
		for child in defense_hull.get_children():
			if child.has_meta("module_data") and not child.is_queued_for_deletion():
				var gen_data = child.get_meta("module_data")
				if gen_data.category == "generator":
					bonus_capacity += gen_data.get_energy_capacity()
					bonus_regen += gen_data.get_energy_regen()
		max_energy = ModuleCatalog.get_base_energy(hull_type) + bonus_capacity
		current_energy = max_energy
		energy_regen_rate = max_energy * 0.08 + bonus_regen

		_create_hp_bar(base_size.y + 2.0)
		_create_selection_ring(max(base_size.x, base_size.z) * 0.72)

func _create_hp_bar(height: float):
	hp_bar = Label3D.new()
	hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_bar.font_size = 24
	hp_bar.outline_size = 5
	hp_bar.position = Vector3(0, height, 0)
	add_child(hp_bar)
	_update_hp_bar()

func _create_selection_ring(radius: float):
	selection_ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = radius - 0.14
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

func set_selected(selected: bool):
	if is_instance_valid(selection_ring):
		selection_ring.visible = selected

func _update_hp_bar():
	if not is_instance_valid(hp_bar): return
	var pct = clamp(hp / max_hp, 0.0, 1.0)
	var filled = int(pct * 10.0)
	var bar = ""
	for i in range(filled): bar += "■"
	for i in range(10 - filled): bar += "□"
	var label_name = kind.to_upper()
	if kind == "factory" and not production_queue.is_empty():
		var job = production_queue[0]
		var job_pct = 1.0 - (job.time_left / job.total_time)
		label_name += " ⚙ %d%%" % int(job_pct * 100)
	hp_bar.text = "%s\n%s" % [label_name, bar]
	hp_bar.modulate = (Color.CYAN if team == 0 else Color.ORANGE_RED).lerp(Color.RED, 1.0 - pct)

func _physics_process(delta):
	if is_dead: return
	if current_energy < max_energy:
		current_energy = min(max_energy, current_energy + energy_regen_rate * delta)
	if kind == "factory" and not production_queue.is_empty():
		var job = production_queue[0]
		job.time_left -= delta
		_update_hp_bar()
		if job.time_left <= 0.0:
			production_queue.pop_front()
			_spawn_unit(job.blueprint)

func queue_unit(blueprint_data: Dictionary, build_time: float):
	production_queue.append({"blueprint": blueprint_data, "time_left": build_time, "total_time": build_time})
	_update_hp_bar()

func _spawn_unit(blueprint_data: Dictionary):
	if not bp_manager or not is_instance_valid(bp_manager): return
	var unit = CharacterBody3D.new()
	unit.set_script(load("res://scripts/battle_unit.gd"))
	get_parent().add_child(unit)
	var exit_offset = Vector3(0, 0.5, footprint.z / 2.0 + 3.0) * (1 if team == 0 else -1)
	exit_offset.y = 0.5
	unit.global_position = global_position + exit_offset
	unit.setup(blueprint_data, team, bp_manager)
	var scene_root = get_parent()
	if scene_root and scene_root.has_method("_on_resources_delivered"):
		unit.resources_delivered.connect(scene_root._on_resources_delivered)
	unit.order_move(rally_point)
	emit_signal("unit_produced", unit)

func get_active_modules() -> Array:
	var list = []
	if is_instance_valid(defense_hull):
		for child in defense_hull.get_children():
			if child.has_meta("module_data") and not child.is_queued_for_deletion():
				list.append(child)
	return list

func take_damage(amount: float, damage_type: String = "kinetic", hit_origin = null):
	if is_dead: return
	var threshold = 5.0
	var reduction = 0.85
	if kind == "defense":
		# Placed armor modules now add the same aggregate bonus here as they
		# do for vehicle hulls (battle_unit.gd/player_vehicle.gd) - defense
		# buildings previously didn't get this at all, a real parity gap
		# found while deduping the armor math into damage_resolver.gd.
		var resolved = DamageResolverScript.resolve(defense_hull, get_active_modules(), damage_type, self, hit_origin)
		threshold = resolved.x
		reduction = resolved.y
	if amount < threshold:
		return
	hp = max(0.0, hp - amount * reduction)
	_update_hp_bar()
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
	_update_hp_bar()

func die():
	if is_dead: return
	is_dead = true
	remove_from_group("damageable")
	collision_layer = 0
	var scene = get_tree().current_scene
	if scene:
		for i in range(14):
			var particle = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.4, 0.4, 0.4)
			particle.mesh = box
			var p_mat = StandardMaterial3D.new()
			p_mat.albedo_color = Color.RED.lerp(Color.YELLOW, randf())
			p_mat.emission_enabled = true
			p_mat.emission = p_mat.albedo_color
			particle.material_override = p_mat
			scene.add_child(particle)
			particle.global_position = global_position + Vector3(0, 1, 0)
			var dir = Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-2, 2)).normalized()
			var tween_p = create_tween()
			tween_p.tween_property(particle, "global_position", particle.global_position + dir * 7.0, 0.9)
			tween_p.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.9)
			tween_p.finished.connect(func(): particle.queue_free())
	emit_signal("died", self)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	tween.finished.connect(func(): queue_free())
