extends CanvasLayer
# In-match performance overlay. Toggle with F3 during a real Skirmish.
#
# WHY THIS EXISTS. The offline harnesses (scratch/perf_matrix.gd,
# scratch/perf_probe.gd) cannot reproduce the slowdown Chris reports at 6-8
# engaged units: in perf_matrix, 8 units in sustained combat measured 15.4ms
# against 15.3ms for a completely empty map - i.e. no measurable unit cost at
# all. Either the harness is missing something real play does (units under
# move orders and pathfinding, the live HUD and minimap, enemy AI, fog
# updates, production, actual deaths) or the slowdown is situational. Rather
# than keep guessing at scenarios, this puts the numbers on screen during the
# real match where the problem actually happens.
#
# WHAT IT REPORTS AND WHY THESE FIELDS.
#   frame ms mean/p95/worst - frame INTERVAL measured here per frame, from
#     Time.get_ticks_usec(), NOT Performance.TIME_PROCESS. Godot's Performance
#     monitors refresh on their own ~1Hz cadence, so sampling them per frame
#     returns the same stale value repeatedly - that mistake produced "81ms of
#     _process alongside 35fps" in the first measurement pass. Anything that
#     must be accurate per frame is timed directly here; monitors are only
#     read for counters where staleness is harmless.
#   hitches - frames over 33ms and over 50ms in the last second. This is the
#     field to watch: a stutter that makes the game FEEL broken often barely
#     moves the mean while spiking the worst-frame and hitch counts. Mean
#     frame time alone hid exactly this during the investigation.
#   draws/objects - if these climb with unit count while frame time does not,
#     draw-call/mesh-baking work has no headroom to recover and is not worth
#     doing.
#   munitions - live transient combat visuals, to confirm whether a slowdown
#     coincides with projectile volume.
#   vsync/msaa/scale - shown because they dominate the baseline: at 1920x1080+
#     with the project's msaa_3d=2 (4x), MSAA alone measured ~31% of frame
#     time on an empty map, and vsync-on pins everything to exactly 60.0fps,
#     which silently masks real regressions until they exceed 16.7ms.

const WINDOW_SEC := 1.0

var _label: Label = null
var _samples: Array[float] = []
var _last_usec: int = 0
var _accum: float = 0.0
var _hitch_33: int = 0
var _hitch_50: int = 0
var _shown_33: int = 0
var _shown_50: int = 0

func _ready() -> void:
	layer = 128 # above the match HUD
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -330
	panel.offset_top = 74 # clear of skirmish.gd's 68px top info strip
	panel.offset_right = -8
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# HUDPanel, the recessed plate the rest of the in-match chrome uses. The old
	# inline box was a 62%-opacity pure black with hand-picked margins, which is the
	# generic "debug overlay" look rather than part of this interface.
	panel.theme_type_variation = "HUDPanel"
	add_child(panel)

	_label = Label.new()
	# StatLabel puts the numbers on the mono face, which is what a per-frame
	# readout wants - proportional digits make a changing FPS counter jitter
	# sideways. Replaces a pale-green tint that appears nowhere in ui_tokens.gd.
	_label.theme_type_variation = "StatLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)

	_last_usec = Time.get_ticks_usec()

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_samples.append(ms)
	if ms > 33.0: _hitch_33 += 1
	if ms > 50.0: _hitch_50 += 1

	# Refresh the text once a second. Sampling stays per-frame (above) so
	# hitches inside the second are still counted, but rebuilding the string
	# every frame would make the overlay a measurable cost of its own.
	_accum += delta
	if _accum < WINDOW_SEC:
		return
	_accum = 0.0
	_shown_33 = _hitch_33
	_shown_50 = _hitch_50
	_hitch_33 = 0
	_hitch_50 = 0

	var sorted := _samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in sorted: total += s
	var mean: float = total / max(1, sorted.size())
	var p95: float = sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0
	var worst: float = sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0
	_samples.clear()

	var vp := get_viewport()
	var tree := get_tree()
	var units := 0
	for u in tree.get_nodes_in_group("units"):
		if is_instance_valid(u) and not ("is_dead" in u and u.is_dead):
			units += 1

	var vsync_on := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED

	_label.text = "\n".join([
		"frame  mean %5.1f  p95 %5.1f  worst %5.1f ms" % [mean, p95, worst],
		"fps    %5.1f%s" % [1000.0 / max(0.001, mean), "   (vsync capped)" if vsync_on else ""],
		"hitch  >33ms: %-3d  >50ms: %-3d  (per sec)" % [_shown_33, _shown_50],
		"phys   %5.2f ms   (1Hz monitor)" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"draws  %-6d objects %-6d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)],
		"nodes  %-6d orphans %-4d" % [
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)],
		"units  %-4d  munitions %-4d" % [units, _count_munitions()],
		"msaa   %s   scale %.2f   %dx%d" % [
			["off", "2x", "4x", "8x"][int(vp.msaa_3d)] if int(vp.msaa_3d) < 4 else "?",
			vp.scaling_3d_scale,
			int(vp.get_visible_rect().size.x), int(vp.get_visible_rect().size.y)],
	])

# Transient combat visuals are parented to the scene root by auto_weapon.gd's
# _effects_parent(), so a bare MeshInstance3D child of the scene is a munition
# (units and buildings are CharacterBody3D/StaticBody3D/Node3D roots).
func _count_munitions() -> int:
	var scene := get_tree().current_scene
	if not scene:
		return 0
	var n := 0
	for child in scene.get_children():
		if child is MeshInstance3D or child is GPUParticles3D:
			n += 1
	return n
