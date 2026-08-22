class_name CRTReadout
extends PanelContainer
# Reusable phosphor CRT readout widget.
# Used for resources, power, mission clock — amber or green tube.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UITheme = preload("res://scripts/ui_theme.gd")

@export var tube_color: String = "amber"  # "amber" | "green"
@export var font_size: int = 14
@export var show_scanlines: bool = true
@export var show_vignette: bool = true
@export var alignment: int = HORIZONTAL_ALIGNMENT_RIGHT

# Colorblind mode: swaps amber/green phosphor to high-contrast blue/white.
# Reads from SettingsService "colourblind_mode" (0=off, 1-3=various).
const COLORBLIND_LIT = Color(0.4, 0.6, 1.0, 1.0)
const COLORBLIND_UNLIT = Color(0.04, 0.06, 0.12, 1.0)
const COLORBLIND_GLASS = Color(0.02, 0.03, 0.05, 1.0)

var _label: Label
var _shader_material: ShaderMaterial
var _phosphor_shader: Shader = preload("res://shaders/phosphor_display.gdshader")

func _init() -> void:
	theme_type_variation = "HUDPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _ready() -> void:
	# Deferred from _init()/_build() because get_tree() is null during the
	# parent's _init() chain — a child added via add_child() inside a
	# parent's _init() has is_inside_tree() == true immediately, but
	# get_tree() returns null until the parent's _init() has fully returned.
	_apply_phosphor_shader()

func _build() -> void:
	_label = Label.new()
	_label.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
	_label.add_theme_font_size_override("font_size", font_size)
	_label.horizontal_alignment = alignment
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.clip_text = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_bind_panel_size()
	tree_entered.connect(_on_tree_entered)

func _on_tree_entered() -> void:
	var settings = _get_settings()
	if settings != null and settings.has_signal("settings_changed"):
		if not settings.settings_changed.is_connected(_on_settings_changed):
			settings.settings_changed.connect(_on_settings_changed)

func _on_settings_changed(key: String, _value) -> void:
	if key == "colourblind_mode" or key == "reduced_motion":
		_apply_phosphor_shader()

func _apply_phosphor_shader() -> void:
	var pair = Tokens.phosphor_pair(tube_color)
	var settings = _get_settings()
	if settings != null and settings.get("colourblind_mode", 0) != 0:
		pair = {"lit": COLORBLIND_LIT, "unlit": COLORBLIND_UNLIT, "glass": COLORBLIND_GLASS}
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = _phosphor_shader
	_shader_material.set_shader_parameter("lit_color", pair["lit"])
	_shader_material.set_shader_parameter("unlit_color", pair["unlit"])
	_shader_material.set_shader_parameter("glass_color", pair["glass"])
	_shader_material.set_shader_parameter("scanline_pitch", Tokens.SCANLINE_PITCH)
	_shader_material.set_shader_parameter("persistence_decay", Tokens.PERSISTENCE_DECAY)
	_shader_material.set_shader_parameter("enable_scanlines", show_scanlines)
	_shader_material.set_shader_parameter("enable_vignette", show_vignette)
	_shader_material.set_shader_parameter("enable_radar_sweep", false)
	_shader_material.set_shader_parameter("show_range_rings", false)
	var reduced := false
	if settings != null and settings.has_method("get_value"):
		reduced = bool(settings.get_value("reduced_motion"))
	_shader_material.set_shader_parameter("flicker_amount", 0.0 if reduced else 0.012)
	material = _shader_material

func _get_settings():
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root != null and root.has_node("SettingsService"):
		return root.get_node("SettingsService")
	return tree.get_first_node_in_group("settings_service")

func _bind_panel_size() -> void:
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_on_resized()

func _on_resized() -> void:
	if size.x > 1.0 and size.y > 1.0 and _shader_material != null:
		_shader_material.set_shader_parameter("panel_size", size)

func set_text(text: String) -> void:
	_label.text = text

func get_text() -> String:
	return _label.text

func set_tube_color(color: String) -> void:
	if color == tube_color:
		return
	tube_color = color
	_apply_phosphor_shader()