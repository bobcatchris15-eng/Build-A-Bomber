@tool
extends SceneTree

func _init():
    var dict = {"size": Vector3(1, 2, 3)}
    print("dict.size type: ", typeof(dict.size))
    print("dict['size'] type: ", typeof(dict["size"]))
    quit()
