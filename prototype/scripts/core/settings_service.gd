extends Node
# Autoload: every player preference, in one place, persisted.
#
# WHY THIS EXISTS. The game shipped with no settings screen and no preference
# store. There was no way to change master volume, window mode, resolution,
# quality, or anything else - not because the screen was unbuilt, but because
# there was nothing for a screen to edit. Two small stores existed and neither
# was general: user://ui_layout.cfg (ui_dock.gd's own collapsed/expanded state)
# and user://tutorial_seen.cfg (a single bool). Key bindings live next door in
# input_service.gd, which owns its own file for the same reason a theme owns its
# own resource - it is a different kind of data with a different editor.
#
# THE AUDIO SITUATION THIS FIXES. audio_manager.gd created 32 SFX players and one
# music player and assigned every one of them bus &"Master". There was exactly
# one bus, so "SFX volume" was not merely unexposed - it was unrepresentable.
# _ensure_buses() below creates the four the mixer needs and the manager routes
# to them.
#
# DESIGN RULES, both learned from how ui_tokens.gd earned its keep:
#
#   1. ONE DEFAULTS DICTIONARY. Every key, its default, and its type in a single
#      table. A setting that is not in DEFAULTS does not exist - get() pushes an
#      error rather than inventing a value, so a typo'd key surfaces immediately
#      instead of silently reading null forever.
#   2. CHANGES ARE ANNOUNCED, NOT POLLED. settings_changed(key, value) fires on
#      every write. Nothing should read a setting every frame; subscribe once and
#      react. This is what lets the Controls screen show live results.

signal settings_changed(key: String, value)

const CONFIG_PATH := "user://settings.cfg"

# Audio bus layout. Order matters: index 0 is always Master in Godot, and the
# three children route into it, so a master slider scales everything.
const BUS_MASTER := "Master"
const BUS_SFX := "SFX"
const BUS_MUSIC := "Music"
const BUS_VOICE := "Voice"
const CHILD_BUSES := [BUS_SFX, BUS_MUSIC, BUS_VOICE]

# Volume keys map to buses. Kept as a table so _apply_audio() cannot drift from
# the slider set the Settings screen builds.
const VOLUME_BUS := {
	"audio_master": BUS_MASTER,
	"audio_sfx": BUS_SFX,
	"audio_music": BUS_MUSIC,
	"audio_voice": BUS_VOICE,
}

# Below this, treat the slider as OFF and mute the bus outright. linear_to_db(0)
# is -inf, which Godot accepts but which reads back as garbage on the next load;
# a real mute flag round-trips cleanly.
const SILENCE_THRESHOLD := 0.001


# --- Defaults ----------------------------------------------------------------
#
# Sections are a display concern (which Settings tab a key appears on) and are
# carried here so the screen can be built from the table rather than from a
# hand-written list that can fall out of step with it.
const DEFAULTS := {
	# Display
	"window_mode": {"value": 0, "section": "display"},          # 0 windowed, 1 borderless, 2 fullscreen
	"resolution_index": {"value": -1, "section": "display"},    # -1 = native
	"vsync": {"value": true, "section": "display"},
	"frame_cap": {"value": 0, "section": "display"},            # 0 = uncapped
	"render_scale": {"value": 1.0, "section": "display"},
	"quality_preset": {"value": 1, "section": "display"},       # 0 low, 1 medium, 2 high
	# CORE_DESIGN_LANGUAGE.md 7.1/7.2: the macro tilt-shift is the game's stated
	# optical signature and rts_camera.gd now implements the band. Exposed as a
	# strength multiplier rather than an on/off, because 7.2 asks for the effect
	# to DEGRADE gracefully rather than snap between present and absent.
	"tilt_shift_strength": {"value": 1.0, "section": "display"},

	# Audio - linear 0..1, converted to dB at the bus.
	"audio_master": {"value": 0.8, "section": "audio"},
	"audio_sfx": {"value": 0.9, "section": "audio"},
	"audio_music": {"value": 0.6, "section": "audio"},
	"audio_voice": {"value": 1.0, "section": "audio"},

	# Camera - these are settings rather than bindings, so they live here and not
	# in input_service.gd. Edge scroll in particular is a preference a lot of
	# players turn off immediately because it fires when reaching for the HUD.
	"edge_scroll_enabled": {"value": true, "section": "controls"},
	"edge_scroll_margin": {"value": 18.0, "section": "controls"},
	"camera_pan_speed": {"value": 30.0, "section": "controls"},
	"camera_rotate_speed": {"value": 90.0, "section": "controls"},
	"invert_zoom": {"value": false, "section": "controls"},

	# Game
	"tutorial_hints": {"value": true, "section": "game"},
	"reduced_motion": {"value": false, "section": "game"},
	"ui_scale": {"value": 1.0, "section": "game"},
	"colourblind_mode": {"value": 0, "section": "game"},        # 0 off, 1 deuter, 2 protan, 3 tritan
	"damage_numbers": {"value": 1, "section": "game"},          # 0 off, 1 significant, 2 all
	"captions": {"value": false, "section": "game"},
}

const SECTION_ORDER := ["display", "audio", "controls", "game"]
const SECTION_LABELS := {
	"display": "Display",
	"audio": "Audio",
	"controls": "Controls",
	"game": "Game",
}


var _values: Dictionary = {}


func _ready() -> void:
	_reset_to_defaults()
	_load()
	_ensure_buses()
	apply_all()


# --- Access ------------------------------------------------------------------

func get_value(key: String):
	if not DEFAULTS.has(key):
		push_error("SettingsService: unknown setting '%s'" % key)
		return null
	return _values.get(key, DEFAULTS[key]["value"])


func set_value(key: String, value) -> void:
	if not DEFAULTS.has(key):
		push_error("SettingsService: unknown setting '%s'" % key)
		return
	if _values.get(key) == value:
		return
	_values[key] = value
	_apply(key)
	_save()
	settings_changed.emit(key, value)


func default_of(key: String):
	if not DEFAULTS.has(key):
		return null
	return DEFAULTS[key]["value"]


func keys_in_section(section: String) -> Array:
	var out: Array = []
	for key in DEFAULTS:
		if DEFAULTS[key].get("section", "") == section:
			out.append(key)
	out.sort()
	return out


func reset_section(section: String) -> void:
	for key in keys_in_section(section):
		_values[key] = DEFAULTS[key]["value"]
		_apply(key)
		settings_changed.emit(key, _values[key])
	_save()


# --- Application -------------------------------------------------------------

func apply_all() -> void:
	for key in DEFAULTS:
		_apply(key)


func _apply(key: String) -> void:
	if VOLUME_BUS.has(key):
		_apply_volume(key)
		return
	match key:
		"window_mode": _apply_window_mode()
		"vsync": _apply_vsync()
		"frame_cap": Engine.max_fps = int(get_value("frame_cap"))
		_:
			# Everything else is read by whoever cares, when they care, via the
			# settings_changed signal. Deliberately not a silent default branch
			# that does nothing invisibly - see the comment on DEFAULTS.
			pass


func _ensure_buses() -> void:
	# Headless has an audio driver stub but creating buses on it is pointless and
	# the test suite runs headless constantly.
	if DisplayServer.get_name() == "headless":
		return
	for bus_name in CHILD_BUSES:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, BUS_MASTER)


func _apply_volume(key: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var bus_name: String = VOLUME_BUS[key]
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var linear := float(get_value(key))
	if linear <= SILENCE_THRESHOLD:
		AudioServer.set_bus_mute(idx, true)
		return
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match int(get_value("window_mode")):
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(get_value("vsync")) else DisplayServer.VSYNC_DISABLED)


# --- Persistence -------------------------------------------------------------

func _reset_to_defaults() -> void:
	_values.clear()
	for key in DEFAULTS:
		_values[key] = DEFAULTS[key]["value"]


func _save() -> void:
	var cfg := ConfigFile.new()
	for key in _values:
		# Only write what differs from the default. A settings file that records
		# every key makes changing a default a no-op for every existing player,
		# which is the classic way a tuned default never reaches anyone.
		if _values[key] != DEFAULTS[key]["value"]:
			cfg.set_value("settings", key, _values[key])
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("SettingsService: could not write %s (error %d)" % [CONFIG_PATH, err])


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	if not cfg.has_section("settings"):
		return
	for key in cfg.get_section_keys("settings"):
		if not DEFAULTS.has(key):
			continue
		var loaded = cfg.get_value("settings", key, DEFAULTS[key]["value"])
		# Type-guard against a hand-edited or version-skewed file. A float where
		# an int is expected is survivable; a Dictionary where a float is expected
		# crashes whatever reads it, far from here.
		if typeof(loaded) == typeof(DEFAULTS[key]["value"]):
			_values[key] = loaded
		elif typeof(loaded) in [TYPE_INT, TYPE_FLOAT] \
				and typeof(DEFAULTS[key]["value"]) in [TYPE_INT, TYPE_FLOAT]:
			_values[key] = loaded
