@tool
extends SceneTree

func _init():
    print("Loading MainLab...")
    var packed = load("res://scenes/MainLab.tscn")
    if packed:
        var scene = packed.instantiate()
        print("Instantiated! mirror_enabled: ", scene.get("mirror_enabled"))
    else:
        print("Failed to load MainLab!")
    quit()
