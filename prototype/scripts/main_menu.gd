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
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")
const SpecPlacardScript = preload("res://scripts/ui/spec_placard.gd")
const WordmarkScript = preload("res://scripts/ui/wordmark.gd")
const DesignStatsScript = preload("res://scripts/design_stats.gd")
# Test Range launcher (battle-system unification Phase 3). Same launcher the
# Design Lab's "Test in Arena" button uses, so the two entry points cannot
# drift on which map, which dummies, and which rule set the Test Range actually
# boots with. The card data declares a `launcher` field; the destination card's
# pressed handler routes through it instead of the legacy scene path.
const TestRangeLauncherScript = preload("res://scripts/test_range_launcher.gd")
const TwoPhaseTutorialManagerScript = preload("res://scripts/tutorial_two_phase/two_phase_tutorial_manager.gd")

const TITLE := "KITBASH COMMAND"
const TAGLINE := "Design bureau and proving ground"
const SHOWCASE_CYCLE_INTERVAL := 30.0

const FALLBACK_HULL_TYPES := [
	"brenntal_medium_a",
	"block_heavy_meridian_a",
	"wedge_scout_meridian_a",
	"flying_wing_hull",
	"super_heavy_hull",
	"kestrel_scout_a",
	"tri_hull",
	"bunker_main_meridian"
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
				# launcher wins over scene: the Test Range entry point
				# resolves the player blueprint, builds a MatchRuleSet, and
				# routes through SceneRouter. The fallback below is what the
				# card lands on if `launcher` is ever removed, so it has to be
				# a scene that exists - it used to name Battlefield.tscn, which
				# was DELETED in the 2026-08-10 unification (DECISIONS.md §7),
				# making the one entry that existed to prevent a broken route
				# the only broken route in this table. Battle.tscn is both real
				# and what TestRangeLauncher routes to anyway.
				"launcher": "TestRangeLauncher",
				"scene": "res://scenes/Battle.tscn",
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
			{
				"title": "BLOCK HULL BUILDER",
				"desc": "Modular grid-based brick hull suite with strict snapping and CSG weld.",
				"scene": "res://scenes/ModularHullBuilder.tscn",
				"badge": "CAD // BLOCKS (NEW)"
			},
		],
	},
	{
		"section": "TRAINING",
		"items": [
			{
				"title": "TUTORIAL",
				"desc": "Experience defeat with weak units, then build one that wins. Two phases.",
				"scene": "res://scenes/MainLab.tscn",
				"badge": "SYS // TRAINING",
				"tutorial": true
			},
		],
	},
]

# Tutorial card for the TRAINING section - always visible
const TUTORIAL_CARD := {
	"title": "TUTORIAL",
	"desc": "Experience defeat with weak units, then build one that wins. Two phases.",
	"scene": "res://scenes/MainLab.tscn",
	"badge": "SYS // TRAINING",
	"tutorial": true
}

# WHICH RUNTIME EACH COMBAT DESTINATION ACTUALLY REACHES, because it is not
# obvious from the scene paths above.
#
#   SKIRMISH        MatchSetup.tscn       -> Battle.tscn -> battle/match_director.gd
#   OPERATIONS      OperationsSetup.tscn  -> Battle.tscn -> battle/match_director.gd
#   PROVING GROUND  (TestRangeLauncher)   -> Battle.tscn -> battle/match_director.gd
#
# All three reach the same battle layer (scripts/battle/), whose units are
# battle/units/unit.gd. There is no second unit script in the tree: the
# legacy battlefield.gd / battle_unit.gd / player_vehicle.gd / target_dummy.gd
# set was retired on 2026-08-10 in the unification's Phase 4. The
# per-mode gating is a MatchRuleSet that match_director.gd reads at _ready;
# see scripts/match_rule_set.gd and tests/battle/test_match_rule_set_integration.gd
# for the rules. TestRangeLauncher is a Node (not a static helper) so the
# SceneRouter routes through it the same way every other launcher does,
# and the Main Menu's PROVING GROUND card and the Design Lab's
# "Test in Arena" button share one function.
#
# This block replaces a comment describing the battle layer as a work in
# progress listed "BESIDE Skirmish" that would take its name at parity, and
# a follow-up about "THE PROVING GROUND IS THE EXCEPTION" that documented
# the now-retired Battlefield.tscn / battle_unit.gd split. Both
# superseded; the unification finished in 2026-08-10.

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
	root_vbox.add_theme_constant_override("separation", Tokens.SPACE_MD)
	frame.add_child(root_vbox)

	# Top Navigation Ribbon
	_build_top_ribbon(root_vbox)

	# Center Middle Space for 3D Turntable & Upper-Right Spec Placard
	var mid_row = HBoxContainer.new()
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_row.add_theme_constant_override("separation", Tokens.SPACE_LG)
	root_vbox.add_child(mid_row)

	var center_space = Control.new()
	center_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid_row.add_child(center_space)

	_build_status_column(mid_row)

	# Bottom Command Deck Band (Height: 224)
	_build_bottom_deck(root_vbox)

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
			var hull_id := str(bp.get("hull_type", "brenntal_medium_a"))
			_build_hull_mesh_node(hull_id, model_root)
		else:
			# Kept for the SpecPlacard sync below - the SAME live node
			# DesignStats.analyze() reads elsewhere (the Lab rail, the battle
			# selection panel), so the Front Desk placard shows the identical
			# weight/speed/dps/range figures rather than a re-derivation.
			_showcase_vehicle = vehicle
	else:
		var hull_id: String = item.get("hull_type", "brenntal_medium_a")
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

var _active_tab: String = "DEPLOY"
var _category_flows: Dictionary = {}

func _build_top_ribbon(parent: Control) -> void:
	var ribbon = PanelContainer.new()
	ribbon.theme_type_variation = "HeaderPanel"
	ribbon.custom_minimum_size = Vector2(0, 36)
	parent.add_child(ribbon)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_right", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_top", Tokens.SPACE_XS)
	margin.add_theme_constant_override("margin_bottom", Tokens.SPACE_XS)
	ribbon.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", Tokens.SPACE_MD)
	margin.add_child(hbox)

	var mark := WordmarkScript.new()
	mark.lockup = WordmarkScript.Lockup.HORIZONTAL
	mark.part_number = "DESIGN BUREAU & PROVING GROUND"
	hbox.add_child(mark)

	var sep = Label.new()
	sep.text = "//"
	sep.theme_type_variation = "HintLabel"
	hbox.add_child(sep)

	var status = Label.new()
	status.text = "STATUS: OPERATIONAL"
	status.theme_type_variation = "HintLabel"
	status.add_theme_color_override("font_color", Tokens.SIGNAL_GO)
	hbox.add_child(status)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var records_btn = Button.new()
	records_btn.text = "RECORDS"
	records_btn.custom_minimum_size = Vector2(100, 28)
	UIFeedbackScript.wire(records_btn)
	records_btn.pressed.connect(func():
		var router = get_node_or_null("/root/SceneRouter")
		if router: router.goto("res://scenes/BlueprintLibrary.tscn")
		else: get_tree().change_scene_to_file("res://scenes/BlueprintLibrary.tscn")
	)
	hbox.add_child(records_btn)

	var livery_btn = Button.new()
	livery_btn.text = "LIVERY"
	livery_btn.custom_minimum_size = Vector2(100, 28)
	UIFeedbackScript.wire(livery_btn)
	livery_btn.pressed.connect(func():
		var router = get_node_or_null("/root/SceneRouter")
		if router: router.goto("res://scenes/Livery.tscn")
		else: get_tree().change_scene_to_file("res://scenes/Livery.tscn")
	)
	hbox.add_child(livery_btn)

	var settings_btn = Button.new()
	settings_btn.text = "SYSTEM"
	settings_btn.custom_minimum_size = Vector2(100, 28)
	UIFeedbackScript.wire(settings_btn)
	settings_btn.pressed.connect(func():
		var system_layer = get_node_or_null("/root/SystemLayer")
		if system_layer: system_layer.open()
	)
	hbox.add_child(settings_btn)

	var quit_btn = Button.new()
	quit_btn.text = "EXIT"
	quit_btn.custom_minimum_size = Vector2(80, 28)
	quit_btn.theme_type_variation = "DangerButton"
	UIFeedbackScript.wire(quit_btn)
	quit_btn.pressed.connect(func(): get_tree().quit())
	hbox.add_child(quit_btn)


func _build_bottom_deck(parent: Control) -> void:
	var deck = PanelContainer.new()
	deck.theme_type_variation = "CardPanel"
	deck.custom_minimum_size = Vector2(0, 224)
	deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(deck)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", Tokens.SPACE_SM)
	deck.add_child(inner)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", Tokens.SPACE_XS)
	tab_row.custom_minimum_size = Vector2(0, 32)
	inner.add_child(tab_row)

	var content_deck = Control.new()
	content_deck.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(content_deck)

	for group in GROUPS:
		var sec_name: String = group["section"]
		var tab_btn = Button.new()
		tab_btn.text = sec_name
		tab_btn.toggle_mode = true
		tab_btn.button_pressed = (sec_name == _active_tab)
		tab_btn.custom_minimum_size = Vector2(150, 32)
		tab_btn.theme_type_variation = "TabButton"
		UIFeedbackScript.wire(tab_btn, "select")
		tab_row.add_child(tab_btn)

		var scroll = ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.visible = (sec_name == _active_tab)
		content_deck.add_child(scroll)
		_category_flows[sec_name] = scroll

		var flow = HBoxContainer.new()
		flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("separation", Tokens.SPACE_MD)
		scroll.add_child(flow)

		for item in group["items"]:
			_add_deck_card(flow, item["title"], item["desc"],
				item["scene"], item["badge"], item.get("tutorial", false),
				item.get("launcher", ""))

		tab_btn.pressed.connect(func():
			_active_tab = sec_name
			for s in _category_flows:
				_category_flows[s].visible = (s == sec_name)
			for b in tab_row.get_children():
				if b is Button:
					b.button_pressed = (b.text == sec_name)
		)


func _add_deck_card(parent: Control, title_text: String, description: String, scene_path: String, badge_text: String, is_tutorial: bool = false, launcher_name: String = "") -> void:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(300, 140)
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.theme_type_variation = "NavCard"
	parent.add_child(btn)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_right", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_top", Tokens.SPACE_SM)
	margin.add_theme_constant_override("margin_bottom", Tokens.SPACE_SM)
	btn.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", Tokens.SPACE_XS)
	margin.add_child(vbox)

	var top_row = HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	var name_label = Label.new()
	name_label.text = title_text
	name_label.theme_type_variation = "HeadingLabel"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(name_label)

	var badge = Label.new()
	badge.text = badge_text
	badge.theme_type_variation = "HintLabel"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
	top_row.add_child(badge)

	vbox.add_child(HSeparator.new())

	var desc_label = Label.new()
	desc_label.text = description
	desc_label.theme_type_variation = "HintLabel"
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	UIFeedbackScript.wire(btn)
	btn.pressed.connect(func():
		if is_tutorial:
			var tutorial = get_node_or_null("/root/TwoPhaseTutorialManager")
			if tutorial:
				tutorial.begin()
		if launcher_name != "":
			if launcher_name == "TestRangeLauncher":
				var launcher = TestRangeLauncherScript.new()
				add_child(launcher)
				if launcher.launch("main_menu"):
					return
				launcher.queue_free()
		var router = get_node_or_null("/root/SceneRouter")
		if router:
			router.goto(scene_path)
		else:
			get_tree().change_scene_to_file(scene_path)
	)


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
		var hull_id: String = item.get("hull_type", "brenntal_medium_a")
		_spec_placard.from_blueprint(design_name, "STANDARD BUREAU CHASSIS // READY FOR ASSEMBLY",
			{"hull_type": hull_id})

func _prettify(id: String) -> String:
	if id == "":
		return "-"
	return id.replace("_", " ").capitalize()
