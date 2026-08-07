extends SceneTree
# Is the first-contact hitch the cost of first-drawing a munition?
#
# THE REPORT. Two large hitches in a short playtest, both as a unit Chris was
# following closely entered combat. Unit simulation is already ruled out - it
# measured 0.03-0.16ms across 2 to 34 units - so the suspect is the transient
# combat visuals, which are built LAZILY: MunitionPool constructs each mesh and
# each material variant on first use, and Godot compiles a render pipeline the
# first time a given material is actually DRAWN. Both land on the frame a weapon
# first fires, which is the frame Chris was watching.
#
# HOW THIS SEPARATES THE TWO COSTS. Construction is CPU work in
# MunitionPool.*(); pipeline compilation happens later, on the first frame the
# thing is on screen. So the probe times them apart:
#
#   phase A - call every MunitionPool variant, nothing added to the tree.
#   phase B - put one instance of each in front of the camera for a frame.
#   phase C - do phase B again with the now-warm cache, as the control.
#
# If B >> C, the hitch is pipeline compilation and pre-warming behind the DEPLOY
# curtain fixes it. If A dominates, it is allocation and the cache needs
# populating earlier. If neither, the hitch is somewhere else entirely and this
# rules out a whole class of cause.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_first_shot_hitch.gd

const MunitionPool = preload("res://scripts/munition_pool.gd")


func _init():
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	while not battle.world_is_ready:
		await process_frame
	for _i in range(60):
		await process_frame

	var idle := await _worst(90)
	print("")
	print("  idle worst frame:                    %7.2f ms" % idle)

	# --- A: construction only -------------------------------------------------
	var t0 := Time.get_ticks_usec()
	var mats := _build_materials()
	var meshes := _build_meshes()
	var construct := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  A  building %d materials + %d meshes: %7.2f ms"
		% [mats.size(), meshes.size(), construct])

	# --- B: first draw --------------------------------------------------------
	var holder := Node3D.new()
	battle.add_child(holder)
	var b := await _draw_all(battle, holder, mats, meshes)
	print("  B  FIRST draw of all of them:        %7.2f ms" % b)

	# --- C: same again, warm --------------------------------------------------
	var c := await _draw_all(battle, holder, mats, meshes)
	print("  C  second draw (control):            %7.2f ms" % c)

	print("")
	print("  first-draw penalty: %.2f ms over the warm control" % (b - c))
	if b - c > 8.0:
		print("  => pipeline compilation. Pre-warm behind the DEPLOY curtain.")
	elif construct > 8.0:
		print("  => allocation. Populate the MunitionPool cache at match start.")
	else:
		print("  => NOT the munitions. Look elsewhere.")

	battle.queue_free()
	await process_frame
	quit(0)


# Every distinct MunitionPool material the weapons actually ask for, harvested
# from auto_weapon.gd's call sites. Colour is part of the cache key, so each of
# these is a separate material and therefore a separate first draw.
func _build_materials() -> Array:
	var out: Array = []
	for pair in [
		[Color.CYAN, Color.CYAN], [Color.GOLD, Color.GOLD],
		[Color.LIGHT_CORAL, Color.RED], [Color.OLIVE, Color.YELLOW],
		[Color.CHOCOLATE, Color.ORANGE], [Color.SADDLE_BROWN, Color.ORANGE],
		[Color.BLUE_VIOLET, Color.BLUE_VIOLET], [Color.WHITE, Color.CYAN],
		[Color.MEDIUM_SPRING_GREEN, Color.MEDIUM_SPRING_GREEN],
		[Color.DARK_GOLDENROD, Color.GOLD],
		[Color(0.85, 0.4, 0.1), Color(1.0, 0.55, 0.1)],
		[Color(1.0, 0.86, 0.55), Color(1.0, 0.72, 0.35)],
		[Color(0.70, 0.40, 0.20), Color.ORANGE_RED],
		[Color(0.35, 0.38, 0.22), Color(0.7, 0.65, 0.2)],
	]:
		out.append(MunitionPool.emissive(pair[0], pair[1]))
	out.append(MunitionPool.emissive(Color(1.0, 0.97, 0.8), Color(1.0, 0.95, 0.7), 2.0))
	out.append(MunitionPool.emissive(Color(0.9, 0.9, 0.85), Color(0.8, 0.8, 0.75), 0.6))
	for col in [Color(0.35, 0.26, 0.16), Color(0.35, 0.33, 0.22), Color(0.35, 0.36, 0.32)]:
		out.append(MunitionPool.albedo(col))
	for col in [Color(0.15, 0.15, 0.15, 0.7), Color(0.5, 0.45, 0.35, 0.7),
			Color(0.55, 0.85, 0.90, 0.10), Color(0.62, 0.58, 0.50, 0.42),
			Color(0.75, 0.72, 0.66, 0.55), Color(0.95, 0.85, 0.45, 0.20)]:
		out.append(MunitionPool.alpha(col))
	out.append(MunitionPool.alpha_emissive(
		Color(1.0, 0.9, 0.6, 0.5), Color(1.0, 0.8, 0.4), 1.5))
	return out


func _build_meshes() -> Array:
	return [MunitionPool.unit_sphere(), MunitionPool.unit_cylinder(),
		MunitionPool.unit_box(), MunitionPool.unit_prism(),
		MunitionPool.unit_taper(0.4)]


# Puts one instance of every material/mesh pair directly in front of the camera
# for one frame. In front, because a munition culled offscreen is never drawn and
# therefore never compiles anything - which is the trap a naive warm pass falls
# into.
func _draw_all(battle, holder: Node3D, mats: Array, meshes: Array) -> float:
	for child in holder.get_children():
		child.queue_free()
	await process_frame

	var cam: Camera3D = battle.camera
	var origin: Vector3 = cam.global_position - cam.global_transform.basis.z * 6.0
	var i := 0
	for mat in mats:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i % meshes.size()]
		mi.material_override = mat
		mi.position = origin + Vector3(
			float(i % 8) * 0.35 - 1.2, float(i / 8) * 0.35, 0.0)
		mi.scale = Vector3.ONE * 0.25
		holder.add_child(mi)
		i += 1

	var t := Time.get_ticks_usec()
	await process_frame
	await process_frame
	return float(Time.get_ticks_usec() - t) / 1000.0


func _worst(frames: int) -> float:
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for _i in range(frames):
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) / 1000.0)
		last = now
	return worst
