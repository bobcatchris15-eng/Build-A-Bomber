extends SceneTree
# Scratch: break the skirmish-load stall into its actual phases, and time a
# single unit spawn (reconstruct_vehicle) on its own.
#
# probe_skirmish_load.gd measured load()/instantiate()/_ready() as three
# opaque blocks and reported ~0ms for _ready() under --headless, which is not
# credible for a path that bakes navmeshes and reconstructs a dozen vehicles -
# the dummy renderer/servers skip most of the real work. So this runs WITHOUT
# --headless and calls the same functions Skirmish._ready() calls, directly,
# timing each one.
#
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/probe_load_phases.gd --path .

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")
const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")

func _t() -> int:
	return Time.get_ticks_usec()

func _ms(from: int) -> float:
	return (_t() - from) / 1000.0

func _init():
	print("=== skirmish load phases (map: lake_crossing) ===")

	var t := _t()
	var map = MapCatalog.get_map("lake_crossing")
	print("MapCatalog.get_map()          : %8.1f ms" % _ms(t))

	t = _t()
	var nav = TerrainBuilder.build_navmeshes(map, [])
	print("build_navmeshes()             : %8.1f ms" % _ms(t))

	t = _t()
	var ground = TerrainBuilder.build_ground_visual_mesh(map)
	print("build_ground_visual_mesh()    : %8.1f ms" % _ms(t))
	if ground and ground is Mesh:
		var faces = ground.get_faces().size() / 3
		print("    ground mesh triangles     : %d" % faces)

	var holder = Node3D.new()
	root.add_child(holder)
	t = _t()
	TerrainBuilder.spawn_visuals(map, holder)
	print("spawn_visuals()               : %8.1f ms" % _ms(t))
	print("    spawn_visuals node count  : %d" % _count_nodes(holder))

	# --- per-unit reconstruction cost (the build/spawn hitch) ---
	print("")
	print("=== reconstruct_vehicle() per blueprint (battle spawn path) ===")
	var bpm = BlueprintManagerScript.new()
	bpm.name = "BlueprintManager"
	root.add_child(bpm)

	var dir = DirAccess.open("res://data/loadout")
	var paths := []
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				paths.append("res://data/loadout/" + f)
	paths.sort()

	var total := 0.0
	for p in paths:
		var data = bpm.load_blueprint(p)
		if data.is_empty():
			continue
		var parent = Node3D.new()
		root.add_child(parent)
		t = _t()
		var hull = bpm.reconstruct_vehicle(data, parent, false, "industrialists")
		var dt = _ms(t)
		total += dt
		print("  %-34s %8.1f ms  (%d nodes)" % [p.get_file(), dt, _count_nodes(parent)])
		parent.queue_free()

	print("  %-34s %8.1f ms  TOTAL for %d designs" % ["", total, paths.size()])

	# Second pass: is any of it cached/warm on repeat?
	print("")
	print("=== second pass (same designs, warm caches) ===")
	total = 0.0
	for p in paths:
		var data = bpm.load_blueprint(p)
		if data.is_empty():
			continue
		var parent = Node3D.new()
		root.add_child(parent)
		t = _t()
		bpm.reconstruct_vehicle(data, parent, false, "industrialists")
		total += _ms(t)
		parent.queue_free()
	print("  warm total                   : %8.1f ms" % total)

	quit(0)

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
