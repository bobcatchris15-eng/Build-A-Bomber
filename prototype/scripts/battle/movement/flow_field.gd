class_name FlowField
extends RefCounted
# One shared vector field per destination, so N units cost one search instead of
# N searches.
#
# WHY, CONCRETELY. Every unit under NavigationAgent3D runs its own A* to the same
# point. Thirty units means thirty searches over the same graph producing thirty
# near-identical corridors, and because each corridor is a thin line of waypoints
# they all funnel onto it - which is what a conga line actually is. A field is
# computed once from the destination outward, and every unit just reads the cell
# it is standing in.
#
# PASSABILITY COMES FROM THE NAVMESH, NOT FROM THE TERRAIN.
# The tempting implementation re-derives walkability here: sample the heightmap,
# check the slope, test the water blobs, subtract the building footprints. That
# is a second, parallel definition of "where can a unit go", and the moment it
# disagrees with the baked navmesh - a Recast cell-size rounding, a bridge deck,
# a building hole - units driven by the field walk somewhere agents refuse to,
# and the bug looks like a movement bug rather than a definition bug.
#
# Instead each cell asks NavigationServer3D for the closest point on the real
# ground navmesh and calls itself passable only if that point is nearby. The
# field agrees with the navmesh BY CONSTRUCTION, including the building holes the
# rebake already carves, and there is nothing to keep in sync.
#
# WHAT IT DOES NOT DO. Ground only. Naval, deep-water, amphibious and air keep
# their agents: each is a different navmesh, so each would need its own field per
# destination, and none of them ever move in the numbers that make a field pay.

# 4 m is a bit over one medium hull. Fine enough that a field corner reads as a
# curve rather than a staircase, coarse enough that a 320 m map is 80x80 = 6,400
# cells rather than a quarter of a million.
const CELL_SIZE := 4.0

# How far a cell centre may sit from the navmesh and still count as passable.
# Slightly over half a diagonal, so a cell straddling the navmesh edge is
# included rather than fraying the walkable region by a cell all the way round.
const PASSABLE_TOLERANCE := CELL_SIZE * 0.75

# Sentinel for "not reached". Any real integrated cost is far below it.
const UNREACHABLE := 1.0e20

# 8-connected, cardinals first so those relaxations land before the diagonals.
# Typed, because an untyped Array yields Variants and `var next := cell + n` then
# cannot infer a type.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var origin := Vector3.ZERO   # world position of cell (0,0)'s corner
var dims := Vector2i.ZERO
var destination := Vector3.ZERO

var _passable: PackedByteArray = PackedByteArray()
# FLOAT64, NOT FLOAT32, and this is not a precision nicety - it is correctness.
#
# The heap carries GDScript floats, which are float64. Storing the integrated
# cost as float32 rounds it on the way in, so a diagonal step of sqrt(2) is
# written as 1.4142135 and read back as very slightly LESS than the 1.41421356
# still sitting in the heap. The staleness check `if cost > _cost[index]` then
# fires on a perfectly fresh entry and the cell is discarded unexpanded.
#
# Only exactly-representable costs - pure-cardinal integer paths - survived that,
# and since a diagonal is always cheaper than the two cardinals it replaces, the
# cheap diagonal entries poisoned their cells and the cardinal routes never got
# to overwrite them. The frontier collapsed and most of the map integrated to
# UNREACHABLE. Caught by test_flow_field_integrates_and_points_home.
var _cost: PackedFloat64Array = PackedFloat64Array()
# Unit XZ direction per cell, packed as Vector2(x, z).
var _flow: PackedVector2Array = PackedVector2Array()


static func build(nav_map: RID, map_half_extents: float, to: Vector3) -> FlowField:
	var f := FlowField.new()
	f.destination = to
	f.origin = Vector3(-map_half_extents, 0.0, -map_half_extents)
	var side := int(ceil((map_half_extents * 2.0) / CELL_SIZE))
	f.dims = Vector2i(side, side)
	f._sample_passability(nav_map)
	f._integrate()
	f._derive_flow()
	return f


func cell_count() -> int:
	return dims.x * dims.y


func index_of(cell: Vector2i) -> int:
	return cell.y * dims.x + cell.x


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < dims.x and cell.y < dims.y


func cell_at(world: Vector3) -> Vector2i:
	return Vector2i(
		int(floor((world.x - origin.x) / CELL_SIZE)),
		int(floor((world.z - origin.z) / CELL_SIZE)))


func centre_of(cell: Vector2i) -> Vector3:
	return Vector3(
		origin.x + (float(cell.x) + 0.5) * CELL_SIZE,
		0.0,
		origin.z + (float(cell.y) + 0.5) * CELL_SIZE)


func is_passable(cell: Vector2i) -> bool:
	return in_bounds(cell) and _passable[index_of(cell)] == 1


# Whether the destination was reachable from `world`. A unit standing in a
# pocket the field never filled must fall back to its agent rather than sitting
# still - the field genuinely has no answer for it.
func has_route(world: Vector3) -> bool:
	var cell := cell_at(world)
	if not in_bounds(cell):
		return false
	return _cost[index_of(cell)] < UNREACHABLE


# The horizontal direction to travel from `world`, or ZERO if the field has
# nothing to say here.
func direction_at(world: Vector3) -> Vector3:
	var cell := cell_at(world)
	if not in_bounds(cell):
		return Vector3.ZERO
	var v := _flow[index_of(cell)]
	return Vector3(v.x, 0.0, v.y)


# --- Construction -----------------------------------------------------------

func _sample_passability(nav_map: RID) -> void:
	var count := cell_count()
	_passable.resize(count)
	if not nav_map.is_valid():
		# No navmesh (a standalone test, or a match built without terrain).
		# Everything is passable, which degrades the field to straight-line
		# steering rather than to a wall of impassable cells.
		for i in range(count):
			_passable[i] = 1
		return
	for y in range(dims.y):
		for x in range(dims.x):
			var centre := centre_of(Vector2i(x, y))
			var nearest := NavigationServer3D.map_get_closest_point(nav_map, centre)
			# Horizontal distance only. The navmesh sits at terrain height and
			# the probe point is at y=0, so a vertical component would make every
			# hilltop read as unreachable.
			var dx := nearest.x - centre.x
			var dz := nearest.z - centre.z
			_passable[y * dims.x + x] = 1 if (dx * dx + dz * dz) <= (PASSABLE_TOLERANCE * PASSABLE_TOLERANCE) else 0


# Dijkstra outward from the destination cell.
#
# Dijkstra rather than BFS because the field is 8-connected: a diagonal step is
# sqrt(2) times as long, and treating it as equal cost makes the field prefer
# staircases and produces visibly wrong routes around obstacle corners.
#
# The queue is a binary heap kept in a flat array. GDScript has no priority queue,
# and the alternatives are both worse at this size - sorting an array on every
# insert is O(n^2), and a plain Array.min() scan is the same.
func _integrate() -> void:
	var count := cell_count()
	_cost.resize(count)
	for i in range(count):
		_cost[i] = UNREACHABLE

	var start := cell_at(destination)
	if not in_bounds(start):
		return
	# A destination clicked onto an impassable cell (the shore of a lake, a
	# building) still has to produce a usable field, or right-clicking slightly
	# off the walkable area does nothing at all. Seed from the nearest passable
	# cell instead of giving up.
	if not is_passable(start):
		start = _nearest_passable(start)
		if start.x < 0:
			return

	var heap_cell: Array[int] = []
	var heap_cost: Array[float] = []
	_cost[index_of(start)] = 0.0
	_heap_push(heap_cell, heap_cost, index_of(start), 0.0)

	var root_two := sqrt(2.0)

	while not heap_cell.is_empty():
		var popped := _heap_pop(heap_cell, heap_cost)
		var index: int = popped[0]
		var cost: float = popped[1]
		# Stale entry: this cell was already relaxed to something cheaper after
		# it was pushed. Cheaper to skip here than to support decrease-key.
		if cost > _cost[index]:
			continue
		var cell := Vector2i(index % dims.x, int(index / dims.x))
		for n in NEIGHBOURS:
			var next := cell + n
			if not is_passable(next):
				continue
			var step: float = root_two if (n.x != 0 and n.y != 0) else 1.0
			# A diagonal must not cut the corner between two blocked cells, or
			# units clip through the gap between two buildings placed corner to
			# corner.
			if n.x != 0 and n.y != 0:
				if not is_passable(Vector2i(cell.x + n.x, cell.y)) or not is_passable(Vector2i(cell.x, cell.y + n.y)):
					continue
			var next_index := index_of(next)
			var next_cost := cost + step
			if next_cost < _cost[next_index]:
				_cost[next_index] = next_cost
				_heap_push(heap_cell, heap_cost, next_index, next_cost)


# Outward ring search for a passable cell near an unusable seed.
func _nearest_passable(from: Vector2i) -> Vector2i:
	var max_radius: int = maxi(dims.x, dims.y)
	for radius in range(1, max_radius):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				# Perimeter of the ring only - the interior was covered by
				# smaller radii.
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := Vector2i(from.x + dx, from.y + dy)
				if is_passable(candidate):
					return candidate
	return Vector2i(-1, -1)


# Each cell points at whichever neighbour has the lowest integrated cost.
func _derive_flow() -> void:
	var count := cell_count()
	_flow.resize(count)
	for y in range(dims.y):
		for x in range(dims.x):
			var cell := Vector2i(x, y)
			var index := index_of(cell)
			if _cost[index] >= UNREACHABLE:
				_flow[index] = Vector2.ZERO
				continue
			var best := _cost[index]
			var best_dir := Vector2.ZERO
			for n in NEIGHBOURS:
				var next := cell + n
				if not in_bounds(next):
					continue
				var next_cost := _cost[index_of(next)]
				if next_cost < best:
					best = next_cost
					best_dir = Vector2(float(n.x), float(n.y))
			_flow[index] = best_dir.normalized() if best_dir != Vector2.ZERO else Vector2.ZERO


# --- Binary heap (min by cost) ----------------------------------------------

static func _heap_push(cells: Array[int], costs: Array[float], cell: int, cost: float) -> void:
	cells.append(cell)
	costs.append(cost)
	var i := cells.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if costs[parent] <= costs[i]:
			break
		_heap_swap(cells, costs, i, parent)
		i = parent


static func _heap_pop(cells: Array[int], costs: Array[float]) -> Array:
	var top_cell := cells[0]
	var top_cost := costs[0]
	var last := cells.size() - 1
	cells[0] = cells[last]
	costs[0] = costs[last]
	cells.remove_at(last)
	costs.remove_at(last)

	var size := cells.size()
	var i := 0
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var smallest := i
		if left < size and costs[left] < costs[smallest]:
			smallest = left
		if right < size and costs[right] < costs[smallest]:
			smallest = right
		if smallest == i:
			break
		_heap_swap(cells, costs, i, smallest)
		i = smallest
	return [top_cell, top_cost]


static func _heap_swap(cells: Array[int], costs: Array[float], a: int, b: int) -> void:
	var c := cells[a]
	cells[a] = cells[b]
	cells[b] = c
	var t := costs[a]
	costs[a] = costs[b]
	costs[b] = t
