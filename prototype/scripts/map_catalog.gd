extends Node
class_name MapCatalog
# Skirmish map library. RTS_CORE_ROADMAP.md B3: maps are now JSON files
# under res://data/maps/*.json, scanned and cached once (same lazy
# scan-and-cache pattern as hull_loader.gd - a directory scan + N file
# reads/parses on every get_map() call would be a real perf regression;
# module_catalog.gd/enemy_ai.gd call through this on nearly every tick).
# D1's decision: shipped content (this directory) hard-fails loudly on
# invalid data (push_error + assert) rather than warn-and-skip - a broken
# map is a broken install, not a normal modding scenario. User-authored
# maps under user://maps/ (not built yet - no UI creates them) will get
# the warn-and-attempt treatment when that lands.
#
# JSON encodes Vector3/Vector2/Color as plain number arrays ([x,y,z] /
# [x,y] / [r,g,b]) since raw JSON has no vector/color type - FIELD_SPEC
# (originally B1's validator-only spec) now drives BOTH validation AND
# decoding back into real Godot types, so there's one schema description,
# not two things that could drift apart.
#
# Field shapes:
#   water_areas: [{center: Vector3, half_extents: Vector2}, ...]
#     (rectangular XZ footprints, Y ignored - flat-ground features)
#   obstacles: [{center, half_extents, type: "rock"/"building", building_height (opt)}, ...]
#     "type" defaults to "rock" (a jumbled boulder cluster) if omitted;
#     "building" is a single boxy structure with a flat roof and window
#     greebles - both are equally real cover (StaticBody3D on collision
#     layer 1), which is what makes them block weapon LOS (auto_weapon.gd)
#     and vision LOS (TerrainBuilder/skirmish.gd's _has_line_of_sight())
#     alike, not just movement.
#   elevation_zones: [{center, half_extents, height, ramp_side, ramp_width}, ...]
#     a raised rectangular plateau with ONE ramp on the given side
#     ("north"/"south"/"east"/"west" = +Z/-Z/+X/-X ground-level approach).
#     Ramp run length is derived (TerrainBuilder.RAMP_RUN_PER_HEIGHT), not
#     authored per-zone, to keep map data terse and every ramp's slope angle
#     consistently walkable.
#   bridges: [{center, half_extents, deck_height (opt)}, ...]
#     a rectangular strip carved through a water_areas hole, walkable for
#     ground/legged locomotion ONLY (not naval/amphibious, which don't need
#     it - see TerrainBuilder._collect_bridges()) - flanked by water on
#     both sides that ISN'T carved, so it's a genuine narrow chokepoint, not
#     a way to remove the water. Deliberately does not block water_map/
#     deep_water_map - naval units still float and pass freely underneath,
#     same as a real bridge over a river. A bridge's footprint should
#     always fully span a water_areas rect along the crossing axis (so
#     there's dry land - or at least the water's edge - on both ends);
#     nothing enforces this automatically, it's a map-authoring convention.
#   resource_nodes: [{position: Vector3, type: "metal"/"crystal", amount: int}, ...]
#   spawns: [{id: String, hq, factory, refinery, harvester: Vector3}, ...]
#     was player_start/enemy_start (B3) - "player"/"enemy" ids preserve the
#     exact 2-spawn runtime behavior; real N-player spawn assignment (pick
#     which slot uses which spawn) is B10's job, not this schema's.
#   players (optional): B2's slot fields, not yet authored by any map -
#     reserved for a future real N-player match-setup flow.
#   markers (optional): {name: {position, kind}} - OpenRA's named-map-actor
#     idea without the actor/trait machinery. Unused today.
#   terrain (optional): {heightmap, surfacemap, height_scale, features}
#     reserved for B4's Python heightmap generator - the field exists in
#     the schema now so B4 doesn't need a schema_version bump later.

const DEFAULT_MAP_ID: String = "lake_crossing"
const MAPS_DIR: String = "res://data/maps"

# Lazy scan-and-cache (hull_loader.gd's own established pattern) - the
# directory scan + N JSON parses happen once per process, not per call.
static var _cache: Dictionary = {}
static var _scanned: bool = false

# Test-only: forces the next get_map()/get_map_ids() call to rescan from
# disk. Production code never needs this (the cache lives for the process
# lifetime by design), but the automated suite runs everything in one
# process and B3's deep-equal test wants a guaranteed-fresh load.
static func reset_cache_for_tests() -> void:
	_cache = {}
	_scanned = false
	_last_load_error = ""

# The specific reason the most recent hard-fail was rejected - "" if
# nothing has failed to load yet this scan.
static func get_last_load_error() -> String:
	return _last_load_error

static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	_cache = {}
	var dir = DirAccess.open(MAPS_DIR)
	if not dir:
		push_error("MapCatalog: could not open '%s' - no maps will load." % MAPS_DIR)
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension() == "json":
			_load_map_file(fname.get_basename(), "%s/%s" % [MAPS_DIR, fname])
		fname = dir.get_next()
	dir.list_dir_end()

# D1: shipped content (res://data/maps/) hard-fails loudly - matching the
# deliberately strict GLB _part() loader (visual_builder.gd), not
# hull_loader.gd's current warn-and-skip (that file predates D1's decision
# and is explicitly called out to get this same treatment "later"). "Hard
# fail" here means the broken map is REFUSED - never enters the usable
# catalog (get_map() for its id silently falls back to DEFAULT_MAP_ID,
# same graceful-fallback behavior an unknown id already had) - with a
# push_error() loud enough to show up in any log, debug or release.
# Deliberately not assert()-based: this needs to be exercisable by an
# automated test in the same process without pausing/aborting it, and a
# broken map shouldn't be able to take the whole game down anyway.
# _last_load_error mirrors blueprint_manager.gd's own last_load_error
# convention - the one place a test (or a future in-game error dialog)
# reads the specific reason from.
static var _last_load_error: String = ""

static func _load_map_file(map_id: String, path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		_fail_load(path, "could not open file")
		return
	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_err = json.parse(text)
	if parse_err != OK:
		_fail_load(path, "JSON parse error: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return
	var raw = json.get_data()
	if typeof(raw) != TYPE_DICTIONARY:
		_fail_load(path, "must be a JSON object at the top level")
		return

	# Decode BEFORE validating: raw JSON has no Vector3/Vector2/Color type,
	# so "center": [1,2,3] is a TYPE_ARRAY until _decode_dict() turns it
	# into a real Vector3 - validating the raw shape would reject every
	# single vector/color field as "wrong type." _decode_value() is
	# defensive (a malformed array is passed through unchanged rather than
	# indexed into and crashing), so a genuinely bad value still reaches
	# validate_map_def() and gets reported with a useful message instead.
	var decoded = _decode_dict(raw, FIELD_SPEC)
	var errors = validate_map_def(decoded)
	if not errors.is_empty():
		_fail_load(path, "failed schema validation:\n  %s" % "\n  ".join(errors))
		return

	_cache[map_id] = decoded

static func _fail_load(path: String, reason: String) -> void:
	_last_load_error = "MapCatalog: '%s' %s" % [path, reason]
	push_error(_last_load_error)

static func get_map_ids() -> Array:
	_ensure_scanned()
	var ids = _cache.keys()
	ids.sort()
	return ids

static func get_map(map_id: String) -> Dictionary:
	_ensure_scanned()
	return _cache.get(map_id, _cache.get(DEFAULT_MAP_ID, {}))

static func get_map_name(map_id: String) -> String:
	return get_map(map_id).get("name", map_id)

# The one supported way to go from a map's spawns array to "the player's
# start" / "the enemy's start" - replaces the old direct
# current_map.player_start/.enemy_start access. "player"/"enemy" ids are
# what every bundled map's spawns array uses (B3); a real N-player spawn
# picker (which slot gets which spawn) is B10's job.
static func get_spawn(map_def: Dictionary, spawn_id: String) -> Dictionary:
	for s in map_def.get("spawns", []):
		if s.get("id") == spawn_id:
			return s
	return {}

# RTS_CORE_ROADMAP.md B1: a declarative field -> type -> required -> range
# spec, walked by one reflective validator (validate_map()) instead of
# hand-written per-field asserts - the GDScript analogue of OpenRA's lint
# passes (D1's decision). Ships BEFORE the B3 JSON-format swap so that
# migration has a safety net to catch a transcription error against, per
# this file's own MAPS const being the only source of truth today.
#
# Each leaf spec: {"type": <below>, "required": bool, "min": num (opt),
# "enum": Array[String] (opt)}. Array/Dictionary specs additionally carry
# "item": a nested field-spec Dictionary, applied to every array element
# (Array) or directly (Dictionary) - same recursive shape used all the way
# down, so obstacles/elevation_zones/etc. get free per-subkey + unknown-key
# checking without a bespoke validator each.
const FIELD_SPEC: Dictionary = {
	"name": {"type": "string", "required": true},
	"description": {"type": "string", "required": true},
	"map_half_extents": {"type": "number", "required": true, "min": 1.0},
	"ground_color": {"type": "color", "required": true},
	"water_blobs": {"type": "array", "required": false, "item": {
		"center": {"type": "vector3", "required": true},
		"radius": {"type": "number", "required": true, "min": 0.01},
		"irregularity": {"type": "number", "required": false},
		"depth": {"type": "number", "required": false},
		"shore_blend": {"type": "number", "required": false},
	}},
	"water_areas": {"type": "array", "required": false, "item": {
		"center": {"type": "vector3", "required": true},
		"half_extents": {"type": "vector2", "required": true},
	}},
	"shallow_water_areas": {"type": "array", "required": false, "item": {
		"center": {"type": "vector3", "required": true},
		"half_extents": {"type": "vector2", "required": true},
	}},
	"obstacles": {"type": "array", "required": false, "item": {
		"center": {"type": "vector3", "required": true},
		"half_extents": {"type": "vector2", "required": true},
		"type": {"type": "string", "required": false, "enum": ["rock", "building"]},
		"building_height": {"type": "number", "required": false, "min": 0.01},
	}},
	"elevation_zones": {"type": "array", "required": false, "item": {
		"center": {"type": "vector3", "required": true},
		"half_extents": {"type": "vector2", "required": true},
		"height": {"type": "number", "required": true},
		"ramp_side": {"type": "string", "required": true, "enum": ["north", "south", "east", "west"]},
		"ramp_width": {"type": "number", "required": true, "min": 0.01},
	}},
	"surface_zones": {"type": "array", "required": false, "item": {
		"center": {"type": "vector3", "required": true},
		"half_extents": {"type": "vector2", "required": true},
		"surface_type": {"type": "string", "required": true, "enum": ["marsh", "rocky", "snow_mud", "sand"]},
	}},
	"bridges": {"type": "array", "required": false, "item": {
		"center": {"type": "vector3", "required": true},
		"half_extents": {"type": "vector2", "required": true},
		"deck_height": {"type": "number", "required": false},
	}},
	"resource_nodes": {"type": "array", "required": false, "item": {
		"position": {"type": "vector3", "required": true},
		"type": {"type": "string", "required": true, "enum": ["metal", "crystal"]},
		"amount": {"type": "number", "required": true, "min": 1},
	}},
	# B3: was player_start/enemy_start (2 fixed dict fields); now a
	# spawns array with an id per entry. "player"/"enemy" are the ids
	# every bundled map uses today (see get_spawn()).
	"spawns": {"type": "array", "required": true, "item": {
		"id": {"type": "string", "required": true},
		"hq": {"type": "vector3", "required": true},
		"factory": {"type": "vector3", "required": true},
		"refinery": {"type": "vector3", "required": true},
		"harvester": {"type": "vector3", "required": true},
	}},
	"schema_version": {"type": "number", "required": true, "min": 1},
	# Reserved fields (B3): not authored by any of the 8 bundled maps yet,
	# so deliberately shallow specs (no "item") - just type-checked, not
	# deeply validated, until something actually populates them.
	"players": {"type": "array", "required": false},
	"markers": {"type": "dictionary", "required": false},
	"terrain": {"type": "dictionary", "required": false},
}

# Returns an Array[String] of human-readable errors; empty = valid.
# Re-validates the already-loaded (and already hard-fail-checked-at-load)
# cached map - mainly useful for tests. A raw/corrupted Dictionary that
# was never loaded through _load_map_file() should call validate_map_def()
# directly instead (see test_map_schema_validator()).
static func validate_map(map_id: String) -> Array:
	_ensure_scanned()
	if not _cache.has(map_id):
		return ["Unknown map id '%s'" % map_id]
	return validate_map_def(_cache[map_id])

# Walks FIELD_SPEC against any map Dictionary - no per-map hand-written
# asserts, so a 9th map (or a test's corrupted copy) gets the exact same
# coverage the first 8 already do.
static func validate_map_def(map_def: Dictionary) -> Array:
	var errors: Array = []
	_validate_dict(map_def, FIELD_SPEC, "", errors)

	# Cross-field check (not expressible in the per-field spec alone):
	# every resource node has to actually sit inside the map's own bounds -
	# nothing upstream of this enforces that today.
	var half_extents = map_def.get("map_half_extents", 0)
	if typeof(half_extents) == TYPE_FLOAT or typeof(half_extents) == TYPE_INT:
		var nodes = map_def.get("resource_nodes", [])
		if typeof(nodes) == TYPE_ARRAY:
			for i in range(nodes.size()):
				var node = nodes[i]
				if typeof(node) == TYPE_DICTIONARY and typeof(node.get("position")) == TYPE_VECTOR3:
					var pos: Vector3 = node["position"]
					if abs(pos.x) > half_extents or abs(pos.z) > half_extents:
						errors.append("resource_nodes[%d].position %s is outside map_half_extents %s" % [i, pos, half_extents])
	return errors

static func _validate_dict(d: Dictionary, spec: Dictionary, prefix: String, errors: Array) -> void:
	for key in spec.keys():
		var full_key = prefix + key
		if not d.has(key):
			if spec[key].get("required", false):
				errors.append("Missing required field '%s'" % full_key)
			continue
		_validate_value(d[key], spec[key], full_key, errors)
	for key in d.keys():
		if not spec.has(key):
			errors.append("Unknown field '%s'" % (prefix + str(key)))

static func _validate_value(value, field_spec: Dictionary, full_key: String, errors: Array) -> void:
	var t: String = field_spec.get("type", "")
	match t:
		"string":
			if typeof(value) != TYPE_STRING:
				errors.append("'%s' should be a String, got type %d" % [full_key, typeof(value)])
				return
			if field_spec.has("enum") and not (value in field_spec["enum"]):
				errors.append("'%s' value '%s' not in allowed set %s" % [full_key, value, field_spec["enum"]])
		"number":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				errors.append("'%s' should be a number, got type %d" % [full_key, typeof(value)])
				return
			if field_spec.has("min") and value < field_spec["min"]:
				errors.append("'%s' value %s is below minimum %s" % [full_key, value, field_spec["min"]])
		"color":
			if typeof(value) != TYPE_COLOR:
				errors.append("'%s' should be a Color, got type %d" % [full_key, typeof(value)])
		"vector3":
			if typeof(value) != TYPE_VECTOR3:
				errors.append("'%s' should be a Vector3, got type %d" % [full_key, typeof(value)])
		"vector2":
			if typeof(value) != TYPE_VECTOR2:
				errors.append("'%s' should be a Vector2, got type %d" % [full_key, typeof(value)])
		"array":
			if typeof(value) != TYPE_ARRAY:
				errors.append("'%s' should be an Array, got type %d" % [full_key, typeof(value)])
				return
			if field_spec.has("item"):
				for i in range(value.size()):
					var elem = value[i]
					if typeof(elem) != TYPE_DICTIONARY:
						errors.append("'%s[%d]' should be a Dictionary, got type %d" % [full_key, i, typeof(elem)])
						continue
					_validate_dict(elem, field_spec["item"], "%s[%d]." % [full_key, i], errors)
		"dictionary":
			if typeof(value) != TYPE_DICTIONARY:
				errors.append("'%s' should be a Dictionary, got type %d" % [full_key, typeof(value)])
				return
			if field_spec.has("item"):
				_validate_dict(value, field_spec["item"], full_key + ".", errors)
		_:
			errors.append("Internal: unknown field-spec type '%s' for '%s'" % [t, full_key])

# RTS_CORE_ROADMAP.md B3: turns raw JSON (arrays of numbers) back into real
# Godot types, driven by the exact same FIELD_SPEC the validator walks -
# one schema description instead of a second, separately-maintained decode
# table that could drift out of sync with it. Same recursive shape as
# _validate_dict/_validate_value on purpose.
static func _decode_dict(d: Dictionary, spec: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in d.keys():
		if spec.has(key):
			result[key] = _decode_value(d[key], spec[key])
		else:
			result[key] = d[key] # unknown key - validate_map_def() will flag it; pass through so the error can name it
	return result

# Defensive on purpose: a malformed value (wrong array length, wrong
# element types) is passed through UNCHANGED rather than indexed into and
# crashing - validate_map_def() runs right after decoding and reports the
# mismatch with a real message instead of a stack trace.
static func _decode_value(value, field_spec: Dictionary):
	var t: String = field_spec.get("type", "")
	match t:
		"vector3":
			if typeof(value) == TYPE_ARRAY and value.size() == 3:
				return Vector3(value[0], value[1], value[2])
			return value
		"vector2":
			if typeof(value) == TYPE_ARRAY and value.size() == 2:
				return Vector2(value[0], value[1])
			return value
		"color":
			if typeof(value) == TYPE_ARRAY and (value.size() == 3 or value.size() == 4):
				return Color(value[0], value[1], value[2], value[3] if value.size() == 4 else 1.0)
			return value
		"array":
			if typeof(value) != TYPE_ARRAY:
				return value
			if not field_spec.has("item"):
				return value.duplicate()
			var out: Array = []
			for elem in value:
				if typeof(elem) == TYPE_DICTIONARY:
					out.append(_decode_dict(elem, field_spec["item"]))
				else:
					out.append(elem)
			return out
		"dictionary":
			if typeof(value) == TYPE_DICTIONARY and field_spec.has("item"):
				return _decode_dict(value, field_spec["item"])
			return value
		_:
			return value # string/number - JSON's own type already matches
