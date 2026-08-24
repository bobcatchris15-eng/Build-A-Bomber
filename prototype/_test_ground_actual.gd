extends SceneTree
# VISUAL polish 2026-08-23: actually launch the test range map's terrain
# via the same code path match_director uses, and dump EVERY material on
# the ground meshes. This is the test that tells us what's actually being
# rendered vs what the code path says should be there.
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

func _init() -> void:
	# Load the test range map.
	var map_def_text: String = FileAccess.get_file_as_string("res://data/maps/test_range.json")
	var map_def: Dictionary = JSON.parse_string(map_def_text)
	print("map_half_extents=", map_def.get("map_half_extents"))
	print("hills=", map_def.get("hills", []))
	print("flat_ground_collider=", map_def.get("flat_ground_collider"))

	# Build the heightmap visual mesh (this is what gets rendered as the
	# main ground under the unit). This is the function match_director
	# calls to build the actual rendered ground.
	print("\nBuilding heightmap visual mesh (await coroutine)...")
	var vis_result: Dictionary = await TerrainBuilderScript.build_ground_visual_mesh(map_def)
	var mesh: ArrayMesh = vis_result.get("mesh", null)
	if mesh == null:
		print("FAIL: no mesh returned from build_ground_visual_mesh")
		quit(1)
		return
	print("  mesh surface count=", mesh.get_surface_count())
	for i in range(mesh.get_surface_count()):
		var mat_arr = mesh.surface_get_material(i)
		print("  surface ", i, " material: ", mat_arr.get_class() if mat_arr else "(null)")
		if mat_arr is ShaderMaterial:
			print("    shader: ", mat_arr.shader.resource_path)
			for slot in ["albedo_0", "albedo_1", "albedo_2", "albedo_3", "rock_albedo"]:
				var tex: Texture = mat_arr.get_shader_parameter(slot)
				if tex:
					print("    ", slot, " -> ", tex.resource_path)

	# Build the heightmap material directly (no mesh, just the material).
	print("\nBuilding heightmap material directly...")
	var mat = TerrainBuilderScript.build_ground_material_heightmap(Color(0.36, 0.34, 0.30), map_def)
	if mat is ShaderMaterial:
		print("  shader: ", mat.shader.resource_path)
		for slot in ["albedo_0", "albedo_1", "albedo_2", "albedo_3", "rock_albedo"]:
			var tex: Texture = mat.get_shader_parameter(slot)
			if tex:
				print("  ", slot, " -> ", tex.resource_path)
			else:
				print("  ", slot, " -> (empty)")

	# Check: does the test range have a heightmap image?
	var heightmap_img = TerrainBuilderScript._get_heightmap_image(map_def)
	print("\ntest_range heightmap image: ", "present" if heightmap_img else "absent")

	# Now do the same for the simple ground material (non-heightmap path).
	print("\nBuilding simple ground material (non-heightmap fallback)...")
	var simple_mat = TerrainBuilderScript.build_ground_material(Color(0.36, 0.34, 0.30), Vector2(80, 80))
	if simple_mat is StandardMaterial3D:
		print("  type: StandardMaterial3D")
		print("  albedo_texture: ", simple_mat.albedo_texture.resource_path if simple_mat.albedo_texture else "(null)")
		print("  normal_texture: ", simple_mat.normal_texture.resource_path if simple_mat.normal_texture else "(null)")
		print("  rough_texture:  ", simple_mat.roughness_texture.resource_path if simple_mat.roughness_texture else "(null)")
		print("  albedo_color:   ", simple_mat.albedo_color)
	else:
		print("  type: ", simple_mat.get_class())

	quit(0)
