extends SceneTree

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")

func _init():
	print("--- Testing bake_from_source_geometry_data_async on Thread vs Main ---")
	var map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, 1.0)
	NavigationServer3D.map_set_cell_height(map, 0.25)
	NavigationServer3D.map_set_active(map, true)

	var region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)

	# Initial bake: flat 20x20 quad at Y=0
	var verts := PackedVector3Array()
	TerrainBuilder._add_nav_quad(verts, Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 10))
	var nm := NavigationMesh.new()
	nm.cell_size = 1.0
	nm.cell_height = 0.25
	nm.agent_radius = 1.0
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(verts, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	NavigationServer3D.region_set_navigation_mesh(region, nm)

	for _i in range(10):
		await physics_frame

	var p0 = NavigationServer3D.map_get_closest_point(map, Vector3.ZERO)
	print("Initial closest to origin = %s (expected (0,0,0))" % p0)

	# Now test async rebake with hole from a Thread (how _rebuild_thread does it!)
	var verts_with_hole := PackedVector3Array()
	# Only quads outside [-4, 4]
	TerrainBuilder._add_nav_quad(verts_with_hole, Vector3(-10, 0, -10), Vector3(-4, 0, -10), Vector3(-4, 0, 10), Vector3(-10, 0, 10))
	TerrainBuilder._add_nav_quad(verts_with_hole, Vector3(4, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10), Vector3(4, 0, 10))

	var done_flag := {"done": false}
	var thread := Thread.new()
	thread.start(func():
		print("Worker thread started")
		var nm_hole := NavigationMesh.new()
		nm_hole.cell_size = 1.0
		nm_hole.cell_height = 0.25
		nm_hole.agent_radius = 1.0
		var src_hole := NavigationMeshSourceGeometryData3D.new()
		src_hole.add_faces(verts_with_hole, Transform3D.IDENTITY)
		print("Worker thread calling bake_from_source_geometry_data_async...")
		NavigationServer3D.bake_from_source_geometry_data_async(nm_hole, src_hole, func():
			print("Callback fired!")
			NavigationServer3D.region_set_navigation_mesh(region, nm_hole)
			done_flag["done"] = true
		)
		print("Worker thread returning")
	)

	for f in range(60):
		await physics_frame
		if done_flag["done"]:
			print("Done flag detected at frame %d" % f)
			break

	for _i in range(10):
		await physics_frame

	var p1 = NavigationServer3D.map_get_closest_point(map, Vector3.ZERO)
	print("After Thread async rebake closest to origin = %s (expected dist >= 4m)" % p1)
	print("XZ dist to origin = %.3f" % Vector2(p1.x, p1.z).length())

	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)
	if thread.is_alive():
		thread.wait_to_finish()
	quit(0)
