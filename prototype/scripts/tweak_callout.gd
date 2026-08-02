extends Control
class_name TweakCallout

var target_node: Node3D
var max_zoom_distance: float = 40.0

var panel: PanelContainer
var vbox: VBoxContainer
var title_label: Label
var control_node: Control

var is_hub: bool = false
var hub_rect: Rect2 = Rect2()
var module_aabb: AABB

func _init(tweak_title: String, ctrl: Control, dir: Vector2, dist: float):
	is_hub = (tweak_title == "Module Stats" or tweak_title == "Identity")
	scale = Vector2(0.9, 0.9)
	clip_contents = false
	
	panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.15, 0.8)
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.6, 0.2, 0.9) if not is_hub else Color(0.4, 0.8, 1.0, 0.9)
	style.corner_radius_top_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)
	
	if tweak_title != "":
		title_label = Label.new()
		title_label.text = tweak_title
		title_label.add_theme_font_size_override("font_size", 10)
		title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7) if not is_hub else Color(0.6, 0.9, 1.0))
		vbox.add_child(title_label)
	
	control_node = ctrl
	if control_node.get_parent():
		control_node.reparent(vbox)
	else:
		vbox.add_child(control_node)

func _ready():
	if is_hub and target_node:
		module_aabb = _get_module_aabb(target_node)
	
	# Initial spawn position to avoid lerping from 0,0
	var camera = get_viewport().get_camera_3d()
	if camera and target_node and is_instance_valid(target_node):
		global_position = camera.unproject_position(target_node.global_position)

func _get_module_aabb(node: Node3D) -> AABB:
	var aabb = AABB()
	var first = true
	var meshes = _get_all_meshes(node)
	for m in meshes:
		var trans = node.global_transform.affine_inverse() * m.global_transform
		var maabb = trans * m.get_aabb()
		if first:
			aabb = maabb
			first = false
		else:
			aabb = aabb.merge(maabb)
	if first:
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))
	return aabb

func _get_all_meshes(node: Node) -> Array:
	var res = []
	if node is MeshInstance3D:
		res.append(node)
	for c in node.get_children():
		res.append_array(_get_all_meshes(c))
	return res

func _get_2d_rect(camera: Camera3D, node: Node3D, aabb: AABB) -> Rect2:
	var corners = [
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z)
	]
	
	var min_p = Vector2(INF, INF)
	var max_p = Vector2(-INF, -INF)
	for c in corners:
		var p = camera.unproject_position(node.global_transform * c)
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
		
	return Rect2(min_p, max_p - min_p)

func _process(delta):
	if not is_instance_valid(target_node):
		if is_instance_valid(control_node) and is_inside_tree():
			var root = get_node_or_null("/root/MainLab")
			if root and root.has_node("UI/StatCalculator"):
				var stat_calc = root.get_node("UI/StatCalculator")
				if stat_calc.get("popup_tweaks_container"):
					control_node.reparent(stat_calc.popup_tweaks_container)
				else:
					control_node.reparent(root)
			else:
				control_node.reparent(get_tree().root)
		queue_free()
		return
		
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var pos_3d = target_node.global_position
	var dist_to_cam = camera.global_position.distance_to(pos_3d)
	if dist_to_cam > max_zoom_distance:
		modulate.a = lerp(modulate.a, 0.0, 10.0 * delta)
		if modulate.a < 0.05:
			visible = false
	else:
		visible = true
		modulate.a = lerp(modulate.a, 1.0, 10.0 * delta)
	
	if not visible:
		return
		
	if camera.is_position_behind(pos_3d):
		visible = false
		return

	if is_hub:
		hub_rect = _get_2d_rect(camera, target_node, module_aabb)
		# Add some padding to the box
		hub_rect = hub_rect.grow(10.0)
		
		var target_pos = Vector2(hub_rect.position.x + hub_rect.size.x/2.0 - (panel.size.x*scale.x)/2.0, hub_rect.position.y - (panel.size.y*scale.y) - 40.0)
		global_position = global_position.lerp(target_pos, 20.0 * delta)
	else:
		var hub = null
		if get_parent():
			for sib in get_parent().get_children():
				if sib is TweakCallout and sib.is_hub:
					hub = sib
					break
		
		if hub:
			var my_idx = 0
			for sib in get_parent().get_children():
				if sib == self: break
				if sib is TweakCallout and not sib.is_hub and sib.visible:
					my_idx += 1
			
			var is_right = (my_idx % 2 == 0)
			var vert_idx = my_idx / 2
			
			var y_pos = hub.hub_rect.position.y + (vert_idx * (panel.size.y * scale.y + 10.0))
			var x_pos = 0.0
			if is_right:
				x_pos = hub.hub_rect.end.x + 30.0
			else:
				x_pos = hub.hub_rect.position.x - (panel.size.x*scale.x) - 30.0
				
			var target_pos = Vector2(x_pos, y_pos)
			global_position = global_position.lerp(target_pos, 15.0 * delta)

	queue_redraw()

func _draw():
	var line_color = Color(0.4, 0.8, 1.0, 0.7) if is_hub else Color(0.8, 0.6, 0.2, 0.7)
	
	if is_hub:
		# Draw the bounding box around the module
		var local_rect = Rect2(get_global_transform().affine_inverse() * hub_rect.position, hub_rect.size)
		draw_rect(local_rect, line_color, false, 2.0)
		
		# Draw line from bottom center of panel to top center of bounding box
		var start_pt = Vector2(panel.size.x / 2.0, panel.size.y)
		var end_pt = get_global_transform().affine_inverse() * Vector2(hub_rect.position.x + hub_rect.size.x / 2.0, hub_rect.position.y)
		draw_line(start_pt, end_pt, line_color, 2.0, true)
	else:
		var hub = null
		if get_parent():
			for sib in get_parent().get_children():
				if sib is TweakCallout and sib.is_hub:
					hub = sib
					break
		
		if hub:
			var attach_y = panel.size.y / 2.0
			var attach_x = 0.0
			
			if global_position.x > hub.hub_rect.position.x:
				# We are on the right side
				attach_x = 0.0
			else:
				# We are on the left side
				attach_x = panel.size.x
				
			var start_pt = Vector2(attach_x, attach_y)
			
			var target_offset = _get_target_offset(hub.module_aabb, title_label.text if title_label else "")
			var camera = get_viewport().get_camera_3d()
			var target_screen = camera.unproject_position(target_node.global_transform * target_offset)
			
			var end_pt = get_global_transform().affine_inverse() * target_screen
			
			# Draw the straight line
			draw_line(start_pt, end_pt, line_color, 2.0, true)
			draw_circle(start_pt, 3.0, line_color)
			
			# Draw a small crosshair/dot where it touches the 3D part
			draw_circle(end_pt, 3.0, line_color)
			draw_line(end_pt - Vector2(5, 0), end_pt + Vector2(5, 0), line_color, 1.0, true)
			draw_line(end_pt - Vector2(0, 5), end_pt + Vector2(0, 5), line_color, 1.0, true)

func _get_target_offset(aabb: AABB, title: String) -> Vector3:
	var offset = aabb.position + (aabb.size * 0.5)
	
	if "Barrel Length" in title:
		offset.z -= aabb.size.z * 0.4 # Forward
	elif "Caliber" in title:
		offset.z += aabb.size.z * 0.2 # Rear/Breech
	elif "Barrel Count" in title:
		offset.x += aabb.size.x * 0.3 # Side
		offset.z -= aabb.size.z * 0.2
	elif "Count" in title or "Blade" in title:
		offset.x += aabb.size.x * 0.4 # Side
	elif "Size" in title or "Wheel" in title or "Tread" in title or "Drum" in title:
		offset.x -= aabb.size.x * 0.4
		offset.y -= aabb.size.y * 0.4 # Down to wheels
	elif "Armor" in title:
		offset.x += aabb.size.x * 0.3
		offset.y += aabb.size.y * 0.3
	elif "Energy" in title:
		offset.y += aabb.size.y * 0.2
		offset.z += aabb.size.z * 0.3
		
	return offset
	

