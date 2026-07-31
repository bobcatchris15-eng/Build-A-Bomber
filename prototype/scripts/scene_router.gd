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
#         battle_unit.gd            157 ms
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
signal load_finished()

const LOADING_SCENE := "res://scenes/Loading.tscn"

# Scene -> the script whose preload graph carries its weight. Only scenes
# that actually stall need an entry; anything else loads directly.
const WARM_SOURCES := {
	"res://scenes/Skirmish.tscn": "res://scripts/skirmish.gd",
	"res://scenes/MainLab.tscn": "res://scripts/module_placer.gd",
	"res://scenes/Battlefield.tscn": "res://scripts/battlefield.gd",
}

var _target_path: String = ""
var _loading: bool = false
var pending_context: String = ""


# Switches to the loading screen, which then calls run_load() once it has
# actually rendered. The order matters: an earlier version started the load
# first and swapped scenes after, but change_scene_to_file() is deferred, so
# the loading screen never got a frame before the blocking work began - it
# was never visible at all.
func change_scene_async(path: String, context: String = "") -> void:
	if _loading:
		return
	if not ResourceLoader.exists(path):
		push_error("SceneRouter: no such scene '%s'" % path)
		return
	_target_path = path
	pending_context = context
	get_tree().change_scene_to_file(LOADING_SCENE)


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
	load_finished.emit()

	_loading = false
	if packed == null:
		push_error("SceneRouter: failed to load '%s'" % _target_path)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	get_tree().change_scene_to_packed(packed)


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
	"faction_catalog": "Confirming faction records",
	"skirmish": "Assembling battlefield",
}

func _label_for(path: String) -> String:
	var stem := path.get_file().get_basename()
	return STEP_LABELS.get(stem, "Loading %s" % stem.replace("_", " "))


func is_loading() -> bool:
	return _loading
