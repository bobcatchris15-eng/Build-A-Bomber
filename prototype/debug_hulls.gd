@tool
extends SceneTree

func _init():
    print("--- DEBUG HULLS ---")
    var MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
    var ModuleCatalog = preload("res://scripts/module_catalog.gd")
    
    var ids = ["naval_hull", "assault_hull", "medium_hull"]
    for id in ids:
        var mesh = MeshAssetLoader.get_hull_mesh(id)
        if mesh:
            var aabb = mesh.get_aabb()
            var data = ModuleCatalog.get_module_data(id)
            
            var max_target = max(data.size.x, max(data.size.y, data.size.z))
            var max_authored = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
            var fit_scale = max_target / max_authored if max_authored > 0.0 else 1.0
            
            print(id, " AABB: ", aabb.size, " JSON Size: ", data.size, " fit_scale: ", fit_scale)
        else:
            print(id, " Mesh not found!")
            
    print("--- END DEBUG HULLS ---")
    quit()
