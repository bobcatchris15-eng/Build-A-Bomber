extends "res://tests/suite_base.gd"

# Tactile Interface Programme Phase 6 Tests (Module Action Ring, D13)

const ModuleActionRingScript = preload("res://scripts/ui/module_action_ring.gd")
const RingDrawScript = preload("res://scripts/ui/ring_draw.gd")


func test_action_ring_inner_radius_clears_silhouette() -> bool:
	print("Running Test Suite: Module Action Ring - Inner Radius Clears Silhouette (Phase 6, D13)...")
	var ring = ModuleActionRingScript.new()
	root.add_child(ring)

	var mod: Node3D = Node3D.new()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(2.0, 1.0, 3.0)
	mesh_inst.mesh = box
	mod.add_child(mesh_inst)
	root.add_child(mod)

	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0, 5, 10)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	root.add_child(cam)
	await tree.process_frame

	ring.open_for_module(mod, "TEST MODULE")
	await tree.process_frame

	# Compute expected half diagonal in screen space
	var half_diag: float = ring._compute_projected_half_diagonal(cam, mod)
	if ring.inner_radius < half_diag:
		print("  [FAIL] inner_radius (%.1f) is smaller than projected half-diagonal (%.1f)" % [ring.inner_radius, half_diag])
		ring.queue_free()
		mod.queue_free()
		cam.queue_free()
		return false

	ring.queue_free()
	mod.queue_free()
	cam.queue_free()
	print("  [PASS] Inner radius (%.1f) strictly clears projected half-diagonal (%.1f)." % [ring.inner_radius, half_diag])
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
