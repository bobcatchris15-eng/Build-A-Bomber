# DCTables — Lookup tables and helpers for 3D Dual Contouring.
# Pure data, no state. Used by sdf_mesh_baker.gd.

const CORNER_OFFSETS := [
	Vector3(0, 0, 0), # 0
	Vector3(1, 0, 0), # 1
	Vector3(1, 0, 1), # 2
	Vector3(0, 0, 1), # 3
	Vector3(0, 1, 0), # 4
	Vector3(1, 1, 0), # 5
	Vector3(1, 1, 1), # 6
	Vector3(0, 1, 1), # 7
]

const EDGE_CORNERS := [
	[0, 1], [1, 2], [2, 3], [3, 0], # bottom 0..3
	[4, 5], [5, 6], [6, 7], [7, 4], # top 4..7
	[0, 4], [1, 5], [2, 6], [3, 7], # verticals 8..11
]

# Axis of each edge: 0 = X, 1 = Y, 2 = Z
const EDGE_AXIS := [
	0, 2, 0, 2, # 0..3
	0, 2, 0, 2, # 4..7
	1, 1, 1, 1  # 8..11
]

# For an edge starting at cell corner (ix, iy, iz) along axis X (0), Y (1), or Z (2),
# these are the relative 4 cell indices (in order around the edge) that share the edge.
# Format: Array of Vector3i per axis.
const QUAD_CELL_OFFSETS := [
	# Axis 0 (X-aligned edge): cells in YZ plane
	[Vector3i(0, 0, 0), Vector3i(0, -1, 0), Vector3i(0, -1, -1), Vector3i(0, 0, -1)],
	# Axis 1 (Y-aligned edge): cells in XZ plane
	[Vector3i(0, 0, 0), Vector3i(-1, 0, 0), Vector3i(-1, 0, -1), Vector3i(0, 0, -1)],
	# Axis 2 (Z-aligned edge): cells in XY plane
	[Vector3i(0, 0, 0), Vector3i(0, -1, 0), Vector3i(-1, -1, 0), Vector3i(-1, 0, 0)],
]
