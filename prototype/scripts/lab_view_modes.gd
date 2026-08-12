class_name LabViewModes
extends RefCounted

enum ViewMode {
	DEFAULT,
	WIREFRAME,
	XRAY,
	STRUCTURAL
}

signal view_mode_changed(new_mode: ViewMode)

var current_mode: ViewMode = ViewMode.DEFAULT
var _visual_builder: Node = null

func _init(p_visual_builder: Node = null) -> void:
	_visual_builder = p_visual_builder

func set_view_mode(mode: ViewMode) -> void:
	if current_mode == mode:
		return
	current_mode = mode
	_apply_view_mode()
	view_mode_changed.emit(current_mode)

func _apply_view_mode() -> void:
	if _visual_builder == null or not is_instance_valid(_visual_builder):
		return

	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")
	VisualBuilderScript.apply_analytical_mode(_visual_builder, current_mode)

func get_mode_name(mode: ViewMode = current_mode) -> String:
	match mode:
		ViewMode.DEFAULT:
			return "DEFAULT"
		ViewMode.WIREFRAME:
			return "WIREFRAME"
		ViewMode.XRAY:
			return "XRAY"
		ViewMode.STRUCTURAL:
			return "STRUCTURAL"
		_:
			return "UNKNOWN"
