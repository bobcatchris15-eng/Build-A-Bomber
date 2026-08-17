extends StaticBody3D
const Profiler = preload("res://scripts/battle/battle_profiler.gd")
# A false contact deployed by decoy_projector: an inflatable/holographic
# vehicle silhouette that draws enemy fire.
#
# WHY THIS NEEDS NO AI CHANGES
# ---------------------------------------------------------------------------
# Target selection across this codebase - auto_weapon's _find_nearest_target,
# enemy_ai, the sentry above - all scan the "damageable" and "targets" groups
# and filter by the "team" meta. A decoy joins exactly those groups with the
# owning team's number, so every existing scanner picks it up as an enemy
# without knowing decoys exist. That is the whole trick, and it is why this
# was cheap: the deception is implemented in the same place the game already
# decides what is shootable, rather than as a special case bolted onto each
# shooter.
#
# It takes damage normally and pops when killed, so shots spent on it are
# genuinely wasted rather than being absorbed forever. Low HP on purpose -
# it should not be a shield, only a distraction.

const MunitionPool = preload("res://scripts/munition_pool.gd")

const DECOY_LAYER := 8
const DECOY_LIFETIME := 30.0
const DECOY_HP := 40.0
const INFLATE_TIME := 0.8

var team: int = -1
var is_dead: bool = false

var _age: float = 0.0
var _hp: float = DECOY_HP
var _inflate: float = 0.0
var _shell: Node3D = null

static func spawn(parent: Node, pos: Vector3, decoy_team: int) -> Node:
	var d = StaticBody3D.new()
	d.set_script(preload("res://scripts/decoy_contact.gd"))
	d.team = decoy_team
	parent.add_child(d)
	d.global_position = pos
	return d

func _ready():
	add_to_group("damageable")
	add_to_group("targets")
	set_meta("team", team)
	set_meta("is_decoy", true)
	collision_layer = DECOY_LAYER
	collision_mask = 0

	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1.6, 0.9, 2.4)
	shape.shape = box
	shape.position = Vector3(0, 0.45, 0)
	add_child(shape)

	# A crude vehicle silhouette. Deliberately crude: it is a balloon, and at
	# any real distance a balloon of roughly the right shape is enough.
	_shell = Node3D.new()
	add_child(_shell)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.40, 0.33)
	mat.metallic = 0.05
	mat.roughness = 0.85
	var hull = MeshInstance3D.new()
	var hb = BoxMesh.new()
	hb.size = Vector3(1.5, 0.6, 2.3)
	hull.mesh = hb
	hull.material_override = mat
	hull.position = Vector3(0, 0.35, 0)
	_shell.add_child(hull)
	var turret = MeshInstance3D.new()
	var tb = BoxMesh.new()
	tb.size = Vector3(0.9, 0.45, 1.0)
	turret.mesh = tb
	turret.material_override = mat
	turret.position = Vector3(0, 0.85, -0.1)
	_shell.add_child(turret)
	var barrel = MeshInstance3D.new()
	barrel.mesh = MunitionPool.unit_cylinder()
	barrel.scale = Vector3(0.11, 0.7, 0.11)
	barrel.material_override = mat
	barrel.position = Vector3(0, 0.9, -1.0)
	barrel.rotate_x(PI / 2.0)
	_shell.add_child(barrel)

	_shell.scale = Vector3(0.2, 0.05, 0.2)

func take_damage(amount: float, _damage_type: String = "explosive", _hit_origin = null):
	if is_dead: return
	_hp -= amount
	if _hp <= 0.0:
		_pop()

func _pop():
	if is_dead: return
	is_dead = true
	var parent = get_tree().current_scene if get_tree() and get_tree().current_scene else get_parent()
	if parent and is_inside_tree():
		# Deflates rather than explodes - the reveal is meant to be a little
		# humiliating for whoever just spent a shell on it.
		for i in range(6):
			var rag = MeshInstance3D.new()
			rag.mesh = MunitionPool.unit_sphere()
			rag.material_override = MunitionPool.alpha(Color(0.38, 0.40, 0.33, 0.7))
			parent.add_child(rag)
			rag.global_position = global_position + Vector3(0, 0.5, 0)
			rag.scale = Vector3.ONE * 0.3
			var dir = Vector3(randf_range(-1, 1), randf_range(0.1, 0.6), randf_range(-1, 1)).normalized()
			var t = rag.create_tween()
			t.tween_property(rag, "global_position", rag.global_position + dir * 1.2, 0.5)
			t.parallel().tween_property(rag, "scale", Vector3.ZERO, 0.5)
			t.finished.connect(func(): if is_instance_valid(rag): rag.queue_free())
	queue_free()

func _physics_process(delta):
	if is_dead: return
	var _p := Profiler.start()
	_age += delta
	if _age >= DECOY_LIFETIME:
		_pop()
		Profiler.stop("decoys", _p)
		return
	if _inflate < INFLATE_TIME:
		_inflate += delta
		var t = clampf(_inflate / INFLATE_TIME, 0.0, 1.0)
		if _shell:
			_shell.scale = Vector3(lerpf(0.2, 1.0, t), lerpf(0.05, 1.0, t), lerpf(0.2, 1.0, t))
	Profiler.stop("decoys", _p)
