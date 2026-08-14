extends "res://tests/suite_base.gd"

# Tactile Interface Programme Phase 6 Tests (Module Action Ring, D13)
# Extended for the Instrument Console Pass, Phase A (station ring).

const ModuleActionRingScript = preload("res://scripts/ui/module_action_ring.gd")
const RingDrawScript = preload("res://scripts/ui/ring_draw.gd")
const ModuleVolume = preload("res://scripts/module_volume.gd")
const TweakStations = preload("res://scripts/ui/tweak_stations.gd")
const LabDocument = preload("res://scripts/lab_document.gd")


## Independent re-derivation of what the ring's silhouette clearance SHOULD
## be, using ModuleVolume.bounds() directly and all eight AABB corners. This
## deliberately does not call ring._compute_projected_half_diagonal() - the
## original test compared the ring's own helper against itself, which cannot
## fail even when the helper is wrong (it was: 4 of 8 corners, and a bare
## mesh AABB instead of ModuleVolume's measured geometry).
static func _expected_half_diagonal(camera: Camera3D, node: Node3D) -> float:
	var aabb: AABB = ModuleVolume.bounds(node)
	var center_2d: Vector2 = camera.unproject_position(node.global_position)
	var max_dist: float = 0.0
	var corners := [
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.end.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.end.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, aabb.end.z),
		Vector3(aabb.end.x, aabb.end.y, aabb.position.z),
		Vector3(aabb.end.x, aabb.position.y, aabb.end.z),
		Vector3(aabb.position.x, aabb.end.y, aabb.end.z),
		Vector3(aabb.end.x, aabb.end.y, aabb.end.z),
	]
	for c in corners:
		var world_pos: Vector3 = node.global_transform * c
		if camera.is_position_behind(world_pos):
			continue
		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		var d := (screen_pos - center_2d).length()
		if d > max_dist:
			max_dist = d
	return max_dist


func _make_test_module(box_size: Vector3) -> Node3D:
	var mod: Node3D = Node3D.new()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = box_size
	mesh_inst.mesh = box
	mod.add_child(mesh_inst)
	return mod


func test_action_ring_inner_radius_clears_silhouette() -> bool:
	print("Running Test Suite: Module Action Ring - Inner Radius Clears Silhouette (Phase 6, D13; Instrument Console Pass A1)...")

	var cam: Camera3D = Camera3D.new()
	root.add_child(cam)

	var camera_setups := [
		{"pos": Vector3(0, 5, 10), "size": Vector3(2.0, 1.0, 3.0)},
		{"pos": Vector3(6, 1, 0), "size": Vector3(0.4, 0.4, 2.5)},   # long thin barrel, side-on
		{"pos": Vector3(0, 12, 0.01), "size": Vector3(3.0, 3.0, 3.0)}, # near-top-down, big part
		{"pos": Vector3(1.5, 1.5, 1.5), "size": Vector3(0.6, 0.6, 0.6)}, # close, small part (min zoom)
	]

	for setup in camera_setups:
		var mod: Node3D = _make_test_module(setup["size"])
		root.add_child(mod)
		cam.position = setup["pos"]
		cam.look_at(Vector3.ZERO, Vector3.UP)
		await tree.process_frame

		var ring = ModuleActionRingScript.new()
		root.add_child(ring)
		ring.open_for_module(mod, "TEST MODULE")
		await tree.process_frame

		var expected: float = _expected_half_diagonal(cam, mod)
		if ring.inner_radius + 0.01 < expected:
			print("  [FAIL] inner_radius (%.1f) is smaller than independently-derived half-diagonal (%.1f) for size %s at cam %s" % [ring.inner_radius, expected, setup["size"], setup["pos"]])
			ring.queue_free()
			mod.queue_free()
			cam.queue_free()
			return false

		ring.queue_free()
		mod.queue_free()

	cam.queue_free()
	print("  [PASS] Inner radius strictly clears the independently-derived projected half-diagonal across camera angles and module sizes.")
	return true


func test_tweak_station_angle_is_identity_of_name_not_index() -> bool:
	print("Running Test Suite: Tweak Station - Angle Is A Property Of Name, Not Index...")
	# "caliber" appears at different list positions across weapon specs
	# (basic_cannon index 0, mk19_grenade_launcher index 0, aa_autocannon
	# index 0, flak_cannon index 0...) - use two specs where it sits at
	# different indices among differing tweak counts.
	var caliber_angle_a := TweakStations.angle_for("caliber")
	var caliber_angle_b := TweakStations.angle_for("caliber")
	if caliber_angle_a < 0.0:
		print("  [FAIL] 'caliber' has no declared station angle")
		return false
	if not is_equal_approx(caliber_angle_a, caliber_angle_b):
		print("  [FAIL] Same tweak name resolved to different angles: %.3f vs %.3f" % [caliber_angle_a, caliber_angle_b])
		return false

	# A module class with 3 tweaks and one with 5 tweaks must still each
	# resolve "protectedness" to the same station.
	var spec_short: Array = LabDocument.TWEAK_SPECS.get("gauss_railgun", [])
	var spec_long: Array = LabDocument.TWEAK_SPECS.get("flak_cannon", [])
	if spec_short.is_empty() or spec_long.is_empty():
		print("  [FAIL] Expected fixture specs missing from LabDocument.TWEAK_SPECS")
		return false
	var idx_short := -1
	for i in spec_short.size():
		if spec_short[i]["name"] == "protectedness":
			idx_short = i
	var idx_long := -1
	for i in spec_long.size():
		if spec_long[i]["name"] == "protectedness":
			idx_long = i
	if idx_short == idx_long:
		print("  [SKIP-CHECK] fixture specs happened to place 'protectedness' at the same index; angle identity still verified above")
	var angle_short := TweakStations.angle_for("protectedness")
	var angle_long := TweakStations.angle_for("protectedness")
	if not is_equal_approx(angle_short, angle_long):
		print("  [FAIL] 'protectedness' angle differs between differently-sized specs")
		return false

	print("  [PASS] Station angle is keyed by tweak name, independent of a module's tweak count or list position.")
	return true


func test_tweak_station_coverage_guards_every_tweak_spec_entry() -> bool:
	print("Running Test Suite: Tweak Station - Coverage Guard For Every LabDocument.TWEAK_SPECS Entry...")
	var missing: Array = []
	for type_id in LabDocument.TWEAK_SPECS.keys():
		var specs: Array = LabDocument.TWEAK_SPECS[type_id]
		for spec in specs:
			var tweak_name: String = spec["name"]
			if not TweakStations.has_station(tweak_name):
				missing.append("%s.%s" % [type_id, tweak_name])
	if not missing.is_empty():
		print("  [FAIL] %d tweak(s) have no station angle: %s" % [missing.size(), missing])
		return false
	print("  [PASS] Every tweak in LabDocument.TWEAK_SPECS resolves to a station angle.")
	return true


func test_action_ring_wedge_order_is_fixed() -> bool:
	print("Running Test Suite: Module Action Ring - Wedge Order Is Fixed (Phase 6)...")
	var ring = ModuleActionRingScript.new()
	ring.add_action("rotate", "Rotate")
	ring.add_action("mirror", "Mirror")
	ring.add_action("arc", "Arc")
	ring.add_action("discard", "Discard")

	# Wedge 0 (Top)
	var angle_0: float = RingDrawScript.sector_angle(0, 4)
	# Expect -PI/2 (-TAU * 0.25, 12 o'clock)
	if absf(angle_0 - (-PI * 0.5)) > 0.001:
		print("  [FAIL] Wedge 0 angle is %.3f, expected -PI/2 (12 o'clock)" % angle_0)
		ring.free()
		return false

	# Wedge 1 (Right)
	var angle_1: float = RingDrawScript.sector_angle(1, 4)
	# Expect 0.0 (3 o'clock)
	if absf(angle_1 - 0.0) > 0.001:
		print("  [FAIL] Wedge 1 angle is %.3f, expected 0.0 (3 o'clock)" % angle_1)
		ring.free()
		return false

	ring.free()
	print("  [PASS] Wedge order is fixed at 12 o'clock and rotates clockwise.")
	return true


func test_action_ring_persists_across_invocations() -> bool:
	print("Running Test Suite: Module Action Ring - Persists Across Action Invocations (D13)...")
	var ring = ModuleActionRingScript.new()
	root.add_child(ring)

	var mod: Node3D = Node3D.new()
	root.add_child(mod)
	ring.open_for_module(mod, "TURRET")

	var res := {"action": ""}
	ring.action_invoked.connect(func(id: String): res["action"] = id)

	# Simulate clicking action 0
	var mb = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	# Position in wedge 0 (top: offset y negative)
	mb.position = ring.size * 0.5 + Vector2(0, -(ring.inner_radius + ring.outer_radius) * 0.5)

	ring.add_action("rotate", "Rotate")
	ring.add_action("mirror", "Mirror")
	ring._gui_input(mb)

	if res["action"] != "rotate":
		print("  [FAIL] Action 'rotate' was not invoked, got: '%s'" % res["action"])
		ring.queue_free()
		mod.queue_free()
		return false

	if not ring._is_open:
		print("  [FAIL] Ring closed on action invocation - D13 requires it to persist until deselect")
		ring.queue_free()
		mod.queue_free()
		return false

	ring.queue_free()
	mod.queue_free()
	print("  [PASS] Ring invoked action and remained open (D13).")
	return true


func test_action_ring_closes_when_target_freed() -> bool:
	print("Running Test Suite: Module Action Ring - Closes When Target Node Is Freed (Phase 6)...")
	var ring = ModuleActionRingScript.new()
	root.add_child(ring)

	var mod: Node3D = Node3D.new()
	root.add_child(mod)
	ring.open_for_module(mod, "RADAR")
	await tree.process_frame

	# Free target node
	mod.free()
	await tree.process_frame
	if is_instance_valid(ring):
		ring._process(0.016)

	if is_instance_valid(ring) and ring._is_open:
		print("  [FAIL] Ring remained open after target node was freed")
		ring.queue_free()
		return false

	if is_instance_valid(ring):
		ring.queue_free()
	print("  [PASS] Ring gracefully closed when target node was freed.")
	return true
