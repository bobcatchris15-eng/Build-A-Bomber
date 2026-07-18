extends SceneTree
# Scratch: verifies the ACTUAL shader parameter values on live
# ShaderMaterial instances built by HullMaterialBuilder - not just reading
# the .gdshader source, which only shows defaults, not what
# apply_hull_materials() actually sets at runtime.
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/check_live_shader_params.gd

const HullMaterialBuilder = preload("res://scripts/hull_material_builder.gd")

func _init():
	var armor = HullMaterialBuilder.build_hull_material("hardened_steel", "industrialists")
	var structural = HullMaterialBuilder.build_structural_material("industrialists")
	print("shader resource on armor: ", armor.shader, " path=", armor.shader.resource_path)
	print("shader resource on structural: ", structural.shader, " path=", structural.shader.resource_path)
	print("")
	for p in ["metallic", "roughness", "anisotropy", "base_color", "accent_color", "edge_ink_strength"]:
		print("armor.", p, " = ", armor.get_shader_parameter(p))
	print("")
	for p in ["metallic", "roughness", "anisotropy", "base_color", "accent_color", "edge_ink_strength"]:
		print("structural.", p, " = ", structural.get_shader_parameter(p))
	quit(0)
