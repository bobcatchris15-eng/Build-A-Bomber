extends Node3D

func _process(_delta):
	var housing = get_parent().get_node_or_null("turret_housing")
	if housing:
		rotation.y = housing.rotation.y
		var pivot = housing.get_node_or_null("barrel_pivot")
		# if pivot:
			# rotation.x = pivot.rotation.x # Disabled to prevent gaps
