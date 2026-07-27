extends Node3D
# C&C-style Skirmish mode. The player's saved blueprints (plus bundled defaults)
# form the buildable roster. Destroy the enemy HQ to win; lose yours and it's over.

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const BattleUnitScript = preload("res://scripts/battle_unit.gd")
const BuildingScript = preload("res://scripts/building.gd")
const ResourceNodeScript = preload("res://scripts/resource_node.gd")
const EnemyAIScript = preload("res://scripts/enemy_ai.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")
const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const ProductionQueueScript = preload("res://scripts/production_queue.gd")

# RTS_CORE_ROADMAP.md A1: the one production authority, shared by the
# player's build bar and enemy_ai.gd - see production_queue.gd's own header
# for the model (one queue per team+tier, not per building). Typed as
# RefCounted (its actual base), not a class_name - matching this codebase's
# existing convention (e.g. building.gd's `bp_manager: Node`) rather than
# relying on the global class cache, which a bare `--script` headless run
# doesn't reliably have populated.
var production: RefCounted = null

const PLAYER_TEAM = 0
const ENEMY_TEAM = 1

# RTS_CORE_ROADMAP.md B2: N-player slot metadata - {team, faction, is_local,
# is_bot, allies: Array[int], hq}. Populated in _ready() (2 slots by
# default, matching PLAYER_TEAM/ENEMY_TEAM exactly - runtime still only
# ever SPAWNS 2 by default, since map data only authors 2 start points;
# real N-player spawn assignment is B10's job). `hq` is the actual
# source of truth behind the player_hq/enemy_hq thin properties below.
# LOCAL_SLOT is a slot ARRAY INDEX (not a team id) - slots[LOCAL_SLOT] is
# always "this client's own side," so HUD/debug toggles stay honest even
# if a future session reorders slots.
const LOCAL_SLOT: int = 0
var slots: Array = []

var bp_manager: Node
# Kept keyed by TEAM (not slot index) - already the stable, team-
# parameterized seam A1's own comment called out (can_afford/spend/
# add_resources/is_energy_deficit). B2 just stops hardcoding it as a
# 2-entry literal: _rebuild_economy_from_slots() derives an entry per
# slot, so N slots means N independent economies for free.
var economy: Dictionary = {}
# Energy resource (ENERGY_AND_BALANCE_SPEC.md #1) - deliberately NOT a
# spendable currency like metal/crystal (can_afford/spend/blueprint_cost
# keep their existing 2-resource signatures, see the spec for why). Instead
# a live meter, recomputed every ENERGY_TICK_INTERVAL: "energy" is the
# team's current net generation (capacity minus static-building upkeep,
# floored at 0 - it's a gauge, not an accumulating battery), "capacity" is
# the live sum of the team's BASE power sources only - the HQ baseline,
# power_plant buildings, and generator modules mounted on static
# buildings (defenses). This is deliberately a separate resource from any
# individual vehicle's own energy budget (battle_unit.gd's max_energy/
# current_energy, which powers only that vehicle's own energy-cost
# weapons) - Chris's explicit resolution of FABLE_REVIEW.md 1.6: base
# power is for the base (buildings/production), a vehicle that wants more
# of its own energy has to mount its own generator module, full stop. A
# mobile unit's generator module does NOT feed this team pool (see
# _recalc_energy_economy() below) - it used to, which was exactly the
# review's "put a fusion_generator on a tank so your factories build
# faster; lose the tank, lose the base's power" complaint.
var energy_pool: Dictionary = {}
const ENERGY_TICK_INTERVAL: float = 3.0
const GHOST_COLOR_VALID: Color = Color(0.3, 1.0, 0.4, 0.4)
const GHOST_COLOR_INVALID: Color = Color(1.0, 0.25, 0.2, 0.45)
const ENERGY_UPKEEP_PER_STATIC_BUILDING: float = 3.0
# The HQ has its own baseline power plant - without this, every match
# starts in automatic Energy deficit from frame one, applying the factory
# build-speed penalty before a player has had any chance to build a
# generator. Found via the visual regression pass (skirmish_hud capture
# showed "DEFICIT: builds slower!" at match start, before any real
# gameplay) - sized to roughly offset default starting upkeep so a team is
# breakeven-to-slightly-ahead by default, and generators become a genuine
# optional upgrade (more energy for energy weapons) rather than a
# mandatory tax just to avoid a permanent penalty.
# Re-tuned for the base-building batch: starting static buildings grew from
# 3 (hq/factory/refinery) to 5 (hq/refinery/light+medium+heavy manufactory,
# see _spawn_starting_manufactories()) - 5 * ENERGY_UPKEEP_PER_STATIC_BUILDING
# = 15.0, so this needed to rise from 10.0 to keep the same ~1.0 headroom
# margin, not just the old 3-building value.
const ENERGY_HQ_BASELINE_CAPACITY: float = 16.0
var energy_tick_timer: float = 0.0

# Fog-of-war (built this pass): real vision-radius system, no supporting
# infrastructure existed before this - Technocrats' "+15% sensor/radar
# vision" passive (Factions_and_Buildings.md) was unimplementable until
# now for exactly that reason. Faster tick than Energy's (units move
# continuously, so vision needs to feel responsive) but still a fixed
# interval, not per-frame - a few hundred ms of stale fog is imperceptible
# and this scan is O(player constructs x enemy constructs) every tick.
const FOG_TICK_INTERVAL: float = 0.3

# PERFORMANCE_PLAN.md P1c: auto_weapon.gd's _find_nearest_target() used to
# scan get_tree().get_nodes_in_group("damageable") - EVERY damageable
# construct in the match - for EVERY weapon reacquiring a target, an O(N)
# scan per weapon that becomes O(N^2) the moment many weapons lose their
# targets in the same tick (an alpha strike, a cluster dying together -
# exactly the "fine at 5-6 units, falls off a cliff past that" shape
# reported). This grid buckets every damageable construct by position on
# the same throttled cadence as fog, and get_nearby_damageable() below lets
# a weapon only scan the handful of cells within its own fire_range instead
# of the whole roster. Cell size is a rough middle ground across the actual
# fire_range spread in auto_weapon.gd (9-50) - small enough that short-range
# weapons don't over-scan, large enough that long-range weapons only touch
# a handful of cells, not hundreds.
const DAMAGEABLE_GRID_CELL_SIZE: float = 20.0
var _damageable_grid: Dictionary = {}

func _rebuild_damageable_grid():
	_damageable_grid.clear()
	for c in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(c):
			continue
		var cell = Vector2i(floori(c.global_position.x / DAMAGEABLE_GRID_CELL_SIZE), floori(c.global_position.z / DAMAGEABLE_GRID_CELL_SIZE))
		if not _damageable_grid.has(cell):
			_damageable_grid[cell] = []
		_damageable_grid[cell].append(c)

# Returns every "damageable" construct within `radius` of `pos` (a superset -
# callers still do their own precise distance check, same as they did
# against the old whole-roster scan; this only narrows which candidates get
# considered at all). Duck-typed entry point (auto_weapon.gd calls this via
# `current_scene.get_nearby_damageable(...)` if the method exists, falling
# back to the old full-roster scan otherwise) so test fixtures and the Test
# Range - neither of which has a real Skirmish - keep working unchanged.
func get_nearby_damageable(pos: Vector3, radius: float) -> Array:
	var result = []
	var min_cell = Vector2i(floori((pos.x - radius) / DAMAGEABLE_GRID_CELL_SIZE), floori((pos.z - radius) / DAMAGEABLE_GRID_CELL_SIZE))
	var max_cell = Vector2i(floori((pos.x + radius) / DAMAGEABLE_GRID_CELL_SIZE), floori((pos.z + radius) / DAMAGEABLE_GRID_CELL_SIZE))
	for cx in range(min_cell.x, max_cell.x + 1):
		for cz in range(min_cell.y, max_cell.y + 1):
			var cell = Vector2i(cx, cz)
			if _damageable_grid.has(cell):
				result.append_array(_damageable_grid[cell])
	return result

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

# RTS_CORE_ROADMAP.md C1: set true by any building placement/death, cleared
# and acted on once per physics tick in _physics_process() - see that
# function's own comment for why this is a one-frame debounce, not an
# immediate rebake.
var _nav_rebake_pending: bool = false

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

# RTS_CORE_ROADMAP.md B2: thin properties over slots[i].hq, kept so every
# existing `player_hq`/`enemy_hq` read/write site (including 113+
# pre-existing tests) compiles and behaves identically - the actual
# storage moved to the slots array.
var player_hq: StaticBody3D:
	get: return _get_slot(PLAYER_TEAM).get("hq")
	set(value): _get_slot(PLAYER_TEAM)["hq"] = value
var enemy_hq: StaticBody3D:
	get: return _get_slot(ENEMY_TEAM).get("hq")
	set(value): _get_slot(ENEMY_TEAM)["hq"] = value
var game_over: bool = false

# Roster: array of {blueprint: Dictionary, name, cost_metal, cost_crystal, is_defense}
var roster: Array = []
var enemy_roster: Array = []

# Selection state
var selected: Array = []
var drag_select_start: Vector2 = Vector2.ZERO
var is_drag_selecting: bool = false

# Control groups (VISUAL_AND_UX_POLISH_PLAN.md C1): Ctrl+1-9 assigns the
# current selection to a slot, 1-9 recalls it, matching both OpenRA and RA2
# convention. Keyed by the digit itself (1-9), never populated for 0.
# Recall filters dead/freed members at read time rather than eagerly
# pruning on death, since nothing needs to react to a group shrinking
# until the player actually presses that digit again.
var control_groups: Dictionary = {}
const CONTROL_GROUP_DOUBLE_TAP_MS: int = 400
var _last_group_recall_num: int = -1
var _last_group_recall_time_ms: int = 0

# Building placement state
var placing: Dictionary = {} # {kind: "refinery"/"light_manufactory"/"medium_manufactory"/"heavy_manufactory"/"defense", blueprint (opt), cost_metal, cost_crystal}
var placement_ghost: MeshInstance3D = null

# UI
var resource_label: Label
var status_label: Label
var intel_label: Label
var selection_rect: Panel
# RTS_CORE_ROADMAP.md E1: a real power bar (see _build_ui()'s own comment).
var power_bar_panel: PanelContainer
var power_bar: ProgressBar
var power_status_label: Label

# RTS_CORE_ROADMAP.md D2: tabbed build bar (Structures/Defenses/Units) +
# queue panel (3 tier strips: progress fill, READY/HOLD/timer text).
var build_tab_containers: Dictionary = {} # "structures"/"defenses"/"units" -> HBoxContainer
var build_tab_buttons: Dictionary = {}
var active_build_tab: String = "units"
var _tier_gated_buttons: Array = [] # [{button, tier}] - greyed out when that tier has no live manufactory
var queue_strips: Dictionary = {} # tier -> {bar: ProgressBar, status_label: Label, panel: Control}

@onready var camera: Camera3D = $Camera3D

# --- N-player slots (RTS_CORE_ROADMAP.md B2) ---

# Returns the slot Dictionary for a team (a real reference into `slots`,
# not a copy - mutating the result, e.g. `_get_slot(t)["hq"] = x`, writes
# straight through). Empty Dictionary if the team isn't slotted (shouldn't
# happen once _ready() has run; defensive because player_hq/enemy_hq's
# property getters call this before any slot is guaranteed to exist).
func _get_slot(team: int) -> Dictionary:
	for s in slots:
		if s.get("team") == team:
			return s
	return {}

# Appends a new slot and gives it an economy/energy_pool entry - the one
# supported way to grow past the default 2 slots today (there's no map
# data for a 3rd+ spawn point yet, so this is for tests / a future N-
# player setup flow to call directly, not something _spawn_bases() does
# on its own).
func add_slot(slot: Dictionary) -> void:
	slots.append(slot)
	_rebuild_economy_from_slots()

func _rebuild_economy_from_slots() -> void:
	for s in slots:
		if not economy.has(s.team):
			economy[s.team] = {"metal": 450, "crystal": 150}
		if not energy_pool.has(s.team):
			energy_pool[s.team] = {"energy": 0.0, "capacity": 0.0, "deficit": false}

func _local_team() -> int:
	if slots.size() > LOCAL_SLOT:
		return slots[LOCAL_SLOT].team
	return PLAYER_TEAM

func _all_teams() -> Array:
	var result: Array = []
	for s in slots:
		result.append(s.team)
	return result

# A team's alliance = itself + its own `allies` list. Not a full
# transitive closure (if A lists B and B lists C but A doesn't list C,
# A/C aren't linked) - authored alliances are expected to be symmetric,
# which is all B2's 2v1 scenario needs.
func _alliance_for_team(team: int) -> Array:
	var s = _get_slot(team)
	var result: Array = [team]
	for a in s.get("allies", []):
		if not a in result:
			result.append(a)
	return result

# True if team_b is in team_a's alliance (same team always counts). This
# is the one shared answer fog-of-war, the win condition, and the repair/
# auto-engage targeting fixes below all defer to - one source of truth for
# "is this hostile," not four separately-hardcoded team-equality checks.
func is_allied(team_a: int, team_b: int) -> bool:
	if team_a == team_b:
		return true
	return team_b in _alliance_for_team(team_a)

# One entry per still-alive alliance (an Array[int] of that alliance's
# member teams), used by _on_hq_died() to decide whether the match is
# actually over yet - "one alliance remains," not "first HQ dies loses."
func _alliances_with_living_hq() -> Array:
	var result: Array = []
	var seen_teams: Array = []
	for team in _all_teams():
		if team in seen_teams:
			continue
		var alliance = _alliance_for_team(team)
		for t in alliance:
			if not t in seen_teams:
				seen_teams.append(t)
		var alive = false
		for t in alliance:
			var hq = _get_slot(t).get("hq")
			if is_instance_valid(hq) and not hq.is_dead:
				alive = true
				break
		if alive:
			result.append(alliance)
	return result

func _ready():
	if get_node_or_null("/root/AudioManager"):
		get_node("/root/AudioManager").play_music("main_theme")
	bp_manager = BlueprintManagerScript.new()
	bp_manager.name = "BlueprintManager"
	add_child(bp_manager)

	# Default 2-slot config - PLAYER_TEAM/ENEMY_TEAM exactly, so every
	# existing consumer of economy[PLAYER_TEAM] etc. below sees the same
	# entries it always did. Faction gets re-synced onto the slots once
	# _load_rosters() resolves the real (possibly MatchConfig-overridden)
	# player_faction/enemy_faction further down.
	slots = [
		{"team": PLAYER_TEAM, "faction": player_faction, "is_local": true, "is_bot": false, "allies": [], "hq": null},
		{"team": ENEMY_TEAM, "faction": enemy_faction, "is_local": false, "is_bot": true, "allies": [], "hq": null},
	]
	_rebuild_economy_from_slots()

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

	var debug_settings = get_node_or_null("/root/DebugSettings")
	if debug_settings:
		if "infinite_player_resources" in debug_settings:
			debug_infinite_resources = debug_settings.infinite_player_resources
		if "reveal_all_fog" in debug_settings:
			debug_reveal_all_fog = debug_settings.reveal_all_fog
		if "instant_build" in debug_settings:
			debug_instant_build = debug_settings.instant_build

	if debug_infinite_resources:
		economy[PLAYER_TEAM].metal = INFINITE_RESOURCE_FLOOR
		economy[PLAYER_TEAM].crystal = INFINITE_RESOURCE_FLOOR

	production = ProductionQueueScript.new()
	production.setup(self)

	# RTS_CORE_ROADMAP.md C1: buildings spawn BEFORE the navmesh bakes (not
	# after, as this used to run) so the very first bake already carves
	# holes for the starting HQ/refinery/manufactories - no separate
	# same-frame rebake needed for them. That matters: a rebake mid-match
	# (via _physics_process's debounce) is fine because real player orders
	# always land several real engine frames later, giving NavigationServer3D
	# time to internally sync the updated region - but a rebake happening
	# via a SECOND bake within the same handful of startup frames (the old
	# order: bake once with no holes, spawn buildings, debounced rebake
	# fires next tick) left one narrow window where a unit's very first
	# path query could run before that resync fully settled. Confirmed via
	# a standalone repro script - a unit ordered across the map immediately
	# after such a same-frame rebake could wander into the lake before the
	# nav data had caught up. Baking once, correctly, from the start avoids
	# the race entirely rather than papering over it with extra waits.
	_load_rosters()
	_spawn_resource_nodes()
	_spawn_bases()
	_setup_navigation()
	_setup_fog_shroud()
	_setup_minimap()
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

	# PERFORMANCE_PLAN.md P1c - same cadence/pattern as fog above.
	var grid_timer = Timer.new()
	grid_timer.wait_time = FOG_TICK_INTERVAL
	grid_timer.autostart = true
	add_child(grid_timer)
	grid_timer.timeout.connect(_rebuild_damageable_grid)
	_rebuild_damageable_grid() # populate before the first tick so early reacquisition isn't scanning an empty grid

# Production used to tick inside every manufactory's own _physics_process()
# (building.gd); centralized here now that one ProductionQueue owns every
# team+tier queue (RTS_CORE_ROADMAP.md A1).
func _physics_process(delta):
	if production:
		production.tick(delta)
	# RTS_CORE_ROADMAP.md D1: flush at most once per physics frame, no
	# matter how many spend()/add_resources() calls happened this tick
	# (drip-fed cost across several team+tier queues, HQ trickle, etc.) -
	# see spend()'s own comment for why this exists.
	if _resource_ui_dirty:
		_resource_ui_dirty = false
		_update_resource_ui()
	# RTS_CORE_ROADMAP.md D2: queue panel (progress fill + READY/HOLD/timer)
	# and tier-gated button greying both need to track live production/
	# factory state - cheap enough (3 tier strips, ~a dozen buttons) to just
	# recompute every physics tick rather than add another timer.
	if not queue_strips.is_empty():
		_update_queue_panel()
	_refresh_tier_gated_buttons()
	# RTS_CORE_ROADMAP.md D4: "buildings never auto-exit" - once a
	# structures job is genuinely done, real ghost placement begins
	# automatically (matching the old instant-placement UX exactly, just
	# gated behind a real build timer now). Only when nothing else is
	# already being placed - a second queued structure waits its turn until
	# the first is placed or cancelled.
	if production and placing.is_empty():
		var ready_info = production.pop_ready_structure(PLAYER_TEAM)
		if not ready_info.is_empty():
			_begin_placement(ready_info)
	# RTS_CORE_ROADMAP.md 1.3: the AI's own structures queue (enemy_ai.gd's
	# rebuild/power-plant logic) drip-feeds through the exact same
	# production.enqueue_structure()/pop_ready_structure() pipeline as the
	# player - but the AI has no ghost/UI to place through, so a ready job
	# is placed immediately at a computed legal spot instead of waiting on
	# _begin_placement()'s player-only flow.
	if production:
		var ai_ready = production.pop_ready_structure(ENEMY_TEAM)
		if not ai_ready.is_empty():
			_place_ai_structure(ENEMY_TEAM, ai_ready)
	# RTS_CORE_ROADMAP.md C1: one-frame debounce - a building placed/
	# destroyed this physics tick just sets the flag (possibly several
	# times, e.g. AOE splash killing a cluster of buildings in one tick);
	# whichever call flips it first, the actual rebake+repath only runs
	# once, next tick, right here.
	if _nav_rebake_pending:
		_nav_rebake_pending = false
		_rebuild_dynamic_navmesh_holes()

func _on_trickle():
	if game_over: return
	# Loops over slots (RTS_CORE_ROADMAP.md B2) instead of hardcoding
	# [PLAYER_TEAM, ENEMY_TEAM] - a slot manually added past the default 2
	# (e.g. a test's ally) gets HQ trickle income for free.
	for s in slots:
		var hq = s.get("hq")
		if is_instance_valid(hq) and not hq.is_dead:
			var faction = s.get("faction", "industrialists")
			add_resources(s.team, FactionCatalog.get_passive(faction, "hq_trickle_metal", 0), FactionCatalog.get_passive(faction, "hq_trickle_crystal", 0))

# Energy resource team-level economy (ENERGY_AND_BALANCE_SPEC.md #1). A
# static building is any prefab (hq/refinery/factory are always static) or
# a "defense" building on a foundation hull - each drains a flat upkeep
# just for existing, UNLESS the team's faction is Expansionists (their
# static buildings are entirely self-powered, per Factions_and_Buildings.md).
func _recalc_energy_economy():
	if game_over: return
	for s in slots:
		var team = s.team
		var capacity = 0.0
		var hq = s.get("hq")
		if is_instance_valid(hq) and not hq.is_dead:
			capacity += ENERGY_HQ_BASELINE_CAPACITY
		# Deliberately NOT summing get_team_units(team)'s own generator
		# modules here (FABLE_REVIEW.md 1.6, Chris's explicit resolution) -
		# a mobile unit's generator powers only that unit's own energy-cost
		# weapons (battle_unit.gd's max_energy), never the team's base pool.
		# Only base/building power sources feed this loop: the HQ baseline
		# above, and buildings' own generators/power_plant below.
		var faction = s.get("faction", "industrialists")
		var upkeep = 0.0
		for b in get_tree().get_nodes_in_group("buildings"):
			if not is_instance_valid(b) or b.is_dead or b.team != team: continue
			# RTS_CORE_ROADMAP.md D4: a building mid-construction contributes
			# nothing at all yet - not capacity, not upkeep - until its
			# build_incomplete grace period clears.
			if b.build_incomplete: continue
			# A building's own generators always contribute to capacity,
			# independent of whether it also owes upkeep - Expansionists'
			# perk is "our static buildings don't drain," not "our
			# generators don't count."
			for m in b.get_active_modules():
				if m.has_meta("module_data") and m.get_meta("module_data").category == "generator":
					capacity += m.get_meta("module_data").get_energy_capacity()
			# FABLE_REVIEW.md 2.7: a dedicated supply-side building
			# (power_plant) contributes here too - generic across any
			# prefab kind via building.gd's energy_capacity field, not a
			# power_plant-specific special case.
			if "energy_capacity" in b:
				capacity += b.energy_capacity
			var is_static_building = b.kind in ["hq", "refinery", "light_manufactory", "medium_manufactory", "heavy_manufactory", "power_plant"] or (b.kind == "defense" and is_instance_valid(b.defense_hull) and ModuleCatalog.is_foundation(b.defense_hull.get_meta("type_id", "pillbox_foundation")))
			if not is_static_building: continue
			if FactionCatalog.get_passive(faction, "energy_upkeep_exempt", false): continue
			upkeep += ENERGY_UPKEEP_PER_STATIC_BUILDING
		capacity *= FactionCatalog.get_passive(faction, "energy_capacity_mult", 1.0)
		energy_pool[team].capacity = capacity
		energy_pool[team].upkeep = upkeep
		energy_pool[team].energy = clamp(capacity - upkeep, 0.0, max(capacity, 1.0))
		energy_pool[team].deficit = (capacity - upkeep) < 0.0
		# RTS_CORE_ROADMAP.md E1: OpenRA's real 3-state PowerManager, not
		# just a binary deficit flag. "drained" here is upkeep (the only
		# thing actually consuming power in this game - see the loop above);
		# Normal/Low/Critical purely reflect provided-vs-drained, same
		# thresholds OpenRA itself uses.
		var old_power_state = energy_pool[team].get("power_state", "normal")
		var power_state = "normal"
		if capacity < upkeep:
			power_state = "low" if capacity > upkeep / 2.0 else "critical"
		energy_pool[team].power_state = power_state
		if power_state != old_power_state:
			_update_defense_low_power_visuals(team)
	_update_resource_ui()

func is_energy_deficit(team: int) -> bool:
	return energy_pool[team].deficit

# RTS_CORE_ROADMAP.md E1: "OpenRA treats Low and Critical identically for
# production - the distinction only drives conditions" (this one: defense
# weapons disabled + dimmed). Both non-Normal states collapse to the same
# single low_power boolean here.
func is_low_power(team: int) -> bool:
	return energy_pool[team].get("power_state", "normal") != "normal"

# RTS_CORE_ROADMAP.md E1: "disabling defence weapons and dimming their
# mesh" - only ever touches "defense"-kind buildings (a mobile unit's own
# weapons are never gated by the TEAM's base power, same ENERGY_AND_
# BALANCE_SPEC.md #1 boundary _recalc_energy_economy()'s own comment
# already draws). Called only when a team's power_state actually changes,
# not every tick - dimming is a discrete visual state, not something that
# needs smooth per-frame interpolation.
func _update_defense_low_power_visuals(team: int) -> void:
	var low = is_low_power(team)
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.is_dead or b.team != team or b.kind != "defense": continue
		if b.has_method("set_low_power_dim"):
			b.set_low_power_dim(low)

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


# Duck-typed faction lookup for a construct that might be a battle_unit
# (whose faction lives on its hull_node's meta) or a building (which
# already carries a plain .faction field directly).
func _get_construct_faction(c) -> String:
	if "faction" in c and c.faction != "":
		return c.faction
	if "hull_node" in c and is_instance_valid(c.hull_node) and c.hull_node.has_meta("faction"):
		return c.hull_node.get_meta("faction")
	return FactionCatalog.DEFAULT_FACTION

# Reveal-vs-hide hysteresis (Skirmish refinement pass): a construct sitting
# right at the vision-range boundary used to flicker in/out of fog every
# 0.3s tick as tiny position deltas crossed a single threshold. Now reveal
# still happens at the plain vision range, but a construct that's ALREADY
# visible only drops back out past a wider hide threshold - the two-
# threshold gap is the flicker's dead zone.
const FOG_HIDE_RANGE_MULT: float = 1.15

func _get_effective_vision(o) -> float:
	var vision = o.vision_range if "vision_range" in o else 0.0
	var o_flying = "is_flying" in o and o.is_flying
	if not o_flying:
		var elevation = terrain_height_at(o.global_position)
		vision *= 1.0 + min(elevation, ELEVATION_VISION_CAP) * ELEVATION_VISION_BONUS_PER_UNIT
	return vision

func _recalc_fog_of_war():
	if game_over: return
	# Alliance-aware (RTS_CORE_ROADMAP.md B2): "player_constructs" is
	# everyone allied with LOCAL_SLOT's own team, not just literally
	# PLAYER_TEAM - reduces to the exact old 2-team split when nobody has
	# allies (is_allied(PLAYER_TEAM, ENEMY_TEAM) is false with an empty
	# allies list, same as the old != check).
	var local_team = _local_team()
	var player_constructs: Array = []
	var enemy_constructs: Array = []
	for team in _all_teams():
		var group = get_team_units(team) + get_team_buildings(team)
		if is_allied(local_team, team):
			player_constructs += group
		else:
			enemy_constructs += group
	for c in enemy_constructs:
		if not is_instance_valid(c) or not c.has_method("set_fog_visible"): continue
		var seen = false
		var c_flying = "is_flying" in c and c.is_flying
		var was_visible = not ("fog_hidden" in c and c.fog_hidden)
		# Bayou Irregulars passive: shrinks the effective distance at which
		# ANY observer can spot this specific construct - camouflage is a
		# property of the thing being looked at, not the viewer.
		var detection_mult = FactionCatalog.get_passive(_get_construct_faction(c), "detection_range_mult", 1.0)
		for o in player_constructs:
			if not is_instance_valid(o): continue
			var vision = _get_effective_vision(o) * detection_mult
			var effective_range = vision * FOG_HIDE_RANGE_MULT if was_visible else vision
			var o_flying = "is_flying" in o and o.is_flying
			if c.global_position.distance_to(o.global_position) <= effective_range:
				# Flying viewers/targets skip the terrain-obstacle raycast
				# entirely - already airborne regardless of what's on the
				# ground below, same reasoning the elevation bonus above
				# already uses for flying viewers.
				if o_flying or c_flying or _has_line_of_sight(o.global_position, c.global_position):
					seen = true
					break
		if debug_reveal_all_fog:
			seen = true
		c.set_fog_visible(seen)
	_update_fog_shroud(player_constructs)
	_update_minimap()
	_update_enemy_intel()

# --- Fog shroud (visual): a full-map alpha-mask overlay reusing the same
# GRID_CELL resolution as TerrainBuilder's navmesh grid - unexplored terrain
# reads black, explored-but-not-currently-visible reads dimmed, currently
# visible is fully clear. Deliberately a plain radius reveal (no LOS
# raycast) - unlike per-construct enemy visibility above, which needs real
# LOS to avoid a wallhack-through-fog exploit, the shroud is purely cosmetic
# ground dimming, and a raycast per grid cell per player construct would be
# hundreds-to-thousands of extra ray casts every tick for no gameplay
# payoff. Only cells that actually change state get touched (not a full
# image rewrite every tick), so cost scales with vision area, not map size.
const FOG_GRID_CELL: float = 4.0
const FOG_EXPLORED_ALPHA: float = 0.55
const FOG_UNEXPLORED_ALPHA: float = 1.0
const FOG_SHROUD_HEIGHT: float = 0.4
const FOG_SHROUD_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

varying vec3 world_pos;

uniform sampler2D shroud_tex : hint_default_black, filter_linear;
uniform float map_half = 80.0;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz + vec2(map_half)) / (2.0 * map_half);
	vec4 c = texture(shroud_tex, uv);
	ALBEDO = vec3(0.015, 0.015, 0.02);
	ALPHA = c.a;
}
"""

var _fog_half: float = 0.0
var _fog_dim: int = 0
var _fog_shroud_image: Image
var _fog_shroud_texture: ImageTexture
var _fog_prev_visible_cells: Dictionary = {}

func _setup_fog_shroud():
	_fog_half = current_map.get("map_half_extents", 80.0)
	_fog_dim = max(1, int(ceil((_fog_half * 2.0) / FOG_GRID_CELL)))
	_fog_shroud_image = Image.create(_fog_dim, _fog_dim, false, Image.FORMAT_RGBA8)
	_fog_shroud_image.fill(Color(0, 0, 0, FOG_UNEXPLORED_ALPHA))
	_fog_shroud_texture = ImageTexture.create_from_image(_fog_shroud_image)

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "FogShroud"
	var plane = PlaneMesh.new()
	plane.size = Vector2(_fog_half * 2.0, _fog_half * 2.0)
	mesh_inst.mesh = plane
	var shader = Shader.new()
	shader.code = FOG_SHROUD_SHADER_CODE
	var shader_mat = ShaderMaterial.new()
	shader_mat.shader = shader
	shader_mat.set_shader_parameter("shroud_tex", _fog_shroud_texture)
	shader_mat.set_shader_parameter("map_half", _fog_half)
	mesh_inst.material_override = shader_mat
	add_child(mesh_inst)
	mesh_inst.global_position = Vector3(0, FOG_SHROUD_HEIGHT, 0)

func _fog_world_to_cell(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x + _fog_half) / FOG_GRID_CELL)), int(floor((z + _fog_half) / FOG_GRID_CELL)))

func _update_fog_shroud(player_constructs: Array):
	if not is_instance_valid(_fog_shroud_texture): return
	var new_visible: Dictionary = {}
	for o in player_constructs:
		if not is_instance_valid(o): continue
		var vision = _get_effective_vision(o)
		if vision <= 0.0: continue
		var center = o.global_position
		var cell_radius = int(ceil(vision / FOG_GRID_CELL)) + 1
		var c0 = _fog_world_to_cell(center.x, center.z)
		for dz in range(-cell_radius, cell_radius + 1):
			var gz = c0.y + dz
			if gz < 0 or gz >= _fog_dim: continue
			for dx in range(-cell_radius, cell_radius + 1):
				var gx = c0.x + dx
				if gx < 0 or gx >= _fog_dim: continue
				var world_x = -_fog_half + (gx + 0.5) * FOG_GRID_CELL
				var world_z = -_fog_half + (gz + 0.5) * FOG_GRID_CELL
				if Vector2(world_x - center.x, world_z - center.z).length() <= vision:
					new_visible[Vector2i(gx, gz)] = true

	var changed = false
	for cell in new_visible.keys():
		if not _fog_prev_visible_cells.has(cell):
			_fog_shroud_image.set_pixel(cell.x, cell.y, Color(0, 0, 0, 0.0))
			changed = true
	for cell in _fog_prev_visible_cells.keys():
		if not new_visible.has(cell):
			_fog_shroud_image.set_pixel(cell.x, cell.y, Color(0, 0, 0, FOG_EXPLORED_ALPHA))
			changed = true
	_fog_prev_visible_cells = new_visible
	if changed:
		_fog_shroud_texture.update(_fog_shroud_image)

# --- Minimap (RTS_CORE_ROADMAP.md B9) ---
# Deliberately a real Image the tests can read pixels back from directly,
# NOT render-to-texture - headless never rasterizes a Viewport, which would
# make this untestable (this roadmap chunk's own note). Static terrain
# colors bake ONCE into _minimap_static_image (a coarser grid than the fog
# shroud's - a minimap doesn't need per-vision-tick precision, just a
# recognizable silhouette); every tick, _minimap_image resets to a copy of
# that static bake, then gets live unit/building/resource blips blitted on
# top - cheap since the whole image is small.
const MINIMAP_CELL: float = 8.0
const MINIMAP_UI_SIZE: float = 180.0
const MINIMAP_WATER_COLOR: Color = Color(0.15, 0.32, 0.55)
# Palette echoes generate_terrain_textures.gd's per-surface tints, coarsened
# to a single flat color per type (a minimap swatch, not a material).
const MINIMAP_SURFACE_COLORS: Dictionary = {
	"marsh": Color(0.30, 0.36, 0.24),
	"rocky": Color(0.42, 0.40, 0.38),
	"snow_mud": Color(0.55, 0.58, 0.60),
	"sand": Color(0.62, 0.56, 0.38),
	"gravel": Color(0.48, 0.46, 0.44),
	"forest": Color(0.16, 0.28, 0.16),
	"ice": Color(0.75, 0.85, 0.92),
}
const MINIMAP_METAL_COLOR: Color = Color(0.85, 0.75, 0.4)
const MINIMAP_CRYSTAL_COLOR: Color = Color(0.55, 0.75, 0.95)
const MINIMAP_BLIP_RADIUS: int = 1

var _minimap_half: float = 0.0
var _minimap_dim: int = 0
var _minimap_static_image: Image
var _minimap_image: Image
var _minimap_texture: ImageTexture
var minimap_rect: TextureRect

func _setup_minimap():
	_minimap_half = current_map.get("map_half_extents", 80.0)
	_minimap_dim = max(1, int(ceil((_minimap_half * 2.0) / MINIMAP_CELL)))
	var ground_color_arr = current_map.get("ground_color", [0.2, 0.25, 0.2])
	var ground_color = Color(ground_color_arr[0], ground_color_arr[1], ground_color_arr[2])
	_minimap_static_image = Image.create(_minimap_dim, _minimap_dim, false, Image.FORMAT_RGB8)
	for gz in range(_minimap_dim):
		var world_z = -_minimap_half + (gz + 0.5) * MINIMAP_CELL
		for gx in range(_minimap_dim):
			var world_x = -_minimap_half + (gx + 0.5) * MINIMAP_CELL
			var color: Color
			if TerrainBuilder.is_water_at(current_map, world_x, world_z):
				color = MINIMAP_WATER_COLOR
			else:
				var surf = TerrainBuilder.get_surface_type_at(current_map, Vector3(world_x, 0, world_z))
				color = MINIMAP_SURFACE_COLORS.get(surf, ground_color)
			_minimap_static_image.set_pixel(gx, gz, color)
	_minimap_image = _minimap_static_image.duplicate()
	_minimap_texture = ImageTexture.create_from_image(_minimap_image)

func _minimap_world_to_cell(x: float, z: float) -> Vector2i:
	var gx = int(floor((x + _minimap_half) / MINIMAP_CELL))
	var gz = int(floor((z + _minimap_half) / MINIMAP_CELL))
	return Vector2i(clampi(gx, 0, _minimap_dim - 1), clampi(gz, 0, _minimap_dim - 1))

# Minimap-local UV (0..1, 0..1) -> world (x, z). Used by the click-to-move-
# camera handler below.
func _minimap_uv_to_world(uv: Vector2) -> Vector2:
	return Vector2(-_minimap_half + uv.x * _minimap_half * 2.0, -_minimap_half + uv.y * _minimap_half * 2.0)

func _blit_minimap_blip(world_x: float, world_z: float, color: Color, radius: int = MINIMAP_BLIP_RADIUS):
	var c = _minimap_world_to_cell(world_x, world_z)
	for dz in range(-radius, radius + 1):
		var gz = c.y + dz
		if gz < 0 or gz >= _minimap_dim: continue
		for dx in range(-radius, radius + 1):
			var gx = c.x + dx
			if gx < 0 or gx >= _minimap_dim: continue
			_minimap_image.set_pixel(gx, gz, color)

func _update_minimap():
	if not is_instance_valid(_minimap_texture): return
	_minimap_image.blit_rect(_minimap_static_image, Rect2i(Vector2i.ZERO, Vector2i(_minimap_dim, _minimap_dim)), Vector2i.ZERO)

	# Resource nodes aren't fog-gated anywhere else in this game (map
	# knowledge, not scouting-gated - see resource_node.gd), so they always
	# show here too.
	for r in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(r): continue
		var rcolor = MINIMAP_CRYSTAL_COLOR if r.get("resource_type") == "crystal" else MINIMAP_METAL_COLOR
		_blit_minimap_blip(r.global_position.x, r.global_position.z, rcolor)

	var local_team = _local_team()
	for team in _all_teams():
		var is_own_side = is_allied(local_team, team)
		for c in get_team_units(team) + get_team_buildings(team):
			if not is_instance_valid(c): continue
			# Same visibility rule as everything else the player sees
			# (_recalc_fog_of_war()'s own comment): an enemy blip only
			# shows while currently scouted, no persistent memory.
			if not is_own_side and "fog_hidden" in c and c.fog_hidden: continue
			var color = FactionCatalog.get_visual_color(_get_construct_faction(c))
			_blit_minimap_blip(c.global_position.x, c.global_position.z, color)

	_minimap_texture.update(_minimap_image)

func _on_minimap_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var uv = event.position / MINIMAP_UI_SIZE
		var world = _minimap_uv_to_world(uv)
		# Keep the camera's existing height/angle - just recenter its X/Z
		# over the clicked minimap location (the camera is a fixed overhead
		# angle with no independent pan target today, so X/Z IS its ground
		# focus point).
		camera.global_position.x = world.x
		camera.global_position.z = world.y

# Composition readout for whatever enemy constructs are CURRENTLY visible
# (never fog-hidden ones - same one-directional, no-persistent-memory fog
# model everything else the player sees already uses). Categories match
# enemy_ai.gd's own _scout_player_threat() (flying, armor_thickness >= 2.0)
# so the player's intel and the AI's own scouting read the battlefield the
# same way - not a separate, arbitrary classification.
func _update_enemy_intel():
	if not intel_label: return
	var visible_enemies = []
	for c in get_team_units(ENEMY_TEAM) + get_team_buildings(ENEMY_TEAM):
		if is_instance_valid(c) and not ("fog_hidden" in c and c.fog_hidden):
			visible_enemies.append(c)
	if visible_enemies.is_empty():
		intel_label.text = "👁 No enemies sighted"
		return
	var flying = 0
	var armored = 0
	for c in visible_enemies:
		if "is_flying" in c and c.is_flying:
			flying += 1
		if "hull_node" in c and is_instance_valid(c.hull_node) and c.hull_node.has_meta("armor_thickness") and c.hull_node.get_meta("armor_thickness") >= 2.0:
			armored += 1
	var detail = []
	if flying > 0: detail.append("%d air" % flying)
	if armored > 0: detail.append("%d armored" % armored)
	var detail_str = " (%s)" % ", ".join(detail) if not detail.is_empty() else ""
	intel_label.text = "👁 Enemy sighted: %d%s" % [visible_enemies.size(), detail_str]

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
				var entry = _make_roster_entry(data)
				if not entry.is_empty():
					roster.append(entry)
	else:
		var entries = bp_manager.list_blueprints()
		for e in entries.slice(0, 8): # newest saved designs first, leave room for defaults
			var data = bp_manager.load_blueprint(e.path)
			if not data.is_empty():
				var entry = _make_roster_entry(data)
				if not entry.is_empty():
					roster.append(entry)
	for path in _list_json_files("res://data/loadout"):
		var data = bp_manager.load_blueprint(path)
		if not data.is_empty():
			var entry = _make_roster_entry(data)
			if not entry.is_empty():
				roster.append(entry)
	roster = roster.slice(0, 12) # Loadout limit

	# A skirmish without a harvester design is unwinnable - guarantee one
	if _find_harvester_blueprint(roster).is_empty():
		var trucker = bp_manager.load_blueprint("res://data/loadout/ore_trucker.json")
		if not trucker.is_empty():
			var entry = _make_roster_entry(trucker)
			if not entry.is_empty():
				roster.append(entry)

	if _mc_player_faction != "":
		player_faction = _mc_player_faction
	elif not roster.is_empty():
		player_faction = roster[0].blueprint.get("faction", "industrialists")

	for path in _list_json_files("res://data/enemy"):
		var data = bp_manager.load_blueprint(path)
		if not data.is_empty():
			var entry = _make_roster_entry(data)
			if not entry.is_empty():
				enemy_roster.append(entry)
	if _mc_enemy_faction != "":
		enemy_faction = _mc_enemy_faction
	elif not enemy_roster.is_empty():
		enemy_faction = enemy_roster[0].blueprint.get("faction", "technocrats")

	# Re-sync now that player_faction/enemy_faction have resolved past
	# their _ready()-time defaults (MatchConfig override or roster[0]'s tag).
	_get_slot(PLAYER_TEAM)["faction"] = player_faction
	_get_slot(ENEMY_TEAM)["faction"] = enemy_faction

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

# Returns {} (never a half-built entry) if the blueprint's hull_type isn't
# installed - same "refuse rather than silently corrupt" principle as
# BlueprintManager's hard-fail-on-unknown-hull for the Design Lab's own Load
# button (HULL_MODDING_PLAN.md's latent bug: get_module_data()'s fallback is
# a WEAPON's data, not a hull's - a roster entry cost/tier built off that
# would be silently wrong, not just cosmetically off). Every call site below
# checks for an empty result before appending.
func _make_roster_entry(data: Dictionary) -> Dictionary:
	var hull_type = data.get("hull_type", "medium_hull")
	if not ModuleCatalog.hull_exists(hull_type):
		push_warning("Skirmish: dropping roster entry '%s' - hull '%s' is not installed" % [data.get("name", "Untitled"), hull_type])
		return {}
	var cost = blueprint_cost(data)
	return {
		"blueprint": data,
		"name": data.get("name", "Untitled"),
		"cost_metal": cost.x,
		"cost_crystal": cost.y,
		"is_defense": ModuleCatalog.is_foundation(hull_type),
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

# Recomputed from the CURRENT catalog + the blueprint's own tweaks/scale
# every time (FABLE_REVIEW.md 3.10) - previously this trusted the "stats"
# block baked into the save file, which (a) let a hand-edited user:// JSON
# field units at arbitrary prices and (b) froze costs at whatever the
# catalog said on the day the design was saved, so balance passes (e.g. the
# spigot_mortar/flamethrower repricing) silently never applied to older
# designs. The serialized stats block stays in the save format as a
# debugging/inspection aid; it just isn't the authority on price anymore.
func blueprint_cost(data: Dictionary) -> Vector2i:
	var hull_type = data.get("hull_type", "medium_hull")
	# Hull cost now includes armor material/thickness and hull scale
	# (FABLE_REVIEW.md 1.2/1.3 - previously all three were free power).
	var sc_dict = data.get("hull_scale", {"x": 1.0, "y": 1.0, "z": 1.0})
	var hull_cost = ModuleCatalog.compute_hull_cost(
		hull_type,
		data.get("armor_thickness", 1.0),
		data.get("armor_material", "hardened_steel"),
		Vector3(sc_dict.x, sc_dict.y, sc_dict.z))
	var m = hull_cost.x
	var c = hull_cost.y
	for mod in data.get("modules", []):
		var type_id = mod.get("type_id", "")
		if not ModuleCatalog.module_exists(type_id):
			continue # unknown module - reconstruct_vehicle skips it too, so don't charge for it
		var cat = ModuleCatalog.get_module_data(type_id)
		var md = ModuleDataScript.new()
		md.type_id = type_id
		md.cost_metal = cat.metal
		md.cost_crystal = cat.crystal
		md.tweaks = mod.get("tweaks", {})
		var sc = mod.get("scale", {"x": 1.0, "y": 1.0, "z": 1.0})
		md.scale_multiplier = Vector3(sc.x, sc.y, sc.z)
		var cost = md.get_cost()
		m += cost.x
		c += cost.y
	return Vector2i(m, c)

func build_time_for_cost(cost: Vector2i) -> float:
	return clamp((cost.x + cost.y * 2) * 0.05, 3.0, 40.0)

# --- Economy ---

# Testing cheat (Chris's explicit request): the player's economy never
# actually runs out - every spend() immediately tops back up to a floor
# comfortably above the most expensive roster entry, so build/production
# testing isn't gated by grinding harvester income. Deliberately PLAYER_TEAM
# only - the enemy AI's economy is untouched, so its own production timing
# still behaves normally for balance/AI testing.
#
# RTS_CORE_ROADMAP.md A2: was a hardcoded const; now a runtime var so the
# debug/options panel (_build_debug_panel()) and tests can flip it without a
# source edit. Seeded from the DebugSettings autoload if present (so a
# player's choice persists across a match restart), defaulting to the same
# `true` the const used to hardcode when the autoload is absent (every
# headless test that instantiates Skirmish.tscn directly).
var debug_infinite_resources: bool = true
const INFINITE_RESOURCE_FLOOR: int = 999999

# Same runtime-toggle treatment as debug_infinite_resources above: seeded
# from DebugSettings, flipped live from the debug panel. reveal_all_fog
# short-circuits _recalc_fog_of_war()'s per-construct visibility check;
# instant_build makes production_queue.gd's tick() finish the front job of
# every queue on its next physics tick instead of counting down build_time.
var debug_reveal_all_fog: bool = false
var debug_instant_build: bool = false

func can_afford(team: int, metal: int, crystal: int) -> bool:
	return economy[team].metal >= metal and economy[team].crystal >= crystal

# RTS_CORE_ROADMAP.md D1's own gotcha: spend() now gets called once per
# team+tier queue EVERY physics tick (drip-fed cost, production_queue.gd's
# tick()), not just on a discrete player action - _update_resource_ui()
# itself is cheap, but calling it up to several times a frame for a label
# update that only needs to happen once is wasted work. Both spend() and
# add_resources() just flag dirty now; skirmish.gd's own _physics_process()
# flushes it at most once per frame, after production has ticked.
var _resource_ui_dirty: bool = false

func spend(team: int, metal: int, crystal: int) -> bool:
	if not can_afford(team, metal, crystal):
		return false
	economy[team].metal -= metal
	economy[team].crystal -= crystal
	if debug_infinite_resources and team == PLAYER_TEAM:
		economy[team].metal = max(economy[team].metal, INFINITE_RESOURCE_FLOOR)
		economy[team].crystal = max(economy[team].crystal, INFINITE_RESOURCE_FLOOR)
	_resource_ui_dirty = true
	return true

func add_resources(team: int, metal: int, crystal: int):
	economy[team].metal += metal
	economy[team].crystal += crystal
	_resource_ui_dirty = true

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
	# RTS_CORE_ROADMAP.md C1: the starting buildings (_spawn_bases(), which
	# now runs before this) already exist, so their footprints go straight
	# into the FIRST bake instead of needing an immediate follow-up rebake
	# - see this function's caller for why that ordering matters.
	var nav = TerrainBuilder.build_navmeshes(current_map, _gather_building_holes())
	_nav_rebake_pending = false
	ground_nav_map = nav.ground_map
	water_nav_map = nav.water_map
	amphibious_nav_map = nav.amphibious_map
	deep_water_nav_map = nav.deep_water_map
	_ground_nav_region = nav.ground_region
	_water_nav_region = nav.water_region
	_amphibious_nav_region = nav.amphibious_region
	_deep_water_nav_region = nav.deep_water_region

	var ground = get_node_or_null("Ground")
	if ground:
		# Skirmish refinement pass: Ground used to be one flat BoxMesh/
		# BoxShape3D slab (hence the scene's baked -0.5 Y offset, sizing its
		# top surface to sit at y=0) - replaced with a real subdivided
		# heightmap mesh/shape whose vertices already carry absolute
		# height_at() world Y values (see build_ground_visual_mesh()), so
		# the old slab offset has to go too or every terrain query would be
		# off by half a unit from what units/buildings actually see.
		ground.position = Vector3.ZERO
		var generated = TerrainBuilder.build_ground_visual_mesh(current_map)
		var mesh_inst: MeshInstance3D = ground.get_node_or_null("MeshInstance3D")
		if mesh_inst:
			mesh_inst.mesh = generated.mesh
			var ground_color = current_map.get("ground_color", Color(0.2, 0.26, 0.21))
			mesh_inst.material_override = TerrainBuilder.build_ground_material_heightmap(ground_color)
		var col_shape: CollisionShape3D = ground.get_node_or_null("CollisionShape3D")
		if col_shape:
			col_shape.shape = generated.shape
			col_shape.scale = generated.get("collision_scale", Vector3.ONE)

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
	# RTS_CORE_ROADMAP.md B3: player_start/enemy_start became a spawns
	# array with an id per entry - "player"/"enemy" are the ids every
	# bundled map uses.
	var p_start = MapCatalog.get_spawn(current_map, "player")
	var e_start = MapCatalog.get_spawn(current_map, "enemy")

	player_hq = _spawn_prefab("hq", PLAYER_TEAM, p_start.hq, player_faction)
	_spawn_starting_manufactories(PLAYER_TEAM, p_start.factory, player_faction)
	_spawn_prefab("refinery", PLAYER_TEAM, p_start.refinery, player_faction)

	enemy_hq = _spawn_prefab("hq", ENEMY_TEAM, e_start.hq, enemy_faction)
	_spawn_starting_manufactories(ENEMY_TEAM, e_start.factory, enemy_faction)
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

# Base-building batch: size-tiered manufactories replace the single old
# "factory" prefab. Every match starts with all 3 tiers already built in a
# small cluster around the map's single authored `factory` start position
# (deliberately NOT an unlockable progression - see DECISIONS_NEEDED.md for
# why) - the Light Manufactory keeps the exact original spawn point (so
# every map's already-verified factory position stays legal/unblocked
# unchanged), Medium/Heavy are offset to either side of it. Players (and
# the AI, which never places new buildings) can still build additional
# manufactories of any tier via the build bar for parallel production
# capacity, same as the old single "Factory" button already allowed.
func _spawn_starting_manufactories(team: int, factory_pos: Vector3, faction: String):
	_spawn_prefab("light_manufactory", team, factory_pos, faction)
	_spawn_prefab("medium_manufactory", team, factory_pos + Vector3(8, 0, 0), faction)
	_spawn_prefab("heavy_manufactory", team, factory_pos + Vector3(-8, 0, 0), faction)

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
	# RTS_CORE_ROADMAP.md C1: a new building needs a navmesh hole carved
	# for it, and its eventual death needs to un-carve that hole - both go
	# through the same debounced rebake.
	b.died.connect(func(_b): _mark_navmesh_dirty())
	_mark_navmesh_dirty()
	return b

func spawn_unit(blueprint_data: Dictionary, team: int, pos: Vector3) -> Node:
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	add_child(unit)
	unit.global_position = Vector3(pos.x, terrain_height_at(pos) + pos.y, pos.z)
	# The match's chosen faction overrides whatever the design was saved
	# under (FABLE_REVIEW 1.7) - stats AND looks both follow the team's real
	# faction, not the blueprint's own tag.
	var match_faction = player_faction if team == PLAYER_TEAM else enemy_faction
	unit.setup(blueprint_data, team, bp_manager, match_faction)
	unit.resources_delivered.connect(_on_resources_delivered)
	return unit

func spawn_defense(blueprint_data: Dictionary, team: int, pos: Vector3) -> StaticBody3D:
	var b = StaticBody3D.new()
	b.set_script(BuildingScript)
	add_child(b)
	b.global_position = Vector3(pos.x, terrain_height_at(pos), pos.z)
	# Always PLAYER_TEAM today (the only spawn_defense() call site), but
	# written generically like spawn_unit() above rather than hardcoding
	# player_faction, in case that changes.
	var match_faction = player_faction if team == PLAYER_TEAM else enemy_faction
	b.setup_defense(blueprint_data, team, bp_manager, match_faction)
	# RTS_CORE_ROADMAP.md C1: same navmesh-hole bookkeeping as _spawn_prefab().
	b.died.connect(func(_b): _mark_navmesh_dirty())
	_mark_navmesh_dirty()
	return b

# tier: "" returns a manufactory of ANY tier (backward-compatible
# "just get me a factory" behavior, used by contexts that don't care which
# tier - e.g. the map smoke test's generic production check); "light"/
# "medium"/"heavy" returns only a manufactory of that exact tier, or null
# if the team doesn't have one (e.g. it was destroyed mid-match).
#
# RTS_CORE_ROADMAP.md A1: no longer picks the LEAST-BUSY of several matching
# manufactories (FABLE_REVIEW.md 2.4's fix) - that distinction stopped
# existing the moment production moved to one shared queue per team+tier
# (ProductionQueue/production_queue.gd). Every manufactory of a given tier is
# now equivalent for queuing purposes; this just returns the first live
# match, used as a spawn point / existence check.
func get_team_factory(team: int, tier: String = "") -> Node:
	for b in get_tree().get_nodes_in_group("buildings"):
		# RTS_CORE_ROADMAP.md D4: a manufactory still under construction
		# doesn't count as usable yet - production/queuing/multi-factory
		# speed bonus all key off this same lookup.
		if not is_instance_valid(b) or b.is_dead or b.team != team or b.build_incomplete: continue
		var matches = (tier == "" and b.kind in BuildingScript.MANUFACTORY_KINDS) or b.kind == tier + "_manufactory"
		if matches:
			return b
	return null

func has_factory_of_tier(team: int, tier: String) -> bool:
	return get_team_factory(team, tier) != null

# RTS_CORE_ROADMAP.md D3: how many LIVE manufactories of this tier a team
# has - production_queue.gd's enqueue() uses this to look up the multi-
# factory build-time speed bonus.
func count_factories_of_tier(team: int, tier: String) -> int:
	var count := 0
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.is_dead and b.team == team and b.kind == tier + "_manufactory" and not b.build_incomplete:
			count += 1
	return count

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

# --- Dynamic navmesh for buildings (RTS_CORE_ROADMAP.md C1) ---

func _mark_navmesh_dirty() -> void:
	_nav_rebake_pending = true

# Every LIVE building's footprint, gathered fresh each rebake (not cached -
# a live match's building set only changes on placement/death, both of
# which already call _mark_navmesh_dirty(), so this is never stale when it
# actually runs).
func _gather_building_holes() -> Array:
	var holes: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		# is_inside_tree() guards a real teardown-race: queue_free() defers
		# actual removal to end-of-frame, so a building mid-teardown (e.g.
		# during a test's skirmish.queue_free() cleanup) can stay
		# is_instance_valid() a moment after leaving the tree - reading
		# global_position on it throws (found via a real "!is_inside_tree()"
		# engine error during the test suite once buildings started
		# carving real holes).
		if not is_instance_valid(b) or b.is_dead or not b.is_inside_tree(): continue
		var fp: Vector3 = b.footprint if "footprint" in b else Vector3(5, 3, 5)
		holes.append({"center": b.global_position, "half_extents": Vector2(fp.x / 2.0, fp.z / 2.0)})
	return holes

func _rebuild_dynamic_navmesh_holes() -> void:
	TerrainBuilder.rebake_ground_and_amphibious(current_map, _gather_building_holes(), _ground_nav_region, _amphibious_nav_region)
	_repath_live_units()

# A rebaked navmesh doesn't retroactively invalidate a NavigationAgent3D's
# already-cached path corridor - a unit mid-route when a building goes up
# (or comes down) needs to be told to ask again, or it walks straight into
# (or around, needlessly) geometry that just changed.
func _repath_live_units() -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead and u.is_inside_tree() and u.has_method("request_repath"):
			u.request_repath()

# --- UI ---

func _build_ui():
	var ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	# Brushed-aluminum chrome behind the top info strip, tinted to the
	# player's own faction - added first so it renders behind the labels.
	var top_bar_bg = PanelContainer.new()
	top_bar_bg.anchor_left = 0.0
	top_bar_bg.anchor_right = 1.0
	top_bar_bg.anchor_top = 0.0
	top_bar_bg.anchor_bottom = 0.0
	top_bar_bg.offset_bottom = 68
	ui.add_child(top_bar_bg)
	UITheme.apply_brushed_panel(top_bar_bg, player_faction, 0.4)

	resource_label = Label.new()
	resource_label.position = Vector2(20, 14)
	resource_label.add_theme_font_size_override("font_size", 22)
	ui.add_child(resource_label)

	# RTS_CORE_ROADMAP.md E1: a real power bar (progress fill + Normal/Low/
	# Critical text) instead of the old single status-flash string baked
	# into resource_label. Same panel-with-overlay-label structure as D2's
	# queue strips, for visual consistency.
	power_bar_panel = PanelContainer.new()
	power_bar_panel.position = Vector2(340, 16)
	power_bar_panel.size = Vector2(190, 26)
	var power_bar_style = StyleBoxFlat.new()
	power_bar_style.bg_color = Color(0.1, 0.11, 0.14, 0.85)
	power_bar_style.border_color = Color(0.3, 0.35, 0.4, 0.9)
	power_bar_style.border_width_left = 1
	power_bar_style.border_width_right = 1
	power_bar_style.border_width_top = 1
	power_bar_style.border_width_bottom = 1
	power_bar_panel.add_theme_stylebox_override("panel", power_bar_style)
	ui.add_child(power_bar_panel)

	power_bar = ProgressBar.new()
	power_bar.min_value = 0.0
	power_bar.max_value = 1.0
	power_bar.value = 1.0
	power_bar.show_percentage = false
	power_bar_panel.add_child(power_bar)

	power_status_label = Label.new()
	power_status_label.text = "⚡ Normal"
	power_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	power_status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	power_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_bar_panel.add_child(power_status_label)

	status_label = Label.new()
	status_label.position = Vector2(20, 46)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.modulate = Color(0.8, 0.85, 0.9)
	status_label.text = "Left-click/drag: select | Right-click: move / attack / harvest | Destroy the enemy HQ!"
	ui.add_child(status_label)

	# Enemy composition intel readout (FABLE_REVIEW.md 2.1, the other half
	# of the counter-play loop alongside enemy_ai.gd's counter-picking) -
	# previously "nothing surfaces enemy composition to the player," so the
	# player's own counter-design decisions had no real input. Fog-gated
	# like everything else the player sees (only currently-visible enemy
	# constructs, no persistent "seen once, remembered" memory - matching
	# the existing one-directional fog model's own scope, see
	# _recalc_fog_of_war()'s comment), updated on the same tick as fog.
	intel_label = Label.new()
	intel_label.anchor_left = 1.0
	intel_label.anchor_right = 1.0
	intel_label.offset_left = -620
	intel_label.offset_right = -200
	intel_label.offset_top = 14
	intel_label.offset_bottom = 54
	intel_label.add_theme_font_size_override("font_size", 15)
	intel_label.modulate = Color(0.85, 0.75, 0.6)
	intel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(intel_label)
	_update_enemy_intel()

	var menu_btn = Button.new()
	menu_btn.text = " Menu"
	menu_btn.icon = UIIcons.get_icon("menu")
	menu_btn.expand_icon = true
	menu_btn.anchor_left = 1.0
	menu_btn.anchor_right = 1.0
	menu_btn.offset_left = -190
	menu_btn.offset_right = -105
	menu_btn.offset_top = 14
	menu_btn.offset_bottom = 54
	var menu_style = StyleBoxFlat.new()
	menu_style.bg_color = Color(0.12, 0.14, 0.18, 0.90)
	menu_style.border_color = Color(0.20, 0.60, 0.85, 0.90)
	menu_style.border_width_left = 1
	menu_style.border_width_right = 1
	menu_style.border_width_top = 1
	menu_style.border_width_bottom = 1
	menu_style.corner_radius_top_left = 4
	menu_style.corner_radius_top_right = 4
	menu_style.corner_radius_bottom_left = 4
	menu_style.corner_radius_bottom_right = 4
	menu_btn.add_theme_stylebox_override("normal", menu_style)
	var menu_hover = menu_style.duplicate() as StyleBoxFlat
	menu_hover.bg_color = Color(0.18, 0.22, 0.28, 0.95)
	menu_btn.add_theme_stylebox_override("hover", menu_hover)
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	ui.add_child(menu_btn)

	if OS.is_debug_build():
		_build_debug_panel(ui, menu_style, menu_hover)

	# Bottom build bar (RTS_CORE_ROADMAP.md D2: tabbed Structures/Defenses/
	# Units, replacing the old flat ScrollContainer that mixed 5 building
	# buttons with up to 12 unit entries in one undifferentiated row) + a
	# queue panel (3 tier strips: progress fill, READY/HOLD/timer text).
	var bar_bg = PanelContainer.new()
	bar_bg.anchor_top = 1.0
	bar_bg.anchor_bottom = 1.0
	bar_bg.anchor_left = 0.0
	bar_bg.anchor_right = 1.0
	bar_bg.offset_top = -132
	ui.add_child(bar_bg)
	UITheme.apply_brushed_panel(bar_bg, player_faction, 0.4)

	var bar_vbox = VBoxContainer.new()
	bar_vbox.add_theme_constant_override("separation", 2)
	bar_bg.add_child(bar_vbox)

	_build_queue_panel(bar_vbox)
	_build_tab_bar(bar_vbox)

	# Each tab gets its OWN ScrollContainer (only one visible at a time) -
	# a single shared ScrollContainer with 3 stacked HBoxContainer children
	# computes its scroll region from all of them combined, hidden or not,
	# which fights the tab-switching this is meant to do.
	for tab_name in ["structures", "defenses", "units"]:
		var tab_scroll = ScrollContainer.new()
		tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tab_scroll.custom_minimum_size = Vector2(0, 92)
		tab_scroll.visible = (tab_name == active_build_tab)
		bar_vbox.add_child(tab_scroll)

		var box = HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		tab_scroll.add_child(box)
		build_tab_containers[tab_name] = box

	# Size-tiered manufactories (base-building batch) - every match starts
	# with one of each already built (_spawn_starting_manufactories()); these
	# buttons let a player build MORE of a given tier for parallel production
	# capacity, same as the old single "Factory" button already allowed.
	# RTS_CORE_ROADMAP.md C2: costs read straight from building.gd's
	# PREFAB_STATS instead of being duplicated here as literals (the label
	# strings/colors below are presentation-only, not a second source of
	# cost truth - see this same building's define in PREFAB_STATS for the
	# real numbers).
	const PREFAB_BUTTON_LABELS := {
		"light_manufactory": "🏭 Light Manufactory",
		"medium_manufactory": "🏭 Medium Manufactory",
		"heavy_manufactory": "🏭 Heavy Manufactory",
		"refinery": "⛽ Refinery",
		# Real supply-side Energy building (FABLE_REVIEW.md 2.7) - previously
		# capacity only ever came from generator modules bolted onto units/
		# defenses, so losing the one tank carrying a fusion_generator meant
		# losing the base's power.
		"power_plant": "⚡ Power Plant",
	}
	const PREFAB_BUTTON_COLORS := {
		"light_manufactory": Color(0.68, 0.6, 0.42),
		"medium_manufactory": Color(0.72, 0.55, 0.42),
		"heavy_manufactory": Color(0.6, 0.42, 0.35),
		"refinery": Color(0.55, 0.62, 0.75),
		"power_plant": Color(0.85, 0.65, 0.2),
	}
	for kind in ["light_manufactory", "medium_manufactory", "heavy_manufactory", "refinery", "power_plant"]:
		var stats = BuildingScript.PREFAB_STATS[kind]
		var label_text = "%s\n%dM %dC" % [PREFAB_BUTTON_LABELS[kind], stats.cost_metal, stats.cost_crystal]
		# RTS_CORE_ROADMAP.md D4: "buildings never auto-exit" - clicking
		# QUEUES the structure (real drip-fed build time) instead of
		# starting ghost placement immediately; _try_place_building() only
		# runs once production.pop_ready_structure() says it's actually done.
		_add_build_button(build_tab_containers["structures"], label_text, PREFAB_BUTTON_COLORS[kind], func():
			_queue_structure_build({"kind": kind, "cost_metal": stats.cost_metal, "cost_crystal": stats.cost_crystal}))

	for entry in roster:
		var e = entry
		var label_text = "%s\n%dM %dC" % [e.name, e.cost_metal, e.cost_crystal]
		if e.is_defense:
			_add_build_button(build_tab_containers["defenses"], label_text, Color(0.4, 0.5, 0.4), func():
				_queue_structure_build({"kind": "defense", "blueprint": e.blueprint, "cost_metal": e.cost_metal, "cost_crystal": e.cost_crystal}))
		else:
			# RTS_CORE_ROADMAP.md D2: shift-click queues 5. Greyed out (and
			# not clickable) whenever this entry's tier has no live
			# manufactory - was only a status flash after the fact before,
			# see _refresh_tier_gated_buttons().
			var tier = ModuleCatalog.get_hull_size_tier(e.blueprint.get("hull_type", "medium_hull"))
			var btn = _add_build_button(build_tab_containers["units"], label_text, Color(0.35, 0.42, 0.55), func():
				var copies = 5 if Input.is_key_pressed(KEY_SHIFT) else 1
				for i in range(copies):
					_queue_player_unit(e))
			_tier_gated_buttons.append({"button": btn, "tier": tier})

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

	# Minimap (RTS_CORE_ROADMAP.md B9): bottom-right corner, sitting just
	# above the build bar. Click recenters the camera; right-click-to-order
	# is left as future polish per this roadmap chunk's own note.
	minimap_rect = TextureRect.new()
	minimap_rect.anchor_left = 1.0
	minimap_rect.anchor_right = 1.0
	minimap_rect.anchor_top = 1.0
	minimap_rect.anchor_bottom = 1.0
	minimap_rect.offset_right = -10
	minimap_rect.offset_left = -10 - MINIMAP_UI_SIZE
	minimap_rect.offset_bottom = -106
	minimap_rect.offset_top = -106 - MINIMAP_UI_SIZE
	minimap_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	minimap_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap_rect.texture = _minimap_texture
	minimap_rect.gui_input.connect(_on_minimap_gui_input)
	var minimap_border = StyleBoxFlat.new()
	minimap_border.bg_color = Color(0, 0, 0, 0)
	minimap_border.border_color = Color(0.20, 0.60, 0.85, 0.90)
	minimap_border.border_width_left = 2
	minimap_border.border_width_right = 2
	minimap_border.border_width_top = 2
	minimap_border.border_width_bottom = 2
	var minimap_frame = PanelContainer.new()
	minimap_frame.anchor_left = minimap_rect.anchor_left
	minimap_frame.anchor_right = minimap_rect.anchor_right
	minimap_frame.anchor_top = minimap_rect.anchor_top
	minimap_frame.anchor_bottom = minimap_rect.anchor_bottom
	minimap_frame.offset_left = minimap_rect.offset_left - 2
	minimap_frame.offset_right = minimap_rect.offset_right + 2
	minimap_frame.offset_top = minimap_rect.offset_top - 2
	minimap_frame.offset_bottom = minimap_rect.offset_bottom + 2
	minimap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_frame.add_theme_stylebox_override("panel", minimap_border)
	ui.add_child(minimap_frame)
	ui.add_child(minimap_rect)

	_update_resource_ui()

# RTS_CORE_ROADMAP.md A2: the debug/options panel. Reuses the Menu button's
# own chrome (menu_style/menu_hover) so it doesn't read as a bolted-on debug
# hack sitting next to a designed HUD. A CheckBox per toggle, each writing
# straight to this skirmish instance's own debug_* var (so the effect is
# immediate - no "apply" step) and, if the DebugSettings autoload is present,
# also back to it so the choice survives a match restart.
func _build_debug_panel(ui: CanvasLayer, menu_style: StyleBoxFlat, menu_hover: StyleBoxFlat):
	var debug_btn = Button.new()
	debug_btn.text = " Debug"
	debug_btn.icon = UIIcons.get_icon("gear")
	debug_btn.expand_icon = true
	debug_btn.anchor_left = 1.0
	debug_btn.anchor_right = 1.0
	debug_btn.offset_left = -95
	debug_btn.offset_right = -10
	debug_btn.offset_top = 14
	debug_btn.offset_bottom = 54
	debug_btn.add_theme_stylebox_override("normal", menu_style)
	debug_btn.add_theme_stylebox_override("hover", menu_hover)
	ui.add_child(debug_btn)

	var popup = PopupPanel.new()
	popup.name = "DebugPanel"
	ui.add_child(popup)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	popup.add_child(box)

	var title = Label.new()
	title.text = "Debug Toggles"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	box.add_child(_make_debug_checkbox("Infinite resources (player)", debug_infinite_resources,
		func(pressed: bool):
			debug_infinite_resources = pressed
			var ds = get_node_or_null("/root/DebugSettings")
			if ds and "infinite_player_resources" in ds:
				ds.infinite_player_resources = pressed
			if pressed:
				economy[PLAYER_TEAM].metal = INFINITE_RESOURCE_FLOOR
				economy[PLAYER_TEAM].crystal = INFINITE_RESOURCE_FLOOR
				_update_resource_ui()))

	box.add_child(_make_debug_checkbox("Reveal all fog", debug_reveal_all_fog,
		func(pressed: bool):
			debug_reveal_all_fog = pressed
			var ds = get_node_or_null("/root/DebugSettings")
			if ds and "reveal_all_fog" in ds:
				ds.reveal_all_fog = pressed))

	box.add_child(_make_debug_checkbox("Instant build", debug_instant_build,
		func(pressed: bool):
			debug_instant_build = pressed
			var ds = get_node_or_null("/root/DebugSettings")
			if ds and "instant_build" in ds:
				ds.instant_build = pressed))

	debug_btn.pressed.connect(func():
		popup.position = debug_btn.global_position + Vector2(0, 44)
		popup.popup())

# RTS_CORE_ROADMAP.md D2: 3 hand-rolled tab buttons (matching this project's
# existing collapsible-drawer style rather than Godot's built-in
# TabContainer, which fights the brushed-panel chrome everything else here
# uses) switching which of build_tab_containers is visible.
func _build_tab_bar(parent: Container) -> void:
	var tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	parent.add_child(tab_bar)
	for tab_name in ["structures", "defenses", "units"]:
		var btn = Button.new()
		btn.text = tab_name.capitalize()
		btn.custom_minimum_size = Vector2(90, 26)
		btn.toggle_mode = true
		btn.button_pressed = (tab_name == active_build_tab)
		btn.pressed.connect(func(): _set_active_build_tab(tab_name))
		tab_bar.add_child(btn)
		build_tab_buttons[tab_name] = btn

func _set_active_build_tab(tab_name: String) -> void:
	active_build_tab = tab_name
	for name in build_tab_containers.keys():
		# Toggle the PARENT ScrollContainer, not the HBoxContainer itself
		# (build_tab_containers holds the inner box - see _build_ui()'s own
		# comment on why each tab needs its own ScrollContainer).
		build_tab_containers[name].get_parent().visible = (name == tab_name)
	for name in build_tab_buttons.keys():
		build_tab_buttons[name].button_pressed = (name == tab_name)

# RTS_CORE_ROADMAP.md D2: 4 tier strips (light/medium/heavy/structures - D4
# adds the 4th), each a progress fill + READY/HOLD/timer text over the
# FRONT item of that team+tier queue (production_queue.gd only ever ticks
# the front item - matches everywhere else in this game that already
# assumes FIFO-front-only). Right-click pauses; a SECOND right-click (while
# already paused) cancels and refunds. Kept simple: one shared strip per
# tier regardless of how many manufactories of that tier are alive, since
# the queue itself is already shared per team+tier (RTS_CORE_ROADMAP.md A1).
func _build_queue_panel(parent: Container) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	for tier in ["light", "medium", "heavy", "structures"]:
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(160, 30)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.11, 0.14, 0.85)
		style.border_color = Color(0.3, 0.35, 0.4, 0.9)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		panel.add_theme_stylebox_override("panel", style)
		row.add_child(panel)

		var bar = ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = 0.0
		bar.show_percentage = false
		panel.add_child(bar)

		var label = Label.new()
		label.text = "%s: —" % tier.capitalize()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)

		queue_strips[tier] = {"panel": panel, "bar": bar, "status_label": label}
		panel.gui_input.connect(func(event): _on_queue_strip_input(tier, event))

func _on_queue_strip_input(tier: String, event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	var q = production.get_queue(PLAYER_TEAM, tier)
	if q.is_empty():
		return
	if q[0].get("paused", false):
		# Second right-click while already paused: cancel and refund.
		production.cancel(PLAYER_TEAM, tier, 0)
	else:
		production.set_paused(PLAYER_TEAM, tier, true)

# RTS_CORE_ROADMAP.md D2: OpenRA-style state computed straight off the
# front job - waiting = not producing and not done. "producing" needs the
# job's own stalled flag (production_queue.gd's tick() sets it whenever a
# tick made zero progress, whether from a manual pause or being broke -
# READY/HOLD text can't tell those apart from time_left/total_time alone).
func _update_queue_panel() -> void:
	for tier in queue_strips.keys():
		var strip = queue_strips[tier]
		var q = production.get_queue(PLAYER_TEAM, tier)
		if q.is_empty():
			strip.bar.value = 0.0
			strip.status_label.text = "%s: —" % tier.capitalize()
			continue
		var job = q[0]
		var done = job.time_left <= 0.0
		var stalled = job.get("stalled", false)
		strip.bar.value = 1.0 if done else clampf(1.0 - (job.time_left / max(0.001, job.total_time)), 0.0, 1.0)
		if done:
			strip.status_label.text = "%s: READY" % tier.capitalize()
		elif stalled:
			strip.status_label.text = "%s: HOLD%s" % [tier.capitalize(), " (paused)" if job.get("paused", false) else ""]
		else:
			strip.status_label.text = "%s: %.1fs" % [tier.capitalize(), job.time_left]

# RTS_CORE_ROADMAP.md D2: greys out (Button.disabled) every unit button
# whose tier has no live manufactory - previously only a status flash AFTER
# a doomed click, per this chunk's own note.
func _refresh_tier_gated_buttons() -> void:
	for entry in _tier_gated_buttons:
		if is_instance_valid(entry.button):
			entry.button.disabled = not has_factory_of_tier(PLAYER_TEAM, entry.tier)

func _make_debug_checkbox(label_text: String, initial: bool, on_toggled: Callable) -> CheckBox:
	var cb = CheckBox.new()
	cb.text = label_text
	cb.button_pressed = initial
	cb.toggled.connect(on_toggled)
	return cb

func _add_build_button(parent: Container, text: String, color: Color, callback: Callable) -> Button:
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
	# RTS_CORE_ROADMAP.md D2: greyed-out look for _refresh_tier_gated_buttons()
	# to switch to when this button's tier has no live manufactory - a real
	# distinct look (disabled state + dimmed stylebox), not just the old
	# after-the-fact status flash.
	var disabled_style = style.duplicate()
	disabled_style.bg_color = color.darkened(0.5)
	btn.add_theme_stylebox_override("disabled", disabled_style)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _update_resource_ui():
	if resource_label:
		resource_label.text = "💰 Metal: %d   💎 Crystal: %d" % [economy[PLAYER_TEAM].metal, economy[PLAYER_TEAM].crystal]
	# RTS_CORE_ROADMAP.md E1: a real power bar, replacing the old single
	# "(DEFICIT: builds slower!)" status string - "Base Power" wording kept
	# (FABLE_REVIEW.md 3.9/1.6: this is the BASE's power only, never a
	# vehicle's own onboard energy budget). Fill/color/text all reflect the
	# real 3-state PowerManager (_recalc_energy_economy()), not just a
	# binary deficit flag.
	if power_bar and power_status_label:
		var e = energy_pool[PLAYER_TEAM]
		var state: String = e.get("power_state", "normal")
		var upkeep: float = e.get("upkeep", 0.0)
		# The bar shows drained-vs-provided (upkeep-vs-capacity) - what
		# actually drives Normal/Low/Critical - not the floored "energy"
		# margin, which can't go negative and would hide how deep a
		# Critical deficit really is.
		power_bar.value = clampf(1.0 - (upkeep / max(e.capacity, 1.0)), 0.0, 1.0) if e.capacity > 0.0 else 0.0
		var state_color = Color(0.35, 0.85, 0.4) if state == "normal" else (Color(0.9, 0.75, 0.2) if state == "low" else Color(0.9, 0.3, 0.25))
		var fill_style = StyleBoxFlat.new()
		fill_style.bg_color = state_color
		power_bar.add_theme_stylebox_override("fill", fill_style)
		power_status_label.text = "⚡ Base Power: %s" % state.capitalize()

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
	# Size-tiered manufactories: which building this design can be queued
	# from depends on its own hull's weight tier, not domain - a design on
	# heavy_cruiser_hull needs a Heavy Manufactory exactly like one on
	# heavy_hull would. Tier resolve, legality, drip-fed cost, and build-time
	# all now live in production.enqueue() - the same path enemy_ai.gd's
	# producer calls through (RTS_CORE_ROADMAP.md A1).
	#
	# RTS_CORE_ROADMAP.md D1: no "cant_afford" branch here anymore - queuing
	# no longer requires the full cost banked up front (see enqueue()'s own
	# comment); a build that can't afford its next tick's draw pauses
	# in-place instead of being rejected at queue time.
	var result = production.enqueue(PLAYER_TEAM, entry.blueprint, player_faction, entry.cost_metal, entry.cost_crystal)
	if not result.queued:
		match result.error:
			"no_factory":
				_flash_status("Need a %s Manufactory to build %s!" % [result.tier.capitalize(), entry.name])
			"illegal":
				_flash_status("%s can't be built: %s" % [entry.name, result.reason])
		return
	_flash_status("Building %s... (low power, slower build)" % entry.name if is_energy_deficit(PLAYER_TEAM) else "Building %s..." % entry.name)

# --- Building placement ---

# RTS_CORE_ROADMAP.md D4: the structures-tier analogue of _queue_player_unit()
# above - clicking a Structures/Defenses button queues a real drip-fed build
# instead of starting ghost placement immediately. Once production.
# pop_ready_structure() reports it done (checked every physics tick, see
# _physics_process()), _begin_placement() runs automatically - same
# real-money-already-spent ghost the player used to get instantly.
func _queue_structure_build(info: Dictionary) -> void:
	if game_over: return
	var result = production.enqueue_structure(PLAYER_TEAM, info)
	if not result.queued:
		_flash_status("Can't build this: %s" % result.reason)
		return
	_flash_status("Constructing...")

func _begin_placement(info: Dictionary):
	if game_over: return
	# RTS_CORE_ROADMAP.md D4: no legality/afford gate here anymore - both
	# already happened at production.enqueue_structure() time, before the
	# build even started drip-feeding cost. By the time this runs (auto-
	# triggered once that job is done), it's already fully paid for.
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
	mat.albedo_color = GHOST_COLOR_VALID
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	placement_ghost.material_override = mat
	add_child(placement_ghost)

	# Range preview ring (audit #19): a defense building's real threat radius
	# depends on its armed weapons' fire_range, which itself depends on
	# per-weapon tweaks (barrel_length, caliber, etc. - see auto_weapon.gd)
	# and can't be read off the catalog alone. Rather than duplicate that
	# formula (and risk it drifting out of sync), reconstruct the actual
	# vehicle off to the side just long enough to arm its weapons and read
	# their real fire_range, exactly like building.gd's setup_defense()
	# does for a real placed defense - then discard it. Only costs one
	# reconstruct per placement-start, not per frame.
	if info.kind == "defense":
		var range_preview = 0.0
		# Player-only placement flow - match_faction is always player_faction
		# here, same override reasoning as spawn_defense() below.
		var temp_hull = bp_manager.reconstruct_vehicle(info.blueprint, self, false, player_faction)
		if temp_hull:
			for child in temp_hull.get_children():
				if child.has_meta("module_data"):
					var data = child.get_meta("module_data")
					if ModuleCatalog.needs_combat_script(data.type_id):
						child.set_script(load("res://scripts/auto_weapon.gd"))
						child._ready()
						if "fire_range" in child:
							range_preview = max(range_preview, child.fire_range * 0.85)
			temp_hull.queue_free()
		if range_preview > 0.0:
			var ring = MeshInstance3D.new()
			var torus = TorusMesh.new()
			torus.inner_radius = max(range_preview - 0.3, 0.1)
			torus.outer_radius = range_preview
			ring.mesh = torus
			ring.position = Vector3(0, -box.size.y / 2.0 + 0.05, 0)
			var ring_mat = StandardMaterial3D.new()
			ring_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
			ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ring.material_override = ring_mat
			placement_ghost.add_child(ring)

	_show_buildable_area_decals()

# RTS_CORE_ROADMAP.md C3: "render the union as a translucent ground decal
# so the rule is visible instead of guessed at." One flat disc per friendly
# building that gives_buildable_area, radius'd out to that building's own
# adjacent_m plus its footprint's own half-diagonal - a circle is a
# deliberately conservative (slightly generous at the corners) stand-in for
# the true rounded-rectangle zone _footprint_gap() actually checks, same
# "continuous AABBs, not a precise per-tile grid" simplification this whole
# chunk already leans on.
var _buildable_area_decals: Array = []

func _show_buildable_area_decals() -> void:
	if not _placing_requires_buildable_area():
		return
	# The reach is a property of whatever's currently being PLACED (see
	# _placing_adjacent_m()'s own comment) - one shared value for every
	# anchor's decal this placement session, not a per-building radius.
	var reach = _placing_adjacent_m()
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.is_dead or b.team != PLAYER_TEAM: continue
		if not ("gives_buildable_area" in b and b.gives_buildable_area): continue
		var b_fp: Vector3 = b.footprint if "footprint" in b else Vector3(5, 3, 5)
		var radius = reach + Vector2(b_fp.x, b_fp.z).length() / 2.0
		var decal = MeshInstance3D.new()
		var disc = CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = 0.05
		decal.mesh = disc
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.85, 1.0, 0.12)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		decal.material_override = mat
		add_child(decal)
		decal.global_position = Vector3(b.global_position.x, terrain_height_at(b.global_position) + 0.05, b.global_position.z)
		_buildable_area_decals.append(decal)

func _clear_buildable_area_decals() -> void:
	for d in _buildable_area_decals:
		if is_instance_valid(d):
			d.queue_free()
	_buildable_area_decals.clear()

func _cancel_placement():
	placing = {}
	if is_instance_valid(placement_ghost):
		placement_ghost.queue_free()
	placement_ghost = null
	_clear_buildable_area_decals()

# RTS_CORE_ROADMAP.md's own flagged gap, fixed: by the time a structure's
# ghost is up, production.enqueue_structure()'s drip-fed cost is already
# 100% drawn (that's what "ready to place" means - see pop_ready_structure()'s
# comment). _cancel_placement() itself is shared with the post-success
# cleanup path in _try_place_building() (placement went fine, cost should
# stay spent) - so the refund lives in this separate wrapper, called only
# from the two genuine abandon paths (Escape, right-click-while-placing).
# Refunds the full amount actually paid (placing.cost_metal/cost_crystal,
# the same fields enqueue_structure() charged from); defense ghosts carry
# the same two fields (see _begin_placement's info dict shape), so this
# covers both kinds uniformly.
func _abandon_placement():
	if not placing.is_empty() and placing.has("cost_metal"):
		add_resources(PLAYER_TEAM, placing.cost_metal, placing.cost_crystal)
		_flash_status("Placement cancelled - refunded %dM/%dC" % [placing.cost_metal, placing.cost_crystal])
	_cancel_placement()

# Shared by both the live ghost-color check (every mouse-move while
# placing) and the actual placement attempt, so the two can never
# disagree - position-dependent rules only (terrain/base-proximity), not
# affordability, which doesn't change as the mouse moves and is checked
# separately at _begin_placement/_try_place_building time.
# RTS_CORE_ROADMAP.md C2: 2m lattice over a footprint's XZ rect, edge-to-edge
# inclusive (OpenRA's CanPlaceBuilding = Tiles.All(IsCellBuildable), the
# continuous-3D equivalent of walking every tile a building would occupy).
# center.y is carried through unchanged - only x/z vary, since every real
# check this feeds (bounds/is_position_blocked/resource overlap) is an XZ
# footprint test.
const PLACEMENT_LATTICE: float = 2.0

func _footprint_samples(center: Vector3, footprint: Vector3) -> Array:
	var samples: Array = []
	var half_x = footprint.x / 2.0
	var half_z = footprint.z / 2.0
	var steps_x = max(1, int(ceil((half_x * 2.0) / PLACEMENT_LATTICE)))
	var steps_z = max(1, int(ceil((half_z * 2.0) / PLACEMENT_LATTICE)))
	for iz in range(steps_z + 1):
		var z = center.z - half_z + (half_z * 2.0) * iz / steps_z
		for ix in range(steps_x + 1):
			var x = center.x - half_x + (half_x * 2.0) * ix / steps_x
			samples.append(Vector3(x, center.y, z))
	return samples

func _placement_validity(pos: Vector3) -> Dictionary:
	return _placement_validity_for(PLAYER_TEAM, pos, _placing_footprint(), _placing_requires_buildable_area(), _placing_adjacent_m())

# RTS_CORE_ROADMAP.md 1.3: the actual legality body, pulled out from behind
# the player's `placing` ghost state so the enemy AI can ask the identical
# question for its own team/kind (rebuilding a destroyed manufactory, siting
# a power plant) without a ghost mesh or decals ever existing. `_placement_
# validity()` above is now a thin PLAYER_TEAM-flavored wrapper over this.
func _placement_validity_for(team: int, pos: Vector3, new_footprint: Vector3, requires_area: bool, placing_reach: float) -> Dictionary:
	var half: float = current_map.get("map_half_extents", 80.0)

	# RTS_CORE_ROADMAP.md C2: sample the WHOLE footprint, not just the
	# center point - previously a large building's center could sit on
	# legal ground while a corner overhung water, a cliff-steep slope
	# (meaningful post-B5's heightmaps), or even the map edge, entirely
	# unchecked. Map-bounds and terrain-blocked (water/obstacles/over-slope,
	# matching OpenRA's "buildings never on ramps" rule) both fold into
	# this one lattice walk now instead of a single center-point check.
	for sample in _footprint_samples(pos, new_footprint):
		if abs(sample.x) > half or abs(sample.z) > half:
			return {"valid": false, "reason": "Outside the map boundary!"}
		if TerrainBuilder.is_position_blocked(current_map, sample):
			return {"valid": false, "reason": "Can't build on water, terrain obstacles, or a steep slope!"}

	# Resource-node exclusion - a harvestable node isn't buildable ground
	# (OpenRA-style; nothing previously stopped a building from being
	# dropped directly on top of one).
	for r in current_map.get("resource_nodes", []):
		if abs(r.position.x - pos.x) < new_footprint.x / 2.0 and abs(r.position.z - pos.z) < new_footprint.z / 2.0:
			return {"valid": false, "reason": "Can't build on top of a resource node!"}

	# RTS_CORE_ROADMAP.md C3: buildable-area adjacency - the substance of
	# OpenRA's IsCloseEnoughToBase, measured footprint-to-footprint (the
	# real gap between the two buildings' AABBs) instead of center-to-
	# center. The reach is a property of WHATEVER'S BEING PLACED (OpenRA's
	# per-building-type Adjacent rule) - a defense's own much longer leash
	# (28m) is what lets it ring the outside of a base, not a bigger zone
	# radiated by existing buildings. Only friendly (same-`team`) buildings
	# that GIVE buildable area count as anchors to measure against (a ring
	# of defenses shouldn't let the base spiral outward indefinitely - a
	# defense itself never anchors a further placement). Clear of any OTHER
	# team's zone stays a plain center-to-center check - a denial radius,
	# not a buildable-area rule.
	var near_base = not requires_area
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.is_dead: continue
		# XZ footprint overlap against every existing building, any team -
		# a small 0.5 clearance margin so buildings can't visually kiss.
		var b_fp: Vector3 = b.footprint if "footprint" in b else Vector3(5, 3, 5)
		var dx = abs(b.global_position.x - pos.x)
		var dz = abs(b.global_position.z - pos.z)
		if dx < (b_fp.x + new_footprint.x) / 2.0 + 0.5 and dz < (b_fp.z + new_footprint.z) / 2.0 + 0.5:
			return {"valid": false, "reason": "Blocked by another building!"}
		if b.team == team:
			if not near_base and "gives_buildable_area" in b and b.gives_buildable_area:
				if _footprint_gap(b.global_position, b_fp, pos, new_footprint) <= placing_reach:
					near_base = true
		elif b.global_position.distance_to(pos) < 20.0:
			return {"valid": false, "reason": "Too close to enemy territory!"}
	if not near_base:
		return {"valid": false, "reason": "Too far from your base!"}
	return {"valid": true, "reason": ""}

# Real gap between two XZ footprint AABBs (0 if overlapping or touching),
# not a center-to-center distance.
func _footprint_gap(a_center: Vector3, a_footprint: Vector3, b_center: Vector3, b_footprint: Vector3) -> float:
	var dx = max(0.0, abs(a_center.x - b_center.x) - (a_footprint.x + b_footprint.x) / 2.0)
	var dz = max(0.0, abs(a_center.z - b_center.z) - (a_footprint.z + b_footprint.z) / 2.0)
	return Vector2(dx, dz).length()

# Whether whatever's currently `placing` needs to be within someone's
# buildable-area zone at all (everything does today - see PREFAB_STATS/
# setup_defense() - but this is a real field, not a hardcoded true, so a
# future building type could opt out without new branching here).
func _placing_requires_buildable_area() -> bool:
	if placing.is_empty():
		return true
	if placing.kind == "defense":
		return true
	return BuildingScript.PREFAB_STATS[placing.kind].get("requires_buildable_area", true)

# How far whatever's currently `placing` is allowed to be from the nearest
# gives_buildable_area anchor - a property of the THING BEING PLACED
# (OpenRA's per-building-type Adjacent), not of whatever it's being measured
# against. Defenses get the long 28m leash; every prefab kind defaults to
# 8.0 via PREFAB_STATS.
func _placing_adjacent_m() -> float:
	if placing.is_empty():
		return BuildingScript.DEFAULT_ADJACENT_M
	if placing.kind == "defense":
		return BuildingScript.DEFENSE_ADJACENT_M
	return BuildingScript.PREFAB_STATS[placing.kind].get("adjacent_m", BuildingScript.DEFAULT_ADJACENT_M)

# RTS_CORE_ROADMAP.md C2: OpenRA's ClearBlockersOrders, continuous-3D style -
# a unit standing where a building is about to spawn gets physically shoved
# clear instead of the placement failing outright (matches this project's
# own "simplify vs OpenRA" call for C2: no discrete tiles/BuildingInfluence
# layer needed, just an AABB and a straight teleport). Only the PLAYER's own
# units get shoved - this only ever runs from the player's own placement
# flow, and an enemy unit standing on the spot is contested ground, not "in
# the way."
func _shove_blockers_clear(center: Vector3, footprint: Vector3) -> void:
	var half_x = footprint.x / 2.0 + 1.0
	var half_z = footprint.z / 2.0 + 1.0
	for u in get_team_units(PLAYER_TEAM):
		if not is_instance_valid(u): continue
		var dx = u.global_position.x - center.x
		var dz = u.global_position.z - center.z
		if abs(dx) >= half_x or abs(dz) >= half_z: continue
		# Push out along whichever axis needs the shorter nudge.
		if half_x - abs(dx) < half_z - abs(dz):
			u.global_position.x = center.x + half_x * (1.0 if dx >= 0.0 else -1.0)
		else:
			u.global_position.z = center.z + half_z * (1.0 if dz >= 0.0 else -1.0)

# Footprint of the building currently being placed (ghost/click validity).
func _placing_footprint() -> Vector3:
	if placing.is_empty():
		return Vector3(5, 3, 5)
	if placing.kind == "defense":
		var hull_data = ModuleCatalog.get_module_data(placing.blueprint.get("hull_type", "pillbox_foundation"))
		return hull_data.size
	return BuildingScript.PREFAB_STATS[placing.kind].size

# RTS_CORE_ROADMAP.md 1.3: enemy_ai.gd never placed a building - the base
# was pre-placed complete at match start and stayed that way, so a killed
# manufactory was gone for the rest of the match and Phase C/D/E's placement
# legality/adjacency/build-time work was entirely player-only. This finds a
# legal spot for the AI's own structures queue to land on, searching an
# expanding ring of candidate points around the team's HQ (or, failing that,
# any live building of theirs) rather than anything scripted per-map - the
# same _placement_validity_for() the player's own ghost placement uses, so
# the AI is held to the identical rules (buildable-area adjacency, terrain,
# resource-node exclusion) instead of a separate, looser one.
const AI_BUILD_SEARCH_RADII: Array = [10.0, 16.0, 22.0, 30.0, 40.0, 55.0]
const AI_BUILD_ANGLE_STEPS: int = 10

func _find_ai_build_position(team: int, footprint: Vector3, requires_area: bool, adjacent_m: float) -> Vector3:
	var anchor: Node = _get_slot(team).get("hq")
	var anchor_pos: Vector3
	if is_instance_valid(anchor):
		anchor_pos = anchor.global_position
	else:
		var buildings = get_team_buildings(team)
		if buildings.is_empty():
			return Vector3.INF
		anchor_pos = buildings[0].global_position
	for radius in AI_BUILD_SEARCH_RADII:
		for i in range(AI_BUILD_ANGLE_STEPS):
			var angle = TAU * i / AI_BUILD_ANGLE_STEPS
			var candidate = anchor_pos + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			candidate.y = terrain_height_at(candidate)
			if _placement_validity_for(team, candidate, footprint, requires_area, adjacent_m).valid:
				return candidate
	return Vector3.INF

# Places a job popped off `team`'s own structures queue - the AI-side
# analogue of _try_place_building(), minus the ghost/decal UI (nothing to
# show, nobody watching) and _shove_blockers_clear() (that only ever shoves
# the PLAYER's own units, by design - see its own comment; an AI structure
# landing where an enemy unit stands would need a very different call, and
# _find_ai_build_position()'s legality search already keeps it off any
# building's footprint regardless).
func _place_ai_structure(team: int, info: Dictionary) -> void:
	var footprint: Vector3
	var adjacent_m: float
	var requires_area: bool
	var faction: String = enemy_faction if team == ENEMY_TEAM else player_faction
	if info.kind == "defense":
		var hull_data = ModuleCatalog.get_module_data(info.blueprint.get("hull_type", "pillbox_foundation"))
		footprint = hull_data.size
		adjacent_m = BuildingScript.DEFENSE_ADJACENT_M
		requires_area = true
	else:
		var stats = BuildingScript.PREFAB_STATS[info.kind]
		footprint = stats.size
		adjacent_m = stats.get("adjacent_m", BuildingScript.DEFAULT_ADJACENT_M)
		requires_area = stats.get("requires_buildable_area", true)
	var pos = _find_ai_build_position(team, footprint, requires_area, adjacent_m)
	if pos == Vector3.INF:
		# No legal spot found anywhere in the search ring - refund rather
		# than silently eat the AI's own drip-fed cost for nothing.
		add_resources(team, info.cost_metal, info.cost_crystal)
		return
	var b: StaticBody3D
	if info.kind == "defense":
		b = spawn_defense(info.blueprint, team, pos)
	else:
		b = _spawn_prefab(info.kind, team, pos, faction)
		b.bp_manager = bp_manager
	b.start_construction_animation()

func _try_place_building(pos: Vector3):
	if placing.is_empty(): return
	var validity = _placement_validity(pos)
	if not validity.valid:
		_flash_status(validity.reason)
		return
	# RTS_CORE_ROADMAP.md D4: cost is already fully paid by now - drip-fed
	# over the real build time production.enqueue_structure() queued this
	# under, not spent here. _try_place_building() only ever runs on
	# something production.pop_ready_structure() already popped as done.
	_shove_blockers_clear(pos, _placing_footprint())
	var b: StaticBody3D
	if placing.kind == "defense":
		b = spawn_defense(placing.blueprint, PLAYER_TEAM, pos)
	else:
		b = _spawn_prefab(placing.kind, PLAYER_TEAM, pos, player_faction)
		b.bp_manager = bp_manager
	# RTS_CORE_ROADMAP.md D4: "buildings never auto-exit" - real
	# construction time (scale-up tween + weapons/production/energy
	# disabled) for anything the PLAYER places live, unlike the starting
	# bases (_spawn_bases()), which spawn complete and skip this entirely.
	b.start_construction_animation()
	_cancel_placement()

# --- Input: selection & orders ---

func _unhandled_input(event):
	if game_over: return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_abandon_placement()
		_set_selection([])
		return

	if event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var group_num = event.keycode - KEY_1 + 1
		if event.ctrl_pressed:
			_assign_control_group(group_num)
		else:
			_recall_control_group(group_num)
		return

	if event is InputEventMouseMotion:
		_update_hover_cursor(event.position)
		if not placing.is_empty() and is_instance_valid(placement_ghost):
			var hit = _raycast_ground(event.position)
			if hit != null:
				var ground_y = terrain_height_at(hit)
				placement_ghost.global_position = Vector3(hit.x, ground_y + placement_ghost.mesh.size.y / 2.0, hit.z)
				# Live validity color - same _placement_validity() check the
				# actual click uses, so the ghost never shows green over a
				# spot that would then reject the click.
				var validity = _placement_validity(placement_ghost.global_position)
				placement_ghost.material_override.albedo_color = GHOST_COLOR_VALID if validity.valid else GHOST_COLOR_INVALID
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
					_select_in_rect(Rect2(drag_select_start, event.position - drag_select_start).abs(), event.shift_pressed)
				else:
					_select_at_point(event.position, event.shift_pressed)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not placing.is_empty():
			_abandon_placement()
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
	if not selected.is_empty() and get_node_or_null("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("select")
	for s in selected:
		if is_instance_valid(s) and s.has_method("set_selected"):
			s.set_selected(true)

# Ctrl+1-9 assigns the current selection to a slot, overwriting whatever was
# there before (standard RTS convention - no additive group-assign).
func _assign_control_group(num: int) -> void:
	if selected.is_empty():
		return
	control_groups[num] = selected.duplicate()
	_flash_status("Control group %d set (%d units)" % [num, selected.size()])

# 1-9 recalls a slot, filtering dead/freed members at read time rather than
# eagerly pruning on death (see control_groups' declaration comment).
# Pressing the same digit twice within CONTROL_GROUP_DOUBLE_TAP_MS also
# recenters the camera on the group, matching OpenRA/RA2 convention.
func _recall_control_group(num: int) -> void:
	if not control_groups.has(num):
		return
	var alive = []
	for u in control_groups[num]:
		if is_instance_valid(u):
			alive.append(u)
	control_groups[num] = alive
	if alive.is_empty():
		return
	_set_selection(alive)

	var now_ms = Time.get_ticks_msec()
	var double_tap = num == _last_group_recall_num and (now_ms - _last_group_recall_time_ms) <= CONTROL_GROUP_DOUBLE_TAP_MS
	_last_group_recall_num = num
	_last_group_recall_time_ms = now_ms
	if double_tap:
		var center = Vector3.ZERO
		for u in alive:
			center += u.global_position
		center /= alive.size()
		camera.global_position.x = center.x
		camera.global_position.z = center.z

func _select_at_point(screen_pos: Vector2, additive: bool = false):
	var result = _raycast_screen(screen_pos, 4 + 8)
	if result and result.collider:
		var node = result.collider
		if node.is_in_group("units") or node.is_in_group("buildings"):
			if node.get("team") == PLAYER_TEAM:
				if additive:
					# Shift-clicking an already-selected unit deselects just
					# that unit (standard RTS convention), otherwise adds it.
					var merged = selected.duplicate()
					if merged.has(node):
						merged.erase(node)
					else:
						merged.append(node)
					_set_selection(merged)
				else:
					_set_selection([node])
				return
	if not additive:
		_set_selection([])

func _select_in_rect(rect: Rect2, additive: bool = false):
	var picked = selected.duplicate() if additive else []
	for u in get_team_units(PLAYER_TEAM):
		var screen = camera.unproject_position(u.global_position)
		if rect.has_point(screen) and not picked.has(u):
			picked.append(u)
	_set_selection(picked)

func _update_hover_cursor(screen_pos: Vector2) -> void:
	var cm = get_node_or_null("/root/CursorManager")
	if not cm:
		return
	if not placing.is_empty():
		cm.set_cursor(cm.CursorType.BUILD)
		return
	if selected.is_empty():
		cm.set_cursor(cm.CursorType.DEFAULT)
		return
	var result = _raycast_screen(screen_pos, 4 + 8 + 16)
	if result and result.collider:
		var node = result.collider
		if node.is_in_group("resource_nodes"):
			var can_harvest = false
			for s in selected:
				if is_instance_valid(s) and "is_harvester" in s and s.is_harvester:
					can_harvest = true
					break
			cm.set_cursor(cm.CursorType.HARVEST if can_harvest else cm.CursorType.INVALID)
			return
		var node_fog_hidden = "fog_hidden" in node and node.fog_hidden
		if (node.is_in_group("units") or node.is_in_group("buildings")) and node.get("team") != PLAYER_TEAM and not node_fog_hidden:
			cm.set_cursor(cm.CursorType.ATTACK)
			return
	if _raycast_ground(screen_pos) != null:
		cm.set_cursor(cm.CursorType.MOVE)
	else:
		cm.set_cursor(cm.CursorType.DEFAULT)

# RTS_CORE_ROADMAP.md C4: manufactories a player has selected and
# right-clicked ground for - replaces building.gd:168's old hardcoded ±10z
# rally_point default with a real settable one.
func _selected_manufactories() -> Array:
	var result: Array = []
	for s in selected:
		if is_instance_valid(s) and "kind" in s and s.kind in BuildingScript.MANUFACTORY_KINDS:
			result.append(s)
	return result

func _issue_order(screen_pos: Vector2):
	if selected.is_empty(): return
	if get_node_or_null("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("select", 0.15)

	var manufactories = _selected_manufactories()
	if not manufactories.is_empty():
		var rally_ground = _raycast_ground(screen_pos)
		if rally_ground != null:
			for m in manufactories:
				m.rally_point = rally_ground
			_spawn_order_marker(rally_ground, Color.GOLD)
		return

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
		# Fog gate (FABLE_REVIEW.md 3.9): a fog-hidden enemy keeps its collision
		# layers (only rendering is toggled), so without this check a player
		# could right-click-sweep through unexplored fog and use the red attack
		# marker as a free wallhack to find unscouted units. An unseen enemy
		# under the cursor is treated exactly like empty ground.
		var node_fog_hidden = "fog_hidden" in node and node.fog_hidden
		if (node.is_in_group("units") or node.is_in_group("buildings")) and node.get("team") != PLAYER_TEAM and not node_fog_hidden:
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
	# Alliance-aware win condition (RTS_CORE_ROADMAP.md B2): "one alliance
	# remains," not "first HQ dies loses" - a dead HQ only actually ends
	# the match once its whole alliance has zero living HQs left. With no
	# allies configured (the default 2-team case), every team's alliance
	# is just itself, so this reduces to the exact old 1-HQ-per-side
	# behavior: the losing team's dead HQ immediately empties its own
	# (singleton) alliance.
	var alive_alliances = _alliances_with_living_hq()
	if alive_alliances.size() > 1:
		return
	game_over = true
	var victory = not alive_alliances.is_empty() and _local_team() in alive_alliances[0]
	if get_node_or_null("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("victory" if victory else "defeat")
	var ui = get_node_or_null("UI")
	if not ui: return

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)

	# A framed card behind the text/button, not just text floating on the
	# dimmed overlay - the same "real panel chrome, not bare Controls"
	# upgrade the rest of the UI polish pass applied elsewhere.
	var card = PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.12, 0.14, 0.92)
	card_style.border_color = Color.GOLD if victory else Color(0.7, 0.2, 0.2)
	card_style.border_width_left = 3
	card_style.border_width_top = 3
	card_style.border_width_right = 3
	card_style.border_width_bottom = 3
	card_style.corner_radius_top_left = 10
	card_style.corner_radius_top_right = 10
	card_style.corner_radius_bottom_left = 10
	card_style.corner_radius_bottom_right = 10
	card_style.content_margin_left = 40
	card_style.content_margin_right = 40
	card_style.content_margin_top = 30
	card_style.content_margin_bottom = 30
	card.add_theme_stylebox_override("panel", card_style)
	overlay.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

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
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.3, 0.32, 0.36)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.3, 0.32, 0.36).lightened(0.2)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	vbox.add_child(btn)
