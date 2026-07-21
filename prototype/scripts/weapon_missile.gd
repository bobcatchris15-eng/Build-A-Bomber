extends Node3D
# Real, interceptable weapon missile (FABLE_REVIEW.md 2.2). Fired by
# guided_missile / dual_stage_missile / missile_pod instead of the old
# cosmetic tweened meshes - those never registered in the "missiles" group,
# so point defense had literally nothing to intercept in a real Skirmish
# (only the Test Range's incoming_missile and drone_carrier drones were
# real). Modeled on incoming_missile.gd's shape: own _physics_process,
# "missiles" group + team meta for PD targeting, destroy_missile()
# interception contract, queue_free() lifecycle.
#
# Damage on arrival is routed back through the firing weapon's own
# _deal_weapon_damage() funnel when it still exists (keeps hit-origin
# flattening and any future funnel rules consistent); falls back to a plain
# take_damage if the launcher died mid-flight - the missile is already in
# the air, its warhead doesn't care.

var target: Node3D = null
var owner_weapon: Node3D = null
var damage_amount: float = 20.0
var damage_class: String = "explosive"
var team: int = -1
var speed: float = 16.0
var is_top_attack: bool = false
var salvo_jitter: float = 0.0 # missile_pod: sideways weave so a salvo reads as a swarm
var is_destroyed: bool = false

var _climb_target_y: float = 0.0
var _phase: int = 0 # 0 = climb (top-attack only), 1 = terminal
var _weave_seed: float = 0.0

func setup(missile_target: Node3D, weapon: Node3D, dmg: float, dclass: String, missile_team: int):
	target = missile_target
	owner_weapon = weapon
	damage_amount = dmg
	damage_class = dclass
	team = missile_team
	set_meta("team", team)

func _ready():
	add_to_group("missiles")
	set_meta("team", team)
	_weave_seed = randf() * TAU
	_phase = 0 if is_top_attack else 1
	_climb_target_y = global_position.y + 9.0

	# Visual: slim body + glowing nose cone (same read as the old cosmetic
	# missile, now attached to a real entity)
	var body = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 0.35
	body.mesh = cyl
	var bmat = StandardMaterial3D.new()
	bmat.albedo_color = Color.DARK_SLATE_GRAY
	body.material_override = bmat
	add_child(body)
	body.rotate_x(PI / 2)

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
	add_child(nose)
	nose.position = Vector3(0, 0, -0.23)
	nose.rotate_x(-PI / 2)

	# Smoke trail
	var trail_timer = Timer.new()
	trail_timer.wait_time = 0.05
	trail_timer.autostart = true
	add_child(trail_timer)
	trail_timer.timeout.connect(_spawn_trail_puff)

func _spawn_trail_puff():
	if is_destroyed or not is_inside_tree(): return
	var smoke = MeshInstance3D.new()
	var sph = SphereMesh.new()
	sph.radius = 0.08
	sph.height = 0.16
	smoke.mesh = sph
	var smat = StandardMaterial3D.new()
	smat.albedo_color = Color(0.6, 0.6, 0.6, 0.5)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.material_override = smat
	(get_tree().current_scene if get_tree().current_scene != null else get_tree().root).add_child(smoke)
	smoke.global_position = global_position - global_transform.basis.z * 0.2
	var st = create_tween()
	st.tween_property(smoke, "scale", Vector3.ZERO, 0.25)
	st.finished.connect(func(): if is_instance_valid(smoke): smoke.queue_free())

func _physics_process(delta):
	if is_destroyed: return
	if not is_instance_valid(target) or ("is_dead" in target and target.is_dead):
		destroy_missile(false)
		return

	var dest: Vector3
	if _phase == 0:
		# Top-attack climb phase: straight up over the launch point, then dive
		dest = Vector3(global_position.x, _climb_target_y, global_position.z)
		if global_position.y >= _climb_target_y - 0.3:
			_phase = 1
			return
	else:
		dest = target.global_position + Vector3(0, 0.5, 0)
		if salvo_jitter > 0.0:
			# A little sinusoidal weave, decaying near impact so it still hits
			var dist = global_position.distance_to(dest)
			var weave = sin(Time.get_ticks_msec() / 1000.0 * 6.0 + _weave_seed)
			dest += Vector3(weave, 0.3 * weave, 0).rotated(Vector3.UP, _weave_seed) * salvo_jitter * clamp(dist / 8.0, 0.0, 1.0)

	if global_position.distance_to(dest) > 0.05:
		look_at(dest, Vector3.UP)
	var dir = (dest - global_position).normalized()
	global_position += dir * speed * delta

	if _phase == 1 and global_position.distance_to(target.global_position + Vector3(0, 0.5, 0)) < 1.1:
		if is_instance_valid(owner_weapon) and owner_weapon.has_method("_deal_weapon_damage"):
			owner_weapon._deal_weapon_damage(target, damage_amount)
		elif target.has_method("take_damage"):
			target.take_damage(damage_amount, damage_class, global_position)
		_spawn_impact_visual()
		destroy_missile(false)

func _spawn_impact_visual():
	if not is_inside_tree(): return
	var exp = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.4
	exp.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.ORANGE
	mat.emission_enabled = true
	mat.emission = Color.ORANGE
	exp.material_override = mat
	(get_tree().current_scene if get_tree().current_scene != null else get_tree().root).add_child(exp)
	exp.global_position = global_position
	var tween = exp.create_tween()
	tween.tween_property(exp, "scale", Vector3.ZERO, 0.15)
	tween.finished.connect(func(): if is_instance_valid(exp): exp.queue_free())

# Interception contract, same as incoming_missile.gd - PD calls this.
func destroy_missile(intercepted: bool):
	if is_destroyed: return
	is_destroyed = true
	if is_inside_tree():
		var exp = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		exp.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.CYAN if intercepted else Color.ORANGE
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		exp.material_override = mat
		(get_tree().current_scene if get_tree().current_scene != null else get_tree().root).add_child(exp)
		exp.global_position = global_position
		var tween = exp.create_tween()
		tween.tween_property(exp, "scale", Vector3.ZERO, 0.15)
		tween.finished.connect(func(): if is_instance_valid(exp): exp.queue_free())
	queue_free()
