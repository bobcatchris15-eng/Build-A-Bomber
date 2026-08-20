extends Node
# Screenshots the battle HUD, and reports on it in text.
#
# WHY THIS EXISTS. tools/capture_battle.gd renders the world and nothing else -
# run it and the HUD is absent from the PNG - so there has been no way to look at
# the in-match interface without playing the game. That is a bad position to
# iterate a HUD from, and it is the reason a build with two production panels
# stacked on each other could survive.
#
# WHAT IT DOES DIFFERENTLY. It waits for world_ready like capture_battle does,
# then it also:
#   - forces a fixed window size, so two captures are comparable
#   - drives the HUD into a non-empty state (selects the player's units, queues
#     a couple of jobs) before shooting, because an empty HUD hides most of its
#     own layout bugs
#   - prints a node-tree report with each region's rect, so an off-screen or
#     zero-sized panel shows up as a number rather than as a missing pixel
#   - counts the tactical map's fog states, which is the one part of the HUD
#     whose correctness is not visible at a glance in a screenshot
#
# Usage, from prototype/:
#   ./Godot_v4.7.1-stable_win64_console.exe --path . res://tools/capture_hud.tscn
#
# NOT headless. get_viewport().get_texture() needs a real rasterizer; under
# --headless it returns an empty image and the capture silently succeeds with
# nothing in it.

const OUT_DIR := "res://visual_regression/captures"
const WIDTH := 1920
const HEIGHT := 1080


func _ready() -> void:
	var win := get_window()
	win.size = Vector2i(WIDTH, HEIGHT)
	await get_tree().process_frame

	var scene = load("res://scenes/Battle.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().process_frame

	if scene.has_signal("world_ready"):
		await scene.world_ready
	else:
		for _i in range(90):
			await get_tree().process_frame

	# Settle: the HUD lays out over a couple of frames as containers resolve,
	# and the deck populates from a signal.
	for _i in range(16):
		await get_tree().process_frame

	var hud = scene.get("hud")
	if hud == null:
		print("[capture_hud] FAIL: match_director.hud is null - the HUD did not build")
		get_tree().quit(1)
		return

	_populate(scene, hud)
	for _i in range(20):
		await get_tree().process_frame

	_report(hud)
	_report_fog(hud)
	_shoot("hud_full.png")

	# A second frame with a queue open on a different tab, so one run shows both
	# the unit palette and the structure palette.
	hud.deck.set_active("building")
	for _i in range(12):
		await get_tree().process_frame
	_shoot("hud_structures_tab.png")

	get_tree().quit()


# Puts the HUD into a state worth photographing: units selected, jobs queued.
func _populate(scene, hud) -> void:
	# SKIRMISH OPENS IN HQ-SITING MODE - the player places their own HQ before the
	# match proper starts (match_director._enter_hq_placement). Until that happens
	# there is genuinely no HQ, so the STRUCTURES and DEFENCE queues correctly
	# report "no contributor" and the map is 100% unexplored. Site it first.
	if scene.has_method("place_hq_for_human") and scene.is_placing_hq():
		# Clamp to the player's own base zone first. hq_ghost_pos starts at the
		# origin, which is the middle of the map and outside the zone, so
		# place_hq_for_human() refused it and the capture went on to photograph a
		# match with no HQ - every queue correctly reporting "no contributor".
		var at: Vector3 = scene.hq_ghost_pos
		if scene.has_method("_clamp_to_player_zone"):
			at = scene._clamp_to_player_zone(at)
		var placed: bool = scene.place_hq_for_human(at)
		print("[capture_hud] HQ siting at %s -> %s" % [str(at), str(placed)])
		if not placed:
			print("      ^^ HQ REFUSED - the capture will show a pre-HQ match")
		await get_tree().process_frame
		await get_tree().process_frame

	# A fresh match then has an HQ and one harvester, so every unit queue reports
	# "no manufactory" and every enqueue is refused. Plant one of each.
	if scene.has_method("_place_structure"):
		var hq_at := Vector3.ZERO
		var hqs: Array = scene.structures_of_kinds(scene.PLAYER_TEAM, ["hq"])
		if not hqs.is_empty():
			hq_at = hqs[0].global_position
		var offset := 18.0
		for kind in ["light_manufactory", "medium_manufactory", "heavy_manufactory"]:
			scene._place_structure(kind, scene.PLAYER_TEAM,
				hq_at + Vector3(offset, 0.0, 0.0))
			offset += 18.0
		print("[capture_hud] planted three manufactories near the HQ")

	# Reveal a band around the base so the map shows currently-visible,
	# explored-but-not-visible AND unexplored rather than one flat state.
	if scene.vision != null and scene.vision.has_method("reveal_area"):
		var centre := Vector3.ZERO
		var hqs2: Array = scene.structures_of_kinds(scene.PLAYER_TEAM, ["hq"])
		if not hqs2.is_empty():
			centre = hqs2[0].global_position
		for step in range(6):
			scene.vision.reveal_area(scene.PLAYER_TEAM,
				centre + Vector3(step * 26.0, 0.0, step * 14.0), 40.0, 0.6)
		scene.vision.tick()

	var units: Array = scene.get_team_units(scene.PLAYER_TEAM)
	if not units.is_empty() and scene.selection != null:
		scene.selection.set_selection(units)
		print("[capture_hud] selected %d player units" % units.size())
	else:
		print("[capture_hud] WARNING: no player units to select")

	# Queue whatever the light tier can actually build, so the queue strip and
	# the tab progress bars have something in them.
	if scene.production != null:
		var queued := 0
		for design in scene.roster:
			if scene.is_defence_design(design):
				continue
			var costing = load("res://scripts/battle/economy/design_costing.gd")
			var q: String = costing.queue_for_design(design)
			var cost: int = costing.blueprint_cost(design)
			var job: Dictionary = scene.production.enqueue_unit(
				scene.PLAYER_TEAM, design, cost, costing.build_time_for_cost(cost), q)
			if not job.is_empty():
				queued += 1
			if queued >= 4:
				break
		print("[capture_hud] queued %d jobs" % queued)

	# Put the camera on the base. Without this the capture is whatever the camera
	# happened to start at, which on a 480-unit map is usually unexplored ground -
	# a black frame that looks like a rendering bug rather than correct fog. Goes
	# through the HUD's own focus_camera_on(), so a capture also exercises the
	# minimap click-to-jump path.
	var hqs3: Array = scene.structures_of_kinds(scene.PLAYER_TEAM, ["hq"])
	if not hqs3.is_empty():
		hud.focus_camera_on(hqs3[0].global_position)
		print("[capture_hud] camera focused on the HQ at %s"
			% str(hqs3[0].global_position))

	if hud.alert_log != null:
		hud.alert_log.post("CAPTURE HARNESS ALERT", "alert",
			load("res://scripts/hud/hud_style.gd").WARN)
	if hud.hint_label != null:
		hud.hint_label.text = "PLACE REFINERY  -  LEFT CLICK TO SITE, RIGHT CLICK TO CANCEL"


# Every region, with its rect, so a zero-sized or off-screen panel is a number.
func _report(hud) -> void:
	print("\n[capture_hud] --- layout report ---")
	print("  HUDRoot            pos=%s size=%s scale=%s"
		% [str(hud.position), str(hud.size), str(hud.scale)])
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	print("  viewport           %s" % str(vp))
	print("  column             pos=%s size=%s (capped at %.0f)"
		% [str(hud.column.position.round()), str(hud.column.size.round()),
			hud.COLUMN_MAX_WIDTH])
	for pair in [["ribbon", hud.ribbon], ["alert_log", hud.alert_log],
			["minimap", hud.minimap], ["deck", hud.deck],
			["command_card", hud.command_card]]:
		var n = pair[1]
		if n == null:
			print("  %-18s MISSING" % pair[0])
			continue
		var r := Rect2(n.global_position, n.size)
		var onscreen := r.intersects(Rect2(Vector2.ZERO, vp))
		print("  %-18s pos=%s size=%s visible=%s onscreen=%s"
			% [pair[0], str(n.global_position.round()), str(n.size.round()),
				str(n.visible), str(onscreen)])
		if r.size.x < 1.0 or r.size.y < 1.0:
			print("      ^^ ZERO-SIZED - this region will not render")
		if not onscreen:
			print("      ^^ OFF SCREEN")

	# Overlap check between the three band regions. This is the specific failure
	# right_rail.gd was built to work around in the old HUD, so it is worth an
	# assertion rather than an eyeball.
	var regions := [["minimap", hud.minimap], ["deck", hud.deck],
		["command_card", hud.command_card]]
	for i in range(regions.size()):
		for j in range(i + 1, regions.size()):
			var a: Rect2 = Rect2(regions[i][1].global_position, regions[i][1].size)
			var b: Rect2 = Rect2(regions[j][1].global_position, regions[j][1].size)
			if a.intersects(b):
				var o := a.intersection(b)
				print("  OVERLAP: %s and %s overlap by %s"
					% [regions[i][0], regions[j][0], str(o.size.round())])


# Counts pixels in each fog band. A map that is all one band is either fully
# revealed or fully shrouded, and both look plausible in a thumbnail.
func _report_fog(hud) -> void:
	var img: Image = hud.minimap.map_image()
	if img == null:
		print("[capture_hud] no map image")
		return
	# Against the UNFOGGED terrain, not against an absolute luminance threshold.
	# The first cut of this compared each pixel's luminance to 0.5 and reported
	# zero bright pixels on a fully-revealed base - because forest terrain is
	# (0.11, 0.20, 0.12), luminance ~0.17, so every pixel was "dark" whatever the
	# fog was doing. The meaningful quantity is the RATIO to the same pixel
	# unfogged: ~1.0 visible, ~0.48 explored, ~0.06 unexplored.
	var terrain: Image = hud.minimap._terrain_image
	var mm = load("res://scripts/hud/hud_minimap.gd")
	var void_lum: float = load("res://scripts/hud/hud_style.gd").VOID.get_luminance()
	var v := 0
	var e := 0
	var u := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var lum: float = img.get_pixel(x, y).get_luminance()
			var base: float = maxf(terrain.get_pixel(x, y).get_luminance(), 0.001)
			# Bucket by which of the three PREDICTED values this pixel is
			# nearest, computed from the darkening constants and the actual VOID
			# colour. Fixed thresholds do not work here: VOID is not black, so
			# a fully-shrouded pixel over dark terrain still sits at a ratio of
			# ~0.4 and every guessed cut-off put it in the wrong bucket.
			var vl: float = base
			var el: float = void_lum * mm.FOG_EXPLORED_DARKEN 				+ base * (1.0 - mm.FOG_EXPLORED_DARKEN)
			var ul: float = void_lum * mm.FOG_UNEXPLORED_DARKEN 				+ base * (1.0 - mm.FOG_UNEXPLORED_DARKEN)
			var dv: float = absf(lum - vl)
			var de: float = absf(lum - el)
			var du: float = absf(lum - ul)
			if dv <= de and dv <= du:
				v += 1
			elif de <= du:
				e += 1
			else:
				u += 1
	var total: int = img.get_width() * img.get_height()
	print("[capture_hud] fog bands over %d px: visible=%d (%.1f%%) explored=%d (%.1f%%) unexplored=%d (%.1f%%)"
		% [total, v, 100.0 * v / total, e, 100.0 * e / total, u, 100.0 * u / total])
	if u == total:
		print("      ^^ the whole map is unexplored - fog is not being lifted")
	if v == 0:
		print("      ^^ nothing reads as currently visible - the shroud is not clearing")
	if u == 0 and e == 0:
		print("      ^^ no fog at all - reveal_all is on, or the shroud is not being read")


func _shoot(filename: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := OUT_DIR + "/" + filename
	img.save_png(ProjectSettings.globalize_path(path))
	print("[capture_hud] saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
