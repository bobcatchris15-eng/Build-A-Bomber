extends SceneTree
# Quick env-only check. Load Battle.tscn, find the Environment resource,
# print the values, and quit. No physics loop, no full _ready.

func _init():
	var packed := load("res://scenes/Battle.tscn") as PackedScene
	if packed == null:
		print("[FAIL] could not load Battle.tscn")
		quit(1)
		return
	# Find the Environment sub_resource. Walk the scene state directly.
	var state := packed.get_state()
	if state == null:
		print("[FAIL] packed.get_state() returned null")
		quit(1)
		return
	for i in range(state.get_node_count()):
		var node_name := state.get_node_name(i)
	# Cleaner path: just instantiate and read the env via runtime.
	var scene := packed.instantiate()
	root.add_child(scene)
	for child in scene.get_children():
		if child is WorldEnvironment:
			var env: Environment = child.environment
			print("tonemap_mode=%d" % env.tonemap_mode)
			print("sdfgi_enabled=%s" % str(env.sdfgi_enabled))
			print("ssil_enabled=%s" % str(env.ssil_enabled))
			print("volumetric_fog_enabled=%s" % str(env.volumetric_fog_enabled))
			print("adjustment_saturation=%.2f" % env.adjustment_saturation)
			print("ambient_light_source=%d" % env.ambient_light_source)
			print("ssao_enabled=%s ssao_radius=%.2f" % [str(env.ssao_enabled), env.ssao_radius])
			break
	scene.queue_free()
	quit(0)
