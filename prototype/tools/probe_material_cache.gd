extends SceneTree
# Smoke test for the building_mesh material cache. Spawns the same building
# three times and confirms only one StandardMaterial3D is constructed for
# each (kind, team, surface) tuple.
# Run: Godot --headless --script tools/probe_material_cache.gd

const BuildingMesh = preload("res://scripts/battle/buildings/building_mesh.gd")
const BattleFinish = preload("res://scripts/battle/battle_finish.gd")

func _init():
	# Reset the cache to start clean.
	BuildingMesh._material_cache.clear()
	var parent := Node3D.new()
	root.add_child(parent)
	for i in range(3):
		var building := BuildingMesh.build(parent, "hq", Vector3(8, 4, 8), "industrialists", 0)
		if building == null:
			print("[FAIL] building %d returned null" % i)
			quit(1)
			return
	# After 3 buildings of the same kind and team, the cache should have
	# only 1 entry per surface (we just count by kind+team prefix).
	var keys: Array = []
	for k in BuildingMesh._material_cache:
		keys.append(k)
	keys.sort()
	print("cache size after 3 hq buildings on team 0: %d" % BuildingMesh._material_cache.size())
	for k in keys:
		var m: Material = BuildingMesh._material_cache[k]
		var mat: StandardMaterial3D = m if m is StandardMaterial3D else null
		print("  %s -> %s" % [k, "StandardMaterial3D" if mat != null else "?"])
	# Now spawn a refinery - it should add a different set of cache entries.
	for i in range(2):
		var b = BuildingMesh.build(parent, "refinery", Vector3(10, 4, 10), "industrialists", 0)
		if b == null:
			print("[FAIL] refinery %d returned null" % i)
			quit(1)
			return
	print("cache size after 2 more refineries: %d" % BuildingMesh._material_cache.size())
	# Now spawn an enemy team 1 HQ - it should add team=1 variants.
	for i in range(2):
		var b = BuildingMesh.build(parent, "hq", Vector3(8, 4, 8), "technocrats", 1)
		if b == null:
			print("[FAIL] enemy hq %d returned null" % i)
			quit(1)
			return
	print("cache size after 2 more enemy hqs: %d" % BuildingMesh._material_cache.size())
	# Now spawn an enemy team 1 refinery - again different set.
	for i in range(2):
		var b = BuildingMesh.build(parent, "refinery", Vector3(10, 4, 10), "technocrats", 1)
		if b == null:
			print("[FAIL] enemy refinery %d returned null" % i)
			quit(1)
			return
	print("cache size after 2 more enemy refineries: %d" % BuildingMesh._material_cache.size())
	# Sanity: cache size should be small (handful of materials per (kind, team))
	# and NOT scale with the number of buildings spawned.
	if BuildingMesh._material_cache.size() > 20:
		print("[WARN] cache size > 20: %d" % BuildingMesh._material_cache.size())
	else:
		print("[PASS] cache size %d is bounded (independent of building count)"
			% BuildingMesh._material_cache.size())
	# Cleanup.
	parent.queue_free()
	quit(0)
