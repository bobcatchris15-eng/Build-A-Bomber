extends Control

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

@onready var tab_hulls = $PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer
@onready var tab_modules = $PanelContainer/VBoxContainer/TabContainer/Modules/VBoxContainer
@onready var tab_loco = $PanelContainer/VBoxContainer/TabContainer/Locomotion/VBoxContainer
@onready var tab_container = $PanelContainer/VBoxContainer/TabContainer
@onready var panel_container = $PanelContainer
@onready var header_label = $PanelContainer/VBoxContainer/Label

# Track which category drawer is currently open per tab
var open_drawer_hulls: String = ""
var open_drawer_modules: String = ""
var open_drawer_locomotion: String = ""

# --- Grouping ---------------------------------------------------------------
# Every one of the three tabs groups its parts and then sorts LIGHT TO HEAVY
# inside each group. Weight is the right sort key here rather than cost or
# name: it is the one stat every single part in the catalog has, it is
# monotonic with "how big a commitment is this", and on a game where payload
# capacity is the binding constraint it is the number a player is actually
# budgeting against while browsing. Alphabetical would scatter the light
# starter parts through the list; cost would put the crystal-heavy exotics
# next to the cheap junk.
#
# The group KEYS come from data the catalog already owns, never from a table
# of type_ids kept here - see ModuleCatalog.MODULE_ROLES for why. Modules
# group on `role`, hulls on is_foundation + weight class, and locomotion on
# its own `traits` array.

# Hulls: a single 22-entry "Vehicle" drawer was the worst offender in the old
# menu. Weight class is how the hulls actually differ (they have no other
# distinguishing field - no role, no traits), and it maps directly onto the
# only question a player asks when picking one: how much am I going to be
# able to bolt onto it.
const HULL_LIGHT_MAX := 200.0
const HULL_MEDIUM_MAX := 450.0
const HULL_GROUP_ORDER = ["Light Chassis", "Medium Chassis", "Heavy Chassis", "Static Foundations"]

# Locomotion: derived from the traits array each entry already declares, so a
# modded drive sorts itself. Order is checked top-down and first match wins,
# which is what makes the overlapping traits resolve - buoyant_envelope is
# both "airborne" and "buoyant" and belongs under Air, screw_drive is both
# "ground_contact" and "amphibious" and belongs under Ground.
const LOCO_GROUP_ORDER = ["Ground", "Hover", "Naval", "Air"]

# Uniform part-button colors (see _build_part_button()) - one dark background/
# text pair shared by every button regardless of module type, with the
# module's own catalog color demoted to an accent stripe.
const PART_BUTTON_BG = Color(0.14, 0.14, 0.17, 0.95)
const PART_BUTTON_BG_HOVER = Color(0.20, 0.20, 0.24, 0.95)
const PART_BUTTON_TEXT = Color(0.92, 0.93, 0.95, 1.0)
const PART_BUTTON_TEXT_OUTLINE = Color(0.02, 0.02, 0.03, 1.0)
const PART_BUTTON_STAT_TEXT = Color(0.62, 0.66, 0.72, 1.0)

# Every drawer built, across all three tabs, so search can sweep them without
# re-walking the scene tree on each keystroke.
var _all_drawers: Array = []
var _search_box: LineEdit = null
var _empty_hint: Label = null
var _filter: String = ""

func _ready():
	if panel_container:
		UITheme.apply_brushed_panel(panel_container, FactionCatalog.DEFAULT_FACTION, 0.35)

	_build_search_bar()

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

	_populate_tab(tab_hulls, hull_groups, HULL_GROUP_ORDER, "hulls")
	_populate_tab(tab_modules, module_groups, ModuleCatalog.MODULE_ROLE_ORDER, "modules")
	_populate_tab(tab_loco, loco_groups, LOCO_GROUP_ORDER, "locomotion")

	_build_footer_hint()

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

func _populate_tab(host: Node, groups: Dictionary, order: Array, tab_type: String) -> void:
	if host == null:
		return
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
		# runs - Dictionary.keys() order is insertion order, not sorted, and
		# an unstable sidebar is genuinely disorienting to browse.
		entries.sort_custom(func(a, b):
			if is_equal_approx(a.weight, b.weight):
				return String(a.data.get("name", a.id)) < String(b.data.get("name", b.id))
			return a.weight < b.weight)

		var buttons := []
		for entry in entries:
			buttons.append(_build_part_button(entry.id, entry.data))
		var drawer = _make_collapsible_drawer(group, buttons, tab_type)
		host.add_child(drawer)
		_all_drawers.append(drawer)

func _build_part_button(type_id: String, data: Dictionary) -> Button:
	var btn = Button.new()
	btn.set_script(preload("res://scripts/part_button.gd"))
	btn.module_type_id = type_id
	btn.text = data["name"]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.custom_minimum_size = Vector2(150, 30)

	# Uniform dark background for every button regardless of module type
	# (matches this project's locked-in "dark substrate + accent trim, never a
	# color-fill" register - see VISUAL_IMPROVEMENT_PLAN.md's decision log).
	# The module's own color is shown as the bottom accent stripe.
	var style = StyleBoxFlat.new()
	style.bg_color = PART_BUTTON_BG
	style.border_width_bottom = 4
	style.border_color = data["color"]
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = PART_BUTTON_BG_HOVER
	hover_style.border_color = data["color"].lightened(0.25)
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.add_theme_color_override("font_color", PART_BUTTON_TEXT)
	btn.add_theme_color_override("font_hover_color", PART_BUTTON_TEXT)
	btn.add_theme_color_override("font_pressed_color", PART_BUTTON_TEXT)
	btn.add_theme_color_override("font_outline_color", PART_BUTTON_TEXT_OUTLINE)
	btn.add_theme_constant_override("outline_size", 3)

	# Inline weight readout, right-aligned inside the button. The tooltip card
	# already carries the full stat block, but a tooltip only answers a
	# question you already thought to ask - the whole point of sorting the
	# list by weight is defeated if the weight itself is invisible until you
	# hover each entry one at a time. Kept to the one sort-key stat so the row
	# stays a row and doesn't turn into a second stat panel.
	var weight_label = Label.new()
	weight_label.text = "%.0f" % float(data.get("weight", 0.0))
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weight_label.add_theme_font_size_override("font_size", 11)
	weight_label.add_theme_color_override("font_color", PART_BUTTON_STAT_TEXT)
	weight_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	weight_label.offset_right = -10
	# The button carries a 4px accent stripe along its bottom border, which
	# PRESET_FULL_RECT includes - without pulling the label up off it, the
	# number sits visibly low against the stripe instead of centred on the row.
	weight_label.offset_bottom = -4
	# Must not eat the click, and must not eat the drag either - part_button's
	# _get_drag_data() is what makes these draggable onto the hull.
	weight_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(weight_label)

	if data.get("category", "") == "hull":
		# Stat-preview tooltip (not a new visible panel - the sidebar has no
		# layout slack) so a player can compare hulls before dragging one in.
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

	# Cached for search - matching on the visible name plus the id means
	# typing "mk19" or "Grenade" both work.
	btn.set_meta("search_key", ("%s %s" % [data.get("name", ""), type_id]).to_lower())
	return btn

func _build_search_bar() -> void:
	# The single highest-value addition here. Every builder game with a parts
	# palette this size (KSP2's VAB is the canonical example) gets the same
	# complaint - the categories are fine but actually FINDING a specific part
	# means opening drawers one at a time until you spot it. Grouping helps
	# browsing; only search helps retrieval, and they are different tasks.
	var host = header_label.get_parent() if header_label else null
	if host == null:
		return

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "Search parts..."
	_search_box.clear_button_enabled = true
	_search_box.custom_minimum_size = Vector2(0, 28)
	_search_box.text_changed.connect(_on_search_changed)
	host.add_child(_search_box)
	host.move_child(_search_box, header_label.get_index() + 1)

	_empty_hint = Label.new()
	_empty_hint.text = "  No parts match."
	_empty_hint.add_theme_font_size_override("font_size", 12)
	_empty_hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45, 1.0))
	_empty_hint.visible = false
	host.add_child(_empty_hint)
	host.move_child(_empty_hint, _search_box.get_index() + 1)

func _build_footer_hint() -> void:
	# "Document controls in-UI rather than leaving them to external guides" -
	# the recurring discoverability complaint across this whole genre. Drag-
	# to-place has never been stated anywhere in the Lab itself; a new player
	# has no reason to guess that these buttons are drag sources at all,
	# because they look exactly like buttons you click.
	var host = header_label.get_parent() if header_label else null
	if host == null:
		return
	var hint = Label.new()
	hint.text = "Drag a part onto the hull to place it."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.53, 0.48, 1.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.add_child(hint)

# --- Search -----------------------------------------------------------------

func _on_search_changed(new_text: String) -> void:
	_filter = new_text.strip_edges().to_lower()
	var any_visible := false

	for drawer in _all_drawers:
		if not is_instance_valid(drawer):
			continue
		var content: Node = drawer.get_meta("content_container")
		var matches := 0
		for btn in content.get_children():
			var hit := _filter == "" or String(btn.get_meta("search_key", "")).contains(_filter)
			btn.visible = hit
			if hit:
				matches += 1

		# A drawer with nothing in it is hidden entirely rather than left as an
		# empty header - a column of dead headers reads as "the search broke"
		# rather than "no hits in this group".
		drawer.visible = matches > 0
		if matches > 0:
			any_visible = true

		if _filter == "":
			# Leaving the search restores the accordion: everything collapses
			# back to headers, and the per-tab "which drawer is open" state is
			# cleared so the next header click doesn't try to close a drawer
			# that is already shut.
			_set_drawer_open(drawer, false)
		else:
			# While filtering, force every surviving drawer open. Making the
			# player click a header to see the thing they just searched for
			# would defeat the search.
			drawer.set_meta("content_target_height", content.get_combined_minimum_size().y)
			_set_drawer_open(drawer, true)

	if _filter == "":
		open_drawer_hulls = ""
		open_drawer_modules = ""
		open_drawer_locomotion = ""

	if _empty_hint:
		_empty_hint.visible = _filter != "" and not any_visible

func _set_drawer_open(drawer: Control, open: bool) -> void:
	# Instant, not tweened. Search runs on every keystroke; animating each
	# drawer per character would stack dozens of live tweens and lag behind
	# the typing.
	if drawer.has_meta("active_tween"):
		var old = drawer.get_meta("active_tween")
		if old and old.is_valid():
			old.kill()
	var content: Control = drawer.get_meta("content_container")
	var clip: Control = drawer.get_meta("clip_container")
	var target := 0.0
	if open:
		target = drawer.get_meta("content_target_height", content.get_combined_minimum_size().y)
	clip.custom_minimum_size.y = target
	drawer.set_meta("drawer_open", open)

# --- Drawers ----------------------------------------------------------------

func _make_collapsible_drawer(category: String, buttons: Array, tab_type: String) -> Control:
	# Drawer UI: clickable header, contents revealed below.
	# Only one drawer per tab is expanded at a time (outside of search).
	var drawer = VBoxContainer.new()
	drawer.name = "Drawer_%s" % category.replace(" ", "_").replace("&", "and")
	drawer.custom_minimum_size = Vector2(0, 0)

	var header_btn = Button.new()
	header_btn.custom_minimum_size = Vector2(0, 36)
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_btn.text = category
	var header_style = StyleBoxFlat.new()
	header_style.bg_color = Color(0.3, 0.28, 0.22, 1.0)
	header_style.border_width_bottom = 3
	header_style.border_color = Color(0.85, 0.75, 0.4, 1.0)
	header_style.content_margin_left = 8
	header_style.content_margin_right = 8
	header_btn.add_theme_stylebox_override("normal", header_style)
	header_btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6, 1.0))
	var header_hover = header_style.duplicate()
	header_hover.bg_color = Color(0.35, 0.32, 0.25, 1.0)
	header_btn.add_theme_stylebox_override("hover", header_hover)

	# Count badge on the right of the header. With a closed accordion the
	# player otherwise has no idea whether a drawer holds two parts or twelve,
	# which makes deciding where to look a coin flip.
	var count_label = Label.new()
	count_label.text = str(buttons.size())
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.add_theme_color_override("font_color", Color(0.65, 0.60, 0.42, 1.0))
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	count_label.offset_right = -10
	count_label.offset_bottom = -3
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_btn.add_child(count_label)

	drawer.add_child(header_btn)

	# Content, in a plain Control CLIP WRAPPER rather than the button
	# VBoxContainer directly.
	#
	# This matters and isn't cosmetic. A Container propagates its children's
	# combined minimum size to its parent, and clip_contents does NOT change
	# that - so with the buttons' VBox as the drawer's direct child, every
	# COLLAPSED drawer still demanded its full expanded height from the tab
	# above it. With more, finer drawers than the old menu had (and a search
	# bar taking a slice off the top) that tipped the Hulls tab into a real
	# layout overflow, which the UI audit suite catches. A plain Control has
	# no such propagation: it reports exactly the custom_minimum_size we set,
	# which is the height the drawer animation is already driving anyway.
	var clip = Control.new()
	clip.clip_contents = true
	# Explicit opt-out from the layout-overflow audit. A shut drawer is a
	# zero-height window around a full-height list on purpose; see
	# ui_audit.gd's note on why this is a stated flag and not inferred from
	# clip_contents.
	clip.set_meta("ui_audit_clip_ok", true)
	clip.custom_minimum_size = Vector2(0, 0)
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var content = VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_TOP_WIDE)
	content.offset_left = 0
	content.offset_right = 0
	for btn in buttons:
		content.add_child(btn)
	clip.add_child(content)
	drawer.add_child(clip)

	drawer.set_meta("drawer_category", category)
	drawer.set_meta("drawer_tab", tab_type)
	drawer.set_meta("drawer_open", false)
	drawer.set_meta("header_btn", header_btn)
	# "content_container" is the button list (iterated by search and by the
	# tests); "clip_container" is what the open/close animation resizes.
	drawer.set_meta("content_container", content)
	drawer.set_meta("clip_container", clip)

	header_btn.pressed.connect(func(): _toggle_drawer(drawer))

	return drawer

func _toggle_drawer(drawer: Control) -> void:
	var category = drawer.get_meta("drawer_category")
	var tab_type = drawer.get_meta("drawer_tab")
	var should_open = not drawer.get_meta("drawer_open")

	# Close any currently open drawer in this tab
	var open_var = "open_drawer_%s" % tab_type
	var currently_open = get(open_var)
	if currently_open != null and currently_open != "" and currently_open != category:
		var parent = drawer.get_parent()
		for child in parent.get_children():
			if child.has_meta("drawer_category") and child.get_meta("drawer_category") == currently_open:
				_animate_drawer(child, false)
				break

	# Animate this drawer
	_animate_drawer(drawer, should_open)
	set(open_var, category if should_open else "")

func _animate_drawer(drawer: Control, open: bool) -> void:
	var content = drawer.get_meta("content_container")
	var clip = drawer.get_meta("clip_container")

	# Kill any active tween on this drawer
	if drawer.has_meta("active_tween"):
		var old = drawer.get_meta("active_tween")
		if old and old.is_valid():
			old.kill()

	# Cache target height on first open so closing doesn't measure while collapsed
	if open and not drawer.has_meta("content_target_height"):
		drawer.set_meta("content_target_height", content.get_combined_minimum_size().y)

	var target_height = drawer.get_meta("content_target_height") if open else 0.0

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(clip, "custom_minimum_size:y", target_height, 0.18)
	drawer.set_meta("active_tween", tween)
	drawer.set_meta("drawer_open", open)

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
