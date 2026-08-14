extends SceneTree
# Quick sanity check: can we create a compound shape via PhysicsServer3D and
# assign it to a CollisionShape3D.shape? Godot has no GDScript constructor for
# CompoundShape3D, so this is the only path.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_compound_shape_test.gd

func _init():
	print("Testing compound shape via PhysicsServer3D...")

	# Create two simple box pieces.
	var box1 := BoxShape3D.new()
	box1.size = Vector3(1.0, 0.5, 2.0)

	var box2 := BoxShape3D.new()
	box2.size = Vector3(2.0, 0.5, 1.0)

	# Build a compound via the physics server.
	var compound_rid := PhysicsServer3D.shape_create(PhysicsServer3D.SHAPE_COMPOUND)
	PhysicsServer3D.shape_add_child_shape(compound_rid, box1.get_rid(),
		Transform3D(Basis(), Vector3(0.0, 0.0, 1.0)))
	PhysicsServer3D.shape_add_child_shape(compound_rid, box2.get_rid(),
		Transform3D(Basis(), Vector3(0.0, 0.0, -1.0)))

	# Retrieve the data.
	var compound_data = PhysicsServer3D.shape_get_data(compound_rid)
	print("compound_data type: %s" % type_string(typeof(compound_data)))
	print("compound_data: %s" % compound_data)

	# Try assigning it to a CollisionShape3D.
	var col := CollisionShape3D.new()
	if compound_data != null:
		col.shape = compound_data
		print("Assignment succeeded. shape type: %s" % type_string(typeof(col.shape)))
		print("CollisionShape3D.shape assigned: %s" % col.shape)
	else:
		print("FAIL: shape_get_data returned null for compound")

	# Verify it has expected extent.
	if compound_data != null and "get_debug_mesh" in compound_data:
		print("Compound has debug mesh method.")

	# Cleanup
	col.free()
	print("Done.")
	quit(0)
