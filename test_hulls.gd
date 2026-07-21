extends SceneTree

func _init():
    var HullLoader = preload("res://scripts/hull_loader.gd")
    var hulls = HullLoader.get_hulls()
    print("LOADED HULLS:")
    for key in hulls:
        print(" - ", key)
    quit()
