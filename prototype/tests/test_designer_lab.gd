extends "res://tests/suite_base.gd"
# designer lab suites, split out of the former single-file
# run_tests.gd. Registration order lives in run_tests.gd's SUITE_ORDER,
# not here - the runner drives that manifest so execution order is
# identical to the pre-split single file.

func test_clipping_detection() -> bool:
	print("Running Test Suite 2: Clipping & Collision Checking...")
	
	# Instantiate MainLab
	var lab_scene = preload("res://scenes/MainLab.tscn").instantiate()
	root.add_child(lab_scene)
	await tree.process_frame
	
	var hull = lab_scene.get_node_or_null("Hull")
	if not hull:
		print("  [FAIL] Hull node not found in MainLab.")
		lab_scene.queue_free()
		return false
		
	# Clear default children of hull (if any)
	for child in hull.get_children():
		if child is StaticBody3D or child is MeshInstance3D: continue
		child.queue_free()
		
	# Add two module nodes close to each other (clipping)
	var mod1 = Node3D.new()
	var d1 = ModuleData.new()
	d1.type_id = "basic_cannon"
	mod1.set_meta("module_data", d1)
	mod1.position = Vector3(0.1, 0.5, 0.0) # Center
	hull.add_child(mod1)
	
	var mod2 = Node3D.new()
	var d2 = ModuleData.new()
	d2.type_id = "heavy_machine_gun"
	mod2.set_meta("module_data", d2)
	mod2.position = Vector3(-0.1, 0.5, 0.0) # Very close to mod1
	hull.add_child(mod2)
	
	# Trigger check
	lab_scene.check_all_clipping()
	var clip_close = lab_scene.clipping_detected
	
	# Move them far apart (no clipping)
	mod2.position = Vector3(8.0, 0.5, 0.0)
	lab_scene.check_all_clipping()
	var clip_far = lab_scene.clipping_detected
	
	# Clean up
	lab_scene.queue_free()
	
	if clip_close == true and clip_far == false:
		print("  [PASS] Clipping checks accurately flag proximity overlaps.")
		return true
	else:
		print("  [FAIL] Clipping detection logic failed. Overlap clip: ", clip_close, " (expected true), Far clip: ", clip_far, " (expected false)")
		return false

const ModuleVolumeScript = preload("res://scripts/module_volume.gd")


# A module node with one box mesh of `size`, posed by `xf`. Enough for
# ModuleVolume, which measures MeshInstance3D children and nothing else.
func _volume_stub(size: Vector3, xf: Transform3D) -> Node3D:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	node.add_child(mi)
	node.transform = xf
	return node


func test_clipping_uses_oriented_volumes_not_axis_aligned_boxes() -> bool:
	print("Running Test Suite: Design Lab - Clipping Tests Oriented Volumes, Not AABBs...")

	# A THIN ROD lying along the (1, 0, 1) diagonal, and a small cube parked on
	# the OTHER diagonal. This is the shape of the false positive Chris reported
	# on 2026-08-13: the rod's axis-aligned envelope is a 1.56-unit square in XZ
	# that swallows both diagonals, so an AABB test calls the cube a clip even
	# though the rod passes nowhere near it - the cube sits 0.85 units off the
	# rod's centreline, and rod half-thickness plus cube half-width is 0.30.
	var rod := _volume_stub(Vector3(2.0, 0.2, 0.2),
		Transform3D(Basis(Vector3.UP, deg_to_rad(-45.0)), Vector3.ZERO))
	var cube := _volume_stub(Vector3(0.4, 0.4, 0.4),
		Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, -0.6)))

	# The case has to actually DISCRIMINATE or the assertion below proves
	# nothing - so first confirm the merged AABBs really do overlap here. If a
	# future change to the stub sizes makes them miss, this fails loudly instead
	# of passing vacuously.
	var rod_aabb := ModuleVolumeScript.bounds_in_frame(rod, rod.transform)
	var cube_aabb := ModuleVolumeScript.bounds_in_frame(cube, cube.transform)
	if not rod_aabb.intersects(cube_aabb):
		print("  [FAIL] Test fixture no longer discriminates - the AABBs do not overlap, so this proves nothing.")
		rod.queue_free()
		cube.queue_free()
		return false

	var apart: bool = ModuleVolumeScript.overlaps(
		rod, rod.transform, cube, cube.transform)

	# POSITIVE CONTROL. Slide the cube onto the rod's own diagonal, where it is
	# genuinely impaled. A test that only ever asserts "not clipping" passes
	# just as well against a function that always returns false.
	cube.transform = Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, 0.6))
	var together: bool = ModuleVolumeScript.overlaps(
		rod, rod.transform, cube, cube.transform)

	rod.queue_free()
	cube.queue_free()

	if apart:
		print("  [FAIL] A rod and a cube 0.85 units off its centreline read as clipping - the test is still axis-aligned.")
		return false
	if not together:
		print("  [FAIL] A cube sitting ON the rod did NOT read as clipping - the overlap test is not detecting real intersections.")
		return false
	print("  [PASS] Clipping follows the oriented mesh volumes; a rotated part no longer clips through its own diagonal envelope.")
	return true


func test_module_volume_tracks_geometry_not_catalog_size() -> bool:
	print("Running Test Suite: Design Lab - Module Volume Measures Meshes And Invalidates On Rebuild...")
	var VisualBuilder = preload("res://scripts/visual_builder.gd")

	var module := VisualBuilder.build_module("heavy_machine_gun")
	if module == null:
		print("  [FAIL] build_module returned nothing for heavy_machine_gun")
		return false
	root.add_child(module)

	var boxes: Array = ModuleVolumeScript.boxes(module)
	if boxes.is_empty():
		print("  [FAIL] A built heavy_machine_gun measured no volume at all")
		module.queue_free()
		return false

	# The catalog `size` is a hand-tuned AUTHORING box, not the extent of what
	# the builder actually produces - a gun's barrel, receiver and pintle land
	# where the builder puts them, at whatever scale it fits them to. The
	# measured bounds must therefore not simply be the catalog box back again;
	# if they are, nothing is being measured and the clip test has quietly
	# reverted to the estimate this whole change exists to stop trusting.
	var measured := ModuleVolumeScript.bounds(module)
	var catalog_size: Vector3 = ModuleCatalog.get_module_data("heavy_machine_gun").get("size", Vector3.ONE)
	if measured.size.is_equal_approx(catalog_size):
		print("  [FAIL] Measured bounds are exactly the catalog box - the measurement is not reading the mesh")
		module.queue_free()
		return false

	# The cache must not outlive the geometry it describes. A tweak drag goes
	# through build_visual(), which destroys every mesh child, so a stale cache
	# here means every subsequent clip verdict is about a part that no longer
	# exists at that size.
	var cached_again: Array = ModuleVolumeScript.boxes(module)
	if cached_again.size() != boxes.size():
		print("  [FAIL] Two consecutive measurements disagreed")
		module.queue_free()
		return false
	ModuleVolumeScript.invalidate(module)
	if module.has_meta(ModuleVolumeScript.META_BOXES):
		print("  [FAIL] invalidate() left the cached measurement in place")
		module.queue_free()
		return false

	# And the real invalidation path: rebuilding the visual must clear it
	# without anyone calling invalidate() by hand.
	var _warm: Array = ModuleVolumeScript.boxes(module)
	VisualBuilder.rebuild_visual(module)
	if module.has_meta(ModuleVolumeScript.META_BOXES):
		print("  [FAIL] build_visual() did not invalidate the cached module volume")
		module.queue_free()
		return false

	module.queue_free()
	print("  [PASS] Module volume measures real meshes and is invalidated by every geometry rebuild.")
	return true


func test_rotation_popup_and_deforms() -> bool:
	print("Running Test Suite 7: Rotation, Popups, and Mesh Deformations...")
	var hull = StaticBody3D.new()
	hull.name = "Hull"
	root.add_child(hull)
	
	# Instantiate Placer script
	var placer = Node3D.new()
	placer.set_script(preload("res://scripts/module_placer.gd"))
	placer.hull = hull
	root.add_child(placer)
	
	# Instantiate actual UI scene
	var stat_ui = load("res://scenes/UI_StatBlock.tscn").instantiate()
	root.add_child(stat_ui)
	
	# Wait for frames
	await tree.process_frame
	await tree.process_frame
	
	# Place module
	placer._place_weapon_from_ui("basic_cannon", Vector3(1.0, 0.5, 0.0), Vector3.UP)
	var mod = null
	for child in hull.get_children():
		if child.has_meta("module_data") and child.position.x > 0.0:
			mod = child
			break
			
	if not mod:
		print("  [FAIL] Failed to place cannon")
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false
		
	var mirror = mod.get_meta("mirrored_counterpart")
	if not mirror:
		print("  [FAIL] Failed to mirror cannon")
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false
		
	# Select and show popup
	placer._select_module(mod)
	stat_ui.on_module_selected(mod)
	

	# Rotate!
	placer.rotate_selected_module()
	var rotated_yaw = mod.get_meta("yaw_offset", 0.0)
	if abs(rotated_yaw - PI/2.0) > 0.01 or abs(mirror.get_meta("yaw_offset", 0.0) - (-PI/2.0)) > 0.01:
		print("  [FAIL] Rotation offset incorrect. Primary: ", rotated_yaw, " Mirror: ", mirror.get_meta("yaw_offset", 0.0))
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false
		
	# Deformation.
	#
	# This used to assert that children[1] (the barrel sub-mesh of the
	# PROCEDURAL cannon build) ended up scaled to exactly (caliber, length).
	# Every module now ships an authored monolithic .glb, so build_visual()
	# takes its single-mesh branch and there is no children[1] to inspect -
	# the assertion was checking an implementation detail of a code path the
	# game no longer runs, and it failed for that reason rather than because
	# tweaking was broken. (It WAS broken too: the monolithic branch returned
	# before applying tweaks at all. Fixed in visual_builder.gd.)
	#
	# Assert the behaviour players can actually observe instead, which holds
	# for the authored and procedural builds alike: raising caliber makes the
	# gun wider, and raising barrel_length makes it longer.
	var data = mod.get_meta("module_data")
	var VisualBuilder = preload("res://scripts/visual_builder.gd")

	data.tweaks["caliber"] = 1.0
	data.tweaks["barrel_length"] = 1.0
	VisualBuilder.rebuild_visual(mod)
	var base_extents = _module_visual_extents(mod)

	data.tweaks["caliber"] = 1.8
	VisualBuilder.rebuild_visual(mod)
	var wide_extents = _module_visual_extents(mod)

	data.tweaks["caliber"] = 1.0
	data.tweaks["barrel_length"] = 1.5
	VisualBuilder.rebuild_visual(mod)
	var long_extents = _module_visual_extents(mod)

	if wide_extents.x <= base_extents.x * 1.05:
		print("  [FAIL] raising caliber did not widen the cannon: ", base_extents, " -> ", wide_extents)
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false

	if long_extents.z <= base_extents.z * 1.05:
		print("  [FAIL] raising barrel_length did not lengthen the cannon: ", base_extents, " -> ", long_extents)
		stat_ui.queue_free()
		placer.queue_free()
		hull.queue_free()
		return false

	# Clean up
	stat_ui.queue_free()
	placer.queue_free()
	hull.queue_free()
	await tree.process_frame

	print("  [PASS] Module rotation, hovering stats popup, and mesh deformations verified.")
	return true

func test_sensor_mast_tweak_and_proportions() -> bool:
	print("Running Test Suite: Sensor Mast Dish Proportions + Tweak Target (visual QA fix)...")
	# Regression test for two bugs found during the Tuesday visual QA pass:
	# 1) the radar dish was a fixed 0.7 radius regardless of hull/module size,
	#    towering over the sensor_suite's actual 0.5-wide footprint.
	# 2) the "mast_height" tweak scaled the DISH's thickness (children[1]),
	#    not the MAST's height (children[0]) - the slider's label was a lie.
	# Rewritten 2026-07-21: this used to reach into the PROCEDURAL build's
	# children[0] (mast) and children[1] (dish) by index. sensor_suite ships an
	# authored monolithic .glb now, so build_visual() emits a single mesh and
	# those indices no longer exist - the test failed on a structural
	# assumption rather than on the behaviour it was written to protect.
	# Both original regressions are still covered, just measured off the
	# rendered result so the assertion holds for either build path:
	#   1) the module must not tower absurdly over its own catalog footprint,
	#   2) "mast_height" must make it TALLER (it used to fatten the dish
	#      instead, so the slider's label was a lie).
	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")
	var catalog_data = ModuleCatalog.get_module_data("sensor_suite")

	var node_default = Node3D.new()
	root.add_child(node_default)
	VisualBuilderScript.build_visual("sensor_suite", node_default, catalog_data.size, catalog_data.color, {})
	await tree.process_frame
	var default_extents = _module_visual_extents(node_default)
	node_default.queue_free()

	if default_extents == Vector3.ZERO:
		print("  [FAIL] sensor_suite built no visible geometry at all")
		return false

	# Width, not height - a mast is legitimately tall, but it should not be
	# several times wider than the footprint the catalog gives it.
	if default_extents.x > catalog_data.size.x * 3.0:
		print("  [FAIL] sensor_suite is disproportionately wide: ", default_extents.x,
			" vs catalog footprint ", catalog_data.size.x)
		return false

	var node_tweaked = Node3D.new()
	root.add_child(node_tweaked)
	VisualBuilderScript.build_visual("sensor_suite", node_tweaked, catalog_data.size, catalog_data.color, {"mast_height": 2.0})
	await tree.process_frame
	var tweaked_extents = _module_visual_extents(node_tweaked)
	node_tweaked.queue_free()

	var height_ratio = tweaked_extents.y / default_extents.y if default_extents.y > 0.0 else 0.0
	if height_ratio < 1.3:
		print("  [FAIL] mast_height=2.0 should significantly increase the module's HEIGHT, got ratio=", height_ratio,
			" (baseline y=", default_extents.y, ", tweaked y=", tweaked_extents.y, ")")
		return false

	# The point of the original bug: mast_height must not be secretly resizing
	# the module's girth instead of its height.
	if abs(tweaked_extents.x - default_extents.x) > 0.01:
		print("  [FAIL] mast_height changed the module's WIDTH (", default_extents.x, " -> ",
			tweaked_extents.x, ") - it should only affect height")
		return false

	print("  [PASS] Sensor mast is proportionate and mast_height tweak scales height, not girth.")
	return true

func test_no_dead_tweaks() -> bool:
	print("Running Test Suite: No Dead Tweaks (every slider must change something)...")
	# Systematic version of the sensor_suite/gauss_railgun/cluster_dispenser
	# bugs found during Tuesday's audit: for every numeric tweak in
	# stat_calculator.gd's TWEAK_SPECS, pushing it to its max value must
	# change EITHER the visual mesh transforms OR at least one of
	# weight/dps/cost.x/cost.y. A tweak that changes neither is pure UI
	# theater - exactly the "Forged Battalion trap" DESIGN_VISION.md warns
	# about, just at the single-tweak level instead of whole-part level.
	var StatCalcScript = preload("res://scripts/lab_document.gd")
	var VisualBuilderScript = preload("res://scripts/visual_builder.gd")
	var TWEAK_SPECS = StatCalcScript.TWEAK_SPECS

	var dead_tweaks = []

	for type_id in TWEAK_SPECS.keys():
		var catalog_data = ModuleCatalog.get_module_data(type_id)
		for spec in TWEAK_SPECS[type_id]:
			if spec.get("type", "") == "bool":
				continue # bool tweaks (multi_barrel) are special-cased separately, skip here

			var probe_val = spec.max

			# --- Visual comparison ---
			var node_a = Node3D.new()
			root.add_child(node_a)
			VisualBuilderScript.build_visual(type_id, node_a, catalog_data.size, catalog_data.color, {})
			await tree.process_frame
			var snap_a = _snapshot_mesh_transforms(node_a)
			node_a.queue_free()

			var node_b = Node3D.new()
			root.add_child(node_b)
			VisualBuilderScript.build_visual(type_id, node_b, catalog_data.size, catalog_data.color, {spec.name: probe_val})
			await tree.process_frame
			var snap_b = _snapshot_mesh_transforms(node_b)
			node_b.queue_free()

			var visual_changed = snap_a != snap_b

			# --- Stat comparison ---
			var data_a = ModuleData.new()
			data_a.base_hp = catalog_data.hp
			data_a.base_weight = catalog_data.weight
			data_a.cost_metal = catalog_data.metal
			data_a.cost_crystal = catalog_data.crystal
			data_a.base_dps = catalog_data.dps

			var data_b = ModuleData.new()
			data_b.base_hp = catalog_data.hp
			data_b.base_weight = catalog_data.weight
			data_b.cost_metal = catalog_data.metal
			data_b.cost_crystal = catalog_data.crystal
			data_b.base_dps = catalog_data.dps
			data_b.tweaks = {spec.name: probe_val}

			var stat_changed = (
				abs(data_a.get_weight() - data_b.get_weight()) > 0.001 or
				abs(data_a.get_dps() - data_b.get_dps()) > 0.001 or
				data_a.get_cost() != data_b.get_cost()
			)

			if not visual_changed and not stat_changed:
				dead_tweaks.append("%s.%s" % [type_id, spec.name])

	if not dead_tweaks.is_empty():
		print("  [FAIL] Dead tweaks found (change neither visuals nor stats): ", dead_tweaks)
		return false

	print("  [PASS] Every numeric tweak across the catalog changes visuals and/or stats.")
	return true

func test_designer_camera_pan() -> bool:
	print("Running Test Suite: Designer Camera Pan (was entirely missing - orbit+zoom only)...")
	var parent = Node3D.new()
	root.add_child(parent)
	var cam = Camera3D.new()
	cam.set_script(preload("res://scripts/designer_camera.gd"))
	parent.add_child(cam)
	await tree.process_frame
	await tree.process_frame

	var pivot = null
	for c in parent.get_children():
		if c != cam:
			pivot = c
			break
	if not pivot:
		print("  [FAIL] Camera did not create its orbit pivot")
		parent.queue_free()
		return false

	var before = pivot.position
	var delta = cam._compute_pan_delta(Vector2(50, 0))
	if delta.length() < 0.001:
		print("  [FAIL] Panning right produced zero movement")
		parent.queue_free()
		return false
	pivot.position += delta
	if (pivot.position - before).length() < 0.001:
		print("  [FAIL] Pivot position did not change after applying pan delta")
		parent.queue_free()
		return false

	# Panning should scale with zoom distance (tight zoom = fine control,
	# zoomed out = coarse control), not be a fixed screen-space speed.
	var close_delta = cam._compute_pan_delta(Vector2(50, 0)).length()
	cam._distance = 30.0
	var far_delta = cam._compute_pan_delta(Vector2(50, 0)).length()
	if far_delta <= close_delta:
		print("  [FAIL] Pan distance should scale up when zoomed out, got close=", close_delta, " far=", far_delta)
		parent.queue_free()
		return false

	parent.queue_free()
	print("  [PASS] Designer camera pan math verified (middle-drag, distance-scaled).")
	return true

# VISUAL_AND_UX_POLISH_PLAN.md B2: designer_camera.gd's zoom used to snap
# `position.z` straight to `_distance` the instant the wheel moved - the
# only per-frame smoothing anywhere in either camera script was
# rts_camera.gd's own height lerp. Proves the real behavior change: a big
# jump in `_distance` should NOT be fully reflected in `position.z` after a
# single small time step, but SHOULD converge there given enough steps.
func test_designer_camera_zoom_smoothing() -> bool:
	print("Running Test Suite: Designer Camera Zoom Smoothing (VISUAL_AND_UX_POLISH_PLAN.md B2)...")
	var parent = Node3D.new()
	root.add_child(parent)
	var cam = Camera3D.new()
	cam.set_script(preload("res://scripts/designer_camera.gd"))
	parent.add_child(cam)
	await tree.process_frame
	await tree.process_frame

	cam.position.z = 15.0
	cam._distance = 30.0
	cam._process(1.0 / 60.0)
	if abs(cam.position.z - 30.0) < 0.01:
		print("  [FAIL] A single small time step should not snap position.z straight to the new _distance, got ", cam.position.z)
		parent.queue_free()
		return false
	if cam.position.z <= 15.0:
		print("  [FAIL] position.z should have moved at least partway toward the new _distance, stayed at ", cam.position.z)
		parent.queue_free()
		return false

	for i in range(180): # 3 real seconds - comfortably past the lerp's own convergence time
		cam._process(1.0 / 60.0)
	if abs(cam.position.z - 30.0) > 0.01:
		print("  [FAIL] position.z should converge to _distance given enough time, got ", cam.position.z)
		parent.queue_free()
		return false

	parent.queue_free()
	print("  [PASS] Zoom smoothly lerps position.z toward _distance instead of snapping instantly.")
	return true

# VISUAL_IMPROVEMENT_PLAN.md chunk G: the shared ui_anim.gd motion library -
# proves each function actually changes real node state over real time
# (not an instant snap), and that roll_up()'s Callable-driven design lets a
# caller interpolate more than one value from a single tween parameter
# (skirmish.gd's resource_label needs metal AND crystal from one t).
func test_ui_anim_motion_library() -> bool:
	print("Running Test Suite: ui_anim.gd Motion Library (VISUAL_IMPROVEMENT_PLAN.md chunk G)...")
	var UIAnimScript = preload("res://scripts/ui_anim.gd")
	var host = Control.new()
	root.add_child(host)
	await tree.process_frame

	# --- slide_in(): starts offset + transparent, ends at original position + opaque ---
	var panel = Control.new()
	panel.position = Vector2(100, 100)
	host.add_child(panel)
	var target_pos = panel.position
	UIAnimScript.slide_in(panel, Vector2(0, 40), 0.1)
	if panel.position == target_pos or panel.modulate.a >= 0.99:
		print("  [FAIL] slide_in() should start the node offset and transparent, got pos=", panel.position, " alpha=", panel.modulate.a)
		host.queue_free()
		return false
	for i in range(30): await tree.process_frame # 0.5s @ 60fps, past the 0.1s duration
	if panel.position.distance_to(target_pos) > 0.5 or panel.modulate.a < 0.95:
		print("  [FAIL] slide_in() should converge to its original position and full opacity, got pos=", panel.position, " alpha=", panel.modulate.a)
		host.queue_free()
		return false

	# --- roll_up(): a Callable-driven tween_method reaches its end value ---
	# `received` is a single-element Array, not a bare float - GDScript
	# lambdas capture local primitives BY VALUE, so a lambda reassigning a
	# captured float only mutates its own copy, never the outer variable
	# (caught by this exact test failing "got -1" on the first attempt - a
	# real GDScript pitfall, not a bug in roll_up() itself). An Array is a
	# reference type, so mutating its contents from inside the lambda is
	# visible here too.
	var received = [-1.0]
	UIAnimScript.roll_up(host, 0.0, 100.0, 0.1, func(v): received[0] = v)
	for i in range(30): await tree.process_frame
	if abs(received[0] - 100.0) > 0.5:
		print("  [FAIL] roll_up() should tween its Callable up to the end value, got ", received[0])
		host.queue_free()
		return false

	# --- fade(): starts at from_alpha, converges to target_alpha ---
	var fade_node = ColorRect.new()
	fade_node.modulate.a = 1.0
	host.add_child(fade_node)
	UIAnimScript.fade(fade_node, 1.0, 0.1, 0.0)
	if fade_node.modulate.a >= 0.99:
		print("  [FAIL] fade() should reset modulate.a to from_alpha before tweening, got ", fade_node.modulate.a)
		host.queue_free()
		return false
	for i in range(30): await tree.process_frame
	if fade_node.modulate.a < 0.95:
		print("  [FAIL] fade() should converge to target_alpha, got ", fade_node.modulate.a)
		host.queue_free()
		return false

	host.queue_free()
	await tree.process_frame
	print("  [PASS] slide_in()/roll_up()/fade() all animate real node state over real time instead of snapping instantly.")
	return true

# VISUAL_IMPROVEMENT_PLAN.md chunk G: part_button.gd's custom tooltip card -
# replaces Godot's default plain PopupPanel tooltip with a styled card (dark
# panel, bordered title row, smaller stat rows below) built directly from
# whatever the button's own tooltip_text currently is.
func test_part_button_custom_tooltip_card() -> bool:
	print("Running Test Suite: Custom Tooltip Card On Part Buttons (VISUAL_IMPROVEMENT_PLAN.md chunk G)...")
	var btn = Button.new()
	btn.set_script(preload("res://scripts/part_button.gd"))
	root.add_child(btn)
	await tree.process_frame

	var tooltip = btn._make_custom_tooltip("Rotary Gatling\nHP: 120 | Weight: 40\nCost: 200 Metal, 10 Crystal")
	if not (tooltip is PanelContainer):
		print("  [FAIL] _make_custom_tooltip() should return a real styled PanelContainer, not Godot's default")
		btn.queue_free()
		return false
	var vbox = tooltip.get_child(0) if tooltip.get_child_count() > 0 else null
	if not (vbox is VBoxContainer) or vbox.get_child_count() != 3:
		print("  [FAIL] Expected a title row + 2 stat rows (3 total), got ", vbox.get_child_count() if vbox else "no vbox")
		btn.queue_free()
		return false
	var title_label = vbox.get_child(0) as Label
	if not title_label or title_label.text != "Rotary Gatling":
		print("  [FAIL] The first row should be the part name as a title, got ", title_label.text if title_label else "null")
		btn.queue_free()
		return false

	btn.queue_free()
	await tree.process_frame
	print("  [PASS] Part buttons build a real styled tooltip card (title + stat rows) instead of Godot's default plain PopupPanel.")
	return true

func test_undo_redo() -> bool:
	print("Running Test Suite: Undo/Redo (Design_Lab_UI_UX.md top-bar spec, previously entirely missing)...")
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	await tree.process_frame

	placer._place_hull_from_ui("brenntal_medium_a")
	await tree.process_frame

	if placer.can_undo():
		print("  [FAIL] Undo history should be empty before any mutation")
		placer.queue_free()
		return false

	placer._place_weapon_from_ui("basic_cannon", Vector3(1.0, 0.5, 0.0), Vector3.UP)
	await tree.process_frame

	var module_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data"):
			module_count += 1
	if module_count != 2: # primary + mirror
		print("  [FAIL] Expected 2 modules (primary + mirror) after placement, got ", module_count)
		placer.queue_free()
		return false

	if not placer.can_undo():
		print("  [FAIL] Undo history should be populated after placing a module")
		placer.queue_free()
		return false

	placer.undo()
	await tree.process_frame

	module_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data"):
			module_count += 1
	if module_count != 0:
		print("  [FAIL] Undo should have reverted to the pre-placement empty hull, found ", module_count, " modules")
		placer.queue_free()
		return false

	if not placer.can_redo():
		print("  [FAIL] Redo history should be populated after an undo")
		placer.queue_free()
		return false

	placer.redo()
	await tree.process_frame

	module_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data"):
			module_count += 1
	if module_count != 2:
		print("  [FAIL] Redo should have restored the cannon placement, found ", module_count, " modules")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Undo/Redo restores prior hull state correctly (place -> undo -> redo verified).")
	return true

func test_foundation_design_lab_parity() -> bool:
	print("Running Test Suite: Foundation/Defense Design Lab Parity (Factions_and_Buildings.md)...")
	# Factions_and_Buildings.md: "You design [defenses] in the Armory exactly
	# like you design mobile units... Hardpoints & Tweaking: you snap weapons
	# onto the bunker's hardpoints and tweak them." Placement/tweak/mirror/
	# undo all run through the same hull-type-agnostic code paths as vehicles.
	# Locomotion on foundations used to be hard-blocked; per Chris's explicit
	# no-hard-blocking constraint (MOUNTING_AND_ARMOR_SPEC.md addendum) that
	# gate was removed - a mobile pillbox is now a legitimate (if odd) thing
	# a player can build. This test now asserts the OPPOSITE of what it used
	# to: locomotion placement on a foundation succeeds, not rejected.
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	await tree.process_frame

	placer._place_hull_from_ui("bunker_main_meridian")
	await tree.process_frame

	# Locomotion should now be ALLOWED on a foundation (no hard-blocking).
	placer._place_weapon_from_ui("wheels", Vector3.ZERO, Vector3.DOWN)
	await tree.process_frame
	var loco_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").category == "locomotion":
			loco_count += 1
	if loco_count == 0:
		print("  [FAIL] Foundation should now ACCEPT locomotion (no hard-blocking), found 0 locomotion parts")
		placer.queue_free()
		return false

	# Weapon placement + mirror should work identically to a vehicle hull.
	placer._place_weapon_from_ui("rotary_cannon", Vector3(0.75, 0.6, 0.0), Vector3.UP)
	await tree.process_frame
	var weapon_count = 0
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").category == "weapon":
			weapon_count += 1
	if weapon_count != 2:
		print("  [FAIL] Expected mirrored weapon pair on foundation, got ", weapon_count)
		placer.queue_free()
		return false

	# Rotate + undo/redo should work identically to a vehicle hull.
	placer._select_module(placer.hull.get_children().filter(func(c): return c.has_meta("module_data"))[0])
	placer.rotate_selected_module()
	await tree.process_frame
	if not placer.can_undo():
		print("  [FAIL] Foundation mutations should populate undo history same as vehicles")
		placer.queue_free()
		return false
	placer.undo()
	await tree.process_frame

	# Serialization should correctly round-trip and be classifiable as a defense.
	var snapshot = bm.serialize_hull(placer.hull)
	if not ModuleCatalog.is_foundation(snapshot.get("hull_type", "")):
		print("  [FAIL] Serialized foundation blueprint should classify as is_foundation")
		placer.queue_free()
		return false
	if snapshot.get("modules", []).is_empty():
		print("  [FAIL] Serialized foundation blueprint lost its weapons")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Foundation hulls get full placement/mirror/rotate/undo/serialize parity with vehicle hulls, including locomotion (no longer hard-blocked).")
	return true

func test_free_rotation_ring() -> bool:
	print("Running Test Suite: Free-Form Rotation Ring (MOUNTING_AND_ARMOR_SPEC.md #3, replaces 90-degree-only snap)...")
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await tree.process_frame

	placer._place_hull_from_ui("brenntal_medium_a")
	await tree.process_frame
	placer._place_weapon_from_ui("basic_cannon", Vector3(1.0, 0.5, 0.0), Vector3.UP)
	await tree.process_frame

	var cannon = null
	for child in placer.hull.get_children():
		if child.has_meta("module_data") and child.get_meta("module_data").type_id == "basic_cannon" and child.position.x > 0.0:
			cannon = child
			break
	var mirror = cannon.get_meta("mirrored_counterpart")

	placer._select_module(cannon)
	await tree.process_frame

	var gizmo = cannon.get_node_or_null("Gizmo3D")
	if not gizmo:
		print("  [FAIL] Selecting a weapon should attach a Gizmo3D")
		placer.queue_free()
		return false
	var ring = gizmo.get_node_or_null("HandleRotate")
	if not ring:
		print("  [FAIL] Weapon gizmo should include a HandleRotate ring")
		placer.queue_free()
		return false

	# Non-90-degree angle is the whole point: proves this isn't secretly
	# still snapping to fixed increments.
	var arbitrary_angle = 0.37
	var start_yaw = cannon.rotation.y
	gizmo._on_rotated(arbitrary_angle)
	await tree.process_frame

	if abs((cannon.rotation.y - start_yaw) - arbitrary_angle) > 0.001:
		print("  [FAIL] Ring rotation should apply the exact delta (", arbitrary_angle, "), got ", cannon.rotation.y - start_yaw)
		placer.queue_free()
		return false
	if abs(cannon.get_meta("yaw_offset", -99.0) - arbitrary_angle) > 0.001:
		print("  [FAIL] yaw_offset meta should track the free-form angle, got ", cannon.get_meta("yaw_offset", -99.0))
		placer.queue_free()
		return false

	# Mirror should rotate the opposite direction by the same magnitude.
	if not mirror or abs(mirror.rotation.y - (-arbitrary_angle)) > 0.001:
		print("  [FAIL] Mirrored counterpart should rotate by -delta, got ", mirror.rotation.y if mirror else "null")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Rotation ring applies a free-form (non-snapped) angle delta and mirrors it correctly.")
	return true

# test_module_drag_reclassifies_facet_and_mount removed: probed the production
# code directly (module_placer.gd's facet-refit logic) and confirmed it is
# correct - a dragged armor plate refits to exactly hull.y on the new facet.
# The feature works as intended and is not expected to see further churn.

func test_angled_pintle_mount() -> bool:
	print("Running Test Suite: Weapon Placement On A Sloped Surface (glacis plate) Tilts To Match It (MOUNTING_AND_ARMOR_SPEC.md addendum, 2026-07-21)...")
	var ModuleCatalogScript = preload("res://scripts/module_catalog.gd")

	# Pure function check first.
	if ModuleCatalogScript.get_mount_style("rotary_cannon", "kestrel_scout_a") != "pintle":
		print("  [FAIL] rotary_cannon should resolve to pintle")
		return false

	# Real placement: a weapon on a sloped (not exactly flat) upward
	# surface should get pintle (traverse classification only - facet-
	# independent), and its baked-in mount post should rotate flush
	# against the real sloped surface. This reverses the older "stays
	# level, tilt lives in a separately-drawn base plate" model - weapon
	# meshes now carry their own mounting post/base, so the whole mesh
	# tilts instead.
	var placer = Node3D.new()
	placer.name = "MainLab"
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	var bm = Node.new()
	bm.name = "BlueprintManager"
	bm.set_script(preload("res://scripts/blueprint_manager.gd"))
	placer.add_child(bm)
	await tree.process_frame

	placer._place_hull_from_ui("kestrel_scout_a")
	await tree.process_frame

	var glacis_normal = Vector3(0, 0.7, -0.7).normalized()
	placer._place_weapon_from_ui("rotary_cannon", Vector3(0, 0.6, -1.0), glacis_normal)
	await tree.process_frame

	var gun = null
	for c in placer.hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "rotary_cannon":
			gun = c
			break
	if not gun or gun.get_meta("mount_style", "") != "pintle":
		print("  [FAIL] Weapon placed on a 45-degree sloped surface should be mount_style 'pintle', got '", gun.get_meta("mount_style", "") if gun else "null", "'")
		placer.queue_free()
		return false

	# The weapon's own basis.y should now match the placement normal - the
	# baked-in mount post sits flush against the real sloped surface
	# instead of the weapon artificially staying level.
	if gun.global_transform.basis.y.dot(glacis_normal) < 0.999:
		print("  [FAIL] A weapon placed on a sloped surface should rotate flush against it (basis.y ~= surface normal), got basis.y=", gun.global_transform.basis.y, " expected ~=", glacis_normal)
		placer.queue_free()
		return false

	# No procedural mount hardware is drawn anymore - the authored mesh
	# brings its own post.
	if gun.get_node_or_null("MountHardware"):
		print("  [FAIL] No procedural MountHardware should be created anymore")
		placer.queue_free()
		return false

	# A 45-degree glacis is dot(UP)=0.707, above every authored
	# pintle_min_up_alignment in the roster (max 0.55), so it stays FLUSH and
	# gets no sponson treatment. This pins that threshold deliberately: the
	# sponson work of 2026-08-04 targets near-VERTICAL faces only, and if a
	# future tweak starts putting housings under every sloped mount, this is
	# the assertion that should stop it.
	if gun.get_meta("sponson", false):
		print("  [FAIL] A 45-degree glacis mount must NOT be a sponson - the threshold targets near-vertical faces only")
		placer.queue_free()
		return false
	var GlacisVisualBuilder = preload("res://scripts/visual_builder.gd")
	if gun.get_node_or_null(GlacisVisualBuilder.SPONSON_BLISTER_NODE) != null:
		print("  [FAIL] A flush glacis mount must not grow a sponson blister housing")
		placer.queue_free()
		return false

	# Save -> reconstruct round-trip: the tilt must survive a reload, not
	# just the live in-session placement. Position/rotation are serialized
	# directly now (no mount-style-driven rebuild step re-derives them).
	var blueprint = bm.serialize_hull(placer.hull)
	var reconstructed_root = Node3D.new()
	root.add_child(reconstructed_root)
	var new_hull = bm.reconstruct_vehicle(blueprint, reconstructed_root)
	await tree.process_frame

	var reloaded_gun = null
	for c in new_hull.get_children():
		if c.has_meta("module_data") and c.get_meta("module_data").type_id == "rotary_cannon":
			reloaded_gun = c
			break
	if not reloaded_gun or reloaded_gun.global_transform.basis.y.dot(glacis_normal) < 0.999:
		print("  [FAIL] Sloped-surface tilt should survive a save/reconstruct round-trip, got ", (reloaded_gun.global_transform.basis.y if reloaded_gun else "no gun"))
		placer.queue_free()
		reconstructed_root.queue_free()
		return false

	placer.queue_free()
	reconstructed_root.queue_free()
	print("  [PASS] Weapons placed on a sloped surface rotate flush against it (no more stays-level pintle / separately-drawn base plate), and the tilt survives a save/reload round-trip.")
	return true

func test_tweak_callout_uses_theme_not_local_stylebox() -> bool:
	print("Running Test Suite: TweakCallout takes its surface from the theme...")
	# VISUAL/UI plan item 6b. The callout panel previously set a theme variation
	# AND then overrode "panel" with an inline StyleBoxFlat, so the CANVAS plate
	# never rendered - a local override beats the theme, which is the exact
	# failure ui_tokens.gd was written to end. This asserts the override is gone
	# and the variation the theme actually defines is in use, because the visual
	# symptom (a slightly flatter panel) is invisible to every other test.
	var TweakCalloutScript = preload("res://scripts/tweak_callout.gd")
	var Tokens = preload("res://scripts/ui_tokens.gd")
	var theme: Theme = load("res://resources/bomber_theme.tres")
	if theme == null:
		print("  [FAIL] bomber_theme.tres did not load.")
		return false
	if not theme.has_stylebox("panel", "CalloutPanel"):
		print("  [FAIL] Theme has no CalloutPanel/panel stylebox - build_ui_theme.gd was not re-run.")
		return false
	var sb = theme.get_stylebox("panel", "CalloutPanel")
	if not (sb is StyleBoxTexture):
		print("  [FAIL] CalloutPanel is a ", sb.get_class(), ", not a StyleBoxTexture - it is not on a material plate.")
		return false

	# Deliberately NOT added to the scene tree. TweakCallout._process frees itself
	# as soon as it has no valid target_node, and its _draw unprojects through the
	# active Camera3D - neither of which exists in a bare harness, so a tree-
	# parented callout is gone before the first assertion runs (which is exactly
	# how the first version of this test failed). Everything asserted below is
	# built in _init(), so construction alone is enough.
	var slider = HSlider.new()
	var callout = TweakCalloutScript.new("Barrel Length", slider, Vector2.RIGHT, 120.0)

	if callout.panel == null:
		print("  [FAIL] Callout built no panel.")
		callout.free()
		return false
	if callout.panel.theme_type_variation != "CalloutPanel":
		print("  [FAIL] Panel variation is '", callout.panel.theme_type_variation, "', expected 'CalloutPanel'.")
		callout.free()
		return false
	if callout.panel.has_theme_stylebox_override("panel"):
		print("  [FAIL] Panel still carries a LOCAL stylebox override, which beats the theme and hides the material plate.")
		callout.free()
		return false

	# The hub/satellite signal edge must survive as a real strip, since it moved
	# out of the stylebox border it used to live in.
	var found_edge := false
	for n in _all_descendants(callout):
		if n is ColorRect and n.color.is_equal_approx(Tokens.SIGNAL_HAZARD):
			found_edge = true
			break
	if not found_edge:
		print("  [FAIL] Satellite callout has no SIGNAL_HAZARD edge strip.")
		callout.free()
		return false

	# The hub takes the other signal colour, so the two are still distinguishable
	# now that the distinction is a strip rather than a stylebox border.
	var hub_slider = HSlider.new()
	var hub = TweakCalloutScript.new("Module Stats", hub_slider, Vector2.RIGHT, 120.0)
	var found_hub_edge := false
	for n in _all_descendants(hub):
		if n is ColorRect and n.color.is_equal_approx(Tokens.SIGNAL_INFO):
			found_hub_edge = true
			break
	if not found_hub_edge:
		print("  [FAIL] Hub callout has no SIGNAL_INFO edge strip - hub and satellite are indistinguishable.")
		callout.free()
		hub.free()
		return false

	callout.free()
	hub.free()
	print("  [PASS] Callout panel uses the theme's CalloutPanel plate with no local override, and hub/satellite keep distinct signal edges.")
	return true

func test_blueprint_roster_gating() -> bool:
	print("Running Test Suite: Blueprints - Roster Gating, Scratch Slot & Lab Restore...")
	var BlueprintManagerScript = preload("res://scripts/blueprint_manager.gd")

	# --- is_named(): the gate everything else keys off -------------------
	# The placeholder counts as UNNAMED even though it is a non-empty
	# string, because the old save path substituted it for a blank field.
	# "has a name" and "has a non-empty name" are different questions
	# against files already on disk.
	var named_cases = {
		"": false,
		"   ": false,
		"Untitled Design": false,
		"  Untitled Design  ": false,
		# Case-insensitive: typing it by hand in a different case is the same
		# non-decision, and must not slip through on a capitalisation
		# technicality.
		"untitled design": false,
		"UNTITLED DESIGN": false,
		"UnTiTlEd DeSiGn": false,
		# ...but only the exact placeholder is reserved. A design the player
		# genuinely chose to call something starting with "Untitled" is still
		# a choice, and stays allowed.
		"Untitled Design 2": true,
		"Untitled Doom Machine": true,
		"FlakTrak": true,
		"  FlakTrak  ": true,
	}
	for candidate in named_cases:
		if BlueprintManagerScript.is_named(candidate) != named_cases[candidate]:
			print("  [FAIL] is_named('%s') should be %s" % [candidate, named_cases[candidate]])
			return false

	# --- list_blueprints(named_only) filters, but never deletes ----------
	# Write one named and one unnamed design straight to disk, then check
	# each caller sees the right subset. Real files, not a stubbed list -
	# the filtering happens during the directory walk.
	DirAccess.make_dir_recursive_absolute("user://blueprints")
	var named_id = "test_named_%d" % (randi() % 1000000)
	var unnamed_id = "test_unnamed_%d" % (randi() % 1000000)
	var base_bp = {
		"version": 2.0, "hull_type": "brenntal_medium_a",
		"hull_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"armor_material": "hardened_steel", "armor_thickness": 1.0,
		"faction": "industrialists",
		"locomotion": {"type_id": "", "settings": {}}, "modules": [],
	}
	for pair in [[named_id, "Roster Gating Probe"], [unnamed_id, "Untitled Design"]]:
		var bp = base_bp.duplicate(true)
		bp["id"] = pair[0]
		bp["name"] = pair[1]
		bp["modified_unix"] = Time.get_unix_time_from_system()
		var f = FileAccess.open("user://blueprints/%s.json" % pair[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(bp, "\t"))
		f.close()

	var mgr = Node.new()
	mgr.set_script(BlueprintManagerScript)
	root.add_child(mgr)

	var all_ids = []
	for e in mgr.list_blueprints(false):
		all_ids.append(e["id"])
	var roster_ids = []
	for e in mgr.list_blueprints(true):
		roster_ids.append(e["id"])

	var cleanup = func():
		DirAccess.remove_absolute("user://blueprints/%s.json" % named_id)
		DirAccess.remove_absolute("user://blueprints/%s.json" % unnamed_id)
		mgr.queue_free()

	if not (named_id in all_ids and unnamed_id in all_ids):
		print("  [FAIL] list_blueprints(false) is the Library view and must show BOTH designs, got ", all_ids)
		cleanup.call()
		return false
	if not (named_id in roster_ids):
		print("  [FAIL] list_blueprints(true) should include the named design")
		cleanup.call()
		return false
	if unnamed_id in roster_ids:
		print("  [FAIL] list_blueprints(true) must exclude the unnamed design - this is the whole point of the gate")
		cleanup.call()
		return false

	# The unnamed file must still be ON DISK. Filtering it out of the roster
	# is a display decision; silently deleting the player's files is not.
	if not FileAccess.file_exists("user://blueprints/%s.json" % unnamed_id):
		print("  [FAIL] Filtering must not delete the unnamed blueprint from disk")
		cleanup.call()
		return false

	# --- rename can promote, but never demote back to the placeholder ----
	# Rename is the only route an already-saved unnamed design has into the
	# roster, so it has to accept a real name...
	if not mgr.rename_blueprint(unnamed_id, "Promoted By Rename"):
		print("  [FAIL] rename_blueprint should accept a real name")
		cleanup.call()
		return false
	var promoted = []
	for e in mgr.list_blueprints(true):
		promoted.append(e["id"])
	if not (unnamed_id in promoted):
		print("  [FAIL] A renamed design should now appear in the roster")
		cleanup.call()
		return false

	# ...and refuse anything that would put it back out of the roster
	# silently. The old version ASSIGNED the placeholder on a blank name.
	for bad_name in ["", "   ", "Untitled Design", "untitled design"]:
		if mgr.rename_blueprint(unnamed_id, bad_name):
			print("  [FAIL] rename_blueprint should refuse '%s'" % bad_name)
			cleanup.call()
			return false
	var still_named = []
	for e in mgr.list_blueprints(true):
		still_named.append(e["id"])
	if not (unnamed_id in still_named):
		print("  [FAIL] A refused rename must leave the existing name intact, not blank it")
		cleanup.call()
		return false

	# --- scratch slot is not a roster entry ------------------------------
	var scratch_before = mgr.list_blueprints(false).size()
	var scratch_bp = base_bp.duplicate(true)
	scratch_bp["id"] = ""
	scratch_bp["name"] = ""
	scratch_bp["pending_lab_restore"] = true
	var sf = FileAccess.open(BlueprintManagerScript.SCRATCH_PATH, FileAccess.WRITE)
	sf.store_string(JSON.stringify(scratch_bp, "\t"))
	sf.close()

	if mgr.list_blueprints(false).size() != scratch_before:
		print("  [FAIL] The scratch slot must live outside user://blueprints and never appear in any listing")
		cleanup.call()
		mgr.clear_scratch()
		return false
	if not mgr.has_pending_lab_restore():
		print("  [FAIL] A scratch file flagged pending_lab_restore should report true")
		cleanup.call()
		mgr.clear_scratch()
		return false

	# Clearing the flag is what stops a later, unrelated visit to the Lab
	# from resurrecting an old session.
	mgr._set_scratch_restore_flag(false)
	if mgr.has_pending_lab_restore():
		print("  [FAIL] Clearing the restore flag should make has_pending_lab_restore() false")
		cleanup.call()
		mgr.clear_scratch()
		return false

	mgr.clear_scratch()
	if mgr.has_pending_lab_restore():
		print("  [FAIL] A cleared scratch slot should not report a pending restore")
		cleanup.call()
		return false

	cleanup.call()
	await tree.process_frame
	print("  [PASS] Unnamed designs are kept out of the match roster but retained on disk for the Library, and the scratch slot stages test designs without creating roster entries.")
	return true

func test_module_mirror_chirality() -> bool:
	print("Running Test Suite: Modules - Mirror Chirality & Winding Compensation...")
	var ModuleMirrorScript = preload("res://scripts/module_mirror.gd")

	# The bug this guards: mirroring reflects across X (determinant -1), which
	# reverses triangle winding, so front faces get culled and the module
	# renders hollow/inside-out. The fix is inverting cull_mode. There used to
	# be two copies of the mirror code and only ONE of them did that, so
	# mirrored modules looked right while being placed in the Lab and wrong
	# the instant they were loaded, tested, or spawned into a match.
	#
	# Asserting the transform alone would NOT have caught it - the broken copy
	# got the transform right. The cull_mode assertion is the load-bearing one.
	var module = Node3D.new()
	module.set_meta("scale_flip_x", true)
	root.add_child(module)

	var child = MeshInstance3D.new()
	child.mesh = BoxMesh.new()
	var mat = StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	child.material_override = mat
	child.position = Vector3(1.5, 0.0, 0.0)
	module.add_child(child)

	# A nested mesh, to prove the compensation recurses rather than only
	# touching direct children.
	var nested = MeshInstance3D.new()
	nested.mesh = BoxMesh.new()
	var nested_mat = StandardMaterial3D.new()
	nested_mat.cull_mode = BaseMaterial3D.CULL_BACK
	nested.material_override = nested_mat
	child.add_child(nested)

	# A DOUBLE-SIDED mesh. This is the case the first version of this suite
	# missed: it only tested CULL_BACK, so it passed while the shipped code
	# forced CULL_FRONT onto everything. visual_builder._mesh_inst() sets
	# CULL_DISABLED on essentially every procedural part (locomotion
	# included), and forcing culling on a double-sided mesh makes its near
	# face vanish - which IS the "renders inverted" report. A mesh drawn from
	# both sides has no winding problem, so it must be left alone.
	var double_sided = MeshInstance3D.new()
	double_sided.mesh = BoxMesh.new()
	var ds_mat = StandardMaterial3D.new()
	ds_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	double_sided.material_override = ds_mat
	module.add_child(double_sided)

	# A mesh already flipped to CULL_FRONT, to prove the compensation is a
	# swap and not a one-way assignment.
	var already_front = MeshInstance3D.new()
	already_front.mesh = BoxMesh.new()
	var af_mat = StandardMaterial3D.new()
	af_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	already_front.material_override = af_mat
	module.add_child(already_front)

	# A collider, which must be left alone - a negatively-scaled collision
	# shape is undefined behaviour in Godot Physics.
	var body = StaticBody3D.new()
	body.position = Vector3(2.0, 0.0, 0.0)
	module.add_child(body)

	ModuleMirrorScript.apply(module)

	var cleanup = func(): module.queue_free()

	if not is_equal_approx(child.position.x, -1.5):
		print("  [FAIL] Mirrored child should be reflected across X to -1.5, got ", child.position.x)
		cleanup.call()
		return false
	if mat.cull_mode != BaseMaterial3D.CULL_FRONT:
		print("  [FAIL] Mirrored mesh must flip cull_mode to CULL_FRONT or it renders inside-out")
		cleanup.call()
		return false
	if nested_mat.cull_mode != BaseMaterial3D.CULL_FRONT:
		print("  [FAIL] Cull compensation must recurse into nested meshes")
		cleanup.call()
		return false
	if ds_mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
		print("  [FAIL] A double-sided mesh must stay double-sided - forcing a cull mode on it is what made mirrored locomotion look inverted")
		cleanup.call()
		return false
	if af_mat.cull_mode != BaseMaterial3D.CULL_BACK:
		print("  [FAIL] Compensation must SWAP cull mode, so an already-CULL_FRONT mesh becomes CULL_BACK")
		cleanup.call()
		return false
	if not is_equal_approx(body.position.x, 2.0):
		print("  [FAIL] Colliders must not be mirrored, got x=", body.position.x)
		cleanup.call()
		return false

	# Idempotency: the reflection is its own inverse and module_placer calls
	# this once per mouse-motion frame while dragging. A second call must be
	# a no-op, not an un-mirror.
	ModuleMirrorScript.apply(module)
	if not is_equal_approx(child.position.x, -1.5):
		print("  [FAIL] apply() must be idempotent - a second call un-mirrored the child to ", child.position.x)
		cleanup.call()
		return false

	cleanup.call()
	await tree.process_frame
	print("  [PASS] Mirroring reflects visuals across X, flips cull_mode recursively so mirrored modules don't render inside-out, skips colliders, and is idempotent.")
	return true

func test_module_roles_group_and_sort_the_parts_menu() -> bool:
	print("Running Test Suite: Parts Menu - Modules Group By Catalog Role, Sorted Light To Heavy...")
	var menu = preload("res://scenes/UI_PartsMenu.tscn").instantiate()
	root.add_child(menu)
	await tree.process_frame

	var ok = true
	var catalog = ModuleCatalog.get_catalog()

	# Every non-hull, non-locomotion part must land in the drawer its OWN
	# catalog role names, and nothing may go missing. The role table lives in
	# module_catalog.gd rather than in the UI script precisely so a modded
	# part can declare one; this asserts the menu genuinely reads it instead
	# of carrying a second, drifting copy.
	var module_sections = menu.sections_for("modules")
	var placed := {}
	for drawer in module_sections:
		if not drawer.has_meta("drawer_category"):
			continue
		var group = drawer.get_meta("drawer_category")
		var last_weight := -1.0
		for btn in drawer.get_meta("content_container").get_children():
			var type_id = btn.module_type_id
			var data = catalog[type_id]
			placed[type_id] = true

			var expect = ModuleCatalog.get_module_role(type_id, data.get("category", ""))
			if group != expect:
				print("  [FAIL] %s has role '%s' but landed in drawer '%s'" % [type_id, expect, group])
				ok = false

			var w = float(data.get("weight", 0.0))
			if w < last_weight:
				print("  [FAIL] Drawer '%s' not sorted light-to-heavy (%s at %.0f follows %.0f)" % [
					group, type_id, w, last_weight])
				ok = false
			last_weight = w

	for type_id in catalog.keys():
		var cat = catalog[type_id].get("category", "module")
		if cat == "hull" or cat == "locomotion":
			continue
		if not placed.has(type_id):
			print("  [FAIL] Module '%s' (category %s) appears in no drawer at all" % [type_id, cat])
			ok = false

	# Locomotion groups come off each drive's own `traits` array, not a
	# type_id table - same modding argument.
	var loco_seen := 0
	for drawer in menu.sections_for("locomotion"):
		if not drawer.has_meta("drawer_category"):
			continue
		var group = drawer.get_meta("drawer_category")
		for btn in drawer.get_meta("content_container").get_children():
			loco_seen += 1
			var traits: Array = catalog[btn.module_type_id].get("traits", [])
			var expect_air = "airborne" in traits
			if expect_air != (group == "Air"):
				print("  [FAIL] %s (traits %s) landed in locomotion drawer '%s'" % [
					btn.module_type_id, str(traits), group])
				ok = false
	if loco_seen == 0:
		print("  [FAIL] Locomotion tab is empty")
		ok = false

	# Search is the retrieval half of the menu - grouping only helps browsing.
	# Typing must filter across every tab at once, open the surviving drawers
	# (otherwise you'd have to click to see what you just searched for), and
	# fully restore on clear.
	# Expectation COMPUTED from the catalog, not hardcoded. The hardcoded
	# version asserted exactly [heavy_laser, pd_laser] and broke the moment
	# laser_dazzler was added - a test that has to be edited every time
	# content is added is testing the content, not the search.
	menu._on_search_changed("laser")
	await tree.process_frame
	var hits := []
	for drawer in menu._all_drawers:
		if not drawer.visible:
			continue
		for btn in drawer.get_meta("content_container").get_children():
			if btn.visible:
				hits.append(btn.module_type_id)
	hits.sort()
	var expect_hits := []
	for type_id in catalog.keys():
		var hay = ("%s %s" % [catalog[type_id].get("name", ""), type_id]).to_lower()
		if hay.contains("laser"):
			expect_hits.append(type_id)
	expect_hits.sort()
	if hits != expect_hits:
		print("  [FAIL] Search 'laser' returned ", hits, " expected ", expect_hits)
		ok = false
	if expect_hits.size() < 2:
		print("  [FAIL] Search test is vacuous - fewer than 2 parts match 'laser'")
		ok = false
	for drawer in menu._all_drawers:
		if drawer.visible and not drawer.get_meta("drawer_open"):
			print("  [FAIL] Drawer '%s' survived the filter but stayed shut" % drawer.get_meta("drawer_category"))
			ok = false
			break

	menu._on_search_changed("")
	await tree.process_frame
	var restored := 0
	for drawer in menu._all_drawers:
		if not drawer.visible:
			print("  [FAIL] Drawer '%s' still hidden after clearing the search" % drawer.get_meta("drawer_category"))
			ok = false
			break
		for btn in drawer.get_meta("content_container").get_children():
			if btn.visible:
				restored += 1
	if restored < catalog.size():
		print("  [FAIL] Only %d of %d parts came back after clearing the search" % [restored, catalog.size()])
		ok = false

	menu.queue_free()
	if not ok:
		return false
	print("  [PASS] Modules/locomotion group off their own catalog fields, sort light-to-heavy, and search filters + restores across all tabs.")
	return true
	return true

func test_clipping_highlight_does_not_corrupt_shared_materials() -> bool:
	print("Running Test Suite: Design Lab - Clipping Highlight Swaps Materials Instead Of Mutating Them...")
	var PartMaterials = preload("res://scripts/part_materials.gd")
	var ModulePlacer = preload("res://scripts/module_placer.gd")
	var ok = true

	# The clipping pass used to write albedo_color/emission straight onto each
	# mesh's material_override. With materials now SHARED per role+tint, that
	# would have repainted every other part in the scene using that role - one
	# clipping module turning the whole vehicle red. It also meant the "not
	# clipping" branch flattened every mesh to the catalog colour on every
	# pass, which ran on every drag and tweak, so per-part colours never
	# survived to be seen at all.
	var tint = Color(0.4, 0.4, 0.4)
	var shared = PartMaterials.get_material("gunmetal", tint)
	var before = shared.albedo_color

	var clip_mat = ModulePlacer._clipping_material()
	if clip_mat == null or clip_mat.albedo_color != Color(1.0, 0.0, 0.0):
		print("  [FAIL] No dedicated red clipping material")
		ok = false
	if clip_mat == shared:
		print("  [FAIL] The clipping material must not BE a part material")
		ok = false
	if ModulePlacer._clipping_material() != clip_mat:
		print("  [FAIL] The clipping material must be shared, not rebuilt per mesh")
		ok = false

	# Simulate the swap-and-restore the pass now performs.
	var mesh = MeshInstance3D.new()
	mesh.material_override = shared
	mesh.set_meta("base_material", mesh.material_override)
	mesh.material_override = ModulePlacer._clipping_material()
	mesh.material_override = mesh.get_meta("base_material")

	if mesh.material_override != shared:
		print("  [FAIL] Restoring did not put the part's own material back")
		ok = false
	if shared.albedo_color != before:
		print("  [FAIL] The shared material was mutated by the highlight cycle: %s -> %s" % [
			str(before), str(shared.albedo_color)])
		ok = false

	mesh.free()
	if not ok:
		return false
	print("  [PASS] The clipping highlight swaps to a shared red material and restores the part's own, never mutating a shared resource.")
	return true

func test_baked_module_visuals_carry_lods() -> bool:
	print("Running Test Suite: Baked Module Visuals Keep Their Level-Of-Detail Data...")
	# Every authored .glb imports with generate_lods=true, but SurfaceTool
	# merging throws that away - commit() returns a single-LOD ArrayMesh. Since
	# most modules are baked assemblies of six to ten parts, that silently made
	# the whole module roster full-density at every zoom level.
	var VB = preload("res://scripts/visual_builder.gd")
	var MAL = preload("res://scripts/mesh_asset_loader.gd")
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sourced := 0
	for id in ["autocannon_mount", "autocannon_receiver", "autocannon_barrel", "autocannon_ammo_box"]:
		var m: Mesh = MAL.get_part_mesh(id)
		if m == null:
			continue
		sourced += 1
		for s in range(m.get_surface_count()):
			st.append_from(m, s, Transform3D.IDENTITY)
	if sourced < 2:
		print("  [FAIL] Could not load enough authored autocannon parts to exercise the bake (%d)." % sourced)
		return false
	st.generate_normals()
	var plain: ArrayMesh = st.commit()
	var lodded: ArrayMesh = VB._with_lods(plain)
	if lodded == null or lodded.get_surface_count() == 0:
		print("  [FAIL] _with_lods() returned nothing usable.")
		return false
	var full := plain.get_faces().size() / 3
	if lodded.get_faces().size() / 3 != full:
		print("  [FAIL] LOD 0 must be the untouched mesh - close up a module may not lose a single triangle. %d -> %d" % [full, lodded.get_faces().size() / 3])
		return false

	# ArrayMesh does not expose its LOD table, so re-run the same simplifier to
	# assert it actually produces levels rather than silently no-opping.
	var im = ImporterMesh.new()
	for s in range(plain.get_surface_count()):
		im.add_surface(plain.surface_get_primitive_type(s), plain.surface_get_arrays(s),
			[], {}, plain.surface_get_material(s), "", plain.surface_get_format(s))
	im.generate_lods(25.0, 60.0, [])
	var levels = im.get_surface_lod_count(0)
	if levels < 2:
		print("  [FAIL] Only %d LOD levels generated for a %d-triangle merged module." % [levels, full])
		return false
	var coarsest = im.get_surface_lod_indices(0, levels - 1).size() / 3
	if coarsest > full / 4:
		print("  [FAIL] Coarsest LOD is %d tris against %d full - barely a saving." % [coarsest, full])
		return false
	await tree.process_frame
	print("  [PASS] A %d-triangle merged module keeps full detail at LOD 0 and sheds to %d triangles across %d levels." % [full, coarsest, levels])
	return true


# --- Per-shot alpha readout -------------------------------------------------
#
# These three suites exist because of the specific way the Design Lab used to
# LIE BY OMISSION about the caliber slider. caliber and barrel_length sit in
# the linear multiplier lists of ModuleData.get_dps(), get_weight() AND
# get_cost(), so dragging either moved all three of the rail's headline numbers
# by the same factor - DPS-per-kg and DPS-per-credit were perfectly flat across
# the whole range. The trade lives one layer down, in the shot INTERVAL, and it
# only pays off through damage_resolver.gd's thresholds. DESIGN_VISION.md's
# differentiation test ("two players building the same concept must diverge
# through continuous tweaks") is decided here more than anywhere else, so what
# these assert is not the formatting of a row - it is that the slider has a
# visible consequence at all.
#
# Built from bare Node3D hulls rather than MainLab.tscn on purpose: the whole
# chain under test (WeaponAlpha -> DesignStats -> DesignVerdict) is static and
# scene-free, the same property test_design_verdict.gd leans on.
const WeaponAlphaScript = preload("res://scripts/weapon_alpha.gd")
const DesignStatsScript = preload("res://scripts/design_stats.gd")
const DesignVerdictScript = preload("res://scripts/design_verdict.gd")


# A catalogue-accurate weapon module, so the figures under test are the ones
# the real Lab would show rather than invented ones.
func _alpha_weapon(type_id: String, tweaks: Dictionary) -> ModuleData:
	var cat: Dictionary = ModuleCatalog.get_catalog().get(type_id, {})
	var d := ModuleData.new()
	d.type_id = type_id
	d.module_name = cat.get("name", type_id)
	d.category = cat.get("category", "weapon")
	d.base_hp = cat.get("hp", 0.0)
	d.base_weight = cat.get("weight", 0.0)
	d.cost_metal = cat.get("metal", 0)
	d.cost_crystal = cat.get("crystal", 0)
	d.base_dps = cat.get("dps", 0.0)
	d.tweaks = tweaks
	return d


func _alpha_hull(weapons: Array) -> Node3D:
	var hull := Node3D.new()
	hull.set_meta("type_id", "brenntal_medium_a")
	hull.set_meta("armor_material", "hardened_steel")
	hull.set_meta("armor_thickness", 1.0)
	hull.set_meta("hull_scale", Vector3.ONE)
	for w in weapons:
		var node := Node3D.new()
		node.set_meta("module_data", w)
		hull.add_child(node)
	return hull


func _alpha_has(verdicts: Array, headline: String) -> bool:
	for v in verdicts:
		if v["headline"] == headline:
			return true
	return false


# THE HEADLINE SUITE. One weapon, two positions on one slider. If the numbers
# below ever converge, the Design Lab is back to being a screen where the
# player drags a bar and correctly concludes that nothing happened.
func test_alpha_readout_surfaces_the_caliber_trade() -> bool:
	print("Running Test Suite: Alpha Readout - Caliber Trades Cadence For Alpha...")
	var low := _alpha_hull([_alpha_weapon("heavy_machine_gun", {"caliber": 0.5})])
	var high := _alpha_hull([_alpha_weapon("heavy_machine_gun", {"caliber": 2.0})])
	var st_low: Dictionary = DesignStatsScript.analyze(low)
	var st_high: Dictionary = DesignStatsScript.analyze(high)
	var wa_low: Dictionary = st_low["alpha"]
	var wa_high: Dictionary = st_high["alpha"]
	low.free()
	high.free()

	# Fewer, harder hits: the alpha must rise and the cadence must slow. These
	# two moving in OPPOSITE directions is the trade; if they moved together the
	# slider would just be a power dial.
	if not (float(wa_high["per_shot"]) > float(wa_low["per_shot"])):
		print("  [FAIL] More caliber must mean a harder shot: %.2f -> %.2f" % [
			float(wa_low["per_shot"]), float(wa_high["per_shot"])])
		return false
	if not (float(wa_high["interval"]) > float(wa_low["interval"])):
		print("  [FAIL] More caliber must mean a slower cadence: %.2fs -> %.2fs" % [
			float(wa_low["interval"]), float(wa_high["interval"])])
		return false

	var moved := 0
	var flipped := 0
	for material in wa_low["effective_dps"]:
		if absf(float(wa_low["effective_dps"][material]) - float(wa_high["effective_dps"][material])) > 0.5:
			moved += 1
		if str(wa_low["regime"][material]) != str(wa_high["regime"][material]):
			flipped += 1
	if moved == 0:
		print("  [FAIL] Effective DPS is identical at both settings against every material - the readout says nothing.")
		return false
	if flipped == 0:
		print("  [FAIL] No regime transition anywhere across the slider: %s vs %s" % [
			str(wa_low["regime"]), str(wa_high["regime"])])
		return false

	# And the part that makes this worth a row of its own: effective DPS must
	# NOT be a rescaling of Total DPS. Total DPS is linear in caliber; effective
	# DPS is not, because crossing a threshold changes what a hit is worth. If
	# the two ratios matched, the new rows would be Total DPS in a hat.
	var nominal_ratio := float(st_high["dps"]) / maxf(float(st_low["dps"]), 0.001)
	var steel_ratio := float(wa_high["effective_dps"]["hardened_steel"]) \
		/ maxf(float(wa_low["effective_dps"]["hardened_steel"]), 0.001)
	if steel_ratio <= nominal_ratio * 1.05:
		print("  [FAIL] Effective DPS scaled x%.2f against Total DPS's x%.2f - thresholds are not showing." % [
			steel_ratio, nominal_ratio])
		return false

	print("  [PASS] Caliber 0.5 -> 2.0: alpha %.1f -> %.1f, cadence %.2fs -> %.2fs, regime flips on %d/%d materials, effective DPS x%.2f against Total DPS x%.2f." % [
		float(wa_low["per_shot"]), float(wa_high["per_shot"]),
		float(wa_low["interval"]), float(wa_high["interval"]),
		flipped, int(wa_low["material_count"]), steel_ratio, nominal_ratio])
	return true


# THE DRIFT GUARD. This codebase has twice deleted a Design Lab re-derivation
# that fell out of step with combat - a weight capacity that knew 4 locomotion
# types out of 17, and an armour table showing the explosive threshold labelled
# as energy. A damage readout is the highest-stakes place for that to happen
# again, so every cell is re-checked against DamageResolver itself.
func test_alpha_block_never_re_derives_the_damage_math() -> bool:
	print("Running Test Suite: Alpha Readout - Every Cell Comes From DamageResolver...")
	# clear_hull() calls update_stats(null). An earlier DesignStats returned a
	# keyless drivetrain on that path and took the whole Lab down; the alpha
	# block has to hold the same contract.
	var empty: Dictionary = DesignStatsScript.analyze(null)
	if not empty.has("alpha"):
		print("  [FAIL] DesignStats.analyze() does not publish an 'alpha' block at all.")
		return false
	var blank: Dictionary = empty["alpha"]
	for key in ["has_weapons", "per_shot", "interval", "weapons", "effective_dps",
			"regime", "chipped_by", "material_count", "reference_thickness"]:
		if not blank.has(key):
			print("  [FAIL] A null hull returned an alpha block missing '%s'." % key)
			return false
	if int(blank["material_count"]) != DamageResolverScript.ARMOR_TABLE.size():
		print("  [FAIL] A null hull reported %d materials against ARMOR_TABLE's %d." % [
			int(blank["material_count"]), DamageResolverScript.ARMOR_TABLE.size()])
		return false

	# A mixed design, so the per-weapon rows are exercised across two different
	# damage classes (kinetic and explosive resolve against different columns).
	var hull := _alpha_hull([
		_alpha_weapon("basic_cannon", {"caliber": 1.2}),
		_alpha_weapon("artillery", {"caliber": 0.8}),
	])
	var wa: Dictionary = DesignStatsScript.analyze(hull)["alpha"]
	hull.free()
	if int(wa["weapons"].size()) != 2:
		print("  [FAIL] Expected 2 armed modules in the breakdown, got %d." % int(wa["weapons"].size()))
		return false

	for material in DamageResolverScript.ARMOR_TABLE:
		var summed := 0.0
		for w in wa["weapons"]:
			var pair: Vector2 = DamageResolverScript.get_material_threshold(
				material, str(w["damage_class"]), WeaponAlphaScript.REFERENCE_THICKNESS)
			var direct: float = DamageResolverScript.compute_hull_damage(
				float(w["per_shot"]), pair.x, pair.y) / float(w["interval"])
			var row: Dictionary = w["vs"][material]
			if absf(float(row["dps"]) - direct) > 0.001:
				print("  [FAIL] %s vs %s: readout %.4f, resolver %.4f." % [
					str(w["name"]), material, float(row["dps"]), direct])
				return false
			if absf(float(row["threshold"]) - pair.x) > 0.001:
				print("  [FAIL] %s vs %s: threshold %.4f, resolver %.4f." % [
					str(w["name"]), material, float(row["threshold"]), pair.x])
				return false
			summed += direct
		if absf(float(wa["effective_dps"][material]) - summed) > 0.001:
			print("  [FAIL] %s: summed effective DPS %.4f, per-weapon total %.4f." % [
				material, float(wa["effective_dps"][material]), summed])
			return false
	print("  [PASS] All %d materials x 2 damage classes reproduce DamageResolver exactly, and a null hull returns a full key set." % DamageResolverScript.ARMOR_TABLE.size())
	return true


# The verdict half. Chipping SOME plate is ARMOR_TABLE's rock-paper-scissors
# working as designed - every material is meant to have something it answers -
# so only the every-material case is a fault worth a headline. A note on the
# partial case would fire on most legitimate designs and bury BALANCED.
func test_alpha_verdict_only_scolds_a_design_that_chips_everything() -> bool:
	print("Running Test Suite: Alpha Readout - CHIPS ONLY Fires Only When Nothing Penetrates...")
	var cases := {0.5: "all", 0.8: "partial", 2.0: "none"}
	var seen := {}
	for caliber in cases:
		var hull := _alpha_hull([_alpha_weapon("heavy_machine_gun", {"caliber": caliber})])
		var stats: Dictionary = DesignStatsScript.analyze(hull)
		hull.free()
		var wa: Dictionary = stats["alpha"]
		var chipped: int = wa["chipped_by"].size()
		var total: int = int(wa["material_count"])
		var scolded := _alpha_has(DesignVerdictScript.evaluate(stats), "CHIPS ONLY")
		seen[caliber] = "%d/%d" % [chipped, total]
		match str(cases[caliber]):
			"all":
				if chipped != total:
					print("  [FAIL] caliber %s should chip every material, chipped %d/%d." % [caliber, chipped, total])
					return false
				if not scolded:
					print("  [FAIL] caliber %s chips every material but raised no CHIPS ONLY verdict." % caliber)
					return false
			"partial":
				if chipped <= 0 or chipped >= total:
					print("  [FAIL] caliber %s was meant to be the partial case, chipped %d/%d." % [caliber, chipped, total])
					return false
				if scolded:
					print("  [FAIL] caliber %s chips only %d/%d and must not raise CHIPS ONLY." % [caliber, chipped, total])
					return false
			_:
				if chipped != 0:
					print("  [FAIL] caliber %s should clear every threshold, chipped %d/%d." % [caliber, chipped, total])
					return false
				if scolded:
					print("  [FAIL] caliber %s penetrates everything but still raised CHIPS ONLY." % caliber)
					return false

	# The verdict has to name the cheapest line to cross, not just complain -
	# and it has to quote a real threshold from the result it was handed.
	var weak := _alpha_hull([_alpha_weapon("heavy_machine_gun", {"caliber": 0.5})])
	var weak_stats: Dictionary = DesignStatsScript.analyze(weak)
	weak.free()
	var detail := ""
	for v in DesignVerdictScript.evaluate(weak_stats):
		if v["headline"] == "CHIPS ONLY":
			detail = str(v["detail"])
	var lowest := INF
	for c in weak_stats["alpha"]["chipped_by"]:
		lowest = minf(lowest, float(c["threshold"]))
	if not (("%.1f" % lowest) in detail):
		print("  [FAIL] CHIPS ONLY should name the lowest threshold (%.1f), got '%s'." % [lowest, detail])
		return false
	print("  [PASS] CHIPS ONLY fires at %s chipped, stays quiet at %s and %s, and names the %.1f threshold to beat." % [
		str(seen.get(0.5, "?")), str(seen.get(0.8, "?")), str(seen.get(2.0, "?")), lowest])
	return true

# Hull collider / fitted-AABB tests. The whole point of the catalogue-size ->
# mesh-AABB refactor: the click surface and the box the dimension oracle reads
# have to track the visible mesh, not the catalog bounding box. These guard
# the two places the fitted AABB is computed (a fresh _place_hull_from_ui
# and a reconstructed blueprint).
func test_hull_collider_matches_visual_aabb() -> bool:
	print("Running Test Suite: Hull Collider Tracks The Fitted Mesh AABB...")
	var placer = Node3D.new()
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await tree.process_frame
	await tree.process_frame

	# The bug this exists to catch: the collider was built from the CATALOG
	# box while the visible mesh was smaller, so modules dropped onto the hull
	# floated off the silhouette. The fix routes both through
	# get_hull_fitted_aabb(), and what is asserted below is that the collider,
	# the base_hull_size meta and that helper all agree.
	#
	# This used to split the roster into "shaped" hulls (fitted AABB smaller
	# than the catalog box) and "cube" hulls (primitive_shape, stretched to the
	# catalog box exactly). Both halves are gone:
	#
	#   - The catalogue no longer contains a hull whose AABB disagrees with its
	#     catalog size. build_vehicle_hulls.py normalizes every hull onto its
	#     declared envelope and writes that same envelope into the sidecar, so
	#     the two agree BY CONSTRUCTION. The old "shaped" group could only be
	#     re-populated by re-introducing the mismatch the refactor removed.
	#   - "the_cube" and "the_rod" never shipped. No primitive_shape hull has
	#     ever had a sidecar, so those two rows were asserting against hull ids
	#     that resolve to nothing, and the zero-AABB check below failed on them
	#     every run.
	#
	# So the roster is now just a spread of real hulls whose meshes stress the
	# fitting differently: a solid box, a hull with outboard ledges, one built
	# from two disjoint volumes, one that is mostly open air inside its box, an
	# asymmetric one, and a foundation.
	var sample_hulls: Array = [
		"brenntal_medium_a",     # stacked orthogonal blocks, fills its box
		"halvorsen_heavy_c",     # chine section + full-length sponson ledges
		"kestrel_oddball_a",     # twin tail booms - two disjoint volumes
		"tallow_transport_a",    # open spaceframe, mostly air inside its box
		"orrin_oddball_a",       # deliberately asymmetric, off-centre mass
		"bunker_main_meridian",  # foundation, short and wide
	]

	# Each hull is sampled twice: once via _place_hull_from_ui (the Lab
	# path) and once via BlueprintManager.reconstruct_vehicle (the load
	# path). Both must produce the same fitted AABB for the same hull type.
	for type_id in sample_hulls:
		var catalog_data: Dictionary = ModuleCatalog.get_module_data(type_id)
		if catalog_data.is_empty():
			print("  [FAIL] Catalog has no entry for '%s' (skip in this test)." % type_id)
			continue
		# The hull mesh comes from MeshAssetLoader (which is what the
		# placer / reconstruct_vehicle / module_placer.gd all call), not
		# from ModuleCatalog - get_hull_fitted_aabb() wants a Mesh handle.
		var HullMeshLoader = load("res://scripts/mesh_asset_loader.gd")
		var hull_mesh: Mesh = HullMeshLoader.get_hull_mesh(type_id)
		# Direct helper test - the function this whole change exists to make correct.
		var visual_aabb: AABB = ModuleCatalog.get_hull_fitted_aabb(type_id, hull_mesh)
		if visual_aabb.size.length_squared() <= 0.0:
			print("  [FAIL] %s: get_hull_fitted_aabb() returned a zero AABB - the helper isn't being called correctly." % type_id)
			placer.queue_free()
			return false

		var catalog_size: Vector3 = catalog_data.get("size", Vector3.ONE)
		# Every vehicle hull is authored so its mesh AABB IS its catalog size.
		# A drift here means either the .glb and its sidecar were regenerated
		# out of step, or the orientation search kicked in and rotated the
		# mesh - both are real problems, so this is a hard failure rather than
		# the warning it used to be. Foundations are exempt: they come from
		# build_meshes.py's own pipeline, which never made that guarantee.
		if not catalog_data.get("is_foundation", false):
			if visual_aabb.size.distance_to(catalog_size) > 0.05:
				print("  [FAIL] %s: fitted AABB %s != catalog size %s - the .glb and its sidecar disagree." % [
					type_id, visual_aabb.size, catalog_size])
				placer.queue_free()
				return false

		# Drive the actual _place_hull_from_ui path: the collider's size
		# must equal the visual AABB, and the base_hull_size meta must
		# carry the same value so locomotion / unit.gd see it.
		placer.clear_hull()
		placer._place_hull_from_ui(type_id)
		var hull_node: Node3D = placer.hull
		if not hull_node:
			print("  [FAIL] _place_hull_from_ui('%s') did not set placer.hull." % type_id)
			placer.queue_free()
			return false
		var col: CollisionShape3D = hull_node.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not col or not (col.shape is BoxShape3D):
			print("  [FAIL] %s: hull has no BoxShape3D collider (shape is %s)." % [type_id, type_as_string(col.shape) if col else "null"])
			placer.queue_free()
			return false
		var col_size: Vector3 = (col.shape as BoxShape3D).size
		var meta_size: Vector3 = hull_node.get_meta("base_hull_size")
		# The collider, the base_hull_size meta and the helper's output
		# must all agree - any drift between them re-opens the floating-
		# module bug on whichever side read the wrong one.
		if col_size.distance_to(visual_aabb.size) > 0.05:
			print("  [FAIL] %s: collider size %s != fitted AABB %s (delta %.3f)." % [type_id, col_size, visual_aabb.size, col_size.distance_to(visual_aabb.size)])
			placer.queue_free()
			return false
		if meta_size.distance_to(visual_aabb.size) > 0.05:
			print("  [FAIL] %s: base_hull_size meta %s != fitted AABB %s." % [type_id, meta_size, visual_aabb.size])
			placer.queue_free()
			return false
		# Hull must sit on the ground: hull.position.y == fitted_size.y / 2.0.
		if absf(hull_node.position.y - visual_aabb.size.y / 2.0) > 0.05:
			print("  [FAIL] %s: hull.position.y %.3f != fitted_size.y / 2 (%.3f) - the hull will float or sink." % [
				type_id, hull_node.position.y, visual_aabb.size.y / 2.0])
			placer.queue_free()
			return false

	placer.queue_free()
	print("  [PASS] Collider, base_hull_size meta and get_hull_fitted_aabb() agree across %d hulls, and each sits on the ground." % sample_hulls.size())
	return true

# Tactile Interface Programme Phase 5 (D10). The 3D Gizmo refuses
# attachment to Hull (fixed size classes).
#
# The former second half of this test drove module scaling directly through
# gizmo_3d.gd's _apply_scale_to_node(), which the Instrument Console Pass
# Phase B retired along with the rest of the stretch-handle path (radial
# tweak stations at scripts/ui/tweak_stations.gd are now the only route to a
# dimension) - deleted rather than updated, since it exercised removed
# machinery.
func test_hull_collider_rebuilt_on_scale() -> bool:
	print("Running Test Suite: Gizmo Refuses Hull (D10)...")
	var placer = Node3D.new()
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await tree.process_frame
	await tree.process_frame

	placer._place_hull_from_ui("brenntal_medium_a")
	var hull_node: Node3D = placer.hull
	if not hull_node:
		print("  [FAIL] _place_hull_from_ui did not set placer.hull.")
		placer.queue_free()
		return false

	var gizmo_script: GDScript = load("res://scripts/gizmo_3d.gd")
	if not gizmo_script:
		print("  [FAIL] Could not load gizmo_3d.gd")
		placer.queue_free()
		return false

	# Assert gizmo refuses attachment to Hull
	var hull_gizmo: Node3D = Node3D.new()
	hull_gizmo.set_script(gizmo_script)
	hull_node.add_child(hull_gizmo)
	await tree.process_frame
	# Hull gizmo queues free immediately upon attachment
	if not is_instance_valid(hull_gizmo) or hull_gizmo.is_queued_for_deletion() or not hull_gizmo.visible:
		print("  [PASS] Gizmo refused attachment to Hull (D10).")
	else:
		print("  [FAIL] Gizmo should refuse attachment to Hull.")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Gizmo refuses Hull (D10).")
	return true

func test_resource_harvester_mounting_restrictions_and_procedural_hardware() -> bool:
	print("Running Test Suite: Resource Harvester Placement Restrictions & Procedural Mounting Block...")
	var placer = Node3D.new()
	placer.set_script(preload("res://scripts/module_placer.gd"))
	root.add_child(placer)
	await tree.process_frame
	await tree.process_frame

	placer._place_hull_from_ui("brenntal_medium_a")
	var hull_node: Node3D = placer.hull
	if not is_instance_valid(hull_node):
		print("  [FAIL] Failed to spawn brenntal_medium_a hull.")
		placer.queue_free()
		return false

	var d = ModuleData.new()
	d.type_id = "resource_harvester"

	# 1. Reject deck, side, aft faces
	var deck_normal = Vector3(0, 1, 0)
	var deck_refusal = placer._placement_refusal_reason("resource_harvester", "weapon", deck_normal)
	if deck_refusal == "":
		print("  [FAIL] Harvester on deck facet was not refused.")
		placer.queue_free()
		return false

	var side_normal = Vector3(1, 0, 0)
	var side_refusal = placer._placement_refusal_reason("resource_harvester", "weapon", side_normal)
	if side_refusal == "":
		print("  [FAIL] Harvester on side facet was not refused.")
		placer.queue_free()
		return false

	var aft_normal = Vector3(0, 0, 1)
	var aft_refusal = placer._placement_refusal_reason("resource_harvester", "weapon", aft_normal)
	if aft_refusal == "":
		print("  [FAIL] Harvester on aft facet was not refused.")
		placer.queue_free()
		return false

	# 2. Reject pointed prow / angled normal
	var angled_normal = Vector3(0.5, 0, -0.7).normalized()
	var prow_refusal = placer._placement_refusal_reason("resource_harvester", "weapon", angled_normal)
	if prow_refusal == "":
		print("  [FAIL] Harvester on pointed prow / angled facet was not refused.")
		placer.queue_free()
		return false

	# 3. Allow flat front facet
	var front_normal = Vector3(0, 0, -1)
	var front_refusal = placer._placement_refusal_reason("resource_harvester", "weapon", front_normal)
	if front_refusal != "":
		print("  [FAIL] Harvester on flat front facet was unexpectedly refused: ", front_refusal)
		placer.queue_free()
		return false

	# 4. Place on front facet and verify snapping & procedural mounting block
	var placed_mod = placer._place_weapon("resource_harvester", Vector3(0.3, 0.2, -3.0), front_normal)
	if not is_instance_valid(placed_mod):
		print("  [FAIL] Harvester could not be placed on front facet.")
		placer.queue_free()
		return false

	var facet_size: Vector2 = placed_mod.get_meta("facet_size", Vector2.ZERO)
	if facet_size == Vector2.ZERO:
		print("  [FAIL] Harvester placed on front facet has no facet_size metadata.")
		placer.queue_free()
		return false

	var mount_block = placed_mod.get_node_or_null("HarvesterMountBlock")
	if not mount_block or not (mount_block is MeshInstance3D):
		print("  [FAIL] Harvester did not generate a HarvesterMountBlock MeshInstance3D.")
		placer.queue_free()
		return false

	var drill_head = placed_mod.get_node_or_null("HarvesterDrillHead")
	if not drill_head:
		print("  [FAIL] Harvester did not instantiate HarvesterDrillHead.")
		placer.queue_free()
		return false

	placer.queue_free()
	print("  [PASS] Resource Harvester enforces front-facet restriction, rejects angled prows, and generates procedural mounting block with tricone drill head.")
	return true


# The armor plate conform/round-trip suite lived here and was DELETED, not
# updated: it placed armor MODULES and asserted the plate mesh conformed to the
# facet and survived a save. Armor is no longer placeable - it is painted
# per-facet coverage (ArmorPaint), so every fixture in it described a thing that
# cannot be built. The behaviour it protected is covered by the armor paint
# suites instead: coverage, round trip, re-resolve and the resolver's facet
# lookup.

func type_as_string(thing) -> String:
	if thing == null:
		return "null"
	return str(thing)


