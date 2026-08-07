extends SceneTree
# WHAT ONE UNIT COSTS TO DRAW.
#
# probe_perf_drift.gd ruled out a leak: node count tracks live unit count and
# plateaus. What it also showed is the ratio - roughly SIXTY NODES PER UNIT.
# That is the number worth chasing, because headless cannot see the renderer
# and a kitbashed unit is, by construction, a pile of separate meshes.
#
# Two costs hide in that pile and they are different problems:
#
#   DRAW CALLS   one per surface per MeshInstance3D. Cheap individually,
#                murderous in aggregate, and shadows pay it a second time.
#
#   UNIQUE MATERIALS   the one that actually bites. Godot batches by material;
#                two meshes sharing a ShaderMaterial can be instanced, two
#                meshes with EQUIVALENT-BUT-SEPARATE materials cannot. Every
#                ShaderMaterial.new() is a fresh RID, a fresh uniform set, and
#                a hard batch break. hull_material_builder.gd caches TEXTURES
#                but builds a new material on every single call.
#
# So: spawn one real unit and count both, plus how many of those materials are
# actually distinct in CONTENT rather than in identity. If content-distinct is
# far below identity-distinct, the fix is a material cache, not a mesh budget.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_unit_render_cost.gd

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")


func _init():
	await process_frame

	var battle = preload("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await process_frame
		guard += 1
	if not battle.world_is_ready:
		print("[FAIL] Battle never built its world")
		quit(1)
		return

	print("=== PER-UNIT RENDER COST ===")
	print("%-24s %7s %7s %7s %7s %7s"
		% ["design", "nodes", "meshes", "surf", "mat_ids", "mat_uniq"])

	for design in battle.roster:
		var unit = battle.spawn_unit(design, battle.PLAYER_TEAM, Vector3(0, 0, 0))
		await process_frame
		await process_frame
		if unit == null or not is_instance_valid(unit):
			continue

		var stats := {"nodes": 0, "meshes": 0, "surfaces": 0}
		var ids := {}
		var fingerprints := {}
		_tally(unit, stats, ids, fingerprints)

		print("%-24s %7d %7d %7d %7d %7d"
			% [str(design.get("name", "?")).substr(0, 24), stats.nodes,
				stats.meshes, stats.surfaces, ids.size(), fingerprints.size()])

		unit.queue_free()
		await process_frame

	print("")
	print("mat_ids  = distinct material OBJECTS (each one breaks batching)")
	print("mat_uniq = distinct material CONTENT (what it could be, cached)")

	battle.queue_free()
	await process_frame
	quit(0)


func _tally(node: Node, stats: Dictionary, ids: Dictionary, prints: Dictionary) -> void:
	stats.nodes += 1
	if node is MeshInstance3D and node.mesh != null:
		stats.meshes += 1
		var n_surf: int = node.mesh.get_surface_count()
		stats.surfaces += n_surf
		_record(node.material_override, ids, prints)
		for i in range(n_surf):
			_record(node.get_surface_override_material(i), ids, prints)
			_record(node.mesh.surface_get_material(i), ids, prints)
	for c in node.get_children():
		_tally(c, stats, ids, prints)


# Identity vs content. get_instance_id() is the batching-relevant one; the
# fingerprint is what the material WOULD collapse to if it were shared.
func _record(mat: Material, ids: Dictionary, prints: Dictionary) -> void:
	if mat == null:
		return
	ids[mat.get_instance_id()] = true
	prints[_fingerprint(mat)] = true


func _fingerprint(mat: Material) -> String:
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		var parts: Array = []
		var shader_id := 0 if sm.shader == null else sm.shader.get_instance_id()
		parts.append("shader:%d" % shader_id)
		if sm.shader != null:
			for u in sm.shader.get_shader_uniform_list():
				parts.append("%s=%s" % [u.name, str(sm.get_shader_parameter(u.name))])
		return "|".join(parts)
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		return "std|%s|%.3f|%.3f" % [str(bm.albedo_color), bm.metallic, bm.roughness]
	return str(mat.get_class())
