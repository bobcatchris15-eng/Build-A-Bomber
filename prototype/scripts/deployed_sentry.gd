extends StaticBody3D
# An autonomous turret dropped by the sentry_deployer.
#
# Modelled on proximity_mine.gd's shape rather than on a module: it has to
# outlive the vehicle that placed it, so it owns its whole lifecycle - its own
# timer, its own target scan, its own expiry - and never reaches back into its
# deployer. A sentry whose owner has been destroyed keeps shooting, which is
# the entire point of deploying one.
#
# It is a StaticBody3D on the BUILDINGS layer (8), not the modules layer:
# once on the ground it is a thing in the world that can be shot, walked
# around and targeted, exactly like a defensive structure. Putting it on the
# module layer would have made it part of a vehicle it is not attached to.

const MunitionPool = preload("res://scripts/munition_pool.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

const SENTRY_LAYER := 8
const SENTRY_LIFETIME := 75.0
const SENTRY_HP := 90.0
const SCAN_INTERVAL := 0.35
const FIRE_INTERVAL := 0.55
const DEPLOY_TIME := 1.2

var team: int = -1
var damage_per_shot: float = 12.0
var engage_range: float = 12.0
var is_dead: bool = false

var _age: float = 0.0
var _scan_timer: float = 0.0
var _fire_timer: float = 0.0
var _deploy_timer: float = 0.0
var _hp: float = SENTRY_HP
var _target: Node3D = null
var _turret: Node3D = null

static func spawn(parent: Node, pos: Vector3, sentry_team: int, dmg: float, rng: float) -> Node:
	var s = StaticBody3D.new()
	s.set_script(preload("res://scripts/deployed_sentry.gd"))
	s.team = sentry_team
	s.damage_per_shot = dmg
	s.engage_range = rng
	parent.add_child(s)
	s.global_position = pos
	return s

func _ready():
	add_to_group("damageable")
	add_to_group("targets")
	set_meta("team", team)
	collision_layer = SENTRY_LAYER
	collision_mask = 0

	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.5, 0.45, 0.5)
	shape.shape = box
	shape.position = Vector3(0, 0.22, 0)
	add_child(shape)

	# Uses the SAME authored mesh the deployer carries in its rack, so what
	# you see loaded is what you get on the ground.
	_turret = Node3D.new()
	add_child(_turret)
	var mesh = MeshAssetLoader.get_part_mesh("sentry_turret")
	var mi = MeshInstance3D.new()
	if mesh:
		mi.mesh = mesh
	else:
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.35, 0.3, 0.45)
		mi.mesh = box_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.27, 0.29, 0.24)
	mat.metallic = 0.5
	mat.roughness = 0.52
	mi.material_override = mat
	_turret.add_child(mi)

	# Starts folded and unfolds - a beat of vulnerability after it lands.
	_turret.scale = Vector3(1.0, 0.25, 1.0)

func take_damage(amount: float, _damage_type: String = "explosive", _hit_origin = null):
	if is_dead: return
	_hp -= amount
	if _hp <= 0.0:
		_destroy()

func _destroy():
	if is_dead: return
	is_dead = true
	var parent = get_tree().current_scene if get_tree() and get_tree().current_scene else get_parent()
	if parent and is_inside_tree():
		var burst = MeshInstance3D.new()
		burst.mesh = MunitionPool.unit_sphere()
		burst.material_override = MunitionPool.emissive(Color.ORANGE, Color.ORANGE)
		parent.add_child(burst)
		burst.global_position = global_position
		var t = burst.create_tween()
		t.tween_property(burst, "scale", Vector3.ZERO, 0.2)
		t.finished.connect(func(): if is_instance_valid(burst): burst.queue_free())
	queue_free()

func _physics_process(delta):
	if is_dead: return
	_age += delta
	if _age >= SENTRY_LIFETIME:
		_destroy()
		return

	if _deploy_timer < DEPLOY_TIME:
		_deploy_timer += delta
		var t = clampf(_deploy_timer / DEPLOY_TIME, 0.0, 1.0)
		if _turret:
			_turret.scale = Vector3(1.0, lerpf(0.25, 1.0, t), 1.0)
		return

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_acquire()

	if not is_instance_valid(_target):
		return

	if _turret:
		var to_t = _target.global_position - global_position
		to_t.y = 0.0
		if to_t.length_squared() > 0.01:
			_turret.rotation.y = atan2(-to_t.x, -to_t.z)

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = FIRE_INTERVAL
		_shoot()

func _acquire():
	_target = null
	var best := engage_range * engage_range
	for c in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(c) or c == self:
			continue
		if "is_dead" in c and c.is_dead:
			continue
		if c.has_meta("team") and team != -1 and c.get_meta("team") == team:
			continue
		if not (c is Node3D):
			continue
		var d = global_position.distance_squared_to((c as Node3D).global_position)
		if d < best:
			best = d
			_target = c

func _shoot():
	if not is_instance_valid(_target):
		return
	var parent = get_tree().current_scene if get_tree() and get_tree().current_scene else get_parent()
	if parent:
		var tracer = MeshInstance3D.new()
		tracer.mesh = MunitionPool.unit_cylinder()
		tracer.material_override = MunitionPool.emissive(Color(1.0, 0.85, 0.5), Color(1.0, 0.7, 0.3))
		parent.add_child(tracer)
		MunitionPool.aim_beam(tracer, global_position + Vector3(0, 0.3, 0), _target.global_position, 0.04)
		var t = tracer.create_tween()
		t.tween_property(tracer, "scale", Vector3(0.005, tracer.scale.y, 0.005), 0.12)
		t.finished.connect(func(): if is_instance_valid(tracer): tracer.queue_free())
	if _target.has_method("take_damage"):
		_target.take_damage(damage_per_shot, "kinetic", global_position)
