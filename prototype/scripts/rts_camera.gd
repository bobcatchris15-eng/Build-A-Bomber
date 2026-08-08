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
#
# CORE_DESIGN_LANGUAGE.md §7.2: this used to be 240 against a min_height of
# 10, which the doc calls out as "the macro language holds at the low end
# and does not at 240" - past a certain height there is no plausible lens
# that sees that much ground at that depth of field, and the miniature read
# inverts into a map view. Lowered to where the DOF band (see
# dof_band_half_width() below, which now WIDENS with height instead of
# staying fixed) can still plausibly cover the visible ground, rather than
# silently doing neither of the two things §7.2 says must be chosen between.
@export var max_height: float = 160.0

# VISUAL_AND_UX_POLISH_PLAN.md B1: edge-scroll + zoom-to-cursor - both core
# RTS camera expectations this project had neither of. Edge margin in real
# pixels (viewport-space, not logical/stretched) - kept modest so it
# doesn't trigger from a build-bar click a few pixels off the bottom edge.
@export var edge_scroll_margin: float = 18.0

# CORE_DESIGN_LANGUAGE.md §3.2: NOT the DOF/zoom ceiling (max_height stays
# fixed - the miniature illusion breaks past a certain altitude regardless
# of how big the map is, an art constraint independent of world size). This
# instead scales PAN SPEED and middle-drag, so traversing a map that's now
# genuinely bigger under world_scale doesn't get proportionally slower via
# keyboard/edge-scroll/middle-drag - long cross-map travel time is the
# accepted design (CORE_DESIGN_LANGUAGE.md §3.2's own "accept long
# traversal" call), but getting there shouldn't fight the input itself. Set
# by whichever runtime loads the map (match_director.gd) - defaults to 1.0
# so a camera with nothing setting it behaves exactly as before this chunk.
var world_scale: float = 1.0

var height: float = 26.0

# CORE_DESIGN_LANGUAGE.md §2/§7.1: the battle camera previously had no DOF at
# all, while designer_camera.gd implemented the full tilt-shift band - "the
# largest gap between this document and the build". This is that band,
# ported to the RTS camera's height-based zoom instead of designer_camera's
# orbit distance. §2.1 is explicit that the focal BAND (near+far DOF working
# together) is the whole effect, not a radial blur, and that the blur amount
# must stay low (0.08) because unit readability at RTS zoom is a gameplay
# requirement, not just an aesthetic one - see designer_camera.gd:26-41 for
# the reference implementation this mirrors.
var _cam_attributes: CameraAttributesPractical = null
# CORE_DESIGN_LANGUAGE.md §7.2's other half of the fix: rather than a single
# fixed band width (designer_camera.gd's orbit rig never zooms out far
# enough to need one), the band WIDENS as height rises, so the macro read
# fades out smoothly across the zoom range instead of snapping between
# "miniature" and "map view" at some arbitrary height. At min_height it
# matches designer_camera.gd's own 4.0 exactly.
const DOF_BAND_MIN_HALF_WIDTH: float = 4.0
const DOF_BAND_MAX_HALF_WIDTH: float = 30.0

# How gradually blur ramps in beyond the sharp band, in metres.
#
# WIDENED 3x (was 6.0) because the effect read as too aggressive in play. This is
# the "3x farther from centre transition" lever rather than the "a third the
# intensity on units" one, because the latter is NOT AVAILABLE: Godot's DOF is a
# screen-space post-process keyed on depth alone, applied by
# CameraAttributesPractical to the whole frame. It has no per-object, per-layer
# or per-material opt-out, and a unit standing on the ground is at essentially
# the same depth as the terrain right behind it - so nothing about the effect can
# distinguish the two. Blurring units less than the ground they stand on would
# need a custom compositor pass rendering units to their own buffer, which is a
# different and much larger piece of work.
#
# Widening the transition keeps the tilt-shift read at the extremes of the frame
# while letting the playfield stay sharp much further from the focal plane, which
# is the part that matters for unit readability.
const DOF_TRANSITION: float = 18.0

# Peak blur strength. Reduced to roughly a third of designer_camera.gd's 0.08 -
# Chris's "a third the intensity", applied globally since it cannot be applied to
# units alone. CORE_DESIGN_LANGUAGE.md §2.1 sets 0.08 as a CEILING for unit
# readability, not a target, so going under it is within the design rather than a
# departure from it.
const DOF_BLUR_AMOUNT: float = 0.03

# Pure function (no node state) so it's directly testable headless, same
# reasoning as compute_edge_scroll_direction() above: linear interpolation
# between the two band widths across the min/max height range, so it is
# provably monotonic rather than "probably feels right."
static func dof_band_half_width(height: float, min_h: float, max_h: float) -> float:
	if max_h <= min_h:
		return DOF_BAND_MIN_HALF_WIDTH
	var t = clamp((height - min_h) / (max_h - min_h), 0.0, 1.0)
	return lerp(DOF_BAND_MIN_HALF_WIDTH, DOF_BAND_MAX_HALF_WIDTH, t)

func _ready():
	height = clamp(global_position.y, min_height, max_height)
	_apply_pitch()
	_setup_tilt_shift_dof()

func _apply_pitch():
	# Steeper look-down when zoomed out
	var t = (height - min_height) / (max_height - min_height)
	rotation_degrees.x = lerp(-42.0, -62.0, t)

func _setup_tilt_shift_dof():
	_cam_attributes = CameraAttributesPractical.new()
	_cam_attributes.dof_blur_far_enabled = true
	_cam_attributes.dof_blur_far_transition = DOF_TRANSITION
	_cam_attributes.dof_blur_near_enabled = true
	_cam_attributes.dof_blur_near_transition = DOF_TRANSITION
	_cam_attributes.dof_blur_amount = DOF_BLUR_AMOUNT
	attributes = _cam_attributes
	_apply_dof_distances_from(height)

# The camera looks down at height from directly above its focal point (not
# straight down the -Z axis the way designer_camera's orbit rig does), so the
# near/far DOF distances track the camera's altitude itself rather than a
# distance-to-pivot value - altitude already IS the camera's distance from
# the ground plane it's focused on.
func _apply_dof_distances_from(altitude: float) -> void:
	if not _cam_attributes:
		return
	var half_width = dof_band_half_width(altitude, min_height, max_height)
	_cam_attributes.dof_blur_far_distance = altitude + half_width
	_cam_attributes.dof_blur_near_distance = max(1.0, altitude - half_width)

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
		move = move.normalized() * pan_speed * world_scale * delta * (height / 26.0)
		global_position.x += move.x
		global_position.z += move.y

	global_position.y = lerp(global_position.y, height, 10.0 * delta)
	# Track the camera's REAL (lerped) altitude, not the target `height` -
	# same reasoning as designer_camera.gd:38-41, whose DOF distances follow
	# position.z every frame rather than the target distance.
	_apply_dof_distances_from(global_position.y)

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
	_apply_dof_distances_from(height)
	var after = ray_plane_hit(screen_pos)
	if before != null and after != null:
		global_position.x += before.x - after.x
		global_position.z += before.z - after.z

func _unhandled_input(event):
	# `event.pressed` IS LOAD-BEARING, not tidiness. A mouse wheel emits a pressed
	# event AND a released one for every notch, so without this guard each notch
	# zoomed twice - and, worse, a wheel that a Control had already consumed still
	# zoomed the world on the release half. That is why scrolling a build list
	# scrolled the list and zoomed the map at the same time: the fix belonged here,
	# not in the HUD, and two attempts to absorb the event on the HUD side could
	# never have worked.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_to_cursor(height - zoom_speed, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_to_cursor(height + zoom_speed, event.position)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var factor = (height / 500.0) * world_scale
		global_position.x -= event.relative.x * factor
		global_position.z -= event.relative.y * factor
