class_name BlockMeshes
extends RefCounted

# Procedural meshes for the hull builder block types.
# Generates flat-faced planar meshes with proper UVs and verified Godot
# front-facing winding, plus a procedural chamfer normal map for edge highlights.

static var _cached_chamfer_normal_map: ImageTexture = null

static func get_chamfer_normal_map() -> ImageTexture:
	if _cached_chamfer_normal_map and is_instance_valid(_cached_chamfer_normal_map):
		return _cached_chamfer_normal_map

	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var bevel_margin := 0.08  # 8% chamfer margin around face perimeter

	for y in range(size):
		var v := (float(y) + 0.5) / float(size)
		for x in range(size):
			var u := (float(x) + 0.5) / float(size)

			var d_left := u
			var d_right := 1.0 - u
			var d_top := v
			var d_bottom := 1.0 - v

			var nx := 0.0
			var ny := 0.0

			if d_left < bevel_margin:
				var t := (bevel_margin - d_left) / bevel_margin
				nx -= t * 0.707
			elif d_right < bevel_margin:
				var t := (bevel_margin - d_right) / bevel_margin
				nx += t * 0.707

			if d_top < bevel_margin:
				var t := (bevel_margin - d_top) / bevel_margin
				ny += t * 0.707
			elif d_bottom < bevel_margin:
				var t := (bevel_margin - d_bottom) / bevel_margin
				ny += t * 0.707

			var nz := sqrt(maxf(0.001, 1.0 - (nx * nx + ny * ny)))
			var norm := Vector3(nx, ny, nz).normalized()

			var col := Color(
				norm.x * 0.5 + 0.5,
				norm.y * 0.5 + 0.5,
				norm.z * 0.5 + 0.5,
				1.0
			)
			img.set_pixel(x, y, col)

	_cached_chamfer_normal_map = ImageTexture.create_from_image(img)
	return _cached_chamfer_normal_map

static func build_cube() -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var st := SurfaceTool.new()
	st.create_from(bm, 0)
	st.generate_tangents()
	return st.commit()

static func build_wedge() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var v_bfl := Vector3(-0.5, -0.5, -0.5) # bottom front left (tip)
	var v_bfr := Vector3( 0.5, -0.5, -0.5) # bottom front right (tip)
	var v_bbl := Vector3(-0.5, -0.5,  0.5) # bottom back left
	var v_bbr := Vector3( 0.5, -0.5,  0.5) # bottom back right
	var v_tbl := Vector3(-0.5,  0.5,  0.5) # top back left
	var v_tbr := Vector3( 0.5,  0.5,  0.5) # top back right

	# 1. Bottom (-Y)
	_add_quad(st, v_bbl, v_bbr, v_bfr, v_bfl, Vector3(0, -1, 0))

	# 2. Back (+Z)
	_add_quad(st, v_bbl, v_tbl, v_tbr, v_bbr, Vector3(0, 0, 1))

	# 3. 45° Slope Ramp (normal is (0, 0.7071, -0.7071))
	var slope_norm := Vector3(0, 1, -1).normalized()
	_add_quad(st, v_bfr, v_tbr, v_tbl, v_bfl, slope_norm)

	# 4. Left (-X Triangle)
	_add_tri(st, v_bfl, v_tbl, v_bbl, Vector3(-1, 0, 0))

	# 5. Right (+X Triangle)
	_add_tri(st, v_bfr, v_bbr, v_tbr, Vector3(1, 0, 0))

	st.generate_tangents()
	return st.commit()

static func _add_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, norm: Vector3) -> void:
	# Tri 1: (p0, p1, p2)
	st.set_normal(norm)
	st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
	st.set_normal(norm)
	st.set_uv(Vector2(0, 1)); st.add_vertex(p1)
	st.set_normal(norm)
	st.set_uv(Vector2(1, 1)); st.add_vertex(p2)

	# Tri 2: (p0, p2, p3)
	st.set_normal(norm)
	st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
	st.set_normal(norm)
	st.set_uv(Vector2(1, 1)); st.add_vertex(p2)
	st.set_normal(norm)
	st.set_uv(Vector2(1, 0)); st.add_vertex(p3)

static func _add_tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, norm: Vector3) -> void:
	st.set_normal(norm)
	st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
	st.set_normal(norm)
	st.set_uv(Vector2(0, 1)); st.add_vertex(p1)
	st.set_normal(norm)
	st.set_uv(Vector2(1, 0)); st.add_vertex(p2)
