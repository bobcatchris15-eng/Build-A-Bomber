extends Control
class_name TweakCallout
# One annotation hanging off the selected module, joined to a specific piece of
# its geometry by a leader line - an engineering drawing's callout, live.
#
# THE HUB AND ITS SATELLITES. One callout per selection is the HUB: it frames
# the module's projected bounding box and carries the name and headline stats.
# Every other callout is a SATELLITE holding one live tweak control (barrel
# length, calibre, wheel size, blade count), with its leader line pointing at
# the part of the model that tweak actually changes - the muzzle for barrel
# length, the breech for calibre. That mapping lives in _get_target_offset()
# and is what sells the whole thing as a technical drawing rather than as
# floating tooltips.
#
# WHAT WAS HALF-BUILT, and what this fixes. stat_calculator._add_callout()
# computes an eight-point RADIAL RING of directions (_callout_dirs) and a
# per-index distance, and passes both into this constructor - and the previous
# version of _process() ignored both, stacking satellites in two vertical
# columns to the left and right of the hub instead. The ring was the design
# intent; the columns were a placeholder that outlived it. Consequences of the
# placeholder, all visible in the Lab:
#   * Leader lines from a left-column callout to a right-side part crossed the
#     model, which is exactly what a callout must never do.
#   * Column entries were spaced by index, so with six tweaks the lower ones
#     walked off the bottom of the screen.
#   * Two callouts at the same index height overlapped whenever their panels
#     were of different heights.
#
# So placement now genuinely uses the ring, with three things the naive version
# needs to survive contact:
#   1. SIDE COHERENCE - a satellite is placed on the side of the hub its target
#      geometry is actually on, so lines never cross the model.
#   2. OVERLAP RESOLUTION - satellites push outward along their own ray until
#      they stop overlapping each other, rather than falling back to a column.
#   3. VIEWPORT CLAMPING - a direction that would leave the screen is reflected
#      across the hub first, and only then clamped, so clamping never drags a
#      callout on top of the model.

const Tokens = preload("res://scripts/ui_tokens.gd")

var target_node: Node3D
var max_zoom_distance: float = 40.0

# Where this callout's control goes when the callout dies. Set by
# stat_calculator._add_callout(). An explicit reference, not a node path - see
# the orphaned-widget note in _process().
var stash: Node = null

var panel: PanelContainer
var vbox: VBoxContainer
var title_label: Label
var control_node: Control

var is_hub: bool = false
var hub_rect: Rect2 = Rect2()
var module_aabb: AABB

# Ring placement, supplied by stat_calculator._add_callout().
var ring_dir: Vector2 = Vector2.RIGHT
var ring_dist: float = 120.0

# Where this callout settled last frame, so overlap resolution is stable
# instead of oscillating between two equally-bad positions.
var _resolved_pos: Vector2 = Vector2.ZERO
var _has_resolved: bool = false

# Pixels of clearance required between two satellite panels.
const OVERLAP_PAD := 8.0
# How far a satellite may be pushed out along its ray before giving up.
const MAX_PUSH := 260.0
const SCREEN_PAD := 12.0

func _init(tweak_title: String, ctrl: Control, dir: Vector2, dist: float):
	is_hub = (tweak_title == "Module Stats" or tweak_title == "Identity")
	ring_dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	ring_dist = dist
	scale = Vector2(0.9, 0.9)
	clip_contents = false

	panel = PanelContainer.new()
	# CANVAS backing from the theme, with a signal edge for the hub/satellite
	# distinction. Was an inline StyleBoxFlat with hardcoded gold and cyan -
	# a local override, which beats the theme and so kept the design system out
	# of the one part of the Design Lab the player looks at most.
	panel.theme_type_variation = "FlyoutPanel"
	var edge = StyleBoxFlat.new()
	edge.bg_color = Color(Tokens.BASE_900, 0.86)
	edge.border_width_left = 3
	edge.border_color = Tokens.SIGNAL_INFO if is_hub else Tokens.SIGNAL_HAZARD
	edge.corner_radius_top_left = Tokens.RADIUS_CONTROL
	edge.corner_radius_bottom_right = Tokens.RADIUS_CONTROL
	edge.content_margin_left = Tokens.SPACE_SM
	edge.content_margin_right = Tokens.SPACE_SM
	edge.content_margin_top = 2
	edge.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", edge)
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
		# Hand the tweak control back to the stash before dying.
		#
		# THIS WAS THE ORPHANED-WIDGET BUG. The previous version looked the
		# stash up by walking node paths - get_node("/root/MainLab") then
		# has_node("UI/StatCalculator") - and there IS no "UI/StatCalculator"
		# node; the stat block is a UI_StatBlock instance on the MainLab root.
		# So the lookup failed every time and fell through to
		# `control_node.reparent(get_tree().root)`, which dumped a live slider
		# or dropdown onto the SCENE TREE ROOT, where it was still visible, no
		# longer owned by anything, and never cleaned up. Deselecting a part
		# left its sliders scattered across the screen forever.
		#
		# The stash is now an explicit reference handed over at construction, so
		# there is no path to get wrong, and the fallback is to free the control
		# rather than to strand it somewhere visible.
		if is_instance_valid(control_node):
			if is_instance_valid(stash) and control_node.get_parent() != stash:
				control_node.reparent(stash)
			elif not is_instance_valid(stash):
				control_node.queue_free()
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
		global_position = global_position.lerp(_clamp_to_viewport(target_pos), 20.0 * delta)
	else:
		var hub = _find_hub()
		if hub:
			var target_pos := _ring_position(hub, camera)
			global_position = global_position.lerp(target_pos, 15.0 * delta)

	queue_redraw()


func _find_hub() -> TweakCallout:
	if get_parent() == null:
		return null
	for sib in get_parent().get_children():
		if sib is TweakCallout and sib.is_hub:
			return sib
	return null


# Places this satellite on the ring around the hub.
func _ring_position(hub: TweakCallout, camera: Camera3D) -> Vector2:
	var my_size := panel.size * scale
	var centre := hub.hub_rect.get_center()

	# 1. SIDE COHERENCE. Point the callout out on the same side as the geometry
	#    its leader line ends at, so the line never has to cross the model. The
	#    ring direction supplies the vertical placement and the general fan;
	#    the target's own screen position decides left-versus-right.
	var dir := ring_dir
	if is_instance_valid(target_node):
		var anchor_3d: Vector3 = target_node.global_transform * _get_target_offset(
			hub.module_aabb, title_label.text if title_label else "")
		if not camera.is_position_behind(anchor_3d):
			var anchor := camera.unproject_position(anchor_3d)
			# Flip only the horizontal component - the ring's vertical spread is
			# what keeps several callouts on one side from piling up, so it must
			# be preserved.
			if signf(anchor.x - centre.x) != signf(dir.x) and absf(anchor.x - centre.x) > 4.0:
				dir.x = -dir.x
	if dir.length() < 0.01:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	# 2. Start at the hub box edge plus the ring distance, then resolve overlaps
	#    by pushing further along the SAME ray. Pushing along the ray (rather
	#    than sliding sideways, or dropping into a column) keeps the leader line
	#    pointing the same way, which is what makes the fan readable.
	var base_r: float = ring_dist + maxf(hub.hub_rect.size.x, hub.hub_rect.size.y) * 0.5
	# The hub's own panel is an obstacle too, not just the other satellites.
	# Leaving it out was visible immediately: the stats card sits directly above
	# the module, which is exactly where the first top-corner satellite wants to
	# go, so the two overlapped on every selection.
	var hub_panel_rect := Rect2(hub.global_position, hub.panel.size * hub.scale)

	var pos := Vector2.ZERO
	var pushed := 0.0
	while true:
		pos = centre + dir * (base_r + pushed) - my_size * 0.5
		var my_rect := Rect2(pos, my_size)
		var clear := not _overlaps_earlier_satellite(my_rect)
		if clear and my_rect.grow(OVERLAP_PAD).intersects(hub_panel_rect):
			clear = false
		if clear:
			break
		pushed += my_size.y + OVERLAP_PAD
		if pushed > MAX_PUSH:
			break

	# 3. VIEWPORT HANDLING. Reflect across the hub before clamping - a callout
	#    clamped straight back from the edge lands on top of the model, which is
	#    the one place it must not be.
	var vp := get_viewport_rect().size
	var off_screen := (pos.x < SCREEN_PAD or pos.y < SCREEN_PAD
		or pos.x + my_size.x > vp.x - SCREEN_PAD
		or pos.y + my_size.y > vp.y - SCREEN_PAD)
	if off_screen:
		var mirrored := centre - dir * (base_r + pushed) - my_size * 0.5
		var mirror_ok := (mirrored.x >= SCREEN_PAD and mirrored.y >= SCREEN_PAD
			and mirrored.x + my_size.x <= vp.x - SCREEN_PAD
			and mirrored.y + my_size.y <= vp.y - SCREEN_PAD)
		if mirror_ok:
			pos = mirrored

	pos = _clamp_to_viewport(pos)
	_resolved_pos = pos
	_has_resolved = true
	return pos


# Overlap is only tested against satellites EARLIER in the sibling order.
#
# Testing against all of them would make resolution order-dependent and
# oscillate: A pushes off B, which pushes off A, forever. With a strict
# ordering the first satellite never moves, the second avoids the first, and so
# on - one stable pass.
func _overlaps_earlier_satellite(my_rect: Rect2) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	for sib in parent.get_children():
		if sib == self:
			return false
		if not (sib is TweakCallout):
			continue
		var other := sib as TweakCallout
		if other.is_hub or not other.visible or not other._has_resolved:
			continue
		var other_rect := Rect2(other._resolved_pos, other.panel.size * other.scale)
		if my_rect.grow(OVERLAP_PAD).intersects(other_rect):
			return true
	return false


func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var my_size := panel.size * scale
	var vp := get_viewport_rect().size
	return Vector2(
		clampf(pos.x, SCREEN_PAD, maxf(SCREEN_PAD, vp.x - my_size.x - SCREEN_PAD)),
		clampf(pos.y, SCREEN_PAD, maxf(SCREEN_PAD, vp.y - my_size.y - SCREEN_PAD)))

func _draw():
	var line_color = Color(Tokens.SIGNAL_INFO, 0.7) if is_hub else Color(Tokens.SIGNAL_HAZARD, 0.7)
	
	if is_hub:
		# Draw the bounding box around the module
		var local_rect = Rect2(get_global_transform().affine_inverse() * hub_rect.position, hub_rect.size)
		draw_rect(local_rect, line_color, false, 2.0)
		
		# Draw line from bottom center of panel to top center of bounding box
		var start_pt = Vector2(panel.size.x / 2.0, panel.size.y)
		var end_pt = get_global_transform().affine_inverse() * Vector2(hub_rect.position.x + hub_rect.size.x / 2.0, hub_rect.position.y)
		draw_line(start_pt, end_pt, line_color, 2.0, true)
	else:
		var hub = _find_hub()

		if hub:
			var attach_y = panel.size.y / 2.0
			var attach_x = 0.0

			# The line leaves from whichever vertical edge faces the model, so
			# it never starts by running back across the callout's own text.
			# Compared against the hub's CENTRE, not its left edge - the old
			# version used hub_rect.position.x, so a callout sitting anywhere
			# over the box's own width attached on the wrong side.
			if global_position.x > hub.hub_rect.get_center().x:
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
	

