extends Control
# Live tuning overlay (Phase 2, Milestone B). Toggle with F1 in Battlefield.tscn.
# Lets GlobalConfig's scale factors be adjusted while a fight plays out,
# instead of hand-editing GlobalConfig.gd and relaunching the test range.
# NOTE: auto_weapon.gd reads ModuleData.get_dps() once at spawn time, so
# changes only affect units spawned *after* the change - hence the
# "Respawn Player + Dummies" button below.

const GlobalConfig = preload("res://scripts/global_config.gd")

var battlefield: Node3D

var hp_slider: HSlider
var weight_slider: HSlider
var dps_slider: HSlider
var cost_slider: HSlider

var hp_label: Label
var weight_label: Label
var dps_label: Label
var cost_label: Label

func _ready():
	battlefield = get_parent()
	visible = false
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(20, 60)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "Tuning Overlay [F1]"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())
	hp_label = Label.new()
	vbox.add_child(hp_label)
	hp_slider = _make_slider(vbox, 0.0, 2.0, GlobalConfig.hp_scale_factor)
	hp_slider.value_changed.connect(_on_hp_changed)

	weight_label = Label.new()
	vbox.add_child(weight_label)
	weight_slider = _make_slider(vbox, 0.0, 2.0, GlobalConfig.weight_scale_factor)
	weight_slider.value_changed.connect(_on_weight_changed)

	dps_label = Label.new()
	vbox.add_child(dps_label)
	dps_slider = _make_slider(vbox, 0.0, 2.0, GlobalConfig.dps_scale_factor)
	dps_slider.value_changed.connect(_on_dps_changed)

	cost_label = Label.new()
	vbox.add_child(cost_label)
	cost_slider = _make_slider(vbox, 0.0, 2.0, GlobalConfig.cost_scale_factor)
	cost_slider.value_changed.connect(_on_cost_changed)

	vbox.add_child(HSeparator.new())
	var respawn_btn = Button.new()
	respawn_btn.text = "Respawn Player + Dummies"
	respawn_btn.modulate = Color(0.4, 0.7, 1, 1)
	respawn_btn.pressed.connect(_on_respawn_pressed)
	vbox.add_child(respawn_btn)

	var hint = Label.new()
	hint.text = "Changes apply live to newly-spawned units."
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	_refresh_labels()

func _make_slider(parent: VBoxContainer, min_v: float, max_v: float, initial: float) -> HSlider:
	var slider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.05
	slider.value = initial
	parent.add_child(slider)
	return slider

func _on_hp_changed(value: float):
	GlobalConfig.hp_scale_factor = value
	_refresh_labels()

func _on_weight_changed(value: float):
	GlobalConfig.weight_scale_factor = value
	_refresh_labels()

func _on_dps_changed(value: float):
	GlobalConfig.dps_scale_factor = value
	_refresh_labels()

func _on_cost_changed(value: float):
	GlobalConfig.cost_scale_factor = value
	_refresh_labels()

func _refresh_labels():
	hp_label.text = "HP Scale: %.2f" % GlobalConfig.hp_scale_factor
	weight_label.text = "Weight Scale: %.2f" % GlobalConfig.weight_scale_factor
	dps_label.text = "DPS Scale: %.2f" % GlobalConfig.dps_scale_factor
	cost_label.text = "Cost Scale: %.2f" % GlobalConfig.cost_scale_factor

func _on_respawn_pressed():
	if not battlefield: return
	var old_vehicle = battlefield.get("vehicle")
	if old_vehicle and is_instance_valid(old_vehicle):
		old_vehicle.queue_free()
	if battlefield.has_method("_spawn_vehicle"):
		battlefield.call_deferred("_spawn_vehicle")
	if battlefield.has_method("_spawn_target_dummies"):
		battlefield.call_deferred("_spawn_target_dummies")

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			visible = not visible
			get_viewport().set_input_as_handled()
