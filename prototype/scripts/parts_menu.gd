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

# Every ground/naval/air/static hull the catalog defines, all dumped into
# one undifferentiated "Hulls" tab with no domain grouping - a player
# couldn't compare, say, "Naval Hull" against "Light Hull" without
# already knowing which is which. Hardcoded here (not a new catalog
# field) to keep this a UI-only, low-risk change rather than touching
# module_catalog.gd's data schema.
const HULL_DOMAINS = {
	"light_hull": "Ground", "medium_hull": "Ground", "heavy_hull": "Ground",
	"interceptor_hull": "Ground", "assault_hull": "Ground", "sponson_hull": "Ground",
	"naval_hull": "Naval", "small_boat_hull": "Naval", "heavy_cruiser_hull": "Naval",
	"flying_wing_hull": "Air", "fuselage_hull": "Air", "airship_hull": "Air",
	"pillbox_foundation": "Static Defense", "tower_foundation": "Static Defense",
	"fortress_wall_foundation": "Static Defense",
}
const DOMAIN_ORDER = ["Ground", "Naval", "Air", "Static Defense"]

# Modules sub-categorization: weapon/armor/generator map directly off the
# catalog's own `category` field. The generic "module" category is itself a
# mix of two genuinely different roles (per module_catalog.gd's own
# "UTILITY & SUPPORT" vs "MOBILITY ADD-ONS" comment sections) - split via
# ModuleCatalog's existing SUPPORT_TYPE_IDS list (already the source of
# truth for "which modules count as support" elsewhere, e.g. energy/vision
# bonus wiring) rather than inventing a second, potentially-drifting list.
const MODULE_DOMAIN_ORDER = ["Weapons", "Armor", "Generators", "Utility", "Mobility"]

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

		# Visually differentiate buttons
		var style = StyleBoxFlat.new()
		style.bg_color = data["color"]
		style.border_width_bottom = 4
		style.border_color = data["color"].darkened(0.3)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", style)

		var hover_style = style.duplicate()
		hover_style.bg_color = data["color"].lightened(0.2)
		btn.add_theme_stylebox_override("hover", hover_style)

		var category = data.get("category", "module")
		if category == "hull":
			# Stat-preview tooltip (not a new visible panel - the sidebar
			# has no layout slack, see the manufactory-tier tooltip judgment
			# call) so a player can compare hulls before dragging one in.
			var size = data.get("size", Vector3.ZERO)
			var domain = HULL_DOMAINS.get(type_id, "Ground")
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

	# Header button (thin tab on the spine)
	var header_btn = Button.new()
	header_btn.custom_minimum_size = Vector2(0, 36)
	header_btn.text = category
	var header_style = StyleBoxFlat.new()
	header_style.bg_color = Color(0.2, 0.18, 0.15, 1.0)
	header_style.border_width_bottom = 2
	header_style.border_color = Color(0.45, 0.38, 0.2, 1.0)
	header_btn.add_theme_stylebox_override("normal", header_style)
	var header_hover = header_style.duplicate()
	header_hover.bg_color = Color(0.28, 0.24, 0.18, 1.0)
	header_btn.add_theme_stylebox_override("hover", header_hover)
	drawer.add_child(header_btn)

	# Content container (VBoxContainer with the buttons, starts hidden)
	var content = VBoxContainer.new()
	content.custom_minimum_size = Vector2(0, 0)
	content.visible = false
	for btn in buttons:
		content.add_child(btn)
	drawer.add_child(content)

	# Store drawer metadata for toggle handler
	drawer.set_meta("drawer_category", category)
	drawer.set_meta("drawer_tab", tab_type)
	drawer.set_meta("header_btn", header_btn)
	drawer.set_meta("content_container", content)

	# Connect header button click to toggle handler
	header_btn.pressed.connect(func(): _toggle_drawer(drawer))

	return drawer

func _toggle_drawer(drawer: Control) -> void:
	var category = drawer.get_meta("drawer_category")
	var tab_type = drawer.get_meta("drawer_tab")
	var content = drawer.get_meta("content_container")
	var should_open = not content.visible

	# Close any currently open drawer in this tab
	var open_var = "open_drawer_%s" % tab_type
	var currently_open = get(open_var)
	if currently_open != "" and currently_open != category:
		var parent = drawer.get_parent()
		for child in parent.get_children():
			if child.has_meta("drawer_category") and child.get_meta("drawer_category") == currently_open:
				var other_content = child.get_meta("content_container")
				other_content.visible = false
				break

	# Toggle this drawer
	content.visible = should_open
	set(open_var, category if should_open else "")

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
