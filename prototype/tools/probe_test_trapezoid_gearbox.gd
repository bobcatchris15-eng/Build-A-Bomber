extends SceneTree

const MountReachScript = preload("res://scripts/mount_reach.gd")
const HullChineScript = preload("res://scripts/hull_chine.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")

func _init():
	print("--- Testing MountReach cache and Sprocket Trapezoid Gearbox ---")
	
	var hull_path = "res://assets/models/hulls/brenntal_medium_a.glb"
	var glb: PackedScene = load(hull_path)
	var hull = glb.instantiate()

	# 1. Test MountReach.cache_hull
	MountReachScript.clear_cache()
	MountReachScript.cache_hull(hull)
	
	var surface = MountReachScript.surface_for(null)
	if surface.is_empty():
		print("[FAIL] MountReach.surface_for(null) returned empty despite cache_hull!")
		quit(1)
		return
	print("[OK] MountReach.surface_for(null) resolved surface with %d tris." % [(surface["tris"] as PackedVector3Array).size() / 3])
	
	# 2. Test trapezoid mesh generator
	var r: float = 0.5
	var l_out = r * 1.5
	var l_in = r * 0.9
	var w = r * 1.1
	var h = r * 0.65
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v0 := Vector3(0.0, h * 0.5, -l_out * 0.5)
	var v1 := Vector3(0.0, h * 0.5, l_out * 0.5)
	var v2 := Vector3(-w, h * 0.5, l_in * 0.5)
	var v3 := Vector3(-w, h * 0.5, -l_in * 0.5)
	var v4 := Vector3(0.0, -h * 0.5, -l_out * 0.5)
	var v5 := Vector3(0.0, -h * 0.5, l_out * 0.5)
	var v6 := Vector3(-w, -h * 0.5, l_in * 0.5)
	var v7 := Vector3(-w, -h * 0.5, -l_in * 0.5)
	
	var add_quad = func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3):
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)

	add_quad.call(v0, v4, v5, v1, Vector3.RIGHT)
	add_quad.call(v3, v2, v6, v7, Vector3.LEFT)
	add_quad.call(v0, v1, v2, v3, Vector3.UP)
	add_quad.call(v4, v7, v6, v5, Vector3.DOWN)
	add_quad.call(v0, v3, v7, v4, (v3 - v0).cross(v4 - v0).normalized())
	add_quad.call(v1, v5, v6, v2, (v1 - v5).cross(v6 - v5).normalized())

	var mesh: ArrayMesh = st.commit()
	print("[OK] Trapezoid mesh generated with %d surfaces, %d faces." % [mesh.get_surface_count(), mesh.get_faces().size() / 3])
	
	# 3. Test road wheel shaft reach with cache_hull
	var tweaks = {
		"station_x": 1.73,
		"station_y": -0.89,
		"station_z": 0.0,
		"node_scale_x": 1.0,
		"node_scale_y": 1.0,
		"node_scale_z": 1.0,
	}
	var bottom_wheel = Vector3(0.0 - 0.22 * 0.4, -0.46 - 0.38 + 0.22 * 0.35, 0.0)
	var shaft_angle = deg_to_rad(40.0)
	var dir_wheel = Vector3(-sin(shaft_angle), cos(shaft_angle), 0.0).normalized()
	var solved_len = MountReachScript.solve(null, MountReachScript.station_from(tweaks), bottom_wheel, dir_wheel, 1.0)
	print("[OK] Solved road wheel shaft reach: %.3f (not fallback 1.0)" % solved_len)

	hull.free()
	quit(0)
