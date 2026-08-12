class_name EdgeMarker
extends Control
# Projects off-screen alerts to the edge of the viewport so the player 
# knows where action is happening.

const Tokens = preload("res://scripts/ui_tokens.gd")

var _director: Node
var _camera: Camera3D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func setup(director: Node) -> void:
	_director = director
	_camera = _director.camera

func _process(delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _director == null or _director.alerts == null or _camera == null:
		return
	
	var alerts = _director.alerts.get_active_alerts()
	var vp_size = get_viewport_rect().size
	var center = vp_size / 2.0
	
	for alert in alerts:
		var target = alert.world_pos
		var screen_pos = _camera.unproject_position(target)
		var is_behind = _camera.is_position_behind(target)
		
		if is_behind:
			# If behind the camera, invert the vector from center so it points
			# backwards correctly
			var offset = screen_pos - center
			screen_pos = center - offset
			
		if not is_behind and Rect2(Vector2.ZERO, vp_size).has_point(screen_pos):
			continue # Valid and on screen
			
		var dir = (screen_pos - center).normalized()
		var edge_pos = center
		
		if abs(dir.x) * vp_size.y > abs(dir.y) * vp_size.x:
			edge_pos.x = vp_size.x if dir.x > 0 else 0
			if dir.x != 0:
				edge_pos.y = center.y + (edge_pos.x - center.x) * (dir.y / dir.x)
		else:
			edge_pos.y = vp_size.y if dir.y > 0 else 0
			if dir.y != 0:
				edge_pos.x = center.x + (edge_pos.y - center.y) * (dir.x / dir.y)
				
		edge_pos.x = clamp(edge_pos.x, 16.0, vp_size.x - 16.0)
		edge_pos.y = clamp(edge_pos.y, 16.0, vp_size.y - 16.0)
		
		var points = PackedVector2Array()
		points.append(edge_pos + dir * 12)
		points.append(edge_pos - dir * 8 + Vector2(-dir.y, dir.x) * 8)
		points.append(edge_pos - dir * 8 - Vector2(-dir.y, dir.x) * 8)
		
		var color = Tokens.SIGNAL_ALERT if alert.type == "attack" else Tokens.BASE_500
		draw_colored_polygon(points, color)
