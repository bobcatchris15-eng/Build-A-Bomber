extends Node3D

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const GlobalConfig = preload("res://scripts/global_config.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const VFXBurstScript = preload("res://scripts/vfx_burst.gd")
# Shared unit meshes + cached materials for every munition visual below. See
# munition_pool.gd's header for the measurements that motivated it; the short
# version is that a fresh primitive Mesh per projectile was costing more frame
# time at 8 units than the units themselves. Everything it returns is shared
# and must not be mutated - size munitions via the node's scale.
const MunitionPool = preload("res://scripts/munition_pool.gd")

var target: Node3D = null
var fire_range: float = 12.0
var fire_rate: float = 1.0 # Shot interval
var time_since_last_shot: float = 0.0

var dps: float = 10.0
# Crimson Concordat's passive (dps rises the closer this weapon's own
# vehicle is to death) needs a per-tick recompute, unlike every other
# faction dps/range bonus which is a fixed one-time value set in _ready() -
# base_dps is that fixed value; `dps` itself becomes the live, possibly-
# boosted number every _fire_*() function already reads.
var base_dps: float = 10.0
var heal_rate: float = 0.0
var laser_color: Color = Color.RED
var type_id: String = ""

var damage_class: String = "kinetic"
# Ray-start height for the LOS check - computed once from the catalog size in
# _ready() instead of re-fetching catalog data every physics tick.
var _los_height_offset: float = 0.5
var traverse_limit_angle: float = PI / 4.0
var traverse_speed: float = 4.0
var resting_transform: Transform3D
var spin_up_timer: float = 0.0

# PERFORMANCE_PLAN.md P1: _is_current_target_still_valid() used to call
# _is_los_blocked_to() every single physics tick for every weapon on every
# unit - each call walks both this weapon's and the target's ENTIRE node
# tree to build a raycast exclude list, then fires up to two raycasts. That
# was the dominant cost behind the "falls off a cliff past ~5-6 units"
# report - O(units x weapons) tree-walks/raycasts every tick in steady
# state. LOS geometry doesn't meaningfully change within ~150ms at RTS unit
# speeds, so cache the result instead of re-querying every frame.
var _los_cache_blocked: bool = false
var _los_cache_target: Node3D = null
var _los_cache_timer: float = 0.0
const LOS_CACHE_TTL: float = 0.15

# PERFORMANCE_PLAN.md P1a: reacquiring a target (_find_nearest_target()'s
# full grid/roster scan) is the other expensive path, throttled the same
# way _try_auto_engage() already throttles its own O(n) scan.
# _ready() staggers each weapon's timer with a random phase so a mass
# target-loss event (an alpha strike, a scouted group dying) doesn't turn
# into every weapon re-scanning on the same physics frame.
var _reacquire_timer: float = 0.0
const REACQUIRE_INTERVAL: float = 0.2

# frame_built weapons (ModuleCatalog.get_traverse_limit_angle == 0.0 exactly -
# the barrel is fixed to the hull, so the whole vehicle aims instead, see
# battle_unit.gd's has_frame_built_weapon) still need a real, reachable
# ACQUISITION tolerance. Every target-scan below used to gate on
# `angle_to(dir) <= traverse_limit_angle` directly, which for a frame_built
# weapon means literally 0.0 - bit-exact alignment with a continuous slerp
# (battle_unit.gd's _turn_toward) essentially never produces that, so target
# stayed permanently null and these weapons almost never fired regardless of
# how well the hull was actually aimed (the "flaky firing" bug report).
# Flooring the comparison at this tolerance (same 0.26 rad/~15 degrees the
# firing gate below already uses) lets acquisition succeed once the hull's
# real-time turn has it roughly on target, so the firing gate - which checks
# the true CURRENT angle every frame, not this stale acquisition snapshot -
# gets a real chance to close the rest of the way and fire. No effect on
# turret/pintle (traverse_limit_angle == PI already exceeds this).
const MIN_ACQUISITION_ARC: float = 0.26

# repair_array's real fix (ENERGY_AND_BALANCE_SPEC.md #3): inverts
# targeting to same-team/HP-deficit candidates instead of hostiles.
var targets_allies: bool = false

# Energy weapons (ENERGY_AND_BALANCE_SPEC.md #4/#5): cost the FIRING unit's
# own current_energy per shot (checked/spent via spend_energy() on the
# vehicle root, duck-typed) and, for tesla_coil/ion_cannon, drain the
# TARGET's energy pool alongside HP damage. arc_projector is the dedicated
# pure-drain weapon.
const ENERGY_WEAPON_TYPES = ["tesla_coil", "arc_projector", "ion_cannon"]
var energy_cost_per_shot: float = 0.0
var energy_drain_per_shot: float = 0.0

# damage_class reclassification (DECISIONS_NEEDED.md - deliberately
# deferred, then revisited once damage_resolver.gd actually had a real
# "energy" armor-table row to resolve against): heavy_laser/plasma_lobber/
# pd_laser are thematically directed-energy weapons, reclassified to
# damage_class "energy" for real armor-matchup purposes. Deliberately kept
# OUT of ENERGY_WEAPON_TYPES above - they don't cost the shooter's own
# Energy pool to fire or drain the target's, only tesla_coil/arc_projector/
# ion_cannon (this pass's new weapons) have that mechanic. Mixing the two
# lists would have silently turned three week-old weapons into
# capacitor-limited ones, which is a much bigger change than "which armor
# threshold they resolve against."
const ENERGY_DAMAGE_CLASS_TYPES = ["tesla_coil", "arc_projector", "ion_cannon", "heavy_laser", "plasma_lobber", "pd_laser"]

const PD_WEAPON_TYPES = ["ciws", "pd_laser", "flak_cannon"]
# FABLE_REVIEW.md 1.8: the point-defense family finally gets a real anti-AIR
# identity (previously "flak = AA" was pure flavor - nothing anywhere
# distinguished air targets, and PD per-shot damage rounded to zero against
# any armor). A flat multiplier vs airborne hulls is deliberately gamey/C&C
# rather than simulationist - it makes flak the answer to armored fliers
# without touching its (intentionally weak) anti-ground numbers.
const PD_ANTI_AIR_DAMAGE_MULT: float = 3.0

# --- Evasion model (FABLE_REVIEW.md 1.4) ---
# Speed finally has DEFENSIVE value: a shot can miss a fast-moving target,
# scaled by the weapon's projectile class (ModuleCatalog.PROJECTILE_CLASS)
# and the target's actual current horizontal velocity (not its design-time
# move_speed - a fast unit standing still is an easy target). Bigger hulls
# are easier to hit (footprint factor), so compact scouts genuinely dodge
# better than stretched-out gun platforms. Hitscan beams and guided
# munitions never miss from speed - guided's counter is PD interception.
const MISS_SPEED_FACTOR = {"hitscan": 0.0, "ballistic": 0.035, "arc": 0.09, "guided": 0.0}
const MISS_CHANCE_CAP: float = 0.75

func _roll_hit(t: Node3D) -> bool:
	var cls = ModuleCatalog.get_projectile_class(type_id)
	var factor = MISS_SPEED_FACTOR.get(cls, 0.035)
	if factor <= 0.0:
		return true
	var target_speed = 0.0
	if t is CharacterBody3D:
		target_speed = Vector3(t.velocity.x, 0.0, t.velocity.z).length()
	if target_speed < 0.5:
		return true # stationary (or a building) - can't dodge standing still
	var size_factor = 1.0
	if "hull_node" in t and is_instance_valid(t.hull_node) and t.hull_node.has_meta("base_hull_size") and t.hull_node.has_meta("hull_scale"):
		var s = t.hull_node.get_meta("base_hull_size") * t.hull_node.get_meta("hull_scale")
		size_factor = clamp(sqrt((s.x * s.z) / (4.0 * 6.0)), 0.6, 1.6)
	var miss_chance = clamp(target_speed * factor / size_factor, 0.0, MISS_CHANCE_CAP)
	return randf() >= miss_chance

# Parent node for spawned projectiles, tracers and impact VFX.
#
# Every _fire_*() below used to call _effects_parent().add_child()
# directly. current_scene is null whenever no scene has been marked current -
# briefly during a scene transition, and permanently in any harness that
# instantiates a scene straight under the tree root (which is exactly how
# run_tests.gd drives the Test Range). In that state the add_child() aborted
# the shot with "Cannot call method 'add_child' on a null value" AFTER the
# weapon had already reset its cooldown: the gun cycled, played its timing,
# and fired blanks - target dummies sat at full health while every other
# signal (target lock, line of sight, aim angle) looked perfectly healthy.
# Falling back to the tree root keeps the projectile real in that case.
func _effects_parent() -> Node:
	var t = get_tree()
	if t == null:
		return null
	return t.current_scene if t.current_scene != null else t.root

# Small dirt-puff visual where a missed shot lands, so a miss reads as a
# miss instead of silent nothing.
func _spawn_miss_puff(t: Node3D):
	if not is_instance_valid(t) or not is_inside_tree():
		return
	var puff = MeshInstance3D.new()
	puff.mesh = MunitionPool.unit_sphere()
	puff.scale = Vector3(0.6, 0.6, 0.6)
	puff.material_override = MunitionPool.alpha(Color(0.5, 0.45, 0.35, 0.7))
	_effects_parent().add_child(puff)
	var side = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	puff.global_position = t.global_position + side * randf_range(1.2, 2.2)
	var tween = create_tween()
	tween.tween_property(puff, "scale", Vector3.ZERO, 0.3)
	tween.finished.connect(func(): if is_instance_valid(puff): puff.queue_free())

# Single funnel for all weapon HP damage (every _fire_*() routes through
# here). Centralizes: the evasion roll, the PD anti-air bonus above, and
# the hit-origin altitude flattening below.
func _deal_weapon_damage(t: Node3D, amount: float):
	if not is_instance_valid(t) or not t.has_method("take_damage"):
		return
	if not _roll_hit(t):
		_spawn_miss_puff(t)
		return
	if type_id in PD_WEAPON_TYPES and "is_flying" in t and t.is_flying:
		amount *= PD_ANTI_AIR_DAMAGE_MULT
	t.take_damage(amount, damage_class, _hit_origin(t))

# Real AoE (FABLE_REVIEW.md 2.3) - the other missing leg of the counter-
# triangle ("AoE beats swarm"). A shared radius query around an impact
# point, called from the explosive weapons' hit callbacks instead of their
# old single-target-only _deal_weapon_damage() call. Linear falloff from
# full damage at the impact center to zero at the blast radius edge; each
# hit still routes through _deal_weapon_damage() so evasion/PD-anti-air/
# hit-origin-flattening all still apply per target. Hostiles only, matching
# every other weapon's own team filter - friendly fire is a real, separate
# design question (own units clustering would suddenly matter) deliberately
# not bundled into this pass; see DECISIONS_NEEDED.md.
func _deal_aoe_damage(center: Vector3, radius: float, amount: float):
	var my_team = get_team()
	for c in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(c) or not c.has_method("take_damage"):
			continue
		if "is_dead" in c and c.is_dead:
			continue
		var c_team = c.get_meta("team") if c.has_meta("team") else -1
		if my_team >= 0 and c_team == my_team:
			continue
		var dist = center.distance_to(c.global_position)
		if dist > radius:
			continue
		var falloff = clamp(1.0 - (dist / radius), 0.0, 1.0)
		if falloff <= 0.0:
			continue
		_deal_weapon_damage(c, amount * falloff)

# FABLE_REVIEW.md 1.8 fix: flying units cruise at y=4.0, permanently above
# DamageResolver's 2.0 elevation-advantage threshold - so every air-to-ground
# shot silently collected the armor-pierce bonus meant to reward holding
# high TERRAIN. A flying attacker's hit origin is flattened to the target's
# own height (treated as level fire); ground attackers (including ones
# standing on a real hill) keep their true position and the earned bonus.
func _hit_origin(t: Node3D) -> Vector3:
	var origin = global_position
	var vehicle = get_vehicle_root()
	if vehicle and "is_flying" in vehicle and vehicle.is_flying and is_instance_valid(t):
		origin.y = min(origin.y, t.global_position.y + 0.5)
	return origin

# Helper to find all colliders recursively
func _get_colliders_recursive(node: Node, list: Array):
	if node is CollisionObject3D:
		list.append(node.get_rid())
	for child in node.get_children():
		_get_colliders_recursive(child, list)

# PERFORMANCE_PLAN.md P1b: _get_colliders_recursive() walks a node's ENTIRE
# subtree (for a full vehicle: the hull plus every mounted module) on every
# single LOS raycast - this weapon's own tree, plus whichever candidate is
# currently being checked, every tick a target is tracked and every
# candidate considered during reacquisition. Cache the result on the node
# itself via set_meta() (not a static Dictionary here - metadata dies with
# the node, so a freed vehicle can't leak a cache entry forever) with a
# short TTL. A module lost mid-battle (subsystem stripping) can leave one
# stale, already-invalid RID in a cached list for up to the TTL - Godot's
# exclude array silently skips RIDs that no longer resolve to a live
# collider, so this is a harmless, bounded imprecision, not a correctness
# bug.
const COLLIDER_CACHE_TTL_MS: int = 1000
func _cached_colliders_for(node: Node) -> Array:
	var now = Time.get_ticks_msec()
	if node.has_meta("_collider_cache_expires_at") and now < node.get_meta("_collider_cache_expires_at"):
		return node.get_meta("_collider_cache_list")
	var list = []
	_get_colliders_recursive(node, list)
	node.set_meta("_collider_cache_list", list)
	node.set_meta("_collider_cache_expires_at", now + COLLIDER_CACHE_TTL_MS)
	return list

# Helper to find vehicle root
func get_vehicle_root() -> Node3D:
	var p = get_parent()
	while p:
		if p.is_in_group("player_vehicle") or p.is_in_group("targets") or p.is_in_group("damageable"):
			return p
		p = p.get_parent()
	return null

# Team of the construct this weapon is mounted on (-1 = legacy test range, no team)
func get_team() -> int:
	var root_vehicle = get_vehicle_root()
	if root_vehicle and root_vehicle.has_meta("team"):
		return root_vehicle.get_meta("team")
	return -1

# RTS_CORE_ROADMAP.md B2: defers to skirmish.gd's is_allied() (slots'
# `allies` lists) wherever this file used to hardcode "same team = not
# hostile." Duck-typed via current_scene so this stays zero-dependency in
# every context without a real Skirmish (test range, legacy tests) - falls
# back to plain team equality there, i.e. unchanged old behavior.
func _teams_allied(a: int, b: int) -> bool:
	if a == b:
		return true
	var scene = get_tree().current_scene
	if scene and scene.has_method("is_allied"):
		return scene.is_allied(a, b)
	return false

# Line of sight raycast check.
#
# FABLE_REVIEW.md 3.1 fix: the old logic only reported "blocked" when the ray
# hit the weapon's OWN vehicle - a hit on a rock, urban building, or any other
# world geometry fell through to "clear," so units fired straight through
# cover the moment a target was team-spotted (the vision system blocked
# sightlines, the weapons didn't). Now ANY non-excluded hit blocks: world
# geometry (layer 1 - obstacles/rocks/urban buildings, the same layer
# skirmish.gd's vision LOS already checks), module bodies (layer 2 - own
# sibling masts etc., matching the Design Lab firing-arc visualization's
# blocked-segment behavior), and buildings (layer 8). Units (layer 4)
# deliberately do NOT block - firing through/past friendly units is standard
# RTS behavior and blocking on it would deadlock any grouped formation.
# The target's own colliders are excluded so the target can never "block"
# the shot at itself. Own-hull blocking (the logged sponson-through-own-hull
# question, DECISIONS_NEEDED.md 2026-07-17) is handled by a second, narrower
# check inside _is_los_blocked_to() below - see its comment - since the
# layer-4 omission above (needed to keep OTHER units from blocking) also
# happened to exempt a weapon's own vehicle, which lives on that same layer.
func _is_line_of_sight_blocked() -> bool:
	return _is_los_blocked_to(target)

# Line of sight from this weapon's muzzle to an arbitrary candidate.
#
# Pulled out of _is_line_of_sight_blocked() so target ACQUISITION can consult
# it too, not just the firing gate. A pintle mount has no mechanical traverse
# limit (see ModuleCatalog.get_traverse_limit_angle) - what actually decides
# whether it can engage a given direction is whether the hull or a neighbouring
# module is in the way. With acquisition blind to that, a weapon would lock
# onto the nearest enemy, discover at the firing gate that its own hull was
# between them, and then sit there aiming at it forever instead of picking a
# target it could actually hit.
func _is_los_blocked_to(candidate: Node3D) -> bool:
	if not candidate or not is_instance_valid(candidate): return true

	var space_state = get_world_3d().direct_space_state
	# Weapons face forward along negative Z relative to their own local space
	var muzzle_forward = -global_transform.basis.z.normalized()

	# Offset along the weapon's OWN up axis, not world up. Since placement
	# aligns local +Y with the surface normal it was mounted on, this always
	# steps AWAY from the hull - whereas the old world-up offset pushed a
	# side- or belly-mounted weapon's ray start straight into the hull it was
	# bolted to.
	var muzzle_up = global_transform.basis.y.normalized()
	var ray_start = global_position + muzzle_up * _los_height_offset + muzzle_forward * 0.8
	var ray_end = candidate.global_position + Vector3(0, 0.5, 0) # target center

	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1 + 2 + 8 # Ground/obstacles (1), Modules (2), Buildings (8) - not units (4)
	query.collide_with_areas = true

	# Exclude this weapon's own colliders and everything belonging to the
	# candidate (a target can never "block" the shot at itself). Units
	# (layer 4) stay out of this query's mask - firing through/past other
	# units is standard RTS behavior, blocking on it would deadlock any
	# grouped formation.
	#
	# Excludes the whole VEHICLE ROOT's subtree, not just this weapon
	# module's own - a mobile unit's own hull collider lives on layer 4
	# (units), already outside this query's mask by construction, so using
	# just `self` here never mattered for those. A defense building's own
	# foundation collider (building.gd's CollisionShape3D) lives on layer 8
	# ("Buildings"), which this query's mask DOES include - excluding only
	# the weapon module's own (empty) subtree left every defense weapon's
	# own foundation box eligible to block its own first raycast, so a
	# defense's turret could permanently "see" its own base and treat every
	# target as blocked. get_vehicle_root() covers both cases uniformly.
	var vehicle_for_exclude = get_vehicle_root()
	var own_colliders = _cached_colliders_for(vehicle_for_exclude if vehicle_for_exclude else self) + _cached_colliders_for(candidate)
	query.exclude = own_colliders

	var result = space_state.intersect_ray(query)
	if not result.is_empty():
		return true

	# Own-hull self-occlusion (DECISIONS_NEEDED.md 2026-07-17 "sponson
	# weapons may be able to shoot through their own hull"): a battle-spawned
	# hull's collider lives on battle_unit.gd's own CharacterBody3D (layer
	# 4, "units" - see setup()'s CollisionShape3D and the running-gear
	# collider), the very layer the query above deliberately omits so other
	# units never block a shot. That omission meant a weapon's OWN hull
	# could never block its own shot either - a sponson/pintle mounted on
	# the near side could "see" and hit a target its own vehicle's mass was
	# actually between it and. A second, narrower ray - units back in the
	# mask, but only this weapon's own vehicle counts as a block - catches
	# that case without reopening the ally-formation deadlock: if the first
	# thing hit is some OTHER unit standing in the way, that's disregarded
	# (same permissive behavior the first query already has for units);
	# only a hit on this weapon's own vehicle body counts as blocked.
	var vehicle = get_vehicle_root()
	if vehicle:
		var self_query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		self_query.collision_mask = 4 # Units
		self_query.collide_with_areas = true
		self_query.exclude = _cached_colliders_for(candidate)
		var self_result = space_state.intersect_ray(self_query)
		if not self_result.is_empty() and self_result.get("collider") == vehicle:
			return true

	return false

# Basis pointing -Z along `dir`, safe for a target directly overhead or
# directly underneath.
#
# Basis.looking_at(dir, Vector3.UP) is undefined when dir is parallel to the
# up reference - it collapses to a singular matrix and Godot logs
# 'Condition "det == 0" is true'. That is exactly the straight-up and
# straight-down case, so a pintle weapon could traverse freely in azimuth but
# went haywire the moment it tried to fully depress onto something beneath it
# (or elevate onto something directly above). Swapping to a sideways
# reference vector in that cone keeps the basis well-conditioned, which is
# what lets a pintle actually cover the whole sphere rather than just a band
# around the horizon.
static func _looking_at_safe(dir: Vector3) -> Basis:
	var d = dir.normalized()
	if d.length_squared() < 0.5:
		return Basis.IDENTITY
	var up_ref = Vector3.UP
	if abs(d.dot(Vector3.UP)) > 0.999:
		up_ref = Vector3.BACK
	return Basis.looking_at(d, up_ref)

func _ready():
	resting_transform = transform
	# PERFORMANCE_PLAN.md P1a: random phase so every weapon doesn't reacquire
	# on the same physics frame as every other weapon.
	_reacquire_timer = randf() * REACQUIRE_INTERVAL
	if has_meta("module_data"):
		var data = get_meta("module_data")
		type_id = data.type_id
		var mount_faction = get_parent().get_meta("faction", "industrialists") if get_parent() and get_parent().has_meta("faction") else "industrialists"
		base_dps = data.get_dps() * FactionCatalog.get_passive(mount_faction, "dps_mult", 1.0)
		dps = base_dps
		heal_rate = data.get_heal_rate()
		
		# Calculate traverse speed based on weight, then apply this weapon
		# type's own agility character (ModuleCatalog.get_traverse_agility()
		# - see its comment for the full per-type reasoning). Two weapons of
		# similar weight but very different archetypes (a CIWS vs. a
		# mortar_array, both ~90kg) previously got identical traverse speed
		# since weight was the ONLY input. Base clamp widened from the old
		# (0.6, 6.0) to (0.4, 8.0) so the per-type multiplier has real
		# headroom to differentiate rather than being squashed back into a
		# narrow shared band.
		var weight = data.get_weight()
		traverse_speed = clamp(200.0 / weight, 0.4, 8.0) * ModuleCatalog.get_traverse_agility(type_id)
		_los_height_offset = ModuleCatalog.get_module_data(type_id).size.y * 0.7
		
		# Traverse limit angle: shared with the Design Lab's firing-arc
		# visualization via ModuleCatalog.get_traverse_limit_angle() so the
		# two can never drift apart.
		var mount_facet = get_meta("facet", "")
		var mount_hull_type = ""
		var mount_parent = get_parent()
		if mount_parent and mount_parent.has_meta("type_id"):
			mount_hull_type = mount_parent.get_meta("type_id")
		traverse_limit_angle = ModuleCatalog.get_traverse_limit_angle(type_id, mount_facet, mount_hull_type)
			
		if type_id in ["basic_cannon", "heavy_machine_gun", "rotary_cannon", "gauss_railgun", "ciws"]:
			damage_class = "kinetic"
		elif type_id in ["artillery", "mortar_array", "guided_missile", "missile_pod", "cluster_dispenser", "flak_cannon"]:
			damage_class = "explosive"
		elif type_id in ENERGY_DAMAGE_CLASS_TYPES:
			# See ENERGY_DAMAGE_CLASS_TYPES's own comment for the full
			# reasoning and DECISIONS_NEEDED.md for the concrete
			# before/after threshold numbers this reclassification changes.
			damage_class = "energy"
		else:
			damage_class = "thermal"

		targets_allies = ModuleCatalog.targets_allies(type_id)
			
		# Base fire profile. These used to be a ~120-line if/elif chain right
		# here; they now live in ModuleCatalog.WEAPON_FIRE_PROFILES so balance
		# tooling can actually see and sweep them (fire_rate is the shot
		# interval, and per-shot damage `dps * fire_rate` is what the armor
		# thresholds gate on - so it's the strongest balance lever there is).
		# The tweak modifiers below still apply on top, unchanged.
		var fire_profile = ModuleCatalog.get_fire_profile(type_id)
		fire_range = fire_profile.fire_range
		fire_rate = fire_profile.fire_rate
		laser_color = fire_profile.laser_color
			
		# Apply Range & Traverse Speed Tweak Modifiers
		if data.tweaks.has("barrel_length"):
			fire_range *= data.tweaks["barrel_length"]
		if data.tweaks.has("elevation"):
			fire_range *= data.tweaks["elevation"]
		if data.tweaks.has("rod_thickness") and data.tweaks["rod_thickness"] > 0.0:
			fire_range /= data.tweaks["rod_thickness"]
		if data.tweaks.has("engine_length"):
			fire_range *= data.tweaks["engine_length"]
		if data.tweaks.has("payload_size") and data.tweaks["payload_size"] > 0.0:
			fire_range /= data.tweaks["payload_size"]
		if data.tweaks.has("nozzle_width") and data.tweaks["nozzle_width"] > 0.0:
			fire_range /= data.tweaks["nozzle_width"]
		if data.tweaks.has("lens_aperture") and data.tweaks["lens_aperture"] > 0.0:
			fire_range /= data.tweaks["lens_aperture"]
		if data.tweaks.has("containment") and data.tweaks["containment"] > 0.0:
			fire_range /= data.tweaks["containment"]
		if data.tweaks.has("radar_dish"):
			fire_range *= data.tweaks["radar_dish"]
		# Audit (task 47/49): several weapons' only tweaks previously had
		# zero effect on fire_range at all - a bigger caliber round flies
		# further, a longer railgun accelerator rail means more muzzle
		# velocity (gauss_railgun's rail_length tweak did NOTHING to its own
		# range before this), a bigger missile seeker locks on further out,
		# a bigger ascent thruster gives a top-attack missile more reach,
		# more fuel pressure pushes a flamethrower's stream further, and a
		# flak shell's proximity fuse setting IS its effective engagement
		# range. Left out deliberately: count-type tweaks (multi_barrel/
		# barrel_count/tube_count/grid_size - "more copies," not "reaches
		# further") and tweaks with no real range link (drum_size/motor_size
		# are ammo capacity and spin torque, not reach; dispersion is spread
		# pattern, not distance; cooling_jacket is sustained-fire capacity,
		# not reach).
		if data.tweaks.has("caliber"):
			fire_range *= data.tweaks["caliber"]
		if data.tweaks.has("rail_length"):
			fire_range *= data.tweaks["rail_length"]
		if data.tweaks.has("seeker_size"):
			fire_range *= data.tweaks["seeker_size"]
		if data.tweaks.has("ascent_thruster"):
			fire_range *= data.tweaks["ascent_thruster"]
		if data.tweaks.has("pressure_valve"):
			fire_range *= data.tweaks["pressure_valve"]
		if data.tweaks.has("fuse_setting"):
			fire_range *= data.tweaks["fuse_setting"]

		# Audit (task 47/48): previously only barrel_length/elevation nudged
		# traverse_speed, leaving most weapon types' actual tweaks
		# (drum_size, motor_size, rail_length, etc.) with zero direct
		# traverse effect - they only moved traverse indirectly through the
		# weight-driven base formula above. Generalized to every "single
		# part gets physically bigger" tweak name (ModuleCatalog.
		# LINEAR_SCALE_WEAPON_TWEAKS, shared with module_data.gd's
		# weight-scaling list) so a bigger/heavier part now also directly
		# costs some traverse speed on top of its weight effect - a real,
		# type-relevant tweak-to-traverse link for nearly every weapon in
		# the roster, not just the two that happened to share a tweak name
		# with heavy_howitzer/basic_cannon.
		for tweak_name in ModuleCatalog.LINEAR_SCALE_WEAPON_TWEAKS:
			if data.tweaks.has(tweak_name) and data.tweaks[tweak_name] > 0.0:
				traverse_speed /= data.tweaks[tweak_name]
		traverse_speed = clamp(traverse_speed, 0.15, 20.0)

		# Apply Fire Rate Tweak Modifiers (Shot Intervals)
		if data.tweaks.has("caliber"):
			fire_rate *= data.tweaks["caliber"]
		if data.tweaks.has("multi_barrel") and data.tweaks["multi_barrel"] == true:
			fire_rate /= 2.0
		if data.tweaks.has("tube_count") and data.tweaks["tube_count"] > 0.0:
			fire_rate *= (data.tweaks["tube_count"] / 2.0)
		if data.tweaks.has("grid_size") and data.tweaks["grid_size"] > 0.0:
			fire_rate *= (data.tweaks["grid_size"] / 4.0)
		if data.tweaks.has("pressure_valve") and data.tweaks["pressure_valve"] > 0.0:
			fire_rate /= data.tweaks["pressure_valve"]
		if data.tweaks.has("launch_catapult") and data.tweaks["launch_catapult"] > 0.0:
			fire_rate /= data.tweaks["launch_catapult"]

		# Energy weapons: cost to fire scales with the weapon's own damage
		# output (dps*fire_rate is the per-shot damage), so a bigger/harder-
		# hitting energy weapon also drains the capacitor faster per shot -
		# no separate catalog field needed, it falls out of existing stats.
		if type_id in ENERGY_WEAPON_TYPES:
			var per_shot_damage = dps * fire_rate
			energy_cost_per_shot = per_shot_damage * 0.4
			if type_id == "arc_projector":
				energy_drain_per_shot = per_shot_damage * 1.5
			else:
				energy_drain_per_shot = per_shot_damage * 0.5

		fire_range *= FactionCatalog.get_passive(mount_faction, "range_mult", 1.0)

	# Desynchronize initial reload timers
	time_since_last_shot = randf_range(0.0, fire_rate)

# Crimson Concordat's passive: desperation damage that ramps up as this
# weapon's own vehicle approaches death (linear 0 at full HP -> bonus_max at
# 0 HP) - recomputed every tick since HP changes constantly, unlike every
# other faction dps/range bonus which is a fixed value set once in _ready().
func _recalculate_low_hp_dps_bonus():
	dps = base_dps
	var vehicle = get_vehicle_root()
	if not vehicle or not ("hp" in vehicle) or not ("max_hp" in vehicle) or vehicle.max_hp <= 0.0:
		return
	var mount_faction = get_parent().get_meta("faction", "industrialists") if get_parent() and get_parent().has_meta("faction") else "industrialists"
	var bonus_max = FactionCatalog.get_passive(mount_faction, "low_hp_dps_bonus_max", 0.0)
	if bonus_max <= 0.0:
		return
	var hp_ratio = clamp(vehicle.hp / vehicle.max_hp, 0.0, 1.0)
	dps = base_dps * (1.0 + bonus_max * (1.0 - hp_ratio))

# RTS_CORE_ROADMAP.md D4: a defense building's weapons are inert for its
# whole build_incomplete grace period (real construction time, not just a
# cosmetic scale-up) - walks up to whichever ancestor actually carries the
# flag (building.gd), since a weapon module sits several nodes below the
# building itself in the reconstructed hull hierarchy.
func _owner_building_incomplete() -> bool:
	var node = get_parent()
	while node:
		if "build_incomplete" in node:
			return node.build_incomplete
		node = node.get_parent()
	return false

# RTS_CORE_ROADMAP.md E1: "disabling defence weapons" while a team's power
# is Low or Critical - only ever applies to a "defense"-kind building.gd
# owner (a mobile unit's weapons run off its own onboard capacitor, never
# the team's base power - see ENERGY_AND_BALANCE_SPEC.md #1, the same
# boundary skirmish.gd's _recalc_energy_economy() already draws). Duck-
# typed through current_scene same as _teams_allied() - a real Skirmish's
# is_low_power(team), nothing in a synthetic test/test-range context.
func _owner_defense_low_power() -> bool:
	var node = get_parent()
	while node:
		if "kind" in node and node.kind == "defense":
			var scene = get_tree().current_scene
			if scene and scene.has_method("is_low_power"):
				return scene.is_low_power(node.team)
			return false
		node = node.get_parent()
	return false

func _physics_process(delta):
	if _owner_building_incomplete() or _owner_defense_low_power():
		return
	# Spin radar mast dish
	if type_id == "sensor_suite":
		var dish = get_node_or_null("sensor_suite_dish")
		if not dish:
			dish = get_node_or_null("RadarDish")
		if dish:
			dish.rotate_y(delta * 2.5)
		return

	time_since_last_shot += delta
	_los_cache_timer -= delta
	_recalculate_low_hp_dps_bonus()
	_find_nearest_target(delta)

	if target and is_instance_valid(target):
		var target_pos = target.global_position
		# Target center height
		if target.is_in_group("targets") or target.is_in_group("player_vehicle"):
			target_pos += Vector3(0, 0.5, 0)
			
		var dir_to_target = (target_pos - global_position).normalized()

		# frame_built (traverse_limit_angle == 0): the barrel is fixed
		# relative to the hull by definition - skip the independent-aim
		# slerp entirely and stay at resting_transform. The whole vehicle
		# has to turn to bring it to bear (battle_unit.gd's
		# _has_frame_built_weapon/whole-vehicle-aim handles that), and the
		# angle_to_target check just below naturally reflects that since
		# global_transform now tracks the hull's own facing 1:1.
		if traverse_limit_angle > 0.001:
			# Target local direction relative to THIS WEAPON's own mount
			# point, not the hull's origin. Previously this normalized
			# target_local_pos directly - the target's position relative
			# to the hull's ORIGIN, not to the weapon's own (usually
			# off-center) mount position - which is only the correct aim
			# direction for a weapon sitting exactly at the hull's center.
			# Every other weapon (nearly all of them) aimed with a
			# permanent, never-converging angular error proportional to
			# its offset from hull-center and inversely proportional to
			# target distance (worse up close), so angle_to_target could
			# sit well above the 0.26 rad firing gate forever - a fully
			# independently-traversing pintle weapon that visibly slews
			# toward a target and then simply never actually fires.
			var target_local_pos = get_parent().to_local(target_pos)
			var local_dir = (target_local_pos - position).normalized()
			var target_local_basis = _looking_at_safe(local_dir)

			# Gradually rotate local basis towards target using Quaternions
			var q_current = transform.basis.get_rotation_quaternion()
			var q_target = target_local_basis.get_rotation_quaternion()
			var q_next = q_current.slerp(q_target, traverse_speed * delta)
			var local_scale = transform.basis.get_scale()
			transform.basis = Basis(q_next).scaled(local_scale)

		# Check if pointing close enough to fire
		var current_dir = -global_transform.basis.z.normalized()
		var angle_to_target = current_dir.angle_to(dir_to_target)
		
		# Only fire if pointing within ~15 degrees (0.26 rad) and not blocked.
		# Widened from 0.17 rad (10°): slow/heavy turrets that physically have
		# 360° arc were tracking targets indefinitely without ever closing into
		# the 10° cone tight enough to trigger a shot. 15° still requires the
		# weapon to be meaningfully pointed at the target while giving the
		# traverse mechanism realistic slack to complete its slew.
		if angle_to_target < 0.26 and not _is_line_of_sight_blocked():
			# Spin up check for Rotary Cannon
			if type_id == "rotary_cannon":
				var spin_needed = 0.8
				if has_meta("module_data"):
					var m_data = get_meta("module_data")
					var motor_size = m_data.tweaks.get("motor_size", 1.0)
					if motor_size > 0.0:
						spin_needed /= motor_size
				
				# Visually rotate barrels if spun up or spinning.
				var barrel_cluster = get_node_or_null("BarrelCluster")
				if not barrel_cluster:
					barrel_cluster = find_child("BarrelCluster", true, false)
				if barrel_cluster:
					barrel_cluster.rotate_object_local(Vector3.FORWARD, delta * (spin_up_timer / spin_needed) * 30.0)
				
				if spin_up_timer < spin_needed:
					spin_up_timer += delta
					return # still spinning up!
					
			if time_since_last_shot >= fire_rate:
				# Energy weapons need a charged capacitor to fire - a real
				# soft-limit on sustained fire, not just a stat number. If
				# the shooter has no current_energy field at all (a legacy/
				# test-harness node), fire freely rather than hard-blocking
				# on a duck-typed method that doesn't exist.
				var can_fire = true
				if type_id in ENERGY_WEAPON_TYPES:
					var root_vehicle = get_vehicle_root()
					if root_vehicle and root_vehicle.has_method("spend_energy"):
						can_fire = root_vehicle.spend_energy(energy_cost_per_shot)
				if can_fire:
					time_since_last_shot = 0.0
					_fire_at_target()
		else:
			# Not pointing at target, spin down
			if type_id == "rotary_cannon":
				spin_up_timer = max(0.0, spin_up_timer - delta * 2.0)
	else:
		# Return to resting transform in local space using Quaternions
		var q_current = transform.basis.get_rotation_quaternion()
		var q_target = resting_transform.basis.get_rotation_quaternion()
		var q_next = q_current.slerp(q_target, traverse_speed * delta)
		var local_scale = transform.basis.get_scale()
		transform.basis = Basis(q_next).scaled(local_scale)
		
		# Spin down Gatling
		if type_id == "rotary_cannon":
			spin_up_timer = max(0.0, spin_up_timer - delta * 2.0)

# Target stickiness: re-scanning "nearest" from scratch every physics tick
# means two roughly-equidistant candidates (patrolling test dummies, two
# enemies converging on a flank) flip which one is "nearest" every single
# frame as they move, yanking the turret's slew back and forth and never
# letting angle_to_target close enough to fire - weapons could visibly
# track a target forever without ever landing a shot. Keeping the current
# target as long as it's still a legal pick (alive, in range, in arc, not
# fog-hidden, still the right kind of candidate for this weapon's mode)
# avoids the thrash; only reacquire once it's actually no longer valid.
func _is_current_target_still_valid(resting_forward: Vector3) -> bool:
	if not target or not is_instance_valid(target):
		return false
	if "is_dead" in target and target.is_dead:
		return false
	if "health" in target and target.health <= 0.0:
		return false
	if target.is_in_group("missiles"):
		return true # transient - PD logic re-validates range/team itself below
	if targets_allies:
		if not ("hp" in target and "max_hp" in target) or target.hp >= target.max_hp:
			return false
	else:
		var my_team = get_team()
		if my_team >= 0:
			var t_team = target.get_meta("team") if target.has_meta("team") else -1
			if _teams_allied(t_team, my_team):
				return false
			if "fog_hidden" in target and target.fog_hidden:
				return false
	if global_position.distance_to(target.global_position) > fire_range:
		return false
	var dir = (target.global_position - global_position).normalized()
	if resting_forward.angle_to(dir) > max(traverse_limit_angle, MIN_ACQUISITION_ARC):
		return false
	# Stop clinging to something our own hull is standing in front of -
	# otherwise the weapon tracks an unshootable target indefinitely instead
	# of reacquiring one it can actually engage.
	if _is_los_blocked_cached(target):
		return false
	return true

# PERFORMANCE_PLAN.md P1: cached wrapper around _is_los_blocked_to() for the
# "is my CURRENT target still valid" fast path - see the _los_cache_* var
# comments above. Reacquisition scans below call _is_los_blocked_to()
# directly (uncached), since those check many different one-off candidates
# rather than repeatedly re-checking the same target.
func _is_los_blocked_cached(candidate: Node3D) -> bool:
	if candidate == _los_cache_target and _los_cache_timer > 0.0:
		return _los_cache_blocked
	_los_cache_blocked = _is_los_blocked_to(candidate)
	_los_cache_target = candidate
	_los_cache_timer = LOS_CACHE_TTL
	return _los_cache_blocked

# PERFORMANCE_PLAN.md P1c: narrows the whole-roster "damageable" scan down
# to just the cells within `radius` of `pos` when a real Skirmish (with the
# spatial grid) is running the scene - duck-typed the same way
# _teams_allied() defers to current_scene.is_allied(), so the Test Range and
# every headless test fixture (neither has a real Skirmish) fall back to the
# exact old full-roster scan unchanged.
func _damageable_candidates(pos: Vector3, radius: float) -> Array:
	var scene = get_tree().current_scene
	if scene and scene.has_method("get_nearby_damageable"):
		return scene.get_nearby_damageable(pos, radius)
	return get_tree().get_nodes_in_group("damageable")

# delta defaults to -1.0 (a "forced/manual scan" sentinel, distinct from any
# real physics delta which is always >= 0.0) so every direct/manual caller in
# run_tests.gd - which calls this with no arguments and expects a synchronous,
# unthrottled scan - keeps working unchanged. Only real _physics_process(delta)
# ticks (delta >= 0.0) are subject to the throttle below.
func _find_nearest_target(delta: float = -1.0):
	var resting_forward = get_parent().global_transform.basis * resting_transform.basis * Vector3.FORWARD

	if _is_current_target_still_valid(resting_forward):
		return

	# PERFORMANCE_PLAN.md P1a: the full-roster/grid scans below are the
	# expensive path - throttle them instead of running every tick while no
	# valid target exists. target stays whatever it currently is (usually
	# null) between scans. (Previously attempted and reverted this same
	# session over a suspected regression that turned out to be an
	# unrelated pre-existing flaky test - see git history / PROGRESS.md.)
	if delta >= 0.0:
		_reacquire_timer -= delta
		if _reacquire_timer > 0.0:
			return
		_reacquire_timer = REACQUIRE_INTERVAL

	# --- TEAM MODE (Skirmish): target any hostile "damageable" construct ---
	var my_team = get_team()
	if my_team >= 0:
		# repair_array's real fix: same-team, HP-deficit candidates instead
		# of hostiles - the opposite filter from every other weapon below.
		if targets_allies:
			var ally_candidates = _damageable_candidates(global_position, fire_range)
			var closest_ally: Node3D = null
			var closest_ally_dist: float = fire_range
			for c in ally_candidates:
				if not is_instance_valid(c) or not c.has_method("repair_hp"): continue
				var c_team = c.get_meta("team") if c.has_meta("team") else -1
				if not _teams_allied(c_team, my_team): continue
				if "is_dead" in c and c.is_dead: continue
				if not ("hp" in c and "max_hp" in c) or c.hp >= c.max_hp: continue
				var dist = global_position.distance_to(c.global_position)
				if dist < closest_ally_dist:
					var dir = (c.global_position - global_position).normalized()
					if resting_forward.angle_to(dir) <= max(traverse_limit_angle, MIN_ACQUISITION_ARC):
						closest_ally = c
						closest_ally_dist = dist
			target = closest_ally
			return
		# Point defense still prioritizes missiles aimed at friendlies
		if type_id in ["ciws", "pd_laser", "flak_cannon"]:
			var missiles = get_tree().get_nodes_in_group("missiles")
			var closest_m: Node3D = null
			var closest_m_dist: float = fire_range
			for m in missiles:
				if not is_instance_valid(m): continue
				var m_team = m.get_meta("team") if m.has_meta("team") else -1
				if _teams_allied(m_team, my_team): continue
				var dist_m = global_position.distance_to(m.global_position)
				if dist_m < closest_m_dist:
					var dir_m = (m.global_position - global_position).normalized()
					if resting_forward.angle_to(dir_m) <= max(traverse_limit_angle, MIN_ACQUISITION_ARC):
						closest_m = m
						closest_m_dist = dist_m
			if closest_m:
				target = closest_m
				return
		var candidates = _damageable_candidates(global_position, fire_range)
		var closest_c: Node3D = null
		var closest_c_dist: float = fire_range
		for c in candidates:
			if not is_instance_valid(c) or not c.has_method("take_damage"): continue
			var c_team = c.get_meta("team") if c.has_meta("team") else -1
			if _teams_allied(c_team, my_team): continue
			if "is_dead" in c and c.is_dead: continue
			# Fog-of-war: can't target what hasn't been scouted. Only ever
			# true for enemy-team constructs (skirmish.gd's fog scan never
			# hides the player's own units), so this is a safe universal
			# check regardless of which team's weapon is doing the
			# targeting - it only ever filters out something that was
			# already going to be a hostile candidate.
			if "fog_hidden" in c and c.fog_hidden: continue
			var dist = global_position.distance_to(c.global_position)
			if dist < closest_c_dist:
				var dir = (c.global_position - global_position).normalized()
				if resting_forward.angle_to(dir) <= max(traverse_limit_angle, MIN_ACQUISITION_ARC) and not _is_los_blocked_to(c):
					closest_c = c
					closest_c_dist = dist
		target = closest_c
		return

	# Point Defenses prioritize incoming missiles
	if type_id in ["ciws", "pd_laser", "flak_cannon"]:
		var missiles = get_tree().get_nodes_in_group("missiles")
		var closest: Node3D = null
		var closest_dist: float = fire_range
		for m in missiles:
			if is_instance_valid(m):
				var dist = global_position.distance_to(m.global_position)
				if dist < closest_dist:
					var dir = (m.global_position - global_position).normalized()
					if resting_forward.angle_to(dir) <= max(traverse_limit_angle, MIN_ACQUISITION_ARC):
						closest = m
						closest_dist = dist
		target = closest
		if target: return

	# Standard target dummies
	var targets = get_tree().get_nodes_in_group("targets")
	
	# If this weapon is on target dummy, target the player instead!
	var root_vehicle = get_vehicle_root()
	if root_vehicle and root_vehicle.is_in_group("targets"):
		var player = get_tree().get_first_node_in_group("player_vehicle")
		if player and is_instance_valid(player) and not player.is_dead:
			var dist = global_position.distance_to(player.global_position)
			if dist < fire_range:
				var dir = (player.global_position - global_position).normalized()
				if resting_forward.angle_to(dir) <= max(traverse_limit_angle, MIN_ACQUISITION_ARC):
					target = player
					return
		target = null
		return

	# Player targeting dummies
	var closest: Node3D = null
	var closest_dist: float = fire_range
	for t in targets:
		if is_instance_valid(t) and t.has_method("take_damage"):
			if "health" in t and t.health <= 0.0:
				continue
			var dist = global_position.distance_to(t.global_position)
			if dist < closest_dist:
				var dir = (t.global_position - global_position).normalized()
				if resting_forward.angle_to(dir) <= max(traverse_limit_angle, MIN_ACQUISITION_ARC) and not _is_los_blocked_to(t):
					closest = t
					closest_dist = dist
	target = closest

func _fire_at_target():
	if not target or not is_instance_valid(target): return
	
	# Point Defense intercepting a missile
	if target.is_in_group("missiles"):
		_fire_pd_at_missile()
		return
		
	# Spawn a nice muzzle flash (except for silent lasers/beams/harvester/welder)
	if not type_id in ["heavy_laser", "pd_laser", "resource_harvester", "repair_array"]:
		VFXBurstScript.spawn(self, Vector3(0, 0.4, -0.6), laser_color, 8, 0.1, 25.0, 3.0, 6.0, Vector3.ZERO, 0.4, 0.9)

	var sfx_name = "cannon"
	match type_id:
		"basic_cannon", "artillery", "flak_cannon", "plasma_lobber": sfx_name = "cannon"
		"heavy_machine_gun", "rotary_cannon", "ciws": sfx_name = "machine_gun"
		"gauss_railgun", "heavy_laser", "pd_laser", "tesla_coil", "arc_projector", "ion_cannon": sfx_name = "laser"
		"guided_missile", "missile_pod", "cluster_dispenser": sfx_name = "missile"
		"resource_harvester", "repair_array": sfx_name = "harvest"
	if get_node_or_null("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx_3d(sfx_name, global_position, null, 50.0)

	# Call unique visual functions
	match type_id:
		"basic_cannon":
			_fire_kinetic_projectile(0.05, 0.5, 0.18, laser_color, true)
		"heavy_machine_gun":
			_fire_kinetic_projectile(0.015, 0.25, 0.08, laser_color, false)
		"rotary_cannon":
			_fire_kinetic_projectile(0.012, 0.2, 0.06, laser_color, false)
		"gauss_railgun":
			_fire_railgun_beam()
		"artillery":
			_fire_artillery()
		"mortar_array":
			_fire_mortar_salvo()
		"guided_missile":
			_fire_missile_projectile(false)
		"missile_pod":
			_fire_swarm_missiles()
		"drone_carrier":
			_fire_drone_swarm()
		"cluster_dispenser":
			_fire_cluster_dispenser()
		"flamethrower":
			_fire_flame_spray()
		"heavy_laser":
			_fire_continuous_beam()
		"plasma_lobber":
			_fire_plasma_lobber()
		"ciws":
			_fire_kinetic_projectile(0.01, 0.18, 0.06, laser_color, false)
		"pd_laser":
			_fire_continuous_beam()
		"flak_cannon":
			_fire_flak_cannon()
		"resource_harvester":
			_fire_resource_harvester_tether()
		"repair_array":
			_fire_repair_array_beam()
		"tesla_coil":
			_fire_tesla_coil()
		"arc_projector":
			_fire_arc_projector()
		"ion_cannon":
			_fire_ion_cannon()
		_:
			_fire_standard_laser()

func _fire_pd_at_missile():
	if type_id == "pd_laser":
		var beam = MeshInstance3D.new()
		beam.mesh = MunitionPool.unit_cylinder()
		beam.material_override = MunitionPool.emissive(Color.LIGHT_CORAL, Color.RED)
		_effects_parent().add_child(beam)
		MunitionPool.aim_beam(beam, global_position, target.global_position, 0.04)
		var timer = get_tree().create_timer(0.08)
		timer.timeout.connect(func(): if is_instance_valid(beam): beam.queue_free())
		
	if target.has_method("destroy_missile"):
		target.destroy_missile(true)

func _fire_kinetic_projectile(radius: float, length: float, duration: float, color: Color, explode_on_hit: bool):
	var tracer = MeshInstance3D.new()
	tracer.mesh = MunitionPool.unit_cylinder()
	tracer.scale = Vector3(radius * 2.0, length, radius * 2.0)
	tracer.material_override = MunitionPool.emissive(color, color)
	_effects_parent().add_child(tracer)

	var start = global_position + Vector3(0, 0.4, 0)
	tracer.global_position = start
	tracer.look_at(target.global_position, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, PI/2)
	
	var tween = create_tween()
	var end = target.global_position
	tween.tween_property(tracer, "global_position", end, duration)
	tween.finished.connect(func():
		if is_instance_valid(tracer): tracer.queue_free()
		if is_instance_valid(target):
			_deal_weapon_damage(target, dps * fire_rate)
			if explode_on_hit:
				_spawn_explosion_visual(end, 0.4, color)
	)

func _fire_railgun_beam():
	var beam = MeshInstance3D.new()
	beam.mesh = MunitionPool.unit_cylinder()
	beam.material_override = MunitionPool.emissive(Color.BLUE_VIOLET, Color.BLUE_VIOLET)
	_effects_parent().add_child(beam)

	var beam_len = MunitionPool.aim_beam(beam, global_position, target.global_position, 0.06)

	for i in range(4):
		var spark = MeshInstance3D.new()
		spark.mesh = MunitionPool.unit_sphere()
		spark.scale = Vector3(0.3, 0.3, 0.3)
		spark.material_override = MunitionPool.emissive(Color.CYAN, Color.CYAN)
		_effects_parent().add_child(spark)

		var pct = randf()
		spark.global_position = global_position.lerp(target.global_position, pct) + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
		
		var stween = create_tween()
		stween.tween_property(spark, "scale", Vector3.ZERO, 0.1)
		stween.finished.connect(func(): spark.queue_free())
		
	if is_instance_valid(target):
		_deal_weapon_damage(target, dps * fire_rate)
		_spawn_explosion_visual(target.global_position, 0.6, Color.BLUE_VIOLET)

	# Collapses the beam's radius while holding its length - the y component
	# used to be a literal 1.0 because length lived in the mesh; it now lives
	# in scale.y, so it has to be preserved explicitly here.
	var tween = create_tween()
	tween.tween_property(beam, "scale", Vector3(0.0, beam_len, 0.0), 0.15)
	tween.finished.connect(func(): beam.queue_free())

func _fire_artillery():
	var shell = MeshInstance3D.new()
	shell.mesh = MunitionPool.unit_sphere()
	shell.scale = Vector3(0.4, 0.4, 0.4)
	shell.material_override = MunitionPool.emissive(Color.SADDLE_BROWN, Color.ORANGE)
	_effects_parent().add_child(shell)
	
	var start = global_position
	var end = target.global_position
	var tween = create_tween()
	var callable = func(val: float):
		if not is_instance_valid(shell): return
		var current_target = end
		if is_instance_valid(target):
			current_target = target.global_position
		var pos = start.lerp(current_target, val)
		pos.y += sin(val * PI) * 12.0
		shell.global_position = pos
		
	tween.tween_method(callable, 0.0, 1.0, 0.8)
	tween.finished.connect(func():
		if is_instance_valid(shell): shell.queue_free()
		_deal_aoe_damage(end, 6.0, dps * fire_rate)
		_spawn_explosion_visual(end, 1.2, Color.ORANGE)
	)

func _fire_mortar_salvo():
	var count = 3
	if has_meta("module_data"):
		var data = get_meta("module_data")
		count = int(data.tweaks.get("tube_count", 2.0))
		
	for i in range(count):
		get_tree().create_timer(i * 0.18).timeout.connect(func():
			if not is_instance_valid(target): return
			var shell = MeshInstance3D.new()
			shell.mesh = MunitionPool.unit_sphere()
			shell.scale = Vector3(0.2, 0.2, 0.2)
			shell.material_override = MunitionPool.emissive(Color.OLIVE, Color.YELLOW)
			_effects_parent().add_child(shell)
			
			var start = global_position
			var end = target.global_position + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
			var tween = create_tween()
			var height = 6.0
			var callable = func(val: float):
				if not is_instance_valid(shell): return
				var pos = start.lerp(end, val)
				pos.y += sin(val * PI) * height
				shell.global_position = pos
				
			tween.tween_method(callable, 0.0, 1.0, 0.6)
			tween.finished.connect(func():
				if is_instance_valid(shell): shell.queue_free()
				_deal_aoe_damage(end, 4.0, (dps * fire_rate) / count)
				_spawn_explosion_visual(end, 0.5, Color.YELLOW)
			)
		)

const WeaponMissileScene = preload("res://scripts/weapon_missile.gd")

# Real, interceptable missile (FABLE_REVIEW.md 2.2/2.2) instead of a cosmetic
# tween - see weapon_missile.gd. is_top_attack/target/damage must be set
# before add_child() since _ready() reads them immediately.
func _fire_missile_projectile(is_top_attack: bool):
	if not is_instance_valid(target): return
	var missile = Node3D.new()
	missile.set_script(WeaponMissileScene)
	missile.position = global_position + Vector3(0, 0.5, 0)
	missile.is_top_attack = is_top_attack
	missile.setup(target, self, dps * fire_rate, damage_class, get_team())
	_effects_parent().add_child(missile)

func _fire_swarm_missiles():
	var count = 4
	if has_meta("module_data"):
		var data = get_meta("module_data")
		count = int(data.tweaks.get("grid_size", 4.0))
	count = max(1, count)
	var per_missile_damage = (dps * fire_rate) / count

	for i in range(count):
		get_tree().create_timer(i * 0.08).timeout.connect(func():
			if not is_instance_valid(target): return
			var missile = Node3D.new()
			missile.set_script(WeaponMissileScene)
			missile.position = global_position + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
			missile.speed = 20.0
			missile.salvo_jitter = 1.2
			missile.setup(target, self, per_missile_damage, damage_class, get_team())
			_effects_parent().add_child(missile)
		)

func _fire_drone_swarm():
	# Real autonomous drones (drone_unit.gd), not tweened throwaway meshes -
	# see ENERGY_AND_BALANCE_SPEC.md #3. Count driven by the "Hangar Size"
	# tweak (previously documented in Arsenal_Weapons_List.md but missing
	# from TWEAK_SPECS entirely).
	var count = 2
	if has_meta("module_data"):
		var data = get_meta("module_data")
		count = int(data.tweaks.get("hangar_size", 2.0))
	count = max(1, count)
	var per_drone_damage = (dps * fire_rate) / count
	var my_team = get_team()
	var vehicle_root = get_vehicle_root()
	var carrier = vehicle_root if is_instance_valid(vehicle_root) else self
	for i in range(count):
		var drone = Node3D.new()
		drone.set_script(load("res://scripts/drone_unit.gd"))
		_effects_parent().add_child(drone)
		drone.global_position = global_position + Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5))
		drone.carrier = carrier
		drone.target = target
		drone.speed = 14.0
		drone.damage_per_hit = per_drone_damage
		drone.damage_class = damage_class
		drone.team = my_team

func _fire_cluster_dispenser():
	# Housing recoil animation
	for c in get_children():
		if c is MeshInstance3D:
			var orig_pos = c.position
			var rec_tween = create_tween()
			rec_tween.tween_property(c, "position", orig_pos + Vector3(0, 0, 0.08), 0.05)
			rec_tween.tween_property(c, "position", orig_pos, 0.15)
			break

	var dispersion = 1.0
	var payload_size = 1.0
	var t_count = 2
	if has_meta("module_data"):
		var data = get_meta("module_data")
		dispersion = data.tweaks.get("dispersion", 1.0)
		payload_size = data.tweaks.get("payload_size", 1.0)
		t_count = int(data.tweaks.get("tube_count", 2.0))

	var submunitions_per_canister = 3
	var total_bomblets = t_count * submunitions_per_canister
	var per_bomblet_damage = (dps * fire_rate) / float(total_bomblets)
	var scatter_radius = 3.0 * dispersion

	for c_idx in range(t_count):
		get_tree().create_timer(c_idx * 0.10).timeout.connect(func():
			if not is_instance_valid(target): return
			var canister = MeshInstance3D.new()
			var can_scene = load("res://assets/models/parts/cluster_dispenser_canister.glb")
			if can_scene:
				var inst = can_scene.instantiate()
				for child in inst.get_children():
					if child is MeshInstance3D:
						canister.mesh = child.mesh
						break
			else:
				# Left un-pooled deliberately: this is the
				# authored-mesh-missing fallback, so it fires at most once per
				# canister on a broken install, not on the hot path.
				var box = BoxMesh.new()
				box.size = Vector3(0.12 * payload_size, 0.12 * payload_size, 0.24 * payload_size)
				canister.mesh = box
			canister.material_override = MunitionPool.emissive(Color(0.70, 0.40, 0.20), Color.ORANGE_RED)
			_effects_parent().add_child(canister)

			var start = global_position + Vector3(randf_range(-0.1, 0.1), 0.3, randf_range(-0.1, 0.1))
			var end = target.global_position
			canister.global_position = start
			canister.scale = Vector3(payload_size, payload_size, payload_size)
			canister.look_at(end, Vector3.UP)

			var mid = start.lerp(end, 0.4) + Vector3(0, 1.5, 0)
			var tween = create_tween()
			tween.tween_property(canister, "global_position", mid, 0.25)
			tween.finished.connect(func():
				if is_instance_valid(canister): canister.queue_free()

				for i in range(submunitions_per_canister):
					var sub = MeshInstance3D.new()
					sub.mesh = MunitionPool.unit_sphere()
					sub.scale = Vector3.ONE * (0.12 * payload_size)
					sub.material_override = MunitionPool.emissive(Color.CHOCOLATE, Color.ORANGE)
					_effects_parent().add_child(sub)
					sub.global_position = mid

					var scatter_dest = end + Vector3(randf_range(-scatter_radius, scatter_radius), 0.0, randf_range(-scatter_radius, scatter_radius))
					var st = create_tween()
					st.tween_property(sub, "global_position", scatter_dest, 0.2)
					st.finished.connect(func():
						if is_instance_valid(sub): sub.queue_free()
						_deal_aoe_damage(scatter_dest, 2.5 * payload_size, per_bomblet_damage)
						_spawn_explosion_visual(scatter_dest, 0.3 * payload_size, Color.CHOCOLATE)
					)
			)
		)

func _fire_flame_spray():
	var n_width = 1.0
	var p_valve = 1.0
	if has_meta("module_data"):
		var data = get_meta("module_data")
		n_width = data.tweaks.get("nozzle_width", 1.0)
		p_valve = data.tweaks.get("pressure_valve", 1.0)

	# Body/Nozzle recoil vibration
	for c in get_children():
		if c is MeshInstance3D:
			var orig_pos = c.position
			var rec_tween = create_tween()
			rec_tween.tween_property(c, "position", orig_pos + Vector3(0, 0, 0.04 * p_valve), 0.04)
			rec_tween.tween_property(c, "position", orig_pos, 0.12)
			break

	for i in range(6):
		var flame = MeshInstance3D.new()
		flame.mesh = MunitionPool.unit_sphere()
		var init_scale = 0.15 * n_width
		var peak_scale = 0.45 * n_width
		flame.scale = Vector3(init_scale, init_scale, init_scale)
		# Per-flame colour jitter is what makes the spray read as fire rather
		# than as six identical balls, so it stays - but quantised to 0.05 so
		# the pool converges on a small fixed set of flame materials instead
		# of minting a new one for every continuously-random colour. At
		# fire_rate 0.06 x6 flames that is the difference between a bounded
		# cache and an unbounded leak over a long match.
		var flame_color = Color(
			snappedf(randf_range(0.85, 1.0), 0.05),
			snappedf(randf_range(0.2, 0.5), 0.05),
			0.0)
		flame.material_override = MunitionPool.emissive(flame_color, flame_color)
		_effects_parent().add_child(flame)

		flame.global_position = global_position + Vector3(randf_range(-0.1, 0.1), 0.35, randf_range(-0.1, 0.1))
		var spread = Vector3(randf_range(-1.2, 1.2) * n_width, randf_range(-0.2, 0.5) * n_width, randf_range(-1.2, 1.2) * n_width)
		var dest = target.global_position + spread

		var flight_dur = 0.35 * p_valve
		var tween = create_tween()
		tween.tween_property(flame, "global_position", dest, flight_dur)
		tween.parallel().tween_property(flame, "scale", Vector3(peak_scale, peak_scale, peak_scale), flight_dur * 0.4)
		tween.chain().tween_property(flame, "scale", Vector3.ZERO, flight_dur * 0.6)
		tween.finished.connect(func():
			if is_instance_valid(flame): flame.queue_free()
			if is_instance_valid(target) and i == 0:
				_deal_weapon_damage(target, dps * fire_rate)
		)

func _fire_continuous_beam():
	var beam = MeshInstance3D.new()
	beam.mesh = MunitionPool.unit_cylinder()
	beam.material_override = MunitionPool.emissive(laser_color, laser_color)
	_effects_parent().add_child(beam)

	MunitionPool.aim_beam(beam, global_position, target.global_position, 0.08)

	if is_instance_valid(target):
		_deal_weapon_damage(target, dps * fire_rate)

	var timer = get_tree().create_timer(0.06)
	timer.timeout.connect(func(): if is_instance_valid(beam): beam.queue_free())

func _fire_plasma_lobber():
	var plasma = MeshInstance3D.new()
	plasma.mesh = MunitionPool.unit_sphere()
	plasma.scale = Vector3(0.35, 0.35, 0.35)
	plasma.material_override = MunitionPool.emissive(Color.MEDIUM_SPRING_GREEN, Color.MEDIUM_SPRING_GREEN)
	_effects_parent().add_child(plasma)
	
	var start = global_position
	var end = target.global_position
	var tween = create_tween()
	var callable = func(val: float):
		if not is_instance_valid(plasma): return
		var pos = start.lerp(end, val)
		pos.y += sin(val * PI) * 4.0
		plasma.global_position = pos
		
	tween.tween_method(callable, 0.0, 1.0, 0.6)
	tween.finished.connect(func():
		if is_instance_valid(plasma): plasma.queue_free()
		_deal_aoe_damage(end, 4.5, dps * fire_rate)
		_spawn_explosion_visual(end, 0.8, Color.MEDIUM_SPRING_GREEN)

		var puddle = MeshInstance3D.new()
		puddle.mesh = MunitionPool.unit_cylinder()
		puddle.scale = Vector3(2.0, 0.05, 2.0)
		puddle.material_override = MunitionPool.alpha_emissive(
			Color(0.1, 0.8, 0.2, 0.4), Color.MEDIUM_SPRING_GREEN)
		_effects_parent().add_child(puddle)
		puddle.global_position = end

		var pt = create_tween()
		pt.tween_property(puddle, "scale", Vector3.ZERO, 1.5)
		pt.finished.connect(func(): puddle.queue_free())
	)

func _fire_flak_cannon():
	var shell = MeshInstance3D.new()
	shell.mesh = MunitionPool.unit_sphere()
	shell.scale = Vector3(0.18, 0.18, 0.18)
	shell.material_override = MunitionPool.emissive(Color.DARK_GOLDENROD, Color.GOLD)
	_effects_parent().add_child(shell)
	
	var start = global_position
	var end = target.global_position
	var detonate_pos = start.lerp(end, 0.85)
	
	var tween = create_tween()
	tween.tween_property(shell, "global_position", detonate_pos, 0.22)
	tween.finished.connect(func():
		if is_instance_valid(shell): shell.queue_free()
		
		var smoke = MeshInstance3D.new()
		smoke.mesh = MunitionPool.unit_sphere()
		smoke.scale = Vector3(1.6, 1.6, 1.6)
		smoke.material_override = MunitionPool.alpha(Color(0.15, 0.15, 0.15, 0.7))
		_effects_parent().add_child(smoke)
		smoke.global_position = detonate_pos
		
		var st = create_tween()
		st.tween_property(smoke, "scale", Vector3.ZERO, 0.4)
		st.finished.connect(func(): smoke.queue_free())

		_deal_aoe_damage(detonate_pos, 5.0, dps * fire_rate)
	)

func _fire_resource_harvester_tether():
	var tether = MeshInstance3D.new()
	tether.mesh = MunitionPool.unit_cylinder()
	tether.material_override = MunitionPool.emissive(Color.GOLD, Color.GOLD)
	_effects_parent().add_child(tether)

	var tether_len = MunitionPool.aim_beam(tether, global_position, target.global_position, 0.16)

	if is_instance_valid(target):
		_deal_weapon_damage(target, dps * fire_rate)

	# y holds the tether's length now that it is no longer baked into the mesh
	# (was a literal 1); only the radius collapses.
	var tween = create_tween()
	tween.tween_property(tether, "scale", Vector3(0, tether_len, 0), 0.08)
	tween.finished.connect(func(): tether.queue_free())

func _fire_repair_array_beam():
	var beam = MeshInstance3D.new()
	beam.mesh = MunitionPool.unit_cylinder()
	beam.material_override = MunitionPool.emissive(Color.CYAN, Color.CYAN)
	_effects_parent().add_child(beam)

	MunitionPool.aim_beam(beam, global_position, target.global_position, 0.06)

	var spark = MeshInstance3D.new()
	spark.mesh = MunitionPool.unit_sphere()
	spark.scale = Vector3(0.3, 0.3, 0.3)
	spark.material_override = MunitionPool.emissive(Color.WHITE, Color.CYAN)
	_effects_parent().add_child(spark)
	spark.global_position = target.global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.8), randf_range(-0.3, 0.3))
	var st = create_tween()
	st.tween_property(spark, "scale", Vector3.ZERO, 0.1)
	st.finished.connect(func(): spark.queue_free())
	
	if is_instance_valid(target) and target.has_method("repair_hp"):
		target.repair_hp(heal_rate * fire_rate)

	var timer = get_tree().create_timer(0.08)
	timer.timeout.connect(func(): if is_instance_valid(beam): beam.queue_free())

# --- Energy weapons (ENERGY_AND_BALANCE_SPEC.md #4/#5) ---
# All three drain the TARGET's current_energy (duck-typed via
# has_method("drain_energy")) on top of whatever HP damage they deal -
# energy_drain_per_shot/energy_cost_per_shot are computed once in _ready()
# from the weapon's own dps*fire_rate, see there for the formula.

func _fire_tesla_coil():
	# A little silly on purpose (Chris's explicit invitation) - a zigzag
	# chain-lightning bolt built from a handful of jittered segments,
	# rather than a straight beam like every other weapon.
	var segments = 5
	var prev_pos = global_position + Vector3(0, 0.5, 0)
	var end_pos = target.global_position
	for i in range(1, segments + 1):
		var t = float(i) / float(segments)
		var pos = global_position.lerp(end_pos, t)
		if i < segments:
			pos += Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4))
		var bolt = MeshInstance3D.new()
		bolt.mesh = MunitionPool.unit_cylinder()
		bolt.material_override = MunitionPool.emissive(laser_color, laser_color, 1.5)
		_effects_parent().add_child(bolt)
		MunitionPool.aim_beam(bolt, prev_pos, pos, 0.05)
		var bt = create_tween()
		bt.tween_interval(0.1)
		bt.finished.connect(func(): if is_instance_valid(bolt): bolt.queue_free())
		prev_pos = pos

	if is_instance_valid(target):
		_deal_weapon_damage(target, dps * fire_rate)
		if target.has_method("drain_energy"):
			target.drain_energy(energy_drain_per_shot)
		_spawn_explosion_visual(end_pos, 0.5, laser_color)

func _fire_arc_projector():
	# The dedicated pure-drain "disable" weapon - minor HP damage, big
	# energy drain (see _ready()'s energy_drain_per_shot formula).
	var beam = MeshInstance3D.new()
	# The only beam in the arsenal that widens along its length (0.02 -> 0.05),
	# so it takes the taper variant rather than the plain unit cylinder; the
	# 0.4 ratio is that same 0.02/0.05, with the 0.05 bottom carried by the
	# 0.10 diameter passed to aim_beam.
	beam.mesh = MunitionPool.unit_taper(0.4)
	beam.material_override = MunitionPool.emissive(laser_color, laser_color, 2.0)
	_effects_parent().add_child(beam)
	MunitionPool.aim_beam(beam, global_position, target.global_position, 0.10)

	if is_instance_valid(target):
		_deal_weapon_damage(target, (dps * fire_rate) * 0.2)
		if target.has_method("drain_energy"):
			target.drain_energy(energy_drain_per_shot)

	var timer = get_tree().create_timer(0.1)
	timer.timeout.connect(func(): if is_instance_valid(beam): beam.queue_free())

func _fire_ion_cannon():
	# The "grounded" energy heavy-hitter - single strong beam, full HP
	# damage plus a real energy drain alongside it.
	var beam = MeshInstance3D.new()
	beam.mesh = MunitionPool.unit_cylinder()
	beam.material_override = MunitionPool.emissive(laser_color, laser_color, 1.2)
	_effects_parent().add_child(beam)
	var beam_len = MunitionPool.aim_beam(beam, global_position, target.global_position, 0.12)

	if is_instance_valid(target):
		_deal_weapon_damage(target, dps * fire_rate)
		if target.has_method("drain_energy"):
			target.drain_energy(energy_drain_per_shot)
		_spawn_explosion_visual(target.global_position, 0.7, laser_color)

	# Radius-only collapse; y preserves the length that now lives in scale.
	var tween = create_tween()
	tween.tween_property(beam, "scale", Vector3(0.0, beam_len, 0.0), 0.15)
	tween.finished.connect(func(): if is_instance_valid(beam): beam.queue_free())

func _spawn_explosion_visual(pos: Vector3, custom_scale: float = 0.6, color: Color = Color.ORANGE):
	var exp = MeshInstance3D.new()
	exp.mesh = MunitionPool.unit_sphere()
	# custom_scale was the sphere's RADIUS (with height 2x it, i.e. a true
	# sphere), so the equivalent uniform scale on a unit-diameter sphere is
	# twice it.
	exp.scale = Vector3.ONE * (custom_scale * 2.0)
	exp.material_override = MunitionPool.emissive(color, color)
	_effects_parent().add_child(exp)
	exp.global_position = pos
	
	var tween = create_tween()
	tween.tween_property(exp, "scale", Vector3.ZERO, 0.15)
	tween.finished.connect(func(): exp.queue_free())

func _fire_standard_laser():
	var laser = MeshInstance3D.new()
	laser.mesh = MunitionPool.unit_cylinder()
	laser.material_override = MunitionPool.emissive(laser_color, laser_color)
	_effects_parent().add_child(laser)

	MunitionPool.aim_beam(laser, global_position, target.global_position, 0.10)


	if is_instance_valid(target):
		_deal_weapon_damage(target, dps * fire_rate)
	
	var timer = get_tree().create_timer(0.08)
	timer.timeout.connect(func(): if is_instance_valid(laser): laser.queue_free())
