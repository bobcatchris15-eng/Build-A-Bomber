class_name CommandConsole
extends Control
# Root orchestrator for the diegetic command console.
# Owns layout and wiring; all chrome lives in child components.

const Tokens = preload("res://scripts/ui_tokens.gd")
const DeskInstrumentBarScript = preload("res://scripts/battle/hud/desk_instrument_bar.gd")
const ProductionTabBarScript = preload("res://scripts/battle/hud/production_tab_bar.gd")
const ContextDrawerScript = preload("res://scripts/battle/hud/context_drawer.gd")
const ProductionDrawerScript = preload("res://scripts/battle/hud/production_drawer.gd")
const IntelFeedScript = preload("res://scripts/battle/hud/intel_feed.gd")
const MinimapOverlayScript = preload("res://scripts/battle/hud/minimap_overlay.gd")

var _director: Node = null
var _local_team: int = 0

var desk_bar: DeskInstrumentBar
var tab_bar: ProductionTabBar
var context_drawer: ContextDrawer
var production_drawer: ProductionDrawer
var intel_feed: IntelFeed
var minimap: MinimapOverlay

signal alert_clicked(category: String)
signal rally_click_requested(pos: Vector3)
signal rally_cancelled()

func _init() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Build all child chrome programmatically (no .tscn, no @onready).
	desk_bar = DeskInstrumentBarScript.new()
	desk_bar.name = "DeskInstrumentBar"
	add_child(desk_bar)

	tab_bar = ProductionTabBarScript.new()
	tab_bar.name = "ProductionTabBar"
	add_child(tab_bar)

	context_drawer = ContextDrawerScript.new()
	context_drawer.name = "ContextDrawer"
	add_child(context_drawer)

	production_drawer = ProductionDrawerScript.new()
	production_drawer.name = "ProductionDrawer"
	add_child(production_drawer)

	intel_feed = IntelFeedScript.new()
	intel_feed.name = "IntelFeed"
	add_child(intel_feed)

	minimap = MinimapOverlayScript.new()
	minimap.name = "MinimapOverlay"
	add_child(minimap)

func _ready() -> void:
	fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(fit_to_viewport):
		vp.size_changed.connect(fit_to_viewport)
	tree_entered.connect(_on_tree_entered)

func _on_tree_entered() -> void:
	var settings = _get_settings()
	if settings != null:
		if settings.has_signal("settings_changed"):
			settings.settings_changed.connect(_on_settings_changed)
		_apply_ui_scale(settings.get("ui_scale", 1.0))

func _on_settings_changed(key: String, value) -> void:
	if key == "ui_scale":
		_apply_ui_scale(value)

func _apply_ui_scale(s: float) -> void:
	s = clampf(s, 0.8, 1.5)
	scale = Vector2(s, s)

func _get_settings():
	var tree = get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("settings_service")

func setup(director: Node, local_team: int, current_map: Dictionary) -> void:
	_director = director
	_local_team = local_team

	desk_bar.setup(director, local_team)
	tab_bar.setup(director)
	context_drawer.setup(director)
	production_drawer.setup(director)
	intel_feed.setup(director, local_team)
	minimap.setup(current_map)

	_wire_signals()

	# Provide rally raycast callable to viewport so CommandConsole can
	# resolve ground positions without knowing the match_director internals.
	var vp := get_viewport()
	if vp != null:
		vp.set_meta("rally_raycast", _rally_raycast)

func _rally_raycast(screen_pos: Vector2) -> Vector3:
	if _director != null and _director.has_method("_raycast"):
		var hit: Dictionary = _director._raycast(
			screen_pos, preload("res://scripts/battle/battle_layers.gd").GROUND_PICK_MASK, false)
		if not hit.is_empty():
			return hit.position
	return Vector3.ZERO

func fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	position = Vector2.ZERO
	size = vp.get_visible_rect().size

func _wire_signals() -> void:
	if _director == null:
		return

	var economy = _director.economy
	if economy != null and economy.has_signal("changed"):
		economy.changed.connect(desk_bar._refresh_resources)

	var production = _director.production
	if production != null and production.has_signal("queue_changed"):
		production.queue_changed.connect(_on_queue_changed)

	var selection = _director.selection
	if selection != null and selection.has_signal("selection_changed"):
		selection.selection_changed.connect(_on_selection_changed)

	var vision = _director.vision
	if vision != null and vision.has_signal("shroud_version_changed"):
		vision.shroud_version_changed.connect(minimap._composite_fog)

	if _director.has_signal("structure_built"):
		_director.structure_built.connect(_on_structure_built)
	if _director.has_signal("structure_lost"):
		_director.structure_lost.connect(_on_structure_lost)

	tab_bar.tab_toggled.connect(_on_tab_toggled)
	desk_bar.alert_clicked.connect(_on_alert_clicked)

func _on_queue_changed(team: int, queue: String) -> void:
	if team == _local_team:
		tab_bar.refresh_badge(queue)
		if production_drawer.visible and production_drawer.current_tier == queue:
			production_drawer.rebuild_tier(queue)

func _on_selection_changed(units: Array) -> void:
	context_drawer.update_selection(units)
	if not units.is_empty():
		context_drawer.expand()

func _on_structure_built(team: int, kind: String) -> void:
	if team == _local_team:
		intel_feed.add_entry("structure_ready", kind)
		tab_bar.refresh_all_badges()
		production_drawer.re_evaluate_gates()

func _on_structure_lost(team: int, kind: String) -> void:
	if team == _local_team:
		intel_feed.add_entry("low_power", "Structure lost: %s" % kind)
		tab_bar.refresh_all_badges()
		production_drawer.re_evaluate_gates()

func _on_tab_toggled(queue_name: String, open: bool) -> void:
	if open:
		production_drawer.open_tier(queue_name)
	else:
		production_drawer.close_tier(queue_name)

func _on_alert_clicked(category: String) -> void:
	intel_feed.expand_to_category(category)
	alert_clicked.emit(category)

func _unhandled_input(event: InputEvent) -> void:
	# Rally placement mode swallows mouse
	if production_drawer.is_rally_pending():
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var raycast_fn = get_viewport().get_meta("rally_raycast", null)
				if raycast_fn != null and raycast_fn is Callable:
					var pos: Vector3 = raycast_fn.call(event.position)
					if pos != Vector3.ZERO:
						production_drawer.complete_rally(pos)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				production_drawer.cancel_rally()
				rally_cancelled.emit()
				get_viewport().set_input_as_handled()
				return
		return

	# Global HUD hotkeys
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M:
				minimap.toggle()
			KEY_I:
				intel_feed.toggle_collapse()
			KEY_B:
				tab_bar.toggle_last_hovered()
			KEY_TAB:
				if event.shift:
					context_drawer.cycle_tab(-1)
				else:
					context_drawer.cycle_tab(1)
			KEY_SPACE:
				context_drawer.toggle_pin()
			KEY_ESCAPE:
				if production_drawer.is_rally_pending():
					production_drawer.cancel_rally()
					rally_cancelled.emit()
				else:
					context_drawer.collapse()
					production_drawer.close_tier(production_drawer.current_tier)
					intel_feed.toggle_collapse()