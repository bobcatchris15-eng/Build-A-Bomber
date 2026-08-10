extends Node
# Autoload: the single source of truth for what every key in the game does.
#
# WHY THIS EXISTS. Before it, `project.godot` had no `[input]` section at all and
# `is_action_pressed` appeared nowhere in scripts/. Every key was a raw keycode
# compared inline, spread across six files. Three consequences, all of which had
# already cost something:
#
#   1. NOTHING WAS REBINDABLE. There was no settings screen because there was
#      nothing for one to edit.
#   2. IT FORCED A GAMEPLAY DECISION. match_director.gd carried a comment
#      explaining that attack-move was on Q rather than the conventional A
#      "because rts_camera.gd polls WASD directly in _process() via
#      Input.is_key_pressed() rather than consuming input events, so a command
#      bound to A fires AND pans the camera - both handlers see the key and
#      neither can mark it handled." An implementation accident chose a binding.
#   3. IT FORCED A PERMANENT ON-SCREEN CHEAT SHEET. Because the bindings were
#      unconventional and nothing could render them from data, the battlefield
#      drew a fixed two-line keymap in the corner, with its own comment admitting
#      "nothing else in the build documents them yet."
#
# WHY THE TABLE LIVES HERE AND NOT IN project.godot. A `[input]` section is a
# flat list: it cannot express a switchable profile, it cannot be unit-tested
# headless, and it cannot carry the human-readable label or the group a binding
# belongs to. All three are needed by the Controls screen. So project.godot keeps
# only Godot's built-in `ui_*` actions and this installs everything else at boot.
#
# THE CAMERA DECISION, recorded because every command binding is downstream of
# it. WASD-camera and letter command hotkeys are mutually exclusive - StarCraft
# II, C&C and Age of Empires put the camera on arrows plus edge-scroll precisely
# so the letters stay free. Kitbash Command goes the other way (Chris: "WASD and
# Edge scroll, i like it better. Users can remap keys individually if they want",
# and "Q/E feel natural for camera rotation"), so the camera owns
# W A S D Q E and the commands route around them:
#
#     camera    W A S D pan · Q E yaw · wheel zoom · middle-drag · edge scroll
#     commands  R T / F G H / Z X C V B · Space · F1 F2 · 1-9 groups
#
# Eleven contextual command slots, with the on-screen command card as the
# discovery surface rather than the letters themselves. Every binding is
# individually remappable, which is the release valve for anyone who wants the
# conventional A-move back.
#
# NOTE THE HISTORY THIS REPLACES. Attack-move and stop used to be Q and E - not
# chosen, but *defaulted to* because the camera's raw WASD polling made A and S
# unusable. They are now F and G because the camera legitimately owns Q and E.
# The bindings moved; more importantly the reason did.

signal bindings_changed(action: String)
signal profile_changed(profile: String)

const CONFIG_PATH := "user://input.cfg"

# Groups exist so the Controls screen can section itself and so "reset to
# defaults" can be per-section rather than all-or-nothing. A player who has
# customised their camera should not lose it to fix one command binding.
const GROUP_CAMERA := "camera"
const GROUP_COMMAND := "command"
const GROUP_LAB := "lab"
const GROUP_SYSTEM := "system"

const GROUP_LABELS := {
	GROUP_CAMERA: "Camera",
	GROUP_COMMAND: "Battle commands",
	GROUP_LAB: "Design Lab",
	GROUP_SYSTEM: "System",
}

const GROUP_ORDER := [GROUP_CAMERA, GROUP_COMMAND, GROUP_LAB, GROUP_SYSTEM]


# --- The action table --------------------------------------------------------
#
# One entry per action. `events` is a list of DESCRIPTORS, not InputEvent
# instances: a plain dictionary serialises to the config file directly, compares
# with ==, and can be written in a test without constructing engine objects.
# _event_from() turns one into a real InputEvent at install time.
#
# Descriptor forms:
#   {"key": KEY_W}                         a plain key
#   {"key": KEY_Z, "ctrl": true}           with modifiers (ctrl/shift/alt)
#   {"mouse": MOUSE_BUTTON_WHEEL_UP}       a mouse button
#
# `label` is what the Controls screen shows. It is written as a phrase a player
# would recognise, not as the action id with underscores removed.
const ACTIONS := {
	# --- Camera ---------------------------------------------------------------
	# Both WASD and the arrows, matching the behaviour rts_camera.gd shipped with.
	# This migration is deliberately binding-neutral: it changes HOW the camera
	# reads input, not WHICH keys it reads, so a red suite after it can only mean
	# the refactor broke something.
	"cam_pan_up": {
		"group": GROUP_CAMERA, "label": "Pan forward",
		"events": [{"key": KEY_W}, {"key": KEY_UP}],
	},
	"cam_pan_down": {
		"group": GROUP_CAMERA, "label": "Pan back",
		"events": [{"key": KEY_S}, {"key": KEY_DOWN}],
	},
	"cam_pan_left": {
		"group": GROUP_CAMERA, "label": "Pan left",
		"events": [{"key": KEY_A}, {"key": KEY_LEFT}],
	},
	"cam_pan_right": {
		"group": GROUP_CAMERA, "label": "Pan right",
		"events": [{"key": KEY_D}, {"key": KEY_RIGHT}],
	},
	"cam_zoom_in": {
		"group": GROUP_CAMERA, "label": "Zoom in",
		"events": [{"mouse": MOUSE_BUTTON_WHEEL_UP}],
	},
	"cam_zoom_out": {
		"group": GROUP_CAMERA, "label": "Zoom out",
		"events": [{"mouse": MOUSE_BUTTON_WHEEL_DOWN}],
	},
	# Q/E yaw, the Age of Empires IV / Company of Heroes convention and the
	# natural companion to WASD (Chris: "Q/E feel natural for camera rotation").
	#
	# THESE ARE NEW CAPABILITY, NOT A REBINDING. rts_camera.gd is a fixed overhead
	# rig with no yaw whatsoever - battle_hud.gd's minimap recentre relies on that
	# ("The camera is a fixed overhead rig with no separate pan target, so its X/Z
	# is its ground focus"). Adding yaw means pan must become YAW-RELATIVE in the
	# same change, or panning after a rotation drives the camera sideways relative
	# to what the player is looking at. See rts_camera.gd's own migration note.
	"cam_rotate_left": {
		"group": GROUP_CAMERA, "label": "Rotate camera left",
		"events": [{"key": KEY_Q}],
	},
	"cam_rotate_right": {
		"group": GROUP_CAMERA, "label": "Rotate camera right",
		"events": [{"key": KEY_E}],
	},
	"cam_reset_rotation": {
		"group": GROUP_CAMERA, "label": "Reset camera rotation",
		"events": [{"key": KEY_HOME}],
	},

	# --- Battle commands ------------------------------------------------------
	# Everything here avoids W/A/S/D/Q/E by construction. See the header note.
	#
	# F and G rather than the conventional A and S, because the camera owns the
	# left-hand home row. They sit directly under the index finger from WASD rest
	# position, which is the best ergonomics available once A/S/Q/E are spoken
	# for. Attack-move and stop are the two most-issued commands in an RTS, so
	# they get the two best remaining keys.
	"cmd_attack_move": {
		"group": GROUP_COMMAND, "label": "Attack-move",
		"events": [{"key": KEY_F}],
	},
	"cmd_stop": {
		"group": GROUP_COMMAND, "label": "Stop",
		"events": [{"key": KEY_G}],
	},
	"cmd_patrol": {
		"group": GROUP_COMMAND, "label": "Patrol",
		"events": [{"key": KEY_R}],
	},
	"cmd_set_rally": {
		"group": GROUP_COMMAND, "label": "Set rally point",
		"events": [{"key": KEY_T}],
	},
	"cmd_stance_aggressive": {
		"group": GROUP_COMMAND, "label": "Stance: aggressive",
		"events": [{"key": KEY_Z}],
	},
	"cmd_stance_return_fire": {
		"group": GROUP_COMMAND, "label": "Stance: return fire",
		"events": [{"key": KEY_X}],
	},
	"cmd_hold": {
		"group": GROUP_COMMAND, "label": "Hold position",
		"events": [{"key": KEY_C}],
	},
	# New in this phase, and both are RTS table stakes the build did not have.
	# They are bound but inert until the alert and idle-worker services land in
	# Phase 5 - declaring them now means the Controls screen ships complete and
	# no later phase has to touch this table to add a key.
	"cmd_jump_alert": {
		"group": GROUP_COMMAND, "label": "Jump to latest alert",
		"events": [{"key": KEY_SPACE}],
	},
	"cmd_idle_worker": {
		"group": GROUP_COMMAND, "label": "Cycle idle harvesters",
		"events": [{"key": KEY_F1}],
	},
	"cmd_select_all_army": {
		"group": GROUP_COMMAND, "label": "Select all combat units",
		"events": [{"key": KEY_F2}],
	},

	# --- Design Lab -----------------------------------------------------------
	"lab_mirror": {
		"group": GROUP_LAB, "label": "Toggle mirror mode",
		"events": [{"key": KEY_M}],
	},
	"lab_rotate": {
		"group": GROUP_LAB, "label": "Rotate selected part",
		"events": [{"key": KEY_R}],
	},
	"lab_delete": {
		"group": GROUP_LAB, "label": "Delete selected part",
		# KP_PERIOD because hull_builder.gd accepted it before the migration and
		# dropping a binding during a refactor is how a refactor becomes a change.
		"events": [{"key": KEY_DELETE}, {"key": KEY_BACKSPACE}, {"key": KEY_KP_PERIOD}],
	},
	"lab_duplicate": {
		"group": GROUP_LAB, "label": "Duplicate selected",
		"events": [{"key": KEY_D, "ctrl": true}],
	},
	"lab_undo": {
		"group": GROUP_LAB, "label": "Undo",
		"events": [{"key": KEY_Z, "ctrl": true}],
	},
	# Both conventions, because both are muscle memory for different people and
	# there is no cost to accepting each. Ctrl+Shift+Z must be listed BEFORE the
	# plain Ctrl+Z form is matched anywhere, which _matches() handles by
	# comparing modifiers exactly rather than permissively - see its comment.
	"lab_redo": {
		"group": GROUP_LAB, "label": "Redo",
		"events": [{"key": KEY_Y, "ctrl": true}, {"key": KEY_Z, "ctrl": true, "shift": true}],
	},
	"lab_save": {
		"group": GROUP_LAB, "label": "Save design",
		"events": [{"key": KEY_S, "ctrl": true}],
	},

	# --- System ---------------------------------------------------------------
	"sys_perf": {
		"group": GROUP_SYSTEM, "label": "Performance overlay",
		"events": [{"key": KEY_F3}],
	},
	"sys_console": {
		"group": GROUP_SYSTEM, "label": "Debug menu",
		"events": [{"key": KEY_F10}, {"key": KEY_QUOTELEFT}],
	},
}

# Control groups are generated rather than written out, because nine near-identical
# table entries is nine chances to typo one and strand a digit.
const CONTROL_GROUP_COUNT := 9


var _overrides: Dictionary = {}
var _generated: Dictionary = {}


func _ready() -> void:
	_generated = _build_control_group_actions()
	_load()
	install_all()


# --- Installation ------------------------------------------------------------

func all_actions() -> Dictionary:
	# The static table plus the generated control-group entries, as one dictionary.
	# Callers (the Controls screen, the tests) should use this rather than ACTIONS
	# directly or they will silently miss nine bindings.
	var out: Dictionary = {}
	for id in ACTIONS:
		out[id] = ACTIONS[id]
	for id in _generated:
		out[id] = _generated[id]
	return out


func install_all() -> void:
	for action in all_actions():
		_install(action)


func _install(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for descriptor in events_for(action):
		# Untyped on purpose: _event_from() returns InputEventKey,
		# InputEventMouseButton or null, so there is no single type to infer.
		var ev = _event_from(descriptor)
		if ev != null:
			InputMap.action_add_event(action, ev)


# The descriptors currently in force for an action: the player's override if they
# have one, the table default otherwise.
func events_for(action: String) -> Array:
	if _overrides.has(action):
		return _overrides[action]
	var table := all_actions()
	if not table.has(action):
		return []
	return table[action].get("events", [])


func default_events_for(action: String) -> Array:
	var table := all_actions()
	if not table.has(action):
		return []
	return table[action].get("events", [])


func group_of(action: String) -> String:
	var table := all_actions()
	if not table.has(action):
		return ""
	return table[action].get("group", "")


func actions_in_group(group: String) -> Array:
	var out: Array = []
	var table := all_actions()
	for id in table:
		if table[id].get("group", "") == group:
			out.append(id)
	out.sort()
	return out


# --- Rebinding ---------------------------------------------------------------

func rebind(action: String, descriptors: Array) -> void:
	if not all_actions().has(action):
		push_error("InputService: cannot rebind unknown action '%s'" % action)
		return
	_overrides[action] = descriptors.duplicate(true)
	_install(action)
	_save()
	bindings_changed.emit(action)


func reset_action(action: String) -> void:
	_overrides.erase(action)
	_install(action)
	_save()
	bindings_changed.emit(action)


func reset_group(group: String) -> void:
	for action in actions_in_group(group):
		_overrides.erase(action)
		_install(action)
		bindings_changed.emit(action)
	_save()


func reset_all() -> void:
	_overrides.clear()
	install_all()
	_save()
	bindings_changed.emit("")


# Which other actions already use this descriptor.
#
# ADVISORY, NOT BLOCKING. Chris's direction is that users remap individually, so
# a conflict is reported to the Controls screen and drawn as a warning rather
# than refused. A player who deliberately wants two things on one key - or who is
# mid-way through swapping two bindings, which transiently conflicts by
# definition - should not be stopped.
func conflicts_for(descriptor: Dictionary, ignore_action: String = "") -> Array:
	var out: Array = []
	for action in all_actions():
		if action == ignore_action:
			continue
		for existing in events_for(action):
			if _descriptors_equal(existing, descriptor):
				out.append(action)
				break
	return out


# --- Labels ------------------------------------------------------------------

# The human-readable binding for an action, e.g. "Ctrl+Z" or "Q".
#
# THIS IS WHAT REPLACES THE HARDCODED CHEAT SHEET. Every on-screen hint must
# render through here, so a rebind is reflected everywhere immediately and no
# string in the game can claim a key that is no longer bound to that action.
func binding_label(action: String, index: int = 0) -> String:
	var descriptors := events_for(action)
	if descriptors.is_empty() or index >= descriptors.size():
		return "Unbound"
	return descriptor_label(descriptors[index])


# Every binding for an action, joined - "W or Up Arrow".
func binding_label_all(action: String, joiner: String = " or ") -> String:
	var descriptors := events_for(action)
	if descriptors.is_empty():
		return "Unbound"
	var parts: PackedStringArray = []
	for d in descriptors:
		parts.append(descriptor_label(d))
	return joiner.join(parts)


static func descriptor_label(descriptor: Dictionary) -> String:
	var parts: PackedStringArray = []
	if descriptor.get("ctrl", false):
		parts.append("Ctrl")
	if descriptor.get("shift", false):
		parts.append("Shift")
	if descriptor.get("alt", false):
		parts.append("Alt")
	if descriptor.has("mouse"):
		parts.append(_mouse_label(int(descriptor["mouse"])))
	elif descriptor.has("key"):
		parts.append(OS.get_keycode_string(int(descriptor["key"])))
	else:
		return "Unbound"
	return "+".join(parts)


static func _mouse_label(button: int) -> String:
	match button:
		MOUSE_BUTTON_LEFT: return "Left Mouse"
		MOUSE_BUTTON_RIGHT: return "Right Mouse"
		MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
		MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
		_: return "Mouse %d" % button


# Turns a real InputEvent - the one captured when a player presses a key on the
# Controls screen - back into a descriptor this service can store.
static func descriptor_from_event(event: InputEvent):
	if event is InputEventKey:
		var d := {"key": int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)}
		if event.ctrl_pressed:
			d["ctrl"] = true
		if event.shift_pressed:
			d["shift"] = true
		if event.alt_pressed:
			d["alt"] = true
		return d
	if event is InputEventMouseButton:
		return {"mouse": int(event.button_index)}
	return null


# --- Internals ---------------------------------------------------------------

func _build_control_group_actions() -> Dictionary:
	var out: Dictionary = {}
	for i in range(1, CONTROL_GROUP_COUNT + 1):
		out["cmd_group_%d" % i] = {
			"group": GROUP_COMMAND,
			"label": "Recall control group %d" % i,
			"events": [{"key": KEY_0 + i}],
		}
		out["cmd_group_assign_%d" % i] = {
			"group": GROUP_COMMAND,
			"label": "Assign control group %d" % i,
			"events": [{"key": KEY_0 + i, "ctrl": true}],
		}
	return out


static func _event_from(descriptor: Dictionary):
	if descriptor.has("mouse"):
		var mb := InputEventMouseButton.new()
		mb.button_index = int(descriptor["mouse"])
		return mb
	if not descriptor.has("key"):
		return null
	var ev := InputEventKey.new()
	# PHYSICAL keycode, not keycode. A binding stored as a unicode keycode moves
	# when the player changes keyboard layout: W on QWERTY is Z on AZERTY, so a
	# camera bound to the letter would pan on a different physical key. Physical
	# scancodes keep WASD in the same place on the board regardless of layout,
	# which is what every game with a WASD default relies on.
	ev.physical_keycode = int(descriptor["key"])
	ev.ctrl_pressed = descriptor.get("ctrl", false)
	ev.shift_pressed = descriptor.get("shift", false)
	ev.alt_pressed = descriptor.get("alt", false)
	return ev


static func _descriptors_equal(a: Dictionary, b: Dictionary) -> bool:
	# Modifiers compared EXACTLY, with a missing key treated as false. Permissive
	# comparison is what would make Ctrl+Shift+Z match Ctrl+Z, which is precisely
	# the undo/redo pair in this table - so redo would register as a conflict
	# against undo and, worse, whichever installed second would win.
	if a.get("key", -1) != b.get("key", -1):
		return false
	if a.get("mouse", -1) != b.get("mouse", -1):
		return false
	return a.get("ctrl", false) == b.get("ctrl", false) \
		and a.get("shift", false) == b.get("shift", false) \
		and a.get("alt", false) == b.get("alt", false)


func _save() -> void:
	var cfg := ConfigFile.new()
	for action in _overrides:
		cfg.set_value("bindings", action, _overrides[action])
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("InputService: could not write %s (error %d)" % [CONFIG_PATH, err])


func _load() -> void:
	_overrides.clear()
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	if not cfg.has_section("bindings"):
		return
	var known := all_actions()
	for action in cfg.get_section_keys("bindings"):
		# Drop overrides for actions that no longer exist rather than carrying
		# them forever. Without this, renaming an action leaves a dead entry that
		# reappears in the file on every save.
		if not known.has(action):
			continue
		var value = cfg.get_value("bindings", action, [])
		if value is Array:
			_overrides[action] = value
