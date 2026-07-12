extends Node3D
# C&C-style Skirmish mode. The player's saved blueprints (plus bundled defaults)
# form the buildable roster. Destroy the enemy HQ to win; lose yours and it's over.

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const BattleUnitScript = preload("res://scripts/battle_unit.gd")
const BuildingScript = preload("res://scripts/building.gd")
const ResourceNodeScript = preload("res://scripts/resource_node.gd")
const EnemyAIScript = preload("res://scripts/enemy_ai.gd")

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
var energy_tick_timer: float = 0.0
var player_faction: String = "industrialists"
var enemy_faction: String = "technocrats"

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

func _on_trickle():
	if game_over: return
	if player_faction == "expansionists" and is_instance_valid(player_hq) and not player_hq.is_dead:
		add_resources(PLAYER_TEAM, 8, 2)
	if enemy_faction == "expansionists" and is_instance_valid(enemy_hq) and not enemy_hq.is_dead:
		add_resources(ENEMY_TEAM, 8, 2)

# Energy resource team-level economy (ENERGY_AND_BALANCE_SPEC.md #1). A
# static building is any prefab (hq/refinery/factory are always static) or
# a "defense" building on a foundation hull - each drains a flat upkeep
# just for existing, UNLESS the team's faction is Expansionists (their
# static buildings are entirely self-powered, per Factions_and_Buildings.md).
func _recalc_energy_economy():
	if game_over: return
	for team in [PLAYER_TEAM, ENEMY_TEAM]:
		var capacity = 0.0
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
			if faction == "expansionists": continue
			upkeep += ENERGY_UPKEEP_PER_STATIC_BUILDING
		energy_pool[team].capacity = capacity
		energy_pool[team].energy = clamp(capacity - upkeep, 0.0, max(capacity, 1.0))
		energy_pool[team].deficit = (capacity - upkeep) < 0.0
	_update_resource_ui()

func is_energy_deficit(team: int) -> bool:
	return energy_pool[team].deficit

# --- Rosters ---

func _load_rosters():
	# Player: saved designs first, bundled defaults fill the gaps
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

	if not roster.is_empty():
		player_faction = roster[0].blueprint.get("faction", "industrialists")

	for path in _list_json_files("res://data/enemy"):
		var data = bp_manager.load_blueprint(path)
		if not data.is_empty():
			enemy_roster.append(_make_roster_entry(data))
	if not enemy_roster.is_empty():
		enemy_faction = enemy_roster[0].blueprint.get("faction", "technocrats")

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

func _spawn_resource_nodes():
	var spots = [
		[Vector3(-22, 0, 18), "metal", 1200], [Vector3(-28, 0, 12), "metal", 1000],
		[Vector3(22, 0, -18), "metal", 1200], [Vector3(28, 0, -12), "metal", 1000],
		[Vector3(0, 0, 0), "crystal", 800],
		[Vector3(-30, 0, -25), "crystal", 700], [Vector3(30, 0, 25), "crystal", 700],
		[Vector3(-5, 0, -8), "metal", 900], [Vector3(5, 0, 8), "metal", 900],
	]
	for s in spots:
		var node = StaticBody3D.new()
		node.set_script(ResourceNodeScript)
		add_child(node)
		node.global_position = s[0]
		node.setup(s[1], s[2])

func _spawn_bases():
	# Player base (south), enemy base (north)
	player_hq = _spawn_prefab("hq", PLAYER_TEAM, Vector3(0, 0, 34), player_faction)
	_spawn_prefab("factory", PLAYER_TEAM, Vector3(-10, 0, 30), player_faction)
	_spawn_prefab("refinery", PLAYER_TEAM, Vector3(9, 0, 28), player_faction)

	enemy_hq = _spawn_prefab("hq", ENEMY_TEAM, Vector3(0, 0, -34), enemy_faction)
	_spawn_prefab("factory", ENEMY_TEAM, Vector3(10, 0, -30), enemy_faction)
	_spawn_prefab("refinery", ENEMY_TEAM, Vector3(-9, 0, -28), enemy_faction)

	player_hq.died.connect(_on_hq_died)
	enemy_hq.died.connect(_on_hq_died)

	# Starting harvesters
	var harv_bp = _find_harvester_blueprint(roster)
	if not harv_bp.is_empty():
		spawn_unit(harv_bp, PLAYER_TEAM, Vector3(6, 0.5, 24))
	var e_harv = _find_harvester_blueprint(enemy_roster)
	if not e_harv.is_empty():
		spawn_unit(e_harv, ENEMY_TEAM, Vector3(-6, 0.5, -24))

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
	b.global_position = pos
	b.setup_prefab(kind, team, faction)
	b.bp_manager = bp_manager
	return b

func spawn_unit(blueprint_data: Dictionary, team: int, pos: Vector3) -> Node:
	var unit = CharacterBody3D.new()
	unit.set_script(BattleUnitScript)
	add_child(unit)
	unit.global_position = pos
	unit.setup(blueprint_data, team, bp_manager)
	unit.resources_delivered.connect(_on_resources_delivered)
	return unit

func spawn_defense(blueprint_data: Dictionary, team: int, pos: Vector3) -> StaticBody3D:
	var b = StaticBody3D.new()
	b.set_script(BuildingScript)
	add_child(b)
	b.global_position = pos
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
	# Must be near your base (within 28m of any friendly building)
	var near_base = false
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and not b.is_dead and b.team == PLAYER_TEAM:
			if b.global_position.distance_to(pos) < 28.0:
				near_base = true
				break
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
				placement_ghost.global_position = hit + Vector3(0, placement_ghost.mesh.size.y / 2.0, 0)
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
