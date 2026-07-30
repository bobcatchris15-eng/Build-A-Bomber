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

const SDFMeshBaker = preload("res://scripts/sdf_mesh_baker.gd")

const ASSEMBLY_DIR := "res://data/hull_assemblies"
const OUT_DIR := "res://assets/models/hulls"

# Baked-AABB vs declared-`size` tolerance. Below SOFT it's noise from the
# skin-fit inset; above HARD the collision box is visibly wrong.
const SOFT_DRIFT := 0.05
const HARD_DRIFT := 0.15

# Hulls whose baked extents disagree with their declared size beyond HARD_DRIFT.
# Reported always; fails the run only under --strict, so an existing red roster
# doesn't block unrelated work.
var drifted := 0
var strict := false

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
	var sources := _list_assemblies()
	if sources.is_empty():
		printerr("No assemblies found in %s" % ASSEMBLY_DIR)
		quit(1)
		return

	var baked := 0
	var failed := 0
	var total_tris := 0

	for path in sources:
		var stem: String = str(path).get_file().get_basename()
		if not only_ids.is_empty() and not only_ids.has(stem):
			continue
		var result := _bake_one(path, stem)
		if result < 0:
			failed += 1
		else:
			baked += 1
			total_tris += result

	print("")
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
	return tris

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
