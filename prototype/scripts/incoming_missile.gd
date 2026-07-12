extends Node3D

var target_node: Node3D = null
var speed: float = 9.0
var damage_amount: float = 15.0
var is_destroyed: bool = false

func _ready():
	add_to_group("missiles")
	
	# Visual rocket body
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.15, 0.15, 0.5)
	mesh_inst.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	mat.emission_enabled = true
	mat.emission = Color.ORANGE
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func _physics_process(delta):
	if is_destroyed: return
	
	if not is_instance_valid(target_node):
		destroy_missile(false)
		return
		
	# Move towards target
	var dest = target_node.global_position + Vector3(0, 0.5, 0) # Hit center
	look_at(dest, Vector3.UP)
	var dir = (dest - global_position).normalized()
	global_position += dir * speed * delta
	
	# Check distance
	if global_position.distance_to(dest) < 1.2:
		# Hit player!
		if target_node.has_method("take_damage"):
			target_node.take_damage(damage_amount, "explosive")
		destroy_missile(false)

func destroy_missile(intercepted: bool):
	if is_destroyed: return
	is_destroyed = true
	
	# Spawn explosion sphere
	var exp = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	exp.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.ORANGE if not intercepted else Color.CYAN
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	exp.material_override = mat
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	
	var tween = create_tween()
	tween.tween_property(exp, "scale", Vector3.ZERO, 0.15)
	tween.finished.connect(func(): exp.queue_free())
	
	queue_free()
