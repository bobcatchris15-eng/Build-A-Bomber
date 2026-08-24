# probe_terrain_vision.gd
@tool
extends SceneTree

const VisionService = preload("res://scripts/battle/vision/vision_service.gd")
const MapCatalog = preload("res://scripts/map_catalog.gd")
const TerrainBuilder = preload("res://scripts/terrain_builder.gd")
const BattleLayers = preload("res://scripts/battle/battle_layers.gd")

class MockController extends Node3D:
	var current_map: Dictionary = {}
	func terrain_height_at(pos: Vector3) -> float:
		return TerrainBuilder.terrain_height_at(current_map, pos)

func _init() -> void:
	print("=== PROBING TERRAIN & OBSTACLE VISION OCCLUSION ===")
	var success := true
	var map_def = MapCatalog.get_map("lake_crossing")
	
	var controller = MockController.new()
	controller.current_map = map_def
	get_root().add_child(controller)
	
	var scale = 4.0 # lake_crossing world_scale
	var vs = VisionService.new()
	vs.setup(controller, 0, map_def.get("map_half_extents", 240.0 * scale), scale)
	
	print("VisionService setup: dim=%d, cell_size=%.1f, obstacles=%d" % [vs._dim, vs._cell_size(), vs._obstacles.size()])
	
	# Hill 0 at scaled center (-560, 0, 380) with height ~38.7m
	var hill_center: Vector3 = map_def.hills[0].center
	var hill_peak_y = controller.terrain_height_at(hill_center)
	print("Hill peak at %s height=%.2f" % [hill_center, hill_peak_y])
	
	# Test 1: Viewer at low ground south of hill looking north past the hill
	var viewer_low = Node3D.new()
	controller.add_child(viewer_low)
	var low_pos = Vector3(hill_center.x, controller.terrain_height_at(Vector3(hill_center.x, 0, hill_center.z - 180.0)), hill_center.z - 180.0)
	viewer_low.position = low_pos
	viewer_low.set_meta("team", 0)
	viewer_low.set_meta("vision_range", 260.0)
	
	vs.invalidate_los_cache()
	vs._update_shroud([viewer_low], [])
	
	var cell_front_pos = Vector3(hill_center.x, 0, hill_center.z - 90.0)
	var cell_behind_pos = Vector3(hill_center.x, 0, hill_center.z + 80.0)
	
	var front_visible = vs._image.get_pixelv(vs._world_to_cell(cell_front_pos.x, cell_front_pos.z)).a < 0.1
	var behind_visible = vs._image.get_pixelv(vs._world_to_cell(cell_behind_pos.x, cell_behind_pos.z)).a < 0.1
	
	print("Test 1 (Hill Occlusion from Low Ground):")
	print("  Front slope %s visible: %s (expected true)" % [cell_front_pos, front_visible])
	print("  Behind hill %s visible: %s (expected false)" % [cell_behind_pos, behind_visible])
	
	if not front_visible:
		print("FAIL: Front slope of hill should be visible!")
		success = false
	if behind_visible:
		print("FAIL: Ground behind tall hill should be occluded!")
		success = false
	if front_visible and not behind_visible:
		print("PASS: Hill properly occludes terrain behind it.")
	
	# Test 2: Viewer on top of the hill looking into the valley behind it
	var viewer_high = Node3D.new()
	controller.add_child(viewer_high)
	viewer_high.position = Vector3(hill_center.x, hill_peak_y, hill_center.z)
	viewer_high.set_meta("team", 0)
	viewer_high.set_meta("vision_range", 200.0)
	
	vs.invalidate_los_cache()
	vs._update_shroud([viewer_high], [])
	
	var valley_from_peak_visible = vs._image.get_pixelv(vs._world_to_cell(cell_behind_pos.x, cell_behind_pos.z)).a < 0.1
	print("Test 2 (High Ground Vantage from Hilltop):")
	print("  Valley behind hill %s visible from peak: %s (expected true)" % [cell_behind_pos, valley_from_peak_visible])
	
	if not valley_from_peak_visible:
		print("FAIL: Viewer on hilltop should be able to see down into valley!")
		success = false
	else:
		print("PASS: High ground viewer successfully sees over ridge into valley.")
	
	# Test 3: Boulder obstacle occlusion
	var obs0 = vs._obstacles[0]
	var obs_center_x = (obs0.x0 + obs0.x1) * 0.5
	var obs_center_z = (obs0.z0 + obs0.z1) * 0.5
	var obs_front_z = obs0.z0 - 30.0
	var obs_behind_z = obs0.z1 + 30.0
	
	var viewer_boulder = Node3D.new()
	controller.add_child(viewer_boulder)
	viewer_boulder.position = Vector3(obs_center_x, controller.terrain_height_at(Vector3(obs_center_x, 0, obs_front_z - 10.0)), obs_front_z - 10.0)
	viewer_boulder.set_meta("team", 0)
	viewer_boulder.set_meta("vision_range", 100.0)
	
	vs.invalidate_los_cache()
	vs._update_shroud([viewer_boulder], [])
	
	var in_front_boulder_vis = vs._image.get_pixelv(vs._world_to_cell(obs_center_x, obs_front_z)).a < 0.1
	var behind_boulder_vis = vs._image.get_pixelv(vs._world_to_cell(obs_center_x, obs_behind_z)).a < 0.1
	
	print("Test 3 (Boulder Obstacle Occlusion):")
	print("  In front of boulder visible: %s (expected true)" % in_front_boulder_vis)
	print("  Directly behind boulder visible: %s (expected false)" % behind_boulder_vis)
	
	if not in_front_boulder_vis:
		print("FAIL: Cell in front of boulder should be visible!")
		success = false
	if behind_boulder_vis:
		print("FAIL: Cell directly behind large boulder should be occluded!")
		success = false
	if in_front_boulder_vis and not behind_boulder_vis:
		print("PASS: Boulder obstacle casts realistic vision shadow.")
	
	# Test 4: Flying Unit bypasses terrain occlusion
	var viewer_flying = Node3D.new()
	controller.add_child(viewer_flying)
	viewer_flying.position = Vector3(hill_center.x, 25.0, hill_center.z - 180.0)
	viewer_flying.set_meta("team", 0)
	viewer_flying.set_meta("vision_range", 300.0)
	viewer_flying.set_meta("is_flying", true)
	
	vs.invalidate_los_cache()
	vs._update_shroud([viewer_flying], [])
	
	var flying_behind_visible = vs._image.get_pixelv(vs._world_to_cell(cell_behind_pos.x, cell_behind_pos.z)).a < 0.1
	print("Test 4 (Flying Aircraft Sightline):")
	print("  Flying aircraft reveals terrain: %s (expected true)" % flying_behind_visible)
	if not flying_behind_visible:
		print("FAIL: Flying aircraft should have unimpeded aerial view!")
		success = false
	else:
		print("PASS: Flying aircraft sees ground correctly.")
	
	# Test 5: Benchmark performance of shroud raymarching
	var viewers_bench: Array = []
	for i in range(16):
		var v = Node3D.new()
		controller.add_child(v)
		v.position = Vector3(-100.0 + i * 15.0, 0.0, -100.0 + i * 15.0)
		v.position.y = controller.terrain_height_at(v.position)
		v.set_meta("team", 0)
		v.set_meta("vision_range", 60.0)
		viewers_bench.append(v)
	
	var t_start = Time.get_ticks_usec()
	vs.invalidate_los_cache()
	vs._update_shroud(viewers_bench, [])
	var t_elapsed_ms = float(Time.get_ticks_usec() - t_start) / 1000.0
	print("Test 5 (Performance with 16 active viewers):")
	print("  Shroud update elapsed time: %.3f ms" % t_elapsed_ms)
	if t_elapsed_ms > 15.0:
		print("FAIL: Shroud update too slow (%.3f ms > 15 ms)" % t_elapsed_ms)
		success = false
	else:
		print("PASS: Shroud update execution is well within budget.")
	
	controller.queue_free()
	if success:
		print(">>> ALL TERRAIN & OBSTACLE VISION TESTS PASSED SUCCESSFULLY! <<<")
	else:
		print(">>> SOME TESTS FAILED! <<<")
	quit(0 if success else 1)
