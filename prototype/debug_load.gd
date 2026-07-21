extends SceneTree

func _init():
    var f = FileAccess.open("E:/Build-A-Bomber/prototype/debug_out.txt", FileAccess.WRITE)
    var path = "res://assets/models/parts/heavy_machine_gun.glb"
    var exists = ResourceLoader.exists(path)
    f.store_line("Resource exists: " + str(exists))
    if exists:
        var res = load(path)
        f.store_line("Loaded resource: " + str(res))
    else:
        var dir = DirAccess.open("res://assets/models/parts")
        if dir:
            dir.list_dir_begin()
            var file_name = dir.get_next()
            while file_name != "":
                f.store_line("Found file: " + file_name)
                file_name = dir.get_next()
        else:
            f.store_line("Failed to open directory.")
    f.close()
    quit()
