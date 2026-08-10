class_name PhosphorPanel
extends PanelContainer
# A CRT readout: the L2 phosphor layer, as a widget.
#
# WHY A WIDGET AND NOT JUST A THEME VARIATION. The other five materials are
# 9-sliced plates, so a StyleBoxTexture in bomber_theme.tres is enough for them.
# Phosphor is not a texture - it is a shader over whatever the control drew, and
# a Theme cannot carry a ShaderMaterial with per-instance parameters. So the
# glass, the bezel inset and the tube colour live here, and the theme still owns
# the BEZEL around it (PhosphorBezel) the same way it owns every other surface.
#
# THE ONE RULE: phosphor means live. Put telemetry on this; put labels on the
# bezel. See ui_tokens.gd's phosphor block and the shader's header.

const Tokens = preload("res://scripts/ui_tokens.gd")
const PhosphorShader = preload("res://shaders/phosphor_display.gdshader")

enum Tube { AMBER, GREEN }

# AMBER is the Design Lab register, GREEN is the battle register. Defaulting to
# amber rather than to "whatever the caller forgot to set" means an unconfigured
# panel is visibly in the wrong half of the game, which is easier to notice than
# a subtly wrong tint.
@export var tube: Tube = Tube.AMBER:
	set(value):
		tube = value
		_apply_tube()

var _mat: ShaderMaterial = null


func _init() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = PhosphorShader
	material = _mat


func _ready() -> void:
	_apply_tube()
	_apply_motion_preference()
	var s = get_node_or_null("/root/SettingsService")
	if s != null and not s.settings_changed.is_connected(_on_setting_changed):
		s.settings_changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, _value) -> void:
	if key == "reduced_motion":
		_apply_motion_preference()


func _apply_tube() -> void:
	if _mat == null:
		return
	var pair := Tokens.phosphor_pair("green" if tube == Tube.GREEN else "amber")
	_mat.set_shader_parameter("lit_color", pair["lit"])
	_mat.set_shader_parameter("unlit_color", pair["unlit"])
	_mat.set_shader_parameter("glass_color", pair["glass"])
	_mat.set_shader_parameter("scanline_pitch", Tokens.SCANLINE_PITCH)


# REDUCED MOTION KILLS THE FLICKER, not the whole effect. The scanlines, glass
# and bloom are static surface qualities and removing them would change what the
# interface is made of for no accessibility gain. The refresh flicker is the only
# part that actually moves, and it is exactly the kind of low-frequency
# luminance oscillation that triggers discomfort - so it is the part that goes.
func _apply_motion_preference() -> void:
	if _mat == null:
		return
	var reduced := false
	var s = get_node_or_null("/root/SettingsService")
	if s != null:
		reduced = bool(s.get_value("reduced_motion"))
	_mat.set_shader_parameter("flicker_amount", 0.0 if reduced else 0.012)


# Convenience for the common case: a readout that is one line of live numbers.
# Returns the Label so the caller can keep a reference and update it.
func add_readout(text: String = "") -> Label:
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", Tokens.BEZEL_INSET)
	inner.add_theme_constant_override("margin_right", Tokens.BEZEL_INSET)
	inner.add_theme_constant_override("margin_top", Tokens.SPACE_XS)
	inner.add_theme_constant_override("margin_bottom", Tokens.SPACE_XS)
	add_child(inner)

	var label := Label.new()
	label.text = text
	# Monospace, because these are tabular readouts and a proportional face makes
	# a counter change width as it ticks. Same reasoning as StatLabel's font.
	label.theme_type_variation = "StatLabel"
	# WHITE, not the tube colour. The shader treats whatever is drawn as
	# EXCITATION and colours it itself - drawing amber text on an amber tube
	# double-applies the tint and crushes the top end to a flat block.
	label.add_theme_color_override("font_color", Color.WHITE)
	inner.add_child(label)
	return label
