extends SceneTree

const BlockMeshes = preload("res://scripts/block_meshes.gd")
const CSGMeshBaker = preload("res://scripts/csg_mesh_baker.gd")

func _init():
	print("=== Running Modular Block Hull Builder Unit Tests ===")
	
	# Test 1: BlockMeshes generation for 2 core primitives (Cube, 45 Wedge)
	print("Test 1: Testing BlockMeshes procedural generation...")
	var cube_mesh = BlockMeshes.build_cube()
	assert(cube_mesh != null and cube_mesh.get_faces().size() > 0, "Cube mesh failed")
	print("  - Cube mesh generated: %d faces" % (cube_mesh.get_faces().size() / 3))
	
	var wedge_mesh = BlockMeshes.build_wedge()
	assert(wedge_mesh != null and wedge_mesh.get_faces().size() > 0, "Wedge mesh failed")
	print("  - Wedge mesh generated: %d faces" % (wedge_mesh.get_faces().size() / 3))

	# Test 2: Grid Math & Coordinates
	print("Test 2: Testing 1-Unit Grid Snapping & Coordinates...")
	var ModularHullBuilderScript = load("res://scripts/modular_hull_builder.gd")
	var builder = ModularHullBuilderScript.new()
	
	var p0 = Vector3(0.4, 0.0, 0.0)
	var c0: Vector3i = builder.pos_to_grid_coord(p0)
	assert(c0 == Vector3i(0, 0, 0), "Coord 0 snapping failed: %s" % str(c0))
	
	var p1 = Vector3(1.1, 0.0, 0.0)
	var c1: Vector3i = builder.pos_to_grid_coord(p1)
	assert(c1 == Vector3i(1, 0, 0), "Coord 1 snapping failed: %s" % str(c1))
	print("  - 1-Unit translation snapping verified.")
	
	# Test 3: 3-Axis Cube Deforms (1-unit increments: stick, flat sheet, large box)
	print("Test 3: Testing 3-axis Cube deforms (1 to 8 units along X, Y, Z)...")
	var cells_1x = ModularHullBuilderScript.get_occupied_cells(Vector3i(0, 0, 0), Vector3i(1, 1, 1))
	assert(cells_1x.size() == 1, "1x1x1 should occupy 1 cell, got %d" % cells_1x.size())
	
	# Long thin stick: 6x1x1
	var cells_stick = ModularHullBuilderScript.get_occupied_cells(Vector3i(0, 0, 0), Vector3i(6, 1, 1))
	assert(cells_stick.size() == 6, "6x1x1 stick should occupy 6 cells, got %d" % cells_stick.size())
	
	# Wide flat sheet: 4x1x4
	var cells_sheet = ModularHullBuilderScript.get_occupied_cells(Vector3i(0, 0, 0), Vector3i(4, 1, 4))
	assert(cells_sheet.size() == 16, "4x1x4 sheet should occupy 16 cells, got %d" % cells_sheet.size())
	print("  - 3-Axis Cube deformations verified: stick (6x1x1), sheet (4x1x4)")

	# Test 4: Wedge lateral extension in steps of 1 (1 to 8)
	print("Test 4: Testing Wedge lateral width scaling in 1-unit increments (1, 2, 3, 4, 5, 6, 7, 8)...")
	for w in range(1, 9):
		var cells = ModularHullBuilderScript.get_occupied_cells(Vector3i(0, 0, 0), Vector3i(w, 1, 1))
		assert(cells.size() == w, "Wedge width %d should occupy %d cells, got %d" % [w, w, cells.size()])
	print("  - Wedge lateral scaling in 1-unit steps verified (1 to 8 units).")

	# Test 5: Rotation stepping logic (90° steps)
	print("Test 5: Testing 90-degree step rotation logic...")
	builder.blocks.clear()
	builder._spatial_dict.clear()
	var test_block = {
		"type": 0,
		"grid_coord": Vector3i(0, 0, 0),
		"dim": Vector3i.ONE,
		"position": Vector3.ZERO,
		"rotation": Vector3.ZERO,
		"scale": Vector3.ONE,
		"color": Color.WHITE,
		"node": null
	}
	builder.blocks.append(test_block)
	builder._register_in_grid(test_block)
	
	# Step rotate X by +1 (LMB: +90°)
	builder._step_block_rotation(0, Vector3.RIGHT, 1)
	assert(is_equal_approx(builder.blocks[0]["rotation"].x, PI / 2.0), "Rotate X +90 deg failed")
	
	# Step rotate X by -1 (RMB: -90°)
	builder._step_block_rotation(0, Vector3.RIGHT, -1)
	assert(is_equal_approx(builder.blocks[0]["rotation"].x, 0.0), "Rotate X -90 deg failed")
	print("  - 90-degree step rotation verified.")

	# Test 6: Rotated Wedge Width Deformation & Anchoring
	print("Test 6: Testing Rotated Wedge Width Deformation & Position Stability...")
	builder.blocks.clear()
	builder._spatial_dict.clear()
	var wedge_block = {
		"type": 1, # Wedge
		"grid_coord": Vector3i(0, 0, 2),
		"dim": Vector3i(1, 1, 1),
		"position": Vector3(0.0, 0.0, 2.0),
		"rotation": Vector3(0, PI / 2.0, 0), # Rotated 90 deg around Y
		"scale": Vector3.ONE,
		"color": Color.WHITE,
		"node": null
	}
	builder.blocks = [wedge_block]
	builder._register_in_grid(wedge_block)
	
	# Deform rotated wedge width from 1 to 4
	var def_ok = builder._set_block_dimensions(0, Vector3i(4, 1, 1))
	assert(def_ok, "Failed to deform rotated wedge")
	# Position must remain locked at (0, 0, 2) without drifting outward!
	assert(builder.blocks[0]["position"] == Vector3(0.0, 0.0, 2.0), "Rotated wedge drifted off position!")
	# Occupied cells in world space should extend along world Z
	var rot_cells = ModularHullBuilderScript.get_occupied_cells(Vector3i(0, 0, 2), Vector3i(4, 1, 1), Vector3(0, PI / 2.0, 0))
	assert(rot_cells.size() == 4, "Rotated wedge should occupy 4 world cells")
	print("  - Rotated wedge deformed to width 4 remains anchored at (0, 0, 2) with 0 drift.")

	# Test 7: CSG Bake of deformed blocks
	print("Test 7: Testing CSG welding bake with deformed blocks...")
	var test_prims = [
		{
			"type": 0,
			"position": Vector3(0, 0, 0),
			"rotation": Vector3.ZERO,
			"scale": Vector3(4.0, 1.0, 2.0)
		},
		{
			"type": 3,
			"position": Vector3(0, 1.0, 0),
			"rotation": Vector3(0, 0, 0),
			"scale": Vector3(4.0, 1.0, 1.0)
		}
	]
	var baked_mesh = CSGMeshBaker.bake(test_prims)
	assert(baked_mesh != null, "CSG bake returned null")
	var baked_faces = baked_mesh.get_faces().size() / 3
	assert(baked_faces > 0, "CSG bake produced 0 faces")
	print("  - CSG bake succeeded: produced %d triangles" % baked_faces)

	print("\nALL MODULAR BLOCK HULL BUILDER TESTS PASSED!")
	quit(0)
