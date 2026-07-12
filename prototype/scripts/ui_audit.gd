class_name UIAudit
# Headless UI regression checks. Both techniques here were empirically
# validated against the real UI_StatBlock.tscn/MainLab.tscn scenes before
# being built in (see PROGRESS.md) - notably, the naive "compare a Label's
# own .size to its own get_minimum_size()" approach does NOT work in this
# codebase: the UI is built on auto-sizing VBoxContainers that grow to
# exactly fit their children, so a control's size trivially always equals
# its own minimum. The real signal is a genuinely fixed-size ancestor
# panel (one whose size comes from screen anchors, not from expanding to
# fit content) versus its content's natural combined minimum size.

# Scans for "fixed" Controls (size_flags without SIZE_EXPAND on that axis)
# whose direct Control children need more space than the fixed size
# provides. Returns an Array of Dictionaries:
#   {path, fixed_size, content_min_size, overflow_x, overflow_y, culprit}
static func find_overflowing_panels(node: Node, results: Array = []) -> Array:
	if node is Control and node.is_visible_in_tree() and node.get_child_count() > 0:
		var h_fixed = not (node.size_flags_horizontal & Control.SIZE_EXPAND)
		var v_fixed = not (node.size_flags_vertical & Control.SIZE_EXPAND)
		# A "fixed" panel with a near-zero actual size hasn't been through a
		# real layout pass yet (or is a collapsed/not-yet-shown popup that
		# is_visible_in_tree() didn't catch for some other reason) - not a
		# genuine "too small for its content" case, skip it rather than
		# flag a false positive.
		if node.size.x < 4.0 and node.size.y < 4.0:
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

# Scans for visible Controls whose global rect has zero overlap with the
# viewport's visible rect - i.e. fully off-screen (a popup positioned
# outside the window, a panel with a broken anchor calculation, etc).
# Ignores zero-size controls (containers not yet laid out, or genuinely
# empty spacers) since those aren't visually meaningful either way.
static func find_offscreen_controls(node: Node, viewport_rect: Rect2, results: Array = []) -> Array:
	if node is Control and node.is_visible_in_tree():
		var rect = node.get_global_rect()
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			if not viewport_rect.intersects(rect):
				results.append({"path": str(node.get_path()), "rect": rect})
	for child in node.get_children():
		find_offscreen_controls(child, viewport_rect, results)
	return results
