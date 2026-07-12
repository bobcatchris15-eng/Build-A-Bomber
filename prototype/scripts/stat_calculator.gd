extends Control

const ModuleData = preload("res://scripts/module_data.gd")

@onready var hp_label = $ScrollContainer/VBoxContainer/HPLabel
@onready var weight_label = $ScrollContainer/VBoxContainer/WeightLabel
@onready var cost_label = $ScrollContainer/VBoxContainer/CostLabel
@onready var dps_label = $ScrollContainer/VBoxContainer/DPSLabel
@onready var mirror_checkbox = $ScrollContainer/VBoxContainer/MirrorCheckBox
@onready var delete_button = $ScrollContainer/VBoxContainer/DeleteButton
@onready var save_button = $ScrollContainer/VBoxContainer/SaveButton
@onready var test_button = $ScrollContainer/VBoxContainer/TestButton
@onready var blueprint_name_edit = $ScrollContainer/VBoxContainer/BlueprintNameEdit
@onready var library_button = $ScrollContainer/VBoxContainer/LibraryButton

@onready var locomotion_tweaks = $ScrollContainer/VBoxContainer/LocomotionTweaks
@onready var size_label = $ScrollContainer/VBoxContainer/LocomotionTweaks/SizeContainer/SizeLabel
@onready var size_slider = $ScrollContainer/VBoxContainer/LocomotionTweaks/SizeContainer/SizeSlider
@onready var count_container = $ScrollContainer/VBoxContainer/LocomotionTweaks/CountContainer
@onready var count_slider = $ScrollContainer/VBoxContainer/LocomotionTweaks/CountContainer/CountSlider

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")
var current_selected_module: Node3D = null
var is_updating_sliders: bool = false
var module_tweaks_container: VBoxContainer

# Floating Popup Window fields
var popup_panel: PanelContainer
var popup_vbox: VBoxContainer
var popup_name_label: Label
var popup_stats_label: Label
var popup_tweaks_container: VBoxContainer
var popup_rotate_btn: Button

const TWEAK_SPECS = {
	"basic_cannon": [
		{"name": "caliber", "label": "Caliber", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "barrel_length", "label": "Barrel Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"heavy_machine_gun": [
		{"name": "multi_barrel", "label": "Multi-Barrel Mode", "type": "bool", "default": false},
		{"name": "drum_size", "label": "Ammo Drum Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"rotary_cannon": [
		{"name": "barrel_count", "label": "Barrel Count", "min": 3.0, "max": 8.0, "step": 1.0, "default": 6.0},
		{"name": "motor_size", "label": "Electric Motor Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"gauss_railgun": [
		{"name": "rail_length", "label": "Electromagnetic Rail Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"heavy_howitzer": [
		{"name": "elevation", "label": "Howitzer Elevation Mount", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"mortar_array": [
		{"name": "tube_count", "label": "Mortar Tube Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0}
	],
	"spigot_mortar": [
		{"name": "rod_thickness", "label": "Spigot Rod Thickness", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"guided_missile": [
		{"name": "seeker_size", "label": "Seeker Head Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "engine_length", "label": "Missile Engine Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"dual_stage_missile": [
		{"name": "ascent_thruster", "label": "Top-Attack Ascent Thruster", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "payload_size", "label": "Warhead Payload Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"missile_pod": [
		{"name": "grid_size", "label": "Swarm Pod Grid Size", "min": 2.0, "max": 6.0, "step": 1.0, "default": 4.0}
	],
	"cluster_dispenser": [
		{"name": "dispersion", "label": "Dispersion Matrix Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"flamethrower": [
		{"name": "nozzle_width", "label": "Emitter Nozzle Width", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0},
		{"name": "pressure_valve", "label": "Pressure Fuel Valve", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"heavy_laser": [
		{"name": "lens_aperture", "label": "Laser Lens Aperture", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"plasma_lobber": [
		{"name": "containment", "label": "Containment Field Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"ciws": [
		{"name": "radar_dish", "label": "CIWS Tracking Radar Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"pd_laser": [
		{"name": "cooling_jacket", "label": "PD Laser Cooling Jacket", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"flak_cannon": [
		{"name": "fuse_setting", "label": "Proximity Fuse Setter", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"resource_harvester": [
		{"name": "extractor_size", "label": "Extractor Arm Length", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"repair_array": [
		{"name": "welder_count", "label": "Welder Arm Count", "min": 1.0, "max": 4.0, "step": 1.0, "default": 2.0}
	],
	"sensor_suite": [
		{"name": "mast_height", "label": "Radar Mast Height", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"logistics_tank": [
		{"name": "tank_capacity", "label": "Fuel/Power Capacity", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	# Previously documented in Arsenal_Weapons_List.md but missing from this
	# dict entirely - drone_carrier rendered zero tweak sliders in the
	# Design Lab (ENERGY_AND_BALANCE_SPEC.md #3).
	"drone_carrier": [
		{"name": "hangar_size", "label": "Hangar Size (Drone Count)", "min": 1.0, "max": 5.0, "step": 1.0, "default": 2.0},
		{"name": "launch_catapult", "label": "Launch Catapult", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	# Energy weapons (ENERGY_AND_BALANCE_SPEC.md #5)
	"tesla_coil": [
		{"name": "caliber", "label": "Coil Charge Size", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"arc_projector": [
		{"name": "containment", "label": "Arc Containment Field", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	],
	"ion_cannon": [
		{"name": "lens_aperture", "label": "Ion Focusing Lens", "min": 0.5, "max": 2.0, "step": 0.1, "default": 1.0}
	]
}

var armor_mat_label: Label
var armor_mat_btn: OptionButton
var armor_thick_label: Label
var armor_thick_slider: HSlider
var armor_threshold_label: Label
var energy_label: Label
var nose_taper_label: Label
var nose_taper_slider: HSlider

func _ready():
	add_to_group("stat_ui")
	mirror_checkbox.toggled.connect(_on_mirror_toggled)
	delete_button.pressed.connect(_on_delete_pressed)
	save_button.pressed.connect(_on_save_pressed)
	test_button.pressed.connect(_on_test_pressed)
	library_button.pressed.connect(_on_library_pressed)
	blueprint_name_edit.text_changed.connect(_on_blueprint_name_changed)
	
	size_slider.value_changed.connect(_on_size_value_changed)
	count_slider.value_changed.connect(_on_count_value_changed)
	size_slider.drag_started.connect(_push_undo)
	count_slider.drag_started.connect(_push_undo)
	
	# Dynamically create Armor Material dropdown
	armor_mat_label = Label.new()
	armor_mat_label.text = "Armor Material"
	$ScrollContainer/VBoxContainer.add_child(armor_mat_label)
	
	armor_mat_btn = OptionButton.new()
	armor_mat_btn.add_item("Hardened Steel")
	armor_mat_btn.add_item("Reactive Armor")
	armor_mat_btn.add_item("Ablative Ceramic")
	armor_mat_btn.add_item("Energy Shielding")
	$ScrollContainer/VBoxContainer.add_child(armor_mat_btn)
	armor_mat_btn.item_selected.connect(_on_armor_material_selected)
	
	# Dynamically create Faction dropdown
	var faction_label = Label.new()
	faction_label.text = "Faction Selection"
	$ScrollContainer/VBoxContainer.add_child(faction_label)
	
	var faction_btn = OptionButton.new()
	faction_btn.add_item("Heavy Industrialists")
	faction_btn.add_item("Technocrats")
	faction_btn.add_item("Expansionists")
	faction_btn.name = "FactionDropdown"
	$ScrollContainer/VBoxContainer.add_child(faction_btn)
	faction_btn.item_selected.connect(_on_faction_selected)
	
	# Dynamically create Armor Thickness slider
	armor_thick_label = Label.new()
	armor_thick_label.text = "Armor Thickness"
	$ScrollContainer/VBoxContainer.add_child(armor_thick_label)
	
	armor_thick_slider = HSlider.new()
	armor_thick_slider.min_value = 0.5
	armor_thick_slider.max_value = 3.0
	armor_thick_slider.step = 0.1
	armor_thick_slider.value = 1.0
	$ScrollContainer/VBoxContainer.add_child(armor_thick_slider)
	armor_thick_slider.value_changed.connect(_on_armor_thickness_changed)
	armor_thick_slider.drag_started.connect(_push_undo)

	# Per-hull-type custom deform proof-of-concept (MOUNTING_AND_ARMOR_SPEC.md
	# #4) - only shown for interceptor_hull, see DECISIONS_NEEDED.md for why
	# the other 6 hulls don't have this yet. Reshapes the nose region of the
	# actual mesh (HullDeform.apply_nose_taper via MeshDataTool), distinct
	# from the uniform hull-scale handles which stretch the whole hull evenly.
	nose_taper_label = Label.new()
	nose_taper_label.text = "Nose Taper"
	$ScrollContainer/VBoxContainer.add_child(nose_taper_label)

	nose_taper_slider = HSlider.new()
	nose_taper_slider.min_value = 0.3
	nose_taper_slider.max_value = 1.5
	nose_taper_slider.step = 0.05
	nose_taper_slider.value = 1.0
	$ScrollContainer/VBoxContainer.add_child(nose_taper_slider)
	nose_taper_slider.value_changed.connect(_on_nose_taper_changed)
	nose_taper_slider.drag_started.connect(_push_undo)
	nose_taper_slider.visible = false
	nose_taper_label.visible = false

	# Create Module Tweaks container
	module_tweaks_container = VBoxContainer.new()
	module_tweaks_container.name = "ModuleTweaksContainer"
	module_tweaks_container.add_theme_constant_override("separation", 8)
	$ScrollContainer/VBoxContainer.add_child(module_tweaks_container)
	
	# Dynamic Floating Customization Popup setup
	popup_panel = PanelContainer.new()
	popup_panel.name = "ModulePopup"
	popup_panel.visible = false
	popup_panel.custom_minimum_size = Vector2(280, 0)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.7, 1.0, 0.7) # Glowing cyan border
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	popup_panel.add_theme_stylebox_override("panel", style)
	
	add_child(popup_panel)
	
	popup_vbox = VBoxContainer.new()
	popup_vbox.add_theme_constant_override("separation", 6)
	popup_panel.add_child(popup_vbox)
	
	popup_name_label = Label.new()
	popup_name_label.text = "Module Customization"
	popup_name_label.add_theme_font_size_override("font_size", 16)
	popup_name_label.add_theme_color_override("font_color", Color.GOLD)
	popup_vbox.add_child(popup_name_label)
	
	popup_stats_label = Label.new()
	popup_stats_label.text = ""
	popup_stats_label.add_theme_font_size_override("font_size", 12)
	popup_vbox.add_child(popup_stats_label)
	
	popup_rotate_btn = Button.new()
	popup_rotate_btn.text = "🔄 Rotate 90° [R]"
	popup_rotate_btn.add_theme_font_size_override("font_size", 12)
	popup_rotate_btn.pressed.connect(func():
		var root = get_node_or_null("/root/MainLab")
		var placer = root.get_node_or_null("ModulePlacer") if root else null
		if placer and placer.has_method("rotate_selected_module"):
			placer.rotate_selected_module()
	)
	popup_vbox.add_child(popup_rotate_btn)
	
	popup_tweaks_container = VBoxContainer.new()
	popup_tweaks_container.add_theme_constant_override("separation", 6)
	popup_vbox.add_child(popup_tweaks_container)
	
	# Undo/Redo (Design_Lab_UI_UX.md top-bar spec: also bound to Ctrl+Z / Ctrl+Y)
	var undo_redo_row = HBoxContainer.new()
	undo_redo_row.add_theme_constant_override("separation", 6)
	$ScrollContainer/VBoxContainer.add_child(undo_redo_row)

	var undo_btn = Button.new()
	undo_btn.text = "↶ Undo"
	undo_btn.pressed.connect(func():
		var root = get_node_or_null("/root/MainLab")
		if root and root.has_method("undo"):
			root.undo()
	)
	undo_redo_row.add_child(undo_btn)

	var redo_btn = Button.new()
	redo_btn.text = "↷ Redo"
	redo_btn.pressed.connect(func():
		var root = get_node_or_null("/root/MainLab")
		if root and root.has_method("redo"):
			root.redo()
	)
	undo_redo_row.add_child(redo_btn)

	# Navigation back to the main menu
	var menu_btn = Button.new()
	menu_btn.text = "◀ Main Menu"
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	$ScrollContainer/VBoxContainer.add_child(menu_btn)

	# Initial sync of armor UI
	call_deferred("_initial_sync")

func _push_undo():
	var root = get_node_or_null("/root/MainLab")
	if root and root.has_method("push_undo_snapshot"):
		root.push_undo_snapshot()

func _on_delete_pressed():
	var root = get_node("/root/MainLab")
	if root and root.has_method("delete_selected_module"):
		root.delete_selected_module()
		
func _on_save_pressed():
	var root = get_node("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		var name_text = blueprint_name_edit.text.strip_edges()
		if name_text == "":
			name_text = "Untitled Design"
			blueprint_name_edit.text = name_text
		hull.set_meta("blueprint_name", name_text)
	var blueprint_manager = root.get_node_or_null("BlueprintManager")
	if blueprint_manager:
		blueprint_manager.save_blueprint()

func _on_blueprint_name_changed(new_text: String):
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		hull.set_meta("blueprint_name", new_text)

func _on_library_pressed():
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	# Avoid opening a second copy of the panel
	if root.has_node("BlueprintLibraryPanel"):
		return
	var LibraryPanel = preload("res://scripts/blueprint_library_panel.gd")
	var panel = LibraryPanel.new()
	panel.name = "BlueprintLibraryPanel"
	root.add_child(panel)

func sync_hull_ui(hull: Node3D):
	if not hull:
		if blueprint_name_edit:
			blueprint_name_edit.text = "Untitled Design"
		return
	is_updating_sliders = true
	if blueprint_name_edit:
		var bp_name = hull.get_meta("blueprint_name") if hull.has_meta("blueprint_name") else "Untitled Design"
		blueprint_name_edit.text = bp_name
	if armor_mat_btn:
		var mat = hull.get_meta("armor_material") if hull.has_meta("armor_material") else "hardened_steel"
		match mat:
			"hardened_steel": armor_mat_btn.selected = 0
			"reactive_armor": armor_mat_btn.selected = 1
			"ablative_ceramic": armor_mat_btn.selected = 2
			"energy_shielding": armor_mat_btn.selected = 3
	if armor_thick_slider:
		var thick = hull.get_meta("armor_thickness") if hull.has_meta("armor_thickness") else 1.0
		armor_thick_slider.value = thick
		if armor_thick_label:
			armor_thick_label.text = "Armor Thickness: %.1f" % thick
	if nose_taper_slider and nose_taper_label:
		var hull_type = hull.get_meta("type_id") if hull.has_meta("type_id") else "medium_hull"
		var is_interceptor = hull_type == "interceptor_hull"
		nose_taper_slider.visible = is_interceptor
		nose_taper_label.visible = is_interceptor
		if is_interceptor:
			var taper = hull.get_meta("nose_taper") if hull.has_meta("nose_taper") else 1.0
			nose_taper_slider.value = taper
			nose_taper_label.text = "Nose Taper: %.2fx" % taper
	var faction_btn = $ScrollContainer/VBoxContainer.get_node_or_null("FactionDropdown") as OptionButton
	if faction_btn:
		var fac = hull.get_meta("faction") if hull.has_meta("faction") else "industrialists"
		match fac:
			"industrialists": faction_btn.selected = 0
			"technocrats": faction_btn.selected = 1
			"expansionists": faction_btn.selected = 2
	is_updating_sliders = false
	update_stats(hull)

func _on_test_pressed():
	var root = get_node("/root/MainLab")
	var blueprint_manager = root.get_node_or_null("BlueprintManager")
	if blueprint_manager:
		# Auto-save before testing. If save fails (e.g. clipping), block transition!
		var success = blueprint_manager.save_blueprint()
		if not success:
			var ui = get_tree().get_first_node_in_group("stat_ui")
			if ui and ui.has_node("ScrollContainer/VBoxContainer/Title"):
				ui.get_node("ScrollContainer/VBoxContainer/Title").text = "TEST BLOCKED: Resolve Clipping!"
				get_tree().create_timer(3.0).timeout.connect(func():
					if is_instance_valid(ui) and ui.has_node("ScrollContainer/VBoxContainer/Title"):
						ui.get_node("ScrollContainer/VBoxContainer/Title").text = "Blueprint Stats"
				)
			return
	
	# Transition to battlefield
	get_tree().change_scene_to_file("res://scenes/Battlefield.tscn")

func _on_mirror_toggled(button_pressed: bool):
	var root = get_node("/root/MainLab")
	if root and root.has_method("set_mirror_enabled"):
		root.set_mirror_enabled(button_pressed)

func set_mirror_toggle(enabled: bool):
	if mirror_checkbox:
		# Set without triggering the signal to avoid infinite loops
		mirror_checkbox.set_pressed_no_signal(enabled)

func update_stats(hull: Node3D):
	var total_hp = 0.0
	var total_weight = 0.0
	var total_cost_metal = 0
	var total_cost_crystal = 0
	var total_dps = 0.0
	var total_energy_capacity = 0.0

	# Assume the hull itself has some base stats in a real implementation,
	# but for the prototype we'll just sum the modules.
	if hull:
		for child in hull.get_children():
			if child.has_meta("module_data"):
				var data = child.get_meta("module_data") as ModuleData
				if data:
					total_hp += data.get_hp()
					total_weight += data.get_weight()
					total_cost_metal += data.get_cost().x
					total_cost_crystal += data.get_cost().y
					total_dps += data.get_dps()
					if data.category == "generator":
						total_energy_capacity += data.get_energy_capacity()
				
	var hp_mult = 1.0
	var wt_mult = 1.0

	var armor_material = "hardened_steel"
	var armor_thickness = 1.0
	var faction = "industrialists"

	if hull:
		if hull.has_meta("armor_material"):
			armor_material = hull.get_meta("armor_material")
		if hull.has_meta("armor_thickness"):
			armor_thickness = hull.get_meta("armor_thickness")
		if hull.has_meta("faction"):
			faction = hull.get_meta("faction")

	match armor_material:
		"hardened_steel":
			hp_mult = 1.0
			wt_mult = 1.0
		"reactive_armor":
			hp_mult = 1.3
			wt_mult = 1.2
		"ablative_ceramic":
			hp_mult = 1.6
			wt_mult = 0.9
		"energy_shielding":
			hp_mult = 2.0
			wt_mult = 0.5

	# Faction Passive Bonus: Industrialists get 20% less armor weight
	if faction == "industrialists":
		wt_mult *= 0.8

	total_hp = total_hp * hp_mult * armor_thickness
	total_weight = total_weight * wt_mult * armor_thickness

	# Read straight from DamageResolver.ARMOR_TABLE (single source of truth,
	# same as combat) instead of a second hardcoded k_base/t_base/e_base
	# table - the two had drifted: "E:" here used to be a copy-paste of the
	# EXPLOSIVE threshold mislabeled as Energy (damage_resolver.gd had no
	# real "energy" row at all until this pass). Found while scoping the
	# energy-weapon damage_class reclassification work.
	var k_thresh = DamageResolverScript.get_material_threshold(armor_material, "kinetic", armor_thickness).x
	var t_thresh = DamageResolverScript.get_material_threshold(armor_material, "thermal", armor_thickness).x
	var e_thresh = DamageResolverScript.get_material_threshold(armor_material, "energy", armor_thickness).x

	# Stat rounding: total_hp/total_weight/total_dps are sums of
	# module_data.gd getters that already round to the nearest 0.5 at the
	# point they're computed (GlobalConfig.round_to_half), so what's shown
	# here is exactly what combat uses - this %.1f is just consistent
	# formatting (a sum of clean .5-stepped numbers is itself clean), not a
	# second, independent rounding pass. Previously these 4 labels were the
	# one place in this file using bare str() on a float, which is why they
	# alone showed raw float precision (e.g. "14.723891...") while every
	# other label here was already %.1f/%.2f/%d formatted.
	hp_label.text = "Total HP: %.1f" % total_hp
	weight_label.text = "Total Weight: %.1f" % total_weight
	cost_label.text = "Cost: %d Metal, %d Crystal" % [total_cost_metal, total_cost_crystal]
	dps_label.text = "Total DPS: %.1f" % total_dps

	if not energy_label:
		energy_label = Label.new()
		$ScrollContainer/VBoxContainer.add_child(energy_label)
	energy_label.text = "Energy Capacity: +%.1f" % total_energy_capacity
	energy_label.visible = total_energy_capacity > 0.0

	if not armor_threshold_label:
		armor_threshold_label = Label.new()
		# Found by the new headless UI-overflow audit: this label's natural
		# single-line width (305px, "Armor Thresholds: K: 15.0, T: 5.0,
		# E: 10.0") exceeds the sidebar's fixed 210px width - it was
		# silently clipping/spilling past the panel edge (visible in
		# several of today's own verification screenshots as a stray
		# trailing character, never flagged as a bug until now). Word-wrap
		# instead of a hardcoded width, since threshold values can grow to
		# more digits than today's baseline numbers.
		armor_threshold_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		$ScrollContainer/VBoxContainer.add_child(armor_threshold_label)
	armor_threshold_label.text = "Armor Thresholds: K: %.1f, T: %.1f, E: %.1f" % [k_thresh, t_thresh, e_thresh]

func on_module_selected(module: Node3D):
	current_selected_module = module
	
	# Clear old tweaks in the popup tweaks container
	if popup_tweaks_container:
		for child in popup_tweaks_container.get_children():
			child.queue_free()
			
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	
	if hull and (module == null or module == hull or module.name == "Hull"):
		sync_hull_ui(hull)
		if popup_panel: popup_panel.visible = false

	if not locomotion_tweaks: return
	
	if not module or not module.has_meta("module_data"):
		locomotion_tweaks.visible = false
		if popup_panel: popup_panel.visible = false
		return
		
	var data = module.get_meta("module_data")
	
	# Populate Module stats & tweaks into the hovering popup!
	if popup_panel:
		popup_panel.visible = true
		popup_name_label.text = "🛠️ " + data.module_name.to_upper()
		
		var hp = data.get_hp()
		var wt = data.get_weight()
		var cost = data.get_cost()
		var dps = data.get_dps()
		var heal = data.get_heal_rate()
		var last_line = "Heal Rate: %.1f/s" % heal if heal > 0.0 else "DPS: %.1f" % dps
		popup_stats_label.text = "HP: %.1f | Weight: %.1f kg\nCost: %d Metal, %d Crystal\n%s" % [hp, wt, cost.x, cost.y, last_line]
		
	if data.category != "locomotion":
		locomotion_tweaks.visible = false
		_generate_custom_tweaks(module, data)
		return
		
	root = get_node("/root/MainLab")
	hull = root.get_node_or_null("Hull")
	if not hull:
		locomotion_tweaks.visible = false
		return
		
	var type_id = data.type_id
	var settings = {}
	if hull.has_meta("locomotion_settings"):
		settings = hull.get_meta("locomotion_settings")
		
	is_updating_sliders = true
	locomotion_tweaks.visible = true
	
	if type_id == "wheels":
		size_label.text = "Wheel Size:"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("size", 1.0)
		count_slider.value = settings.get("count", 4)
	elif type_id == "tracked_treads":
		size_label.text = "Tread Width:"
		count_container.visible = false
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("width", 1.0)
	elif type_id == "helicopter_rotors":
		size_label.text = "Rotor Size:"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("size", 1.0)
		count_slider.value = settings.get("count", 4)
	elif type_id == "legs":
		size_label.text = "Leg Length:"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("size", 1.0)
		count_slider.value = settings.get("count", 4)
	elif type_id == "anti_grav":
		size_label.text = "Ring Size:"
		count_container.visible = false
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("size", 1.0)
	elif type_id == "hover_engine":
		size_label.text = "Hover Pad Size:"
		count_container.visible = false
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("size", 1.0)
	else:
		locomotion_tweaks.visible = false
		
	is_updating_sliders = false

func _on_size_value_changed(value: float):
	if is_updating_sliders or not current_selected_module: return
	_apply_tweaks()

func _on_count_value_changed(value: float):
	if is_updating_sliders or not current_selected_module: return
	_apply_tweaks()

func _apply_tweaks():
	var root = get_node("/root/MainLab")
	var hull = root.get_node_or_null("Hull")
	if not root or not hull or not current_selected_module: return
	
	var data = current_selected_module.get_meta("module_data")
	var type_id = data.type_id
	var new_settings = {}
	
	if type_id == "wheels":
		new_settings = {
			"size": size_slider.value,
			"count": int(count_slider.value)
		}
	elif type_id == "tracked_treads":
		new_settings = {
			"width": size_slider.value
		}
	elif type_id == "helicopter_rotors":
		new_settings = {
			"size": size_slider.value,
			"count": int(count_slider.value)
		}
	elif type_id == "legs":
		new_settings = {
			"size": size_slider.value,
			"count": int(count_slider.value)
		}
	elif type_id == "anti_grav":
		new_settings = {
			"size": size_slider.value
		}
	elif type_id == "hover_engine":
		new_settings = {
			"size": size_slider.value
		}

	if root.has_method("update_locomotion"):
		# Update positions/scales immediately
		root.update_locomotion(type_id, new_settings)
		# Reselect the new node counterpart to keep selection and UI visible
		var new_selected = null
		for child in hull.get_children():
			if child.has_meta("module_data"):
				var m_data = child.get_meta("module_data")
				if m_data and m_data.type_id == type_id:
					new_selected = child
					break
		if new_selected:
			root.call_deferred("_select_module", new_selected)

func _on_armor_material_selected(index: int):
	if is_updating_sliders: return
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	var hull = root.get_node_or_null("Hull")
	if not hull: return
	_push_undo()

	var mat_name = "hardened_steel"
	match index:
		0: mat_name = "hardened_steel"
		1: mat_name = "reactive_armor"
		2: mat_name = "ablative_ceramic"
		3: mat_name = "energy_shielding"
		
	hull.set_meta("armor_material", mat_name)
	if root.has_method("update_hull_appearance"):
		root.update_hull_appearance()
	update_stats(hull)

func _on_armor_thickness_changed(value: float):
	if is_updating_sliders: return
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	var hull = root.get_node_or_null("Hull")
	if not hull: return
	
	hull.set_meta("armor_thickness", value)
	if armor_thick_label:
		armor_thick_label.text = "Armor Thickness: %.1f" % value
	if root.has_method("update_hull_appearance"):
		root.update_hull_appearance()
	update_stats(hull)

func _on_nose_taper_changed(value: float):
	if is_updating_sliders: return
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	var hull = root.get_node_or_null("Hull")
	if not hull: return

	hull.set_meta("nose_taper", value)
	if nose_taper_label:
		nose_taper_label.text = "Nose Taper: %.2fx" % value
	if root.has_method("update_hull_appearance"):
		root.update_hull_appearance()
	update_stats(hull)

func _on_faction_selected(index: int):
	if is_updating_sliders: return
	var root = get_node_or_null("/root/MainLab")
	if not root: return
	var hull = root.get_node_or_null("Hull")
	if not hull: return
	_push_undo()

	var fac_name = "industrialists"
	match index:
		0: fac_name = "industrialists"
		1: fac_name = "technocrats"
		2: fac_name = "expansionists"
		
	hull.set_meta("faction", fac_name)
	update_stats(hull)

func _initial_sync():
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		if not hull.has_meta("blueprint_name"):
			hull.set_meta("blueprint_name", "Untitled Design")
		sync_hull_ui(hull)

func _on_tweak_changed():
	if current_selected_module and is_instance_valid(current_selected_module):
		VisualBuilder.rebuild_visual(current_selected_module)
		if current_selected_module.has_meta("mirrored_counterpart"):
			var mirror = current_selected_module.get_meta("mirrored_counterpart")
			if mirror and is_instance_valid(mirror):
				VisualBuilder.rebuild_visual(mirror)
				
	var root = get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		update_stats(hull)
		# Update popup stats label text too
		if current_selected_module and is_instance_valid(current_selected_module) and current_selected_module.has_meta("module_data"):
			var data = current_selected_module.get_meta("module_data")
			if popup_stats_label:
				var hp = data.get_hp()
				var wt = data.get_weight()
				var cost = data.get_cost()
				var dps = data.get_dps()
				var heal = data.get_heal_rate()
				var last_line = "Heal Rate: %.1f/s" % heal if heal > 0.0 else "DPS: %.1f" % dps
				popup_stats_label.text = "HP: %.1f | Weight: %.1f kg\nCost: %d Metal, %d Crystal\n%s" % [hp, wt, cost.x, cost.y, last_line]
		var placer = root.get_node_or_null("ModulePlacer") if root else null
		if placer:
			placer.check_all_clipping()

const ARMOR_MATERIALS = ["hardened_steel", "reactive_armor", "ablative_ceramic", "energy_shielding"]
const ARMOR_MATERIAL_LABELS = ["Hardened Steel", "Reactive Armor", "Ablative Ceramic", "Energy Shielding"]

func _generate_custom_tweaks(module: Node3D, data: ModuleData):
	if not popup_tweaks_container: return
	var type_id = data.type_id

	# Per-module armor material (Armor phase 3, MOUNTING_AND_ARMOR_SPEC.md
	# addendum): each placed armor plate can pick its own material - a
	# front plate can be reactive while the sides are ablative, instead of
	# one material for the whole hull. Not TWEAK_SPECS-driven since it's a
	# material choice, not a numeric slider; stored in the same tweaks dict
	# so it rides the existing save/load path for free.
	if data.category == "armor":
		var mat_container = VBoxContainer.new()
		mat_container.add_theme_constant_override("separation", 2)
		popup_tweaks_container.add_child(mat_container)

		var mat_label = Label.new()
		var current_mat = data.tweaks.get("material", "hardened_steel")
		var current_idx = ARMOR_MATERIALS.find(current_mat)
		if current_idx < 0: current_idx = 0
		mat_label.text = "Plate Material: %s" % ARMOR_MATERIAL_LABELS[current_idx]
		mat_container.add_child(mat_label)

		var mat_btn = OptionButton.new()
		for lbl in ARMOR_MATERIAL_LABELS:
			mat_btn.add_item(lbl)
		mat_btn.selected = current_idx
		mat_container.add_child(mat_btn)
		mat_btn.item_selected.connect(func(index: int):
			_push_undo()
			data.tweaks["material"] = ARMOR_MATERIALS[index]
			mat_label.text = "Plate Material: %s" % ARMOR_MATERIAL_LABELS[index]
			_on_tweak_changed()
		)

	if not TWEAK_SPECS.has(type_id): return

	var specs = TWEAK_SPECS[type_id]
	for spec in specs:
		var container = VBoxContainer.new()
		container.add_theme_constant_override("separation", 2)
		popup_tweaks_container.add_child(container)
		
		var label = Label.new()
		container.add_child(label)
		
		if spec.get("type", "") == "bool":
			var check = CheckButton.new()
			check.text = spec.label
			check.button_pressed = data.tweaks.get(spec.name, spec.default)
			container.add_child(check)
			
			label.text = "%s: %s" % [spec.label, "ENABLED" if check.button_pressed else "DISABLED"]
			
			check.toggled.connect(func(pressed):
				_push_undo()
				data.tweaks[spec.name] = pressed
				label.text = "%s: %s" % [spec.label, "ENABLED" if pressed else "DISABLED"]
				_on_tweak_changed()
			)
		else:
			var slider = HSlider.new()
			slider.min_value = spec.min
			slider.max_value = spec.max
			slider.step = spec.step
			slider.value = data.tweaks.get(spec.name, spec.default)
			container.add_child(slider)

			if spec.step == 1.0:
				label.text = "%s: %d" % [spec.label, int(slider.value)]
			else:
				label.text = "%s: %.2fx" % [spec.label, slider.value]

			slider.drag_started.connect(_push_undo)
			slider.value_changed.connect(func(val):
				data.tweaks[spec.name] = val
				if spec.step == 1.0:
					label.text = "%s: %d" % [spec.label, int(val)]
				else:
					label.text = "%s: %.2fx" % [spec.label, val]
				_on_tweak_changed()
			)

func _process(delta):
	if popup_panel and popup_panel.visible and is_instance_valid(current_selected_module) and current_selected_module != null and current_selected_module.name != "Hull":
		var camera = get_viewport().get_camera_3d()
		if camera:
			var pos_3d = current_selected_module.global_position
			var offset_pos_3d = pos_3d + Vector3(0, 0.85, 0)
			var pos_2d = camera.unproject_position(offset_pos_3d)
			popup_panel.global_position = pos_2d - Vector2(popup_panel.size.x / 2.0, popup_panel.size.y)
