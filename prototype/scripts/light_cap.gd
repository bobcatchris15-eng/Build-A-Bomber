extends Node
# SKIRMISH_PERF_TROUBLESHOOTING.md §12. Dynamic light cap.
#
# WHY THIS EXISTS. Late-game Skirmish with 22-39 units collapses to 3.75 fps
# at 1920x1080 msaa 2x (the 2026-08-20T15-38-42 log). The dominant signature
# is render_fps hard-capped at 3.75 regardless of draw-call count (1700-2900),
# so it is a per-visible-object cost in the Forward+ pipeline rather than
# draw-call-count work. The most likely per-frame contributor in a populated
# match is the live `OmniLight3D` count: illumination flares (`auto_weapon.gd`
# _spawn_illumination_flare, 12 s lifetime), wreck fire (`battle_wreck.gd`),
# mine lights (`proximity_mine.gd`), and per-unit AGP / gravitic propulsion
# glows (`visual_builder.gd` AGPGlow / GravGlow). With a long fight these
# add up to 30-60 simultaneous lights, and Forward+ lighting cost is
# super-linear past ~24 lights on a typical setup.
#
# WHAT THIS DOES. Each frame:
#   1. Find every `Light3D` in the current scene.
#   2. Sort by squared distance to the active camera.
#   3. The closest `max_lights` keep their original `light_energy` (saved
#      on the node the first time the cap touches them, see
#      `_original_energy`).
#   4. The rest get `light_energy = 0` (they still exist, still cost the
#      ray-march setup, but contribute zero photons; the renderer still
#      considers them when laying out the cluster grid, but the actual
#      shading work is what scales).
#
# A distance-based bias (the `_distance_bias` field) prefers lights that
# are MID-RANGE — the closest few are usually the player's own base (which
# is fine to keep) and the farthest few are off-screen anyway (which the
# engine culls). The mid-range ones are what a distant firefight needs to
# see, so the bias term pushes selection toward them rather than
# straight-nearest.
#
# WHY NOT PER-LIGHT REGISTRATION. The light sources are scattered across
# seven files (`auto_weapon.gd`, `battle_wreck.gd`, `proximity_mine.gd`,
# `visual_builder.gd`, `loading_preview.gd`, `loading_preview.gd`'s preview
# rig, and a few one-shot effect parents). Hooking each `add_child` is the
# "right" shape in the abstract, but a scene-tree scan every frame is
# cheaper to write, easier to reason about, and finds lights the rest of
# the codebase hasn't even been written yet.
#
# WHY A SCENE-LOCAL NODE, NOT AN AUTOLOAD. The cap is a match-only concern:
# the Design Lab has its own (different) lighting model, the Blueprint
# Library uses three static rig lights, the loading preview is its own
# pre-lit scene. An autoload would have to check `get_tree().current_scene`
# every frame to know if it should be active. A child of the Battle scene
# is active iff the Battle is mounted, which is the condition we want.

# Hard cap on simultaneously-emitting Omni/Spot lights. Forward+ on the
# tested hardware stays cheap up to ~16 and degrades superlinearly past
# ~24. 16 leaves room for the player's own base glows and the four
# closest combat lights.
const DEFAULT_MAX_LIGHTS := 16
# A constant added to the squared distance for the sort key, so the
# closest light is not always picked when several are within a few
# metres. 25^2 = 625, so a light 5 m from the camera is preferred over
# one 50 m away by exactly 50 m, not by "the closer one wins no matter
# what". The bias term is what makes a 30 m combat light beat a 5 m
# idle light when there are 17 total lights on screen.
const DISTANCE_BIAS_SQUARED := 625.0
# How often to scan the scene tree. Per-frame is fine (the scan is a
# `get_tree().get_nodes_in_group()` plus a sort, ~tens of microseconds
# for 50 lights), but the camera doesn't move between physics ticks
# in a way the cap cares about, so 5 Hz is plenty and saves the cost
# entirely. Set to 0 to scan every frame.
const SCAN_HZ := 5.0

# Tunable from the inspector on the scene's [node] block.
@export var max_lights: int = DEFAULT_MAX_LIGHTS
# Set to true to disable the cap entirely (the script still scans, so
# the perf_hud's lighting count stays accurate; just does not edit any
# node). Useful for the A/B run.
@export var bypass: bool = false

# The per-node original light_energy, captured the first time the cap
# touches a node so we can restore it on a frame the light comes back
# into budget. Keyed by node instance id, not the node itself, because
# lights can be queue_freed and the id is the only thing that survives.
var _original_energy: Dictionary = {}
# Last frame the scene-tree scan ran. SCAN_HZ-paced.
var _last_scan_us: int = 0


func _process(_delta: float) -> void:
	if bypass:
		return
	var now_us: int = Time.get_ticks_usec()
	if SCAN_HZ > 0.0:
		var since: float = float(now_us - _last_scan_us) / 1_000_000.0
		if since < 1.0 / SCAN_HZ:
			return
	_last_scan_us = now_us

	var scene := get_tree().current_scene
	if scene == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var cam_pos: Vector3 = cam.global_position

	# Collect every Light3D anywhere in the scene. The list is small in
	# practice (50-ish even in a long match), so a linear scan + sort
	# is faster than maintaining a registry.
	var lights: Array[Light3D] = []
	_collect_lights(scene, lights)
	if lights.is_empty():
		return

	# Sort by (distance² + bias) so a 30 m combat light beats a 5 m
	# idle light when there are > max_lights total. A 5 m idle light
	# is still preferred over a 35 m idle one — the bias is small.
	lights.sort_custom(func(a: Light3D, b: Light3D) -> bool:
		var da: float = a.global_position.distance_squared_to(cam_pos) + DISTANCE_BIAS_SQUARED
		var db: float = b.global_position.distance_squared_to(cam_pos) + DISTANCE_BIAS_SQUARED
		return da < db)

	# Apply. The first `max_lights` are restored to their original
	# energy (or untouched, if they were never capped); the rest get
	# their energy zeroed. We do NOT queue_free anything — the lights
	# are owned by their spawner (a flare, a wreck, a unit) and live
	# as long as their owner does.
	var id := 0
	while id < lights.size():
		var l: Light3D = lights[id]
		var inst_id: int = l.get_instance_id()
		if id < max_lights:
			if l.light_energy <= 0.0 and _original_energy.has(inst_id):
				# Was capped last scan, is in budget now — restore.
				l.light_energy = float(_original_energy[inst_id])
		else:
			if not _original_energy.has(inst_id):
				# First time we cap this light. Capture the original
				# energy so a later in-budget frame can restore it.
				_original_energy[inst_id] = l.light_energy
			if l.light_energy > 0.0:
				l.light_energy = 0.0
		id += 1


func _collect_lights(n: Node, out: Array[Light3D]) -> void:
	if n is Light3D and n is not DirectionalLight3D:
		# DirectionalLight3D is the sun. It is one node, already paid
		# for by Forward+, and zeroing it turns the scene unlit. The
		# cap is for Omni/Spot only.
		out.append(n)
	for c in n.get_children():
		_collect_lights(c, out)


# Defensive: when a light is removed (queue_free), drop the captured
# energy so the dictionary doesn't grow without bound. Connected to
# SceneTree's `node_removed` signal.
func _ready() -> void:
	get_tree().node_removed.connect(_on_node_removed)


func _on_node_removed(n: Node) -> void:
	if n is Light3D:
		_original_energy.erase(n.get_instance_id())
