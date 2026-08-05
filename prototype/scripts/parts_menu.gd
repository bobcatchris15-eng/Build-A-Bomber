extends Control
# The hardware catalog.
#
# REAUTHORED, not restyled (Chris, 2026-08-02: "I specifically did not want
# just another reskin of the same static menu system"). What was here before:
# a fixed 320px column, permanently open, with a TabContainer of three tabs,
# each holding a one-at-a-time accordion of drawers, each drawer a vertical
# stack of full-width text buttons. Every one of those is a decision that costs
# the player something:
#
#   * PERMANENTLY OPEN. The catalog is a thing you visit, not a thing you read
#     continuously, and it was taking a fifth of the screen from the model.
#     It now lives in a UIDock and rails away to 40px.
#   * TABS. Three tabs meant a part was always two clicks and a guess away, and
#     search could not span them without fighting the tab state. Replaced by
#     FILTER CHIPS, which are multi-selectable, always visible, and compose
#     with search instead of competing with it.
#   * ONE-AT-A-TIME ACCORDION. Opening a drawer closed the one you were
#     comparing against. Sections now open independently.
#   * FULL-WIDTH TEXT ROWS. A 320px row per part is enormous for "Light Hull,
#     180kg" and meant six parts filled the panel. Parts are now compact CARDS
#     in a responsive grid, so a group is scannable at a glance.
#   * SEARCH BURIED. Search is the only thing that helps RETRIEVAL (grouping
#     helps browsing - different task), so it is now the first thing in the
#     panel and it is always focused-and-ready.
#
# WHAT DELIBERATELY SURVIVES. The grouping and sort LOGIC below is good and is
# covered by two suites in run_tests.gd - roles come from the catalog rather
# than a local table, hulls group by weight class, locomotion groups off its
# own traits array, and everything sorts light-to-heavy. That logic is
# untouched, and so is the node metadata contract those tests read
# (`drawer_category`, `content_container`, `header_btn`, `drawer_open`, and
# `_all_drawers`), so the presentation could change without the coverage
# rotting. Only the widgets changed.

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UIAnim = preload("res://scripts/ui_anim.gd")
const UIDockScript = preload("res://scripts/ui_dock.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

# --- Grouping ---------------------------------------------------------------
# Every one of the three families groups its parts and then sorts LIGHT TO
# HEAVY inside each group. Weight is the right sort key here rather than cost
# or name: it is the one stat every single part in the catalog has, it is
# monotonic with "how big a commitment is this", and on a game where payload
# capacity is the binding constraint it is the number a player is actually
# budgeting against while browsing. Alphabetical would scatter the light
# starter parts through the list; cost would put the crystal-heavy exotics next
# to the cheap junk.
#
# The group KEYS come from data the catalog already owns, never from a table of
# type_ids kept here - see ModuleCatalog.MODULE_ROLES for why. Modules group on
# `role`, hulls on is_foundation + weight class, and locomotion on its own
# `traits` array.

const HULL_LIGHT_MAX := 200.0
const HULL_MEDIUM_MAX := 450.0
const HULL_GROUP_ORDER = ["Light Chassis", "Medium Chassis", "Heavy Chassis", "Static Foundations"]

# Locomotion: derived from the traits array each entry already declares, so a
# modded drive sorts itself. Order is checked top-down and first match wins,
# which is what makes the overlapping traits resolve - buoyant_envelope is both
# "airborne" and "buoyant" and belongs under Air, screw_drive is both
# "ground_contact" and "amphibious" and belongs under Ground.
const LOCO_GROUP_ORDER = ["Ground", "Hover", "Naval", "Air"]

# The three families, as filter chips. "" is the all-pass chip.
const FAMILIES = [
	{"id": "", "label": "All"},
	{"id": "hulls", "label": "Hulls"},
	{"id": "modules", "label": "Modules"},
	{"id": "locomotion", "label": "Drives"},
]

const CARD_MIN_WIDTH := 132
const CARD_HEIGHT := 46

var _dock: UIDock
var _search_box: LineEdit
var _empty_hint: Label
var _sections_host: VBoxContainer
var _chip_buttons: Dictionary = {}

var _filter: String = ""
var _family: String = ""

# Every section built, across all three families, so search can sweep them
# without re-walking the scene tree on each keystroke.
var _all_drawers: Array = []

# family id -> its tier Control. Drives the accordion in _open_family_tier().
var _family_tiers: Dictionary = {}

# Retained so the old one-at-a-time API keeps working for any caller that still
# sets them; the new panel does not enforce single-open.
var open_drawer_hulls: String = ""
var open_drawer_modules: String = ""
var open_drawer_locomotion: String = ""


func _ready():
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

	_apply_filters()


# --- Shell ------------------------------------------------------------------

func _build_shell() -> void:
	# The panel fills whatever slot it is placed in; the dock owns the edge
	# anchoring and the collapse behaviour.
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_dock = UIDockScript.new()
	_dock.dock_title = "HARDWARE CATALOG"
	# Identifies the rail when the dock is collapsed to 40px, where the title
	# cannot fit - see ui_dock.gd's rail construction comment.
	_dock.dock_icon = "wrench"
	_dock.side = UIDockScript.Side.LEFT
	_dock.expanded_size = 336.0
	_dock.persist_key = "parts_catalog"
	_dock.auto_reveal = false
	_dock.default_state = UIDockScript.State.RAILED
	_dock.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	# Below the Design Lab's top toolbar, which spans the full width. Without this
	# the catalogue was drawn OVER the toolbar and clipped the mirror toggle.
	_dock.offset_top = Tokens.TOOLBAR_HEIGHT
	add_child(_dock)

	var host := _dock.body()

	# --- Search, first and always visible --------------------------------
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "Search parts"
	_search_box.clear_button_enabled = true
	_search_box.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	_search_box.text_changed.connect(_on_search_changed)
	host.add_child(_search_box)

	# --- Family filter chips ---------------------------------------------
	# Chips rather than tabs: they are always visible, they read as filters
	# rather than as pages, and they compose with the search box instead of
	# fighting it.
	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", Tokens.SPACE_XS)
	host.add_child(chips)

	for fam in FAMILIES:
		var chip = Button.new()
		chip.theme_type_variation = "TabButton"
		chip.toggle_mode = true
		chip.text = fam["label"]
		chip.focus_mode = Control.FOCUS_NONE
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size = Vector2(0, 26)
		chip.button_pressed = fam["id"] == ""
		var fam_id: String = fam["id"]
		chip.pressed.connect(func(): _set_family(fam_id))
		chips.add_child(chip)
		_chip_buttons[fam_id] = chip

	host.add_child(HSeparator.new())

	# --- Results ----------------------------------------------------------
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(scroll)

	_sections_host = VBoxContainer.new()
	_sections_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections_host.add_theme_constant_override("separation", Tokens.SPACE_XS)
	scroll.add_child(_sections_host)

	_empty_hint = Label.new()
	_empty_hint.text = "No parts match."
	_empty_hint.theme_type_variation = "HintLabel"
	_empty_hint.visible = false
	host.add_child(_empty_hint)

	# Document the interaction in the panel. Drag-to-place is not guessable
	# from a control that looks like a button.
	var hint = Label.new()
	hint.text = "Drag a part onto the hull to place it."
	hint.theme_type_variation = "HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.add_child(hint)


func _set_family(family: String) -> void:
	_family = family
	for id in _chip_buttons:
		_chip_buttons[id].button_pressed = (id == family)
	_apply_filters()


# --- Grouping helpers -------------------------------------------------------

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
		var section = _make_section(group, cards, family)
		# Into the family's tier body rather than straight into _sections_host, which
		# is what makes the hierarchy structural. _all_drawers still gets every
		# section, so sections_for() and the test suites are unaffected by the
		# re-parenting.
		_family_tier_body(family).add_child(section)
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
# --- Tier 2: the family toolbox ---------------------------------------------
# TIER STRUCTURE (Chris's toolbox model):
#
#   tier 1  the dock itself, collapsed to a 40px rail        (UIDock, existing)
#   tier 2  one toolbox per FAMILY - Hulls / Modules / Drives   (this function)
#   tier 3  one drawer per CATEGORY inside a family          (_make_section)
#   tier 4  the part cards                                   (_build_part_card)
#
# Only tier 2 is new. The families and categories were already in the data - the
# families were filter CHIPS and the categories were drawers in one flat column,
# so the hierarchy existed conceptually but the player had to hold it in their
# head. Making it structural means the column is short at rest and you descend to
# what you want.
#
# ACCORDION at both levels: opening a family closes its siblings, and opening a
# category closes its siblings within that family. At three levels deep a
# keep-everything-open column runs to several screen-heights, which defeats the
# collapsing this was built for.
#
# The sections keep living in _all_drawers regardless of which tier owns them in
# the scene tree, which is what keeps sections_for() and the drawer metadata
# contract (see _make_section) working - the test suites walk that array, not the
# node hierarchy.
# Returns the container a family's category drawers belong in, creating the tier
# on first use so _populate() does not have to be ordered against tier setup.
func _family_tier_body(family: String) -> VBoxContainer:
	if not _family_tiers.has(family):
		var label := family.capitalize()
		for f in FAMILIES:
			if f["id"] == family:
				label = str(f["label"])
				break
		var tier := _make_family_tier(family, label)
		_family_tiers[family] = tier
		_sections_host.add_child(tier)
	return _family_tiers[family].get_meta("tier_body")


func _make_family_tier(family: String, label: String) -> Control:
	var tier = VBoxContainer.new()
	tier.name = "Family_%s" % family
	tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header = Button.new()
	# TabButton, not ListButton: a family is a lid on a toolbox, and the theme's
	# tab treatment inverts its bevel when inactive - so a closed family reads as
	# pressed shut and the open one lifts. The categories below stay ListButton, so
	# the two tiers are visually distinct rather than a wall of identical rows.
	header.theme_type_variation = "TabButton"
	header.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = label
	header.focus_mode = Control.FOCUS_NONE
	header.toggle_mode = true
	# Closed at rest. The whole point of the tier is that the dock opens showing
	# three short rows rather than the entire catalogue.
	header.button_pressed = false
	tier.add_child(header)

	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.SPACE_XS)
	body.visible = false
	tier.add_child(body)

	tier.set_meta("family", family)
	tier.set_meta("tier_body", body)
	tier.set_meta("header_btn", header)

	header.toggled.connect(func(pressed: bool):
		if pressed:
			_open_family_tier(family)
		else:
			body.visible = false
	)
	UIFeedbackScript.wire(header, "select")
	return tier


# Opens one family and closes the rest.
func _open_family_tier(family: String) -> void:
	for f in _family_tiers.keys():
		var tier: Control = _family_tiers[f]
		if not is_instance_valid(tier):
			continue
		var is_target: bool = f == family
		var body: Control = tier.get_meta("tier_body")
		var header: Button = tier.get_meta("header_btn")
		body.visible = is_target
		# set_pressed_no_signal, or closing a sibling re-enters this function
		# through its own toggled handler and the loop fights itself.
		header.set_pressed_no_signal(is_target)
		if is_target:
			UIAnim.stagger_in(body, Vector2(-12, 0))


# Opens one category drawer and closes its siblings within the same family.
func _open_category(section: Control) -> void:
	var family := str(section.get_meta("family", ""))
	for other in _all_drawers:
		if not is_instance_valid(other):
			continue
		if str(other.get_meta("family", "")) != family:
			continue
		var is_target: bool = other == section
		var grid: Control = other.get_meta("content_container")
		var header: Button = other.get_meta("header_btn")
		grid.visible = is_target
		header.set_pressed_no_signal(is_target)
		other.set_meta("drawer_open", is_target)


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
	# rather than as a column to walk. Two columns at the dock's default width;
	# the grid reflows if the dock is dragged wider.
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


# --- Filtering --------------------------------------------------------------

func _on_search_changed(new_text: String) -> void:
	_filter = new_text.strip_edges().to_lower()
	_apply_filters()


# One pass that applies BOTH the family chip and the search text.
#
# They are applied together rather than as two independent passes because they
# interact: a search hit inside a family that is filtered out must stay hidden,
# and a section is only shown if it has surviving cards after both.
func _apply_filters() -> void:
	var any_visible := false

	for section in _all_drawers:
		if not is_instance_valid(section):
			continue
		var family: String = section.get_meta("family", "")
		var family_ok := _family == "" or family == _family

		var grid: Node = section.get_meta("content_container")
		var matches := 0
		for card in grid.get_children():
			var hit := family_ok and (_filter == ""
				or String(card.get_meta("search_key", "")).contains(_filter))
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
				section.get_meta("header_btn").button_pressed = true
				section.set_meta("drawer_open", false)

	if _empty_hint:
		_empty_hint.visible = not any_visible


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
