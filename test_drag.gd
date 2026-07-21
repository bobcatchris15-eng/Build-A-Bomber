@tool
extends SceneTree

func _init():
    var drag_drop = preload("res://scripts/drag_drop_manager.gd").new()
    print("Drag Drop loaded!")
    quit()
