extends Node

const RECORDS_PATH = "user://design_records.json"
var records: Dictionary = {}

func _ready() -> void:
	_load_records()

func _load_records() -> void:
	if FileAccess.file_exists(RECORDS_PATH):
		var file = FileAccess.open(RECORDS_PATH, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			var json = JSON.parse_string(text)
			if typeof(json) == TYPE_DICTIONARY:
				records = json
			file.close()

func _save_records() -> void:
	var file = FileAccess.open(RECORDS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(records, "\t"))
		file.close()

func add_match_results(bp_stats: Dictionary) -> void:
	for bp_name in bp_stats:
		var stats = bp_stats[bp_name]
		if not records.has(bp_name):
			records[bp_name] = {
				"built": 0, "kills": 0, "damage_dealt": 0,
				"damage_taken": 0, "credits_spent": 0
			}
		
		var rec = records[bp_name]
		rec["built"] += stats.get("built", 0)
		rec["kills"] += stats.get("kills", 0)
		rec["damage_dealt"] += stats.get("damage_dealt", 0)
		rec["damage_taken"] += stats.get("damage_taken_kinetic", 0) + stats.get("damage_taken_thermal", 0) + stats.get("damage_taken_explosive", 0)
		rec["credits_spent"] += stats.get("credits_spent", 0)
	
	_save_records()

func get_record(bp_name: String) -> Dictionary:
	return records.get(bp_name, {})
