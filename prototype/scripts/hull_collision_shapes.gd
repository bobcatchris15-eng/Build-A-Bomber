extends Resource
# The convex pieces a hull's collision shell decomposes into, saved next to the
# hull mesh as `assets/models/hulls/<id>_collision.res` by
# tools/bake_hull_roster.gd.
#
# WHY THIS IS BAKED RATHER THAN COMPUTED AT SPAWN. Convex decomposition is
# expensive - seconds, on a mesh this size - and unit_assembly.gd's own note
# records that it used to HANG outright on the unwelded triangle soup the SDF
# baker emitted (mesh_weld.gd is the fix for that half). Even now that it
# terminates, running it when a factory finishes a tank would be a multi-second
# stall exactly when reinforcements arrive, which is the same failure the hull
# template cache exists to prevent. It is a tool-time cost, so it is paid at
# tool time.
#
# WHY A RESOURCE AND NOT JSON. These are point clouds - a dozen hulls of a few
# dozen vertices each. A text sidecar would be a large, unreadable, unmergeable
# diff on every re-bake; a binary .res is compact and Godot deserialises it
# straight into the PackedVector3Arrays that ConvexPolygonShape3D wants.
#
# No class_name deliberately, matching hull_surface.gd / mesh_asset_loader.gd:
# the saved .res records the script PATH, so it loads correctly without the
# global, and class_name is unreliable in a headless run before the .godot
# cache exists - which is precisely the situation the baker runs in.

# One PackedVector3Array per convex piece, in HULL MESH LOCAL SPACE - the same
# space Mesh.create_convex_shape() produced its single hull in, so a caller
# swapping between the two needs no transform change.
@export var hulls: Array[PackedVector3Array] = []

# What produced this, for the record. A hull baked before a decomposition
# setting changed is otherwise indistinguishable from one baked after.
@export var source_triangles: int = 0
@export var max_convex_hulls: int = 0


func piece_count() -> int:
	return hulls.size()


## The pieces as ready-to-mount shapes. Built fresh each call rather than
## cached on the resource: a Shape3D held by the resource would be SHARED by
## every unit that mounts it, which is fine, but it would also be kept alive by
## the resource cache long after the match that used it - and clear_hull_cache()
## exists precisely so between-match state does not accumulate.
func to_shapes() -> Array:
	var out: Array = []
	for points in hulls:
		if points.size() < 4:
			# Fewer than four points cannot bound a volume. VHACD does not emit
			# these, but a hand-edited or truncated file could, and a degenerate
			# ConvexPolygonShape3D is a physics-server error per frame rather
			# than a visible failure.
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		out.append(shape)
	return out
