extends Control
# The screen shown while the SceneRouter loads the next scene.
#
# THE TWO PHASES THIS SCREEN NOW COVERS.
#
# Phase 1 - WARM LIST (script preloads). The router walks the scene's
# preload graph one node per frame so the bar moves. During this
# phase the screen looks the same as it always has: status, step
# label, lamps, progress bar.
#
# Phase 2 - WORLD BUILD (only for Battle.tscn). After the warm list
# the router hands the loaded Battle PackedScene to this screen via
# attach_battle_scene(). The screen instantiates it as a hidden
# child of /root, pauses the tree, and waits for the match
# director's `world_ready` signal. While it waits, the live 3D
# vehicle preview (see LoadingPreview) cycles through the player's
# roster in their own livery - which is the whole reason the user
# asked for a non-deploy-gate version of this screen. The
# frosted-glass deploy gate is gone; this is a plain instrument
# panel with a hangar preview behind it.
#
# When world_ready fires, the screen shows a DEPLOY button. The
# player presses it, the screen fades itself out, and emits
# `deploy_requested(battle_instance)`. The router awaits that
# signal, unpauses the tree, and calls change_scene_to(battle) to
# make the already-built Battle the current scene.
#
# WHY PROCESS_MODE_ALWAYS. When the tree is paused (after
# attach_battle_scene) the lamps and the preview would freeze
# without this. ALWAYS keeps the loading screen's _process firing
# through the pause, so the lamps still march and the turntable
# still rotates. The Battle scene stays paused - we only keep
# THIS screen alive.
#
# Styled as instrument panel rather than as a spinner - a row of lamps
# marching across a stamped bezel is the same visual family as the rest
# of the chrome, and it degrades gracefully if the load finishes instantly.

const UITheme = preload("res://scripts/ui_theme.gd")
const UIShell = preload("res://scripts/ui_shell.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const UILampsScript = preload("res://scripts/ui_lamps.gd")
const StampedButtonScript = preload("res://scripts/ui_stamped_button.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")

# DEPLOY button geometry. Lifted from the retired deploy gate so the
# loading screen's button is the same physical object the player used
# to click in the gate - a 280x52 stamped plate, not a generic button.
const DEPLOY_BUTTON_MIN_SIZE := Vector2(280, 52)

# How long the loading screen's own fade takes on DEPLOY. Short -
# the match is ready, the player has clicked, the moment is
# "go" not "wait". A second-long fade here would read as the
# game hesitating after the player's decision.
const DEPLOY_FADE_SECONDS := 0.4

# Emitted when the player presses DEPLOY. Carries the already-built
# Battle instance so the router does not have to re-instantiate
# (which would re-run the multi-second world build). See
# scene_router.gd's run_load for the receiving end.
signal deploy_requested(battle: Node)

var _context: String = ""
var _bar: ProgressBar
var _lamps: UILamps
var _elapsed: float = 0.0
var _status_label: Label
var _step_label: Label
var _deploy_button: StampedButton
# The LoadingPreview Control, so we can hand it the match roster
# after attach_battle_scene() has run. Stored here because
# attach_battle_scene() is called by the router in a separate
# function from the _ready() that created the preview, and the
# preview reference is otherwise local to the VBoxContainer.
var _preview: Control = null

# The Battle scene once it has been instantiated and is waiting in
# the tree. Null until attach_battle_scene() runs, null again after
# the router takes ownership on deploy_requested.
var _attached_battle: Node = null

# Latch for the deferred roster filter. The match director populates
# its `roster` array in _load_roster() at ~70% progress, AFTER
# attach_battle_scene() has already returned and read the (empty)
# default. We capture the first non-empty roster in
# _on_director_progress() and call set_roster exactly once, so the
# preview switches from the player's library to the match's actual
# designs without flicker.
var _roster_filtered: bool = false

# CanvasLayer nodes the Battle's _build_hud adds during the world
# build. Node.visible = false on the Battle parent does NOT reliably
# propagate to CanvasLayer in Godot 4 (CanvasLayer has its own
# render path, independent of its parent's visible flag), so the
# BattleHUD would otherwise draw on top of the loading screen.
# _on_battle_child_entered() hides each CanvasLayer as it arrives
# and tracks it here; _on_deploy_pressed() un-hides them on the
# way out so the HUD appears with the world, not before.
var _hidden_canvas_layers: Array = []


func _ready() -> void:
	# See "WHY PROCESS_MODE_ALWAYS" above. The tree is paused while
	# the Battle builds, and the lamps / preview / status text need
	# to keep ticking through that. Battle nodes (PROCESS_MODE_INHERIT
	# by default) are paused correctly.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# SceneRouter can't configure the instance change_scene_to_packed()
	# builds, so the context is handed over through the autoload.
	var router = get_node_or_null("/root/SceneRouter")
	if router and "pending_context" in router and router.pending_context != "":
		_context = router.pending_context

	# Out-of-match screen - sits on the workbench, not on the in-match steel.
	# Chipboard reads as the bench under the loading hardware, and the
	# segment lamps / progress bar are easier to read against its visible
	# grain than against the steel backdrop the in-match screens use.
	UIShell.workbench(self, "chipboard")
	# Canonical screen frame. Was 72/72/56/48 - none of those are spacing tokens,
	# and it made the loading screen's content sit visibly further in than the
	# screen it transitions to, so the frame appeared to jump on arrival.
	var frame := UIShell.screen_frame(self)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.SPACE_SM)
	frame.add_child(col)

	# The 3D vehicle preview sits in the top slot for the long Battle
	# build; the short Lab boot keeps the empty filler because the
	# SubViewport cost would dominate the wait it exists to soften.
	# The preview script self-hides if the router's target is not
	# Battle or the player's roster is empty, so the fallback is
	# just a plain filler Control - same look as before this was
	# added.
	if router and router.has_method("current_target_path"):
		var _rpath: String = router.current_target_path()
		if _rpath == "res://scenes/Battle.tscn":
			var preview_scene: PackedScene = load("res://scenes/LoadingPreview.tscn")
			if preview_scene != null:
				var preview: Control = preview_scene.instantiate()
				preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
				# Min height so the labels below always have room, even on
				# a very short window. The SubViewport scales to whatever
				# it ends up with; this is a layout floor not a fixed size.
				preview.custom_minimum_size = Vector2(0, 200)
				col.add_child(preview)
				# Stash the reference so attach_battle_scene() can
				# hand the preview the match roster after the Battle
				# has built it. See attach_battle_scene() for the
				# timing on this - the Battle is instantiated here in
				# the SAME _ready, and its synchronous portion of
				# _ready populates the match_director.roster array
				# before the first await.
				_preview = preview
			else:
				var push = Control.new()
				push.size_flags_vertical = Control.SIZE_EXPAND_FILL
				col.add_child(push)
		else:
			# Not a Battle load (Lab, etc.). The 3D preview costs a
			# SubViewport + lights + turntable, which would dominate
			# the short Lab boot it would otherwise appear in front
			# of. The empty filler keeps the layout from collapsing.
			var push = Control.new()
			push.size_flags_vertical = Control.SIZE_EXPAND_FILL
			col.add_child(push)
	else:
		# No router or no current_target_path - the same situation
		# as the non-Battle branch above, with the same reason for
		# the empty filler. Reaching this branch on a real playtest
		# would mean SceneRouter wasn't autoloaded, which is a
		# project.godot regression - a pushed error there is more
		# useful than a silent fall-through.
		push_error("LoadingScreen: SceneRouter missing or has no current_target_path; no preview")
		var push = Control.new()
		push.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(push)

	_status_label = Label.new()
	_status_label.text = "PREPARING DEPLOYMENT"
	_status_label.theme_type_variation = "TitleLabel"
	col.add_child(_status_label)

	if _context != "":
		var ctx = Label.new()
		ctx.text = _context
		ctx.theme_type_variation = "HintLabel"
		col.add_child(ctx)

	# Names the step currently running. Real per-step reporting is the whole
	# reason the load is walked incrementally rather than done in one call -
	# a bar that only moves twice is barely better than no bar.
	_step_label = Label.new()
	_step_label.text = "Preparing"
	_step_label.theme_type_variation = "StatLabel"
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

	# DEPLOY button. NOT a child of the VBox - the user wants it in
	# the big open space on the LEFT of the 3D preview, not stacked
	# below the bar. A child of the loading screen itself with
	# absolute positioning (anchor_left = 0, anchor_top vertically
	# centered) lands it next to the preview, where the empty
	# SubViewport clear color leaves room for it.
	#
	# Hidden until world_ready fires. Same physical object the
	# deploy gate used so the click target feels familiar.
	# UIFeedbackScript.wire() attaches the same hover/press audio
	# the gate's button had, so the player's existing muscle
	# memory carries over.
	_deploy_button = StampedButtonScript.new()
	_deploy_button.legend = "DEPLOY FORCES"
	_deploy_button.variant = StampedButtonScript.Variant.PRIMARY
	_deploy_button.custom_minimum_size = DEPLOY_BUTTON_MIN_SIZE
	_deploy_button.disabled = true
	_deploy_button.visible = false
	_deploy_button.pressed.connect(_on_deploy_pressed)
	UIFeedbackScript.wire(_deploy_button, "confirm")
	# Anchor on the left, vertically centered. Offsets measured
	# from the button's own min size so a future size tweak
	# (280x52 -> 320x56) keeps it on the same spot without
	# re-deriving the constants.
	_deploy_button.anchor_left = 0.0
	_deploy_button.anchor_right = 0.0
	_deploy_button.anchor_top = 0.5
	_deploy_button.anchor_bottom = 0.5
	_deploy_button.offset_left = Tokens.SPACE_LG
	_deploy_button.offset_right = Tokens.SPACE_LG + DEPLOY_BUTTON_MIN_SIZE.x
	_deploy_button.offset_top = -DEPLOY_BUTTON_MIN_SIZE.y * 0.5
	_deploy_button.offset_bottom = DEPLOY_BUTTON_MIN_SIZE.y * 0.5
	add_child(_deploy_button)

	if router and router.has_signal("load_progress"):
		router.load_progress.connect(_on_progress)

	set_process(true)

	# Start the load only AFTER this screen has actually rendered a couple of
	# frames. Kicking it off in _ready() means the first blocking step runs
	# before anything reaches the swap chain, and the player sees the old
	# screen sit frozen instead of seeing this one appear.
	if router and router.has_method("run_load"):
		await get_tree().process_frame
		await get_tree().process_frame
		router.run_load()


func _on_progress(fraction: float, label: String = "") -> void:
	_bar.value = clampf(fraction, 0.0, 1.0)
	if label != "" and is_instance_valid(_step_label):
		_step_label.text = label


# Phase 2 entry point. Called by SceneRouter.run_load after the
# warm list has finished, with the PackedScene it loaded.
#
# Instantiates the Battle as a child of /root, HIDDEN, and pauses
# the tree so nothing in Battle ticks while it builds. _ready() on
# the Battle still runs (adding to the tree is what triggers
# _ready), so the world starts building immediately. Its deferred
# navmesh bake continues to make progress because process_frame
# on the SceneTree fires regardless of pause - the worker
# thread's completion callbacks are marshalled to the main thread
# via call_deferred, which lands in the next idle frame even while
# paused.
#
# WHY visible = false FROM THE START. Battle.tscn's Camera3D has
# `current = true`. The moment a node with a current camera enters
# the tree, that camera becomes the active render camera, and
# anything it can see (the sky, the empty world before terrain
# builds, etc.) is drawn. With the loading screen on top, the 3D
# would still bleed through any transparent parts of the chrome
# AND cost GPU work rendering a world the player is not supposed
# to see. Hidden from t=0 keeps the loading screen the only thing
# the player sees. The router un-hides on DEPLOY, just before
# change_scene_to.
func attach_battle_scene(packed: PackedScene) -> void:
	if packed == null:
		return
	# Reset the deferred-roster latch - a second Battle boot in the
	# same session (a player that hits DEPLOY, returns to menu, and
	# launches another match) needs to re-filter the preview to
	# the new match's roster, not skip it because the previous
	# match's filter is still latched true.
	_roster_filtered = false
	_hidden_canvas_layers.clear()
	_attached_battle = packed.instantiate()
	# Renamed so it doesn't collide with any in-scene node named
	# "Battle" if the router ever instantiates two. The router
	# changes scene to this node on DEPLOY; the name doesn't matter
	# after that.
	_attached_battle.name = "BattlePending"
	# Hidden so the Battle's Camera3D does not draw the sky / empty
	# world behind the loading screen. Un-hidden by the router on
	# DEPLOY, just before change_scene_to. Set BEFORE add_child so
	# the Battle's _ready runs with the visibility it should have
	# for the entire wait - if any child flips visibility during
	# _ready, that flip lands inside an already-hidden parent and
	# the child stays hidden too.
	_attached_battle.visible = false
	# PROCESS_MODE_DISABLED stops the Battle's _process / _physics_process
	# from running at all - belt-and-braces with the tree.paused
	# gate below. _ready still runs (PROCESS_MODE_DISABLED does NOT
	# suppress _ready, only _process / _physics_process), so the
	# world build runs.
	_attached_battle.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(_attached_battle)
	# Pause so units don't start moving, projectiles don't fire, and
	# the economy doesn't tick during the build. Loading screen's
	# process_mode = ALWAYS keeps its own lamps / preview alive.
	get_tree().paused = true

	# The Battle's _build_hud() (called at ~83% progress in the
	# match director's _ready coroutine) creates a CanvasLayer named
	# "UI" and parents the BattleHUD, production HUD, admin menu,
	# selection rect, and HUD hint to it. Node.visible = false on
	# the Battle parent does NOT propagate to CanvasLayer children
	# in Godot 4 (the CanvasLayer has its own render path and its
	# own visible flag) - the BattleHUD would draw on top of the
	# loading screen regardless. The fix is to hook
	# child_entered_tree on the Battle and hide any CanvasLayer
	# that arrives during the build, tracking each one so we can
	# un-hide on DEPLOY. child_entered_tree is the right signal
	# here (not child_order_changed or a polled walk) because it
	# fires synchronously inside add_child, before the new node's
	# own _ready has a chance to put UI on screen for a frame.
	_attached_battle.child_entered_tree.connect(_on_battle_child_entered)

	# THE BATTLE ROOT IS THE DIRECTOR. match_director.gd is attached
	# to the [node name="Battle" type="Node3D"] root in Battle.tscn,
	# not to a child named "MatchDirector". A previous version of
	# this code looked for a child and silently failed to connect
	# the world_ready signal, which meant _on_world_ready never
	# fired, the DEPLOY button never appeared, and the user was
	# stuck on the loading screen for the entire build.
	var director = _attached_battle
	if director == null:
		push_error("LoadingScreen: _attached_battle is null after add_child")
		return

	# Forward the director's own progress events to the local bar /
	# step label so the player sees "Surveying terrain" / "Settling
	# structures" cycle through during the world build. The director
	# emits 0.0..1.0 across the build, and 1.0 fires world_ready.
	if director.has_signal("progress"):
		director.progress.connect(_on_director_progress)
	if director.has_signal("world_ready"):
		director.world_ready.connect(_on_world_ready)

	# ROSTER FILTERING. The preview script's set_roster() takes the
	# match's actual designs so the player sees what they're about
	# to field, not the entire library. The director's `roster` is
	# populated by _load_roster() at ~70% progress (after the
	# "Indexing designs" beat), which is well AFTER this function
	# returns - add_child only triggers the synchronous portion of
	# the director's _ready up to the first await, and that portion
	# is the camera-mode resolution and the rule-set caching, not
	# the roster load. Reading director.roster HERE returns the
	# default [] and the preview's set_roster([]) hides the
	# preview, which collapses the loading screen's layout: the
	# 3D preview Control is gone, the VBox re-flows, the labels
	# and bar stack at the top, and the SubViewport's render
	# target (still on UPDATE_ALWAYS, still clearing to black)
	# covers the chipboard backdrop.
	#
	# The fix is to defer the filter until the roster is actually
	# in. _on_director_progress() runs every progress emission; the
	# first non-empty read of director.roster is the one to use,
	# and we latch a flag so we only call set_roster once (the
	# roster does not change after _load_roster returns).
	# Until then, the preview keeps cycling through the player's
	# library - the same set the menu shows, the same set the
	# preview was already showing in the warm-list phase.

	# Update the screen chrome for Phase 2.
	_status_label.text = "BUILDING BATTLEFIELD"
	_step_label.text = "Initializing systems..."
	# Reset the bar to 0 so the world-build stretch starts fresh;
	# the warm-list stretch already filled it to warm/total.
	_bar.value = 0.0


# Director progress (0.05..1.00 during world build) feeds the local
# step label. Lives on the loading screen rather than the deploy
# gate because the gate is gone; the loading screen now owns
# reading and displaying this stretch.
func _on_director_progress(fraction: float, label: String) -> void:
	# The director's progress is a fraction of its own build (not
	# of the overall load). Render it as a normalized 0..1 on the
	# bar so the player sees it climb from 0 to 1 during the build.
	_bar.value = clampf(fraction, 0.0, 1.0)
	if label != "" and is_instance_valid(_step_label):
		_step_label.text = label

	# DEFERRED ROSTER FILTER. The match director's _load_roster()
	# runs at ~70% progress, after add_child has returned to
	# attach_battle_scene() and so after the synchronous read in
	# there could only see the default []. We catch the first
	# non-empty roster here and feed it to the preview. The latch
	# keeps set_roster from being called on every progress emit
	# after the roster is in - it's a one-shot filter.
	if not _roster_filtered and _preview != null and _preview.has_method("set_roster") \
			and _attached_battle != null and is_instance_valid(_attached_battle) \
			and "roster" in _attached_battle:
		var r: Array = _attached_battle.get("roster")
		if r.size() > 0:
			_preview.call("set_roster", r)
			_roster_filtered = true


# Called when the match director flips world_ready. The build is
# done; the player is now committed. Show DEPLOY.
func _on_world_ready() -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = "ALL SYSTEMS READY"
	_step_label.text = "Press DEPLOY to begin engagement"
	# Bring the bar to its terminal state. The director's last
	# progress emit should already have done this, but the
	# "all systems ready" hand-off is the moment the player is
	# explicitly told the wait is over; an under-filled bar would
	# contradict the label.
	_bar.value = 1.0
	# Reveal and arm the button. grab_focus so the player can
	# press Enter without aiming at it - same as the deploy gate.
	_deploy_button.disabled = false
	_deploy_button.visible = true
	_deploy_button.grab_focus()


# Catches the CanvasLayer(s) the Battle's _build_hud() adds during
# the world build. See attach_battle_scene() for the why - Node
# visibility does not propagate to CanvasLayer in Godot 4, so the
# BattleHUD would otherwise draw on top of the loading screen
# while the world is still building.
#
# We track the layer rather than just un-hiding it by name on
# DEPLOY, because:
#   1. The match director adds the UI CanvasLayer; nothing else
#      does during the world build, but a future subsystem could.
#   2. The signal fires from inside add_child, before the new
#      node's _ready runs, so the hide lands before any of its
#      UI is on screen for even a frame.
func _on_battle_child_entered(node: Node) -> void:
	if node is CanvasLayer and node.name == "UI":
		node.visible = false
		_hidden_canvas_layers.append(node)


# DEPLOY pressed. Reveal the Battle and fade the loading screen
# out, then tell the router to swap current_scene. The signal
# carries _attached_battle so the router can pass it straight
# to the scene tree without re-instantiating.
#
# WHY THE BATTLE IS REVEALED HERE, NOT IN THE ROUTER. The router
# used to set battle.visible = true just before its
# change_scene_to(battle) call. change_scene_to(node) is not a
# SceneTree API in Godot 4.7 - the only reparent-the-current-scene
# entry point is change_scene_to_packed() which re-instantiates
# (the multi-second world build we set out to avoid). The fix
# is to set current_scene directly: get_tree().current_scene =
# battle. The router now does that, but the visible+process_mode
# flip is this screen's job - the Battle has to be showing for
# the 0.4s modulate-a fade to reveal it, otherwise the player
# watches the loading screen fade out onto black.
#
# If anything went wrong and there's no attached Battle, this is
# a silent no-op rather than a stranded player - the loading
# screen stays up, the tree stays paused, and the developer sees
# the attached_battle being null in the next debugger session.
func _on_deploy_pressed() -> void:
	if _attached_battle == null:
		push_warning("LoadingScreen: DEPLOY pressed with no attached Battle")
		return
	_deploy_button.disabled = true
	# Reveal the Battle BEFORE the fade starts so the 0.4s modulate
	# uncovers the world underneath, not a black viewport. The tree
	# is still paused at this point (the router unpauses after the
	# signal lands), so the Battle's process_mode = INHERIT
	# children stay paused - units don't start moving, the
	# economy doesn't tick. The Battle's Camera3D with
	# current = true does render (camera rendering is part of
	# the engine loop, not the script process loop, and is
	# unaffected by pause), which is the whole point - the
	# player needs to see what they're about to engage.
	_attached_battle.visible = true
	_attached_battle.process_mode = Node.PROCESS_MODE_INHERIT
	# Un-hide the CanvasLayer(s) we hid during the build. Their
	# own _ready has long since finished, so un-hiding lands
	# them fully populated and ready to interact. The list is
	# cleared on the way out - a second match boot in the same
	# session starts with a clean slate.
	for layer in _hidden_canvas_layers:
		if is_instance_valid(layer):
			layer.visible = true
	_hidden_canvas_layers.clear()
	# Fade the loading screen out. Modulate.a tween is the lightest
	# option; a `visible = false` would skip the fade and feel
	# like a hard cut. The router's queue_free() then drops this
	# node at the next idle frame, which lands at modulate.a == 0
	# and never flashes.
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, DEPLOY_FADE_SECONDS)
	await tween.finished
	deploy_requested.emit(_attached_battle)


func _process(delta: float) -> void:
	_elapsed += delta
	# Lamps own their own _process / queue_redraw since the 2026-08-13
	# lift into scripts/ui_lamps.gd - this function is just the
	# "STAND BY" text escalation now.

	# After a few seconds, say something rather than leaving the player
	# staring at an unexplained wait. Phrased for the warm-list phase
	# only; the BUILDING BATTLEFIELD label set in attach_battle_scene
	# overrides this once the world build starts.
	if _elapsed > 4.0 and is_instance_valid(_status_label) \
			and _status_label.text == "PREPARING DEPLOYMENT":
		_status_label.text = "PREPARING DEPLOYMENT - STAND BY"
