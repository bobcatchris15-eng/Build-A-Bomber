extends Node3D

func _process(_delta):
	var p = get_parent()
	if p is Node3D:
		var hull = p.get_parent()
		if hull is Node3D:
			var forward = -p.global_transform.basis.z
			var hull_up = hull.global_transform.basis.y
			var proj_forward = (forward - hull_up * forward.dot(hull_up)).normalized()
			if proj_forward.length_squared() > 0.01:
				global_transform.basis = Basis.looking_at(proj_forward, hull_up)
