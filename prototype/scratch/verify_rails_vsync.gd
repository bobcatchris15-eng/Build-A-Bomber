extends SceneTree
# Verifies the two small fixes made after the performance investigation:
#
# 1. project.godot's explicit display/window/vsync/vsync_mode - reads it back
#    to prove the file still parses and the value is what was intended (a
#    malformed project.godot fails quietly in ways that are easy to miss).
#
# 2. terrain_builder._spawn_bridge()'s guard-rail ordering. Two cases:
#      parent at ORIGIN - proves the fix is a no-op for the real caller
#        (skirmish.gd passes the Skirmish root, which sits at the origin), so
#        no bridge changes appearance.
#      parent OFFSET   - proves the fix is actually worth making: with
#        add_child before global_position the rails track the deck; with the
#        old ordering they would have been placed in the parent's LOCAL space
#        and torn away from the deck by the parent's offset.
#
# Usage: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/verify_rails_vsync.gd --path .

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")

func _init():
	var failures := 0

	var mode = ProjectSettings.get_setting("display/window/vsync/vsync_mode")
	print("vsync_mode setting = ", mode, " (1 == Enabled)")
	if int(mode) != 1:
		print("  FAIL: expected 1")
		failures += 1
	else:
		print("  PASS: project.godot parses and vsync_mode is explicit")

	var bridge := {
		"center": Vector3(10.0, 0.0, -6.0),
		"half_extents": Vector2(12.0, 3.0), # long axis X
		"deck_height": 1.0,
	}
	# rail_h 0.5 / rail_thickness 0.3 are private to _spawn_bridge; expected
	# values below mirror them.
	var expect_y := 1.0 + 0.25
	var expect_z := [-6.0 - (3.0 - 0.15), -6.0 + (3.0 - 0.15)]

	for offset in [Vector3.ZERO, Vector3(100.0, 5.0, -40.0)]:
		var holder := Node3D.new()
		holder.position = offset
		root.add_child(holder)
		await process_frame

		TerrainBuilder._spawn_bridge(bridge, holder)
		await process_frame

		# Children: [0] deck, [1] rail -1, [2] rail +1
		var kids := holder.get_children()
		print("\nparent offset ", offset, " -> ", kids.size(), " children")
		if kids.size() != 3:
			print("  FAIL: expected deck + 2 rails")
			failures += 1
			holder.free()
			continue

		var deck_pos: Vector3 = kids[0].global_position
		print("  deck  global_position = ", deck_pos)
		if not is_equal_approx(deck_pos.x, 10.0) or not is_equal_approx(deck_pos.z, -6.0):
			print("  FAIL: deck not at the bridge centre in world space")
			failures += 1

		for i in [1, 2]:
			var p: Vector3 = kids[i].global_position
			print("  rail  global_position = ", p)
			var ok := is_equal_approx(p.x, 10.0) and is_equal_approx(p.y, expect_y) \
				and (is_equal_approx(p.z, expect_z[0]) or is_equal_approx(p.z, expect_z[1]))
			if not ok:
				print("  FAIL: rail not at its intended WORLD position (expected x=10, y=%.2f, z in %s)" % [expect_y, expect_z])
				failures += 1

		# The whole point: rails must sit at the deck's own height+edge in world
		# space regardless of where the parent is.
		var rail_to_deck: float = absf(kids[1].global_position.x - deck_pos.x)
		if rail_to_deck > 0.001:
			print("  FAIL: rails drifted from the deck along the span axis by ", rail_to_deck)
			failures += 1
		else:
			print("  PASS: rails stay aligned to the deck in world space")

		holder.free()
		await process_frame

	print("\n", "ALL CHECKS PASSED" if failures == 0 else "%d CHECK(S) FAILED" % failures)
	quit(0 if failures == 0 else 1)
