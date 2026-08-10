extends Control
# AAA Main Menu Rearchitecture.
# Features:
#   * Live 3D Hangar Background: A SubViewport rendering a rotating 3D turntable
#     with studio key/rim lighting, SSAO, and ACES Filmic tonemapping.
#   * 30-Second Showcase Cycling: The 3D rotating object on the background turntable
#     automatically jumps between saved player blueprints and available hull chassis
#     types every 30 seconds (or on manual button click).
#   * Synchronized 2D Telemetry Placard: The right-side Procurement Specification Placard
#     updates dynamically in real-time to match the exact 3D vehicle currently showcased on the turntable!
#   * Asymmetric AAA Command Deck: Modern left-aligned navigation with animated cards,
#     glowing active indicators, and audio feedback on hover/click.

const UITheme = preload("res://scripts/ui_theme.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const FactionCatalog = preload("res://scripts/faction_catalog.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")
const SpecPlacardScript = preload("res://scripts/ui/spec_placard.gd")
const WordmarkScript = preload("res://scripts/ui/wordmark.gd")
const DesignStatsScript = preload("res://scripts/design_stats.gd")

const TITLE := "KITBASH COMMAND"
const TAGLINE := "Design bureau and proving ground"
const ROSTER_CAP := 15
const SHOWCASE_CYCLE_INTERVAL := 30.0

const FALLBACK_HULL_TYPES := [
	"medium_hull",
	"heavy_hull",
	"scout_hull",
	"flying_wing_hull",
	"super_heavy_hull",
	"light_hull",
	"tri_hull",
	"pillbox_foundation"
]

# UX_REDESIGN_PLAN.md's target information architecture: three activities plus
# a system layer, replacing seven equal-weight cards with none of them
# answering "which do I press first". First-run still shows exactly one card
# (see _build_left_column) regardless of what is declared here - GROUPS is the
# steady-state menu a returning player sees.
const GROUPS := [
	{
		"section": "DEPLOY",
		"items": [
			{
				"title": "SKIRMISH",
				"desc": "Select a map and a roster, then engage enemy forces.",
				"scene": "res://scenes/MatchSetup.tscn",
				"badge": "COMBAT // SKIRMISH"
			},
			{
				"title": "OPERATIONS",
				"desc": "Three to twelve engagements. Re-draft your roster between each.",
				"scene": "res://scenes/OperationsSetup.tscn",
				"badge": "TAC // CAMPAIGN"
			},
			{
				"title": "PROVING GROUND",
				"desc": "Field the current design against target dummies.",
				"scene": "res://scenes/Battlefield.tscn",
				"badge": "TEST // RANGE"
			},
		],
	},
	{
		"section": "DESIGN",
		"items": [
			{
				"title": "DESIGN LAB",
				"desc": "Assemble blueprints from hulls, modules and drives.",
				"scene": "res://scenes/MainLab.tscn",
				"badge": "SYS // BUILD"
			},
			{
				"title": "BLUEPRINT LIBRARY",
				"desc": "Browse, manage, and preview your vehicle designs.",
				"scene": "res://scenes/BlueprintLibrary.tscn",
				"badge": "SYS // ARCHIVE"
			},
			{
				"title": "HULL AUTHORING",
				"desc": "Shape new hull forms from primitives.",
				"scene": "res://scenes/HullBuilder.tscn",
				"badge": "CAD // MESH"
			},
		],
	},
]

# First-run card, shown INSTEAD of GROUPS until the player has completed (or
# skipped) the tutorial once - "no seven-door problem when there is one door".
# Routes to the Lab like any other card; the only difference is arming
# TutorialManager on the way, and the Lab is where the guided loop starts.
const TUTORIAL_CARD := {
	"title": "BUILD YOUR FIRST VEHICLE",
	"desc": "Fifteen guided steps, then field it under fire.",
	"scene": "res://scenes/MainLab.tscn",
	"badge": "SYS // TRAINING",
	"tutorial": true
}

# WHICH RUNTIME EACH COMBAT DESTINATION ACTUALLY REACHES, because it is not
# obvious from the scene paths above and there are two unit scripts in the tree.
#
#   SKIRMISH        MatchSetup.tscn      -> Battle.tscn -> battle/match_director.gd
#   OPERATIONS      OperationsSetup.tscn -> Battle.tscn -> battle/match_director.gd
#   PROVING GROUND  Battlefield.tscn     -> battlefield.gd
#
# Skirmish and Operations both run the battle layer (scripts/battle/), whose
# units are battle/units/unit.gd. There is no older controller underneath them:
# skirmish.gd and Skirmish.tscn were deleted outright when the battle layer
# reached parity, and nothing in scripts/battle/ references the legacy unit.
#
# THE PROVING GROUND IS THE EXCEPTION, and it is the one worth knowing about.
# battlefield.gd still runs the legacy battle_unit.gd for both the player
# vehicle and the target dummies. It reaches it through a runtime
# `load("res://scripts/battle_unit.gd")` rather than a preload, so a search for
# preloads finds only test files and the script looks dead when it is not.
#
# The practical consequence: any unit-level mechanic added to one script and not
# the other works in Skirmish and silently does nothing in the Test Range, or
# the reverse. The Resource Bay's cargo capacity, the power budget and the
# brownout are all deliberately implemented in both for exactly this reason -
# see the shared helpers they route through (ModuleCatalog.resource_bay_capacity,
# PowerBudget.analyze) rather than duplicating the arithmetic.
#
# This block replaces a comment describing the battle layer as a work in
# progress listed "BESIDE Skirmish" that would take its name at parity. That
# already happened; the entry it documented no longer exists.

var _turntable_node: Node3D = null
var _turntable_model_container: Node3D = null
var _showcase_vehicle: Node3D = null
var _spec_placard: Control = null
var _showcase_items: Array = []
var _current_showcase_index: int = 0
var _showcase_timer: float = 0.0

func _ready() -> void:
	_gather_showcase_items()

	# Build live 3D Hangar SubViewport background if not running headless
	if DisplayServer.get_name() != "headless":
		_build_3d_background()

	# Main 2D UI Overlay
	var frame := UIShell.screen_frame(self)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", Tokens.SPACE_LG)
	frame.add_child(root_vbox)

	_build_console_bar(root_vbox)

	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", Tokens.SPACE_XL)
	root_vbox.add_child(columns)

	_build_left_column(columns)

	# Flexible middle space to frame the rotating 3D showcase unit
	var center_space = Control.new()
	center_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(center_space)

	_build_status_column(columns)

	# Initial 3D & Placard sync
	_update_showcase_display()

	# THE FIRST MUSIC CALL THE GAME HAS EVER MADE. AudioManager.play_music()
	# existed for the whole life of the project with zero callers anywhere, so
	# the menu track shipped unreachable. Safe to call unconditionally: the
	# manager no-ops on a repeat request and when running headless.
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.play_music("menu")

func _process(delta: float) -> void:
	if is_instance_valid(_turntable_node):
		_turntable_node.rotation.y += 0.25 * delta

	# 30-Second Showcase Cycle Timer
	_showcase_timer += delta
	if _showcase_timer >= SHOWCASE_CYCLE_INTERVAL:
		_showcase_timer = 0.0
		_next_showcase_item()

func _gather_showcase_items() -> void:
	_showcase_items.clear()

	# 1. Saved Player Blueprints, MOST RECENT FIRST - "the player's latest
	# design on the turntable rather than a stock chassis" (UX_REDESIGN_PLAN.md
	# Phase 2). Sorted by the file's own mtime rather than roster order, which
	# reflects nothing about recency.
	var mgr = BlueprintManagerScript.new()
	var roster: Array = mgr.list_blueprints(true)
	var blueprint_entries: Array = []
	for entry in roster:
		var path := str(entry.get("path", ""))
		if path != "":
			var full_bp: Dictionary = mgr.load_blueprint(path)
			if not full_bp.is_empty():
				blueprint_entries.append({
					"type": "blueprint",
					"name": entry.get("name", "UNNAMED DESIGN"),
					"blueprint": full_bp,
					"summary": entry,
					"mtime": FileAccess.get_modified_time(path),
				})
	blueprint_entries.sort_custom(func(a, b): return a["mtime"] > b["mtime"])
	_showcase_items.append_array(blueprint_entries)

	# 2. Add Standard Hull Chassis types so there is always a rich variety
	for hull_id in FALLBACK_HULL_TYPES:
		_showcase_items.append({
			"type": "hull",
			"name": _prettify(hull_id).to_upper() + " CHASSIS",
			"hull_type": hull_id
		})

	_current_showcase_index = 0

func _next_showcase_item() -> void:
	if _showcase_items.is_empty():
		return
	_current_showcase_index = (_current_showcase_index + 1) % _showcase_items.size()
	_update_showcase_display()

func _update_showcase_display() -> void:
	if _showcase_items.is_empty():
		return

	var item: Dictionary = _showcase_items[_current_showcase_index]

	# Update 3D Model on Turntable
	if is_instance_valid(_turntable_model_container):
		for child in _turntable_model_container.get_children():
			child.queue_free()
		_build_3d_showcase_model(item, _turntable_model_container)

	# Update 2D Specification Placard UI
	_update_placard_ui(item)

func _build_3d_background() -> void:
	var vp_container = SubViewportContainer.new()
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp_container)

	var vp = SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp_container.add_child(vp)

	var scene = Node3D.new()
	vp.add_child(scene)

	# Studio WorldEnvironment (ACES Filmic, SSAO, Glow)
	# Studio WorldEnvironment (Featureless Studio Grey, ACES Filmic, SSAO)
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.38, 0.40, 0.42, 1.0) # Featureless studio grey
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.4
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.08
	env_node.environment = env
	scene.add_child(env_node)

	# Main Key Light
	var sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.35
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)

	# Cool Fill Light
	var rim = DirectionalLight3D.new()
	rim.light_color = Color(0.65, 0.75, 0.85)
	rim.light_energy = 0.85
	rim.rotation_degrees = Vector3(25, 145, 0)
	scene.add_child(rim)

	# Camera framed at center turntable - Zoomed way farther out
	var cam = Camera3D.new()
	cam.position = Vector3(1.2, 4.8, 15.5)
	cam.rotation_degrees = Vector3(-16, 12, 0)
	cam.fov = 46.0
	scene.add_child(cam)

	# Turntable Base & Model Container
	_turntable_node = Node3D.new()
	_turntable_node.position = Vector3(0.5, -0.4, 0.0)
	scene.add_child(_turntable_node)

	var platform_mesh = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 4.8
	cyl.bottom_radius = 5.2
	cyl.height = 0.4
	platform_mesh.mesh = cyl
	platform_mesh.position = Vector3(0, -0.2, 0)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.32, 0.34, 1.0)
	mat.metallic = 0.2
	mat.roughness = 0.65
	platform_mesh.material_override = mat
	_turntable_node.add_child(platform_mesh)

	_turntable_model_container = Node3D.new()
	_turntable_node.add_child(_turntable_model_container)

func _build_3d_showcase_model(item: Dictionary, parent: Node3D) -> void:
	var model_root = Node3D.new()
	model_root.position = Vector3(0, 0.1, 0)

	var item_type: String = item.get("type", "hull")
	_showcase_vehicle = null

	if item_type == "blueprint":
		var bp: Dictionary = item.get("blueprint", {})
		var mgr = BlueprintManagerScript.new()
		var vehicle = mgr.reconstruct_vehicle(bp, model_root, true)
		if vehicle == null:
			var hull_id := str(bp.get("hull_type", "medium_hull"))
			_build_hull_mesh_node(hull_id, model_root)
		else:
			# Kept for the SpecPlacard sync below - the SAME live node
			# DesignStats.analyze() reads elsewhere (the Lab rail, the battle
			# selection panel), so the Front Desk placard shows the identical
			# weight/speed/dps/range figures rather than a re-derivation.
			_showcase_vehicle = vehicle
	else:
		var hull_id: String = item.get("hull_type", "medium_hull")
		_build_hull_mesh_node(hull_id, model_root)

	# Apply uniform matte greenish-grey plastic finish (unpainted scale model sprue look)
	_apply_unpainted_scale_model_material(model_root)

	parent.add_child(model_root)

func _build_hull_mesh_node(hull_id: String, parent: Node3D) -> void:
	var mesh = MeshAssetLoader.get_hull_mesh(hull_id)
	var hull_data = ModuleCatalogScript.get_module_data(hull_id)
	var dim: Vector3 = hull_data.get("dimensions", Vector3(3.8, 1.1, 5.4))

	var mesh_inst = MeshInstance3D.new()
	if mesh != null:
		mesh_inst.mesh = mesh
	else:
		var box = BoxMesh.new()
		box.size = dim
		mesh_inst.mesh = box

	mesh_inst.position = Vector3(0, dim.y * 0.5, 0)
	parent.add_child(mesh_inst)

func _apply_unpainted_scale_model_material(node: Node, mat: StandardMaterial3D = null) -> void:
	# Don't overwrite alpha-cutout greeble cards (which are quads) with a solid opaque material.
	if node.name == "HullGreebles":
		return
		
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.38, 0.44, 0.37, 1.0) # Unpainted scale model greenish-grey plastic
		mat.metallic = 0.0
		mat.roughness = 0.8

	if node is GeometryInstance3D:
		node.material_override = mat
		node.material_overlay = null
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			node.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_unpainted_scale_model_material(child, mat)

func _build_console_bar(parent: Control) -> void:
	var bar = PanelContainer.new()
	bar.theme_type_variation = "HeaderPanel"
	parent.add_child(bar)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_right", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_top", Tokens.SPACE_XS)
	margin.add_theme_constant_override("margin_bottom", Tokens.SPACE_XS)
	bar.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", Tokens.SPACE_MD)
	margin.add_child(hbox)

	var ident = Label.new()
	ident.text = "DESIGN BUREAU / CONSOLE 04"
	ident.theme_type_variation = "HintLabel"
	ident.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
	hbox.add_child(ident)

	var divider = Label.new()
	divider.text = "//"
	divider.theme_type_variation = "HintLabel"
	hbox.add_child(divider)

	var status = Label.new()
	status.text = "STATUS: OPERATIONAL"
	status.theme_type_variation = "HintLabel"
	status.add_theme_color_override("font_color", Tokens.SIGNAL_GO)
	hbox.add_child(status)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var cycle_notice = Label.new()
	cycle_notice.text = "3D SHOWCASE CYCLE: 30S ROTATION"
	cycle_notice.theme_type_variation = "HintLabel"
	cycle_notice.add_theme_color_override("font_color", Tokens.SIGNAL_INFO)
	hbox.add_child(cycle_notice)

func _build_left_column(parent: Control) -> void:
	var col = VBoxContainer.new()
	col.custom_minimum_size = Vector2(520, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", Tokens.SPACE_SM)
	parent.add_child(col)

	var mark := WordmarkScript.new()
	mark.lockup = WordmarkScript.Lockup.HORIZONTAL
	mark.part_number = TAGLINE.to_upper()
	col.add_child(mark)

	var gap_top = Control.new()
	gap_top.custom_minimum_size = Vector2(0, Tokens.SPACE_MD)
	col.add_child(gap_top)

	var nav = VBoxContainer.new()
	nav.add_theme_constant_override("separation", Tokens.SPACE_MD)
	col.add_child(nav)

	var tutorial_manager = get_node_or_null("/root/TutorialManager")
	var first_run: bool = tutorial_manager == null or not tutorial_manager.has_been_seen()

	if first_run:
		# "No seven-door problem when there is one door" - a returning player
		# who explicitly wants the full menu can still reach it via SYSTEM ->
		# Replay training once that exists (Phase 7); until then, finishing or
		# skipping the tutorial is what unlocks GROUPS below.
		var single := VBoxContainer.new()
		single.add_theme_constant_override("separation", Tokens.SPACE_SM)
		nav.add_child(single)
		_add_destination_card(single, TUTORIAL_CARD["title"], TUTORIAL_CARD["desc"],
			TUTORIAL_CARD["scene"], TUTORIAL_CARD["badge"], true)
	else:
		for group in GROUPS:
			_add_section_header(nav, group["section"])
			var section := VBoxContainer.new()
			section.add_theme_constant_override("separation", Tokens.SPACE_SM)
			nav.add_child(section)
			for item in group["items"]:
				_add_destination_card(section, item["title"], item["desc"],
					item["scene"], item["badge"], item.get("tutorial", false))

	var gap_bottom = Control.new()
	gap_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap_bottom)

	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	col.add_child(bottom_row)

	var records_btn = Button.new()
	records_btn.text = "RECORDS"
	records_btn.custom_minimum_size = Vector2(140, 44)
	UIFeedbackScript.wire(records_btn)
	records_btn.pressed.connect(func():
		var router = get_node_or_null("/root/SceneRouter")
		if router:
			router.goto("res://scenes/BlueprintLibrary.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/BlueprintLibrary.tscn")
	)
	bottom_row.add_child(records_btn)

	var settings_btn = Button.new()
	settings_btn.text = "SYSTEM"
	settings_btn.custom_minimum_size = Vector2(140, 44)
	UIFeedbackScript.wire(settings_btn)
	settings_btn.pressed.connect(func():
		var system_layer = get_node_or_null("/root/SystemLayer")
		if system_layer:
			system_layer.open()
	)
	bottom_row.add_child(settings_btn)

	var quit_btn = Button.new()
	quit_btn.text = "EXIT BUREAU"
	quit_btn.custom_minimum_size = Vector2(180, 44)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# UIFeedback.wire() supplies the hover sound, the hover lift and the press
	# response in one call - replacing a press-audio lambda plus a whole separate
	# mouse_entered lambda that existed only to play a hover sound.
	UIFeedbackScript.wire(quit_btn)
	quit_btn.pressed.connect(func(): get_tree().quit())
	bottom_row.add_child(quit_btn)


# A stamped, non-clickable L3 section label - "everything stays one click
# deep" per UX_REDESIGN_PLAN.md, so these organise rather than navigate.
func _add_section_header(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "HintLabel"
	label.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
	parent.add_child(label)

func _add_destination_card(parent: Control, title_text: String, description: String, scene_path: String, badge_text: String, is_tutorial: bool = false) -> void:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 64)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Industrial shaped outlines and dark fill gradient styleboxes
	# NavCard is now a registered theme variation (see build_ui_theme.gd), so the
	# four per-instance stylebox overrides this used to build are gone. Those
	# overrides also carried hardcoded cool blue-greys that appear nowhere in the
	# palette - a local override always beats the theme, so they were actively
	# holding the design system out of the most prominent control in the game.
	btn.theme_type_variation = "NavCard"
	parent.add_child(btn)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_SM)
	margin.add_theme_constant_override("margin_right", Tokens.SPACE_SM)
	margin.add_theme_constant_override("margin_top", Tokens.SPACE_XS)
	margin.add_theme_constant_override("margin_bottom", Tokens.SPACE_XS)
	btn.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", Tokens.SPACE_MD)
	margin.add_child(hbox)

	var indicator = ColorRect.new()
	indicator.custom_minimum_size = Vector2(5, 0)
	indicator.color = Tokens.SIGNAL_HAZARD
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.modulate.a = 0.0
	hbox.add_child(indicator)

	var stack = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	hbox.add_child(stack)

	var name_label = Label.new()
	name_label.text = title_text
	name_label.theme_type_variation = "HeadingLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(name_label)

	var desc_label = Label.new()
	desc_label.text = description
	desc_label.theme_type_variation = "HintLabel"
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(desc_label)

	# Industrial Badge Plate
	var badge_panel = PanelContainer.new()
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b_sb = StyleBoxFlat.new()
	b_sb.bg_color = Color(0.08, 0.09, 0.10, 0.8)
	b_sb.border_color = Color(0.35, 0.38, 0.42, 0.7)
	b_sb.set_border_width_all(1)
	b_sb.set_content_margin_all(4)
	badge_panel.add_theme_stylebox_override("panel", b_sb)

	var badge = Label.new()
	badge.text = badge_text
	badge.theme_type_variation = "HintLabel"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	badge_panel.add_child(badge)
	hbox.add_child(badge_panel)

	UIFeedbackScript.wire(btn)
	btn.pressed.connect(func():
		# Armed BEFORE the route, so the Lab's own first-run check sees an active
		# run and stands down rather than stacking its offer on top of it.
		if is_tutorial:
			var tutorial = get_node_or_null("/root/TutorialManager")
			if tutorial:
				tutorial.begin()
		# Through the router so the destination arrives on a fade, and so the
		# router decides whether this target needs the loading screen - the call
		# site no longer has to know which scenes stall.
		var router = get_node_or_null("/root/SceneRouter")
		if router:
			router.goto(scene_path)
		else:
			get_tree().change_scene_to_file(scene_path)
	)
	# Indicator only - the hover SOUND and lift come from UIFeedback.wire() above.
	btn.mouse_entered.connect(func():
		indicator.modulate.a = 1.0
	)
	btn.mouse_exited.connect(func():
		indicator.modulate.a = 0.0
	)

# _create_industrial_button_style() was here. Replaced by the NavCard theme
# variation, which expresses the same asymmetric left gutter through a registered
# flat stylebox instead of a per-instance one.

func _build_status_column(parent: Control) -> void:
	var col = VBoxContainer.new()
	col.custom_minimum_size = Vector2(460, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_theme_constant_override("separation", Tokens.SPACE_SM)
	parent.add_child(col)

	var heading_hbox = HBoxContainer.new()
	col.add_child(heading_hbox)

	var heading = Label.new()
	heading.text = "SPECIFICATION PLACARD"
	heading.theme_type_variation = "HeadingLabel"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_hbox.add_child(heading)

	# Manual Cycle Button
	var cycle_btn = Button.new()
	cycle_btn.text = "ROTATE HULL ▶"
	cycle_btn.custom_minimum_size = Vector2(130, 28)
	UIFeedbackScript.wire(cycle_btn)
	cycle_btn.pressed.connect(func():
		_showcase_timer = 0.0
		_next_showcase_item()
	)
	heading_hbox.add_child(cycle_btn)

	# SpecPlacard.Level.FRONT_DESK: the same widget the Lab rail, the battle
	# selection panel and the after-action report render, at the detail level
	# this screen wants (UX_REDESIGN_PLAN.md's "unifying component"). Replaces
	# a hand-built stat table that was this screen's own private vocabulary.
	_spec_placard = SpecPlacardScript.new()
	_spec_placard.level = SpecPlacardScript.Level.FRONT_DESK
	_spec_placard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_spec_placard)

func _update_placard_ui(item: Dictionary) -> void:
	if _spec_placard == null:
		return

	var item_type: String = item.get("type", "hull")
	var design_name := str(item.get("name", "UNKNOWN")).to_upper()

	if item_type == "blueprint":
		var bp: Dictionary = item.get("blueprint", {})
		var stats: Dictionary = {}
		if _showcase_vehicle != null and is_instance_valid(_showcase_vehicle):
			stats = DesignStatsScript.analyze(_showcase_vehicle)
		_spec_placard.from_blueprint(design_name, "CERTIFIED PLAYER BLUEPRINT", bp, stats)
	else:
		var hull_id: String = item.get("hull_type", "medium_hull")
		_spec_placard.from_blueprint(design_name, "STANDARD BUREAU CHASSIS // READY FOR ASSEMBLY",
			{"hull_type": hull_id})

func _prettify(id: String) -> String:
	if id == "":
		return "-"
	return id.replace("_", " ").capitalize()
