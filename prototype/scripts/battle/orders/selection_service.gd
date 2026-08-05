class_name SelectionService
extends RefCounted
# Who is selected, and how the player says so.
#
# THE FRUSTUM. A drag box is trivially a Rect2 in 2D. In 3D it is a truncated
# pyramid, and the old runtime dodged that by projecting each unit's origin to
# the screen and testing `rect.has_point()` (skirmish.gd:3191). That is wrong in
# three specific ways, all of which a player notices:
#
#   * NO DEPTH. A unit behind the camera projects to a screen point like any
#     other, so a drag box could select units behind the player.
#   * ORIGIN ONLY. A tank whose origin is a pixel outside the box is missed even
#     when nine tenths of it is inside.
#   * NO OCCLUSION AWARENESS. There is no shape involved at all, so nothing can
#     ever be reasoned about spatially.
#
# Projecting the box's four corners into the world at the near and far planes
# gives eight points; their convex hull IS the frustum; and the physics server
# answers "what is inside this volume" natively. It is less code than the
# projection loop and it is correct.
#
# It queries the SELECTION layer only - a per-unit proxy box, see
# battle_layers.gd - so it gets exactly one hit per unit and never has to walk
# parents or dedupe.

const LayersScript = preload("res://scripts/battle/battle_layers.gd")

# intersect_shape defaults to 32 results, which an RTS reaches in one drag across
# its own base. Well above any plausible army; the cost of an unused ceiling is
# nothing, and silently truncating a selection is maddening to diagnose.
const MAX_QUERY_RESULTS := 1024

# Below this, a drag is a click. Matches the old runtime's threshold so the feel
# of a slightly-shaky click is unchanged.
const DRAG_THRESHOLD_PX := 10.0

const CONTROL_GROUP_DOUBLE_TAP_MS := 400

signal selection_changed(units: Array)
# Emitted on a double-tapped control group digit, for the camera to act on.
signal group_recentre_requested(centre: Vector3)

var selected: Array = []

# num -> Array of units. Members are filtered for validity at READ time rather
# than pruned on death: a unit can be freed in any order relative to this
# dictionary, and eager pruning means every death has to find every group it
# might be in. Reading is where the answer has to be right.
var control_groups: Dictionary = {}

var _camera: Camera3D = null
var _space: PhysicsDirectSpaceState3D = null
var _team: int = 0

var _last_group_num: int = -1
var _last_group_time_ms: int = 0


func setup(camera: Camera3D, space: PhysicsDirectSpaceState3D, owning_team: int) -> void:
	_camera = camera
	_space = space
	_team = owning_team


# --- Queries ----------------------------------------------------------------

# Everything owned by `_team` whose selection proxy intersects the screen-space
# rectangle.
func units_in_rect(rect: Rect2) -> Array:
	if _camera == null or _space == null:
		return []
	var shape := ConvexPolygonShape3D.new()
	shape.points = frustum_points(_camera, rect)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# Points are already in world space, so the shape needs no placement of its
	# own. Building them in world space rather than camera-local avoids a second
	# basis conversion that has nothing to check it.
	query.transform = Transform3D.IDENTITY
	query.collision_mask = LayersScript.SELECTION_QUERY_MASK
	# Proxies are Area3Ds. Bodies are excluded deliberately - including them would
	# return the unit's own CharacterBody3D alongside its proxy.
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var out: Array = []
	for hit in _space.intersect_shape(query, MAX_QUERY_RESULTS):
		var unit := _unit_from(hit.get("collider"))
		if unit != null and not out.has(unit):
			out.append(unit)
	return out


# The eight world-space corners of the volume `rect` sweeps out.
#
# Static and camera-in so a test can assert the geometry without a physics world:
# the frustum is the part that is easy to get subtly wrong, and it is the part
# that never needs a scene to check.
static func frustum_points(camera: Camera3D, rect: Rect2) -> PackedVector3Array:
	var corners := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	]
	var points := PackedVector3Array()
	# camera.near rather than 0: a point at the ray origin sits ON the camera
	# plane, and four coincident-ish near points can collapse the hull for a very
	# small drag box.
	var near: float = maxf(camera.near, 0.05)
	var far: float = camera.far
	for c in corners:
		var origin := camera.project_ray_origin(c)
		var normal := camera.project_ray_normal(c)
		points.append(origin + normal * near)
		points.append(origin + normal * far)
	return points


# The unit under a single click, or null.
func unit_at_point(screen_pos: Vector2) -> Node:
	if _camera == null or _space == null:
		return null
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * _camera.far
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = LayersScript.SELECTION_QUERY_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := _space.intersect_ray(query)
	return _unit_from(hit.get("collider")) if not hit.is_empty() else null


# The proxy carries a back-reference to its unit, so this never has to guess how
# deep in the unit's tree the shape sits.
func _unit_from(collider) -> Node:
	if collider == null or not is_instance_valid(collider) or not collider.has_meta("unit"):
		return null
	var unit = collider.get_meta("unit")
	if not is_instance_valid(unit) or unit.is_dead or unit.team != _team:
		return null
	return unit


# --- Mutation ---------------------------------------------------------------

func set_selection(units: Array) -> void:
	for u in selected:
		if is_instance_valid(u):
			u.set_selected(false)
	selected = []
	for u in units:
		if is_instance_valid(u) and not selected.has(u):
			u.set_selected(true)
			selected.append(u)
	selection_changed.emit(selected)


func add_to_selection(units: Array) -> void:
	var merged := selected.duplicate()
	for u in units:
		if is_instance_valid(u) and not merged.has(u):
			merged.append(u)
	set_selection(merged)


func clear() -> void:
	set_selection([])


# Drops freed units. Called after deaths so the HUD and any group order stop
# counting corpses.
func prune() -> void:
	var alive: Array = []
	for u in selected:
		if is_instance_valid(u) and not u.is_dead:
			alive.append(u)
	if alive.size() != selected.size():
		selected = alive
		selection_changed.emit(selected)


# --- Control groups ---------------------------------------------------------

func assign_group(num: int) -> bool:
	if selected.is_empty():
		return false
	control_groups[num] = selected.duplicate()
	return true


# Recalls a slot. Pressing the same digit twice inside the double-tap window also
# asks for a camera recentre, which is the OpenRA/RA2 convention.
func recall_group(num: int) -> bool:
	if not control_groups.has(num):
		return false
	var alive: Array = []
	for u in control_groups[num]:
		if is_instance_valid(u) and not u.is_dead:
			alive.append(u)
	control_groups[num] = alive
	if alive.is_empty():
		return false
	set_selection(alive)

	var now := Time.get_ticks_msec()
	var double_tapped := num == _last_group_num and (now - _last_group_time_ms) <= CONTROL_GROUP_DOUBLE_TAP_MS
	_last_group_num = num
	_last_group_time_ms = now
	if double_tapped:
		group_recentre_requested.emit(centroid())
	return true


func centroid() -> Vector3:
	if selected.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for u in selected:
		sum += u.global_position
	return sum / float(selected.size())
