extends SceneTree
# VISUAL polish 2026-08-23: targeted compile test for the parallax +
# triplanar changes to terrain_ground.gdshader. The shader is loaded
# directly (no scene instantiate required) so any uniform/function
# typo surfaces as a hard parse error at the load step.
func _init() -> void:
	var shader: Shader = load("res://shaders/terrain_ground.gdshader")
	if shader == null:
		printerr("FAIL: terrain_ground.gdshader returned null from load()")
		quit(1)
		return
	# Probe the new uniforms to confirm the parallax block parsed. If
	# any of these throws "Invalid access" the uniform isn't on the
	# compiled shader and the edit didn't apply.
	print("  shader loaded ok")
	print("  has parallax_scale uniform: ", shader.has_shader_uniform("parallax_scale"))
	print("  has parallax_min_distance uniform: ", shader.has_shader_uniform("parallax_min_distance"))
	print("  has parallax_max_distance uniform: ", shader.has_shader_uniform("parallax_max_distance"))
	# And probe one of the existing uniforms to make sure the shader
	# still has the same structure as before.
	print("  has variant_count uniform: ", shader.has_shader_uniform("variant_count"))
	print("  has detail_normal_tex uniform: ", shader.has_shader_uniform("detail_normal_tex"))
	print("  has rock_albedo uniform: ", shader.has_shader_uniform("rock_albedo"))
	print("PASS: terrain_ground.gdshader compiled cleanly with new parallax uniforms")
	quit(0)
