class_name UIAudit
extends RefCounted

static func find_overflowing_panels(node: Node, results: Array = []) -> Array:
	if node is Control and node.is_visible_in_tree() and node.get_child_count() > 0:
		var h_fixed = not (node.size_flags_horizontal & Control.SIZE_EXPAND)
		var v_fixed = not (node.size_flags_vertical & Control.SIZE_EXPAND)
		if node.size.x < 4.0 and node.size.y < 4.0:
			h_fixed = false
			v_fixed = false
		# Explicit opt-out for containers whose whole job is to clip. A
		# collapsed drawer (parts_menu.gd) is a zero-height clip window around
		# a full-height button list: correct behaviour that looks exactly like
		# the bug this audit hunts for.
		#
		# Deliberately a meta flag and NOT a `clip_contents` check, which was
		# the obvious version and is wrong: ScrollContainer sets clip_contents
		# internally, so keying off it would have silently exempted every
		# ScrollContainer in the project - the exact node type the real
		# overflow bug this tool was written for lived in. Caught by
		# test_ui_audit_has_real_teeth, which is what that suite is for.
		# An opt-out has to be something a caller states on purpose.
		if node.get_meta("ui_audit_clip_ok", false):
			h_fixed = false
			v_fixed = false
		if h_fixed or v_fixed:
			var content_min = Vector2.ZERO
			var culprit_path = ""
			for child in node.get_children():
				if child is Control and child.is_visible_in_tree():
					var cmin = child.get_combined_minimum_size()
					if cmin.x > content_min.x:
						content_min.x = cmin.x
						culprit_path = str(child.get_path())
					content_min.y = max(content_min.y, cmin.y)
			var overflow_x = h_fixed and content_min.x > node.size.x + 2.0
			var overflow_y = v_fixed and content_min.y > node.size.y + 2.0
			if overflow_x or overflow_y:
				results.append({
					"path": str(node.get_path()),
					"fixed_size": node.size,
					"content_min_size": content_min,
					"overflow_x": overflow_x,
					"overflow_y": overflow_y,
					"culprit": culprit_path,
				})
	for child in node.get_children():
		find_overflowing_panels(child, results)
	return results

static func find_offscreen_controls(node: Node, viewport_rect: Rect2, results: Array = []) -> Array:
	if node is Control and node.is_visible_in_tree():
		var rect = node.get_global_rect()
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			if not viewport_rect.intersects(rect):
				results.append({"path": str(node.get_path()), "rect": rect})
	for child in node.get_children():
		find_offscreen_controls(child, viewport_rect, results)
	return results

static func check_theme_resource_validity() -> Dictionary:
	var res_path = "res://resources/bomber_theme.tres"
	var exists = ResourceLoader.exists(res_path)
	if not exists:
		return {"valid": false, "reason": "bomber_theme.tres does not exist"}
	var theme = load(res_path) as Theme
	if not theme:
		return {"valid": false, "reason": "Failed to load bomber_theme.tres as Theme"}
	var has_panel = theme.has_stylebox("panel", "Panel")
	var has_button = theme.has_stylebox("normal", "Button")
	return {"valid": has_panel and has_button, "reason": "Theme resource contains core styleboxes"}

static func check_icon_assets() -> Dictionary:
	var missing = []
	for icon_name in UIIcons.ICON_PATHS:
		var path = UIIcons.ICON_PATHS[icon_name]
		if not FileAccess.file_exists(path):
			missing.append(icon_name)
	return {"valid": missing.is_empty(), "missing": missing}

static func check_cursor_assets() -> Dictionary:
	var missing = []
	for type in CursorManager.CURSOR_CONFIGS:
		var path = CursorManager.CURSOR_CONFIGS[type]["path"]
		if not FileAccess.file_exists(path):
			missing.append(path)
	return {"valid": missing.is_empty(), "missing": missing}
