extends Node3D
# A real autonomous drone launched by a drone_carrier weapon - independent
# physics-driven flight and its own launch/attack/return state machine.
# Previously drone_carrier's "_fire_drone_swarm()" just tweened two
# throwaway MeshInstance3D prisms with damage applied in a tween callback -
# no persistent entity, no independent AI. Modeled on incoming_missile.gd's
# shape instead (own _physics_process, group self-registration so
# point-defense can shoot it down like any other projectile, self-managed
# lifecycle) rather than inventing a new pattern.

enum State { LAUNCH, ATTACK, RETURN }

var carrier: Node3D = null
var target: Node3D = null
var speed: float = 14.0
var damage_per_hit: float = 20.0
var damage_class: String = "kinetic"
var team: int = -1
var state: State = State.LAUNCH
var is_destroyed: bool = false
var attack_timer: float = 0.0
const ATTACK_LINGER: float = 0.35 # brief strafing loiter before returning, visual only
const RETURN_TIMEOUT: float = 8.0
var return_timer: float = 0.0

func _ready():
	add_to_group("missiles") # reuses existing point-defense interception logic (CIWS/pd_laser/flak_cannon already scan this group)
	set_meta("team", team)

	var mesh_inst = MeshInstance3D.new()
	var prism = PrismMesh.new()
	prism.size = Vector3(0.22, 0.1, 0.22)
	mesh_inst.mesh = prism
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.NAVY_BLUE
	mat.emission_enabled = true
	mat.emission = Color.CYAN
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func _physics_process(delta):
	if is_destroyed: return
	match state:
		State.LAUNCH:
			if not is_instance_valid(target) or ("is_dead" in target and target.is_dead):
				state = State.RETURN
				return
			_fly_toward(target.global_position + Vector3(0, 1.0, 0), delta)
			if global_position.distance_to(target.global_position) < 2.0:
				# Single lump-sum hit on arrival, matching every other
				# weapon's one-take_damage-call-per-shot convention - a
				# per-frame damage tick here would roll subsystem-stripping
				# dozens of times per attack pass instead of once.
				if is_instance_valid(target) and target.has_method("take_damage"):
					target.take_damage(damage_per_hit, damage_class, global_position)
				state = State.ATTACK
				attack_timer = 0.0
		State.ATTACK:
			attack_timer += delta
			if attack_timer >= ATTACK_LINGER:
				state = State.RETURN
		State.RETURN:
			return_timer += delta
			if not is_instance_valid(carrier) or return_timer > RETURN_TIMEOUT:
				destroy_missile(false)
				return
			_fly_toward(carrier.global_position, delta)
			if global_position.distance_to(carrier.global_position) < 1.5:
				destroy_missile(false)

func _fly_toward(dest: Vector3, delta: float):
	var dir = dest - global_position
	if dir.length() > 0.05:
		look_at(dest, Vector3.UP)
		global_position += dir.normalized() * speed * delta

# Duck-typed the same way incoming_missile.gd's is - auto_weapon.gd's
# point-defense code calls this unconditionally (guarded by has_method)
# when a PD weapon shoots a drone down mid-flight.
func destroy_missile(intercepted: bool):
	if is_destroyed: return
	is_destroyed = true
	var exp = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	exp.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.ORANGE if not intercepted else Color.CYAN
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	exp.material_override = mat
	var scene = get_tree().current_scene
	if not scene: scene = get_parent()
	if scene: scene.add_child(exp)
	exp.global_position = global_position
	var tween = create_tween()
	tween.tween_property(exp, "scale", Vector3.ZERO, 0.15)
	tween.finished.connect(func(): if is_instance_valid(exp): exp.queue_free())
	queue_free()
