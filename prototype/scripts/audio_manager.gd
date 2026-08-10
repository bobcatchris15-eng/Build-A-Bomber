extends Node

## Central audio manager: UI sounds, 3D world SFX, comms, ambience and music.
##
## WHAT THIS REPLACES, AND WHY IT IS A REWRITE RATHER THAN AN EXTENSION.
## The previous version loaded ~30 single-variant WAVs from a hardcoded
## dictionary and offered play_sfx / play_sfx_3d / play_music. Three things were
## structurally wrong with it rather than merely missing:
##
##   1. play_music() HAD NO CALLERS ANYWHERE IN THE PROJECT. The game shipped
##      with a music track that could never be heard. Music was not a feature
##      that was tuned badly; it had never been switched on.
##   2. The SFX_PATHS dictionary and ui_feedback.gd's ROLE_SFX table were
##      maintained by hand in separate files, and they had already drifted -
##      eight roles spent time pointing at files that did not exist, playing
##      nothing, with no way for anything in the codebase to notice.
##   3. play_sfx_3d allocated an AudioStreamPlayer3D per shot and queue_free()d
##      it on finish - once per bullet, for every unit on the field.
##
## THE MANIFEST IS THE FIX FOR (2). Banks load from
## assets/audio/audio_manifest.json, which tools/generate_audio.py writes as it
## renders the files. The engine's idea of what sounds exist is therefore
## DERIVED from what is on disk and cannot drift from it. Adding a sound is a
## Python edit plus a re-run; this file does not change.
##
## THE SINCERE/ABSURD SPLIT (CORE_DESIGN_LANGUAGE.md 6) IS A BUS DECISION HERE.
## Ordnance vocalisations are absurd, but they are WEAPONS, so they play on the
## SFX bus - pulling the Voice slider to zero must never silence combat. The
## Voice bus carries the sincere comms layer only. The manifest carries the bus
## per key, so that rule lives in exactly one place.

const MANIFEST_PATH := "res://assets/audio/audio_manifest.json"

# --- Pools -------------------------------------------------------------------
# Both pools steal their oldest voice rather than growing, so a pathological
# frame degrades by dropping the least recent sound instead of by allocating.
const MAX_SFX_PLAYERS: int = 32
const MAX_3D_PLAYERS: int = 48

# Per-key concurrency cap. Twelve cannons firing in one frame is twelve copies
# of the same waveform summing to roughly +21 dB, which clips the master bus and
# reads as a single loud crackle rather than as twelve guns.
const MAX_PER_KEY: int = 4

const MUSIC_FADE := 1.6          # seconds, crossfade between music states
const STEM_FADE := 2.2           # seconds, combat-intensity layer ramp
const AMBIENCE_FADE := 2.5
const AMBIENCE_DB := -14.0

# Music ducks by this much while comms or a stinger plays. The sincere radio
# layer has to win against the track, or it is decoration.
const DUCK_DB := -7.0
const DUCK_ATTACK := 0.12
const DUCK_RELEASE := 0.9

const MUSIC_STEMS := ["bed", "rhythm", "lead"]

var _banks: Dictionary = {}            # key -> {bus: String, streams: Array}
var _music_manifest: Dictionary = {}   # state -> {loop: bool, stems: {name: AudioStream}}

var _sfx_players: Array = []
var _sfx_index: int = 0
var _pool_3d: Array = []
var _pool_3d_index: int = 0
var _active_per_key: Dictionary = {}
var _last_variant: Dictionary = {}

var _music_players: Dictionary = {}
var _music_state: String = ""
var _music_target_db: Dictionary = {}
var _combat_intensity: float = 0.0
var _duck: float = 0.0

var _ambience_players: Array = []
var _ambience_key: String = ""
var _ambience_active: int = 0

var _loops: Dictionary = {}            # instance id -> AudioStreamPlayer3D

var _headless: bool = false
var _loaded: bool = false


func _ready() -> void:
	_ensure_loaded()


# INITIALISATION IS LAZY RATHER THAN _ready()-ORDERED, and that is a fix, not a
# style choice. Doing this work in _ready() made every caller depend on the
# autoload's _ready() having already fired, and that is not guaranteed: a
# SceneTree script (run_tests.gd) can instantiate a scene before autoloads are
# readied, and the observed result was stat_calculator.gd's _ready() calling
# play_music("lab") against an empty manifest with _headless still at its
# default false - one spurious warning, and the first music request of the
# process silently dropped. Any entry point can be the first one now.
func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_headless = DisplayServer.get_name() == "headless"
	# THE MANIFEST LOADS EVEN HEADLESS. test_audio_system asserts against bank
	# contents and runs headless; only the player nodes are skipped.
	_load_manifest()
	if _headless:
		return
	_setup_players()


# --- Loading -----------------------------------------------------------------

func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("AudioManager: no manifest at %s - run tools/generate_audio.py"
			% MANIFEST_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AudioManager: manifest is not a JSON object")
		return

	for key in parsed.get("sfx", {}):
		var entry: Dictionary = parsed["sfx"][key]
		var streams: Array = []
		for path in entry.get("files", []):
			if ResourceLoader.exists(path):
				streams.append(load(path))
		if streams.is_empty():
			push_warning("AudioManager: bank '%s' resolved to no files" % key)
			continue
		_banks[key] = {"bus": String(entry.get("bus", "SFX")), "streams": streams}

	for state in parsed.get("music", {}):
		var entry: Dictionary = parsed["music"][state]
		var loops: bool = bool(entry.get("loop", false))
		var stems: Dictionary = {}
		for stem_name in entry.get("stems", {}):
			# A stem is EITHER a single path (one track, loops as a stream) OR a
			# JSON array of paths (a rotation pool - curated_music.py's skirmish
			# entry). Normalising to an array unconditionally means every other
			# function in this file only has one shape to handle: "streams.size()
			# == 1" is the single-track case, "> 1" is a rotation, and both read
			# the same way.
			var raw = entry["stems"][stem_name]
			var paths: Array = raw if raw is Array else [raw]
			var streams: Array = []
			for path in paths:
				if not ResourceLoader.exists(path):
					continue
				var stream = load(path)
				# Looping is set HERE rather than in the .import, because Godot
				# regenerates those sidecars on every reimport and would discard
				# it. Three stream types are handled because the shipped
				# soundtrack is now MP3 (curated_music.py) rather than the Ogg
				# the procedural renderer produces.
				#
				# A ROTATION MEMBER NEVER LOOPS ON THE STREAM ITSELF, regardless
				# of the state's `loop` flag - repetition for a rotation is
				# handled by advancing to the NEXT track when one finishes
				# (_on_music_stem_finished), not by the same track repeating.
				var should_loop: bool = loops and paths.size() == 1
				if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
					stream.loop = should_loop
				elif stream is AudioStreamWAV:
					stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if should_loop \
						else AudioStreamWAV.LOOP_DISABLED
				streams.append(stream)
			if not streams.is_empty():
				stems[stem_name] = streams
		if not stems.is_empty():
			_music_manifest[state] = {"loop": loops, "stems": stems}


# Falls back to Master when a bus is missing. SettingsService creates SFX/Music/
# Voice at boot, but this manager must still work if it is instantiated on its
# own in a probe, and an AudioStreamPlayer pointed at a nonexistent bus is a
# runtime error on every play() rather than a quiet fallback.
func _bus_or_master(bus_name: StringName) -> StringName:
	return bus_name if AudioServer.get_bus_index(bus_name) != -1 else &"Master"


func _setup_players() -> void:
	var sfx_bus := _bus_or_master(&"SFX")
	for i in range(MAX_SFX_PLAYERS):
		var player := AudioStreamPlayer.new()
		player.bus = sfx_bus
		add_child(player)
		player.finished.connect(_on_sfx_finished.bind(player))
		_sfx_players.append(player)

	# POOLED, NOT ALLOCATED PER SHOT - see (3) in the class comment.
	for i in range(MAX_3D_PLAYERS):
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = sfx_bus
		p3.unit_size = 12.0
		add_child(p3)
		p3.finished.connect(_on_sfx3d_finished.bind(p3))
		_pool_3d.append(p3)

	var music_bus := _bus_or_master(&"Music")
	for stem_name in MUSIC_STEMS:
		var mp := AudioStreamPlayer.new()
		mp.bus = music_bus
		mp.volume_db = -80.0
		add_child(mp)
		# Connected once, unconditionally, rather than per play_music() call -
		# `finished` only actually fires for a non-looping stream, which is
		# exactly the rotation case (see _load_manifest's should_loop note), so
		# a single-track state's player simply never triggers this.
		mp.finished.connect(_on_music_stem_finished.bind(stem_name))
		_music_players[stem_name] = mp
		_music_target_db[stem_name] = -80.0

	for i in range(2):
		var amb := AudioStreamPlayer.new()
		amb.bus = sfx_bus
		amb.volume_db = -80.0
		add_child(amb)
		_ambience_players.append(amb)


# --- Introspection (used by the tests) ---------------------------------------

func has_sound(key: String) -> bool:
	_ensure_loaded()
	return _banks.has(key)


func bank_size(key: String) -> int:
	_ensure_loaded()
	return (_banks[key]["streams"] as Array).size() if _banks.has(key) else 0


func bank_bus(key: String) -> String:
	_ensure_loaded()
	return String(_banks[key]["bus"]) if _banks.has(key) else ""


func sound_keys() -> Array:
	_ensure_loaded()
	return _banks.keys()


func music_states() -> Array:
	_ensure_loaded()
	return _music_manifest.keys()


func music_stems(state: String) -> Array:
	if not _music_manifest.has(state):
		return []
	return (_music_manifest[state]["stems"] as Dictionary).keys()


## Length of a stem's first track. For a rotation stem (skirmish's "bed") this
## is only the first pool member, not the whole rotation - there is no single
## "length" for a pool that shuffles indefinitely.
func music_stem_length(state: String, stem: String) -> float:
	var streams := _music_streams_for(state, stem)
	return (streams[0] as AudioStream).get_length() if not streams.is_empty() else -1.0


func music_stem_track_count(state: String, stem: String) -> int:
	return _music_streams_for(state, stem).size()


func _music_streams_for(state: String, stem: String) -> Array:
	if not _music_manifest.has(state):
		return []
	var stems: Dictionary = _music_manifest[state]["stems"]
	return stems[stem] as Array if stems.has(stem) else []


func active_3d_count() -> int:
	var n := 0
	for p in _pool_3d:
		if p.playing:
			n += 1
	return n


# --- Variant selection -------------------------------------------------------

func pick_index(key: String) -> int:
	"""Choose the next SFX variant. NEVER the same index twice in a row.

	UI_STYLE_GUIDE.md:359 requires this of pitch; once there are real variant
	banks it has to apply to the choice of FILE too, because hearing the same
	waveform back to back is far more noticeable than hearing it at a slightly
	different pitch.
	"""
	return _no_repeat_index(key, bank_size(key))


## The general form pick_index specialises. Shared with the skirmish music
## rotation (_advance_rotation) so "never repeat the last one" is one
## implementation instead of two - a shuffled soundtrack and a shuffled SFX
## bank are the same problem at different timescales.
func _no_repeat_index(key: String, count: int) -> int:
	if count <= 1:
		return 0
	var last: int = int(_last_variant.get(key, -1))
	var idx: int = randi() % count
	if idx == last:
		idx = (idx + 1) % count
	_last_variant[key] = idx
	return idx


func _pick(key: String) -> AudioStream:
	return (_banks[key]["streams"] as Array)[pick_index(key)]


func _claim(key: String) -> bool:
	var active: int = int(_active_per_key.get(key, 0))
	if active >= MAX_PER_KEY:
		return false
	_active_per_key[key] = active + 1
	return true


func _release(key: String) -> void:
	_active_per_key[key] = maxi(0, int(_active_per_key.get(key, 1)) - 1)


# --- 2D playback -------------------------------------------------------------

func play_sfx(key: String, pitch_variance: float = 0.12) -> void:
	_ensure_loaded()
	if _headless or not _banks.has(key) or _sfx_players.is_empty():
		return
	if not _claim(key):
		return

	var player: AudioStreamPlayer = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % MAX_SFX_PLAYERS
	if player.playing and player.has_meta("sfx_key"):
		_release(String(player.get_meta("sfx_key")))

	player.bus = _bus_or_master(StringName(_banks[key]["bus"]))
	player.stream = _pick(key)
	player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance) \
		if pitch_variance > 0.0 else 1.0
	player.set_meta("sfx_key", key)
	player.play()

	if String(_banks[key]["bus"]) == "Voice":
		_duck = 1.0


func _on_sfx_finished(player: AudioStreamPlayer) -> void:
	if player.has_meta("sfx_key"):
		_release(String(player.get_meta("sfx_key")))
		player.remove_meta("sfx_key")


## The sincere comms layer. Routes to the Voice bus (via the manifest) and ducks
## the music under itself.
func play_voice(key: String) -> void:
	if not _banks.has(key):
		return
	# Barely any pitch variance: a professional radio read that wobbles in pitch
	# stops sounding professional, which is the one thing this layer must be.
	play_sfx(key, 0.03)


# --- 3D playback -------------------------------------------------------------

func play_sfx_3d(key: String, pos: Vector3, parent_node: Node = null,
		max_dist: float = 60.0, pitch_variance: float = 0.15) -> void:
	_ensure_loaded()
	if _headless or not _banks.has(key) or _pool_3d.is_empty():
		return
	if not _claim(key):
		return

	var player: AudioStreamPlayer3D = _pool_3d[_pool_3d_index]
	_pool_3d_index = (_pool_3d_index + 1) % MAX_3D_PLAYERS
	if player.playing and player.has_meta("sfx_key"):
		# Stealing a still-sounding voice: hand its slot back first.
		_release(String(player.get_meta("sfx_key")))

	player.stream = _pick(key)
	player.bus = _bus_or_master(StringName(_banks[key]["bus"]))
	player.max_distance = max_dist
	player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance) \
		if pitch_variance > 0.0 else 1.0
	player.set_meta("sfx_key", key)

	# POSITION IS SAFE TO SET DIRECTLY NOW, and the old hazard is gone rather
	# than worked around. The previous code created a fresh node, reparented it
	# under the caller, and had to be careful to assign global_position only
	# AFTER add_child - a Node3D outside the tree has no global transform, so
	# getting that order wrong both spammed "Condition !is_inside_tree() is
	# true" once per call and silently played every weapon report at its
	# parent's origin instead of at the muzzle (~9,000 errors per 240-frame
	# sample with 8 rapid-fire units engaged). Pooled players are permanent
	# children of this autoload, so they are always inside the tree.
	player.global_position = pos
	player.play()
	# parent_node is accepted for source compatibility with the old signature
	# and is deliberately unused: reparenting was the bug, not the feature.


func _on_sfx3d_finished(player: AudioStreamPlayer3D) -> void:
	if player.has_meta("sfx_key"):
		_release(String(player.get_meta("sfx_key")))
		player.remove_meta("sfx_key")


# --- Looping emitters (engines, treads, rotors) ------------------------------

## Attach a seamless loop to a node. Idempotent per (node, key), so it is safe
## to call every physics frame from a unit's movement code.
func attach_loop(node: Node3D, key: String, volume_db: float = -18.0,
		max_dist: float = 45.0) -> void:
	_ensure_loaded()
	if _headless or node == null or not is_instance_valid(node) or not _banks.has(key):
		return
	var id := node.get_instance_id()
	if _loops.has(id):
		var existing = _loops[id]
		if is_instance_valid(existing) and String(existing.get_meta("loop_key", "")) == key:
			return
		detach_loop(node)

	var player := AudioStreamPlayer3D.new()
	var stream = _pick(key)
	# The Python side renders these with a crossfaded seam so they loop without
	# a click; the flag still has to be set for Godot to honour it.
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	player.stream = stream
	player.bus = _bus_or_master(&"SFX")
	player.max_distance = max_dist
	player.unit_size = 10.0
	player.volume_db = volume_db
	player.set_meta("loop_key", key)
	node.add_child(player)
	player.play()
	_loops[id] = player


func detach_loop(node: Node3D) -> void:
	if node == null:
		return
	var id := node.get_instance_id()
	if not _loops.has(id):
		return
	var player = _loops[id]
	if is_instance_valid(player):
		player.queue_free()
	_loops.erase(id)


## Drive a running loop from the unit's speed. `normalised` is 0..1.
func set_loop_intensity(node: Node3D, normalised: float, base_db: float = -22.0) -> void:
	if node == null or not _loops.has(node.get_instance_id()):
		return
	var player = _loops[node.get_instance_id()]
	if not is_instance_valid(player):
		return
	var t := clampf(normalised, 0.0, 1.0)
	# An idling engine is both quieter AND lower-pitched than one under load.
	# Both cues together are what make the loop track the unit rather than sit
	# on top of it.
	player.volume_db = base_db + 10.0 * t
	player.pitch_scale = 0.82 + 0.36 * t


# --- Music -------------------------------------------------------------------

## Switch music state. Crossfades; never hard-cuts. Re-requesting the current
## state is a no-op, so screens may call this unconditionally from _ready().
func play_music(state: String) -> void:
	_ensure_loaded()
	if _headless or state == _music_state:
		return
	if not _music_manifest.has(state):
		push_warning("AudioManager: no music state '%s'" % state)
		return

	_music_state = state
	var stems: Dictionary = _music_manifest[state]["stems"]
	for stem_name in _music_players:
		var player: AudioStreamPlayer = _music_players[stem_name]
		var streams: Array = stems.get(stem_name, [])
		if not streams.is_empty():
			# A single-track stem always picks index 0 (there is nothing to
			# choose between); a rotation stem (skirmish's "bed") picks with the
			# same no-immediate-repeat rule the SFX banks use.
			player.stream = streams[_no_repeat_index("music:%s:%s" % [state, stem_name],
				streams.size())]
			# ALL STEMS START IN THE SAME FRAME when the state has more than
			# one - the procedural renderer guarantees identical sample lengths
			# across a real bed/rhythm/lead split precisely so this works;
			# starting them apart would phase them against each other. A
			# rotation stem has no such partner to stay in phase with.
			player.play()
		else:
			player.stop()
			player.stream = null
	_refresh_music_targets()


## A rotation member (skirmish's "bed") finished playing on its own - advance
## to the next pool member. A single-track stem's stream loops on itself and
## never fires `finished`, so this only ever does anything for a rotation.
func _on_music_stem_finished(stem_name: String) -> void:
	if _music_state == "":
		return
	var streams: Array = _music_streams_for(_music_state, stem_name)
	if streams.size() <= 1:
		return
	var player: AudioStreamPlayer = _music_players.get(stem_name)
	if player == null:
		return
	player.stream = streams[_no_repeat_index(
		"music:%s:%s" % [_music_state, stem_name], streams.size())]
	player.play()


func stop_music() -> void:
	_music_state = ""
	for stem_name in _music_players:
		_music_players[stem_name].stop()


func current_music() -> String:
	return _music_state


## Combat intensity, 0..1. Raises the rhythm stem, then the lead stem.
func set_combat_intensity(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _combat_intensity):
		return
	_combat_intensity = clamped
	_refresh_music_targets()


func combat_intensity() -> float:
	return _combat_intensity


func _refresh_music_targets() -> void:
	if _music_state == "" or _music_players.is_empty():
		return
	var stems: Dictionary = _music_manifest[_music_state]["stems"]
	# The bed is always full. Rhythm comes up over the lower half of the
	# intensity range and lead only over the upper half, so a skirmish escalates
	# in two stages instead of everything arriving at once.
	var wanted := {
		"bed": 1.0,
		"rhythm": clampf(_combat_intensity / 0.55, 0.0, 1.0),
		"lead": clampf((_combat_intensity - 0.45) / 0.55, 0.0, 1.0),
	}
	for stem_name in _music_players:
		if not stems.has(stem_name):
			_music_target_db[stem_name] = -80.0
			continue
		# A single-stem track (menu, lab, the stingers) names its one stem
		# "bed" and plays at full level.
		var amount: float = float(wanted.get(stem_name, 1.0))
		_music_target_db[stem_name] = linear_to_db(maxf(amount, 0.0001)) \
			if amount > 0.0001 else -80.0


func _process(delta: float) -> void:
	if _headless:
		return
	_tick_duck(delta)
	_tick_music(delta)
	_tick_ambience(delta)


func _tick_duck(delta: float) -> void:
	# Fast attack, slow release - standard broadcast behaviour, and much less
	# noticeable than a symmetric fade.
	if _duck <= 0.0:
		return
	_duck = maxf(0.0, _duck - delta / DUCK_RELEASE)


func _tick_music(delta: float) -> void:
	if _music_state == "":
		return
	var bed_step := delta / MUSIC_FADE * 80.0
	var stem_step := delta / STEM_FADE * 80.0
	for stem_name in _music_players:
		var player: AudioStreamPlayer = _music_players[stem_name]
		var target: float = float(_music_target_db[stem_name]) + _duck * DUCK_DB
		player.volume_db = move_toward(player.volume_db, target,
			bed_step if stem_name == "bed" else stem_step)


# --- Ambience ----------------------------------------------------------------

## Cross-fade to the bed for a surface type. Safe to call every frame with the
## same key. Pass "" to fade ambience out entirely.
func play_ambience(key: String) -> void:
	_ensure_loaded()
	if _headless or key == _ambience_key or _ambience_players.is_empty():
		return
	if key != "" and not _banks.has(key):
		return
	_ambience_key = key
	if key == "":
		return

	_ambience_active = 1 - _ambience_active
	var player: AudioStreamPlayer = _ambience_players[_ambience_active]
	var stream = _pick(key)
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	player.stream = stream
	player.volume_db = -80.0
	player.play()


func current_ambience() -> String:
	return _ambience_key


func _tick_ambience(delta: float) -> void:
	var step := delta / AMBIENCE_FADE * 80.0
	for i in range(_ambience_players.size()):
		var player: AudioStreamPlayer = _ambience_players[i]
		var target: float = AMBIENCE_DB if (i == _ambience_active and _ambience_key != "") \
			else -80.0
		player.volume_db = move_toward(player.volume_db, target, step)
		if player.volume_db <= -79.9 and player.playing:
			player.stop()
