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
const StanceScript = preload("res://scripts/battle/orders/stance.gd")
const FlowFieldServiceScript = preload("res://scripts/battle/movement/flow_field_service.gd")
const HarvesterFSMScript = preload("res://scripts/battle/economy/harvester_fsm.gd")
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

# How far out a neighbour has to be before it stops pushing. Scaled from the
# unit's own footprint at setup so a super-heavy hull keeps more room than a
# scout - a single constant would have big hulls permanently overlapping and
# small ones drifting apart for no reason.
const SEPARATION_RADIUS_MULT := 1.35
# Separation's authority relative to the unit's own speed. Deliberately well
# under 1: it should nudge a crowded unit sideways, never overpower the order it
# was given. At 1.0 a dense group's mutual pushes cancel the seek entirely and
# the group stalls in place shoving itself.
const SEPARATION_WEIGHT := 0.45

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

# Standing policy, outliving every order. See orders/stance.gd - the old runtime
# had exactly one hardcoded policy and no way to ask for another.
var stance: int = StanceScript.DEFAULT

# Economy. Present only on designs mounting a resource_harvester module; null on
# everything else, which is what `is_harvester` really means.
var is_harvester: bool = false
var harvester: HarvesterFSM = null

var _controller: Node = null
var _selection_ring: MeshInstance3D = null
var _is_selected: bool = false
var _separation_radius: float = 3.0

# Where the harvester FSM wants to go. Kept apart from the order system on
# purpose: hauling ore is not a player order and must not overwrite one. A
# harvester given a real MOVE obeys it and stops harvesting until it goes idle
# again, which is the behaviour every RTS player already expects.
var _internal_destination: Vector3 = Vector3.ZERO
var _has_internal_destination: bool = false


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
	var base_size: Vector3 = facts["base_size"]
	_separation_radius = maxf(base_size.x, base_size.z) * SEPARATION_RADIUS_MULT
	_sync_nav_radii()
	_recalculate_move_speed()
	_create_selection_ring(base_size)
	_detect_harvester(controller)
	return true


# A design is a harvester if it actually mounts the module. Derived from the
# blueprint rather than from the hull name, so any design the player builds a
# harvester module onto becomes one.
func _detect_harvester(controller: Node) -> void:
	if not is_instance_valid(hull_node):
		return
	for child in hull_node.get_children():
		if not child.has_meta("module_data"):
			continue
		var data = child.get_meta("module_data")
		if data != null and data.get("type_id") == "resource_harvester":
			is_harvester = true
			break
	if is_harvester:
		harvester = HarvesterFSMScript.new()
		harvester.setup(self, controller)


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
	_tick_economy(delta)
	_apply_movement(delta)
	_apply_vertical(delta)
	move_and_slide()


# The harvest loop runs when the unit has nothing else to do, or was explicitly
# sent to a node. A harvester under a MOVE order is off duty until it arrives -
# and it releases its dock reservation on the way out, or a bay stays held by a
# truck that has been sent across the map.
func _tick_economy(delta: float) -> void:
	if not is_harvester or harvester == null:
		return
	var working := current_order == null or current_order.type == Order.Type.HARVEST
	if not working:
		# Both ends of the round trip hold reservations - a dock bay and a slot
		# on an ore patch - and a harvester sent elsewhere must give back both,
		# or it removes capacity from the economy for as long as it is away.
		harvester.release_all()
		_has_internal_destination = false
		return
	if current_order != null and current_order.type == Order.Type.HARVEST \
			and is_instance_valid(current_order.target) \
			and harvester.node != current_order.target:
		# A player-directed harvest: work THIS node rather than whatever was
		# nearest.
		harvester.node = current_order.target
		harvester.state = HarvesterFSMScript.State.MOVING_TO_NODE
		set_internal_destination(current_order.target.global_position)
	harvester.tick(delta)


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


# Set by the harvester FSM. Not an Order: hauling is not a player command, and
# routing it through the order system would let it silently overwrite one.
func set_internal_destination(to: Vector3) -> void:
	_internal_destination = to
	_has_internal_destination = true


func halt() -> void:
	_has_internal_destination = false
	velocity.x = 0.0
	velocity.z = 0.0


func _apply_movement(delta: float) -> void:
	var destination: Vector3
	if current_order != null and current_order.has_destination():
		destination = current_order.position
	elif _has_internal_destination:
		destination = _internal_destination
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	if move_speed <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to_point := _steer_direction(destination)
	if to_point.length() < 0.05:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Separation is folded into the HEADING rather than added to the final
	# velocity. Added afterwards it would slide the unit sideways while it still
	# faced straight ahead, which for a tracked vehicle looks like ice; blended
	# into the direction, the unit turns out of the crowd and drives out of it.
	var crowd := _separation_push()
	if crowd != Vector3.ZERO:
		to_point = (to_point.normalized() + crowd * SEPARATION_WEIGHT).normalized() * to_point.length()

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


# Which way to head this tick, resolved across three sources in priority order.
#
# 1. FLOW FIELD, while the group destination is still far off. One shared search
#    for the whole group instead of one A* each, which is what stops thirty units
#    funnelling onto one corridor in a conga line.
# 2. NAV AGENT, for the last leg and for any unit not part of a field-sized
#    group. The agent routes to this unit's own formation slot.
# 3. DIRECT, when there is no agent at all - a unit built standalone in a test.
#
# The handover in (1)->(2) is the point of the whole arrangement: the field knows
# only the clicked point, so following it all the way in would drive every unit
# onto the same spot and undo the formation.
func _steer_direction(slot: Vector3) -> Vector3:
	var field_weight := 0.0
	var flow := Vector3.ZERO
	if current_order != null and _controller != null and _controller.has_method("flow_direction_for"):
		var to_group := current_order.group_destination - global_position
		to_group.y = 0.0
		field_weight = FlowFieldServiceScript.field_weight(to_group.length())
		if field_weight > 0.0:
			flow = _controller.flow_direction_for(current_order, global_position)
			if flow == Vector3.ZERO:
				field_weight = 0.0

	# The unit's OWN heading, toward its OWN slot. This is always computed, even
	# when the field is fully in charge, because it is what the blend below folds
	# the field into - and it is what keeps twelve units going to twelve places.
	var own := Vector3.ZERO
	if is_instance_valid(nav_agent):
		if nav_agent.target_position.distance_to(slot) > 0.1:
			nav_agent.target_position = slot
		if not nav_agent.is_navigation_finished():
			var corner := nav_agent.get_next_path_position() - global_position
			corner.y = 0.0
			if corner.length() > 0.05:
				own = corner
	if own == Vector3.ZERO:
		own = slot - global_position
		own.y = 0.0

	if field_weight <= 0.0 or flow == Vector3.ZERO:
		return own

	# Blend, preserving the magnitude of the unit's own heading so the arrival
	# ramp downstream still measures a real remaining distance. A hard switch to
	# the field here is what stacked a twelve-unit squad at 0.90 m - see
	# flow_field_service.gd's BLEND_BAND for the measurements.
	var blended := own.normalized().lerp(flow.normalized(), field_weight)
	if blended.length_squared() < 0.0001:
		return own
	return blended.normalized() * own.length()


func _separation_push() -> Vector3:
	if _controller == null or not _controller.has_method("neighbour_positions"):
		return Vector3.ZERO
	var neighbours: Array = _controller.neighbour_positions(self, _separation_radius)
	if neighbours.is_empty():
		return Vector3.ZERO
	return SteeringScript.separation(global_position, neighbours, _separation_radius)


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


# --- Damage ------------------------------------------------------------------
#
# SCOPE NOTE. This is flat damage against a single HP pool. The real model -
# damage classes against armour materials, per-facet thresholds, chip damage,
# brute-force blending, subsystem stripping - lives in damage_resolver.gd, which
# this rebuild keeps and does not reimplement. Routing hits through it needs the
# attacker's facet and damage class, which arrive with weapons. Until then this
# exists so that things which kill units (the harvester explosion below, and the
# AI in Phase 3) have something to call.
func take_damage(amount: float) -> void:
	if is_dead:
		return
	hp -= amount
	if hp > 0.0:
		return
	hp = 0.0
	is_dead = true

	# A LOADED HARVESTER DETONATES. Classic C&C, and a real tactical layer rather
	# than flavour: it makes economic harassment worth timing, because catching a
	# full truck inside an enemy base damages what is around it instead of merely
	# denying income. Scales with the load, so an empty one is just a dead truck.
	if is_harvester and harvester != null:
		var damage := harvester.death_explosion_damage()
		var radius := harvester.death_explosion_radius()
		# Both reservations go back either way - one held by a wreck is capacity
		# permanently removed from the economy.
		harvester.release_all()
		if damage > 0.0 and radius > 0.0 and _controller != null \
				and _controller.has_method("apply_explosion"):
			_controller.apply_explosion(global_position, radius, damage, self)

	died.emit(self)
	queue_free()


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
