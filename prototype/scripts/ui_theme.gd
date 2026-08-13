extends RefCounted
class_name UITheme
# Helpers for the parts of the interface a Theme resource can't express -
# the shader-backed backdrop, and a few "style this node like X" shortcuts
# for controls built in code.
#
# Everything with a StyleBox belongs in tools/build_ui_theme.gd instead.
# This file is for what has to happen at runtime.

const MATERIAL_SHADER = preload("res://shaders/ui_material.gdshader")
const Tokens = preload("res://scripts/ui_tokens.gd")
const LiveryScript = preload("res://scripts/livery.gd")

# ---------------------------------------------------------------------------
# MATERIAL VOCABULARY
# ---------------------------------------------------------------------------
# Six surfaces, each with one job. This is the list that replaces "pick a
# background colour" - a caller names what a thing is MADE OF and the
# appearance follows. See tools/generate_ui_plates.py for how each is authored
# and VISUAL_ART_DIRECTION.md for the wider material language.
#
#   POWDERCOAT  panel and dock bodies, HUD chrome
#   STEEL       frames, rails, splitters, toolbars, dividers
#   MOULDED     buttons, tabs, toggles, the radial ring
#   CANVAS      drawer/flyout backing, tooltips
#   CARBON      primary action only - SPARING, at most two per screen
#   FIBERGLASS  hazard placards, alert states
const MATERIALS = ["powdercoat", "steel", "moulded", "canvas", "carbon", "fiberglass", "toolbox"]

const FIELD_DIR = "res://assets/textures/ui/"

# Per-material shader defaults. Kept here rather than at call sites so that
# "canvas" looks like canvas everywhere without every caller remembering to
# turn the vignette down on cloth.
const MATERIAL_DEFAULTS = {
	"powdercoat": {"wear": 0.25, "grime": 0.20, "scale": 1.0, "vignette": 0.30},
	"steel":      {"wear": 0.35, "grime": 0.12, "scale": 1.0, "vignette": 0.22},
	"moulded":    {"wear": 0.10, "grime": 0.18, "scale": 0.8, "vignette": 0.18},
	# Cloth does not scuff to a bright edge and does not carry a corner
	# falloff the way a curved metal plate does - it is matte and flat.
	"canvas":     {"wear": 0.06, "grime": 0.30, "scale": 0.7, "vignette": 0.12},
	"carbon":     {"wear": 0.04, "grime": 0.08, "scale": 0.6, "vignette": 0.20},
	"fiberglass": {"wear": 0.15, "grime": 0.14, "scale": 1.0, "vignette": 0.24},
	# The Design Lab parts dock, and nothing else. wear is LOW despite this
	# being the most worn-looking surface in the game: the chips and scratches
	# are baked into field_toolbox.png as actual bare metal, and stacking the
	# shader's luminance scuff on top of them just washes the enamel out. grime
	# runs high instead - a toolbox collects dirt in every recess.
	"toolbox":    {"wear": 0.05, "grime": 0.34, "scale": 1.0, "vignette": 0.34},
}

static var _field_cache: Dictionary = {}


static func material_field(material: String) -> Texture2D:
	if _field_cache.has(material):
		return _field_cache[material]
	var path := FIELD_DIR + "field_%s.png" % material
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	else:
		# Not an error worth crashing over - the shader falls back to a flat
		# base_color - but it IS worth saying, because the symptom otherwise is
		# a panel that looks merely a bit plain.
		push_warning("UITheme: missing material field '%s'" % path)
	_field_cache[material] = tex
	return tex


# Paints a named MATERIAL onto a node. The general entry point; prefer this
# over apply_backdrop() for anything that is a surface rather than a backdrop.
#
# Like apply_backdrop(), this keeps the shader's `panel_size` in sync with the
# node - a Control's size is not final until layout has run, so pushing it once
# at setup gives a material that is correct at the design resolution and wrong
# at every other window size.
static func apply_material(node: CanvasItem, material: String,
		overrides: Dictionary = {}) -> void:
	if material not in MATERIALS:
		push_warning("UITheme: unknown material '%s'" % material)
		material = "powdercoat"

	var mat := node.material as ShaderMaterial
	if not mat or mat.shader != MATERIAL_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = MATERIAL_SHADER
		node.material = mat

	var field := material_field(material)
	mat.set_shader_parameter("material_field", field)
	mat.set_shader_parameter("has_field", field != null)

	var d: Dictionary = MATERIAL_DEFAULTS.get(material, MATERIAL_DEFAULTS["powdercoat"])
	mat.set_shader_parameter("wear_amount", overrides.get("wear", d["wear"]))
	mat.set_shader_parameter("grime_amount", overrides.get("grime", d["grime"]))
	mat.set_shader_parameter("field_scale", overrides.get("scale", d["scale"]))
	mat.set_shader_parameter("vignette", overrides.get("vignette", d["vignette"]))
	mat.set_shader_parameter("brightness", overrides.get("brightness", 1.0))
	mat.set_shader_parameter("tint_strength", overrides.get("tint_strength", 0.0))
	if overrides.has("tint"):
		mat.set_shader_parameter("accent_tint", overrides["tint"])

	_bind_panel_size(node, mat)


# Shared between apply_material() and apply_backdrop(): push the node's pixel
# size into the shader now and on every resize.
static func _bind_panel_size(node: CanvasItem, mat: ShaderMaterial) -> void:
	if not (node is Control):
		return
	var ctrl := node as Control
	var push := func() -> void:
		var s := ctrl.size
		if s.x > 1.0 and s.y > 1.0:
			mat.set_shader_parameter("panel_size", s)
	push.call()
	if not ctrl.resized.is_connected(push):
		ctrl.resized.connect(push)


# Paints the sheet-metal backdrop onto a full-screen (or panel-sized) node.
#
# The shader needs to know the node's pixel size to keep its grain a fixed
# physical size, and a Control's size isn't final until layout has run - so
# this both pushes the current size and keeps it current via `resized`.
# Without that, the backdrop is correct at the design resolution and wrong
# at every other window size, which is the kind of bug that only shows up on
# someone else's monitor.
# Now a thin wrapper over apply_material(). Backdrops are STEEL - the bare
# sheet the whole console is built on - held well below panel luminance by
# `brightness`, so that anything laid on top separates from it.
#
# That last part is load-bearing and was a real defect once: the first version
# of the backdrop used the same value as the panel bodies, and menu cards had
# nothing to sit on. A panel and its background at equal luminance read as one
# flat field no matter what border sits between them. The backdrop is the
# floor; everything else is above it.
static func apply_backdrop(node: CanvasItem, accent: Color = Color.WHITE, accent_strength: float = 0.0) -> void:
	apply_material(node, "steel", {
		"brightness": 0.42,
		"wear": 0.30,
		"grime": 0.25,
		"vignette": 0.30,
		"tint": accent,
		"tint_strength": accent_strength,
	})


# apply_brushed_panel() lived here as a back-compat shim over apply_backdrop()
# while the call sites were migrated off faction-tinted chrome. All of them have
# now moved - match_setup and the Design Lab call apply_backdrop() directly, and
# skirmish's top bar became a HUDPanel theme variation - so the shim is gone.
# Same for style_option_button() and style_slider(), which had already been
# reduced to `pass` once OptionButton and HSlider were themed centrally: a no-op
# that every screen still called only made it look like styling was happening.
#
# For a genuine faction-identity surface - the faction picker's preview
# swatch, and nothing else. Kept separate so it can't be reached by accident.
static func apply_faction_preview(node: CanvasItem, faction: String) -> void:
	apply_backdrop(node, LiveryScript.zone_color(faction, "hull_upper"), 0.45)




# Applies a theme type variation, with a clear failure mode. Typo'd
# variation names fail silently in Godot (the control just renders with the
# base type's style), which is hard to spot in a screenshot.
const KNOWN_VARIATIONS = [
	"CardPanel", "HeaderPanel", "HUDPanel", "InsetPanel",
	"DockPanel", "DockRail", "FlyoutPanel", "CalloutPanel",
	"PrimaryButton", "DangerButton", "TabButton", "ListButton",
	"DisplayLabel", "TitleLabel", "HeadingLabel", "HintLabel",
	"HUDValueLabel", "StatLabel",
]

static func variation(ctrl: Control, name: String) -> Control:
	if name not in KNOWN_VARIATIONS:
		push_warning("UITheme: unknown theme variation '%s'" % name)
	ctrl.theme_type_variation = name
	return ctrl
