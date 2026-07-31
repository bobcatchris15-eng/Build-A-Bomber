class_name UITokens
extends RefCounted
# Single source of truth for the interface's visual language - palette, type
# scale, spacing, and border radii. Everything else (build_ui_theme.gd, the
# per-screen scripts, the panel shader) reads from here rather than writing
# its own literals.
#
# Why this file exists: before it, roughly half the UI came from
# bomber_theme.tres and the other half from StyleBoxFlat instances built
# inline in skirmish.gd / stat_calculator.gd / match_setup.gd with hardcoded
# colors. The two halves had drifted - the theme's accent was a cyan-blue
# (0.20, 0.60, 0.85) while the inline panels used a grey-blue (0.30, 0.35,
# 0.40), and the build buttons used flat saturated web red/green/blue that
# appear nowhere in the theme at all. A design system that only covers half
# the screen isn't one, so the literals had to collect somewhere.
#
# DIRECTION (Chris): units are cartoonish and semi-zany, terrain is serious
# and realistic, and all of it is played completely straight. The interface
# is on the serious side of that split. Its job is to be a quiet, credible
# instrument housing so the saturated toy-like units read as the loud thing
# on screen. If the UI competes with the units for saturation, both lose.

# ---------------------------------------------------------------------------
# PALETTE
# ---------------------------------------------------------------------------
# Base is a WARM neutral dark, not the blue-black it used to be. The old
# (0.07, 0.08, 0.10) base with a cyan accent is the default "sci-fi dark
# mode" palette that ships with every engine demo, and it fought the warm
# aluminum/olive direction the units and terrain already commit to. Warm
# greys also sit further from the cool sky and water the terrain renders,
# so the chrome separates from the world instead of blending into it.
const BASE_900 = Color(0.075, 0.074, 0.068, 1.0)  # deepest recess, modal scrim
const BASE_800 = Color(0.108, 0.106, 0.098, 1.0)  # panel body
const BASE_700 = Color(0.145, 0.142, 0.131, 1.0)  # raised control body
const BASE_600 = Color(0.196, 0.190, 0.174, 1.0)  # hover / raised edge
const BASE_500 = Color(0.290, 0.281, 0.257, 1.0)  # borders, dividers
const BASE_400 = Color(0.404, 0.392, 0.360, 1.0)  # disabled text, hairlines

# Text. Warm off-white rather than pure white - pure white on a warm dark
# panel reads as a blown-out highlight and vibrates at small sizes.
const TEXT_PRIMARY = Color(0.937, 0.925, 0.898, 1.0)
const TEXT_SECONDARY = Color(0.678, 0.663, 0.627, 1.0)
const TEXT_DISABLED = Color(0.435, 0.424, 0.396, 1.0)
const TEXT_INVERSE = Color(0.075, 0.074, 0.068, 1.0)  # on top of a signal fill

# SIGNAL COLORS. Deliberately few, and each one means exactly one thing
# everywhere it appears. This is the rule the old UI broke worst: it had a
# saturated red "Delete", a saturated green "Save", and a saturated blue
# "Test" sitting in a row, which spends the player's entire attention budget
# on three buttons that are not emergencies. Signal color is for STATE, not
# for decorating actions.
const SIGNAL_HAZARD = Color(0.878, 0.667, 0.180, 1.0)   # attention, selection, warning
const SIGNAL_ALERT = Color(0.784, 0.267, 0.196, 1.0)    # damage, failure, destructive
const SIGNAL_GO = Color(0.400, 0.612, 0.290, 1.0)       # ready, affordable, confirmed
const SIGNAL_INFO = Color(0.376, 0.573, 0.663, 1.0)     # informational only, never an action

# Dimmed variants, for fills that sit UNDER text rather than beside it.
const SIGNAL_HAZARD_DIM = Color(0.259, 0.204, 0.075, 1.0)
const SIGNAL_ALERT_DIM = Color(0.243, 0.098, 0.078, 1.0)
const SIGNAL_GO_DIM = Color(0.133, 0.196, 0.106, 1.0)

# ---------------------------------------------------------------------------
# TYPE SCALE
# ---------------------------------------------------------------------------
# Fixed steps, not arbitrary per-call font sizes. The old UI had 14, 15, 16,
# 18, 22, 24 and 42 scattered across call sites with no relationship between
# them, which is why nothing on screen looked like it belonged to anything
# else on screen.
const FONT_DISPLAY = 40  # title screen wordmark only
const FONT_TITLE = 24    # screen titles
const FONT_HEADING = 17  # panel/section headers
const FONT_BODY = 15     # default reading size
const FONT_SMALL = 13    # secondary/hint text
const FONT_MICRO = 11    # dense tabular readouts, footnotes

# ---------------------------------------------------------------------------
# SPACING - a 4px base grid. Every margin and gap should be one of these.
# ---------------------------------------------------------------------------
const SPACE_XS = 4
const SPACE_SM = 8
const SPACE_MD = 12
const SPACE_LG = 20
const SPACE_XL = 32

# ---------------------------------------------------------------------------
# GEOMETRY
# ---------------------------------------------------------------------------
# Near-square corners. The old 4-6px radii read as consumer-software
# roundedness; stamped and machined panels have a barely-broken edge. 2px is
# enough to keep corners from looking like an aliasing artifact without
# reading as "soft".
const RADIUS_PANEL = 2
const RADIUS_CONTROL = 2
const BORDER_HAIRLINE = 1
const BORDER_EMPHASIS = 2

# Minimum hit target for anything clicked during real-time play. Below this,
# the bottom command bar starts costing players fights.
const HIT_TARGET_MIN = 32


# Returns the fill/border pair for a signal role, so callers don't hand-pick
# a dim variant and get the pairing subtly wrong.
static func signal_pair(role: String) -> Dictionary:
	match role:
		"hazard":
			return {"fill": SIGNAL_HAZARD_DIM, "edge": SIGNAL_HAZARD}
		"alert":
			return {"fill": SIGNAL_ALERT_DIM, "edge": SIGNAL_ALERT}
		"go":
			return {"fill": SIGNAL_GO_DIM, "edge": SIGNAL_GO}
		_:
			return {"fill": BASE_700, "edge": BASE_500}
