extends SceneTree
func _init():
	var t = load("res://run_tests.gd").new()
	root.add_child(t)
	await process_frame
	var ok = await t.test_design_to_battle_integration()
	print("RESULT=", ok)
	quit()
