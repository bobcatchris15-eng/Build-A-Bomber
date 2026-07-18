extends RefCounted
class_name UITheme
# Brushed-aluminum UI chrome, shared across every screen (Design Lab
# sidebar, Skirmish HUD, MainMenu/MapSelect/MatchSetup) - Chris's direct
# art brief: "bright and faintly goofy underneath a serious overtone,
# brushed anodized aluminum... color and wear switches based on faction."
# One shader (brushed_aluminum_panel.gdshader), one helper to stamp it onto
# any CanvasItem background - no per-screen bespoke styling code, matching
# how hull_material_builder.gd is the single hull-material entry point.

const PANEL_SHADER = preload("res://shaders/brushed_aluminum_panel.gdshader")
const FactionCatalogScript = preload("res://scripts/faction_catalog.gd")

# Applies (or refreshes) the brushed-aluminum look on any CanvasItem that
# has a `.material` property (Panel, PanelContainer, ColorRect, ...).
# Reuses the existing ShaderMaterial instance on repeated calls (e.g. when
# the player changes their faction selection live) instead of allocating a
# new one every time.
static func apply_brushed_panel(node: CanvasItem, faction: String, tint_strength: float = 0.55):
	var mat := node.material as ShaderMaterial
	if not mat or mat.shader != PANEL_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = PANEL_SHADER
		node.material = mat
	mat.set_shader_parameter("faction_tint", FactionCatalogScript.get_visual_color(faction))
	mat.set_shader_parameter("wear_amount", FactionCatalogScript.get_visual_wear_amount(faction))
	mat.set_shader_parameter("tint_strength", tint_strength)

static func style_option_button(btn: OptionButton) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	# set_border_enabled_all() is a Godot 3 API that doesn't exist on 4.3's
	# StyleBoxFlat - the invalid call errored out of this whole function at
	# runtime, so the border/corner styling below silently never applied
	# (found via test-run error spam). Border width > 0 is what enables
	# borders in Godot 4; no separate "enabled" call exists.
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("focus", style)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))

static func style_slider(slider: HSlider) -> void:
	var grabber = StyleBoxFlat.new()
	grabber.bg_color = Color(0.5, 0.5, 0.5, 1.0)
	# Same Godot 3 API removal as style_option_button() above.
	grabber.set_border_width_all(1)
	grabber.border_color = Color(0.3, 0.3, 0.3, 1.0)
	slider.add_theme_stylebox_override("grabber_area", grabber)
