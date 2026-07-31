@tool
extends MainLoop
# Generates res://resources/bomber_theme.tres from the tokens in
# scripts/ui_tokens.gd. Run:
#   ./Godot_v4.3-stable_win64_console.exe --headless --script tools/build_ui_theme.gd --quit-after 2
#
# The theme is generated rather than hand-edited in the inspector so the
# palette lives in reviewable source and one token change repaints the whole
# interface. Do not edit bomber_theme.tres directly - it is an artifact.
#
# Coverage matters here. The previous version styled Panel, Button and two
# Label variations and nothing else, so every OptionButton, CheckBox,
# ProgressBar, ScrollBar and LineEdit in the game fell through to Godot's
# stock grey-blue default theme. That is the actual reason the shipped
# screens looked like a mix of two products: they were.

const Tokens = preload("res://scripts/ui_tokens.gd")

func _process(_delta: float) -> bool:
	build_theme()
	return true

func _load_font(path: String) -> FontFile:
	var font = FontFile.new()
	if font.load_dynamic_font(path) == OK:
		return font
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is FontFile:
			return res as FontFile
	return null

# StyleBoxFlat has no set_*_all() helpers in Godot 4 (they were Godot 3 APIs -
# calling them silently aborted the rest of the styling function, which is how
# the old theme's borders quietly never applied). These wrap the per-side
# assignment so that mistake can't recur.
func _flat(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_width
	sb.border_width_right = border_width
	sb.border_width_top = border_width
	sb.border_width_bottom = border_width
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	return sb

func _pad(sb: StyleBoxFlat, h: int, v: int) -> StyleBoxFlat:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb

func build_theme() -> void:
	print("Building theme -> res://resources/bomber_theme.tres")
	var theme = Theme.new()

	var ui_reg = _load_font("res://assets/fonts/UIFont-Regular.ttf")
	var ui_bold = _load_font("res://assets/fonts/UIFont-Bold.ttf")
	var mono_reg = _load_font("res://assets/fonts/MonoFont-Regular.ttf")
	var stencil = _load_font("res://assets/fonts/StencilFont-Regular.ttf")

	# The DEFAULT font is the clean UI sans, not the stencil face.
	#
	# This is a deliberate reversal. The stencil (Special Elite - a worn
	# typewriter face) used to be the default, which meant every label,
	# button, tooltip and dropdown in the game rendered in a deliberately
	# irregular, ink-blotted typeface at 13-15px. It gives one strong
	# impression on a title and becomes unreadable mush in a 24-row parts
	# list - see the MainLab and MatchSetup baseline captures, where the
	# body text is genuinely hard to parse.
	#
	# The stencil now does what a display face should: titles and section
	# headers, where it is large, short, and carrying the tone on its own.
	if ui_reg:
		ui_reg.multichannel_signed_distance_field = true
		theme.set_default_font(ui_reg)
	elif stencil:
		theme.set_default_font(stencil)
	theme.set_default_font_size(Tokens.FONT_BODY)

	_build_panels(theme)
	_build_buttons(theme)
	_build_labels(theme, stencil, ui_bold, mono_reg)
	_build_inputs(theme, mono_reg)
	_build_bars(theme)
	_build_misc(theme)
	# MUST come after the builders above - see _register_variations().
	_register_variations(theme)

	var err = ResourceSaver.save(theme, "res://resources/bomber_theme.tres")
	print("  saved" if err == OK else "  FAILED, error %d" % err)


# Every theme type variation MUST be registered against its base class or
# Godot never resolves it.
#
# This was silently broken for the entire life of the old theme. Setting
# `theme_type_variation = "CardPanel"` on a PanelContainer does nothing
# unless the Theme also knows CardPanel derives from PanelContainer - the
# lookup finds no such type and quietly falls back to the control's own
# class. So every CardPanel, HeaderPanel, TitleLabel, PrimaryButton and
# DangerButton in the game was rendering as a plain Panel/Label/Button.
#
# It was invisible because the old theme's default font was the stencil
# face, which made the "TitleLabel" headings look intentional. They were
# just inheriting the default.
#
# There is no error and no warning for this. The only symptom is a control
# that looks slightly plainer than expected, which is exactly the kind of
# thing that survives review for months.
#
# ORDERING, learned the hard way: set_type_variation_base() only takes on a
# theme type that ALREADY EXISTS. Called before the styleboxes/fonts that
# create the type, it is silently discarded - nothing is written and nothing
# complains. So this runs last, after every builder has populated its types.
# Verified with scratch/probe_theme.gd, which asks a live Control what it
# resolves rather than trusting the saved .tres.
const VARIATION_BASES = {
	"CardPanel": "PanelContainer",
	"HeaderPanel": "PanelContainer",
	"HUDPanel": "PanelContainer",
	"InsetPanel": "PanelContainer",
	"PrimaryButton": "Button",
	"DangerButton": "Button",
	"TabButton": "Button",
	"ListButton": "Button",
	"DisplayLabel": "Label",
	"TitleLabel": "Label",
	"HeadingLabel": "Label",
	"HintLabel": "Label",
	"HUDValueLabel": "Label",
	"StatLabel": "Label",
}

func _register_variations(theme: Theme) -> void:
	# NOTE the asymmetric API: the setter is set_type_variation(), but the
	# getter is get_type_variation_base(). Calling the plausible-sounding
	# set_type_variation_base() raises "Nonexistent function" - which, in a
	# @tool MainLoop, does not stop the build. The theme saved "successfully"
	# with the variation bases missing, so the only visible symptom was
	# controls continuing to render as their plain base class.
	for variation in VARIATION_BASES:
		theme.set_type_variation(variation, VARIATION_BASES[variation])


func _build_panels(theme: Theme) -> void:
	# Base panel: opaque enough to actually be a surface. The old panel was
	# 0.88 alpha and several screens used no panel at all, so text was
	# landing directly on the 3D viewport (see the MainLab baseline capture -
	# the entire right-hand stat column is unreadable against the sky).
	# Chrome that a player reads mid-fight is not a place for transparency.
	var panel = _pad(_flat(Tokens.BASE_800, Tokens.BASE_500,
		Tokens.BORDER_HAIRLINE, Tokens.RADIUS_PANEL), Tokens.SPACE_MD, Tokens.SPACE_MD)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)

	# CardPanel - a free-floating card on a backdrop (menus, dialogs).
	var card = _pad(_flat(Tokens.BASE_800, Tokens.BASE_400,
		Tokens.BORDER_EMPHASIS, Tokens.RADIUS_PANEL), Tokens.SPACE_XL, Tokens.SPACE_LG)
	theme.set_stylebox("panel", "CardPanel", card)

	# HeaderPanel - a titled band. Its identity is the hazard underline, not
	# a fill, so it can sit on top of any panel without introducing a
	# third background value.
	var header = _flat(Tokens.BASE_700, Tokens.SIGNAL_HAZARD, 0, 0)
	header.border_width_bottom = Tokens.BORDER_EMPHASIS
	_pad(header, Tokens.SPACE_MD, Tokens.SPACE_SM)
	theme.set_stylebox("panel", "HeaderPanel", header)

	# HUDPanel - in-match chrome. Slightly darker and fully opaque so unit
	# colors never bleed through and confuse ownership reads.
	var hud = _pad(_flat(Tokens.BASE_900, Tokens.BASE_500,
		Tokens.BORDER_HAIRLINE, 0), Tokens.SPACE_SM, Tokens.SPACE_XS)
	theme.set_stylebox("panel", "HUDPanel", hud)

	# InsetPanel - a recessed well (list backgrounds, viewport surrounds).
	var inset = _pad(_flat(Tokens.BASE_900, Tokens.BASE_700,
		Tokens.BORDER_HAIRLINE, Tokens.RADIUS_PANEL), Tokens.SPACE_SM, Tokens.SPACE_SM)
	theme.set_stylebox("panel", "InsetPanel", inset)


func _build_buttons(theme: Theme) -> void:
	# Every state is defined, including disabled. The old theme left
	# "disabled" unset, so a greyed-out build button (there is real logic
	# gating these on having a manufactory of the right tier) looked
	# identical to an available one.
	var normal = _pad(_flat(Tokens.BASE_700, Tokens.BASE_500,
		Tokens.BORDER_HAIRLINE, Tokens.RADIUS_CONTROL), Tokens.SPACE_MD, Tokens.SPACE_SM)

	var hover = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Tokens.BASE_600
	hover.border_color = Tokens.BASE_400

	# Pressed reads as physically depressed: darker than its own rest state,
	# with the top border brightened to imply a lip catching the light.
	var pressed = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Tokens.BASE_900
	pressed.border_color = Tokens.SIGNAL_HAZARD
	pressed.content_margin_top = Tokens.SPACE_SM + 1
	pressed.content_margin_bottom = Tokens.SPACE_SM - 1

	var disabled = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Tokens.BASE_800
	disabled.border_color = Tokens.BASE_700

	# Focus is a hazard hairline, never a fill - a fill would collide with
	# the pressed/selected reads during keyboard navigation.
	var focus = _flat(Color(0, 0, 0, 0), Tokens.SIGNAL_HAZARD,
		Tokens.BORDER_HAIRLINE, Tokens.RADIUS_CONTROL)

	for type in ["Button", "MenuButton", "OptionButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_color", type, Tokens.TEXT_PRIMARY)
		theme.set_color("font_hover_color", type, Tokens.TEXT_PRIMARY)
		theme.set_color("font_pressed_color", type, Tokens.SIGNAL_HAZARD)
		theme.set_color("font_disabled_color", type, Tokens.TEXT_DISABLED)
		theme.set_constant("h_separation", type, Tokens.SPACE_SM)

	# PrimaryButton - the single "commit" action on a screen. Neutral body
	# with a go-green edge and green text, rather than a saturated green
	# slab. It still wins the screen because it is the only green thing on
	# it, and it does not shout at the player during a match.
	var prim = normal.duplicate() as StyleBoxFlat
	prim.bg_color = Tokens.SIGNAL_GO_DIM
	prim.border_color = Tokens.SIGNAL_GO
	prim.border_width_bottom = Tokens.BORDER_EMPHASIS
	var prim_hover = prim.duplicate() as StyleBoxFlat
	prim_hover.bg_color = Tokens.SIGNAL_GO_DIM.lightened(0.10)
	theme.set_stylebox("normal", "PrimaryButton", prim)
	theme.set_stylebox("hover", "PrimaryButton", prim_hover)
	theme.set_stylebox("pressed", "PrimaryButton", pressed)
	theme.set_stylebox("disabled", "PrimaryButton", disabled)
	theme.set_color("font_color", "PrimaryButton", Tokens.TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "PrimaryButton", Tokens.TEXT_DISABLED)

	# DangerButton - irreversible only (delete, sell, quit to desktop).
	var danger = normal.duplicate() as StyleBoxFlat
	danger.bg_color = Tokens.SIGNAL_ALERT_DIM
	danger.border_color = Tokens.SIGNAL_ALERT
	var danger_hover = danger.duplicate() as StyleBoxFlat
	danger_hover.bg_color = Tokens.SIGNAL_ALERT_DIM.lightened(0.10)
	theme.set_stylebox("normal", "DangerButton", danger)
	theme.set_stylebox("hover", "DangerButton", danger_hover)
	theme.set_stylebox("pressed", "DangerButton", pressed)
	theme.set_stylebox("disabled", "DangerButton", disabled)
	theme.set_color("font_color", "DangerButton", Tokens.TEXT_PRIMARY)

	# TabButton - a latched selector. Selected state is carried by a hazard
	# bar along the bottom edge plus a lifted fill, so it reads as a
	# mechanically held-down control rather than just a recolor. This is the
	# pattern the build tabs and the parts-catalog categories both use.
	var tab = _pad(_flat(Tokens.BASE_800, Tokens.BASE_500,
		Tokens.BORDER_HAIRLINE, 0), Tokens.SPACE_MD, Tokens.SPACE_SM)
	var tab_hover = tab.duplicate() as StyleBoxFlat
	tab_hover.bg_color = Tokens.BASE_700
	var tab_on = tab.duplicate() as StyleBoxFlat
	tab_on.bg_color = Tokens.BASE_600
	tab_on.border_color = Tokens.SIGNAL_HAZARD
	tab_on.border_width_bottom = 3
	theme.set_stylebox("normal", "TabButton", tab)
	theme.set_stylebox("hover", "TabButton", tab_hover)
	theme.set_stylebox("pressed", "TabButton", tab_on)
	theme.set_stylebox("disabled", "TabButton", tab)
	theme.set_color("font_color", "TabButton", Tokens.TEXT_SECONDARY)
	theme.set_color("font_pressed_color", "TabButton", Tokens.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "TabButton", Tokens.TEXT_PRIMARY)

	# ListButton - a row in a scrolling list (parts catalog, map select,
	# blueprint library). Flat and borderless at rest so a long list reads
	# as a list instead of as fifty stacked buttons; gains a hazard left
	# edge when selected.
	var row = _pad(_flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0),
		Tokens.SPACE_MD, Tokens.SPACE_SM)
	var row_hover = _pad(_flat(Tokens.BASE_700, Color(0, 0, 0, 0), 0, 0),
		Tokens.SPACE_MD, Tokens.SPACE_SM)
	var row_on = _flat(Tokens.BASE_600, Tokens.SIGNAL_HAZARD, 0, 0)
	row_on.border_width_left = 3
	_pad(row_on, Tokens.SPACE_MD, Tokens.SPACE_SM)
	theme.set_stylebox("normal", "ListButton", row)
	theme.set_stylebox("hover", "ListButton", row_hover)
	theme.set_stylebox("pressed", "ListButton", row_on)
	theme.set_stylebox("focus", "ListButton", row)
	theme.set_color("font_color", "ListButton", Tokens.TEXT_SECONDARY)
	theme.set_color("font_hover_color", "ListButton", Tokens.TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "ListButton", Tokens.TEXT_PRIMARY)


func _build_labels(theme: Theme, stencil: FontFile, ui_bold: FontFile, mono: FontFile) -> void:
	theme.set_color("font_color", "Label", Tokens.TEXT_PRIMARY)
	theme.set_font_size("font_size", "Label", Tokens.FONT_BODY)

	# The stencil face earns its keep here and nowhere else.
	var display_font = stencil if stencil else ui_bold
	if display_font:
		theme.set_font("font", "DisplayLabel", display_font)
		theme.set_font("font", "TitleLabel", display_font)
		theme.set_font("font", "HeadingLabel", display_font)
	theme.set_font_size("font_size", "DisplayLabel", Tokens.FONT_DISPLAY)
	theme.set_color("font_color", "DisplayLabel", Tokens.TEXT_PRIMARY)
	theme.set_font_size("font_size", "TitleLabel", Tokens.FONT_TITLE)
	theme.set_color("font_color", "TitleLabel", Tokens.TEXT_PRIMARY)
	theme.set_font_size("font_size", "HeadingLabel", Tokens.FONT_HEADING)
	theme.set_color("font_color", "HeadingLabel", Tokens.SIGNAL_HAZARD)

	theme.set_font_size("font_size", "HintLabel", Tokens.FONT_SMALL)
	theme.set_color("font_color", "HintLabel", Tokens.TEXT_SECONDARY)

	# Numeric readouts stay on the monospace face for real tabular figures -
	# a resource counter that changes width as it ticks is a genuine
	# readability problem at a glance, not a stylistic preference.
	if mono:
		theme.set_font("font", "HUDValueLabel", mono)
		theme.set_font("font", "StatLabel", mono)
	theme.set_font_size("font_size", "HUDValueLabel", Tokens.FONT_HEADING)
	theme.set_color("font_color", "HUDValueLabel", Tokens.TEXT_PRIMARY)
	theme.set_font_size("font_size", "StatLabel", Tokens.FONT_SMALL)
	theme.set_color("font_color", "StatLabel", Tokens.TEXT_SECONDARY)


func _build_inputs(theme: Theme, mono: FontFile) -> void:
	var field = _pad(_flat(Tokens.BASE_900, Tokens.BASE_500,
		Tokens.BORDER_HAIRLINE, Tokens.RADIUS_CONTROL), Tokens.SPACE_SM, Tokens.SPACE_SM)
	var field_focus = field.duplicate() as StyleBoxFlat
	field_focus.border_color = Tokens.SIGNAL_HAZARD
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_color("font_color", "LineEdit", Tokens.TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", Tokens.TEXT_DISABLED)
	theme.set_color("caret_color", "LineEdit", Tokens.SIGNAL_HAZARD)
	if mono:
		theme.set_font("font", "LineEdit", mono)

	theme.set_color("font_color", "CheckBox", Tokens.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "CheckBox", Tokens.TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "CheckBox", Tokens.TEXT_DISABLED)
	theme.set_constant("h_separation", "CheckBox", Tokens.SPACE_SM)

	# Slider: a thin recessed track with a substantial grabber. The old theme
	# styled only "grabber_area" and left the track and grabber themselves
	# on engine defaults, so sliders were the most obviously off-brand
	# control in the Design Lab.
	var track = _flat(Tokens.BASE_900, Tokens.BASE_700, Tokens.BORDER_HAIRLINE, 1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	theme.set_stylebox("slider", "HSlider", track)
	var fill = _flat(Tokens.SIGNAL_HAZARD_DIM, Tokens.SIGNAL_HAZARD, Tokens.BORDER_HAIRLINE, 1)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)

	var popup = _pad(_flat(Tokens.BASE_800, Tokens.BASE_400,
		Tokens.BORDER_EMPHASIS, Tokens.RADIUS_PANEL), Tokens.SPACE_XS, Tokens.SPACE_XS)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_color("font_color", "PopupMenu", Tokens.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "PopupMenu", Tokens.SIGNAL_HAZARD)
	theme.set_color("font_separator_color", "PopupMenu", Tokens.BASE_500)
	theme.set_constant("v_separation", "PopupMenu", Tokens.SPACE_XS)


func _build_bars(theme: Theme) -> void:
	# ProgressBar is load-bearing in this game - it is the production queue
	# readout and the power meter. It was running on engine defaults.
	theme.set_stylebox("background", "ProgressBar",
		_flat(Tokens.BASE_900, Tokens.BASE_700, Tokens.BORDER_HAIRLINE, 1))
	theme.set_stylebox("fill", "ProgressBar",
		_flat(Tokens.SIGNAL_GO_DIM, Tokens.SIGNAL_GO, Tokens.BORDER_HAIRLINE, 1))
	theme.set_color("font_color", "ProgressBar", Tokens.TEXT_PRIMARY)

	for axis in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", axis, _flat(Tokens.BASE_900, Color(0, 0, 0, 0), 0, 1))
		theme.set_stylebox("grabber", axis, _flat(Tokens.BASE_600, Color(0, 0, 0, 0), 0, 1))
		theme.set_stylebox("grabber_highlight", axis, _flat(Tokens.BASE_500, Color(0, 0, 0, 0), 0, 1))
		theme.set_stylebox("grabber_pressed", axis, _flat(Tokens.SIGNAL_HAZARD, Color(0, 0, 0, 0), 0, 1))


func _build_misc(theme: Theme) -> void:
	# Tooltips were unstyled, which meant every hover hint in the game
	# appeared in Godot's stock pale-yellow box.
	var tip = _pad(_flat(Tokens.BASE_900, Tokens.SIGNAL_HAZARD,
		Tokens.BORDER_HAIRLINE, Tokens.RADIUS_CONTROL), Tokens.SPACE_SM, Tokens.SPACE_XS)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", Tokens.TEXT_PRIMARY)
	theme.set_font_size("font_size", "TooltipLabel", Tokens.FONT_SMALL)

	theme.set_color("separator", "HSeparator", Tokens.BASE_500)
	theme.set_constant("separation", "HSeparator", Tokens.SPACE_SM)
	theme.set_color("separator", "VSeparator", Tokens.BASE_500)

	theme.set_stylebox("panel", "AcceptDialog",
		_pad(_flat(Tokens.BASE_800, Tokens.BASE_400, Tokens.BORDER_EMPHASIS,
			Tokens.RADIUS_PANEL), Tokens.SPACE_LG, Tokens.SPACE_LG))
