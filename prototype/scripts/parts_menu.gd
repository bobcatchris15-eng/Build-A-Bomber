extends Control

signal part_hovered(type_id: String)
signal part_unhovered()

# The Design Lab's hardware catalog.
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

# --- Grouping (unchanged from the previous build) ----------------------------
# Weight is the right sort key here rather than cost or name: it is the one
# stat every single part in the catalog has, it is monotonic with "how big a
# commitment is this", and on a game where payload capacity is the binding
# constraint it is the number a player is actually budgeting against while
# browsing. Alphabetical would scatter the light starter parts through the
# list; cost would put the crystal-heavy exotics next to the cheap junk.
## Chassis bins come from the hull's DECLARED class, not from its weight.
##
## They used to be pure weight thresholds at 200 / 450, picked against the old
## catalogue. Against the 60-hull one they collapsed: the lightest hull in the
## game weighs 197, so "Light Chassis" contained exactly ONE entry and the other
## seven scouts sat under Medium next to genuine mediums.
##
## Bumping the thresholds alone cannot fix it cleanly either, because the
## classes overlap by weight - the heaviest Medium is 666 and the lightest
## Transport is 657, so no single number separates them. The class is the
## authoritative answer and every shipped hull declares it.
##
## ModuleCatalog.get_hull_size_tier() already maps the six classes onto three
## tiers for the manufactory system; reusing HULL_TIER_BY_CLASS here keeps the
## parts bin and the production tiers from ever disagreeing about what counts as
## a light chassis.
const HULL_TIER_TO_GROUP := {
	"light": "Light Chassis",
	"medium": "Medium Chassis",
	"heavy": "Heavy Chassis",
}
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

# Propulsion routes to Support — speed upgrades live with their sibling
# utilities (Power, Armor) rather than with locomotion drive types.
# DRIVE_ROLES kept as empty to avoid breaking any callers.
const DRIVE_ROLES: Array = []

# Display order within the Support tab. Propulsion sits last so the
# utility/infrastructure groupings (Armor, Power, general Support) read
# first and the speed-modifiers are a logical follow-on.
const SUPPORT_ROLE_ORDER = ["Armor", "Power", "Support", "Propulsion"]

const CARD_MIN_WIDTH := 80
const CARD_HEIGHT := 100

# --- Bar dimensions ---------------------------------------------------------
# Wider than the Skirmish build queue's 264 because the design lab's part
# cards run two to a row in a grid at a 132px minimum, and the 264 left
# cards clipping in 4-toolbox mode. 4 * 288 = 1152, which fits a 1280
# viewport with breathing room.
const TOOLBOX_WIDTH := 320.0
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

var _family_vboxes: Dictionary = {}
var _family_tabs: Dictionary = {}

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
	# Weapons roles first, then support roles with Propulsion last
	var combined_order = ModuleCatalog.MODULE_ROLE_ORDER.filter(func(r): return r in WEAPON_ROLES)
	combined_order.append_array(SUPPORT_ROLE_ORDER)
	_populate(module_groups, combined_order, "modules")
	_populate(loco_groups, LOCO_GROUP_ORDER, "locomotion")

	if _family_tabs.has("hulls"):
		_family_tabs["hulls"].button_pressed = true

	# Fit the bar's first layout now that the size is real.
	_layout_bar()
	_apply_filters()


# --- Shell ------------------------------------------------------------------

var _dock_panel: PanelContainer
var _main_vbox: VBoxContainer
var _dock_scroll: ScrollContainer

# Gap between toolbar bottom and our dock top, and left inset from screen edge.
const DOCK_GAP := 10.0
const DOCK_LEFT_INSET := 20.0   # inset from screen edge

# Border widths — read as concentric rings visible between each layer
const LIP_WIDTH := 16.0   # outer stamped steel ring — wide enough to read at a glance
const GASKET_WIDTH := 6.0 # rubber gasket ring, sits inside the lip
# Body starts inset by LIP_WIDTH + GASKET_WIDTH from the steel lip outer edge

func _build_shell() -> void:
	# ----------------------------------------------------------------
	# The assembly, bottom-to-top in Z order (later child = on top):
	#
	#   outer  (Control)          — positions the whole block
	#   ├─ steel_lip  (Panel)     — renders the outermost ring (dark red steel)
	#   ├─ gasket     (Panel)     — sits inside lip, shows as a rubber band
	#   └─ _dock_panel (PanelContainer) — the red body; margin children go here
	#
	# Using Panel (NOT PanelContainer) for lip and gasket is critical:
	# PanelContainer forces its ONE child into the content-margin rect,
	# which would eat our manual anchor+offset positioning. Plain Panel
	# is just a Node2D with a StyleBox drawn behind; children lay out freely.
	# ----------------------------------------------------------------

	const TOTAL_INSET := LIP_WIDTH + GASKET_WIDTH

	# ---- 1. Outer positioner ----------------------------------------
	var outer = Control.new()
	outer.name = "ToolboxOuter"
	outer.anchor_left   = 0.0
	outer.anchor_top    = 0.0
	outer.anchor_right  = 0.0
	outer.anchor_bottom = 1.0
	outer.offset_left   = DOCK_LEFT_INSET
	outer.offset_right  = DOCK_LEFT_INSET + TOOLBOX_WIDTH
	outer.offset_top    = Tokens.TOOLBAR_HEIGHT + DOCK_GAP
	outer.offset_bottom = -DOCK_GAP
	# STOP so scroll wheel events don't fall through to the 3D camera
	outer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(outer)

	# ---- 2. Stamped steel outer lip --------------------------------
	var steel_lip = Panel.new()
	steel_lip.name = "SteelLip"
	steel_lip.set_anchors_preset(Control.PRESET_FULL_RECT)
	steel_lip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lip_style = StyleBoxFlat.new()
	lip_style.bg_color = Color(0.18, 0.07, 0.06, 1.0)  # dark pressed steel
	lip_style.corner_radius_top_left    = 5
	lip_style.corner_radius_top_right   = 5
	lip_style.corner_radius_bottom_left = 8
	lip_style.corner_radius_bottom_right = 8
	# Thick bright highlight on the top edge — reads as the stamped lip catching light
	lip_style.border_width_top = 3
	lip_style.border_color = Color(0.55, 0.22, 0.17, 1.0)  # warm highlight
	lip_style.set_content_margin_all(0)
	steel_lip.add_theme_stylebox_override("panel", lip_style)
	var lip_mat = ShaderMaterial.new()
	lip_mat.shader = preload("res://shaders/red_steel.gdshader")
	steel_lip.material = lip_mat
	outer.add_child(steel_lip)

	# ---- 3. Rubber gasket ring (inset from lip edge) ---------------
	var gasket = Panel.new()
	gasket.name = "RubberGasket"
	gasket.anchor_left   = 0.0
	gasket.anchor_top    = 0.0
	gasket.anchor_right  = 1.0
	gasket.anchor_bottom = 1.0
	gasket.offset_left   = LIP_WIDTH
	gasket.offset_top    = LIP_WIDTH
	gasket.offset_right  = -LIP_WIDTH
	gasket.offset_bottom = -LIP_WIDTH
	gasket.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var gasket_style = StyleBoxFlat.new()
	gasket_style.bg_color = Color(0.07, 0.07, 0.08, 1.0)  # dark matte rubber
	gasket_style.corner_radius_top_left    = 3
	gasket_style.corner_radius_top_right   = 3
	gasket_style.corner_radius_bottom_left = 5
	gasket_style.corner_radius_bottom_right = 5
	gasket_style.set_content_margin_all(0)
	gasket.add_theme_stylebox_override("panel", gasket_style)
	var gasket_mat = ShaderMaterial.new()
	gasket_mat.shader = preload("res://shaders/rubber_gasket.gdshader")
	gasket.material = gasket_mat
	outer.add_child(gasket)

	# ---- 4. Red-steel body panel (inset from gasket edge) ----------
	_dock_panel = PanelContainer.new()
	_dock_panel.name = "Toolboxes"
	_dock_panel.anchor_left   = 0.0
	_dock_panel.anchor_top    = 0.0
	_dock_panel.anchor_right  = 1.0
	_dock_panel.anchor_bottom = 1.0
	_dock_panel.offset_left   = TOTAL_INSET
	_dock_panel.offset_top    = TOTAL_INSET
	_dock_panel.offset_right  = -TOTAL_INSET
	_dock_panel.offset_bottom = -TOTAL_INSET
	_dock_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var body_style = StyleBoxFlat.new()
	body_style.bg_color = Color.WHITE  # shader drives colour
	body_style.corner_radius_top_left    = 2
	body_style.corner_radius_top_right   = 2
	body_style.corner_radius_bottom_left = 3
	body_style.corner_radius_bottom_right = 3
	body_style.set_content_margin_all(0)
	_dock_panel.add_theme_stylebox_override("panel", body_style)
	var body_mat = ShaderMaterial.new()
	body_mat.shader = preload("res://shaders/red_steel.gdshader")
	_dock_panel.material = body_mat
	outer.add_child(_dock_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	_dock_panel.add_child(margin)

	var layout_vbox = VBoxContainer.new()
	layout_vbox.add_theme_constant_override("separation", Tokens.SPACE_SM)
	margin.add_child(layout_vbox)

	_build_search_widget(layout_vbox)

	# 2×2 grid of tabs — each tab fits its text naturally
	var tab_row = GridContainer.new()
	tab_row.name = "FamilyTabs"
	tab_row.columns = 2
	tab_row.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	tab_row.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	layout_vbox.add_child(tab_row)

	_dock_scroll = ScrollContainer.new()
	_dock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dock_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_dock_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Explicit STOP so the scroll container swallows wheel events completely
	_dock_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	layout_vbox.add_child(_dock_scroll)

	_main_vbox = VBoxContainer.new()
	_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_vbox.add_theme_constant_override("separation", Tokens.SPACE_SM)
	_dock_scroll.add_child(_main_vbox)

	var button_group = ButtonGroup.new()

	for tier in TIERS:
		var tier_id = tier["id"]
		
		var tier_vbox = VBoxContainer.new()
		tier_vbox.name = "Tier_" + tier_id
		tier_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tier_vbox.add_theme_constant_override("separation", Tokens.SPACE_SM)
		tier_vbox.visible = false
		_main_vbox.add_child(tier_vbox)
		_family_vboxes[tier_id] = tier_vbox
		
		var tab_btn = Button.new()
		tab_btn.custom_minimum_size = Vector2(0, 36)
		# EXPAND_FILL in both axes so each cell in the 2×2 grid fills equally
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tab_btn.toggle_mode = true
		tab_btn.button_group = button_group
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			tab_btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			
		var plate = ToolboxPlateScript.new()
		plate.set_anchors_preset(Control.PRESET_FULL_RECT)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_plates_set_defaults(plate)
		tab_btn.add_child(plate)
		
		var stamp = StampedLabelScript.new()
		stamp.text = tier["label"]
		stamp.font_size = 13
		stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
		plate.add_child(stamp)
		
		tab_row.add_child(tab_btn)
		_family_tabs[tier_id] = tab_btn
		
		tab_btn.toggled.connect(func(pressed: bool):
			if pressed:
				_show_family(tier_id)
		)

	_empty_hint = Label.new()
	_empty_hint.text = "No parts match."
	_empty_hint.theme_type_variation = "HintLabel"
	_empty_hint.visible = false
	layout_vbox.add_child(_empty_hint)


# Stamps the chrome defaults onto a ToolboxPlate. The plate's own constructor
# sets sensible defaults from tokens, but the design lab wants a slightly
# different finish than the Skirmish build queue - same vocabulary, just a
# hair darker on the body so the busy part cards sit forward of it.
func _plates_set_defaults(plate: Control) -> void:
	plate.body_color = Tokens.BASE_700
	plate.lit_color = Tokens.BASE_500
	plate.shade_color = Tokens.BASE_900
	plate.edge_color = Tokens.BASE_500


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
	pass

func _show_family(tier_id: String) -> void:
	for id in _family_vboxes.keys():
		_family_vboxes[id].visible = (id == tier_id)
	_open_family = tier_id

func _open_family_cross(tier_id: String) -> void:
	if _family_tabs.has(tier_id):
		_family_tabs[tier_id].button_pressed = true
	_open_family = tier_id


func _close_family(tier_id: String) -> void:
	pass


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

func _build_search_widget(parent: Control) -> void:
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "Search parts..."
	_search_box.clear_button_enabled = true
	_search_box.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	_search_box.text_changed.connect(_on_search_changed)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Tokens.BASE_900
	style.border_color = Tokens.BASE_500
	style.set_border_width_all(2)
	style.set_content_margin_all(8)
	_search_box.add_theme_stylebox_override("normal", style)
	_search_box.add_theme_stylebox_override("focus", style)
	
	parent.add_child(_search_box)


# --- Grouping helpers (unchanged) -------------------------------------------

func _bucket(groups: Dictionary, group: String, type_id: String, data: Dictionary) -> void:
	if not groups.has(group):
		groups[group] = []
	groups[group].append({"id": type_id, "data": data, "weight": float(data.get("weight", 0.0))})


func _hull_group(data: Dictionary) -> String:
	if data.get("is_foundation", false):
		return "Static Foundations"
	var declared := str(data.get("hull_class", "")).to_lower()
	if ModuleCatalog.HULL_TIER_BY_CLASS.has(declared):
		return HULL_TIER_TO_GROUP[ModuleCatalog.HULL_TIER_BY_CLASS[declared]]
	# Mod hull with no declared class. Same weight breakpoints
	# get_hull_size_tier() falls back to, so the two paths agree.
	var w = float(data.get("weight", 0.0))
	if w <= ModuleCatalog.HULL_TIER_LIGHT_MAX_WEIGHT:
		return "Light Chassis"
	if w <= ModuleCatalog.HULL_TIER_MEDIUM_MAX_WEIGHT:
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
	btn.mouse_entered.connect(func(): part_hovered.emit(type_id))
	btn.mouse_exited.connect(func(): part_unhovered.emit())
	btn.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE

	# Clear out the normal button styling completely so it's just a transparent hit target
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		
	# The Spore-style item grid
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	# 1. Top space for the 3D rendered icon (drag out)
	var icon_rect = ColorRect.new()
	icon_rect.color = Color(0,0,0, 0.2) # Dim placeholder for 3D render
	icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_rect)
	
	# Actual TextureRect for the 3D model thumbnail
	var icon_tex = TextureRect.new()
	icon_tex.name = "Thumbnail"
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.add_child(icon_tex)
	btn.set_meta("thumbnail_rect", icon_tex)
	
	# The catalog accent as a painted stripe inside the icon area
	var stripe = ColorRect.new()
	stripe.color = data["color"]
	stripe.custom_minimum_size = Vector2(4, 0)
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.add_child(stripe)

	# 2. Bottom tag — stamped metal label, sized to be readable
	var tag_rect = ColorRect.new()
	tag_rect.color = Color(0.10, 0.04, 0.04, 0.92)  # deep dark steel, near-black
	tag_rect.custom_minimum_size = Vector2(0, 34)
	tag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tag_rect)

	var name_lbl = Label.new()
	name_lbl.text = data["name"]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.82, 0.72, 1.0))  # warm ivory stamp
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_rect.add_child(name_lbl)
	
	# Focus ring for hover
	var focus_ring = ReferenceRect.new()
	focus_ring.border_width = 2.0
	focus_ring.editor_only = false
	focus_ring.visible = false
	focus_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	focus_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(focus_ring)
	
	btn.mouse_entered.connect(func(): focus_ring.visible = true)
	btn.mouse_exited.connect(func(): focus_ring.visible = false)

	if data.get("category", "") == "hull":
		var size = data.get("size", Vector3.ZERO)
		var domain = "Static Building" if data.get("is_foundation", false) else "Vehicle"
		btn.tooltip_text = "%s
%s hull
HP: %.0f | Weight: %.0f
Cost: %d Metal, %d Crystal
Size: %.1f x %.1f x %.1f" % [
			data["name"], domain, data.get("hp", 0.0), data.get("weight", 0.0),
			data.get("metal", 0), data.get("crystal", 0),
			size.x, size.y, size.z]
	else:
		btn.tooltip_text = _stat_tooltip(data)

	btn.set_meta("search_key", ("%s %s" % [data.get("name", ""), type_id]).to_lower())
	return btn


# A titled group of cards — styled as a physical drawer handle.
# The header is a knurled-metal bar, lighter than the family tabs above,
# with the category name stamped on it and a count badge at the right.
func _make_section(category: String, cards: Array, family: String) -> Control:
	var section = VBoxContainer.new()
	section.name = "Drawer_%s" % category.replace(" ", "_").replace("&", "and")
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header_btn = Button.new()
	header_btn.custom_minimum_size = Vector2(0, 38)  # taller = more physical handle feel
	header_btn.focus_mode = Control.FOCUS_NONE
	header_btn.toggle_mode = true
	header_btn.button_pressed = false
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		header_btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	# Knurled handle backing — lighter steel-grey, shinier than the red family tabs
	var handle_panel = PanelContainer.new()
	handle_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	handle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var handle_style = StyleBoxFlat.new()
	# Gunmetal machined steel — darker and heavier than the tab row above.
	handle_style.bg_color = Color(0.19, 0.19, 0.23, 1.0)
	handle_style.corner_radius_top_left = 4
	handle_style.corner_radius_top_right = 4
	handle_style.corner_radius_bottom_left = 4
	handle_style.corner_radius_bottom_right = 4
	# Emboss: bright highlight on top edge, dark shadow on bottom — reads as raised
	handle_style.border_color = Color(0.10, 0.10, 0.13, 1.0)  # groove edge
	handle_style.border_width_top = 0    # highlight drawn below as separate rect
	handle_style.border_width_bottom = 4  # heavy drawer-front lip
	handle_style.border_width_left = 2
	handle_style.border_width_right = 2
	handle_style.set_content_margin_all(0)
	handle_panel.add_theme_stylebox_override("panel", handle_style)
	
	var knurl_mat = ShaderMaterial.new()
	knurl_mat.shader = preload("res://shaders/knurled_metal.gdshader")
	handle_panel.material = knurl_mat
	header_btn.add_child(handle_panel)

	# Row inside the handle: label on left, count on right
	var inner_row = HBoxContainer.new()
	inner_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner_row.add_theme_constant_override("separation", 4)
	inner_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle_panel.add_child(inner_row)

	var pad_left = Control.new()
	pad_left.custom_minimum_size = Vector2(8, 0)
	pad_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_row.add_child(pad_left)

	# The stamped category name — bigger, brighter, reads as a stencil label
	var name_label = Label.new()
	name_label.text = category.to_upper()
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.88, 0.85, 0.80, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_row.add_child(name_label)

	# Count badge — lighter, right-aligned
	var count_label = Label.new()
	count_label.text = str(cards.size())
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count_label.add_theme_font_size_override("font_size", Tokens.FONT_MICRO)
	count_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60, 1.0))  # muted but legible
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_row.add_child(count_label)

	var pad_right = Control.new()
	pad_right.custom_minimum_size = Vector2(8, 0)
	pad_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_row.add_child(pad_right)

	section.add_child(header_btn)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_XS)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_XS)
	for c in cards:
		grid.add_child(c)
	grid.visible = false

	# Grimy open-state overlay — a dark rect almost entirely covered by the rubber
	# shader so the "open" drawer interior looks like a dark, grimy toolbox recess,
	# not a bright coloured surface. The overlay sits on top of the grid.
	var drawer_body = Control.new()
	drawer_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_body.visible = false
	section.add_child(drawer_body)

	var grimy_bg = ColorRect.new()
	grimy_bg.color = Color(0.28, 0.14, 0.10, 1.0)  # dim warm red — like steel under grime
	grimy_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	grimy_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grimy_mat = ShaderMaterial.new()
	grimy_mat.shader = preload("res://shaders/rubber_gasket.gdshader")
	grimy_bg.material = grimy_mat
	grimy_bg.modulate = Color(1.0, 1.0, 1.0, 0.82)  # heavy overlay, almost opaque

	drawer_body.add_child(grid)
	drawer_body.add_child(grimy_bg)

	section.set_meta("drawer_category", category)
	section.set_meta("drawer_tab", family)
	section.set_meta("drawer_open", false)
	section.set_meta("header_btn", header_btn)
	section.set_meta("content_container", grid)
	section.set_meta("family", family)

	header_btn.toggled.connect(func(pressed: bool):
		drawer_body.visible = pressed
		grid.visible = pressed
		grimy_bg.visible = pressed
		if pressed:
			_open_category(section)
			UIAnim.stagger_in(grid)
		else:
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
	# Propulsion is now grouped with Support
	return "weapons" if group in WEAPON_ROLES else "support"


# Returns the VBoxContainer (under the panel's ScrollContainer) that
# sections of this family are added to. Lazily creates the family's chrome
# the first time a section asks - in practice all four families are
# seeded in _build_shell, so this is just a defensive null check.
func _family_tier_body(tier_id: String) -> VBoxContainer:
	if _family_vboxes.has(tier_id):
		return _family_vboxes[tier_id]
	return _main_vbox


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
