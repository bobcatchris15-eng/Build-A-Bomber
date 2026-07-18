extends SceneTree
# Scratch: investigates whether hull_faction_material.gdshader's disabled
# tex_albedo line (a debug leftover found while root-causing an unrelated
# "whole game looks glossy" report - see DECISIONS_NEEDED.md) means the
# real per-faction baked texture was ever actually visible in gameplay, or
# whether the earlier "verified via real screenshots" claim
# (progress_captures/2026-07-13/faction_textures/) was looking at something
# else entirely. Uses BlueprintManager.reconstruct_vehicle() directly - the
# exact same call MainLab.tscn's own runtime code makes - so the hull mesh/
# material this produces is pixel-for-pixel what the real Design Lab shows;
# only the surrounding UI chrome and camera are different from a literal
# app screenshot, and neither of those affects whether the shader bug is
# visible.
#
# Faction choice is deliberate: bayou_irregulars' "blotch" overlay_style
# (tools/generate_faction_textures.gd) touches ONLY albedo, not roughness
# or height - the purest possible isolation of whether tex_albedo is
# live. salvage_union's "patch" overlay ALSO nudges roughness, so it's a
# partial-visibility case. industrialists has no overlay at all - it's the
# "generic ink panel-lines + rivets" baseline every faction shares.
#
# Must run WITHOUT --headless. Run BEFORE and AFTER the shader fix with the
# SAME filename (script overwrites), renaming the output directory between
# runs to keep both sets.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/verify_hull_albedo_fix.gd

const BlueprintManager = preload("res://scripts/blueprint_manager.gd")

const OUT_DIR = "res://progress_captures/2026-07-17/hull_albedo_fix"

func _make_world() -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 1.2
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.36, 0.38)
	env.ambient_light_energy = 0.9
	env_node.environment = env
	world.add_child(env_node)
	return world

func _capture_faction(faction: String, fname: String) -> void:
	var w = _make_world()
	var cam = Camera3D.new()
	w.add_child(cam)
	# Close-up on the top/near panel, matching industrialists_normal_scale.png's
	# framing distance closely enough to be a fair comparison.
	cam.look_at_from_position(Vector3(2.2, 2.0, 2.6), Vector3(0, 0.6, 0), Vector3.UP)
	var bp_manager = BlueprintManager.new()
	w.add_child(bp_manager)
	var parent = Node3D.new()
	w.add_child(parent)
	bp_manager.reconstruct_vehicle({
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": faction, "modules": [],
	}, parent, false)
	for i in range(6): await process_frame
	root.get_texture().get_image().save_png(OUT_DIR + "/" + fname)
	print("[CAPTURE] saved ", fname)
	w.queue_free()
	await process_frame

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _capture_faction("industrialists", "industrialists.png")
	await _capture_faction("salvage_union", "salvage_union.png")
	await _capture_faction("bayou_irregulars", "bayou_irregulars.png")
	await _capture_faction("glacier_syndicate", "glacier_syndicate.png")
	quit(0)
