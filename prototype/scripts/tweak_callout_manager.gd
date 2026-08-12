class_name TweakCalloutManager
extends RefCounted
const ModuleDataResource = preload("res://scripts/module_data.gd")
const ResourceCatalogScript = preload("res://scripts/battle/economy/resource_catalog.gd")

var lab: Node
var _action_ring

func _init(p_lab: Node):
	lab = p_lab

# --- Live read-throughs to `lab`, NOT cached copies -------------------------
#
# These were all snapshotted in _init(), and that was a real bug rather than a
# style question. lab_document.gd constructs this manager at line ~605 of its
# _ready(), but does not create tweak_canvas until ~903, popup_tweaks_container
# until ~910, or popup_name_label until ~915. The snapshot therefore captured
# null for those three and held it for the entire session, so every callout path
# died on "Nonexistent function 'add_child' in base 'Nil'" - _add_callout()'s
# tweak_canvas.add_child() and _clear_callouts()' step-2
# popup_tweaks_container.add_child() both.
#
# A "call bind() after the UI exists" fix would work today and break the next
# time _ready() is reordered. Reading through on every access cannot go stale.
# They are deliberately getter-only: assigning to one is now a parse error,
# which is the invariant these should have had all along.
var locomotion_tweaks:
	get: return lab.locomotion_tweaks
var size_container:
	get: return lab.size_container
var size_label:
	get: return lab.size_label
var size_slider:
	get: return lab.size_slider
var count_container:
	get: return lab.count_container
var count_slider:
	get: return lab.count_slider
var count_label:
	get: return lab.count_label
var tweak_canvas:
	get: return lab.tweak_canvas
var popup_name_label:
	get: return lab.popup_name_label
var popup_tweaks_container:
	get: return lab.popup_tweaks_container

# This class's OWN state, not handles on lab-owned nodes: the per-drive-type
# match blocks below assign them ("Wheel Size", "Tread Width", ...). They were
# seeded from lab.* in _init, which only captured the Lab's placeholder and was
# overwritten on the first selection - the Lab's own declarations were dead and
# have been removed.
var size_label_base := "Size"
var count_label_base := "Count"
func _open_action_ring(module: Node3D, designation: String) -> void:
	_close_action_ring()
	if tweak_canvas == null or module == null:
		return

	var ring = UIRadialMenu.new()
	ring.target_node = module
	ring.subject_label = designation
	# TEXT LEGENDS, NOT ICONS, deliberately.
	#
	# The icons in scripts/ui_icons.gd carry their stroke colour baked into the
	# SVG - rotate_right is cyan, close is red, and so on. draw_texture_rect's
	# modulate MULTIPLIES, so there is no way to force a coloured icon to the
	# ring's own tint; the first version put saturated cyan and red clip-art on
	# a warm neutral dial and it fought the palette badly. Stencilled words are
	# also simply more correct for this object: real equipment legends are
	# words. A monochrome icon set would let icons back in here later.
	ring.add_action("rotate", "Rotate", "", _module_can_rotate(module))
	ring.add_action("mirror", "Mirror")
	ring.add_action("arc", "Arc")
	ring.add_action("discard", "Discard")
	ring.action_invoked.connect(_on_ring_action)
	tweak_canvas.add_child(ring)

	var camera = lab.get_viewport().get_camera_3d()
	var at = Vector2.ZERO
	if camera and not camera.is_position_behind(module.global_position):
		at = camera.unproject_position(module.global_position)
	ring.open_at(at)
	_action_ring = ring


# The Gizmo3D instance parented to the currently selected module, if any.
# module_placer.gd names it "Gizmo3D" when it attaches it.
func _selected_gizmo() -> Node:
	if not is_instance_valid(lab.current_selected_module):
		return null
	return lab.current_selected_module.get_node_or_null("Gizmo3D")


# Whether the rotation ring exists for this part. module_placer.gd frees
# HandleRotate outright for locomotion, armor and structural categories (armor
# is facet-fitted, structural stays flush - see MOUNTING_AND_ARMOR_SPEC.md), so
# offering Rotate on those would be a button that does nothing.
func _module_can_rotate(module: Node3D) -> bool:
	if module == null or not module.has_meta("module_data"):
		return false
	var data = module.get_meta("module_data")
	var cat = data.get("category") if "category" in data else "module"
	return cat == "weapon" or cat == "module"


func _close_action_ring() -> void:
	if is_instance_valid(_action_ring):
		_action_ring.close()
	_action_ring = null


func _on_ring_action(action_id: String) -> void:
	match action_id:
		"rotate":
			# Summons the rotation RING rather than stepping 90 degrees.
			#
			# Chris's note: the fixed-step button sitting next to a permanently
			# visible grab-handle ring was clunky - two ways to rotate, both on
			# screen at once, neither obviously the main one. Now Rotate is the
			# way IN to free rotation: the gizmo swaps its stretch handles for
			# the ring (gizmo_3d.set_rotate_mode), and the ring is restyled to
			# match this menu so the two read as one mechanism.
			var giz = _selected_gizmo()
			if giz and giz.has_method("set_rotate_mode"):
				giz.set_rotate_mode(true)
		"mirror":
			# Reuses the existing global mirror toggle rather than introducing a
			# second, per-module notion of mirroring that would then have to be
			# kept in sync with the checkbox.
			if lab.mirror_checkbox:
				lab.mirror_checkbox.button_pressed = not lab.mirror_checkbox.button_pressed
		"arc":
			var root = lab.get_node_or_null("/root/MainLab")
			if root and root.has_method("toggle_firing_arc"):
				root.toggle_firing_arc()
		"discard":
			lab.lab_toolbar._on_delete_pressed()

func _add_callout(module: Node3D, title: String, control: Control):
	# Same guard as _clear_callouts(): reached from on_module_selected(), which
	# the Lab can fire before its UI layer exists.
	if not tweak_canvas or not popup_tweaks_container or control == null:
		return
	if control.get_parent():
		control.reparent(tweak_canvas) # Temporarily avoid issues if it's already in the tree somewhere
	var dir = lab._callout_dirs[lab._current_callout_idx % lab._callout_dirs.size()]
	var dist = 100.0 + (lab._current_callout_idx / lab._callout_dirs.size()) * 70.0
	var callout = load("res://scripts/tweak_callout.gd").new(title, control, dir, dist)
	callout.target_node = module
	callout.stash = popup_tweaks_container
	tweak_canvas.add_child(callout)
	lab._current_callout_idx += 1

# The persistent locomotion widgets. These are REUSED across selections rather
# than rebuilt, so they must be rescued out of a dying callout instead of freed
# with it. Everything else a callout holds is built fresh per selection and
# should go when the callout goes.
func _persistent_tweak_widgets() -> Array:
	return [size_container, count_container, lab.wheels_per_axle_container,
		lab.blade_count_container, lab.blade_pitch_container, lab.helix_depth_container,
		lab.duct_container, lab.leg_type_container, lab.leg_width_container,
		popup_name_label, lab.popup_stats_label, lab.popup_rotate_btn]

func _clear_callouts():
	# Both, not just tweak_canvas: lab_document.gd creates them seven lines
	# apart, so there is a window where one exists and the other does not, and
	# steps 2 and 3 below dereference popup_tweaks_container unconditionally.
	if not tweak_canvas or not popup_tweaks_container: return

	# STEP 1: reclaim every callout's control into the invisible stash BEFORE
	# anything is freed.
	#
	# Doing this here, rather than leaving it to each callout's own _process,
	# is what actually fixes the orphaned widgets: a callout only ran its
	# hand-back path when its TARGET went invalid, so a plain deselect (target
	# still alive, callout freed by the sweep below) never handed anything back
	# at all. Reparenting into popup_tweaks_container is safe for both kinds of
	# control because that container is invisible; step 3 then throws away the
	# ones that were single-use.
	for child in tweak_canvas.get_children():
		if child is TweakCallout:
			var ctrl = (child as TweakCallout).control_node
			if is_instance_valid(ctrl) and ctrl.get_parent() != popup_tweaks_container:
				ctrl.reparent(popup_tweaks_container)

	# STEP 2: make sure the persistent widgets are in the stash and parented.
	var persistent_items = _persistent_tweak_widgets()
	for c in persistent_items:
		if is_instance_valid(c) and c.get_parent() != popup_tweaks_container:
			if c.get_parent() != null:
				c.reparent(popup_tweaks_container)
			else:
				popup_tweaks_container.add_child(c)

	# STEP 3: purge the single-use controls that step 1 just swept in.
	# Without this the stash grows by a few nodes on every selection for the
	# whole session - invisible, so it would never be noticed, but it is still
	# an unbounded leak.
	for child in popup_tweaks_container.get_children():
		if child not in persistent_items:
			child.queue_free()


	# The ring is a child of tweak_canvas too, so the sweep below would free it
	# out from under _action_ring and leave a dangling reference. Drop it
	# explicitly first.
	_close_action_ring()

	for child in tweak_canvas.get_children():
		child.queue_free()
	lab._current_callout_idx = 0

func on_module_selected(module: Node3D):
	if module and not is_instance_valid(module):
		module = null
	lab.current_selected_module = module

	_clear_callouts()

	# Default every locomotion tweak widget to hidden
	size_container.visible = false
	count_container.visible = false
	lab.wheels_per_axle_container.visible = false
	lab.blade_count_container.visible = false
	lab.blade_pitch_container.visible = false
	lab.helix_depth_container.visible = false
	lab.duct_container.visible = false
	lab.leg_type_container.visible = false
	lab.leg_width_container.visible = false

	var root = lab.get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null

	if hull and (module == null or module == hull or module.name == "Hull"):
		lab.sync_hull_ui(hull)

	if not locomotion_tweaks: return

	if not module or not module.has_meta("module_data"):
		return

	var data = module.get_meta("module_data")

	# We no longer use a single popup_panel. Instead we will create a callout for the stats
	# We can just use the popup_name_label and lab.popup_stats_label but add them to a callout.
	
	# Actually, to avoid breaking, let's keep the name and stat label but put them in a dedicated callout
	var stats_container = VBoxContainer.new()
	if popup_name_label:
		if popup_name_label.get_parent(): popup_name_label.reparent(stats_container)
		else: stats_container.add_child(popup_name_label)
	
	if lab.popup_stats_label:
		if lab.popup_stats_label.get_parent(): lab.popup_stats_label.reparent(stats_container)
		else: stats_container.add_child(lab.popup_stats_label)
		
	if lab.popup_rotate_btn:
		if lab.popup_rotate_btn.get_parent(): lab.popup_rotate_btn.reparent(stats_container)
		else: stats_container.add_child(lab.popup_rotate_btn)
		
	if popup_name_label:
		popup_name_label.text = data.module_name.to_upper()

	# The action ring opens with the callouts, on the part itself.
	_open_action_ring(module, data.module_name.to_upper())

	var hp = data.get_hp()
	var wt = data.get_weight()
	var cost = data.get_cost()
	var dps = data.get_dps()
	var heal = data.get_heal_rate()
	var last_line = "Heal Rate: %.1f/s" % heal if heal > 0.0 else "DPS: %.1f" % dps
	var mount_line = _mount_style_line(module.get_meta("mount_style", ""))
	lab.popup_stats_label.text = "HP: %.1f | Weight: %.1f kg\nCost: %d credits\n%s%s" % [hp, wt, ResourceCatalogScript.credits_from_materials(cost), last_line, mount_line]
	
	_add_callout(module, "Module Stats", stats_container)

	if data.category != "locomotion":
		_generate_custom_tweaks(module, data)
		return

	root = lab.get_node("/root/MainLab")
	hull = root.get_node_or_null("Hull")
	if not hull:
		return

	var type_id = data.type_id
	var settings = {}
	if hull.has_meta("locomotion_settings"):
		settings = hull.get_meta("locomotion_settings")

	lab.is_updating_sliders = true
	size_container.visible = true
	count_slider.min_value = 2.0
	count_slider.max_value = 8.0
	count_slider.step = 2.0
	# lab.blade_count_container is now shared between helicopter_rotors and
	# buoyant_envelope (Chris's ask, 2026-07-24) - reset unconditionally so
	# it doesn't stay visible after switching away from whichever of those
	# types last showed it (only helicopter_rotors used it before, so this
	# never came up).
	lab.blade_count_container.visible = false
	lab.blade_pitch_container.visible = false
	count_label_base = "Count"
	lab.bool_tweak_key = "duct"
	lab.bool_tweak_title = "Ducted"

	if type_id == "wheels":
		size_label_base = "Wheel Size"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("wheel_size", settings.get("size", 1.0))
		count_slider.min_value = 4.0
		count_slider.value = settings.get("num_axles", settings.get("count", 4))
		lab.wheels_per_axle_container.visible = true
		lab.wheels_per_axle_slider.value = settings.get("wheels_per_axle", 1.0)
	elif type_id == "tracked_treads":
		size_label_base = "Tread Width"
		count_container.visible = false
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("tread_width", settings.get("width", 1.0))
	elif type_id == "helicopter_rotors":
		size_label_base = "Rotor Size"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("size", 1.0)
		count_slider.value = settings.get("count", 4)
		lab.blade_count_container.visible = true
		lab.blade_count_slider.value = settings.get("blade_count", 4.0)
		lab.duct_container.visible = true
		lab.duct_checkbox.tooltip_text = "Ducted Shroud"
		lab.duct_checkbox.button_pressed = settings.get("duct", false)
	elif type_id == "legs":
		# Leg Length (stride, drives thrust) and Leg Width (section, drives
		# capacity) replaced Knee Height, which had nothing left to move once the
		# limbs became authored models - see LOCOMOTION_TWEAKS in the catalog.
		size_label_base = "Leg Length"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.0
		size_slider.value = settings.get("leg_length", settings.get("size", 1.0))
		count_slider.value = settings.get("count", 4)
		lab.leg_width_container.visible = true
		lab.leg_width_slider.value = settings.get("leg_width", 1.0)
		# Which of the six authored sets is fitted. Set without firing the
		# signal - this runs on selection, and letting it emit would re-apply
		# the tweak and respawn the legs every time the player clicked one.
		lab.leg_type_container.visible = true
		var leg_options: Array = ModuleCatalog.get_leg_options()
		var leg_id: String = ModuleCatalog.get_leg_type(settings)
		lab.leg_type_button.select(maxi(leg_options.find(leg_id), 0))
		lab.leg_type_desc.text = ModuleCatalog.get_leg_profile(leg_id).desc
	elif type_id == "hover_engine":
		size_label_base = "Electron Megavoltage"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("emv_level", 1.0)
		count_slider.min_value = 4.0
		count_slider.step = 1.0
		count_slider.value = settings.get("pad_count", 4)
	elif type_id == "fixed_wing_engine":
		size_label_base = "Turbine Compression"
		count_container.visible = true
		size_slider.min_value = 0.5
		size_slider.max_value = 2.0
		size_slider.value = settings.get("turbine_compression", 1.0)
		count_slider.min_value = 2.0
		count_slider.max_value = 6.0
		count_slider.step = 1.0
		count_slider.value = settings.get("engine_count", 2)
	elif type_id == "buoyant_envelope":
		# Pylon-mounted rebuild (Chris's ask, 2026-07-24): no Size tweak at
		# all - Count doubles as Propeller Count, plus the shared Blade Count
		# slider (reused from helicopter_rotors above) and a new Blade Pitch
		# slider.
		size_container.visible = false
		count_container.visible = true
		count_slider.min_value = 1.0
		# 6: buoyant_envelope's pod progression runs to three per side (Chris).
		count_slider.max_value = 6.0
		count_slider.step = 1.0
		count_slider.value = settings.get("prop_count", settings.get("count", 2))
		count_label_base = "Propeller Count"
		lab.blade_count_container.visible = true
		lab.blade_count_slider.value = settings.get("blade_count", 3.0)
		lab.blade_pitch_container.visible = true
		lab.blade_pitch_slider.value = settings.get("blade_pitch", 1.0)
	elif type_id == "screw_drive":
		# Rebuilt (Chris's ask, 2026-07-24): no Count at all - always one
		# drum per side, like tracked_treads. Size doubles as Drum Diameter
		# (see LabDocument.LOCOMOTION_SIZE_KEY), plus a new Helix Depth slider.
		size_label_base = "Drum Diameter"
		count_container.visible = false
		size_slider.min_value = 0.5
		size_slider.max_value = 2.0
		size_slider.value = settings.get("drum_diameter", settings.get("drum_width", 1.0))
		lab.helix_depth_container.visible = true
		lab.helix_depth_slider.value = settings.get("helix_depth", 1.0)
	elif type_id == "ornithopter_wing":
		size_label_base = "Wingspan"
		count_container.visible = false
		size_slider.min_value = 0.5
		size_slider.max_value = 2.5
		size_slider.value = settings.get("wingspan", settings.get("size", 1.0))
		lab.blade_pitch_container.visible = true
		lab.blade_pitch_label.text = "Wing Sweep Angle:"
		lab.blade_pitch_slider.min_value = 0.5
		lab.blade_pitch_slider.max_value = 1.5
		lab.blade_pitch_slider.value = settings.get("wing_sweep", 1.0)
	elif type_id == "half_track":
		size_label_base = "Track Width"
		size_slider.min_value = 0.5
		size_slider.max_value = 2.0
		size_slider.value = settings.get("tread_width", 1.0)
		count_container.visible = true
		count_slider.min_value = 2.0
		count_slider.max_value = 5.0
		count_slider.step = 1.0
		count_slider.value = settings.get("bogie_count", 3.0)
		count_label_base = "Track Bogie Count"
		lab.blade_pitch_container.visible = true
		lab.blade_pitch_label.text = "Front Axle Size:"
		lab.blade_pitch_slider.min_value = 0.6
		lab.blade_pitch_slider.max_value = 1.8
		lab.blade_pitch_slider.value = settings.get("front_axle_size", 1.0)
	elif type_id == "rocker_bogie":
		size_label_base = "Wheel Size"
		size_slider.min_value = 0.6
		size_slider.max_value = 2.0
		size_slider.value = settings.get("wheel_size", 1.0)
		count_container.visible = true
		count_slider.min_value = 2.0
		count_slider.max_value = 4.0
		count_slider.step = 1.0
		count_slider.value = settings.get("bogie_pairs", 3.0)
		count_label_base = "Bogie Pairs"
		lab.blade_pitch_container.visible = true
		lab.blade_pitch_label.text = "Rocker Arm Length:"
		lab.blade_pitch_slider.min_value = 0.6
		lab.blade_pitch_slider.max_value = 1.8
		lab.blade_pitch_slider.value = settings.get("arm_length", 1.0)
	elif type_id == "air_cushion_skirt":
		size_label_base = "Skirt Diameter"
		size_slider.min_value = 0.6
		size_slider.max_value = 2.0
		size_slider.value = settings.get("skirt_diameter", 1.0)
		count_container.visible = true
		count_slider.min_value = 2.0
		count_slider.max_value = 6.0
		count_slider.step = 1.0
		count_slider.value = settings.get("lift_fan_count", 3.0)
		count_label_base = "Lift Fan Count"
		lab.blade_pitch_container.visible = true
		lab.blade_pitch_label.text = "Plenum Pressure:"
		lab.blade_pitch_slider.min_value = 0.5
		lab.blade_pitch_slider.max_value = 1.8
		lab.blade_pitch_slider.value = settings.get("plenum_pressure", 1.0)
	elif type_id == "anti_grav_plate":
		size_label_base = "Field Strength"
		size_slider.min_value = 0.5
		size_slider.max_value = 2.2
		size_slider.value = settings.get("field_strength", 1.0)
		count_container.visible = true
		count_slider.min_value = 3.0
		count_slider.max_value = 8.0
		count_slider.step = 1.0
		count_slider.value = settings.get("plate_count", 4.0)
		count_label_base = "Plate Count"
		lab.bool_tweak_key = "stabilizer_ring"
		lab.bool_tweak_title = "Stabiliser Ring"
		lab.duct_container.visible = true
		lab.duct_checkbox.tooltip_text = "Stabiliser Ring"
		lab.duct_checkbox.button_pressed = settings.get("stabilizer_ring", true)
	elif type_id == "pontoon_wheels":
		# module_catalog.gd has declared these three since the type was added,
		# but no UI branch ever read them, so the type came up with no
		# tweakables at all (Chris's report, 2026-08-02) - it fell through to
		# the else below and hid the Size slider.
		size_label_base = "Pontoon Size"
		size_slider.min_value = 0.6
		size_slider.max_value = 1.8
		size_slider.value = settings.get("pontoon_size", 1.0)
		count_container.visible = true
		count_slider.min_value = 2.0
		count_slider.max_value = 6.0
		count_slider.step = 2.0
		count_slider.value = settings.get("axle_count", 4)
		count_label_base = "Axle Count"
		lab.bool_tweak_key = "paddle_vanes"
		lab.bool_tweak_title = "Paddle Vanes"
		lab.duct_container.visible = true
		lab.duct_checkbox.tooltip_text = "Paddle Vanes"
		lab.duct_checkbox.button_pressed = settings.get("paddle_vanes", true)
	else:
		size_container.visible = false

	_refresh_locomotion_labels()
	
	if size_container.visible: _add_callout(module, "Size", size_container)
	if count_container.visible: _add_callout(module, "Count", count_container)
	if lab.wheels_per_axle_container.visible: _add_callout(module, "Wheels Per Axle", lab.wheels_per_axle_container)
	if lab.blade_count_container.visible: _add_callout(module, "Blade Count", lab.blade_count_container)
	if lab.blade_pitch_container.visible: _add_callout(module, "Blade Pitch", lab.blade_pitch_container)
	if lab.helix_depth_container.visible: _add_callout(module, "Helix Depth", lab.helix_depth_container)
	if lab.duct_container.visible: _add_callout(module, lab.bool_tweak_title, lab.duct_container)
	# THE LINE THAT ACTUALLY PUTS A TWEAK ON SCREEN. Setting .visible in the
	# per-type branch above is necessary but not sufficient - a widget only
	# reaches the player once it has been handed to _add_callout(), which lifts
	# it out of the stash into a floating callout beside the selected module.
	# Without this, the leg picker was built, wired, and permanently invisible.
	if lab.leg_width_container.visible: _add_callout(module, "Leg Width", lab.leg_width_container)
	if lab.leg_type_container.visible: _add_callout(module, "Leg Set", lab.leg_type_container)

	lab.is_updating_sliders = false

func _refresh_locomotion_labels():
	# Every locomotion size tweak is now a MULTIPLIER, so they all read "1.25x".
	# Knee Height was the one exception - it was a signed offset in metres and
	# needed its own "+0.38m" format - and it is gone.
	size_label.text = "%s: %.2fx" % [size_label_base, size_slider.value]
	if lab.leg_width_container.visible:
		lab.leg_width_label.text = "Leg Width: %.2fx" % lab.leg_width_slider.value
	if count_container.visible:
		count_label.text = "%s: %d" % [count_label_base, int(count_slider.value)]
	if lab.wheels_per_axle_container.visible:
		var dually = int(lab.wheels_per_axle_slider.value) >= 2
		lab.wheels_per_axle_label.text = "Wheels Per Axle: %d%s" % [int(lab.wheels_per_axle_slider.value), " (dually)" if dually else ""]
	if lab.blade_count_container.visible:
		lab.blade_count_label.text = "Blade Count: %d" % int(lab.blade_count_slider.value)
	if lab.blade_pitch_container.visible:
		lab.blade_pitch_label.text = "Blade Pitch: %.2fx" % lab.blade_pitch_slider.value
	if lab.helix_depth_container.visible:
		lab.helix_depth_label.text = "Helix Depth: %.2fx" % lab.helix_depth_slider.value

func _on_size_value_changed(value: float):
	_refresh_locomotion_labels()
	if lab.is_updating_sliders or not lab.current_selected_module or not is_instance_valid(lab.current_selected_module): return
	var root = lab.get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	var data = lab.current_selected_module.get_meta("module_data")
	var type_id = data.type_id
	var key = LabDocument.LOCOMOTION_SIZE_KEY.get(type_id, "size")
	root.update_locomotion_geometry_tweak(type_id, key, value)

func _on_count_value_changed(value: float):
	_refresh_locomotion_labels()
	if lab.is_updating_sliders or not lab.current_selected_module or lab._loco_slider_dragging: return
	_apply_tweaks()

func _on_wheels_per_axle_changed(value: float):
	_refresh_locomotion_labels()
	if lab.is_updating_sliders or not lab.current_selected_module or not is_instance_valid(lab.current_selected_module): return
	var root = lab.get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	root.update_locomotion_geometry_tweak("wheels", "wheels_per_axle", int(value))

func _on_blade_count_changed(value: float):
	_refresh_locomotion_labels()
	if lab.is_updating_sliders or not lab.current_selected_module or not is_instance_valid(lab.current_selected_module): return
	var root = lab.get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	# Shared between helicopter_rotors and buoyant_envelope (Chris's ask,
	# 2026-07-24) - was hardcoded to "helicopter_rotors", which silently
	# no-opped this slider for buoyant_envelope (its module_data.tweaks never
	# actually got a "blade_count" key written, since
	# update_locomotion_geometry_tweak() matches children by type_id).
	var data = lab.current_selected_module.get_meta("module_data")
	root.update_locomotion_geometry_tweak(data.type_id, "blade_count", int(value))

func _on_blade_pitch_changed(value: float):
	_refresh_locomotion_labels()
	if lab.is_updating_sliders or not lab.current_selected_module or not is_instance_valid(lab.current_selected_module): return
	var root = lab.get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	var data = lab.current_selected_module.get_meta("module_data")
	var key = LabDocument.LOCOMOTION_SECONDARY_SIZE_KEY.get(data.type_id, "blade_pitch")
	root.update_locomotion_geometry_tweak(data.type_id, key, value)

func _on_helix_depth_changed(value: float):
	_refresh_locomotion_labels()
	if lab.is_updating_sliders or not lab.current_selected_module or not is_instance_valid(lab.current_selected_module): return
	var root = lab.get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	var data = lab.current_selected_module.get_meta("module_data")
	root.update_locomotion_geometry_tweak(data.type_id, "helix_depth", value)

## Leg Width. A geometry tweak, so it takes the live rebuild path rather than
## the full respawn - unlike leg_type, changing a limb's section does not move
## the stations it mounts at.
func _on_leg_width_changed(value: float):
	_refresh_locomotion_labels()
	if lab.is_updating_sliders or not lab.current_selected_module or not is_instance_valid(lab.current_selected_module): return
	var root = lab.get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	var data = lab.current_selected_module.get_meta("module_data")
	root.update_locomotion_geometry_tweak(data.type_id, "leg_width", value)

func _on_duct_toggled(pressed: bool):
	if lab.is_updating_sliders or not lab.current_selected_module or not is_instance_valid(lab.current_selected_module): return
	lab._push_undo()
	var root = lab.get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion_geometry_tweak"): return
	var data = lab.current_selected_module.get_meta("module_data")
	root.update_locomotion_geometry_tweak(data.type_id, lab.bool_tweak_key, pressed)

## Picking a different leg set.
##
## Routed through the FULL update_locomotion() respawn rather than
## update_locomotion_geometry_tweak(), which every other locomotion tweak on
## this panel uses. That is not a stylistic choice: the geometry-tweak path only
## calls rebuild_visual() on each existing module, and a leg set changes where
## the modules BELONG - Mantis and Crawler mount to the hull's flank, the other
## four to its belly. Rebuilding the mesh in place would leave a shouldered leg
## hanging under the hull with its shoulder buried in it.
##
## No debounce, unlike the count slider: a dropdown has no drag to wait out.
func _on_leg_type_selected(index: int) -> void:
	if lab.is_updating_sliders or not lab.current_selected_module or not is_instance_valid(lab.current_selected_module):
		return
	var options: Array = ModuleCatalog.get_leg_options()
	if index < 0 or index >= options.size():
		return
	lab._push_undo()
	var picked: String = options[index]
	lab.leg_type_desc.text = ModuleCatalog.get_leg_profile(picked).desc

	var root = lab.get_node_or_null("/root/MainLab")
	if not root or not root.has_method("update_locomotion"):
		return
	var settings: Dictionary = {}
	if root.hull and root.hull.has_meta("locomotion_settings"):
		settings = root.hull.get_meta("locomotion_settings").duplicate()
	settings[ModuleCatalog.LEG_TWEAK_KEY] = picked
	root.update_locomotion("legs", settings)
	lab.update_stats(root.hull)

func _on_loco_drag_started():
	lab._loco_slider_dragging = true
	lab._push_undo()

# Fires once when the mouse releases the slider grabber - this is where the
# actual (expensive, full-respawn) update_locomotion() call happens, not on
# every intermediate value_changed tick during the drag. See the comment on
# the drag_started/drag_ended connections in _ready() for why.
func _on_loco_drag_ended(value_changed: bool):
	lab._loco_slider_dragging = false
	if lab.is_updating_sliders or not lab.current_selected_module: return
	if value_changed:
		_apply_tweaks()

func _apply_tweaks():
	var root = lab.get_node("/root/MainLab")
	var hull = root.get_node_or_null("Hull")
	if not root or not hull or not lab.current_selected_module: return
	
	var data = lab.current_selected_module.get_meta("module_data")
	var type_id = data.type_id
	var new_settings = {}
	
	if type_id == "wheels":
		new_settings = {
			"wheel_size": size_slider.value,
			"num_axles": int(count_slider.value),
			"wheels_per_axle": int(lab.wheels_per_axle_slider.value)
		}
	elif type_id == "tracked_treads":
		new_settings = {
			"tread_width": size_slider.value
		}
	elif type_id == "helicopter_rotors":
		new_settings = {
			"size": size_slider.value,
			"count": int(count_slider.value),
			"blade_count": int(lab.blade_count_slider.value),
			"duct": lab.duct_checkbox.button_pressed
		}
	elif type_id == "legs":
		new_settings = {
			"leg_length": size_slider.value,
			"leg_width": lab.leg_width_slider.value,
			"count": int(count_slider.value),
			# Carried through, not read off the dropdown: this runs on a SLIDER
			# change, and rebuilding new_settings from scratch without it would
			# silently reset the player's leg set to the default every time they
			# nudged leg count or knee height.
			ModuleCatalog.LEG_TWEAK_KEY: ModuleCatalog.get_leg_type(
				lab.current_selected_module.get_meta("module_data").tweaks)
		}
	elif type_id == "pontoon_wheels":
		# paddle_vanes rides along for the same reason blade_count does below:
		# an Axle Count change respawns every instance, so a tweak left out of
		# this dict silently resets to its default on the next Count drag.
		new_settings = {
			"pontoon_size": size_slider.value,
			"axle_count": int(count_slider.value),
			"paddle_vanes": lab.duct_checkbox.button_pressed
		}
	elif type_id == "hover_engine":
		new_settings = {
			"emv_level": size_slider.value,
			"pad_count": int(count_slider.value)
		}
	elif type_id == "fixed_wing_engine":
		new_settings = {
			"turbine_compression": size_slider.value,
			"engine_count": int(count_slider.value)
		}
	elif type_id == "buoyant_envelope":
		# Count (Propeller Count) is structural here too - changing it
		# respawns every prop instance, so blade_count/blade_pitch have to
		# ride along in the same settings dict or they'd silently reset to
		# their defaults on the very next Count drag.
		new_settings = {
			"prop_count": int(count_slider.value),
			"blade_count": int(lab.blade_count_slider.value),
			"blade_pitch": lab.blade_pitch_slider.value
		}
	elif type_id == "screw_drive":
		new_settings = {
			"drum_diameter": size_slider.value,
			"helix_depth": lab.helix_depth_slider.value
		}
	elif type_id == "ornithopter_wing":
		new_settings = {
			"wingspan": size_slider.value,
			"wing_sweep": lab.blade_pitch_slider.value
		}
	elif type_id == "half_track":
		new_settings = {
			"tread_width": size_slider.value,
			"bogie_count": int(count_slider.value),
			"front_axle_size": lab.blade_pitch_slider.value
		}
	elif type_id == "rocker_bogie":
		new_settings = {
			"wheel_size": size_slider.value,
			"bogie_pairs": int(count_slider.value),
			"arm_length": lab.blade_pitch_slider.value
		}
	elif type_id == "air_cushion_skirt":
		new_settings = {
			"skirt_diameter": size_slider.value,
			"lift_fan_count": int(count_slider.value),
			"plenum_pressure": lab.blade_pitch_slider.value
		}
	elif type_id == "anti_grav_plate":
		new_settings = {
			"field_strength": size_slider.value,
			"plate_count": int(count_slider.value),
			"stabilizer_ring": lab.duct_checkbox.button_pressed
		}

	if root.has_method("update_locomotion"):
		# Update positions/scales immediately
		root.update_locomotion(type_id, new_settings)
		# Reselect the new node counterpart to keep selection and UI visible
		var new_selected = null
		for child in hull.get_children():
			# update_locomotion() just queue_free()'d every OLD instance of
			# this type before spawning the new ones - queue_free() doesn't
			# remove a node from its parent immediately, so the doomed old
			# instances are still in get_children() (and, since they were
			# added earlier, sorted BEFORE the fresh replacements) at this
			# exact point. Without this check, "first match" reliably picked
			# a soon-to-be-freed old instance instead of a live new one; by
			# the time the deferred _select_module below actually ran, that
			# instance had already been freed, and on_module_selected()
			# calling .has_meta() on it threw - which left
			# lab.current_selected_module corrupted (pointing at a freed
			# object) for every tweak afterward, until the player manually
			# reselected. Confirmed via a real drag-up-then-drag-down test:
			# the second (down) drag silently no-op'd because of exactly
			# this.
			if child.is_queued_for_deletion(): continue
			if child.has_meta("module_data"):
				var m_data = child.get_meta("module_data")
				if m_data and m_data.type_id == type_id:
					new_selected = child
					break
		if new_selected:
			root.call_deferred("_select_module", new_selected)

# --- Rail dock + top toolbar (VISUAL/UI plan item 7) ------------------------

# Wraps the telemetry rail in a UIDock and lifts its action controls into a thin
# STEEL toolbar across the top of the Lab.
#
# WHY THE TOOLBAR EXISTS. Undo, Redo, Mirror, Save, Test, Library and the
# hull-spec trigger were seven rows stacked in a 320px column, present whether or
# not they applied to anything - and Undo/Redo in particular are document-level
# actions that belong on a toolbar, not buried under a stat readout. Lifting them
# out is also what lets the dock rail away to 40px and still be useful: what is
# left in the rail is genuinely just the blueprint's identity and its headline
# numbers, which is the only part worth reading continuously.
#
# DEFAULT STATE IS RAILED. The plan's whole complaint about the Design Lab is
# that the 3D model - the actual subject - got the leftover middle. Both docks
# start collapsed so the viewport has the screen until the player asks for a
# panel. `auto_reveal` stays OFF: a dock that vanishes on mouse-out is a nuisance
# in an editor and a defect in combat, and this primitive is shared with the HUD.
func _on_tweak_changed():
	if lab.current_selected_module and is_instance_valid(lab.current_selected_module):
		var primary_data = lab.current_selected_module.get_meta("module_data") if lab.current_selected_module.has_meta("module_data") else null
		VisualBuilder.rebuild_visual(lab.current_selected_module)
		if lab.current_selected_module.has_meta("mirrored_counterpart"):
			var mirror = lab.current_selected_module.get_meta("mirrored_counterpart")
			if mirror and is_instance_valid(mirror):
				# Sync tweaks directly to the mirror so symmetric edits work correctly
				var mirror_data = mirror.get_meta("module_data") if mirror.has_meta("module_data") else null
				if primary_data and mirror_data:
					mirror_data.tweaks = primary_data.tweaks.duplicate()
				VisualBuilder.rebuild_visual(mirror)
				
	var root = lab.get_node_or_null("/root/MainLab")
	var hull = root.get_node_or_null("Hull") if root else null
	if hull:
		lab.update_stats(hull)
		# Update popup stats label text too
		if lab.current_selected_module and is_instance_valid(lab.current_selected_module) and lab.current_selected_module.has_meta("module_data"):
			var data = lab.current_selected_module.get_meta("module_data")
			if lab.popup_stats_label:
				var hp = data.get_hp()
				var wt = data.get_weight()
				var cost = data.get_cost()
				var dps = data.get_dps()
				var heal = data.get_heal_rate()
				var last_line = "Heal Rate: %.1f/s" % heal if heal > 0.0 else "DPS: %.1f" % dps
				var mount_line = _mount_style_line(lab.current_selected_module.get_meta("mount_style", ""))
				lab.popup_stats_label.text = "HP: %.1f | Weight: %.1f kg\nCost: %d credits\n%s%s" % [hp, wt, ResourceCatalogScript.credits_from_materials(cost), last_line, mount_line]
		# Same root-not-child correction as the rotate sites above.
		if root and root.has_method("check_all_clipping"):
			root.check_all_clipping()

# mount_style (module_placer.gd/module_catalog.gd) drives real combat
# behavior (whether the weapon independently traverses or the whole
# vehicle aims instead) but was never named or explained anywhere in the
# UI - a player just saw the result with no indication these are distinct
# categories with different rules. Appended to the floating module popup
# (not the fixed sidebar, which has zero layout slack left - see the
# manufactory-tier tooltip judgment call above) since this only applies to
# weapons, not every module. Visual placement (flush-mounted to whatever
# facet it's on) is the same for all three styles now - only traverse
# differs, so the wording below describes traverse, not mount geometry.
func _mount_style_line(style: String) -> String:
	var desc = ""
	match style:
		"turret": desc = "Turret mount (full traverse)"
		"frame_built": desc = "Frame-built (fixed - whole vehicle aims)"
		"pintle": desc = "Pintle mount (full traverse)"
	return "\n%s" % desc if desc != "" else ""

func _generate_custom_tweaks(module: Node3D, data: ModuleDataResource):
	var type_id = data.type_id

	if ModuleCatalog.is_ammo_capable(type_id):
		var ammo_options = ModuleCatalog.get_ammo_options(type_id)
		var current_ammo = ModuleCatalog.get_ammo(type_id, data.tweaks)
		var ammo_idx = max(ammo_options.find(current_ammo), 0)

		var ammo_container = VBoxContainer.new()
		ammo_container.add_theme_constant_override("separation", 2)

		var ammo_btn = OptionButton.new()
		for a in ammo_options:
			ammo_btn.add_item(ModuleCatalog.get_ammo_profile(a).label)
		ammo_btn.selected = ammo_idx
		ammo_container.add_child(ammo_btn)

		var ammo_desc = Label.new()
		ammo_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ammo_desc.custom_minimum_size.x = 220
		ammo_desc.add_theme_font_size_override("font_size", 11)
		ammo_desc.modulate = Color(1, 1, 1, 0.65)
		ammo_desc.text = ModuleCatalog.get_ammo_profile(ammo_options[ammo_idx]).desc
		ammo_container.add_child(ammo_desc)

		ammo_btn.item_selected.connect(func(index: int):
			lab._push_undo()
			var picked = ammo_options[index]
			data.tweaks[ModuleCatalog.AMMO_TWEAK_KEY] = picked
			var profile = ModuleCatalog.get_ammo_profile(picked)
			ammo_desc.text = profile.desc
			_on_tweak_changed()
		)
		_add_callout(module, "Loaded Ammo", ammo_container)

	if not LabDocument.TWEAK_SPECS.has(type_id): return

	var specs = LabDocument.TWEAK_SPECS[type_id]
	for spec in specs:
		if spec.get("type", "") == "bool":
			var check = CheckBox.new()
			check.button_pressed = data.tweaks.get(spec.name, spec.default)
			check.tooltip_text = spec.label
			
			check.toggled.connect(func(pressed):
				lab._push_undo()
				data.tweaks[spec.name] = pressed
				_on_tweak_changed()
			)
			_add_callout(module, spec.label, check)
		else:
			var container = VBoxContainer.new()
			container.add_theme_constant_override("separation", 0)
			
			var label = Label.new()
			container.add_child(label)

			var slider = HSlider.new()
			slider.min_value = spec.min
			slider.max_value = spec.max
			slider.step = spec.step
			slider.value = data.tweaks.get(spec.name, spec.default)
			slider.custom_minimum_size = Vector2(180, 0)
			container.add_child(slider)

			if spec.step == 1.0:
				label.text = "%d" % int(slider.value)
			else:
				label.text = "%.2fx" % slider.value

			slider.drag_started.connect(lab._push_undo)
			slider.value_changed.connect(func(val):
				data.tweaks[spec.name] = val
				if spec.step == 1.0:
					label.text = "%d" % int(val)
				else:
					label.text = "%.2fx" % val
				_on_tweak_changed()
			)
			_add_callout(module, spec.label, container)
