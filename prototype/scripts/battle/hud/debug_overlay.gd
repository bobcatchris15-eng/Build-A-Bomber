class_name DebugOverlay
extends Control
# The Skirmish-era "Debug" menu: live toggles for the developer cheats
# surfaced by the DebugSettings autoload (scripts/debug_settings.gd).
#
# WHY IT EXISTS AGAIN. The three flags - infinite_player_resources,
# instant_build, reveal_all_fog - have always been real runtime toggles
# (the gameplay services read them defensively every frame, see
# economy_service.gd:65, production_service.gd:114, vision_service.gd:258).
# The Battle-system unification (BATTLE_UNIFICATION_PLAN.md Phase 1)
# collapsed the old per-mode boot paths into a single Battle.tscn /
# match_director.gd, and along the way the old skirmish.gd HUD button
# that flipped these was lost - the cheats kept working (the services
# still consult the autoload) but there was no UI to set them. This
# overlay puts the buttons back, exactly where the old menu had them.
#
# SCOPE. This panel is intentionally tiny: three CheckBoxes that write
# to the autoload. It does NOT add new cheats, and it does NOT replicate
# the F1 tuning overlay (debug_tuning_panel.gd) which is a different
# concern - per-uniform visual slider, not gameplay cheat.
#
# VISIBILITY. Gated on `is_debug` by match_director.gd, the same gate
# the admin menu already uses, so a release build never ships with this
# on screen. F2 toggles it; the binding is registered with InputService
# (input_service.gd) so it shows up in the Controls screen alongside
# F1 (tuning overlay) and F3 (perf overlay).

const DebugSettingsScript = preload("res://scripts/debug_settings.gd")

const WIDTH := 260.0


func _ready() -> void:
	# Pinned top-left, below the F1 tuning overlay (which sits at y=60). The
	# tuning overlay is more frequently opened, so it stays above this one.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(20, 80)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# PROCESS_MODE_ALWAYS so F2 can dismiss the overlay mid-pause (e.g. the
	# admin menu pauses the tree; without this, the toggle would be inert
	# while the panel is hidden behind the pause menu).
	process_mode = Node.PROCESS_MODE_ALWAYS

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Debug Overlay  [F2]"
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	_add_checkbox(vbox, "Infinite Resources", "infinite_player_resources")
	_add_checkbox(vbox, "Instant Build", "instant_build")
	_add_checkbox(vbox, "Reveal All Fog", "reveal_all_fog")

	var hint := Label.new()
	hint.text = "Cheats persist for the session."
	hint.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(hint)

	_refresh_from_settings()


# Single shared handler instead of three. The bound `key` is appended via
# Callable.bind(), so the signature here is (pressed, key) rather than the
# (key, pressed) the bind order would suggest. Mirrors the same pattern in
# debug_tuning_panel.gd:154.
func _add_checkbox(parent: VBoxContainer, label_text: String, key: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label_text
	cb.focus_mode = Control.FOCUS_NONE
	parent.add_child(cb)
	cb.toggled.connect(_on_checkbox_toggled.bind(key))
	# Hand the checkbox back via a tag so _refresh_from_settings can find
	# it without a parallel name->cb dictionary. The autoload flag name and
	# the panel order are kept in sync by the calls above, so reading them
	# off in the same order is the only invariant _refresh needs.
	cb.set_meta("debug_key", key)
	return cb


func _on_checkbox_toggled(pressed: bool, key: String) -> void:
	var ds = DebugSettingsScript.get_active()
	if ds == null:
		return
	ds.set(key, pressed)


# Re-reads the autoload into the checkboxes. Called once on _ready and
# re-callable from outside if some other code flips a flag (none does
# today, but the hook is cheap and keeps the UI honest if it happens).
func _refresh_from_settings() -> void:
	var ds = DebugSettingsScript.get_active()
	if ds == null:
		return
	for c in get_children():
		# PanelContainer is the only Control child; descend into it to reach
		# the checkboxes, which are two layers down.
		if not (c is PanelContainer):
			continue
		for inner in c.find_children("*", "CheckBox", true, false):
			if not inner.has_meta("debug_key"):
				continue
			var key: String = inner.get_meta("debug_key")
			inner.set_pressed_no_signal(bool(ds.get(key)))


func _unhandled_input(event: InputEvent) -> void:
	# Prefer the InputService action so the keybind is rebindable from the
	# Controls screen (F1/F2/F3 cluster is already a recognised pattern in
	# the actions table). Fall back to a direct F2 check in case the action
	# is unavailable in a non-input-service boot path (headless tests).
	if event.is_action_pressed("sys_debug"):
		visible = not visible
		if visible:
			_refresh_from_settings()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			visible = not visible
			if visible:
				_refresh_from_settings()
			get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible
