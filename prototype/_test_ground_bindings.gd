extends SceneTree
# VISUAL polish 2026-08-23: targeted test that loads the test range
# terrain via the same code path the runtime uses, then prints the actual
# texture path on every surface zone's StandardMaterial3D. This tells us
# whether the variant picker is hitting the variants (v1/v2/v3) or
# falling back to the base for some reason.
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")

func _init() -> void:
	# Mirror what test_range_launcher + match_director do for the ground.
	var map_def: Dictionary = {
		"map_half_extents": 40.0,
		"ground_color": [0.36, 0.34, 0.30],
		"surface_zones": [
			{ "surface_type": "marsh",    "center": [-30.0, 0.0, -30.0], "half_extents": [10.0, 10.0] },
			{ "surface_type": "rocky",    "center": [-15.0, 0.0, -30.0], "half_extents": [10.0, 10.0] },
			{ "surface_type": "snow_mud", "center": [  0.0, 0.0, -30.0], "half_extents": [10.0, 10.0] },
			{ "surface_type": "sand",     "center": [ 15.0, 0.0, -30.0], "half_extents": [10.0, 10.0] },
			{ "surface_type": "gravel",   "center": [ 30.0, 0.0, -30.0], "half_extents": [10.0, 10.0] },
			{ "surface_type": "forest",   "center": [-30.0, 0.0,  30.0], "half_extents": [10.0, 10.0] },
			{ "surface_type": "ice",      "center": [ 30.0, 0.0,  30.0], "half_extents": [10.0, 10.0] },
		],
	}
	# First: what does the variant picker return for each surface at
	# each zone's position? This is the function the spawn path calls.
	for zone in map_def["surface_zones"]:
		var v: String = TerrainBuilderScript._variant_for_position(zone["surface_type"], zone["center"][0], zone["center"][2])
		print("  zone %s @ (%d, %d) -> variant '%s'" % [zone["surface_type"], int(zone["center"][0]), int(zone["center"][2]), v])

	# Second: what does _get_terrain_variants return for each surface?
	# This is the disk-state check - is the variant picker even FINDING
	# the v1/v2/v3 files?
	for s in ["rocky", "marsh", "snow_mud", "sand", "gravel", "forest", "ice"]:
		var variants: Array = TerrainBuilderScript._get_terrain_variants(s)
		print("  _get_terrain_variants(%s) -> %s" % [s, str(variants)])

	# Third: actually build the materials for each surface and dump the
	# albedo_texture path. This is the end-to-end check.
	for s in ["rocky", "marsh", "snow_mud", "sand", "gravel", "forest", "ice"]:
		var mat = TerrainBuilderScript._build_terrain_material(s, Vector2(20, 20))
		if mat and mat.albedo_texture:
			print("  _build_terrain_material(%s) -> %s" % [s, mat.albedo_texture.resource_path])
		else:
			print("  _build_terrain_material(%s) -> (no texture)" % s)

	# Fourth: what does the heightmap-style material (used for the
	# baseline ground under everything) actually have bound? This is the
	# rocky triplanar overlay the user might be seeing.
	var base_mat = TerrainBuilderScript.build_ground_material_heightmap(Color(0.36, 0.34, 0.30), map_def)
	if base_mat is ShaderMaterial:
		for slot in ["albedo_0", "albedo_1", "albedo_2", "albedo_3", "rock_albedo"]:
			var tex: Texture = base_mat.get_shader_parameter(slot)
			if tex:
				print("  heightmap slot %s -> %s" % [slot, tex.resource_path])
			else:
				print("  heightmap slot %s -> (empty)" % slot)
	quit(0)
