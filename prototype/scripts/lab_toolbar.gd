class_name LabToolbar
extends RefCounted

const UIStampScript = preload("res://scripts/ui_stamp.gd")
const BlueprintNamerScript = preload("res://scripts/blueprint_namer.gd")
const TestRangeLauncherScript = preload("res://scripts/test_range_launcher.gd")
const MeshIconScript = preload("res://scripts/ui/mesh_icon.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const UIIconsScript = preload("res://scripts/ui_icons.gd")

var lab: Node

func _init(p_lab: Node):
	lab = p_lab
	save_button = lab.save_button
	test_button = lab.test_button
	library_button = lab.library_button
	delete_button = lab.delete_button
	blueprint_name_edit = lab.blueprint_name_edit
	_undo_btn = lab._undo_btn
	_redo_btn = lab._redo_btn
	_mirror_icon = lab._mirror_icon
	mirror_checkbox = lab.mirror_checkbox
	_name_roll_button = lab._name_roll_button
	toolbar = lab.toolbar
	
	_slot_hull_label = lab._slot_hull_label
	_slot_parts_label = lab._slot_parts_label
	_slot_cost_label = lab._slot_cost_label
	hull_spec_btn = lab.hull_spec_btn
	_rail_vbox = lab._rail_vbox

var save_button
var test_button
var library_button
var delete_button
var blueprint_name_edit
var _undo_btn
var _redo_btn
var _mirror_icon
var mirror_checkbox
var _name_roll_button
var toolbar

var _slot_hull_label
var _slot_parts_label
var _slot_cost_label
var hull_spec_btn
var _rail_vbox

func _push_undo():
	var root = lab.get_node_or_null("/root/MainLab")
	if root and root.has_method("push_undo_snapshot"):
		root.push_undo_snapshot()

func _on_delete_pressed():
	var root = lab.get_node_or_null("/root/MainLab")
	if root and root.has_method("delete_selected_module"):
		UIStampScript.spawn_stamp(lab.get_tree().root, "DECOMMISSIONED / DISCARDED", "alert")
		root.delete_selected_module()
		
func _on_save_pressed():
	var root = lab.get_node("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		var name_text = blueprint_name_edit.text.strip_edges()
		hull.set_meta("blueprint_name", name_text)
	var blueprint_manager = root.get_node_or_null("BlueprintManager")
	if blueprint_manager:
		if blueprint_manager.save_blueprint():
			UIStampScript.spawn_stamp(lab.get_tree().root, "APPROVED FOR FIELD TEST", "go")
		else:
			blueprint_name_edit.grab_focus()

# Adds a "Roll" button beside the name field that fills in a generated
# designation ("GoatHauler Mk VI", "Type 17 IronDung").
#
# Built in code rather than added to UI_StatBlock.tscn so the LineEdit keeps
# its existing path - stat_calculator.gd reaches it via an @onready node
# path, and reparenting it into a new HBox in the scene would break that
# reference (and every other script that walks the same path).
func _setup_name_roller() -> void:
	if not blueprint_name_edit:
		return
	var parent = blueprint_name_edit.get_parent()
	var idx = blueprint_name_edit.get_index()

	var row = HBoxContainer.new()
	row.name = "BlueprintNameRow"
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	parent.move_child(row, idx)

	# reparent() preserves the node itself, so $ScrollContainer/VBoxContainer/
	# BlueprintNameEdit becomes .../BlueprintNameRow/BlueprintNameEdit. The
	# @onready var already resolved at _ready(), so the reference stays valid.
	blueprint_name_edit.reparent(row)
	blueprint_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_name_roll_button = Button.new()
	_name_roll_button.text = "Roll"
	_name_roll_button.tooltip_text = "Suggest a designation"
	_name_roll_button.pressed.connect(_on_roll_name_pressed)
	row.add_child(_name_roll_button)

	_reroll_name_suggestion()

func _reroll_name_suggestion() -> void:
	# Shown as placeholder text only. A suggestion the player never looked at
	# is not a name they chose, so it must not count as one - it stays out of
	# the field (and therefore out of the save) until Roll is pressed.
	if blueprint_name_edit:
		blueprint_name_edit.placeholder_text = BlueprintNamerScript.generate()

func _on_roll_name_pressed() -> void:
	if not blueprint_name_edit:
		return
	var rolled: String = BlueprintNamerScript.generate()
	blueprint_name_edit.text = rolled
	_on_blueprint_name_changed(rolled)
	_reroll_name_suggestion()

func _on_blueprint_name_changed(new_text: String):
	var root = lab.get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		hull.set_meta("blueprint_name", new_text)

func _on_library_pressed():
	var root = lab.get_node_or_null("/root/MainLab")
	if not root: return
	var router = lab.get_node_or_null("/root/SceneRouter")
	if router:
		# Pass the lab as context so the library knows to return here
		router.goto("res://scenes/BlueprintLibrary.tscn", "res://scenes/MainLab.tscn")
	else:
		lab.get_tree().change_scene_to_file("res://scenes/BlueprintLibrary.tscn")

func _on_test_pressed():
	var root = lab.get_node("/root/MainLab")
	var blueprint_manager = root.get_node_or_null("BlueprintManager")
	if blueprint_manager:
		var success = blueprint_manager.save_scratch()
		if success:
			UIStampScript.spawn_stamp(lab.get_tree().root, "DESTRUCTIVE TEST PERMIT", "hazard")
			# Battle-system unification Phase 3: route through TestRangeLauncher
			# rather than the legacy Battlefield.tscn. The launcher reads the
			# scratch slot we just saved, builds a Test Range MatchRuleSet, and
			# routes through SceneRouter. The 0.35s stamp gate still fires so
			# the player sees the DESTRUCTIVE TEST PERMIT stamp clear before
			# the screen swaps.
			lab.get_tree().create_timer(0.35).timeout.connect(func():
				var launcher = TestRangeLauncherScript.new()
				lab.add_child(launcher)
				if not launcher.launch("design_lab"):
					launcher.queue_free()
			)
		else:
			var ui = lab.get_tree().get_first_node_in_group("stat_ui")
			if ui and ui.has_node("ScrollContainer/VBoxContainer/Title"):
				ui.get_node("ScrollContainer/VBoxContainer/Title").text = "TEST BLOCKED: Resolve Clipping!"
				lab.get_tree().create_timer(3.0).timeout.connect(func():
					if is_instance_valid(ui) and ui.has_node("ScrollContainer/VBoxContainer/Title"):
						ui.get_node("ScrollContainer/VBoxContainer/Title").text = "Blueprint Stats"
				)
	else:
		# No BlueprintManager in the tree (headless test path). Fall back to
		# the launcher; it will resolve the bundled default (Bulwark MBT) when
		# the scratch slot is empty and no saved designs exist.
		var launcher = TestRangeLauncherScript.new()
		lab.add_child(launcher)
		if not launcher.launch("design_lab"):
			launcher.queue_free()

func _on_mirror_toggled(button_pressed: bool):
	if _mirror_icon:
		_mirror_icon.set_active(button_pressed)
	var root = lab.get_node("/root/MainLab")
	if root and root.has_method("set_mirror_enabled"):
		root.set_mirror_enabled(button_pressed)

func set_mirror_toggle(enabled: bool):
	if mirror_checkbox:
		# Set without triggering the signal to avoid infinite loops
		mirror_checkbox.set_pressed_no_signal(enabled)
	if _mirror_icon:
		_mirror_icon.set_active(enabled)

# Chris: "do not fail to author meshes for toggles and switches... especially
# in the Design Lab." mirror_checkbox is scene-tree furniture from
# UI_StatBlock.tscn rather than built in code, so the icon is spliced in as a
# sibling right before it instead of assuming a container shape to build into.
func _build_mirror_icon() -> void:
	var parent = mirror_checkbox.get_parent()
	if parent == null:
		return
	_mirror_icon = MeshIconScript.new()
	_mirror_icon.mesh_path = "res://assets/models/ui/ui_toggle_switch.glb"
	_mirror_icon.icon_size = Vector2i(28, 28)
	parent.add_child(_mirror_icon)
	parent.move_child(_mirror_icon, mirror_checkbox.get_index())
	_mirror_icon.set_active(mirror_checkbox.button_pressed)

func _build_toolbar() -> void:
	var bar = PanelContainer.new()
	bar.name = "Toolbar"
	bar.theme_type_variation = "HeaderPanel"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	# Tall enough to clear Tokens.HIT_TARGET_MIN with the band's own padding. Both
	# docks inset their top by this same token so nothing is drawn over the bar.
	bar.offset_bottom = Tokens.TOOLBAR_HEIGHT
	lab.add_child(bar)
	toolbar = bar

	var row = HBoxContainer.new()
	# XS, not SM: the slots carry their own dividers now, so the gap between them
	# only has to keep the rules off the content.
	row.add_theme_constant_override("separation", Tokens.SPACE_XS)
	bar.add_child(row)

	# --- INFO SLOTS ---------------------------------------------------------
	# Chris's model for the top bar: mostly transparent slots, each holding either
	# one piece of static info or one global button. The readouts come first
	# because they are read, not operated - the eye scans left, and putting the
	# things you click at the ends keeps them away from the ones you don't.
	#
	# These are live: _update_toolbar_info() refreshes them from the same
	# DesignStats result update_stats() already computed, so they cannot disagree
	# with the telemetry rail.
	_slot_hull_label = lab._info_slot(row, "HULL")
	_slot_parts_label = lab._info_slot(row, "PARTS")
	# COST replaces the FACTION slot. Faction is no longer a Lab concept at all
	# (it is chosen at battle time - see module_placer's scale-model finish), and
	# what the slot's space is worth instead is the one number the player has to
	# carry out of this screen and into a build queue.
	#
	# It is the SAME figure DesignCosting.blueprint_cost() charges, because both
	# sides are ResourceCatalog.credits_from_materials() over the same metal and
	# crystal sums - DesignStats.analyze() computes them from the live hull, and
	# design_costing.gd computes them from the serialized blueprint. Two readers,
	# one formula; there is no separate "lab price".
	_slot_cost_label = lab._info_slot(row, "COST")

	# Undo/Redo first: they act on the document, and reading order should match
	# the fact that they are the two most-used controls in the Lab.
	_undo_btn = _toolbar_button(row, "UNDO", "undo", func(): _toolbar_undo())
	_redo_btn = _toolbar_button(row, "REDO", "redo", func(): _toolbar_redo())

	row.add_child(VSeparator.new())

	# Mirror is a mode, so it stays a checkbox rather than becoming a button -
	# a latched state needs to look latched.
	if mirror_checkbox:
		mirror_checkbox.reparent(row)

	row.add_child(VSeparator.new())
	
	var auto_armor_btn = _toolbar_button(row, "AUTO-ARMOR", "auto_armor", func(): _on_auto_armor_pressed())
	
	row.add_child(VSeparator.new())

	var view_mode_btn = OptionButton.new()
	view_mode_btn.add_item("VIEW: DEFAULT", 0)
	view_mode_btn.add_item("VIEW: WIREFRAME", 1)
	view_mode_btn.add_item("VIEW: XRAY", 2)
	view_mode_btn.add_item("VIEW: STRUCTURAL", 3)
	var LabViewModesScript = preload("res://scripts/lab_view_modes.gd")
	var lab_view_modes = LabViewModesScript.new(lab)
	view_mode_btn.item_selected.connect(func(idx: int):
		lab_view_modes.set_view_mode(idx as LabViewModes.ViewMode)
	)
	row.add_child(view_mode_btn)

	row.add_child(VSeparator.new())

	# The flyout trigger, and then the document actions. Save last-but-one and
	# Test last, so the two that leave or commit the screen sit furthest from
	# Undo/Redo and cannot be hit by accident on the way to them.
	if hull_spec_btn:
		hull_spec_btn.reparent(row)
	if library_button:
		library_button.reparent(row)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	if save_button:
		save_button.reparent(row)
	if test_button:
		test_button.reparent(row)

	# Navigation back to the main menu - reparented from the rail (where it
	# used to live below the stats) so it sits with the other "leave the
	# screen" controls at the right end. Placed AFTER test_button so the
	# two commits (save, test) sit next to each other and the menu sits at
	# the absolute right edge, away from the read-only info slots.
	var menu_btn = _rail_vbox.get_node_or_null("MainMenuButton")
	if menu_btn:
		menu_btn.reparent(row)

	UIFeedbackScript.wire_tree(row)
	# The docks inset their top by Tokens.TOOLBAR_HEIGHT, but nothing forces the
	# BAR to that height - a PanelContainer cannot render shorter than its content,
	# so a change to button padding silently makes the bar taller and the rails
	# start covering its outermost buttons. That is exactly what happened once (see
	# the token's own comment), and the symptom - UNDO/REDO and SAVE/TEST becoming
	# unclickable - looks like an input bug rather than a layout one. Deferred
	# because size is not final until layout has run.
	call_deferred("_verify_toolbar_height")


func _verify_toolbar_height() -> void:
	if not is_instance_valid(toolbar):
		return
	var actual: float = toolbar.size.y
	if actual > float(Tokens.TOOLBAR_HEIGHT) + 0.5:
		push_warning(
			"stat_calculator: toolbar renders %.0fpx but Tokens.TOOLBAR_HEIGHT is %d. "
			% [actual, Tokens.TOOLBAR_HEIGHT]
			+ "The docks inset by the token, so the bottom %.0fpx of the bar is now "
			% [actual - float(Tokens.TOOLBAR_HEIGHT)]
			+ "under the collapsed rails and its outermost buttons are unclickable. "
			+ "Raise the token to match, or reduce the toolbar buttons' padding."
		)


func _toolbar_undo() -> void:
	var root = lab.get_node_or_null("/root/MainLab")
	if root and root.has_method("undo"):
		root.undo()


func _toolbar_redo() -> void:
	var root = lab.get_node_or_null("/root/MainLab")
	if root and root.has_method("redo"):
		root.redo()


func _toolbar_button(parent: Container, label: String, icon_name: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = label
	if UIIconsScript.has_icon(icon_name):
		b.icon = UIIconsScript.get_icon(icon_name)
	b.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _on_auto_armor_pressed():
	var root = lab.get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if not hull: return
	
	var mesh_inst = hull.get_node_or_null("MeshInstance3D")
	if not mesh_inst: mesh_inst = hull.get_node_or_null("PhysicsMesh")
	if not mesh_inst or not mesh_inst.mesh: return
	
	_push_undo()
	
	var WFCSolver = preload("res://scripts/wfc_solver.gd")
	var wfc = WFCSolver.new()
	wfc.add_tile("plate_flat", { Vector3i.RIGHT: "edge", Vector3i.LEFT: "edge", Vector3i.FORWARD: "edge", Vector3i.BACK: "edge" })
	wfc.add_tile("plate_corner", { Vector3i.RIGHT: "corner", Vector3i.FORWARD: "corner", Vector3i.LEFT: "edge", Vector3i.BACK: "edge" })
	wfc.set_opposite_sockets({"edge": "edge", "corner": "corner"})
	
	var aabb = mesh_inst.mesh.get_aabb()
	var cell_size = 1.0
	var min_bound = Vector3i(floor(aabb.position.x / cell_size), floor(aabb.position.y / cell_size), floor(aabb.position.z / cell_size))
	var max_bound = min_bound + Vector3i(ceil(aabb.size.x / cell_size), ceil(aabb.size.y / cell_size), ceil(aabb.size.z / cell_size))
	
	var surface_cells: Array[Vector3i] = []
	for x in range(min_bound.x, max_bound.x + 1):
		for y in range(min_bound.y, max_bound.y + 1):
			for z in range(min_bound.z, max_bound.z + 1):
				if y == max_bound.y:
					surface_cells.append(Vector3i(x, y, z))
					
	wfc.set_grid(surface_cells)
	var result = wfc.solve()
	
	var VisualBuilder = preload("res://scripts/visual_builder.gd")
	var ModuleCatalog = preload("res://scripts/module_catalog.gd")
	
	for coord in result:
		var tile_id = result[coord]
		var type_id = "armor_plating"
		
		# If the player already placed armor near here, we might want to skip, 
		# but for this prototype, we'll just spawn them all.
		var module = VisualBuilder.build_module(type_id)
		
		module.position = Vector3(coord.x * cell_size, coord.y * cell_size + cell_size * 0.5, coord.z * cell_size)
		
		# Give it the standard stats payload so it works like a placed module
		module.set_meta("module_data", ModuleCatalog.get_module_data(type_id))
		module.set_meta("type_id", type_id)
		
		hull.add_child(module)
		
	# Refresh UI stats and visually update
	if root.has_method("update_hull_appearance"):
		root.update_hull_appearance()
		
	var lab_doc = root.get_node_or_null("LabDocument")
	if lab_doc and lab_doc.telemetry_rail:
		lab_doc.telemetry_rail.update_stats(hull)


# --- Hull spec flyout -------------------------------------------------------

# Opens the hull-spec flyout, or closes it if it is already up so the trigger
# toggles rather than stacking a second copy on every press.
func _return_to_menu() -> void:
	var router = lab.get_node_or_null("/root/SceneRouter")
	if router:
		router.goto("res://scenes/MainMenu.tscn")
	else:
		lab.get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# --- Verdict block (UX_REDESIGN_PLAN.md Phase 4, item 1) --------------------
#
# ANCHORED TO hp_label.get_parent(), NOT $ScrollContainer/VBoxContainer. The
# rail's container gets reparented into a UIDock at runtime by _build_shell(),
# so a re-resolved literal path is null by the time this runs - hp_label's own
# @onready reference stays valid across that move (see this file's header
# comment on why every @onready here does), and its parent IS the rail vbox.
