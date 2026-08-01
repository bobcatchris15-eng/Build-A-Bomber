extends SceneTree
# Scratch: micro-benchmark the terrain query functions that both the map load
# AND every ground unit's per-tick Y snap go through.
#
# _spawn_grassland_clutter() measured 4.85s to place at most 50 props
# (probe_spawn_visuals.gd) - ~100ms per prop, which no amount of mesh
# building explains. The loop only calls three things per attempt:
# is_position_blocked(), terrain_height_at(), place_grassland_prop(). This
# times each in isolation so the cost lands on one of them.
#
# terrain_height_at() is the important one beyond load time: per its own
# header comment it is called for "every moving ground unit's per-tick Y
# snap", so its per-call cost multiplies by units x 60Hz in a live match.
#
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/probe_terrain_micro.gd --path .

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const TerrainGreebles = preload("res://scripts/terrain_greebles.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")

const N := 2000

func _init():
	for map_id in ["lake_crossing", "highland_chokepoint"]:
		var map = MapCatalog.get_map(map_id)
		print("=== %s ===" % map_id)
		var rng = RandomNumberGenerator.new()
		rng.seed = 12345
		var half: float = map.get("map_half_extents", 80.0)
		var pts := []
		for i in range(N):
			pts.append(Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half)))

		var t = Time.get_ticks_usec()
		for p in pts:
			TerrainBuilder.height_at(map, p.x, p.z)
		_report("height_at", t)

		t = Time.get_ticks_usec()
		for p in pts:
			TerrainBuilder.terrain_height_at(map, p)
		_report("terrain_height_at", t)

		t = Time.get_ticks_usec()
		for p in pts:
			TerrainBuilder.is_position_blocked(map, p)
		_report("is_position_blocked", t)

		t = Time.get_ticks_usec()
		for p in pts:
			TerrainBuilder.get_surface_type_at(map, p)
		_report("get_surface_type_at", t)

		# 50 props is the real per-map clutter count.
		var holder = Node3D.new()
		root.add_child(holder)
		t = Time.get_ticks_usec()
		for i in range(50):
			TerrainGreebles.place_grassland_prop(pts[i], rng.randi(), holder)
		print("  %-22s %8.1f ms total for 50 props" % ["place_grassland_prop", (Time.get_ticks_usec() - t) / 1000.0])
		holder.queue_free()
		print("")
	quit(0)

func _report(label: String, t: int) -> void:
	var total_ms := (Time.get_ticks_usec() - t) / 1000.0
	print("  %-22s %8.3f ms / %d calls = %7.4f ms per call  (%6.2f ms for 12 units x 60Hz for 1s)"
		% [label, total_ms, N, total_ms / N, (total_ms / N) * 12 * 60])
