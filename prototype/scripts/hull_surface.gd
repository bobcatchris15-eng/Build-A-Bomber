# HullSurface: the precise, trimesh-of-the-visible-mesh collider that placement
# and damage raycasts trace against, instead of the hull's simplified bounding
# box.
#
# No class_name / no `extends` - same convention as hull_loader.gd,
# mesh_asset_loader.gd and sdf_mesh_baker.gd (class_name globals aren't
# reliable in scripts run headless before the .godot cache exists).
#
# This used to live as _rebuild_surface_body() inside module_placer.gd, which
# meant only the two paths that script owns (a freshly placed hull, and a hull
# swap) ever got one. blueprint_manager.gd's designer reconstruction built the
# bounding box and nothing else, so a LOADED blueprint had no precise surface at
# all and every module dropped onto it snapped to the bounding shell - the same
# floating-module bug the surface body was introduced to fix, still present on
# exactly the path most used for iterating on a saved design.
#
# Extracted here so there is one definition of the layer and the shape setup,
# reachable from both scripts.

# Layer 5 (bit value 16) is unused by the hull(1)/modules(2)/gizmos(4)/
# buildings(8) assignments already in play, so placement can query the precise
# surface alone without picking up anything else.
const SURFACE_COLLISION_LAYER := 16

# Replaces any existing HullSurface under `target_hull` with a fresh trimesh of
# `source_mesh_inst`. Safe to call repeatedly; a no-op if there is no mesh to
# trace against (the caller's bounding-box collider stays the fallback).
static func rebuild(target_hull: Node3D, source_mesh_inst: MeshInstance3D) -> void:
	if not target_hull or not is_instance_valid(target_hull):
		return
	var existing = target_hull.get_node_or_null("HullSurface")
	if existing:
		target_hull.remove_child(existing)
		existing.free()
	if not source_mesh_inst or not source_mesh_inst.mesh:
		return
	var tri_shape: ConcavePolygonShape3D = source_mesh_inst.mesh.create_trimesh_shape()
	if not tri_shape:
		return

	# Collide from both sides.
	#
	# ConcavePolygonShape3D defaults to backface_collision = false, so a ray
	# that reaches a triangle's back face passes straight through it. The SDF
	# baker was emitting ~30% of every hull's triangles wound inward (fixed in
	# sdf_mesh_baker.gd's _build_faceted_mesh), and those faces were invisible
	# to placement raycasts - large stretches of hull that simply would not
	# accept a module. Winding is correct now, so this is belt-and-braces: one
	# stray flipped triangle from a future baker change costs a small amount of
	# raycast work here instead of silently reopening a dead zone.
	tri_shape.backface_collision = true

	var body := StaticBody3D.new()
	body.name = "HullSurface"
	body.collision_layer = SURFACE_COLLISION_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = tri_shape
	# Match the visual mesh exactly - same orientation correction and same
	# per-axis fit - so the surface we snap to IS the surface being drawn.
	col.transform = source_mesh_inst.transform
	body.add_child(col)
	target_hull.add_child(body)
