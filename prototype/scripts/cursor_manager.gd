extends Node

## Autoload node managing custom tactical mouse cursors and context swaps.

enum CursorType {
	DEFAULT,
	POINTER,
	MOVE,
	ATTACK,
	HARVEST,
	INVALID,
	BUILD
}

const CURSOR_CONFIGS: Dictionary = {
	CursorType.DEFAULT: {"path": "res://assets/cursors/cursor_default.png", "hotspot": Vector2(0, 0)},
	CursorType.POINTER: {"path": "res://assets/cursors/cursor_pointer.png", "hotspot": Vector2(8, 2)},
	CursorType.MOVE: {"path": "res://assets/cursors/cursor_move.png", "hotspot": Vector2(16, 16)},
	CursorType.ATTACK: {"path": "res://assets/cursors/cursor_attack.png", "hotspot": Vector2(16, 16)},
	CursorType.HARVEST: {"path": "res://assets/cursors/cursor_harvest.png", "hotspot": Vector2(16, 16)},
	CursorType.INVALID: {"path": "res://assets/cursors/cursor_invalid.png", "hotspot": Vector2(16, 16)},
	CursorType.BUILD: {"path": "res://assets/cursors/cursor_build.png", "hotspot": Vector2(16, 16)},
}

var _loaded_textures: Dictionary = {}
var _current_cursor: int = CursorType.DEFAULT

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_load_textures()
	set_cursor(CursorType.DEFAULT)

func _load_textures() -> void:
	for type in CURSOR_CONFIGS:
		var cfg = CURSOR_CONFIGS[type]
		var path: String = cfg["path"]
		if ResourceLoader.exists(path):
			_loaded_textures[type] = load(path)

func set_cursor(type: int) -> void:
	_current_cursor = type
	if DisplayServer.get_name() == "headless":
		return
	if not _loaded_textures.has(type):
		Input.set_custom_mouse_cursor(null)
		return
	var tex: Texture2D = _loaded_textures[type]
	var hotspot: Vector2 = CURSOR_CONFIGS[type]["hotspot"]
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, hotspot)

