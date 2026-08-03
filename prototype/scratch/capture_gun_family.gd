extends SceneTree
# Visual capture: the re-authored autocannon, and the guns it has to belong with.
#
# Chris, 2026-08-03: the autocannon needed "buffer tubes and mechanical parts
# projecting backwards from the trunnion" to fit in with the machine gun /
# rifle / cannon. scratch/probe_autocannon_mesh.gd confirms the rear now reaches
# as far as its siblings'; only a picture shows whether it READS as the same
# kind of hardware.
#
# ONE GUN PER IMAGE, tightly framed. Two earlier attempts put the whole family
# in one shot: spaced along X the "profile" camera looked straight down the row
# and rendered one gun hiding four, and once respaced along Z the guns are long
# enough (1.4+ units) that at any framing close enough to read the rear
# hardware, the neighbours intrude into shot. Comparison is better served by
# identical framing across separate images than by one crowded group.
#
# Lit hard on a mid-grey backdrop on purpose: these parts are authored at
# 0.13-0.24 luminance, and under softer light the whole family renders as black
# blobs - which is what the first attempt produced.
#
# Must run WITHOUT --headless: it reads back the rendered framebuffer.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_gun_family.gd

const OUT_DIR = "res://progress_captures/2026-08-03-autocannon"
const VisualBuilder = preload("res://scripts/visual_builder.gd")

# The autocannon first so its two images sort to the top, then the family in the
# order they most need comparing against it.
const GUNS := ["autocannon", "anti_materiel_rifle", "heavy_machine_gun", "basic_cannon"]

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1500, 800))
	root.content_scale_size = Vector2i(1500, 800)
	await process_frame

	for i in range(GUNS.size()):
		var gun: String = GUNS[i]
		var scene := _make_scene()
		var holder := Node3D.new()
		scene.add_child(holder)
		VisualBuilder.build_visual(gun, holder, Vector3(0.4, 0.4, 0.4), Color(0.46, 0.48, 0.46), {})
		for _f in range(3):
			await process_frame

		var cam := Camera3D.new()
		cam.fov = 40.0
		scene.add_child(cam)

		# Framed on the BREECH end, not the whole gun: the barrel is ~1.4 long
		# and would force the camera so far back that the rear hardware - the
		# entire point of this pass - becomes a few dark pixels.
		var focus := Vector3(0, 0.24, 0.10)

		cam.position = focus + Vector3(1.30, 0.16, 0.30)
		cam.look_at(focus, Vector3.UP)
		await _shot(cam, "%02d_%s_side" % [i * 2 + 1, gun])

		cam.position = focus + Vector3(0.72, 0.34, 1.05)
		cam.look_at(focus, Vector3.UP)
		await _shot(cam, "%02d_%s_rear_quarter" % [i * 2 + 2, gun])

		scene.queue_free()
		await process_frame

	print("[CAPTURE] done -> %s" % OUT_DIR)
	quit()

func _make_scene() -> Node3D:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.44, 0.45, 0.47)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.74, 0.76, 0.80)
	e.ambient_light_energy = 1.8
	env.environment = e
	scene.add_child(env)

	for spec in [[Vector3(-32, 128, 0), 3.1], [Vector3(-10, -40, 0), 1.6], [Vector3(-68, 210, 0), 1.0]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_energy = spec[1]
		scene.add_child(l)
	return scene

func _shot(cam: Camera3D, name: String) -> void:
	cam.make_current()
	for _i in range(6):
		await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[CAPTURE] %s" % name)
