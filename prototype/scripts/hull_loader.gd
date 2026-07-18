# HullLoader (use via preload, e.g. const HullLoader = preload("res://scripts/hull_loader.gd"))
# Hull modding (HULL_MODDING_PLAN.md): scans same-stem .glb+.json pairs from
# two directories - built-in hulls under res://assets/models/hulls (packed
# into the exported .pck, read-only to a real player) and player-added mod
# hulls under user://mods/hulls (writable after ship, same principle as this
# project's existing user://blueprints/ - see blueprint_manager.gd) - and
# merges them into one hull-only catalog dict, shaped exactly like the hull
# entries ModuleCatalog.get_catalog() used to hardcode.
#
# Scanned once, lazily, on first get_hulls() call - NOT per call. get_catalog()
# is a static func that rebuilds a brand-new dict literal on every single call
# and get_module_data() (the hottest function in the whole catalog system)
# calls it on nearly every stat calc/mount decision/AI tick - a directory
# scan + N file reads + N JSON parses on every one of those calls would be a
# real, immediate performance regression. This class owns the one-time scan;
# ModuleCatalog just merges the cached result in cheaply.
#
# Deliberately no `class_name` here (project gotcha: class_name globals
# aren't reliable in scripts run headless before the .godot cache exists -
# this bit module_placer.gd once) - always access via preload(), same
# convention as mesh_asset_loader.gd.

const BUILTIN_DIR = "res://assets/models/hulls"
const MOD_DIR = "user://mods/hulls"

const REQUIRED_FIELDS = ["name", "hp", "weight", "metal", "crystal", "size", "color"]
const NUMERIC_TYPES = [TYPE_INT, TYPE_FLOAT]

# medium_hull is a hardcoded fallback default in 7+ call sites across the
# codebase (battle_unit.gd, battlefield.gd, blueprint_manager.gd,
# module_placer.gd, stat_calculator.gd, enemy_ai.gd, skirmish.gd) - it must
# always exist and always be loadable. A moddable hull system can't let that
# guarantee depend on a third-party-editable sidecar file never going
# missing/corrupt, so this is a last-resort embedded copy of its own shipped
# sidecar (assets/models/hulls/medium_hull.json) - only ever used if that
# file is somehow missing or fails validation, which should never happen in
# a normal install and is loud (push_error) specifically because it
# indicates a broken installation, not a normal modding scenario.
const PROTECTED_MEDIUM_HULL_FALLBACK = {
	"name": "Medium Hull", "hp": 400.0, "weight": 250.0, "metal": 100, "crystal": 20,
	"dps": 0.0, "is_foundation": false, "base_energy": 70.0, "base_vision": 20.0,
	"draught": 0.5, "underside_y_bias": 0.0, "turreted_capable": true, "category": "hull",
}

static var _cache: Dictionary = {}
static var _mod_ids: Dictionary = {}
static var _scanned: bool = false

static func get_hulls() -> Dictionary:
	_ensure_scanned()
	return _cache

# Whether a given hull id was sourced from user://mods/hulls (as opposed to
# the built-in res:// directory) - not currently surfaced in any UI, but
# cheap to track and useful for a future "modded" badge / for tests.
static func is_modded(type_id: String) -> bool:
	_ensure_scanned()
	return _mod_ids.has(type_id)

# Test-only: forces the next get_hulls() call to rescan from disk instead of
# reusing the cached result. Production code never needs this - the whole
# point of the cache is that it lives for the process lifetime - but the
# automated test suite runs everything in one process and needs to add a
# temp mod file mid-run and see it picked up.
static func reset_cache_for_tests() -> void:
	_cache = {}
	_mod_ids = {}
	_scanned = false

static func _ensure_scanned() -> void:
	if _scanned:
		return
	_cache = {}
	_mod_ids = {}
	DirAccess.make_dir_recursive_absolute(MOD_DIR)
	_scan_directory(BUILTIN_DIR, false)
	_scan_directory(MOD_DIR, true)
	_ensure_medium_hull_protected()
	_scanned = true

static func _scan_directory(dir_path: String, is_mod: bool) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return # directory doesn't exist yet - not an error (mods dir starts empty)
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension() == "glb":
			_try_load_hull(dir_path, fname.get_basename(), is_mod)
		fname = dir.get_next()
	dir.list_dir_end()

static func _try_load_hull(dir_path: String, stem: String, is_mod: bool) -> void:
	var regex = RegEx.new()
	regex.compile("^[a-z0-9_]+$")
	if not regex.search(stem):
		push_warning("HullLoader: skipping '%s.glb' in %s - type_id must be lowercase snake_case [a-z0-9_]+" % [stem, dir_path])
		return

	var json_path = "%s/%s.json" % [dir_path, stem]
	if not FileAccess.file_exists(json_path):
		push_warning("HullLoader: skipping '%s.glb' in %s - no matching .json sidecar (a .glb with no sidecar is left for the procedural fallback, not treated as an error)" % [stem, dir_path])
		return

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_warning("HullLoader: skipping '%s' - could not open file" % json_path)
		return
	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_err = json.parse(text)
	if parse_err != OK:
		push_warning("HullLoader: skipping '%s' - JSON parse error: %s (line %d)" % [json_path, json.get_error_message(), json.get_error_line()])
		return
	var raw = json.get_data()
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("HullLoader: skipping '%s' - sidecar JSON must be an object" % json_path)
		return

	var validated = _validate_and_default(raw, json_path)
	if validated == null:
		return # _validate_and_default already logged the specific reason

	validated["category"] = "hull" # never trusted from the sidecar - see class header

	if _cache.has(stem):
		if is_mod:
			push_warning("HullLoader: mod hull '%s' (%s) OVERRIDES the built-in hull of the same id - the mod's data wins" % [stem, json_path])
		else:
			push_warning("HullLoader: duplicate built-in hull id '%s' at '%s' - keeping the first one found" % [stem, json_path])
			return

	_cache[stem] = validated
	if is_mod:
		_mod_ids[stem] = true
	elif _mod_ids.has(stem):
		_mod_ids.erase(stem) # built-in shouldn't be scanned after mods, but stay correct either way

static func _validate_and_default(raw: Dictionary, source_path: String):
	for field in REQUIRED_FIELDS:
		if not raw.has(field):
			push_warning("HullLoader: skipping '%s' - missing required field '%s'" % [source_path, field])
			return null

	if typeof(raw["name"]) != TYPE_STRING or raw["name"].strip_edges() == "":
		push_warning("HullLoader: skipping '%s' - 'name' must be a non-empty string" % source_path)
		return null

	for field in ["hp", "weight", "metal", "crystal"]:
		if typeof(raw[field]) not in NUMERIC_TYPES:
			push_warning("HullLoader: skipping '%s' - '%s' must be a number" % [source_path, field])
			return null

	var size_raw = raw["size"]
	if typeof(size_raw) != TYPE_ARRAY or size_raw.size() != 3:
		push_warning("HullLoader: skipping '%s' - 'size' must be a 3-element array [x, y, z]" % source_path)
		return null
	for v in size_raw:
		if typeof(v) not in NUMERIC_TYPES:
			push_warning("HullLoader: skipping '%s' - 'size' must contain only numbers" % source_path)
			return null

	var color_raw = raw["color"]
	if typeof(color_raw) != TYPE_ARRAY or (color_raw.size() != 3 and color_raw.size() != 4):
		push_warning("HullLoader: skipping '%s' - 'color' must be a 3 or 4-element array [r, g, b] or [r, g, b, a]" % source_path)
		return null
	for v in color_raw:
		if typeof(v) not in NUMERIC_TYPES:
			push_warning("HullLoader: skipping '%s' - 'color' must contain only numbers" % source_path)
			return null

	# Defaults mirror the exact getter defaults ModuleCatalog already used
	# for these optional fields (HULL_MODDING_PLAN.md §1/§3) - a sparse
	# sidecar that only fills in the required fields behaves identically to
	# today's code path for anything it omits.
	return {
		"name": raw["name"],
		"hp": float(raw["hp"]),
		"weight": float(raw["weight"]),
		"metal": int(raw["metal"]),
		"crystal": int(raw["crystal"]),
		"dps": float(raw.get("dps", 0.0)),
		"size": Vector3(size_raw[0], size_raw[1], size_raw[2]),
		"color": Color(color_raw[0], color_raw[1], color_raw[2], color_raw[3] if color_raw.size() == 4 else 1.0),
		"is_foundation": bool(raw.get("is_foundation", false)),
		"base_energy": float(raw.get("base_energy", 0.0)),
		"base_vision": float(raw.get("base_vision", 20.0)),
		"draught": float(raw.get("draught", 0.5)),
		"underside_y_bias": float(raw.get("underside_y_bias", 0.0)),
		"turreted_capable": bool(raw.get("turreted_capable", true)),
	}

static func _ensure_medium_hull_protected() -> void:
	if _cache.has("medium_hull"):
		return
	push_error("HullLoader: medium_hull sidecar is missing or invalid at %s/medium_hull.json - falling back to an embedded protected default. This should never happen in a normal install; 7+ scripts hardcode medium_hull as their safe fallback hull." % BUILTIN_DIR)
	var fallback = PROTECTED_MEDIUM_HULL_FALLBACK.duplicate()
	fallback["size"] = Vector3(4.0, 1.0, 6.0)
	fallback["color"] = Color(0.745098054409027, 0.745098054409027, 0.745098054409027, 1.0)
	_cache["medium_hull"] = fallback
