extends CenterContainer
# The deploy gate: the last beat of a battle's opening sequence.
#
# WHAT THIS REPLACES. The old _deploy_gate() lived inline in
# scene_router.gd:303-343 and was a CenterContainer with a HintLabel
# and a plain Button. It only ran AFTER world_is_ready flipped, so
# the player spent the ~4s terrain bake staring at a half-built map
# with no visual acknowledgement - the hitch documented in
# docs/design/DEPLOY_GATE_REDESIGN.md §1. The gate now comes up
# DURING the build, owns the world-readiness polling, owns the
# tree-pause lifecycle, and exposes a single `deploy_pressed` signal
# the router awaits.
#
# WHAT THIS DOES NOT DO
#
#   * The router still owns the fade rect (scene_router.gd:59-105).
#     The gate is a Control inside the router's fade layer; it does
#     not own the screen-wide fade.
#   * The gate does not own the loading screen - that is its own
#     scene (Loading.tscn + loading_screen.gd) shown before the
#     scene swap. The gate lives on the OTHER side of the swap.
#
# STATE MACHINE
#
#   build   default on start(). The glass + lamps + bar + step
#           text are up. The DEPLOY button is hidden. The tree is
#           not paused - the match director is still being built
#           and a pause would race the rest of _ready().
#   ready   world_is_ready has flipped. Glass + lamps + bar stay
#           up. The bezel's border colour eases to SIGNAL_GO and
#           the bezel status lamps flip on. The status label
#           changes to "ALL SYSTEMS READY". The DEPLOY button
#           appears (disabled -> enabled). The tree is paused
#           so the AI commander does not take its first
#           decision before the player has read the map.
#   dismissed  deploy_pressed has fired. The tree is unpaused.
#           The glass fades to clear. The gate frees itself.
#
# LIFECYCLE (the router's job)
#
#   _fade_layer.add_child(gate)
#   gate.start()                 # enter build state
#   await gate.deploy_pressed    # wait for the player
#   gate.dismiss()               # tree unpause, fade, free
#
# The router does not poll world_is_ready directly anymore. The
# gate subscribes to the current scene's `progress` signal and
# detects the 1.0 emission as "world is ready".

const Tokens = preload("res://scripts/ui_tokens.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")
const UILampsScript = preload("res://scripts/ui_lamps.gd")
const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")
const MatchRuleSetScript = preload("res://scripts/match_rule_set.gd")

# The glass shader (shaders/deploy_glass.gdshader). See its
# header for the three blur options and why this commit
# ships Option 3 (per-pixel Gaussian + frost) instead of
# Option 1 (CompositorEffect + separable Gaussian compute
# shader). The locked decision is Option 1; the upgrade
# path is documented and the shader's blur_amount=0 makes
# the swap a one-uniform change.
const GlassShader = preload("res://shaders/deploy_glass.gdshader")

# The DEPLOY button's dimensions. 260x56 is what the old gate used
# (scene_router.gd:328) - slightly taller than StampedButton's
# 132x44 minimum so the mesh has room. StampedButton scales the
# 3D mesh to fit, so 260x56 renders the same proportion as
# 132x44 with more visible chamfer detail.
const BUTTON_MIN_SIZE := Vector2(260, 56)

# The bezel's border thickness and the inset for the inner column.
# 2px border is the minimum that reads as "frame" rather than as
# a line; 24px inset matches the loading screen's UIShell.screen_frame
# convention so the two screens feel like the same surface.
const BEZEL_BORDER := 2
const BEZEL_INSET := 24

# Border colour the bezel eases to when the world is ready. SIGNAL_GO
# is the design language's "ready, affordable, confirmed" colour
# (ui_tokens.gd:52), and is the same green StampedButton.PRIMARY's
# chamfer emission uses - the bezel and the button share a colour so
# the ready state reads as a single visual moment.
const READY_BORDER := Tokens.SIGNAL_GO
# Border colour during build. BASE_500 is the design language's
# "borders, dividers" colour (ui_tokens.gd:36) - present but not
# drawing attention, which is what the build state should look like.
const BUILD_BORDER := Tokens.BASE_500

# 2026-08-13: how long the bezel border colour takes to ease from
# BUILD_BORDER to READY_BORDER. DURATION_NORMAL (0.22s) is the same
# timing the loading screen's status escalates from "PREPARING
# DEPLOYMENT" to "STAND BY" - one timing constant for the gate's
# own visual transitions.
const BEZEL_BORDER_EASE := Tokens.DURATION_NORMAL

# Number of small status lamps on the bezel itself. 6 = 3 on each
# side of the DEPLOY button. The lamps are flipped on together
# at the mark-ready moment, so the count is a layout choice, not
# an information encoding - 6 reads as "panel of status lights"
# without looking like a Christmas tree.
const BEZEL_LAMP_COUNT := 6

# How long the gate's dismissing fade takes. Symmetric with the
# scene-router's fade_in (DURATION_NORMAL) so the gate dissolving
# matches the fade_in that follows it. Two slightly-different
# timings on adjacent transitions is what reads as a stutter.
const DISMISS_FADE := Tokens.DURATION_NORMAL

# 2026-08-13: ceiling on the world-readiness poll. Matches the
# old scene_router.gd:268 WORLD_READY_TIMEOUT (30s). If the
# match director errors out partway through _ready() the flag
# never flips, and without a ceiling the player sits on a glass
# overlay with no way back. Forcing mark_ready() at the timeout
# is degraded - the world may be partially built - but the
# alternative is a player who cannot proceed at all.
const READY_TIMEOUT := 30.0


# Emitted when the player presses DEPLOY. The router awaits this
# and then calls dismiss(). Naming is past-tense / event-named
# per minimax.md §2.2.
signal deploy_pressed

# The status label. TitleLabel (24px stencil) per §6 of the doc,
# not the HintLabel the old gate used.
var _status_label: Label

# The step label. StatLabel per the loading screen's _step_label
# at loading_screen.gd:74-77. Says what part of the build is
# currently running ("Surveying terrain" / "Raising command
# deck" / "Briefing opposition" / "Ready").
var _step_label: Label

# The shared progress bar. Pinned to the same _on_progress()
# handler the loading screen uses, but driven from the match
# director's `progress` signal (0.05..1.00) instead of the
# router's load_progress (0.0..warm_list/total).
var _bar: ProgressBar

# The shared segment-lamp strip. Sweep colour stays at the
# default SIGNAL_HAZARD (amber) - this is "things are happening",
# not a state indicator. The bezel's status lamps are the
# state indicators.
var _lamps: UILamps

# The DEPLOY button. Created in _ready but kept hidden during
# the build state; shown when the world is ready.
var _button: StampedButton

# The bezel. A Panel whose StyleBoxFlat border colour is the
# visual handle for the state transition. Border eases from
# BUILD_BORDER to READY_BORDER on mark_ready().
var _bezel: Panel
var _bezel_stylebox: StyleBoxFlat

# The bezel's status lamps - 6 small ColorRects, BASE_700 during
# build, SIGNAL_GO when ready. Flipped on together so the
# transition is a single visual moment, not a sequenced ramp.
var _bezel_lamps: Array[ColorRect] = []

# The glass overlay. A ColorRect behind the bezel that fills
# the screen with a translucent dark tint. The blur effect
# (Option 1, CompositorEffect) is applied as a ShaderMaterial
# here in a follow-up; the rest of the glass visual works
# without it (dim + noise, the Option 3 fallback).
var _glass: ColorRect

# Cached reference to the current scene (the match director's
# root). Resolved in start() and used to subscribe to the
# `progress` signal. The reference is duck-typed because not
# every scene the router swaps to declares a progress signal
# (the deploy gate is a no-op for a scene that does not).
var _director: Node = null

# State. build -> ready -> dismissed. A enum is overkill for
# three states; a string is enough and reads at the assignment
# site.
var _state: String = "build"


func _ready() -> void:
	# CenterContainer already anchors to PRESET_FULL_RECT; we set
	# it explicitly for the same reason the old gate did
	# (scene_router.gd:309) - an explicit anchor is what every
	# future editor edit will read.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP so a stray click landing on the glass (the panel covers
	# the whole screen) does not issue an order during the pause.
	# The match is already live by the time the gate is up; this is
	# the chokepoint that prevents the player from clicking
	# THROUGH the gate.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# The gate pauses the tree on mark_ready() so the AI commander
	# does not take its first decision before the player has read
	# the map. With the tree paused, the gate itself would stop
	# processing - the button could not repaint, the dismiss fade
	# could not run, the tween's finished signal would not arrive.
	# ALWAYS keeps the gate (and its children) running through the
	# pause, which is what the old _deploy_gate did via
	# _fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_glass()
	_build_bezel()


# The diffuse-glass layer behind everything. Drawn first so the
# bezel + lamps + button sit on top. The Option 3 fallback
# (per-pixel Gaussian + frost) is what ships in this commit;
# the CompositorEffect blur is a follow-up - see
# docs/design/DEPLOY_GATE_REDESIGN.md §4 for the three options
# and which one was locked in. The shader is at
# shaders/deploy_glass.gdshader; the gate's dim+frost is the
# gate's job, the actual world-behind-glass sampling is the
# shader's job.
func _build_glass() -> void:
	_glass = ColorRect.new()
	_glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Color is alpha 1.0 here because the shader writes its own
	# alpha; the ColorRect's modulate.a is the gate's master
	# control and is tweened to 0.0 on dismiss.
	_glass.color = Color(1.0, 1.0, 1.0, 1.0)

	# Apply the glass shader. The shader samples SCREEN_TEXTURE
	# and writes a tinted, blurred, frosted version of the world
	# with the glass's own alpha. The four uniforms match the
	# defaults in the shader so an instance with no overrides
	# looks the same as the shader's documented first-pass look.
	var mat := ShaderMaterial.new()
	mat.shader = GlassShader
	mat.set_shader_parameter("alpha", 0.45)
	mat.set_shader_parameter("tint", Tokens.BASE_900)
	mat.set_shader_parameter("blur_amount", 0.6)
	mat.set_shader_parameter("frost_amount", 0.10)
	_glass.material = mat

	# The glass sits BEHIND the bezel, so it has to be added to
	# the same parent (the gate itself, a CenterContainer) BEFORE
	# the bezel. add_child's default order puts the new child on
	# top; we re-order explicitly.
	add_child(_glass)
	move_child(_glass, 0)


# The bezel: a stamped-steel Panel with a StyleBoxFlat border
# that eases from BUILD_BORDER to READY_BORDER on mark_ready.
# The bezel is the OUTERMOST visible element of the gate's
# central column, and swallows clicks so the gate's STOP
# mouse_filter is the only thing the player can hit.
func _build_bezel() -> void:
	_bezel = Panel.new()
	_bezel.mouse_filter = Control.MOUSE_FILTER_STOP

	_bezel_stylebox = StyleBoxFlat.new()
	_bezel_stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # transparent - glass shows through
	_bezel_stylebox.border_width_left = BEZEL_BORDER
	_bezel_stylebox.border_width_right = BEZEL_BORDER
	_bezel_stylebox.border_width_top = BEZEL_BORDER
	_bezel_stylebox.border_width_bottom = BEZEL_BORDER
	_bezel_stylebox.border_color = BUILD_BORDER
	# 8px corner radius so the bezel reads as a stamped panel,
	# not as a wireframe outline. Matches the StampedButton's
	# own chamfered profile.
	_bezel_stylebox.corner_radius_top_left = 8
	_bezel_stylebox.corner_radius_top_right = 8
	_bezel_stylebox.corner_radius_bottom_left = 8
	_bezel_stylebox.corner_radius_bottom_right = 8
	# A small content margin so the inner column does not sit
	# flush against the border. The bezel is the frame; the
	# inner content is what the player reads.
	_bezel_stylebox.content_margin_left = BEZEL_INSET
	_bezel_stylebox.content_margin_right = BEZEL_INSET
	_bezel_stylebox.content_margin_top = BEZEL_INSET
	_bezel_stylebox.content_margin_bottom = BEZEL_INSET
	_bezel.add_theme_stylebox_override("panel", _bezel_stylebox)
	# Stamped steel material on the bezel - the same vocabulary
	# match_setup.gd's backdrop uses (match_setup.gd:85-91). The
	# bezel needs to read as "metal", and the UI material shader
	# is what gives everything in the chrome the same surface.
	UITheme.apply_material(_bezel, "steel", {
		"brightness": 0.42,
		"wear": 0.18,
		"grime": 0.10,
		"scale": 1.4,
		"vignette": 0.18,
	})
	add_child(_bezel)

	_build_inner_column()


# The vertical column inside the bezel: status -> step -> bar
# -> lamps -> bezel status lamps row -> button. The bezel
# status lamps row is added AFTER the segment lamps so it
# sits below them in the column (the bezel lamps are the
# small flanking indicators, not the wide sweep).
func _build_inner_column() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.SPACE_MD)
	# EXPAND_FILL so the column fills the bezel's content area;
	# the bezel itself is sized by its content.
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bezel.add_child(col)

	_status_label = Label.new()
	_status_label.text = "PREPARING DEPLOYMENT"
	_status_label.theme_type_variation = "TitleLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status_label)

	_step_label = Label.new()
	_step_label.text = "Preparing"
	_step_label.theme_type_variation = "StatLabel"
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_step_label)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	col.add_child(_bar)

	_lamps = UILampsScript.new()
	col.add_child(_lamps)

	_build_lamps_and_button_row(col)


# The combined "bezel status lamps + DEPLOY button" row.
# 3 lamps on each side of the DEPLOY button, in a single
# HBox. They flank the button; the button is centered by
# the EXPAND_FILL spacers between the lamp clusters and the
# button, so the layout reads as a single row of
# [lamps] [button] [lamps].
func _build_lamps_and_button_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.SPACE_SM)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)

	# Left cluster: 3 lamps, packed against the left edge of
	# the row. The HBox's alignment centers the whole group;
	# the EXPAND_FILL spacers between the cluster and the
	# button push the cluster outward.
	for _i in range(BEZEL_LAMP_COUNT / 2):
		row.add_child(_make_bezel_lamp())

	# Spacer between the left cluster and the button. Sized
	# EXPAND_FILL so it absorbs all the row's slack, pushing
	# the button away from the lamps.
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left_spacer)

	# DEPLOY button, in the row.
	_button = StampedButtonScript.new()
	_button.legend = "DEPLOY"
	_button.variant = StampedButtonScript.Variant.PRIMARY
	_button.custom_minimum_size = BUTTON_MIN_SIZE
	_button.disabled = true
	_button.pressed.connect(_on_deploy_pressed)
	UIFeedbackScript.wire(_button, "confirm")
	row.add_child(_button)

	# Right spacer + right cluster, symmetric.
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right_spacer)

	for _i in range(BEZEL_LAMP_COUNT / 2):
		row.add_child(_make_bezel_lamp())


# A single bezel status lamp. 12x12 ColorRect, BASE_700 during
# build, SIGNAL_GO when ready. The lamp is just a coloured
# square - the visual reads as a status indicator because of
# its position on the bezel and its contrast against the
# stamped-steel background.
func _make_bezel_lamp() -> ColorRect:
	var lamp := ColorRect.new()
	lamp.custom_minimum_size = Vector2(12, 12)
	lamp.color = Tokens.BASE_700
	# IGNORE: the lamp is decorative, never a hit target. A
	# clickable lamp would steal focus from the DEPLOY button
	# and break the gate's STOP mouse_filter story.
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bezel_lamps.append(lamp)
	return lamp


# --- Public API ---------------------------------------------------------------

# The router calls this after adding the gate to its fade layer.
# Subscribes to the current scene's progress signal (if it has
# one) and starts the world-readiness polling loop.
func start() -> void:
	_director = get_tree().current_scene
	if _director != null and _director.has_signal("progress"):
		_director.progress.connect(_on_progress)
		# Late-subscriber race: the match director's first
		# emissions fire during _ready, which can run on the
		# same frames the router was yielding on (see
		# scene_router.gd:251-252). A signal already emitted
		# is a signal that never arrives, so the bar would
		# otherwise sit at 0% for the entire build. The
		# match director keeps a replay buffer (see
		# get_last_progress) precisely for this case - read
		# it once, set the bar/step, then the live signal
		# takes over.
		if _director.has_method("get_last_progress"):
			var current: Dictionary = _director.get_last_progress()
			if current.get("fraction", 0.0) > 0.0:
				_on_progress(float(current["fraction"]),
					str(current.get("label", "")))
	# The world_is_ready flag (match_director.gd:148) is the
	# source of truth for "world is playable". The signal
	# world_ready arrives on the same frame, but a polled
	# flag handles the race where the world finishes building
	# BEFORE the router gets around to awaiting it.
	_poll_world_is_ready()


# Pauses the tree, eases the bezel border to SIGNAL_GO, lights
# the bezel lamps, flips the status label, and enables the
# DEPLOY button. Called by _poll_world_is_ready the moment
# the flag flips. Idempotent - calling it twice is a no-op.
func mark_ready() -> void:
	if _state != "build":
		return
	_state = "ready"

	# PAUSE THE TREE HERE, not in the router. The old gate
	# paused the tree in scene_router.gd:340 the moment the
	# gate was created, which meant the world was paused
	# during the build too - harmless for Skirmish because
	# the world is mid-build and not yet playable, but a
	# race against the AI commander's first decision if
	# anyone refactors the build order later. Tying the
	# pause to the mark-ready moment is the cleaner
	# contract: the world is paused only when the player
	# has a button to unpause it with.
	get_tree().paused = true

	# Border colour ease. The codebase's UIAnimScript does not
	# have a generic tween_property() helper, and the only other
	# transitions on this gate (the dismiss fade) also use
	# create_tween directly. create_tween is the Godot 4 built-in
	# and is what every other one-off tween in the codebase uses.
	var tween := create_tween()
	tween.tween_property(_bezel_stylebox, "border_color",
		READY_BORDER, BEZEL_BORDER_EASE)

	# Bump the glass blur from build (0.6) to ready (0.85) so
	# the world reads as more "behind frosted glass" when the
	# gate is the player's primary focus. The dim stays at the
	# same alpha - what changes is the visual texture of the
	# glass, not how much of the world shows through.
	tween.parallel().tween_method(_set_glass_blur, 0.6, 0.85, BEZEL_BORDER_EASE)

	# Light the bezel status lamps. Same instant - the
	# design is "the system is online, all at once", not
	# "the system powers up sequentially".
	for lamp in _bezel_lamps:
		lamp.color = READY_BORDER

	# Status label flips to "ALL SYSTEMS READY" with the
	# SIGNAL_GO colour so the label and the bezel read as
	# the same moment. The step label drops the "Preparing"
	# prefix in favour of "Ready".
	# Operations between stages (locked decision in §7) prepends
	# the engagement number: "ENGAGEMENT 3 OF 5 — ALL SYSTEMS
	# READY". The rule set is the source of truth; an absent
	# rule set (e.g. test fixture) falls through to the
	# Skirmish copy.
	_status_label.text = _ready_status_text()
	_status_label.add_theme_color_override("font_color", READY_BORDER)
	_step_label.text = "Ready"

	# Button enable. The disabled -> enabled transition is
	# one Tokens.DURATION_NORMAL ease; StampedButton owns
	# the visual transition (its pressed/hover state
	# pipeline uses the same constant), so just flipping
	# disabled = false is enough.
	_button.disabled = false
	_button.grab_focus()


# The status label's ready-state copy. "ALL SYSTEMS READY" for
# Skirmish, "ENGAGEMENT N OF M — ALL SYSTEMS READY" for
# Operations, with the N/M read from the rule set the
# match_setup / operations_setup screens wrote into the
# MatchConfig autoload. Test Range is rare on the deploy
# gate (the chase-camera path bypasses Battle.tscn for
# now) but if it ever shows up, fall through to the
# Skirmish copy.
func _ready_status_text() -> String:
	if _director == null:
		return "ALL SYSTEMS READY"
	# `_match_rule_set` is the cached rule set match_director.gd
	# resolved from /root/MatchConfig in _ready(). The leading
	# underscore is convention, not access control - the gate
	# reads it because it has no other path to "is this an
	# Operations match", and the director publishes it for
	# exactly that reason.
	if not ("_match_rule_set" in _director):
		return "ALL SYSTEMS READY"
	var rs = _director._match_rule_set
	if rs == null:
		return "ALL SYSTEMS READY"
	if rs.mode == MatchRuleSetScript.Mode.OPERATIONS:
		# Read the OperationsManager autoload for the current
		# stage pointer and total. The rule set carries
		# operation_id and stage_index; the manager's
		# total_stages is the itinerary length, the same
		# number operations_setup built.
		var ops := get_tree().root.get_node_or_null("OperationsManager")
		if ops == null:
			return "ALL SYSTEMS READY"
		var n: int = int(ops.current_stage) + 1
		var total: int = int(ops.total_stages)
		return "ENGAGEMENT %d OF %d — ALL SYSTEMS READY" % [n, total]
	return "ALL SYSTEMS READY"


# Emitted via the deploy_pressed signal; the router awaits
# this and calls dismiss() in response. The button's own
# pressed signal is what fires this; UIAnimScript / the
# StampedButton state pipeline handle the visual feedback.
func _on_deploy_pressed() -> void:
	if _state != "ready":
		return
	deploy_pressed.emit()


# The gate's exit. Unpauses the tree, fades the glass to
# clear, and frees itself. The router calls this from
# `await gate.deploy_pressed` -> `gate.dismiss()`.
func dismiss() -> void:
	if _state == "dismissed":
		return
	_state = "dismissed"
	get_tree().paused = false
	# Fade the glass to clear over DURATION_NORMAL. The
	# shader writes its own alpha, so the tween drives the
	# `alpha` shader parameter rather than the ColorRect's
	# modulate.a - mixing the two would compound the fade
	# (modulate.a * shader_alpha) and make the math
	# non-obvious. The scene-router's fade_in is the next
	# transition; the two together read as one continuous
	# lift.
	var tween := create_tween()
	tween.tween_method(_set_glass_alpha, 0.45, 0.0, DISMISS_FADE)
	await tween.finished
	queue_free()


# Helper for the dismiss tween. tween_method's callable
# passes (value_from_interpolation), so the signature takes
# one float. The shader parameter is the same `alpha` the
# _build_glass() default wrote; tweening it from 0.45 (the
# build state) to 0.0 (the dismissed state) is the dismiss
# fade.
func _set_glass_alpha(value: float) -> void:
	if _glass == null or _glass.material == null:
		return
	(_glass.material as ShaderMaterial).set_shader_parameter("alpha", value)


# Helper for the mark_ready blur bump. Same pattern as
# _set_glass_alpha; the dismiss alpha uses one helper, the
# ready-state blur uses another, neither would compose well
# into a single tween_method because they touch different
# shader parameters and run at different times.
func _set_glass_blur(value: float) -> void:
	if _glass == null or _glass.material == null:
		return
	(_glass.material as ShaderMaterial).set_shader_parameter("blur_amount", value)


# --- Internal -----------------------------------------------------------------

# Match director's progress signal handler. Updates the bar
# and the step label. The 1.0 emission is the mark-ready
# moment; the polling loop would also catch it, but the
# signal is the more direct path and arrives on the same
# frame.
func _on_progress(fraction: float, label: String) -> void:
	_bar.value = clampf(fraction, 0.0, 1.0)
	if label != "" and is_instance_valid(_step_label):
		_step_label.text = label
	if fraction >= 1.0 and _state == "build":
		mark_ready()


# Polls world_is_ready every frame. A signal would be a
# cleaner contract, but the polled flag handles the race
# where the world finishes building BEFORE start() runs -
# a signal already emitted is a signal that never arrives.
# The poll is a no-op cost (one bool read per frame) and
# exits the moment the flag flips, or at READY_TIMEOUT if
# the world never finishes building.
func _poll_world_is_ready() -> void:
	if _director == null:
		return
	var waited := 0.0
	while _state == "build":
		if "world_is_ready" in _director and _director.world_is_ready:
			mark_ready()
			return
		if waited >= READY_TIMEOUT:
			# World is broken or stuck. Force the gate to the
			# ready state so the player can still press DEPLOY
			# and (best case) recover, rather than sitting on a
			# glass overlay forever.
			push_warning("DeployGate: world_is_ready never flipped after %.1fs, forcing ready" % READY_TIMEOUT)
			mark_ready()
			return
		await get_tree().process_frame
		waited += get_process_delta_time()
