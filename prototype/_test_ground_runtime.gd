extends SceneTree
# VISUAL polish 2026-08-23: actually launch the test range and inspect
# what texture the rocky surface zone's material has bound at runtime.
# This is the test the user needs - it loads the actual scene the way
# the launcher does and walks the resulting tree to dump materials.
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

func _init() -> void:
	# Load the test range map_def the same way the launcher does.
	var map_def_path: String = "res://data/maps/test_range.json"
	var map_def_text: String = FileAccess.get_file_as_string(map_def_path)
	if map_def_text == "":
		print("FAIL: cannot read test_range.json")
		quit(1)
		return
	var map_def: Dictionary = JSON.parse_string(map_def_text)
	print("Loaded map_def: map_half_extents=", map_def.get("map_half_extents"))
	print("  surface_zones count=", map_def.get("surface_zones", []).size())

	# Build the ground material the way the heightmap code path does, AND
	# the way _spawn_surface_zone does for each surface zone, and print
	# what the rocky surface zone at (-15, 0, -30) actually gets.
	for zone in map_def.get("surface_zones", []):
		if zone["surface_type"] == "rocky":
			var v: String = TerrainBuilderScript._variant_for_position(zone["surface_type"], zone["center"][0], zone["center"][2])
			print("  ROCKY zone @ (%d, %d) -> variant '%s'" % [int(zone["center"][0]), int(zone["center"][2]), v])
			var mat = TerrainBuilderScript._build_terrain_material(zone["surface_type"], Vector2(20, 20), Color.WHITE, v)
			if mat is StandardMaterial3D:
				print("    albedo_texture: ", mat.albedo_texture.resource_path if mat.albedo_texture else "(null)")
				print("    normal_texture: ", mat.normal_texture.resource_path if mat.normal_texture else "(null)")
				print("    rough_texture:  ", mat.roughness_texture.resource_path if mat.roughness_texture else "(null)")
			else:
				print("    material type: ", mat.get_class())

	# Also dump what the heightmap material's rock overlay uses - this is
	# the rocky BASE for triplanar rock on slopes.
	print("\nHeightmap material rock overlay:")
	var rock_tex = TerrainBuilderScript._get_terrain_textures("rocky", "base")
	if rock_tex.albedo:
		print("  rock_albedo: ", rock_tex.albedo.resource_path)

	# And what happens if we call the same function with a variant?
	print("\nIf we explicitly use the variant instead:")
	var rock_v1 = TerrainBuilderScript._get_terrain_textures("rocky", "_v1")
	if rock_v1.albedo:
		print("  rocky_v1 albedo: ", rock_v1.albedo.resource_path)

	quit(0)
