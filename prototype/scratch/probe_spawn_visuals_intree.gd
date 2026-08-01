extends SceneTree
# Scratch: CONTROL for probe_spawn_visuals.gd.
#
# That probe attached its container to `root` from SceneTree._init(), where
# the tree is not live yet - so every `global_position` write inside the
# clutter builders emitted "!is_inside_tree()" and each error costs ~8ms
# (probe_error_logging_cost.gd). It reported spawn_visuals() at 1-5s.
#
# But the REAL caller is Skirmish._ready(), where the parent genuinely IS
# inside the tree and no error is emitted. sim_skirmish.gd running the real
# scene for 110s emitted 2 errors total, which says the real load probably
# never hits this. This measures the same call with a properly in-tree
# parent so the two numbers can be compared directly and the earlier figure
# either confirmed or retracted.
#
# Usage: ./godot.exe --script scratch/probe_spawn_visuals_intree.gd --path .

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")

func _init():
	# A real current_scene, with frames actually processed, so anything
	# parented under it is genuinely inside the tree.
	var scene = Node3D.new()
	scene.name = "FakeSkirmish"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var map = MapCatalog.get_map("lake_crossing")
	print("parent.is_inside_tree() = %s" % scene.is_inside_tree())

	var holder = Node3D.new()
	scene.add_child(holder)
	print("holder.is_inside_tree() = %s" % holder.is_inside_tree())

	var t := Time.get_ticks_usec()
	TerrainBuilder.spawn_visuals(map, holder)
	print("spawn_visuals() IN-TREE  : %8.1f ms  (%d nodes)"
		% [(Time.get_ticks_usec() - t) / 1000.0, _count(holder)])

	# And the detached comparison, same process, same map.
	var detached = Node3D.new() # deliberately never added to the tree
	t = Time.get_ticks_usec()
	TerrainBuilder.spawn_visuals(map, detached)
	print("spawn_visuals() DETACHED : %8.1f ms  (%d nodes)"
		% [(Time.get_ticks_usec() - t) / 1000.0, _count(detached)])
	detached.free()
	quit(0)

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c
