extends SceneTree
# Scratch: baseline screenshots of the CURRENT interface, taken before any
# redesign work so the "after" has something honest to be compared against.
#
# Deliberately captures the shell screens only (MainMenu / MapSelect /
# MatchSetup / MainLab). Skirmish is skipped: it needs a generated map, a
# faction, and a live match to look like anything, and booting one from a
# bare SceneTree reliably produces a screenshot of a half-built world that
# says more about the harness than about the UI.
#
# Must run WITHOUT --headless (needs a real framebuffer to screenshot).
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/capture_ui_baseline.gd

const OUT_DIR = "res://progress_captures/2026-07-30/ui_pass12"

const SCREENS = [
	{"name": "main_menu", "path": "res://scenes/MainMenu.tscn"},
	{"name": "map_select", "path": "res://scenes/MapSelect.tscn"},
	{"name": "match_setup", "path": "res://scenes/MatchSetup.tscn"},
	{"name": "main_lab", "path": "res://scenes/MainLab.tscn"},
]

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# 1600x900: close to the aspect the game actually ships at, so panel
	# anchoring and overflow read the same here as in play. A default small
	# window would hide exactly the layout problems worth finding.
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.content_scale_size = Vector2i(1600, 900)
	await process_frame

	for screen in SCREENS:
		await _capture(screen["name"], screen["path"])
	print("Baseline captures written to ", OUT_DIR)
	quit(0)

func _capture(name: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		print("  SKIP %s (missing %s)" % [name, path])
		return
	var packed = load(path) as PackedScene
	if packed == null:
		print("  SKIP %s (not a PackedScene)" % name)
		return

	var inst = packed.instantiate()
	root.add_child(inst)
	current_scene = inst

	# These screens build themselves in _ready() and several fetch icons and
	# fonts off disk on first use, so one frame is not enough - an early grab
	# catches unstyled controls and reads as a far worse UI than what ships.
	for i in range(12):
		await process_frame

	var img = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("  wrote %s.png" % name)

	inst.queue_free()
	await process_frame
