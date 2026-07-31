extends Node

## Central audio manager node for UI sounds, 3D world SFX, and ambient music.

const SFX_PATHS: Dictionary = {
	"click": "res://assets/audio/sfx/sfx_click.wav",
	"hover": "res://assets/audio/sfx/sfx_hover.wav",
	"error": "res://assets/audio/sfx/sfx_error.wav",
	"select": "res://assets/audio/sfx/sfx_select.wav",
	"place": "res://assets/audio/sfx/sfx_place.wav",
	"cannon": "res://assets/audio/sfx/sfx_cannon.wav",
	"machine_gun": "res://assets/audio/sfx/sfx_machine_gun.wav",
	"laser": "res://assets/audio/sfx/sfx_laser.wav",
	"missile": "res://assets/audio/sfx/sfx_missile.wav",
	"explosion": "res://assets/audio/sfx/sfx_explosion.wav",
	"hit": "res://assets/audio/sfx/sfx_hit.wav",
	"harvest": "res://assets/audio/sfx/sfx_harvest.wav",
	"construct": "res://assets/audio/sfx/sfx_construct.wav",
	"victory": "res://assets/audio/sfx/sfx_victory.wav",
	"defeat": "res://assets/audio/sfx/sfx_defeat.wav"
}

const MUSIC_PATHS: Dictionary = {
	"main_theme": "res://assets/audio/music/music_main_theme.wav"
}

var _streams: Dictionary = {}
var _music_streams: Dictionary = {}
var _music_player: AudioStreamPlayer = null
var _sfx_players: Array = []
var _sfx_index: int = 0
const MAX_SFX_PLAYERS: int = 32

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_load_audio_assets()
	_setup_players()

func _load_audio_assets() -> void:
	for name in SFX_PATHS:
		var path: String = SFX_PATHS[name]
		if ResourceLoader.exists(path):
			_streams[name] = load(path)
	for name in MUSIC_PATHS:
		var path: String = MUSIC_PATHS[name]
		if ResourceLoader.exists(path):
			var mstream = load(path)
			if mstream is AudioStreamWAV:
				mstream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			_music_streams[name] = mstream

func _setup_players() -> void:
	for i in range(MAX_SFX_PLAYERS):
		var player = AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_sfx_players.append(player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Master"
	add_child(_music_player)

func play_sfx(name: String, pitch_variance: float = 0.12) -> void:
	if DisplayServer.get_name() == "headless" or not _streams.has(name):
		return
	var stream = _streams[name] as AudioStream
	if not stream or _sfx_players.is_empty():
		return
	var player = _sfx_players[_sfx_index] as AudioStreamPlayer
	_sfx_index = (_sfx_index + 1) % MAX_SFX_PLAYERS

	player.stream = stream
	if pitch_variance > 0.0:
		player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	else:
		player.pitch_scale = 1.0
	player.play()

func play_sfx_3d(name: String, pos: Vector3, parent_node: Node = null, max_dist: float = 60.0, pitch_variance: float = 0.15) -> void:
	if DisplayServer.get_name() == "headless" or not _streams.has(name):
		return
	var stream = _streams[name] as AudioStream
	if not stream:
		return

	var player = AudioStreamPlayer3D.new()
	player.stream = stream
	player.max_distance = max_dist
	player.unit_size = 12.0
	if pitch_variance > 0.0:
		player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	player.finished.connect(func(): player.queue_free())

	var target = parent_node if parent_node else get_tree().current_scene
	if target:
		# global_position MUST be assigned after add_child, not before. A
		# Node3D outside the tree has no global transform, so the old ordering
		# both spammed "Condition !is_inside_tree() is true" once per call
		# AND silently dropped the position - every weapon report played at
		# its parent's origin instead of at the muzzle, so positional audio
		# was quietly wrong as well as expensive. Measured at ~9,000 errors
		# per 240-frame sample with 8 rapid-fire units engaged, since this is
		# called once per shot (auto_weapon.gd's _fire_at_target).
		target.add_child(player)
		player.global_position = pos
		player.play()

func play_music(track_name: String) -> void:
	if DisplayServer.get_name() == "headless" or not _music_streams.has(track_name):
		return
	var stream = _music_streams[track_name] as AudioStream
	if not stream or not _music_player:
		return
	_music_player.stream = stream
	_music_player.play()

func stop_music() -> void:
	if _music_player and _music_player.playing:
		_music_player.stop()
