class_name SemanticZoomService
extends RefCounted

enum ZoomLevel {
	MICRO,
	NORMAL,
	MACRO
}

signal zoom_level_changed(new_level: ZoomLevel, distance: float)

var micro_threshold: float = 10.0
var macro_threshold: float = 22.0

var current_level: ZoomLevel = ZoomLevel.NORMAL
var current_distance: float = 15.0

func _init(p_micro: float = 10.0, p_macro: float = 22.0) -> void:
	micro_threshold = p_micro
	macro_threshold = p_macro

func update_distance(distance: float) -> ZoomLevel:
	current_distance = distance
	var new_level: ZoomLevel = ZoomLevel.NORMAL

	if distance < micro_threshold:
		new_level = ZoomLevel.MICRO
	elif distance > macro_threshold:
		new_level = ZoomLevel.MACRO
	else:
		new_level = ZoomLevel.NORMAL

	if new_level != current_level:
		current_level = new_level
		zoom_level_changed.emit(current_level, current_distance)

	return current_level

func get_level_name(level: ZoomLevel = current_level) -> String:
	match level:
		ZoomLevel.MICRO:
			return "MICRO"
		ZoomLevel.NORMAL:
			return "NORMAL"
		ZoomLevel.MACRO:
			return "MACRO"
		_:
			return "UNKNOWN"
