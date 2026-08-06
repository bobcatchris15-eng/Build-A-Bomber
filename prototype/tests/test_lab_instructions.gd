@tool
extends SceneTree

func _init():
	print("=== Running Design Lab Instructions Unit Test ===")
	_test_instructions_dialog_creation()
	print("=== All Design Lab Instruction Tests Passed Successfully! ===")
	quit(0)

func _test_instructions_dialog_creation():
	var ModulePlacerScript = load("res://scripts/module_placer.gd")
	var placer = ModulePlacerScript.new()

	placer.show_instructions_dialog(true)
	assert(is_instance_valid(placer.instructions_canvas_layer), "instructions_canvas_layer not created")
	assert(placer.instructions_canvas_layer.has_node("Scrim"), "Scrim missing from instructions modal")
	
	placer.instructions_canvas_layer.queue_free()
	placer.free()
	print("  [PASS] Instructions modal creation verified.")
