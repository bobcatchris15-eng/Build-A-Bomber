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
	load_progress.emit(1.0, "Ready")

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

	# Fade out over the loading screen before the swap. Skipping this is what
	# would make the whole transition read as fading INTO a loading screen and
	# then hard-cutting into the match, which is worse than no fade at all -
	# an inconsistent transition draws more attention than an absent one.
	await fade_out()
	get_tree().change_scene_to_packed(packed)
	# Skirmish's _ready() does substantial work (terrain, navmesh, spawns). Two
	# frames rather than one, so the fade lifts on a built battlefield instead of
	# on an empty stage that then pops into existence.
	await get_tree().process_frame
	await get_tree().process_frame
	# The world finishes building BEHIND the black, then the player chooses when
	# to drop in. Both are no-ops for a scene that does not declare `world_ready`.
	await _await_world_ready()
	await _deploy_gate()
	await fade_in()
	_transitioning = false
	_target_path = ""


# Holds the fade until the incoming scene says it is playable.
#
# TWO FRAMES IS NOT A UNIVERSAL RULE. It is enough for a scene whose _ready()
# runs to completion synchronously, and wrong for one that awaits inside it:
# match_director._ready() awaits its terrain bake, so it RETURNS at that await
# and finishes many frames later. The fade lifted on a half-built Battle - bases
# spawned and floating over an unbuilt map, no terrain, no HUD - because the
# router had counted two frames and declared victory.
#
# Opt-in by convention rather than by type: any scene that declares `world_ready`
# gets waited on, and everything else keeps the old behaviour. The router does
# not need to know what a match is.
#
# THE TIMEOUT IS NOT OPTIONAL. If a scene errors out partway through its own
# setup the signal never fires, and without a ceiling the player sits on a black
# screen forever with no way back. Arriving early on a half-built map is bad;
# arriving never is worse.
const WORLD_READY_TIMEOUT := 30.0

func _await_world_ready() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_signal("world_ready"):
		return
	# Already finished while the fade was running. Awaiting a signal that has
	# ALREADY been emitted hangs forever, which is why the scene carries a flag
	# as well as a signal.
	if "world_is_ready" in scene and scene.world_is_ready:
		return
	# POLLED RATHER THAN AWAITED ON THE SIGNAL. `await` takes exactly one signal
	# and there is no "first of these two" form, so racing the signal against a
	# timeout means watching the flag the scene sets alongside it. That flag is
	# needed regardless - see the comment above - so this costs nothing extra.
	var waited := 0.0
	while not scene.world_is_ready and waited < WORLD_READY_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not is_instance_valid(scene):
			return


# The DEPLOY gate: the last beat of the loading sequence.
#
# The alternative is dropping the player straight into a live match the instant
# it finishes building, which is worse than it sounds - the match is REAL from
# frame one, the AI commander is already deciding and harvesters are already
# moving, so a player still reading the map is a player already behind. A button
# makes entry deliberate.
#
# It is drawn on the router's own fade overlay rather than on the loading screen,
# because by this point the loading screen has been freed: the world has to exist
# in order to be ready, and it cannot exist until the scene swap. The overlay is
# the only thing that survives that swap.
func _deploy_gate() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_signal("world_ready"):
		return

	var gate := CenterContainer.new()
	gate.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP so nothing behind the curtain can be clicked through it. The match is
	# already live at this point - a stray click landing on the battlefield would
	# issue a real order before the player has seen the map.
	gate.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_layer.add_child(gate)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.SPACE_MD)
	gate.add_child(col)

	var ready_label := Label.new()
	ready_label.text = "ALL SYSTEMS READY"
	ready_label.theme_type_variation = "HintLabel"
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(ready_label)

	var button := Button.new()
	button.text = "DEPLOY"
	button.custom_minimum_size = Vector2(260, 56)
	col.add_child(button)
	button.grab_focus()

	# HOLDS THE MATCH, not just the view. Without this the comment above is only
	# half-solved: the world would be built AND RUNNING while the player looked at
	# a DEPLOY button, so the AI commander would take its first decisions and the
	# harvesters their first trips before anyone had pressed anything.
	#
	# The overlay opts out of the pause it causes - a paused pause-screen cannot
	# be dismissed - and so does its own layer, or the button would not repaint.
	_fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	await button.pressed
	get_tree().paused = false
	gate.queue_free()


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


