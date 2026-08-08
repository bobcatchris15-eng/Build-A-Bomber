extends SceneTree
const M = preload("res://tests/battle/test_battle_movement.gd")
const T = preload("res://tests/test_terrain_and_maps.gd")
const D = preload("res://tests/test_designer_lab.gd")
func _init():
	var m = M.new(); m.tree = self; m.root = root
	var t = T.new(); t.tree = self; t.root = root
	var d = D.new(); d.tree = self; d.root = root
	var r1 = await m.test_real_unit_actually_converges_toward_a_move_order_on_a_real_map()
	var r2 = await t.test_map_scattered_peaks_smoke()
	var r3 = await d.test_module_drag_reclassifies_facet_and_mount()
	print("\n>>> BASELINE converges=%s peaks=%s module_drag=%s" % [
		"PASS" if r1 else "FAIL", "PASS" if r2 else "FAIL", "PASS" if r3 else "FAIL"])
	quit(0)
