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
const SelectionServiceScript = preload("res://scripts/battle/orders/selection_service.gd")
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

var ground_nav_map: RID
var water_nav_map: RID
var amphibious_nav_map: RID
var deep_water_nav_map: RID
var _ground_nav_region: RID
var _water_nav_region: RID
var _amphibious_nav_region: RID
var _deep_water_nav_region: RID

var selection: SelectionService = null
var orders: OrderService = null
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
var vision: VisionService = null
var battle_hud: BattleHUD = null
var commander: Commander = null

# One live squad per AI team. Kept between decisions so a squad's state -
# retreating, regrouping, and the peak health those are measured against -
# survives; rebuilding it each tick would reset its memory every two seconds.
var _squads: Dictionary = {}

# Set when the match has been decided. Stops the vision scan and the win check
# from running over a field nobody is playing on any more.
var game_over: bool = false

# The designs this team can field. Bundled defaults for now; hand-picked roster
# selection from MatchConfig arrives with the pre-match screen.
var roster: Array = []
# The AI's own designs, kept separate from the player's so a match is not a
# mirror and counter-picking has something to pick from.
var enemy_roster: Array = []

# Starting bank. Enough for a refinery plus a light manufactory, so the opening
# is a real choice rather than a forced single purchase.
# 750 credits = the old 450 metal + 150 crystal at the 2x crystal rate, so the
# opening bank buys exactly what it always did.
const STARTING_CREDITS := 750

# The player's build bar tops out here, matching the old runtime's loadout limit.
const ROSTER_LIMIT := 12
# How many of the player's own saved designs get auto-drafted when they did not
# hand-pick a roster. Deliberately short of ROSTER_LIMIT so bundled defaults
# still fill the remainder - a roster of eight half-finished experiments with no
# harvester is not a playable match.
const ROSTER_AUTOPICK_LIMIT := 8
# A match whose roster cannot mine is unwinnable, so this is force-added when
# nothing else in the roster harvests.
const FALLBACK_HARVESTER := "res://data/loadout/ore_trucker.json"

# Drag-select state. A press below SelectionService.DRAG_THRESHOLD_PX resolves as
# a click instead.
var _drag_origin := Vector2.ZERO
var _dragging := false
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

	var match_config := get_node_or_null("/root/MatchConfig")
	if match_config and "selected_map_id" in match_config and match_config.selected_map_id != "":
		map_id = match_config.selected_map_id
	if match_config and "player_faction" in match_config and match_config.player_faction != "":
		player_faction = match_config.player_faction
	current_map = MapCatalog.get_map(map_id)
	# CORE_DESIGN_LANGUAGE.md §3.2: pan/middle-drag speed track world_scale so
	# a genuinely bigger map doesn't also feel proportionally slower to move
	# around in - duck-typed the same way the rest of this file treats the
	# camera, so a camera without the property (an older scene, a test stub)
	# degrades to its own default rather than erroring.
	if camera and "world_scale" in camera:
		camera.world_scale = WorldScaleScript.for_map(current_map)

	orders = OrderServiceScript.new()
	flow_fields = FlowFieldServiceScript.new()

	economy = EconomyServiceScript.new()
	production = ProductionServiceScript.new()
	production.setup(economy, self)
	for t in [PLAYER_TEAM, ENEMY_TEAM]:
		# The pre-match screen's resource preset, when it set one. Both sentinels
		# are -1 rather than 0, because "start with nothing" is a legitimate
		# choice and must be distinguishable from "not configured".
		var start_credits: int = STARTING_CREDITS
		if match_config and "starting_credits" in match_config and match_config.starting_credits >= 0:
			start_credits = match_config.starting_credits
		economy.add_team(t, start_credits)
		production.add_team(t)
	production.unit_completed.connect(_on_unit_completed)
	production.structure_ready.connect(_on_structure_ready)

	# Buildings BEFORE the bake, so their footprints go into the first navmesh
	# rather than needing an immediate second one. A rebake inside the first few
	# startup frames leaves a window where a unit's very first path query runs
	# before NavigationServer3D has resynced, and the unit drives into the lake.
	_spawn_resource_nodes()
	_spawn_bases()

	await _setup_terrain()

	# After the bake: the flow field samples the ground navmesh for passability,
	# so it needs the map RID that _setup_terrain() just produced.
	flow_fields.setup(ground_nav_map, current_map.get("map_half_extents", 80.0), WorldScaleScript.for_map(current_map))

	selection = SelectionServiceScript.new()
	selection.setup(camera, get_world_3d().direct_space_state, PLAYER_TEAM)
	selection.group_recentre_requested.connect(_on_group_recentre)

	_setup_vision()

	_load_roster()
	_spawn_starting_units()
	_build_hud()

	stats = MatchStatsScript.new()
	commander = CommanderScript.new()
	commander.setup(self, ENEMY_TEAM,
		match_config.ai_difficulty if match_config and "ai_difficulty" in match_config else "normal")

	world_is_ready = true
	world_ready.emit()


# Vision runs on its own timer rather than in _physics_process. The scan is
# O(viewers x targets) per team and its answer changing three times a second is
# imperceptible; running it per frame would be the single most expensive thing in
# the match for no visible gain.
func _setup_vision() -> void:
	vision = VisionServiceScript.new()
	vision.setup(self, PLAYER_TEAM, current_map.get("map_half_extents", 80.0), WorldScaleScript.for_map(current_map))
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
		for entry in nav["pending"]:
			TerrainBuilder.bake_pending_entry_async(entry, nav["cell_size"], func():
				remaining["n"] -= 1)
		while remaining["n"] > 0:
			await get_tree().process_frame

	ground_nav_map = nav.ground_map
	water_nav_map = nav.water_map
	amphibious_nav_map = nav.amphibious_map
	deep_water_nav_map = nav.deep_water_map
	_ground_nav_region = nav.ground_region
	_water_nav_region = nav.water_region
	_amphibious_nav_region = nav.amphibious_region
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
	for rid in [_ground_nav_region, _water_nav_region, _amphibious_nav_region, _deep_water_nav_region,
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

	var chosen: Array = []
	if match_config and "selected_blueprint_paths" in match_config:
		chosen = match_config.selected_blueprint_paths
	if not chosen.is_empty():
		for path in chosen:
			_append_design(roster, bp_manager.load_blueprint(path))
	else:
		for entry in bp_manager.list_blueprints(true):
			if roster.size() >= ROSTER_AUTOPICK_LIMIT:
				break
			_append_design(roster, bp_manager.load_blueprint(entry.path))

	for path in _bundled_loadout_paths():
		_append_design(roster, bp_manager.load_blueprint(path))
	if roster.size() > ROSTER_LIMIT:
		roster = roster.slice(0, ROSTER_LIMIT)

	if _harvester_in(roster).is_empty():
		_append_design(roster, bp_manager.load_blueprint(FALLBACK_HARVESTER))

	# Factions: the pre-match choice wins; otherwise the roster's own lead design
	# decides, which is the old behaviour and keeps a hand-built roster feeling
	# like it belongs to somebody.
	if match_config and "player_faction" in match_config and match_config.player_faction != "":
		player_faction = match_config.player_faction
	elif not roster.is_empty():
		player_faction = roster[0].get("faction", "industrialists")

	# ONE SHARED DEFAULT POOL (Chris's call). On a fresh install the player and
	# the AI have the same designs available, so neither side is fighting with
	# equipment the other could not have fielded.
	#
	# The AI draws from the BUNDLED defaults rather than from `roster`, because
	# roster may now be the player's own saved designs - handing those to the
	# opponent would field the player's army against them, which is a different
	# game than the one they chose.
	enemy_roster.clear()
	for path in _bundled_loadout_paths():
		_append_design(enemy_roster, bp_manager.load_blueprint(path))
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
	var ops = get_node_or_null("/root/OperationsManager")
	if ops != null and ops.is_active_operation:
		var history: Array = ops.fielded_history()
		if not history.is_empty():
			enemy_roster = CounterDraftScript.order_roster(enemy_roster, history)
			print("[Operations] AI counter-draft: %s" % CounterDraftScript.explain(history))

	if match_config and "enemy_faction" in match_config and match_config.enemy_faction != "":
		enemy_faction = match_config.enemy_faction
	elif not enemy_roster.is_empty():
		enemy_faction = enemy_roster[0].get("faction", "technocrats")


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
	for spawn in current_map.get("spawns", []):
		var team := PLAYER_TEAM if spawn.get("id") == "player" else ENEMY_TEAM
		_place_structure("hq", team, spawn.get("hq", Vector3.ZERO))
		_place_structure("refinery", team, spawn.get("refinery", Vector3.ZERO))
		# ALL THREE MANUFACTORY TIERS, as the old runtime does
		# (skirmish.gd:1517). This phase originally withheld them on the grounds
		# that the first factory should be the player's own decision - which reads
		# well and is unplayable here: the player has no ghost-placement UI yet, so
		# a match starting without a manufactory is a match where they can never
		# build anything at all. Parity with the mode this replaces wins.
		var factory: Vector3 = spawn.get("factory", spawn.get("hq", Vector3.ZERO) + Vector3(0, 0, -14))
		_place_structure("light_manufactory", team, factory)
		_place_structure("medium_manufactory", team, factory + Vector3(12, 0, 0))
		_place_structure("heavy_manufactory", team, factory + Vector3(-12, 0, 0))
	for t in [PLAYER_TEAM, ENEMY_TEAM]:
		economy.recalculate_power(t, get_team_structures(t))


func _place_structure(kind: String, structure_team: int, at: Vector3) -> Structure:
	var _prof := Profiler.start()
	var s := StructureScript.new()
	add_child(s)
	s.global_position = Vector3(at.x, terrain_height_at(at), at.z)
	s.setup(kind, structure_team)
	s.died.connect(_on_structure_died)
	Profiler.stop("place_structure", _prof)
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
	if not _ground_nav_region.is_valid():
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
	TerrainBuilder.rebake_ground_and_amphibious_async(
		current_map, _building_holes(), _ground_nav_region, _amphibious_nav_region,
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
	# The navmesh had a hole carved for this building and no longer should, and
	# every cached flow field was sampled against the old passability.
	#
	# NOT URGENT. A dead building only frees ground - the worst that happens
	# before the bake lands is that units take the long way round a hole where
	# nothing stands. Baking inline here cost a 4139 ms frame; see
	# NAV_LAZY_REBAKE_DELAY.
	_mark_navmesh_dirty(false)
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
	if stats == null:
		return
	stats.record_damage(_design_of(source), _design_of(victim), amount, damage_class)


func record_unit_lost(victim, source) -> void:
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

	if event is InputEventMouseMotion:
		_update_hover_cursor(event.position)
		if _dragging:
			_update_selection_rect(event.position)
			return

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
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _attack_move_armed:
			_set_armed(false)
			_issue_at(event.position, true, event.shift_pressed)
		else:
			_issue_at(event.position, false, event.shift_pressed)


func _handle_key(event: InputEventKey) -> void:
	# Digits 1-9: assign with Ctrl, recall without. Double-tapping a recall
	# recentres the camera, which SelectionService signals rather than doing, so
	# it never needs to know a camera exists.
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var num := event.keycode - KEY_0
		if event.ctrl_pressed:
			selection.assign_group(num)
		else:
			selection.recall_group(num)
		return

	# NOT A AND S, THE CONVENTIONAL BINDINGS. rts_camera.gd polls WASD directly in
	# _process() via Input.is_key_pressed() rather than consuming input events, so
	# a command bound to A or S fires AND pans the camera - both handlers see the
	# key and neither can mark it handled. The camera is shared with the old
	# Skirmish scene, so rebinding it there to free up A/S is a change to a screen
	# this rebuild is not touching. Commands go on free keys instead.
	match event.keycode:
		KEY_Q:
			# Armed, one-shot: the next right-click is an attack-move.
			_set_armed(not _attack_move_armed)
		KEY_E:
			orders.stop(selection.selected)
			_flash("STOP")
		KEY_Z:
			orders.set_stance(selection.selected, StanceScript.Kind.AGGRESSIVE)
			_flash("STANCE: AGGRESSIVE")
		KEY_X:
			orders.set_stance(selection.selected, StanceScript.Kind.RETURN_FIRE)
			_flash("STANCE: RETURN FIRE")
		KEY_C:
			orders.hold(selection.selected)
			_flash("STANCE: HOLD POSITION")
		KEY_F3:
			_toggle_perf_hud()
		KEY_ESCAPE:
			# Escape backs out of the most specific mode first. Clearing the
			# selection out from under a player who meant "put this building down"
			# is two mistakes in one keystroke.
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
			# Nothing left to back out of, so Escape means the menu - which is
			# where a player who has pressed it twice already expects to arrive.
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
	if selection.selected.is_empty():
		return
	# WHAT WAS CLICKED DECIDES WHAT THE ORDER IS. An ore patch means "go work
	# that", ground means "go there". Resource nodes are queried first because
	# they sit ON the ground - a terrain-only ray would always find the dirt
	# underneath and the patch would never be clickable.
	if not aggressive:
		var node_hit := _raycast(screen_pos, LayersScript.RESOURCE_NODES, false)
		if not node_hit.is_empty() and node_hit.collider.is_in_group("resource_nodes"):
			orders.harvest(selection.selected, node_hit.collider, queued)
			# Anything in the selection that cannot harvest still needs an order,
			# or right-clicking a patch with a mixed group leaves the tanks
			# standing there having visibly ignored the click.
			var combat: Array = []
			for u in selection.selected:
				if is_instance_valid(u) and not u.is_harvester:
					combat.append(u)
			if not combat.is_empty():
				orders.move(combat, node_hit.collider.global_position, queued)
			return

	var hit := _raycast(screen_pos, LayersScript.GROUND_PICK_MASK, false)
	if hit.is_empty():
		return
	if aggressive:
		orders.attack_move(selection.selected, hit.position, queued)
	else:
		orders.move(selection.selected, hit.position, queued)


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

	_selection_rect = Panel.new()
	_selection_rect.visible = false
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Tokens.SIGNAL_GO.r, Tokens.SIGNAL_GO.g, Tokens.SIGNAL_GO.b, 0.12)
	box.border_color = Tokens.SIGNAL_GO
	box.set_border_width_all(1)
	_selection_rect.add_theme_stylebox_override("panel", box)
	layer.add_child(_selection_rect)

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

	# The bindings, on screen, because they are not the conventional ones and
	# nothing else in the build documents them yet.
	var bindings := Label.new()
	bindings.theme_type_variation = "HintLabel"
	bindings.position = Vector2(Tokens.SPACE_MD, below_strip)
	bindings.text = "DRAG SELECT  |  RMB MOVE  |  SHIFT+RMB QUEUE  |  Q ATTACK-MOVE  |  E STOP" \
		+ "\nZ AGGRESSIVE  |  X RETURN FIRE  |  C HOLD  |  CTRL+1-9 SET GROUP  |  1-9 RECALL"
	layer.add_child(bindings)

	_hud_hint = Label.new()
	_hud_hint.theme_type_variation = "HintLabel"
	_hud_hint.position = Vector2(Tokens.SPACE_MD, below_strip + 44)
	_hud_hint.text = ""
	layer.add_child(_hud_hint)

	production_hud = ProductionHUDScript.new()
	layer.add_child(production_hud)
	production_hud.setup(self)

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


func _flash(text: String) -> void:
	if _hud_hint:
		_hud_hint.text = text


func _raycast(screen_pos: Vector2, mask: int, areas: bool) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * PICK_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	query.collide_with_areas = areas
	query.collide_with_bodies = not areas
	return get_world_3d().direct_space_state.intersect_ray(query)
