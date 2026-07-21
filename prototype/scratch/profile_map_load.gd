extends SceneTree
# Scratch: profile where match-start time actually goes for a large map -
# navmesh baking, ground mesh generation, or something else (grassland
# clutter, resource nodes, etc). Prints elapsed ms per phase to stdout.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/profile_map_load.gd -- <map_id>

func _init():
	var args = OS.get_cmdline_user_args()
	var map_id = args[0] if args.size() > 0 else "lake_crossing"
	print("[PROFILE] map=", map_id)

	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	var map_def = MapCatalogScript.get_map(map_id)
	print("[PROFILE] half_extents=", map_def.get("map_half_extents", 80.0))

	var t0 = Time.get_ticks_msec()
	var ground_verts = TerrainBuilderScript._build_ground_faces(map_def)
	var t0b = Time.get_ticks_msec()
	print("[PROFILE] _build_ground_faces GDScript loop: ", t0b - t0, "ms, verts=", ground_verts.size())

	var ground_nav_mesh = NavigationMesh.new()
	var ground_source = NavigationMeshSourceGeometryData3D.new()
	ground_source.add_faces(ground_verts, Transform3D.IDENTITY)
	var t0c = Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data(ground_nav_mesh, ground_source)
	var t0d = Time.get_ticks_msec()
	print("[PROFILE] Recast bake_from_source_geometry_data: ", t0d - t0c, "ms")

	var nav = TerrainBuilderScript.build_navmeshes(map_def)
	var t1 = Time.get_ticks_msec()
	print("[PROFILE] build_navmeshes (full, all 4 maps): ", t1 - t0d, "ms")

	var mesh_data = TerrainBuilderScript.build_ground_visual_mesh(map_def)
	var t2 = Time.get_ticks_msec()
	print("[PROFILE] build_ground_visual_mesh: ", t2 - t1, "ms")

	NavigationServer3D.free_rid(nav.ground_region)
	if nav.water_region.is_valid(): NavigationServer3D.free_rid(nav.water_region)
	NavigationServer3D.free_rid(nav.amphibious_region)
	if nav.deep_water_region.is_valid(): NavigationServer3D.free_rid(nav.deep_water_region)
	NavigationServer3D.free_rid(nav.ground_map)
	NavigationServer3D.free_rid(nav.water_map)
	NavigationServer3D.free_rid(nav.amphibious_map)
	NavigationServer3D.free_rid(nav.deep_water_map)

	print("[PROFILE] TOTAL: ", t2 - t0, "ms")
	quit(0)
