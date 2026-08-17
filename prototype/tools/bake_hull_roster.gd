extends SceneTree
# Headless built-in hull roster baker.
#
#   Godot_v4.3-stable_win64_console.exe --headless --script res://tools/bake_hull_roster.gd
#   ... --headless --script res://tools/bake_hull_roster.gd -- medium_hull light_hull
#
# Reads the editable hull ASSEMBLY sources in data/hull_assemblies/*.json
# (authored in the in-game Hull Builder via its Save Assembly button, then
# committed) and bakes each one into the pair the rest of the game already
# consumes:
#     assets/models/hulls/<id>.res    - fused mesh (SDF smooth-min + Marching
#                                       Cubes, see scripts/sdf_mesh_baker.gd)
#     assets/models/hulls/<id>.json   - stats sidecar (scripts/hull_loader.gd)
#
# This is the SDF-pipeline counterpart to tools/blender/build_meshes.py's hull
# half: the roster stays reproducible from version-controlled source data
# rather than depending on someone hand-clicking Export in the editor. The
# parts/weapons half of build_meshes.py is untouched and still required.
#
# Passing hull ids after a bare `--` bakes only those (fast iteration on one
# hull); with no ids, the whole directory is baked.
#
# Each bake also writes a third file:
#     assets/models/hulls/<id>_collision.res  - convex decomposition of the
#                                               welded shell (see _bake_collision)
# `-- --collision-only` writes ONLY that, from the mesh already on disk, so
# collision data can be added to a shipped roster without regenerating - and
# therefore risking a change to - the hull geometry itself.

const SDFMeshBaker = preload("res://scripts/sdf_mesh_baker.gd")
const MeshWeld = preload("res://scripts/mesh_weld.gd")
const HullCollisionShapes = preload("res://scripts/hull_collision_shapes.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const HullFacets = preload("res://scripts/hull_facets.gd")
# Explicit preload rather than leaning on `class_name ModuleCatalog`: this file
# runs as `--headless --script`, where a cold/stale .godot class cache resolves
# global class names inconsistently. Used for classify_facet() when grouping
# facets into the six sides.
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

const ASSEMBLY_DIR := "res://data/hull_assemblies"
const OUT_DIR := "res://assets/models/hulls"

# --- Collision decomposition ---------------------------------------------
#
# A spawned unit's body collider was a SINGLE convex fit of the hull mesh
# (unit_assembly._add_hull_collider), which fills deck wells, the gap under a
# tapered keel and the space between sponsons - all of it solid. The usual
# answer is convex DECOMPOSITION, and that file records why it wasn't used:
# it "never returned on the smallest hull in the roster at max_convex_hulls as
# low as 4", because _build_faceted_mesh emits unwelded triangle soup and the
# decomposer has no vertex adjacency to work from. mesh_weld.gd fixes the input;
# this bakes the output so no unit ever pays for it at spawn time.
#
# 16 pieces is the ceiling. Each piece is a real shape in the physics server for
# every unit alive, so this trades directly against how many units a match can
# hold - and past a dozen or so the remaining error is deck greebles, not the
# structural concavities that made shots land on empty air. Measured, the
# roster does not come close: hulls decompose into 1-3 pieces.
const MAX_CONVEX_HULLS := 16

# VHACD's voxel budget. The default (10000) loses features around the size of a
# sponson recess; 50000 keeps them and still finishes in ~150 ms per hull at
# tool time, which is the only time it runs.
const DECOMP_RESOLUTION := 50000

# THE SETTING THAT ACTUALLY DOES THE WORK, and the one that is useless at its
# default. max_concavity is "how much concavity may a piece keep", and it
# defaults to 1.0 - which is to say "all of it", so VHACD hands back ONE piece
# and the whole exercise reproduces the single convex fit that already shipped.
# Measured across the roster: at 1.0 every hull returns 1 piece; at 0.25 some
# return 2; at 0.05 they settle at 1-3 and stop changing by 0.01. So 0.05 is the
# point where the concavities that matter have been split out and further
# tightening only costs time.
const DECOMP_MAX_CONCAVITY := 0.05

# A weld that merges nothing means the mesh arrived already indexed OR the
# tolerance missed, and a decomposition run on it will hang the way it always
# did. Loud, because the failure mode it guards is "the baker appears to work
# and the next person to run it waits forever".
const WELD_RATIO_CEILING := 0.9

# Baked-AABB vs declared-`size` tolerance. Below SOFT it's noise from the
# skin-fit inset; above HARD the collision box is visibly wrong.
const SOFT_DRIFT := 0.05
const HARD_DRIFT := 0.15

# Hulls whose baked extents disagree with their declared size beyond HARD_DRIFT.
# Reported always; fails the run only under --strict, so an existing red roster
# doesn't block unrelated work.
var drifted := 0
var strict := false

# `-- --collision-only` skips the SDF bake and the sidecar entirely and just
# (re)writes each hull's `_collision.res` from the mesh already on disk.
#
# This exists because adding the decomposition should not force a full roster
# re-bake. Re-baking rewrites every `<id>.res`, which is a multi-megabyte binary
# diff across the whole roster and re-runs marching cubes on geometry that is
# already correct and already shipped - any drift in the baker since those files
# were written would silently change hull SHAPES as a side effect of adding
# collision data. Loading what is there and decomposing that changes nothing a
# player can see.
var collision_only := false

# `-- --facets-only` writes ONLY the facet segmentation into the existing
# sidecars, from the meshes already on disk. Enumerates the same shipped-roster
# set as --collision-only and for the same reason: the Blender-authored hulls
# have sidecars but no assembly sources.
var facets_only := false

# Must stay in sync with hull_builder.gd's PrimitiveType enum. Duplicated
# here rather than imported because hull_builder.gd is a Node3D bound to a
# scene full of @onready UI references - instancing it headlessly just to read
# an enum would drag the whole editor scene in. The round-trip test in
# scripts/tests/ asserts the two lists match, so drift fails loudly.
const PRIMITIVE_TYPE_NAMES := [
	"BOX", "SPHERE", "CYLINDER", "WEDGE", "CONE", "TORUS",
	"SLOPE", "FRUSTUM", "CHAMFER_BOX", "HALF_CYLINDER", "HEMISPHERE",
	"CAPSULE", "I_BEAM", "L_BEAM", "HEX_PRISM", "PYRAMID",
	"FENDER", "CANOPY", "RING",
]

func _init() -> void:
	var only_ids := _parse_id_filter()

	# --collision-only enumerates the SHIPPED roster (sidecars in OUT_DIR),
	# every other mode enumerates the SOURCE assemblies. They are not the same
	# set and cannot be: the assemblies are what this file bakes, the sidecars
	# are what the game loads, and the Blender-authored hulls that make up the
	# current roster have the latter without the former.
	var from_sidecars := collision_only or facets_only
	var sources: Array = _list_collision_ids() if from_sidecars else _list_assemblies()
	if sources.is_empty():
		if from_sidecars:
			printerr("No hull sidecars found in %s" % OUT_DIR)
		else:
			printerr("No assemblies found in %s" % ASSEMBLY_DIR)
		quit(1)
		return

	var baked := 0
	var failed := 0
	var total_tris := 0

	for path in sources:
		# In collision-only mode `path` IS the stem; otherwise it is a full
		# assembly path to take the basename of.
		var stem: String = str(path) if from_sidecars else str(path).get_file().get_basename()
		if not only_ids.is_empty() and not only_ids.has(stem):
			continue
		var result: int
		if facets_only:
			result = _facets_only_one(stem)
		elif collision_only:
			result = _collision_only_one(stem)
		else:
			result = _bake_one(path, stem)
		if result < 0:
			failed += 1
		else:
			baked += 1
			total_tris += result

	print("")
	if facets_only:
		print("Wrote facet maps for %d hull(s), %d failed. Total %d triangles." % [
			baked, failed, total_tris])
	elif collision_only:
		print("Wrote collision for %d hull(s), %d failed. Total %d triangles." % [
			baked, failed, total_tris])
	else:
		print("Baked %d hull(s), %d failed, %d with size drift. Total %d triangles." % [
			baked, failed, drifted, total_tris])
	if drifted > 0 and not strict:
		print("Re-run with `-- --strict` to make size drift fail the build.")
	quit(1 if failed > 0 or (strict and drifted > 0) else 0)

func _parse_id_filter() -> Dictionary:
	var ids := {}
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--strict":
			strict = true
			continue
		if a == "--collision-only":
			collision_only = true
			continue
		if a == "--facets-only":
			facets_only = true
			continue
		ids[a] = true
	return ids

func _list_assemblies() -> Array:
	var out := []
	var dir := DirAccess.open(ASSEMBLY_DIR)
	if not dir:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "json":
			out.append("%s/%s" % [ASSEMBLY_DIR, f])
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

# Returns the triangle count on success, or -1 on failure.
func _bake_one(path: String, stem: String) -> int:
	var data = _read_json(path)
	if data == null:
		return -1

	var primitives := _to_runtime_primitives(data.get("primitives", []), stem)
	if primitives.is_empty():
		printerr("  %s: assembly has no usable primitives" % stem)
		return -1

	var bake: Dictionary = data.get("bake", {})
	var smoothness := float(bake.get("smoothness", 0.15))
	var resolution := int(bake.get("resolution", 24))
	var method := str(bake.get("method", "dc"))
	var fit_percent := float(bake.get("fit_percent", 95.0))
	var facet_angle := float(bake.get("facet_angle", 15.0))
	var crystallinity := float(bake.get("crystallinity", 0.0))
	# Every knob SDFMeshBaker.bake() accepts must be read here and passed on.
	# chamfer_edge_pct was missing, so the pipeline baked at the 5.0 default
	# regardless of what was authored - the same hull came out of CI different
	# from the way it came out of the in-game builder.
	var chamfer_edge_pct := float(bake.get("chamfer_edge_pct", 5.0))
	var mirror_x := bool(bake.get("mirror_x", false))

	_warn_on_subvoxel_features(primitives, resolution, smoothness, stem)

	var t0 := Time.get_ticks_msec()
	var mesh: ArrayMesh = SDFMeshBaker.bake(primitives, smoothness, resolution, method, fit_percent, facet_angle, crystallinity, chamfer_edge_pct, mirror_x)
	var elapsed := Time.get_ticks_msec() - t0
	if mesh == null:
		printerr("  %s: bake produced no geometry" % stem)
		return -1

	var mesh_path := "%s/%s.res" % [OUT_DIR, stem]
	var err := ResourceSaver.save(mesh, mesh_path)
	if err != OK:
		printerr("  %s: could not save mesh (error %d)" % [stem, err])
		return -1

	# The sidecar is copied through VERBATIM from the assembly source. It is
	# deliberately never recomputed from the baked AABB the way the in-editor
	# export dialog does it: `size` drives the collision box, mount facets,
	# ModuleCatalog.get_hull_mesh_fit()'s orientation search and size tier, so
	# re-deriving it would silently move every module mount zone on every
	# existing design; and hp/weight/metal/crystal are hand-balanced.
	var sidecar: Dictionary = data.get("sidecar", {})
	if sidecar.is_empty():
		printerr("  %s: assembly has no sidecar block - refusing to write a statless hull" % stem)
		return -1
	if not _write_sidecar(stem, sidecar):
		return -1

	var tris := mesh.get_faces().size() / 3
	var aabb := mesh.get_aabb()
	print("  %-30s %5d tris  %4d ms  mesh aabb %s  size %s" % [
		stem, tris, elapsed,
		_fmt_v3(aabb.size), str(sidecar.get("size", "?"))])
	_check_size_drift(stem, aabb, sidecar)
	_check_topology(stem, mesh, method)
	_bake_collision(stem, mesh, tris)
	return tris


# Decomposition for a hull whose mesh is already on disk.
#
# RESOLVED THROUGH MeshAssetLoader, not by reading `<id>.res` directly, and that
# is load-bearing rather than tidiness. The roster is NOT all one format: the
# SDF pipeline in this file writes .res, but every hull currently shipping is a
# Blender-authored .glb from tools/blender/build_vehicle_hulls.py, and a hull
# can also declare `primitive_shape` in its sidecar and have no mesh file at
# all. get_hull_mesh() is the precedence chain the GAME uses, so going through
# it is what guarantees the collision shell describes the mesh a unit actually
# spawns with. An earlier version of this looked for `<id>.res` and would have
# reported "no baked mesh" for all 94 hulls.
#
# Returns the triangle count, or -1 if nothing resolved.
# `-- --facets-only` writes ONLY the facet segmentation into each hull's
# existing `<id>.json` sidecar, from the mesh already on disk. Same reasoning as
# --collision-only: adding placement data must never rewrite hull GEOMETRY, and
# it resolves the mesh through MeshAssetLoader.get_hull_mesh() - the same
# precedence chain the game uses - so the segmentation is guaranteed to describe
# the mesh a unit actually spawns with.
#
# The sidecar is read, mutated and rewritten rather than regenerated, so every
# hand-tuned stat field in it survives untouched.
func _facets_only_one(stem: String) -> int:
	var mesh := MeshAssetLoader.get_hull_mesh(stem)
	if mesh == null:
		printerr("  %s: get_hull_mesh() resolved nothing - no mesh to segment" % stem)
		return -1
	var tris := mesh.get_faces().size() / 3
	if tris <= 0:
		printerr("  %s: mesh has no triangles" % stem)
		return -1

	var path := "%s/%s.json" % [OUT_DIR, stem]
	var existing = _read_json(path)
	if not (existing is Dictionary):
		printerr("  %s: sidecar missing or unreadable at %s" % [stem, path])
		return -1

	var seg := HullFacets.segment(mesh)
	if int(seg.get("count", 0)) <= 0:
		printerr("  %s: segmentation produced no facets" % stem)
		return -1

	# Stored as a plain int array so the sidecar stays diffable JSON. tri_count
	# rides along as the runtime guard - the map is indexed BY TRIANGLE, so it
	# is only meaningful against the exact mesh it came from, and a re-exported
	# .glb has to be detected rather than silently mis-assigning facets.
	var map_out := []
	for v in (seg["map"] as PackedInt32Array):
		map_out.append(v)

	# Per-facet geometry, plus the six-side grouping the armor brush and the
	# damage resolver both key on.
	#
	# The SIDE classification is done HERE rather than inside HullFacets.segment()
	# on purpose. hull_facets.gd has no preloads at all - that is what lets it run
	# in this headless tool and in a test with no scene tree - and pulling in
	# module_catalog.gd (4000+ lines) to reach one 8-line pure function would cost
	# it that. Copying classify_facet() instead was the other option and is worse:
	# its own header calls it the single source of truth for what "the front"
	# means, shared with weapon mounting, and a second copy is exactly the drift
	# that comment exists to prevent.
	var f_normal: PackedVector3Array = seg.get("normal", PackedVector3Array())
	var f_centroid: PackedVector3Array = seg.get("centroid", PackedVector3Array())
	var f_area: PackedFloat32Array = seg.get("area", PackedFloat32Array())
	var n_out := []
	var c_out := []
	var a_out := []
	var side_out := []
	var weight_out := []
	var sides := {}
	var side_area := {}
	for s in HullFacets.SIDE_AXES.keys():
		sides[s] = []
		side_area[s] = 0.0
	for f in range(int(seg["count"])):
		var n: Vector3 = f_normal[f]
		var c: Vector3 = f_centroid[f]
		var a := float(f_area[f])
		# The dominant side. Kept as a label and for anything that wants one
		# answer per facet; it is NOT what the brush or the coverage math use -
		# see HullFacets.BRUSH_SIDE_MIN_WEIGHT for why that would lose the
		# glacis on 15 of the 94 hulls.
		var dominant: String = ModuleCatalog.classify_facet(n)
		var w := {}
		for s in HullFacets.SIDE_AXES.keys():
			var wt: float = maxf(0.0, n.dot(HullFacets.SIDE_AXES[s]))
			w[s] = wt
			# Projected area: what this facet is worth when shot at from `s`.
			# This is the denominator every coverage fraction divides by, so it
			# has to be the weighted area rather than a raw sum.
			side_area[s] = float(side_area[s]) + a * wt
			if wt >= HullFacets.BRUSH_SIDE_MIN_WEIGHT or s == dominant:
				sides[s].append(f)
		n_out.append([n.x, n.y, n.z])
		c_out.append([c.x, c.y, c.z])
		a_out.append(a)
		side_out.append(dominant)
		weight_out.append(w)

	# A side's brush set must never be empty, or that side is unpaintable.
	# The fixed threshold still leaves five hulls short - heavily rounded ones
	# (kestrel_oddball_b, tallow_transport_a) where no single facet faces a
	# given side by 60 degrees even though up to 13% of the hull's projected
	# area is there. Fall back to everything within half the best weight, which
	# adapts to how rounded the hull actually is instead of guessing a lower
	# global threshold that would over-select on the other 89.
	for s in sides.keys():
		if not (sides[s] as Array).is_empty():
			continue
		var best := 0.0
		for f in range(int(seg["count"])):
			best = maxf(best, float((weight_out[f] as Dictionary)[s]))
		if best <= 0.0:
			continue
		for f in range(int(seg["count"])):
			if float((weight_out[f] as Dictionary)[s]) >= best * 0.5:
				sides[s].append(f)

	existing[HullFacets.SIDECAR_KEY] = {
		"tri_count": int(seg["tri_count"]),
		"facet_count": int(seg["count"]),
		"winding": float(seg.get("winding", 1.0)),
		"map": map_out,
		"facet_normal": n_out,
		"facet_centroid": c_out,
		"facet_area": a_out,
		"facet_side": side_out,
		"facet_side_weight": weight_out,
		"sides": sides,
		"side_area": side_area,
		"total_area": float(seg.get("total_area", 0.0)),
	}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("  %s: could not open sidecar for writing" % stem)
		return -1
	f.store_string(JSON.stringify(existing, "  "))
	f.close()
	print("  %s: %d triangles -> %d facets" % [stem, tris, int(seg["count"])])
	return tris


func _collision_only_one(stem: String) -> int:
	var mesh := MeshAssetLoader.get_hull_mesh(stem)
	if mesh == null:
		printerr("  %s: get_hull_mesh() resolved nothing - no mesh to decompose" % stem)
		return -1
	var tris := mesh.get_faces().size() / 3
	if tris <= 0:
		printerr("  %s: mesh has no triangles" % stem)
		return -1
	_bake_collision(stem, mesh, tris)
	return tris


# Hull ids for --collision-only, taken from the SIDECARS in the output dir
# rather than from data/hull_assemblies. Both pipelines write a `<id>.json`
# sidecar, so this covers the Blender-authored roster as well as the SDF one;
# listing assemblies would have covered only hulls this file bakes itself.
func _list_collision_ids() -> Array:
	var out := []
	var dir := DirAccess.open(OUT_DIR)
	if not dir:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "json":
			out.append(f.get_basename())
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


# Welds the render mesh into a manifold shell and saves its convex decomposition
# alongside it. Never fails the bake: a hull with no `_collision.res` falls back
# at runtime to the single convex fit that shipped before this existed
# (unit_assembly._add_hull_collider), so a roster can migrate one hull at a time
# exactly the way the .glb -> .res conversion did.
func _bake_collision(stem: String, mesh: ArrayMesh, tris: int) -> void:
	var path := "%s/%s_collision.res" % [OUT_DIR, stem]
	var welded := MeshWeld.weld(mesh)
	if welded == null:
		printerr("  %s: weld produced no geometry - no collision decomposition written" % stem)
		return
	var ratio := MeshWeld.weld_ratio(welded)
	if ratio > WELD_RATIO_CEILING:
		printerr("  %s: WELD DID NOTHING (%.0f%% of vertices survived) - decomposition would hang, skipping." % [
			stem, ratio * 100.0])
		drifted += 1
		return

	# ClassDB/`call` rather than the literal type and method. This tool must
	# PARSE on any engine build - a bare MeshConvexDecompositionSettings.new()
	# is an "Identifier not declared" parse error if the class is absent, which
	# would take the whole roster bake down rather than just this step.
	#
	# AND THE DECOMPOSER IS NOT ON Mesh. There is no Mesh.convex_decompose in
	# 4.7.1 - Mesh exposes only create_convex_shape, and the only decomposition
	# entry point in the whole of ClassDB is
	# MeshInstance3D.create_multiple_convex_collisions, which does not return
	# the shapes but attaches a StaticBody3D full of them as a child. So the
	# shapes are harvested off a throwaway instance.
	var settings = ClassDB.instantiate("MeshConvexDecompositionSettings")
	var holder := MeshInstance3D.new()
	holder.mesh = welded
	root.add_child(holder)
	if settings == null or not holder.has_method("create_multiple_convex_collisions"):
		print("  %s: convex decomposition unavailable on this engine build - skipped." % stem)
		root.remove_child(holder)
		holder.free()
		return
	settings.set("max_convex_hulls", MAX_CONVEX_HULLS)
	settings.set("resolution", DECOMP_RESOLUTION)
	settings.set("max_concavity", DECOMP_MAX_CONCAVITY)

	var t0 := Time.get_ticks_msec()
	holder.call("create_multiple_convex_collisions", settings)
	var elapsed := Time.get_ticks_msec() - t0

	var res = HullCollisionShapes.new()
	var points_total := 0
	for holder_body in holder.find_children("*", "StaticBody3D", true, false):
		for child in holder_body.get_children():
			if not (child is CollisionShape3D):
				continue
			var shape = (child as CollisionShape3D).shape
			if not (shape is ConvexPolygonShape3D):
				continue
			# Only the point cloud is stored - the Shape3D itself is rebuilt at
			# load time so nothing shares a live physics shape with whatever the
			# resource cache is holding.
			var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
			if points.size() < 4:
				continue
			res.hulls.append(points)
			points_total += points.size()
	root.remove_child(holder)
	holder.free()
	if res.hulls.is_empty():
		printerr("  %s: every decomposed piece was degenerate - no collision written" % stem)
		return
	res.source_triangles = tris
	res.max_convex_hulls = MAX_CONVEX_HULLS

	var err := ResourceSaver.save(res, path)
	if err != OK:
		printerr("  %s: could not save collision decomposition (error %d)" % [stem, err])
		return
	print("  %s: collision %d hull(s), %d points, weld kept %.0f%%, %d ms" % [
		stem, res.hulls.size(), points_total, ratio * 100.0, elapsed])

# A hull must bake as ONE closed shell. Nothing checked this, and two hulls had
# been shipping broken in a way no other check could see:
#
#   airship_hull baked as TWO disconnected components - a ball with the gondola,
#   nose and tail boxes floating separately in mid-air - because the SPHERE SDF
#   collapsed its 5.8 x 3.6 x 12.6 envelope to a ball of the smallest half-extent
#   (fixed in sdf_mesh_baker.gd's _sdf_ellipsoid). The size-drift check could not
#   catch it: the floating pieces kept the overall AABB roughly plausible.
#
# Components > 1 means detached geometry. Boundary edges (an edge used by exactly
# one triangle) are the rim of a hole. Both are reported; neither fails the build
# unless --strict, same as size drift.
func _check_topology(stem: String, mesh: ArrayMesh, method: String) -> void:
	var faces := mesh.get_faces()
	if faces.is_empty():
		return
	var ids := {}
	var parent: Array[int] = []
	var edge_use := {}
	for i in range(0, faces.size(), 3):
		var tri: Array[int] = []
		for k in range(3):
			var key := "%.4f|%.4f|%.4f" % [faces[i + k].x, faces[i + k].y, faces[i + k].z]
			if not ids.has(key):
				ids[key] = parent.size()
				parent.append(parent.size())
			tri.append(ids[key])
		for k in range(3):
			var a: int = tri[k]
			var b: int = tri[(k + 1) % 3]
			var ek := "%d_%d" % [mini(a, b), maxi(a, b)]
			edge_use[ek] = int(edge_use.get(ek, 0)) + 1
			var ra := _uf_find(parent, a)
			var rb := _uf_find(parent, b)
			if ra != rb:
				parent[rb] = ra

	var boundary := 0
	for ek in edge_use:
		if int(edge_use[ek]) == 1:
			boundary += 1
	var roots := {}
	for v in range(parent.size()):
		roots[_uf_find(parent, v)] = true

	if roots.size() > 1:
		printerr("  %s: %d DISCONNECTED COMPONENTS - parts of this hull float free of the rest." % [
			stem, roots.size()])
		drifted += 1
	if boundary > 0:
		# Under CSG these are T-junctions, not holes, and they are expected: two
		# primitives' faces meet exactly along a line, but one side carries an
		# extra vertex from its own clipping, so the edges do not pair up
		# combinatorially. The surfaces still coincide geometrically - verified by
		# enclosed-volume comparison against an independent SDF lattice sample -
		# so there is no gap to see. Reported at a lower volume for that method.
		if method.to_lower() == "csg":
			print("  %s: %d T-junction edge(s) (expected for CSG - surfaces meet, vertices don't)." % [
				stem, boundary])
		else:
			print("  %s: NOTE %d boundary edge(s) - small holes in the shell." % [stem, boundary])

func _uf_find(parent: Array[int], x: int) -> int:
	var r: int = x
	while parent[r] != r:
		r = parent[r]
	var c: int = x
	while parent[c] != c:
		var nxt: int = parent[c]
		parent[c] = r
		c = nxt
	return r

# The sidecar's `size` drives the collision box, the mount facets and
# ModuleCatalog.get_hull_mesh_fit()'s size tier, while the baked AABB is what
# the player actually sees. Nothing used to compare them, so a hull could bake
# a fifth narrower than its declared size (airship_hull: 4.73 baked vs 6
# declared) and the pipeline still reported success - visuals and hitbox
# quietly disagreeing.
func _check_size_drift(stem: String, aabb: AABB, sidecar: Dictionary) -> void:
	var declared = sidecar.get("size", null)
	if typeof(declared) != TYPE_ARRAY or (declared as Array).size() < 3:
		printerr("  %s: sidecar has no usable `size` - cannot verify baked extents" % stem)
		drifted += 1
		return
	var want := _to_vec3(declared)
	var got := aabb.size
	var axis_names := ["x", "y", "z"]
	var worst := 0.0
	var worst_msg := ""
	for a in range(3):
		if want[a] <= 0.0001:
			continue
		var dev: float = abs(got[a] - want[a]) / want[a]
		if dev > worst:
			worst = dev
			worst_msg = "%s %.2f baked vs %.2f declared (%+.0f%%)" % [
				axis_names[a], got[a], want[a], (got[a] / want[a] - 1.0) * 100.0]
	if worst >= HARD_DRIFT:
		printerr("  %s: SIZE DRIFT %s - collision box and visual mesh disagree." % [stem, worst_msg])
		drifted += 1
	elif worst >= SOFT_DRIFT:
		print("  %s: NOTE size drift %s" % [stem, worst_msg])

# Marching Cubes samples the SDF on a voxel grid, so it physically cannot
# represent a feature thinner than ~1 voxel - such a primitive is silently
# absorbed into its neighbours or vanishes outright, with NO error. This bit
# real geometry during the roster conversion: the flying wing hull's 0.50-thick
# wings on a 10.8-unit span at resolution 18 (voxel 0.60) disappeared
# completely, collapsing the baked hull from 10.80 wide to 4.57.
#
# Rule of thumb used here: a feature needs ~2 voxels across it to survive
# recognisably, so warn below 2x voxel and shout below 1x.
#
# The durable lesson (which matches HULL_MASSING_SPEC.md's own philosophy):
# the SDF pipeline is for MASSING - volumes - not for greeble-scale detail.
# Thin fins, battens and collars belong to the module/greeble layer, not the
# baked base mesh. If a hull needs sub-voxel detail, the answer is usually to
# remove it rather than to crank resolution (cost is ~quadratic in it).
func _warn_on_subvoxel_features(primitives: Array, resolution: int, smoothness: float, stem: String) -> void:
	# Ask the baker for the voxel size rather than re-deriving it. This used to
	# build its own AABB from scale*0.5 with no rotation and no smoothness
	# margin, while the baker uses _UNIT_BOUND=0.6, applies each primitive's
	# rotation, and grows by the margin - so the figure printed here was ~25%
	# smaller than the grid actually used (heavy_hull: 0.31 reported vs ~0.39
	# real). Under-reporting the voxel means the "WILL BE LOST" branch below
	# almost never fires, which is how the flying wing hull's wings disappeared.
	var voxel := SDFMeshBaker.compute_voxel_size(primitives, smoothness, resolution)
	if voxel <= 0.0:
		return
	var bake_size: Vector3 = SDFMeshBaker.compute_bake_bounds(primitives, smoothness).size
	var longest: float = max(bake_size.x, max(bake_size.y, bake_size.z))

	for i in range(primitives.size()):
		var scl: Vector3 = primitives[i]["scale"]
		var thin: float = min(abs(scl.x), min(abs(scl.y), abs(scl.z)))
		if thin < voxel:
			printerr("  %s: primitive %d (%s) is %.2f thick vs voxel %.2f - WILL BE LOST. Thicken it, drop it, or raise resolution to >= %d." % [
				stem, i, PRIMITIVE_TYPE_NAMES[primitives[i]["type"]], thin, voxel,
				int(ceil(2.0 * longest / max(thin, 0.001)))])
		elif thin < voxel * 2.0:
			print("  %s: NOTE primitive %d (%s) is %.2f thick vs voxel %.2f - will render soft/partial." % [
				stem, i, PRIMITIVE_TYPE_NAMES[primitives[i]["type"]], thin, voxel])

func _to_runtime_primitives(entries: Array, stem: String) -> Array:
	var out := []
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var type_name := str(e.get("type", "BOX")).to_upper()
		var type_idx := PRIMITIVE_TYPE_NAMES.find(type_name)
		if type_idx < 0:
			printerr("  %s: unknown primitive type '%s' - skipping it" % [stem, type_name])
			continue
		out.append({
			"type": type_idx,
			"position": _to_vec3(e.get("position", [0, 0, 0])),
			"rotation": _to_vec3(e.get("rotation", [0, 0, 0])),
			"scale": _to_vec3(e.get("scale", [1, 1, 1])),
			"color": Color.WHITE,
		})
	return out

func _write_sidecar(stem: String, sidecar: Dictionary) -> bool:
	var out := sidecar.duplicate(true)
	out["category"] = "hull"  # never trusted from source - hull_loader.gd forces this too
	var path := "%s/%s.json" % [OUT_DIR, stem]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		printerr("  %s: could not write sidecar %s" % [stem, path])
		return false
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	return true

func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		printerr("  could not open %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		printerr("  %s: JSON parse error: %s (line %d)" % [path, json.get_error_message(), json.get_error_line()])
		return null
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		printerr("  %s: assembly must be a JSON object" % path)
		return null
	return data

static func _to_vec3(arr) -> Vector3:
	if typeof(arr) == TYPE_ARRAY and arr.size() >= 3:
		return Vector3(arr[0], arr[1], arr[2])
	return Vector3.ZERO

static func _fmt_v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
