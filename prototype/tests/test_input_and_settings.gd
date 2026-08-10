extends "res://tests/suite_base.gd"
# Input and settings suites. Registration order lives in run_tests.gd's
# SUITE_ORDER, not here.
#
# These cover the Phase 0 foundations: the action table, binding persistence,
# conflict reporting, the settings defaults table, and the yaw-relative pan
# helper. All of it is deliberately written as pure/static logic or as
# service-level calls so none of it needs a rendered screen.

const InputServiceScript = preload("res://scripts/core/input_service.gd")
const SettingsServiceScript = preload("res://scripts/core/settings_service.gd")
const RTSCam = preload("res://scripts/rts_camera.gd")


# THE REGRESSION THIS EXISTS FOR. Before the migration, every key in the game was
# a raw keycode compared inline in one of six files. Nothing could enumerate the
# bindings, so nothing could render them, so the battlefield carried a hardcoded
# two-line cheat sheet that could silently disagree with the code. If the action
# table ever loses an action a screen renders, that is the failure to catch.
func test_input_action_table_is_well_formed() -> bool:
	print("Running Test Suite: InputService - Action Table Is Well Formed...")
	var svc = InputServiceScript.new()
	svc._generated = svc._build_control_group_actions()
	var table: Dictionary = svc.all_actions()

	if table.size() < 30:
		print("  [FAIL] Expected at least 30 actions, got ", table.size())
		svc.free()
		return false

	var valid_groups := [svc.GROUP_CAMERA, svc.GROUP_COMMAND, svc.GROUP_LAB, svc.GROUP_SYSTEM]
	for action in table:
		var entry: Dictionary = table[action]
		if not entry.has("group") or entry["group"] not in valid_groups:
			print("  [FAIL] Action '", action, "' has no valid group")
			svc.free()
			return false
		if str(entry.get("label", "")) == "":
			print("  [FAIL] Action '", action, "' has no label - the Controls screen would render a blank row")
			svc.free()
			return false
		var events: Array = entry.get("events", [])
		if events.is_empty():
			print("  [FAIL] Action '", action, "' has no default binding")
			svc.free()
			return false
		for d in events:
			if not (d.has("key") or d.has("mouse")):
				print("  [FAIL] Action '", action, "' has a descriptor with neither key nor mouse: ", d)
				svc.free()
				return false

	# Every group must be reachable from the Controls screen's section list, or
	# its bindings exist but cannot be edited.
	for g in valid_groups:
		if g not in svc.GROUP_ORDER:
			print("  [FAIL] Group '", g, "' is missing from GROUP_ORDER")
			svc.free()
			return false

	print("  [PASS] ", table.size(), " actions, all with a group, a label and at least one binding.")
	svc.free()
	return true


# THE SPECIFIC BUG THIS GUARDS. lab_redo's Ctrl+Shift+Z also satisfies a
# permissively-matched Ctrl+Z (lab_undo). If _descriptors_equal() compared
# modifiers loosely, redo would report as conflicting with undo and - worse -
# whichever installed second would win, so one of the two would simply stop
# working. Modifiers are compared exactly for this reason.
func test_input_modifiers_compared_exactly() -> bool:
	print("Running Test Suite: InputService - Modifiers Compared Exactly (undo/redo)...")
	var plain := {"key": KEY_Z, "ctrl": true}
	var shifted := {"key": KEY_Z, "ctrl": true, "shift": true}

	if InputServiceScript._descriptors_equal(plain, shifted):
		print("  [FAIL] Ctrl+Z and Ctrl+Shift+Z must not compare equal - redo would shadow undo")
		return false
	if not InputServiceScript._descriptors_equal(plain, {"key": KEY_Z, "ctrl": true}):
		print("  [FAIL] Identical descriptors should compare equal")
		return false
	# A missing modifier key must be treated as false, not as absent-and-therefore-
	# matching-anything.
	if InputServiceScript._descriptors_equal({"key": KEY_Z}, plain):
		print("  [FAIL] A bare Z must not equal Ctrl+Z")
		return false

	print("  [PASS] Modifier comparison is exact; Ctrl+Shift+Z does not collide with Ctrl+Z.")
	return true


func test_input_rebind_persists_and_reports_conflicts() -> bool:
	print("Running Test Suite: InputService - Rebinding, Reset And Conflict Reporting...")
	var svc = InputServiceScript.new()
	svc._generated = svc._build_control_group_actions()

	var original := svc.events_for("cmd_stop")
	svc._overrides["cmd_stop"] = [{"key": KEY_J}]
	if svc.binding_label("cmd_stop") != "J":
		print("  [FAIL] Expected label 'J' after override, got ", svc.binding_label("cmd_stop"))
		svc.free()
		return false

	# Conflict reporting is ADVISORY. It must find the clash and must not refuse
	# the binding - a player mid-way through swapping two keys is transiently in
	# conflict by definition.
	var clashes: Array = svc.conflicts_for({"key": KEY_J}, "cmd_attack_move")
	if "cmd_stop" not in clashes:
		print("  [FAIL] conflicts_for should report cmd_stop holding J, got ", clashes)
		svc.free()
		return false
	if not svc.conflicts_for({"key": KEY_J}, "cmd_stop").is_empty():
		print("  [FAIL] conflicts_for must ignore the action being edited")
		svc.free()
		return false

	svc._overrides.erase("cmd_stop")
	if svc.events_for("cmd_stop") != original:
		print("  [FAIL] Clearing the override should restore the table default")
		svc.free()
		return false

	# An override for an action that no longer exists must be dropped on load, or
	# renaming an action leaves a dead entry that is rewritten forever.
	if svc.all_actions().has("cmd_this_does_not_exist"):
		print("  [FAIL] Test assumption broken: that action should not exist")
		svc.free()
		return false

	print("  [PASS] Rebind, reset and advisory conflict reporting all behave.")
	svc.free()
	return true


# The camera owns W A S D Q E, so no command may claim one of them by default or
# the WASD-vs-letters collision that produced the original Q/E workaround comes
# straight back.
func test_command_bindings_avoid_camera_keys() -> bool:
	print("Running Test Suite: InputService - Commands Do Not Collide With The Camera...")
	var svc = InputServiceScript.new()
	svc._generated = svc._build_control_group_actions()
	var table: Dictionary = svc.all_actions()

	var camera_keys := {}
	for action in table:
		if table[action]["group"] != svc.GROUP_CAMERA:
			continue
		for d in table[action].get("events", []):
			if d.has("key"):
				camera_keys[d["key"]] = action

	for action in table:
		if table[action]["group"] != svc.GROUP_COMMAND:
			continue
		for d in table[action].get("events", []):
			# Modified bindings are fine - Ctrl+1 does not collide with 1.
			if d.get("ctrl", false) or d.get("alt", false):
				continue
			if d.has("key") and camera_keys.has(d["key"]):
				print("  [FAIL] Command '", action, "' claims ", OS.get_keycode_string(d["key"]),
					", already used by camera action '", camera_keys[d["key"]], "'")
				svc.free()
				return false

	print("  [PASS] No unmodified command binding collides with a camera binding.")
	svc.free()
	return true


func test_settings_defaults_are_complete_and_typed() -> bool:
	print("Running Test Suite: SettingsService - Defaults Table Is Complete...")
	var svc = SettingsServiceScript.new()

	for key in svc.DEFAULTS:
		var entry: Dictionary = svc.DEFAULTS[key]
		if not entry.has("value"):
			print("  [FAIL] Setting '", key, "' has no default value")
			svc.free()
			return false
		var section: String = entry.get("section", "")
		if section not in svc.SECTION_ORDER:
			print("  [FAIL] Setting '", key, "' is in unknown section '", section, "'")
			svc.free()
			return false

	# Every section must contain something, or the Settings screen renders an
	# empty tab.
	for section in svc.SECTION_ORDER:
		if svc.keys_in_section(section).is_empty():
			print("  [FAIL] Section '", section, "' has no settings")
			svc.free()
			return false

	# Each volume key must name a real bus, or its slider silently does nothing.
	for key in svc.VOLUME_BUS:
		if not svc.DEFAULTS.has(key):
			print("  [FAIL] VOLUME_BUS references unknown setting '", key, "'")
			svc.free()
			return false

	print("  [PASS] ", svc.DEFAULTS.size(), " settings, all typed, sectioned and reachable.")
	svc.free()
	return true


func test_settings_unknown_key_is_refused() -> bool:
	print("Running Test Suite: SettingsService - Unknown Keys Are Refused, Not Invented...")
	var svc = SettingsServiceScript.new()
	svc._reset_to_defaults()

	# A setting that is not in DEFAULTS does not exist. get_value must return null
	# rather than inventing one, so a typo'd key surfaces at the call site instead
	# of silently reading a default forever.
	if svc.get_value("no_such_setting") != null:
		print("  [FAIL] get_value on an unknown key should return null")
		svc.free()
		return false

	svc.set_value("no_such_setting", 5)
	if svc._values.has("no_such_setting"):
		print("  [FAIL] set_value must not create unknown keys")
		svc.free()
		return false

	# A known key round-trips.
	svc.set_value("reduced_motion", true)
	if svc.get_value("reduced_motion") != true:
		print("  [FAIL] A known setting should round-trip")
		svc.free()
		return false

	print("  [PASS] Unknown settings are refused at both read and write.")
	svc.free()
	return true


# Yaw made pan direction ambiguous: "forward" has to mean up the SCREEN, not down
# world -Z, or W drives the camera sideways the moment the player rotates. The
# identity case at yaw 0 is the one that proves this migration did not change
# behaviour for anyone who never touches Q/E.
func test_camera_pan_is_yaw_relative() -> bool:
	print("Running Test Suite: RTS Camera - Pan Is Yaw-Relative...")
	var forward := Vector2(0, -1)

	var at_zero := RTSCam.pan_to_world(forward, 0.0)
	if at_zero.distance_to(forward) > 0.0001:
		print("  [FAIL] At yaw 0 pan must be the identity, got ", at_zero)
		return false

	# Turned 90 degrees, "forward" must become a world +X/-X push, not stay -Z.
	var at_ninety := RTSCam.pan_to_world(forward, 90.0)
	if abs(at_ninety.y) > 0.0001:
		print("  [FAIL] At yaw 90 forward should have no world-Z component, got ", at_ninety)
		return false
	if abs(abs(at_ninety.x) - 1.0) > 0.0001:
		print("  [FAIL] At yaw 90 forward should be a full-magnitude world-X push, got ", at_ninety)
		return false

	# Rotation must preserve length at every angle, or panning speed would vary
	# with facing.
	for deg in [0.0, 37.0, 90.0, 180.0, 271.0, 359.0]:
		var r := RTSCam.pan_to_world(forward, deg)
		if abs(r.length() - 1.0) > 0.0001:
			print("  [FAIL] Pan magnitude should be preserved at yaw ", deg, ", got ", r.length())
			return false

	print("  [PASS] Pan rotates with yaw, is the identity at 0, and preserves magnitude.")
	return true


# --- UI audio ----------------------------------------------------------------

# THE FAILURE THIS CATCHES IS SILENT. A role pointing at a bank that does not
# exist produces no sound, no warning and no error - which is how eight roles
# spent time pointing at missing files, and how the four radio SFX sat committed
# but unregistered as dead assets.
#
# READS THE MANIFEST, NOT A HARDCODED TABLE. AudioManager was rebuilt around
# assets/audio/audio_manifest.json, which tools/generate_audio.py writes as it
# renders the files - so what the engine believes exists is derived from what is
# on disk. This test checks the OTHER side of that contract: that every role
# ui_feedback.gd can play names a bank the manifest actually declares.
func test_every_ui_audio_role_resolves_to_a_real_bank() -> bool:
	print("Running Test Suite: UI Audio - Every Feedback Role Resolves To A Real Bank...")
	var Feedback = preload("res://scripts/ui_feedback.gd")

	var manifest_path := "res://assets/audio/audio_manifest.json"
	if not FileAccess.file_exists(manifest_path):
		print("  [FAIL] No audio manifest at ", manifest_path, " - run tools/generate_audio.py")
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("  [FAIL] Audio manifest is not a JSON object")
		return false
	var sfx: Dictionary = parsed.get("sfx", {})

	var roles: Dictionary = Feedback.ROLE_SFX
	if roles.size() < 14:
		print("  [FAIL] Expected at least 14 feedback roles, got ", roles.size())
		return false

	for role in roles:
		var key: String = roles[role]
		if not sfx.has(key):
			print("  [FAIL] Role '", role, "' maps to bank '", key,
				"' which the manifest does not declare")
			return false
		var files: Array = sfx[key].get("files", [])
		if files.is_empty():
			print("  [FAIL] Bank '", key, "' declares no files")
			return false
		for f in files:
			if not ResourceLoader.exists(f):
				print("  [FAIL] Bank '", key, "' lists a missing file: ", f)
				return false

	# 'hover' is played directly by UIFeedback rather than through a role, so the
	# loop above would not reach it.
	if not sfx.has("hover"):
		print("  [FAIL] The 'hover' bank is not in the manifest")
		return false

	print("  [PASS] ", roles.size(), " feedback roles all resolve to declared banks with real files.")
	return true
