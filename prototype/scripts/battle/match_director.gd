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
const OrderScript = preload("res://scripts/battle/orders/order.gd")
const LayersScript = preload("res://scripts/battle/battle_layers.gd")

const PLAYER_TEAM := 0
const ENEMY_TEAM := 1

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

# Phase 0 selection: a plain list, replaced by SelectionService in Phase 1 when
# frustum querying and control groups arrive. It lives here now only so
# right-click has something to command.
var selected: Array = []

# Increments per group command so orders issued together share a group_id. The
# flow field caches on it in Phase 1.
var _next_group_id: int = 1


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

	await _setup_terrain()
	_spawn_starting_units()


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
	if DisplayServer.get_name() == "headless":
		nav = TerrainBuilder.build_navmeshes(current_map, [])
	else:
		nav = TerrainBuilder.build_navmeshes_deferred(current_map, [])
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


# --- Input ------------------------------------------------------------------
#
# Phase 0 wiring only: click to select one unit, right-click to move the
# selection. Drag-box frustum selection, formations, stances and attack-move all
# land in Phase 1, at which point this forwards to SelectionService and
# OrderService instead of doing the work itself.

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or camera == null:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_select_at(event.position, event.shift_pressed)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_order_move_to(event.position)


# Picks the selection PROXY, not the unit body - see battle_layers.gd for why
# they are different volumes. The proxy carries a back-reference to its unit so
# this never has to guess how deep in the unit's tree the shape sits.
func _select_at(screen_pos: Vector2, additive: bool) -> void:
	var hit := _raycast(screen_pos, LayersScript.SELECTION_QUERY_MASK, true)
	var picked: Node = null
	if not hit.is_empty() and hit.collider.has_meta("unit"):
		var candidate = hit.collider.get_meta("unit")
		if is_instance_valid(candidate) and candidate.team == PLAYER_TEAM:
			picked = candidate

	if not additive:
		for u in selected:
			if is_instance_valid(u):
				u.set_selected(false)
		selected.clear()

	if picked and not selected.has(picked):
		picked.set_selected(true)
		selected.append(picked)


func _order_move_to(screen_pos: Vector2) -> void:
	if selected.is_empty():
		return
	var hit := _raycast(screen_pos, LayersScript.GROUND_PICK_MASK, false)
	if hit.is_empty():
		return

	var group := _next_group_id
	_next_group_id += 1
	for u in selected:
		if is_instance_valid(u):
			# Straight onto the unit in Phase 0. Phase 1 routes this through
			# OrderService so shift-queueing and formation slots have somewhere
			# to live, and so the AI issues orders through the same door.
			u.current_order = OrderScript.move(hit.position, group)
			u.order_queue.clear()


func _raycast(screen_pos: Vector2, mask: int, areas: bool) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * PICK_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	query.collide_with_areas = areas
	query.collide_with_bodies = not areas
	return get_world_3d().direct_space_state.intersect_ray(query)
