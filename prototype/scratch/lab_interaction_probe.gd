extends SceneTree
# Design Lab interaction probe: drives real hull/module placement, cross-facet
# dragging, hull swapping and scaling through the SAME code paths the player
# hits (synthetic mouse events into the viewport for selection/drag, the
# overlay Control's own _can_drop_data/_drop_data for palette drops), then
# asserts structural invariants and saves screenshots.
#
# Must run WITHOUT --headless - the dummy renderer never rasterizes, so
# get_texture() would hand back a blank image.
# Run: ./Godot_v4.3-stable_win64_console.exe --script scratch/lab_interaction_probe.gd

const OUT_DIR = "res://progress_captures/2026-07-21_lab_bugs"

var lab: Node3D
var cam: Camera3D
var overlay: Control
var failures: Array = []
var checks_run: int = 0

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.size = Vector2i(1280, 720)
	lab = load("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab)
	await _settle(8)

	# designer_camera.gd reparents itself under a pivot it creates at _ready,
	# so it is NOT a direct child of MainLab by the time we look.
	cam = root.get_camera_3d()
	overlay = lab.get_node_or_null("DragDropOverlay")
	if not cam or not overlay:
		print("[PROBE] FATAL: missing Camera3D or DragDropOverlay")
		quit(1)
		return

	await _probe_startup_hull()
	await _probe_hull_collider_alignment()
	await _probe_module_placement()
	await _probe_module_drag()
	await _probe_hull_swap()
	await _probe_hull_scale()
	await _probe_tweaks()
	await _probe_primitive_hulls()
	await _probe_locomotion_mirroring()
	await _probe_underside_mounting()
	await _probe_surface_snapping()
	await _probe_firing_envelope()

	print("\n==============================================")
	print("  PROBE COMPLETE - %d checks, %d failure(s)" % [checks_run, failures.size()])
	print("==============================================")
	for f in failures:
		print("  [FAIL] ", f)
	if failures.is_empty():
		print("  All interaction invariants hold.")
	quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- helpers

func _settle(frames: int = 4):
	for i in range(frames):
		await process_frame

func _check(label: String, ok: bool, detail: String = ""):
	checks_run += 1
	if ok:
		print("  [ok]   ", label)
	else:
		var msg = label + ((" -- " + detail) if detail != "" else "")
		print("  [FAIL] ", msg)
		failures.append(msg)

func _shot(name: String):
	await _settle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("  [shot] ", name, ".png")

func _hull() -> Node3D:
	return lab.hull

# The designer camera orbits a pivot that starts at the world origin, but the
# hull is lifted well above that once locomotion is mounted (wheels raise it by
# over 2 units). Left alone, the camera stares at the empty floor and the
# hull's own front face occludes the deck - so clicks aimed at deck modules
# legitimately hit the hull. Re-frame on the hull and look down at the deck,
# which is the angle a player actually builds from.
func _frame_hull(pitch_deg: float = -32.0, distance: float = 14.0):
	var h = _hull()
	if not h or not cam:
		return
	var pivot = cam.get_parent() as Node3D
	if not pivot:
		return
	pivot.position = h.global_position
	pivot.rotation = Vector3(deg_to_rad(pitch_deg), 0, 0)
	cam.position = Vector3(0, 0, distance)
	await _settle(2)

# Screen position of a world point, for synthetic clicks.
func _screen(world_pos: Vector3) -> Vector2:
	return cam.unproject_position(world_pos)

func _click(screen_pos: Vector2, pressed: bool):
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = screen_pos
	ev.global_position = screen_pos
	root.push_input(ev)

func _move(screen_pos: Vector2, relative: Vector2 = Vector2.ZERO):
	var ev = InputEventMouseMotion.new()
	ev.position = screen_pos
	ev.global_position = screen_pos
	ev.relative = relative
	root.push_input(ev)

# Raycast straight down onto the hull's top deck at a hull-local XZ, returning
# the world hit + normal the way the real placement raycast would.
func _deck_hit(local_x: float, local_z: float):
	var h = _hull()
	if not h:
		return null
	var above = h.to_global(Vector3(local_x, 0, local_z)) + Vector3(0, 50, 0)
	var q = PhysicsRayQueryParameters3D.create(above, above + Vector3(0, -200, 0))
	q.collision_mask = 1
	return lab.get_world_3d().direct_space_state.intersect_ray(q)

func _count_named(parent: Node, prefix: String) -> int:
	var n = 0
	for c in parent.get_children():
		if c.name.begins_with(prefix):
			n += 1
	return n

func _modules() -> Array:
	var out = []
	var h = _hull()
	if not h:
		return out
	for c in h.get_children():
		if c.has_meta("module_data") and not c.is_queued_for_deletion():
			out.append(c)
	return out

# ---------------------------------------------------------------- probes

func _probe_startup_hull():
	print("\n--- Probe 1: startup hull initialization ---")
	var h = _hull()
	_check("startup hull exists", h != null)
	if not h:
		return
	_check("startup hull has PhysicsMesh", h.get_node_or_null("PhysicsMesh") != null,
		"update_hull_appearance() early-returns without it, skipping material/greebles/decals/FrontArrow/collider sizing")
	_check("startup hull has FrontArrow (proves update_hull_appearance ran)",
		h.get_node_or_null("FrontArrow") != null)
	var mi = h.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi:
		_check("startup hull mesh is the authored hull, not the placeholder box",
			not (mi.mesh is BoxMesh), "mesh class = " + (mi.mesh.get_class() if mi.mesh else "<null>"))
	await _shot("01_startup")

func _probe_hull_collider_alignment():
	print("\n--- Probe 2: hull collider vs visual alignment ---")
	for hull_id in ["medium_hull", "light_hull", "heavy_hull", "naval_hull", "interceptor_hull"]:
		lab.clear_hull()
		await _settle(2)
		lab._place_hull_from_ui(hull_id)
		await _settle(3)
		var h = _hull()
		if not h:
			_check("placed " + hull_id, false)
			continue
		var mi = h.get_node_or_null("MeshInstance3D") as MeshInstance3D
		var col = h.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not mi or not col or not (col.shape is BoxShape3D):
			_check(hull_id + " has mesh + box collider", false)
			continue

		# Visual extents in hull-local space, including the node's own rotation.
		var vis_aabb = mi.mesh.get_aabb()
		var vis_local = _transformed_extents(vis_aabb, mi.transform)
		# Collider extents in hull-local space, including its rotation.
		var col_aabb = AABB(-col.shape.size / 2.0, col.shape.size)
		var col_local = _transformed_extents(col_aabb, col.transform)

		await _frame_hull(-25.0, max(14.0, vis_local.z * 1.9))
		var ratio_x = col_local.x / vis_local.x if vis_local.x > 0.001 else 0.0
		var ratio_z = col_local.z / vis_local.z if vis_local.z > 0.001 else 0.0
		# A collider rotated 90deg off the visual shows up as one ratio far
		# above 1 and the other far below.
		var aligned = ratio_x > 0.55 and ratio_x < 1.8 and ratio_z > 0.55 and ratio_z < 1.8
		_check("%s collider aligned with visual" % hull_id, aligned,
			"visual local extents=%s collider local extents=%s (x ratio %.2f, z ratio %.2f)"
				% [vis_local, col_local, ratio_x, ratio_z])

		# A hull whose catalog says it is longer than it is wide should render
		# that way too.
		var cat_size = preload("res://scripts/module_catalog.gd").get_module_data(hull_id).get("size", Vector3.ONE)
		var cat_longer = cat_size.z > cat_size.x
		var vis_longer = vis_local.z > vis_local.x
		_check("%s visual keeps catalog's length-vs-width orientation" % hull_id,
			cat_longer == vis_longer,
			"catalog=%s visual local extents=%s" % [cat_size, vis_local])

		# And its proportions should be recognisably the catalog's, not a
		# uniform blow-up of a mesh with a different aspect ratio.
		var worst = 0.0
		for axis in ["x", "y", "z"]:
			var c = cat_size[axis]
			var v = vis_local[axis]
			if c > 0.001 and v > 0.001:
				worst = max(worst, max(c / v, v / c))
		_check("%s proportions within 1.6x of catalog on every axis" % hull_id, worst < 1.6,
			"catalog=%s visual=%s worst axis ratio %.2f" % [cat_size, vis_local, worst])
		await _shot("02_hull_%s" % hull_id)

func _transformed_extents(aabb: AABB, t: Transform3D) -> Vector3:
	var min_p = Vector3.INF
	var max_p = -Vector3.INF
	for i in range(8):
		var p = t * aabb.get_endpoint(i)
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	return max_p - min_p

func _probe_module_placement():
	print("\n--- Probe 3: module placement across categories ---")
	lab.clear_hull()
	await _settle(2)
	lab._place_hull_from_ui("medium_hull")
	await _settle(3)

	# One of each category, at distinct spots so nothing legitimately overlaps.
	var plan = [
		["basic_cannon", -0.9, -1.2],
		["sensor_suite", 0.9, 1.4],
		["armor_plating", 0.0, 0.0],
	]
	for entry in plan:
		var type_id = entry[0]
		var hit = _deck_hit(entry[1], entry[2])
		if not hit:
			_check("deck raycast hit for " + type_id, false,
				"nothing under the ray - hull collider is probably not where the hull looks")
			continue
		var before = _modules().size()
		lab._place_weapon_from_ui(type_id, hit.position, hit.normal)
		await _settle(3)
		_check("placed " + type_id, _modules().size() > before,
			"module count %d -> %d" % [before, _modules().size()])

	_check("no spurious clipping flagged on a clean layout", not lab.clipping_detected)
	await _frame_hull()
	await _shot("03_modules_placed")

	# Locomotion goes through a different branch entirely.
	lab._place_weapon_from_ui("wheels", Vector3.ZERO, Vector3.DOWN)
	await _settle(3)
	var wheels = []
	for m in _modules():
		if m.get_meta("module_data").type_id == "wheels":
			wheels.append(m)
	await _frame_hull()
	_check("wheels spawned", wheels.size() >= 4, "got %d" % wheels.size())
	if wheels.size() >= 2:
		# Wheels must straddle the hull's real visual sides, not sit buried
		# inside it or float out past the ends.
		var h = _hull()
		var mi = h.get_node_or_null("MeshInstance3D") as MeshInstance3D
		var vis = _transformed_extents(mi.mesh.get_aabb(), mi.transform)
		var max_wheel_x = 0.0
		var max_wheel_z = 0.0
		for w in wheels:
			max_wheel_x = max(max_wheel_x, abs(w.position.x))
			max_wheel_z = max(max_wheel_z, abs(w.position.z))
		_check("wheels sit near the hull's visual sides", max_wheel_x > vis.x * 0.30,
			"outermost wheel |x|=%.2f vs hull half-width %.2f" % [max_wheel_x, vis.x / 2.0])
		_check("wheels stay within the hull's visual length", max_wheel_z <= vis.z / 2.0 + 0.35,
			"outermost wheel |z|=%.2f vs hull half-length %.2f" % [max_wheel_z, vis.z / 2.0])
	await _shot("04_wheels")

func _probe_module_drag():
	print("\n--- Probe 4: selecting and dragging a module ---")
	await _frame_hull()

	# Aim at the middle of a module's collider rather than at its origin - the
	# origin sits exactly on the hull skin, so a ray there grazes hull and
	# module at once. Then resolve which module that pixel ACTUALLY reaches
	# first and make that the drag target: from any given camera angle a tall
	# neighbour (the sensor mast, say) can legitimately stand in front of the
	# module we picked, and asserting "the click selects whatever is in front"
	# is the invariant that matters anyway.
	var target: Node3D = null
	var start_screen := Vector2.ZERO
	for m in _modules():
		if m.get_meta("module_data").category == "locomotion":
			continue
		var body := m.get_node_or_null("StaticBody3D") as Node3D
		var screen_pos = _screen(body.global_position if body else m.global_position)
		var ray_origin = cam.project_ray_origin(screen_pos)
		var q = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + cam.project_ray_normal(screen_pos) * 1000.0)
		q.collision_mask = 7
		q.collide_with_areas = true
		var hit = lab.get_world_3d().direct_space_state.intersect_ray(q)
		if hit and hit.collider.get_parent() != null and hit.collider.get_parent().has_meta("module_data"):
			target = hit.collider.get_parent()
			start_screen = screen_pos
			break
	if not target:
		_check("a placed module is reachable by a click ray", false)
		return

	var target_name = target.get_meta("module_data").type_id
	_click(start_screen, true)
	await _settle(2)
	_check("click selected the module under the cursor (%s)" % target_name,
		lab.selected_module == target,
		"selected=%s" % (lab.selected_module.name if lab.selected_module else "<null>"))
	_check("exactly one Gizmo3D after select", _count_named(target, "Gizmo3D") == 1,
		"found %d" % _count_named(target, "Gizmo3D"))
	await _shot("05_selected")

	# Drag it across the deck. Aim at a different hull-local spot and walk the
	# mouse there in steps, the way a real drag arrives.
	var dest_hit = _deck_hit(0.6, 1.0)
	if not dest_hit:
		_check("destination deck raycast", false)
		return
	var end_screen = _screen(dest_hit.position)
	var origin_pos = target.position
	for i in range(1, 9):
		var t = float(i) / 8.0
		_move(start_screen.lerp(end_screen, t), (end_screen - start_screen) / 8.0)
		await _settle(1)
	_click(end_screen, false)
	await _settle(3)

	_check("drag moved the module", target.position.distance_to(origin_pos) > 0.1,
		"before=%s after=%s" % [origin_pos, target.position])
	_check("exactly one Gizmo3D after drag release", _count_named(target, "Gizmo3D") == 1,
		"found %d - queue_free()+same-frame re-add renames the new one and orphans it"
			% _count_named(target, "Gizmo3D"))
	_check("exactly one ArcCone after drag release", _count_named(target, "ArcCone") <= 1,
		"found %d" % _count_named(target, "ArcCone"))
	_check("undo history recorded the drag", lab.can_undo())
	await _shot("06_after_drag")

	# Repeated select/deselect must not accumulate gizmos either.
	for i in range(3):
		lab._select_module(null)
		await _settle(1)
		lab._select_module(target)
		await _settle(1)
	_check("no gizmo accumulation over repeated selects", _count_named(target, "Gizmo3D") == 1,
		"found %d after 3 reselect cycles" % _count_named(target, "Gizmo3D"))

func _probe_hull_swap():
	print("\n--- Probe 5: swapping the hull from the palette ---")
	var data = {"type": "module_part", "id": "heavy_hull"}
	overlay._can_drop_data(Vector2(640, 360), data)
	overlay._drop_data(Vector2(640, 360), data)
	await _settle(4)

	var h = _hull()
	_check("a hull exists after the swap", h != null)
	if h:
		_check("swapped-in hull is still named \"Hull\"", h.name == "Hull",
			"named \"%s\" - every get_node(\"Hull\") lookup breaks" % h.name)
		_check("lab.hull matches the node found by name",
			lab.get_node_or_null("Hull") == h,
			"get_node(\"Hull\")=%s lab.hull=%s"
				% [str(lab.get_node_or_null("Hull")), str(h)])
	_check("only one Hull node in the scene", _count_named(lab, "Hull") == 1,
		"found %d" % _count_named(lab, "Hull"))

	# The real consequence: can a module still be placed afterwards?
	var can_place = overlay._can_drop_data(Vector2(640, 360), {"type": "module_part", "id": "basic_cannon"})
	_check("modules can still be dropped after a hull swap", can_place,
		"_can_drop_data refused - it looks up the hull by name")
	await _shot("07_after_hull_swap")

	# Ghost cleanup on a cancelled drag. Hover over the hull itself so the
	# ghost actually gets created - a miss leaves it null and proves nothing.
	var h2 = _hull()
	if h2:
		var over_hull = _screen(h2.global_position + Vector3(0, 1.0, 0))
		overlay._can_drop_data(over_hull, {"type": "module_part", "id": "basic_cannon"})
		await _settle(1)
		_check("drag ghost is created while hovering over the hull",
			overlay.ghost_mesh != null, "no ghost to test cleanup against")
		overlay.notification(Control.NOTIFICATION_DRAG_END)
		await _settle(2)
		_check("drag ghost cleaned up when the drag is cancelled",
			overlay.ghost_mesh == null and overlay.ghost_mesh_mirror == null,
			"ghost=%s mirror=%s" % [str(overlay.ghost_mesh), str(overlay.ghost_mesh_mirror)])

func _probe_hull_scale():
	print("\n--- Probe 6: scaling the hull with the gizmo ---")
	lab.clear_hull()
	await _settle(2)
	lab._place_hull_from_ui("medium_hull")
	await _settle(3)
	var h = _hull()
	if not h:
		_check("hull for scale test", false)
		return
	var mi = h.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var before = _transformed_extents(mi.mesh.get_aabb(), mi.transform)
	await _frame_hull()

	lab._select_module(h)
	await _settle(2)
	var gizmo = h.get_node_or_null("Gizmo3D")
	if not gizmo:
		_check("hull gizmo present", false)
		return
	# Grab the X handle and nudge it: a scale drag must not teleport the mesh.
	gizmo._on_drag_started()
	gizmo._on_dragged(Vector3(0.001, 0, 0), Vector3(1, 0, 0))
	await _settle(3)
	var after = _transformed_extents(mi.mesh.get_aabb(), mi.transform)
	var jump = (after - before).length() / max(before.length(), 0.001)
	_check("hull visual does not jump when a scale drag begins", jump < 0.10,
		"extents %s -> %s (%.0f%% jump) - the fit_scale factor is dropped" % [before, after, jump * 100.0])

	var pm = h.get_node_or_null("PhysicsMesh") as MeshInstance3D
	if pm:
		_check("PhysicsMesh stays in sync with the visual mesh during scaling",
			pm.scale.is_equal_approx(mi.scale),
			"PhysicsMesh.scale=%s MeshInstance3D.scale=%s" % [pm.scale, mi.scale])
	await _shot("08_hull_scaled")

func _probe_tweaks():
	print("\n--- Probe 7: tweak sliders actually deform the mesh ---")
	lab.clear_hull()
	await _settle(2)
	lab._place_hull_from_ui("medium_hull")
	await _settle(3)
	var hit = _deck_hit(0.0, -1.0)
	if not hit:
		_check("deck raycast for tweak test", false)
		return
	lab._place_weapon_from_ui("basic_cannon", hit.position, hit.normal)
	await _settle(3)
	await _frame_hull()
	var cannon: Node3D = null
	for m in _modules():
		if m.get_meta("module_data").type_id == "basic_cannon":
			cannon = m
			break
	if not cannon:
		_check("cannon placed for tweak test", false)
		return

	# rebuild_visual() frees and recreates every child, so names are freshly
	# auto-generated each time and can't be compared. Compare the resulting
	# geometry between two DIFFERENT tweak values instead.
	var VisualBuilder = preload("res://scripts/visual_builder.gd")
	var data = cannon.get_meta("module_data")

	data.tweaks["caliber"] = 1.0
	data.tweaks["barrel_length"] = 1.0
	VisualBuilder.rebuild_visual(cannon)
	await _settle(2)
	var baseline = _mesh_footprint(cannon)

	data.tweaks["caliber"] = 1.8
	data.tweaks["barrel_length"] = 1.5
	VisualBuilder.rebuild_visual(cannon)
	await _settle(2)
	var tweaked = _mesh_footprint(cannon)

	_check("caliber/barrel_length tweaks change the cannon's geometry",
		not baseline.is_equal_approx(tweaked),
		"identical world-space extents %s at caliber 1.0 and 1.8 - build_visual() returns before _apply_tweak_deformations()"
			% baseline)
	await _shot("09_tweaked_cannon")

# Combined local-space extents of every MeshInstance3D under a module, so a
# tweak's effect is measurable regardless of how the mesh tree is structured.
func _mesh_footprint(module: Node3D) -> Vector3:
	var min_p = Vector3.INF
	var max_p = -Vector3.INF
	var stack: Array = [module]
	while not stack.is_empty():
		var n = stack.pop_back()
		# Skip the editor overlays wholesale - the firing arc's child meshes
		# are a fixed 3-unit-radius fan, far bigger than any weapon, and would
		# pin the measurement at 6 x 6 regardless of the tweak.
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


func _probe_primitive_hulls():
	print("\n--- Probe 8: rod/slab/orb/cube are real primitives ---")
	var MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
	var Catalog = preload("res://scripts/module_catalog.gd")
	var medium = MeshAssetLoader.get_hull_mesh("medium_hull")
	for hull_id in ["the_cube", "the_slab", "the_orb", "the_rod"]:
		var mesh = MeshAssetLoader.get_hull_mesh(hull_id)
		_check("%s has a mesh" % hull_id, mesh != null)
		if not mesh:
			continue
		_check("%s is NOT a copy of medium_hull's mesh" % hull_id, mesh != medium)
		# A primitive is built at unit size, so the fit is a pure per-axis
		# stretch onto the catalog box with no rotation.
		var fit = Catalog.get_hull_mesh_fit(hull_id, mesh)
		var rot: Vector3 = fit["rotation"]
		_check("%s needs no orientation correction" % hull_id, rot.length() < 0.001,
			"rotation=%s" % rot)
		var cat: Vector3 = Catalog.get_module_data(hull_id).get("size", Vector3.ONE)
		var aabb = mesh.get_aabb().size
		var sc: Vector3 = fit["scale"]
		var landed = Vector3(aabb.x * sc.x, aabb.y * sc.y, aabb.z * sc.z)
		_check("%s fills its catalog box exactly" % hull_id, landed.distance_to(cat) < 0.01,
			"catalog=%s landed=%s" % [cat, landed])

	lab.clear_hull()
	await _settle(2)
	lab._place_hull_from_ui("the_rod")
	await _settle(3)
	await _frame_hull(-25.0, 20.0)
	await _shot("10_the_rod")
	lab.clear_hull()
	await _settle(2)
	lab._place_hull_from_ui("the_orb")
	await _settle(3)
	await _frame_hull(-25.0, 10.0)
	await _shot("11_the_orb")

func _probe_locomotion_mirroring():
	print("\n--- Probe 9: chiral locomotion mirrors left/right ---")
	for loco in ["legs", "hover_engine", "fixed_wing_engine", "ornithopter_wing", "wheels"]:
		lab.clear_hull()
		await _settle(2)
		lab._place_hull_from_ui("medium_hull")
		await _settle(3)
		lab._place_weapon_from_ui(loco, Vector3.ZERO, Vector3.DOWN)
		await _settle(3)

		var left = []
		var right = []
		for m in _modules():
			if m.get_meta("module_data").type_id != loco:
				continue
			if m.position.x < -0.01:
				left.append(m)
			elif m.position.x > 0.01:
				right.append(m)
		if left.is_empty() or right.is_empty():
			_check("%s spawned a left/right pair" % loco, false,
				"left=%d right=%d" % [left.size(), right.size()])
			continue
		# Every left-side instance must be flagged as the reflected one, and
		# that reflection must actually be applied to its visual children
		# (a negative-determinant basis is a genuine mirror).
		var flagged = 0
		var reflected = 0
		for m in left:
			if m.get_meta("scale_flip_x", false):
				flagged += 1
			for c in m.get_children():
				if c is CollisionObject3D or not (c is Node3D):
					continue
				if c.transform.basis.determinant() < 0.0:
					reflected += 1
					break
		_check("%s left-side instances are flagged mirrored" % loco, flagged == left.size(),
			"%d of %d" % [flagged, left.size()])
		_check("%s left-side geometry is actually reflected" % loco, reflected == left.size(),
			"%d of %d have a reflected child basis" % [reflected, left.size()])
		# The right side must NOT be reflected, or both sides match again -
		# just wrongly.
		var right_reflected = 0
		for m in right:
			for c in m.get_children():
				if c is CollisionObject3D or not (c is Node3D):
					continue
				if c.transform.basis.determinant() < 0.0:
					right_reflected += 1
					break
		_check("%s right-side instances are left unreflected" % loco, right_reflected == 0,
			"%d of %d were reflected too" % [right_reflected, right.size()])
	await _frame_hull()
	await _shot("12_locomotion_mirroring")

func _probe_underside_mounting():
	print("\n--- Probe 10: modules mount base-first on every facet ---")
	lab.clear_hull()
	await _settle(2)
	lab._place_hull_from_ui("medium_hull")
	await _settle(3)

	# For each facet, the module's local +Y (the direction its body projects
	# away from its mounting base) must end up along that surface normal.
	var facets = {
		"top": Vector3.UP,
		"bottom": Vector3.DOWN,
		"left": Vector3.LEFT,
		"right": Vector3.RIGHT,
		"front": Vector3.FORWARD,
		"back": Vector3.BACK,
	}
	for facet_name in facets:
		var n: Vector3 = facets[facet_name]
		var before = _modules().size()
		lab._place_weapon_from_ui("basic_cannon", hull_surface_point(n), n)
		await _settle(2)
		var added = []
		var all = _modules()
		for i in range(before, all.size()):
			added.append(all[i])
		if added.is_empty():
			_check("placed a cannon on the %s facet" % facet_name, false)
			continue
		# A side placement also spawns a MIRRORED twin on the opposite facet,
		# whose own normal is the opposite one - so check each instance
		# against ITS OWN recorded mount normal rather than against the normal
		# we asked for, or the twin looks like a failure when it is correct.
		var ok_count = 0
		for placed in added:
			var own_normal: Vector3 = placed.get_meta("mount_normal", n)
			var body_axis = (placed.global_transform.basis * Vector3.UP).normalized()
			if body_axis.dot(own_normal.normalized()) > 0.99:
				ok_count += 1
		_check("%s-facet module(s) project along their own surface normal" % facet_name,
			ok_count == added.size(), "%d of %d aligned" % [ok_count, added.size()])
	await _frame_hull(-20.0, 16.0)
	await _shot("13_facet_mounting")

func hull_surface_point(n: Vector3) -> Vector3:
	var h = _hull()
	var cat = preload("res://scripts/module_catalog.gd").get_module_data(h.get_meta("type_id")).get("size", Vector3.ONE)
	return h.to_global(Vector3(n.x * cat.x, n.y * cat.y, n.z * cat.z) * 0.5)

func _probe_surface_snapping():
	print("\n--- Probe 11: modules land on the visible hull, not its bounding box ---")
	for hull_id in ["medium_hull", "naval_hull", "airship_hull"]:
		lab.clear_hull()
		await _settle(2)
		lab._place_hull_from_ui(hull_id)
		await _settle(3)
		var h = _hull()
		_check("%s has a precise HullSurface collider" % hull_id,
			h.get_node_or_null("HullSurface") != null)

		# Drop straight down onto the deck through the precise surface, then
		# confirm the returned point is on the rendered mesh rather than up on
		# the bounding box lid.
		var above = h.global_position + Vector3(0, 60, 0)
		var hit = lab.surface_raycast(above, Vector3.DOWN, 200.0)
		if not hit:
			_check("%s deck raycast hits the precise surface" % hull_id, false)
			continue
		var box_top = h.global_position.y
		var col = h.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col and col.shape is BoxShape3D:
			box_top += col.shape.size.y / 2.0
		_check("%s placement point is not above the bounding box lid" % hull_id,
			hit.position.y <= box_top + 0.02,
			"hit y=%.3f box lid y=%.3f" % [hit.position.y, box_top])
	await _shot("14_surface_snapping")

func _probe_firing_envelope():
	print("\n--- Probe 12: pintle firing envelope is a sphere ---")
	lab.clear_hull()
	await _settle(2)
	lab._place_hull_from_ui("medium_hull")
	await _settle(3)
	var hit = _deck_hit(0.0, -1.0)
	if not hit:
		_check("deck raycast for envelope test", false)
		return
	lab._place_weapon_from_ui("heavy_machine_gun", hit.position, hit.normal)
	await _settle(3)
	var gun: Node3D = null
	for m in _modules():
		if m.get_meta("module_data").type_id == "heavy_machine_gun":
			gun = m
			break
	if not gun:
		_check("pintle weapon placed", false)
		return
	lab._select_module(gun)
	await _settle(3)

	var arc = gun.get_node_or_null("ArcCone")
	_check("selected pintle weapon shows a firing envelope", arc != null)
	if not arc:
		return
	var clear_mi = arc.get_node_or_null("ClearArc") as MeshInstance3D
	_check("envelope has clear (unblocked) directions", clear_mi != null)
	if clear_mi and clear_mi.mesh:
		var e = clear_mi.mesh.get_aabb().size
		# A flat horizontal fan has ~zero vertical extent; a sphere does not.
		_check("envelope covers elevation AND depression, not just a flat band",
			e.y > 1.0, "envelope extents=%s" % e)
	var blocked_mi = arc.get_node_or_null("BlockedArc") as MeshInstance3D
	_check("hull occludes part of the envelope (LOS is the limiter)",
		blocked_mi != null and blocked_mi.mesh != null,
		"nothing reported blocked, so the hull is not occluding anything")
	await _frame_hull(-20.0, 12.0)
	await _shot("15_firing_envelope")
