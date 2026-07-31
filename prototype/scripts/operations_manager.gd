extends Node
# OperationsManager (Autoload / Singleton)
# Manages multi-round Operations campaign state, tracking stage progression,
# map rotation, player/AI roster state, and target blueprint pre-selection
# for inter-round Design Lab iteration.

signal operation_started(operation_data: Dictionary)
signal stage_completed(stage_index: int, results: Dictionary)
signal operation_completed(overall_results: Dictionary)

# Current active Operation session data
var is_active_operation: bool = false
var current_stage: int = 0
var total_stages: int = 3
var difficulty: String = "normal" # "easy", "normal", "hard"
var target_iteration_blueprint: String = "" # Blueprint name queued to open in Design Lab

# Stages itinerary: map IDs and AI difficulty parameters
var stages_itinerary: Array = [
	{"map_id": "open_plains", "ai_difficulty": "easy", "title": "Stage 1: Proving Ground"},
	{"map_id": "highland_chokepoint", "ai_difficulty": "normal", "title": "Stage 2: Mountain Pass"},
	{"map_id": "urban_sprawl", "ai_difficulty": "hard", "title": "Stage 3: Fortress Siege"}
]

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
