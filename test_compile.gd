@tool
extends SceneTree

func _init():
    var file = FileAccess.open("user://error_log.txt", FileAccess.WRITE)
    
    var script = load("res://scripts/module_placer.gd")
    if script:
        file.store_string("Script loaded successfully!")
    else:
        file.store_string("FAILED to load script!")
        
    file.close()
    quit()
