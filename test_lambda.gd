@tool
extends SceneTree

func _init():
    var flip_meshes = func(node: Node, flip_func: Callable):
        if node is MeshInstance3D:
            node.scale.z = -abs(node.scale.z)
        for child in node.get_children():
            flip_func.call(child, flip_func)
    
    var root = Node3D.new()
    flip_meshes.call(root, flip_meshes)
    
    var file = FileAccess.open("user://lambda_test.txt", FileAccess.WRITE)
    file.store_string("Lambda OK\n")
    file.close()
    quit()
