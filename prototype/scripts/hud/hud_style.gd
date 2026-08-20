class_name HUDStyle
extends RefCounted
# The whole visual vocabulary of the battle HUD, in one file.
#
# THIS IS A DELIBERATE BREAK from ui_tokens.gd / bakelite_panel.gd /
# crt_readout.gd / aluminum_trim.gd / folded_paper_panel.gd. Those build a
# diegetic 1950s command desk by generating textures at runtime, and the battle
# HUD is the one surface where that costs more than it pays: the player reads
# these panels while something is shooting at them. Every value here is chosen
# for legibility at a glance, and nothing here generates a texture.
#
# The rules, so a later addition stays consistent:
#   - Panels are flat fills with a 1 px edge. No gradients, no bevels, no noise.
#   - Colour carries exactly one meaning at a time. TEAM_FRIENDLY is never used
#     for "good", OK is never used for "friendly".
#   - Numbers are monospaced so a changing digit does not reflow the row.
#   - Icons are monochrome white SVGs tinted by modulate. Never a coloured icon.

# --- Palette ----------------------------------------------------------------
# Neutral ramp. Dark enough that the 3D world reads as brighter than the HUD,
# which is what keeps the eye in the battle rather than on the chrome.
const VOID        := Color(0.055, 0.067, 0.086)   # #0E1116 deepest, minimap unexplored
const PANEL       := Color(0.086, 0.106, 0.133)   # #161B22 panel fill
const PANEL_RAISE := Color(0.118, 0.145, 0.180)   # #1E252E interactive surface
const PANEL_HOVER := Color(0.157, 0.192, 0.235)   # #28313C hover
const EDGE        := Color(0.173, 0.208, 0.247)   # #2C353F panel edge
const EDGE_BRIGHT := Color(0.243, 0.290, 0.341)   # #3E4A57 divider / active edge

const TEXT        := Color(0.894, 0.914, 0.937)   # #E4E9EF primary
const TEXT_DIM    := Color(0.541, 0.588, 0.639)   # #8A96A3 secondary
const TEXT_FAINT  := Color(0.353, 0.400, 0.455)   # #5A6674 disabled / hint

# Semantic. Kept apart from the team colours on purpose.
const OK          := Color(0.373, 0.788, 0.541)   # #5FC98A complete, affordable
const WARN        := Color(0.910, 0.639, 0.239)   # #E8A33D low power, stalled
const BAD         := Color(0.910, 0.337, 0.310)   # #E8564F unaffordable, damage

# Team identity. Also the minimap blip colours - one definition, so a blip and
# a selection ring can never disagree about which side a unit is on.
const TEAM_FRIENDLY := Color(0.310, 0.690, 0.910)  # #4FB0E8
const TEAM_HOSTILE  := Color(0.910, 0.337, 0.310)  # #E8564F
const TEAM_NEUTRAL  := Color(0.678, 0.706, 0.741)  # #ADB4BD

# Resources. Distinct from every status colour so a resource count is never
# mistaken for a warning.
const METAL       := Color(0.780, 0.800, 0.820)
const CRYSTAL     := Color(0.545, 0.694, 0.910)
const POWER       := Color(0.910, 0.780, 0.318)

const SELECTED    := Color(1.0, 1.0, 1.0)

# --- Metrics ----------------------------------------------------------------
const SP_XS := 3
const SP_SM := 6
const SP_MD := 10
const SP_LG := 16
const SP_XL := 24

const RADIUS := 2        # near-square. Rounded corners read as "app", not "instrument".
const BORDER := 1

# Minimum comfortable click target. Every button here meets it.
const HIT := 28

# --- Layout -----------------------------------------------------------------
# The bottom band that holds map / production / command card. Everything above
# it is battle viewport and stays clear.
# The map is SQUARE and fills the band's full height, so these two are one
# number. They were 208 and 240, which made the map 32 px taller than the band it
# sits in - it would have hung over the production deck's top edge.
const BAND_HEIGHT := 224.0
const MAP_SIZE := 224.0
const CARD_WIDTH := 320.0
const RIBBON_HEIGHT := 34.0

# --- Type -------------------------------------------------------------------
const FONT_UI := "res://assets/fonts/UIFont-Regular.ttf"
const FONT_UI_BOLD := "res://assets/fonts/UIFont-Bold.ttf"
const FONT_MONO := "res://assets/fonts/MonoFont-Regular.ttf"

const SZ_MICRO := 10
const SZ_SMALL := 12
const SZ_BODY  := 14
const SZ_HEAD  := 16
const SZ_BIG   := 20


static func font(path: String) -> Font:
	# load() not preload(): a static func cannot hold a preload constant, and
	# the engine resource cache makes the repeat cost a dictionary lookup.
	var f = load(path)
	return f if f is Font else null


# --- Panels -----------------------------------------------------------------

# The one panel look. `raised` is for anything the mouse interacts with;
# unraised is for backing surfaces.
static func panel_box(raised: bool = false, edge: Color = EDGE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_RAISE if raised else PANEL
	sb.set_border_width_all(BORDER)
	sb.border_color = edge
	sb.set_corner_radius_all(RADIUS)
	sb.set_content_margin_all(SP_MD)
	return sb


# A filled swatch with no border - progress fills, badges, 2D blips.
static func fill_box(c: Color, radius: int = RADIUS) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(0)
	return sb


# An empty box that only draws one edge. Used for tab underlines, where a full
# border would box in content meant to read as continuous with its body.
static func underline_box(c: Color, thickness: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_width_bottom = thickness
	sb.border_color = c
	sb.set_content_margin_all(0)
	return sb


static func apply_panel(to: Control, raised: bool = false, edge: Color = EDGE) -> void:
	to.add_theme_stylebox_override("panel", panel_box(raised, edge))


# --- Labels -----------------------------------------------------------------

static func label(text: String, size: int = SZ_BODY, color: Color = TEXT,
		mono: bool = false, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	var path := FONT_MONO if mono else (FONT_UI_BOLD if bold else FONT_UI)
	var f := font(path)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


# A number that changes every tick. Monospaced and right-aligned so the row does
# not twitch as digits gain and lose width.
static func readout(text: String, size: int = SZ_BODY, color: Color = TEXT) -> Label:
	var l := label(text, size, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


# Small all-caps section heading.
static func heading(text: String) -> Label:
	return label(text.to_upper(), SZ_MICRO, TEXT_DIM, false, true)


# --- Buttons ----------------------------------------------------------------
# One button appearance, four states. Built as an explicit StyleBox set rather
# than a theme type variation so the battle HUD does not inherit from
# bomber_theme.tres and cannot be broken by a lab-side theme edit.
static func style_button(b: Button, accent: Color = TEAM_FRIENDLY) -> void:
	var normal := panel_box(true)
	var hover := panel_box(true, EDGE_BRIGHT)
	hover.bg_color = PANEL_HOVER
	var pressed := panel_box(true, accent)
	pressed.bg_color = PANEL_HOVER.lerp(accent, 0.25)
	var disabled := panel_box(false)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("disabled", disabled)

	var f := font(FONT_UI)
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", SZ_SMALL)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	b.focus_mode = Control.FOCUS_NONE


static func button(text: String, accent: Color = TEAM_FRIENDLY) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, HIT)
	style_button(b, accent)
	return b


# --- Small compound widgets -------------------------------------------------

# A 1 px rule. Horizontal by default; `vertical` for column separators.
static func divider(vertical: bool = false) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", fill_box(EDGE, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		p.custom_minimum_size = Vector2(1, 0)
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		p.custom_minimum_size = Vector2(0, 1)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


# A thin bar. ProgressBar rather than two Panels because it already clamps and
# lays out the fill; the theme baggage is fully overridden here.
static func bar(height: int, fill: Color, track: Color = VOID) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = 0.0
	pb.custom_minimum_size = Vector2(0, height)
	pb.add_theme_stylebox_override("background", fill_box(track, 0))
	pb.add_theme_stylebox_override("fill", fill_box(fill, 0))
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb


# Colour for an HP fraction. Three bands, not a gradient: a gradient makes "is
# that unit in trouble" a judgement call instead of a glance.
static func health_color(frac: float) -> Color:
	if frac > 0.6:
		return OK
	if frac > 0.3:
		return WARN
	return BAD
