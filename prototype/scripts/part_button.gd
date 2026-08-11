extends Button

var module_type_id: String = ""

# VISUAL_IMPROVEMENT_PLAN.md chunk G: Godot's default tooltip is a plain
# PopupPanel - this overrides the virtual _make_custom_tooltip() Godot
# itself calls to build one, returning a styled card instead. `for_text` is
# whatever this button's own `tooltip_text` is currently set to (parts_menu.
# gd's _stat_tooltip() - "<name>\nHP: ... | Weight: ...\nCost: ...\nDPS: ...")
# - split on newlines into a bold title row (the part name) plus smaller
# stat rows below, matching the "icon + title + stat rows" card shape the
# plan calls for (no icon graphic system exists in this project yet - see
# VISUAL_IMPROVEMENT_PLAN.md's own note that every "icon" today is emoji in
# button text, which the title row already carries through unchanged).
func _make_custom_tooltip(for_text: String) -> Control:
	var panel = PanelContainer.new()
	# CANVAS from the theme, the same soft backing the flyouts and callouts use -
	# a tooltip is exactly that category of object, laid over the interface rather
	# than built into it.
	#
	# The inline stylebox this replaces was a blue-black fill with a 5px "Yellow
	# Model Kit Instruction Decal Border" and 4px corners: three separate values
	# that appear nowhere in ui_tokens.gd, on the one card a player reads dozens of
	# times per session while comparing parts.
	panel.theme_type_variation = "FlyoutPanel"

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var lines = for_text.split("\n")
	if lines.is_empty():
		return panel
	var title = Label.new()
	title.text = lines[0]
	title.theme_type_variation = "HeadingLabel"
	vbox.add_child(title)
	for i in range(1, lines.size()):
		var row = Label.new()
		row.text = lines[i]
		# StatLabel: these rows ARE stats ("HP: 75 | Weight: 65 kg"), and the mono
		# face is what makes a column of them comparable between two tooltips.
		row.theme_type_variation = "StatLabel"
		vbox.add_child(row)

	# Flavor row (VISUAL_ART_DIRECTION.md 1.2 - the tone target's cheapest
	# detail-scale channel; see ModuleCatalog.MODULE_FLAVOR for the voice
	# rules). Looked up from module_type_id rather than parsed out of
	# `for_text`: keeps tooltip_text as pure stat data with no sentinel
	# encoding, and means the flavor line can't be mistaken for a stat row
	# by anything else reading that string.
	var flavor := ""
	if module_type_id != "":
		flavor = ModuleCatalog.get_module_flavor(module_type_id)
	if flavor != "":
		# Thin rule separating hard numbers from voice, so the card doesn't
		# read as though the flavor line were another stat.
		var sep = HSeparator.new()
		sep.add_theme_constant_override("separation", 6)
		vbox.add_child(sep)

		var flavor_label = Label.new()
		flavor_label.text = flavor
		# HintLabel is the secondary-text role: present but subordinate, so the
		# voice line never competes with the numbers a player is comparing. That is
		# what the old hand-mixed (0.62, 0.60, 0.55) was approximating - it is
		# within a hair of Tokens.TEXT_SECONDARY, which HintLabel already carries.
		flavor_label.theme_type_variation = "HintLabel"
		# These lines run to ~90 chars; without an explicit wrap the tooltip
		# card would stretch into a single very wide strip.
		flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor_label.custom_minimum_size = Vector2(260, 0)
		vbox.add_child(flavor_label)

	return panel

func _get_drag_data(at_position: Vector2):
	# DRAG PREVIEW. The old version was a plain Label with the part's name,
	# which read as a drag-ANYWHERE-and-look-for-the-text bookmark rather
	# than as a visual handle. The player is choosing a shape, and the
	# shape is the thing the cursor should be carrying.
	#
	# Implementation: a small PanelContainer with a TextureRect of the
	# rendered part (see part_thumbnail.gd) above a one-line label. The
	# thumbnail is fetched from the MainLab PartThumbnailCache - cached on
	# first request, so the second-and-later drags of the same part are
	# instant. The first drag of a session pays one frame for the bake.
	#
	# Backed by a PanelContainer (not a bare TextureRect) so the preview
	# has the same dark drop-shadow + hairline border the parts-menu cards
	# do - otherwise the dragged icon would look like a screenshot
	# pasted onto the cursor, instead of a piece of the same UI.
	var preview_control := PanelContainer.new()
	preview_control.theme_type_variation = "FlyoutPanel"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	preview_control.add_child(vbox)

	var preview_tex := TextureRect.new()
	preview_tex.custom_minimum_size = Vector2(96, 96)
	preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Hard-coded tint if the bake was not ready (cache miss + first
	# async bake in flight) so the preview is never empty. A TextureRect
	# with a null texture paints a black rectangle, which would look like
	# the part had loaded as a hole.
	preview_tex.modulate = Color(1, 1, 1, 1)
	vbox.add_child(preview_tex)

	# Sync cache path. If the bake for this type_id has already run for
	# any other drag this session, hand the texture back right now and
	# skip the async wait - the cursor is moving every frame and any
	# frame spent waiting is a frame the player sees a blank icon.
	var cache := _get_thumbnail_cache()
	if cache != null:
		# cache is typed Node (not PartThumbnailCache) so the dynamic call
		# is untyped; declare the receiver's type explicitly so the strict
		# parser can infer.
		var existing: Texture2D = cache.get_thumbnail_now(module_type_id)
		if existing != null:
			preview_tex.texture = existing

	var preview_label := Label.new()
	preview_label.text = text
	preview_label.theme_type_variation = "StatLabel"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(preview_label)

	set_drag_preview(preview_control)

	# Async path. The first drag of a session triggers the actual bake.
	# When it finishes, the preview TextureRect is updated in place - the
	# drag_control is now a child of the viewport's drag layer, so a late
	# mutation is the only safe way to swap in the texture after the
	# drag has already started. The cursor is already visible, so there
	# is a one-frame window where the preview shows a black box; that is
	# the exact cost the same trade blueprint_thumbnail.gd accepts.
	if cache != null and preview_tex.texture == null:
		_run_bake(cache, preview_tex)

	return {"type": "module_part", "id": module_type_id}


# The cache lives on MainLab as a sibling node (see MainLab.tscn). The
# button is created in the parts menu deep inside UI_PartsMenu, so a
# direct path lookup is the cleanest reach. Returns null if MainLab has
# been torn down (test teardown, scene swap) so the preview falls back
# to the label-only form rather than crashing.
func _get_thumbnail_cache() -> Node:
	var root := get_tree().root if get_tree() != null else null
	if root == null:
		return null
	var lab := root.get_node_or_null("MainLab")
	if lab == null:
		return null
	return lab.get_node_or_null("PartThumbnailCache")


func _run_bake(cache: Node, target: TextureRect) -> void:
	var tex: Texture2D = await cache.get_thumbnail(module_type_id)
	# The button or the texture rect can have been freed between the
	# bake and its await resuming (parts-menu rebuild, scene swap, a
	# fast second click). is_instance_valid guards both without having
	# to track ownership.
	if tex != null and is_instance_valid(target):
		target.texture = tex
