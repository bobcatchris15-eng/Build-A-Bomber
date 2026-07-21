# MeshAssetLoader (use via preload, e.g. const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd"))
# Loads authored .glb assets (built by tools/blender/build_meshes.py, or
# hand-authored by a hull modder) and hands back a plain Mesh resource, so
# calling code can keep treating it exactly like a procedurally-built
# CylinderMesh/BoxMesh (assign to MeshInstance3D.mesh, then position/rotate/
# scale/material_override as before). Falls back to null if no authored
# asset exists yet, so visual_builder.gd / module_placer.gd can gracefully
# keep using the procedural path for anything not yet upgraded.
#
# Hull meshes (get_hull_mesh only - parts are always built-in, res:// only)
# can come from two places: built-in hulls under res://assets/models/hulls,
# which Godot's editor already imported at build time (a normal load() off
# the .import cache), or player-added mod hulls under user://mods/hulls
# (HULL_MODDING_PLAN.md's real post-ship-moddability requirement - res://
# gets packed into the exported .pck and isn't writable/accessible to a
# player after ship, same reasoning as this project's existing
# user://blueprints/). A raw .glb dropped into user:// at runtime was never
# part of the export and has no .import cache entry, so load() can't read
# it - it has to go through GLTFDocument's runtime import API instead. Mod
# mesh wins if both exist for the same id, matching hull_loader.gd's own
# mod-overrides-built-in metadata precedence.

static var _cache: Dictionary = {}

static func get_part_mesh(part_name: String) -> Mesh:
	return _load_and_cache("res://assets/models/parts/%s.glb" % part_name)

static func get_hull_mesh(hull_type_id: String) -> Mesh:
	# A hull whose shape is genuinely a plain primitive declares
	# "primitive_shape" in its sidecar instead of shipping a .glb, and wins
	# over any .glb that happens to sit next to it. the_cube/the_orb/the_rod/
	# the_slab were supposed to be exactly that - simple geometric solids -
	# but shipped as byte-identical COPIES of medium_hull.glb, so all four
	# rendered as a medium hull stretched to their catalog dimensions.
	var primitive = _primitive_shape_for(hull_type_id)
	if primitive != "":
		return _build_primitive(primitive)
	var mod_path = "user://mods/hulls/%s.glb" % hull_type_id
	if FileAccess.file_exists(mod_path):
		return _load_and_cache_runtime_gltf(mod_path)
	return _load_and_cache("res://assets/models/hulls/%s.glb" % hull_type_id)

static func _primitive_shape_for(hull_type_id: String) -> String:
	# Runtime load rather than preload: module_catalog.gd sits upstream of
	# this file in the preload graph, so a preload here would close a cycle.
	var ModuleCatalogScript = load("res://scripts/module_catalog.gd")
	if ModuleCatalogScript == null:
		return ""
	return ModuleCatalogScript.get_module_data(hull_type_id).get("primitive_shape", "")

# Primitives are built at UNIT size (a 1x1x1 bounding box) and left there.
# ModuleCatalog.get_hull_mesh_fit() then stretches them per-axis onto the
# hull's catalog size exactly as it does for an authored mesh, so a 1x1x8 rod
# and a 3x3x3 cube both fall out of the same unit source with no special
# casing - and the orientation search is a no-op on a cube-shaped AABB, so
# they are never spuriously rotated.
static func _build_primitive(shape: String) -> Mesh:
	var cache_key = "primitive://%s" % shape
	if _cache.has(cache_key):
		return _cache[cache_key]

	var source: Mesh = null
	var bake := Transform3D.IDENTITY
	match shape:
		"sphere":
			var sphere = SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 32
			sphere.rings = 16
			source = sphere
		"cylinder":
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 1.0
			cyl.radial_segments = 24
			source = cyl
			# CylinderMesh runs along Y. Bake a quarter turn about X so the
			# long axis is Z, matching the -Z-forward convention every hull
			# uses - otherwise a "rod" 8 units long in Z would come out as a
			# 1-unit-tall disc stretched sideways.
			bake = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
		_:
			var box = BoxMesh.new()
			box.size = Vector3.ONE
			source = box

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(source, 0, bake)
	st.generate_normals()
	st.generate_tangents()
	var mesh = st.commit()
	_cache[cache_key] = mesh
	return mesh

static func _load_and_cache(path: String) -> Mesh:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return null
	var packed_scene = load(path) as PackedScene
	if not packed_scene:
		_cache[path] = null
		return null
	var instance = packed_scene.instantiate()
	var mesh_inst = _find_first_mesh_instance(instance)
	var mesh: Mesh = mesh_inst.mesh if mesh_inst else null
	instance.free()
	_cache[path] = mesh
	return mesh

# Runtime glTF import (no .import cache available for a user:// file, since
# it was never part of the editor's asset pipeline) - GLTFDocument is
# Godot's own supported API for exactly this ("load a glTF file at runtime
# without pre-importing it"), same binary format, just a different loading
# path than the editor-import one _load_and_cache() uses for res:// assets.
static func _load_and_cache_runtime_gltf(path: String) -> Mesh:
	if _cache.has(path):
		return _cache[path]
	var gltf_document = GLTFDocument.new()
	var gltf_state = GLTFState.new()
	var err = gltf_document.append_from_file(path, gltf_state)
	if err != OK:
		push_warning("MeshAssetLoader: failed to import mod hull mesh '%s' (glTF error %d) - falling back to the box-primitive/color fallback" % [path, err])
		_cache[path] = null
		return null
	var scene_root = gltf_document.generate_scene(gltf_state)
	if not scene_root:
		push_warning("MeshAssetLoader: '%s' parsed but produced no scene" % path)
		_cache[path] = null
		return null
	var mesh_inst = _find_first_mesh_instance(scene_root)
	var mesh: Mesh = mesh_inst.mesh if mesh_inst else null
	scene_root.free()
	_cache[path] = mesh
	return mesh

static func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found = _find_first_mesh_instance(child)
		if found:
			return found
	return null
