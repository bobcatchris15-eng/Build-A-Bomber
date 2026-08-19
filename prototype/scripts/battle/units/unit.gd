class_name BattleUnit
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
# NAME. Was `BattleUnitV2` through 2026-08-17 because the original
# `battle_unit.gd` (now retired) still claimed the bare `BattleUnit`
# class_name. Renamed after battle_unit.gd was deleted in the unification's
# Phase 4. PROGRESS.md entry: "follow-up rename to BattleUnit" (2026-08-17).

const SteeringScript = preload("res://scripts/battle/movement/steering.gd")
const AssemblyScript = preload("res://scripts/battle/units/unit_assembly.gd")
const StanceScript = preload("res://scripts/battle/orders/stance.gd")
const FlowFieldServiceScript = preload("res://scripts/battle/movement/flow_field_service.gd")
const Profiler = preload("res://scripts/battle/battle_profiler.gd")
const HarvesterFSMScript = preload("res://scripts/battle/economy/harvester_fsm.gd")
const DamageModelScript = preload("res://scripts/battle/units/damage_model.gd")
const BattleWreckScript = preload("res://scripts/battle/units/battle_wreck.gd")
# The simulation random stream - see its header. This file's only draws are the
# subsystem-strip roll and the choice of which module it takes, both of which
# change the outcome of a fight, so both are SIM.
const SimRNG = preload("res://scripts/battle/sim_rng.gd")
const Drivetrain = preload("res://scripts/drivetrain.gd")
const PowerBudgetScript = preload("res://scripts/power_budget.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
const VFXBurstScript = preload("res://scripts/vfx_burst.gd")

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

# The capacitor. Feeds energy weapons, the barrier projector and - since power
# draw became a real quantity - the electronics, which now cost something to run
# rather than being free.
#
# energy_regen_rate is NET: generation minus continuous draw. It can be
# NEGATIVE, which is new and is the entire mechanism behind the brownout below.
# A design that mounts more electronics than its hull and generators can feed
# does not fail to build and does not fail to spawn; it runs down its buffer and
# starts shedding systems, and how long that takes is what its storage bought.
var max_energy: float = 0.0
var current_energy: float = 0.0
var energy_regen_rate: float = 0.0

# Which systems are currently shed, from PowerBudget.brownout_state(). Held as
# state rather than recomputed at each use site for two reasons: the thresholds
# carry hysteresis, which needs the previous frame's answer to resolve, and
# vision is a cached figure that has to be RECOMPUTED on a transition rather
# than multiplied at read time.
var _brownout: Dictionary = {
	"shields_offline": false,
	"electronics_brownout": false,
	"weapons_offline": false,
}

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

# DISTANCE-BASED VISIBILITY (PR3, 2026-08-15). Godot's built-in
# `visibility_range_end` culls a GeometryInstance3D beyond the end distance
# without forcing the per-frame frustum cull cost, which is what we want
# for the units out at the edge of a max-zoom-out Skirmish. The fade
# band at the end is a 4 m linear alpha so a unit does not pop out at
# the camera's exact transition point. Tuned for a 2660x1080 viewport:
# at the camera's max zoom-out (height = max_height), the playable map
# is ~120 m across, so 110 m is "off the field" for a single frame and
# well beyond the fog of war's reach.
const UNIT_VISIBILITY_END: float = 110.0
const UNIT_VISIBILITY_FADE: float = 4.0

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
# World-space cargo fill bar, harvesters only - see _create_cargo_bar().
var _cargo_bar_root: Node3D = null
var _cargo_fill: MeshInstance3D = null
var _cargo_bar_width: float = 0.0
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

# Boost controller for burst speed parts (nitrous_injector, booster_rack)
var boost_controller: BoostController = null
# The last Drivetrain.analyze() result, cached by _recalculate_move_speed().
# Read by BoostController, which needs the "boost" sub-dictionary from it.
var drivetrain_analysis: Dictionary = {}
# Exhaust plume while a boost is lit - periodic bursts rather than a
# continuous emitter, so an idling boosted unit doesn't carry a live particle
# system the rest of the time. Interval, not per-frame, to keep the cost of
# a boosting group down.
var _boost_vfx_timer: float = 0.0
const BOOST_VFX_INTERVAL := 0.12

# Cold-War vehicle suspension & chassis pitch/roll state
var _suspension_pitch: float = 0.0
var _suspension_roll: float = 0.0
var _prev_speed: float = 0.0
var _prev_yaw: float = 0.0

# DEPLOYABLE_MODULES_OVERHAUL.md §4: mine layer movement-distance tracking.
# Accumulates ground distance travelled; drops a mine every ~4.5× hull length.
var _mine_distance_accum: float = 0.0
var _prev_mine_pos: Vector3 = Vector3.ZERO
const MINE_DROP_DISTANCE_MULT: float = 4.5
# PR5 (2026-08-15). Cached at setup() so the per-tick _tick_mine_layer_tracking
# can short-circuit for the 90%+ of units that have no mine_layer weapon,
# instead of walking the hull subtree every physics tick to find out. Without
# this gate, every unit paid the meta-lookup cost on every tick (the function
# is called from _physics_process, so 30 Hz × 12 units = 360 wasted lookups/sec
# in a typical Skirmish, plus the hull_node.has_meta reads).
var _has_mine_layer: bool = false


func _ready() -> void:
	add_to_group("units")
	add_to_group("damageable")
	_prev_mine_pos = global_position   # seed so first tick has zero delta


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
	# PR5 (2026-08-15). Cache the mine_layer presence at spawn so the per-tick
	# distance tracker can short-circuit without re-walking the hull subtree.
	# Single hull_node iteration at setup time; zero per-tick cost for the
	# 90%+ of units that have no mine_layer.
	_has_mine_layer = _has_weapon_of_type(hull_node, "mine_layer")
	_recalculate_energy()
	_recalculate_vision()

	_p = Profiler.start()
	nav_agent = AssemblyScript.build_nav_agent(self, facts, controller)
	Profiler.stop("spawn.nav_agent", _p)
	var base_size: Vector3 = facts["base_size"]
	_separation_radius = maxf(base_size.x, base_size.z) * SEPARATION_RADIUS_MULT
	_sync_nav_radii()
	_recalculate_move_speed()

	# Boost controller for burst speed parts
	boost_controller = BoostController.new()
	# `facts["drivetrain"]` DID NOT EXIST. UnitAssembly.build_facts() returns
	# sixteen keys and drivetrain is not among them, so this crashed on every
	# single unit spawn with "Invalid access to property or key 'drivetrain' on a
	# base object of type 'Dictionary'" - and because setup() aborted there, no
	# unit ever finished spawning. That one missing key was upstream of twenty
	# failing suites: production, damage, movement convergence and every map smoke
	# test, none of which look like a boost-controller problem from the outside.
	#
	# _recalculate_move_speed() four lines above already computed exactly this
	# analysis and discarded it; it now caches it instead.
	boost_controller.setup(self, drivetrain_analysis)

	_p = Profiler.start()
	_create_selection_ring(base_size)
	Profiler.stop("spawn.selection_ring", _p)
	_log_collider_census()
	_detect_harvester(controller)
	_create_cargo_bar(base_size)

	# PR3 (2026-08-15). Apply the distance-based visibility range to every
	# GeometryInstance3D under the hull. Walks the subtree once, sets the
	# range begin (no fade-in from zero - units at spawn distance always
	# render), range end, and a 4 m linear fade. The 4 m fade width is
	# measured against the camera's worst-case zoom speed (a 0.2 s
	# fast-zoom at 60 fps travels 12 frames over the fade band, so
	# alpha-0 is reached before the unit's silhouette would have popped
	# if the fade were a hard cut).
	if is_instance_valid(hull_node):
		_apply_unit_visibility_range(hull_node)
	return true


# Walks a node subtree and sets visibility_range_end on every
# GeometryInstance3D. Cheap (one pass at spawn time), and a unit's hull
# subtree is shallow enough that the recursion is not worth refactoring.
func _apply_unit_visibility_range(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi: GeometryInstance3D = node
		gi.visibility_range_begin = 0.0
		gi.visibility_range_end = UNIT_VISIBILITY_END
		gi.visibility_range_begin_margin = 0.0
		gi.visibility_range_end_margin = UNIT_VISIBILITY_FADE
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for child in node.get_children():
		_apply_unit_visibility_range(child)


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
	vision_range = base + bonus
	# Brownout applied LAST, as a multiplier on the finished figure, so it
	# composes with the faction passive above rather than competing with it: a
	# Technocrat scout that browns out should lose the same PROPORTION of its
	# sight as anyone else, not have its passive silently cancelled.
	#
	# This is also why _recalculate_vision() is called when the brownout state
	# changes and not only when modules are lost - vision is recomputed from
	# scratch each time, so a stale multiplier cannot accumulate.
	vision_range *= PowerBudgetScript.vision_multiplier(_brownout)
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
		harvester.configure(modules, _hull_type,
			ModuleCatalog.resource_bay_capacity(hull_node))


# Speed, weight and overload all come from Drivetrain.analyze() - the same
# function the Design Lab's stat rail calls. They must agree: the number a player
# sizes a drivetrain against in the Lab is the number it moves at in a battle.
# An abbreviated second copy is exactly how the old ones drifted apart.
#
# Reads move_speed, not top_speed (2026-08-08 speed pass) - was reading the
# latter, which is the clean pre-overload/pre-passive figure the Design Lab
# quotes BEFORE the load penalty, the underload bonus and faction speed
# passives are applied. That silently zeroed out all three in every real
# Skirmish match: an overloaded unit never actually slowed down, a
# stripped-down one never sped up, and the Glacier Syndicate/Aerodrome Cartel
# speed passives had no effect on the units they were supposed to change.
# battle_unit.gd's own _recalculate_move_speed() already read the right key;
# the new runtime did not. battle_unit.gd retired 2026-08-10.
func _recalculate_move_speed() -> void:
	if not is_instance_valid(hull_node):
		return
	var dt: Dictionary = Drivetrain.analyze(hull_node, locomotion_type, locomotion_settings, is_flying)
	# CACHED, because BoostController needs the same analysis and there is no
	# reason to run it twice. It also needs it AFTER this function has run, which
	# is why setup() reads the member rather than being handed a value.
	drivetrain_analysis = dt
	move_speed = dt["move_speed"] if dt["has_locomotion"] else 0.0
	_sync_nav_radii()


func _arrive_distance() -> float:
	return maxf(ARRIVE_DISTANCE_MIN, move_speed * ARRIVE_DISTANCE_PER_SPEED)


# The capture radii cannot be constants. A waypoint counts as reached only once
# the unit is inside path_desired_distance of it; a unit doing 18 m/s turns along
# an arc several metres wide and can sweep past a 1 m circle without ever
# entering it, never advance, and loop back to try the same waypoint again. The
# faster the design, the more certain the miss.
#
# CORE_DESIGN_LANGUAGE.md §3.2 (2026-08-08 playtest): there is a SECOND way to
# miss a waypoint, found live and reproduced in test_real_unit_actually_
# converges_toward_a_move_order_on_a_real_map - a unit sitting at its start
# position, move_speed and nav_agent both real, jittering in a ~1.5m box for
# 8 full seconds. path_desired_distance stayed a flat ~1.0m (unit-space, on
# purpose - a fast unit's own turning arc is a unit property, not a map one),
# but terrain_builder.gd's own navmesh bake cell_size is NOT unit-space - it
# deliberately WIDENS as map_half_extents grows (Chunk 14's self-bounding
# formula), and at world_scale=4 on an ordinary map that's already ~1.87m,
# bigger than the 1.0m the agent was demanding. A corner's true position is
# only precise to within the bake's own cell_size, so asking to get closer
# to it than that quantization allows is asking for something the navmesh
# cannot promise - the agent gets "almost there" forever and never advances,
# which reads as a unit standing still and vibrating in place.
#
# Floored against the SAME cell_size formula the bake itself used, so this
# is guaranteed consistent with the actual navmesh precision by
# construction rather than a second guessed number that could drift out of
# sync with it again.
func _sync_nav_radii() -> void:
	if not is_instance_valid(nav_agent):
		return
	nav_agent.target_desired_distance = _arrive_distance()
	# Floored above the navmesh's vertical error, because path_desired_distance
	# is measured in 3D and the ground navmesh is deliberately flat while the
	# body follows real terrain. Without this the vertical gap alone can equal
	# the whole tolerance, and the agent never advances past its first corner -
	# see TerrainBuilderScript.nav_vertical_slack(). The 1.5 gives the
	# horizontal component something left to work with once the vertical error
	# is paid for.
	var slack := 0.0
	if _controller != null and "current_map" in _controller:
		slack = TerrainBuilderScript.nav_vertical_slack(_controller.current_map) * 1.5
	nav_agent.path_desired_distance = maxf(maxf(1.0, move_speed * 0.06), slack)


# The buffer, and what shedding load looks like when it empties.
#
# Two changes from the one-line version this replaces
# (`if current_energy < max_energy: current_energy += rate * delta`):
#
# 1. The rate can now be NEGATIVE, so the guard had to go. Clamping the update
#    to "only when below max" meant a design in deficit sat pinned at full
#    forever - the draw would have been computed, reported in the Lab, and then
#    silently never applied, which is the worst of both worlds. It now runs
#    unconditionally and clamps to the 0..max range at the end.
#
# 2. Crossing a brownout threshold re-derives vision, rather than vision being
#    multiplied at read time. vision_range is a cached figure that several
#    systems read every frame; recomputing it only on a TRANSITION keeps that
#    read cheap and means the multiplier cannot compound across frames.
func _tick_power(delta: float) -> void:
	if max_energy <= 0.0:
		return
	current_energy = clampf(current_energy + energy_regen_rate * delta, 0.0, max_energy)

	var before_electronics: bool = _brownout.get("electronics_brownout", false)
	_brownout = PowerBudgetScript.brownout_state(current_energy / max_energy, _brownout)
	if _brownout.get("electronics_brownout", false) != before_electronics:
		_recalculate_vision()


# Terrain variety task: surface terrain (marsh/rocky/snow_mud/sand/...) slows
# or favors specific locomotion types - this looks up the CURRENT tile every
# physics tick (position changes constantly, unlike move_speed which is only
# recomputed when the design changes) and stores the multiplier for
# _apply_movement() to apply. Flying/naval units never touch ground surface
# terrain (is_flying skips this entirely; is_naval's "surface" is water,
# which has no surface_zones), so both stay at the default 1.0. Duck-typed
# like get_ground_nav_map()/terrain_height_at() - every synthetic test
# without a real match controller falls through to the harmless 1.0 default,
# unchanged.
#
# Ported from battle_unit.gd (2026-08-08 speed pass; battle_unit.gd retired
# 2026-08-10 in the unification's Phase 4) - this runtime declared
# terrain_speed_multiplier and read it in _apply_movement(), but nothing here
# ever assigned it, so the whole per-surface locomotion table (and the tread-
# width/Glacier Syndicate modifiers on top of it) was dead in every real
# Skirmish match. It only ever ran in tests that built a battle_unit.gd unit
# directly.
func _recalculate_terrain_speed_multiplier() -> void:
	if is_flying or is_naval:
		terrain_speed_multiplier = 1.0
		return
	if _controller == null or not _controller.has_method("get_surface_type_at"):
		terrain_speed_multiplier = 1.0
		return
	var surface_type = _controller.get_surface_type_at(global_position)
	if surface_type == "":
		terrain_speed_multiplier = 1.0
		return
	terrain_speed_multiplier = ModuleCatalog.get_terrain_speed_multiplier(locomotion_type, surface_type)
	# Wider track spreads weight over more contact area (real flotation, less
	# sinking), so it eats further into whatever penalty the base table
	# already assigns; a narrower track digs in more and eats further into
	# it. Only shifts the number tracked_treads already has for this
	# surface, doesn't grant terrain immunity (clamped at 1.2).
	if locomotion_type == "tracked_treads":
		var width = locomotion_settings.get("tread_width", locomotion_settings.get("width", 1.0))
		var width_delta = (width - 1.0) * 0.25
		terrain_speed_multiplier = clamp(terrain_speed_multiplier + width_delta, 0.15, 1.2)

	# The Glacier Syndicate's terrain-penalty reduction used to be applied here.
	# Faction passives are gone (see livery.gd) - terrain now affects every
	# unit identically, by its locomotion type alone.


# Exhaust plume for whichever boost part is lit - one burst per
# BOOST_VFX_INTERVAL rather than every physics tick, so a boosting group
# doesn't carry a live particle system per unit per frame. Reset to 0.0
# rather than left counting down while not boosting, so the FIRST tick a
# boost engages always shows a burst immediately instead of waiting out
# whatever was left on the timer from the last time it was lit.
func _update_boost_vfx(delta: float, is_boosting: bool) -> void:
	if not is_boosting:
		_boost_vfx_timer = 0.0
		return
	_boost_vfx_timer -= delta
	if _boost_vfx_timer > 0.0:
		return
	_boost_vfx_timer = BOOST_VFX_INTERVAL
	VFXBurstScript.spawn(self, Vector3(0, 0.3, 0.8), Color(1.0, 0.65, 0.2), 5, 0.18, 40.0, 2.0, 4.0, Vector3.ZERO, 0.35, 0.7)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	var _t := Profiler.start()
	var _p := Profiler.start()
	_tick_power(delta)
	Profiler.stop("unit.tick_power", _p)
	_p = Profiler.start()
	_recalculate_terrain_speed_multiplier()
	Profiler.stop("unit.terrain_speed", _p)
	_p = Profiler.start()
	_advance_orders()
	Profiler.stop("unit.advance_orders", _p)
	_p = Profiler.start()
	_tick_economy(delta)
	Profiler.stop("unit.tick_economy", _p)

	# Tick boost controller - must run before _apply_movement so its multiplier
	# applies to this frame's speed.
	var boost_mult: float = 1.0
	if boost_controller != null:
		boost_mult = boost_controller.tick(delta)
	_update_boost_vfx(delta, boost_mult > 1.0)

	_apply_movement(delta, boost_mult)
	_apply_vertical(delta)
	_tick_mine_layer_tracking(delta)
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
	# Cheap enough to run on the economy tick rather than per-frame, and a fill
	# level does not need per-frame precision the way a position does.
	_update_cargo_bar()
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


# DEPLOYABLE_MODULES_OVERHAUL.md §4: mine layer distance-based auto-fire.
# Each physics tick accumulates ground distance travelled. When it reaches
# ~4.5× the unit's hull length, drops a proximity mine if the weapon is ready.
# PR5 (2026-08-15). Short-circuits on _has_mine_layer (cached at setup) so
# the 90%+ of units that have no mine_layer weapon pay nothing here.
func _tick_mine_layer_tracking(delta: float) -> void:
	if not _has_mine_layer or is_dead or move_speed <= 0.0:
		return

	var moved := global_position - _prev_mine_pos
	moved.y = 0.0
	_mine_distance_accum += moved.length()
	_prev_mine_pos = global_position

	var hull_len := 5.0  # fallback
	if is_instance_valid(hull_node):
		if hull_node.has_meta("base_hull_size"):
			hull_len = hull_node.get_meta("base_hull_size").z
		if hull_node.has_meta("hull_scale"):
			hull_len *= hull_node.get_meta("hull_scale").z

	var drop_threshold := hull_len * MINE_DROP_DISTANCE_MULT
	if _mine_distance_accum < drop_threshold:
		return

	# Find the first ready mine_layer weapon on this unit.
	var mine_wpn = _get_ready_mine_layer_weapon()
	if mine_wpn == null:
		_mine_distance_accum = 0.0
		return

	# Fire the mine layer toward the threat (or forward if no threat).
	# _find_nearest_target() is not called here — we just trigger the
	# existing _fire_mine_layer() on whichever weapon is ready.
	var aim_pos: Vector3
	var t = mine_wpn.target if "target" in mine_wpn else null
	if t != null and is_instance_valid(t):
		aim_pos = t.global_position
	else:
		var range_val: float = 14.0
		if "fire_range" in mine_wpn:
			range_val = float(mine_wpn.fire_range)
		aim_pos = global_position - global_transform.basis.z.normalized() * range_val

	# Hand the target to the weapon and fire.
	mine_wpn.set("target", _mine_layer_target_marker(aim_pos))
	mine_wpn._fire_mine_layer()
	_mine_distance_accum = 0.0

# Returns the first mine_layer weapon on this unit whose cooldown has expired,
# or null if none are ready.
func _get_ready_mine_layer_weapon() -> Node:
	if not is_instance_valid(hull_node):
		return null
	for child in hull_node.get_children():
		if not child.has_meta("module_data"):
			continue
		var data = child.get_meta("module_data")
		if data == null or data.type_id != "mine_layer":
			continue
		# auto_weapon-scripted weapons expose time_since_last_shot and fire_rate.
		var tsls: float = float(child.time_since_last_shot) if "time_since_last_shot" in child else 0.0
		var fr: float = float(child.fire_rate) if "fire_rate" in child else 3.5
		if tsls >= fr:
			return child
	return null

# Creates a brief world-space marker Node3D at aim_pos so _fire_mine_layer()
# has a valid Vector3 target without polluting the weapon's own target slot.
func _mine_layer_target_marker(aim_pos: Vector3) -> Node3D:
	var m = Node3D.new()
	m.name = "MineLayerTarget"
	var scene = get_tree().current_scene
	if scene:
		scene.add_child(m)
	else:
		get_parent().add_child(m)
	m.global_position = aim_pos
	# PR5 (2026-08-15). The previous version used get_tree().create_timer(3.0)
	# for cleanup, which works, but a per-timer SceneTreeTimer is a heap
	# allocation and the lambda closure adds more. A child Timer node
	# shares the SceneTree's timer and frees itself when it fires. The
	# 3 s window is the same: long enough for _fire_mine_layer() to have
	# read the marker, short enough that an orphaned marker from a
	# match-end mid-throw cannot outlive the match.
	var cleanup_timer := Timer.new()
	cleanup_timer.one_shot = true
	cleanup_timer.wait_time = 3.0
	cleanup_timer.autostart = true
	cleanup_timer.timeout.connect(func():
		if is_instance_valid(m):
			m.queue_free()
		if is_instance_valid(cleanup_timer):
			cleanup_timer.queue_free())
	m.add_child(cleanup_timer)
	return m


# Walks the hull subtree once and returns true if any weapon has
# module_data.type_id == type_id. PR5 (2026-08-15) introduced this to cache
# the mine_layer presence at setup time. Used elsewhere it would do the
# same for smoke_discharger (auto-pop at <10% HP), but that path is
# already gated on the actual take_damage call so caching is unnecessary.
func _has_weapon_of_type(node: Node, type_id: String) -> bool:
	if node.has_meta("module_data"):
		var data = node.get_meta("module_data")
		if data != null and data.type_id == type_id:
			return true
	for child in node.get_children():
		if _has_weapon_of_type(child, type_id):
			return true
	return false


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


# --- Boost controller helper methods ---

func get_remaining_distance() -> float:
	if current_order != null and current_order.has_destination():
		var dest := current_order.position
		return Vector3(global_position.x - dest.x, 0.0, global_position.z - dest.z).length()
	elif _has_internal_destination:
		return Vector3(global_position.x - _internal_destination.x, 0.0, global_position.z - _internal_destination.z).length()
	return 0.0

func get_heading_throttle() -> float:
	if current_order == null and not _has_internal_destination:
		return 0.0
	var destination: Vector3
	if current_order != null and current_order.has_destination():
		destination = current_order.position
	elif _has_internal_destination:
		destination = _internal_destination
	else:
		return 0.0
	var to_point := _steer_direction(destination)
	if to_point.length() < 0.05:
		return 0.0
	var current_yaw := rotation.y
	var target_yaw := SteeringScript.yaw_for(to_point, current_yaw)
	return SteeringScript.heading_throttle(current_yaw, target_yaw)

func has_hostile_in_range() -> bool:
	if attack_range <= 0.0:
		return false
	# Check nearby units - duck-typed to avoid import cycles
	var enemies := get_tree().get_nodes_in_group("units")
	for e in enemies:
		if e == self:
			continue
		if e.team != team and not e.is_dead:
			if e.global_position.distance_to(global_position) <= attack_range:
				return true
	return false

func get_energy_fraction() -> float:
	if max_energy <= 0.0:
		return 0.0
	return current_energy / max_energy


func _apply_movement(delta: float, boost_mult: float = 1.0) -> void:
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
	var _st := Profiler.start()
	var to_point := _steer_direction(destination)
	Profiler.stop("unit.steer_nav", _st)
	if to_point.length() < 0.05:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Separation is folded into the HEADING rather than added to the final
	# velocity. Added afterwards it would slide the unit sideways while it still
	# faced straight ahead, which for a tracked vehicle looks like ice; blended
	# into the direction, the unit turns out of the crowd and drives out of it.
	var _sp := Profiler.start()
	var crowd := _separation_push()
	Profiler.stop("unit.separation", _sp)
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
	#
	# CORE_DESIGN_LANGUAGE.md §5 "Rigid Miniatures" wants "no deceleration
	# curve worth noticing," which an earlier version of this line chased by
	# shrinking the speed-proportional term to a flat 0.05 - and that broke
	# navigation outright. The line above (413-418) already documents WHY:
	# at full throttle a unit's turning radius is v/TURN_RATE, and if
	# slow_radius is smaller than that, the unit physically cannot align
	# its heading before it's already past the capture zone - it overshoots,
	# turns around, overshoots again, forever. An 18 m/s design has a ~6.9m
	# turning radius; the flat-0.05 version produced a ~4.3m slow_radius,
	# well inside it - "units just sit in one spot and go in a circle."
	# Derived from the actual geometry instead of a magic coefficient, with
	# a 30% margin over the minimum that geometry requires - genuinely
	# tighter than the original 0.45 coefficient's ~17% margin, but not the
	# near-instant stop §5 asks for. Getting further than this safely means
	# also raising TURN_RATE (a faster-turning vehicle can tolerate a
	# smaller slow_radius), which is a separate, deliberate change, not a
	# side effect of retuning this line again.
	const SLOW_RADIUS_TURN_SAFETY_MARGIN := 1.3
	var remaining := Vector3(destination.x - global_position.x, 0.0, destination.z - global_position.z).length()
	var turning_radius := move_speed / TURN_RATE
	var slow_radius := maxf(_arrive_distance() * 2.0, turning_radius * SLOW_RADIUS_TURN_SAFETY_MARGIN)
	var speed: float = SteeringScript.arrival_speed(remaining, move_speed, slow_radius) \
		* terrain_speed_multiplier * throttle * boost_mult

	var forward := -transform.basis.z.normalized()
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed

	# Cold-War vehicle suspension physics (chassis squat/dip on accel/brake and roll into turns)
	# DIRTY-TRANSFORM GATE (PR1, 2026-08-15). The old code wrote
	# hull_node.rotation on every physics tick, even for stationary units
	# whose target_pitch and target_roll had already converged to 0. The
	# write still marks the transform tree dirty and forces every child
	# mesh and weapon module to re-evaluate their global transform, which
	# the renderer cannot batch across. The fix: only write when the
	# value actually changes, and skip the entire block when the unit is
	# effectively at rest. The lerp continues to update internally so
	# the next acceleration snaps the suspension in the right direction.
	if is_instance_valid(hull_node) and not is_flying:
		var accel: float = (speed - _prev_speed) / maxf(delta, 0.001)
		_prev_speed = speed
		var target_pitch: float = clampf(-accel * 0.006, -0.05, 0.05)
		var pitch_delta: float = target_pitch - _suspension_pitch
		_suspension_pitch = lerpf(_suspension_pitch, target_pitch, 8.0 * delta)

		var yaw_rate: float = wrapf(rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.001)
		_prev_yaw = rotation.y
		var target_roll: float = clampf(yaw_rate * 0.012, -0.06, 0.06)
		var roll_delta: float = target_roll - _suspension_roll
		_suspension_roll = lerpf(_suspension_roll, target_roll, 8.0 * delta)

		# Combined gate: the unit is at rest when the deltas to the targets
		# are both below one milli-radian AND the unit is not moving.
		# Writing to hull_node.rotation in that case costs a tree-wide
		# dirty propagation for zero visible change.
		var resting: bool = absf(pitch_delta) < 0.001 \
				and absf(roll_delta) < 0.001 \
				and absf(speed) < 0.05 \
				and absf(yaw_rate) < 0.01
		if not resting:
			hull_node.rotation.x = _suspension_pitch
			hull_node.rotation.z = _suspension_roll
		elif hull_node.rotation.x != 0.0 or hull_node.rotation.z != 0.0:
			# One last write to reset to neutral once the suspension has
			# settled, then stay clean until the next acceleration.
			hull_node.rotation.x = 0.0
			hull_node.rotation.z = 0.0


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
		# battle_unit.gd:900-924 already solved this and recorded why
		# (battle_unit.gd retired 2026-08-10; the ported fix is what this
		# block now does). A flyer that
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
	#
	# Shields are the FIRST thing a brownout sheds (PowerBudget's threshold
	# ordering), and this is where that happens. Deliberately gated on the
	# brownout state rather than on `current_energy > 0` alone: without it, a
	# design in deficit would keep eating hits with the last few points in its
	# buffer, which is precisely the energy its weapons and optics need to stay
	# up. Dropping the shield early is what leaves something in reserve for the
	# systems that shed later, and it is the cue to the player that the design is
	# under-powered - a shield that silently stops working at zero looks like a
	# bug, one that drops at half looks like a consequence.
	if hit_origin != null and current_energy > 0.0 and not _brownout.get("shields_offline", false):
		amount = _absorb_with_barrier(amount, modules, hit_origin)
		if amount <= 0.0:
			return

	var resolved := DamageModelScript.resolve(hull_node, modules, damage_type, self, hit_origin)

	# Subsystem stripping. A hit that lands on a module spends itself entirely on
	# that module - it does not also come off the hull, which is what makes
	# stripping a real trade for the attacker rather than a free bonus.
	var facet := DamageModelScript.hit_facet(self, hit_origin)
	# Traced against the per-module hit volumes when there is a physics world to
	# trace in, so the module a shot takes is the one it visibly struck; falls
	# back to the facet filter otherwise. Draw count is identical either way -
	# see strippable_along_shot's header on why that had to be true.
	var strippable := DamageModelScript.strippable_along_shot(
		self, hull_node, modules, hit_origin, facet)
	#
	# SIM, twice over: whether this hit strips at all, and which of the exposed
	# modules it takes. Both are outcome-defining - a strip consumes the hit
	# entirely (the early return below), so the roll decides whether the hull
	# took damage at all, and the choice decides whether the unit lost a gun, a
	# sensor or its last locomotion module and is now immobilised.
	#
	# The short-circuit order matters and is load-bearing for the split: `not
	# strippable.is_empty()` is evaluated first, so a hit on a unit with nothing
	# exposed does not draw. Reversing it would make stream position depend on
	# how many modules a unit happened to have left, which is exactly the kind of
	# incidental coupling the sim/cosmetic separation exists to remove.
	if not strippable.is_empty() and SimRNG.randf() < DamageModelScript.MODULE_STRIP_CHANCE:
		_strip_module(SimRNG.pick(strippable), amount)
		return

	var dealt := DamageModelScript.hull_damage(amount, resolved.x, resolved.y)
	hp = maxf(0.0, hp - dealt)
	if _controller != null and _controller.has_method("record_combat_damage"):
		_controller.record_combat_damage(self, hit_origin, dealt, damage_type)

	# DEPLOYABLE_MODULES_OVERHAUL.md §2: emergency smoke auto-pop at <10% HP.
	# Fires the smoke_discharger toward the hit origin if the weapon is ready.
	# Gated on hp > 0 (don't double-trigger on the killing blow) and cooldown.
	if hp > 0.0 and max_hp > 0.0 and hp / max_hp <= 0.10:
		_try_emergency_smoke(hit_origin)

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
	BattleWreckScript.spawn_from_unit(self, hit_origin)
	queue_free()


# DEPLOYABLE_MODULES_OVERHAUL.md §2: finds the unit's smoke_discharger and fires
# an emergency screen toward hit_origin if the weapon is off cooldown.
func _try_emergency_smoke(hit_origin) -> void:
	if not is_instance_valid(hull_node):
		return
	for child in hull_node.get_children():
		if not child.has_meta("module_data"):
			continue
		var data = child.get_meta("module_data")
		if data == null or data.type_id != "smoke_discharger":
			continue
		# Guard: only fire if the weapon is off cooldown.
		var tsls: float = float(child.time_since_last_shot) if "time_since_last_shot" in child else 0.0
		var fr: float = float(child.fire_rate) if "fire_rate" in child else 2.5
		if tsls < fr:
			continue
		if child.has_method("request_screen") and hit_origin != null:
			var origin_vec: Vector3
			if hit_origin is Vector3:
				origin_vec = hit_origin
			else:
				origin_vec = global_position  # fallback; should not happen
			child.request_screen(origin_vec)
			return   # one smoke pop per hit; stop after the first ready weapon


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


# Playtest: "the harvester units need a bar above them showing how full their
# bays are."
#
# Built only on units that are actually harvesters - _detect_harvester() has
# already run by the time this is called, so a combat unit never carries a dead
# node for a state it can't have. The fill fraction needs no new economy
# plumbing: HarvesterFSM already exposes cargo() and resolves `capacity` per
# design via capacity_for(), which accounts for module count, hull tier and
# resource-bay capacity, so cargo()/capacity IS the fill fraction.
#
# Two stacked quads - a dark backing plate and a colored fill - is the classic
# RTS bar, and the fill is SCALED rather than re-meshed each tick, the same
# idiom resource_node.gd's _update_visual_scale() already uses for depletion.
# Billboarded and unshaded so it stays legible from any camera angle and
# doesn't take terrain shading, matching _create_selection_ring()'s treatment
# of the other piece of world-space unit UI.
#
# This is the game's first world-space status bar on a unit. Kept deliberately
# plain for that reason: it sets the vocabulary anything later (ammo, capture
# progress, build progress) will have to match, and a plain plate is easier to
# build on than a styled one is to walk back.
const CARGO_BAR_WIDTH_MULT: float = 1.15
const CARGO_BAR_HEIGHT: float = 0.16

func _create_cargo_bar(base_size: Vector3) -> void:
	if not is_harvester or harvester == null:
		return
	var width: float = maxf(base_size.x, base_size.z) * CARGO_BAR_WIDTH_MULT
	var root := Node3D.new()
	root.name = "CargoBar"
	# Clear of the hull's own top, not a fixed altitude - hulls differ in height
	# by a lot across tiers.
	root.position = Vector3(0, base_size.y * 0.5 + CARGO_BAR_HEIGHT * 3.0, 0)
	add_child(root)

	root.add_child(_cargo_bar_quad(width, CARGO_BAR_HEIGHT, Color(0.06, 0.07, 0.08, 0.85), 0.0))
	# Drawn a hair in front of the backing plate. Both are billboarded, so they
	# stay coplanar-facing and would z-fight without the offset.
	_cargo_fill = _cargo_bar_quad(width, CARGO_BAR_HEIGHT * 0.72, Color(0.95, 0.78, 0.25, 1.0), 0.01)
	root.add_child(_cargo_fill)
	_cargo_bar_width = width
	_cargo_bar_root = root
	_update_cargo_bar()

func _cargo_bar_quad(width: float, height: float, color: Color, z_offset: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, z_offset)
	return mi

func _update_cargo_bar() -> void:
	if not is_instance_valid(_cargo_bar_root) or harvester == null:
		return
	var cap: int = harvester.capacity
	var frac: float = 0.0 if cap <= 0 else clampf(float(harvester.cargo()) / float(cap), 0.0, 1.0)
	# Hidden when empty. An empty bar over every idle truck on the field is
	# clutter that says nothing; the bar appearing IS the signal that this one
	# is carrying something.
	_cargo_bar_root.visible = frac > 0.0
	if not is_instance_valid(_cargo_fill):
		return
	# Grows from the left edge rather than from the centre: scaling a quad about
	# its own origin would shrink it toward the middle from both ends, which
	# reads as a shrinking bar rather than a filling one.
	_cargo_fill.scale.x = maxf(frac, 0.0001)
	_cargo_fill.position.x = -(_cargo_bar_width * 0.5) * (1.0 - frac)

# SKIRMISH_PERF_TROUBLESHOOTING.md §10.2. `unit.move_and_slide` is the single
# largest line item in a real match - 44 s of a 259 s capture, ~4 ms per unit
# per frame at 15 units - and its per-unit cost rose ~46x between 2 and 15
# units. That superlinearity points at the broadphase rather than at any
# GDScript here: Godot generates one collision pair PER SHAPE per interacting
# body, so N units at S shapes each is an N x N x S problem, and S is the term
# nothing in the log currently reports.
#
# S is not derivable from the blueprint either. unit_assembly._add_hull_collider
# resolves through three tiers (authored convex fit / box fallback) and the
# module hit volumes are capped at BATTLE_MODULE_MAX_SHAPES per module, so the
# only honest way to know the number is to count the nodes after assembly.
#
# Logged once per spawn, not per frame. Cost is one subtree walk on a frame that
# already spends ~125 ms assembling the unit.
func _log_collider_census() -> void:
	if not BattleLogger.enabled:
		return
	var body_shapes := 0
	for c in get_children():
		if c is CollisionShape3D:
			body_shapes += 1
	# Module hit volumes are Area3Ds parented under the hull, each carrying its
	# own shapes. Counted separately from the body's own shapes because they sit
	# on a different physics layer (BattleLayers.UNIT_MODULES) and are queried by
	# weapons rather than by movement - so a fix that removes them helps hit
	# detection cost, not move_and_slide, and the two must not be conflated.
	var area_count := 0
	var area_shapes := 0
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Area3D:
			area_count += 1
			for c in n.get_children():
				if c is CollisionShape3D:
					area_shapes += 1
	BattleLogger.log_unit_colliders(name, team, {
		"design": str(blueprint.get("name", "")),
		"hull": _hull_type,
		"body_shapes": body_shapes,
		"module_areas": area_count,
		"module_shapes": area_shapes,
		"total_shapes": body_shapes + area_shapes,
	})


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
