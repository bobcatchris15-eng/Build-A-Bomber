@tool
extends SceneTree

func _init():
    var d = {"size": Vector3(1, 2, 3)}
    var methods = []
    for m in d.get_method_list():
        methods.append(m.name)
    var file = FileAccess.open("e:/Build-A-Bomber/dict_test.txt", FileAccess.WRITE)
    file.store_string("size in methods? " + str("size" in methods) + "\n")
    if d.has("size"):
        file.store_string("Has key size\n")
    
    # Try dot notation
    file.store_string("d.size type: " + str(typeof(d.size)) + "\n")
    
    file.close()
    quit()
