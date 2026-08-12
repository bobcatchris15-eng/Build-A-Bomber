extends Node
# Autoload. Drives the guided loop through the Design Lab and the Test Arena.
#
# WHY AN AUTOLOAD: the tutorial spans two scenes and a round trip back
# (MainLab -> Battlefield -> MainLab). Every node in the scene it started in is
# freed on the way, so the step counter has to live somewhere that outlives a
# scene change. Same reasoning as OperationsManager.
#
# WHY CONDITIONS ARE POLLED: module_placer.gd - the Design Lab's 2,700-line root
# script - emits no signals at all. Rather than thread a signal bus through a
# script that ten suites already drive, each step names a condition id and this
# file reads live state once a frame. Cheap (a step is a handful of property
# reads), and it means the tutorial observes the game rather than the game having
# to announce itself to the tutorial.
#
# The conditions are deliberately LOOSE - "a locomotion part exists", not "the
# highlighted Wheels card was the one used". A player who takes the hint as a
# suggestion and fits Treads instead has done the thing the step was teaching,
# and should not be told otherwise.

const TutorialSteps = preload("res://scripts/tutorial/tutorial_steps.gd")
const TutorialOverlay = preload("res://scripts/tutorial/tutorial_overlay.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")

## Emitted when the run ends. `completed` is false when the player skipped.
signal finished(completed: bool)

const SEEN_PATH := "user://tutorial_seen.cfg"

# Above the Design Lab's UI layer (90) and its instructions modal (100), but
# BELOW SceneRouter's fade at 128 - so a scene transition covers the tutorial
# rather than the tutorial being painted over the loading screen.
const OVERLAY_LAYER := 110

var active: bool = false

var _step: int = 0
var _layer: CanvasLayer = null
var _overlay: Control = null
var _last_scene: Node = null
var _button_pressed: bool = false
# Per-step "what it looked like when this step began", for the conditions that
# are differences rather than absolutes. See _enter_step().
var _baseline: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


# --- Lifecycle --------------------------------------------------------------

func begin() -> void:
	if active:
		return
	active = true
	_step = 0
	_last_scene = null
	mark_seen()
	set_process(true)
	_enter_step()


func skip() -> void:
	_end(false)


func has_been_seen() -> bool:
	return FileAccess.file_exists(SEEN_PATH)


func mark_seen() -> void:
	var f := FileAccess.open(SEEN_PATH, FileAccess.WRITE)
	if f:
		f.store_line("seen=true")
		f.close()


# Called by the overlay's NEXT / FINISH button. A flag rather than a direct
# advance so that every step, button-driven or state-driven, is resolved through
# the same _condition_met() path on the same frame boundary.
func notify_button() -> void:
	_button_pressed = true


func _end(completed: bool) -> void:
	active = false
	set_process(false)
	_teardown_overlay()
	_step = 0
	_baseline.clear()
	finished.emit(completed)


func _teardown_overlay() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_overlay = null


# --- Per-frame driving ------------------------------------------------------

func _process(_delta: float) -> void:
	if not active:
		return

	# current_scene goes null for a frame during a change - stat_calculator's
	# "Test in Arena" calls change_scene_to_file() directly rather than going
	# through SceneRouter, so this is a real window, not a theoretical one.
	var scene := get_tree().current_scene
	if scene != _last_scene:
		_last_scene = scene
		_teardown_overlay()
		if is_instance_valid(scene):
			_spawn_overlay_if_relevant()

	if _condition_met():
		_advance()


func _advance() -> void:
	_step += 1
	if _step >= TutorialSteps.count():
		_end(true)
		return
	_enter_step()


func _enter_step() -> void:
	_button_pressed = false
	_baseline.clear()

	# Absolutes cannot express "the player replaced the hull" - the Lab ships a
	# placeholder Hull node and module_placer._ready() stamps type_id
	# "block_main_meridian_a" onto it, so "a medium hull exists" is true before the player
	# has touched anything. Capturing the identity at step entry and watching for
	# it to change is what makes the step real; drag_drop_manager._drop_data()
	# calls clear_hull() then _place_hull_from_ui(), so the node is genuinely a
	# different one afterwards.
	var placer := _lab()
	if placer and is_instance_valid(placer.hull):
		_baseline["hull_id"] = placer.hull.get_instance_id()

	var arena := _arena()
	if arena:
		_baseline["dummies"] = _live_dummies(arena)

	_spawn_overlay_if_relevant()
	if is_instance_valid(_overlay):
		_overlay.show_step(_step, TutorialSteps.step(_step))


# The overlay only exists while the player is actually on the step's own screen.
# Conditions keep being evaluated regardless - step 10 lives in the Lab but
# completes when the Arena loads, which is the whole point of it.
func _spawn_overlay_if_relevant() -> void:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return
	var step := TutorialSteps.step(_step)
	if scene.scene_file_path != str(step.get("scene", "")):
		_teardown_overlay()
		return
	if is_instance_valid(_overlay):
		return

	_layer = CanvasLayer.new()
	_layer.name = "TutorialLayer"
	_layer.layer = OVERLAY_LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(_layer)

	_overlay = TutorialOverlay.new()
	_overlay.name = "TutorialOverlay"
	_overlay.manager = self
	_layer.add_child(_overlay)
	_overlay.show_step(_step, step)


# --- Conditions -------------------------------------------------------------

# Every id here appears in TutorialSteps.ADVANCE_IDS, and test_tutorial.gd
# asserts the two sets agree exactly. A typo would strand the player on a step
# with no way forward but Skip, which is the worst failure this feature has.
func _condition_met() -> bool:
	var step := TutorialSteps.step(_step)
	if step.is_empty():
		return false

	match str(step.get("advance", "")):
		"next_button", "finish_button":
			return _button_pressed
		"hull_replaced":
			var placer := _lab()
			if placer == null or not is_instance_valid(placer.hull):
				return false
			return placer.hull.get_instance_id() != _baseline.get("hull_id", 0)
		"locomotion_placed":
			return _has_module_of_category(["locomotion"])
		"weapon_placed":
			return _has_module_of_category(["weapon"])
		"module_selected":
			var p := _lab()
			return p != null and is_instance_valid(p.selected_module)
		"design_named":
			var edit = _stat_member("blueprint_name_edit")
			if edit == null:
				return false
			return BlueprintManagerScript.is_named(edit.text)
		"blueprint_saved":
			# save_blueprint() stamps the id onto the hull as it writes the file,
			# so this is true only after a save that actually succeeded - a save
			# refused for clipping or for a missing name leaves it unset.
			var pl := _lab()
			if pl == null or not is_instance_valid(pl.hull):
				return false
			return str(pl.hull.get_meta("blueprint_id", "")) != ""
		"scene_is_arena":
			return _arena() != null
		"scene_is_lab":
			return _lab() != null
		"arena_move_ordered":
			var a := _arena()
			return a != null and a.target_destination != Vector3.ZERO
		"arena_dummy_destroyed":
			var a2 := _arena()
			if a2 == null:
				return false
			return _live_dummies(a2) < int(_baseline.get("dummies", 0))
	return false


func _has_module_of_category(categories: Array) -> bool:
	var placer := _lab()
	if placer == null or not is_instance_valid(placer.hull):
		return false
	for child in placer.hull.get_children():
		if not child.has_meta("module_data"):
			continue
		var type_id := str(child.get_meta("module_data").type_id)
		var data: Dictionary = ModuleCatalog.get_module_data(type_id)
		if str(data.get("category", "")) in categories:
			return true
	return false


# target_dummy.gd had no death signal - die() just freed the node - so
# counting survivors was the available route. target_dummy.gd and its
# arena.target_dummies list were retired 2026-08-10 in the unification's
# Phase 4, so this function is now dead unless a future step reintroduces
# the equivalent field on the Test Range's match_director (TODO).
func _live_dummies(arena: Node) -> int:
	var n := 0
	for dummy in arena.target_dummies:
		if is_instance_valid(dummy):
			n += 1
	return n


# --- Scene accessors --------------------------------------------------------
# Duck-typed rather than compared against a scene path, so a suite that builds
# the Lab by hand is recognised the same as the packed scene.

func _lab() -> Node:
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and scene.has_method("_place_hull_from_ui"):
		return scene
	return null


func _arena() -> Node:
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and "target_dummies" in scene:
		return scene
	return null


func _stat_member(member: String):
	var ui := get_tree().get_first_node_in_group("stat_ui")
	if ui == null:
		return null
	return ui.get(member)


# --- First-run offer --------------------------------------------------------

# Shown once, on the player's first arrival in the Design Lab, in place of the
# wall-of-text manual that used to auto-open there. The manual is not gone - it
# is still behind the Lab's own "Instructions" button, where it works better as a
# reference card than as a thing that greets you.
func offer_first_run() -> void:
	if active or has_been_seen():
		return
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return

	var layer := CanvasLayer.new()
	layer.name = "TutorialOfferLayer"
	layer.layer = OVERLAY_LAYER
	scene.add_child(layer)

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.03, 0.03, 0.028, 0.72)
	layer.add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.add_child(centre)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
	panel.custom_minimum_size = Vector2(520, 0)
	centre.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_LG)
	margin.add_theme_constant_override("margin_right", Tokens.SPACE_LG)
	margin.add_theme_constant_override("margin_top", Tokens.SPACE_LG)
	margin.add_theme_constant_override("margin_bottom", Tokens.SPACE_LG)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", Tokens.SPACE_MD)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "FIRST TIME IN THE BUREAU"
	title.theme_type_variation = "TitleLabel"
	vbox.add_child(title)

	var body := Label.new()
	body.text = "Kitbash Command has one loop at its centre: design a vehicle here, "\
		+ "prove it on the range, then field it in a battle.\n\n"\
		+ "The tutorial walks you through that loop once, start to finish. It takes "\
		+ "a few minutes and you can leave at any point.\n\n"\
		+ "The full controls reference is always on the Instructions button, top left."
	body.theme_type_variation = "HintLabel"
	body.add_theme_color_override("font_color", Tokens.TEXT_PRIMARY)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520 - Tokens.SPACE_LG * 2, 0)
	vbox.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	vbox.add_child(row)

	var later := Button.new()
	later.text = "SKIP FOR NOW"
	later.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	UIFeedbackScript.wire(later)
	row.add_child(later)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var start := Button.new()
	start.text = "START TUTORIAL"
	start.theme_type_variation = "PrimaryButton"
	start.custom_minimum_size = Vector2(180, Tokens.HIT_TARGET_MIN)
	UIFeedbackScript.wire(start, "confirm")
	row.add_child(start)

	# Either button retires the offer for good - a prompt that reappears every
	# launch until you say yes is nagware, not onboarding.
	later.pressed.connect(func():
		mark_seen()
		layer.queue_free())
	start.pressed.connect(func():
		layer.queue_free()
		begin())
