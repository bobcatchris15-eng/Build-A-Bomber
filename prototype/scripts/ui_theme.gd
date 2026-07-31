extends RefCounted
class_name UITheme
# Helpers for the parts of the interface a Theme resource can't express -
# the shader-backed backdrop, and a few "style this node like X" shortcuts
# for controls built in code.
#
# Everything with a StyleBox belongs in tools/build_ui_theme.gd instead.
# This file is for what has to happen at runtime.

const PANEL_SHADER = preload("res://shaders/brushed_aluminum_panel.gdshader")
const Tokens = preload("res://scripts/ui_tokens.gd")
const FactionCatalogScript = preload("res://scripts/faction_catalog.gd")


# Paints the sheet-metal backdrop onto a full-screen (or panel-sized) node.
#
# The shader needs to know the node's pixel size to keep its grain a fixed
# physical size, and a Control's size isn't final until layout has run - so
# this both pushes the current size and keeps it current via `resized`.
# Without that, the backdrop is correct at the design resolution and wrong
# at every other window size, which is the kind of bug that only shows up on
# someone else's monitor.
static func apply_backdrop(node: CanvasItem, accent: Color = Color.WHITE, accent_strength: float = 0.0) -> void:
	var mat := node.material as ShaderMaterial
	if not mat or mat.shader != PANEL_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = PANEL_SHADER
		node.material = mat
	mat.set_shader_parameter("accent_tint", accent)
	mat.set_shader_parameter("tint_strength", accent_strength)
	mat.set_shader_parameter("wear_amount", 0.3)

	if node is Control:
		var ctrl := node as Control
		var push := func() -> void:
			var s := ctrl.size
			if s.x > 1.0 and s.y > 1.0:
				mat.set_shader_parameter("panel_size", s)
		push.call()
		if not ctrl.resized.is_connected(push):
			ctrl.resized.connect(push)


# Backwards-compatible entry point for the existing call sites (main_menu,
# map_select, match_setup, parts_menu, skirmish, stat_calculator).
#
# The faction argument is now deliberately IGNORED for tinting. It used to
# repaint all UI chrome in the player's faction color, which collided with
# faction color's real job on the battlefield - telling the player who owns
# a unit. The parameter is kept so the call sites don't all have to change
# in the same commit as the visual work, and so the intent of "this panel
# belongs to the player" stays recorded at each site.
static func apply_brushed_panel(node: CanvasItem, _faction: String, _tint_strength: float = 0.55) -> void:
	apply_backdrop(node)


# For a genuine faction-identity surface - the faction picker's preview
# swatch, and nothing else. Kept separate so it can't be reached by accident.
static func apply_faction_preview(node: CanvasItem, faction: String) -> void:
	apply_backdrop(node, FactionCatalogScript.get_visual_color(faction), 0.45)


static func style_option_button(btn: OptionButton) -> void:
	# The theme covers OptionButton now; this remains only so existing
	# callers keep working. Deliberately a no-op rather than a second,
	# competing set of overrides - local overrides beat the theme, so the
	# old version of this function was actively preventing the design system
	# from reaching any dropdown in the game.
	pass


static func style_slider(_slider: HSlider) -> void:
	# Same reasoning as style_option_button(): HSlider is themed centrally.
	pass


# Applies a theme type variation, with a clear failure mode. Typo'd
# variation names fail silently in Godot (the control just renders with the
# base type's style), which is hard to spot in a screenshot.
const KNOWN_VARIATIONS = [
	"CardPanel", "HeaderPanel", "HUDPanel", "InsetPanel",
	"PrimaryButton", "DangerButton", "TabButton", "ListButton",
	"DisplayLabel", "TitleLabel", "HeadingLabel", "HintLabel",
	"HUDValueLabel", "StatLabel",
]

static func variation(ctrl: Control, name: String) -> Control:
	if name not in KNOWN_VARIATIONS:
		push_warning("UITheme: unknown theme variation '%s'" % name)
	ctrl.theme_type_variation = name
	return ctrl
