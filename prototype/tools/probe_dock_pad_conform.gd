extends SceneTree
# Smoke test for the dock-pad-on-slope fix. Places a refinery on a
# sloped map area and checks that the dock pad's local Y is offset
# from the building's centre - the pad should be at the bay's actual
# terrain height, not the building's centre height.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_dock_pad_conform.gd

const StructureScript = preload("res://scripts/battle/buildings/structure.gd")


func _init():
	var packed = load("res://scenes/Battle.tscn")
	if packed == null:
		print("[FAIL] Battle.tscn did not load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)

	# Wait for the boot to complete so the navmesh and world are ready.
	var guard := 0
	while not ("world_is_ready" in battle) or not battle.world_is_ready:
		if guard > 600:
			print("[FAIL] battle never became ready (waited %d frames)" % guard)
			quit(1)
			return
		await physics_frame
		guard += 1
	print("[OK]   battle ready after %d frames" % guard)

	# --- Place a refinery -----------------------------------------------
	# The player HQ is at approximately (0, 0, 80) on lake_crossing
	# (default map). A refinery is a buildable next to the HQ. We pick
	# (15, 0, 90) which is just outside the HQ's footprint and inside
	# the buildable zone. The terrain at (15, 90) may be sloped; the
	# test is informative whether it is or isn't.
	var site := Vector3(15, 0, 90)
	site.y = battle.terrain_height_at(site)
	print("[OK]   site terrain y=%.2f" % site.y)

	var refinery = battle._place_structure("refinery", 0, site)
	if refinery == null or not is_instance_valid(refinery):
		print("[FAIL] could not place a refinery at %s" % site)
		quit(1)
		return
	print("[OK]   placed refinery at %s, footprint %s" % [refinery.global_position, refinery.footprint])

	# --- Inspect the dock pad -----------------------------------------
	# The pad nodes are added as children of the refinery. We look
	# for child MeshInstance3D whose name contains "Pad" or whose
	# material_override is _pad_material. The pad's local Y should
	# now be terrain-relative, not 0.07.
	var pad_count := 0
	var pad_ys := []
	for child in refinery.get_children():
		if child is MeshInstance3D and child.material_override == StructureScript._pad_material:
			pad_count += 1
			pad_ys.append(child.position.y)
			print("[INFO]   pad at local %s (global %s)" % [child.position, child.global_position])
	if pad_count == 0:
		print("[FAIL] refinery has no dock pads as children (expected at least 1)")
		quit(1)
		return
	print("[OK]   refinery has %d dock pad(s)" % pad_count)

	# Compare to a refinery placed on FLAT ground. The flat refinery
	# should have pads at local Y close to 0.07. The sloped one
	# should have pads at local Y offset from 0.07. We can't
	# easily assert "offset != 0" without knowing the slope, but
	# we can at least confirm no pad is wildly wrong (e.g. a
	# thousand metres below the building).
	for py in pad_ys:
		if absf(py) > 100.0:
			print("[FAIL]   pad at local y=%.2f m - looks wrong" % py)
			quit(1)
			return

	# Place a second refinery at a known flat spot. Compare pad Y.
	var flat_site := Vector3(0, 0, 60)  # just north of the HQ
	flat_site.y = battle.terrain_height_at(flat_site)
	var flat_refinery = battle._place_structure("refinery", 0, flat_site)
	if flat_refinery != null and is_instance_valid(flat_refinery):
		var flat_pad_ys := []
		for child in flat_refinery.get_children():
			if child is MeshInstance3D and child.material_override == StructureScript._pad_material:
				flat_pad_ys.append(child.position.y)
		print("[INFO] flat refinery at %s, pad local ys: %s" % [flat_site, flat_pad_ys])

	# --- Inspect ambient-tree displacement ----------------------------
	# Count ambient trees in the resource_nodes group before and
	# after. After placement, the trees whose XZ falls within the
	# refinery's footprint radius should be scaled to zero (visible
	# in their MultiMesh transform).
	var ambient_trees: Array = []
	for n in get_nodes_in_group("resource_nodes"):
		if is_instance_valid(n) and n.get("is_ambient"):
			ambient_trees.append(n)
	print("[OK]   %d ambient trees in resource_nodes group" % ambient_trees.size())

	print("[PASS] smoke test completed: dock pads exist, ambient tree displacement did not crash. Visual conformance needs a real playtest.")
	quit(0)