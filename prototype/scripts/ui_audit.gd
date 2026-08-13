class_name UIAudit
extends RefCounted

# Interface audit routines (Phase 12 enforcement).
# Enforces mechanical constraints: overflow, offscreen controls, theme/icon/cursor
# validity, no-emoji rule, layer discipline, and input binding collision checks.

const UIIcons = preload("res://scripts/ui_icons.gd")
const CursorManager = preload("res://scripts/cursor_manager.gd")


static func find_overflowing_panels(node: Node, results: Array = []) -> Array:
	if node is Control and node.is_visible_in_tree() and node.get_child_count() > 0:
		var h_fixed = not (node.size_flags_horizontal & Control.SIZE_EXPAND)
		var v_fixed = not (node.size_flags_vertical & Control.SIZE_EXPAND)
		if node.size.x < 4.0 and node.size.y < 4.0:
			h_fixed = false
			v_fixed = false
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
			if not viewport_rect.intersects(rect) and not _is_inside_scroll(node):
				results.append({"path": str(node.get_path()), "rect": rect})
	for child in node.get_children():
		find_offscreen_controls(child, viewport_rect, results)
	return results


static func _is_inside_scroll(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


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


# Phase 12: No-emoji enforcement.
# Scans text across controls to catch prohibited emoji ranges (e.g. 0x1F300-0x1FAFF).
# Allows standard ASCII, Latin, Cyrillic, Greek, mathematical symbols, arrows (0x2190-0x21FF),
# and box-drawing characters (0x2500-0x257F).
static func find_emoji_usage(node: Node, results: Array = []) -> Array:
	var text_to_check := ""
	if node is Label:
		text_to_check = (node as Label).text
	elif node is Button:
		text_to_check = (node as Button).text
	elif node is RichTextLabel:
		text_to_check = (node as RichTextLabel).text
	elif node is LineEdit:
		text_to_check = (node as LineEdit).text

	if text_to_check != "":
		for i in range(text_to_check.length()):
			var code := text_to_check.unicode_at(i)
			# Emoji block ranges: Miscellaneous Symbols and Pictographs (0x1F300-0x1F5FF),
			# Emoticons (0x1F600-0x1F64F), Transport/Map (0x1F680-0x1F6FF), Supplemental (0x1F900-0x1FAFF)
			if (code >= 0x1F300 and code <= 0x1FAFF) or (code >= 0x1F600 and code <= 0x1F64F):
				results.append({
					"path": str(node.get_path()),
					"char": text_to_check[i],
					"codepoint": code,
					"text": text_to_check,
				})
				break

	for child in node.get_children():
		find_emoji_usage(child, results)
	return results


# Phase 12: Input binding collision check.
# Asserts that no command or lab action shares a physical key with any camera action.
static func check_input_binding_collisions() -> Dictionary:
	var input_service_script = load("res://scripts/core/input_service.gd")
	if input_service_script == null:
		return {"valid": false, "collisions": ["Could not load input_service.gd"]}

	var actions: Dictionary = input_service_script.ACTIONS
	var cam_keys: Dictionary = {}

	# Collect all keys used by camera actions
	for action_name in actions.keys():
		if action_name.begins_with("cam_"):
			var entry: Dictionary = actions[action_name]
			for ev in entry.get("events", []):
				if "key" in ev:
					cam_keys[ev["key"]] = action_name

	var collisions: Array = []
	for action_name in actions.keys():
		if not action_name.begins_with("cam_"):
			var entry: Dictionary = actions[action_name]
			for ev in entry.get("events", []):
				if "key" in ev and not bool(ev.get("ctrl", false)) and not bool(ev.get("alt", false)):
					var k = ev["key"]
					if cam_keys.has(k):
						collisions.append("Action '%s' collides with camera action '%s' on key %s" % [action_name, cam_keys[k], str(k)])

	return {"valid": collisions.is_empty(), "collisions": collisions}
