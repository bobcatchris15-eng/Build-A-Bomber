extends Control

const ModuleCatalog = preload("res://scripts/module_catalog.gd")

@onready var tab_hulls = $PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer
@onready var tab_modules = $PanelContainer/VBoxContainer/TabContainer/Modules/VBoxContainer
@onready var tab_loco = $PanelContainer/VBoxContainer/TabContainer/Locomotion/VBoxContainer

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

func _ready():
	# Populate buttons from catalog
	var catalog = ModuleCatalog.get_catalog()
	var hull_buttons_by_domain: Dictionary = {}
	for domain in DOMAIN_ORDER:
		hull_buttons_by_domain[domain] = []

	for type_id in catalog.keys():
		var data = catalog[type_id]

		var btn = Button.new()
		btn.set_script(preload("res://scripts/part_button.gd"))
		btn.module_type_id = type_id
		btn.text = data["name"]
		btn.custom_minimum_size = Vector2(150, 40)

		# Visually differentiate buttons
		var style = StyleBoxFlat.new()
		style.bg_color = data["color"]
		style.border_width_bottom = 4
		style.border_color = data["color"].darkened(0.3)
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
			tab_loco.add_child(btn)
		else:
			tab_modules.add_child(btn)

	# Grouped by domain via button ORDER only, no header row - a first
	# attempt added a Label per domain, but even at a small font that
	# tripped the project's own UI-overflow test (this ScrollContainer
	# already sits right at its height budget with just the 15 buttons).
	# Each button's tooltip below still names its own domain, so the
	# grouping is discoverable without spending any extra vertical space.
	for domain in DOMAIN_ORDER:
		for btn in hull_buttons_by_domain[domain]:
			tab_hulls.add_child(btn)
