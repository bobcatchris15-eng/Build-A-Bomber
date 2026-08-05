class_name BattleUnitV2
extends CharacterBody3D
# A mobile unit: intent in, movement out.
#
# WHAT THIS DELIBERATELY DOES NOT DO, and where it went instead:
#
#   harvesting        -> economy/harvester_fsm.gd  (Phase 2)
#   target selection  -> ai/squad.gd               (Phase 3)
#   fog visibility    -> vision/vision_service.gd  (Phase 4)
#   physical assembly -> units/unit_assembly.gd
#   movement math     -> movement/steering.gd
#
# The old runtime folded all five into one 1,701-line node, which is why a
# harvester's docking bug and a tank's turning-circle bug lived in the same
# function and were fixed by editing the same lines. This file's whole job is to
# hold the current Order, ask Steering what velocity that implies, and apply it.
#
# NAME. `BattleUnitV2` rather than `BattleUnit` because battle_unit.gd already
# claims that class_name and still runs the old Skirmish scene. The name is
# temporary and goes away with the retirement commit.

const SteeringScript = preload("res://scripts/battle/movement/steering.gd")
const AssemblyScript = preload("res://scripts/battle/units/unit_assembly.gd")
const Drivetrain = preload("res://scripts/drivetrain.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

signal died(unit)
signal order_completed(unit)

# How fast the hull can yaw, radians/sec. Vehicles, not turrets.
const TURN_RATE := 2.6
# Arrival radius floor. Scaled up by speed in _arrive_distance() because a fast
# unit needs a wider capture circle than it travels in one tick, or it sweeps
# past and orbits - the failure the old runtime hit hardest on light designs.
const ARRIVE_DISTANCE_MIN := 2.0
const ARRIVE_DISTANCE_PER_SPEED := 0.12
# Never fully stall while turning: a unit wedged against geometry with zero
# throttle can never rotate its way out.
const MIN_THROTTLE := 0.12
const GRAVITY := 24.0

var team: int = 0
var faction: String = "industrialists"
var hull_node: Node3D = null
var nav_agent: NavigationAgent3D = null

var max_hp: float = 100.0
var hp: float = 100.0
var is_dead: bool = false

var move_speed: float = 0.0
var terrain_speed_multiplier: float = 1.0

var is_flying: bool = false
var is_fixed_wing: bool = false
var is_naval: bool = false
var is_amphibious: bool = false

var locomotion_type: String = ""
var locomotion_settings: Dictionary = {}

# INTENT. One current order plus a queue, which is the whole reason orders are a
# type - see orders/order.gd. Only OrderService writes these.
var current_order: Order = null
var order_queue: Array[Order] = []

var _controller: Node = null
var _selection_ring: MeshInstance3D = null
var _is_selected: bool = false


func _ready() -> void:
	add_to_group("units")
	add_to_group("damageable")


# `controller` is the match director. Passed explicitly rather than read from
# get_parent() so a test can hand in a stub, or nothing at all - with no
# controller the unit falls back to direct-line steering, which is what keeps
# synthetic tests free of a whole navmesh bake.
func setup(blueprint_data: Dictionary, unit_team: int, bp_manager: Node,
		controller: Node = null, match_faction: String = "") -> bool:
	team = unit_team
	_controller = controller

	var facts := AssemblyScript.build(self, blueprint_data, unit_team, bp_manager, match_faction)
	if facts.is_empty():
		# reconstruct_vehicle() returned null - the blueprint names a hull the
		# catalog no longer has. A half-built unit is worse than no unit, so the
		# caller gets a false and decides.
		return false

	hull_node = facts["hull_node"]
	faction = facts["faction"]
	max_hp = facts["max_hp"]
	hp = max_hp
	locomotion_type = facts["locomotion_type"]
	locomotion_settings = facts["locomotion_settings"]
	is_flying = facts["is_flying"]
	is_fixed_wing = facts["is_fixed_wing"]
	is_naval = facts["is_naval"]
	is_amphibious = facts["is_amphibious"]

	nav_agent = AssemblyScript.build_nav_agent(self, facts, controller)
	_sync_nav_radii()
	_recalculate_move_speed()
	_create_selection_ring(facts["base_size"])
	return true


# Speed, weight and overload all come from Drivetrain.analyze() - the same
# function the Design Lab's stat rail calls. They must agree: the number a player
# sizes a drivetrain against in the Lab is the number it moves at in a battle.
# An abbreviated second copy is exactly how the old ones drifted apart.
func _recalculate_move_speed() -> void:
	if not is_instance_valid(hull_node):
		return
	var dt: Dictionary = Drivetrain.analyze(hull_node, locomotion_type, locomotion_settings, is_flying)
	move_speed = dt["top_speed"] if dt["has_locomotion"] else 0.0
	_sync_nav_radii()


func _arrive_distance() -> float:
	return maxf(ARRIVE_DISTANCE_MIN, move_speed * ARRIVE_DISTANCE_PER_SPEED)


# The capture radii cannot be constants. A waypoint counts as reached only once
# the unit is inside path_desired_distance of it; a unit doing 18 m/s turns along
# an arc several metres wide and can sweep past a 1 m circle without ever
# entering it, never advance, and loop back to try the same waypoint again. The
# faster the design, the more certain the miss.
func _sync_nav_radii() -> void:
	if not is_instance_valid(nav_agent):
		return
	nav_agent.target_desired_distance = _arrive_distance()
	nav_agent.path_desired_distance = maxf(1.0, move_speed * 0.06)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_advance_orders()
	_apply_movement(delta)
	_apply_vertical(delta)
	move_and_slide()


# Pops the queue when the current order finishes. Phase 0 only resolves
# destinations; ATTACK and HARVEST completion arrive with the systems that
# execute them.
func _advance_orders() -> void:
	if current_order == null:
		if not order_queue.is_empty():
			current_order = order_queue.pop_front()
		return
	if current_order.is_complete(global_position, _arrive_distance()):
		current_order = order_queue.pop_front() if not order_queue.is_empty() else null
		order_completed.emit(self)


func _apply_movement(delta: float) -> void:
	if current_order == null or not current_order.has_destination() or move_speed <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Where to steer THIS tick: the next path corner if an agent is routing us,
	# the destination itself otherwise. The agent owns the route; steering owns
	# the driving.
	var destination := current_order.position
	var steer_point := destination
	if is_instance_valid(nav_agent):
		if nav_agent.target_position.distance_to(destination) > 0.1:
			nav_agent.target_position = destination
		if not nav_agent.is_navigation_finished():
			steer_point = nav_agent.get_next_path_position()

	var to_point := steer_point - global_position
	to_point.y = 0.0
	if to_point.length() < 0.05:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var current_yaw := rotation.y
	var target_yaw := SteeringScript.yaw_for(to_point, current_yaw)
	rotation.y = SteeringScript.turn_toward(current_yaw, target_yaw, TURN_RATE * delta)

	# Throttle back while badly aimed. Turning radius is r = v / w: at 18 m/s and
	# a 45-degree error a unit needs ~5.7 m to come around, which is wider than
	# any capture radius here - so at full throttle it orbits its destination
	# forever and no amount of repathing helps, because the geometry is wrong
	# rather than the path. Less speed for the same turn rate shrinks the radius
	# until it fits. It is also just how vehicles behave.
	var throttle := maxf(
		SteeringScript.heading_throttle(rotation.y, target_yaw), MIN_THROTTLE)

	# Arrival ramp measured against the REAL destination, not the next corner -
	# braking for every path corner would make the unit crawl the whole route.
	var remaining := Vector3(destination.x - global_position.x, 0.0, destination.z - global_position.z).length()
	var slow_radius := maxf(_arrive_distance() * 2.0, move_speed * 0.45)
	var speed: float = SteeringScript.arrival_speed(remaining, move_speed, slow_radius) \
		* terrain_speed_multiplier * throttle

	var forward := -transform.basis.z.normalized()
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed


# Ground units follow the terrain HEIGHTMAP rather than falling onto it. The
# visual mesh and the sampled height are authoritative (terrain_builder's
# height_at()), and the physics collider is a subdivided approximation of the
# same surface - so resolving height by gravity and is_on_floor() lets a unit
# rest a little above or below where the terrain says it should be, and
# move_and_slide() then spends the rest of the match depenetrating it.
#
# Gravity is the fallback for when no controller can answer.
func _apply_vertical(delta: float) -> void:
	if is_flying or is_fixed_wing:
		velocity.y = 0.0
		return
	if _controller != null and _controller.has_method("terrain_height_at"):
		var target_y: float = _controller.terrain_height_at(global_position)
		global_position.y = target_y
		velocity.y = 0.0
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


# Called by the match director after a navmesh rebake. A NavigationAgent3D does
# not know its cached path corridor might now cut through a building that was
# just placed, so it has to be told to ask again.
func request_repath() -> void:
	if is_instance_valid(nav_agent):
		nav_agent.target_position = global_position


func set_selected(value: bool) -> void:
	_is_selected = value
	if is_instance_valid(_selection_ring):
		_selection_ring.visible = value


func is_selected() -> bool:
	return _is_selected


func _create_selection_ring(base_size: Vector3) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "SelectionRing"
	var torus := TorusMesh.new()
	var radius: float = maxf(base_size.x, base_size.z) * 0.62
	torus.inner_radius = radius
	torus.outer_radius = radius + 0.16
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.36, 0.86, 0.44)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, 0.12, 0)
	ring.visible = false
	add_child(ring)
	_selection_ring = ring
