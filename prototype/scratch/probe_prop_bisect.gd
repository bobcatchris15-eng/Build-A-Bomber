extends SceneTree
# Scratch: bisect place_grassland_prop()'s ~88ms.
#
# probe_primitive_alloc.gd ruled out the obvious explanation: allocating a
# MeshInstance3D + primitive mesh + StandardMaterial3D and adding it to the
# tree costs 0.06ms, and a prop allocates at most 5 of them (~0.3ms). So
# ~88ms per prop is coming from somewhere else. This calls the three prop
# builders directly, and an inlined hand-copy of the tuft builder, to find
# which step actually carries the cost.
#
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/probe_prop_bisect.gd --path .

const TerrainGreebles = preload("res://scripts/terrain_greebles.gd")

const N := 30

func _init():
	var holder = Node3D.new()
	root.add_child(holder)
	var rng = RandomNumberGenerator.new()
	rng.seed = 99

	_bench("place_grassland_prop (public)", func(i):
		TerrainGreebles.place_grassland_prop(Vector3(i, 0, 0), i, holder))

	_bench("_place_grass_tuft", func(i):
		TerrainGreebles._place_grass_tuft(Vector3(i, 0, 0), rng, holder))

	_bench("_place_grassland_rock", func(i):
		TerrainGreebles._place_grassland_rock(Vector3(i, 0, 0), rng, holder))

	_bench("_place_brush_clump", func(i):
		TerrainGreebles._place_brush_clump(Vector3(i, 0, 0), rng, holder))

	_bench("_flat_material only", func(_i):
		TerrainGreebles._flat_material(Color.RED, 0.8))

	# Hand-inlined copy of _place_grass_tuft, same work, local code.
	_bench("INLINED tuft (same work)", func(i):
		var blade_count = 4
		for b in range(blade_count):
			var blade = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.015
			cyl.bottom_radius = 0.035
			cyl.height = 0.3
			blade.mesh = cyl
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.4, 0.17)
			mat.roughness = 0.8
			blade.material_override = mat
			holder.add_child(blade)
			blade.global_position = Vector3(i, 0.15, b)
			blade.rotation = Vector3(0.1, 1.0, 0.1))

	# Same as above but WITHOUT the global_position write (which requires the
	# node's global transform, and forces a transform flush).
	_bench("INLINED tuft, position (local)", func(i):
		for b in range(4):
			var blade = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.015
			cyl.bottom_radius = 0.035
			cyl.height = 0.3
			blade.mesh = cyl
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.4, 0.17)
			mat.roughness = 0.8
			blade.material_override = mat
			holder.add_child(blade)
			blade.position = Vector3(i, 0.15, b)
			blade.rotation = Vector3(0.1, 1.0, 0.1))

	quit(0)

func _bench(label: String, fn: Callable) -> void:
	var t := Time.get_ticks_usec()
	for i in range(N):
		fn.call(i)
	var total := (Time.get_ticks_usec() - t) / 1000.0
	print("  %-34s %9.3f ms / %d = %8.3f ms each" % [label, total, N, total / N])
