extends Node
# OperationsManager (Autoload / Singleton)
# Manages multi-round Operations campaign state, tracking stage progression,
# map rotation, player/AI roster state, and target blueprint pre-selection
# for inter-round Design Lab iteration.

const MapCatalogScript = preload("res://scripts/map_catalog.gd")

signal operation_started(operation_data: Dictionary)
signal stage_completed(stage_index: int, results: Dictionary)
signal operation_completed(overall_results: Dictionary)

# How many engagements an operation may be. The floor is 3 because two rounds
# is not a campaign - there is only one draft between them, so nothing is
# learned twice. The ceiling is 12 because that is where the itinerary editor
# stops fitting a screen and where re-drafting stops being a decision.
const MIN_ENGAGEMENTS := 3
const MAX_ENGAGEMENTS := 12

# Current active Operation session data
var is_active_operation: bool = false
var current_stage: int = 0
var difficulty: String = "normal" # "easy", "normal", "hard"
var target_iteration_blueprint: String = "" # Blueprint name queued to open in Design Lab

# Stages itinerary: map IDs and AI difficulty parameters. Replaced wholesale by
# start_new_operation() when the setup screen passes one in; this default is
# what a campaign started without a screen (a test, a direct boot) gets.
var stages_itinerary: Array = default_itinerary(3, "normal")


# Total stages is the itinerary's length, not a separate field. It used to be
# both, and the two could disagree the moment a custom itinerary was passed in -
# start_new_operation() replaced the array and left the count at 3.
var total_stages: int:
	get:
		return stages_itinerary.size()


# The default rotation, for `count` engagements at a chosen difficulty.
#
# Static so the setup screen can read it without instantiating a manager it then
# has to free - which is what it used to do, one line before constructing a
# SECOND manager into /root.
static func default_itinerary(count: int, base_difficulty: String = "normal") -> Array:
	var maps := MapCatalogScript.get_map_ids()
	var out: Array = []
	var n: int = clampi(count, MIN_ENGAGEMENTS, MAX_ENGAGEMENTS)
	for i in range(n):
		out.append({
			"map_id": str(maps[i % maps.size()]) if not maps.is_empty() else "open_plains",
			"ai_difficulty": ramped_difficulty(i, n, base_difficulty),
			"title": "Engagement %d" % (i + 1),
		})
	return out


# An operation ramps: the chosen difficulty is where it ENDS, not a flat setting
# applied to every round. The first third opens one tier easier so the opening
# engagement is a place to find out what your roster does wrong, and the last
# third is the tier that was actually picked.
static func ramped_difficulty(index: int, count: int, base_difficulty: String) -> String:
	var tiers := ["easy", "normal", "hard"]
	var top: int = maxi(0, tiers.find(base_difficulty))
	if count <= 1 or top <= 0:
		return tiers[top]
	# Rounds map onto [top-1 .. top], spending the first third below.
	var progress: float = float(index) / float(count - 1)
	return tiers[top - 1] if progress < 0.34 else tiers[top]

# Round history tracking
var stage_results_history: Array = []

func start_new_operation(custom_itinerary: Array = [], selected_difficulty: String = "normal") -> void:
	is_active_operation = true
	current_stage = 0
	difficulty = selected_difficulty
	stage_results_history.clear()
	target_iteration_blueprint = ""
	player_roster_paths.clear()
	operation_id = _new_operation_id()

	if not custom_itinerary.is_empty():
		stages_itinerary = custom_itinerary.duplicate(true)

	operation_started.emit({
		"stages": stages_itinerary,
		"difficulty": difficulty
	})
	save()

func get_current_stage_info() -> Dictionary:
	if current_stage >= 0 and current_stage < stages_itinerary.size():
		return stages_itinerary[current_stage]
	return {}

# The combat log, one entry per finished engagement. `stage_stats` is
# MatchStats.to_report() plus who won, what each side fielded, and how long it
# took - which is everything counter-drafting needs to read later, recorded at
# the only moment it is all still in one place.
func record_stage_result(stage_stats: Dictionary) -> void:
	var entry: Dictionary = stage_stats.duplicate(true)
	entry["stage"] = current_stage
	entry["map_id"] = str(get_current_stage_info().get("map_id", ""))
	stage_results_history.append(entry)
	stage_completed.emit(current_stage, entry)
	save()


func advance_to_next_stage() -> bool:
	current_stage += 1
	if current_stage >= stages_itinerary.size():
		is_active_operation = false
		operation_completed.emit({"history": stage_results_history})
		save()
		return false
	save()
	return true


# Whether there is another engagement after the one just finished. Asked by the
# after-action report to decide between "Next Engagement" and "Operation
# Complete", and it must NOT be answered by advancing - the report is shown
# before the player has chosen to go on.
func has_next_stage() -> bool:
	return is_active_operation and current_stage + 1 < stages_itinerary.size()


# What the player fielded going into the next engagement. Set by the draft
# screen, read by MatchConfig on the way into the match.
func set_player_roster(paths: Array) -> void:
	player_roster_paths = paths.duplicate()
	save()


# What each side fielded, per round, newest last. The seam counter-drafting
# reads: Commander.design_fills_role() can classify a design it has never seen,
# so this is enough to bias a roster without new AI.
func fielded_history() -> Array:
	var out: Array = []
	for entry in stage_results_history:
		out.append({
			"stage": entry.get("stage", 0),
			"map_id": entry.get("map_id", ""),
			"victory": entry.get("victory", false),
			"player_designs": entry.get("player_designs", []),
			"enemy_designs": entry.get("enemy_designs", []),
		})
	return out


# --- Persistence --------------------------------------------------------------
#
# JSON to user://operations/, NOT .tres Resources. The research pass proposed
# nested Resource + ResourceSaver with FLAG_BUNDLE_RESOURCES; that solves a
# problem this codebase does not have. Blueprints are already JSON at schema
# v2.0 with a deliberate scratch-vs-saved split, and data/loadout/ and
# data/enemy/ are load-bearing JSON. One serialisation format.
#
# VERSIONED FROM DAY ONE. The blueprint schema earned its version the hard way -
# a silently mis-loaded old save is worse than a refused one.
const SAVE_VERSION := 1
const SAVE_DIR := "user://operations"

var operation_id: String = ""
var player_roster_paths: Array = []


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"operation_id": operation_id,
		"is_active_operation": is_active_operation,
		"current_stage": current_stage,
		"difficulty": difficulty,
		"stages_itinerary": stages_itinerary.duplicate(true),
		"stage_results_history": stage_results_history.duplicate(true),
		"player_roster_paths": player_roster_paths.duplicate(),
	}


# Returns false rather than half-applying. A campaign restored from a file whose
# shape has moved on is worse than one that admits it cannot be restored.
func from_dict(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != SAVE_VERSION:
		push_warning("OperationsManager: refusing to load save version %s (expected %d)"
			% [str(data.get("version", "?")), SAVE_VERSION])
		return false
	var itinerary: Array = data.get("stages_itinerary", [])
	if itinerary.is_empty():
		push_warning("OperationsManager: refusing to load a save with no itinerary")
		return false
	operation_id = str(data.get("operation_id", ""))
	is_active_operation = bool(data.get("is_active_operation", false))
	current_stage = int(data.get("current_stage", 0))
	difficulty = str(data.get("difficulty", "normal"))
	stages_itinerary = itinerary.duplicate(true)
	stage_results_history = (data.get("stage_results_history", []) as Array).duplicate(true)
	player_roster_paths = (data.get("player_roster_paths", []) as Array).duplicate()
	return true


func save_path() -> String:
	return "%s/%s.json" % [SAVE_DIR, operation_id if operation_id != "" else "current"]


func save() -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(save_path(), FileAccess.WRITE)
	if file == null:
		push_warning("OperationsManager: could not write %s" % save_path())
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("OperationsManager: %s is not a JSON object" % path)
		return false
	return from_dict(parsed)


# Every saved operation, newest first, as {id, path, stage, total, difficulty}.
func list_saved() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var path: String = "%s/%s" % [SAVE_DIR, name]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		out.append({
			"id": str(parsed.get("operation_id", name.get_basename())),
			"path": path,
			"stage": int(parsed.get("current_stage", 0)),
			"total": (parsed.get("stages_itinerary", []) as Array).size(),
			"difficulty": str(parsed.get("difficulty", "normal")),
			"active": bool(parsed.get("is_active_operation", false)),
		})
	out.reverse()
	return out


# Time-based, so two operations started in the same session do not collide and
# so list_saved()'s reverse-alphabetical order is newest-first.
func _new_operation_id() -> String:
	return "op_%d" % Time.get_unix_time_from_system()

func queue_blueprint_iteration(blueprint_name: String) -> void:
	target_iteration_blueprint = blueprint_name

func pop_queued_iteration_blueprint() -> String:
	var bp_name = target_iteration_blueprint
	target_iteration_blueprint = ""
	return bp_name

func reset_operation() -> void:
	is_active_operation = false
	current_stage = 0
	stage_results_history.clear()
	target_iteration_blueprint = ""
