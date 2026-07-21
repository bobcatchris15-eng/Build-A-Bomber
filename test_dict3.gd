@tool
extends SceneTree

func _init():
    var file = FileAccess.open("user://dict_test.txt", FileAccess.WRITE)
    file.store_string("Started\n")
    
    var d = {"size": Vector3(1, 2, 3)}
    
    # Check if dot notation on dictionary with 'size' works
    var s = d.size
    file.store_string("Type of d.size: " + str(typeof(s)) + "\n")
    
    file.close()
    quit()
