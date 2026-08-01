extends SceneTree
# Scratch: spawn_visuals() measured 5.3s for only 122 nodes in
# probe_load_phases.gd - i.e. ~43ms per node, so the cost is per-item work
# (texture loads, procedural mesh generation, clutter scatter), not node
# count. This breaks it down by the sub-loops spawn_visuals() runs.
#
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/probe_spawn_visuals.gd --path .

const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
var TerrainBuilder = TerrainBuilderScript.new()
const MapCatalog = preload("res://scripts/map_catalog.gd")

var _map: Dictionary

func _init():
	_map = MapCatalog.get_map("lake_crossing")
	print("=== spawn_visuals() breakdown (lake_crossing) ===")
	_phase("water_areas          ", "_spawn_water_plane", _map.get("water_areas", []))
	_phase("water_blobs          ", "_spawn_water_blob", _map.get("water_blobs", []))
	_phase("obstacles            ", "_spawn_obstacle", _map.get("obstacles", []))
	_phase("surface_zones        ", "_spawn_surface_zone", _map.get("surface_zones", []))
	_phase("shallow_water_areas  ", "_spawn_shallow_water_marker", _map.get("shallow_water_areas", []))
	_phase("bridges              ", "_spawn_bridge", _map.get("bridges", []))

	var holder = Node3D.new()
	root.add_child(holder)
	var t = Time.get_ticks_usec()
	TerrainBuilder.call("_spawn_grassland_clutter", _map, holder)
	print("%-22s %4s items %8.1f ms  (%d nodes)" % ["grassland_clutter", "-", (Time.get_ticks_usec() - t) / 1000.0, _count(holder)])

	# Second run of the whole thing: how much of the above is cold texture
	# loading (which a warm cache would hide) vs. real per-load work?
	var holder2 = Node3D.new()
	root.add_child(holder2)
	t = Time.get_ticks_usec()
	TerrainBuilder.spawn_visuals(_map, holder2)
	print("")
	print("WARM full spawn_visuals(): %8.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	quit(0)

func _phase(label: String, fn: String, items: Array) -> void:
	var holder = Node3D.new()
	root.add_child(holder)
	var t = Time.get_ticks_usec()
	for it in items:
		TerrainBuilder.call(fn, it, holder)
	print("%-22s %4d items %8.1f ms  (%d nodes)" % [label, items.size(), (Time.get_ticks_usec() - t) / 1000.0, _count(holder)])

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c
