extends SceneTree
# Debug: reproduce module_placer.gd's exact mirror-flip process for a leg
# module, then apply the same swing.rotation.x animation battle_unit.gd
# uses, and compare the mirrored vs unmirrored leg's resulting foot world
# position/orientation over a swing cycle - to find out whether the mirror
# and the X-axis swing are interacting badly ("upside down" report).
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/debug_leg_mirror_swing.gd --path .

const _MIRROR_X := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

func _apply_mirror_flip(module: Node3D):
	for child in module.get_children():
		if not (child is Node3D):
			continue
		child.transform = Transform3D(_MIRROR_X * child.transform.basis, _MIRROR_X * child.transform.origin)

func _init():
	var VisualBuilder = load("res://scripts/visual_builder.gd")

	var right_leg = Node3D.new()
	root.add_child(right_leg)
	VisualBuilder.build_visual("legs", right_leg, Vector3(0.5, 1.5, 0.5), Color.DARK_RED, {"leg_length": 1.0, "foot_size": 1.0, "leg_stance_reach": 3.2, "leg_hull_centerline_y": 1.35, "knee_height": 0.375})

	var left_leg = Node3D.new()
	root.add_child(left_leg)
	VisualBuilder.build_visual("legs", left_leg, Vector3(0.5, 1.5, 0.5), Color.DARK_RED, {"leg_length": 1.0, "foot_size": 1.0, "leg_stance_reach": 3.2, "leg_hull_centerline_y": 1.35, "knee_height": 0.375})
	_apply_mirror_flip(left_leg)

	for i in range(4): await process_frame

	var right_swing = right_leg.get_node_or_null("LegRoot/LegSwing")
	var left_swing = left_leg.get_node_or_null("LegRoot/LegSwing")
	print("[DEBUG] right_swing found: ", right_swing != null, " left_swing found: ", left_swing != null)
	if not right_swing or not left_swing:
		quit(1)
		return

	print("[DEBUG] right_swing.scale (before anim): ", right_swing.scale, " rotation: ", right_swing.rotation)
	print("[DEBUG] left_swing.scale (before anim): ", left_swing.scale, " rotation: ", left_swing.rotation)

	var right_foot = right_swing.get_children().filter(func(c): return c.name.begins_with("MeshInstance") or true)
	# Just grab global positions of all children to compare silhouettes instead of guessing node order.
	print("[DEBUG] --- BEFORE animation (theta=0) ---")
	for c in right_swing.get_children():
		print("  RIGHT ", c.get_class(), " global_pos=", c.global_position, " global_rot=", c.global_rotation)
	for c in left_swing.get_children():
		print("  LEFT  ", c.get_class(), " global_pos=", c.global_position, " global_rot=", c.global_rotation)

	var theta = 0.4
	right_swing.rotation.x = theta
	left_swing.rotation.x = theta
	for i in range(2): await process_frame

	print("[DEBUG] --- AFTER animation (theta=0.4) ---")
	for c in right_swing.get_children():
		print("  RIGHT ", c.get_class(), " global_pos=", c.global_position, " global_rot=", c.global_rotation)
	for c in left_swing.get_children():
		print("  LEFT  ", c.get_class(), " global_pos=", c.global_position, " global_rot=", c.global_rotation)

	quit(0)
