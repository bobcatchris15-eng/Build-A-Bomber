extends Control
# THE LIVERY EDITOR - where the player authors the one faction in the game.
#
# Replaces the two 10-entry faction dropdowns that used to sit on MatchSetup
# and OperationsSetup. Those asked the player to pick someone else's identity
# once per match; this asks them to author their own, once, and then it is
# theirs. It is a profile screen, not a match setting, which is why it hangs
# off the main menu rather than off either setup flow.
#
# FIVE ZONES, each a colour and a finish (scripts/livery.gd owns the data and
# the twelve finishes). The controls are deliberately a colour picker and a
# NAMED finish dropdown rather than colour + metallic/roughness sliders: the
# sliders would let a player author the blown-out near-mirror surface that
# hull_material_builder.gd's ARMOR_PBR note records root-causing once already,
# with nothing on screen to explain why their tank looked like wet plastic.
# Twelve authored finishes, all satin-capped, cannot produce that.
#
# RANDOMISE is the primary action, not a novelty. livery.gd defaults to a
# random scheme for a player who has never opened this screen, so the button
# is the same thing the game already did for them - which makes "roll until
# you like one" a legitimate way to use the editor, and means the screen opens
# on something worth looking at rather than on flat grey.

const LiveryScript = preload("res://scripts/livery.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
# The chrome the Design Lab's bottom toolboxes and the battle production HUD
# are both built from - a chamfered metal plate with enamel lettering stamped
# into it. Used here rather than the plain themed panels a menu screen would
# normally reach for, so this screen reads as the same piece of hardware as
# the two it sits between rather than as a settings dialog bolted on beside
# them.
const ToolboxPlateScript = preload("res://scripts/ui_toolbox_plate.gd")
const StampedLabelScript = preload("res://scripts/ui_stamped_label.gd")
const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")

var _livery: Dictionary = {}
var _pickers: Dictionary = {}     # zone id -> ColorPickerButton
var _finish_btns: Dictionary = {} # zone id -> OptionButton
var _preview_root: Node3D = null
var _preview_hull: Node3D = null
var _bp_manager: Node = null
var _spin: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_livery = LiveryScript.load_player()

	UIShell.backdrop(self)
	var frame := UIShell.screen_frame(self)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.SPACE_LG)
	frame.add_child(col)

	# TITLE AS STAMPED ENAMEL, not a themed Label. A DisplayLabel here would be
	# correct by the style guide and would still read as a different piece of
	# software from the Lab and the battle HUD, both of which letter their
	# headings by cutting them into a plate.
	var header := PanelContainer.new()
	header.theme_type_variation = "HeaderPanel"
	col.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", Tokens.SPACE_MD)
	header.add_child(header_row)
	var title_holder := Control.new()
	title_holder.custom_minimum_size = Vector2(220, 40)
	header_row.add_child(title_holder)
	var title: Control = StampedLabelScript.new()
	title.text = "LIVERY"
	title.font_size = 28
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_holder.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Your colours, on every construct you field. Cosmetic only - nothing fights better for its paint."
	subtitle.theme_type_variation = "HintLabel"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(subtitle)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", Tokens.SPACE_LG)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	# --- Zone controls, on a plate ---
	var zones_content := _plated_section(body, "ZONES", 580)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", Tokens.SPACE_MD)
	grid.add_theme_constant_override("v_separation", Tokens.SPACE_SM)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zones_content.add_child(grid)

	for zone in LiveryScript.ZONES:
		var zid: String = zone["id"]
		var label := Label.new()
		label.text = zone["name"]
		label.theme_type_variation = "HeadingLabel"
		label.custom_minimum_size = Vector2(190, Tokens.HIT_TARGET_MIN)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(label)

		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(96, Tokens.HIT_TARGET_MIN + 4)
		picker.color = _livery[zid]["color"]
		# edit_alpha off: a livery is paint. A translucent hull is a rendering
		# state (energy shielding), not a colour choice.
		picker.edit_alpha = false
		UIFeedbackScript.wire(picker)
		picker.color_changed.connect(_on_color_changed.bind(zid))
		grid.add_child(picker)
		_pickers[zid] = picker

		var finish := OptionButton.new()
		finish.custom_minimum_size = Vector2(210, Tokens.HIT_TARGET_MIN + 4)
		var ids := LiveryScript.finish_ids()
		for i in range(ids.size()):
			finish.add_item(LiveryScript.finish_name(ids[i]), i)
			if ids[i] == _livery[zid]["finish"]:
				finish.selected = i
		UIFeedbackScript.wire(finish)
		finish.item_selected.connect(_on_finish_selected.bind(zid))
		grid.add_child(finish)
		_finish_btns[zid] = finish

	var finish_hint := Label.new()
	finish_hint.text = "Finishes are capped in the satin range - anything glossier blows out under the battle lighting."
	finish_hint.theme_type_variation = "HintLabel"
	finish_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	zones_content.add_child(finish_hint)

	# --- Live preview, in a recessed well ---
	# The point of the finish half of a zone is how it behaves under light, and
	# a flat swatch cannot show matte primer against anodised metal - which is
	# most of what the player is actually choosing.
	var preview_content := _plated_section(body, "PREVIEW", 440)
	var well := PanelContainer.new()
	# InsetPanel, not CardPanel: the viewport is sunk INTO the plate, and the
	# style guide's elevation rule is that a recessed surface must not cast.
	well.theme_type_variation = "InsetPanel"
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_content.add_child(well)
	var preview := SubViewportContainer.new()
	preview.custom_minimum_size = Vector2(400, 330)
	preview.stretch = true
	well.add_child(preview)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = Vector2i(400, 330)
	preview.add_child(vp)
	_preview_root = Node3D.new()
	vp.add_child(_preview_root)
	_build_preview(vp)

	# --- Actions ---
	# All three bottom-bar buttons are real 3D hardware now - the same
	# ui_push_button.glb mesh the production HUD and the design lab
	# toolboxes are built on, with a variant tint for role:
	#   * RANDOMISE - default (matte gunmetal)
	#   * RETURN    - GHOST (lighter, no signal glow) - the screen is not
	#                 asking the player to commit, just to leave
	#   * COMMIT LIVERY - PRIMARY (green emission, the one signal colour
	#                     that means "do this")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	col.add_child(row)

	var random_btn := StampedButtonScript.new()
	random_btn.legend = "RANDOMISE"
	random_btn.custom_minimum_size = Vector2(170, 44)
	UIFeedbackScript.wire(random_btn)
	random_btn.pressed.connect(_on_randomise)
	row.add_child(random_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var back_btn := StampedButtonScript.new()
	back_btn.legend = "RETURN"
	back_btn.variant = StampedButtonScript.Variant.GHOST
	back_btn.custom_minimum_size = Vector2(150, 44)
	UIFeedbackScript.wire(back_btn)
	back_btn.pressed.connect(func():
		var router = get_node_or_null("/root/SceneRouter")
		if router:
			router.goto("res://scenes/MainMenu.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	row.add_child(back_btn)

	# The single PRIMARY action on this screen. The style guide allows at
	# most one PRIMARY per screen, and committing the paint is unambiguously
	# the commit point - a PrimaryButton role would be the same call on a
	# 2D primitive, but on the 3D one the role is carried by the green
	# emission on the chamfer plus a confirmed feedback sound, not by a
	# green stylebox around a flat fill.
	var save_btn := StampedButtonScript.new()
	save_btn.legend = "COMMIT LIVERY"
	save_btn.variant = StampedButtonScript.Variant.PRIMARY
	save_btn.custom_minimum_size = Vector2(210, 44)
	UIFeedbackScript.wire(save_btn, "confirm")
	save_btn.pressed.connect(_on_save)
	row.add_child(save_btn)


# One titled section on a chamfered ToolboxPlate, matching the Design Lab's
# bottom toolboxes. The plate is added FIRST so it draws behind this section's
# controls - sibling order is draw order, the same contract production_hud.gd
# documents for its own plates - and it ignores the mouse so the controls on
# top of it still receive clicks.
func _plated_section(parent: Control, heading: String, min_width: int) -> VBoxContainer:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(min_width, 0)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)

	var plate: Control = ToolboxPlateScript.new()
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(plate)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", Tokens.SPACE_LG)
	margin.add_theme_constant_override("margin_right", Tokens.SPACE_LG)
	margin.add_theme_constant_override("margin_top", Tokens.SPACE_MD)
	margin.add_theme_constant_override("margin_bottom", Tokens.SPACE_MD)
	holder.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", Tokens.SPACE_MD)
	margin.add_child(content)

	var stamp_holder := Control.new()
	stamp_holder.custom_minimum_size = Vector2(0, 24)
	content.add_child(stamp_holder)
	var stamp: Control = StampedLabelScript.new()
	stamp.text = heading
	stamp.font_size = 17
	stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	stamp_holder.add_child(stamp)

	return content


func _process(delta: float) -> void:
	# Slow turntable, so the player sees the finish catch light on more than
	# one facet - a static three-quarter view hides exactly the difference
	# between satin and matte that this screen exists to let them choose.
	if is_instance_valid(_preview_hull):
		_spin += delta * 0.45
		_preview_hull.rotation.y = _spin


func _build_preview(vp: SubViewport) -> void:
	var cam := Camera3D.new()
	# Three-quarter and slightly above, the angle the RTS camera actually looks
	# from - a head-on view foreshortens the hull's length and hides the belt
	# line between the upper and lower zones, which is half of what is being
	# chosen here.
	cam.position = Vector3(4.4, 3.0, 5.6)
	cam.look_at_from_position(Vector3(4.4, 3.0, 5.6), Vector3(0.0, 0.35, 0.0), Vector3.UP)
	_preview_root.add_child(cam)

	# LIGHTING (2026-08-10 pass). The original settings (key 1.5, fill 0.45,
	# cool-blue ambient at 1.0) rendered every finish - matte primer to
	# anodised metal - as a bright, reflective top surface. Key contributor
	# was the cool ambient tint: against a warm key, cool ambient is the
	# exact recipe for "looks glossy" because cool = reflection. Lowered key
	# + warmed the ambient + dropped exposure to keep the colour saturated
	# but the surface reading as PAINT rather than as polished plastic.
	# The other lever (the toon shader's color_saturation) is global and
	# affects every hull, so it is left alone here.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	key.light_energy = 1.05
	_preview_root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -128.0, 0.0)
	fill.light_energy = 0.30
	_preview_root.add_child(fill)

	# A SubViewport has NO WORLD LIGHTING of its own. Without an environment the
	# hull renders against pure black with zero ambient, which crushed every
	# zone colour and left the toon shader's edge-ink saturating into a green
	# and red speckled mess - the first screenshot of this screen looked like a
	# shader failure rather than a paint job. The ambient term is what lets a
	# MATTE finish read at all: a matte surface has almost no specular, so with
	# no ambient there is nothing to see.
	#
	# WARMED 2026-08-10. The original (0.62, 0.66, 0.74) was a cool slate - the
	# direction every "studio render" demo reaches for by default, and the
	# exact wrong choice for a game where the world is warm dirt and warm
	# metal. Cool ambient against a warm key is what makes a surface read as
	# reflection rather than as fill - the gloss complaint in the bug
	# report was a tinted ambient, not a too-bright key. 0.68 / 0.65 / 0.58
	# is a neutral warm grey: warm enough to agree with the key, neutral
	# enough to not tint any finish.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Tokens.BASE_900
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.68, 0.65, 0.58)
	e.ambient_light_energy = 0.75
	e.tonemap_exposure = 0.95
	env.environment = e
	_preview_root.add_child(env)

	_bp_manager = BlueprintManagerScript.new()
	add_child(_bp_manager)
	# Seed the cache the material builders read BEFORE the first build. Without
	# this the preview called LiveryScript.for_id(PLAYER_ID), which rolled its
	# OWN random livery, so the model wore a completely different scheme from
	# the one the pickers beside it were showing.
	_apply_live()


func _rebuild_preview() -> void:
	if is_instance_valid(_preview_hull):
		_preview_root.remove_child(_preview_hull)
		_preview_hull.queue_free()
		_preview_hull = null
	if _bp_manager == null:
		return
	# A stand-in design rather than one of the player's saved blueprints: this
	# screen has to work before they have saved anything, and a fixed subject
	# makes two liveries genuinely comparable.
	var blueprint := {
		"version": 2.0,
		"hull_type": "block_main_meridian_a",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel",
		"faction": LiveryScript.PLAYER_ID,
		"modules": [],
	}
	_preview_hull = _bp_manager.reconstruct_vehicle(blueprint, _preview_root, false, LiveryScript.PLAYER_ID)
	_spin = 0.0


# Every edit writes through to the cache the material builders read, then
# rebuilds - so the preview shows the real pipeline's answer rather than a
# separate approximation of it that could drift.
func _apply_live() -> void:
	LiveryScript._cache[LiveryScript.PLAYER_ID] = _livery.duplicate(true)
	_rebuild_preview()


func _on_color_changed(color: Color, zone_id: String) -> void:
	_livery[zone_id]["color"] = color
	_apply_live()


func _on_finish_selected(index: int, zone_id: String) -> void:
	var ids := LiveryScript.finish_ids()
	if index < 0 or index >= ids.size():
		return
	_livery[zone_id]["finish"] = ids[index]
	_apply_live()


func _on_randomise() -> void:
	_livery = LiveryScript.random_livery()
	for zone in LiveryScript.ZONES:
		var zid: String = zone["id"]
		if _pickers.has(zid):
			_pickers[zid].color = _livery[zid]["color"]
		if _finish_btns.has(zid):
			var ids := LiveryScript.finish_ids()
			var idx := ids.find(_livery[zid]["finish"])
			if idx >= 0:
				_finish_btns[zid].selected = idx
	_apply_live()


func _on_save() -> void:
	LiveryScript.save_player(_livery)
	LiveryScript.invalidate(LiveryScript.PLAYER_ID)
	_apply_live()
