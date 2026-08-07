extends RefCounted
# Shared base for every tests/test_<area>.gd suite file.
#
# WHY THIS EXISTS: the suites were 16,000 lines in one run_tests.gd, which
# `extends SceneTree`, so they used `root`, `current_scene` and
# `await process_frame` as plain members of themselves. Splitting them into
# separate files means they are no longer the tree, and this class hands those
# three things back unchanged:
#
#   root           a plain member, assigned once by the runner - so all ~280
#                  `root.add_child(...)` calls moved verbatim
#   current_scene  a property proxying the real tree, because suites both read
#                  it and assign to it (`current_scene = stub`)
#   tree           the SceneTree itself, for the handful of things that cannot
#                  be aliased - signals especially. `await process_frame` had to
#                  become `await tree.process_frame`, since a signal cannot be
#                  re-exposed as a member.
#
# It also holds the preloads, golden fixtures and helpers that more than one
# area needs, so no suite file has to reach sideways into another.

var tree: SceneTree
var root: Window

var current_scene: Node:
	get:
		return tree.current_scene
	set(value):
		tree.current_scene = value

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleData = preload("res://scripts/module_data.gd")
const HullLoader = preload("res://scripts/hull_loader.gd")
# player_vehicle.gd is no longer used in production - battlefield.gd:51 explains
# why battle_unit.gd replaced it - but four damage-model suites still use it as a
# minimal CharacterBody3D damage target, which is exactly what they want there.
const PlayerVehicleScript = preload("res://scripts/player_vehicle.gd")
const TargetDummyScript = preload("res://scripts/target_dummy.gd")
const IncomingMissileScript = preload("res://scripts/incoming_missile.gd")
const DamageResolverScript = preload("res://scripts/damage_resolver.gd")
const DrivetrainScript = preload("res://scripts/drivetrain.gd")
const LocomotionLayoutScript = preload("res://scripts/locomotion_layout.gd")

# Ranges deliberately EXCLUDE the Geometric Shapes block (0x25xx) and Latin/
# punctuation. Box-drawing and geometric characters are legitimate technical
# notation in this project - battle_unit.gd's health bars are built from them -
# whereas emoji and dingbats are the decoration item 0 bans.
const _GLYPH_RANGES := [
	[0x2190, 0x21FF],   # arrows
	[0x2600, 0x27BF],   # misc symbols + dingbats (stars, ✓, ⚙, ⚡)
	[0x2B00, 0x2BFF],   # misc symbols and arrows
	[0x1F000, 0x1FAFF], # emoji planes
]

# --- Golden locomotion layout fixture -----------------------------------
# Frozen output of module_placer.gd's update_locomotion() as it stood at
# ff757ef, captured by scratch/probe_locomotion_layout.gd across three hull
# sizes for all ten types.
#
# The point is not that these numbers are right - several are the residue of
# a long tail of hand-tuned visual fixes (the comments inside
# update_locomotion() read as a changelog of them). The point is that they
# are what the game currently looks like, and the placement factoring
# (LOCOMOTION_EXPANSION_PLAN.md 2.3) has to reproduce them EXACTLY, so that
# a 540-line elif chain can be replaced without silently undoing one of
# those fixes. Any intentional change to placement updates this fixture in
# its own commit, with the delta explained - never as a side effect of a
# refactor.
#
# UPDATED 2026-08-02, deliberately. Two intentional changes moved these numbers:
#   1. The hull lift is now MEASURED from where each type's geometry actually
#      ends, instead of being derived from the chassis height. Ground-contact
#      types previously floated (wheels 0.13 above the plane, half_track 0.30)
#      or sank (legs 0.31 through it); every one now touches at exactly 0.
#   2. A per-type width clamp scales an assembly that would otherwise reach
#      absurdly far outboard - ornithopter_wing was 4.25x the hull's width and
#      legs 2.69x, against ~1.1x for the tracked types.
# So hull_y and some scales differ from the ff757ef capture. Station positions
# are unchanged.
const GOLDEN_LOCOMOTION_LAYOUT := {
	"small": {
		"wheels": {"hull_y": 0.9680, "stations": [[Vector3(-1.1500, -0.3000, -1.0500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(-1.1500, -0.3000, 1.0500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(1.1500, -0.3000, -1.0500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(1.1500, -0.3000, 1.0500), Vector3(1.0000, 1.0000, 1.0000)]]},
		"tracked_treads": {"hull_y": 0.4886, "stations": [[Vector3(-0.8800, -0.5000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(0.8800, -0.5000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"legs": {"hull_y": 1.3908, "stations": [[Vector3(-1.0000, -0.3000, -1.0500), Vector3(0.7522, 0.7522, 0.7522)], [Vector3(-1.0000, -0.3000, 1.0500), Vector3(0.7522, 0.7522, 0.7522)], [Vector3(1.0000, -0.3000, -1.0500), Vector3(0.7522, 0.7522, 0.7522)], [Vector3(1.0000, -0.3000, 1.0500), Vector3(0.7522, 0.7522, 0.7522)]]},
		"hover_engine": {"hull_y": 0.5223, "stations": [[Vector3(-1.5000, -0.3000, 0.0000), Vector3(0.6239, 0.6239, 0.6239)], [Vector3(0.0000, -0.3000, -2.0000), Vector3(0.6239, 0.6239, 0.6239)], [Vector3(0.0000, -0.3000, 2.0000), Vector3(0.6239, 0.6239, 0.6239)], [Vector3(1.5000, -0.3000, 0.0000), Vector3(0.6239, 0.6239, 0.6239)]]},
		"helicopter_rotors": {"hull_y": 0.9000, "stations": [[Vector3(-2.2500, 0.6000, -1.0000), Vector3(0.3500, 0.3500, 0.3500)], [Vector3(-2.2500, 0.6000, 1.0000), Vector3(0.3500, 0.3500, 0.3500)], [Vector3(2.2500, 0.6000, -1.0000), Vector3(0.3500, 0.3500, 0.3500)], [Vector3(2.2500, 0.6000, 1.0000), Vector3(0.3500, 0.3500, 0.3500)]]},
		"fixed_wing_engine": {"hull_y": 0.9000, "stations": [[Vector3(-1.4000, 0.0000, 0.5000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(1.4000, 0.0000, 0.5000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"ornithopter_wing": {"hull_y": 0.9000, "stations": [[Vector3(-1.3000, 0.0000, 0.2500), Vector3(0.7000, 0.3500, 0.7000)], [Vector3(1.3000, 0.0000, 0.2500), Vector3(0.7000, 0.3500, 0.7000)]]},
		"naval_propeller": {"hull_y": 0.9000, "stations": [[Vector3(-0.5000, 0.0000, 2.1000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(0.5000, 0.0000, 2.1000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"buoyant_envelope": {"hull_y": 0.9000, "stations": [[Vector3(-2.1000, 0.0000, 0.0000), Vector3(0.8702, 0.8702, 0.8702)], [Vector3(2.1000, 0.0000, 0.0000), Vector3(0.8702, 0.8702, 0.8702)]]},
		"screw_drive": {"hull_y": 0.8157, "stations": [[Vector3(-1.0000, -0.2500, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(1.0000, -0.2500, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
	},
	"reference": {
		"wheels": {"hull_y": 1.1680, "stations": [[Vector3(-2.1500, -0.5000, -2.1000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(-2.1500, -0.5000, 2.1000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(2.1500, -0.5000, -2.1000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(2.1500, -0.5000, 2.1000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"tracked_treads": {"hull_y": 0.7272, "stations": [[Vector3(-1.7600, -0.7500, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(1.7600, -0.7500, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"legs": {"hull_y": 1.9500, "stations": [[Vector3(-2.0000, -0.5000, -2.1000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(-2.0000, -0.5000, 2.1000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(2.0000, -0.5000, -2.1000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(2.0000, -0.5000, 2.1000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"hover_engine": {"hull_y": 0.9094, "stations": [[Vector3(-2.5000, -0.5000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(0.0000, -0.5000, -3.5000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(0.0000, -0.5000, 3.5000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(2.5000, -0.5000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"helicopter_rotors": {"hull_y": 0.9000, "stations": [[Vector3(-3.2500, 0.8000, -2.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(-3.2500, 0.8000, 2.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.2500, 0.8000, -2.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.2500, 0.8000, 2.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"fixed_wing_engine": {"hull_y": 0.9000, "stations": [[Vector3(-2.4000, 0.0000, 1.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(2.4000, 0.0000, 1.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"ornithopter_wing": {"hull_y": 0.9000, "stations": [[Vector3(-2.3000, 0.0000, 0.2500), Vector3(0.9356, 0.4678, 0.9356)], [Vector3(2.3000, 0.0000, 0.2500), Vector3(0.9356, 0.4678, 0.9356)]]},
		"naval_propeller": {"hull_y": 0.9000, "stations": [[Vector3(-1.2500, -0.2500, 3.6000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(1.2500, -0.2500, 3.6000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"buoyant_envelope": {"hull_y": 0.9000, "stations": [[Vector3(-3.1000, 0.0000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.1000, 0.0000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"screw_drive": {"hull_y": 1.4429, "stations": [[Vector3(-2.0000, -0.5000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(2.0000, -0.5000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
	},
	"large": {
		"wheels": {"hull_y": 1.7680, "stations": [[Vector3(-3.6500, -1.1000, -3.8500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(-3.6500, -1.1000, 3.8500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.6500, -1.1000, -3.8500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.6500, -1.1000, 3.8500), Vector3(1.0000, 1.0000, 1.0000)]]},
		"tracked_treads": {"hull_y": 1.7082, "stations": [[Vector3(-3.0800, -1.7500, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.0800, -1.7500, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"legs": {"hull_y": 2.5500, "stations": [[Vector3(-3.5000, -1.1000, -3.8500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(-3.5000, -1.1000, 3.8500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.5000, -1.1000, -3.8500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.5000, -1.1000, 3.8500), Vector3(1.0000, 1.0000, 1.0000)]]},
		"hover_engine": {"hull_y": 1.5315, "stations": [[Vector3(-4.0000, -1.1000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(0.0000, -1.1000, -6.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(0.0000, -1.1000, 6.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(4.0000, -1.1000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"helicopter_rotors": {"hull_y": 0.9000, "stations": [[Vector3(-4.7500, 1.4000, -3.7500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(-4.7500, 1.4000, 3.7500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(4.7500, 1.4000, -3.7500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(4.7500, 1.4000, 3.7500), Vector3(1.0000, 1.0000, 1.0000)]]},
		"fixed_wing_engine": {"hull_y": 0.9000, "stations": [[Vector3(-3.9000, 0.0000, 1.7500), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.9000, 0.0000, 1.7500), Vector3(1.0000, 1.0000, 1.0000)]]},
		"ornithopter_wing": {"hull_y": 0.9000, "stations": [[Vector3(-3.8000, 0.2500, 0.5000), Vector3(1.7098, 0.8549, 1.7098)], [Vector3(3.8000, 0.2500, 0.5000), Vector3(1.7098, 0.8549, 1.7098)]]},
		"naval_propeller": {"hull_y": 0.9000, "stations": [[Vector3(-2.0000, -0.2500, 6.1000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(2.0000, -0.2500, 6.1000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"buoyant_envelope": {"hull_y": 0.9000, "stations": [[Vector3(-4.6000, 0.0000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(4.6000, 0.0000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
		"screw_drive": {"hull_y": 3.0744, "stations": [[Vector3(-3.5000, -1.0000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)], [Vector3(3.5000, -1.0000, 0.0000), Vector3(1.0000, 1.0000, 1.0000)]]},
	},
}

const GOLDEN_HULL_SIZES := {
	"small": Vector3(2.0, 0.6, 3.0),
	"reference": Vector3(4.0, 1.0, 6.0),
	"large": Vector3(7.0, 2.2, 11.0),
}

# Combined extents of a module's rendered geometry, in the module's own local
# space. Lets a test assert what a tweak does to the model without depending
# on how the mesh tree happens to be structured (one authored mesh vs. a
# procedural base + barrel + drum).
func _module_visual_extents(module: Node3D) -> Vector3:
	var min_p = Vector3.INF
	var max_p = -Vector3.INF
	var stack: Array = [module]
	while not stack.is_empty():
		var n = stack.pop_back()
		# Skip the editor overlays wholesale. The firing arc in particular is a
		# fixed 3-unit-radius fan whose ClearArc/BlockedArc child meshes are
		# far larger than any weapon, so leaving it in pins the measured
		# extents at 6 x 6 and hides whatever the tweak actually did.
		if n.name.begins_with("ArcCone") or n.name.begins_with("Gizmo3D"):
			continue
		if n is MeshInstance3D and n.mesh:
			var rel = module.global_transform.affine_inverse() * n.global_transform
			var box = n.mesh.get_aabb()
			for i in range(8):
				var p = rel * box.get_endpoint(i)
				min_p = min_p.min(p)
				max_p = max_p.max(p)
		for c in n.get_children():
			if not (c is CollisionObject3D):
				stack.append(c)
	if min_p == Vector3.INF:
		return Vector3.ZERO
	return max_p - min_p

func _snapshot_mesh_transforms(node: Node3D) -> Array:
	var result = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append([child.position, child.scale, child.rotation])
	return result

func _count_mesh_vertices(mesh: Mesh) -> int:
	var total = 0
	for surf in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(surf)
		total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total

func _is_decorative_glyph(c: int) -> bool:
	for r in _GLYPH_RANGES:
		if c >= r[0] and c <= r[1]:
			return true
	return false

func _collect_glyph_offenders(node: Node, screen: String, out: Array) -> void:
	var text := ""
	if node is Label:
		text = (node as Label).text
	elif node is Button:
		text = (node as Button).text
	elif node is CheckBox:
		text = (node as CheckBox).text
	if text != "":
		for i in range(text.length()):
			if _is_decorative_glyph(text.unicode_at(i)):
				out.append({
					"glyph": text[i], "screen": screen.get_file(),
					"path": String(node.get_path()).right(60), "text": text,
				})
				break
	for c in node.get_children():
		_collect_glyph_offenders(c, screen, out)

func _all_descendants(node: Node, out: Array = []) -> Array:
	for c in node.get_children():
		out.append(c)
		_all_descendants(c, out)
	return out

func bp_manager_test_load(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	return data

# A legal, cheap medium-tier fixture reused by both D1 tests below - real
# hull + weapon module so ModuleCatalog.validate_build_legality() passes,
# which production.enqueue() requires before a job ever reaches the queue.
func _d1_test_blueprint() -> Dictionary:
	return {
		"version": 1.0, "hull_type": "medium_hull",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"locomotion": {"type_id": "tracked_treads", "settings": {"width": 1.0}},
		"modules": [
			{"type_id": "tracked_treads", "name": "Treads", "position": {"x": 0, "y": 0, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}},
			{"type_id": "basic_cannon", "name": "Cannon", "position": {"x": 0, "y": 0.75, "z": 0}, "rotation": {"x": 0, "y": 0, "z": 0}, "scale": {"x": 1, "y": 1, "z": 1}, "tweaks": {}},
		],
	}

# BFS helper (no self-referencing lambda needed) - finds the first real
# renderable mesh under a node, used by the E1 low-power dimming test to
# confirm a defense's actual mesh transparency changes, not just a flag.
func _e1_find_first_geometry_instance(node: Node) -> GeometryInstance3D:
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is GeometryInstance3D:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

# Reusable per-map smoke test (per Chris's one-at-a-time verification
# instruction: each map gets a real scripted playthrough, not just eyeball
# screenshots) - real Skirmish spawn on the given map_id, checks:
# start points are legal/unblocked, every resource node is actually
# reachable from its own team's harvester spawn (no unreachable resources
# from a bad hand-authored position), the two HQs are mutually reachable
# on the ground navmesh (the AI can actually reach the player and vice
# versa), and the economy/build-queue loop still produces a real unit.
func _smoke_test_map(map_id: String) -> bool:
	var MapCatalogScript = preload("res://scripts/map_catalog.gd")
	var TerrainBuilderScript = preload("res://scripts/terrain_builder.gd")
	var map_def = MapCatalogScript.get_map(map_id)

	# MIGRATED FROM Skirmish.tscn TO Battle.tscn with the retirement of the legacy
	# runtime. These ten per-map suites are about the MAPS - spawn legality,
	# resource reachability, HQ-to-HQ connectivity, fairness lint - and none of
	# that belongs to a particular match controller, so they were migrated rather
	# than retired with the 62 suites that tested the legacy implementation itself.
	#
	# THE ONE STRUCTURAL DIFFERENCE: match_director._ready() awaits its terrain
	# bake, so it is a coroutine and the scene is NOT ready after a fixed number of
	# frames the way Skirmish was. Waiting on `world_is_ready` is required, not
	# defensive - a fixed frame count here would assert against an unbuilt map and
	# fail for reasons that have nothing to do with the map.
	var battle = preload("res://scenes/Battle.tscn").instantiate()
	battle.map_id = map_id
	root.add_child(battle)
	current_scene = battle
	var guard := 0
	while not battle.world_is_ready and guard < 3000:
		await tree.process_frame
		guard += 1
	if not battle.world_is_ready:
		print("  [FAIL] Battle never finished building map '", map_id, "'")
		battle.queue_free()
		return false
	if not await _await_nav_map(battle.ground_nav_map):
		print("  [FAIL] Ground navigation map never synchronised on map '", map_id, "'")
		battle.queue_free()
		return false

	if battle.map_id != map_id or battle.current_map.get("name", "") != map_def.name:
		print("  [FAIL] Battle did not load the requested map '", map_id, "'")
		battle.queue_free()
		return false
	var player_hq = _find_hq(battle, battle.PLAYER_TEAM)
	var enemy_hq = _find_hq(battle, battle.ENEMY_TEAM)
	if player_hq == null or enemy_hq == null:
		print("  [FAIL] Player/enemy HQ failed to spawn on map '", map_id, "'")
		battle.queue_free()
		return false

	# RTS_CORE_ROADMAP.md B3: player_start/enemy_start became a spawns
	# array with an id per entry - MapCatalog.get_spawn() is the one
	# supported way to get "the player's start"/"the enemy's start" back.
	var player_start = MapCatalogScript.get_spawn(map_def, "player")
	var enemy_start = MapCatalogScript.get_spawn(map_def, "enemy")

	# Start points must be real, unblocked, buildable ground.
	for start_name in ["player", "enemy"]:
		var start = player_start if start_name == "player" else enemy_start
		for key in ["hq", "factory", "refinery"]:
			if TerrainBuilderScript.is_position_blocked(map_def, start[key]):
				print("  [FAIL] ", start_name, ".", key, " (", start[key], ") sits on blocked terrain (water/obstacle/ramp)")
				battle.queue_free()
				return false

	# Every resource node must be reachable from ITS side's harvester spawn.
	var player_start_pos = player_start.harvester
	var enemy_start_pos = enemy_start.harvester
	for node_data in map_def.get("resource_nodes", []):
		var from_pos = player_start_pos if node_data.position.distance_to(player_start_pos) < node_data.position.distance_to(enemy_start_pos) else enemy_start_pos
		var path = NavigationServer3D.map_get_path(battle.ground_nav_map, from_pos, node_data.position, true)
		if path.size() < 2 or path[path.size() - 1].distance_to(node_data.position) > 3.0:
			print("  [FAIL] Resource node at ", node_data.position, " is not reachable by ground navmesh from the nearest base")
			battle.queue_free()
			return false

	# The two HQs must be mutually reachable (AI can path to the player,
	# player can path to the AI) - not stranded on disconnected navmesh
	# islands by a badly-placed water/obstacle/elevation zone.
	# RTS_CORE_ROADMAP.md C1: a path can no longer reach the HQ's own exact
	# center - the HQ IS a building now, so it carves its own navmesh hole
	# same as any other. HQ_REACHABLE_MARGIN accounts for stopping at the
	# hole's edge plus up to one GRID_CELL (4.0) of quantization slop.
	const HQ_REACHABLE_MARGIN := 12.0
	var hq_path = NavigationServer3D.map_get_path(battle.ground_nav_map, player_start.hq, enemy_start.hq, true)
	if hq_path.size() < 2 or hq_path[hq_path.size() - 1].distance_to(enemy_start.hq) > HQ_REACHABLE_MARGIN:
		print("  [FAIL] Player and enemy HQs are not mutually reachable on the ground navmesh")
		battle.queue_free()
		return false

	# RTS_CORE_ROADMAP.md B10: the fairness lint every map has to clear.
	var fairness_errors = MapCatalogScript.lint_spawn_fairness(map_def, battle.ground_nav_map)
	if not fairness_errors.is_empty():
		print("  [FAIL] Spawn fairness lint failed for map '", map_id, "': ", fairness_errors)
		battle.queue_free()
		return false

	# Economy/build loop still works: queue a unit, tick past its build time,
	# confirm it was actually produced. Goes through ProductionService rather than
	# through a factory node - production is a service in the new runtime, and the
	# queue is global per tier rather than owned by a building.
	var harv_bp = _find_harvester_blueprint(battle)
	if harv_bp.is_empty():
		print("  [FAIL] No harvester blueprint found in the roster for map '", map_id, "'")
		battle.queue_free()
		return false
	var queue_name = preload("res://scripts/battle/economy/design_costing.gd").queue_for_design(harv_bp)
	var units_before = battle.get_team_units(battle.PLAYER_TEAM).size()
	battle.production.enqueue_unit(battle.PLAYER_TEAM, harv_bp, 0, 0, 0.05, queue_name)
	for i in range(30):
		await tree.process_frame
	var units_after = battle.get_team_units(battle.PLAYER_TEAM).size()
	if units_after <= units_before:
		print("  [FAIL] Production did not produce a queued unit on map '", map_id, "' (before=", units_before, " after=", units_after, ")")
		battle.queue_free()
		return false

	battle.queue_free()
	await tree.process_frame
	return true


# WAITING FOR world_is_ready IS NOT ENOUGH, and this is what made all ten map
# smokes fail after the retirement commit.
#
# NavigationServer3D applies map_create/map_set_active/region_set_navigation_mesh
# as QUEUED COMMANDS, flushed on its own sync pass, not immediately on call. In
# headless, match_director._setup_terrain() takes the blocking bake path with no
# awaits in it, so _ready() completes inside add_child() and world_is_ready is
# already true on the first check - zero frames later, with the map created but
# not yet synchronised. Every map_get_path() against it returns an EMPTY array,
# which the helper correctly reported as "resource node is not reachable".
#
# The maps were never broken. Proof: the FIRST map in a process passed and every
# subsequent one failed, purely because the first had spent a frame elsewhere.
# The same shape as the map_get_closest_point()-returns-origin trap found on
# 2026-08-06, and it deserves the same explicit wait.
# MEASURED, not guessed. Building the B5 fixture's navmesh and sampling every
# frame (tools/probe_nav_sync.gd):
#
#   frame 0: active=false regions=0 iteration=0 path=0 pts
#   frame 1: active=true  regions=1 iteration=0 path=0 pts
#   frame 2: active=true  regions=1 iteration=1 path=0 pts   <- NOT queryable yet
#   frame 8: active=true  regions=1 iteration=2 path=29 pts  <- queryable
#
# So neither map_is_active nor a non-empty region list means the map can be
# pathed on, and neither does the first iteration bump - the polygons land on the
# SECOND one. Waiting a fixed one or two frames, which is what every one of these
# suites did, is waiting on a number that happened to work on the machine it was
# written on. This waits for the actual condition instead.
func _await_nav_map(nav_map: RID, max_frames: int = 240) -> bool:
	if not nav_map.is_valid():
		return false
	var waited := 0
	while waited < max_frames:
		if NavigationServer3D.map_is_active(nav_map) \
				and not NavigationServer3D.map_get_regions(nav_map).is_empty() \
				and NavigationServer3D.map_get_iteration_id(nav_map) >= 2:
			return true
		await tree.process_frame
		waited += 1
	return false


func _find_hq(battle, team: int):
	for s in battle.get_team_structures(team):
		if s.kind == "hq":
			return s
	return null


func _find_harvester_blueprint(battle) -> Dictionary:
	for design in battle.roster:
		if battle.is_defence_design(design):
			continue
		for module in design.get("modules", []):
			if str(module.get("type_id", "")) == "resource_harvester":
				return design
	return {}


# RTS_CORE_ROADMAP.md B9: an 8-bit-per-channel Image (FORMAT_RGB8, what
# _minimap_static_image/_minimap_image both use) quantizes/rounds a float
# Color on set_pixel - comparing a sampled pixel against a raw float Color
# constant with `==` fails on harmless rounding, not a real bug. Tolerant
# only across a single-pixel compare - not a substitute for the existing
# whole-image screenshot_diff.gd tolerance, a different problem.
func _color_close(a: Color, b: Color, eps: float = 0.02) -> bool:
	return abs(a.r - b.r) <= eps and abs(a.g - b.g) <= eps and abs(a.b - b.b) <= eps

