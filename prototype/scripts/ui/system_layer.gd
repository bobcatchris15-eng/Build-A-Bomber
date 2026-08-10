extends CanvasLayer
# Autoload: the pause menu, and the one place Escape ends up.
#
# WHAT THIS REPLACES. There was no pause menu and no pause. Escape in a match
# opened admin_menu.gd - the CHEAT panel (infinite resources, instant build,
# reveal fog) - which also happened to carry the only "Main Menu" and "Quit"
# buttons in the game. So the debug surface was load-bearing for shipping
# navigation, and the game could not be paused at all: get_tree().paused was set
# in exactly one place, SceneRouter._deploy_gate(), and never during play.
#
# LAYER 120: above every in-scene CanvasLayer (the HUDs sit in single digits,
# TutorialManager at 110) and BELOW SceneRouter's fade at 128. A transition must
# cover this the same way it covers everything else - a pause menu floating over
# a scene change would be the one thing that never fades.
#
# PROCESS_MODE_ALWAYS, because a paused pause-screen cannot dismiss itself. Same
# reasoning, and the same trap, as _deploy_gate().

signal opened()
signal closed()

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const SettingsPanelScript = preload("res://scripts/ui/settings_panel.gd")

const LAYER_INDEX := 120

var _root: Control = null
var _scrim: ColorRect = null
var _panel_host: CenterContainer = null
var _menu_host: PanelContainer = null
var _menu_box: VBoxContainer = null
var _settings_panel: Control = null
var _open: bool = false
var _paused_by_us: bool = false


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_set_visible(false)


func is_open() -> bool:
	return _open


# --- The Escape contract -----------------------------------------------------
#
# THE RULE, generalised from the one place that already had it right
# (match_director's Escape handler): Escape pops the MOST SPECIFIC open thing,
# and only reaches this menu when there is nothing left to pop. Clearing a
# player's selection out from under them when they meant "close this dialog" is
# two mistakes in one keystroke.
#
# Scenes opt in by implementing `handle_cancel() -> bool` - return true if you
# consumed it. This is deliberately duck-typed rather than an interface, the same
# convention SceneRouter uses for `world_ready`: the router does not need to know
# what a match is, and this does not need to know what a scene is.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _open:
		# The stack rule applies INSIDE this layer too: Escape out of Settings
		# returns to the menu, and only a second Escape leaves.
		if _settings_panel != null and is_instance_valid(_settings_panel) \
				and _settings_panel.visible:
			_settings_panel.visible = false
			_menu_host.visible = true
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("handle_cancel"):
		if scene.handle_cancel():
			get_viewport().set_input_as_handled()
			return
	open()
	get_viewport().set_input_as_handled()


func open() -> void:
	if _open:
		return
	_open = true
	# Always reopen on the MENU, never on whatever sub-panel was showing last
	# time. Reopening into Settings would be a hidden mode the player did not ask
	# for and cannot see the cause of.
	if _settings_panel != null and is_instance_valid(_settings_panel):
		_settings_panel.visible = false
	_menu_host.visible = true
	_rebuild_menu()
	_set_visible(true)
	UIFeedbackScript.play(_root, "ui_menu_open")
	# Only pause if something else has not already. Stomping an existing pause
	# means close() would unpause a tree that was deliberately frozen - the
	# DEPLOY gate being the obvious case.
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	UIFeedbackScript.play(_root, "ui_menu_close")
	_set_visible(false)
	if _paused_by_us:
		get_tree().paused = false
		_paused_by_us = false
	closed.emit()


func _set_visible(v: bool) -> void:
	if _root != null:
		_root.visible = v
		# STOP only while open. A full-screen Control that always swallowed input
		# would make the entire game unclickable - the same guard SceneRouter's
		# fade rect needs and for the same reason.
		_root.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE


# --- Construction ------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "SystemRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_scrim = ColorRect.new()
	_scrim.color = Color(Tokens.BASE_900, 0.78)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scrim)

	# The host holds EITHER the menu or the settings panel - they swap visibility
	# rather than stacking, so Escape never lands on an ambiguous two-deep state.
	_panel_host = CenterContainer.new()
	_panel_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel_host)

	_menu_host = PanelContainer.new()
	_menu_host.theme_type_variation = "CardPanel"
	_menu_host.custom_minimum_size = Vector2(340, 0)
	_panel_host.add_child(_menu_host)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.SPACE_LG)
	_menu_host.add_child(margin)

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", Tokens.SPACE_SM)
	margin.add_child(_menu_box)


# Rebuilt on every open rather than built once, because the entry list is
# context-dependent: RESUME and CONCEDE only mean anything inside a match, and a
# menu that offers "Concede" on the main menu is worse than one that is a frame
# slower to appear.
func _rebuild_menu() -> void:
	for child in _menu_box.get_children():
		child.queue_free()

	var heading := Label.new()
	heading.text = "SYSTEM"
	heading.theme_type_variation = "HeadingLabel"
	_menu_box.add_child(heading)
	_menu_box.add_child(HSeparator.new())

	var in_match := _in_match()

	if in_match:
		_add_entry("RESUME", func(): close())
	_add_entry("SETTINGS", func(): _open_settings())
	if in_match:
		_add_entry("OBJECTIVES", func(): _show_objectives())

	_menu_box.add_child(HSeparator.new())

	if in_match:
		_add_entry("CONCEDE MATCH", func(): _leave("res://scenes/MainMenu.tscn"), "danger")
	_add_entry("RETURN TO FRONT DESK", func(): _leave("res://scenes/MainMenu.tscn"))
	_add_entry("QUIT", func(): get_tree().quit(), "danger")

	var build := Label.new()
	build.text = "BUILD %s" % ProjectSettings.get_setting("application/config/version", "dev")
	build.theme_type_variation = "StatLabel"
	_menu_box.add_child(build)


func _add_entry(label: String, action: Callable, role: String = "default") -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 40)
	if role == "danger":
		btn.theme_type_variation = "DangerButton"
	UIFeedbackScript.wire(btn, role)
	btn.pressed.connect(action)
	_menu_box.add_child(btn)


# Duck-typed the same way handle_cancel() is: a match is any scene that declares
# `world_ready`, which is already the convention SceneRouter uses to decide
# whether to wait for a scene to finish building.
func _in_match() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.has_signal("world_ready")


func _leave(path: String) -> void:
	# Unpause BEFORE routing. A scene change while the tree is paused leaves the
	# incoming scene frozen with nothing left on screen able to unfreeze it.
	close()
	var router = get_node_or_null("/root/SceneRouter")
	if router != null:
		router.goto(path)
	else:
		get_tree().change_scene_to_file(path)


func _open_settings() -> void:
	# A PANEL IN THIS LAYER, NOT A SCENE. Settings has to be reachable from a
	# paused match, and a scene change would tear the match down to show a volume
	# slider. Built lazily so the panel's ~30 controls are not constructed for
	# every player who never opens it.
	if _settings_panel != null and is_instance_valid(_settings_panel):
		_settings_panel.visible = true
		_menu_host.visible = false
		return
	_settings_panel = SettingsPanelScript.new()
	_settings_panel.close_requested.connect(func():
		_settings_panel.visible = false
		_menu_host.visible = true)
	_panel_host.add_child(_settings_panel)
	_menu_host.visible = false


func _show_objectives() -> void:
	push_warning("SystemLayer: objectives panel not yet built")
