class_name TerrainVisualScatter
extends Node3D

# MultiMesh Visual Scatter System for Terrain Greebling.
#
# Generates thousands of high-coverage environmental visual details:
#  - Authored Grass Tufts & Wildflower Clusters (MultiMesh instancing)
#  - Authored Woody Shrubs, Bushes & Desert Scrub
#  - Authored Ambient Trees (20 distinct high-fidelity species silhouettes)
#  - Authored Scree, Talus & Pebble Clusters on slopes
#  - Authored Wetland Cattails & Marsh Reeds near water edges
#  - Authored Rock Spires & Cliff Facades along escarpments and ravine walls
#
# PERFORMANCE CONTRACT:
#  - 100% pure visual: zero StaticBody3D, zero CollisionShape3D, zero navigation footprint.
#  - Zero shadow caster overhead: cast_shadow = SHADOW_CASTING_SETTING_OFF.
#  - Single draw-call batching per mesh part via MultiMeshInstance3D.
#  - Deterministic generation seeded by map name and seed parameters.

const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

const GRASS_TUFT_MODEL_DIR := "res://assets/models/terrain/grass_tuft_%d.glb"
const GRASS_TUFT_POOL_SIZE := 6
const WILDFLOWER_MODEL_DIR := "res://assets/models/terrain/wildflower_tuft_%d.glb"
const WILDFLOWER_POOL_SIZE := 3
const SHRUB_MODEL_DIR := "res://assets/models/terrain/shrub_%d.glb"
const SHRUB_POOL_SIZE := 4
const REEDS_MODEL_DIR := "res://assets/models/terrain/reeds_%d.glb"
const REEDS_POOL_SIZE := 3
const AMBIENT_TREE_MODEL_DIR := "res://assets/models/terrain/ambient_tree_%d.glb"
const AMBIENT_TREE_POOL_SIZE := 20
const BOULDER_MODEL_DIR := "res://assets/models/terrain/boulder_%d.glb"
const BOULDER_POOL_SIZE := 6
const ROCK_SPIRE_MODEL_DIR := "res://assets/models/terrain/rock_spire_%d.glb"
const ROCK_SPIRE_POOL_SIZE := 4
const PEBBLE_MODEL_DIR := "res://assets/models/terrain/pebble_cluster_%d.glb"
const PEBBLE_POOL_SIZE := 4
const CLIFF_FACE_MODEL_DIR := "res://assets/models/terrain/cliff_face_%d.glb"
const CLIFF_FACE_POOL_SIZE := 4
const CLIFF_CORNER_MODEL_DIR := "res://assets/models/terrain/cliff_corner_%d.glb"
const CLIFF_CORNER_POOL_SIZE := 3

const BASE_ZONE_CLEAR_RADIUS := 24.0

var _material_cache: Dictionary = {}
var _template_cache: Dictionary = {}


static func get_or_create(parent: Node3D) -> Node3D:
	var existing = parent.get_node_or_null("TerrainVisualScatter")
	if existing != null:
		return existing
	var scatter_script = load("res://scripts/terrain_visual_scatter.gd")
	var s: Node3D = scatter_script.new()
	s.name = "TerrainVisualScatter"
	parent.add_child(s)
	return s


func _get_material(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var key = "%s_%.2f_%.2f" % [color.to_html(false), roughness, metallic]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material_cache[key] = mat
	return mat


# ------------------------------------------------------------------------------
# Procedural Fallback Mesh Generators
# ------------------------------------------------------------------------------

func _build_grass_mesh(prop_scale: float = 1.0) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var blade_w = 0.06 * prop_scale
	var blade_h = 0.65 * prop_scale
	var num_blades = 5
	
	for i in range(num_blades):
		var angle = (TAU / float(num_blades)) * i + 0.2 * sin(float(i))
		var r_offset = 0.08 * prop_scale
		var bx = cos(angle) * r_offset
		var bz = sin(angle) * r_offset
		var lean = 0.25 * prop_scale
		var tip_x = bx + cos(angle) * lean
		var tip_z = bz + sin(angle) * lean
		
		var perp_x = -sin(angle) * blade_w * 0.5
		var perp_z = cos(angle) * blade_w * 0.5
		
		var v0 = Vector3(bx - perp_x, 0.0, bz - perp_z)
		var v1 = Vector3(bx + perp_x, 0.0, bz + perp_z)
		var v2 = Vector3(tip_x, blade_h, tip_z)
		
		var normal = Vector3(0, 1, 0)
		st.set_normal(normal)
		st.set_uv(Vector2(0, 0))
		st.add_vertex(v0)
		st.set_uv(Vector2(1, 0))
		st.add_vertex(v1)
		st.set_uv(Vector2(0.5, 1))
		st.add_vertex(v2)
		
		st.add_vertex(v0)
		st.add_vertex(v2)
		st.add_vertex(v1)
		
	st.generate_normals()
	return st.commit()


func _build_shrub_mesh(prop_scale: float = 1.0) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var r = 0.75 * prop_scale
	var h = 0.65 * prop_scale
	var segments = 6
	
	for i in range(segments):
		var a1 = (TAU / float(segments)) * i
		var a2 = (TAU / float(segments)) * (i + 1)
		var p1 = Vector3(cos(a1) * r, h * 0.4, sin(a1) * r)
		var p2 = Vector3(cos(a2) * r, h * 0.4, sin(a2) * r)
		var apex = Vector3(0, h, 0)
		var bot1 = Vector3(cos(a1) * r * 0.4, 0.0, sin(a1) * r * 0.4)
		var bot2 = Vector3(cos(a2) * r * 0.4, 0.0, sin(a2) * r * 0.4)
		
		st.add_vertex(bot1); st.add_vertex(p2); st.add_vertex(p1)
		st.add_vertex(bot1); st.add_vertex(bot2); st.add_vertex(p2)
		st.add_vertex(p1); st.add_vertex(p2); st.add_vertex(apex)
		
	st.generate_normals()
	return st.commit()


func _build_pebble_mesh(prop_scale: float = 1.0) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r = 0.3 * prop_scale
	var h = 0.2 * prop_scale
	var segs = 5
	for i in range(segs):
		var a1 = (TAU / float(segs)) * i
		var a2 = (TAU / float(segs)) * (i + 1)
		var p1 = Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		var p2 = Vector3(cos(a2) * r, 0.0, sin(a2) * r)
		var apex = Vector3(0, h, 0)
		st.add_vertex(p1); st.add_vertex(p2); st.add_vertex(apex)
	st.generate_normals()
	return st.commit()


func _build_reed_mesh(prop_scale: float = 1.0) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h = 1.4 * prop_scale
	var w = 0.04 * prop_scale
	for i in range(3):
		var a = i * 2.1
		var ox = cos(a) * 0.1 * prop_scale
		var oz = sin(a) * 0.1 * prop_scale
		var v0 = Vector3(ox - w, 0.0, oz)
		var v1 = Vector3(ox + w, 0.0, oz)
		var v2 = Vector3(ox + cos(a) * 0.15, h, oz + sin(a) * 0.15)
		st.add_vertex(v0); st.add_vertex(v1); st.add_vertex(v2)
		st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v1)
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------------------
# GLTF Template Extraction (MultiMesh Part Loader)
# ------------------------------------------------------------------------------

func _load_gltf_parts(scene_path: String) -> Array:
	if _template_cache.has(scene_path):
		return _template_cache[scene_path]
	if not ResourceLoader.exists(scene_path):
		return []
	var packed = load(scene_path) as PackedScene
	if packed == null:
		return []
	var inst = packed.instantiate()
	if inst == null:
		return []
	var parts: Array = []
	var stack: Array = [[inst, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var cur_xform: Transform3D = item[1]
		if n is Node3D and n != inst:
			cur_xform = cur_xform * (n as Node3D).transform
		if n is MeshInstance3D and n.mesh != null:
			parts.append({"mesh": (n as MeshInstance3D).mesh, "xform": cur_xform})
		for c in n.get_children():
			stack.append([c, cur_xform])
	inst.queue_free()
	_template_cache[scene_path] = parts
	return parts


# ------------------------------------------------------------------------------
# Core MultiMesh Creation Helper
# ------------------------------------------------------------------------------

func _add_multimesh_batch(mesh: Mesh, material: Material, transforms: Array[Transform3D], batch_name: String) -> MultiMeshInstance3D:
	if transforms.is_empty() or mesh == null:
		return null
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	
	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if material != null:
		mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = batch_name
	add_child(mmi)
	return mmi


func _add_gltf_variant_batches(model_template_path: String, pool_size: int, variant_xforms: Dictionary, fallback_mesh: Mesh, fallback_mat: Material, batch_prefix: String) -> void:
	for var_idx in variant_xforms.keys():
		var xf_list: Array = variant_xforms[var_idx]
		if xf_list.is_empty():
			continue
		var glb_path = model_template_path % var_idx
		var parts = _load_gltf_parts(glb_path)
		if parts.is_empty():
			if fallback_mesh != null:
				var casted_xforms: Array[Transform3D] = []
				for xf in xf_list:
					casted_xforms.append(xf)
				_add_multimesh_batch(fallback_mesh, fallback_mat, casted_xforms, "%s_Fallback_%d" % [batch_prefix, var_idx])
			continue
		for p_idx in range(parts.size()):
			var part = parts[p_idx]
			var mesh: Mesh = part["mesh"]
			var local_xform: Transform3D = part["xform"]
			var composed_xforms: Array[Transform3D] = []
			for xf in xf_list:
				composed_xforms.append((xf as Transform3D) * local_xform)
			_add_multimesh_batch(mesh, null, composed_xforms, "%s_%d_%d" % [batch_prefix, var_idx, p_idx])


# ------------------------------------------------------------------------------
# Main Scatter Pipeline
# ------------------------------------------------------------------------------

func scatter_all(map_def: Dictionary, prop_scale: float = 1.0) -> void:
	if bool(map_def.get("disable_ambient_scatter", false)):
		return
	
	var half: float = map_def.get("map_half_extents", 100.0)
	var map_name: String = map_def.get("name", "battlefield")
	var area: float = (half * 2.0) * (half * 2.0)
	
	# Precalculate clear points
	var clear_points: Array[Vector3] = []
	for bz in map_def.get("base_zones", []):
		clear_points.append(bz.get("center", Vector3.ZERO))
	for sp in map_def.get("spawns", []):
		for k in sp.keys():
			if k != "id" and sp[k] is Vector3:
				clear_points.append(sp[k])
	for rn in map_def.get("resource_nodes", []):
		clear_points.append(rn.get("position", Vector3.ZERO))
		
	# Water & Bridges
	var water_areas: Array = map_def.get("water_areas", [])
	var bridges: Array = map_def.get("bridges", [])
	var surface_zones: Array = map_def.get("surface_zones", [])
	
	var ground_color_arr = map_def.get("ground_color", [0.24, 0.28, 0.18])
	var base_green = Color(ground_color_arr[0], ground_color_arr[1], ground_color_arr[2])
	
	# --------------------------------------------------------------------------
	# 1. DENSE AUTHORED GRASS TUFTS & WILDFLOWERS (1,200 - 14,000 instances)
	# --------------------------------------------------------------------------
	var grass_count = clampi(int(area / 16.0), 1200, 14000)
	var grass_rng = RandomNumberGenerator.new()
	grass_rng.seed = hash(map_name + "_grass_dense")
	
	var grass_xforms_by_variant: Dictionary = {}
	for v in range(GRASS_TUFT_POOL_SIZE):
		grass_xforms_by_variant[v] = []
		
	var flower_xforms_by_variant: Dictionary = {}
	for v in range(WILDFLOWER_POOL_SIZE):
		flower_xforms_by_variant[v] = []
	
	for i in range(grass_count):
		var gx = grass_rng.randf_range(-half * 0.96, half * 0.96)
		var gz = grass_rng.randf_range(-half * 0.96, half * 0.96)
		var pos = Vector3(gx, 0.0, gz)
		
		var too_close = false
		for cp in clear_points:
			if Vector2(pos.x - cp.x, pos.z - cp.z).length() < 6.5:
				too_close = true
				break
		if too_close or _is_in_water(pos, water_areas, bridges):
			continue
			
		pos.y = TerrainBuilderScript.terrain_height_at(map_def, pos)
		var slope = TerrainBuilderScript.slope_at(map_def, pos.x, pos.z)
		if slope > 0.65:
			continue
			
		var yaw = grass_rng.randf_range(0, TAU)
		var scale_jitter = grass_rng.randf_range(0.8, 1.4) * prop_scale
		var t = Transform3D().rotated(Vector3.UP, yaw).scaled(Vector3.ONE * scale_jitter)
		t.origin = pos
		
		# 10% chance of wildflower cluster in meadow areas
		if grass_rng.randf() < 0.10:
			var flower_var = grass_rng.randi() % WILDFLOWER_POOL_SIZE
			flower_xforms_by_variant[flower_var].append(t)
		else:
			var grass_var = grass_rng.randi() % GRASS_TUFT_POOL_SIZE
			grass_xforms_by_variant[grass_var].append(t)
		
	var fallback_grass_mesh = _build_grass_mesh(prop_scale)
	var fallback_grass_mat = _get_material(base_green.lightened(0.12), 0.8)
	_add_gltf_variant_batches(GRASS_TUFT_MODEL_DIR, GRASS_TUFT_POOL_SIZE, grass_xforms_by_variant,
		fallback_grass_mesh, fallback_grass_mat, "Batch_GrassTuft")
	_add_gltf_variant_batches(WILDFLOWER_MODEL_DIR, WILDFLOWER_POOL_SIZE, flower_xforms_by_variant,
		fallback_grass_mesh, fallback_grass_mat, "Batch_Wildflower")
	
	# --------------------------------------------------------------------------
	# 2. AUTHORED SHRUBS & BUSHES (300 - 2,500 instances)
	# --------------------------------------------------------------------------
	var shrub_count = clampi(int(area / 110.0), 300, 2500)
	var shrub_rng = RandomNumberGenerator.new()
	shrub_rng.seed = hash(map_name + "_shrubs_v2")
	
	var shrub_xforms_by_variant: Dictionary = {}
	for v in range(SHRUB_POOL_SIZE):
		shrub_xforms_by_variant[v] = []
	
	for i in range(shrub_count):
		var sx = shrub_rng.randf_range(-half * 0.95, half * 0.95)
		var sz = shrub_rng.randf_range(-half * 0.95, half * 0.95)
		var pos = Vector3(sx, 0.0, sz)
		
		var too_close = false
		for cp in clear_points:
			if Vector2(pos.x - cp.x, pos.z - cp.z).length() < 8.5:
				too_close = true
				break
		if too_close or _is_in_water(pos, water_areas, bridges):
			continue
			
		pos.y = TerrainBuilderScript.terrain_height_at(map_def, pos)
		var slope = TerrainBuilderScript.slope_at(map_def, pos.x, pos.z)
		if slope > 0.60:
			continue
			
		var yaw = shrub_rng.randf_range(0, TAU)
		var scale_jitter = shrub_rng.randf_range(0.85, 1.5) * prop_scale
		var t = Transform3D().rotated(Vector3.UP, yaw).scaled(Vector3.ONE * scale_jitter)
		t.origin = pos
		
		var shrub_var = shrub_rng.randi() % SHRUB_POOL_SIZE
		shrub_xforms_by_variant[shrub_var].append(t)
		
	var fallback_shrub_mesh = _build_shrub_mesh(prop_scale)
	var fallback_shrub_mat = _get_material(base_green.darkened(0.08), 0.85)
	_add_gltf_variant_batches(SHRUB_MODEL_DIR, SHRUB_POOL_SIZE, shrub_xforms_by_variant,
		fallback_shrub_mesh, fallback_shrub_mat, "Batch_Shrub")
	
	# --------------------------------------------------------------------------
	# 3. AUTHORED VISUAL TREES (150 - 1,200 instances)
	# --------------------------------------------------------------------------
	var tree_count = clampi(int(area / 240.0), 150, 1200)
	var tree_rng = RandomNumberGenerator.new()
	tree_rng.seed = hash(map_name + "_visual_trees")
	
	var tree_xforms_by_variant: Dictionary = {}
	for sp_idx in range(AMBIENT_TREE_POOL_SIZE):
		tree_xforms_by_variant[sp_idx] = []
		
	for i in range(tree_count):
		var tx = tree_rng.randf_range(-half * 0.92, half * 0.92)
		var tz = tree_rng.randf_range(-half * 0.92, half * 0.92)
		var pos = Vector3(tx, 0.0, tz)
		
		var too_close = false
		for cp in clear_points:
			if Vector2(pos.x - cp.x, pos.z - cp.z).length() < BASE_ZONE_CLEAR_RADIUS * 0.8:
				too_close = true
				break
		if too_close or _is_in_water(pos, water_areas, bridges):
			continue
			
		pos.y = TerrainBuilderScript.terrain_height_at(map_def, pos)
		var slope = TerrainBuilderScript.slope_at(map_def, pos.x, pos.z)
		if slope > 0.55:
			continue
			
		var sp_choice = tree_rng.randi() % AMBIENT_TREE_POOL_SIZE
		var yaw = tree_rng.randf_range(0, TAU)
		var scale_jitter = tree_rng.randf_range(0.85, 1.3) * prop_scale
		var t = Transform3D().rotated(Vector3.UP, yaw).scaled(Vector3.ONE * scale_jitter)
		t.origin = pos
		tree_xforms_by_variant[sp_choice].append(t)
		
	_add_gltf_variant_batches(AMBIENT_TREE_MODEL_DIR, AMBIENT_TREE_POOL_SIZE, tree_xforms_by_variant,
		null, null, "Batch_VisualTree")
	
	# --------------------------------------------------------------------------
	# 4. AUTHORED SLOPE SCREE, TALUS & PEBBLES (200 - 2,000 instances)
	# --------------------------------------------------------------------------
	var scree_count = clampi(int(area / 140.0), 200, 2000)
	var scree_rng = RandomNumberGenerator.new()
	scree_rng.seed = hash(map_name + "_scree_talus")
	
	var pebble_xforms_by_variant: Dictionary = {}
	for v in range(PEBBLE_POOL_SIZE):
		pebble_xforms_by_variant[v] = []
	
	for i in range(scree_count):
		var rx = scree_rng.randf_range(-half * 0.98, half * 0.98)
		var rz = scree_rng.randf_range(-half * 0.98, half * 0.98)
		var pos = Vector3(rx, 0.0, rz)
		
		if _is_in_water(pos, water_areas, bridges):
			continue
			
		var slope = TerrainBuilderScript.slope_at(map_def, pos.x, pos.z)
		if slope < 0.12:
			continue
			
		pos.y = TerrainBuilderScript.terrain_height_at(map_def, pos)
		var yaw = scree_rng.randf_range(0, TAU)
		var scale_jitter = scree_rng.randf_range(0.7, 1.8) * prop_scale
		var t = Transform3D().rotated(Vector3.UP, yaw).scaled(Vector3.ONE * scale_jitter)
		t.origin = pos
		
		var p_var = scree_rng.randi() % PEBBLE_POOL_SIZE
		pebble_xforms_by_variant[p_var].append(t)
		
	var fallback_pebble_mesh = _build_pebble_mesh(prop_scale)
	var fallback_pebble_mat = _get_material(Color(0.38, 0.36, 0.33), 0.95)
	_add_gltf_variant_batches(PEBBLE_MODEL_DIR, PEBBLE_POOL_SIZE, pebble_xforms_by_variant,
		fallback_pebble_mesh, fallback_pebble_mat, "Batch_PebbleCluster")
	
	# --------------------------------------------------------------------------
	# 5. AUTHORED ROCK SPIRES & MONOLITHS (20 - 180 instances)
	# --------------------------------------------------------------------------
	var spire_count = clampi(int(area / 1800.0), 20, 180)
	var spire_rng = RandomNumberGenerator.new()
	spire_rng.seed = hash(map_name + "_rock_spires")
	
	var spire_xforms_by_variant: Dictionary = {}
	for v in range(ROCK_SPIRE_POOL_SIZE):
		spire_xforms_by_variant[v] = []
		
	for i in range(spire_count):
		var rx = spire_rng.randf_range(-half * 0.94, half * 0.94)
		var rz = spire_rng.randf_range(-half * 0.94, half * 0.94)
		var pos = Vector3(rx, 0.0, rz)
		
		var too_close = false
		for cp in clear_points:
			if Vector2(pos.x - cp.x, pos.z - cp.z).length() < 12.0:
				too_close = true
				break
		if too_close or _is_in_water(pos, water_areas, bridges):
			continue
			
		pos.y = TerrainBuilderScript.terrain_height_at(map_def, pos)
		var slope = TerrainBuilderScript.slope_at(map_def, pos.x, pos.z)
		# Spires placed on hills / moderate slopes (0.20 - 0.55)
		if slope < 0.20 or slope > 0.55:
			continue
			
		var yaw = spire_rng.randf_range(0, TAU)
		var scale_jitter = spire_rng.randf_range(0.8, 1.4) * prop_scale
		var t = Transform3D().rotated(Vector3.UP, yaw).scaled(Vector3.ONE * scale_jitter)
		t.origin = pos
		
		var sp_var = spire_rng.randi() % ROCK_SPIRE_POOL_SIZE
		spire_xforms_by_variant[sp_var].append(t)
		
	_add_gltf_variant_batches(ROCK_SPIRE_MODEL_DIR, ROCK_SPIRE_POOL_SIZE, spire_xforms_by_variant,
		fallback_pebble_mesh, fallback_pebble_mat, "Batch_RockSpire")
	
	# --------------------------------------------------------------------------
	# 6. AUTHORED CLIFF FACADES ON STEEP ESCARPMENTS (30 - 250 instances)
	# --------------------------------------------------------------------------
	var cliff_count = clampi(int(area / 1200.0), 30, 250)
	var cliff_rng = RandomNumberGenerator.new()
	cliff_rng.seed = hash(map_name + "_cliff_facades")
	
	var cliff_xforms_by_variant: Dictionary = {}
	for v in range(CLIFF_FACE_POOL_SIZE):
		cliff_xforms_by_variant[v] = []
		
	for i in range(cliff_count):
		var cx = cliff_rng.randf_range(-half * 0.94, half * 0.94)
		var cz = cliff_rng.randf_range(-half * 0.94, half * 0.94)
		var pos = Vector3(cx, 0.0, cz)
		
		if _is_in_water(pos, water_areas, bridges):
			continue
			
		var slope = TerrainBuilderScript.slope_at(map_def, pos.x, pos.z)
		# Cliff facades dress steep ground (slope > 0.55)
		if slope < 0.55:
			continue
			
		pos.y = TerrainBuilderScript.terrain_height_at(map_def, pos)
		
		# Compute slope facing angle
		var eps = 1.0
		var h_px = TerrainBuilderScript.terrain_height_at(map_def, Vector3(pos.x + eps, 0, pos.z))
		var h_mx = TerrainBuilderScript.terrain_height_at(map_def, Vector3(pos.x - eps, 0, pos.z))
		var h_pz = TerrainBuilderScript.terrain_height_at(map_def, Vector3(pos.x, 0, pos.z + eps))
		var h_mz = TerrainBuilderScript.terrain_height_at(map_def, Vector3(pos.x, 0, pos.z - eps))
		var grad_x = (h_px - h_mx) / (2.0 * eps)
		var grad_z = (h_pz - h_mz) / (2.0 * eps)
		var cliff_yaw = atan2(-grad_x, -grad_z)
		
		var scale_jitter = cliff_rng.randf_range(0.85, 1.25) * prop_scale
		var t = Transform3D().rotated(Vector3.UP, cliff_yaw).scaled(Vector3.ONE * scale_jitter)
		t.origin = pos
		
		var c_var = cliff_rng.randi() % CLIFF_FACE_POOL_SIZE
		cliff_xforms_by_variant[c_var].append(t)
		
	_add_gltf_variant_batches(CLIFF_FACE_MODEL_DIR, CLIFF_FACE_POOL_SIZE, cliff_xforms_by_variant,
		null, null, "Batch_CliffFace")
	
	# --------------------------------------------------------------------------
	# 7. AUTHORED WETLAND REEDS (Near water edges & marsh zones)
	# --------------------------------------------------------------------------
	if not water_areas.is_empty() or _has_marsh_zones(surface_zones):
		var reed_xforms_by_variant: Dictionary = {}
		for v in range(REEDS_POOL_SIZE):
			reed_xforms_by_variant[v] = []
			
		var reed_rng = RandomNumberGenerator.new()
		reed_rng.seed = hash(map_name + "_wetland_reeds")
		
		for water in water_areas:
			var c = water.get("center", Vector3.ZERO)
			var he = water.get("half_extents", Vector2(10, 10))
			var perimeter_points = int(he.x + he.y) * 4
			for p in range(perimeter_points):
				var side = reed_rng.randi() % 4
				var ox = 0.0
				var oz = 0.0
				match side:
					0:
						ox = reed_rng.randf_range(-he.x, he.x)
						oz = he.y + reed_rng.randf_range(-1.0, 2.5)
					1:
						ox = reed_rng.randf_range(-he.x, he.x)
						oz = -he.y - reed_rng.randf_range(-1.0, 2.5)
					2:
						ox = he.x + reed_rng.randf_range(-1.0, 2.5)
						oz = reed_rng.randf_range(-he.y, he.y)
					3:
						ox = -he.x - reed_rng.randf_range(-1.0, 2.5)
						oz = reed_rng.randf_range(-he.y, he.y)
				var pos = Vector3(c.x + ox, 0.0, c.z + oz)
				pos.y = TerrainBuilderScript.terrain_height_at(map_def, pos)
				var yaw = reed_rng.randf_range(0, TAU)
				var t = Transform3D().rotated(Vector3.UP, yaw).scaled(Vector3.ONE * reed_rng.randf_range(0.8, 1.4) * prop_scale)
				t.origin = pos
				var r_var = reed_rng.randi() % REEDS_POOL_SIZE
				reed_xforms_by_variant[r_var].append(t)
				
		var fallback_reed_mesh = _build_reed_mesh(prop_scale)
		var fallback_reed_mat = _get_material(Color(0.28, 0.36, 0.18), 0.75)
		_add_gltf_variant_batches(REEDS_MODEL_DIR, REEDS_POOL_SIZE, reed_xforms_by_variant,
			fallback_reed_mesh, fallback_reed_mat, "Batch_WetlandReeds")

static func _is_in_water(pos: Vector3, water_areas: Array, bridges: Array) -> bool:
	for b in bridges:
		var c = b.get("center", Vector3.ZERO)
		var he = b.get("half_extents", Vector2(4, 10))
		if absf(pos.x - c.x) <= he.x and absf(pos.z - c.z) <= he.y:
			return false
	for w in water_areas:
		var c = w.get("center", Vector3.ZERO)
		var he = w.get("half_extents", Vector2(10, 10))
		if absf(pos.x - c.x) <= he.x and absf(pos.z - c.z) <= he.y:
			return true
	return false

static func _has_marsh_zones(surface_zones: Array) -> bool:
	for z in surface_zones:
		if z.get("surface_type", "") == "marsh":
			return true
	return false
