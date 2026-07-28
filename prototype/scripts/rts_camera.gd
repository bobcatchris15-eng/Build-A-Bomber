extends Camera3D
# Classic RTS camera: WASD/arrow pan, mouse-wheel zoom, middle-mouse drag pan.

@export var pan_speed: float = 30.0
@export var zoom_speed: float = 8.0
@export var min_height: float = 10.0
# Skirmish refinement pass: maps grew to ~3x their original size (see
# map_catalog.gd - two scale-up passes, 1.5x then another 2x after the
# first still read as too small) and the old 45-unit cap meant you could
# never zoom out far enough to see a meaningful fraction of even the
# smallest map. Pan speed already scales with height (see _process()
# below), so raising this doesn't make traversal at max zoom-out feel
# sluggish.
@export var max_height: float = 240.0

# VISUAL_AND_UX_POLISH_PLAN.md B1: edge-scroll + zoom-to-cursor - both core
# RTS camera expectations this project had neither of. Edge margin in real
# pixels (viewport-space, not logical/stretched) - kept modest so it
# doesn't trigger from a build-bar click a few pixels off the bottom edge.
@export var edge_scroll_margin: float = 18.0

var height: float = 26.0

func _ready():
	height = clamp(global_position.y, min_height, max_height)
	_apply_pitch()

func _apply_pitch():
	# Steeper look-down when zoomed out
	var t = (height - min_height) / (max_height - min_height)
	rotation_degrees.x = lerp(-42.0, -62.0, t)

# Pure function (no Input/viewport reads) so it's directly testable headless -
# given where the mouse sits relative to the viewport and the margin, which
# way (if any) should the camera pan. Returns a possibly-diagonal, NOT
# normalized direction (matches keyboard pan's own union-then-normalize
# below - a corner shouldn't scroll faster than an edge).
static func compute_edge_scroll_direction(mouse_pos: Vector2, viewport_size: Vector2, margin: float) -> Vector2:
	var dir = Vector2.ZERO
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return dir
	if mouse_pos.x <= margin:
		dir.x -= 1
	elif mouse_pos.x >= viewport_size.x - margin:
		dir.x += 1
	if mouse_pos.y <= margin:
		dir.y -= 1
	elif mouse_pos.y >= viewport_size.y - margin:
		dir.y += 1
	return dir

func _process(delta):
	var move = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1

	# Edge-scroll only while the window actually has input focus - otherwise
	# a mouse merely sitting near the edge of an unfocused window (e.g. this
	# game running behind another one) would silently drag the camera.
	if is_inside_tree() and get_window() and get_window().has_focus():
		var vp = get_viewport()
		var edge_dir = compute_edge_scroll_direction(vp.get_mouse_position(), vp.get_visible_rect().size, edge_scroll_margin)
		move += edge_dir

	if move != Vector2.ZERO:
		move = move.normalized() * pan_speed * delta * (height / 26.0)
		global_position.x += move.x
		global_position.z += move.y

	global_position.y = lerp(global_position.y, height, 10.0 * delta)

# VISUAL_AND_UX_POLISH_PLAN.md B1: where the mouse ray hits a flat plane at
# world Y=`plane_y` - the same "flat ground" approximation skirmish.gd's own
# _raycast_ground() effectively assumes for cursor-driven placement/orders.
# A pure function of the camera's own transform + a screen point, so it's
# testable without a real physics world (no CollisionShape3D needed to hit).
func ray_plane_hit(screen_pos: Vector2, plane_y: float = 0.0):
	var origin = project_ray_origin(screen_pos)
	var dir = project_ray_normal(screen_pos)
	if abs(dir.y) < 0.0001:
		return null
	var t = (plane_y - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t

# VISUAL_AND_UX_POLISH_PLAN.md B1: zoom-to-cursor - the previous behavior
# changed height (and, via _apply_pitch(), pitch) in place, so zooming in/out
# always recentered on the camera's own XZ position regardless of where the
# mouse was pointing, unlike every modern map/RTS camera. Keeps the same
# world point (on the flat-plane approximation above) under the cursor
# before and after the height change by measuring the ray-plane hit both
# before and after, then nudging XZ by the difference.
func zoom_to_cursor(new_height: float, screen_pos: Vector2) -> void:
	var before = ray_plane_hit(screen_pos)
	height = clamp(new_height, min_height, max_height)
	_apply_pitch()
	# Apply the height change immediately (skip _process()'s smoothing lerp)
	# so the "after" raycast below is measured against the camera's REAL
	# post-zoom transform, not a stale one mid-lerp.
	global_position.y = height
	var after = ray_plane_hit(screen_pos)
	if before != null and after != null:
		global_position.x += before.x - after.x
		global_position.z += before.z - after.z

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_to_cursor(height - zoom_speed, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_to_cursor(height + zoom_speed, event.position)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var factor = height / 500.0
		global_position.x -= event.relative.x * factor
		global_position.z -= event.relative.y * factor
