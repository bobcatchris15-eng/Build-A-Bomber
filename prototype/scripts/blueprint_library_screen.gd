extends Control

const UITheme = preload("res://scripts/ui_theme.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")
const SceneRouter = preload("res://scripts/scene_router.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const UIAnimScript = preload("res://scripts/ui_anim.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const TestRangeLauncherScript = preload("res://scripts/test_range_launcher.gd")
const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")

var list_vbox: VBoxContainer
var blueprint_manager: Node

var _turntable_node: Node3D = null
var _turntable_model_container: Node3D = null

func _ready() -> void:
	blueprint_manager = BlueprintManagerScript.new()
	add_child(blueprint_manager)
	
	if DisplayServer.get_name() != "headless":
		_build_3d_background()
		
	_build_ui()
	_refresh_list()

func _process(delta: float) -> void:
	if is_instance_valid(_turntable_node):
		_turntable_node.rotation.y += 0.25 * delta

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

	# Studio WorldEnvironment
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.38, 0.40, 0.42, 1.0)
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

	var sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.35
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)

	var rim = DirectionalLight3D.new()
	rim.light_color = Color(0.65, 0.75, 0.85)
	rim.light_energy = 0.85
	rim.rotation_degrees = Vector3(25, 145, 0)
	scene.add_child(rim)

	var cam = Camera3D.new()
	cam.position = Vector3(1.2, 4.8, 15.5)
	cam.rotation_degrees = Vector3(-16, 12, 0)
	cam.fov = 46.0
	scene.add_child(cam)

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

func _build_ui() -> void:
	var frame := UIShell.screen_frame(self)
	
	var hbox = HBoxContainer.new()
	frame.add_child(hbox)
	
	# Left Side: Library List
	var left_panel = PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(500, 0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.15, 0.85)
	left_panel.add_theme_stylebox_override("panel", style)
	hbox.add_child(left_panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_right", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_top", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_bottom", Tokens.SPACE_MD)
	left_panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	var header = Label.new()
	header.text = "BLUEPRINT LIBRARY"
	header.theme_type_variation = "TitleLabel"
	vbox.add_child(header)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)
	
	var back_btn = StampedButtonScript.new()
	back_btn.legend = "RETURN"
	back_btn.variant = StampedButtonScript.Variant.GHOST
	back_btn.custom_minimum_size = Vector2(0, 48)
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.pressed.connect(func():
		var router = get_node_or_null("/root/SceneRouter")
		var target = "res://scenes/MainMenu.tscn"
		if router and router.pending_context != "":
			target = router.pending_context
		# goto(), not change_scene_async(): `target` is often MainMenu, which has no
		# WARM_SOURCES entry, and change_scene_async() put it behind the loading
		# screen regardless. goto() only uses the loading screen for scenes that
		# actually stall.
		if router:
			router.goto(target)
		else:
			get_tree().change_scene_to_file(target)
	)
	vbox.add_child(back_btn)

func _refresh_list() -> void:
	for child in list_vbox.get_children():
		child.queue_free()
		
	var roster = blueprint_manager.list_blueprints(false)
	if roster.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No saved blueprints found."
		# HintLabel rather than a 50% alpha modulate. Fading white to half opacity
		# over a textured backdrop lets the grain read straight through the glyphs;
		# TEXT_SECONDARY is a real colour that stays legible on it.
		empty_lbl.theme_type_variation = "HintLabel"
		list_vbox.add_child(empty_lbl)
		return
		
	for entry in roster:
		_add_entry_ui(entry)
	# Deferred: stagger_in reads each child's position, which is not final until
	# the VBox has laid the new rows out.
	call_deferred("_animate_list_entrance")

func _animate_list_entrance() -> void:
	if is_instance_valid(list_vbox):
		UIAnimScript.stagger_in(list_vbox)


func _add_entry_ui(entry: Dictionary) -> void:
	var entry_vbox = VBoxContainer.new()
	entry_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	list_vbox.add_child(entry_vbox)
	
	var bg = ColorRect.new()
	bg.color = Color(1, 1, 1, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	entry_vbox.add_child(bg)
	
	var name_lbl = Label.new()
	name_lbl.text = entry.get("name", "Untitled Design")
	name_lbl.theme_type_variation = "HeadingLabel"
	entry_vbox.add_child(name_lbl)
	
	var meta_hbox = HBoxContainer.new()
	entry_vbox.add_child(meta_hbox)
	
	var hull_lbl = Label.new()
	hull_lbl.text = _prettify(entry.get("hull_type", ""))
	hull_lbl.modulate = Color(1, 1, 1, 0.6)
	meta_hbox.add_child(hull_lbl)
	
	var date_lbl = Label.new()
	date_lbl.text = " | " + _format_modified(entry.get("modified_unix", 0))
	date_lbl.modulate = Color(1, 1, 1, 0.4)
	meta_hbox.add_child(date_lbl)

	# The one row in this list that says what a design is FOR rather than what
	# it is made of. Hull type and date do not distinguish an ore hauler from a
	# tank built on the same chassis, and the Library is where a player goes to
	# find "the harvester I made" among thirty saves.
	#
	# A tag, not another dim meta label: it is deliberately the brightest thing
	# in this row after the name, because scanning for it is the whole job. It
	# also carries the payload, so two harvesters in the list are comparable
	# without opening either. It reads off the roster index entry rather than
	# reconstructing the design - see list_blueprints(), which derives it while
	# the blueprint JSON is already parsed and in hand.
	if bool(entry.get("is_harvester", false)):
		var harv_lbl = Label.new()
		harv_lbl.text = "  HARVESTER %d" % int(entry.get("cargo_capacity", 0))
		harv_lbl.theme_type_variation = "StatLabel"
		harv_lbl.modulate = Color(1.0, 0.82, 0.35, 1.0)
		harv_lbl.tooltip_text = "Mounts a Resource Harvester - this design can gather metal and crystal.\nThe number is its hopper: how much it carries per trip, Resource Bays included."
		meta_hbox.add_child(harv_lbl)
	
	var btn_hbox = HBoxContainer.new()
	entry_vbox.add_child(btn_hbox)

	# Per-row action buttons. Variants carry the visual role - the old
	# modulate=Color(0.4,1,0.4) green / Color(1,0.8,0.2) amber / Color(1,0.4,0.4)
	# red were the original "color the flat button" hack and are now retired;
	# PRIMARY / DANGER on the chamfer do the same job without the
	# off-palette saturated tinting.
	#
	# Edit in Lab is the row's primary action (sends the design to the Lab
	# to keep iterating). Test in Arena is a side-quest (kicks off a one-
	# off Test Range). Delete is destructive. Duplicate and Rename are
	# default neutral.
	var edit_btn = StampedButtonScript.new()
	edit_btn.legend = "EDIT IN LAB"
	edit_btn.variant = StampedButtonScript.Variant.PRIMARY
	edit_btn.custom_minimum_size = Vector2(140, 36)
	edit_btn.pressed.connect(_on_edit_pressed.bind(entry.get("id", ""), entry.get("path", "")))
	btn_hbox.add_child(edit_btn)

	var test_btn = StampedButtonScript.new()
	test_btn.legend = "TEST IN ARENA"
	test_btn.custom_minimum_size = Vector2(140, 36)
	test_btn.pressed.connect(_on_test_pressed.bind(entry.get("id", ""), entry.get("path", "")))
	btn_hbox.add_child(test_btn)

	var dup_btn = StampedButtonScript.new()
	dup_btn.legend = "DUPLICATE"
	dup_btn.custom_minimum_size = Vector2(110, 36)
	dup_btn.pressed.connect(_on_duplicate_pressed.bind(entry.get("id", "")))
	btn_hbox.add_child(dup_btn)

	var rename_btn = StampedButtonScript.new()
	rename_btn.legend = "RENAME"
	rename_btn.custom_minimum_size = Vector2(110, 36)
	rename_btn.pressed.connect(_on_rename_pressed.bind(entry.get("id", ""), entry.get("name", "Untitled Design")))
	if entry.get("read_only", false):
		rename_btn.disabled = true
	btn_hbox.add_child(rename_btn)

	var del_btn = StampedButtonScript.new()
	del_btn.legend = "DELETE"
	del_btn.variant = StampedButtonScript.Variant.DANGER
	del_btn.custom_minimum_size = Vector2(110, 36)
	del_btn.pressed.connect(_on_delete_pressed.bind(entry.get("id", ""), entry.get("name", "Untitled Design")))
	if entry.get("read_only", false):
		del_btn.disabled = true
	btn_hbox.add_child(del_btn)
	
	entry_vbox.add_child(HSeparator.new())
	
	# Hover preview logic
	entry_vbox.mouse_entered.connect(func():
		bg.color = Color(1, 1, 1, 0.05)
		_preview_blueprint(entry.get("path", ""))
	)
	entry_vbox.mouse_exited.connect(func():
		bg.color = Color(1, 1, 1, 0.0)
	)

func _preview_blueprint(path: String) -> void:
	if not is_instance_valid(_turntable_model_container):
		return
	for child in _turntable_model_container.get_children():
		child.queue_free()
		
	var bp = blueprint_manager.load_blueprint(path)
	if bp.is_empty():
		return
		
	var model_root = Node3D.new()
	model_root.position = Vector3(0, 0.1, 0)
	var vehicle = blueprint_manager.reconstruct_vehicle(bp, model_root, true)
	if vehicle == null:
		var hull_id = str(bp.get("hull_type", "medium_hull"))
		var mesh = MeshAssetLoader.get_hull_mesh(hull_id)
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.mesh = mesh
		model_root.add_child(mesh_inst)
		
	# Apply scale model look
	HullMaterialBuilderScript.apply_scale_model_finish(model_root)
	_turntable_model_container.add_child(model_root)

# _apply_unpainted_scale_model_material() lived here as a verbatim duplicate of
# main_menu.gd's copy. Both now call HullMaterialBuilder.apply_scale_model_finish(),
# which is the file that exists to end exactly this copy-paste - and which also
# holds the albedo colour that previously had two definitions as well as two
# implementations.

func _on_edit_pressed(id: String, path: String):
	# The library is now a separate scene, so the Lab isn't in the tree to load into directly.
	# We write the design to the scratch slot and flag it for restore, then transition to the Lab.
	var data = blueprint_manager.load_blueprint(path)
	if data.is_empty():
		_show_error("Could not read blueprint data.")
		return
		
	# Important: Make sure the ID and Name are retained in the scratch file so it doesn't fork on save.
	data["pending_lab_restore"] = true
	var json_string = JSON.stringify(data, "\t")
	
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("blueprints"):
		dir.make_dir("blueprints")
		
	var f = FileAccess.open(BlueprintManagerScript.SCRATCH_PATH, FileAccess.WRITE)
	if f:
		f.store_string(json_string)
		f.close()
		var router = get_node_or_null("/root/SceneRouter")
		if router:
			router.goto("res://scenes/MainLab.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/MainLab.tscn")
	else:
		_show_error("Failed to write design to scratch slot.")

func _on_test_pressed(id: String, path: String):
	# Save the selected blueprint to the scratch slot for the arena to pick up
	var data = blueprint_manager.load_blueprint(path)
	data["pending_lab_restore"] = false
	var json_string = JSON.stringify(data, "\t")
	var f = FileAccess.open(BlueprintManagerScript.SCRATCH_PATH, FileAccess.WRITE)
	if f:
		f.store_string(json_string)
		f.close()
		# 2026-08-10: Battlefield.tscn retired; the Test Range now boots on
		# Battle.tscn via TestRangeLauncher. Same flow as stat_calculator's
		# "Test in Arena" button - the launcher writes a Test Range rule
		# set and routes through SceneRouter so the loading screen and fade
		# are still the same as every other launcher.
		var launcher = TestRangeLauncherScript.new()
		add_child(launcher)
		if not launcher.launch("blueprint_library"):
			launcher.queue_free()
			get_tree().change_scene_to_file("res://scenes/Battle.tscn")
	else:
		_show_error("Failed to write test scratch file.")

func _on_rename_pressed(id: String, current_name: String):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Rename Blueprint"
	dialog.dialog_text = "New name:"
	add_child(dialog)
	var line_edit = LineEdit.new()
	line_edit.text = current_name if BlueprintManagerScript.is_named(current_name) else ""
	line_edit.custom_minimum_size = Vector2(300, 0)
	dialog.add_child(line_edit)
	dialog.confirmed.connect(func():
		blueprint_manager.rename_blueprint(id, line_edit.text)
		_refresh_list()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.popup_centered()
	line_edit.grab_focus()
	line_edit.select_all()

func _on_duplicate_pressed(id: String):
	blueprint_manager.duplicate_blueprint(id)
	_refresh_list()

func _on_delete_pressed(id: String, display_name: String):
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Permanently delete \"%s\"?" % display_name
	confirm.title = "Delete Blueprint"
	add_child(confirm)
	confirm.confirmed.connect(func():
		blueprint_manager.delete_blueprint(id)
		_refresh_list()
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	confirm.confirmed.connect(func(): confirm.queue_free())
	confirm.popup_centered()

func _show_error(msg: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = msg
	dialog.title = "Error"
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _format_modified(unix_time: int) -> String:
	if unix_time <= 0: return "Unknown date"
	var dt = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

func _prettify(id: String) -> String:
	if id == "": return "Unknown"
	var words = id.split("_")
	var out: Array = []
	for w in words:
		if w.length() > 0:
			out.append(w[0].to_upper() + w.substr(1))
	return " ".join(PackedStringArray(out))
