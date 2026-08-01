extends SceneTree
# Scratch: _spawn_bases() measured 27.4s of a 34.6s match load - by far the
# largest single cost in the game, and roughly 7x the navmesh bake that the
# earlier investigation focused on.
#
# _spawn_bases() builds the starting HQ / refinery / manufactories for both
# teams via building.gd's setup_prefab(), which loads an authored .glb and
# then runs the shared hull dressing passes on it (materials, greebles,
# decals). hull_decals/hull_greebles project via hull_projection.gd, which
# does Moller-Trumbore raycasts against EVERY triangle of the host mesh in
# GDScript - cheap on a small module, potentially enormous on a building.
#
# Times each prefab kind separately, then the dressing passes within one, so
# the 27s lands on a specific function instead of "spawning is slow".
#
# Usage: ./godot.exe --script scratch/probe_base_spawn.gd --path .

const BuildingScript = preload("res://scripts/building.gd")
const HullMaterialBuilder = preload("res://scripts/hull_material_builder.gd")
const HullGreebles = preload("res://scripts/hull_greebles.gd")
const HullDecals = preload("res://scripts/hull_decals.gd")
const HullProjection = preload("res://scripts/hull_projection.gd")

func _init():
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	await process_frame

	print("=== setup_prefab() per building kind ===")
	var kinds = ["hq", "refinery", "power_plant", "light_manufactory", "medium_manufactory", "heavy_manufactory"]
	var total := 0.0
	for kind in kinds:
		var b = BuildingScript.new()
		world.add_child(b)
		var t = Time.get_ticks_usec()
		b.setup_prefab(kind, 0, "industrialists")
		var dt = (Time.get_ticks_usec() - t) / 1000.0
		total += dt
		var mesh_inst = _find_mesh(b)
		var tris := 0
		if mesh_inst and mesh_inst.mesh:
			tris = mesh_inst.mesh.get_faces().size() / 3
		print("  %-20s %9.1f ms   (mesh tris: %d)" % [kind, dt, tris])
		b.queue_free()
	print("  %-20s %9.1f ms TOTAL for one team" % ["", total])

	# Where does it go inside one building? Re-run the dressing passes on a
	# fresh copy of the heaviest mesh.
	print("")
	print("=== dressing passes on the hq mesh ===")
	var probe = BuildingScript.new()
	world.add_child(probe)
	probe.setup_prefab("hq", 0, "industrialists")
	var src = _find_mesh(probe)
	if src == null or src.mesh == null:
		print("  (no mesh found)")
		quit(0)
		return

	var host = MeshInstance3D.new()
	host.mesh = src.mesh
	world.add_child(host)

	var t2 = Time.get_ticks_usec()
	var surf = HullProjection.build_surface(host)
	print("  HullProjection.build_surface   %9.1f ms  (%d tris gathered)"
		% [(Time.get_ticks_usec() - t2) / 1000.0, surf["tris"].size() / 3])

	t2 = Time.get_ticks_usec()
	HullMaterialBuilder.apply_hull_materials(host, "hardened_steel", "industrialists")
	print("  apply_hull_materials           %9.1f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))

	t2 = Time.get_ticks_usec()
	HullGreebles.apply_greebles(host, "industrialists", Vector3(8, 6, 8))
	print("  apply_greebles                 %9.1f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))

	t2 = Time.get_ticks_usec()
	HullDecals.apply_decals(host, "industrialists", Vector3(8, 6, 8))
	print("  apply_decals                   %9.1f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))
	quit(0)

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.mesh != null:
		return n
	for c in n.get_children():
		var f = _find_mesh(c)
		if f:
			return f
	return null
