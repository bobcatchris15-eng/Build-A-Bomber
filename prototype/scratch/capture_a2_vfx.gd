extends SceneTree
# A2 verification: real GPUParticles3D muzzle flash + death explosion.
# Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64.exe --script scratch/capture_a2_vfx.gd --path .

func _init():
	var out_dir = "res://progress_captures/2026-07-27_a2_vfx"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene = load("res://scenes/Skirmish.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 800)
	for i in range(10): await process_frame

	var units = scene.get_team_units(scene.PLAYER_TEAM)
	if units.is_empty():
		print("[CAPTURE] no player units found")
		quit(1)
		return
	var u = units[0]
	var cam = scene.camera
	cam.global_position = u.global_position + Vector3(0, 4, 8)
	cam.look_at(u.global_position, Vector3.UP)
	for i in range(4): await process_frame

	# Force a muzzle flash burst on whatever weapon this unit has, if any.
	for weapon in u.get_children():
		if weapon.has_method("_fire_at_target"):
			weapon.target = scene.enemy_hq
			weapon._fire_at_target()
			break
	# Force a death explosion burst directly.
	u._spawn_explosion(u.global_position + Vector3(2, 1, 0), 1.5)
	await process_frame

	root.get_texture().get_image().save_png("%s/a2_vfx_burst.png" % out_dir)
	print("[CAPTURE] A2 VFX burst saved")
	quit(0)
