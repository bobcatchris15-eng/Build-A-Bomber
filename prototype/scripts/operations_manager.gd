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
	
	if not custom_itinerary.is_empty():
		stages_itinerary = custom_itinerary.duplicate(true)
	
	operation_started.emit({
		"stages": stages_itinerary,
		"difficulty": difficulty
	})

func get_current_stage_info() -> Dictionary:
	if current_stage >= 0 and current_stage < stages_itinerary.size():
		return stages_itinerary[current_stage]
	return {}

func record_stage_result(stage_stats: Dictionary) -> void:
	stage_results_history.append(stage_stats)
	stage_completed.emit(current_stage, stage_stats)
	
func advance_to_next_stage() -> bool:
	current_stage += 1
	if current_stage >= stages_itinerary.size():
		is_active_operation = false
		operation_completed.emit({"history": stage_results_history})
		return false
	return true

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
