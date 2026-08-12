extends Camera3D
# Classic RTS camera: WASD/arrow pan (yaw-relative), Q/E rotate, mouse-wheel
# zoom, middle-mouse drag pan. Reads InputService's cam_* actions rather than
# raw keycodes - see scripts/core/input_service.gd's header for why.
#
# WHAT WAS HERE AND WHAT IS GONE.
#
# The camera used to run a tilt-shift depth-of-field band (DOF_BAND_MIN/MAX,
# DOF_TRANSITION, DOF_BLUR_AMOUNT, the _cam_attributes CameraAttributesPractical
# resource, _setup_tilt_shift_dof and _apply_dof_distances_from). It was
# disabled 2026-08-10 because it was the dominant per-frame cost in a Skirmish
# after the first ~20 seconds (3 FPS, never recovered, also reproduces in the
# new Test Range). The cause: Godot's DOF is a screen-space post-process keyed
# on depth alone - the renderer runs the band every frame, plus this camera
# was writing to the CameraAttributesPractical properties every frame from
# _process() to track the lerp between min/max zoom. The fixed write was the
# smaller half; the full-screen DOF pass was the rest. A designer_camera.gd
# copy of the same effect in the Lab still ships; the battle scene is the
# place that needed to recover, and the band was already documented as "not
# looking right" in playtests before the perf regression. Killed.
#
# Re-enabling DOF in the future is a one-line `attributes = CameraAttributesPractical.new()`
# in _ready() - the helpers and constants are gone on purpose, so nobody
# re-introduces a partially-stripped version. The playtest finding in
# CORE_DESIGN_LANGUAGE.md §2.1 ("0.08 is a CEILING, not a target") stands;
# whoever brings the band back owns re-tuning against that constraint.

@export var pan_speed: float = 30.0
@export var zoom_speed: float = 8.0
@export var rotate_speed: float = 90.0
@export var min_height: float = 10.0
# Skirmish refinement pass: maps grew to ~3x their original size (see
# map_catalog.gd - two scale-up passes, 1.5x then another 2x after the
# first still read as too small) and the old 45-unit cap meant you could
# never zoom out far enough to see a meaningful fraction of even the
# smallest map. Pan speed already scales with height (see _process()
# below), so raising this doesn't make traversal at max zoom-out feel
# sluggish.
@export var max_height: float = 160.0

# VISUAL_AND_UX_POLISH_PLAN.md B1: edge-scroll + zoom-to-cursor - both core
# RTS camera expectations this project had neither of. Edge margin in real
# pixels (viewport-space, not logical/stretched) - kept modest so it
# doesn't trigger from a build-bar click a few pixels off the bottom edge.
@export var edge_scroll_margin: float = 18.0

# CORE_DESIGN_LANGUAGE.md §3.2: scales pan speed and middle-drag, so
# traversing a map that's now genuinely bigger under world_scale doesn't
# get proportionally slower via keyboard/edge-scroll/middle-drag - long
# cross-map travel time is the accepted design (§3.2's own "accept long
# traversal" call), but getting there shouldn't fight the input itself.
# Set by whichever runtime loads the map (match_director.gd) - defaults to
# 1.0 so a camera with nothing setting it behaves exactly as before.
var world_scale: float = 1.0

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
	if mouse_pos.x < margin:
		dir.x -= 1.0
	elif mouse_pos.x > viewport_size.x - margin:
		dir.x += 1.0
	if mouse_pos.y < margin:
		dir.y -= 1.0
	elif mouse_pos.y > viewport_size.y - margin:
		dir.y += 1.0
	return dir


# Yaw-relative pan: keyboard input is camera-relative, but world movement is
# axis-aligned. Maps a screen direction back to a world direction by rotating
# the input by the camera's current yaw so WASD always means "forward in the
# view", regardless of where the camera is pointed.
static func pan_to_world(input: Vector2, yaw_deg: float) -> Vector2:
	var yaw := deg_to_rad(yaw_deg)
	var sin_y := sin(yaw)
	var cos_y := cos(yaw)
	return Vector2(
		input.x * cos_y + input.y * sin_y,
		-input.x * sin_y + input.y * cos_y
	)


# Returns a unit direction (0,0 when nothing to do) for the camera to scroll
# toward given the current mouse position and viewport size. Pulled into a
# pure function so test_rts_camera.gd can pin the four-quadrant + corner
# behaviour without instantiating a Camera3D.
static func compute_movement(
	keyboard: Vector2, mouse_pos: Vector2, viewport_size: Vector2, margin: float,
	window_has_focus: bool
) -> Vector2:
	var move := keyboard
	if window_has_focus:
		move += compute_edge_scroll_direction(mouse_pos, viewport_size, margin)
	return move


# Yaw-up vector of a Camera3D pitched by `pitch_deg` - same algebra as
# designer_camera.gd's, kept here so the ground-stick offset this camera
# computes for ray-plane hit math doesn't depend on Godot's transform
# pipeline re-running mid-call.
static func compute_yaw_up(pitch_deg: float) -> Vector3:
	return Vector3(0.0, sin(deg_to_rad(pitch_deg)), cos(deg_to_rad(pitch_deg)))


func _process(delta):
	var move := Input.get_vector("cam_pan_left", "cam_pan_right", "cam_pan_up", "cam_pan_down")

	# Edge-scroll only while the window actually has input focus - otherwise
	# a mouse merely sitting near the edge of an unfocused window (e.g. this
	# game running behind another one) would silently drag the camera.
	if is_inside_tree() and get_window() and get_window().has_focus():
		var vp = get_viewport()
		var edge_dir = compute_edge_scroll_direction(vp.get_mouse_position(), vp.get_visible_rect().size, edge_scroll_margin)
		move += edge_dir

	if Input.is_action_pressed("cam_rotate_left"): rotation_degrees.y += rotate_speed * delta
	if Input.is_action_pressed("cam_rotate_right"): rotation_degrees.y -= rotate_speed * delta
	if Input.is_action_just_pressed("cam_reset_rotation"): rotation_degrees.y = 0.0

	if move != Vector2.ZERO:
		move = move.normalized() * pan_speed * world_scale * delta * (height / 26.0)
		var world_move := pan_to_world(move, rotation_degrees.y)
		global_position.x += world_move.x
		global_position.z += world_move.y

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


# Zoom-to-cursor: keep the world point under the cursor at the same screen
# position before and after the height change. Done by ray-plane hitting
# before and after and shifting the camera by the world delta.
func _on_zoom(screen_pos: Vector2, height_delta: float):
	height = clamp(height + height_delta, min_height, max_height)
	_apply_pitch()
	var before = ray_plane_hit(screen_pos)
	# Snap y to the new target before the second hit so the after-raycast
	# is measured against the camera's REAL post-zoom transform, not a
	# stale one mid-lerp.
	global_position.y = height
	var after = ray_plane_hit(screen_pos)
	if before != null and after != null:
		global_position.x += before.x - after.x
		global_position.z += before.z - after.z


func _unhandled_input(event):
	if event.is_action_pressed("cam_zoom_in"):
		_on_zoom(get_viewport().get_mouse_position(), -zoom_speed * world_scale)
	elif event.is_action_pressed("cam_zoom_out"):
		_on_zoom(get_viewport().get_mouse_position(), zoom_speed * world_scale)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_drag_origin = event.position
			_middle_drag_last = event.position
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		var delta = event.position - _middle_drag_last
		_middle_drag_last = event.position
		if delta.length() == 0:
			return
		var world_move := pan_to_world(delta, rotation_degrees.y) * pan_speed * world_scale * 0.01
		global_position.x -= world_move.x
		global_position.z -= world_move.y

var _middle_drag_origin: Vector2 = Vector2.ZERO
var _middle_drag_last: Vector2 = Vector2.ZERO
