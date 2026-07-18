extends SceneTree
# Scratch: prints how many mesh surfaces an authored hull .glb actually has
# once loaded through Godot's real import pipeline - the definitive check
# for whether the Blender build script's dual-material-slot authoring
# actually produced a second surface, independent of what the Blender
# export console log says.
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/check_hull_surfaces.gd -- <hull_name>

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

func _init():
	var hull_name = "medium_hull"
	for arg in OS.get_cmdline_user_args():
		hull_name = arg
	var mesh = MeshAssetLoader.get_hull_mesh(hull_name)
	if not mesh:
		print("[CHECK] No authored mesh found for ", hull_name)
		quit(1)
		return
	print("[CHECK] ", hull_name, " surface_count=", mesh.get_surface_count())
	for i in range(mesh.get_surface_count()):
		var mat = mesh.surface_get_material(i)
		print("  surface ", i, " material=", mat)
	quit(0)
