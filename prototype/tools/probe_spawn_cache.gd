extends SceneTree
# Is a duplicated hull the same unit as a freshly built one?
#
# unit_assembly.gd now builds one hull per design and duplicates it for every
# later spawn, because reconstruct_vehicle() measured 1046.90ms of a 1069.94ms
# spawn. That is only a valid trade if the copy is indistinguishable, and the
# assembly code leans hard on things duplication could plausibly drop:
#
#   * METADATA. hull_type, armor_thickness, armor_material, hull_scale, faction
#     and base_hull_size are all read back off the hull node as metas, and
#     attach_weapons() finds weapons by looking for a `module_data` meta on each
#     child. If duplicate() dropped metadata, units would silently come out as
#     unarmed medium hulls with default armour - plausible-looking and wrong.
#   * DERIVED STATS. max_hp is computed from those metas, so it is a single
#     number that proves the whole chain survived.
#   * CHILD STRUCTURE. Module count, and the weapons actually attached.
#
# Compares the FIRST spawn of a design (a cache miss, built from the blueprint)
# against the SECOND (a cache hit, duplicated), which is exactly the pair that
# has to agree.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_spawn_cache.gd

var _fails: int = 0


func _init():
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	while not battle.world_is_ready:
		await process_frame
	for _i in range(30):
		await process_frame

	var design: Dictionary = {}
	for d in battle.roster:
		if not battle.is_defence_design(d):
			design = d
			break
	if design.is_empty():
		print("[FAIL] no unit design in the roster")
		quit(1)
		return
	print("  design: %s" % design.get("name", "?"))

	var first = battle.spawn_unit(design, battle.PLAYER_TEAM, Vector3(-10, 0, -10))
	var t := Time.get_ticks_usec()
	var second = battle.spawn_unit(design, battle.PLAYER_TEAM, Vector3(10, 0, -10))
	var cached_ms := float(Time.get_ticks_usec() - t) / 1000.0
	if first == null or second == null:
		print("[FAIL] a spawn returned null")
		quit(1)
		return
	await process_frame

	print("  cached spawn took %.1f ms" % cached_ms)
	_same("max_hp", first.max_hp, second.max_hp)
	_same("attack_range", first.attack_range, second.attack_range)
	_same("vision_range", first.vision_range, second.vision_range)
	_same("max_energy", first.max_energy, second.max_energy)
	_same("move speed", first.move_speed, second.move_speed)
	_same("faction", first.faction, second.faction)
	_same("locomotion", first.locomotion_type, second.locomotion_type)

	for meta_name in ["type_id", "armor_thickness", "armor_material",
			"hull_scale", "faction", "base_hull_size"]:
		_same("meta " + meta_name,
			first.hull_node.get_meta(meta_name, "<missing>"),
			second.hull_node.get_meta(meta_name, "<missing>"))

	_same("module children", _modules(first.hull_node), _modules(second.hull_node))
	_same("armed weapons", _weapons(first.hull_node), _weapons(second.hull_node))
	_check("the copy actually has weapons", _weapons(second.hull_node) > 0
		or _weapons(first.hull_node) == 0)
	_check("the copy has a collider",
		second.get_node_or_null("CollisionShape3D") != null
			or _has_collider(second))

	# And it must actually MOVE - a hull that duplicates perfectly but whose
	# collider or nav radius came out wrong would sit still.
	var start_pos: Vector3 = second.global_position
	second.set_internal_destination(Vector3(10, 0, 20))
	for _i in range(120):
		await physics_frame
	_check("the copy moves under an order",
		second.global_position.distance_to(start_pos) > 1.0)

	print("")
	print("PASS" if _fails == 0 else "%d CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _modules(hull: Node3D) -> int:
	var n := 0
	for c in hull.get_children():
		if c.has_meta("module_data"):
			n += 1
	return n


func _weapons(hull: Node3D) -> int:
	var n := 0
	for c in hull.get_children():
		if "fire_range" in c:
			n += 1
	return n


func _has_collider(node: Node) -> bool:
	for c in node.get_children():
		if c is CollisionShape3D:
			return true
	return false


func _same(what: String, a, b) -> void:
	var ok: bool = str(a) == str(b)
	if a is float and b is float:
		ok = is_equal_approx(a, b)
	print("  [%s] %-24s built=%s  duplicated=%s"
		% ["PASS" if ok else "FAIL", what, a, b])
	if not ok:
		_fails += 1


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1
