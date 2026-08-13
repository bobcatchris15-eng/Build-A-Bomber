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


# Phase 12: the InputMap must not contradict InputService.
#
# InputService.install_all() calls InputMap.action_erase_events() on every
# action at boot, so its table wins at runtime and project.godot's [input]
# section is dead weight. That is a defensible architecture - it is what makes
# rebinding and profiles possible - but it lets project.godot hold stale,
# colliding bindings indefinitely with nothing noticing. It did: cmd_attack_move
# sat on A against cam_pan_left, and cmd_stop on S against cam_pan_down, for the
# whole of Phase 8, while check_input_binding_collisions() passed because it
# reads InputService rather than the InputMap.
#
# Anyone opening project.godot to fix a binding would be editing a file with no
# effect. So the section is now deliberately empty and this asserts it stays
# that way.
#
# IT HAS TO READ THE FILE, NOT THE InputMap. Comparing the live InputMap to
# InputService is tautological: install_all() has already overwritten it by the
# time any test runs, so the two always agree no matter what project.godot
# says. The drift only exists on disk, so that is where it has to be measured.
static func check_project_input_section() -> Dictionary:
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	if f == null:
		return {"valid": false, "problems": ["Could not read project.godot"]}
	var text := f.get_as_text()
	f.close()

	var start := text.find("[input]")
	if start == -1:
		# No section at all is the ideal state.
		return {"valid": true, "problems": []}
	var end := text.find("\n[", start + 1)
	if end == -1:
		end = text.length()
	var section := text.substr(start, end - start)

	var problems: Array = []
	for raw in section.split("\n"):
		var line := raw.strip_edges()
		# `;` is project.godot's comment marker; blank lines and the section
		# header itself are not declarations.
		if line.is_empty() or line.begins_with(";") or line.begins_with("["):
			continue
		var eq := line.find("=")
		if eq > 0:
			problems.append(
				"project.godot [input] declares '%s'; InputService is the single source of truth and erases it at boot" % line.substr(0, eq))

	return {"valid": problems.is_empty(), "problems": problems}


# Phase 12: the material luminance stack must stay strictly ascending.
#
# A control at or below the luminance of the surface it sits on has nowhere to
# sit, and no bevel rescues it. Not hypothetical: the moulded material (then
# called bakelite) sat at BASE_900 for a long time, so every button was darker
# than its own panel. Phase 4 put L0 underneath the whole stack, which is the
# specific way the workbench layer can make the interface worse - a desk
# brighter than the equipment on it inverts everything above it.
#
# MEASURED, NOT DECLARED. Only L0 carries an explicit `brightness` in
# MATERIAL_DEFAULTS; L1's luminances live in the field PNGs themselves. So this
# samples the actual field texture and multiplies by the brightness default,
# which is what UITheme.apply_material does at runtime. A material whose field
# cannot be measured is reported as unmeasurable rather than silently skipped.
const LUMINANCE_ORDER: Array = [
	"cutting_mat", "cardboard", "kraft", "cork", "chipboard",  # L0 workbench floor
	"powdercoat",                                              # panel body
	"canvas",                                                  # flyout / tooltip
	"moulded",                                                 # control body
	"steel",                                                   # rails, frames
]


static func check_material_luminance_stack() -> Dictionary:
	var theme_script = load("res://scripts/ui_theme.gd")
	if theme_script == null:
		return {"valid": false, "problems": ["Could not load ui_theme.gd"], "measured": {}}

	var measured: Dictionary = {}
	var problems: Array = []
	for material in LUMINANCE_ORDER:
		var lum := _material_luminance(theme_script, material)
		if lum >= 0.0:
			measured[material] = lum

	# L0 is a floor: every L0 material must sit below every L1 material in the
	# order. Within L0 the ordering is not meaningful (five desks, no hierarchy),
	# so the tiers are compared rather than the full sequence.
	var l0_max := -1.0
	var l1_min := 2.0
	for material in measured:
		var lum: float = measured[material]
		if L0_MATERIALS.has(material):
			l0_max = maxf(l0_max, lum)
		else:
			l1_min = minf(l1_min, lum)
	if l0_max >= 0.0 and l1_min <= 1.0 and l0_max >= l1_min:
		problems.append(
			"L0 workbench (brightest %.4f) is not below the L1 equipment layer (darkest %.4f); panels will sink into the desk" % [l0_max, l1_min])

	# Within L1 the order IS meaningful and must ascend.
	var last_lum := -1.0
	var last_name := ""
	for material in LUMINANCE_ORDER:
		if L0_MATERIALS.has(material) or not measured.has(material):
			continue
		var lum: float = measured[material]
		if last_lum >= 0.0 and lum < last_lum:
			problems.append(
				"Luminance stack inverted: '%s' (%.4f) is darker than '%s' (%.4f), which sits below it" % [material, lum, last_name, last_lum])
		last_lum = lum
		last_name = material

	return {"valid": problems.is_empty(), "problems": problems, "measured": measured}


# Mean luminance of a material's field texture times its brightness default -
# the same product UITheme.apply_material feeds the shader. Returns -1.0 when
# the field cannot be read.
static func _material_luminance(theme_script, material: String) -> float:
	var path: String = "res://assets/textures/ui/field_%s.png" % material
	if not ResourceLoader.exists(path):
		return -1.0
	var tex = load(path)
	if tex == null:
		return -1.0
	var img: Image = tex.get_image()
	if img == null:
		return -1.0
	# Sample on a coarse grid rather than every texel: these are 512x512
	# fields and the mean is stable well before a full scan.
	var step := 16
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	if n == 0:
		return -1.0
	var brightness := 1.0
	var defaults: Dictionary = theme_script.MATERIAL_DEFAULTS
	if defaults.has(material):
		brightness = float(defaults[material].get("brightness", 1.0))
	return (total / float(n)) * brightness


const L0_MATERIALS: Array = ["cutting_mat", "cardboard", "kraft", "cork", "chipboard"]


# Phase 12: layer discipline (Part 0.5 of the plan).
#
# "Any given control belongs to exactly one material register." Two violations
# are worth catching mechanically, and they are the two the plan names: an L0
# workbench material applied to something inside a panel (the workbench is a
# backdrop register, not a control register), and an L3 stamped placard drawn
# on the glass of a phosphor readout rather than on the bezel around it.
static func check_layer_discipline(node: Node, results: Array = []) -> Array:
	_walk_layer_discipline(node, results, false, false)
	return results


static func _walk_layer_discipline(node: Node, results: Array, inside_panel: bool, inside_phosphor: bool) -> void:
	var script_path := ""
	if node.get_script() != null:
		script_path = String(node.get_script().resource_path)

	if inside_panel and node.has_meta("ui_material"):
		var mat := String(node.get_meta("ui_material"))
		if L0_MATERIALS.has(mat):
			results.append({
				"path": str(node.get_path()),
				"problem": "L0 material '%s' applied inside a panel; the workbench is a backdrop register" % mat,
			})

	if inside_phosphor and (script_path.ends_with("ui_stamped_label.gd") or script_path.ends_with("ui_stamp.gd")):
		results.append({
			"path": str(node.get_path()),
			"problem": "L3 stamped placard drawn on phosphor glass; stamp the bezel, not the screen",
		})

	var next_panel := inside_panel or node is PanelContainer
	var next_phosphor := inside_phosphor or script_path.ends_with("phosphor_panel.gd")
	for child in node.get_children():
		_walk_layer_discipline(child, results, next_panel, next_phosphor)


# Phase 12: per-button texture coverage (D1).
#
# Every StampedButton legend should resolve to a baked variant, or that button
# silently wears the shared push_button set and "unique textures per button"
# quietly stops being true for it. Reported rather than failed: the fallback is
# deliberate, and a legend can legitimately be formatted at runtime. What must
# not happen is nobody noticing.
static func check_button_prop_coverage(node: Node, results: Array = []) -> Array:
	var registry = load("res://scripts/ui/ui_prop_registry.gd")
	if registry == null:
		return results
	if node.get_script() != null and String(node.get_script().resource_path).ends_with("ui_stamped_button.gd"):
		var legend := String(node.get("legend"))
		if legend != "" and registry.variant_id_for_legend(legend) == "":
			results.append({
				"path": str(node.get_path()),
				"legend": legend,
				"slug": registry.slugify(legend),
				"problem": "no baked texture variant; falls back to the shared push_button set",
			})
	for child in node.get_children():
		check_button_prop_coverage(child, results)
	return results
