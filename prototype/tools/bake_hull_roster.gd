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
	print("Baked %d hull(s), %d failed. Total %d triangles." % [baked, failed, total_tris])
	quit(1 if failed > 0 else 0)

func _parse_id_filter() -> Dictionary:
	var ids := {}
	var args := OS.get_cmdline_user_args()
	for a in args:
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

	_warn_on_subvoxel_features(primitives, resolution, stem)

	var t0 := Time.get_ticks_msec()
	var mesh: ArrayMesh = SDFMeshBaker.bake(primitives, smoothness, resolution, method, fit_percent, facet_angle, crystallinity)
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
	return tris

# Marching Cubes samples the SDF on a voxel grid, so it physically cannot
# represent a feature thinner than ~1 voxel - such a primitive is silently
# absorbed into its neighbours or vanishes outright, with NO error. This bit
# real geometry during the roster conversion: flying_wing_hull's 0.50-thick
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
func _warn_on_subvoxel_features(primitives: Array, resolution: int, stem: String) -> void:
	var bounds := AABB()
	var first := true
	for p in primitives:
		var half: Vector3 = (p["scale"] as Vector3).abs() * 0.5
		var a := AABB(p["position"] - half, half * 2.0)
		if first:
			bounds = a
			first = false
		else:
			bounds = bounds.merge(a)
	var longest: float = max(bounds.size.x, max(bounds.size.y, bounds.size.z))
	if longest <= 0.0:
		return
	var voxel := longest / float(max(resolution, 1))

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
