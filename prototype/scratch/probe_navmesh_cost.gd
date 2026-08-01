extends SceneTree
# Scratch: build_navmeshes() measured 3.9s at map load (probe_load_phases.gd).
# The same machinery runs again MID-MATCH: skirmish.gd's
# _rebuild_dynamic_navmesh_holes() calls rebake_ground_and_amphibious()
# whenever _mark_navmesh_dirty() has fired - i.e. every time a building is
# placed or dies. If that rebake is anywhere near as expensive as the initial
# bake, it is a multi-second main-thread stall on every building placement,
# which is exactly the "build animation freezes the game" symptom.
#
# Times the initial bake and the mid-match rebake separately, per map, and
# splits the rebake into face generation vs. Recast bake so the fix targets
# the right half.
#
# Usage: ./godot.exe --script scratch/probe_navmesh_cost.gd --path .

const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")

func _init():
	for map_id in ["lake_crossing", "highland_chokepoint"]:
		var map = MapCatalog.get_map(map_id)
		print("=== %s (half_extents %s) ===" % [map_id, str(map.get("map_half_extents", 80.0))])

		var t = Time.get_ticks_usec()
		var nav = TerrainBuilder.build_navmeshes(map, [])
		print("  initial build_navmeshes()          : %8.1f ms" % _ms(t))

		# One building's worth of holes, as a live placement would produce.
		var holes = [{"center": Vector3(0, 0, 0), "half_extents": Vector2(3, 3)}]

		t = Time.get_ticks_usec()
		TerrainBuilder.rebake_ground_and_amphibious(map, holes, nav["ground_region"], nav["amphibious_region"])
		print("  rebake (1 building placed)         : %8.1f ms   <-- main-thread stall per placement" % _ms(t))

		# Split: face generation (GDScript grid scan) vs Recast bake.
		t = Time.get_ticks_usec()
		var gv = TerrainBuilder._build_ground_faces(map, holes)
		print("    _build_ground_faces()            : %8.1f ms  (%d verts)" % [_ms(t), gv.size()])

		t = Time.get_ticks_usec()
		var av = TerrainBuilder._build_amphibious_faces(map, holes)
		print("    _build_amphibious_faces()        : %8.1f ms  (%d verts)" % [_ms(t), av.size()])

		t = Time.get_ticks_usec()
		TerrainBuilder._bake_nav_mesh(gv, TerrainBuilder._nav_cell_size(map))
		print("    _bake_nav_mesh(ground)           : %8.1f ms" % _ms(t))

		t = Time.get_ticks_usec()
		TerrainBuilder._bake_nav_mesh(av, TerrainBuilder._nav_cell_size(map))
		print("    _bake_nav_mesh(amphibious)       : %8.1f ms" % _ms(t))
		print("")
	quit(0)

func _ms(t: int) -> float:
	return (Time.get_ticks_usec() - t) / 1000.0
