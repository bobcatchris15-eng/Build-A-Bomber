extends VBoxContainer
class_name UIToolbox
# A stack of collapsible tiers - the "toolbox" widget.
#
# One header per tier; clicking it reveals that tier's body and (by default)
# closes its siblings. Used for the Design Lab's hardware catalogue on the left
# (Hulls / Weapons / Support / Drives) and its document actions on the right.
#
# EXTRACTED, not invented. This shipped twice first - parts_menu.gd's
# _make_family_tier/_open_family_tier/_force_open_family and
# stat_calculator.gd's _build_admin_toolbox were the same widget built twice,
# with the second copy written deliberately while the first was still unproven.
# Both call sites move onto this in the same change that adds it, which is the
# bar ui_shell.gd's history sets: the six helpers removed from that file had zero
# call sites because they were written before anything needed them.
#
# WHY A NODE AND NOT STATIC HELPERS. The accordion needs to know a tier's
# siblings, so something has to own the set. A node that IS the container is the
# honest place for that - the alternative is a static function plus a
# caller-managed dictionary, which is what the two copies did and is how they
# drifted apart on stagger direction.

const Tokens = preload("res://scripts/ui_tokens.gd")
const UIAnim = preload("res://scripts/ui_anim.gd")
const UIFeedbackScript = preload("res://scripts/ui_feedback.gd")

signal tier_opened(id: String)

# Horizontal offset the body's children slide in from. Negative reads as
# "unfolding rightward out of the header" for a left-edge dock; a right-edge dock
# passes a positive value so it unfolds the other way.
var stagger_from: Vector2 = Vector2(-12, 0)

# id -> {tier, header, body}
var _tiers: Dictionary = {}
var _order: Array = []


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", Tokens.SPACE_XS)


# Adds a tier and returns its BODY, which is what a caller fills.
#
# `start_open` exists for a toolbox with a single tier, where closing it by
# default just hides the only thing there is.
func add_tier(id: String, label: String, start_open: bool = false) -> VBoxContainer:
	if _tiers.has(id):
		return _tiers[id]["body"]

	var tier := VBoxContainer.new()
	tier.name = "Tier_%s" % id
	tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := Button.new()
	# TabButton: the theme inverts a tab's bevel when inactive, so a closed tier
	# reads as pressed shut and the open one lifts. That is the cue that makes a
	# stack of these read as lids rather than as a list of rows.
	header.theme_type_variation = "TabButton"
	header.text = label
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size = Vector2(0, Tokens.HIT_TARGET_MIN)
	header.focus_mode = Control.FOCUS_NONE
	header.toggle_mode = true
	header.button_pressed = start_open
	tier.add_child(header)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.SPACE_XS)
	body.visible = start_open
	tier.add_child(body)

	_tiers[id] = {"tier": tier, "header": header, "body": body}
	_order.append(id)
	add_child(tier)

	header.toggled.connect(func(pressed: bool):
		if pressed:
			open(id)
		else:
			body.visible = false
	)
	UIFeedbackScript.wire(header, "select")
	return body


# Opens one tier and closes the rest.
func open(id: String) -> void:
	for other in _order:
		var t: Dictionary = _tiers[other]
		var tier: Control = t["tier"]
		if not is_instance_valid(tier):
			continue
		var is_target: bool = other == id
		t["body"].visible = is_target
		# set_pressed_no_signal, or closing a sibling re-enters this function
		# through its own toggled handler and the loop fights itself.
		t["header"].set_pressed_no_signal(is_target)
		if is_target:
			UIAnim.stagger_in(t["body"], stagger_from)
	tier_opened.emit(id)


# Opens a tier WITHOUT closing its siblings.
#
# For search, which is not a navigation act: a query can match parts in several
# tiers and revealing one while hiding the others would lose most of the hits.
func force_open(id: String) -> void:
	if not _tiers.has(id):
		return
	var t: Dictionary = _tiers[id]
	if not is_instance_valid(t["tier"]):
		return
	t["tier"].visible = true
	t["body"].visible = true
	t["header"].set_pressed_no_signal(true)


func body_of(id: String) -> VBoxContainer:
	return _tiers[id]["body"] if _tiers.has(id) else null


func has_tier(id: String) -> bool:
	return _tiers.has(id)


func tier_ids() -> Array:
	return _order.duplicate()
