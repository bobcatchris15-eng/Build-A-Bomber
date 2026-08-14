extends Node3D
# The match. Composition and nothing else.
#
# THE POINT OF THIS FILE IS ITS LENGTH. The system it replaces, skirmish.gd, is
# 3,423 lines because it owns the economy ledger, fog of war, the minimap image,
# the HUD, unit selection, building placement, navmesh rebaking, energy
# bookkeeping and the win condition all at once. Nothing there can be tested,
# reused or replaced without dragging in the rest.
#
# So the rule for this file: it assembles the world, holds references to the
# services, and forwards input. Any logic that could be asked a question in
# isolation belongs in a service. If this file passes ~400 lines, something has
# been put in the wrong place.
#
# DUCK-TYPED CONTRACTS. Units find their navmesh and their ground height by
# calling methods on their controller if it has them:
#
#     get_ground_nav_map() / get_water_nav_map()
#     get_amphibious_nav_map() / get_deep_water_nav_map()
#     terrain_height_at() / get_surface_type_at()
#
# The same six the old runtime exposed, with the same names, on purpose. It is
# what lets a unit built standalone in a test get no navmesh and fall back to
# direct steering without the test knowing anything about navigation.

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")
const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const WorldScaleScript = preload("res://scripts/world_scale.gd")
const UnitScript = preload("res://scripts/battle/units/unit.gd")
const LayersScript = preload("res://scripts/battle/battle_layers.gd")
const MatchRuleSetScript = preload("res://scripts/match_rule_set.gd")
const SimRNG = preload("res://scripts/battle/sim_rng.gd")
const SelectionServiceScript = preload("res://scripts/battle/orders/selection_service.gd")
const AlertServiceScript = preload("res://scripts/battle/alert_service.gd")
const OrderServiceScript = preload("res://scripts/battle/orders/order_service.gd")
const FlowFieldServiceScript = preload("res://scripts/battle/movement/flow_field_service.gd")
const StanceScript = preload("res://scripts/battle/orders/stance.gd")
const EconomyServiceScript = preload("res://scripts/battle/economy/economy_service.gd")
const ProductionServiceScript = preload("res://scripts/battle/economy/production_service.gd")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const StructureScript = preload("res://scripts/battle/buildings/structure.gd")
const PlacementServiceScript = preload("res://scripts/battle/buildings/placement_service.gd")
const MatchStatsScript = preload("res://scripts/battle/match_stats.gd")
const AfterActionReportScript = preload("res://scripts/after_action_report.gd")
const PerfHUDScript = preload("res://scripts/perf_hud.gd")
const AdminMenuScript = preload("res://scripts/battle/hud/admin_menu.gd")
const BattleFinishScript = preload("res://scripts/battle/battle_finish.gd")
const Profiler = preload("res://scripts/battle/battle_profiler.gd")
const UnitAssemblyScript = preload("res://scripts/battle/units/unit_assembly.gd")
const ResourceNodeScript = preload("res://scripts/resource_node.gd")
const ResourceFieldScript = preload("res://scripts/battle/economy/resource_field.gd")
const ResourceCatalogScript = preload("res://scripts/battle/economy/resource_catalog.gd")
const ProductionHUDScript = preload("res://scripts/battle/hud/production_hud.gd")
const VisionServiceScript = preload("res://scripts/battle/vision/vision_service.gd")
const BattleHUDScript = preload("res://scripts/battle/hud/battle_hud.gd")
const CommanderScript = preload("res://scripts/battle/ai/commander.gd")
const CounterDraftScript = preload("res://scripts/battle/ai/counter_draft.gd")
const SquadScript = preload("res://scripts/battle/ai/squad.gd")
const DesignCostingScript = preload("res://scripts/battle/economy/design_costing.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1

# Cached rule set for the current match. Resolved from /root/MatchConfig in
# _ready() and read by every later function that needs to know which mode
# the match is in (Skirmish / Operations / Test Range) or any per-mode
# override (cameras, factions, fog, starting credits, HUD toggles).
#
# WHY A MEMBER, NOT A LOCAL. _ready() awaits _setup_terrain(), and GDScript
# drops any local declared before an `await` once that await resumes - the
# same identifier becomes "not declared" past the await point at parse
# time. A function called from _ready() after the await (e.g. _setup_vision
# reading rs.enable_fog_of_war) would also need the local re-passed, which
# is a contract that scales poorly. A member costs one assignment and is
# visible everywhere for the lifetime of the match.
var _match_rule_set: MatchRuleSet = null

# Neighbour lookup grid. One cell comfortably exceeds the largest separation
# radius, so a unit only ever has to check its own cell and the eight around it.
const NEIGHBOUR_CELL := 8.0

# How far a right-click ray reaches. Longer than any map's diagonal so a click
# near the horizon at full zoom-out still finds ground.
const PICK_RAY_LENGTH := 4000.0

var map_id: String = MapCatalog.DEFAULT_MAP_ID
var current_map: Dictionary = {}
var player_faction: String = "industrialists"
var enemy_faction: String = "technocrats"

var bp_manager: Node = null
var camera: Camera3D = null
# The chase camera, when present, follows a single unit instead of
# framing the whole battlefield. Battle-system unification (Phase 3):
# Test Range sets this active and routes focus_unit to the player
# unit; Skirmish and Operations leave it inactive and use the RTS
# camera. Both are Camera3D children of Battle.tscn; only one has
# `current = true` at a time.
var chase_camera: Camera3D = null
# The unit the chase camera tracks. Set by _wire_test_range_camera()
# from the rule set's player roster. Null in any mode that is not
# Test Range.
var focus_unit: Node3D = null

var ground_nav_map: RID
var water_nav_map: RID
var amphibious_nav_map: RID
var deep_water_nav_map: RID
# Chunk 21: one region PER NAVMESH TILE, not one region for the whole
# ground/amphibious surface - see terrain_builder.gd's NAV_TILE_SIZE header
# comment. water/deep_water stay single-region; neither is ever rebaked
# mid-match (buildings don't carve water) and neither was the fidelity
# problem tiling exists to fix.
var _ground_nav_regions: Array = []
var _amphibious_nav_regions: Array = []
var _nav_tile_rects: Array = []
var _water_nav_region: RID
var _deep_water_nav_region: RID

var selection: SelectionService = null
var orders: OrderService = null
var alerts: AlertService = null
var flow_fields: FlowFieldService = null
var economy: EconomyService = null
var production: ProductionService = null
var production_hud: ProductionHUD = null
var stats = null
var _perf_hud: CanvasLayer = null
var admin_menu: Control = null

# Emitted once the match is genuinely playable: terrain baked, units spawned, HUD
# built. SceneRouter waits on this before lifting its fade.
#
# WHY IT IS NEEDED. _ready() awaits _setup_terrain(), which makes _ready() a
# COROUTINE - it returns to the engine at that await and finishes many frames
# later. The router's "wait two frames for the incoming scene to build itself"
# is true for an ordinary scene and false for this one, so the fade lifted on a
# half-built match: bases already spawned (they are created before the await) and
# floating over an unbuilt map, with no terrain and no HUD yet.
#
# The flag exists alongside the signal for the race where the world finishes
# BEFORE the router gets around to awaiting - a signal already emitted is a
# signal that never arrives, and awaiting one hangs forever.
signal world_ready
var world_is_ready: bool = false

# Build progress, emitted during the world build phase that runs inside
# _ready() between the scene swap and world_ready. The SceneRouter's
# old load_progress stream was fraction 0..1 across the warm-list only;
# the world's own build (terrain bake, roster, units, HUD, AI) was an
# unaccounted-for middle. A new subscriber (the deploy gate's glass
# overlay) needs fraction 0..1 across the WHOLE sequence, so the
# match director publishes its own progress at each known milestone
# in _ready(). The 0..0.05 slice is the warm-list; this signal owns
# 0.05..1.00.
#
# Emissions land at the 8 milestones documented in
# docs/design/DEPLOY_GATE_REDESIGN.md §3.1 (resource nodes, bases,
# per-tile terrain, terrain done, roster, units, HUD, AI, ready).
# The 1.00 emission is the same moment world_is_ready flips, so a
# subscriber can use either as "the world is fully built" - the
# signal is the one that arrives on every subscriber, the flag is
# the one that handles the race where the router polled before
# the signal had a chance to land.
signal progress(fraction: float, label: String)

# Last emission of the progress signal, kept as a member so a
# late subscriber (e.g. the deploy gate, which is created after
# the first few emissions have already fired during _ready)
# can read the current value on connect rather than sitting
# at 0.0 until the next emission lands. The progress signal
# itself is fire-and-forget; this is the replay buffer.
var _last_progress_fraction: float = 0.0
var _last_progress_label: String = ""

# Public so a late subscriber can read the most recent progress
# value on connect. The pair is the same dict-shaped read the
# signal carries; the deploy gate uses it to seed its bar before
# the next live emission lands.
func get_last_progress() -> Dictionary:
	return {"fraction": _last_progress_fraction, "label": _last_progress_label}


# Internal: emit progress and update the replay buffer in one
# step. Every emission site in _ready() goes through this so
# the buffer and the signal cannot drift. Sites are
# documented in the table at the top of this file.
func _emit_progress(fraction: float, label: String) -> void:
	_last_progress_fraction = fraction
	_last_progress_label = label
	progress.emit(fraction, label)


var vision: VisionService = null
var battle_hud: BattleHUD = null
var commander: Commander = null

# One live squad per AI team. Kept between decisions so a squad's state -
# retreating, regrouping, and the peak health those are measured against -
# survives; rebuilding it each tick would reset its memory every two seconds.
var _squads: Dictionary = {}

# Per-team assigned base zone, indexed by team id.
#
# Set once during _spawn_bases() from MapCatalog.assign_base_zones() and held
# for the lifetime of the match. Two reasons for storing it rather than re-
# assigning on demand:
#   1. The assignment is a deterministic max-distance spread - re-running it
#      would just return the same value, but would couple every later query
#      to the same rng/state the orchestrator used on match start, and to
#      the map being still loaded. Holding the result means a UI layer that
#      wants to draw the zone ("drop HQ here") doesn't have to know either.
#   2. The human-placement hook (place_hq_for_human) needs to know which
#      zone belongs to the human, and that lookup happens in the input
#      layer, far from _spawn_bases. A precomputed table is the cheapest
#      contract for both.
var _team_base_zone: Dictionary = {}

# Set when the match has been decided. Stops the vision scan and the win check
# from running over a field nobody is playing on any more.
var game_over: bool = false

# The designs this team can field. Bundled defaults for now; hand-picked roster
# selection from MatchConfig arrives with the pre-match screen.
var roster: Array = []
# The AI's own designs, kept separate from the player's so a match is not a
# mirror and counter-picking has something to pick from.
var enemy_roster: Array = []

# 2026-08-10 (Chris): the pre-game HQ-placement change removed the
# auto-spawned refinery + 3 manufactories from the match start, so
# the player now has to BUILD them with their own credits. The bank
# is sized for "refinery + 2 manufactories of your choice" - the
# smart opening the user described, where the refinery comes with
# the free roster harvester and the 2 manufactories are an actual
# choice (2 light = cheap + flexible, 2 heavy = expensive but
# immediate late-game access).
#
# Worst case (refinery + 2 heavy): 150 + 320 + 320 = 790 metal,
# 0 + 85 + 85 = 170 crystal = 1130 credits at the 2x crystal
# rate. 1200 is 70 credits of buffer past that, small enough that
# a player who wants a power plant on top has to make a real
# choice between the heavy + power-plant combination and the
# refinery + 2 light + power-plant combination, which is what the
# "choice" framing implies.
#
# Pre-change bank was 750 (the old 450 metal + 150 crystal at 2x),
# which bought a single refinery and a single light manufactory with
# nothing left over - effectively forcing the rest of the
# manufactories to be built slowly from income. 1200 buys the
# "smart opening" the new flow is balanced around.
const STARTING_CREDITS := 1200

# The player's build bar tops out here, matching the old runtime's loadout limit.
const ROSTER_LIMIT := 12
# How many of the player's own saved designs get auto-drafted when they did not
# hand-pick a roster. Deliberately short of ROSTER_LIMIT so bundled defaults
# still fill the remainder - a roster of eight half-finished experiments with no
# harvester is not a playable match.
const ROSTER_AUTOPICK_LIMIT := 8
# A match whose roster cannot mine is unwinnable, so this is force-added when
# nothing else in the roster harvests.
const FALLBACK_HARVESTER := "res://data/loadout/magpie_ore_hauler.json"

# Drag-select state. A press below SelectionService.DRAG_THRESHOLD_PX resolves as
# a click instead.
var _drag_origin := Vector2.ZERO
var _dragging := false
# Right-click moves a unit; right-click + drag orbits the chase camera
# in Test Range. The two are disambiguated by whether the press and
# release positions are within DRAG_CLICK_THRESHOLD pixels of each
# other - a stationary click issues a move order, a dragged click is
# owned by the camera. Pre-existing left-click drag (selection
# rectangle) is unchanged.
const DRAG_CLICK_THRESHOLD: float = 4.0
var _right_press_pos: Vector2 = Vector2.ZERO
var _right_press_active: bool = false
var _right_dragged: bool = false
var _selection_rect: Panel = null

# Armed one-shot modes: the next right-click means something other than "move".
# Same convention OpenRA's sidebar icons use, and the same one the old runtime
# used for repair/sell.
var _attack_move_armed := false
var _hud_hint: Label = null

# cell -> Array of units, rebuilt each physics tick. Separation asks this rather
# than scanning every unit, which would be O(n^2) per frame across the army.
var _neighbour_grid: Dictionary = {}


func _ready() -> void:
	# The hull-template cache is static and therefore outlives a match. Dropped at
	# the start of every one, so a design re-saved in the Lab between matches is
	# rebuilt rather than served from the previous match's geometry.
	UnitAssemblyScript.clear_hull_cache()

	bp_manager = BlueprintManagerScript.new()
	bp_manager.name = "BlueprintManager"
	add_child(bp_manager)

	camera = get_node_or_null("Camera3D")
	chase_camera = get_node_or_null("ChaseCamera")
	# MatchConfig is the source of truth for both the camera-mode gate below
	# AND the per-mode rule set the rest of this function reads. Resolve it
	# ONCE at the top so the camera pick and the rule set lookup cannot
	# disagree about whether the autoload is mounted.
	var match_config := get_node_or_null("/root/MatchConfig")

	# PERF_TESTING_RIG.md Fix A. Applied before any physics work, so all
	# subsequent await physics_frame calls in this scene inherit the rate.
	# Skirmish/Operations set 30; Test Range stays at 60 (rule-set default).
	# Resolved from match_config.rule_set directly because _match_rule_set
	# (the member) is not assigned until the blocks below.
	var tick_rate := 60
	if match_config != null and "rule_set" in match_config \
			and match_config.rule_set != null:
		tick_rate = match_config.rule_set.physics_ticks_per_second
	Engine.physics_ticks_per_second = tick_rate
	if tick_rate != 60:
		print("[match_director] physics_ticks_per_second = %d" % tick_rate)

	# Battle-system unification (Phase 3). The rule set, when set,
	# picks which camera is `current`. Test Range activates the chase
	# camera and wires it to the player unit; Skirmish and Operations
	# leave the RTS camera active (the chase camera is null-defended
	# so a Test Range launcher that forgets to set focus_unit is
	# harmless - the camera sits at the world origin and waits).
	if match_config and "rule_set" in match_config and match_config.rule_set != null \
			and chase_camera != null and is_instance_valid(chase_camera):
		_match_rule_set = match_config.rule_set
		if _match_rule_set.camera_mode == MatchRuleSetScript.CameraMode.CHASE:
			chase_camera.current = true
			if camera != null and is_instance_valid(camera):
				camera.current = false
		else:
			chase_camera.current = false
			if camera != null and is_instance_valid(camera):
				camera.current = true

	# Battle-system unification (Phase 5, 2026-08-10). The seven legacy
	# pre-match fields on MatchConfig (selected_map_id, player_faction,
	# enemy_faction, selected_blueprint_paths, ai_difficulty, starting_credits)
	# are retired. The per-mode rule set written by match_setup.gd /
	# operations_draft.gd / test_range_launcher.gd is the single source
	# of truth; its fields are read here, with the rule set's own defaults
	# (set in MatchRuleSetScript.skirmish/operations/test_range) carrying
	# the case where the caller did not specify a value. A test path that
	# instantiates Battle.tscn without the autoload at all still gets a
	# null match_config and falls through to the hardcoded director
	# defaults - the same posture every prior phase preserved.
	if match_config and "rule_set" in match_config:
		_match_rule_set = match_config.rule_set
	if _match_rule_set != null:
		if _match_rule_set.map_id != "":
			map_id = _match_rule_set.map_id
		if _match_rule_set.player_faction != "":
			player_faction = _match_rule_set.player_faction
		if _match_rule_set.enemy_faction != "":
			enemy_faction = _match_rule_set.enemy_faction

	# SEED THE SIMULATION STREAM HERE, and nowhere else. This has to happen
	# after the rule set is resolved (it carries sim_seed) and BEFORE anything
	# spawns: auto_weapon.gd's reacquire stagger and its initial fire-phase
	# offset are both sim draws taken during _ready(), so a unit built ahead of
	# this line would be drawing from the previous match's tail. A null rule set
	# is fine - begin_match() rolls a fresh seed and writes it back, which is
	# what the Test Range and the headless fixtures get. SimRNG.current_seed()
	# is then the number a replay header or a netcode handshake would carry.
	SimRNG.begin_match(_match_rule_set)

	current_map = MapCatalog.get_map(map_id)
	# CORE_DESIGN_LANGUAGE.md §3.2: pan/middle-drag speed track world_scale so
	# a genuinely bigger map doesn't also feel proportionally slower to move
	# around in - duck-typed the same way the rest of this file treats the
	# camera, so a camera without the property (an older scene, a test stub)
	# degrades to its own default rather than erroring.
	if camera and "world_scale" in camera:
		camera.world_scale = WorldScaleScript.for_map(current_map)
	_scale_lighting_to_world()

	orders = OrderServiceScript.new()
	flow_fields = FlowFieldServiceScript.new()

	economy = EconomyServiceScript.new()
	production = ProductionServiceScript.new()
	production.setup(economy, self)
	for t in [PLAYER_TEAM, ENEMY_TEAM]:
		# 2026-08-10: the per-team starting credit bank comes from the
		# per-mode rule set, with a sentinel of -1 meaning "use the
		# director's own default" (STARTING_CREDITS, 750). The legacy
		# MatchConfig.starting_credits field is retired.
		var start_credits: int = STARTING_CREDITS
		if _match_rule_set != null and _match_rule_set.starting_credits >= 0:
			start_credits = _match_rule_set.starting_credits
		economy.add_team(t, start_credits)
		production.add_team(t)
	production.unit_completed.connect(_on_unit_completed)
	production.structure_ready.connect(_on_structure_ready)

	# Buildings BEFORE the bake, so their footprints go into the first navmesh
	# rather than needing an immediate second one. A rebake inside the first few
	# startup frames leaves a window where a unit's very first path query runs
	# before NavigationServer3D has resynced, and the unit drives into the lake.
	_spawn_resource_nodes()
	# 2026-08-13: deploy-gate progress emissions. See the `progress` signal
	# header at :147-160 for the 0..1 fraction contract. Fractions below
	# under-weight the early build steps (resource nodes, bases) so the
	# deploy gate's bar does not stall at 10% for 3 seconds while the
	# terrain bake runs - the bake is the wall-clock-dominant phase and
	# owns 0.10..0.55 of the bar.
	_emit_progress(0.05, "Locating resource deposits")
	_spawn_bases()
	_emit_progress(0.10, "Surveying build sites")

	await _setup_terrain()
	_emit_progress(0.60, "Plotting movement lanes")

	# After the bake: the flow field samples the ground navmesh for passability,
	# so it needs the map RID that _setup_terrain() just produced.
	flow_fields.setup(ground_nav_map, current_map.get("map_half_extents", 80.0), WorldScaleScript.for_map(current_map))

	selection = SelectionServiceScript.new()
	selection.setup(camera, get_world_3d().direct_space_state, PLAYER_TEAM)
	selection.group_recentre_requested.connect(_on_group_recentre)
	
	alerts = AlertServiceScript.new()
	add_child(alerts)

	_setup_vision()

	_load_roster()
	_emit_progress(0.70, "Indexing designs")
	_spawn_starting_units()
	_emit_progress(0.80, "Preparing vehicle systems")
	_build_hud()
	_emit_progress(0.90, "Raising command deck")

	stats = MatchStatsScript.new()
	# Battle-system unification (Phase 2). Test Range's rule set has
	# enable_ai=false, which is the per-mode gate for "does the AI
	# commander run at all". Skirmish and Operations both leave it on
	# (the default), so the legacy behaviour is unchanged for the modes
	# that exist today. The gate is forward-looking: Phase 3 wires the
	# Test Range launcher to use Battle.tscn, and this branch is what
	# makes Test Range not spin up a Commander at all.
	# 2026-08-10: rule set is the single source; legacy ai_difficulty fallback
	# is gone. enable_ai + ai_difficulty both come from the rule set, with
	# the rule set's own defaults (true / "normal") carrying the no-rule-set
	# case via the same duck-typed null guard.
	var ai_enabled: bool = true
	var ai_diff: String = "normal"
	if _match_rule_set != null:
		ai_enabled = _match_rule_set.enable_ai
		ai_diff = _match_rule_set.ai_difficulty
	if ai_enabled:
		commander = CommanderScript.new()
		commander.setup(self, ENEMY_TEAM, ai_diff)
	# Always emit the 0.95 step, even when the AI is disabled (Test
	# Range's rule set has enable_ai=false). The label is the
	# "briefing" beat regardless of whether there is an opponent
	# commander to brief; the jump from 0.90 to 1.00 without it
	# would be a 10% step the bar smooths over awkwardly.
	_emit_progress(0.95, "Briefing opposition")

	# 1.00 is the LAST emission. world_is_ready flips first so the
	# flag-based poll in scene_router.gd:_await_world_ready exits on
	# its next tick; world_ready signal fires next for any direct
	# subscribers; the progress(1.0, "Ready") emission lands last so
	# the deploy gate transitions to its ready state in the same
	# order it was reading the rest of the stream.
	world_is_ready = true
	world_ready.emit()
	_emit_progress(1.0, "Ready")

	_setup_audio()


# --- Audio -------------------------------------------------------------------
#
# set_combat_intensity() feeds a combat-intensity mixer in AudioManager. When
# the skirmish track has separate bed/rhythm/lead stems (the procedural
# renderer in tools/audio/tracks/skirmish.py), it raises the rhythm and lead
# layers as a real engagement heats up. The currently-shipped soundtrack
# (tools/audio/curated_music.py) is finished single-master tracks with no stem
# split, so this call is a no-op for the extra layers and the track just
# plays - still correct, just without the dynamic layering. See
# scripts/audio_manager.gd's _refresh_music_targets.

var _audio: Node = null
# Decays toward zero every frame; damage events push it back up. Effectively a
# leaky integrator over "how much shooting is happening", which is a far better
# signal for the music than unit counts or proximity - it only rises when shots
# are actually landing.
var _combat_heat: float = 0.0
const COMBAT_HEAT_DECAY := 0.22        # per second
const COMBAT_HEAT_PER_DAMAGE := 0.014  # per point of damage dealt
var _ambience_check := 0.0


func _setup_audio() -> void:
	_audio = get_node_or_null("/root/AudioManager")
	if _audio == null:
		return
	_audio.play_music("skirmish")
	_audio.set_combat_intensity(0.0)
	match_ended.connect(_on_match_ended_audio)
	if production != null:
		production.unit_completed.connect(_on_unit_completed_audio)
		production.structure_ready.connect(_on_structure_ready_audio)


func _on_match_ended_audio(winning_team: int) -> void:
	if _audio == null:
		return
	_audio.play_music("victory" if winning_team == PLAYER_TEAM else "defeat")


func _on_unit_completed_audio(team: int, _queue: String, _blueprint: Dictionary) -> void:
	if _audio == null or team != PLAYER_TEAM:
		return
	_audio.play_sfx("unit_rollout")
	_audio.play_voice("radio_ready")


func _on_structure_ready_audio(team: int, _queue: String, _job: Dictionary) -> void:
	if _audio == null or team != PLAYER_TEAM:
		return
	_audio.play_sfx("construct_done")


func _tick_audio(delta: float) -> void:
	if _audio == null:
		return
	_combat_heat = maxf(0.0, _combat_heat - COMBAT_HEAT_DECAY * delta)
	_audio.set_combat_intensity(_combat_heat)

	# Ambience follows the surface under the camera. Sampled a few times a
	# second rather than per frame: the answer changes only when the player pans
	# across a biome boundary, and get_surface_type_at does real work.
	_ambience_check -= delta
	if _ambience_check <= 0.0:
		_ambience_check = 0.5
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			var surface := get_surface_type_at(cam.global_position)
			if surface != "":
				_audio.play_ambience("ambience_" + surface)


# Vision runs on its own timer rather than in _physics_process. The scan is
# O(viewers x targets) per team and its answer changing three times a second is
# imperceptible; running it per frame would be the single most expensive thing in
# the match for no visible gain.
func _setup_vision() -> void:
	vision = VisionServiceScript.new()
	vision.setup(self, PLAYER_TEAM, current_map.get("map_half_extents", 80.0), WorldScaleScript.for_map(current_map))
	# _match_rule_set is the cached rule set from _ready(). Fog of war is
	# the per-mode opt-out: Skirmish / Operations leave it on (the default
	# when no rule set is mounted), Test Range's launcher turns it off so
	# the dummies are visible across the whole range.
	if _match_rule_set != null and not _match_rule_set.enable_fog_of_war:
		return
	add_child(vision.build_shroud())

	# The HUD refreshes on the SAME tick as vision, deliberately. The minimap
	# draws what the player can see, so refreshing it more often than visibility
	# is recomputed just redraws the same answer, and refreshing it less often
	# would show blips the fog has already taken away.
	var timer := Timer.new()
	timer.name = "VisionTick"
	timer.wait_time = VisionServiceScript.TICK_INTERVAL
	timer.timeout.connect(_on_vision_tick)
	add_child(timer)
	timer.start()


func _on_vision_tick() -> void:
	if game_over:
		return
	var t := Profiler.start()
	vision.tick()
	Profiler.stop("vision", t)
	if battle_hud != null:
		t = Profiler.start()
		battle_hud.refresh()
		Profiler.stop("hud_minimap", t)


# --- World ------------------------------------------------------------------

# Bakes the four navmeshes and dresses the terrain.
#
# The bake is ~4 seconds on lake_crossing. In the real game the four surfaces go
# one per frame so the message loop keeps pumping - four seconds inside a single
# frame is what made Windows grey the title bar and report the app as not
# responding. Headless keeps the single blocking call, because a test that
# add_child()s this scene and immediately reads state must not have _ready()
# suspend part-way through.
#
# No buildings exist yet in Phase 0, so the first bake carves no holes. When base
# building lands in Phase 2 the starting structures must be spawned BEFORE this
# runs, so their footprints go into the FIRST bake - a second same-frame rebake
# leaves a window where a unit's very first path query runs before
# NavigationServer3D has resynced, and the unit wanders into the lake.
# Playtest: "maybe some lighting tricks can make [elevation] more apparent."
#
# Both of the settings below were authored in Battle.tscn against a world that
# has since grown, and both are measured in absolute world units, so neither
# followed it - the same class of scale-exposed constant as the fog shroud
# height and the AI threat radius before them.
#
# directional_shadow_max_distance is the bigger one and was never set at all,
# leaving Godot's default of 100 world units. On an open_plains grown to 840
# half-extent, terrain shadows simply stopped existing a short way out from the
# camera, so the relief that did exist cast nothing to read it by - which is
# most of why elevation looked flat regardless of how deep it actually was.
#
# ssao_radius is the sampling radius for ambient occlusion. At 0.8 units it
# only ever found tiny crevices; a ravine 8 units deep and tens of units wide
# is invisible to it. Widening it is what makes a dip read as a dip even where
# no direct shadow falls into it.
#
# Driven off WorldScale rather than re-authored in the .tscn so it tracks any
# future scale change instead of needing to be re-tuned by hand each time -
# and duck-typed/null-guarded like every other optional node here, so a test
# stub or a scene without them degrades rather than erroring.
const SHADOW_DISTANCE_BASE: float = 320.0
const SSAO_RADIUS_BASE: float = 0.8

func _scale_lighting_to_world() -> void:
	var scale: float = WorldScaleScript.for_map(current_map)
	var light := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light:
		light.directional_shadow_max_distance = SHADOW_DISTANCE_BASE * scale
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		world_env.environment.ssao_radius = SSAO_RADIUS_BASE * scale

func _setup_terrain() -> void:
	var nav: Dictionary
	var holes := _building_holes()
	if DisplayServer.get_name() == "headless":
		nav = TerrainBuilder.build_navmeshes(current_map, holes)
	else:
		# Genuinely async, not just spread across frames - see
		# bake_pending_entry_async()'s header for why the per-frame version
		# still blocked long enough to trip Windows' Not Responding watchdog.
		# Safe specifically because scene_router.gd's Deploy gate already
		# withholds player control until world_is_ready (set below, only
		# after every surface reports back), so nothing can query a region
		# whose mesh has not landed yet.
		nav = TerrainBuilder.build_navmeshes_deferred(current_map, holes)
		# `remaining` MUST be a Dictionary (or other reference type), not a
		# bool - GDScript closures capture locals BY VALUE. A `var done :=
		# false` set from inside the callback below mutates only that
		# lambda's own copy; the `while not done` loop below reads a
		# never-updated outer copy and spins forever. That silently hung
		# _setup_terrain() before world_is_ready could ever flip, so the
		# HUD and map never appeared - the same lambda-capture bug
		# test_battle_combat.gd's own `deaths` comment already documents,
		# just hit for real instead of in a test.
		var remaining := {"n": nav["pending"].size()}
		# 2026-08-13: per-tile progress for the deploy gate. Maps the
		# terrain-bake stretch of the bar (0.10..0.55) onto the bake's
		# own progress. The fraction is computed inside the lambda so
		# `done` / `total` can be captured by value without going stale
		# (the `done` counter is a Dictionary member, so the lambda
		# mutates the same reference the loop reads - the same pattern
		# the existing `remaining` dict already uses for the wait loop).
		var total_tiles: int = remaining["n"]
		var done: Dictionary = {"n": 0}
		for entry in nav["pending"]:
			TerrainBuilder.bake_pending_entry_async(entry, nav["cell_size"], func():
				done["n"] += 1
				if total_tiles > 0:
					var tile_frac: float = float(done["n"]) / float(total_tiles)
					_emit_progress(0.10 + tile_frac * 0.45, "Surveying terrain")
				remaining["n"] -= 1)
		while remaining["n"] > 0:
			await get_tree().process_frame

	ground_nav_map = nav.ground_map
	water_nav_map = nav.water_map
	amphibious_nav_map = nav.amphibious_map
	deep_water_nav_map = nav.deep_water_map
	# Chunk 21: one region per navmesh TILE now, not one region for the
	# whole map - see terrain_builder.gd's NAV_TILE_SIZE header comment.
	_ground_nav_regions = nav.ground_regions
	_amphibious_nav_regions = nav.amphibious_regions
	_nav_tile_rects = nav.tile_rects
	_water_nav_region = nav.water_region
	_deep_water_nav_region = nav.deep_water_region

	var ground := get_node_or_null("Ground")
	if ground:
		# The heightmap mesh's vertices already carry absolute world Y, so the
		# scene's placeholder slab offset has to be cleared or every terrain
		# query sits half a unit off what units and buildings actually see.
		ground.position = Vector3.ZERO
		var generated: Dictionary = TerrainBuilder.build_ground_visual_mesh(current_map)
		var mesh_inst: MeshInstance3D = ground.get_node_or_null("MeshInstance3D")
		if mesh_inst:
			mesh_inst.mesh = generated.mesh
			mesh_inst.material_override = TerrainBuilder.build_ground_material_heightmap(
				current_map.get("ground_color", Color(0.2, 0.26, 0.21)))
		var col: CollisionShape3D = ground.get_node_or_null("CollisionShape3D")
		if col:
			col.shape = generated.shape
			col.scale = generated.get("collision_scale", Vector3.ONE)

	TerrainBuilder.spawn_visuals(current_map, self)


# NavigationServer3D RIDs are not owned by the scene tree the way child nodes
# are - they leak unless freed explicitly. Found as a real RID-leak warning at
# engine exit during the headless suite, which builds and frees a fresh match
# scene many times per run.
func _exit_tree() -> void:
	for rid in _ground_nav_regions + _amphibious_nav_regions + [
			_water_nav_region, _deep_water_nav_region,
			ground_nav_map, water_nav_map, amphibious_nav_map, deep_water_nav_map]:
		if rid.is_valid():
			NavigationServer3D.free_rid(rid)


# --- Duck-typed contracts the unit runtime looks for -------------------------

func get_ground_nav_map() -> RID:
	return ground_nav_map

func get_water_nav_map() -> RID:
	return water_nav_map

func get_amphibious_nav_map() -> RID:
	return amphibious_nav_map

func get_deep_water_nav_map() -> RID:
	return deep_water_nav_map

func terrain_height_at(pos: Vector3) -> float:
	return TerrainBuilder.terrain_height_at(current_map, pos)

func get_surface_type_at(pos: Vector3) -> String:
	return TerrainBuilder.get_surface_type_at(current_map, pos)


# --- Units ------------------------------------------------------------------

# What each side can BUILD this match.
#
# THE ROSTER IS NOT THE STARTING FORCE. Phase 0 conflated the two - it spawned
# every bundled design at the player's spawn so there was something to drive -
# and that stops making sense the moment a roster means "the designs available
# from the build bar". Starting units are handled separately below.
#
# Selection follows the rules the old runtime already settled on
# (skirmish.gd:1160), because they encode decisions rather than accidents:
#
#   1. The exact designs the pre-match screen picked, if it picked any.
#   2. Otherwise the player's newest NAMED saved designs. Named only - an
#      unnamed scratch design left over from a test-range trip was never a
#      choice to field, so it should not be auto-drafted into a match.
#   3. Bundled defaults fill whatever room is left, so a player with no saved
#      designs at all still has a full build bar.
#   4. Capped at ROSTER_LIMIT.
#   5. A harvester is GUARANTEED. A match whose roster cannot mine is
#      unwinnable, and that is a much worse failure than an odd roster.
func _load_roster() -> void:
	roster.clear()
	var match_config := get_node_or_null("/root/MatchConfig")
	# Battle-system unification (Phase 2). Same precedence as in _ready():
	# the per-mode rule set wins if it was written; otherwise the seven
	# legacy fields on MatchConfig stay in charge. Test Range's rule set
	# has player_blueprint_path (singular) and enemy_blueprint_paths
	# (plural) instead of selected_blueprint_paths, so the rule set has
	# to also seed the player roster and the enemy roster directly when
	# the mode is TEST_RANGE. The legacy _bundled_loadout_paths() seed
	# still runs on top in either path, so a roster that comes in with
	# fewer than ROSTER_LIMIT designs is still filled.
	var rs: MatchRuleSet = _match_rule_set
	# Computed once up here so the player-roster branch (and the enemy-roster
	# branch below) can both read it without re-deriving from `rs`. Single
	# source of truth within this function, declared at the top because
	# GDScript locals are visible only from their declaration forward.
	var is_test_range: bool = rs != null and rs.mode == MatchRuleSetScript.Mode.TEST_RANGE

	var chosen: Array = []
	if rs != null and rs.mode == MatchRuleSetScript.Mode.TEST_RANGE and rs.player_blueprint_path != "":
		# Test Range: exactly one player design, plus the bundled defaults
		# if there's room.
		chosen = [rs.player_blueprint_path]
	elif rs != null and rs.selected_blueprint_paths.size() > 0:
		chosen = rs.selected_blueprint_paths
	if not chosen.is_empty():
		for path in chosen:
			_append_design(roster, bp_manager.load_blueprint(path))
	else:
		for entry in bp_manager.list_blueprints(true):
			if roster.size() >= ROSTER_AUTOPICK_LIMIT:
				break
			_append_design(roster, bp_manager.load_blueprint(entry.path))

	# In test range mode the player roster is already set to exactly one
	# design (the test subject). Don't pollute it with the bundled defaults.
	#
	# is_test_range is computed at the top of this function (next to the
	# rule-set lookup, before the player-roster branch reads it) and again
	# near the enemy-roster branch. The reason: GDScript locals are not
	# visible past an `await`, and the rule-set reference `rs` is local
	# to this function. One declaration up here, one in the enemy block,
	# both reading the same `rs.mode` - they are short boolean expressions
	# and the duplication is the price of not promoting `rs` to a member
	# just for the test_range gate.
	if not is_test_range:
		for path in _bundled_loadout_paths():
			_append_design(roster, bp_manager.load_blueprint(path))
		if roster.size() > ROSTER_LIMIT:
			roster = roster.slice(0, ROSTER_LIMIT)

		if _harvester_in(roster).is_empty():
			_append_design(roster, bp_manager.load_blueprint(FALLBACK_HARVESTER))

	# Factions: the pre-match choice wins; otherwise the roster's own lead design
	# decides, which is the old behaviour and keeps a hand-built roster feeling
	# like it belongs to somebody. Rule set (when set) is the single source
	# of truth - 2026-08-10: legacy MatchConfig.player_faction fallback gone.
	if rs != null and rs.player_faction != "":
		player_faction = rs.player_faction
	elif not roster.is_empty() and roster[0].get("faction", "") != "":
		player_faction = roster[0].get("faction", "")
	else:
		player_faction = "industrialists"

	# Test Range's enemy roster comes from the rule set rather than from
	# the bundled defaults. The legacy code path (Skirmish, Operations)
	# also reads `enemy_faction` further down and falls back to the
	# enemy_roster lead design - that path is unchanged.
	if rs != null and rs.mode == MatchRuleSetScript.Mode.TEST_RANGE \
			and rs.enemy_blueprint_paths.size() > 0:
		enemy_roster.clear()
		for path in rs.enemy_blueprint_paths:
			_append_design(enemy_roster, bp_manager.load_blueprint(path))
		if _harvester_in(enemy_roster).is_empty():
			_append_design(enemy_roster, bp_manager.load_blueprint(FALLBACK_HARVESTER))

	# ONE SHARED DEFAULT POOL (Chris's call). On a fresh install the player and
	# the AI have the same designs available, so neither side is fighting with
	# equipment the other could not have fielded.
	#
	# The AI draws from the BUNDLED defaults rather than from `roster`, because
	# roster may now be the player's own saved designs - handing those to the
	# opponent would field the player's army against them, which is a different
	# game than the one they chose.
	#
	# SKIP IN TEST RANGE. The test_range block above already populated
	# enemy_roster with the three dummies from the rule set (or the bundled
	# defaults as a fallback). This block was overwriting that result on every
	# launch - lines 687-693 set it correctly and lines 703-707 immediately
	# clobbered it. Guarded now; the test_range block already handles the
	# harvester fallback. `is_test_range` is the function-top local declared
	# above - not redeclared here, to keep the test-range gate one source.
	elif rs == null or rs.mode != MatchRuleSetScript.Mode.TEST_RANGE:
		enemy_roster.clear()
		for path in _bundled_loadout_paths():
			_append_design(enemy_roster, bp_manager.load_blueprint(path))
		if enemy_roster.size() > ROSTER_LIMIT:
			enemy_roster = enemy_roster.slice(0, ROSTER_LIMIT)
		if _harvester_in(enemy_roster).is_empty():
			_append_design(enemy_roster, bp_manager.load_blueprint(FALLBACK_HARVESTER))

	# COUNTER-DRAFTING. In an operation the AI reorders its pool against what the
	# player has actually fielded in engagements already fought - which is what
	# stops it bringing an identical army to round 6 as to round 1.
	#
	# A REORDER, NOT A REBUILD. ai_design_for_role() takes the FIRST design in
	# enemy_roster matching a role, so changing the order is the whole mechanism;
	# no design is added or dropped, and the AI plays exactly as it always did.
	# Outside an operation, or on round one, this is a no-op.
	var ops = get_node_or_null("/root/OperationsService")
	if ops != null and ops.is_active_operation:
		var history: Array = ops.fielded_history()
		if not history.is_empty():
			enemy_roster = CounterDraftScript.order_roster(enemy_roster, history)
			print("[Operations] AI counter-draft: %s" % CounterDraftScript.explain(history))

	if rs != null and rs.enemy_faction != "":
		enemy_faction = rs.enemy_faction
	elif not enemy_roster.is_empty() and enemy_roster[0].get("faction", "") != "":
		enemy_faction = enemy_roster[0].get("faction", "")
	else:
		enemy_faction = "technocrats"


# Skips empties rather than making every caller check. reconstruct_vehicle()
# returns nothing for a design naming a hull the catalog no longer has, and a
# roster slot holding a design that cannot be built is a build button that does
# nothing.
func _append_design(into: Array, design: Dictionary) -> void:
	if not design.is_empty():
		into.append(design)


func _harvester_in(from: Array) -> Dictionary:
	for design in from:
		if CommanderScript.design_fills_role(design, "harvester"):
			return design
	return {}


func _list_json(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(dir_path + "/" + f)
	out.sort()
	return out


# ONE HARVESTER PER SIDE, and nothing else.
#
# Phase 0 fielded the entire bundled loadout at the player's spawn so there was
# something to drive with no production yet. That was scaffolding: with a real
# roster and a real build bar, handing the player a dozen free units is not a
# starting force, it is the whole match already won. The old runtime starts each
# side with exactly one harvester (skirmish.gd:1499) and everything else is
# earned - matched here, because this mode is replacing that one.
func _spawn_starting_units() -> void:
	# Battle-system unification (Phase 3). Test Range spawns EVERY
	# design in both rosters, not just the harvester, because Test
	# Range's rule set has enable_production=false - the production
	# queue is the wrong tool for "show the player their unit and
	# three dummies on a small map". The lineup is small (4 units
	# total per the rule set) so a direct loop is fine; a Skirmish
	# unit's first move is the production queue, which is what the
	# legacy path here keeps doing.
	# _match_rule_set is the cached rule set from _ready(); reading from
	# the member keeps the mode gate in the same idiom the rest of the
	# director uses.
	var test_range_mode: bool = _match_rule_set != null and _match_rule_set.mode == MatchRuleSetScript.Mode.TEST_RANGE
	if test_range_mode:
		_spawn_test_range_force()
		return

	for team_id in [PLAYER_TEAM, ENEMY_TEAM]:
		var spawn := MapCatalog.get_spawn(current_map,
			"player" if team_id == PLAYER_TEAM else "enemy")
		if spawn.is_empty():
			continue
		var pool: Array = roster if team_id == PLAYER_TEAM else enemy_roster
		var harvester := _harvester_in(pool)
		if harvester.is_empty():
			continue
		# The map authors a harvester start position; fall back to a corner of the
		# base if it does not, rather than dropping the unit on the HQ itself.
		var at: Vector3 = spawn.get("harvester", spawn.get("hq", Vector3.ZERO) + Vector3(8, 0, -8))
		spawn_unit(harvester, team_id, at)


# Test Range places the player unit and the dummies on the map
# directly. The placement uses the test_range map's authored spawn
# points when it has them, falling back to a line-up across the
# map's centre for a map that does not (the Phase 3 ship map will
# author its own spawns).
#
# The player unit is captured into focus_unit so the chase camera
# has a target. The dummies are not auto-engaging on spawn - their
# normal BattleUnitV2 AI runs from the moment they are on the map,
# which is what the player wanted when they picked the COMBAT-flagged
# dummies; the legacy TARGET_DUMMY_SCRIPT hover-and-pace is gone
# with the battlefield.gd retirement.
func _spawn_test_range_force() -> void:
	# Player unit: use the test_range map's player spawn if it has
	# one, otherwise the centre of the map's half_extents.
	var player_spawn: Vector3 = _test_range_spawn("player", Vector3(0, 0, 0))
	var player_design: Dictionary = roster[0] if not roster.is_empty() else {}
	if not player_design.is_empty():
		var unit := spawn_unit(player_design, PLAYER_TEAM, player_spawn)
		if unit != null:
			focus_unit = unit
			# Force-select the player unit from spawn. The selection
			# system's click raycast does not work in Test Range (the
			# hull-cache proxy shares stale team metadata with the
			# template), so we bypass it entirely for the test subject.
			# Orders still go through the normal _issue_at pipeline;
			# only selection is forced here.
			if selection != null:
				selection.set_selection([unit])
			# Push the same reference to the chase camera. The match
			# director's `focus_unit` and ChaseCamera3D's `focus_unit`
			# are the same value; the camera reads it from its own
			# field. Skirmish / Operations leave chase_camera.current
			# false and the camera never reads its own field, so this
			# is the one place the two are linked.
			if chase_camera != null and is_instance_valid(chase_camera) \
					and "focus_unit" in chase_camera:
				chase_camera.focus_unit = unit

	# Dummies: a row in front of the player, each ~6m apart so weapons
	# engage at sensible ranges. The exact spacing does not matter for
	# behaviour, only for the player's read of the field. The dummy
	# row's anchor is the player_spawn + (0, 0, 24) so dummies sit 24m
	# south of the player by default; the map's enemy HQ is used as a
	# directional hint (dummies spread on the line the player takes to
	# reach that HQ) rather than as a literal spawn point. Maps without
	# an enemy spawn fall back to the player-relative anchor.
	var enemy_anchor: Vector3 = _test_range_spawn("enemy", Vector3.ZERO)
	var has_enemy_spawn: bool = enemy_anchor != Vector3.ZERO
	var base_anchor: Vector3 = player_spawn + Vector3(0.0, 0.0, 24.0)
	var right: Vector3 = Vector3(0.0, 0.0, 1.0)  # default: spread along Z
	if has_enemy_spawn:
		# Use the map's enemy HQ as the row's centre, not as a per-dummy
		# position. Spread dummies perpendicular to the line from player
		# to enemy HQ so they read as "the things between me and the
		# objective" rather than three units stacked on one point.
		var to_enemy: Vector3 = enemy_anchor - player_spawn
		to_enemy.y = 0.0
		var fwd: Vector3 = to_enemy.normalized() if to_enemy.length() > 0.01 else Vector3(0, 0, 1)
		right = fwd.cross(Vector3.UP).normalized()
		base_anchor = player_spawn + to_enemy * 0.5  # midpoint of the engagement
	var dummy_index: int = 0
	for design in enemy_roster:
		if design.is_empty():
			dummy_index += 1
			continue
		var side_offset: float = float(dummy_index - (enemy_roster.size() - 1) * 0.5) * 6.0
		var spawn_pos: Vector3 = base_anchor + right * side_offset
		spawn_unit(design, ENEMY_TEAM, spawn_pos)
		dummy_index += 1


# Spawn point lookup for Test Range. Reads the test_range map's
# authored spawns ("player" / "enemy") if the map provides them,
# otherwise returns a sensible default derived from the map's
# half_extents. The legacy Battlefield.tscn map shipped with hard-
# coded spawns in the script (battlefield.gd:19-38); the unified
# map catalog inherits those as default.
func _test_range_spawn(spawn_id: String, fallback: Vector3) -> Vector3:
	var spawns: Array = current_map.get("spawns", [])
	for s in spawns:
		if str(s.get("id", "")) == spawn_id:
			var hq: Vector3 = s.get("hq", Vector3.ZERO)
			return hq
	return fallback


# The bundled default designs. Phase 0 fields these directly so there is
# something to drive; real roster selection (MatchConfig's hand-picked paths,
# then the player's newest saved designs, then these as filler) arrives with
# production in Phase 2.
func _bundled_loadout_paths() -> Array:
	var paths: Array = []
	var dir := DirAccess.open("res://data/loadout")
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			paths.append("res://data/loadout/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


func spawn_unit(blueprint: Dictionary, unit_team: int, at: Vector3) -> Node3D:
	var _prof := Profiler.start()
	var unit := UnitScript.new()
	# Added to the tree BEFORE setup(): reconstruct_vehicle() and the nav agent
	# both need the node to be inside the tree to resolve global transforms and
	# to reach NavigationServer3D.
	add_child(unit)
	unit.global_position = Vector3(at.x, terrain_height_at(at), at.z)
	# The unit wears its OWN side's faction. Passing player_faction for everything
	# gave the AI's army the player's colours and the player's passives, which
	# reads as a rendering oddity and is really a balance one.
	var faction: String = player_faction if unit_team == PLAYER_TEAM else enemy_faction
	if stats != null and unit_team == PLAYER_TEAM:
		# Player only. The report is the player's own debrief, and mixing the
		# opponent's designs into it would make every column meaningless.
		stats.record_built(blueprint, DesignCostingScript.blueprint_cost(blueprint))
	if not unit.setup(blueprint, unit_team, bp_manager, self, faction):
		# The blueprint named a hull the catalog no longer has. Drop it rather
		# than leaving a half-assembled body on the field.
		unit.queue_free()
		Profiler.stop("spawn_unit", _prof)
		return null
	# The battlefield finish. Applied after assembly, because the materials do not
	# exist until reconstruct_vehicle() has built the hull and its modules.
	BattleFinishScript.apply(unit)
	Profiler.stop("spawn_unit", _prof)
	return unit


func get_team_units(for_team: int) -> Array:
	var out: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead and u.team == for_team:
			out.append(u)
	return out


# --- Base and economy --------------------------------------------------------

# Each map entry is now a FIELD CENTRE, not a lump.
#
# The schema is unchanged - position, type, amount - so all ten bundled maps and
# the spawn-fairness lint carry over untouched. What changed is what gets built
# from it: resource_field.gd scatters collectibles around the point and replaces
# them as they are worked out, per Chris's direction that ore and crystal "get
# reworked into spread out fields around the central node that spawns the
# collectible resource objects".
func _spawn_resource_nodes() -> void:
	for entry in current_map.get("resource_nodes", []):
		var field := Node3D.new()
		field.set_script(ResourceFieldScript)
		add_child(field)
		var pos: Vector3 = entry.get("position", Vector3.ZERO)
		field.global_position = Vector3(pos.x, terrain_height_at(pos), pos.z)
		field.setup(entry.get("type", "metal"), entry.get("amount", 1000), self)


func _spawn_bases() -> void:
	# Test Range has no bases. _spawn_test_range_force() handles player + dummies
	# and the rule set has no HQ to place. Skipping here mirrors the same guard
	# in _spawn_starting_units so the two are consistent. _match_rule_set is
	# the cached rule set from _ready(); reading from the member is what every
	# other phase of the director does, no need to re-resolve off /root here.
	# Also guard on null: headless test paths that instantiate Battle.tscn
	# without the MatchConfig autoload have no roster and no bases to place.
	if _match_rule_set != null and _match_rule_set.mode == MatchRuleSetScript.Mode.TEST_RANGE:
		return

	# Per-team assigned base zone, indexed by team id (PLAYER_TEAM / ENEMY_TEAM).
	#
	# Two things this assignment does for the orchestrator:
	#   1. Decides WHICH zone each team starts in, using the same OpenRA
	#      max-distance-spread iteration assign_spawns() uses. With exactly
	#      two slots and two zones, this picks the zones farthest apart so
	#      no map boots with a player and an AI spawn in the same corner.
	#   2. Pins the result for the lifetime of the match, so the human
	#      placement hook (place_hq_for_human) and the AI auto-placer can
	#      both look up the same zone without re-running the spread step.
	#
	# Old order argument is preserved verbatim: assign_spawns and
	# assign_base_zones are called with the same [PLAYER_TEAM, ENEMY_TEAM]
	# list, so the i-th slot's spawn and its zone are decided together
	# and the "max-distance spread" lands on the same side for both -
	# a map with a 0-distance spawn pair will have the same 0-distance
	# zone pair, which is what made the old code testable in isolation.
	#
	# The PLAYER team does NOT get an auto-placed HQ - instead, the
	# pre-game phase below raises a placement ghost and waits for the
	# player to drop the HQ in their assigned zone. The AI auto-places
	# as before (no UI for the AI to interact with). On older maps that
	# have no base_zones, the player falls through to the legacy
	# auto-place at the spawn.hq coordinate, so modder maps without
	# zones still boot the old way.
	_team_base_zone = MapCatalog.assign_base_zones(
		current_map.get("base_zones", []),
		[PLAYER_TEAM, ENEMY_TEAM])
	var player_zone_id: String = _team_base_zone.get(PLAYER_TEAM, "")
	var has_zones: bool = not _team_base_zone.is_empty()
	for spawn in current_map.get("spawns", []):
		var team: int = PLAYER_TEAM if spawn.get("id") == "player" else ENEMY_TEAM
		var zone_id: String = _team_base_zone.get(team, "")
		# Prefer the zone centre. Fall back to the (still-authored) spawn.hq
		# when this map has no base_zones - keeps older/modder maps booting.
		var hq_pos: Vector3 = _base_zone_centre(zone_id) if zone_id != "" else spawn.get("hq", Vector3.ZERO)
		# AI auto-places always. Player auto-places ONLY on maps without
		# base_zones (the legacy boot path). On maps with base_zones the
		# player gets a placement ghost instead - see _enter_hq_placement
		# below. The same auto-place-then-raise-ghost path is the only
		# other thing that calls _place_structure, so this is the one
		# and only place the player-HQ decision lives.
		if team == PLAYER_TEAM and has_zones:
			continue
		_place_structure("hq", team, hq_pos)
	for t in [PLAYER_TEAM, ENEMY_TEAM]:
		economy.recalculate_power(t, get_team_structures(t))

	# Enter the pre-game placement phase for the player on maps that
	# have a base zone assigned. A failed or no-zone map already has
	# the player HQ at the legacy spot, so this is a no-op.
	if has_zones:
		_enter_hq_placement()


# Centre of the zone a slot has been assigned to, in world space. Vector3.ZERO
# on miss (no zone, no map, empty zone) - _spawn_bases() already gates on a
# non-empty zone_id before calling, and the only other caller is the human
# placement hook, which also gates. Keeping the fallthrough silent rather
# than asserting is the right call: the orchestrator is a wrapper around
# map data, and a malformed map is a map data problem, not a runtime one.
func _base_zone_centre(zone_id: String) -> Vector3:
	if zone_id == "":
		return Vector3.ZERO
	var zone: Dictionary = MapCatalog.get_base_zone(current_map, zone_id)
	if zone.is_empty():
		return Vector3.ZERO
	var center: Vector3 = zone.get("center", Vector3.ZERO)
	return center


# Drops the human HQ at `at` and goes live.
#
# The free HQ is the one building the new pre-game phase gives the player
# without spending from the starting bank - the rest of the base (refinery,
# manufactories, harvester) is bought and built normally with the credits
# the bank hands out. This hook is what the placement-UI layer calls when
# the human clicks the ghost:
#   - refuses outside the assigned zone (half_extents-bounded rectangle,
#     because zone shapes are axis-aligned and the math is two absf()s;
#     a non-axis-aligned zone would need a point-in-polygon test, which
#     the FIELD_SPEC doesn't claim to support);
#   - refuses if a live player HQ already exists (the zone assignment
#     pins a single HQ per team, and a second one is a stale ghost);
#   - places via the same _place_structure path the auto-spawn uses, so
#     terrain snap, died.connect and the power recalc are identical.
#
# Returns true on commit, false on refusal. UI layer treats a false
# return as "keep the ghost up" rather than as an error.
#
# WHY NOT GO THROUGH confirm_placement. confirm_placement() pulls the
# build job out of a production queue and decrements resources. The free
# HQ has neither - it is given to the player, not produced. Bypassing
# that path is what makes "free HQ" mean anything, and it is why this
# hook is its own function rather than a flag on begin_placement.
func place_hq_for_human(at: Vector3) -> bool:
	var zone_id: String = _team_base_zone.get(PLAYER_TEAM, "")
	var zone: Dictionary = MapCatalog.get_base_zone(current_map, zone_id)
	if zone.is_empty():
		return false
	var center: Vector3 = zone.get("center", Vector3.ZERO)
	var half: Vector2 = zone.get("half_extents", Vector2.ZERO)
	# Axis-aligned rectangle test. absf()s so the sign of the offset
	# (which side of the centre) doesn't matter - a click on the +X
	# edge and a click on the -X edge are equally "inside" if both
	# are within half.x. Equal halves on either side is what
	# half_extents:Vector2 means; the FIELD_SPEC comment is the
	# contract.
	if absf(at.x - center.x) > half.x or absf(at.z - center.z) > half.y:
		return false
	# One human HQ per match. A second one means a stale ghost or a
	# double-fire on the input layer, both of which are UI bugs -
	# the orchestrator just refuses and lets the caller decide.
	for s in get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and not s.is_dead and s.team == PLAYER_TEAM and s.kind == "hq":
			return false
	_place_structure("hq", PLAYER_TEAM, at)
	economy.recalculate_power(PLAYER_TEAM, get_team_structures(PLAYER_TEAM))
	return true


func _place_structure(kind: String, structure_team: int, at: Vector3) -> Structure:
	var _prof := Profiler.start()
	var s := StructureScript.new()
	add_child(s)
	s.global_position = Vector3(at.x, terrain_height_at(at), at.z)
	s.setup(kind, structure_team)
	s.died.connect(_on_structure_died)
	Profiler.stop("place_structure", _prof)
	# A new live structure can change which designs pass the tech-tree gate
	# (a fresh tech_lab unlocks every tech_lab-gated design, a fresh refinery
	# unlocks nothing, a fresh HQ unlocks nothing, etc.). The HUD's button
	# `disabled` state is set at button-creation time only, so it would stay
	# stale until the HUD rebuilt every button - which it never does.
	# Emitting here lets ProductionHUD re-evaluate the gates immediately on
	# structure placement, rather than on the next 5 Hz refresh tick (200 ms
	# of stale UI is the failure mode the playtest hit).
	structure_built.emit(structure_team, kind)
	return s


func get_team_structures(for_team: int) -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and not s.is_dead and s.team == for_team:
			out.append(s)
	return out


# How far past its own footprint a building's navmesh hole extends.
#
# WHY THIS IS NOT ZERO. The navmesh is baked with NavigationMesh's default
# agent_radius of 0.5 m, so Recast keeps paths only half a metre clear of an
# obstacle - but a vehicle is metres wide and is steered by its ORIGIN. A path
# that is legal for a 0.5 m agent runs straight through the corner of a building
# for a 4 m tank, which then grinds along the collider until something else
# dislodges it. Measured: harvesters wedging on the refinery's corner for 20 s at
# a time, and it is why their dock approach needed a stuck-recovery path at all.
#
# Inflating the HOLE rather than raising agent_radius on the bake is deliberate:
# terrain_builder.gd is shared with the legacy Skirmish runtime and its navmesh
# suites, and agent_radius would also shrink the walkable surface along every
# cliff and shoreline on the map, not just around buildings. This is the same
# correction applied only where the problem actually is.
#
# Sized from the widest hull the roster fields rather than an average - the cost
# of being generous is a slightly wider detour, and the cost of being tight is a
# stuck unit.
const BUILDING_CLEARANCE := 2.5

# Every live structure's footprint, gathered fresh rather than cached. The set
# only changes on placement and death, both of which already trigger a rebake, so
# this is never stale when it actually runs.
func _building_holes() -> Array:
	var holes: Array = []
	for s in get_tree().get_nodes_in_group("structures"):
		# is_inside_tree() guards a real teardown race: queue_free() defers
		# removal to end of frame, so a structure mid-teardown can still be
		# is_instance_valid() while reading global_position throws.
		if not is_instance_valid(s) or s.is_dead or not s.is_inside_tree():
			continue
		holes.append({
			"center": s.global_position,
			"half_extents": Vector2(
				s.footprint.x / 2.0 + BUILDING_CLEARANCE,
				s.footprint.z / 2.0 + BUILDING_CLEARANCE),
		})
	return holes


# --- Runtime navmesh -----------------------------------------------------------
#
# The startup bake carves the STARTING buildings only, because at Phase 0 nothing
# was ever built mid-match. The AI places buildings while the match runs, and a
# structure that is not in the navmesh is one units cheerfully path straight
# through - so placement and death both have to re-carve.
#
# Debounced to end-of-frame rather than run inline: several buildings can go up
# or die in one frame (a blast, a wave completing), and a Recast bake per event
# would be several hundred milliseconds of stall for one identical result.
var _nav_rebake_pending: bool = false

# A LAZY REBAKE, for changes that only OPEN ground.
#
# Measured (tools/probe_death_hitch.gd): killing one building cost a 4139 ms
# frame against a 55 ms idle worst case. The whole of it is this rebake - a
# synchronous Recast pass over the entire map - and end-of-frame debouncing does
# not help, because one death is already one bake.
#
# The asymmetry that makes this fixable: PLACING a building must re-carve
# promptly, or units walk straight through a wall that is visibly there.
# DESTROYING one only frees space. Until the bake catches up, units route around
# a hole where a building no longer stands - which costs them a slightly long way
# round and nothing else. So a death can wait, and several deaths in a firefight
# can wait together and cost ONE bake instead of one each.
const NAV_LAZY_REBAKE_DELAY := 3.0

var _nav_lazy_pending: bool = false
var _nav_lazy_timer: float = 0.0


# `urgent` carves immediately at end of frame; the default defers and coalesces.
# Callers that make ground IMPASSABLE must pass true.
func _mark_navmesh_dirty(urgent: bool = true) -> void:
	if not urgent:
		_nav_lazy_pending = true
		_nav_lazy_timer = 0.0
		return
	if _nav_rebake_pending:
		return
	_nav_rebake_pending = true
	# An urgent bake satisfies any lazy one already waiting.
	_nav_lazy_pending = false
	_rebake_navmesh.call_deferred()


# Runs the deferred bake once the map has been quiet for NAV_LAZY_REBAKE_DELAY.
# The timer RESETS on each new death, so a sustained firefight keeps postponing
# it rather than stalling in the middle of the fight.
func _tick_lazy_navmesh(delta: float) -> void:
	if not _nav_lazy_pending:
		return
	_nav_lazy_timer += delta
	if _nav_lazy_timer < NAV_LAZY_REBAKE_DELAY:
		return
	_nav_lazy_pending = false
	_nav_lazy_timer = 0.0
	_rebake_navmesh()


func _rebake_navmesh() -> void:
	_nav_rebake_pending = false
	if _ground_nav_regions.is_empty():
		return
	# ASYNC. terrain_builder.gd has carried an async twin of this call since the
	# old runtime, written for exactly this situation and documented in its own
	# header as "the mid-match rebake is the one that must not block" - and the
	# battle layer was calling the SYNCHRONOUS one anyway.
	#
	# Measured in a staged engagement: a single mid-match placement stalled one
	# frame for 3940 ms. That is not a dropped frame, it is the game stopping
	# dead, and it lands whenever the AI sites a building - which is why a hitch
	# can appear to coincide with entering combat while having nothing to do with
	# combat.
	#
	# Only the GDScript face generation stays on the main thread; Recast itself
	# goes to a worker. The repath moves into the callback so units are steered
	# against the FINISHED navmesh rather than a half-updated one.
	#
	# Chunk 21: rebakes every tile, not just the one(s) the change touched -
	# selective per-tile rebake (Chunk 22) is a further optimization on top
	# of an already-async, already-non-blocking path, not a correctness
	# requirement (see rebake_ground_amphibious_tiles_async()'s own comment).
	TerrainBuilder.rebake_ground_amphibious_tiles_async(
		current_map, _building_holes(), _ground_nav_regions, _amphibious_nav_regions, _nav_tile_rects,
		_on_navmesh_rebaked)


# Runs when both surfaces have finished baking. Every cached field was sampled
# against the OLD passability, and every live agent is following a path through
# what may now be a wall.
func _on_navmesh_rebaked() -> void:
	if not is_inside_tree():
		return
	flow_fields.invalidate()
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead and u.has_method("request_repath"):
			u.request_repath()


func _on_structure_died(structure) -> void:
	economy.recalculate_power(structure.team, get_team_structures(structure.team))
	# Losing the last contributor to a queue refunds everything in it: that line
	# can never advance again, so holding the money is a bug with extra steps.
	production.cancel_unbuildable(structure.team)
	# See structure_lost comment in the signal declaration. We emit BEFORE
	# the audio / navmesh / end-match work so the HUD's re-eval lands on
	# the same frame the player notices the death, not after the audio
	# line and not after the rebake debounce.
	structure_lost.emit(structure.team, structure.kind)
	# The navmesh had a hole carved for this building and no longer should, and
	# every cached flow field was sampled against the old passability.
	#
	# NOT URGENT. A dead building only frees ground - the worst that happens
	# before the bake lands is that units take the long way round a hole where
	# nothing stands. Baking inline here cost a 4139 ms frame; see
	# NAV_LAZY_REBAKE_DELAY.
	_mark_navmesh_dirty(false)
	# The sincere comms layer reporting a loss, over whatever is still going
	# "pew" out there. CORE_DESIGN_LANGUAGE.md 6.2 calls that pairing the whole
	# thesis in one moment.
	if _audio != null and structure.team == PLAYER_TEAM:
		_audio.play_voice("radio_structure_lost")
	if structure.kind == "hq":
		_end_match(PLAYER_TEAM if structure.team != PLAYER_TEAM else ENEMY_TEAM)


# --- Win condition -----------------------------------------------------------

signal match_ended(winning_team)

# Losing your HQ loses the match.
#
# Driven by the structure's own death signal rather than polled, so there is no
# window in which the HQ is gone and the match has not noticed. Guarded against
# re-entry because both HQs can die in the same frame to the same blast, and the
# first result is the one that counts.
func _end_match(winning_team: int) -> void:
	if game_over:
		return
	game_over = true
	match_ended.emit(winning_team)
	_show_result(winning_team == PLAYER_TEAM)


# The end of a match, as an actual sequence rather than a word on the screen.
#
# WHAT THIS REPLACES. A bare "VICTORY" Label anchored to the top of the HUD, and
# nothing else - no stats, no way out, no acknowledgement that the match was
# over beyond the units stopping. after_action_report.gd has been fully written
# and completely orphaned this whole time (OPERATIONS_PLAN.md names it), because
# nothing produced the per-design statistics it takes. MatchStats does now.
func _show_result(player_won: bool) -> void:
	if battle_hud == null:
		return

	# The banner stays - it lands immediately, while the report needs a beat so
	# the killing blow is actually seen rather than being instantly covered up.
	var banner := Label.new()
	banner.name = "ResultBanner"
	banner.text = "VICTORY" if player_won else "DEFEAT"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 120
	banner.add_theme_color_override("font_color",
		Tokens.SIGNAL_GO if player_won else Tokens.SIGNAL_ALERT)
	battle_hud.add_child(banner)

	_show_after_action_report.call_deferred(player_won)


# How long the result banner is left alone before the report covers it.
const RESULT_BEAT := 2.0


func _show_after_action_report(player_won: bool) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(RESULT_BEAT).timeout
	if not is_inside_tree() or battle_hud == null:
		return

	var report := AfterActionReportScript.new()
	report.name = "AfterActionReport"
	report.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Sized by hand for the same reason both HUDs are - see
	# ProductionHUD.fit_to_viewport(). Parented to battle_hud, which is itself a
	# CanvasLayer child, so there is still no Control rect to anchor against.
	battle_hud.add_child(report)
	report.position = Vector2.ZERO
	report.size = battle_hud.size
	report.mouse_filter = Control.MOUSE_FILTER_STOP

	var duration: float = stats.duration() if stats != null else 0.0
	var rows: Dictionary = stats.to_report() if stats != null else {}

	# The campaign seam, live at last. is_operation was hardcoded `false` here,
	# which is why the report never offered a next engagement and an Operation
	# was a single match with a different setup screen.
	var ops = _operations()
	var in_operation: bool = ops != null and ops.is_active_operation
	if in_operation:
		ops.record_stage_result(_stage_result(player_won, duration, rows))
	report.setup(player_won, duration, rows, in_operation and ops.has_next_stage())
	report.main_menu_requested.connect(_on_report_main_menu)
	report.iterate_requested.connect(_on_report_iterate)
	report.next_stage_requested.connect(_on_report_next_stage)


# The manager, or null outside a campaign. Looked up rather than preloaded so a
# Battle scene instantiated by a test - no autoloads at all in that boot path -
# behaves exactly as a skirmish, which is what it is.
func _operations():
	return get_node_or_null("/root/OperationsManager")


# One engagement's line in the combat log. The per-design rows are the report's;
# the roster lists are what counter-drafting will read, and this is the only
# moment both sides' compositions are still in one place.
func _stage_result(player_won: bool, duration: float, rows: Dictionary) -> Dictionary:
	var player_designs: Array = []
	# THREATS ARE CLASSIFIED NOW, NOT AT DRAFT TIME. The blueprints are in hand
	# here; three engagements later the player may have edited or deleted them,
	# and re-classifying from the library would then describe an army that was
	# never fielded. What the log records is what was actually brought.
	var player_threats: Array = []
	for design in roster:
		player_designs.append(str(design.get("name", "")))
		for tag in CounterDraftScript.threats_of(design):
			player_threats.append(tag)
	var enemy_designs: Array = []
	for design in enemy_roster:
		enemy_designs.append(str(design.get("name", "")))
	return {
		"victory": player_won,
		"duration": duration,
		"designs": rows,
		"player_designs": player_designs,
		"player_threats": player_threats,
		"enemy_designs": enemy_designs,
	}


# "Next Engagement". Advancing is the player's choice, made here rather than at
# match end, so a lost engagement still leaves the campaign where it was until
# they say otherwise.
func _on_report_next_stage() -> void:
	var ops = _operations()
	if ops == null or not ops.advance_to_next_stage():
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	# Through the draft screen, not straight back into a match: re-drafting
	# between rounds is the whole reason an operation is more than a playlist.
	var router = get_node_or_null("/root/SceneRouter")
	if router:
		router.goto("res://scenes/OperationsDraft.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/OperationsDraft.tscn")


func _on_report_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# "Iterate on this design" hands straight back to the Design Lab, which is the
# whole point of reporting per-design stats: the report is a debrief that turns
# into the next edit.
func _on_report_iterate(blueprint_name: String) -> void:
	# Which design the player asked to iterate on is remembered rather than
	# dropped on the floor. queue_blueprint_iteration() had no call site either;
	# the Lab reading it back is a separate, small piece of work, but the choice
	# has to survive the scene change before that can be written at all.
	var ops = _operations()
	if ops != null and blueprint_name != "":
		ops.queue_blueprint_iteration(blueprint_name)
	get_tree().change_scene_to_file("res://scenes/MainLab.tscn")


# --- Stat hooks the units call ------------------------------------------------
#
# Duck-typed from unit.gd, so a unit built standalone in a test needs no stats
# service at all. Player designs only: this is the player's own debrief, and
# folding the opponent's designs into it would make every column meaningless.

func record_combat_damage(victim, source, amount: float, damage_class: String) -> void:
	# Feeds the music as well as the debrief. Damage landing anywhere on the
	# field raises combat heat, which _tick_audio bleeds off again - so the
	# rhythm and lead stems rise during a real engagement and settle afterwards
	# without anything having to decide when a "battle" starts or ends.
	_combat_heat = minf(1.0, _combat_heat + amount * COMBAT_HEAT_PER_DAMAGE)

	if stats == null:
		return
	stats.record_damage(_design_of(source), _design_of(victim), amount, damage_class)


func record_unit_lost(victim, source) -> void:
	if _audio != null and "team" in victim and victim.team == PLAYER_TEAM:
		_audio.play_voice("radio_unit_lost")

	if stats == null:
		return
	if "team" in victim and victim.team == PLAYER_TEAM:
		stats.record_lost(_design_of(victim))
	var killer := _design_of(source)
	# Credited only when the blow names a design AND that design is the player's.
	# Splash from a detonating harvester, or a unit that drove into the sea,
	# lands in nobody's column rather than being guessed at.
	if not killer.is_empty() and "team" in source and source.team == PLAYER_TEAM:
		stats.record_kill(killer)


# The design behind a damage source, which may be a unit, a structure, a bare
# position, or nothing at all.
func _design_of(thing) -> Dictionary:
	if thing == null or thing is Vector3 or not is_instance_valid(thing):
		return {}
	if "blueprint" in thing and thing.blueprint is Dictionary:
		if "team" in thing and thing.team != PLAYER_TEAM:
			return {}
		return thing.blueprint
	return {}


# --- Contracts the economy systems look for ----------------------------------

# --- Resource node work slots ------------------------------------------------
#
# THE SAME PROBLEM AS THE REFINERY BAYS, AT THE OTHER END OF THE LOOP, and the
# first version of this phase fixed only one of them. Docking was reserved, so
# harvesters no longer piled onto the refinery - and then all three drove to the
# nearest ore patch, steered at its exact origin, and stacked there instead
# (measured: 0.12 m apart). Reserving one end of a round trip and not the other
# just moves the scrum.
#
# So a node has work slots on a ring, claimed the same way a bay is, and node
# selection prefers a patch with room. Kept here rather than on resource_node.gd
# because that script is shared with the old Skirmish scene, which this rebuild
# leaves alone.
const NODE_WORK_SLOTS := 4
const NODE_WORK_RADIUS := 3.2

var _node_claims: Dictionary = {}


func _claims_for(node: Node3D) -> Array:
	var key := node.get_instance_id()
	if not _node_claims.has(key):
		var slots: Array = []
		slots.resize(NODE_WORK_SLOTS)
		slots.fill(null)
		_node_claims[key] = slots
	return _node_claims[key]


func claim_node_slot(node: Node3D, unit: Node) -> int:
	if not is_instance_valid(node):
		return -1
	var slots := _claims_for(node)
	for i in range(slots.size()):
		if slots[i] == unit:
			return i
	for i in range(slots.size()):
		# A slot held by a freed unit is reclaimed here, so a harvester dying at
		# an ore patch does not permanently shrink that patch's capacity.
		if slots[i] == null or not is_instance_valid(slots[i]):
			slots[i] = unit
			return i
	return -1


func release_node_slot(node: Node3D, unit: Node) -> void:
	if not is_instance_valid(node):
		return
	var slots := _claims_for(node)
	for i in range(slots.size()):
		if slots[i] == unit:
			slots[i] = null
			return


func node_slot_position(node: Node3D, slot: int) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.ZERO
	if slot < 0:
		return node.global_position
	var angle := TAU * float(slot) / float(NODE_WORK_SLOTS)
	return node.global_position + Vector3(cos(angle), 0.0, sin(angle)) * NODE_WORK_RADIUS


func _free_slots(node: Node3D) -> int:
	var free := 0
	for holder in _claims_for(node):
		if holder == null or not is_instance_valid(holder):
			free += 1
	return free


# Nearest node WITH ROOM, falling back to nearest overall.
#
# Distance alone sends every harvester to the same patch, which is both a traffic
# jam and bad economics - four trucks queueing at one patch while three others
# sit untouched. The occupancy penalty spreads them without needing a scheduler.
func nearest_resource_node(from: Vector3, requester: Node = null) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var best_any: Node3D = null
	var best_any_distance := INF
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(n) or n.amount <= 0:
			continue
		var distance: float = from.distance_to(n.global_position)
		if distance < best_any_distance:
			best_any_distance = distance
			best_any = n
		if requester != null and _free_slots(n) <= 0:
			continue
		# Each occupant makes a patch read as this much further away. Enough that
		# an empty patch a short walk further wins, small enough that a lone
		# harvester does not cross the map to avoid one neighbour.
		var occupied: int = NODE_WORK_SLOTS - _free_slots(n)
		# VALUE-WEIGHTED DISTANCE. A round trip costs the same time whatever is in
		# the hopper, so what a harvester should maximise is credits per trip, not
		# metres saved. Dividing by relative value expresses that as effective
		# distance: oil at 4.0 credits reads at ~0.4x its real distance, lumber at
		# 1.0 reads at 1.5x.
		#
		# WITHOUT THIS THE WHOLE RESOURCE DESIGN INVERTS. Measured: with lumber
		# stands authored close to each base - deliberately, as the safe opening
		# income - pure nearest-node targeting sent every truck to lumber and
		# NOTHING else. Crystal income was exactly 0.00/s across a three-minute
		# run. The cheapest resource on the map won every contest because it was
		# the closest, which is the precise opposite of "resources differ by value
		# density".
		var value_scale: float = ResourceCatalogScript.credits("ore") \
			/ maxf(0.01, ResourceCatalogScript.credits(n.resource_type))
		var score: float = distance * value_scale + float(occupied) * 18.0 \
			- _shortage_pull(requester, n.resource_type)
		if score < best_score:
			best_score = score
			best = n
	return best if best != null else best_any


# How much closer a patch of `resource_type` reads when the team is short of it,
# in metres of effective distance.
#
# WHY A DISTANCE DISCOUNT AND NOT A HARD PREFERENCE. Harvesters used to pick
# purely on distance plus crowding, so a team sitting at zero metal with a full
# crystal stockpile would keep sending every harvester to the crystal patch that
# happened to be nearer - the economy starves on one axis while the other
# overflows, and the player watches it happen with no way to intervene short of
# manual orders.
#
# Expressed as a discount on the score rather than as a filter because the
# alternative - "always take the scarce type" - makes harvesters walk past a
# patch at their feet to cross the map, which costs more income than the
# imbalance did. At SHORTAGE_PULL a completely empty stockpile is worth about
# half the map's short axis; a patch further away than that is still not worth
# the trip.
#
# The ramp is against a REFERENCE stock rather than against the other resource:
# what matters is "can I afford to build things", not which pile is bigger.
# Comparing the two piles directly would have a team with 20 metal and 10 crystal
# behaving as though it were flush.
const SHORTAGE_PULL := 55.0
const SHORTAGE_REFERENCE := 700.0

func _shortage_pull(requester: Node, resource_type: String) -> float:
	if requester == null or economy == null:
		return 0.0
	var team: int = requester.team
	# ONE POOL now, so scarcity is simply "am I broke" rather than "am I broke in
	# the particular currency this patch happens to pay out". `resource_type` is
	# kept in the signature because value weighting in nearest_resource_node()
	# already differentiates the types, and a future rule may want to again.
	var stock: float = float(economy.credits(team))
	var scarcity: float = clampf(1.0 - stock / SHORTAGE_REFERENCE, 0.0, 1.0)
	return scarcity * SHORTAGE_PULL


func nearest_refinery(from: Vector3, for_team: int) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for s in get_team_structures(for_team):
		if s.kind != "refinery":
			continue
		var d: float = from.distance_squared_to(s.global_position)
		if d < best_distance:
			best_distance = d
			best = s
	return best


func deliver(for_team: int, amount: int) -> void:
	economy.credit(for_team, amount)


func structures_of_kinds(for_team: int, kinds: Array) -> Array:
	var out: Array = []
	for s in get_team_structures(for_team):
		if s.kind in kinds:
			out.append(s)
	return out


# Anything parked on a finished unit's exit. A completed job waits rather than
# spawning a unit on top of whatever is sitting there.
func exit_blockers_for(for_team: int, queue_name: String) -> Array:
	var factory := _exit_structure(for_team, queue_name)
	if factory == null:
		return []
	var out: Array = []
	var exit := factory.exit_position()
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead and u.global_position.distance_to(exit) < 3.5:
			out.append(u)
	return out


# Blockers get a real shove rather than being silently phased through.
func nudge_blockers(for_team: int, queue_name: String, blockers: Array) -> void:
	var factory := _exit_structure(for_team, queue_name)
	if factory == null:
		return
	var exit := factory.exit_position()
	for u in blockers:
		if not is_instance_valid(u):
			continue
		var blocker_pos: Vector3 = u.global_position
		var away := blocker_pos - exit
		away.y = 0.0
		if away.length() < 0.01:
			away = Vector3(1, 0, 0)
		orders.move([u], u.global_position + away.normalized() * 6.0)


func _exit_structure(for_team: int, queue_name: String) -> Structure:
	var candidates := structures_of_kinds(for_team, BuildingCatalogScript.contributors_for(queue_name))
	return candidates[0] if not candidates.is_empty() else null


# A finished building, waiting for somewhere to go.
#
# The AI sites its own immediately. The PLAYER's raises a ghost and waits for a
# click - the player chooses where their buildings go, and until they do the job
# stays at the head of its queue, paid for and blocking that line. That block is
# deliberate (see ProductionService.claim_structure) and is now visible to the
# player as a ghost on their cursor rather than as a queue that silently stopped.
func _on_structure_ready(for_team: int, queue_name: String, job: Dictionary) -> void:
	if for_team == PLAYER_TEAM:
		begin_placement(queue_name, job)
		return
	var site := _ai_placement_site(for_team, job.get("kind", ""), job.get("blueprint", {}))
	if site == Vector3.INF:
		# Nowhere to put it. Leave it claimed-but-unplaced rather than dropping
		# the money; the site may open up when something dies.
		return
	production.claim_structure(for_team, queue_name)
	var blueprint: Dictionary = job.get("blueprint", {})
	if not blueprint.is_empty():
		_place_defence(blueprint, for_team, site)
	else:
		_place_structure(job.get("kind", "power_plant"), for_team, site)
	economy.recalculate_power(for_team, get_team_structures(for_team))
	_mark_navmesh_dirty()


# --- Player ghost placement ---------------------------------------------------
#
# A finished player building follows the cursor until it is put somewhere. This
# is the flow the rebuild was missing entirely: the AI sited its own buildings
# and the player's completed jobs parked their queue forever.
#
# THE MONEY IS ALREADY SPENT by the time a ghost appears. Production drip-feeds
# cost across the build, so a job that reached `done` has paid in full - the
# ghost is not a purchase prompt, it is a delivery waiting for an address.
# Cancelling therefore does NOT refund; it leaves the job at the head of its
# queue for the player to place later, which is also what happens if they simply
# ignore it. Refunding on Escape would let a player bank a completed building at
# no tempo cost, which is a money printer with extra steps.

const GHOST_COLOR_VALID := Color(0.35, 0.85, 0.45, 0.45)
const GHOST_COLOR_INVALID := Color(0.9, 0.3, 0.25, 0.45)

var placing: Dictionary = {}
var placement_ghost: MeshInstance3D = null

signal placement_started(kind: String)
signal placement_finished(kind: String, placed: bool)

# A live structure was just added (post-_place_structure) or just lost
# (post-_on_structure_died, before the queue cancellation runs). The HUD
# listens to this to re-evaluate its tech-tree gates - a placed tech_lab
# flips every tech_lab-gated design from "disabled" to "live", and a lost
# tech_lab flips them back. team is the owning team, kind is the catalog
# id of the structure (so the HUD can filter on tech_lab/physics_lab/
# exotics_lab if it ever wants to - the current re-eval runs over the
# full set, which is correct because any structure can in principle
# unblock some gate).
signal structure_built(team: int, kind: String)
signal structure_lost(team: int, kind: String)


func is_placing() -> bool:
	return not placing.is_empty()


# Raises the ghost for a finished job. Public because the probe and the tests
# drive it directly - a placement flow that can only be entered by waiting out a
# real build is a placement flow nothing can assert.
func begin_placement(queue_name: String, job: Dictionary) -> void:
	# One at a time. A second finished building while the first is still in hand
	# waits its turn at the head of its own queue rather than replacing the ghost,
	# which would silently strand the first one.
	if is_placing():
		return
	placing = {
		"queue": queue_name,
		"kind": job.get("kind", "power_plant"),
		"blueprint": job.get("blueprint", {}),
	}
	_build_ghost()
	placement_started.emit(placing["kind"])
	_flash("PLACE BUILDING  -  LEFT CLICK TO SITE, ESC TO HOLD")


# Picks a held building back up. A player who pressed Escape, or who was busy
# when the job finished, needs a way back to the ghost - without this the "hold"
# in cancel_placement() is indistinguishable from losing the building.
func resume_placement(queue_name: String) -> bool:
	if is_placing():
		return false
	var q: Array = production.queue(PLAYER_TEAM, queue_name)
	if q.is_empty():
		return false
	var job: Dictionary = q[0]
	if not job.get("is_structure", false) or not job.get("done", false):
		return false
	begin_placement(queue_name, job)
	return true


func _build_ghost() -> void:
	_clear_ghost()
	var footprint: Vector3 = PlacementServiceScript.footprint_for(
		placing["kind"], placing["blueprint"])
	placement_ghost = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = footprint
	placement_ghost.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = GHOST_COLOR_INVALID
	# Unshaded so the tint reads as a validity signal rather than as lighting. A
	# green ghost in shadow and a red one in sun are otherwise hard to tell apart,
	# which defeats the entire point of colouring it.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	placement_ghost.material_override = mat
	add_child(placement_ghost)


func _clear_ghost() -> void:
	if is_instance_valid(placement_ghost):
		placement_ghost.queue_free()
	placement_ghost = null


# Moves the ghost to wherever the cursor is over the ground, and recolours it by
# the SAME validity call the click uses - so the ghost can never show green over
# a spot the click then refuses.
func update_placement(screen_pos: Vector2) -> void:
	if not is_placing() or not is_instance_valid(placement_ghost):
		return
	var hit := _raycast(screen_pos, LayersScript.GROUND_PICK_MASK, false)
	if hit.is_empty():
		return
	var at: Vector3 = hit.position
	at.y = terrain_height_at(at)
	var result := placement_validity(at)
	# Sat on the ground rather than centred in it, or half of every building is
	# buried and the footprint reads as too small.
	placement_ghost.global_position = at + Vector3(0, placement_ghost.mesh.size.y * 0.5, 0)
	placement_ghost.material_override.albedo_color = \
		GHOST_COLOR_VALID if result["valid"] else GHOST_COLOR_INVALID


func placement_validity(at: Vector3) -> Dictionary:
	if not is_placing():
		return {"valid": false, "reason": "NOTHING TO PLACE"}
	return PlacementServiceScript.validity(
		self, PLAYER_TEAM, at, placing["kind"], placing["blueprint"])


# Commits the ghost. Returns false and leaves the job in hand if the spot is
# illegal, so a misclick costs nothing.
func confirm_placement(at: Vector3) -> bool:
	if not is_placing():
		return false
	at.y = terrain_height_at(at)
	var result := placement_validity(at)
	if not result["valid"]:
		_flash(result["reason"])
		return false

	# Claim only once the site is known good. Claiming first and then failing to
	# place would pop the job off its queue and destroy a paid-for building.
	var job: Dictionary = production.claim_structure(PLAYER_TEAM, placing["queue"])
	if job.is_empty():
		# The queue moved under us - the job was cancelled, or its last contributor
		# died and refunded the line. Drop the ghost rather than placing a building
		# nothing is paying for.
		_end_placement(false)
		return false

	var blueprint: Dictionary = placing["blueprint"]
	var kind: String = placing["kind"]
	if not blueprint.is_empty():
		_place_defence(blueprint, PLAYER_TEAM, at)
	else:
		_place_structure(kind, PLAYER_TEAM, at)
	economy.recalculate_power(PLAYER_TEAM, get_team_structures(PLAYER_TEAM))
	_mark_navmesh_dirty()
	_end_placement(true)
	return true


# Puts the ghost down without placing. The job stays at the head of its queue,
# still paid for - see the note above on why this does not refund.
func cancel_placement() -> void:
	if not is_placing():
		return
	_flash("BUILDING HELD  -  CLICK ITS QUEUE TO PLACE")
	_end_placement(false)


func _end_placement(placed: bool) -> void:
	var kind: String = placing.get("kind", "")
	placing = {}
	_clear_ghost()
	placement_finished.emit(kind, placed)


# --- Pre-game HQ placement ---------------------------------------------------
#
# The pre-game phase is its own placement mode, NOT a sibling of the build-queue
# ghost. Three reasons it sits in its own state:
#   1. The HQ is FREE. It is given to the player, not produced - so the path
#      cannot go through confirm_placement() (which claims a job from a
#      production queue and decrements resources). The whole flow is its own
#      chain: begin_hq_placement -> update_hq_placement -> confirm_hq_placement
#      which ends at place_hq_for_human().
#   2. The validity rule is ZONE-CONSTRAINED, not the standard
#      PlacementServiceScript.validity() block-tests / no-overlap / etc. The
#      player must drop the HQ INSIDE their assigned half_extents rectangle
#      (place_hq_for_human already enforces this - the ghost just visualises
#      the rule, never re-implements it).
#   3. The ghost needs TWO meshes, not one: the HQ footprint following the
#      cursor, AND a wireframe of the assigned base zone. The wireframe is
#      what tells the player "drop it here" - a 15x15 rectangle is a much
#      stronger affordance than a single HQ ghost hovering over empty ground.
#
# Mouse wiring reuses the same _unhandled_input switch as the build-queue
# placement - a separate code path is unnecessary because the only thing
# different about pre-game clicks is which commit function runs at the end.
var placing_hq: bool = false
var hq_ghost: MeshInstance3D = null
var hq_zone_outline: MeshInstance3D = null
var hq_ghost_pos: Vector3 = Vector3.ZERO  # last valid (clamped) position; survives raycast misses

# A pre-game HQ placement lifecycle signal. The BattleHUD listens to
# this to swap its prompt banner between "DROP YOUR HQ IN THE HIGHLIGHTED
# ZONE" (placement_started) and the normal in-match UI (placement_finished
# with placed=true). The signal name mirrors placement_started/finished so
# the HUD can use a single subscription pattern for both phases.
signal hq_placement_started
signal hq_placement_finished(placed: bool)


func is_placing_hq() -> bool:
	return placing_hq


# Arms the pre-game phase. Called from _spawn_bases() after the base-zone
# assignment on maps that HAVE base zones; no-op otherwise. The same input
# flow as build-queue placement takes over from here.
func _enter_hq_placement() -> void:
	if placing_hq:
		return
	# Don't enter pre-game placement in Test Range. Test Range drives its
	# own spawn flow and expects the player HQ to be live from frame 1.
	# _match_rule_set is the cached rule set from _ready(); reading from
	# the member is the same pattern _spawn_bases() and _setup_vision()
	# use to gate on mode. Also guard on null for headless test paths.
	if _match_rule_set != null and _match_rule_set.mode == MatchRuleSetScript.Mode.TEST_RANGE:
		return
	placing_hq = true
	_build_hq_zone_outline()
	_build_hq_ghost()
	hq_placement_started.emit()
	_flash("PLACE YOUR HQ  -  CLICK IN THE HIGHLIGHTED ZONE")


# Public. The BattleHUD or any test driver can call this to drop out
# of the pre-game phase without placing (cancels). Used by the AI-vs-AI
# smoke path and by the "skip pre-game" affordance if one is ever added.
func cancel_hq_placement() -> void:
	if not placing_hq:
		return
	_exit_hq_placement(false)


# Ground-following ghost. Same raycast + ground-pick as update_placement;
# the difference is what happens after the raycast lands:
#   - the ground hit is CLAMPED to the assigned base zone (a point outside
#     the half_extents rectangle is dragged to the closest point inside it,
#     so the ghost slides along the zone edge instead of going red);
#   - the ghost is recoloured by the zone test, not the placement service.
# This is why there is no _ghosting helper for both: the colour logic is
# a 2-line zone test, not the multi-rule block-tests the build queue runs.
func update_hq_placement(screen_pos: Vector2) -> void:
	if not placing_hq or not is_instance_valid(hq_ghost):
		return
	var hit := _raycast(screen_pos, LayersScript.GROUND_PICK_MASK, false)
	if hit.is_empty():
		return
	hq_ghost_pos = _clamp_to_player_zone(hit.position)
	hq_ghost.global_position = Vector3(
		hq_ghost_pos.x,
		terrain_height_at(hq_ghost_pos),
		hq_ghost_pos.z)
	# Colour by the SAME test the click uses - the ghost never lies
	# about whether the click will go through. Inside the zone = green,
	# outside = red. After the clamp above the ghost is ALWAYS inside
	# the zone, so the red branch is effectively dead code, but kept
	# for the future where the zone might be a non-axis-aligned polygon
	# that the clamp can't handle.
	var inside: bool = _is_inside_player_zone(hq_ghost_pos)
	hq_ghost.material_override.albedo_color = \
		GHOST_COLOR_VALID if inside else GHOST_COLOR_INVALID


# Public. The click handler routes here from _unhandled_input when
# placing_hq is true. place_hq_for_human does the actual placement and
# the validity check - this wrapper just gates the path and exits the
# placement mode on success.
func confirm_hq_placement() -> bool:
	if not placing_hq:
		return false
	if place_hq_for_human(hq_ghost_pos):
		_exit_hq_placement(true)
		return true
	return false


# Tear-down. Symmetric with _end_placement above. The wireframe is the
# last thing the player sees in the pre-game phase, so it's freed last
# (queue_free order is LIFO, so the wireframe at the bottom of this
# function is actually freed first - on the next frame, the HQ ghost
# disappears, then the zone outline).
func _exit_hq_placement(placed: bool) -> void:
	placing_hq = false
	if is_instance_valid(hq_ghost):
		hq_ghost.queue_free()
	hq_ghost = null
	if is_instance_valid(hq_zone_outline):
		hq_zone_outline.queue_free()
	hq_zone_outline = null
	hq_placement_finished.emit(placed)


# The zone visual: a thin hollow box outline at the player's base zone.
# Hollow is critical - a solid box would HIDE the ground under the zone,
# which is the worst possible affordance for a "drop your HQ here" hint.
# An outline draws on top of the ground without occluding it.
func _build_hq_zone_outline() -> void:
	var zone_id: String = _team_base_zone.get(PLAYER_TEAM, "")
	if zone_id == "":
		return
	var zone: Dictionary = MapCatalog.get_base_zone(current_map, zone_id)
	if zone.is_empty():
		return
	var center: Vector3 = zone.get("center", Vector3.ZERO)
	var half: Vector2 = zone.get("half_extents", Vector2.ZERO)
	# Box mesh with size = 2 * half + a little Y so the box is thin (flat
	# on the ground, not a 30m tall column).
	var outline := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(half.x * 2.0, 0.05, half.y * 2.0)
	outline.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.35, 0.85, 0.45, 0.25)  # green tint, transparent
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.material_override = mat
	outline.global_position = Vector3(center.x, terrain_height_at(center) + 0.03, center.z)
	# No shadow casting. The wireframe is a UI affordance, not a 3D object.
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outline)
	hq_zone_outline = outline


# The HQ ghost itself: a flat box sized to the HQ's footprint, follows
# the cursor (clamped to the zone), recoloured by the zone test. Same
# shader / material pattern as the build-queue ghost - same unshaded +
# transparent tints so the green-vs-red reads the same to the player.
func _build_hq_ghost() -> void:
	var footprint: Vector3 = PlacementServiceScript.footprint_for("hq", {})
	hq_ghost = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = footprint
	hq_ghost.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = GHOST_COLOR_INVALID
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hq_ghost.material_override = mat
	hq_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hq_ghost)


# Clamp a point to the player's base zone (axis-aligned half_extents
# rectangle). The clamp drags an outside point to the closest point
# inside, so a player dragging the cursor just past the zone edge
# sees the ghost slide along the edge rather than flip red.
func _clamp_to_player_zone(p: Vector3) -> Vector3:
	var zone_id: String = _team_base_zone.get(PLAYER_TEAM, "")
	if zone_id == "":
		return p
	var zone: Dictionary = MapCatalog.get_base_zone(current_map, zone_id)
	if zone.is_empty():
		return p
	var center: Vector3 = zone.get("center", Vector3.ZERO)
	var half: Vector2 = zone.get("half_extents", Vector2.ZERO)
	var clamped_x: float = clampf(p.x, center.x - half.x, center.x + half.x)
	var clamped_z: float = clampf(p.z, center.z - half.y, center.z + half.y)
	return Vector3(clamped_x, p.y, clamped_z)


# Inside-the-zone test, mirroring place_hq_for_human's own absf() check.
# The double implementation is intentional: a future non-axis-aligned
# zone shape would change this test but not place_hq_for_human, and the
# ghost would then LIE about whether the click will go through. Both
# need to be updated in lockstep, which is what the comment on
# place_hq_for_human is for.
func _is_inside_player_zone(p: Vector3) -> bool:
	var zone_id: String = _team_base_zone.get(PLAYER_TEAM, "")
	if zone_id == "":
		return false
	var zone: Dictionary = MapCatalog.get_base_zone(current_map, zone_id)
	if zone.is_empty():
		return false
	var center: Vector3 = zone.get("center", Vector3.ZERO)
	var half: Vector2 = zone.get("half_extents", Vector2.ZERO)
	return absf(p.x - center.x) <= half.x and absf(p.z - center.z) <= half.y


# A blueprint-built turret. Same lifecycle as any other structure - it carves the
# navmesh, it dies through the same signal, it ends the match if it were an HQ -
# it just gets its geometry and its guns from a design instead of the catalog.
func _place_defence(blueprint: Dictionary, structure_team: int, at: Vector3) -> Structure:
	var s := StructureScript.new()
	add_child(s)
	s.global_position = Vector3(at.x, terrain_height_at(at), at.z)
	if not s.setup_from_blueprint(blueprint, structure_team, bp_manager):
		# The design names a hull the catalog no longer has. A half-built turret
		# is worse than none, and the money is already spent either way.
		s.queue_free()
		return null
	s.died.connect(_on_structure_died)
	return s


# Queue a defensive structure from the AI's roster.
func ai_build_defence(for_team: int) -> bool:
	var design := ai_design_for_role(for_team, "defense")
	if design.is_empty():
		return false
	var cost: int = DesignCostingScript.blueprint_cost(design)
	return not production.enqueue_structure(for_team,
		BuildingCatalogScript.QUEUE_DEFENSE, "defense",
		cost, DesignCostingScript.build_time_for_cost(cost), design).is_empty()


# Where the AI puts its next building. Delegates to PlacementService, which is
# the same call the player's ghost validates against - so the AI is held to the
# player's rules rather than to a looser private copy. It previously had one: a
# bounds/water/overlap check that ignored buildable-area adjacency entirely, and
# would happily site a power plant six rings out in open field.
func _ai_placement_site(for_team: int, kind: String, blueprint: Dictionary = {}) -> Vector3:
	return PlacementServiceScript.find_site(
		self, for_team, _team_home(for_team), kind, blueprint)


func _on_unit_completed(for_team: int, queue_name: String, blueprint: Dictionary) -> void:
	var factory := _exit_structure(for_team, queue_name)
	var at: Vector3 = factory.exit_position() if factory != null else Vector3.ZERO
	spawn_unit(blueprint, for_team, snap_to_navmesh(at))


# The nearest genuinely walkable point to `at`.
#
# A unit spawned off the navmesh is not merely misplaced, it is inert: the agent
# has no valid path start, so it accepts a move order and turns to face it but
# never produces a waypoint it can leave. exit_position() is authored as a fixed
# offset from the building centre, while the hole the building actually carves
# depends on BUILDING_CLEARANCE, the navmesh grid quantisation and Recast's own
# agent-radius erosion - three things the authored constant cannot see, and all
# of which move with world scale. Snapping makes the spawn correct by
# construction instead of by a margin that has now been re-tuned twice.
#
# The snap is refused if the nearest walkable point is implausibly far, which
# means the navmesh is not built yet rather than that the exit is blocked;
# spawning at the authored point is the better failure there.
const MAX_SPAWN_SNAP := 25.0

func snap_to_navmesh(at: Vector3) -> Vector3:
	if not ground_nav_map.is_valid():
		return at
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(ground_nav_map, at)
	if Vector3(closest.x, 0.0, closest.z).distance_to(Vector3(at.x, 0.0, at.z)) > MAX_SPAWN_SNAP:
		return at
	return closest


# Radial area damage. Used by the loaded-harvester detonation; the same call will
# serve splash weapons when they land.
func apply_explosion(at: Vector3, radius: float, damage: float, source: Node) -> void:
	for target in get_tree().get_nodes_in_group("damageable"):
		if target == source or not is_instance_valid(target) or target.is_dead:
			continue
		if not target.has_method("take_damage"):
			continue
		var distance: float = at.distance_to(target.global_position)
		if distance > radius:
			continue
		# Linear falloff to zero at the rim, so standing at the edge of a blast
		# is meaningfully better than standing in it.
		#
		# Explosive class, and the blast centre as the hit origin, so a splash hit
		# gets the same facet-aware treatment a direct one does - catching a tank
		# from behind with a shell should be worth what it is worth.
		target.take_damage(damage * (1.0 - distance / radius), "explosive", at)


# --- AI support --------------------------------------------------------------
#
# Everything the Commander can do to the world, and nothing more. Each of these
# forwards to the SAME service the player's own UI calls - ProductionService to
# build, OrderService to command - so there is no second path where AI-only
# behaviour could accumulate. That is the structural reason the AI cannot cheat,
# as opposed to a promise that it will not.

# Queue a design filling `role`, chosen from the AI's roster by what it actually
# mounts rather than from a hand-curated per-role list. A design the player built
# would count as anti-air if it carries a CIWS.
func ai_build_unit(for_team: int, role: String) -> bool:
	var pick: Dictionary = ai_design_for_role(for_team, role)
	# No design fills the role - fall back to any VEHICLE rather than stalling.
	# An AI that refuses to build because it has no dedicated AA is worse than
	# one that builds a tank. Routed through ai_design_for_role so the fallback
	# cannot land on a turret and try to drive it out of a factory.
	if pick.is_empty():
		pick = ai_design_for_role(for_team, "general")
	if pick.is_empty():
		return false

	var cost: int = DesignCostingScript.blueprint_cost(pick)
	var queue_name: String = DesignCostingScript.queue_for_design(pick)

	# SELF-THROTTLE. The commander re-decides every DECISION_INTERVAL and calls
	# this each time, so without a depth cap it enqueues another unit every two
	# seconds forever. Production drip-feeds cost, so a deep queue drains every
	# credit as it arrives: the AI sat pinned at 0 credits with three harvesters
	# queued, and every other action - which all gate on having money - was
	# vetoed. It looked like an AI with one idea and was really an AI that had
	# spent everything before it could have a second one.
	#
	# Two deep, the same cap the old runtime used (enemy_ai.gd's _queue_entry).
	if production.queue(for_team, queue_name).size() >= AI_MAX_QUEUE_DEPTH:
		return false
	return not production.enqueue_unit(for_team, pick, cost,
		DesignCostingScript.build_time_for_cost(cost), queue_name).is_empty()


const AI_MAX_QUEUE_DEPTH := 2


# A design on a foundation hull is a static defence, not a vehicle.
#
# Worth a named helper rather than an inline check, because the two places that
# need it fail in completely different and equally quiet ways: spawning one as a
# starting unit gives you an immobile thing that looks like a unit, and queueing
# one into a VEHICLE queue produces a turret that tries to drive out of a
# factory exit.
static func is_defence_design(blueprint: Dictionary) -> bool:
	return ModuleCatalog.is_foundation(blueprint.get("hull_type", ""))


# The design the AI would build for `role`, or {} if it has none.
#
# Foundations are excluded from every MOBILE role, including the catch-all
# "general" - design_fills_role() answers true for anything there, so without
# this filter the AI could pick a gun turret as its general-purpose tank.
func ai_design_for_role(for_team: int, role: String) -> Dictionary:
	var pool: Array = enemy_roster if not enemy_roster.is_empty() else roster
	var want_defence := role == "defense"
	for design in pool:
		if is_defence_design(design) != want_defence:
			continue
		if want_defence or CommanderScript.design_fills_role(design, role):
			return design
	return {}


# Can the AI actually PRODUCE something filling `role` right now - not "does a
# design exist" but "is there a factory that can build it".
#
# The distinction is the whole reason this exists. The AI's only harvester is a
# MEDIUM hull, so owning a light manufactory and a harvester design still means
# it cannot build one. Without this the commander scored "build a harvester"
# highest, called a production path that silently returned false, and starved to
# zero metal while deciding to fix its economy every two seconds.
func ai_can_build_role(for_team: int, role: String) -> bool:
	var design := ai_design_for_role(for_team, role)
	if design.is_empty():
		return false
	return production.contributor_count(for_team,
		DesignCostingScript.queue_for_design(design)) > 0


# Which manufactory to put up next.
#
# Resolved HERE rather than in the commander, so the commander can stay at the
# altitude of "I need more production" without knowing about hull tiers. It
# builds whatever unblocks the harvester first - an economy that cannot start is
# the only truly fatal state - and otherwise fills in the tiers it lacks.
func ai_build_production(for_team: int) -> bool:
	var wanted := ""
	var harvester := ai_design_for_role(for_team, "harvester")
	if not harvester.is_empty() and not ai_can_build_role(for_team, "harvester"):
		wanted = _manufactory_for_queue(DesignCostingScript.queue_for_design(harvester))
	if wanted == "":
		for queue_name in [BuildingCatalogScript.QUEUE_LIGHT,
				BuildingCatalogScript.QUEUE_MEDIUM, BuildingCatalogScript.QUEUE_HEAVY]:
			if production.contributor_count(for_team, queue_name) <= 0:
				wanted = _manufactory_for_queue(queue_name)
				break
	# Every tier covered - add another of the cheapest, which speeds that queue up
	# via the RA table rather than opening a second line.
	if wanted == "":
		wanted = "light_manufactory"
	return ai_build_structure(for_team, wanted)


func _manufactory_for_queue(queue_name: String) -> String:
	var kinds: Array = BuildingCatalogScript.CONTRIBUTORS.get(queue_name, [])
	return kinds[0] if not kinds.is_empty() else "light_manufactory"


func ai_build_structure(for_team: int, kind: String) -> bool:
	var stats := BuildingCatalogScript.get_stats(kind)
	if stats.is_empty():
		return false
	return not production.enqueue_structure(for_team,
		BuildingCatalogScript.QUEUE_BUILDING, kind,
		ResourceCatalogScript.credits_from_materials(Vector2i(
			stats.get("cost_metal", 0), stats.get("cost_crystal", 0))),
		stats.get("build_time", 10.0)).is_empty()


# Pull everything home. The rally is the AI's own HQ, which is the thing worth
# defending - losing it ends the match.
func ai_defend(for_team: int, combat: Array) -> void:
	var home := _team_home(for_team)
	_ai_squad(for_team, combat, home).objective = home


# Commit to an attack on the enemy HQ.
func ai_push(for_team: int, combat: Array) -> void:
	var target := _team_home(PLAYER_TEAM if for_team != PLAYER_TEAM else ENEMY_TEAM)
	_ai_squad(for_team, combat, _team_home(for_team)).objective = target


func _team_home(for_team: int) -> Vector3:
	for s in get_team_structures(for_team):
		if s.kind == "hq":
			return s.global_position
	var spawn := MapCatalog.get_spawn(current_map,
		"player" if for_team == PLAYER_TEAM else "enemy")
	return spawn.get("hq", Vector3.ZERO) if not spawn.is_empty() else Vector3.ZERO


# One squad per AI team, rebuilt from whatever is alive. Kept as a live object
# rather than re-created each decision so its state - retreating, regrouping, and
# the peak health those are measured against - survives between ticks.
func _ai_squad(for_team: int, combat: Array, rally: Vector3):
	if not _squads.has(for_team) or _squads[for_team].is_spent():
		var squad = SquadScript.new()
		squad.setup(self, orders, for_team, combat, rally)
		_squads[for_team] = squad
	else:
		_squads[for_team].reinforce(combat)
	return _squads[for_team]


# --- Weapon support ----------------------------------------------------------
#
# auto_weapon.gd duck-types every one of these off `get_tree().current_scene` and
# guards each with has_method(), so a missing one degrades rather than crashes.
# That is exactly why they are worth writing down: the degraded behaviours are
# silent and individually plausible - weapons that never miss a fog check,
# defences that ignore low power - so an absent method reads as a balance
# problem rather than as a missing method.

# Two teams, so alliance is equality. The legacy runtime carries a real alliance
# table for multi-slot matches; that ports with the slot system, not before it,
# and pretending otherwise here would be a stub that looks finished.
func is_allied(a: int, b: int) -> bool:
	return a == b


# Whether `viewing_team` can currently see `c`. Delegated, and fails open when
# there is no vision service at all - a unit built in a synthetic test has no fog
# to hide behind, and refusing to let its weapons fire would be a strange way to
# express that.
func is_visible_to_team(c: Node, viewing_team: int) -> bool:
	return vision == null or vision.is_visible_to_team(c, viewing_team)


# Reveal a patch of map for a while. Illumination ammo and sensor beacons.
func reveal_area(for_team: int, pos: Vector3, radius: float, duration: float) -> void:
	if vision != null:
		vision.reveal_area(for_team, pos, radius, duration)


# Whether this team's defences should be firing at reduced effect. Delegated so
# there is one definition of "low power" and the HUD, production and weapons all
# read the same one.
func is_low_power(for_team: int) -> bool:
	return economy != null and economy.is_low_power(for_team)


# Damageable things near `pos`, for weapon target acquisition.
#
# UNITS come from the neighbour grid the movement layer already rebuilds every
# tick - an adapter over it, not a second spatial index, because two grids over
# the same units is two chances to go stale in different directions.
#
# STRUCTURES are scanned directly, because they are deliberately NOT in that
# grid. The grid feeds separation steering, which is about units flowing around
# each other; putting buildings in it would have units treat their own base as a
# crowd to squeeze through. There are tens of structures, not hundreds, and they
# do not move, so a flat scan costs nothing worth indexing away.
#
# Leaving them out entirely is the trap here: weapons would silently be unable to
# shoot buildings, which reads as "the AI ignores my base" rather than as a
# missing branch, and it makes the HQ - the win condition - invulnerable.
func get_nearby_damageable(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var cells := int(ceil(radius / NEIGHBOUR_CELL))
	var centre := _grid_key(pos)
	for dz in range(-cells, cells + 1):
		for dx in range(-cells, cells + 1):
			var bucket: Array = _neighbour_grid.get(centre + Vector2i(dx, dz), [])
			for n in bucket:
				if is_instance_valid(n) and pos.distance_to(n.global_position) <= radius:
					out.append(n)
	for s in get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and not s.is_dead and pos.distance_to(s.global_position) <= radius:
			out.append(s)
	return out


# --- Per-tick bookkeeping ----------------------------------------------------

func _physics_process(delta: float) -> void:
	if game_over:
		return
	_tick_audio(delta)

	var t := Profiler.start()
	_rebuild_neighbour_grid()
	Profiler.stop("neighbour_grid", t)

	t = Profiler.start()
	_tick_lazy_navmesh(delta)
	Profiler.stop("navmesh", t)

	if stats:
		stats.tick(delta)
	if economy:
		# Ages the income accumulators. Must run BEFORE production draws this tick's
		# cost, so the rate reflects what came in rather than what is left after
		# spending it - the distinction the whole measure exists to make.
		economy.tick_income(delta)
	if production:
		t = Profiler.start()
		production.tick(delta)
		Profiler.stop("production", t)
	if commander:
		t = Profiler.start()
		commander.tick(delta)
		Profiler.stop("commander", t)
	# Squads tick every frame while the commander re-decides every couple of
	# seconds: the macro choice is slow, but a squad deciding to retreat cannot
	# wait two seconds for the next decision window.
	t = Profiler.start()
	for squad in _squads.values():
		squad.tick(delta)
	Profiler.stop("squads", t)

	# LAST in the director's tick. Units and weapons own their own
	# _physics_process and the engine runs a parent before its children, so this
	# closes the frame on everything: whatever the sections above do not account
	# for shows up as the gap between their sum and the frame total.
	Profiler.end_frame()


# A coarse bucket grid, rebuilt from scratch each tick rather than maintained
# incrementally. Rebuilding is O(n) and needs no invalidation; maintaining is
# O(1) per move but has to be told about every spawn, death and teleport, and one
# missed notification leaves a phantom neighbour shoving at nothing forever.
func _rebuild_neighbour_grid() -> void:
	_neighbour_grid.clear()
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or u.is_dead:
			continue
		var key := _grid_key(u.global_position)
		if not _neighbour_grid.has(key):
			_neighbour_grid[key] = []
		_neighbour_grid[key].append(u)


func _grid_key(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / NEIGHBOUR_CELL)), int(floor(pos.z / NEIGHBOUR_CELL)))


# --- Contracts the unit runtime looks for (movement side) --------------------

# Positions of other units close enough to crowd `unit`. Positions rather than
# nodes: separation only needs the geometry, and handing out node references
# invites the movement layer to start reading state off its neighbours.
func neighbour_positions(unit: Node3D, radius: float) -> Array:
	var out: Array = []
	var centre := _grid_key(unit.global_position)
	var radius_sq := radius * radius
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var bucket = _neighbour_grid.get(Vector2i(centre.x + dx, centre.y + dy))
			if bucket == null:
				continue
			for other in bucket:
				if other == unit or not is_instance_valid(other):
					continue
				var other_pos: Vector3 = other.global_position
				var offset := other_pos - unit.global_position
				offset.y = 0.0
				if offset.length_squared() <= radius_sq:
					out.append(other_pos)
	return out


# The shared field direction for an order's group, or ZERO if that group is too
# small to have one.
func flow_direction_for(order: Order, at: Vector3) -> Vector3:
	if flow_fields == null or order.group_id == 0:
		return Vector3.ZERO
	# Trip length gates the field as much as group size does: over a short hop the
	# search covers the whole reachable map to save a dozen cheap corridor
	# searches, and the convergence it causes is paid for nothing.
	#
	# This is the length recorded when the order was issued, NOT the distance still
	# to run - see Order.trip_length for why the difference matters.
	var field: FlowField = flow_fields.field_for(
		order.group_destination, _group_size(order.group_id), order.trip_length)
	if field == null or not field.has_route(at):
		return Vector3.ZERO
	return field.direction_at(at)


func _group_size(group_id: int) -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead and u.current_order != null \
				and u.current_order.group_id == group_id:
			n += 1
	return n


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if camera == null or selection == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
		return

	# PLACEMENT SWALLOWS THE MOUSE. While a ghost is up, a left click sites the
	# building and a right click puts it down - neither may fall through to
	# selection or to a move order, or siting a power plant would also send the
	# whole army marching to where the player clicked.
	if is_placing():
		if event is InputEventMouseMotion:
			update_placement(event.position)
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var hit := _raycast(event.position, LayersScript.GROUND_PICK_MASK, false)
				if not hit.is_empty():
					confirm_placement(hit.position)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				cancel_placement()
		return

	# PRE-GAME HQ PLACEMENT. Mirrors the build-queue placement block above:
	# left click commits via the dedicated hook (place_hq_for_human via
	# confirm_hq_placement), right click cancels out. Mouse motion tracks
	# the ghost via the same raycast, with the zone clamp and validity test
	# handled by update_hq_placement. A build-queue placement and a
	# pre-game placement are mutually exclusive - is_placing() and
	# is_placing_hq() are never both true - so the early return above
	# (when is_placing() is true) keeps the two flows from racing.
	if is_placing_hq():
		if event is InputEventMouseMotion:
			update_hq_placement(event.position)
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				# No need to raycast here - update_hq_placement already
				# clamped to the zone and stored the result in
				# hq_ghost_pos. The click commits whatever the ghost
				# is currently on, not whatever the cursor is over.
				confirm_hq_placement()
			# Right click is intentionally a no-op for the pre-game
			# phase: the player can never "skip" the HQ - the match
			# needs a player HQ before it can start. The ghost just
			# stays where it is; a re-click at a different spot
			# drops the HQ at the new position. (Test Range bypasses
			# the entire pre-game flow, so it never sees this.)
		return

	if event is InputEventMouseMotion:
		_update_hover_cursor(event.position)
		if _dragging:
			_update_selection_rect(event.position)
			return
		# Right-button drag: mark so a stationary press+release does
		# not look like a move order. The chase camera owns the drag
		# itself - this is just a flag the match director reads on
		# release to decide whether to issue the move order.
		if _right_press_active and event.position.distance_to(_right_press_pos) > DRAG_CLICK_THRESHOLD:
			_right_dragged = true

	if not (event is InputEventMouseButton):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_origin = event.position
			_dragging = true
		elif _dragging:
			_dragging = false
			_hide_selection_rect()
			_resolve_left_release(event.position, event.shift_pressed)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			# Record press position. The move order is issued on
			# release UNLESS the player dragged - in which case the
			# chase camera owns the input and the match director
			# stays out of the way.
			_right_press_pos = event.position
			_right_press_active = true
			_right_dragged = false
		else:
			# Release. Only fire the move order if the press was
			# stationary (no drag).
			if _right_press_active and not _right_dragged \
					and event.position.distance_to(_right_press_pos) <= DRAG_CLICK_THRESHOLD:
				if _attack_move_armed:
					_set_armed(false)
					_issue_at(event.position, true, event.shift_pressed)
				else:
					_issue_at(event.position, false, event.shift_pressed)
			_right_press_pos = Vector2.ZERO
			_right_press_active = false
			_right_dragged = false


func _handle_key(event: InputEventKey) -> void:
	for i in range(1, 10):
		if event.is_action_pressed("cmd_group_assign_%d" % i):
			selection.assign_group(i)
			return
		elif event.is_action_pressed("cmd_group_%d" % i):
			selection.recall_group(i)
			return

	if event.is_action_pressed("cmd_attack_move"):
		_set_armed(not _attack_move_armed)
	elif event.is_action_pressed("cmd_stop"):
		orders.stop(selection.selected)
		_flash("STOP")
	elif event.is_action_pressed("cmd_stance_aggressive"):
		orders.set_stance(selection.selected, StanceScript.Kind.AGGRESSIVE)
		_flash("STANCE: AGGRESSIVE")
	elif event.is_action_pressed("cmd_stance_return_fire"):
		orders.set_stance(selection.selected, StanceScript.Kind.RETURN_FIRE)
		_flash("STANCE: RETURN FIRE")
	elif event.is_action_pressed("cmd_hold"):
		orders.hold(selection.selected)
		_flash("STANCE: HOLD POSITION")
	elif event.is_action_pressed("cmd_jump_alert"):
		var latest = alerts.get_latest_alert()
		if latest != null and camera != null:
			camera.global_position.x = latest.world_pos.x
			camera.global_position.z = latest.world_pos.z
	elif event.is_action_pressed("sys_perf"):
		_toggle_perf_hud()
	elif event.is_action_pressed("ui_cancel"):
		if admin_menu != null and admin_menu.is_open():
			admin_menu.toggle()
			return
		if is_placing():
			cancel_placement()
			return
		if not selection.selected.is_empty() or _attack_move_armed:
			_set_armed(false)
			selection.clear()
			return
		if admin_menu != null:
			admin_menu.toggle()


# F3, matching Skirmish. Built on demand rather than left always-on for the
# reason perf_hud.gd's own header gives: the offline harnesses cannot reproduce
# the slowdown at 6-8 engaged units, so the numbers have to be readable during a
# real match. The overlay is the instrument for the stutter report, not a fix
# for it.
func _toggle_perf_hud() -> void:
	if is_instance_valid(_perf_hud):
		_perf_hud.queue_free()
		_perf_hud = null
		return
	_perf_hud = PerfHUDScript.new()
	_perf_hud.name = "PerfHUD"
	add_child(_perf_hud)


# A left release is a drag if the mouse actually travelled, a click otherwise.
# One threshold, so a slightly shaky click never silently becomes an empty
# one-pixel drag that clears the selection.
func _resolve_left_release(at: Vector2, additive: bool) -> void:
	var rect := Rect2(_drag_origin, at - _drag_origin).abs()
	var picked: Array = []
	if rect.size.length() >= SelectionServiceScript.DRAG_THRESHOLD_PX:
		picked = selection.units_in_rect(rect)
	else:
		# A click on one of our own structures raises its production ring rather
		# than selecting anything. Checked BEFORE the unit pick, because a
		# manufactory with a tank parked against it should still be clickable as
		# a building - the structure is the larger, less mobile target and the
		# player can always click the tank a metre to one side.
		var structure := _structure_at(at)
		if structure != null and production_hud != null:
			selection.clear()
			production_hud.open_structure_ring(structure, at)
			return
		var one := selection.unit_at_point(at)
		if one != null:
			picked = [one]

	if additive:
		selection.add_to_selection(picked)
	else:
		selection.set_selection(picked)


# Our own structures only. An enemy building is a target, not a menu.
# --- Cursor -------------------------------------------------------------------
#
# CursorManager is an autoload and has been since the old runtime; the rebuilt
# battle layer simply never called it, so Battle ran on the bare OS arrow while
# Skirmish had contextual cursors. This is that call.
#
# The cursor answers the same question the click will: what does pressing the
# button here actually DO. So it is resolved from the same raycasts and the same
# selection the order path uses, rather than from a parallel guess.
func _update_hover_cursor(screen_pos: Vector2) -> void:
	var cm = get_node_or_null("/root/CursorManager")
	if cm == null or camera == null:
		return

	# Placing a building overrides everything: the only thing a click does here is
	# site it, and whether the site is legal is the one fact worth showing.
	if is_placing():
		var hit := _raycast(screen_pos, LayersScript.GROUND_PICK_MASK, false)
		var ok := false
		if not hit.is_empty():
			var at: Vector3 = hit.position
			at.y = terrain_height_at(at)
			ok = placement_validity(at)["valid"]
		cm.set_cursor(cm.CursorType.BUILD if ok else cm.CursorType.INVALID)
		return

	# Our own structures raise a production ring on click, not an order.
	if _structure_at(screen_pos) != null:
		cm.set_cursor(cm.CursorType.POINTER)
		return

	if selection == null or selection.selected.is_empty():
		cm.set_cursor(cm.CursorType.DEFAULT)
		return

	if _attack_move_armed:
		cm.set_cursor(cm.CursorType.ATTACK)
		return

	# An ore patch, checked BEFORE the ground, exactly as _issue_at does - a
	# terrain-only ray always finds the dirt underneath and the patch would never
	# be hoverable.
	var node_hit := _raycast(screen_pos, LayersScript.RESOURCE_NODES, false)
	if not node_hit.is_empty() and node_hit.collider.is_in_group("resource_nodes"):
		var can_harvest := false
		for u in selection.selected:
			if is_instance_valid(u) and u.is_harvester:
				can_harvest = true
				break
		cm.set_cursor(cm.CursorType.HARVEST if can_harvest else cm.CursorType.MOVE)
		return

	# Anything hostile and visible under the cursor is an attack.
	var target = _hostile_at(screen_pos)
	if target != null:
		cm.set_cursor(cm.CursorType.ATTACK)
		return

	cm.set_cursor(cm.CursorType.MOVE if not _raycast(
		screen_pos, LayersScript.GROUND_PICK_MASK, false).is_empty()
		else cm.CursorType.INVALID)


# A visible enemy under the cursor, or null. Fog-gated, so the cursor never
# reveals something the player cannot see by turning red over it.
func _hostile_at(screen_pos: Vector2):
	var hit := _raycast(screen_pos, LayersScript.SELECTION_QUERY_MASK, true)
	if hit.is_empty():
		return null
	var thing = hit.collider.get_meta("structure") if hit.collider.has_meta("structure") \
		else hit.collider.get_meta("unit") if hit.collider.has_meta("unit") else null
	if thing == null or not is_instance_valid(thing) or thing.is_dead:
		return null
	if not ("team" in thing) or thing.team == PLAYER_TEAM:
		return null
	if vision != null and vision.has_method("is_visible_to_team") \
			and not vision.is_visible_to_team(thing, PLAYER_TEAM):
		return null
	return thing


func _structure_at(screen_pos: Vector2) -> Structure:
	var hit := _raycast(screen_pos, LayersScript.SELECTION_QUERY_MASK, true)
	if hit.is_empty() or not hit.collider.has_meta("structure"):
		return null
	var s = hit.collider.get_meta("structure")
	if not is_instance_valid(s) or s.is_dead or s.team != PLAYER_TEAM:
		return null
	return s


func _issue_at(screen_pos: Vector2, aggressive: bool, queued: bool) -> void:
	# In Test Range the click-based selection system is broken (the hull-cache
	# proxy shares stale team metadata with the template), so fall back to the
	# focused unit. The player unit is force-selected in _spawn_test_range_force
	# and held in focus_unit from there.
	var recipients: Array = selection.selected
	if recipients.is_empty() and focus_unit != null and is_instance_valid(focus_unit):
		recipients = [focus_unit]
	if recipients.is_empty():
		return
	# WHAT WAS CLICKED DECIDES WHAT THE ORDER IS. An ore patch means "go work
	# that", ground means "go there". Resource nodes are queried first because
	# they sit ON the ground - a terrain-only ray would always find the dirt
	# underneath and the patch would never be clickable.
	if not aggressive:
		var node_hit := _raycast(screen_pos, LayersScript.RESOURCE_NODES, false)
		if not node_hit.is_empty() and node_hit.collider.is_in_group("resource_nodes"):
			orders.harvest(recipients, node_hit.collider, queued)
			# Anything in the selection that cannot harvest still needs an order,
			# or right-clicking a patch with a mixed group leaves the tanks
			# standing there having visibly ignored the click.
			var combat: Array = []
			for u in recipients:
				if is_instance_valid(u) and not u.is_harvester:
					combat.append(u)
			if not combat.is_empty():
				orders.move(combat, node_hit.collider.global_position, queued)
			return
		# RAYCAST MISS FALLBACK (2026-08-10). Ambient resource nodes (the
		# scattered single-tree / single-ore decorative scatter) have NO
		# per-tree physics body - the broadphase cost of 1800+ StaticBody3D
		# entries in the scatter was crashing the per-frame budget. The
		# raycast against layer 16 (RESOURCE_NODES) only hits the 4
		# harvestable fields' 36 colliders now. To keep "right-click on a
		# tree" working for ambient scatter, find the nearest ambient
		# resource to the GROUND click point (the second raycast below).
		# This is the same "nearest to the click" semantics the player
		# got before, just resolved against the resource_nodes group
		# rather than a physics shape.
		var ground_hit := _raycast(screen_pos, LayersScript.GROUND_PICK_MASK, false)
		if not ground_hit.is_empty():
			var ambient_target: Node3D = _nearest_ambient_to(ground_hit.position)
			if ambient_target != null:
				orders.harvest(recipients, ambient_target, queued)
				return

	var hit := _raycast(screen_pos, LayersScript.GROUND_PICK_MASK, false)
	if hit.is_empty():
		return
	if aggressive:
		orders.attack_move(recipients, hit.position, queued)
	else:
		orders.move(recipients, hit.position, queued)


# Nearest ambient resource node to `pos` (XZ distance). Bounded search by the
# AMBIENT_NODE_PICK_RADIUS so a right-click on empty ground doesn't auto-find
# a tree 200m away - the player clicked on THIS patch, treat the click as
# local. Returns null if nothing within radius. The harvester's auto-find
# (unit.gd's _auto_find_harvest_work) does the same kind of search
# but on every tick, and that one DOES search the whole map because the
# harvester is idle and looking for any work - this is a click-driven pick
# and the locality is the player-facing contract.
const AMBIENT_NODE_PICK_RADIUS: float = 8.0
func _nearest_ambient_to(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d_sq: float = AMBIENT_NODE_PICK_RADIUS * AMBIENT_NODE_PICK_RADIUS
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(n):
			continue
		if not ("is_ambient" in n) or not n.is_ambient:
			continue
		if n.amount <= 0:
			continue
		var d_sq: float = pos.distance_squared_to(n.global_position)
		if d_sq < best_d_sq:
			best = n
			best_d_sq = d_sq
	return best


# Puts `centre` under the middle of the screen without touching zoom or pitch.
#
# Reuses rts_camera's own ray_plane_hit() rather than reinventing the geometry:
# the camera looks down at an angle that varies with zoom (_apply_pitch lerps
# -42 to -62 degrees), so "subtract the height from Z" is only right at one
# zoom level. Asking where the screen centre currently lands and shifting by the
# difference is correct at every zoom, and it is the same function zoom-to-cursor
# already trusts.
func _on_group_recentre(centre: Vector3) -> void:
	if camera == null or not camera.has_method("ray_plane_hit"):
		return
	var screen_centre := get_viewport().get_visible_rect().size * 0.5
	var looking_at = camera.ray_plane_hit(screen_centre, centre.y)
	if looking_at == null:
		return
	camera.global_position.x += centre.x - looking_at.x
	camera.global_position.z += centre.z - looking_at.z


# --- HUD ---------------------------------------------------------------------
#
# Deliberately minimal. The real in-match HUD is Phase 4; this is the drag
# rectangle plus a one-line mode readout, which are the two things the command
# layer cannot be used without.

# Built in headless too, deliberately. The obvious guard - skip the HUD when
# there is no display - makes the entire production interface untestable, and
# test_ui_and_camera already constructs UIDock headless without trouble. Control
# nodes do not need a window; only rendering does.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	# Battle-system unification (Phase 2). The per-mode rule set is the
	# single source of truth for which sub-HUDs exist. The default
	# Skirmish values (all on) keep the legacy path identical; Test
	# Range's rule set flips production_hud and admin_menu off. The
	# minimap lives inside BattleHUD - turning it off cleanly is a
	# deeper change to BattleHUD itself, deferred until Phase 3 (Test
	# Range launcher) wires the chase camera and the slim HUD together.
	# _match_rule_set is the cached rule set from _ready(); reading from
	# the member is the same pattern _spawn_bases / _setup_vision / etc
	# use. The local match_config lookup above is no longer needed here.
	var enable_battle_hud: bool = _match_rule_set.enable_battle_hud if _match_rule_set != null else true
	var enable_production_hud: bool = _match_rule_set.enable_production_hud if _match_rule_set != null else true
	var is_debug := OS.has_feature("editor") or OS.is_debug_build() or "--cheats" in OS.get_cmdline_args()
	var enable_admin_menu: bool = (_match_rule_set.enable_admin_menu if _match_rule_set != null else true) and is_debug

	_selection_rect = Panel.new()
	_selection_rect.visible = false
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Tokens.SIGNAL_GO.r, Tokens.SIGNAL_GO.g, Tokens.SIGNAL_GO.b, 0.12)
	box.border_color = Tokens.SIGNAL_GO
	box.set_border_width_all(1)
	_selection_rect.add_theme_stylebox_override("panel", box)
	layer.add_child(_selection_rect)

	if enable_battle_hud:
		battle_hud = BattleHUDScript.new()
		battle_hud.name = "BattleHUD"
		layer.add_child(battle_hud)
		battle_hud.setup(self, PLAYER_TEAM, current_map)

		# BELOW BattleHUD's top strip, not on top of it.
		#
		# All three of these were positioned independently against the top-left corner
		# - the strip is a full-width band at y=8..64, the bindings sat at y=12 and the
		# hint at y=56 - so the corner rendered as three overlapping texts. They are
		# stacked deliberately now, measured off the strip's own height rather than
		# from three separately-guessed constants.
		var below_strip: float = Tokens.SPACE_SM + BattleHUDScript.TOP_STRIP_HEIGHT + Tokens.SPACE_SM

		_hud_hint = Label.new()
		_hud_hint.theme_type_variation = "HintLabel"
		_hud_hint.position = Vector2(Tokens.SPACE_MD, below_strip)
		_hud_hint.text = ""
		layer.add_child(_hud_hint)

	if enable_production_hud:
		production_hud = ProductionHUDScript.new()
		layer.add_child(production_hud)
		production_hud.setup(self)

	if enable_admin_menu:
		admin_menu = AdminMenuScript.new()
		admin_menu.name = "AdminMenu"
		layer.add_child(admin_menu)
		admin_menu.main_menu_requested.connect(func():
			var router = get_node_or_null("/root/SceneRouter")
			if router != null:
				router.goto("res://scenes/MainMenu.tscn")
			else:
				get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
		admin_menu.quit_requested.connect(func(): get_tree().quit())


func _update_selection_rect(at: Vector2) -> void:
	if _selection_rect == null:
		return
	var rect := Rect2(_drag_origin, at - _drag_origin).abs()
	_selection_rect.visible = rect.size.length() >= SelectionServiceScript.DRAG_THRESHOLD_PX
	_selection_rect.position = rect.position
	_selection_rect.size = rect.size


func _hide_selection_rect() -> void:
	if _selection_rect:
		_selection_rect.visible = false


func _set_armed(value: bool) -> void:
	_attack_move_armed = value
	_flash("ATTACK-MOVE: RIGHT-CLICK A DESTINATION" if value else "")
	# X7 (Tactile Interface Programme Part 2.4): the hint label was the only
	# feedback that attack-move was armed, and the player is looking at the
	# battlefield, not at the hint. CursorManager is an autoload and has been
	# since the old runtime; arming sets the cursor to ATTACK immediately so
	# the cue lands without waiting for the next mouse motion. On disarm the
	# cursor is re-resolved from the current hover position, which is what
	# the next click will actually do. The flash text stays as the
	# accessible-channel fallback under the captions setting.
	var cm = get_node_or_null("/root/CursorManager")
	if cm == null:
		return
	if value:
		cm.set_cursor(cm.CursorType.ATTACK)
	else:
		var vp := get_viewport()
		if vp != null:
			_update_hover_cursor(vp.get_mouse_position())


func _flash(text: String) -> void:
	if _hud_hint:
		_hud_hint.text = text


func _raycast(screen_pos: Vector2, mask: int, areas: bool) -> Dictionary:
	# Project the click from whichever camera is currently rendering the
	# scene. The `camera` field still names the RTS Camera3D, but the
	# chase camera takes over in Test Range - a click projected from the
	# RTS camera in that mode would land on a coordinate the player
	# cannot see and a move order would send the unit to a spot off
	# screen. get_viewport().get_camera_3d() returns the active one.
	var ray_cam := get_viewport().get_camera_3d() if camera != null else null
	if ray_cam == null:
		ray_cam = camera
	if ray_cam == null:
		return {}
	var from := ray_cam.project_ray_origin(screen_pos)
	var to := from + ray_cam.project_ray_normal(screen_pos) * PICK_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	query.collide_with_areas = areas
	query.collide_with_bodies = not areas
	return get_world_3d().direct_space_state.intersect_ray(query)
