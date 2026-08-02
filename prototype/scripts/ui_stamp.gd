class_name UIStamp
extends RefCounted
# Reusable Satirical Rubber Ink Stamp Overlay System
# Triggers tactile "APPROVED FOR FIELD TEST", "DESTRUCTIVE TEST PERMIT", or "DECOMMISSIONED"
# rubber ink stamp animations with physics thud and rotation.

static func spawn_stamp(parent: Node, stamp_text: String, stamp_color: Color = Color(0.1, 0.85, 0.35, 0.9)) -> Control:
	if parent == null:
		return null

	var container = CenterContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(container)

	var stamp_box = PanelContainer.new()
	stamp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(stamp_box)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(stamp_color.r * 0.15, stamp_color.g * 0.15, stamp_color.b * 0.15, 0.85)
	sb.border_color = stamp_color
	sb.border_width_left = 6
	sb.border_width_right = 6
	sb.border_width_top = 6
	sb.border_width_bottom = 6
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	stamp_box.add_theme_stylebox_override("panel", sb)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	stamp_box.add_child(margin)

	var label = Label.new()
	label.text = "★ " + stamp_text.to_upper() + " ★"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", stamp_color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	margin.add_child(label)

	# Initial scale and rotation for impact drop
	stamp_box.pivot_offset = stamp_box.size / 2.0
	stamp_box.scale = Vector2(2.5, 2.5)
	stamp_box.rotation = randf_range(-0.15, 0.15)
	stamp_box.modulate.a = 0.0

	# Sound trigger if audio manager is available
	var tree = container.get_tree()
	if tree and tree.root.has_node("AudioManager"):
		tree.root.get_node("AudioManager").play_sfx("select")

	# Impact & Fade Tween bound to container's lifecycle
	var tween = container.create_tween().set_parallel(true)
	tween.tween_property(stamp_box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(stamp_box, "modulate:a", 1.0, 0.12)

	# Hold then fade out
	var fade_tween = container.create_tween()
	fade_tween.tween_interval(1.2)
	fade_tween.tween_property(container, "modulate:a", 0.0, 0.4)
	fade_tween.tween_callback(container.queue_free)

	return container
