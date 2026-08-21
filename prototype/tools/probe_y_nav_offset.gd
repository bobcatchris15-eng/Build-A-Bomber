extends SceneTree

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")

func _init():
	var map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, 1.0)
	NavigationServer3D.map_set_cell_height(map, 0.25)
	NavigationServer3D.map_set_active(map, true)

	var region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)

	var verts := PackedVector3Array()
	TerrainBuilder._add_nav_quad(verts, Vector3(-10, 0, -10), Vector3(-3, 0, -10), Vector3(-3, 0, 10), Vector3(-10, 0, 10))
	TerrainBuilder._add_nav_quad(verts, Vector3(3, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10), Vector3(3, 0, 10))
	TerrainBuilder._add_nav_quad(verts, Vector3(-3, 0, 3), Vector3(3, 0, 3), Vector3(3, 0, 10), Vector3(-3, 0, 10))
	TerrainBuilder._add_nav_quad(verts, Vector3(-3, 0, -10), Vector3(3, 0, -10), Vector3(3, 0, -3), Vector3(-3, 0, -3))

	var nm = NavigationMesh.new()
	nm.cell_size = 1.0
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.5
	var src = NavigationMeshSourceGeometryData3D.new()
	src.add_faces(verts, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	NavigationServer3D.region_set_navigation_mesh(region, nm)

	for _i in range(5):
		await physics_frame

	print("--- Test 1: Start/End at Y=0 ---")
	var path1 = NavigationServer3D.map_get_path(map, Vector3(0, 0, -8), Vector3(0, 0, 8), true)
	print("Path1 points count: %d" % path1.size())
	for i in range(path1.size()):
		print("  path1[%d] = %s" % [i, path1[i]])

	print("--- Test 2: Start/End at Y=-12 (simulating unit global_position at terrain height) ---")
	var path2 = NavigationServer3D.map_get_path(map, Vector3(0, -12, -8), Vector3(0, -12, 8), true)
	print("Path2 points count: %d" % path2.size())
	for i in range(path2.size()):
		print("  path2[%d] = %s" % [i, path2[i]])

	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)
	quit(0)
