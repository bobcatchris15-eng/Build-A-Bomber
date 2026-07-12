extends SceneTree

func _init():
	print("Test started")
	var scene = preload("res://scenes/MainLab.tscn").instantiate()
	root.add_child(scene)
	
	# Wait for physics and scene to settle
	for i in range(5):
		await process_frame
		
	print("Simulating click...")
	
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(640, 360)
	
	Input.parse_input_event(event)
	
	for i in range(5):
		await process_frame
		
	var hull = scene.get_node("Hull")
	print("Hull child count: ", hull.get_child_count())
	for child in hull.get_children():
		print("Child name: ", child.name)
		
	var file = FileAccess.open("res://test_output.txt", FileAccess.WRITE)
	file.store_line("Hull child count: " + str(hull.get_child_count()))
	for child in hull.get_children():
		file.store_line("Child: " + child.name)
	file.close()
	
	print("Test complete")
	quit()
