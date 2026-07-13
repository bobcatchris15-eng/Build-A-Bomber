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
