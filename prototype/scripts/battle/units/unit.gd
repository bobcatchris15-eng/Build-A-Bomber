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
const Profiler = preload("res://scripts/battle/battle_profiler.gd")
const HarvesterFSMScript = preload("res://scripts/battle/economy/harvester_fsm.gd")
const DamageModelScript = preload("res://scripts/battle/units/damage_model.gd")
const Drivetrain = preload("res://scripts/drivetrain.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

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

# Capacitor. Feeds energy weapons and the barrier projector; regenerates from
# hull base plus generator modules.
var max_energy: float = 0.0
var current_energy: float = 0.0
var energy_regen_rate: float = 0.0

# Set by the vision service. True means the LOCAL team cannot see this unit, so
# it is neither rendered nor targetable by them.
var fog_hidden: bool = false

# Longest reach of anything mounted on this unit, and the range an ATTACK order
# closes to. Derived from the weapons at assembly time.
var attack_range: float = 0.0

# How far this unit can SEE, which is a different number from how far it can
# shoot - weapons routinely out-range their own sight, which is what makes
# scouting and spotting matter.
var vision_range: float = 0.0

# Kept so energy and vision can be recomputed after a module is stripped.
var _hull_type: String = ""

var move_speed: float = 0.0
var terrain_speed_multiplier: float = 1.0

# The design this unit was built from. Read by MatchStats for attribution; not
# used for anything the unit itself does.
var blueprint: Dictionary = {}

var is_flying: bool = false
# Cruise height ABOVE THE GROUND for airborne units. 4.0 matches the old
# runtime's battle_unit.gd:201, and it is what DamageResolver's 2.0
# elevation-advantage threshold is calibrated against - see auto_weapon.gd:389,
# which flattens an air-to-ground hit origin so a flyer does not get a permanent
# elevation bonus it never earned.
var target_altitude: float = 0.0
const FLYER_CRUISE_ALTITUDE := 4.0
# How quickly a flyer converges on its cruise height. Same rate as the old
# runtime: fast enough to clear rising ground, slow enough to read as flight
# rather than as a unit snapping to a height.
const ALTITUDE_LERP := 3.0
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
	# KEPT, so the after-action report can say what a DESIGN did rather than what
	# an anonymous body did. Everything MatchStats records is keyed on the design
	# name, and that has to survive this particular unit dying.
	blueprint = blueprint_data

	var _p := Profiler.start()
	var facts := AssemblyScript.build(self, blueprint_data, unit_team, bp_manager, match_faction)
	Profiler.stop("spawn.assemble", _p)
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
	if is_flying or is_fixed_wing:
		target_altitude = FLYER_CRUISE_ALTITUDE
	is_naval = facts["is_naval"]
	is_amphibious = facts["is_amphibious"]
	_resolve_terrain_collision()

	# Weapons before the nav agent so a unit is never briefly alive, mobile and
	# unarmed - the AI acquires targets the frame a unit spawns.
	_p = Profiler.start()
	attack_range = AssemblyScript.attach_weapons(hull_node)
	Profiler.stop("spawn.weapons", _p)
	_hull_type = facts["hull_type"]
	_recalculate_energy()
	_recalculate_vision()

	_p = Profiler.start()
	nav_agent = AssemblyScript.build_nav_agent(self, facts, controller)
	Profiler.stop("spawn.nav_agent", _p)
	var base_size: Vector3 = facts["base_size"]
	_separation_radius = maxf(base_size.x, base_size.z) * SEPARATION_RADIUS_MULT
	_sync_nav_radii()
	_recalculate_move_speed()
	_p = Profiler.start()
	_create_selection_ring(base_size)
	Profiler.stop("spawn.selection_ring", _p)
	_detect_harvester(controller)
	return true


# Capacity and regen from hull base plus generators. Called again when a
# generator is stripped, which is the whole reason it is a function.
func _recalculate_energy() -> void:
	var energy := AssemblyScript.compute_energy(hull_node, _hull_type)
	var previous_max := max_energy
	max_energy = energy["max_energy"]
	energy_regen_rate = energy["energy_regen_rate"]
	# A unit starts charged; after that the pool only ever shrinks to fit, so a
	# stripped generator costs capacity without refilling what is left.
	current_energy = max_energy if previous_max <= 0.0 else clampf(current_energy, 0.0, max_energy)


# Hull base sight plus sensor modules, faction-scaled. The vision service reads
# this; it does not compute it, because what a unit can see is a property of the
# unit and what it is allowed to see is a property of the match.
func _recalculate_vision() -> void:
	var base: float = ModuleCatalog.get_base_vision(_hull_type)
	var bonus := 0.0
	var has_radar := false
	for m in DamageModelScript.active_modules(hull_node):
		var data = m.get_meta("module_data")
		if data == null:
			continue
		if data.type_id == "sensor_suite":
			bonus += data.get_vision_bonus()
		elif data.type_id == "fire_control_radar":
			has_radar = true
	vision_range = (base + bonus) * FactionCatalog.get_passive(faction, "vision_mult", 1.0)
	if is_instance_valid(hull_node):
		# Read off the HULL by auto_weapon.gd's spotting check, not off the unit -
		# a radar lets this unit's weapons engage out to their own reach rather
		# than only as far as it can see.
		hull_node.set_meta("has_fire_control_radar", has_radar)
		hull_node.set_meta("fire_control_max_range", maxf(vision_range, attack_range))


# A design is a harvester if it actually mounts the module. Derived from the
# blueprint rather than from the hull name, so any design the player builds a
# harvester module onto becomes one.
func _detect_harvester(controller: Node) -> void:
	if not is_instance_valid(hull_node):
		return
	# COUNTED, not just detected. How many harvester modules a design mounts sets
	# both its hopper and its extraction rate - see HarvesterFSM.configure() -
	# so a second harvester arm is a real design decision rather than dead weight.
	var modules := 0
	for child in hull_node.get_children():
		if not child.has_meta("module_data"):
			continue
		var data = child.get_meta("module_data")
		if data != null and data.get("type_id") == "resource_harvester":
			modules += 1
	is_harvester = modules > 0
	if is_harvester:
		harvester = HarvesterFSMScript.new()
		harvester.setup(self, controller)
		harvester.configure(modules, _hull_type)


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
	var _t := Profiler.start()
	if current_energy < max_energy:
		current_energy = minf(max_energy, current_energy + energy_regen_rate * delta)
	_advance_orders()
	_tick_economy(delta)
	_apply_movement(delta)
	_apply_vertical(delta)
	# Kept as its own section: this call was 52 ms of a 56 ms frame until
	# _resolve_terrain_collision() landed, and it is the one line here whose
	# cost is set by physics state rather than by anything visible in this
	# file - so if unit cost ever climbs again, this is the first read.
	var _s := Profiler.start()
	move_and_slide()
	Profiler.stop("unit.move_and_slide", _s)
	Profiler.stop("units", _t)


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
	if current_order != null and current_order.type == Order.Type.ATTACK:
		if not _resolve_attack_station():
			velocity.x = 0.0
			velocity.z = 0.0
			return
		destination = _internal_destination
	elif current_order != null and current_order.has_destination():
		# ATTACK-MOVE stops for a fight. The order resumes on its own once nothing
		# hostile is in reach, because this is re-evaluated every tick rather than
		# latched - which is what makes a stalled advance restart without anyone
		# having to notice the fight ended.
		if current_order.type == Order.Type.ATTACK_MOVE and _hostile_within_reach():
			velocity.x = 0.0
			velocity.z = 0.0
			return
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


# --- Engagement --------------------------------------------------------------
#
# The unit CLOSES; it does not shoot. Firing is auto_weapon.gd's business, and it
# acquires its own targets off the `damageable` group without being told. What
# the order layer owns is position: get within reach and stop, so a tank does not
# drive into a fortress to deliver a shot it could have taken from 40 m.

# How close is close enough to open fire. Inside the weapon's actual reach, so a
# unit that arrives is comfortably in range rather than dancing on the boundary
# as the target drifts a metre.
const ENGAGEMENT_RANGE_FRACTION := 0.85

func _engagement_distance() -> float:
	# An unarmed unit has no standoff to keep, so it closes all the way. Harvesters
	# and scouts get an arrive distance rather than parking at range zero forever.
	if attack_range <= 0.0:
		return _arrive_distance()
	return maxf(attack_range * ENGAGEMENT_RANGE_FRACTION, _arrive_distance())


# True when the unit should keep driving toward its ATTACK target, having set
# _internal_destination to where it is going. False means stand still - either
# already in range, or there is nothing left to shoot.
func _resolve_attack_station() -> bool:
	if current_order == null or not is_instance_valid(current_order.target):
		return false
	# HOLD_POSITION does not chase, even under a direct attack order. The order is
	# still honoured - the guns engage if the target comes to them - but the wheels
	# stay put, which is the entire point of parking artillery.
	if stance == StanceScript.Kind.HOLD_POSITION:
		return false
	var gap: float = Vector2(
		current_order.target.global_position.x - global_position.x,
		current_order.target.global_position.z - global_position.z).length()
	if gap <= _engagement_distance():
		return false
	_internal_destination = current_order.target.global_position
	return true


# Whether something shootable and hostile is close enough to stop an advance.
#
# Uses the controller's damageable lookup rather than a group scan, so this costs
# a bucket walk and not a pass over every unit on the field, every tick, per unit.
func _hostile_within_reach() -> bool:
	if attack_range <= 0.0 or _controller == null \
			or not _controller.has_method("get_nearby_damageable"):
		return false
	for c in _controller.get_nearby_damageable(global_position, attack_range):
		if c == self or not is_instance_valid(c) or c.is_dead:
			continue
		var other_team: int = c.get_meta("team") if c.has_meta("team") else -1
		if other_team == team:
			continue
		if _controller.has_method("is_visible_to_team") \
				and not _controller.is_visible_to_team(c, team):
			continue
		return true
	return false


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
# TERRAIN COMES OUT OF THE COLLISION MASK when the heightmap owns Y.
#
# This was the single biggest cost in a match, and it is a conflict of
# authority rather than a heavy computation. _apply_vertical() below WRITES
# global_position.y from terrain_height_at() every tick - the heightmap is
# authoritative and says so. But unit_assembly.gd masked TERRAIN as well, so
# move_and_slide() then re-litigated the same axis against the terrain's
# physics collider, which is only a SUBDIVIDED APPROXIMATION of the surface
# the heightmap describes. The two never agree exactly, so every unit was
# placed fractionally inside the mesh and depenetrated back out, every frame,
# against a full-map trimesh.
#
# Measured, headless, 16 units on open_plains:
#
#     move_and_slide()   52.33 ms/frame  ->  0.66 ms/frame
#     whole frame        56.41 ms        ->  4.11 ms
#
# The units never needed it. A ground unit's height is solved before
# move_and_slide() is called, and its horizontal path is solved by the
# navmesh - which is baked from the same heightmap, and is what actually
# keeps it off cliffs. BUILDINGS stays masked, because that one really is a
# backstop for a navmesh miss (see unit_assembly.gd's note).
#
# The gravity fallback is the exception and keeps TERRAIN: a unit built with
# no controller - every synthetic test - has nothing to ask for a height and
# genuinely does need the floor to land on.
func _resolve_terrain_collision() -> void:
	var heightmap_owns_y := _controller != null \
		and _controller.has_method("terrain_height_at")
	if heightmap_owns_y:
		collision_mask &= ~BattleLayers.TERRAIN
	else:
		collision_mask |= BattleLayers.TERRAIN


# Gravity is the fallback for when no controller can answer.
func _apply_vertical(delta: float) -> void:
	if is_flying or is_fixed_wing:
		velocity.y = 0.0
		# ALTITUDE IS HEIGHT ABOVE THE GROUND, never an absolute world Y, and this
		# is a regression the rebuild introduced by not porting the fix.
		#
		# battle_unit.gd:900-924 already solved this and recorded why. A flyer that
		# does not hold an altitude sits at whatever Y it spawned at - a factory
		# exit, so ground level - and a flyer inside the terrain collides with
		# every obstacle body sitting on that ground, because its collision_mask is
		# TERRAIN | BUILDINGS. move_and_slide() then spends the entire match
		# depenetrating it.
		#
		# Measured in the old runtime (scratch/probe_flyer_plateau.gd): one flyer
		# inside a summit took physics from 2.38 ms to 15.57 ms, a 6.5x cost from a
		# SINGLE unit, and left it shoved above its own target altitude by the
		# collision it should never have had. Holding an absolute y=4.0 has the
		# same failure anywhere the terrain is taller than 4 m - twin_summits peaks
		# at y=10 - which is why this samples the ground underneath rather than
		# flying at a fixed height.
		#
		# Duck-typed on terrain_height_at() exactly like the ground branch below,
		# so a unit built standalone in a test keeps a sane absolute altitude.
		var ground_y := 0.0
		if _controller != null and _controller.has_method("terrain_height_at"):
			ground_y = _controller.terrain_height_at(global_position)
		global_position.y = lerp(global_position.y, ground_y + target_altitude,
			ALTITUDE_LERP * delta)
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
# THE SIGNATURE IS THE CONTRACT. auto_weapon.gd calls
# `take_damage(amount, damage_class, hit_origin)` on whatever it hits, and it
# duck-types the target - anything in the `damageable` group with this method is
# shootable. The three-argument form is not optional decoration: the defaults
# exist for direct callers (the harvester explosion, tests) that genuinely have
# no attacker, and every one of them loses facet-aware behaviour by saying so
# explicitly rather than by accident.
#
# The rules live in damage_model.gd and the numbers in damage_resolver.gd. What
# is here is this unit's own business: energy shields, the strip consequences
# that only a vehicle has (losing locomotion, losing a generator), and death.
func take_damage(amount: float, damage_type: String = "kinetic", hit_origin = null) -> void:
	if is_dead:
		return

	var modules := DamageModelScript.active_modules(hull_node)

	# Energy Barrier Projector: a frontal shield that spends the capacitor to eat
	# the hit. Checked before armour because it is in front of the armour.
	if hit_origin != null and current_energy > 0.0:
		amount = _absorb_with_barrier(amount, modules, hit_origin)
		if amount <= 0.0:
			return

	var resolved := DamageModelScript.resolve(hull_node, modules, damage_type, self, hit_origin)

	# Subsystem stripping. A hit that lands on a module spends itself entirely on
	# that module - it does not also come off the hull, which is what makes
	# stripping a real trade for the attacker rather than a free bonus.
	var facet := DamageModelScript.hit_facet(self, hit_origin)
	var strippable := DamageModelScript.strippable(modules, facet)
	if not strippable.is_empty() and randf() < DamageModelScript.MODULE_STRIP_CHANCE:
		_strip_module(strippable.pick_random(), amount)
		return

	var dealt := DamageModelScript.hull_damage(amount, resolved.x, resolved.y)
	hp = maxf(0.0, hp - dealt)
	if _controller != null and _controller.has_method("record_combat_damage"):
		_controller.record_combat_damage(self, hit_origin, dealt, damage_type)
	if hp > 0.0:
		return
	is_dead = true
	if _controller != null and _controller.has_method("record_unit_lost"):
		_controller.record_unit_lost(self, hit_origin)

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


# Spend the capacitor to absorb a frontal hit, returning what is left of it.
#
# Frontal only, and that is the whole balance of the module: it rewards facing
# the threat, so a flanked unit gets nothing from it. `local.z < 0` is Godot's
# -Z-forward convention, the same one classify_facet() uses.
func _absorb_with_barrier(amount: float, modules: Array, hit_origin) -> float:
	var has_barrier := false
	for m in modules:
		var data = m.get_meta("module_data")
		if data != null and data.type_id == "energy_barrier_projector":
			has_barrier = true
			break
	if not has_barrier:
		return amount
	var origin: Vector3 = hit_origin if hit_origin is Vector3 else hit_origin.global_position
	var local: Vector3 = global_transform.basis.inverse() * (origin - global_position)
	if local.z >= 0.0:
		return amount
	var absorbed := minf(amount, current_energy)
	current_energy -= absorbed
	return amount - absorbed


# Take a module off the unit and deal with what its loss means.
#
# The recalculations are deferred because this runs mid-hit: the module is only
# queue_free()d here, so it is still a child of the hull until the tree flushes,
# and recalculating now would count the module that just died.
func _strip_module(module: Node3D, amount: float) -> void:
	if not DamageModelScript.damage_module(module, amount):
		return
	var data = module.get_meta("module_data")
	var was_locomotion: bool = data != null and data.category == "locomotion"
	var was_generator: bool = data != null and data.category == "generator"
	var was_sensor: bool = data != null and data.type_id in ["sensor_suite", "fire_control_radar"]
	module.queue_free()
	if was_locomotion:
		# Losing the running gear is what immobilises a vehicle. Recalculating
		# rather than zeroing: a design with six wheels that loses one is slower,
		# not stopped, and Drivetrain.analyze() is what knows the difference.
		call_deferred("_recalculate_move_speed")
	if was_generator:
		call_deferred("_recalculate_energy")
	if was_sensor:
		call_deferred("_recalculate_vision")


# --- Energy ------------------------------------------------------------------
#
# All three are duck-typed by auto_weapon.gd. Absent, energy weapons fire for
# free and drain/repair modules silently do nothing - a failure that looks like a
# balance problem rather than a missing method, which is why they are here even
# though nothing in this file calls them.

# Checked before an energy-classed weapon fires. Returns false and spends nothing
# when the capacitor is dry, which is the soft limit on sustained energy fire.
func spend_energy(amount: float) -> bool:
	if is_dead or current_energy < amount:
		return false
	current_energy -= amount
	return true


# An enemy drain weapon. Never restores HP and never goes negative: a drained
# target simply cannot use its own energy weapons until it regenerates.
func drain_energy(amount: float) -> void:
	if is_dead:
		return
	current_energy = maxf(0.0, current_energy - amount)


# A repair_array's ally-targeting beam.
func repair_hp(amount: float) -> void:
	if is_dead or hp >= max_hp:
		return
	hp = minf(max_hp, hp + amount)


# --- Fog of war --------------------------------------------------------------
#
# Written by the vision service, not computed here: "am I visible" depends on
# every construct on the opposing team, which only something that can see the
# whole field can answer. Gates rendering and, via auto_weapon.gd, whether the
# opposing team may target this unit at all.
func set_fog_visible(value: bool) -> void:
	fog_hidden = not value
	visible = value


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
