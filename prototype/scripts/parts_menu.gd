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

# The four TOP-LEVEL TOOLBOXES, in the order they appear when the dock opens.
#
# This is a presentation axis and is deliberately NOT the same thing as a
# section's `family` meta. Sections keep tagging themselves "hulls" / "modules" /
# "locomotion", because that is the catalog CATEGORY they came from and it is what
# sections_for() answers questions about - test_designer_lab and test_hull_and_armor
# both ask by category. Splitting "modules" across two toolboxes is a decision
# about where a player looks for a part, not a reclassification of the part.
const TIERS = [
	{"id": "hulls", "label": "Hulls"},
	{"id": "weapons", "label": "Weapons"},
	{"id": "support", "label": "Support"},
	{"id": "locomotion", "label": "Drives"},
]

# Which module ROLES are weapons. Taken from the catalog's own wording rather
# than invented here: MODULE_ROLES groups Deployables under the comment "weapons
# that leave something behind on the field instead of resolving damage at a
# target", so smoke and mines belong with the guns even at 0 dps. Everything the
# list does not name (Armor, Power, Support, Structural) falls to Support.
const WEAPON_ROLES = [
	"Direct-Fire Guns", "Energy & Electromagnetic", "Indirect Fire",
	"Missiles", "Point Defense", "Deployables",
]

const CARD_MIN_WIDTH := 132
const CARD_HEIGHT := 46

var _dock: UIDock
var _search_box: LineEdit
var _empty_hint: Label
var _sections_host: VBoxContainer

var _filter: String = ""
var _family: String = ""

# Every section built, across all three families, so search can sweep them
# without re-walking the scene tree on each keystroke.
var _all_drawers: Array = []

# The tier-2 toolbox. Created in _build_shell(); tiers are added lazily by
# _family_tier_body() as _populate() encounters each one.
var _toolbox: UIToolbox = null

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

	# NO FAMILY CHIPS. They used to sit here, and with the tiered toolboxes in
	# place they were the "odd hybrid" of two navigation systems: the chips and the
	# tiers were the same axis expressed twice, so a player could filter to Hulls
	# with a chip and then still have to open a Hulls tier, or worse, filter to
	# Drives while the Weapons tier was the one expanded. One structural hierarchy
	# replaces them - the tiers ARE the family selector now.
	#
	# Search stays. It is the only control here that does a different job:
	# grouping helps BROWSING, search helps RETRIEVAL, and it cuts across all four
	# toolboxes at once (see _force_open_family, which opens every tier holding a
	# match rather than accordioning to one).

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

	_toolbox = UIToolbox.new()
	# Unfolds rightward out of its header - this dock lives on the LEFT edge, so
	# content arriving from the left reads as coming out of the panel rather than
	# in from off-screen.
	_toolbox.stagger_from = Vector2(-12, 0)
	_sections_host.add_child(_toolbox)

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


# Retained for any caller still driving the old filter axis (and because
# _family is still honoured by _apply_filters), but nothing in the UI calls it
# now that the tiers carry the family choice structurally.
func _set_family(family: String) -> void:
	_family = family
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
		var tier_id := _tier_for(family, group)
		var section = _make_section(group, cards, family)
		# The toolbox this group is filed under, kept separate from the `family`
		# meta above - see the TIERS comment for why the two axes differ.
		section.set_meta("tier", tier_id)
		# Into the family's tier body rather than straight into _sections_host, which
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
# --- Tier 2: the family toolboxes -------------------------------------------
# TIER STRUCTURE (Chris's toolbox model):
#
#   tier 1  the dock itself, collapsed to a small metallic box   UIDock
#   tier 2  one toolbox per TIERS entry - Hulls/Weapons/Support/Drives  UIToolbox
#   tier 3  one drawer per CATEGORY inside a toolbox            _make_section
#   tier 4  the part cards                                      _build_part_card
#
# Tier 2 is now UIToolbox, which also backs the Design Lab's right-hand document
# actions - the widget was built twice here and in stat_calculator.gd before being
# extracted. Accordion at tier 2 comes from UIToolbox; accordion at tier 3 is
# _open_category below, because a category's siblings are the other drawers in the
# same toolbox rather than the other toolboxes.
#
# Sections keep living in _all_drawers regardless of which toolbox body owns them
# in the scene tree, which is what preserves the drawer metadata contract - the
# test suites walk that array, not the node hierarchy.
# Presentation tier for a (category, group) pair. Only "modules" splits, into
# Weapons and Support - see the TIERS and WEAPON_ROLES comments for why that is a
# presentation decision rather than a reclassification.
func _tier_for(family: String, group: String) -> String:
	if family != "modules":
		return family
	return "weapons" if group in WEAPON_ROLES else "support"


func _family_tier_body(tier_id: String) -> VBoxContainer:
	if not _toolbox.has_tier(tier_id):
		var label := tier_id.capitalize()
		for t in TIERS:
			if t["id"] == tier_id:
				label = str(t["label"])
				break
		_toolbox.add_tier(tier_id, label)
	return _toolbox.body_of(tier_id)


# Opens a toolbox without the accordion, so filtering can reveal matches across
# several at once.
func _force_open_family(tier_id: String) -> void:
	_toolbox.force_open(tier_id)


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
				section.get_meta("header_btn").set_pressed_no_signal(true)
				# TRUE. This read `false` briefly, which is what
				# test_module_roles_group_and_sort_the_parts_menu catches with
				# "survived the filter but stayed shut" - the drawer was opened
				# visually while recording itself as closed.
				section.set_meta("drawer_open", true)
				# ...and the family tier above it has to open too, or the match is
				# revealed inside a collapsed tier and stays invisible. This is new
				# with the tier structure: before it, a section had no ancestor that
				# could be shut.
				_force_open_family(str(section.get_meta("tier", family)))

	if _empty_hint:
		_empty_hint.visible = not any_visible


# _force_open_family() moved up beside the other tier helpers when the tier
# widget was extracted into UIToolbox; this was the second, now-stale copy.


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
