extends SceneTree
# Scratch: probe_prop_bisect.gd found the whole terrain-clutter cost is one
# line - writing `global_position` on a freshly added child costs 181ms per
# tuft where the identical code writing `position` costs 1.08ms (170x).
#
# Before changing any call site, characterise it: is it a flat per-call cost,
# or does it scale with the number of siblings already under the parent
# (i.e. quadratic in nodes added)? That decides whether this is "swap two
# lines in terrain_greebles" or a codebase-wide pattern to hunt down.
#
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/probe_global_position_cost.gd --path .

func _init():
	print("=== cost of one global_position write vs sibling count ===")
	for sibling_count in [0, 50, 200, 800, 2000]:
		var holder = Node3D.new()
		root.add_child(holder)
		for i in range(sibling_count):
			var filler = MeshInstance3D.new()
			filler.mesh = BoxMesh.new()
			holder.add_child(filler)
			filler.position = Vector3(i, 0, 0)

		var probes := []
		for i in range(20):
			var mi = MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			holder.add_child(mi)
			probes.append(mi)

		var t := Time.get_ticks_usec()
		for mi in probes:
			mi.global_position = Vector3(1, 2, 3)
		var per_global := (Time.get_ticks_usec() - t) / 1000.0 / probes.size()

		t = Time.get_ticks_usec()
		for mi in probes:
			mi.position = Vector3(1, 2, 3)
		var per_local := (Time.get_ticks_usec() - t) / 1000.0 / probes.size()

		print("  siblings %5d : global_position %8.3f ms   position %8.4f ms   (%6.0fx)"
			% [sibling_count, per_global, per_local, per_global / max(per_local, 0.00001)])
		holder.free()

	print("")
	print("=== does it matter whether the parent is inside the tree? ===")
	var detached = Node3D.new() # never added to root
	for i in range(500):
		var f = MeshInstance3D.new()
		f.mesh = BoxMesh.new()
		detached.add_child(f)
		f.position = Vector3(i, 0, 0)
	var probes2 := []
	for i in range(20):
		var mi = MeshInstance3D.new()
		detached.add_child(mi)
		probes2.append(mi)
	var t2 := Time.get_ticks_usec()
	for mi in probes2:
		mi.global_position = Vector3(1, 2, 3)
	print("  detached parent, 500 siblings: %8.3f ms per global_position write"
		% ((Time.get_ticks_usec() - t2) / 1000.0 / probes2.size()))
	detached.free()
	quit(0)
