extends SceneTree
# Chunk 20 of the miniature-scale plan: sweep world_scale 4 -> 16 on
# scattered_peaks (largest map, the one that historically segfaulted the
# Recast baker at B8) and record what each system costs, so Phase 3
# (navmesh tiling/streaming, flow-field windowing, two-tier fog) is tuned
# against real numbers instead of a guess.
#
# Diagnostic only - never changes DEFAULT_WORLD_SCALE, never asserts.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_streaming_wall.gd

const MapCatalogScript = preload("res://scripts/map_catalog.gd")
const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
const FlowFieldScript = preload("res://scripts/battle/movement/flow_field.gd")

const MAP_ID := "scattered_peaks"
const SCALES := [4.0, 8.0, 12.0, 16.0]


func _init():
	# The catalog's own get_map() already applies whatever DEFAULT_WORLD_SCALE
	# currently is. Fetch the map once with an explicit world_scale=1.0
	# override to get back genuinely unscaled data, then apply
	# _apply_world_scale() ourselves per sweep point - applying it twice on
	# already-scaled data would double-scale everything.
	MapCatalogScript.reset_cache_for_tests()
	var unscaled_raw: Dictionary = MapCatalogScript.get_map(MAP_ID).duplicate(true)
	unscaled_raw["world_scale"] = 1.0
	var base: Dictionary = MapCatalogScript._apply_world_scale(unscaled_raw)

	for scale in SCALES:
		_measure(base, scale)
	quit(0)


func _measure(base: Dictionary, scale: float) -> void:
	var raw: Dictionary = base.duplicate(true)
	raw["world_scale"] = scale
	var map_def: Dictionary = MapCatalogScript._apply_world_scale(raw)

	var half: float = map_def.get("map_half_extents", 80.0)
	var grid_cell: float = TerrainBuilderScript._nav_grid_cell(map_def)
	var cell_size: float = TerrainBuilderScript._nav_cell_size(map_def)
	var voxel_dim: int = int(ceil((half * 2.0) / cell_size))
	var tri_axis: int = int(ceil((half * 2.0) / grid_cell))

	var t0 := Time.get_ticks_msec()
	var verts := TerrainBuilderScript._build_ground_faces(map_def)
	var build_ms := Time.get_ticks_msec() - t0

	var t1 := Time.get_ticks_msec()
	var nav_mesh := TerrainBuilderScript._bake_nav_mesh(verts, cell_size)
	var bake_ms := Time.get_ticks_msec() - t1

	# Chunk 15: FlowField.build() resolves cell_size = BASE_CELL_SIZE *
	# world_scale, the same linear-with-scale trick as the navmesh grid, so
	# dims (and cell count) stay roughly constant regardless of world_scale.
	var flow_cell: float = FlowFieldScript.BASE_CELL_SIZE * scale
	var flow_dim: int = int(ceil((half * 2.0) / flow_cell))

	print("scale=%s half=%s grid_cell=%.3f cell_size=%.3f voxel_dim=%d tri_axis=%d ground_verts=%d build_ms=%d bake_ms=%d flow_cell=%.2f flow_dim=%d flow_cells=%d" % [
		scale, half, grid_cell, cell_size, voxel_dim, tri_axis, verts.size(), build_ms, bake_ms,
		flow_cell, flow_dim, flow_dim * flow_dim])
