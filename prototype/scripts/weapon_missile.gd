extends Node3D
const MunitionPool = preload("res://scripts/munition_pool.gd")
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

# Smoke lock-break (ammo pass). A guided round's counter used to be point
# defense and nothing else - it could not miss from target speed by design
# (ModuleCatalog.MISS_SPEED_FACTOR gives "guided" a factor of 0.0), so
# there was no counter available to a player without PD mounted. Obscurant
# ammo now provides one: a seeker that loses sight of its target keeps
# flying on its last known heading and goes dumb, rather than tracking
# through the cloud. Deliberately a POINT test on the target rather than a
# raycast along the flight path - a seeker cares whether it can still see
# what it locked onto, not whether some unrelated cloud sits off to one side.
const SmokeVolume = preload("res://scripts/smoke_volume.gd")
const LOCK_BREAK_GRACE: float = 0.35 # brief blindness is survivable; a real screen isn't
const DUMB_FLIGHT_TIME: float = 1.6

var _obscured_for: float = 0.0
var _lock_broken: bool = false
var _dumb_time: float = 0.0
var _dumb_heading: Vector3 = Vector3.ZERO

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
	body.mesh = MunitionPool.unit_cylinder()
	body.scale = Vector3(0.12, 0.35, 0.12)
	body.material_override = MunitionPool.albedo(Color.DARK_SLATE_GRAY)
	add_child(body)
	body.rotate_x(PI / 2)

	var nose = MeshInstance3D.new()
	# top_radius 0.0 over bottom 0.06 - a true cone, so taper ratio 0.
	nose.mesh = MunitionPool.unit_taper(0.0)
	nose.scale = Vector3(0.12, 0.12, 0.12)
	nose.material_override = MunitionPool.emissive(Color.RED, Color.RED)
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
	smoke.mesh = MunitionPool.unit_sphere()
	smoke.scale = Vector3(0.16, 0.16, 0.16)
	smoke.material_override = MunitionPool.alpha(Color(0.6, 0.6, 0.6, 0.5))
	(get_tree().current_scene if get_tree().current_scene != null else get_tree().root).add_child(smoke)
	smoke.global_position = global_position - global_transform.basis.z * 0.2
	var st = create_tween()
	st.tween_property(smoke, "scale", Vector3.ZERO, 0.25)
	st.finished.connect(func(): if is_instance_valid(smoke): smoke.queue_free())

func _physics_process(delta):
	if is_destroyed: return

	# Gone dumb (lock broken by smoke): coast on the last heading, then
	# self-destruct. It can still be shot down by PD during this, and it
	# still explodes - it just isn't aimed at anything any more.
	if _lock_broken:
		_dumb_time += delta
		global_position += _dumb_heading * speed * delta
		if _dumb_time >= DUMB_FLIGHT_TIME:
			_spawn_impact_visual()
			destroy_missile(false)
		return

	if not is_instance_valid(target) or ("is_dead" in target and target.is_dead):
		destroy_missile(false)
		return

	# Seeker check: sustained obscurement of the target breaks the lock.
	if SmokeVolume.is_point_obscured(get_tree(), target.global_position):
		_obscured_for += delta
		if _obscured_for >= LOCK_BREAK_GRACE:
			_lock_broken = true
			_dumb_heading = -global_transform.basis.z.normalized()
			if _dumb_heading.length_squared() < 0.5:
				_dumb_heading = Vector3.FORWARD
			return
	else:
		_obscured_for = 0.0

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
	var eff_speed = speed * 1.35 if (target and target.has_meta("is_laser_painted") and target.get_meta("is_laser_painted")) else speed
	global_position += dir * eff_speed * delta

	if _phase == 1 and global_position.distance_to(target.global_position + Vector3(0, 0.5, 0)) < 1.1:
		# Warhead payload effects (smoke/incendiary/illumination ammo) land
		# at the impact point, same as a shell's would - the launcher owns
		# the ammo profile, so this defers to it. Guarded on the launcher
		# still existing; if it died mid-flight the warhead just does its
		# damage, which is the same fallback the damage path below uses.
		if is_instance_valid(owner_weapon) and owner_weapon.has_method("_apply_ammo_impact"):
			owner_weapon._apply_ammo_impact(global_position)
		if is_instance_valid(owner_weapon) and owner_weapon.has_method("_deal_weapon_damage"):
			owner_weapon._deal_weapon_damage(target, damage_amount)
		elif target.has_method("take_damage"):
			target.take_damage(damage_amount, damage_class, global_position)
		_spawn_impact_visual()
		destroy_missile(false)

func _spawn_impact_visual():
	if not is_inside_tree(): return
	var exp = MeshInstance3D.new()
	exp.mesh = MunitionPool.unit_sphere()
	exp.scale = Vector3(1.4, 1.4, 1.4)
	exp.material_override = MunitionPool.emissive(Color.ORANGE, Color.ORANGE)
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
		exp.mesh = MunitionPool.unit_sphere()
		var exp_color = Color.CYAN if intercepted else Color.ORANGE
		exp.material_override = MunitionPool.emissive(exp_color, exp_color)
		(get_tree().current_scene if get_tree().current_scene != null else get_tree().root).add_child(exp)
		exp.global_position = global_position
		var tween = exp.create_tween()
		tween.tween_property(exp, "scale", Vector3.ZERO, 0.15)
		tween.finished.connect(func(): if is_instance_valid(exp): exp.queue_free())
	queue_free()
