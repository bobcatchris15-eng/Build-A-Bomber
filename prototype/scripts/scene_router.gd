extends Node
# Autoload: scene transitions that keep the window responsive.
#
# WHAT THE FREEZE ACTUALLY WAS (measured, not assumed - see
# scratch/probe_deps.gd and scratch/probe_preloads.gd):
#
#   loading Skirmish.tscn         ~1215 ms
#     of which skirmish.gd         ~978 ms
#       of which its 13 top-level `const X = preload(...)` targets ~968 ms
#         blueprint_manager.gd      479 ms
#         unit.gd (was battle_unit.gd pre-2026-08-10) ~157 ms
#         terrain_builder.gd         90 ms
#         building.gd                79 ms
#         ...
#
# So it is GDScript COMPILATION, not disk I/O and not _ready(). Two
# consequences, both of which cost a wrong fix before they were measured:
#
#   1. ResourceLoader.load_threaded_request() does not help. Verified: it
#      still produced a single ~1.2 s main-thread gap with only 2 main-loop
#      iterations. Script compilation lands on the main thread regardless of
#      which loader asked for it.
#   2. ResourceLoader.get_dependencies() does not see this. It reported 3
#      dependencies for a scene that takes over a second, because a
#      script-level preload() is not a resource dependency.
#
# WHAT DOES WORK: the chain is only atomic if you load the ROOT first.
# Loading each preload target individually is 10-480 ms apiece, so they can
# be walked one per frame with a yield in between. The main thread ticks
# between each, the loading screen animates, and progress is real. Total
# wall time is unchanged - the window just stops lying about being dead.

signal load_progress(fraction: float, label: String)
const LOADING_SCENE := "res://scenes/Loading.tscn"

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIAnimScript = preload("res://scripts/ui_anim.gd")

# ---------------------------------------------------------------------------
# TRANSITION FADE
# ---------------------------------------------------------------------------
# Every scene change used to be a hard cut. That is the single loudest "this is
# a prototype" tell in the whole interface: no amount of material and elevation
# work on a screen matters if arriving at it is a one-frame jump.
#
# THE OVERLAY LIVES ON THIS AUTOLOAD, which is the only reason this works. A
# fade rect owned by the outgoing scene is freed by change_scene_to_file()
# halfway through its own animation; one owned by the incoming scene cannot
# cover the gap before that scene exists. SceneRouter outlives every scene, so
# its overlay is continuous across the swap.
#
# It is a CanvasLayer at a high layer index rather than a Control added to the
# current scene, so it covers 3D viewports too - the Skirmish battlefield and
# the Design Lab canvas are 3D under 2D chrome, and a plain CanvasItem in the
# scene tree would fade the HUD while the world underneath jumped.
#
# BASE_900 because the palette already designates it "deepest recess, modal
# scrim" - the transition is the most modal thing in the game.
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null

# Scene -> the script whose preload graph carries its weight. Only scenes
# that actually stall need an entry; anything else loads directly.
const WARM_SOURCES := {
	"res://scenes/MainLab.tscn": "res://scripts/module_placer.gd",
	# The rebuilt battle layer. It stalls for the same reason Skirmish does -
	# match_director.gd's preload graph reaches blueprint_manager.gd and the unit
	# and terrain scripts - and without an entry here goto() swapped straight to
	# it, so the window simply froze on black instead of showing the lamps.
	# 2026-08-10: Battlefield.tscn / battlefield.gd retired in the
	# battle-system unification's Phase 4; the Test Range now boots
	# on Battle.tscn via TestRangeLauncher (see main_menu's PROVING
	# GROUND card and stat_calculator's "Test in Arena" button).
	"res://scenes/Battle.tscn": "res://scripts/battle/match_director.gd",
}

var _target_path: String = ""
var _loading: bool = false
var pending_context: String = ""

# Where the router is headed. Read-only by convention - mutating this
# from the outside would desync the router's own bookkeeping. Exists
# so the loading screen can decide whether the destination is the
# long-load Battle.tscn (worth a 3D preview) or the short-load
# MainLab.tscn (not). The router's own _target_path is otherwise a
# private implementation detail.
func current_target_path() -> String:
	return _target_path

# Guards against a second transition starting while one is mid-fade. `_loading`
# does not cover this: it is only set once run_load() begins, so it is false for
# the whole fade-out before the swap. Without this guard, double-clicking a
# destination card runs two goto() coroutines, which means two fade tweens
# fighting over the same rect and two change_scene calls.
var _transitioning: bool = false


func _ready() -> void:
	_fade_layer = CanvasLayer.new()
	# Above every in-scene CanvasLayer. The HUD layers sit in the single digits;
	# this has to be over all of them or a transition would fade the world and
	# leave the command bar floating on top of black.
	_fade_layer.layer = 128
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Tokens.BASE_900
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_rect.visible = false
	# IGNORE at rest, STOP mid-transition (see _set_blocking). A full-screen rect
	# that always swallowed input would make the entire game unclickable.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


func _set_blocking(blocking: bool) -> void:
	# Swallows clicks while the screen is covered. Without this a player can click
	# a button on a screen that is 90% faded out and queue an action against a
	# scene that is about to be freed.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP if blocking \
		else Control.MOUSE_FILTER_IGNORE


# Fades to opaque. Awaited by callers, so the swap happens on black.
func fade_out() -> void:
	if _fade_rect == null:
		return
	_set_blocking(true)
	_fade_rect.visible = true
	await UIAnimScript.fade(_fade_rect, 1.0, Tokens.DURATION_SLOW,
		_fade_rect.modulate.a).finished


# Fades back to clear and releases input.
#
# Deliberately faster than fade_out (NORMAL vs SLOW). Leaving a screen can take
# its time; arriving at one should not, because the player is already waiting to
# act on it. A symmetric slow fade-in is what makes a game feel sluggish rather
# than expensive.
func fade_in() -> void:
	if _fade_rect == null:
		return
	_fade_rect.visible = true
	await UIAnimScript.fade(_fade_rect, 0.0, Tokens.DURATION_NORMAL, 1.0).finished
	_fade_rect.visible = false
	_set_blocking(false)


# THE UNIVERSAL ENTRY POINT. Every scene change should come through here rather
# than calling get_tree().change_scene_to_file() directly, so the fade is not
# something each call site has to remember.
#
# Routes itself: a scene with a WARM_SOURCES entry stalls long enough to need the
# loading screen, and everything else swaps directly. Callers no longer have to
# know which is which - that was previously duplicated as an
# `if router: ... else: ...` at five call sites.
func goto(path: String, context: String = "") -> void:
	if _loading or _transitioning:
		return
	if not ResourceLoader.exists(path):
		push_error("SceneRouter: no such scene '%s'" % path)
		return
	if WARM_SOURCES.has(path):
		change_scene_async(path, context)
		return

	_transitioning = true
	await fade_out()
	get_tree().change_scene_to_file(path)
	# One frame for the incoming scene's _ready() to build its UI, so the fade
	# reveals a finished screen rather than a half-populated one.
	await get_tree().process_frame
	await fade_in()
	_transitioning = false


# Switches to the loading screen, which then calls run_load() once it has
# actually rendered. The order matters: an earlier version started the load
# first and swapped scenes after, but change_scene_to_file() is deferred, so
# the loading screen never got a frame before the blocking work began - it
# was never visible at all.
func change_scene_async(path: String, context: String = "") -> void:
	if _loading or _transitioning:
		return
	if not ResourceLoader.exists(path):
		push_error("SceneRouter: no such scene '%s'" % path)
		return
	_transitioning = true
	_target_path = path
	pending_context = context
	# Fade covers the swap to the loading screen, then lifts to reveal it. The
	# loading screen is a real screen the player reads progress on, so it gets the
	# same arrival treatment as any other - it is not a curtain to hide behind.
	await fade_out()
	get_tree().change_scene_to_file(LOADING_SCENE)
	await get_tree().process_frame
	await fade_in()


# Driven by the loading screen as a coroutine, so every `await` here is a
# real frame the throbber gets to animate on.
func run_load() -> void:
	if _loading or _target_path == "":
		return
	_loading = true

	var warm_list := _warm_list_for(_target_path)
	var total := warm_list.size() + 1  # +1 for the scene itself

	for i in range(warm_list.size()):
		var path: String = warm_list[i]
		load_progress.emit(float(i) / float(total), _label_for(path))
		# Yield BEFORE the expensive call, so the label and bar for this step
		# are on screen while it runs rather than after it finishes.
		await get_tree().process_frame
		if ResourceLoader.exists(path):
			ResourceLoader.load(path)

	load_progress.emit(float(warm_list.size()) / float(total), "Assembling battlefield")
	await get_tree().process_frame

	# Cache is warm now, so this is fast.
	var packed: PackedScene = load(_target_path)
	# 2026-08-13: the old 1.0 emission here was a latent bug exposed
	# by the new deploy gate's glass overlay. The bar would hit 100%
	# the moment the warm-list finished, then sit there while the
	# world assembled behind the glass. The match director now owns
	# the 0.05..1.00 stretch (see MatchDirector.progress and the
	# emission sites at the milestones in _ready()), and emits 1.0
	# at the same world_is_ready flip. The router's load_progress
	# signal is the warm-list stream only (0.0 -> warm/total); a
	# new subscriber (the deploy gate) reads match_director.progress
	# for the world-build stretch.

	_loading = false
	if packed == null:
		push_error("SceneRouter: failed to load '%s'" % _target_path)
		await fade_out()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		await get_tree().process_frame
		await fade_in()
		# Cleared on the failure path too, or a single failed load would leave the
		# router permanently refusing every subsequent transition.
		_transitioning = false
		_target_path = ""
		return

	# No fade between the warm list and the world-build phase. The
	# loading screen is what the player is looking at, and the
	# next thing they see is DEPLOY - there is no other screen to
	# transition TO. A fade here would read as the loading screen
	# going dark and coming back, which is exactly the "duplicate"
	# the user described.
	#
	# The loading screen also calls UIShell.workbench() in its
	# own _ready, which paints the chipboard L0 backdrop. The
	# fade rect was only needed for OLD screen -> NEW screen
	# transitions; with the new flow the loading screen IS the
	# only screen the player sees from the moment SceneRouter
	# fades in, until the moment DEPLOY swaps to Battle. So
	# there's no fade rect bookkeeping to do here.
	#
	# Two paths from here.
	#
	# Battle.tscn: hand the PackedScene to the loading screen. The
	# screen instantiates it as a HIDDEN child of /root (visible
	# = false so the Battle's Camera3D doesn't draw the sky behind
	# the loading screen), pauses the tree, and waits for
	# world_ready before showing a DEPLOY button. Re-instantiating
	# the Battle on the way out would re-run the multi-second
	# world build, so the screen hands back the SAME instance
	# it built.
	#
	# Everything else (Lab, etc.): the old fast path. No world
	# build, no DEPLOY - just swap scenes and fade in.
	if _target_path == "res://scenes/Battle.tscn":
		var loading_screen = get_tree().current_scene
		if loading_screen != null and loading_screen.has_method("attach_battle_scene"):
			loading_screen.attach_battle_scene(packed)
			# Awaiting a signal on another node: Godot 4 resolves
			# this at the await point. The signal carries the
			# already-built Battle instance.
			var battle = await loading_screen.deploy_requested
			# The loading screen has done two things by the time the
			# signal fires: faded itself to modulate.a == 0 and made
			# the Battle visible (and process_mode = INHERIT). The
			# tree is still paused; the loading screen's
			# attach_battle_scene() paused it so the world build
			# wouldn't tick. Unpause now so the Battle's INHERIT
			# children can run.
			get_tree().paused = false
			if battle != null and is_instance_valid(battle):
				# Rename to the canonical scene name. attach_battle_scene
				# used "BattlePending" to avoid colliding with the in-
				# scene "Battle" name; now that we're swapping, the
				# canonical name is what the router's debug logs and
				# any "res://scenes/Battle.tscn" reference expect.
				battle.name = "Battle"
				# Make the already-built Battle the current_scene.
				# change_scene_to_packed() would re-instantiate,
				# which is the multi-second world build we just did.
				# change_scene_to(node) does not exist on SceneTree
				# in Godot 4.7 (the only legacy form was on the
				# Viewport, and it's gone). The supported way to swap
				# to a pre-built instance is to write
				# current_scene directly - it's a settable property
				# in Godot 4.x. The loading screen is still a child
				# of /root from when the router
				# change_scene_to_file()'d it in; the current_scene
				# pointer is what gets read on the next frame for
				# input routing, and repointing it at the Battle is
				# the whole swap.
				get_tree().current_scene = battle
				# The loading screen is no longer the current_scene
				# but is still in the tree (faded to alpha 0). Free
				# it; the Battle is now the only scene node. queue_free
				# is deferred, so the next idle frame the loading
				# screen is gone and the Battle is fully on screen.
				loading_screen.queue_free()
			else:
				# Safety fallback: the loading screen gave us nothing.
				# Use the standard path so the player isn't stuck.
				push_warning("SceneRouter: deploy_requested had no Battle; falling back to change_scene_to_packed")
				get_tree().change_scene_to_packed(packed)
			await get_tree().process_frame
			await get_tree().process_frame
		else:
			# No loading screen with attach_battle_scene. Use the
			# safe-but-slow fallback so the player isn't stuck on
			# the warm list.
			push_warning("SceneRouter: current scene has no attach_battle_scene; falling back to direct change")
			get_tree().change_scene_to_packed(packed)
			await get_tree().process_frame
			await get_tree().process_frame
	else:
		# Non-Battle: Lab / other. Fast path. Change scene, fade
		# in, done.
		get_tree().change_scene_to_packed(packed)
		await get_tree().process_frame
		await get_tree().process_frame
		await fade_in()

	_transitioning = false
	_target_path = ""


# The DEPLOY gate (scripts/deploy_gate.gd) is RETIRED. The
# loading screen now owns the build -> DEPLOY handoff itself, on
# the same surface the warm list is shown on. The router's only
# remaining job at this beat is to hand the loaded PackedScene
# to the loading screen, await its deploy_requested signal, and
# call change_scene_to(battle) on the instance the screen built.
# Re-instantiating via change_scene_to_packed would re-run the
# world build.


# Extracts a scene's heavy preload targets from its script SOURCE.
#
# Derived rather than hand-listed so it can't silently go stale as the
# scripts change. Reading the text is microseconds; it's compiling it that
# costs, which is exactly the work being spread out. Recurses one level,
# because the heaviest entry (blueprint_manager.gd) has its own graph.
func _warm_list_for(scene_path: String) -> Array:
	if not WARM_SOURCES.has(scene_path):
		return []
	var root_script: String = WARM_SOURCES[scene_path]
	var seen := {}
	var out := []
	_collect_preloads(root_script, seen, out, 0)
	# Deepest-first: loading a leaf before its parent is what keeps any
	# single step small. The root script goes last.
	out.append(root_script)
	return out


func _collect_preloads(script_path: String, seen: Dictionary, out: Array, depth: int) -> void:
	if seen.has(script_path) or depth > 2:
		return
	seen[script_path] = true
	if not FileAccess.file_exists(script_path):
		return
	var src := FileAccess.get_file_as_string(script_path)
	var re := RegEx.new()
	re.compile('preload\\("(res://[^"]+\\.gd)"\\)')
	for m in re.search_all(src):
		var dep := m.get_string(1)
		if seen.has(dep) or dep in out:
			continue
		_collect_preloads(dep, seen, out, depth + 1)
		if dep not in out:
			out.append(dep)


# Turns a script path into something worth reading on a loading screen.
# Deadpan, matching the rest of the copy - it is describing preparation
# work, not narrating an adventure.
const STEP_LABELS := {
	"blueprint_manager": "Reading blueprints",
	"battle_unit": "Preparing vehicle systems",
	"terrain_builder": "Surveying terrain",
	"building": "Preparing structures",
	"enemy_ai": "Briefing opposition",
	"production_queue": "Opening production lines",
	"map_catalog": "Consulting map registry",
	"resource_node": "Locating resource deposits",
	"module_catalog": "Indexing modules",
	"livery": "Mixing paint",
	"skirmish": "Assembling battlefield",
	# The rebuilt battle layer's own graph. Without these every step on the way
	# into Battle reads as "Loading <script name>", which is the loading screen
	# admitting it does not know what it is doing.
	"match_director": "Assembling battlefield",
	"commander": "Briefing opposition",
	"economy_service": "Auditing stockpiles",
	"production_service": "Opening production lines",
	"structure": "Preparing structures",
	"unit": "Preparing vehicle systems",
	"vision_service": "Deploying sensors",
	"flow_field_service": "Plotting movement lanes",
	"placement_service": "Surveying build sites",
	"selection_service": "Calibrating controls",
	"order_service": "Calibrating controls",
	"battle_hud": "Raising command deck",
	"production_hud": "Raising command deck",
	"after_action_report": "Preparing debrief",
}

func _label_for(path: String) -> String:
	var stem := path.get_file().get_basename()
	return STEP_LABELS.get(stem, "Loading %s" % stem.replace("_", " "))
