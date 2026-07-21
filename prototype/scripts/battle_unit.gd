extends CharacterBody3D
# Generic team-aware combat unit for Skirmish mode.
# Built from a blueprint dictionary via BlueprintManager.reconstruct_vehicle().
# Handles: armor/threshold damage model, subsystem stripping, movement orders,
# flying locomotion, and (if a resource_harvester module is present) an
# automatic harvest -> refinery dropoff economy loop.

signal died(unit)
signal resources_delivered(team, metal, crystal)

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const GlobalConfigScript = preload("res://scripts/global_config.gd")

var team: int = 0
var max_hp: float = 400.0
var hp: float = 400.0
var is_dead: bool = false
# Energy resource (ENERGY_AND_BALANCE_SPEC.md #1): base_energy comes from
# the hull, generator modules add capacity on top - a real placeable-module
# design choice, not a fixed hull number. Regenerates over time; spent by
# firing energy-classed weapons (auto_weapon.gd checks/deducts via
# spend_energy() before it's allowed to fire) and can be drained directly
# by an enemy's energy-drain weapon (drain_energy()).
var max_energy: float = 0.0
var current_energy: float = 0.0
var energy_regen_rate: float = 0.0
var _hull_type_for_energy: String = ""
# Logistics sharing aura (ENERGY_AND_BALANCE_SPEC.md #5)
var has_logistics_tank: bool = false
var logistics_tank_strength: float = 0.0
const LOGISTICS_SHARE_RADIUS: float = 15.0
const LOGISTICS_SHARE_RATE: float = 6.0

# Fog-of-war (built this pass): hull base_vision + sensor_suite bonus,
# Technocrats-boosted. fog_hidden is set by skirmish.gd's periodic
# visibility scan (not computed locally - "am I visible" depends on every
# construct on the OPPOSING team, which only the match controller can see
# in one place) and gates both rendering (set_fog_visible()) and whether
# the opposing team's weapons can target this unit at all.
var vision_range: float = 0.0
var _hull_type_for_vision: String = ""
var fog_hidden: bool = false

var hull_node: Node3D = null
var locomotion_type: String = ""
var locomotion_settings: Dictionary = {}
var move_speed: float = 5.0
# Terrain variety task: current surface's speed multiplier for this unit's
# locomotion type (marsh/rocky/snow_mud/sand - see ModuleCatalog.
# get_terrain_speed_multiplier()), recomputed every physics tick in
# _recalculate_terrain_speed_multiplier(). Stays 1.0 (no-op) for flying/
# naval units and for any synthetic test with no real match controller -
# move_speed itself is left untouched (the base/display stat) so this is
# purely a per-tick multiplier applied where velocity is actually set.
var terrain_speed_multiplier: float = 1.0
var rotate_speed: float = 4.0
var target_altitude: float = 0.0
# Real pathfinding (built this pass) - null unless a real Skirmish match
# controller was found at setup() (see _setup_navigation()), so every
# existing synthetic test that builds a battle_unit standalone keeps
# working with plain direct-line steering, unchanged.
var nav_agent: NavigationAgent3D = null
var is_flying: bool = false
# Traits B3 (MOUNTING_AND_ARMOR_SPEC.md addendum): new movement paradigms,
# distinct from the tank-like steer-and-stop model every ground/hover unit
# uses. Derived from the trait system, not hardcoded type_id checks, so
# they generalize to whatever hull+locomotion combo is actually present.
var is_fixed_wing: bool = false
var is_naval: bool = false
# screw_drive locomotion (real historical screw-propelled vehicles) - a
# ground unit that ALSO crosses water, routed onto a combined ground+water
# navmesh (see get_amphibious_nav_map()) instead of being confined to
# ground_nav_map like every other ground/legged type. Deliberately not
# folded into is_naval: it's not buoyant/surface-locked like a naval hull,
# it drives normally on land and just isn't blocked by water.
var is_amphibious: bool = false
# Batch E task 5: real mecanum/omni-wheel locomotion - unlike every other
# ground locomotion type, an omni unit can translate in ANY direction
# without first rotating to face it (see _steer_towards()'s is_omni
# branch, which decouples velocity direction from hull facing entirely -
# every other ground type couples the two, always turning to face its
# direction of travel).
var is_omni: bool = false
# Terrain variety task: hull-level draught (ModuleCatalog.get_hull_draught()),
# only meaningful for is_naval units - see _setup_navigation() for where
# this routes a deep-draught hull onto deep_water_map instead of
# water_map, blocking it from shallow_water_areas entirely.
var hull_draught: float = 0.0
# AI phase 1 (whole-vehicle-aim): true when any active weapon is frame_built
# (fixed relative to the hull, no independent traverse - see
# module_catalog.gd's get_traverse_limit_angle/get_mount_style). Cached at
# setup instead of recomputed every physics frame, same pattern as
# is_flying/is_fixed_wing/is_naval above.
var has_frame_built_weapon: bool = false

# Orders
enum OrderType { IDLE, MOVE, ATTACK, HARVEST }
var order: OrderType = OrderType.IDLE
var move_target: Vector3 = Vector3.ZERO
var attack_target: Node3D = null

# Harvester state
var is_harvester: bool = false
var harvest_node: Node3D = null
var cargo_metal: int = 0
var cargo_crystal: int = 0
var cargo_capacity: int = 50
var harvest_timer: float = 0.0
const HARVEST_TIME: float = 3.0
# AI phase 2: back off once the enemy has closed inside this fraction of
# attack_range (see the kiting branch of the ATTACK order below).
const KITE_STANDOFF_FRACTION: float = 0.45

var selection_ring: MeshInstance3D = null
var attack_range: float = 12.0

# Auto-engage: a unit sitting IDLE (no order at all) had no way to notice a
# hostile in sight - it would just sit there, only getting whatever passive
# fire its own weapons' independent targeting happened to land. This USED to
# also divert a unit off an active MOVE order the instant it spotted a
# hostile, but Chris's spec is that a move order is inviolable - the unit
# finishes moving where it was told to go, and only starts hunting on its
# own once it's actually sitting idle (no order) for a couple of seconds
# (_idle_duration/IDLE_BEFORE_AUTO_ENGAGE below). Weapons stay free to
# fire at anything in range/arc/LOS the whole time regardless - auto_
# weapon.gd's targeting has no dependency on this unit's order state at
# all, so a moving unit still shoots at whatever it passes. Throttled (not
# every physics tick) since it's an O(n) group scan per unit. Deliberately
# does NOT touch units already under ATTACK order (leaves the existing
# kiting/flanking/wave-target priority alone) or HARVEST order (economy
# units keep working; don't turn every harvester into an accidental
# skirmisher).
var _auto_engage_scan_timer: float = 0.0
var _idle_duration: float = 0.0
const IDLE_BEFORE_AUTO_ENGAGE: float = 1.5
const AUTO_ENGAGE_SCAN_INTERVAL: float = 0.5

func _ready():
	add_to_group("units")
	add_to_group("damageable")

func setup(blueprint_data: Dictionary, unit_team: int, bp_manager: Node, match_faction: String = "") -> void:
	team = unit_team
	set_meta("team", team)
	collision_layer = 4
	collision_mask = 1 # Ground only; units pass through each other in the prototype

	var locomotion = blueprint_data.get("locomotion", {})
	locomotion_type = locomotion.get("type_id", "")
	locomotion_settings = locomotion.get("settings", {})

	# Traits B3: movement paradigm derived from the trait system (whatever
	# hull+locomotion combo is actually present), not a hardcoded type_id
	# check - this is what lets a future new hull automatically pick up the
	# right movement behavior just by carrying the right locomotion trait.
	var hull_type_for_traits = blueprint_data.get("hull_type", "medium_hull")
	var unit_traits = ModuleCatalog.get_traits(hull_type_for_traits, locomotion_type)
	is_flying = "airborne" in unit_traits
	is_fixed_wing = "fixed_wing" in unit_traits
	is_naval = "naval" in unit_traits
	is_amphibious = "amphibious" in unit_traits
	is_omni = "omni" in unit_traits
	hull_draught = ModuleCatalog.get_hull_draught(hull_type_for_traits)
	if is_flying:
		target_altitude = 4.0

	hull_node = bp_manager.reconstruct_vehicle(blueprint_data, self, false, match_faction)
	if not hull_node:
		return

	# HP via the shared hull-stat function (ModuleCatalog.compute_hull_max_hp,
	# FABLE_REVIEW.md 2.6) so combat, defenses, and the Design Lab sidebar
	# all read the same number - hull SCALE now genuinely scales HP too
	# (previously stretching a hull changed nothing but mounting area).
	var hull_type = hull_node.get_meta("type_id") if hull_node.has_meta("type_id") else "medium_hull"
	var catalog_data = ModuleCatalog.get_module_data(hull_type)
	var thick = hull_node.get_meta("armor_thickness") if hull_node.has_meta("armor_thickness") else 1.0
	var mat = hull_node.get_meta("armor_material") if hull_node.has_meta("armor_material") else "hardened_steel"
	var unit_hull_scale = hull_node.get_meta("hull_scale") if hull_node.has_meta("hull_scale") else Vector3.ONE
	var faction_for_hp = hull_node.get_meta("faction") if hull_node.has_meta("faction") else "industrialists"
	max_hp = ModuleCatalog.compute_hull_max_hp(hull_type, thick, mat, unit_hull_scale) * FactionCatalog.get_passive(faction_for_hp, "hp_mult", 1.0)
	hp = max_hp

	# Collision shape matching the hull
	var col_shape = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	var base_size = catalog_data.get("size", Vector3.ONE)
	if hull_node.has_meta("base_hull_size") and hull_node.has_meta("hull_scale"):
		base_size = hull_node.get_meta("base_hull_size") * hull_node.get_meta("hull_scale")
	var bulk = Vector3(1.0 + (thick - 1.0) * 0.15, 1.0 + (thick - 1.0) * 0.15, 1.0)
	
	var authored_hull_mesh = MeshAssetLoader.get_hull_mesh(hull_type)
	if authored_hull_mesh:
		col_shape.shape = authored_hull_mesh.create_convex_shape()
		col_shape.scale = unit_hull_scale * bulk
		col_shape.position = hull_node.position
	else:
		col_shape.scale = Vector3.ONE
		var box = BoxShape3D.new()
		box.size = base_size * bulk
		col_shape.shape = box
		col_shape.position = Vector3(0, box.size.y / 2.0, 0)
	add_child(col_shape)

	# Running-gear collider (test arena "vehicle slides on its belly" fix):
	# the hull's own collider above only covers the hull mesh, so it never
	# reached down to the wheels/treads/legs/screws bp_manager.reconstruct_
	# vehicle() just lifted the hull to make room for. Without this, the
	# CharacterBody3D's is_on_floor()/real-physics fallback (see the
	# gravity branch below) had nothing to actually rest the unit on -
	# it's a second box collider spanning the same running-gear chassis
	# ModuleCatalog.get_running_gear_size() sizes for the visual chassis,
	# so the collider's bottom now lines up with the ground contact the
	# unit is snapped to, not the bare hull belly.
	if ModuleCatalog.needs_running_gear(locomotion_type):
		var running_gear_size = ModuleCatalog.get_running_gear_size(base_size * bulk)
		var gear_shape = CollisionShape3D.new()
		gear_shape.name = "RunningGearCollisionShape3D"
		var gear_box = BoxShape3D.new()
		gear_box.size = running_gear_size
		gear_shape.shape = gear_box
		gear_shape.position = Vector3(0, hull_node.position.y - (base_size.y * bulk.y) / 2.0 - running_gear_size.y / 2.0, 0)
		add_child(gear_shape)

	_setup_weapons()
	_detect_harvester()
	_recalculate_move_speed()
	_recalculate_energy(hull_type)
	_recalculate_vision(hull_type)
	_detect_logistics_tank()
	_setup_navigation()
	_create_selection_ring(base_size)
	_create_hp_bar()

# Real pathfinding (built this pass): looks for a match controller
# (duck-typed via get_ground_nav_map()/get_water_nav_map(), so this stays
# a no-op fallback to plain direct-line steering for every existing
# synthetic test that constructs a battle_unit outside a real Skirmish
# scene - no test needed to change). Flying/fixed-wing units skip this
# entirely (open air, nothing to route around).
func _setup_navigation():
	if is_flying or is_fixed_wing:
		return
	var controller = get_parent()
	if not controller or not controller.has_method("get_ground_nav_map") or not controller.has_method("get_water_nav_map"):
		return
	nav_agent = NavigationAgent3D.new()
	add_child(nav_agent)
	# path_desired_distance: how close the agent must get to each intermediate
	# waypoint before advancing to the next one. 1.0 m gives tight path-following
	# without snapping every frame.
	# target_desired_distance: how close to the FINAL destination counts as
	# "arrived." 2.0 m matches the MOVE arrive_dist in _steer_towards so both
	# systems agree on when the trip is done - the old 1.5 m was smaller than
	# the nav agent's own path quantization in some maps, causing an oscillation
	# loop where nav said "done" but the steering code kept overriding it.
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 2.0
	nav_agent.avoidance_enabled = false
	if is_naval:
		if hull_draught > ModuleCatalog.SHALLOW_WATER_DRAUGHT_THRESHOLD and controller.has_method("get_deep_water_nav_map"):
			nav_agent.set_navigation_map(controller.get_deep_water_nav_map())
		else:
			nav_agent.set_navigation_map(controller.get_water_nav_map())
	elif is_amphibious and controller.has_method("get_amphibious_nav_map"):
		nav_agent.set_navigation_map(controller.get_amphibious_nav_map())
	else:
		nav_agent.set_navigation_map(controller.get_ground_nav_map())

# Fog-of-war (built this pass): base_vision from the hull + sum of mounted
# sensor_suite modules' vision bonus, with the Technocrats faction passive
# (+15%, Factions_and_Buildings.md - previously unimplementable since no
# vision system existed at all) applied on top. Public for the same reason
# _recalculate_energy() is - losing a sensor_suite mid-battle should
# shrink vision_range.
func _recalculate_vision(hull_type_for_vision: String = ""):
	if hull_type_for_vision != "":
		_hull_type_for_vision = hull_type_for_vision
	var base = ModuleCatalog.get_base_vision(_hull_type_for_vision)
	var bonus = 0.0
	if is_instance_valid(hull_node):
		for child in hull_node.get_children():
			if child.has_meta("module_data") and not child.is_queued_for_deletion():
				var data = child.get_meta("module_data")
				if data.type_id == "sensor_suite":
					bonus += data.get_vision_bonus()
	vision_range = base + bonus
	var faction = hull_node.get_meta("faction", "industrialists") if is_instance_valid(hull_node) else "industrialists"
	vision_range *= FactionCatalog.get_passive(faction, "vision_mult", 1.0)

# Logistics sharing aura (ENERGY_AND_BALANCE_SPEC.md #5): "not just
# self-sufficiency" per Chris's instruction - logistics_tank does nothing
# for the carrying unit beyond its existing capacity contribution, its
# whole value is boosting nearby allies' energy regen.
func _detect_logistics_tank():
	has_logistics_tank = false
	logistics_tank_strength = 0.0
	if not is_instance_valid(hull_node): return
	for child in hull_node.get_children():
		if child.has_meta("module_data"):
			var data = child.get_meta("module_data")
			if data.type_id == "logistics_tank":
				has_logistics_tank = true
				logistics_tank_strength += data.tweaks.get("tank_capacity", 1.0)

# Energy resource: base_energy from the hull + sum of mounted generator
# modules' energy_capacity/energy_regen. Public (not just called at setup)
# because losing a generator module mid-battle should shrink max_energy -
# call sites that queue_free() a module should re-call this, same pattern
# take_damage()'s subsystem-stripping branch uses for _recalculate_move_speed().
func _recalculate_energy(hull_type_for_energy: String = ""):
	if hull_type_for_energy != "":
		_hull_type_for_energy = hull_type_for_energy
	var base = ModuleCatalog.get_base_energy(_hull_type_for_energy)
	var bonus_capacity = 0.0
	var bonus_regen = 0.0
	if is_instance_valid(hull_node):
		for child in hull_node.get_children():
			if child.has_meta("module_data") and not child.is_queued_for_deletion():
				var data = child.get_meta("module_data")
				if data.category == "generator":
					bonus_capacity += data.get_energy_capacity()
					bonus_regen += data.get_energy_regen()
	var prev_max = max_energy
	max_energy = base + bonus_capacity
	# Base passive regen (a small % of max/sec) plus generators' own bonus -
	# a unit with zero generators still trickle-regens off its base pool,
	# gennies just make sustained energy-weapon fire actually viable.
	energy_regen_rate = max_energy * 0.08 + bonus_regen
	if prev_max <= 0.0:
		current_energy = max_energy
	else:
		current_energy = clamp(current_energy, 0.0, max_energy)

func _setup_weapons():
	var min_weapon_range = INF
	for child in hull_node.get_children():
		if child.has_meta("module_data"):
			var data = child.get_meta("module_data")
			if ModuleCatalog.needs_combat_script(data.type_id):
				var weapon_script = load("res://scripts/auto_weapon.gd")
				child.set_script(weapon_script)
				child.set_physics_process(true)
				child._ready()
				# Standoff distance for the ATTACK order's approach-and-stop
				# (see that branch below): the SHORTEST-ranged offensive
				# weapon's range, not the longest. The old "track the
				# longest" behavior parked a mixed loadout (e.g. a
				# long-range cluster_dispenser alongside short-range
				# machine guns/cannons) right at the edge of its single
				# longest weapon's reach - every shorter-range weapon then
				# sat permanently out of range, perpetually idle ("sits in
				# view of a target, neither attacks nor maneuvers" - most of
				# its own arsenal literally couldn't reach). The long-range
				# weapon isn't shortchanged by closing in further - it's
				# already firing independently throughout the approach
				# regardless of the unit's own order state (auto_weapon.gd's
				# targeting has no dependency on it), so stopping closer
				# just means it started shooting even earlier. Only real
				# offensive weapons count - repair_array/drone_carrier/etc
				# ("module", not "weapon") have their own auto_weapon.gd-
				# driven range for healing/support and shouldn't drag the
				# whole unit's engagement distance down to theirs.
				# The ATTACK order's approach/hold distance (attack_range,
				# below) is measured from the HULL's center, but a weapon's
				# own fire_range is measured from wherever it's actually
				# mounted - which can be meters away from hull center on a
				# large hull (e.g. a tail-mounted gun on a 16m airship).
				# Subtracting the weapon's own local-position magnitude
				# (its worst-case distance from hull center) before taking
				# the range floor means the hull stops close enough that
				# even an off-center weapon's REAL target distance still
				# fits inside its fire_range, not just the hull-center
				# distance - otherwise the unit could park at a range that
				# looks fine from its own center while every off-center
				# weapon is actually still a few meters short of reaching,
				# and never gets any closer once it's decided it's "in
				# range."
				if data.category == "weapon" and "fire_range" in child:
					var effective_range = child.fire_range - child.position.length()
					min_weapon_range = min(min_weapon_range, effective_range)
				# Reuse the traverse angle auto_weapon.gd just computed (single
				# source of truth) rather than re-deriving mount_style here.
				if "traverse_limit_angle" in child and child.traverse_limit_angle <= 0.001:
					has_frame_built_weapon = true
	if min_weapon_range < INF:
		# Floored at 2.0: an extreme mount offset (fire_range barely bigger
		# than the weapon's own distance from hull center, or smaller)
		# could otherwise drive this to zero or negative, which would make
		# the ATTACK order's "dist > attack_range" approach check always
		# true and the unit would try to close to point-blank forever.
		attack_range = max(min_weapon_range * 0.85, 2.0)

func _detect_harvester():
	for child in hull_node.get_children():
		if child.has_meta("module_data"):
			var data = child.get_meta("module_data")
			if data.type_id == "resource_harvester":
				is_harvester = true
				var extractor = data.tweaks.get("extractor_size", 1.0)
				cargo_capacity = int(50 * extractor)
				break

func _recalculate_move_speed():
	if not is_instance_valid(hull_node):
		return
	# Hull weight is REAL now (FABLE_REVIEW.md 1.2): the hull's own mass -
	# including its armor material/thickness and the Industrialists'
	# armor-weight discount, which was previously display-only - enters the
	# same weight total the thrust and overload math read. Armoring up
	# finally costs speed in combat, not just in the sidebar label.
	var speed_hull_type = hull_node.get_meta("type_id", "medium_hull")
	var speed_thick = hull_node.get_meta("armor_thickness") if hull_node.has_meta("armor_thickness") else 1.0
	var speed_mat = hull_node.get_meta("armor_material") if hull_node.has_meta("armor_material") else "hardened_steel"
	var speed_hull_scale = hull_node.get_meta("hull_scale") if hull_node.has_meta("hull_scale") else Vector3.ONE
	var speed_faction = hull_node.get_meta("faction") if hull_node.has_meta("faction") else "industrialists"
	var armor_wt_mult = FactionCatalog.get_passive(speed_faction, "armor_weight_mult", 1.0)
	var total_weight = ModuleCatalog.compute_hull_weight(speed_hull_type, speed_thick, speed_mat, speed_hull_scale, armor_wt_mult)
	var motor_thrust = 100.0
	var total_weight_capacity = 0.0
	var has_locomotion = false
	for child in hull_node.get_children():
		if child.has_meta("module_data") and not child.is_queued_for_deletion():
			var data = child.get_meta("module_data")
			total_weight += data.get_weight()
			if data.category == "locomotion":
				has_locomotion = true
				# Batch E: axle-count/leg-count/tread-width tweaks now carry
				# a REAL tradeoff instead of a single shared multiplier -
				# thrust and capacity can move in opposite directions.
				# wheels/helicopter_rotors: more of them = proportionally
				# more of both (a straightforward "bigger rig" scale-up,
				# no tradeoff - matches how axle count already worked
				# before this pass).
				# legs: more legs = more capacity (broader stance, more
				# load-bearing contact points) but LESS thrust per leg
				# once you're past 4 (more mechanical mass/drag to
				# coordinate) - fewer legs trades stability for agility,
				# per Chris's ask.
				# tracked_treads: width already drove capacity before
				# (wider = more contact area = more capacity, kept as-is);
				# now ALSO trades against thrust (wider = more friction/
				# less top speed, narrower = lighter and faster) instead
				# of boosting both together.
				var thrust_contrib = 1.0
				var capacity_contrib = 1.0
				if locomotion_type == "wheels" or locomotion_type == "omni_wheels" or locomotion_type == "helicopter_rotors":
					var c = float(locomotion_settings.get("count", 4)) / 4.0
					thrust_contrib = c
					capacity_contrib = c
				elif locomotion_type == "legs":
					var leg_count = float(locomotion_settings.get("count", 4))
					capacity_contrib = leg_count / 4.0
					thrust_contrib = 1.0 + (4.0 - leg_count) / 8.0
				elif locomotion_type == "tracked_treads" or locomotion_type == "rhomboid_treads":
					var width = locomotion_settings.get("width", 1.0)
					capacity_contrib = width
					thrust_contrib = 1.0 + (1.0 - width) * 0.5
				motor_thrust += ModuleCatalog.get_thrust_coefficient(data.type_id) * child.scale.x * child.scale.z * thrust_contrib
				# Weight capacity scales with the size/count/width factor
				# above (a bigger/wider tread, more legs, or a 6-wheel
				# setup carries more than a stock 4-wheel one), per-
				# locomotor-type base from ModuleCatalog.get_base_weight_capacity().
				total_weight_capacity += ModuleCatalog.get_base_weight_capacity(data.type_id) * child.scale.x * child.scale.z * capacity_contrib
			# Mobility add-on modules (wing/thruster/propeller_prop/
			# pusher_prop/paddle_wheel/ship_screw) - attachable, not a
			# primary locomotion choice, so they contribute regardless of
			# category: wings raise the weight budget before the overload
			# penalty kicks in, the rest add real extra thrust on top of
			# whatever the primary locomotion provides.
			var mod_catalog = ModuleCatalog.get_module_data(data.type_id)
			var wc_bonus = mod_catalog.get("weight_capacity_bonus", 0.0)
			var thrust_bonus = mod_catalog.get("thrust_bonus", 0.0)
			if wc_bonus > 0.0:
				total_weight_capacity += wc_bonus * child.scale.x * child.scale.z
			if thrust_bonus > 0.0:
				motor_thrust += thrust_bonus * child.scale.x * child.scale.z
	if not has_locomotion:
		move_speed = 0.0
		return
	if total_weight > 0.0:
		# Constant retuned 5.0 -> 10.0 alongside hull weight entering the
		# denominator (roughly doubles typical totals), so a baseline bundled
		# design keeps close to its old speed. Band widened (was 2.0-15.0):
		# light builds were all converging on the old 15.0 ceiling, erasing
		# thrust/weight differences between "different fast scouts"
		# (FABLE_REVIEW.md 1.4), and the floor drops so a grossly overbuilt
		# brick is genuinely slower than a merely heavy one.
		move_speed = clamp((motor_thrust / total_weight) * 10.0, 1.5, 18.0)
	# Overload penalty (task: "make the overall vehicle Weight stat actually
	# matter"): weight beyond what the locomotion present is built for slows
	# the unit down, on top of the thrust/weight ratio above. No penalty at
	# or under capacity (multiplier 1.0). Beyond it, each 100% over capacity
	# costs 60% of remaining speed, floored at 25% so overload is a real,
	# punishing penalty without ever fully freezing a unit in place (that
	# would look like a bug, not a balance mechanic).
	if total_weight_capacity > 0.0 and total_weight > total_weight_capacity:
		var overload_ratio = total_weight / total_weight_capacity
		var overload_multiplier = clamp(1.0 - (overload_ratio - 1.0) * 0.6, 0.25, 1.0)
		move_speed *= overload_multiplier
	# Faction passive - table-driven (FactionCatalog.get_passive), covers
	# every faction's own speed_mult (only technocrats/berserkers set one;
	# everyone else falls through to the 1.0 default, unchanged).
	var faction = hull_node.get_meta("faction") if hull_node.has_meta("faction") else "industrialists"
	move_speed *= FactionCatalog.get_passive(faction, "speed_mult", 1.0)
	# Aerodrome Cartel passive: only applies to genuinely airborne units -
	# a ground vehicle designed under this faction gets no speed change.
	if is_flying:
		move_speed *= FactionCatalog.get_passive(faction, "air_speed_mult", 1.0)

# Terrain variety task: surface terrain (marsh/rocky/snow_mud/sand) slows or
# favors specific locomotion types - this looks up the CURRENT tile every
# physics tick (position changes constantly, unlike move_speed which is
# only recomputed when the design changes) and stores the multiplier for
# the velocity-setting code below to apply. Flying/naval units never touch
# ground surface terrain (is_flying skips this entirely; is_naval's
# "surface" is water, which has no surface_zones), so both stay at the
# default 1.0. Duck-typed like get_ground_nav_map()/terrain_height_at() -
# every synthetic test without a real match controller falls through to
# the harmless 1.0 default, unchanged.
func _recalculate_terrain_speed_multiplier():
	if is_flying or is_naval:
		terrain_speed_multiplier = 1.0
		return
	var controller = get_parent()
	if not controller or not controller.has_method("get_surface_type_at"):
		terrain_speed_multiplier = 1.0
		return
	var surface_type = controller.get_surface_type_at(global_position)
	if surface_type == "":
		terrain_speed_multiplier = 1.0
		return
	terrain_speed_multiplier = ModuleCatalog.get_terrain_speed_multiplier(locomotion_type, surface_type)
	# Batch E: tread width now also modulates the terrain multiplier itself,
	# not just capacity/thrust - a wider track spreads weight over more
	# contact area (real flotation, less sinking), so it eats further into
	# whatever penalty the base table already assigns; a narrower track
	# digs in more and eats further into it. Only shifts the number tracked_
	# treads already has for this surface, doesn't grant terrain immunity
	# (clamped at 1.2, so even a max-width tread stays "notably better",
	# not "as good as being on pavement").
	if locomotion_type == "tracked_treads" or locomotion_type == "rhomboid_treads":
		var width = locomotion_settings.get("width", 1.0)
		var width_delta = (width - 1.0) * 0.25
		terrain_speed_multiplier = clamp(terrain_speed_multiplier + width_delta, 0.15, 1.2)

	# Glacier Syndicate passive: negates a fraction of whatever terrain
	# penalty is currently in effect (a multiplier BELOW 1.0 - a bonus above
	# 1.0, e.g. screw_drive's marsh bonus, is left untouched, since "reduced
	# penalty" only means something for an actual penalty).
	if terrain_speed_multiplier < 1.0 and is_instance_valid(hull_node):
		var terrain_faction = hull_node.get_meta("faction") if hull_node.has_meta("faction") else "industrialists"
		var reduction = FactionCatalog.get_passive(terrain_faction, "terrain_penalty_reduction", 0.0)
		if reduction > 0.0:
			terrain_speed_multiplier = 1.0 - (1.0 - terrain_speed_multiplier) * (1.0 - reduction)

func _create_selection_ring(base_size: Vector3):
	selection_ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	var radius = max(base_size.x, base_size.z) * 0.65
	torus.inner_radius = radius - 0.12
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

var hp_bar: Label3D = null
func _create_hp_bar():
	hp_bar = Label3D.new()
	hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_bar.font_size = 22
	hp_bar.outline_size = 5
	hp_bar.position = Vector3(0, 2.6, 0)
	add_child(hp_bar)
	_update_hp_bar()

func _update_hp_bar():
	if not is_instance_valid(hp_bar): return
	var pct = clamp(hp / max_hp, 0.0, 1.0)
	var filled = int(pct * 8.0)
	var bar = ""
	for i in range(filled): bar += "■"
	for i in range(8 - filled): bar += "□"
	if is_harvester and (cargo_metal > 0 or cargo_crystal > 0):
		bar += " ⛏"
	hp_bar.text = bar
	hp_bar.modulate = (Color.GREEN if team == 0 else Color.ORANGE_RED).lerp(Color.RED, 1.0 - pct)

func set_selected(selected: bool):
	if is_instance_valid(selection_ring):
		selection_ring.visible = selected

# Fog-of-war: toggles rendering only (.visible cascades to every child -
# hull mesh, HP bar, selection ring). Physics/processing/take_damage all
# keep working normally while hidden; a fog-hidden unit still exists and
# can still be hit by something that already has a lock on it (e.g. a
# missile mid-flight), it just can't be newly targeted or seen. fog_hidden
# itself is set by skirmish.gd's periodic visibility scan.
func set_fog_visible(is_visible: bool):
	fog_hidden = not is_visible
	visible = is_visible

func order_move(dest: Vector3):
	order = OrderType.MOVE
	move_target = dest
	attack_target = null

func order_attack(node: Node3D):
	order = OrderType.ATTACK
	attack_target = node

func order_harvest(node: Node3D):
	if not is_harvester: return
	order = OrderType.HARVEST
	harvest_node = node
	harvest_timer = 0.0

func _try_auto_engage(delta: float):
	# Move orders are inviolable (see the field comment above) - only an
	# idle unit (no order) is ever a candidate to start hunting on its own,
	# and only after it's stayed idle for IDLE_BEFORE_AUTO_ENGAGE straight
	# seconds. Any other order (MOVE, ATTACK, HARVEST) resets the idle
	# clock and bails immediately.
	if order == OrderType.IDLE:
		_idle_duration += delta
	else:
		_idle_duration = 0.0
		_auto_engage_scan_timer = 0.0 # re-scan right away next time it goes idle
		return

	if is_harvester or _idle_duration < IDLE_BEFORE_AUTO_ENGAGE:
		return
	_auto_engage_scan_timer -= delta
	if _auto_engage_scan_timer > 0.0:
		return
	_auto_engage_scan_timer = AUTO_ENGAGE_SCAN_INTERVAL

	# "Closest enemy IN SIGHT" (Chris's spec) - not just closest by raw
	# distance. fog_hidden already filters to what the team has scouted, but
	# a scouted-but-currently-behind-a-rock-or-building enemy still passed
	# that filter, so the unit could commit to (and path/turn toward) a
	# target it structurally can't see or engage yet while ignoring a
	# farther one it could start closing on immediately. Tracks both the
	# closest overall AND the closest with a real, unblocked sightline;
	# prefers the latter, falling back to the former only when NOTHING
	# in range currently has a clear line (so auto-engage still functions
	# rather than going permanently idle the instant every scouted enemy
	# happens to be terrain-occluded).
	var closest: Node3D = null
	var closest_dist: float = vision_range
	var closest_visible: Node3D = null
	var closest_visible_dist: float = vision_range
	for c in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(c) or c == self:
			continue
		if "is_dead" in c and c.is_dead:
			continue
		var c_team = c.get_meta("team") if c.has_meta("team") else -1
		if c_team == team:
			continue
		if "fog_hidden" in c and c.fog_hidden:
			continue
		var dist = global_position.distance_to(c.global_position)
		if dist < closest_dist:
			closest = c
			closest_dist = dist
		if dist < closest_visible_dist and _has_clear_sightline_to(c):
			closest_visible = c
			closest_visible_dist = dist

	var engage_target = closest_visible if closest_visible else closest
	if engage_target:
		order_attack(engage_target)

# Recursively collects CollisionObject3D RIDs under a node, for LOS raycast
# exclude lists. Mirrors auto_weapon.gd's own _get_colliders_recursive (kept
# as a separate small copy here rather than a shared module - it's a 6-line
# utility, not worth factoring out for).
func _get_colliders_recursive(node: Node, list: Array):
	if node is CollisionObject3D:
		list.append(node.get_rid())
	for child in node.get_children():
		_get_colliders_recursive(child, list)

# Coarse "can this unit actually see that candidate" check for auto-engage
# target SELECTION (deciding which enemy to drive toward) - distinct from
# auto_weapon.gd's per-weapon muzzle-level LOS, which gates actual firing
# once a unit is already engaged. Ray from roughly hull-center height to the
# candidate's center; blocked by world geometry/obstacles (layer 1), modules
# (layer 2), or buildings (layer 8) - same layer convention auto_weapon.gd's
# LOS check uses. Units (layer 4) are deliberately excluded from the mask
# for the same reason as there: some OTHER unit standing in the way doesn't
# mean this candidate is unseeable, just that there's something closer.
# Terrain elevation (hills/ramps) has no real collider at all (see
# terrain_builder.gd's header) so it never factors in here either way -
# this only ever catches actual obstacle props and buildings.
func _has_clear_sightline_to(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate):
		return false
	var space_state = get_world_3d().direct_space_state
	var ray_start = global_position + Vector3(0, 1.0, 0)
	var ray_end = candidate.global_position + Vector3(0, 0.5, 0)
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1 + 2 + 8 # Ground/obstacles, Modules, Buildings - not units
	query.collide_with_areas = true
	var excluded = []
	_get_colliders_recursive(self, excluded)
	_get_colliders_recursive(candidate, excluded)
	query.exclude = excluded
	var result = space_state.intersect_ray(query)
	return result.is_empty()

func _physics_process(delta):
	if is_dead: return

	_recalculate_terrain_speed_multiplier()
	_try_auto_engage(delta)

	if current_energy < max_energy:
		current_energy = min(max_energy, current_energy + energy_regen_rate * delta)
	if has_logistics_tank:
		_share_energy_with_allies(delta)

	# Altitude / gravity / surface-lock
	if is_flying:
		velocity.y = 0.0
		global_position.y = lerp(global_position.y, target_altitude, 3.0 * delta)
	elif is_naval:
		# Traits B3: surface-locked like flying units, not affected by
		# gravity/floor detection the way ground locomotion is - there's no
		# terrain-height/water system in this prototype, so "the surface"
		# is just a fixed low waterline.
		velocity.y = 0.0
		global_position.y = lerp(global_position.y, 0.3, 3.0 * delta)
	else:
		var terrain_controller = get_parent()
		if terrain_controller and terrain_controller.has_method("terrain_height_at"):
			# Real multi-map terrain: elevation Y is analytic
			# (terrain_builder.gd's terrain_height_at()), not physics-
			# collided - ramps/plateaus have no real CollisionShape3D (see
			# that file's header for why), so gravity/is_on_floor() would
			# just free-fall a unit standing on one. Smoothly lerps toward
			# the correct height instead, decoupled from gravity entirely
			# so the two systems can't fight over ground that has no real
			# collision floor. Duck-typed same as get_ground_nav_map() -
			# every synthetic test without a real match controller falls
			# through to the old gravity-only behavior below, unchanged.
			velocity.y = 0.0
			var target_y = terrain_controller.terrain_height_at(global_position)
			# Snap hard when significantly off the ground (spawn, teleport, or a
			# large terrain step) so the vehicle never "slides on its belly" for
			# half a second waiting for a slow lerp to converge. Use a fast lerp
			# for small corrections (rolling over surface undulations) so the
			# motion still looks smooth rather than jittery.
			var y_error = target_y - global_position.y
			if abs(y_error) > 0.5:
				global_position.y = target_y
			else:
				global_position.y += y_error * min(12.0 * delta, 1.0)
		elif not is_on_floor():
			velocity.y -= 9.8 * delta
		else:
			velocity.y = -1.0

	match order:
		OrderType.MOVE:
			if is_fixed_wing:
				_steer_fixed_wing(move_target, delta)
				if global_position.distance_to(move_target) < attack_range:
					order = OrderType.IDLE
			# arrive_dist = 2.0 m matches nav_agent.target_desired_distance so the
			# two systems agree on "arrived" - the old 0.6 m was smaller than the
			# nav agent's own finish threshold, causing a tight circle where
			# nav_agent.is_navigation_finished() returned true but direct steering
			# thought the unit was still 0.6-1.5 m away.
			elif _steer_towards(move_target, delta, 2.0):
				order = OrderType.IDLE
		OrderType.ATTACK:
			if not is_instance_valid(attack_target) or ("is_dead" in attack_target and attack_target.is_dead):
				attack_target = null
				order = OrderType.IDLE
			elif is_fixed_wing:
				# Strafing run, not approach-and-stop (a plane can't hover):
				# continuously orbit the target so the flight path naturally
				# brings it back within weapon range on each pass, instead
				# of the ground-unit approach-and-engage pattern.
				var orbit_phase = fmod(Time.get_ticks_msec() / 1000.0 * 0.3 + float(get_instance_id() % 100) * 0.1, TAU)
				var orbit_offset = Vector3(cos(orbit_phase), 0, sin(orbit_phase)) * attack_range * 1.5
				_steer_fixed_wing(attack_target.global_position + orbit_offset, delta)
			else:
				var dist = global_position.distance_to(attack_target.global_position)
				if dist > attack_range:
					# Armor phase 5: approach the target's weakest facet
					# instead of walking straight at it, so a player's
					# directional armor design decisions actually matter in
					# Skirmish (previously only a human in Test Range could
					# exploit facing; the AI never tried). Applies to both
					# teams equally - same steering code runs for player and
					# enemy units, no AI-only special case.
					var approach_point = _compute_flank_point(attack_target)
					_steer_towards(approach_point, delta, attack_range * 0.9)
				elif has_frame_built_weapon:
					# AI phase 1 (whole-vehicle-aim): a frame_built weapon
					# can't aim itself - the whole hull has to keep turning
					# to bring it to bear, even after arriving in range,
					# like a casemate tank destroyer traversing by driving.
					velocity.x = 0.0
					velocity.z = 0.0
					_turn_toward(attack_target.global_position, delta)
				elif dist < attack_range * KITE_STANDOFF_FRACTION:
					# AI phase 2 (kiting): a turreted weapon aims
					# independently of hull facing, so a ranged unit that's
					# been closed on past its comfortable standoff distance
					# can back off to restore it while still tracking/
					# firing - instead of standing still and eating hits at
					# melee range that its weapon range was meant to avoid.
					#
					# Kiting phase 2 (facet-aware): always reposition to
					# keep the STRONGEST facet toward the attacker while
					# retreating, rather than a plain straight-back retreat
					# (which turns to face the travel direction and leaves
					# whichever facet ends up opposite entirely to chance -
					# it could be the weakest one). _kite_reposition()
					# recomputes its target every frame from whichever
					# facet is currently strongest, so it's self-
					# stabilizing once achieved - an earlier version tried
					# to hand off to plain _steer_towards() once the good
					# facet was reached, but that immediately undid the
					# positioning (steer_towards has its own, different
					# idea of what to face: the travel direction, not the
					# attacker). When every facet is equal (no armor
					# modules), "strongest" is an arbitrary tie-break
					# (front), which just means facing the attacker while
					# backing away - still a reasonable default, not a
					# regression from plain retreat.
					_kite_reposition(delta)
				else:
					velocity.x = 0.0
					velocity.z = 0.0
		OrderType.HARVEST:
			_process_harvest(delta)
		_:
			if is_fixed_wing:
				# Can't stop - hold the current heading and keep cruising
				# instead of zeroing velocity like ground/hover units do
				# when idle (minimum airspeed).
				var forward_dir = -global_transform.basis.z.normalized()
				velocity.x = forward_dir.x * move_speed
				velocity.z = forward_dir.z * move_speed
			else:
				velocity.x = 0.0
				velocity.z = 0.0
			if is_harvester:
				_auto_find_harvest_work()

	move_and_slide()

	# Spin rotors. Loosened from "is_flying only" to any hull_node, since
	# propellers/screws apply to naval and amphibious units too, not just
	# airborne ones - each arm below decides for itself whether to spin.
	if is_instance_valid(hull_node):
		for child in hull_node.get_children():
			if not child.has_meta("module_data"): continue
			var child_type_id = child.get_meta("module_data").type_id
			if child_type_id == "helicopter_rotors":
				# Named "RotorBlades" pivot (visual_builder.gd's
				# _attach_rotor_blades) - previously reached in via
				# get_child(0), which actually grabbed the static shaft (the
				# shaft is built before the blades), not the blades, so the
				# rotor never visibly spun. Flag-gated (like auto_weapon.gd's
				# BarrelCluster fix) to keep today's exact behavior, bug
				# included, when the flag is off - this is purely an A/B
				# visual toggle, not a silent behavior change.
				if GlobalConfigScript.enable_animated_monolithic_parts:
					var rotor = child.get_node_or_null("RotorBlades")
					if rotor:
						rotor.rotate_y(15.0 * delta)
				elif child.get_child_count() > 0 and is_instance_valid(child.get_child(0)):
					child.get_child(0).rotate_y(15.0 * delta)
			elif child_type_id == "ornithopter_wing":
				# Flapping motion: an oscillating (not continuous) rotation
				# on the WingPivot node visual_builder.gd built the membrane/
				# tip/ribs under - a sine wave rather than rotate_y's steady
				# spin, since a wing flaps back and forth, it doesn't rotate
				# through a full circle like a rotor blade.
				var pivot = child.get_node_or_null("WingPivot")
				if pivot:
					pivot.rotation.x = sin(Time.get_ticks_msec() / 1000.0 * 8.0) * 0.35
			elif GlobalConfigScript.enable_animated_monolithic_parts and child_type_id in ["propeller_prop", "pusher_prop", "naval_propeller", "ship_screw", "paddle_wheel"]:
				# New continuous idle spin for the prop-style locomotion
				# add-ons (previously fully static in every path) - flag-
				# gated since this is a genuinely new visual, not a bugfix
				# to existing behavior like the two arms above.
				var prop = child.get_node_or_null("PropBlades")
				if prop:
					if child_type_id == "paddle_wheel":
						prop.rotate_x(10.0 * delta)
					else:
						prop.rotate_z(10.0 * delta)

# Returns true when arrived. The "arrived" check always uses the real
# final destination; the per-frame STEERING direction uses the navmesh's
# next waypoint when a nav_agent is set up (real pathfinding, built this
# pass), falling back to the old direct-line behavior otherwise (flying
# units, or any synthetic/test context with no real Skirmish controller).
func _steer_towards(dest: Vector3, delta: float, arrive_dist: float) -> bool:
	var pos_diff = dest - global_position
	pos_diff.y = 0.0
	if pos_diff.length() < arrive_dist:
		velocity.x = 0.0
		velocity.z = 0.0
		return true
	if move_speed <= 0.0:
		return false

	var steer_diff = pos_diff
	if is_instance_valid(nav_agent):
		if nav_agent.target_position.distance_to(dest) > 0.1:
			nav_agent.target_position = dest
		if not nav_agent.is_navigation_finished():
			var next_point = nav_agent.get_next_path_position()
			var candidate = next_point - global_position
			candidate.y = 0.0
			if candidate.length() > 0.05:
				steer_diff = candidate
		else:
			# Nav agent has declared the trip done. If we're also within the
			# nav agent's own finish radius (regardless of the caller's
			# arrive_dist), stop here. Without this guard the unit switches to
			# raw direct steering toward a destination that is 0–2 m away,
			# overshoots, and loops in a tight circle.
			if pos_diff.length() < max(arrive_dist, nav_agent.target_desired_distance):
				velocity.x = 0.0
				velocity.z = 0.0
				return true

	if is_omni:
		# The real mechanical difference (task 5): every other ground type
		# rotates the hull to face its travel direction, then moves along
		# its own local forward - facing and velocity direction are the
		# same vector. An omni unit's rollers let it push in any direction
		# regardless of which way the chassis is pointed, so velocity is
		# set directly from the (nav-agent-adjusted) direction to the
		# destination and the hull's rotation is left untouched entirely -
		# it can drive straight sideways while still facing whatever way
		# it already was, which a normal wheeled/tracked/legged unit
		# structurally cannot do.
		var omni_dir = steer_diff.normalized()
		velocity.x = omni_dir.x * move_speed * terrain_speed_multiplier
		velocity.z = omni_dir.z * move_speed * terrain_speed_multiplier
		return false

	var target_basis = Basis.looking_at(steer_diff, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, rotate_speed * delta).orthonormalized()
	var forward_dir = -global_transform.basis.z.normalized()
	velocity.x = forward_dir.x * move_speed * terrain_speed_multiplier
	velocity.z = forward_dir.z * move_speed * terrain_speed_multiplier
	return false

# AI phase 1: rotates the whole hull to face a point without moving toward
# it - same yaw math as _steer_towards() but no velocity, since this is used
# by a frame_built unit that has already arrived and just needs to keep its
# fixed-forward weapon bearing on a target that may still be moving.
func _turn_toward(dest: Vector3, delta: float):
	var pos_diff = dest - global_position
	pos_diff.y = 0.0
	if pos_diff.length() < 0.05:
		return
	var target_basis = Basis.looking_at(pos_diff, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, rotate_speed * delta).orthonormalized()

# Kiting phase 2: strafes directly away from the attacker (translation)
# while independently rotating (like _turn_toward) toward whatever heading
# would put the unit's STRONGEST facet between it and the attacker,
# instead of _steer_towards()'s coupled behavior where facing is always
# whatever direction the unit happens to be moving. The two are decoupled
# on purpose - a ground vehicle "strafing" isn't realistic tread physics,
# but this codebase already treats janky-but-functional emergent movement
# as acceptable (see the no-hard-blocking trait philosophy), and the
# alternative (a literal reverse-gear drive mode) is a bigger addition for
# the same practical outcome.
func _kite_reposition(delta: float):
	var dir_to_attacker = attack_target.global_position - global_position
	dir_to_attacker.y = 0.0
	if dir_to_attacker.length() < 0.05:
		return
	dir_to_attacker = dir_to_attacker.normalized()

	var extremes = _my_facet_extremes()
	var facet_normal = FACET_NORMALS[extremes.strongest]
	# Same yaw that rotates facet_normal onto dir_to_attacker, applied to
	# FORWARD too (both live in the same local frame, so one rotation
	# solves both) - see PROGRESS.md for the derivation.
	var yaw = facet_normal.signed_angle_to(dir_to_attacker, Vector3.UP)
	var desired_forward = Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var target_basis = Basis.looking_at(desired_forward, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, rotate_speed * delta).orthonormalized()

	if move_speed > 0.0:
		var away_dir = -dir_to_attacker
		velocity.x = away_dir.x * move_speed * terrain_speed_multiplier
		velocity.z = away_dir.z * move_speed * terrain_speed_multiplier
	else:
		velocity.x = 0.0
		velocity.z = 0.0

# Traits B3: fixed-wing flight is a genuinely different movement model from
# _steer_towards(), not a reskin - never arrives-and-stops (minimum
# airspeed/stall speed), and banks (rolls) into turns instead of just
# yawing flat like a tank/hover unit turning in place.
func _steer_fixed_wing(dest: Vector3, delta: float):
	var pos_diff = dest - global_position
	if pos_diff.length() < 0.1:
		pos_diff = -global_transform.basis.z # avoid a degenerate look-at when already at the destination

	var target_basis = Basis.looking_at(pos_diff, Vector3.UP)
	var current_forward = -global_transform.basis.z
	var desired_forward = -target_basis.z
	var turn_amount = current_forward.signed_angle_to(desired_forward, Vector3.UP)

	global_transform.basis = global_transform.basis.slerp(target_basis, rotate_speed * delta).orthonormalized()

	# Bank (roll) into the turn, proportional to how sharply it's turning
	# this frame - purely visual, recomputed fresh each frame so it doesn't
	# accumulate error from the yaw slerp above.
	var bank_angle = clamp(turn_amount * 3.0, -PI / 3.0, PI / 3.0)
	global_transform.basis = global_transform.basis.rotated(current_forward.normalized(), bank_angle)

	# Never stops: move_speed IS the minimum airspeed for this unit - there
	# is no "arrive and halt" state like ground/hover locomotion has.
	var forward_dir = -global_transform.basis.z.normalized()
	velocity.x = forward_dir.x * move_speed
	velocity.z = forward_dir.z * move_speed

# --- Harvest loop ---

func _auto_find_harvest_work():
	if cargo_metal + cargo_crystal >= cargo_capacity:
		order = OrderType.HARVEST
		return
	var nodes = get_tree().get_nodes_in_group("resource_nodes")
	var best: Node3D = null
	var best_dist := INF
	for n in nodes:
		if is_instance_valid(n) and n.amount > 0:
			var d = global_position.distance_to(n.global_position)
			if d < best_dist:
				best = n
				best_dist = d
	if best:
		order_harvest(best)

func _process_harvest(delta):
	# Full? Head to nearest friendly refinery.
	if cargo_metal + cargo_crystal >= cargo_capacity or (not is_instance_valid(harvest_node)) or (is_instance_valid(harvest_node) and harvest_node.amount <= 0 and cargo_metal + cargo_crystal > 0):
		var refinery = _find_nearest_refinery()
		if not refinery:
			velocity.x = 0.0
			velocity.z = 0.0
			return
		if _steer_towards(refinery.global_position, delta, 4.5):
			emit_signal("resources_delivered", team, cargo_metal, cargo_crystal)
			cargo_metal = 0
			cargo_crystal = 0
			_update_hp_bar()
			order = OrderType.IDLE
		return

	if not is_instance_valid(harvest_node) or harvest_node.amount <= 0:
		order = OrderType.IDLE
		return

	# Drive to the node, then extract over time
	if _steer_towards(harvest_node.global_position, delta, 3.0):
		harvest_timer += delta
		if harvest_timer >= HARVEST_TIME:
			harvest_timer = 0.0
			var want = cargo_capacity - (cargo_metal + cargo_crystal)
			var faction_for_harvest = hull_node.get_meta("faction") if is_instance_valid(hull_node) and hull_node.has_meta("faction") else "industrialists"
			var harvest_chunk = int(25 * FactionCatalog.get_passive(faction_for_harvest, "harvest_rate_mult", 1.0))
			var got = harvest_node.harvest(min(harvest_chunk, want))
			if harvest_node.resource_type == "crystal":
				cargo_crystal += got
			else:
				cargo_metal += got
			_update_hp_bar()

func _find_nearest_refinery() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.is_dead and b.team == team and b.kind in ["refinery", "hq"]:
			var d = global_position.distance_to(b.global_position)
			if d < best_dist:
				best = b
				best_dist = d
	return best

# --- Damage model (mirrors player_vehicle.gd) ---

func get_active_modules() -> Array:
	var list = []
	if is_instance_valid(hull_node):
		for child in hull_node.get_children():
			if child.has_meta("module_data") and not child.is_queued_for_deletion():
				list.append(child)
	return list

# --- Flanking (Armor phase 5) ---

const FACET_NORMALS = {
	"front": Vector3(0, 0, -1),
	"back": Vector3(0, 0, 1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
}

# Duck-typed: works for both battle_unit.gd (hull_node) and building.gd
# (defense_hull) targets, whichever the attack_target happens to be.
func _get_target_hull(target: Node3D) -> Node3D:
	if "hull_node" in target and is_instance_valid(target.hull_node):
		return target.hull_node
	if "defense_hull" in target and is_instance_valid(target.defense_hull):
		return target.defense_hull
	return null

# Estimates each of the 4 horizontal facets' effective kinetic threshold
# (hull baseline, or a covering plate's own material+HP bonus if one
# exists - same resolution DamageResolver would use for a real hit).
# Generalized (Kiting phase, facet-aware) from what used to be inlined only
# for a target's weakest facet, so the exact same estimate can be applied
# to the unit's OWN hull for kiting decisions - a single source of truth
# for "how tough is this hull's facet" regardless of who's asking.
func _facet_thresholds(hull: Node3D, modules: Array) -> Dictionary:
	var hull_mat = hull.get_meta("armor_material") if hull.has_meta("armor_material") else "hardened_steel"
	var hull_thick = hull.get_meta("armor_thickness") if hull.has_meta("armor_thickness") else 1.0
	var baseline = DamageResolverScript.get_material_threshold(hull_mat, "kinetic", hull_thick).x

	var result = {}
	for facet in FACET_NORMALS.keys():
		var t = baseline
		for m in modules:
			if not m.has_meta("module_data"): continue
			var m_data = m.get_meta("module_data")
			if m_data.category == "armor" and m.get_meta("facet", "") == facet:
				var plate_mat = m_data.tweaks.get("material", "") if "tweaks" in m_data else ""
				if plate_mat != "":
					t = DamageResolverScript.get_material_threshold(plate_mat, "kinetic", 1.0).x
				t += m_data.get_hp() * 0.1
				break
		result[facet] = t
	return result

# Top/bottom are deliberately excluded - not meaningful to "approach from
# above" with ground-based steering. Returns the WORLD-space direction of
# the weakest one.
func _weakest_facet_normal(target: Node3D) -> Vector3:
	var hull = _get_target_hull(target)
	if not hull:
		return Vector3.ZERO

	var target_modules = []
	if target.has_method("get_active_modules"):
		target_modules = target.get_active_modules()

	var thresholds = _facet_thresholds(hull, target_modules)
	var best_facet = "front"
	var best_threshold = INF
	for facet in thresholds:
		if thresholds[facet] < best_threshold:
			best_threshold = thresholds[facet]
			best_facet = facet

	return FACET_NORMALS[best_facet]

# Facet-aware kiting (Kiting phase 2): my own weakest and strongest
# facets, same estimate as _weakest_facet_normal but applied to myself.
func _my_facet_extremes() -> Dictionary:
	if not is_instance_valid(hull_node):
		return {"weakest": "front", "strongest": "front"}
	var thresholds = _facet_thresholds(hull_node, get_active_modules())
	var weakest = "front"
	var weakest_t = INF
	var strongest = "front"
	var strongest_t = -INF
	for facet in thresholds:
		if thresholds[facet] < weakest_t:
			weakest_t = thresholds[facet]
			weakest = facet
		if thresholds[facet] > strongest_t:
			strongest_t = thresholds[facet]
			strongest = facet
	return {"weakest": weakest, "strongest": strongest}

func _compute_flank_point(target: Node3D) -> Vector3:
	var weak_normal_local = _weakest_facet_normal(target)
	if weak_normal_local == Vector3.ZERO:
		return target.global_position
	var world_normal = (target.global_transform.basis * weak_normal_local).normalized()
	return target.global_position + world_normal * (attack_range * 0.8)

func take_damage(amount: float, damage_type: String = "kinetic", hit_origin = null):
	if is_dead: return

	var active_modules = get_active_modules()
	var resolved = DamageResolverScript.resolve(hull_node, active_modules, damage_type, self, hit_origin)
	var threshold = resolved.x
	var reduction = resolved.y

	# Subsystem stripping: 35% of hits land on an exposed module. Damage is a
	# fraction of the raw hit (DamageResolver.MODULE_STRIP_DAMAGE_FACTOR),
	# not the old flat `amount - 5.0` which rounded every rapid-fire weapon's
	# strip damage to zero - small sustained guns are now the module-stripper
	# archetype the design docs promise, while a huge shell still wastes its
	# overkill on a 100 HP module (action economy, working as intended).
	#
	# FABLE_REVIEW.md 2.5: gated to the module actually facing the shot, and
	# never an armor plate (armor already gets its own facet-aware
	# resolution via DamageResolver.resolve() above). Previously any module
	# ANYWHERE on the hull was an eligible target regardless of hit
	# direction - a howitzer could "whiff" a third of its shells into a
	# wheel on the far side while the hull took nothing, which read as a
	# phantom miss rather than the design docs' targeted "shoot the treads/
	# radar dish" counterplay. Uses each module's own local position (the
	# same classify_facet() convention armor's placement-time facet meta
	# already uses), not a separate per-module meta field, so every
	# category - weapon, locomotion, generator, sensor - is covered
	# uniformly with no per-type wiring. Falls back to every non-armor
	# module (the old pool) when hit_origin isn't available, so a direct
	# take_damage() call (tests, or any future caller that doesn't supply
	# one) doesn't silently lose stripping entirely.
	var hit_facet = ""
	if hit_origin != null:
		var local_dir = global_transform.basis.inverse() * ((hit_origin as Vector3) - global_position)
		hit_facet = ModuleCatalog.classify_facet(local_dir)
	var strippable = []
	for m in active_modules:
		var sm_data = m.get_meta("module_data")
		if sm_data and sm_data.category == "armor":
			continue
		if hit_facet != "" and ModuleCatalog.classify_facet(m.position) != hit_facet:
			continue
		strippable.append(m)

	if not strippable.is_empty() and randf() < 0.35:
		var target_module = strippable.pick_random()
		var m_data = target_module.get_meta("module_data")
		var m_hp = target_module.get_meta("current_hp") if target_module.has_meta("current_hp") else m_data.get_hp()
		var final_mod_damage = amount * DamageResolverScript.MODULE_STRIP_DAMAGE_FACTOR
		m_hp = max(0.0, m_hp - final_mod_damage)
		target_module.set_meta("current_hp", m_hp)
		if m_hp <= 0.0:
			_spawn_explosion(target_module.global_position, 0.5)
			if target_module.has_meta("mirrored_counterpart"):
				var mirror = target_module.get_meta("mirrored_counterpart")
				if is_instance_valid(mirror):
					mirror.remove_meta("mirrored_counterpart")
			var was_locomotion = m_data.category == "locomotion"
			var was_generator = m_data.category == "generator"
			var was_logistics = m_data.type_id == "logistics_tank"
			target_module.queue_free()
			if was_locomotion:
				call_deferred("_recalculate_move_speed")
			if was_generator:
				call_deferred("_recalculate_energy")
			if was_logistics:
				call_deferred("_detect_logistics_tank")
		return

	# Chip-through + brute-force via the shared resolver math (see
	# DamageResolver.compute_hull_damage) - sub-threshold hits are mostly
	# (not entirely) negated, overwhelming hits shrug off reduction.
	var final_damage = DamageResolverScript.compute_hull_damage(amount, threshold, reduction)
	if amount < threshold:
		_flash_shield()
	else:
		_flash_hull()
	hp = max(0.0, hp - final_damage)
	_update_hp_bar()
	if hp <= 0.0:
		die()

# --- Energy resource (ENERGY_AND_BALANCE_SPEC.md #1/#4) ---

# Checked by auto_weapon.gd before an energy-classed weapon is allowed to
# fire. Returns false (and spends nothing) if the capacitor's dry - a real
# soft-limit on sustained energy-weapon fire, not just a cosmetic number.
func spend_energy(amount: float) -> bool:
	if is_dead or current_energy < amount:
		return false
	current_energy -= amount
	return true

# Called by an enemy's energy-drain weapon (arc_projector/tesla_coil/
# ion_cannon). Never restores HP, never goes negative - a target at 0
# energy just can't fire its own energy weapons until it regens or gets a
# logistics boost.
func drain_energy(amount: float):
	if is_dead: return
	current_energy = max(0.0, current_energy - amount)

# Called by repair_array's ally-targeting heal beam (auto_weapon.gd).
# Duck-typed the same way take_damage()/drain_energy() are - any target
# with a "hp"/"max_hp" pair and this method works, no repair_array-specific
# knowledge needed on the receiving end.
func repair_hp(amount: float):
	if is_dead or hp >= max_hp: return
	hp = min(max_hp, hp + amount)
	_update_hp_bar()

# Called on THIS unit's own allies by their logistics_tank aura -
# distinct from passive regen (energy_regen_rate) so a logistics-boosted
# unit visibly charges faster than its own generators alone would produce.
func receive_energy_share(amount: float):
	if is_dead: return
	current_energy = min(max_energy, current_energy + amount)

# Logistics sharing aura: scans nearby allies every physics frame, same
# O(n) scan pattern auto_weapon.gd's targeting already uses. Skirmish
# battles are modest-scale (tens of units), not thousands, so this is
# cheap enough without needing a spatial partition.
func _share_energy_with_allies(delta: float):
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not is_instance_valid(u): continue
		if "is_dead" in u and u.is_dead: continue
		if not ("team" in u) or u.team != team: continue
		if not (u.has_method("receive_energy_share") and "current_energy" in u and "max_energy" in u): continue
		if u.current_energy >= u.max_energy: continue
		if global_position.distance_to(u.global_position) <= LOGISTICS_SHARE_RADIUS:
			u.receive_energy_share(LOGISTICS_SHARE_RATE * logistics_tank_strength * delta)

func _flash_shield():
	var exp_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	exp_mesh.mesh = sphere
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.4)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(0.2, 0.6, 1.0)
	exp_mesh.material_override = flash_mat
	add_child(exp_mesh)
	exp_mesh.position = Vector3(0, 0.5, 0)
	var tween = create_tween()
	tween.tween_property(exp_mesh, "scale", Vector3.ZERO, 0.1)
	tween.finished.connect(func(): exp_mesh.queue_free())

func _flash_hull():
	if not is_instance_valid(hull_node): return
	var mesh_inst = hull_node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_inst: return
	# Hull materials are per-surface overrides now (HullMaterialBuilder.
	# apply_hull_materials() - structural + armor slots), not a single
	# mesh_inst.material_override - flash_hull() sets flash_amount on
	# every ShaderMaterial surface override this hull has.
	HullMaterialBuilderScript.flash_hull(mesh_inst, 1.0)
	get_tree().create_timer(0.12).timeout.connect(func():
		if is_instance_valid(mesh_inst):
			HullMaterialBuilderScript.flash_hull(mesh_inst, 0.0)
	)

func _spawn_explosion(pos: Vector3, size: float):
	var scene = get_tree().current_scene
	if not scene: scene = get_parent()
	if not scene: return
	for i in range(6):
		var particle = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.2, 0.2, 0.2) * size
		particle.mesh = box
		var p_mat = StandardMaterial3D.new()
		p_mat.albedo_color = Color.RED.lerp(Color.YELLOW, randf())
		p_mat.emission_enabled = true
		p_mat.emission = p_mat.albedo_color
		particle.material_override = p_mat
		scene.add_child(particle)
		particle.global_position = pos
		var dir = Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-2, 2)).normalized()
		var tween_p = create_tween()
		tween_p.tween_property(particle, "global_position", pos + dir * 4.0 * size, 0.6)
		tween_p.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.6)
		tween_p.finished.connect(func(): particle.queue_free())

func die():
	if is_dead: return
	is_dead = true
	remove_from_group("damageable")
	collision_layer = 0
	_spawn_explosion(global_position, 1.5)
	emit_signal("died", self)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	tween.finished.connect(func(): queue_free())
