@tool
extends SceneTree

func _init():
    var script = load("res://scripts/module_placer.gd")
    if script:
        print("module_placer loaded successfully!")
    else:
        print("FAILED TO LOAD MODULE PLACER!")
    quit()
