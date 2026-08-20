extends SceneTree

const ModularHullBuilderScript = preload("res://scripts/modular_hull_builder.gd")

func _init():
	var builder = ModularHullBuilderScript.new()
	var wedge_block = {
		"type": 1,
		"grid_coord": Vector3i(0, 0, 2),
		"dim": Vector3i(1, 1, 1),
		"position": Vector3(0.0, 0.0, 2.0),
		"rotation": Vector3(0, PI / 2.0, 0),
		"scale": Vector3.ONE,
		"color": Color.WHITE,
		"node": null
	}
	builder.blocks = [wedge_block]
	builder._register_in_grid(wedge_block)
	
	print("Spatial dict keys after register:", builder._spatial_dict.keys())
	var cells = ModularHullBuilderScript.get_occupied_cells(Vector3i(0, 0, 2), Vector3i(4, 1, 1), Vector3(0, PI / 2.0, 0))
	print("Cells for 4x1x1 rotated wedge:", cells)
	
	var can = builder._can_occupy(Vector3i(0, 0, 2), Vector3i(4, 1, 1), Vector3(0, PI / 2.0, 0), wedge_block)
	print("can_occupy result:", can)
	quit(0)
