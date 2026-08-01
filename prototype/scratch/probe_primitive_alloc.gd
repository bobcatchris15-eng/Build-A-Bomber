extends SceneTree
# Scratch: place_grassland_prop() costs ~88ms per prop (probe_terrain_micro.gd)
# while doing nothing but allocating 1-5 MeshInstance3D, a primitive Mesh each,
# and a StandardMaterial3D each. Nothing in that code is algorithmically
# expensive, so the cost must be in the allocations themselves.
#
# That would be a SHARED root cause rather than a terrain bug:
#   - visual_builder.gd allocates a fresh primitive mesh + material per part
#     (reconstruct_vehicle measured 50-465ms per unit)
#   - munition_pool.gd exists precisely because "a fresh primitive Mesh per
#     projectile cost 41.8ms/frame vs 18.8ms shared" (commit 54b6e0a)
#
# So this isolates each allocation type. If PrimitiveMesh.new() dominates,
# every one of those symptoms is the same fix (share/cache the mesh).
#
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/probe_primitive_alloc.gd --path .

const N := 200

func _init():
	var holder = Node3D.new()
	root.add_child(holder)

	_bench("MeshInstance3D.new() only", func():
		var m = MeshInstance3D.new()
		m.free())

	_bench("StandardMaterial3D.new()", func():
		var _m = StandardMaterial3D.new())

	_bench("BoxMesh.new() (no instance)", func():
		var _m = BoxMesh.new())

	_bench("CylinderMesh.new() (no instance)", func():
		var _m = CylinderMesh.new())

	_bench("SphereMesh.new() (no instance)", func():
		var _m = SphereMesh.new())

	# The real pattern: allocate mesh + material, assign, add to tree.
	_bench("full: BoxMesh+mat+add_child", func():
		var mi = MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = StandardMaterial3D.new()
		holder.add_child(mi))

	# Same, but sharing one mesh and one material across every instance -
	# the munition_pool.gd approach.
	var shared_mesh := BoxMesh.new()
	var shared_mat := StandardMaterial3D.new()
	_bench("shared mesh+mat+add_child", func():
		var mi = MeshInstance3D.new()
		mi.mesh = shared_mesh
		mi.material_override = shared_mat
		holder.add_child(mi))

	# Does assigning a property (which forces the mesh to regenerate its
	# geometry) cost extra on top of construction?
	_bench("BoxMesh.new() + set size", func():
		var m = BoxMesh.new()
		m.size = Vector3(1, 2, 3))

	quit(0)

func _bench(label: String, fn: Callable) -> void:
	var t := Time.get_ticks_usec()
	for i in range(N):
		fn.call()
	var total := (Time.get_ticks_usec() - t) / 1000.0
	print("  %-34s %9.3f ms / %d = %8.4f ms each" % [label, total, N, total / N])
