extends Node3D
# C&C-style Skirmish mode. The player's saved blueprints (plus bundled defaults)
# form the buildable roster. Destroy the enemy HQ to win; lose yours and it's over.

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const BattleUnitScript = preload("res://scripts/battle_unit.gd")
const BuildingScript = preload("res://scripts/building.gd")
const ResourceNodeScript = preload("res://scripts/resource_node.gd")
const EnemyAIScript = preload("res://scripts/enemy_ai.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")
const TerrainBuilder = preload("res://scripts/terrain_builder.gd")

const PLAYER_TEAM = 0
const ENEMY_TEAM = 1

var bp_manager: Node
var economy = {
	PLAYER_TEAM: {"metal": 450, "crystal": 150},
	ENEMY_TEAM: {"metal": 450, "crystal": 150},
}
# Energy resource (ENERGY_AND_BALANCE_SPEC.md #1) - deliberately NOT a
# spendable currency like metal/crystal (can_afford/spend/blueprint_cost
# keep their existing 2-resource signatures, see the spec for why). Instead
# a live meter, recomputed every ENERGY_TICK_INTERVAL: "energy" is the
# team's current net generation (capacity minus static-building upkeep,
# floored at 0 - it's a gauge, not an accumulating battery), "capacity" is
# the live sum of every generator module currently mounted on that team's
# active units+buildings.
var energy_pool = {
	PLAYER_TEAM: {"energy": 0.0, "capacity": 0.0, "deficit": false},
	ENEMY_TEAM: {"energy": 0.0, "capacity": 0.0, "deficit": false},
}
const ENERGY_TICK_INTERVAL: float = 3.0
const ENERGY_UPKEEP_PER_STATIC_BUILDING: float = 3.0
# The HQ has its own baseline power plant - without this, every match
# starts in automatic Energy deficit from frame one (0 capacity vs. 3
# starting static buildings' upkeep = 9.0), applying the factory
# build-speed penalty before a player has had any chance to build a
# generator. Found via the visual regression pass (skirmish_hud capture
# showed "DEFICIT: builds slower!" at match start, before any real
# gameplay) - sized to roughly offset default starting upkeep so a team is
# breakeven-to-slightly-ahead by default, and generators become a genuine
# optional upgrade (more energy for energy weapons) rather than a
# mandatory tax just to avoid a permanent penalty.
const ENERGY_HQ_BASELINE_CAPACITY: float = 10.0
var energy_tick_timer: float = 0.0

# Fog-of-war (built this pass): real vision-radius system, no supporting
# infrastructure existed before this - Technocrats' "+15% sensor/radar
# vision" passive (Factions_and_Buildings.md) was unimplementable until
# now for exactly that reason. Faster tick than Energy's (units move
# continuously, so vision needs to feel responsive) but still a fixed
# interval, not per-frame - a few hundred ms of stale fog is imperceptible
# and this scan is O(player constructs x enemy constructs) every tick.
const FOG_TICK_INTERVAL: float = 0.3

# Real pathfinding + naval terrain (built two passes ago - the map was
# flat and open with nothing to route around, and naval units were purely
# Y-locked to a fixed waterline with no actual water/land distinction
# anywhere). Two SEPARATE NavigationServer3D maps (not layers on one map)
# - simpler to reason about than layer bitmasks: ground units path on
# ground_nav_map (full terrain minus holes for water/obstacles/elevation
# footprints - see terrain_builder.gd), naval units path on water_nav_map
# (just the water areas). Flying units ignore navigation entirely (open
# air, nothing to route around). See battle_unit.gd's
# _setup_navigation()/_steer_towards() for how units actually consume this.
var ground_nav_map: RID
var water_nav_map: RID
# Amphibious (screw_drive locomotion) units path here instead - the same
# ground grid PLUS water areas as walkable terrain, so a screw-drive unit
# can cross a lake in one continuous route instead of being confined to
# ground_nav_map like every other ground/legged type.
var amphibious_nav_map: RID
# Deep-draught-only naval units (heavy_cruiser_hull) path here instead of
# water_nav_map - the same water footprint minus shallow_water_areas as
# holes, a real physical block (a deep hull literally can't float in
# shallow water) rather than a speed penalty. See battle_unit.gd's
# hull_draught/_setup_navigation().
var deep_water_nav_map: RID
var _ground_nav_region: RID
var _water_nav_region: RID
var _amphibious_nav_region: RID
var _deep_water_nav_region: RID

# Multi-map architecture (this pass): the map itself - terrain layout,
# resources, start points - is now data (MapCatalog), not hardcoded here.
# map_id defaults to the original lake map so every pre-existing test/
# save that doesn't care about map selection keeps working unchanged.
# Read from the MatchConfig autoload if present (set by a real map-select
# screen before the scene change) - duck-typed via get_node_or_null so
# this has zero dependency on the autoload existing at all (every headless
# test that instantiates Skirmish.tscn directly, with no autoload
# registered, just falls back to the default map, same as before).
var map_id: String = MapCatalog.DEFAULT_MAP_ID
var current_map: Dictionary = {}

var player_faction: String = "industrialists"
var enemy_faction: String = "technocrats"

# Pre-match settings (MatchSetup.tscn, read the same defensive way map_id
# already is): a player/enemy faction override skips the old "derive from
# roster[0]'s own faction tag" heuristic entirely once explicitly chosen;
# selected_blueprint_paths lets the player choose exactly which saved
# designs enter their roster instead of the automatic "top 8 newest";
# ai_difficulty is read by enemy_ai.gd's own setup(); starting_metal/
# starting_crystal override the flat 450/150 default below if set.
var _mc_player_faction: String = ""
var _mc_enemy_faction: String = ""
var _mc_blueprint_paths: Array = []
var ai_difficulty: String = "normal"

var player_hq: StaticBody3D = null
var enemy_hq: StaticBody3D = null
var game_over: bool = false

# Roster: array of {blueprint: Dictionary, name, cost_metal, cost_crystal, is_defense}
var roster: Array = []
var enemy_roster: Array = []

# Selection state
var selected: Array = []
var drag_select_start: Vector2 = Vector2.ZERO
var is_drag_selecting: bool = false

# Building placement state
var placing: Dictionary = {} # {kind: "refinery"/"factory"/"defense", blueprint (opt), cost_metal, cost_crystal}
var placement_ghost: MeshInstance3D = null

# UI
var resource_label: Label
var status_label: Label
var build_bar: HBoxContainer
var selection_rect: Panel

@onready var camera: Camera3D = $Camera3D

func _ready():
	bp_manager = BlueprintManagerScript.new()
	bp_manager.name = "BlueprintManager"
	add_child(bp_manager)

	var match_config = get_node_or_null("/root/MatchConfig")
	if match_config and "selected_map_id" in match_config and match_config.selected_map_id != "":
		map_id = match_config.selected_map_id
	current_map = MapCatalog.get_map(map_id)

	if match_config:
		if "player_faction" in match_config and match_config.player_faction != "":
			_mc_player_faction = match_config.player_faction
		if "enemy_faction" in match_config and match_config.enemy_faction != "":
			_mc_enemy_faction = match_config.enemy_faction
		if "selected_blueprint_paths" in match_config and not match_config.selected_blueprint_paths.is_empty():
			_mc_blueprint_paths = match_config.selected_blueprint_paths
		if "ai_difficulty" in match_config and match_config.ai_difficulty != "":
			ai_difficulty = match_config.ai_difficulty
		if "starting_metal" in match_config and match_config.starting_metal >= 0:
			economy[PLAYER_TEAM].metal = match_config.starting_metal
			economy[ENEMY_TEAM].metal = match_config.starting_metal
		if "starting_crystal" in match_config and match_config.starting_crystal >= 0:
			economy[PLAYER_TEAM].crystal = match_config.starting_crystal
			economy[ENEMY_TEAM].crystal = match_config.starting_crystal

	_setup_navigation()
	_load_rosters()
	_spawn_resource_nodes()
	_spawn_bases()
	_build_ui()

	var ai = Node.new()
	ai.set_script(EnemyAIScript)
	ai.name = "EnemyAI"
	add_child(ai)
	ai.setup(self)

	# Expansionist passive: HQ trickle
	var trickle = Timer.new()
	trickle.wait_time = 4.0
	trickle.autostart = true
	add_child(trickle)
	trickle.timeout.connect(_on_trickle)

	var energy_timer = Timer.new()
	energy_timer.wait_time = ENERGY_TICK_INTERVAL
	energy_timer.autostart = true
	add_child(energy_timer)
	energy_timer.timeout.connect(_recalc_energy_economy)
	_recalc_energy_economy() # populate before the first tick so the HUD isn't blank

	var fog_timer = Timer.new()
	fog_timer.wait_time = FOG_TICK_INTERVAL
	fog_timer.autostart = true
	add_child(fog_timer)
	fog_timer.timeout.connect(_recalc_fog_of_war)
	_recalc_fog_of_war() # populate before the first tick so enemies aren't briefly visible at match start

func _on_trickle():
	if game_over: return
	if is_instance_valid(player_hq) and not player_hq.is_dead:
		add_resources(PLAYER_TEAM, FactionCatalog.get_passive(player_faction, "hq_trickle_metal", 0), FactionCatalog.get_passive(player_faction, "hq_trickle_crystal", 0))
	if is_instance_valid(enemy_hq) and not enemy_hq.is_dead:
		add_resources(ENEMY_TEAM, FactionCatalog.get_passive(enemy_faction, "hq_trickle_metal", 0), FactionCatalog.get_passive(enemy_faction, "hq_trickle_crystal", 0))

# Energy resource team-level economy (ENERGY_AND_BALANCE_SPEC.md #1). A
# static building is any prefab (hq/refinery/factory are always static) or
# a "defense" building on a foundation hull - each drains a flat upkeep
# just for existing, UNLESS the team's faction is Expansionists (their
# static buildings are entirely self-powered, per Factions_and_Buildings.md).
func _recalc_energy_economy():
	if game_over: return
	for team in [PLAYER_TEAM, ENEMY_TEAM]:
		var capacity = 0.0
		var hq = player_hq if team == PLAYER_TEAM else enemy_hq
		if is_instance_valid(hq) and not hq.is_dead:
			capacity += ENERGY_HQ_BASELINE_CAPACITY
		for u in get_team_units(team):
			for m in u.get_active_modules():
				if m.has_meta("module_data") and m.get_meta("module_data").category == "generator":
					capacity += m.get_meta("module_data").get_energy_capacity()
		var faction = player_faction if team == PLAYER_TEAM else enemy_faction
		var upkeep = 0.0
		for b in get_tree().get_nodes_in_group("buildings"):
			if not is_instance_valid(b) or b.is_dead or b.team != team: continue
			# A building's own generators always contribute to capacity,
			# independent of whether it also owes upkeep - Expansionists'
			# perk is "our static buildings don't drain," not "our
			# generators don't count."
			for m in b.get_active_modules():
				if m.has_meta("module_data") and m.get_meta("module_data").category == "generator":
					capacity += m.get_meta("module_data").get_energy_capacity()
			var is_static_building = b.kind in ["hq", "refinery", "factory"] or (b.kind == "defense" and is_instance_valid(b.defense_hull) and ModuleCatalog.is_foundation(b.defense_hull.get_meta("type_id", "pillbox_foundation")))
			if not is_static_building: continue
			if FactionCatalog.get_passive(faction, "energy_upkeep_exempt", false): continue
			upkeep += ENERGY_UPKEEP_PER_STATIC_BUILDING
		capacity *= FactionCatalog.get_passive(faction, "energy_capacity_mult", 1.0)
		energy_pool[team].capacity = capacity
		energy_pool[team].energy = clamp(capacity - upkeep, 0.0, max(capacity, 1.0))
		energy_pool[team].deficit = (capacity - upkeep) < 0.0
	_update_resource_ui()

func is_energy_deficit(team: int) -> bool:
	return energy_pool[team].deficit

# Fog-of-war: deliberately ONE-DIRECTIONAL (only ever toggles ENEMY
# constructs' visibility, never the player's own). This is a single shared
# 3D scene, not per-client rendering - if this also hid player units
# whenever they left an ENEMY unit's vision, they'd vanish from the
# player's own screen too, which is never what "fog of war" means. The
# enemy AI keeps its existing omniscient targeting (a deliberate scope cut,
# see DECISIONS_NEEDED.md) - only the player's own experience (what
# renders, what the player's own weapons can target) is fog-gated.
# Elevation vision bonus (multi-map pass): a ground construct standing on
# an elevation zone sees further, scaling with how high it's actually
# standing (terrain_height_at(), the same single source of truth
# battle_unit.gd uses to snap Y) - a real, if modest, reward for holding
# high ground, not just a cosmetic hill. Capped so a very tall future map
# doesn't make vision meaningless, and skipped for flying units (already
# airborne regardless of what's on the ground below - this is about
# holding terrain, not altitude).
const ELEVATION_VISION_BONUS_PER_UNIT: float = 0.02
const ELEVATION_VISION_CAP: float = 12.0

# Map variety batch: real sightline-blocking, the mechanical payoff of the
# urban map's building obstacles (and, as a free side effect, every
# existing rock-cluster obstacle too - both are StaticBody3D on collision
# layer 1, same layer auto_weapon.gd's own LOS raycast already checks for
# weapon fire, so this reuses that exact convention rather than inventing a
# separate "is this a sightline blocker" flag). A fixed eye-height offset
# (not each construct's real height) is a deliberate approximation, same
# spirit as auto_weapon.gd's own "+0.5" target-center offset - good enough
# for "does a building genuinely hide what's behind it," not meant to model
# a crouching soldier peeking over a windowsill.
const VISION_EYE_HEIGHT: float = 1.5

func _has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	var space_state = get_world_3d().direct_space_state
	var ray_start = from_pos + Vector3(0, VISION_EYE_HEIGHT, 0)
	var ray_end = to_pos + Vector3(0, VISION_EYE_HEIGHT, 0)
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1 # Ground/obstacle layer only - never blocked by other units (layer 4)
	var result = space_state.intersect_ray(query)
	return result.is_empty()

func _recalc_fog_of_war():
	if game_over: return
	var player_constructs = get_team_units(PLAYER_TEAM) + get_team_buildings(PLAYER_TEAM)
	var enemy_constructs = get_team_units(ENEMY_TEAM) + get_team_buildings(ENEMY_TEAM)
	for c in enemy_constructs:
		if not is_instance_valid(c) or not c.has_method("set_fog_visible"): continue
		var seen = false
		var c_flying = "is_flying" in c and c.is_flying
		for o in player_constructs:
			if not is_instance_valid(o): continue
			var vision = o.vision_range if "vision_range" in o else 0.0
			var o_flying = "is_flying" in o and o.is_flying
			if not o_flying:
				var elevation = terrain_height_at(o.global_position)
				vision *= 1.0 + min(elevation, ELEVATION_VISION_CAP) * ELEVATION_VISION_BONUS_PER_UNIT
			if c.global_position.distance_to(o.global_position) <= vision:
				# Flying viewers/targets skip the terrain-obstacle raycast
				# entirely - already airborne regardless of what's on the
				# ground below, same reasoning the elevation bonus above
				# already uses for flying viewers.
				if o_flying or c_flying or _has_line_of_sight(o.global_position, c.global_position):
					seen = true
					break
		c.set_fog_visible(seen)

# --- Rosters ---

func _load_rosters():
	# Player: either the exact saved designs the pre-match screen selected
	# (_mc_blueprint_paths), or the old automatic heuristic (newest 8 saved
	# designs) if nothing was explicitly chosen. Bundled defaults always
	# fill the remaining gaps either way, same as before.
	if not _mc_blueprint_paths.is_empty():
		for path in _mc_blueprint_paths:
			var data = bp_manager.load_blueprint(path)
			if not data.is_empty():
				roster.append(_make_roster_entry(data))
	else:
		var entries = bp_manager.list_blueprints()
		for e in entries.slice(0, 8): # newest saved designs first, leave room for defaults
			var data = bp_manager.load_blueprint(e.path)
			if not data.is_empty():
				roster.append(_make_roster_entry(data))
	for path in _list_json_files("res://data/loadout"):
		var data = bp_manager.load_blueprint(path)
		if not data.is_empty():
			roster.append(_make_roster_entry(data))
	roster = roster.slice(0, 12) # Loadout limit

	# A skirmish without a harvester design is unwinnable - guarantee one
	if _find_harvester_blueprint(roster).is_empty():
		var trucker = bp_manager.load_blueprint("res://data/loadout/ore_trucker.json")
		if not trucker.is_empty():
			roster.append(_make_roster_entry(trucker))

	if _mc_player_faction != "":
		player_faction = _mc_player_faction
	elif not roster.is_empty():
		player_faction = roster[0].blueprint.get("faction", "industrialists")

	for path in _list_json_files("res://data/enemy"):
		var data = bp_manager.load_blueprint(path)
		if not data.is_empty():
			enemy_roster.append(_make_roster_entry(data))
	if _mc_enemy_faction != "":
		enemy_faction = _mc_enemy_faction
	elif not enemy_roster.is_empty():
		enemy_faction = enemy_roster[0].blueprint.get("faction", "technocrats")

	# Scavengers' "-10% metal cost on everything built" - a TEAM-level
	# passive (the match's chosen faction, not each individual blueprint's
	# own faction tag), applied once here so every consumer of cost_metal
	# (build-bar button labels, can_afford/spend) sees the same discounted
	# number - baking it into the roster entry rather than discounting only
	# at spend-time, which would make the displayed cost lie.
	_apply_faction_cost_discount(roster, player_faction)
	_apply_faction_cost_discount(enemy_roster, enemy_faction)

func _apply_faction_cost_discount(entries: Array, faction: String):
	var mult = FactionCatalog.get_passive(faction, "metal_cost_mult", 1.0)
	if mult == 1.0: return
	for e in entries:
		e.cost_metal = int(e.cost_metal * mult)

func _make_roster_entry(data: Dictionary) -> Dictionary:
	var cost = blueprint_cost(data)
	return {
		"blueprint": data,
		"name": data.get("name", "Untitled"),
		"cost_metal": cost.x,
		"cost_crystal": cost.y,
		"is_defense": ModuleCatalog.is_foundation(data.get("hull_type", "medium_hull")),
	}

func _list_json_files(dir_path: String) -> Array:
	var results = []
	var dir = DirAccess.open(dir_path)
	if not dir: return results
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".json")):
			results.append(dir_path + "/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	results.sort()
	return results

func blueprint_cost(data: Dictionary) -> Vector2i:
	var hull_type = data.get("hull_type", "medium_hull")
	var hull_data = ModuleCatalog.get_module_data(hull_type)
	var m = int(hull_data.metal)
	var c = int(hull_data.crystal)
	for mod in data.get("modules", []):
		var stats = mod.get("stats", {})
		if stats.has("cost_metal"):
			m += int(stats.cost_metal)
			c += int(stats.get("cost_crystal", 0))
		else:
			var cat = ModuleCatalog.get_module_data(mod.get("type_id", ""))
			m += int(cat.metal)
			c += int(cat.crystal)
	return Vector2i(m, c)

func build_time_for_cost(cost: Vector2i) -> float:
	return clamp((cost.x + cost.y * 2) * 0.05, 3.0, 40.0)

# --- Economy ---

func can_afford(team: int, metal: int, crystal: int) -> bool:
	return economy[team].metal >= metal and economy[team].crystal >= crystal

func spend(team: int, metal: int, crystal: int) -> bool:
	if not can_afford(team, metal, crystal):
		return false
	economy[team].metal -= metal
	economy[team].crystal -= crystal
	_update_resource_ui()
	return true

func add_resources(team: int, metal: int, crystal: int):
	economy[team].metal += metal
	economy[team].crystal += crystal
	_update_resource_ui()

func _on_resources_delivered(team: int, metal: int, crystal: int):
	add_resources(team, metal, crystal)

# --- Map setup ---

# Terrain is now data (MapCatalog) + a shared builder (TerrainBuilder),
# not hardcoded per-scene - see terrain_builder.gd's own header comment
# for the navmesh technique (multi-hole ground grid + plateau/ramp bridge
# geometry). This function's job is just: bake the navmeshes, resize/tint
# the flat Ground node to match the map, and spawn the decorative terrain
# (water/obstacles/elevation).
func _setup_navigation():
	var nav = TerrainBuilder.build_navmeshes(current_map)
	ground_nav_map = nav.ground_map
	water_nav_map = nav.water_map
	amphibious_nav_map = nav.amphibious_map
	deep_water_nav_map = nav.deep_water_map
	_ground_nav_region = nav.ground_region
	_water_nav_region = nav.water_region
	_amphibious_nav_region = nav.amphibious_region
	_deep_water_nav_region = nav.deep_water_region

	var half: float = current_map.get("map_half_extents", 80.0)
	var ground = get_node_or_null("Ground")
	if ground:
		var size = Vector3(half * 2.0, 1.0, half * 2.0)
		# Duplicate before mutating - Ground's BoxMesh/BoxShape3D are scene
		# sub-resources that could otherwise be shared across every
		# Skirmish instance (same footgun as the hull nose-taper work,
		# which duplicates its mesh for the same reason), which would leak
		# one map's size/color into another's, particularly noticeable
		# across the many Skirmish instantiate/free cycles in the test suite.
		var mesh_inst: MeshInstance3D = ground.get_node_or_null("MeshInstance3D")
		if mesh_inst and mesh_inst.mesh is BoxMesh:
			var box: BoxMesh = mesh_inst.mesh.duplicate()
			box.size = size
			mesh_inst.mesh = box
			var tinted = StandardMaterial3D.new()
			tinted.albedo_color = current_map.get("ground_color", Color(0.2, 0.26, 0.21))
			mesh_inst.material_override = tinted
		var col_shape: CollisionShape3D = ground.get_node_or_null("CollisionShape3D")
		if col_shape and col_shape.shape is BoxShape3D:
			var box_shape: BoxShape3D = col_shape.shape.duplicate()
			box_shape.size = size
			col_shape.shape = box_shape

	TerrainBuilder.spawn_visuals(current_map, self)

# Raw NavigationServer3D RIDs (map_create()/region_create()) aren't owned by
# the scene tree the way child nodes are - they leak unless explicitly
# freed. Found via a real RID-leak warning at engine exit during the
# headless test suite (which instantiates+frees a fresh Skirmish scene per
# test, many times per run).
func _exit_tree():
	if _ground_nav_region.is_valid():
		NavigationServer3D.free_rid(_ground_nav_region)
	if _water_nav_region.is_valid():
		NavigationServer3D.free_rid(_water_nav_region)
	if _amphibious_nav_region.is_valid():
		NavigationServer3D.free_rid(_amphibious_nav_region)
	if _deep_water_nav_region.is_valid():
		NavigationServer3D.free_rid(_deep_water_nav_region)
	if ground_nav_map.is_valid():
		NavigationServer3D.free_rid(ground_nav_map)
	if water_nav_map.is_valid():
		NavigationServer3D.free_rid(water_nav_map)
	if amphibious_nav_map.is_valid():
		NavigationServer3D.free_rid(amphibious_nav_map)
	if deep_water_nav_map.is_valid():
		NavigationServer3D.free_rid(deep_water_nav_map)

# Duck-typed lookup, same pattern as get_ground_nav_map()/get_water_nav_map()
# - battle_unit.gd/building.gd call this every tick (units) or once at
# spawn (buildings) to snap their Y onto elevated terrain. The single
# source of truth for elevation Y lives in terrain_builder.gd; this is
# just the map-aware wrapper around it.
func terrain_height_at(pos: Vector3) -> float:
	return TerrainBuilder.terrain_height_at(current_map, pos)

# Duck-typed lookup, same pattern as terrain_height_at() - battle_unit.gd
# calls this every physics tick to look up its current surface-terrain
# speed multiplier (marsh/rocky/snow_mud/sand).
func get_surface_type_at(pos: Vector3) -> String:
	return TerrainBuilder.get_surface_type_at(current_map, pos)

func _spawn_resource_nodes():
	for s in current_map.get("resource_nodes", []):
		var node = StaticBody3D.new()
		node.set_script(ResourceNodeScript)
		add_child(node)
		node.global_position = Vector3(s.position.x, terrain_height_at(s.position), s.position.z)
		node.setup(s.type, s.amount)

func _spawn_bases():
	var p_start = current_map.player_start
	var e_start = current_map.enemy_start

	player_hq = _spawn_prefab("hq", PLAYER_TEAM, p_start.hq, player_faction)
	_spawn_prefab("factory", PLAYER_TEAM, p_start.factory, player_faction)
	_spawn_prefab("refinery", PLAYER_TEAM, p_start.refinery, player_faction)

	enemy_hq = _spawn_prefab("hq", ENEMY_TEAM, e_start.hq, enemy_faction)
	_spawn_prefab("factory", ENEMY_TEAM, e_start.factory, enemy_faction)
	_spawn_prefab("refinery", ENEMY_TEAM, e_start.refinery, enemy_faction)

	player_hq.died.connect(_on_hq_died)
	enemy_hq.died.connect(_on_hq_died)

	# Starting harvesters
	var harv_bp = _find_harvester_blueprint(roster)
	if not harv_bp.is_empty():
		spawn_unit(harv_bp, PLAYER_TEAM, p_start.harvester)
	var e_harv = _find_harvester_blueprint(enemy_roster)
	if not e_harv.is_empty():
		spawn_unit(e_harv, ENEMY_TEAM, e_start.harvester)

func _find_harvester_blueprint(from_roster: Array) -> Dictionary:
	for entry in from_roster:
		for mod in entry.blueprint.get("modules", []):
			if mod.get("type_id", "") == "resource_harvester":
				return entry.blueprint
	return {}

func _spawn_prefab(kind: String, team: int, pos: Vector3, faction: String) -> StaticBody3D:
	var b = StaticBody3D.new()
	b.set_script(BuildingScript)
	add_child(b)
	b.global_position = Vector3(pos.x, terrain_height_at(pos), pos.z)
	b.setup_prefab(kind, team, faction)
	b.bp_manager = bp_manager
	return b

func spawn_unit(blueprint_data: Dictionary, team: int, pos: Vector3) -> Node:
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	add_child(unit)
	unit.global_position = Vector3(pos.x, terrain_height_at(pos) + pos.y, pos.z)
	unit.setup(blueprint_data, team, bp_manager)
	unit.resources_delivered.connect(_on_resources_delivered)
	return unit

func spawn_defense(blueprint_data: Dictionary, team: int, pos: Vector3) -> StaticBody3D:
	var b = StaticBody3D.new()
	b.set_script(BuildingScript)
	add_child(b)
	b.global_position = Vector3(pos.x, terrain_height_at(pos), pos.z)
	b.setup_defense(blueprint_data, team, bp_manager)
	return b

func get_team_factory(team: int) -> Node:
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.is_dead and b.team == team and b.kind == "factory":
			return b
	return null

func get_team_units(team: int, combat_only: bool = false) -> Array:
	var list = []
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead and u.team == team:
			if combat_only and u.is_harvester: continue
			list.append(u)
	return list

func get_team_buildings(team: int) -> Array:
	var list = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.is_dead and b.team == team:
			list.append(b)
	return list

# Duck-typed lookup for battle_unit.gd's _setup_navigation() - existence of
# these two methods is what tells a unit "I'm in a real match with real
# navigation maps," vs. every synthetic test constructing a battle_unit
# standalone, which falls back to plain direct-line steering unchanged.
func get_ground_nav_map() -> RID:
	return ground_nav_map

func get_water_nav_map() -> RID:
	return water_nav_map

# Same duck-typed pattern - only screw_drive (amphibious) units call this
# (see battle_unit.gd's is_amphibious branch in _setup_navigation()).
func get_amphibious_nav_map() -> RID:
	return amphibious_nav_map

# Same duck-typed pattern - only deep-draught naval units call this (see
# battle_unit.gd's hull_draught branch in _setup_navigation()).
func get_deep_water_nav_map() -> RID:
	return deep_water_nav_map

# --- UI ---

func _build_ui():
	var ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	resource_label = Label.new()
	resource_label.position = Vector2(20, 14)
	resource_label.add_theme_font_size_override("font_size", 22)
	ui.add_child(resource_label)

	status_label = Label.new()
	status_label.position = Vector2(20, 46)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.modulate = Color(0.8, 0.85, 0.9)
	status_label.text = "Left-click/drag: select | Right-click: move / attack / harvest | Destroy the enemy HQ!"
	ui.add_child(status_label)

	var menu_btn = Button.new()
	menu_btn.text = "Menu"
	menu_btn.position = Vector2(1180, 14)
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	ui.add_child(menu_btn)

	# Bottom build bar
	var bar_bg = PanelContainer.new()
	bar_bg.anchor_top = 1.0
	bar_bg.anchor_bottom = 1.0
	bar_bg.anchor_left = 0.0
	bar_bg.anchor_right = 1.0
	bar_bg.offset_top = -96
	ui.add_child(bar_bg)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 92)
	bar_bg.add_child(scroll)
	build_bar = HBoxContainer.new()
	build_bar.add_theme_constant_override("separation", 8)
	scroll.add_child(build_bar)

	_add_build_button("🏭 Factory\n200M 50C", Color(0.72, 0.55, 0.42), func():
		_begin_placement({"kind": "factory", "cost_metal": 200, "cost_crystal": 50}))
	_add_build_button("⛽ Refinery\n150M", Color(0.55, 0.62, 0.75), func():
		_begin_placement({"kind": "refinery", "cost_metal": 150, "cost_crystal": 0}))

	for entry in roster:
		var e = entry
		var label_text = "%s%s\n%dM %dC" % ["🛡 " if e.is_defense else "", e.name, e.cost_metal, e.cost_crystal]
		var color = Color(0.4, 0.5, 0.4) if e.is_defense else Color(0.35, 0.42, 0.55)
		_add_build_button(label_text, color, func():
			if e.is_defense:
				_begin_placement({"kind": "defense", "blueprint": e.blueprint, "cost_metal": e.cost_metal, "cost_crystal": e.cost_crystal})
			else:
				_queue_player_unit(e))

	# Drag-select rectangle overlay
	selection_rect = Panel.new()
	selection_rect.visible = false
	selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.8, 0.4, 0.15)
	style.border_color = Color(0.3, 1.0, 0.4, 0.8)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	selection_rect.add_theme_stylebox_override("panel", style)
	ui.add_child(selection_rect)

	_update_resource_ui()

func _add_build_button(text: String, color: Color, callback: Callable):
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 80)
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover)
	btn.pressed.connect(callback)
	build_bar.add_child(btn)

func _update_resource_ui():
	if resource_label:
		var e = energy_pool[PLAYER_TEAM]
		var energy_str = "⚡ Energy: %d/%d%s" % [int(e.energy), int(e.capacity), " (DEFICIT: builds slower!)" if e.deficit else ""]
		resource_label.text = "💰 Metal: %d   💎 Crystal: %d   %s" % [economy[PLAYER_TEAM].metal, economy[PLAYER_TEAM].crystal, energy_str]

func _flash_status(msg: String):
	if status_label:
		status_label.text = msg
		status_label.modulate = Color(1.0, 0.8, 0.3)
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(status_label):
				status_label.modulate = Color(0.8, 0.85, 0.9)
		)

func _queue_player_unit(entry: Dictionary):
	if game_over: return
	var factory = get_team_factory(PLAYER_TEAM)
	if not factory:
		_flash_status("No factory! Build one first.")
		return
	var legality = ModuleCatalog.validate_build_legality(entry.blueprint)
	if not legality.valid:
		_flash_status("%s can't be built: %s" % [entry.name, legality.reason])
		return
	if not spend(PLAYER_TEAM, entry.cost_metal, entry.cost_crystal):
		_flash_status("Not enough resources for %s!" % entry.name)
		return
	var build_time = build_time_for_cost(Vector2i(entry.cost_metal, entry.cost_crystal))
	build_time *= FactionCatalog.get_passive(player_faction, "build_time_mult", 1.0)
	if is_energy_deficit(PLAYER_TEAM):
		build_time *= 1.5
	factory.queue_unit(entry.blueprint, build_time)
	_flash_status("Building %s... (low power, slower build)" % entry.name if is_energy_deficit(PLAYER_TEAM) else "Building %s..." % entry.name)

# --- Building placement ---

func _begin_placement(info: Dictionary):
	if game_over: return
	if info.kind == "defense":
		var legality = ModuleCatalog.validate_build_legality(info.blueprint)
		if not legality.valid:
			_flash_status("Can't build this: %s" % legality.reason)
			return
	if not can_afford(PLAYER_TEAM, info.cost_metal, info.cost_crystal):
		_flash_status("Not enough resources!")
		return
	_cancel_placement()
	placing = info
	placement_ghost = MeshInstance3D.new()
	var box = BoxMesh.new()
	if info.kind == "defense":
		var hull_data = ModuleCatalog.get_module_data(info.blueprint.get("hull_type", "pillbox_foundation"))
		box.size = hull_data.size
	else:
		box.size = BuildingScript.PREFAB_STATS[info.kind].size
	placement_ghost.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.4, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	placement_ghost.material_override = mat
	add_child(placement_ghost)

func _cancel_placement():
	placing = {}
	if is_instance_valid(placement_ghost):
		placement_ghost.queue_free()
	placement_ghost = null

func _try_place_building(pos: Vector3):
	if placing.is_empty(): return
	# Terrain check first (water/obstacles/ramp slopes are never buildable,
	# regardless of proximity to a friendly building) - a real check added
	# alongside multi-map terrain; previously nothing stopped a building
	# from being placed inside the lake since there was no terrain data to
	# check against at all.
	if TerrainBuilder.is_position_blocked(current_map, pos):
		_flash_status("Can't build on water or terrain obstacles!")
		return
	# Must be near your base (within 28m of any friendly building) and
	# clear of the enemy's (their base being reachable at all doesn't mean
	# it's "yours" to build next to).
	var near_base = false
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.is_dead: continue
		if b.team == PLAYER_TEAM and b.global_position.distance_to(pos) < 28.0:
			near_base = true
		elif b.team != PLAYER_TEAM and b.global_position.distance_to(pos) < 20.0:
			_flash_status("Too close to enemy territory!")
			return
	if not near_base:
		_flash_status("Too far from your base!")
		return
	if not spend(PLAYER_TEAM, placing.cost_metal, placing.cost_crystal):
		_flash_status("Not enough resources!")
		_cancel_placement()
		return
	if placing.kind == "defense":
		spawn_defense(placing.blueprint, PLAYER_TEAM, pos)
	else:
		var b = _spawn_prefab(placing.kind, PLAYER_TEAM, pos, player_faction)
		b.bp_manager = bp_manager
	_cancel_placement()

# --- Input: selection & orders ---

func _unhandled_input(event):
	if game_over: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placement()
		_set_selection([])
		return

	if event is InputEventMouseMotion:
		if not placing.is_empty() and is_instance_valid(placement_ghost):
			var hit = _raycast_ground(event.position)
			if hit != null:
				var ground_y = terrain_height_at(hit)
				placement_ghost.global_position = Vector3(hit.x, ground_y + placement_ghost.mesh.size.y / 2.0, hit.z)
		if is_drag_selecting:
			_update_selection_rect(event.position)
		return

	if not (event is InputEventMouseButton): return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not placing.is_empty():
				var hit = _raycast_ground(event.position)
				if hit != null:
					_try_place_building(hit)
				return
			drag_select_start = event.position
			is_drag_selecting = true
			selection_rect.visible = false
		else:
			if is_drag_selecting:
				is_drag_selecting = false
				selection_rect.visible = false
				var drag_dist = event.position.distance_to(drag_select_start)
				if drag_dist > 10:
					_select_in_rect(Rect2(drag_select_start, event.position - drag_select_start).abs())
				else:
					_select_at_point(event.position)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not placing.is_empty():
			_cancel_placement()
			return
		_issue_order(event.position)

func _update_selection_rect(mouse_pos: Vector2):
	var rect = Rect2(drag_select_start, mouse_pos - drag_select_start).abs()
	if rect.size.length() > 10:
		selection_rect.visible = true
		selection_rect.position = rect.position
		selection_rect.size = rect.size

func _set_selection(new_selection: Array):
	for s in selected:
		if is_instance_valid(s) and s.has_method("set_selected"):
			s.set_selected(false)
	selected = new_selection
	for s in selected:
		if is_instance_valid(s) and s.has_method("set_selected"):
			s.set_selected(true)

func _select_at_point(screen_pos: Vector2):
	var result = _raycast_screen(screen_pos, 4 + 8)
	if result and result.collider:
		var node = result.collider
		if node.is_in_group("units") or node.is_in_group("buildings"):
			if node.get("team") == PLAYER_TEAM:
				_set_selection([node])
				return
	_set_selection([])

func _select_in_rect(rect: Rect2):
	var picked = []
	for u in get_team_units(PLAYER_TEAM):
		var screen = camera.unproject_position(u.global_position)
		if rect.has_point(screen):
			picked.append(u)
	_set_selection(picked)

func _issue_order(screen_pos: Vector2):
	if selected.is_empty(): return
	# Check click on enemy / resource node first
	var result = _raycast_screen(screen_pos, 4 + 8 + 16)
	if result and result.collider:
		var node = result.collider
		if node.is_in_group("resource_nodes"):
			for s in selected:
				if is_instance_valid(s) and "is_harvester" in s and s.is_harvester:
					s.order_harvest(node)
			_spawn_order_marker(node.global_position, Color.GOLD)
			return
		if (node.is_in_group("units") or node.is_in_group("buildings")) and node.get("team") != PLAYER_TEAM:
			for s in selected:
				if is_instance_valid(s) and s.has_method("order_attack"):
					s.order_attack(node)
			_spawn_order_marker(node.global_position, Color.RED)
			return
	# Otherwise: move order on ground
	var ground = _raycast_ground(screen_pos)
	if ground != null:
		var i = 0
		for s in selected:
			if is_instance_valid(s) and s.has_method("order_move"):
				# Loose spread formation
				var offset = Vector3((i % 3 - 1) * 3.0, 0, int(i / 3.0) * 3.0)
				s.order_move(ground + offset)
				i += 1
		_spawn_order_marker(ground, Color.GREEN)

func _spawn_order_marker(pos: Vector3, color: Color):
	var marker = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	marker.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	marker.material_override = mat
	add_child(marker)
	marker.global_position = pos + Vector3(0, 0.3, 0)
	var tween = create_tween()
	tween.tween_property(marker, "scale", Vector3.ZERO, 0.5)
	tween.finished.connect(func(): marker.queue_free())

func _raycast_screen(screen_pos: Vector2, mask: int):
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_end = ray_origin + camera.project_ray_normal(screen_pos) * 1000.0
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = mask
	return get_world_3d().direct_space_state.intersect_ray(query)

func _raycast_ground(screen_pos: Vector2):
	var result = _raycast_screen(screen_pos, 1)
	if result:
		return result.position
	return null

# --- Win / Lose ---

func _on_hq_died(building):
	if game_over: return
	game_over = true
	var victory = (building.team == ENEMY_TEAM)
	var ui = get_node_or_null("UI")
	if not ui: return

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(vbox)

	var title = Label.new()
	title.text = "🏆 VICTORY!" if victory else "💀 DEFEAT"
	title.add_theme_font_size_override("font_size", 64)
	title.modulate = Color.GOLD if victory else Color.RED
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "The enemy HQ has been destroyed." if victory else "Your HQ has been destroyed."
	sub.add_theme_font_size_override("font_size", 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var btn = Button.new()
	btn.text = "Return to Menu"
	btn.custom_minimum_size = Vector2(220, 50)
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	vbox.add_child(btn)
