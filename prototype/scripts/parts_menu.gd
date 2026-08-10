extends Control
# The Design Lab's hardware catalog.
#
# REWRITTEN 2026-08-10. The previous incarnation parked the catalog in a
# left-side UIDock, RAILED by default, with a TabContainer inside, a search
# box at the top, and accordion-within-accordion drill-in. The dock took
# a fifth of the screen from the model it was editing.
#
# The new shape is FOUR FLOATING TOOLBOXES along the bottom of the screen,
# matching the Skirmish build queue (production_hud.gd): one per family
# (Hulls / Weapons / Support / Drives), each with a chamfered ToolboxPlate
# and a StampedLabel header. Aesthetically identical to the build queue
# because they ARE the same chrome - the plate and the stamp were moved
# out of battle/hud/ into scripts/ in the commit immediately before this
# one, so the two screens cannot drift on the look.
#
# Cross-toolbox behaviour: only one family's body is open at a time.
# Opening a family closes the other three. Within an open family, the
# sub-family drawers accordion among themselves (the existing
# _open_category behaviour, preserved from the previous build).
#
# Search: previously the first control in the dock, it is now behind a
# magnifying-glass icon at the right end of the bar. Clicking the icon
# opens a UIFlyout containing the LineEdit. The search still filters
# across all four toolboxes at once; on a hit, the family holding the
# match opens and the relevant sub-family drawer opens. The user can
# click another family header to see other matches.
#
# PRESERVED FROM THE PREVIOUS IMPLEMENTATION:
#   * All data logic: TIERS, HULL/LOCO grouping, light-to-heavy sort,
#     search key derivation, _tier_for family->tier routing.
#   * The drawer metadata contract (drawer_category, content_container,
#     header_btn, drawer_open, family, tier) and _all_drawers - the test
#     suites walk that array, not the node hierarchy, so they keep working.
#   * Public API: sections_for(), reveal_part(), collapse_all_drawers(),
#     _on_search_changed(), _force_open_family(), _open_category(),
#     get_dock() (now returns null - see "WHAT DOES NOT COME BACK").
#
# WHAT DOES NOT COME BACK:
#   * The left UIDock. The four floating toolboxes replace it.
#   * The TabContainer. The four toolboxes ARE the family selector.
#   * The family-chip filter row. The four toolboxes replace it.
#   * get_dock() returns null. There is no UIDock to expose. Callers that
#     wanted a rect to highlight should point at the parts menu's open
#     family's body, not at a dock that no longer exists.
#   * The old one-at-a-time open_drawer_hulls/modules/locomotion strings
#     are kept as no-op compatibility vars; nothing in the UI reads them
#     anymore.

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UIAnim = preload("res://scripts/ui_anim.gd")
const ToolboxPlateScript = preload("res://scripts/ui_toolbox_plate.gd")
const StampedLabelScript = preload("res://scripts/ui_stamped_label.gd")
const UIFlyoutScript = preload("res://scripts/ui_flyout.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

# --- Grouping (unchanged from the previous build) ----------------------------
# Weight is the right sort key here rather than cost or name: it is the one
# stat every single part in the catalog has, it is monotonic with "how big a
# commitment is this", and on a game where payload capacity is the binding
# constraint it is the number a player is actually budgeting against while
# browsing. Alphabetical would scatter the light starter parts through the
# list; cost would put the crystal-heavy exotics next to the cheap junk.
const HULL_LIGHT_MAX := 200.0
const HULL_MEDIUM_MAX := 450.0
const HULL_GROUP_ORDER = ["Light Chassis", "Medium Chassis", "Heavy Chassis", "Static Foundations"]

# Locomotion: derived from the traits array each entry already declares, so a
# modded drive sorts itself. Order is checked top-down and first match wins,
# which is what makes the overlapping traits resolve - buoyant_envelope is both
# "airborne" and "buoyant" and belongs under Air, screw_drive is both
# "ground_contact" and "amphibious" and belongs under Ground.
const LOCO_GROUP_ORDER = ["Ground", "Hover", "Naval", "Air"]

# The four TOP-LEVEL TOOLBOXES, in left-to-right order along the bottom.
# The "weapons"/"support"/"locomotion" tier ids are the same ones the
# previous build used, so data logic and the tests that read it do not
# change - only the way those tier ids get rendered changes.
const TIERS = [
	{"id": "hulls", "label": "Hulls"},
	{"id": "weapons", "label": "Weapons"},
	{"id": "support", "label": "Support"},
	{"id": "locomotion", "label": "Drives"},
]

# Which module ROLES are weapons. Taken from the catalog's own wording rather
# than invented here: smoke and mines belong with the guns even at 0 dps.
const WEAPON_ROLES = [
	"Direct-Fire Guns", "Energy & Electromagnetic", "Indirect Fire",
	"Missiles", "Point Defense", "Deployables",
]

# Propulsion parts route to the Drives toolbox rather than Support - a player
# looking to make a design faster looks where the locomotion types already
# live, not in a generators drawer.
const DRIVE_ROLES = ["Propulsion"]

const CARD_MIN_WIDTH := 132
const CARD_HEIGHT := 46

# --- Bar dimensions ---------------------------------------------------------
# Wider than the Skirmish build queue's 264 because the design lab's part
# cards run two to a row in a grid at a 132px minimum, and the 264 left
# cards clipping in 4-toolbox mode. 4 * 288 = 1152, which fits a 1280
# viewport with breathing room.
const TOOLBOX_WIDTH := 288.0
const PLATE_PADDING := 10.0
const CONTENT_WIDTH := TOOLBOX_WIDTH - PLATE_PADDING * 2.0
# Same as production_hud.gd's HEADER_HEIGHT - the header needs room to
# read as a plate rather than a tab.
const HEADER_HEIGHT := 44.0
const HEADER_FONT_SIZE := 19
# How tall a family's open sub-family list is allowed to get before it
# scrolls rather than growing up off the top of the screen. 5 sub-families
# in weapons, 4 in hulls/support/drives - this is comfortably above all of
# them at their collapsed-drawer height.
const LIST_MAX_HEIGHT := 360.0
# Gap between adjacent toolboxes along the bar.
const BAR_GAP := 14.0
# How far above the screen bottom the bar's lowest edge sits, so the
# toolboxes do not sit ON the edge.
const BAR_BOTTOM_INSET := 8.0
# The search "toolbox" is a 5th element in the row, treated as a peer of
# the four family toolboxes - same plate, same StampedLabel, same height.
# It is narrower because the lettering ("FIND") is short; 72px gives the
# StampedLabel room to breathe at HEADER_FONT_SIZE without making the
# right end of the bar feel lopsided.
const SEARCH_WIDTH := 72.0

# --- State ------------------------------------------------------------------
var _filter: String = ""
# Which family's body is currently open. "" means none - the very first
# landing on the screen shows only the four headers, no body content.
var _open_family: String = ""

# tier_id -> {plate, slot, panel, header, body}.
# `plate` is the sibling ToolBoxPlate that draws behind the controls.
# `slot` is the VBox that parents the panel + header.
# `panel` is the open list (recess, hidden when closed).
# `header` is the closed-state trigger button (with StampedLabel on top).
# `body` is the panel's ScrollContainer body (where sub-family sections live).
# `is_open` mirrors `panel.visible`; kept separately so _layout_bar can
# read it without poking at a control's visibility from a layout pass.
var _family_widgets: Dictionary = {}

# The horizontal row of plates + slots along the bottom.
var _bar_row: Control

# Every section built, across all three families, so search can sweep them
# without re-walking the scene tree on each keystroke.
var _all_drawers: Array = []

# Magnifying glass + flyout for search.
var _search_btn: Button
var _search_flyout: Control
var _search_box: LineEdit

# Empty-state hint, shown when the search filters out every part.
var _empty_hint: Label

# Retained so the old API keeps working for any caller that still sets them;
# the new panel does not enforce single-open and the per-family accordion
# replaces these strings as the source of truth.
var open_drawer_hulls: String = ""
var open_drawer_modules: String = ""
var open_drawer_locomotion: String = ""


func _ready() -> void:
	# FULL_RECT, so the bar's hand-laid-out toolboxes can use the real viewport
	# size. The screen behind the 3D viewport is the one that matters here -
	# not the per-dock size the old build used.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The bar's children own their own clicks; this is a no-op surface above
	# the 3D viewport, and a STOP filter would eat clicks meant for the model.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_shell()

	var catalog = ModuleCatalog.get_catalog()
	var hull_groups: Dictionary = {}
	var module_groups: Dictionary = {}
	var loco_groups: Dictionary = {}

	for type_id in catalog.keys():
		var data = catalog[type_id]
		var category = data.get("category", "module")

		if category == "hull":
			_bucket(hull_groups, _hull_group(data), type_id, data)
		elif category == "locomotion":
			_bucket(loco_groups, _loco_group(data), type_id, data)
		else:
			_bucket(module_groups, ModuleCatalog.get_module_role(type_id, category), type_id, data)

	_populate(hull_groups, HULL_GROUP_ORDER, "hulls")
	_populate(module_groups, ModuleCatalog.MODULE_ROLE_ORDER, "modules")
	_populate(loco_groups, LOCO_GROUP_ORDER, "locomotion")

	# Fit the bar's first layout now that the size is real.
	_layout_bar()
	_apply_filters()


# --- Shell ------------------------------------------------------------------

func _build_shell() -> void:
	_bar_row = Control.new()
	_bar_row.name = "Toolboxes"
	_bar_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_row)

	# ALL PLATES FIRST, THEN ALL SLOTS. Godot picks siblings in REVERSE child
	# order, so an interleaved plate/slot/plate/slot arrangement puts one
	# toolbox's decorative plate ahead of the NEXT toolbox's controls in the
	# pick order - measured by production_hud.gd's own comment on this trap.
	for tier in TIERS:
		var plate: Control = ToolboxPlateScript.new()
		plate.name = tier["id"] + "Plate"
		_plates_set_defaults(plate)
		_bar_row.add_child(plate)
	# The search gets its own plate too, before any slot, for the same reason.
	var search_plate: Control = ToolboxPlateScript.new()
	search_plate.name = "SearchPlate"
	_plates_set_defaults(search_plate)
	_bar_row.add_child(search_plate)

	for tier in TIERS:
		_build_family_toolbox(tier["id"], tier["label"])

	# Layout the toolboxes in _ready() once the row has a size, and any time
	# the viewport resizes.
	_bar_row.resized.connect(_layout_bar)

	# Magnifying glass + search flyout.
	_build_search_widget()

	# The empty hint (shown when no parts match the search).
	_empty_hint = Label.new()
	_empty_hint.text = "No parts match."
	_empty_hint.theme_type_variation = "HintLabel"
	_empty_hint.visible = false
	# Anchored just above the bar; preset CENTER sizes around the
	# parent, so the position has to be set explicitly afterwards.
	_empty_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_empty_hint.size = Vector2(160.0, 24.0)
	add_child(_empty_hint)


# Stamps the chrome defaults onto a ToolboxPlate. The plate's own constructor
# sets sensible defaults from tokens, but the design lab wants a slightly
# different finish than the Skirmish build queue - same vocabulary, just a
# hair darker on the body so the busy part cards sit forward of it.
func _plates_set_defaults(plate: Control) -> void:
	plate.body_color = Tokens.BASE_700
	plate.lit_color = Tokens.BASE_500
	plate.shade_color = Tokens.BASE_900
	plate.edge_color = Tokens.BASE_500


func _build_family_toolbox(tier_id: String, label: String) -> void:
	var plate: Control = _bar_row.get_node(tier_id + "Plate")

	# The slot is the VBox that parents the panel (above) and header (below).
	# Its size is what the plate is sized to match - so the chamfered outline
	# frames both.
	var slot := VBoxContainer.new()
	slot.name = tier_id
	slot.add_theme_constant_override("separation", 0)
	slot.custom_minimum_size = Vector2(TOOLBOX_WIDTH, 0)
	# STOP, so the slot absorbs mouse-wheel events that the list's own
	# ScrollContainer declines (at the top or bottom of a scrollable range).
	# Without this, a wheel in a closed drawer still reaches the designer
	# camera and zooms the world out from under the player. This is the
	# exact problem production_hud.gd:189-214 documents, in the same words.
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and (
				event.button_index == MOUSE_BUTTON_WHEEL_UP
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			slot.accept_event())
	_bar_row.add_child(slot)

	# --- Panel: a recess inside the plate, hidden when the family is closed.
	# It comes FIRST in the slot's child order so it renders ABOVE the
	# header - the panel opens upward from the bottom of the screen.
	var panel := PanelContainer.new()
	panel.visible = false
	# A recess, not another raised surface. The list opens INTO the plate,
	# so it is darker than the plate body with a hairline rim rather than
	# a bevel - the same well production_hud.gd:223-229 uses.
	var well := StyleBoxFlat.new()
	well.bg_color = Tokens.BASE_900
	well.border_color = Tokens.BASE_500
	well.set_border_width_all(Tokens.BORDER_HAIRLINE)
	well.set_content_margin_all(Tokens.SPACE_XS)
	panel.add_theme_stylebox_override("panel", well)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.SPACE_XS)
	scroll.add_child(body)
	slot.add_child(panel)

	# Cap the panel's height at LIST_MAX_HEIGHT, but let it shrink when its
	# content is shorter. minf() is a floor for the panel, not a clamp on
	# the scroll content; the ScrollContainer's auto-resize still works.
	scroll.custom_minimum_size = Vector2(0, 0)

	# --- Header: the closed-state trigger button, with the family label
	# stamped on top of it. Identical pattern to production_hud.gd:239-260.
	var header := Button.new()
	header.alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.toggle_mode = true
	header.focus_mode = Control.FOCUS_NONE
	header.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	_engrave(header)
	slot.add_child(header)

	var stamp: Control = StampedLabelScript.new()
	stamp.text = label.to_upper()
	stamp.font_size = HEADER_FONT_SIZE
	stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	header.add_child(stamp)
	UIFeedbackScript.wire(header, "select")

	_family_widgets[tier_id] = {
		"plate": plate,
		"slot": slot,
		"panel": panel,
		"header": header,
		"body": body,
		"is_open": false,
	}

	# The cross-toolbox accordion: opening one family closes the others.
	# Toggling the currently-open family OFF closes everything - which
	# reads as "click the active header to dismiss" rather than "I have
	# to find a tiny X to close this", matching the Skirmish build queue.
	header.toggled.connect(func(pressed: bool):
		if pressed:
			_open_family_cross(tier_id)
		elif _open_family == tier_id:
			_close_family(tier_id))


# Strips a header Button back to a bare hit target, exactly as
# production_hud.gd:286-298 does. The plate is the surface, the
# StampedLabel is the lettering, and any theme overrides on the button
# would just be a second copy of both.
func _engrave(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var empty := StyleBoxEmpty.new()
		button.add_theme_stylebox_override(state, empty)


# --- Layout -----------------------------------------------------------------

# Hand-lays the 4 family toolboxes + the search toolbox along the bottom of
# the screen, and sizes each plate to its slot.
#
# Why hand-laid: production_hud.gd:122-125 records the same decision. A
# Container owns its children's positions, and even though we are NOT
# animating vertical slide-off here, every layout pass would have to fight
# a Container for the right thing - and any future change that wanted to
# e.g. jitter the active family would have to swap out the container.
# Two free passes beats one fix-later.
#
# The search is the 5th element in the row, with a normal BAR_GAP between
# it and the Drives toolbox to its left. Same height as the closed family
# toolboxes (HEADER_HEIGHT) so the row's lowest edge reads as one line.
func _layout_bar() -> void:
	if _bar_row == null or _family_widgets.is_empty():
		return
	var bar_w: float = size.x
	var n: int = TIERS.size()
	var total_w: float = TOOLBOX_WIDTH * float(n) + BAR_GAP * float(n - 1) + SEARCH_WIDTH + BAR_GAP
	var left: float = maxf(Tokens.SPACE_LG, (bar_w - total_w) * 0.5)
	var bottom_y: float = size.y - BAR_BOTTOM_INSET

	var x: float = left
	for tier in TIERS:
		var w: Dictionary = _family_widgets[tier["id"]]
		var is_open: bool = w["is_open"]
		var h: float = HEADER_HEIGHT + (LIST_MAX_HEIGHT + Tokens.SPACE_XS if is_open else 0.0)
		w["plate"].position = Vector2(x, bottom_y - h)
		w["plate"].size = Vector2(TOOLBOX_WIDTH, h)
		w["slot"].position = Vector2(x, bottom_y - h)
		w["slot"].size = Vector2(TOOLBOX_WIDTH, h)
		# Cap the open panel to LIST_MAX_HEIGHT; the scroll container does
		# the right thing on its own for shorter content.
		w["panel"].custom_minimum_size = Vector2(0, LIST_MAX_HEIGHT if is_open else 0)
		x += TOOLBOX_WIDTH + BAR_GAP

	# Search toolbox: 5th element, treated as a peer of the four above.
	# Same plate chrome, same height, same gap to its left. The body is
	# always invisible (the search opens a flyout instead), so the height
	# is just HEADER_HEIGHT.
	if _search_plate and is_instance_valid(_search_plate):
		var search_x: float = x + BAR_GAP
		_search_plate.position = Vector2(search_x, bottom_y - HEADER_HEIGHT)
		_search_plate.size = Vector2(SEARCH_WIDTH, HEADER_HEIGHT)
		var search_slot: Control = _bar_row.get_node_or_null("search")
		if search_slot:
			search_slot.position = Vector2(search_x, bottom_y - HEADER_HEIGHT)
			search_slot.size = Vector2(SEARCH_WIDTH, HEADER_HEIGHT)

	# Re-anchor the empty hint so it floats above the bar's centre, just
	# below where the search flyout opens. set_anchors_preset(0) leaves
	# offsets at their defaults, so the explicit position/size stick.
	if _empty_hint:
		_empty_hint.position = Vector2(
			(bar_w - _empty_hint.size.x) * 0.5,
			bottom_y - HEADER_HEIGHT - LIST_MAX_HEIGHT - 32.0)


# --- Cross-toolbox accordion ------------------------------------------------

# Opens one family and closes the rest. The first call lands the first
# family (we never open one on its own without the user asking), so the
# "open on _ready" path is just an explicit _open_family_cross("hulls")
# at the end of _ready if we ever want a default-open state.
func _open_family_cross(tier_id: String) -> void:
	if not _family_widgets.has(tier_id):
		return
	for other_id in _family_widgets.keys():
		var w: Dictionary = _family_widgets[other_id]
		var should_be_open: bool = other_id == tier_id
		if w["is_open"] == should_be_open:
			continue
		w["is_open"] = should_be_open
		w["panel"].visible = should_be_open
		# set_pressed_no_signal, or closing a sibling re-enters this function
		# through its own toggled handler and the loop fights itself. Same
		# trap the existing UIToolbox.open() avoids.
		w["header"].set_pressed_no_signal(should_be_open)
		if should_be_open:
			UIAnim.stagger_in(w["body"], Vector2(0, -8))
	_open_family = tier_id
	_layout_bar()


func _close_family(tier_id: String) -> void:
	if not _family_widgets.has(tier_id):
		return
	var w: Dictionary = _family_widgets[tier_id]
	w["is_open"] = false
	w["panel"].visible = false
	w["header"].set_pressed_no_signal(false)
	_open_family = ""
	_layout_bar()


# --- Search widget ----------------------------------------------------------
#
# A 5th element in the bar, treated as a peer of the four family toolboxes:
# same chamfered ToolboxPlate behind, same StampedLabel lettering on top,
# same HEADER_HEIGHT hit target. The only difference is the body - the
# search opens a UIFlyout containing a LineEdit, rather than an inline
# sub-family list. The plate+stamp treatment is what makes it read as a
# member of the row rather than as an appended "search" button.
#
# "FIND" instead of "SEARCH" because the box is narrow and the StampedLabel
# centres its text. 4 letters at HEADER_FONT_SIZE (19) fit comfortably in
# 72px with the chamfered plate's own padding, whereas "SEARCH" (6) starts
# to crowd the chamfered corners.

var _search_plate: Control

func _build_search_widget() -> void:
	_search_plate = _bar_row.get_node("SearchPlate")

	# The slot is a VBox holding just the header button (no panel - the
	# search opens a flyout, not an inline list). Same shape as a closed
	# family toolbox.
	var slot := VBoxContainer.new()
	slot.name = "search"
	slot.add_theme_constant_override("separation", 0)
	slot.custom_minimum_size = Vector2(SEARCH_WIDTH, 0)
	# STOP + gui_input, same wheel-stealing pattern as the family slots -
	# without it, a wheel over the search bar would reach the camera and
	# zoom the model. The family slots have this for the same reason.
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and (
				event.button_index == MOUSE_BUTTON_WHEEL_UP
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			slot.accept_event())
	_bar_row.add_child(slot)

	# The header button - engraved, same as the family headers.
	_search_btn = Button.new()
	_search_btn.name = "SearchButton"
	_search_btn.toggle_mode = true
	_search_btn.focus_mode = Control.FOCUS_NONE
	_search_btn.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	_engrave(_search_btn)
	slot.add_child(_search_btn)

	# StampedLabel lettering - identical to production_hud.gd:250-254 and
	# to the four family toolboxes above. Same "FIND" rendered in the same
	# enamel-and-wall style, so the row reads as one row of five.
	var stamp: Control = StampedLabelScript.new()
	stamp.text = "FIND"
	stamp.font_size = HEADER_FONT_SIZE
	stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	_search_btn.add_child(stamp)

	UIFeedbackScript.wire(_search_btn, "select")

	# The flyout. Anchored to the search button, opens ABOVE so it does not
	# fall off the bottom of the screen. UIFlyout auto-flips when it would
	# leave the viewport (ui_flyout.gd:133-141), so this is the only
	# direction we have to name.
	_search_flyout = UIFlyoutScript.create(self, "Search")

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "Search parts"
	_search_box.clear_button_enabled = true
	_search_box.custom_minimum_size = Vector2(280, Tokens.HIT_TARGET_MIN)
	_search_box.text_changed.connect(_on_search_changed)
	_search_flyout.body().add_child(_search_box)

	_search_btn.toggled.connect(func(pressed: bool):
		if pressed:
			_search_flyout.open_from(_search_btn, UIFlyoutScript.Align.ABOVE)
			_search_box.grab_focus()
		else:
			_search_flyout.close())

	# Mirror close-on-outside-click back to the button so the toggle state
	# stays in step with the flyout's actual visibility.
	_search_flyout.closed.connect(func():
		_search_btn.set_pressed_no_signal(false))


# --- Grouping helpers (unchanged) -------------------------------------------

func _bucket(groups: Dictionary, group: String, type_id: String, data: Dictionary) -> void:
	if not groups.has(group):
		groups[group] = []
	groups[group].append({"id": type_id, "data": data, "weight": float(data.get("weight", 0.0))})


func _hull_group(data: Dictionary) -> String:
	if data.get("is_foundation", false):
		return "Static Foundations"
	var w = float(data.get("weight", 0.0))
	if w < HULL_LIGHT_MAX:
		return "Light Chassis"
	if w < HULL_MEDIUM_MAX:
		return "Medium Chassis"
	return "Heavy Chassis"


func _loco_group(data: Dictionary) -> String:
	var traits: Array = data.get("traits", [])
	# First match wins - see LOCO_GROUP_ORDER's comment on the overlaps.
	if "airborne" in traits:
		return "Air"
	if "naval" in traits or ("buoyant" in traits and "ground_contact" not in traits):
		return "Naval"
	if "ground_contact" in traits:
		return "Ground"
	if "hovering" in traits:
		return "Hover"
	return "Ground"


# --- Construction -----------------------------------------------------------

func _populate(groups: Dictionary, order: Array, family: String) -> void:
	# Any group the catalog produced that the order array doesn't name still
	# gets shown, appended after the known ones. Same reasoning as
	# get_module_role()'s fallback: an unlisted group must be visible, not
	# silently dropped.
	var seen := []
	var ordered := []
	for g in order:
		if groups.has(g):
			ordered.append(g)
			seen.append(g)
	for g in groups.keys():
		if g not in seen:
			ordered.append(g)

	for group in ordered:
		var entries: Array = groups[group]
		# LIGHT TO HEAVY. Ties broken by name so the order is stable across
		# runs - Dictionary.keys() order is insertion order, not sorted, and an
		# unstable sidebar is genuinely disorienting to browse.
		entries.sort_custom(func(a, b):
			if is_equal_approx(a.weight, b.weight):
				return String(a.data.get("name", a.id)) < String(b.data.get("name", b.id))
			return a.weight < b.weight)

		var cards := []
		for entry in entries:
			cards.append(_build_part_card(entry.id, entry.data))
		var tier_id := _tier_for(family, group)
		var section = _make_section(group, cards, family)
		# The toolbox this group is filed under, kept separate from the `family`
		# meta above - see the TIERS comment for why the two axes differ.
		section.set_meta("tier", tier_id)
		# Into the family's body rather than straight into _bar_row, which
		# is what makes the hierarchy structural. _all_drawers still gets every
		# section, so sections_for() and the test suites are unaffected by the
		# re-parenting.
		_family_tier_body(tier_id).add_child(section)
		_all_drawers.append(section)


# A part card. Compact, gridded, and carrying its weight inline.
#
# Styling comes from the THEME (bakelite plates, from tools/build_ui_theme.gd),
# not from a local StyleBoxFlat. The previous version hand-rolled four
# styleboxes per card here, which duplicated what the theme already builds for
# Button and - because local overrides beat the theme - actively prevented the
# design system from reaching the single most numerous control in the game.
# The only per-part colour left is the catalog accent, as a thin left stripe.
func _build_part_card(type_id: String, data: Dictionary) -> Button:
	var btn = Button.new()
	btn.set_script(preload("res://scripts/part_button.gd"))
	btn.module_type_id = type_id
	btn.text = data["name"]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", Tokens.FONT_SMALL)

	# The catalog accent as a painted stripe on the switch body. A StyleBox
	# override would lose the plate texture, so the stripe is a child ColorRect
	# drawn over the button's left edge instead.
	var stripe = ColorRect.new()
	stripe.color = data["color"]
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_right = 4.0
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(stripe)

	var weight_label = Label.new()
	weight_label.text = "%.0f kg" % float(data.get("weight", 0.0))
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	weight_label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	weight_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	weight_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	weight_label.offset_right = -6
	weight_label.offset_bottom = -3
	weight_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(weight_label)

	if data.get("category", "") == "hull":
		var size = data.get("size", Vector3.ZERO)
		var domain = "Static Building" if data.get("is_foundation", false) else "Vehicle"
		# Name first - see _stat_tooltip()'s comment for why line 0 is
		# load-bearing.
		btn.tooltip_text = "%s\n%s hull\nHP: %.0f | Weight: %.0f\nCost: %d Metal, %d Crystal\nSize: %.1f x %.1f x %.1f" % [
			data["name"], domain, data.get("hp", 0.0), data.get("weight", 0.0),
			data.get("metal", 0), data.get("crystal", 0),
			size.x, size.y, size.z]
	else:
		btn.tooltip_text = _stat_tooltip(data)

	# Cached for search - matching on the visible name plus the id means typing
	# "mk19" or "Grenade" both work.
	btn.set_meta("search_key", ("%s %s" % [data.get("name", ""), type_id]).to_lower())
	return btn


# A titled group of cards. Independently collapsible - opening one no longer
# closes another, because comparing two groups is a normal thing to want.
func _make_section(category: String, cards: Array, family: String) -> Control:
	var section = VBoxContainer.new()
	section.name = "Drawer_%s" % category.replace(" ", "_").replace("&", "and")
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header_btn = Button.new()
	header_btn.theme_type_variation = "ListButton"
	header_btn.custom_minimum_size = Vector2(0, 28)
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_btn.text = category
	header_btn.focus_mode = Control.FOCUS_NONE
	header_btn.toggle_mode = true
	# Closed at rest now that categories sit inside a family tier - opening a
	# family should reveal its category list, not its every part at once.
	header_btn.button_pressed = false

	# Count badge. With sections collapsed the player otherwise has no idea
	# whether a group holds two parts or twelve, which makes deciding where to
	# look a coin flip.
	var count_label = Label.new()
	count_label.text = str(cards.size())
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	count_label.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	count_label.offset_right = -10
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_btn.add_child(count_label)

	section.add_child(header_btn)

	# The cards live in a GridContainer so a group reads as a block to scan
	# rather than as a column to walk. Two columns at the toolbox's default
	# width; the grid reflows if the toolbox is ever wider.
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	for c in cards:
		grid.add_child(c)
	grid.visible = false
	section.add_child(grid)

	# METADATA CONTRACT. run_tests.gd reads these to check that roles, weight
	# classes and locomotion traits put every part in the right group; keeping
	# the names stable is what let the presentation be rebuilt without
	# rewriting those suites. "content_container" is the card list;
	# "drawer_category" and "drawer_tab" identify the group.
	section.set_meta("drawer_category", category)
	section.set_meta("drawer_tab", family)
	section.set_meta("drawer_open", false)
	section.set_meta("header_btn", header_btn)
	section.set_meta("content_container", grid)
	section.set_meta("family", family)

	header_btn.toggled.connect(func(pressed: bool):
		if pressed:
			# Accordion within the family, so a three-deep column stays short.
			_open_category(section)
			UIAnim.stagger_in(grid)
		else:
			grid.visible = false
			section.set_meta("drawer_open", false))
	UIFeedbackScript.wire(header_btn, "select")

	return section


# --- Tier routing -----------------------------------------------------------

# Presentation tier for a (category, group) pair. Only "modules" splits, into
# Weapons, Propulsion (routed to the Drives toolbox, alongside the locomotion
# types these parts modify - see DRIVE_ROLES) and Support - see the TIERS and
# WEAPON_ROLES comments for why that is a presentation decision rather than a
# reclassification.
func _tier_for(family: String, group: String) -> String:
	if family != "modules":
		return family
	if group in DRIVE_ROLES:
		return "locomotion"
	return "weapons" if group in WEAPON_ROLES else "support"


# Returns the VBoxContainer (under the panel's ScrollContainer) that
# sections of this family are added to. Lazily creates the family's chrome
# the first time a section asks - in practice all four families are
# seeded in _build_shell, so this is just a defensive null check.
func _family_tier_body(tier_id: String) -> VBoxContainer:
	if not _family_widgets.has(tier_id):
		return null
	return _family_widgets[tier_id]["body"]


# Opens a family tier in the cross-toolbox sense, used by search and by
# reveal_part(). With the new layout, this is just _open_family_cross
# under a more domain-specific name.
func _force_open_family(tier_id: String) -> void:
	_open_family_cross(tier_id)


# Opens one category drawer and closes its siblings within the same toolbox.
func _open_category(section: Control) -> void:
	var tier_id := str(section.get_meta("tier", ""))
	for other in _all_drawers:
		if not is_instance_valid(other):
			continue
		if str(other.get_meta("tier", "")) != tier_id:
			continue
		var is_target: bool = other == section
		var grid: Control = other.get_meta("content_container")
		var header: Button = other.get_meta("header_btn")
		grid.visible = is_target
		header.set_pressed_no_signal(is_target)
		other.set_meta("drawer_open", is_target)


# --- Filtering --------------------------------------------------------------

func _on_search_changed(new_text: String) -> void:
	_filter = new_text.strip_edges().to_lower()
	_apply_filters()


# One pass that applies the search text.
#
# The previous build also ran a family filter here; with the four toolboxes
# that axis is structural rather than a control, so there is nothing to
# apply at the search level. The filter collapses a part's visibility;
# whether its section's grid is open or closed is the section's own
# responsibility, and the search's job is to find the section.
func _apply_filters() -> void:
	var any_visible := false

	for section in _all_drawers:
		if not is_instance_valid(section):
			continue

		var grid: Node = section.get_meta("content_container")
		var matches := 0
		for card in grid.get_children():
			var hit := _filter == "" or String(card.get_meta("search_key", "")).contains(_filter)
			card.visible = hit
			if hit:
				matches += 1

		# A section with nothing in it is hidden entirely rather than left as
		# an empty header - a column of dead headers reads as "the search
		# broke" rather than "no hits in this group".
		section.visible = matches > 0
		if matches > 0:
			any_visible = true
			# While filtering, force the surviving sections open. Making the
			# player click a header to see the thing they just searched for
			# would defeat the search.
			if _filter != "":
				grid.visible = true
				section.get_meta("header_btn").set_pressed_no_signal(true)
				section.set_meta("drawer_open", true)
				# The family tier above it has to open too, or the match is
				# revealed inside a closed family and stays invisible. The
				# cross-toolbox accordion means the matching family closes
				# the others, which is the right read: "the search found
				# something, here it is, in this family".
				_force_open_family(str(section.get_meta("tier", "")))

	if _empty_hint:
		_empty_hint.visible = not any_visible and _filter != ""


# --- Introspection ----------------------------------------------------------

# Every group section belonging to one family ("hulls" | "modules" |
# "locomotion").
#
# This exists so the grouping suites in run_tests.gd have a stable way in.
# They used to reach through a hardcoded node path
# ("PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer"), which
# coupled tests about CATALOG DATA - do modules group by their own role, do
# hulls group by their own weight class - to the widget tree that happened to
# display it. Rebuilding the panel then broke tests that had no opinion about
# panels. Asking the panel a question instead keeps those suites testing the
# thing they are actually about.
func sections_for(family: String) -> Array:
	var out: Array = []
	for section in _all_drawers:
		if is_instance_valid(section) and section.get_meta("family", "") == family:
			out.append(section)
	return out


# The dock this panel lives in, for callers that need to expand it.
#
# RETURNS NULL. The bottom toolboxes are not a UIDock; they have no
# collapse-to-rail state, no auto-hide, and no per-instance expansion. Any
# caller that used to expand the dock to make a part visible should call
# reveal_part() instead, which handles the cross-toolbox accordion for them.
func get_dock() -> Control:
	return null


# The screen rect occupied by the bar - everything the player can see
# at the bottom of the screen (the 4 toolboxes + the magnifying glass).
# Used by the tutorial to spotlight the bar; not useful for clicks,
# since the toolboxes have their own per-rect hit targets.
#
# Returns an empty Rect2 before _layout_bar has had a chance to run, which
# is the same "target not resolvable" signal the tutorial treats as "draw
# no hole at all" (tutorial_overlay.gd:33-35).
func get_bar_focus_rect() -> Rect2:
	if _family_widgets.is_empty():
		return Rect2()
	var min_pt: Vector2 = Vector2(INF, INF)
	var max_pt: Vector2 = Vector2(-INF, -INF)
	for tier_id in _family_widgets.keys():
		var w: Dictionary = _family_widgets[tier_id]
		if not is_instance_valid(w["plate"]):
			continue
		var r: Rect2 = w["plate"].get_global_rect()
		min_pt = Vector2(minf(min_pt.x, r.position.x), minf(min_pt.y, r.position.y))
		max_pt = Vector2(maxf(max_pt.x, r.end.x), maxf(max_pt.y, r.end.y))
	if _search_btn and is_instance_valid(_search_btn):
		var sr: Rect2 = _search_btn.get_global_rect()
		min_pt = Vector2(minf(min_pt.x, sr.position.x), minf(min_pt.y, sr.position.y))
		max_pt = Vector2(maxf(max_pt.x, sr.end.x), maxf(max_pt.y, sr.end.y))
	if min_pt.x == INF:
		return Rect2()
	return Rect2(min_pt, max_pt - min_pt)


# Opens the catalogue down to one specific part and hands back its card.
#
# Written for the tutorial, which has to point at "the Medium Hull" when the
# family containing it is closed and the sub-family drawer is closed. Returns
# null for an unknown type_id rather than asserting, so a step naming a part
# that has since been retired from the catalog degrades to "no spotlight"
# instead of taking the screen down.
#
# Built entirely on the existing drawer metadata contract (see _make_section) so
# it cannot drift from how the panel actually works.
func reveal_part(type_id: String) -> Button:
	for section in _all_drawers:
		if not is_instance_valid(section):
			continue
		var grid: Control = section.get_meta("content_container")
		for card in grid.get_children():
			if not (card is Button) or card.module_type_id != type_id:
				continue
			# Open the family first - the cross-toolbox accordion means
			# the other three close, which is fine because the tutorial
			# only ever needs one family visible at a time.
			_force_open_family(str(section.get_meta("tier", "")))
			# Through the header's toggle rather than _open_category() directly,
			# so the drawer's own accordion and its pressed state stay in step.
			var header: Button = section.get_meta("header_btn")
			if not header.button_pressed:
				header.button_pressed = true
			return card
	return null


# --- Compatibility ----------------------------------------------------------

func collapse_all_drawers() -> void:
	for section in _all_drawers:
		if is_instance_valid(section):
			section.get_meta("header_btn").button_pressed = false
			section.get_meta("content_container").visible = false
			section.set_meta("drawer_open", false)
	open_drawer_hulls = ""
	open_drawer_modules = ""
	open_drawer_locomotion = ""


# NOTE: line 0 is the part NAME, and that is load-bearing - part_button.gd's
# _make_custom_tooltip() renders the first line as the card's bold gold title
# row and every line after it as a smaller stat row.
func _stat_tooltip(data: Dictionary) -> String:
	var lines = [data.get("name", "Unknown Part")]
	lines.append("HP: %.0f | Weight: %.0f" % [data.get("hp", 0.0), data.get("weight", 0.0)])
	lines.append("Cost: %d Metal, %d Crystal" % [data.get("metal", 0), data.get("crystal", 0)])
	var dps = data.get("dps", 0.0)
	if dps > 0.0:
		lines.append("DPS: %.0f" % dps)
	var heal_rate = data.get("heal_rate", 0.0)
	if heal_rate > 0.0:
		lines.append("Heal Rate: %.1f/s" % heal_rate)
	return "\n".join(lines)
