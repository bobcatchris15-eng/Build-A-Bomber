extends Control

const ModuleCatalog = preload("res://scripts/module_catalog.gd")

@onready var tab_hulls = $PanelContainer/VBoxContainer/TabContainer/Hulls/VBoxContainer
@onready var tab_modules = $PanelContainer/VBoxContainer/TabContainer/Modules/VBoxContainer
@onready var tab_loco = $PanelContainer/VBoxContainer/TabContainer/Locomotion/VBoxContainer

func _ready():
	# Populate buttons from catalog
	var catalog = ModuleCatalog.get_catalog()
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
			tab_hulls.add_child(btn)
		elif category == "locomotion":
			tab_loco.add_child(btn)
		else:
			tab_modules.add_child(btn)
