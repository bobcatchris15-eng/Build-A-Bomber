extends Button

var module_type_id: String = ""

func _get_drag_data(at_position: Vector2):
	# Create a simple preview label for the drag
	var preview_label = Label.new()
	preview_label.text = text
	var preview_control = Control.new()
	preview_control.add_child(preview_label)
	
	set_drag_preview(preview_control)
	
	# Pass a dictionary containing the drag payload
	return {"type": "module_part", "id": module_type_id}
