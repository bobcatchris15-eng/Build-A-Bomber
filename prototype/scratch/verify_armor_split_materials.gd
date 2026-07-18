extends SceneTree
# Scratch: confirms the real spawn pipeline (BlueprintManager.
# reconstruct_vehicle) actually assigns two DIFFERENT materials with the
# expected metallic/roughness values to a re-authored hull's two surfaces,
# not just that surface_count == 2.
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/verify_armor_split_materials.gd

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")

func _init():
	for hull_type in ["interceptor_hull", "pillbox_foundation", "tower_foundation", "fortress_wall_foundation", "flying_wing_hull", "fuselage_hull", "airship_hull"]:
		var bp_manager = BlueprintManager.new()
		root.add_child(bp_manager)
		var parent = Node3D.new()
		root.add_child(parent)
		var hull = bp_manager.reconstruct_vehicle({
			"version": 1.0, "hull_type": hull_type,
			"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
			"armor_material": "hardened_steel", "armor_thickness": 1.0,
			"faction": "industrialists", "modules": [],
		}, parent, false)
		var mesh_inst = hull.get_node_or_null("MeshInstance3D") as MeshInstance3D
		var surf_count = mesh_inst.mesh.get_surface_count() if mesh_inst and mesh_inst.mesh else -1
		var mat0 = mesh_inst.get_surface_override_material(0) if mesh_inst else null
		var mat1 = mesh_inst.get_surface_override_material(1) if mesh_inst and surf_count > 1 else null
		print("--- ", hull_type, " ---")
		print("  surface_count: ", surf_count)
		if mat0:
			print("  surface 0 metallic=", mat0.get_shader_parameter("metallic"), " roughness=", mat0.get_shader_parameter("roughness"), " anisotropy=", mat0.get_shader_parameter("anisotropy"))
		if mat1:
			print("  surface 1 metallic=", mat1.get_shader_parameter("metallic"), " roughness=", mat1.get_shader_parameter("roughness"), " anisotropy=", mat1.get_shader_parameter("anisotropy"))
		parent.queue_free()
		bp_manager.queue_free()
	quit(0)
