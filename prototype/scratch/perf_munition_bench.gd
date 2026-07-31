extends SceneTree
# Isolates WHICH part of auto_weapon.gd's per-shot munition allocation costs
# the frame time that scratch/perf_probe.gd's 'churn' config measured
# (mean 102ms / p95 285ms at 8 units, vs 20ms for the same units idle).
#
# Every _fire_* / _spawn_explosion_visual in auto_weapon.gd builds, per
# projectile: a fresh MeshInstance3D, a fresh primitive Mesh (CylinderMesh /
# SphereMesh), a fresh StandardMaterial3D, and a Tween. _fire_flame_spray()
# does all four SIX times per trigger pull, at fire_rate 0.06.
#
# A fresh primitive Mesh is the expensive one on paper - it generates vertex
# data on the CPU and uploads a new vertex buffer to the GPU - but a fresh
# StandardMaterial3D also forces a new uniform set / descriptor allocation per
# projectile. This benchmark separates them so the fix targets whichever
# actually dominates, instead of assuming.
#
# Four patterns, identical visible output, same spawn rate (100/frame for 180
# frames - roughly the aggregate munition rate of 8 churn-loadout units):
#
#   current  - new MeshInstance3D + new Mesh + new Material   (what ships now)
#   mesh     - new MeshInstance3D + SHARED Mesh + new Material
#   mat      - new MeshInstance3D + new Mesh + SHARED Material
#   shared   - new MeshInstance3D + SHARED Mesh + SHARED Material
#
# current->mesh isolates the per-projectile Mesh cost.
# current->mat  isolates the per-projectile Material cost.
# shared shows the combined ceiling of the cheap (non-pooling) fix.
#
# Must run WITHOUT --headless - the whole question is GPU resource churn.
#
# Usage:
#   ./Godot_v4.3-stable_win64_console.exe --script scratch/perf_munition_bench.gd --path . -- current
#   ...                                                                                  -- mesh
#   ...                                                                                  -- mat
#   ...                                                                                  -- shared

const SPAWN_PER_FRAME := 100
const FRAMES := 180
const LIFETIME := 0.35  # matches _fire_flame_spray()'s flight duration

var _shared_mesh: SphereMesh
var _shared_mat: StandardMaterial3D

func _init():
	var pattern := "current"
	for arg in OS.get_cmdline_user_args():
		if arg in ["current", "mesh", "mat", "shared"]:
			pattern = arg

	print("=== munition bench: pattern '%s' ===" % pattern)

	# Minimal real 3D scene - no terrain, no units, no combat logic. The only
	# thing under measurement is munition allocation and rendering.
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world

	var cam = Camera3D.new()
	cam.position = Vector3(0, 6, 18)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	world.add_child(cam)

	var light = DirectionalLight3D.new()
	light.rotation = Vector3(-1.0, -0.6, 0.0)
	world.add_child(light)

	_shared_mesh = SphereMesh.new()
	_shared_mat = StandardMaterial3D.new()
	_shared_mat.albedo_color = Color(1.0, 0.35, 0.0)
	_shared_mat.emission_enabled = true
	_shared_mat.emission = _shared_mat.albedo_color

	for i in range(10): await process_frame

	var frame_ms: Array = []
	var last := Time.get_ticks_usec()
	for f in range(FRAMES):
		for i in range(SPAWN_PER_FRAME):
			_spawn(world, pattern)
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now

	# Discard the first 30 frames: nothing has begun expiring yet, so the
	# scene is still filling toward its steady-state live-munition count.
	var steady := frame_ms.slice(30)
	print("\n--- pattern '%s': %d spawns/frame over %d frames ---" % [pattern, SPAWN_PER_FRAME, FRAMES])
	_report("frame time (ms)", steady)
	var total := 0.0
	for s in steady: total += s
	print("  implied fps: %.1f" % (1000.0 / (total / steady.size())))
	print("  live nodes:  ", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("  static memory (MB): %.1f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	quit(0)

# Mirrors _spawn_explosion_visual()/_fire_flame_spray()'s structure exactly -
# same node type, same tween shape, same lifetime - varying only which
# resources are freshly allocated per projectile.
func _spawn(parent: Node3D, pattern: String) -> void:
	var inst = MeshInstance3D.new()

	if pattern == "mesh" or pattern == "shared":
		inst.mesh = _shared_mesh
	else:
		inst.mesh = SphereMesh.new()

	if pattern == "mat" or pattern == "shared":
		inst.material_override = _shared_mat
	else:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.35, 0.0)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		inst.material_override = mat

	inst.scale = Vector3(0.15, 0.15, 0.15)
	parent.add_child(inst)
	inst.position = Vector3(randf_range(-8, 8), randf_range(0, 4), randf_range(-8, 8))

	var dest = inst.position + Vector3(randf_range(-4, 4), 1.0, randf_range(-4, 4))
	var tween = inst.create_tween()
	tween.tween_property(inst, "position", dest, LIFETIME)
	tween.parallel().tween_property(inst, "scale", Vector3(0.45, 0.45, 0.45), LIFETIME * 0.4)
	tween.finished.connect(func():
		if is_instance_valid(inst): inst.queue_free()
	)

func _report(label: String, samples: Array) -> void:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in sorted: total += s
	print("  %s  mean %7.2f   median %7.2f   p95 %7.2f   max %7.2f" % [
		label,
		total / sorted.size(),
		sorted[int(sorted.size() * 0.5)],
		sorted[int(sorted.size() * 0.95)],
		sorted[sorted.size() - 1],
	])
