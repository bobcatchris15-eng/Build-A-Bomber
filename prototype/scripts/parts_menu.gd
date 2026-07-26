extends Control

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")

@onready var tab_hulls = $PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer
@onready var tab_modules = $PanelContainer/VBoxContainer/TabContainer/Modules/VBoxContainer
@onready var tab_loco = $PanelContainer/VBoxContainer/TabContainer/Locomotion/VBoxContainer
@onready var panel_container = $PanelContainer

# Track which category drawer is currently open per tab
var open_drawer_hulls: String = ""
var open_drawer_modules: String = ""

# Hull grouping (HULL_MODDING_PLAN.md, simplified per Chris's call): just
# two buckets - "Vehicle" (any hull that moves, ground/naval/air all lumped
# together with no further subdivision) and "Static Building" (is_foundation
# == true - pillbox/tower/fortress_wall). Previously a 4-way Ground/Naval/
# Air/Static Defense split hardcoded by type_id in a table here; that table
# couldn't have generalized to a modded hull without a code change every
# time (see HULL_MODDING_PLAN.md §4c). The 2-way split needs no such table -
# it reads directly off the catalog's own is_foundation field (already
# load-bearing elsewhere, e.g. manufactory-queue eligibility), so a modded
# hull sorts correctly with zero code changes here.
const DOMAIN_ORDER = ["Vehicle", "Static Building"]

# Modules sub-categorization: weapon/armor/generator map directly off the
# catalog's own `category` field. The generic "module" category is itself a
# mix of two genuinely different roles (per module_catalog.gd's own
# "UTILITY & SUPPORT" vs "MOBILITY ADD-ONS" comment sections) - split via
# ModuleCatalog's existing SUPPORT_TYPE_IDS list (already the source of
# truth for "which modules count as support" elsewhere, e.g. energy/vision
# bonus wiring) rather than inventing a second, potentially-drifting list.
const MODULE_DOMAIN_ORDER = ["Weapons", "Armor", "Generators", "Utility", "Mobility", "Structural"]

# Uniform part-button colors (see _ready()'s button-building loop) - one
# dark background/text pair shared by every button regardless of module
# type, with the module's own catalog color demoted to an accent stripe.
const PART_BUTTON_BG = Color(0.14, 0.14, 0.17, 0.95)
const PART_BUTTON_BG_HOVER = Color(0.20, 0.20, 0.24, 0.95)
const PART_BUTTON_TEXT = Color(0.92, 0.93, 0.95, 1.0)
const PART_BUTTON_TEXT_OUTLINE = Color(0.02, 0.02, 0.03, 1.0)

func _ready():
	if panel_container:
		UITheme.apply_brushed_panel(panel_container, FactionCatalog.DEFAULT_FACTION, 0.35)

	# Populate buttons from catalog
	var catalog = ModuleCatalog.get_catalog()
	var hull_buttons_by_domain: Dictionary = {}
	for domain in DOMAIN_ORDER:
		hull_buttons_by_domain[domain] = []
	var module_buttons_by_domain: Dictionary = {}
	for domain in MODULE_DOMAIN_ORDER:
		module_buttons_by_domain[domain] = []

	for type_id in catalog.keys():
		var data = catalog[type_id]

		var btn = Button.new()
		btn.set_script(preload("res://scripts/part_button.gd"))
		btn.module_type_id = type_id
		btn.text = data["name"]
		btn.custom_minimum_size = Vector2(150, 30)

		# Uniform dark background for every button regardless of module
		# type (matches this project's locked-in "dark substrate + accent
		# trim, never a color-fill" register - see VISUAL_IMPROVEMENT_
		# PLAN.md's decision log) - the old per-module bg_color made some
		# buttons' default theme text unreadable depending on how light or
		# dark that module's catalog color happened to be. The module's
		# own color is still shown, just demoted to an accent stripe (the
		# bottom border) instead of the fill, and text gets an explicit
		# light color + outline so it stays legible against every accent.
		var style = StyleBoxFlat.new()
		style.bg_color = PART_BUTTON_BG
		style.border_width_bottom = 4
		style.border_color = data["color"]
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
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

		var category = data.get("category", "module")
		if category == "hull":
			# Stat-preview tooltip (not a new visible panel - the sidebar
			# has no layout slack, see the manufactory-tier tooltip judgment
			# call) so a player can compare hulls before dragging one in.
			var size = data.get("size", Vector3.ZERO)
			var domain = "Static Building" if data.get("is_foundation", false) else "Vehicle"
			btn.tooltip_text = "%s hull\nHP: %.0f | Weight: %.0f\nCost: %d Metal, %d Crystal\nSize: %.1f x %.1f x %.1f" % [
				domain, data.get("hp", 0.0), data.get("weight", 0.0),
				data.get("metal", 0), data.get("crystal", 0),
				size.x, size.y, size.z]
			hull_buttons_by_domain[domain].append(btn)
		elif category == "locomotion":
			# Same stat-preview treatment as hulls - previously only hulls
			# had any tooltip at all, weapon/armor/locomotion buttons had
			# zero explanatory text anywhere.
			btn.tooltip_text = _stat_tooltip(data)
			tab_loco.add_child(btn)
		else:
			btn.tooltip_text = _stat_tooltip(data)
			var module_domain = "Weapons"
			if category == "armor":
				module_domain = "Armor"
			elif category == "generator":
				module_domain = "Generators"
			elif category == "structural":
				module_domain = "Structural"
			elif category == "module":
				module_domain = "Utility" if type_id in ModuleCatalog.SUPPORT_TYPE_IDS else "Mobility"
			module_buttons_by_domain[module_domain].append(btn)

	# Create collapsible drawer containers per domain - only one expanded at a time
	# Each domain gets a clickable header button that reveals its contents in a drawer
	for domain in DOMAIN_ORDER:
		if hull_buttons_by_domain[domain].is_empty(): continue
		var drawer = _make_collapsible_drawer(domain, hull_buttons_by_domain[domain], "hulls")
		tab_hulls.add_child(drawer)

	for domain in MODULE_DOMAIN_ORDER:
		if module_buttons_by_domain[domain].is_empty(): continue
		var drawer = _make_collapsible_drawer(domain, module_buttons_by_domain[domain], "modules")
		tab_modules.add_child(drawer)

func _make_collapsible_drawer(category: String, buttons: Array, tab_type: String) -> Control:
	# Drawer UI: thin header spine on left edge, full-width content below
	# When collapsed, only the header tab (25px wide) is visible
	# When expanded, content slides down with smooth animation
	var drawer = VBoxContainer.new()
	drawer.name = "Drawer_%s" % category
	drawer.custom_minimum_size = Vector2(0, 0)

	# Header button (drawer header - prominent and clickable)
	var header_btn = Button.new()
	header_btn.custom_minimum_size = Vector2(0, 36)
	header_btn.text = category
	var header_style = StyleBoxFlat.new()
	header_style.bg_color = Color(0.3, 0.28, 0.22, 1.0)
	header_style.border_width_bottom = 3
	header_style.border_color = Color(0.85, 0.75, 0.4, 1.0)
	header_btn.add_theme_stylebox_override("normal", header_style)
	header_btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6, 1.0))
	var header_hover = header_style.duplicate()
	header_hover.bg_color = Color(0.35, 0.32, 0.25, 1.0)
	header_btn.add_theme_stylebox_override("hover", header_hover)
	drawer.add_child(header_btn)

	# Content container (VBoxContainer with the buttons, starts collapsed via min height)
	var content = VBoxContainer.new()
	content.custom_minimum_size = Vector2(0, 0)
	content.clip_contents = true
	content.visible = true
	for btn in buttons:
		content.add_child(btn)
	drawer.add_child(content)

	# Store drawer metadata for toggle handler
	drawer.set_meta("drawer_category", category)
	drawer.set_meta("drawer_tab", tab_type)
	drawer.set_meta("drawer_open", false)
	drawer.set_meta("header_btn", header_btn)
	drawer.set_meta("content_container", content)

	# Connect header button click to toggle handler
	header_btn.pressed.connect(func(): _toggle_drawer(drawer))

	return drawer

func _toggle_drawer(drawer: Control) -> void:
	var category = drawer.get_meta("drawer_category")
	var tab_type = drawer.get_meta("drawer_tab")
	var should_open = not drawer.get_meta("drawer_open")

	# Close any currently open drawer in this tab
	var open_var = "open_drawer_%s" % tab_type
	var currently_open = get(open_var)
	if currently_open != "" and currently_open != category:
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
	tween.tween_property(content, "custom_minimum_size:y", target_height, 0.18)
	drawer.set_meta("active_tween", tween)
	drawer.set_meta("drawer_open", open)

func _stat_tooltip(data: Dictionary) -> String:
	var lines = ["HP: %.0f | Weight: %.0f" % [data.get("hp", 0.0), data.get("weight", 0.0)]]
	lines.append("Cost: %d Metal, %d Crystal" % [data.get("metal", 0), data.get("crystal", 0)])
	var dps = data.get("dps", 0.0)
	if dps > 0.0:
		lines.append("DPS: %.0f" % dps)
	var heal_rate = data.get("heal_rate", 0.0)
	if heal_rate > 0.0:
		lines.append("Heal Rate: %.1f/s" % heal_rate)
	return "\n".join(lines)
