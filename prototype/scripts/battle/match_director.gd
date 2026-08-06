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
const ResourceNodeScript = preload("res://scripts/resource_node.gd")
const ProductionHUDScript = preload("res://scripts/battle/hud/production_hud.gd")
const VisionServiceScript = preload("res://scripts/battle/vision/vision_service.gd")
const BattleHUDScript = preload("res://scripts/battle/hud/battle_hud.gd")
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
var vision: VisionService = null
var battle_hud: BattleHUD = null

# Set when the match has been decided. Stops the vision scan and the win check
# from running over a field nobody is playing on any more.
var game_over: bool = false

# The designs this team can field. Bundled defaults for now; hand-picked roster
# selection from MatchConfig arrives with the pre-match screen.
var roster: Array = []

# Starting bank. Enough for a refinery plus a light manufactory, so the opening
# is a real choice rather than a forced single purchase.
const STARTING_METAL := 400
const STARTING_CRYSTAL := 100

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

	orders = OrderServiceScript.new()
	flow_fields = FlowFieldServiceScript.new()

	economy = EconomyServiceScript.new()
	production = ProductionServiceScript.new()
	production.setup(economy, self)
	for t in [PLAYER_TEAM, ENEMY_TEAM]:
		economy.add_team(t, STARTING_METAL, STARTING_CRYSTAL)
		production.add_team(t)
	production.unit_completed.connect(_on_unit_completed)

	# Buildings BEFORE the bake, so their footprints go into the first navmesh
	# rather than needing an immediate second one. A rebake inside the first few
	# startup frames leaves a window where a unit's very first path query runs
	# before NavigationServer3D has resynced, and the unit drives into the lake.
	_spawn_resource_nodes()
	_spawn_bases()

	await _setup_terrain()

	# After the bake: the flow field samples the ground navmesh for passability,
	# so it needs the map RID that _setup_terrain() just produced.
	flow_fields.setup(ground_nav_map, current_map.get("map_half_extents", 80.0))

	selection = SelectionServiceScript.new()
	selection.setup(camera, get_world_3d().direct_space_state, PLAYER_TEAM)
	selection.group_recentre_requested.connect(_on_group_recentre)

	_setup_vision()

	_load_roster()
	_spawn_starting_units()
	_build_hud()


# Vision runs on its own timer rather than in _physics_process. The scan is
# O(viewers x targets) per team and its answer changing three times a second is
# imperceptible; running it per frame would be the single most expensive thing in
# the match for no visible gain.
func _setup_vision() -> void:
	vision = VisionServiceScript.new()
	vision.setup(self, PLAYER_TEAM, current_map.get("map_half_extents", 80.0))
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
	vision.tick()
	if battle_hud != null:
		battle_hud.refresh()


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
		nav = TerrainBuilder.build_navmeshes_deferred(current_map, holes)
		for entry in nav["pending"]:
			await get_tree().process_frame
			TerrainBuilder.bake_pending_entry(entry, nav["cell_size"])

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

# Phase 0 spawns the bundled loadout at the player's spawn point so there is
# something to drive. Rosters, production and the enemy arrive in Phase 2/3.
func _load_roster() -> void:
	roster.clear()
	for path in _bundled_loadout_paths():
		var design: Dictionary = bp_manager.load_blueprint(path)
		if not design.is_empty():
			roster.append(design)


func _spawn_starting_units() -> void:
	# MapCatalog decodes the JSON number-arrays into real Vector3s, so this is a
	# world position already. Spawn ids are "player"/"enemy" - see data/maps/.
	var spawn := MapCatalog.get_spawn(current_map, "player")
	var origin: Vector3 = spawn.get("hq", Vector3.ZERO) if not spawn.is_empty() else Vector3.ZERO

	var index := 0
	for path in _bundled_loadout_paths():
		var blueprint: Dictionary = bp_manager.load_blueprint(path)
		if blueprint.is_empty():
			continue
		# A short row, spaced wider than the biggest hull so nothing spawns
		# inside anything else.
		var offset := Vector3(float(index % 4) * 7.0 - 10.5, 0.0, floorf(index / 4.0) * 7.0)
		spawn_unit(blueprint, PLAYER_TEAM, origin + offset)
		index += 1


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
	var unit := UnitScript.new()
	# Added to the tree BEFORE setup(): reconstruct_vehicle() and the nav agent
	# both need the node to be inside the tree to resolve global transforms and
	# to reach NavigationServer3D.
	add_child(unit)
	unit.global_position = Vector3(at.x, terrain_height_at(at), at.z)
	if not unit.setup(blueprint, unit_team, bp_manager, self, player_faction):
		# The blueprint named a hull the catalog no longer has. Drop it rather
		# than leaving a half-assembled body on the field.
		unit.queue_free()
		return null
	return unit


func get_team_units(for_team: int) -> Array:
	var out: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and not u.is_dead and u.team == for_team:
			out.append(u)
	return out


# --- Base and economy --------------------------------------------------------

func _spawn_resource_nodes() -> void:
	for entry in current_map.get("resource_nodes", []):
		var node := StaticBody3D.new()
		node.set_script(ResourceNodeScript)
		add_child(node)
		var pos: Vector3 = entry.get("position", Vector3.ZERO)
		node.global_position = Vector3(pos.x, terrain_height_at(pos), pos.z)
		node.setup(entry.get("type", "metal"), entry.get("amount", 1000))


func _spawn_bases() -> void:
	for spawn in current_map.get("spawns", []):
		var team := PLAYER_TEAM if spawn.get("id") == "player" else ENEMY_TEAM
		# A starting HQ and refinery only. The manufactories are the player's
		# first real decision rather than a gift - which is the whole point of
		# splitting the building queue out.
		_place_structure("hq", team, spawn.get("hq", Vector3.ZERO))
		_place_structure("refinery", team, spawn.get("refinery", Vector3.ZERO))
	for t in [PLAYER_TEAM, ENEMY_TEAM]:
		economy.recalculate_power(t, get_team_structures(t))


func _place_structure(kind: String, structure_team: int, at: Vector3) -> Structure:
	var s := StructureScript.new()
	add_child(s)
	s.global_position = Vector3(at.x, terrain_height_at(at), at.z)
	s.setup(kind, structure_team)
	s.died.connect(_on_structure_died)
	return s


func get_team_structures(for_team: int) -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and not s.is_dead and s.team == for_team:
			out.append(s)
	return out


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
			"half_extents": Vector2(s.footprint.x / 2.0, s.footprint.z / 2.0),
		})
	return holes


func _on_structure_died(structure) -> void:
	economy.recalculate_power(structure.team, get_team_structures(structure.team))
	# Losing the last contributor to a queue refunds everything in it: that line
	# can never advance again, so holding the money is a bug with extra steps.
	production.cancel_unbuildable(structure.team)
	# The navmesh had a hole carved for this building and no longer should, and
	# every cached flow field was sampled against the old passability.
	flow_fields.invalidate()
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


func _show_result(player_won: bool) -> void:
	if battle_hud == null:
		return
	var banner := Label.new()
	banner.name = "ResultBanner"
	banner.text = "VICTORY" if player_won else "DEFEAT"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 120
	banner.add_theme_color_override("font_color",
		Tokens.SIGNAL_GO if player_won else Tokens.SIGNAL_ALERT)
	battle_hud.add_child(banner)


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
		var score: float = distance + float(occupied) * 18.0
		if score < best_score:
			best_score = score
			best = n
	return best if best != null else best_any


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


func deliver(for_team: int, add_metal: int, add_crystal: int) -> void:
	economy.credit(for_team, add_metal, add_crystal)


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


func _on_unit_completed(for_team: int, queue_name: String, blueprint: Dictionary) -> void:
	var factory := _exit_structure(for_team, queue_name)
	var at: Vector3 = factory.exit_position() if factory != null else Vector3.ZERO
	spawn_unit(blueprint, for_team, at)


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
	_rebuild_neighbour_grid()
	if production:
		production.tick(delta)


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

	if event is InputEventMouseMotion and _dragging:
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
		KEY_ESCAPE:
			_set_armed(false)
			selection.clear()


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

	# The bindings, on screen, because they are not the conventional ones and
	# nothing else in the build documents them yet.
	var bindings := Label.new()
	bindings.theme_type_variation = "HintLabel"
	bindings.position = Vector2(Tokens.SPACE_MD, Tokens.SPACE_MD)
	bindings.text = "DRAG SELECT  |  RMB MOVE  |  SHIFT+RMB QUEUE  |  Q ATTACK-MOVE  |  E STOP" \
		+ "\nZ AGGRESSIVE  |  X RETURN FIRE  |  C HOLD  |  CTRL+1-9 SET GROUP  |  1-9 RECALL"
	layer.add_child(bindings)

	_hud_hint = Label.new()
	_hud_hint.theme_type_variation = "HintLabel"
	_hud_hint.position = Vector2(Tokens.SPACE_MD, Tokens.SPACE_MD + 44)
	_hud_hint.text = ""
	layer.add_child(_hud_hint)

	production_hud = ProductionHUDScript.new()
	layer.add_child(production_hud)
	production_hud.setup(self)


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
