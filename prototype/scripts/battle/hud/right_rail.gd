class_name RightRail
extends PanelContainer
# The under-minimap tactical rail.
#
# A fixed (not collapsible) vertical panel that sits directly below the
# minimap in the top-right corner. Hosts the BattleHUD's per-selection
# chrome that the current build buries under the production toolboxes
# (the bottom-right PRESET_BOTTOM_RIGHT stack at battle_hud.gd:247 and
# :256 lands under the rightmost production toolbox at 1280x720, and on
# 1920x1080 the SpecPlacard overlaps the rightmost two toolboxes by
# ~150px). This is the panel that fixes that.
#
# WHY A FIXED PANEL AND NOT A UIDock. The rail is meant to be the
# always-visible destination for the chrome the player needs most during
# a fight (selection aggregate, spec, command card). A UIDock's
# auto-reveal must stay off during battle (ui_dock.gd:30-34) and its
# railed state would hide the very chrome the rail exists to surface.
# A fixed PanelContainer with a ScrollContainer is the minimum that
# works, and the in-match chrome contract is to use the existing
# HUDPanel variation - no new theme work.
#
# CHROME LAYOUT. The minimap sits at PRESET_TOP_RIGHT with
# offset_top = SPACE_MD + 64 and offset_bottom = SPACE_MD + 64 +
# UI_SIZE (battle_hud.gd:225-227). The rail anchors directly below it,
# aligned to the same right edge, with one SPACE_MD gap so the two
# read as a stacked pair rather than a single fused panel.
#
# SCROLLING. The user asked for it because the rail's full height
# (SelectionPanel + SpecPlacard + CommandCard, vertically) is taller
# than 720p leaves. The rail's contents go inside a ScrollContainer so
# anything that doesn't fit scrolls. The SelectionPanel ships its own
# internal ScrollContainer (selection_panel.gd:27); nested scroll
# containers are fine and the inner one absorbs wheel events before the
# outer has a chance to.
#
# WHAT LIVES HERE (each added by its own PR, not this one):
#   PR2  CommandCard, SpecPlacard
#   PR3  SelectionPanel
#
# This PR ships the empty bezel. A placeholder label marks the rail as
# "in place, contents land in the next commits" so a playtest sees the
# geometry without the rail reading as a bug.
#
# THE IN-MATCH RULE. battle_hud.gd is on the in-match list in
# test_ui_and_camera.gd:734-742, which asserts no L0 workbench
# material and no UIShell.workbench() call. The rail inherits that
# constraint through battle_hud - HUDPanel (steel) is the only
# variation used here, exactly the same as the minimap above it.

const Tokens = preload("res://scripts/ui_tokens.gd")

# Width of the rail. Sized to fit the SelectionPanel's
# custom_minimum_size (240) plus SPACE_MD breathing room on each side;
# the SpecPlacard and CommandCard both fit at this width with no
# wrapping, and the production bar's centred toolbox row is unaffected
# because the rail lives in the right margin that row leaves free.
const RAIL_WIDTH := 260.0
# Height of the top strip - referenced from BattleHUD.TOP_STRIP_HEIGHT
# (battle_hud.gd:145) and copied here because the rail needs the same
# offset to land directly below the minimap rather than guessing. If
# BattleHUD.TOP_STRIP_HEIGHT ever moves, this constant moves with it.
const TOP_STRIP_HEIGHT := 56.0
# The minimap's UI_SIZE - also referenced from BattleHUD.UI_SIZE
# (battle_hud.gd:51) and copied here for the same reason. A change to
# the minimap size MUST propagate here.
const MINIMAP_SIZE := 180.0

var _body_host: VBoxContainer = null


func _init() -> void:
	# L1 elevation - recessed against the in-match steel backdrop, the
	# same variation the minimap, top strip, and HUDPanel chrome use.
	# InsetPanel would read as a drawer; HUDPanel reads as an instrument
	# face, which is what UI_STYLE_GUIDE.md §6a says the in-match chrome
	# should be.
	theme_type_variation = "HUDPanel"
	# MUST not cast a shadow at this tier - ui_style_guide.md §6a
	# "A recessed surface must not cast. flush is 0, not 'a small
	# shadow'." A shadow would claim the rail floats above the
	# minimap, which it does not.
	mouse_filter = Control.MOUSE_FILTER_PASS
	_anchor_under_minimap()


# Anchors + offsets that place the rail directly under the minimap, on
# the same right edge, with a SPACE_MD gap between them.
#
# Extracted so a re-layout (e.g. a future minimap move) has one
# single point of truth to update, not a four-offset block to chase.
func _anchor_under_minimap() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Right edge aligns with the minimap. Minimap uses -SPACE_MD; the
	# rail follows suit so the two read as one stack.
	offset_left = -(RAIL_WIDTH + Tokens.SPACE_MD)
	offset_right = -Tokens.SPACE_MD
	# Top: past the top strip (SPACE_MD + TOP_STRIP_HEIGHT) plus the
	# minimap height (MINIMAP_SIZE) plus one SPACE_MD gap. This is
	# the exact y the minimap's bottom edge occupies, plus a deliberate
	# gap so the two panels read as a stacked pair.
	offset_top = Tokens.SPACE_MD + TOP_STRIP_HEIGHT + MINIMAP_SIZE + Tokens.SPACE_MD
	# No explicit bottom anchor. The rail's height is content-driven,
	# so a fixed bottom would either clip the scrollable content or
	# fight the layout every time the viewport resized. The viewport
	# fit happens in the parent battle_hud (which sizes itself to
	# the viewport rect in fit_to_viewport()).
	offset_bottom = offset_top


# The container callers add their children to. Same pattern as
# UIDock.body() (ui_dock.gd:199-200) so the call site reads the same
# way at every chrome surface in the project: get a body, add
# children, the surface handles the rest.
func body() -> VBoxContainer:
	return _body_host


func _ready() -> void:
	_build()


# One Column VBoxContainer hosts the scroll wrapper. The vertical
# structure mirrors UIDock (ui_dock.gd:117-159) without the header /
# rail machinery - this rail is fixed, not collapsible, and has no
# title row.
func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Tokens.SPACE_SM)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(column)

	var scroll := ScrollContainer.new()
	scroll.name = "RailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# MOUSE_FILTER_STOP is what decouples list scrolling from world
	# zoom - production_hud.gd:223-248 documents the same trap and
	# the same fix. A wheel that the scroll consumes is accepted; one
	# it does not consume still ends here, not at the camera.
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and (
				event.button_index == MOUSE_BUTTON_WHEEL_UP
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			scroll.accept_event())
	column.add_child(scroll)

	_body_host = VBoxContainer.new()
	_body_host.name = "RailBody"
	_body_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_host.add_theme_constant_override("separation", Tokens.SPACE_SM)
	scroll.add_child(_body_host)
