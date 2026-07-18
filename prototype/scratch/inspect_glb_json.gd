extends SceneTree
# Scratch: parses a .glb file's raw JSON chunk directly (bypassing Godot's
# own scene importer entirely) to check how many primitives/materials
# Blender's glTF exporter actually wrote - isolates whether a "only 1
# surface" result is a Blender export bug or a Godot import bug.
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script scratch/inspect_glb_json.gd -- <path>

func _init():
	var path = "res://assets/models/hulls/medium_hull.glb"
	for arg in OS.get_cmdline_user_args():
		path = arg
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		print("[INSPECT] could not open ", path)
		quit(1)
		return
	f.get_32() # magic
	f.get_32() # version
	f.get_32() # total length
	var chunk_len = f.get_32()
	var chunk_type = f.get_32() # 0x4E4F534A = "JSON"
	var json_bytes = f.get_buffer(chunk_len)
	var json_text = json_bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(json_text)
	print("[INSPECT] materials: ", parsed.get("materials", []).size())
	for i in range(parsed.get("materials", []).size()):
		print("  material ", i, ": ", parsed.materials[i].get("name", "?"))
	var meshes = parsed.get("meshes", [])
	print("[INSPECT] meshes: ", meshes.size())
	for i in range(meshes.size()):
		var prims = meshes[i].get("primitives", [])
		print("  mesh ", i, " primitives: ", prims.size())
		for p in prims:
			print("    primitive material index: ", p.get("material", "none"))
	quit(0)
