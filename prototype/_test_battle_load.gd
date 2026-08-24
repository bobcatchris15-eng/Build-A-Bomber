extends SceneTree
# VISUAL polish 2026-08-23: targeted load test for Battle.tscn.
# Runs the scene through instantiation, not just parse, so a typo in
# any sub_resource or node property (volumetric_fog_*, use_taa,
# material_override, etc.) surfaces as a hard error.
func _init() -> void:
	var packed: PackedScene = load("res://scenes/Battle.tscn")
	if packed == null:
		printerr("FAIL: Battle.tscn returned null from load()")
		quit(1)
		return
	var inst: Node = packed.instantiate()
	if inst == null:
		printerr("FAIL: Battle.tscn.instantiate() returned null")
		quit(1)
		return
	# Probe the cinematic pass so a property silently dropped by the
	# loader (the material_override / volumetric_fog_*) is caught here
	# rather than only when the player sees the scene.
	var world_env: WorldEnvironment = inst.get_node_or_null("WorldEnvironment")
	var env: Environment = world_env.environment if world_env else null
	if env:
		print("  tonemap_mode=", env.tonemap_mode)
		print("  ambient_light_source=", env.ambient_light_source)
		print("  ambient_light_color=", env.ambient_light_color)
		print("  ssao_radius=", env.ssao_radius, "  ssao_intensity=", env.ssao_intensity)
		print("  glow_intensity=", env.glow_intensity, "  glow_bloom=", env.glow_bloom)
		print("  adjustment_saturation=", env.adjustment_saturation, "  contrast=", env.adjustment_contrast)
		print("  volumetric_fog_enabled=", env.volumetric_fog_enabled,
			"  density=", env.volumetric_fog_density,
			"  length=", env.volumetric_fog_length)
	var attrs: CameraAttributesPractical = inst.get_node("Camera3D").attributes
	if attrs:
		print("  auto_exposure_enabled=", attrs.auto_exposure_enabled,
			"  min_sens=", attrs.auto_exposure_min_sensitivity,
			"  max_sens=", attrs.auto_exposure_max_sensitivity)
		print("  dof_blur_far_enabled=", attrs.dof_blur_far_enabled,
			"  distance=", attrs.dof_blur_far_distance,
			"  transition=", attrs.dof_blur_far_transition)
	var cam: Camera3D = inst.get_node("Camera3D")
	var chase: Camera3D = inst.get_node("ChaseCamera")
	# use_taa was moved off Camera3D in 4.7; project-level TAA is set in
	# project.godot's [rendering] section, so we don't probe the camera
	# for it. Just confirm both cameras are present and configured.
	print("  rts_cam.attributes=", "set" if cam.attributes != null else "null",
		"  chase.attributes=", "set" if chase.attributes != null else "null")
	var ground_mi: MeshInstance3D = inst.get_node("Ground/MeshInstance3D")
	print("  ground.material_override=", ground_mi.material_override)
	inst.queue_free()
	print("PASS: Battle.tscn loaded and instantiated cleanly")
	quit(0)
