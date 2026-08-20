class_name ToolboxPlate
extends Control
# The physical plate a production toolbox sits on.
#
# MOVED 2026-08-10 from battle/hud/ to scripts/. The plate and its sibling
# StampedLabel are no longer battle-specific chrome - the design lab's new
# bottom toolboxes (see ui_design_lab_toolboxes.gd) want the same chamfered
# metal and the same enamel lettering. The class_name is unchanged so every
# existing caller keeps compiling. NOTE 2026-08-20: production_hud.gd is gone
# (the battle HUD was rebuilt into scripts/hud/, which uses flat StyleBoxFlat
# panels and none of this chrome), so the remaining callers are admin_menu.gd
# and the design-lab widget - both out-of-match.
#
# WHY THIS IS A CUSTOM _draw() AND NOT A StyleBoxFlat. Chris asked for "heavily
# chamfered corners". StyleBoxFlat cannot do that - it offers `corner_radius`,
# which is a ROUNDED corner, and a heavy radius reads as a soft lozenge, the
# opposite of the machined-plate language the rest of the game is built in. A
# chamfer is a flat 45-degree cut, so it has to be an actual polygon.
#
# Everything is drawn behind the toolbox's own children rather than under them as
# a panel style, because the header Button and the CRT readout each own their own
# rect and neither should have to know the plate's shape.
#
# THREE PASSES, in the order light actually works on a thick metal plate:
#   1. A cast shadow, offset down and slightly out, so the plate reads as
#      floating above the battlefield rather than painted onto it.
#   2. The body.
#   3. A two-tone bevel - lit along the top and left edges, shaded along the
#      bottom and right. That single asymmetry is what makes a flat fill read as
#      having thickness; without it the chamfer is just a shape.

const Tokens = preload("res://scripts/ui_tokens.gd")

# How deep the corner cut is. "Heavily" chamfered, so this is a large fraction of
# the plate's short edge rather than a token 2 px nick.
const CHAMFER := 14.0
# How far the cast shadow falls. Beyond SHADOW_OFFSET_MODAL, because these plates
# float over a 3D scene rather than over another panel, and a 6 px offset that
# reads as elevation against a flat UI disappears against terrain.
const SHADOW_DROP := 9.0
const SHADOW_SPREAD := 3.0
const SHADOW_ALPHA := 0.55
# Width of the lit/shaded bevel run along each edge.
const BEVEL := 2.0

var body_color: Color = Tokens.BASE_700
var lit_color: Color = Tokens.BASE_500
var shade_color: Color = Tokens.BASE_900
var edge_color: Color = Tokens.BASE_500
# Set while this toolbox's queue is running, to tint the plate's rim. A dormant
# plate and a plate mid-build should not look identical from across the screen.
var accent: Color = Color(0, 0, 0, 0)


func _init() -> void:
	# STOP, so the plate absorbs anything the controls on top of it did not want -
	# specifically the mouse wheel, which would otherwise reach the camera's
	# _unhandled_input and zoom the world out from under a player who was reading
	# a build list.
	#
	# THIS HAS TO BE THE ENGINE'S PICK ORDER RATHER THAN A GEOMETRIC TEST. The
	# first attempt swallowed the wheel in _input() against the plate's rect, and
	# _input runs BEFORE GUI does - so it also stole the event from the build
	# list's own ScrollContainer and the list stopped scrolling. Here the plate is
	# the LAST thing under the cursor: the slot's controls are later siblings, so
	# they are picked first, and only what they decline lands here.
	#
	# It absorbs clicks too, which is correct - a click on the visible chamfered
	# border of a toolbox is a click on the toolbox, not an order to move units to
	# the ground behind it.
	mouse_filter = Control.MOUSE_FILTER_STOP


# The chamfered outline, inset by `inset` and offset by `offset`.
func _outline(inset: float, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var w: float = size.x - inset * 2.0
	var h: float = size.y - inset * 2.0
	# A chamfer bigger than half the short edge would invert the polygon, which
	# happens for real: a collapsed toolbox is only a few px tall while it slides.
	var c: float = minf(CHAMFER, minf(w, h) * 0.5)
	var o := Vector2(inset, inset) + offset
	return PackedVector2Array([
		o + Vector2(c, 0.0),
		o + Vector2(w - c, 0.0),
		o + Vector2(w, c),
		o + Vector2(w, h - c),
		o + Vector2(w - c, h),
		o + Vector2(c, h),
		o + Vector2(0.0, h - c),
		o + Vector2(0.0, c),
	])


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return

	var shadow := Tokens.SHADOW_COLOR
	shadow.a = SHADOW_ALPHA
	draw_colored_polygon(
		_outline(-SHADOW_SPREAD, Vector2(0.0, SHADOW_DROP)), shadow)

	var hull := _outline(0.0)
	draw_colored_polygon(hull, body_color)

	# The bevel. Points 7->0->1->2 are the top and left run (lit); 3->4->5->6 is
	# the bottom and right run (shaded). Drawn as thick polylines just inside the
	# hull so they sit ON the plate rather than outside its silhouette.
	var inner := _outline(BEVEL)
	draw_polyline(
		PackedVector2Array([inner[7], inner[0], inner[1], inner[2]]),
		lit_color, BEVEL, true)
	draw_polyline(
		PackedVector2Array([inner[3], inner[4], inner[5], inner[6]]),
		shade_color, BEVEL, true)

	var rim: Color = accent if accent.a > 0.0 else edge_color
	draw_polyline(
		hull + PackedVector2Array([hull[0]]),
		rim, 1.0, true)
