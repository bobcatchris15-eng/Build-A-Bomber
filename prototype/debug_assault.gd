@tool
extends SceneTree

func _init():
    var ModuleCatalog = preload("res://scripts/module_catalog.gd")
    var data = ModuleCatalog.get_module_data("assault_hull")
    print("assault_hull: ", data)
    quit()
