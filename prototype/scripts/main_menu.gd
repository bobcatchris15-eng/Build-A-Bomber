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
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")

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

const DESTINATIONS := [
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
		"title": "OPERATIONS",
		"desc": "Multi-stage campaign with after-action reports.",
		"scene": "res://scenes/OperationsSetup.tscn",
		"badge": "TAC // CAMPAIGN"
	},
	{
		"title": "SKIRMISH",
		"desc": "Select a map and a roster, then engage enemy forces.",
		"scene": "res://scenes/MatchSetup.tscn",
		"badge": "COMBAT // SKIRMISH"
	},
	{
		"title": "PROVING GROUND",
		"desc": "Field the current design against target dummies.",
		"scene": "res://scenes/Battlefield.tscn",
		"badge": "TEST // RANGE"
	},
	# The rebuilt battle layer (scripts/battle/), listed BESIDE Skirmish rather
	# than replacing it. The old match controller stays playable and its ~120
	# suites stay green until the new one reaches parity; at that point Skirmish
	# above is deleted and this takes the name. The badge says WIP because for
	# the moment it genuinely is one - see the phase plan.
]

var _turntable_node: Node3D = null
var _turntable_model_container: Node3D = null
var _showcase_items: Array = []
var _current_showcase_index: int = 0
var _showcase_timer: float = 0.0

# 2D Placard UI Nodes for live update
var _placard_title_label: Label = null
var _placard_subtitle_label: Label = null
var _placard_body_vbox: VBoxContainer = null

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

	# 1. Saved Player Blueprints
	var mgr = BlueprintManagerScript.new()
	var roster: Array = mgr.list_blueprints(true)
	for entry in roster:
		var path := str(entry.get("path", ""))
		if path != "":
			var full_bp: Dictionary = mgr.load_blueprint(path)
			if not full_bp.is_empty():
				_showcase_items.append({
					"type": "blueprint",
					"name": entry.get("name", "UNNAMED DESIGN"),
					"blueprint": full_bp,
					"summary": entry
				})

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

	if item_type == "blueprint":
		var bp: Dictionary = item.get("blueprint", {})
		var mgr = BlueprintManagerScript.new()
		var vehicle = mgr.reconstruct_vehicle(bp, model_root, true)
		if vehicle == null:
			var hull_id := str(bp.get("hull_type", "medium_hull"))
			_build_hull_mesh_node(hull_id, model_root)
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

	var title = Label.new()
	title.text = TITLE
	title.theme_type_variation = "DisplayLabel"
	col.add_child(title)

	var tagline = Label.new()
	tagline.text = TAGLINE.to_upper()
	tagline.theme_type_variation = "HintLabel"
	tagline.add_theme_color_override("font_color", Tokens.TEXT_SECONDARY)
	col.add_child(tagline)

	var gap_top = Control.new()
	gap_top.custom_minimum_size = Vector2(0, Tokens.SPACE_MD)
	col.add_child(gap_top)

	var nav = VBoxContainer.new()
	nav.add_theme_constant_override("separation", Tokens.SPACE_SM)
	col.add_child(nav)

	for dest in DESTINATIONS:
		_add_destination_card(nav, dest["title"], dest["desc"], dest["scene"], dest["badge"])

	var gap_bottom = Control.new()
	gap_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap_bottom)

	var quit_btn = Button.new()
	quit_btn.text = "EXIT BUREAU"
	quit_btn.custom_minimum_size = Vector2(180, 44)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# UIFeedback.wire() supplies the hover sound, the hover lift and the press
	# response in one call - replacing a press-audio lambda plus a whole separate
	# mouse_entered lambda that existed only to play a hover sound.
	UIFeedbackScript.wire(quit_btn)
	quit_btn.pressed.connect(func(): get_tree().quit())
	col.add_child(quit_btn)

func _add_destination_card(parent: Control, title_text: String, description: String, scene_path: String, badge_text: String) -> void:
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

	var panel = PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_right", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_top", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_bottom", Tokens.SPACE_MD)
	panel.add_child(margin)

	_placard_body_vbox = VBoxContainer.new()
	_placard_body_vbox.add_theme_constant_override("separation", Tokens.SPACE_SM)
	margin.add_child(_placard_body_vbox)

func _update_placard_ui(item: Dictionary) -> void:
	if _placard_body_vbox == null:
		return

	for child in _placard_body_vbox.get_children():
		child.queue_free()

	var item_type: String = item.get("type", "hull")

	var sub_header = Label.new()
	sub_header.text = "ACTIVE SHOWCASE OBJECT // 30S CYCLE"
	sub_header.theme_type_variation = "HintLabel"
	sub_header.add_theme_color_override("font_color", Tokens.SIGNAL_HAZARD)
	_placard_body_vbox.add_child(sub_header)

	var name_label = Label.new()
	name_label.text = str(item.get("name", "UNKNOWN")).to_upper()
	name_label.theme_type_variation = "TitleLabel"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placard_body_vbox.add_child(name_label)

	_placard_body_vbox.add_child(HSeparator.new())

	if item_type == "blueprint":
		var bp: Dictionary = item.get("blueprint", {})
		var summary: Dictionary = item.get("summary", {})
		var mgr = BlueprintManagerScript.new()

		UIShell.stat_row(_placard_body_vbox, "Type", "Certified Player Blueprint")
		UIShell.stat_row(_placard_body_vbox, "Hull Class", _prettify(str(summary.get("hull_type", ""))))
		UIShell.stat_row(_placard_body_vbox, "Affiliation", _prettify(str(summary.get("faction", ""))))

		var hs: Dictionary = bp.get("hull_size", {})
		if hs.has("x"):
			UIShell.stat_row(_placard_body_vbox, "Envelope (LxWxH)", "%.1f x %.1f x %.1f m" % [
				float(hs.get("z", 0.0)), float(hs.get("x", 0.0)), float(hs.get("y", 0.0))])

		var module_count: int = (bp.get("modules", []) as Array).size()
		UIShell.stat_row(_placard_body_vbox, "Fitted Modules", str(module_count))

		var material := str(bp.get("armor_material", "hardened_steel"))
		var thickness := float(bp.get("armor_thickness", 1.0))
		UIShell.stat_row(_placard_body_vbox, "Armour Rating", "%s, %.1fx" % [_prettify(material), thickness])

		var k: Vector2 = DamageResolverScript.get_material_threshold(material, "kinetic", thickness)
		var t: Vector2 = DamageResolverScript.get_material_threshold(material, "thermal", thickness)
		var e: Vector2 = DamageResolverScript.get_material_threshold(material, "explosive", thickness)
		var table = Label.new()
		table.text = "THRESHOLDS  [ K: %.1f | T: %.1f | E: %.1f ]" % [k.x, t.x, e.x]
		table.theme_type_variation = "StatLabel"
		table.add_theme_color_override("font_color", Tokens.SIGNAL_GO)
		_placard_body_vbox.add_child(table)
	else:
		var hull_id: String = item.get("hull_type", "medium_hull")
		var hull_data: Dictionary = ModuleCatalogScript.get_module_data(hull_id)
		var dim: Vector3 = hull_data.get("dimensions", Vector3(3.8, 1.1, 5.4))

		UIShell.stat_row(_placard_body_vbox, "Type", "Standard Bureau Chassis")
		UIShell.stat_row(_placard_body_vbox, "Hull Class", _prettify(hull_id))
		UIShell.stat_row(_placard_body_vbox, "Category", _prettify(str(hull_data.get("category", "hull"))))
		UIShell.stat_row(_placard_body_vbox, "Envelope (LxWxH)", "%.1f x %.1f x %.1f m" % [dim.z, dim.x, dim.y])
		UIShell.stat_row(_placard_body_vbox, "Base Structural HP", str(int(hull_data.get("hp", 400))))
		UIShell.stat_row(_placard_body_vbox, "Base Chassis Mass", str(int(hull_data.get("weight", 250))) + " kg")

		var stamp_label = Label.new()
		stamp_label.text = "STATUS: BARE CHASSIS // READY FOR ASSEMBLY"
		stamp_label.theme_type_variation = "HintLabel"
		stamp_label.add_theme_color_override("font_color", Tokens.SIGNAL_INFO)
		_placard_body_vbox.add_child(stamp_label)

func _prettify(id: String) -> String:
	if id == "":
		return "-"
	return id.replace("_", " ").capitalize()
