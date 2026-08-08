extends SceneTree
# Verifies the authored boulder/resource-node pool actually loads and
# renders through the real spawn paths (_spawn_rock_obstacle,
# resource_node.gd.setup), not just that the .glb files exist on disk.

const TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
const ResourceNodeScript = preload("res://scripts/resource_node.gd")


func _init():
	_check_files()
	_check_obstacle_spawn()
	_check_resource_nodes()
	quit(0)


func _check_files() -> void:
	print("--- asset existence ---")
	for i in range(4):
		var path := "res://assets/models/terrain/boulder_%d.glb" % i
		print("  ", path, " exists=", ResourceLoader.exists(path))
	for res_type in ["ore", "crystal", "lumber", "oil"]:
		var count := 3 if res_type != "oil" else 2
		for i in range(count):
			var path := "res://assets/models/terrain/resource_%s_%d.glb" % [res_type, i]
			print("  ", path, " exists=", ResourceLoader.exists(path))


func _check_obstacle_spawn() -> void:
	print("--- obstacle spawn (authored path) ---")
	var parent := Node3D.new()
	root.add_child(parent)
	var obstacle := {"center": Vector3(10, 0, 10), "half_extents": Vector2(3, 3), "type": "rock"}
	TerrainBuilderScript._spawn_obstacle(obstacle, parent)
	print("  children after obstacle spawn: ", parent.get_child_count())
	for c in parent.get_children():
		print("    ", c.name, " type=", c.get_class(), " pos=", (c.global_position if c is Node3D else "?"))
	parent.queue_free()


func _check_resource_nodes() -> void:
	print("--- resource node spawn (authored path) ---")
	for res_type in ["ore", "crystal", "lumber", "oil", "metal"]:
		var node := ResourceNodeScript.new()
		root.add_child(node)
		node.global_position = Vector3(randf() * 100, 0, randf() * 100)
		node.setup(res_type, 500)
		var mesh_child = node.mesh_inst
		var is_authored: bool = mesh_child != null and not (mesh_child is MeshInstance3D and mesh_child.get_child_count() == 0 and mesh_child.mesh != null and mesh_child.mesh.resource_path == "")
		print("  type=", res_type, " canonical=", node.resource_type,
			" mesh_inst_class=", (mesh_child.get_class() if mesh_child else "null"),
			" mesh_inst_children=", (mesh_child.get_child_count() if mesh_child else -1))
		node.queue_free()
