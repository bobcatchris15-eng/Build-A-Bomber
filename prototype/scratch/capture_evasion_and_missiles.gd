extends SceneTree
# Windowed visual verification for FABLE_REVIEW 1.4 (evasion/miss model) and
# 2.2 (real interceptable missile projectiles). Must run WITHOUT --headless.
# Run: ./Godot_v4.3-stable_win64.exe --path prototype scratch/capture_evasion_and_missiles.gd
#
# Diagnostics write to res://scratch/diag_log.txt via FileAccess (flushed on
# every call) instead of print(), because stdout piped through this session's
# background-bash wrapper is fully buffered until process exit - a forced
# kill loses everything print() ever wrote. The log file survives a kill.

const ModuleData = preload("res://scripts/module_data.gd")

var _diag_log: Array = []

func _diag(msg: String):
	_diag_log.append(msg)
	var f = FileAccess.open("res://scratch/diag_log.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_diag_log))
		f.close()

func _init():
	_diag("start")
	var out_dir = "res://progress_captures/2026-07-18_evasion_and_missiles"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_diag("out_dir made")

	var BattleUnitScript = preload("res://scripts/battle_unit.gd")
	_diag("battle_unit preloaded")

	# A bare minimal scene (no Skirmish terrain/navmesh/AI setup - that's
	# what was making the windowed run take forever) - just enough to see
	# the missile/miss-puff visuals against a ground plane.
	var scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	root.size = Vector2i(1280, 800)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	scene.add_child(light)

	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var gmat = StandardMaterial3D.new()
	gmat.albedo_color = Color(0.3, 0.32, 0.28)
	ground.material_override = gmat
	scene.add_child(ground)

	var cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	_diag("scene built, awaiting frames")
	for i in range(3):
		await process_frame
		_diag("frame %d" % i)

	var launcher = CharacterBody3D.new()
	launcher.set_script(BattleUnitScript)
	scene.add_child(launcher)
	launcher.team = 0
	launcher.set_meta("team", 0)
	launcher.add_to_group("damageable")
	launcher.global_position = Vector3(0, 0, 0)
	_diag("launcher spawned")

	var target = CharacterBody3D.new()
	target.set_script(BattleUnitScript)
	scene.add_child(target)
	target.team = 1
	target.set_meta("team", 1)
	target.add_to_group("damageable")
	target.max_hp = 500.0
	target.hp = 500.0
	target.global_position = Vector3(0, 0, 14)
	target.velocity = Vector3(15.0, 0.0, 0.0) # fast mover, so it can dodge
	_diag("target spawned")

	var missile_weapon = Node3D.new()
	missile_weapon.set_script(load("res://scripts/auto_weapon.gd"))
	launcher.add_child(missile_weapon)
	var m_data = ModuleData.new()
	m_data.type_id = "guided_missile"
	m_data.base_weight = 200.0
	m_data.base_dps = 40.0
	m_data.tweaks = {}
	missile_weapon.set_meta("module_data", m_data)
	_diag("missile weapon meta set, calling _ready")
	missile_weapon._ready()
	_diag("missile weapon _ready done")
	missile_weapon.target = target
	missile_weapon._fire_missile_projectile(false)
	_diag("guided missile fired")

	var pod_launcher = CharacterBody3D.new()
	pod_launcher.set_script(BattleUnitScript)
	scene.add_child(pod_launcher)
	pod_launcher.team = 0
	pod_launcher.set_meta("team", 0)
	pod_launcher.global_position = Vector3(-4, 0, 0)
	var pod_weapon = Node3D.new()
	pod_weapon.set_script(load("res://scripts/auto_weapon.gd"))
	pod_launcher.add_child(pod_weapon)
	var p_data = ModuleData.new()
	p_data.type_id = "missile_pod"
	p_data.base_weight = 250.0
	p_data.base_dps = 60.0
	p_data.tweaks = {"grid_size": 4.0}
	pod_weapon.set_meta("module_data", p_data)
	pod_weapon._ready()
	pod_weapon.target = target
	pod_weapon._fire_swarm_missiles()
	_diag("swarm missiles fired")

	# Ballistic weapon firing at the fast mover - some shots should miss and
	# show the dirt-puff. Fire several rounds so at least one visibly misses.
	var ballistic_shooter = CharacterBody3D.new()
	ballistic_shooter.set_script(BattleUnitScript)
	scene.add_child(ballistic_shooter)
	ballistic_shooter.team = 0
	ballistic_shooter.set_meta("team", 0)
	ballistic_shooter.global_position = Vector3(4, 0, 0)
	var b_weapon = Node3D.new()
	b_weapon.set_script(load("res://scripts/auto_weapon.gd"))
	ballistic_shooter.add_child(b_weapon)
	var b_data = ModuleData.new()
	b_data.type_id = "rotary_cannon"
	b_data.base_weight = 80.0
	b_data.base_dps = 75.0
	b_data.tweaks = {}
	b_weapon.set_meta("module_data", b_data)
	b_weapon._ready()
	b_weapon.target = target
	seed(7) # a seed that reliably produces at least one miss in the rolls below
	for i in range(20):
		b_weapon._deal_weapon_damage(target, 5.0)
	_diag("ballistic rounds fired")

	# Reposition the camera to frame the whole scene (launcher, target,
	# pod launcher, ballistic shooter all visible).
	var cam2 = root.get_camera_3d()
	if cam2:
		cam2.global_position = Vector3(4, 9, -6)
		cam2.look_at(Vector3(0, 0, 7), Vector3.UP)
	for i in range(3): await process_frame
	_diag("camera repositioned wide, about to screenshot")

	root.get_texture().get_image().save_png("%s/missiles_and_miss_puffs_wide.png" % out_dir)
	_diag("wide screenshot saved")

	# Advance a few physics ticks so the guided missile visibly travels, then
	# grab a closer follow shot.
	for i in range(12):
		await physics_frame
		_diag("physics tick %d" % i)
	if cam2:
		cam2.global_position = Vector3(2, 5, 4)
		cam2.look_at(Vector3(0, 0, 8), Vector3.UP)
	for i in range(3): await process_frame
	root.get_texture().get_image().save_png("%s/missile_midflight_close.png" % out_dir)
	_diag("close screenshot saved - done")

	quit(0)
