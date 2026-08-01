extends SceneTree
# Scratch: reconstruct_vehicle() costs 50-450ms per battle-spawned unit
# (probe_load_phases.gd) - a main-thread stutter every time a manufactory
# finishes a unit, which is the in-skirmish "laggy with a dozen units"
# symptom once the navmesh freezes are gone.
#
# PERFORMANCE_PLAN.md P4 made units cheaper to DRAW (bake-at-spawn merges
# module meshes). It did not make them cheaper to BUILD, and P4d explicitly
# deferred build_running_gear() - flagged there as "one of the worst
# offenders (wheel hub x axle-count x 2 sides, each hub+driveshaft+gearbox)".
# This checks whether that is actually where the time goes before anyone
# optimises on the strength of that guess.
#
# Times, per blueprint: the whole reconstruct, then the individually
# attributable pieces (hull materials, greebles, decals, running gear, and
# per-module build_visual) so the biggest term is identified by measurement.
#
# Usage: ./godot.exe --script scratch/probe_spawn_breakdown.gd --path .

const BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")
const VisualBuilder = preload("res://scripts/visual_builder.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const HullMaterialBuilder = preload("res://scripts/hull_material_builder.gd")
const HullGreebles = preload("res://scripts/hull_greebles.gd")
const HullDecals = preload("res://scripts/hull_decals.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

func _init():
	var scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var bpm = BlueprintManagerScript.new()
	scene.add_child(bpm)

	var paths := []
	var dir = DirAccess.open("res://data/loadout")
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				paths.append("res://data/loadout/" + f)
	paths.sort()

	# Warm every cache first, so this measures steady-state per-spawn cost
	# (what a manufactory pays on unit #2 onward), not one-off asset loads.
	for p in paths:
		var d = bpm.load_blueprint(p)
		if not d.is_empty():
			var warm = Node3D.new()
			scene.add_child(warm)
			bpm.reconstruct_vehicle(d, warm, false, "industrialists")
			warm.queue_free()
	await process_frame

	print("=== warm per-spawn cost, and where it goes ===")
	for p in paths:
		var data = bpm.load_blueprint(p)
		if data.is_empty():
			continue
		var parent = Node3D.new()
		scene.add_child(parent)
		var t = Time.get_ticks_usec()
		bpm.reconstruct_vehicle(data, parent, false, "industrialists")
		var whole := _ms(t)

		# Attribute the per-module visual build on its own.
		var mods = data.get("modules", [])
		var mod_ms := 0.0
		var scratch_parent = Node3D.new()
		scene.add_child(scratch_parent)
		for mod in mods:
			var tid = mod.get("type_id", "")
			if tid == "" or not ModuleCatalog.module_exists(tid):
				continue
			var cd = ModuleCatalog.get_module_data(tid)
			var holder = Node3D.new()
			scratch_parent.add_child(holder)
			var t2 = Time.get_ticks_usec()
			VisualBuilder.build_visual(tid, holder, cd.get("size", Vector3.ONE), cd.color, mod.get("tweaks", {}))
			mod_ms += _ms(t2)

		# Running gear (P4d's suspect), built once per unit.
		var loc = data.get("locomotion", {}).get("type_id", "")
		var gear_ms := 0.0
		if ModuleCatalog.needs_running_gear(loc):
			var gear_host = Node3D.new()
			scratch_parent.add_child(gear_host)
			var t3 = Time.get_ticks_usec()
			VisualBuilder.build_running_gear(gear_host, Vector3(4, 1, 6), Color.GRAY, 0, loc)
			gear_ms = _ms(t3)

		# Hull skin passes.
		var hull_type = data.get("hull_type", "medium_hull")
		var hull_mesh = MeshAssetLoader.get_hull_mesh(hull_type)
		var skin_host = MeshInstance3D.new()
		skin_host.mesh = hull_mesh
		scratch_parent.add_child(skin_host)
		var t4 = Time.get_ticks_usec()
		HullMaterialBuilder.apply_hull_materials(skin_host, "hardened_steel", "industrialists")
		var mat_ms := _ms(t4)
		t4 = Time.get_ticks_usec()
		HullGreebles.apply_greebles(skin_host, "industrialists", Vector3(4, 2, 6))
		var greeble_ms := _ms(t4)
		t4 = Time.get_ticks_usec()
		HullDecals.apply_decals(skin_host, "industrialists", Vector3(4, 2, 6))
		var decal_ms := _ms(t4)

		print("  %-22s total %7.1f ms | %d modules %6.1f | gear(%s) %6.1f | mat %5.1f | greeble %5.1f | decal %5.1f"
			% [p.get_file(), whole, mods.size(), mod_ms, loc, gear_ms, mat_ms, greeble_ms, decal_ms])
		parent.queue_free()
		scratch_parent.queue_free()

	quit(0)

func _ms(t: int) -> float:
	return (Time.get_ticks_usec() - t) / 1000.0
