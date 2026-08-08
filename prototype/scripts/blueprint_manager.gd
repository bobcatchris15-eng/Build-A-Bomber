extends Node
const ModuleDataResource = preload("res://scripts/module_data.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

# Bumped only when the blueprint JSON schema changes in a way that could
# silently mis-load older saves (not for every new field - new fields
# default gracefully via .get() everywhere in reconstruct_vehicle already).
# Never bumped so far, so this can't fire against any of Chris's real
# ~29 saved designs today - it exists so a FUTURE schema change doesn't
# silently load stale data with zero indication, which was the actual gap
# (every save/load path already tolerates a missing "version" key fine).
# Bumped 1.0 -> 2.0 when the hull roster was rebuilt on the SDF/Marching-Cubes
# pipeline (data/hull_assemblies/ + tools/bake_hull_roster.gd). Hull type_ids
# and their load-bearing sidecar `size` were both preserved, so v1 designs
# still LOAD - but their module positions were placed against the previous
# hull surfaces, so mounts can sit slightly proud of or sunk into the new
# ones. The version check below surfaces that instead of loading silently.
const CURRENT_BLUEPRINT_VERSION: float = 2.0

const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")
const HullGreeblesScript = preload("res://scripts/hull_greebles.gd")
const ArmorGreeblesScript = preload("res://scripts/armor_greebles.gd")
const HullDecalsScript = preload("res://scripts/hull_decals.gd")
const ModuleCatalogScript = preload("res://scripts/module_catalog.gd")
const HullSurfaceScript = preload("res://scripts/hull_surface.gd")
# File-level, not the loop-local `var VisualBuilder = preload(...)` inside
# reconstruct_vehicle's module loop - the ground-contact measurement at the end
# of that function runs after the loop, where that local is out of scope.
const VisualBuilderScript = preload("res://scripts/visual_builder.gd")
const ModuleMirrorScript = preload("res://scripts/module_mirror.gd")

# Set by load_blueprint_into_designer() whenever it returns false, so
# callers (blueprint_library_screen.gd) can show a specific reason instead of
# a generic "corrupted" message - most importantly for a blueprint whose
# hull_type is no longer installed (mod uninstalled, typo, hand-edited
# save), which is a real and correct file, just referencing a hull that
# genuinely doesn't exist. Cleared at the start of every load attempt.
var last_load_error: String = ""

# --- Scratch design vs. saved design -----------------------------------
#
# "Test in Arena" used to call save_blueprint(), which wrote a permanent
# file into user://blueprints/ under the fallback name "Untitled Design".
# Every trip to the test range therefore minted a new roster entry, which is
# why the match-setup import list is full of near-identical "Untitled Design
# (Medium Hull | Industrialists)" rows.
#
# The split now:
#   SCRATCH  - the design currently being worked on. Written on every trip
#              to the arena so the arena has something to load and the Lab
#              can restore it on the way back. Never appears in the roster.
#   SAVED    - user://blueprints/<id>.json, created only by an explicit
#              Save with a real name. This is what the roster reads.
const SCRATCH_PATH = "user://lab_scratch.json"
# Legacy single-slot pointer that Battlefield.tscn (the Test Range) reads.
const LEGACY_SLOT_PATH = "user://blueprint.json"

# The name a design has when the player hasn't given it one. A design still
# carrying this is by definition not something they chose to keep.
const PLACEHOLDER_NAME = "Untitled Design"


# A design earns a roster slot by having a real, player-chosen name.
#
# Deliberately also treats the placeholder as unnamed, not just the empty
# string: the old save path silently substituted "Untitled Design" for a
# blank field, so "has a name" and "has a non-empty name" are not the same
# question against existing files on disk.
#
# Matched case-INSENSITIVELY. "untitled design" typed by hand is the same
# non-decision as the one the old code auto-filled, and letting it through
# on a capitalisation technicality would put it straight back in the roster
# - which is the entire thing this gate exists to prevent.
static func is_named(bp_name: String) -> bool:
	var trimmed := bp_name.strip_edges()
	return trimmed != "" and trimmed.to_lower() != PLACEHOLDER_NAME.to_lower()

func _vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}

func serialize_hull(hull: Node3D) -> Dictionary:
	if not hull:
		return {}

	var hull_size = Vector3(4.0, 1.0, 6.0)
	if hull.has_meta("base_hull_size") and hull.has_meta("hull_scale"):
		hull_size = hull.get_meta("base_hull_size") * hull.get_meta("hull_scale")

	var locomotion_type = hull.get_meta("locomotion_type") if hull.has_meta("locomotion_type") else ""
	var locomotion_settings = hull.get_meta("locomotion_settings") if hull.has_meta("locomotion_settings") else {}

	var blueprint = {
		"version": 1.0,
		"hull_type": hull.get_meta("type_id") if hull.has_meta("type_id") else "medium_hull",
		"hull_scale": {"x": hull.get_meta("hull_scale").x, "y": hull.get_meta("hull_scale").y, "z": hull.get_meta("hull_scale").z} if hull.has_meta("hull_scale") else {"x": 1.0, "y": 1.0, "z": 1.0},
		"hull_size": {"x": hull_size.x, "y": hull_size.y, "z": hull_size.z},
		"armor_material": hull.get_meta("armor_material") if hull.has_meta("armor_material") else "hardened_steel",
		"armor_thickness": hull.get_meta("armor_thickness") if hull.has_meta("armor_thickness") else 1.0,
		"nose_taper": hull.get_meta("nose_taper") if hull.has_meta("nose_taper") else 1.0,
		"faction": hull.get_meta("faction") if hull.has_meta("faction") else "industrialists",
		"locomotion": {
			"type_id": locomotion_type,
			"settings": locomotion_settings
		},
		"modules": []
	}

	for child in hull.get_children():
		if child is StaticBody3D: continue # Hull's own collider
		if child is MeshInstance3D: continue # Hull's own mesh

		# Assume this is a module Node3D
		if child.has_meta("module_data"):
			var data = child.get_meta("module_data")
			# Structural pieces carry their resize as a "struct_scale" meta
			# and keep node.scale at ONE (scale isolation - see gizmo_3d.gd's
			# _apply_scale_to_node and visual_builder's structural branch).
			# Reading child.scale for those would save (1,1,1) every time and
			# silently throw away every structural resize in the design on
			# the next save. Same on-disk field either way, so old blueprints
			# still load unchanged.
			var saved_scale: Vector3 = child.get_meta("struct_scale", child.scale)
			var mod_dict = {
				"type_id": data.type_id if "type_id" in data else "",
				"name": data.module_name,
				"position": {"x": child.position.x, "y": child.position.y, "z": child.position.z},
				"rotation": {"x": child.rotation.x, "y": child.rotation.y, "z": child.rotation.z},
				"scale": {"x": saved_scale.x, "y": saved_scale.y, "z": saved_scale.z},
				"yaw_offset": child.get_meta("yaw_offset", 0.0),
				"mount_style": child.get_meta("mount_style", ""),
				"mount_normal": _vec3_to_dict(child.get_meta("mount_normal", Vector3.UP)),
				"facet": child.get_meta("facet", ""),
				# Whether this weapon is embedded in a near-vertical face and
				# fires out through a blister housing (module_placer's
				# _is_sponson_mount). Optional and defaulting to false, so a
				# blueprint written before sponsons existed loads byte-identical
				# to how it always did. The orientation itself rides along in
				# "rotation" like every other module's - this flag exists so
				# rebuild_visual knows to put the housing back.
				"sponson": bool(child.get_meta("sponson", false)),
				# Chirality. A left-side leg/engine/wing is the REFLECTION of
				# its right-side twin, not a second copy, and that reflection
				# lives on the module's visual children (see
				# module_placer.gd's _apply_mirror_flip). It was never
				# serialized, so every mirrored part came back unmirrored the
				# moment a design was saved and reloaded - or fielded in a
				# match, which rebuilds from this same dictionary.
				"scale_flip_x": bool(child.get_meta("scale_flip_x", false)),
				"tweaks": data.tweaks if "tweaks" in data else {},
				"stats": {
					"hp": data.get_hp(),
					"weight": data.get_weight(),
					"cost_metal": data.get_cost().x,
					"cost_crystal": data.get_cost().y,
					"dps": data.get_dps()
				}
			}
			blueprint["modules"].append(mod_dict)

	if hull.has_meta("blueprint_id"):
		blueprint["id"] = hull.get_meta("blueprint_id")
	blueprint["name"] = hull.get_meta("blueprint_name") if hull.has_meta("blueprint_name") and hull.get_meta("blueprint_name") != "" else "Untitled Design"

	return blueprint

# Real floating toast instead of temporarily overwriting the sidebar's
# persistent "Blueprint Stats" title label - the old approach was both
# easy to miss (2-2.5s, in a spot you're not necessarily looking at) and
# a little confusing (the title itself appeared to change state, not just
# show a transient notification).
func _show_toast(msg: String, is_error: bool = false):
	var root = get_node_or_null("/root/MainLab")
	if not root:
		return
	var toast = PanelContainer.new()
	# Keeps a stylebox, because the fill IS the message: succeeded or failed. That
	# is state, which is what ui_tokens.gd reserves signal colour for.
	#
	# What changed is which colours. The DIM variants exist precisely for "fills
	# that sit UNDER text" - the old hand-mixed (0.55, 0.15, 0.15) and (0.15, 0.45,
	# 0.2) were saturated enough to fight the white label on top of them, and
	# neither is in the palette. 8px corners went too; the tokens commit to
	# near-square.
	var style = StyleBoxFlat.new()
	style.bg_color = Tokens.SIGNAL_ALERT_DIM if is_error else Tokens.SIGNAL_GO_DIM
	style.border_color = Tokens.SIGNAL_ALERT if is_error else Tokens.SIGNAL_GO
	style.border_width_left = Tokens.BORDER_EMPHASIS
	style.corner_radius_top_left = Tokens.RADIUS_CONTROL
	style.corner_radius_top_right = Tokens.RADIUS_CONTROL
	style.corner_radius_bottom_left = Tokens.RADIUS_CONTROL
	style.corner_radius_bottom_right = Tokens.RADIUS_CONTROL
	style.content_margin_left = Tokens.SPACE_LG
	style.content_margin_right = Tokens.SPACE_LG
	style.content_margin_top = Tokens.SPACE_SM
	style.content_margin_bottom = Tokens.SPACE_SM
	toast.add_theme_stylebox_override("panel", style)
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -220
	toast.offset_right = 220
	toast.offset_top = 40
	toast.offset_bottom = 76
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast)

	var label = Label.new()
	label.text = msg
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = "HeadingLabel"
	# TEXT_PRIMARY, the warm off-white. Pure white on a warm dark fill reads as a
	# blown-out highlight - ui_tokens.gd's palette section says so explicitly.
	label.add_theme_color_override("font_color", Tokens.TEXT_PRIMARY)
	toast.add_child(label)

	get_tree().create_timer(2.6).timeout.connect(func():
		if is_instance_valid(toast):
			toast.queue_free()
	)

func save_blueprint() -> bool:
	var root = get_node("/root/MainLab")
	if root and root.get("clipping_detected") == true:
		_show_toast("SAVE FAILED: Clipping!", true)
		return false

	var hull = root.get_node_or_null("Hull")
	if not hull:
		print("No hull found to save.")
		return false

	var blueprint = serialize_hull(hull)

	var bp_id = ""
	if hull.has_meta("blueprint_id"):
		bp_id = hull.get_meta("blueprint_id")
	if bp_id == "":
		bp_id = _generate_blueprint_id()
	var bp_name = ""
	if hull.has_meta("blueprint_name"):
		bp_name = str(hull.get_meta("blueprint_name")).strip_edges()

	# Refuse rather than substituting a placeholder. Saving is what puts a
	# design in front of the player in a match, so it needs a deliberate
	# name; quietly inventing one is how the roster filled up with
	# indistinguishable entries in the first place.
	if not is_named(bp_name):
		_show_toast("Name this design before saving.", true)
		return false

	blueprint["id"] = bp_id
	blueprint["name"] = bp_name
	blueprint["modified_unix"] = Time.get_unix_time_from_system()

	hull.set_meta("blueprint_id", bp_id)
	hull.set_meta("blueprint_name", bp_name)

	var json_string = JSON.stringify(blueprint, "\t")

	DirAccess.make_dir_recursive_absolute("user://blueprints")
	var file = FileAccess.open("user://blueprints/%s.json" % bp_id, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Blueprint '%s' saved (id=%s)" % [bp_name, bp_id])

	# Legacy single-slot pointer, kept in sync so the existing single-unit
	# weapon test range (Battlefield.tscn / "Test in Arena") keeps working unchanged.
	var legacy_file = FileAccess.open("user://blueprint.json", FileAccess.WRITE)
	if legacy_file:
		legacy_file.store_string(json_string)
		legacy_file.close()

	_show_toast("Saved '%s'!" % bp_name)
	# An explicit save supersedes whatever was in the scratch slot - the
	# design is now a real, named file, so there is no unsaved work left for
	# the Lab to restore.
	clear_scratch()
	return true


# Writes the in-progress design to the scratch slot WITHOUT creating a
# roster entry. Used by "Test in Arena".
#
# Returns false for the same reason save_blueprint() does - clipping - so
# the caller can block the scene transition. It deliberately does NOT
# require a name: testing an unnamed design is the whole point.
func save_scratch(mark_for_lab_restore: bool = true) -> bool:
	var root = get_node_or_null("/root/MainLab")
	if root and root.get("clipping_detected") == true:
		_show_toast("TEST BLOCKED: Clipping!", true)
		return false

	var hull = root.get_node_or_null("Hull") if root else null
	if not hull:
		print("No hull found to stage for testing.")
		return false

	var blueprint = serialize_hull(hull)
	# Carry the id/name through even when unnamed, so that testing, coming
	# back, and THEN saving updates the same design rather than forking a
	# second copy of it.
	blueprint["id"] = hull.get_meta("blueprint_id", "")
	blueprint["name"] = str(hull.get_meta("blueprint_name", "")).strip_edges()
	blueprint["modified_unix"] = Time.get_unix_time_from_system()
	# Consumed once by the Lab on next load. Stored in the file rather than
	# in a static var so it survives the player closing the game while in
	# the arena - they still get their design back.
	blueprint["pending_lab_restore"] = mark_for_lab_restore

	var json_string = JSON.stringify(blueprint, "\t")
	for path in [SCRATCH_PATH, LEGACY_SLOT_PATH]:
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(json_string)
			f.close()
	return true


# True when the Lab should restore a design on load - i.e. the player left
# for the arena and is now coming back.
func has_pending_lab_restore() -> bool:
	if not FileAccess.file_exists(SCRATCH_PATH):
		return false
	return load_blueprint(SCRATCH_PATH).get("pending_lab_restore", false)


# Rebuilds the scratch design in the Lab and clears the restore flag, so a
# later fresh visit to the Lab starts clean instead of resurrecting an old
# session. Mirrors load_blueprint_into_designer(), minus the roster lookup.
func restore_scratch_into_designer() -> bool:
	last_load_error = ""
	var data = load_blueprint(SCRATCH_PATH)
	if data.is_empty():
		return false

	var hull_type = data.get("hull_type", "medium_hull")
	if not ModuleCatalogScript.hull_exists(hull_type):
		last_load_error = "Couldn't restore your design: hull '%s' is not installed." % hull_type
		_show_toast(last_load_error, true)
		_set_scratch_restore_flag(false)
		return false

	var root = get_node_or_null("/root/MainLab")
	if not root:
		return false

	if root.has_method("clear_hull"):
		root.clear_hull()

	var new_hull = reconstruct_vehicle(data, root, true)
	if not new_hull:
		_set_scratch_restore_flag(false)
		return false
	root.hull = new_hull

	# reconstruct_vehicle() rebuilds geometry, not identity - without this
	# the restored design forgets which saved blueprint it came from and a
	# subsequent Save would fork a duplicate.
	if data.get("id", "") != "":
		new_hull.set_meta("blueprint_id", data["id"])
	if data.get("name", "") != "":
		new_hull.set_meta("blueprint_name", data["name"])

	get_tree().call_group("stat_ui", "update_stats", new_hull)
	get_tree().call_group("stat_ui", "sync_hull_ui", new_hull)
	_set_scratch_restore_flag(false)
	return true


func _set_scratch_restore_flag(value: bool) -> void:
	var data = load_blueprint(SCRATCH_PATH)
	if data.is_empty():
		return
	data["pending_lab_restore"] = value
	var f = FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func clear_scratch() -> void:
	if FileAccess.file_exists(SCRATCH_PATH):
		DirAccess.remove_absolute(SCRATCH_PATH)


func _generate_blueprint_id() -> String:
	return "bp_%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]

# named_only: restrict the result to designs the player deliberately named.
#
# Match setup and the in-match production roster pass true, because those are
# "which of my designs go into battle" lists and an unnamed design isn't a
# choice the player made. The Blueprint Library panel passes false, because
# it is the file manager - it has to show unnamed leftovers so they can be
# renamed (which promotes them) or deleted.
#
# Nothing is hidden permanently and nothing is deleted: pre-existing
# "Untitled Design" files stay on disk and stay visible in the Library.
func list_blueprints(named_only: bool = false) -> Array:
	var results = []
	DirAccess.make_dir_recursive_absolute("user://blueprints")
	
	# Load built-in default blueprints first
	var default_dir = DirAccess.open("res://assets/blueprints/default_roster")
	if default_dir:
		default_dir.list_dir_begin()
		var file_name = default_dir.get_next()
		while file_name != "":
			if not default_dir.current_is_dir() and file_name.ends_with(".json"):
				var data = load_blueprint("res://assets/blueprints/default_roster/" + file_name)
				if not data.is_empty() and (not named_only or is_named(data.get("name", ""))):
					results.append({
						"id": data.get("id", file_name.get_basename()),
						"name": data.get("name", "Untitled Design"),
						"hull_type": data.get("hull_type", "medium_hull"),
						"faction": data.get("faction", "industrialists"),
						"modified_unix": data.get("modified_unix", 0),
						"path": "res://assets/blueprints/default_roster/" + file_name,
						"read_only": true
					})
			file_name = default_dir.get_next()
		default_dir.list_dir_end()
	
	# Load user blueprints
	var dir = DirAccess.open("user://blueprints")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var data = load_blueprint("user://blueprints/" + file_name)
				if not data.is_empty() and (not named_only or is_named(data.get("name", ""))):
					results.append({
						"id": data.get("id", file_name.get_basename()),
						"name": data.get("name", "Untitled Design"),
						"hull_type": data.get("hull_type", "medium_hull"),
						"faction": data.get("faction", "industrialists"),
						"modified_unix": data.get("modified_unix", 0),
						"path": "user://blueprints/" + file_name,
						"read_only": false
					})
			file_name = dir.get_next()
		dir.list_dir_end()
		
	results.sort_custom(func(a, b): return a["modified_unix"] > b["modified_unix"])
	return results

func delete_blueprint(id: String) -> void:
	var path = "user://blueprints/%s.json" % id
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("Deleted blueprint: ", id)

func rename_blueprint(id: String, new_name: String) -> bool:
	var path = "user://blueprints/%s.json" % id
	var data = load_blueprint(path)
	if data.is_empty():
		return false

	# Refuse the placeholder here too, and stop ASSIGNING it on a blank
	# name. Rename is the promotion path for an existing unnamed design -
	# renaming one back to "Untitled Design" (or clearing the field, which
	# used to silently write the placeholder) would demote it out of the
	# roster with no indication that anything had happened.
	if not is_named(new_name):
		_show_toast("Pick a real name - '%s' isn't one." % PLACEHOLDER_NAME, true)
		return false

	data["name"] = new_name.strip_edges()
	data["modified_unix"] = Time.get_unix_time_from_system()
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func _resolve_blueprint_path(id: String) -> String:
	var user_path = "user://blueprints/%s.json" % id
	if FileAccess.file_exists(user_path):
		return user_path
	var res_path = "res://assets/blueprints/default_roster/%s.json" % id
	if FileAccess.file_exists(res_path):
		return res_path
	return user_path

func duplicate_blueprint(id: String) -> String:
	var path = _resolve_blueprint_path(id)
	var data = load_blueprint(path)
	if data.is_empty():
		return ""
	var new_id = _generate_blueprint_id()
	data["id"] = new_id
	data["name"] = str(data.get("name", "Untitled Design")) + " (Copy)"
	data["modified_unix"] = Time.get_unix_time_from_system()
	var json_string = JSON.stringify(data, "\t")
	var file = FileAccess.open("user://blueprints/%s.json" % new_id, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	return new_id

func load_blueprint_into_designer(id: String) -> bool:
	last_load_error = ""
	var path = _resolve_blueprint_path(id)
	var data = load_blueprint(path)
	if data.is_empty():
		print("Could not load blueprint for designer: ", id)
		last_load_error = "Couldn't load that blueprint - the save file may be corrupted."
		return false

	# Hard-fail, not a soft fallback: a blueprint whose hull_type isn't
	# installed (mod uninstalled, typo, hand-edited save) must refuse to
	# load rather than reconstruct with substitute/wrong data. Checked here,
	# BEFORE reconstruct_vehicle() runs at all, so we can name the specific
	# missing hull in the message the player actually sees - reconstruct_vehicle()
	# itself also refuses (returns null) as a second line of defense for
	# every other caller (skirmish spawns, battlefield, defense buildings),
	# but only this path can say exactly which design and which hull.
	var hull_type = data.get("hull_type", "medium_hull")
	if not ModuleCatalogScript.hull_exists(hull_type):
		var bp_name = data.get("name", "Untitled Design")
		last_load_error = "Can't load '%s': hull '%s' is not installed. Reinstall the mod that adds it, or choose a different design." % [bp_name, hull_type]
		_show_toast(last_load_error, true)
		return false

	var root = get_node("/root/MainLab")
	if not root:
		return false

	# A save written by a NEWER game version than this one may use a schema
	# this build doesn't fully understand - warn but still attempt the load
	# (best effort) rather than hard-block, since there's nothing else
	# constructive to do with an otherwise-valid file for a single-player beta.
	var save_version = data.get("version", CURRENT_BLUEPRINT_VERSION)
	if save_version > CURRENT_BLUEPRINT_VERSION:
		_show_toast("This design was saved by a newer version - some parts may not load correctly.", true)
	elif save_version < CURRENT_BLUEPRINT_VERSION:
		# The OLDER direction was previously unchecked entirely, so a stale
		# design loaded silently with no indication anything was wrong. That
		# matters now: v1 designs placed their modules against the previous
		# generation of hull geometry, so on the rebuilt hulls (see
		# data/hull_assemblies/ and tools/bake_hull_roster.gd) mounts can sit
		# slightly off the surface. Deliberately a warning rather than a hard
		# refusal, matching the existing best-effort philosophy above - the
		# design is still mostly usable and hard-blocking would strand it with
		# no recourse.
		_show_toast("This design predates the hull rebuild - weapon mounts may need repositioning.", true)

	if root.has_method("clear_hull"):
		root.clear_hull()

	var new_hull = reconstruct_vehicle(data, root, true)
	root.hull = new_hull

	get_tree().call_group("stat_ui", "update_stats", new_hull)
	get_tree().call_group("stat_ui", "sync_hull_ui", new_hull)
	return true

func load_blueprint(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		print("Blueprint file not found: ", file_path)
		return {}
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
		
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error == OK:
		var data = json.get_data()
		if typeof(data) == TYPE_DICTIONARY:
			return data
	else:
		print("JSON Parse Error: ", json.get_error_message(), " in ", json_string, " at line ", json.get_error_line())
	return {}

func reconstruct_vehicle(blueprint_data: Dictionary, parent_node: Node3D, is_designer: bool = false, match_faction_override: String = "") -> Node3D:
	if blueprint_data.is_empty():
		return null

	var ModuleCatalog = preload("res://scripts/module_catalog.gd")
	var ModuleData = preload("res://scripts/module_data.gd")

	var hull_type = blueprint_data.get("hull_type", "medium_hull")

	# Hard-fail, not ModuleCatalog.get_module_data()'s always-succeeds
	# fallback (which returns basic_cannon's WEAPON data for an unknown
	# id - previously latent since every built-in hull id always existed,
	# now a real, easy-to-hit scenario the moment hulls are moddable).
	# Refusing here (not just in the Design Lab's own Load button) covers
	# every other caller too - skirmish roster spawns, battlefield, defense
	# buildings - all of which already null-check this return value.
	if not ModuleCatalog.hull_exists(hull_type):
		push_warning("BlueprintManager: refusing to reconstruct '%s' - hull '%s' is not installed" % [blueprint_data.get("name", "Untitled Design"), hull_type])
		return null

	var catalog_data = ModuleCatalog.get_module_data(hull_type)

	var hull
	if is_designer:
		hull = StaticBody3D.new()
		hull.collision_layer = 1
		hull.collision_mask = 0
	else:
		hull = Node3D.new()
	hull.name = "Hull"
	
	# Set metadata
	hull.set_meta("base_hull_size", catalog_data.get("size", Vector3.ONE))
	var hull_scale_dict = blueprint_data.get("hull_scale", {"x": 1.0, "y": 1.0, "z": 1.0})
	var hull_scale = Vector3(hull_scale_dict.x, hull_scale_dict.y, hull_scale_dict.z)
	hull.set_meta("hull_scale", hull_scale)
	hull.set_meta("type_id", hull_type)
	
	var armor_thick = blueprint_data.get("armor_thickness", 1.0)
	var armor_mat_name = blueprint_data.get("armor_material", "hardened_steel")
	# Match faction overrides the blueprint's own saved tag entirely - both
	# stats (hull.set_meta("faction") below, read by battle_unit.gd's passive
	# lookups) and looks (HullMaterialBuilder/Greebles/Decals below all take
	# this same faction_name). Chris's explicit resolution of FABLE_REVIEW
	# 1.7: whichever faction was selected in the Design Lab while designing
	# has zero effect once a design is actually in a match - only real,
	# non-designer callers pass a non-empty override (skirmish spawns,
	# manufactory production, defense placement); the Design Lab's own
	# preview reconstructions (is_designer=true) never do, so a player can
	# still preview/tag a faction while designing without it sticking.
	var faction_name = blueprint_data.get("faction", "industrialists")
	if match_faction_override != "":
		faction_name = match_faction_override
	var nose_taper = blueprint_data.get("nose_taper", 1.0)
	hull.set_meta("armor_thickness", armor_thick)
	hull.set_meta("armor_material", armor_mat_name)
	hull.set_meta("faction", faction_name)
	hull.set_meta("nose_taper", nose_taper)
	hull.set_meta("blueprint_id", blueprint_data.get("id", ""))
	hull.set_meta("blueprint_name", blueprint_data.get("name", "Untitled Design"))

	# Bulk size based on thickness
	var armor_bulk = Vector3(1.0 + (armor_thick - 1.0) * 0.15, 1.0 + (armor_thick - 1.0) * 0.15, 1.0)

	# Re-create Hull's MeshInstance3D. Prefer the authored .glb (matches what
	# the Design Lab shows via module_placer.gd's update_hull_appearance())
	# over a plain box - this was previously always a box regardless of
	# authored-mesh availability, meaning every loaded/battle-spawned hull
	# looked different from how it was designed. Found while wiring up the
	# nose-taper hull deform (MOUNTING_AND_ARMOR_SPEC.md #4): without this
	# fix, a tapered nose would only ever be visible in the Design Lab and
	# silently vanish the moment the design was saved, loaded, or fielded.
	# PhysicsMesh (re-use the physical mesh, as a renamed copy)
	var phys_mesh = MeshInstance3D.new()
	phys_mesh.name = "PhysicsMesh"
	var authored_hull_mesh = MeshAssetLoader.get_hull_mesh(hull_type)
	if authored_hull_mesh:
		# nose_taper removed with interceptor_hull - hook point for future per-hull mesh deform
		phys_mesh.mesh = authored_hull_mesh

		# Shared with module_placer.gd's update_hull_appearance() so a design
		# looks and collides identically whether it was just built in the lab
		# or reconstructed from a saved blueprint. These two used to compute
		# the orientation and fit separately and disagree.
		var fit = ModuleCatalogScript.get_hull_mesh_fit(hull_type, authored_hull_mesh, hull_scale * armor_bulk)
		phys_mesh.rotation = fit["rotation"]
		phys_mesh.scale = fit["scale"]
		phys_mesh.position = fit["position"]
	else:
		var box = BoxMesh.new()
		box.size = catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk
		phys_mesh.mesh = box

	# Never drawn - it duplicates the visual MeshInstance3D exactly, so
	# showing it (which the designer used to do) only produced z-fighting
	# against an untextured copy of the same hull.
	phys_mesh.visible = false
	hull.add_child(phys_mesh)

	# MeshInstance3D (visual mesh, renamed/copied visual representation)
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	mesh_inst.mesh = phys_mesh.mesh
	mesh_inst.scale = phys_mesh.scale
	mesh_inst.rotation = phys_mesh.rotation
	mesh_inst.position = phys_mesh.position
	hull.add_child(mesh_inst)

	HullMaterialBuilderScript.apply_hull_materials(mesh_inst, faction_name)
	HullGreeblesScript.apply_greebles(hull, faction_name, catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk)
	ArmorGreeblesScript.apply(hull, "", catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk)
	HullDecalsScript.apply_decals(hull, faction_name, catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk)
	
	# Re-create Hull's CollisionShape3D (only in designer)
	if is_designer:
		# Same shape the Design Lab builds for a freshly placed hull (see
		# module_placer.gd's _place_hull_from_ui): an axis-aligned box of the
		# catalog size, NOT rotated to match the mesh's orientation
		# correction. This used to be a convex hull of the authored mesh
		# instead, which meant `shape is BoxShape3D` was false and every
		# caller reading the hull's dimensions off this shape
		# (update_locomotion, armor auto-fit, _reclassify_module_after_drag)
		# silently fell back to a hardcoded 4 x 1 x 6 - so a loaded blueprint
		# mounted its wheels and armor to different dimensions than the same
		# design freshly built.
		var col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		col.scale = Vector3.ONE
		col.rotation = Vector3.ZERO
		var col_box = BoxShape3D.new()
		col_box.size = catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk
		col.shape = col_box
		hull.add_child(col)

		# The box above stays the hull's DIMENSION oracle (see the comment
		# above - update_locomotion, armor auto-fit and
		# _reclassify_module_after_drag all read their hull size off it, and
		# gizmo_3d.gd resizes it on scale). It is not the surface modules
		# should snap to: everywhere the hull curves, tapers or slopes, the
		# visible skin sits well inside it.
		#
		# module_placer.gd builds a precise trimesh HullSurface for a freshly
		# placed hull and on hull swap, but this designer reconstruction never
		# did - so a LOADED blueprint had only the box, and every module
		# dropped onto it snapped to the bounding shell instead of the hull you
		# can see. Same mesh instance the visuals use, so the surface traced is
		# the surface drawn.
		HullSurfaceScript.rebuild(hull, mesh_inst)
	
	parent_node.add_child(hull)

	# Raise hull height if wheels are present so they touch the ground (Y=0).
	#
	# Locomotion grounding fix (test arena "vehicle slides on its belly"):
	# this used to be a standalone formula that only special-cased
	# wheels/legs/anti_grav and gave every other locomotion type (including
	# tracked_treads, rhomboid_treads, screw_drive, hover_engine) ZERO lift -
	# so a battle-spawned unit's hull (and everything mounted below it) sat
	# right at ground level, and the running-gear chassis + wheels/treads
	# module_placer.gd's update_locomotion() builds below the hull (per
	# ModuleCatalog.get_running_gear_size()) clipped straight through the
	# terrain. Now mirrors update_locomotion()'s own running-gear-aware
	# math exactly, so a design sits identically whether it was just built
	# in the Design Lab or reconstructed here for a battle spawn.
	var locomotion = blueprint_data.get("locomotion", {})
	var loc_type = locomotion.get("type_id", "")
	var settings = locomotion.get("settings", {})
	# battle_unit.gd's thrust/capacity-per-locomotion-setting math (count,
	# width, wheels_per_axle etc.) reads these two metas off the hull - never
	# set here before, so that math silently no-op'd (flat 1.0 contribution)
	# for every battle-spawned unit regardless of its locomotion tweaks; it
	# only ever worked in the Design Lab's live sidebar preview, which reads
	# the same metas off the hull it's actively editing.
	hull.set_meta("locomotion_type", loc_type)
	hull.set_meta("locomotion_settings", settings)
	var hull_size = catalog_data.get("size", Vector3.ONE) * hull_scale * armor_bulk
	var running_gear_size = Vector3.ZERO
	if ModuleCatalog.needs_running_gear(loc_type):
		running_gear_size = ModuleCatalog.get_running_gear_size(hull_size)
		var RunningGearBuilder = load("res://scripts/visual_builder.gd")
		# collision_layer 0 in battle mode (is_designer's hull is a real
		# StaticBody3D on layer 1 for click-selection; a battle-spawned hull
		# is a plain Node3D under a CharacterBody3D whose collision_mask is
		# 1 "Ground only" - a layer-1 chassis right at its own unit's feet
		# would read as terrain and the unit would perpetually push itself
		# off its own running gear). battle_unit.gd's own CollisionShape3D
		# is the real physics collider for this chassis in battle.
		var gear_layer = 1 if is_designer else 0
		var gear_body: StaticBody3D = RunningGearBuilder.build_running_gear(hull, running_gear_size, catalog_data.color, gear_layer, loc_type)
		# Flush the chassis's top against the hull's underside, same as
		# update_locomotion()'s placement.
		gear_body.position = Vector3(0, -hull_size.y / 2.0 - running_gear_size.y / 2.0, 0)

	if running_gear_size.y > 0.0:
		hull.position = Vector3(0, (catalog_data.get("size", Vector3.ONE).y * hull_scale.y) / 2.0 + running_gear_size.y, 0)
	else:
		var wheels_offset = 0.0
		if loc_type == "wheels":
			wheels_offset = 0.8 * settings.get("size", 1.0)
		elif loc_type == "legs":
			wheels_offset = 1.6 * settings.get("size", 1.0)
		hull.position = Vector3(0, (catalog_data.get("size", Vector3.ONE).y * hull_scale.y) / 2.0 + wheels_offset, 0)
	
	# Spawn modules
	var modules = blueprint_data.get("modules", [])
	for mod in modules:
		var type_id = mod.get("type_id", "")
		if type_id == "": continue

		# Same "refuse rather than silently substitute" principle as the
		# hull_exists() hard-fail above, at module granularity: an unknown
		# module type_id (hand-edited save, uninstalled future mod) is
		# SKIPPED with a warning instead of get_module_data()'s silent
		# basic_cannon-weapon-data fallback, which would quietly arm a
		# design with cannons it was never given (FABLE_REVIEW.md 3.4).
		# Skip-not-refuse at module level: losing one part degrades the
		# design visibly, refusing the whole blueprint over one bad module
		# would be harsher than the hull case warrants.
		if not ModuleCatalog.module_exists(type_id):
			push_warning("BlueprintManager: skipping unknown module '%s' in '%s'" % [type_id, blueprint_data.get("name", "Untitled Design")])
			continue

		var mod_catalog_data = ModuleCatalog.get_module_data(type_id)
		var category = mod_catalog_data.get("category", "module")
		
		var new_module = Node3D.new()
		
		var VisualBuilder = preload("res://scripts/visual_builder.gd")
		VisualBuilder.build_visual(type_id, new_module, mod_catalog_data.get("size", Vector3.ONE), mod_catalog_data.color, mod.get("tweaks", {}))
		
		if is_designer:
			var static_body = StaticBody3D.new()
			static_body.collision_layer = 2 # Modules layer
			static_body.collision_mask = 0
			static_body.position = Vector3(0, mod_catalog_data.get("size", Vector3.ONE).y / 2.0, 0)
			var collision_shape = CollisionShape3D.new()
			var col_box_mod = BoxShape3D.new()
			col_box_mod.size = mod_catalog_data.get("size", Vector3.ONE)
			collision_shape.shape = col_box_mod
			static_body.add_child(collision_shape)
			new_module.add_child(static_body)
			
			var ModulePlacerScript = preload("res://scripts/module_placer.gd")
			ModulePlacerScript._refit_module_collider(new_module)
		
		var m_data = ModuleDataResource.new()
		m_data.type_id = type_id
		m_data.module_name = mod_catalog_data.name
		m_data.category = category
		m_data.base_hp = mod_catalog_data.hp
		m_data.base_weight = mod_catalog_data.weight
		m_data.cost_metal = mod_catalog_data.metal
		m_data.cost_crystal = mod_catalog_data.crystal
		m_data.base_dps = mod_catalog_data.dps
		m_data.base_heal_rate = mod_catalog_data.get("heal_rate", 0.0)
		m_data.base_energy_capacity = mod_catalog_data.get("energy_capacity", 0.0)
		m_data.base_energy_regen = mod_catalog_data.get("energy_regen", 0.0)
		m_data.base_vision_bonus = mod_catalog_data.get("vision_bonus", 0.0)
		if mod.has("tweaks"):
			m_data.tweaks = mod["tweaks"]
		
		# Set scale
		var sc_dict = mod.get("scale", {"x": 1.0, "y": 1.0, "z": 1.0})
		var mod_scale = Vector3(sc_dict.x, sc_dict.y, sc_dict.z)
		new_module.scale = mod_scale
		m_data.scale_multiplier = mod_scale
		new_module.set_meta("module_data", m_data)
		
		# Add module to hull
		hull.add_child(new_module)
		
		# Set local position and rotation
		var pos_dict = mod.get("position", {"x": 0.0, "y": 0.0, "z": 0.0})
		new_module.position = Vector3(pos_dict.x, pos_dict.y, pos_dict.z)
		
		var rot_dict = mod.get("rotation", {"x": 0.0, "y": 0.0, "z": 0.0})
		new_module.rotation = Vector3(rot_dict.x, rot_dict.y, rot_dict.z)
		
		new_module.set_meta("yaw_offset", mod.get("yaw_offset", 0.0))
		if mod.get("mount_style", "") != "":
			new_module.set_meta("mount_style", mod["mount_style"])
		if mod.has("mount_normal"):
			var mn = mod["mount_normal"]
			new_module.set_meta("mount_normal", Vector3(mn.x, mn.y, mn.z))
		if mod.get("facet", "") != "":
			new_module.set_meta("facet", mod["facet"])
		# Absent on every blueprint written before sponsons existed, which is
		# exactly the right default. Must be set BEFORE rebuild_visual() below -
		# that is what reads it and rebuilds the blister housing.
		new_module.set_meta("sponson", bool(mod.get("sponson", false)))
		# Force mesh deformation rebuild - this is also what re-creates the
		# sponson blister (build_visual clears every visual child on entry, so
		# the housing only exists because it is rebuilt here). For a structural
		# piece it is additionally what applies the struct_scale set above.
		VisualBuilder.rebuild_visual(new_module)

		# Re-apply chirality AFTER rebuild_visual, which recreates the very
		# children the reflection is applied to. Kept in sync with
		# module_placer.gd's _apply_mirror_flip() - same module-space X
		# reflection, same "_mirrored" idempotency marker - so a design looks
		# identical whether it was just built in the lab or reconstructed
		# here for a save, a load, or a battle spawn.
		if bool(mod.get("scale_flip_x", false)):
			new_module.set_meta("scale_flip_x", true)
			_apply_mirror_flip_to(new_module)

		# PERFORMANCE_PLAN.md P4: only a battle instance's module needs this -
		# the Design Lab keeps the per-part nodes as the live-editable
		# representation (gizmo handles, tweak deformation target them
		# directly). Must run AFTER rebuild_visual and the mirror-flip above,
		# both of which need the real, un-merged sub-part nodes to work on.
		if not is_designer:
			VisualBuilder.bake_module_visual(new_module)

	# GROUND CONTACT, measured from the locomotion geometry that now exists.
	#
	# This is the fix for "the locomotors fall through the ground in the test
	# arena, leaving the vehicles sliding around on their belly" (Chris,
	# 2026-08-03). The provisional lift set before the module loop is the OLD
	# standalone formula, and it is wrong in three separate ways:
	#
	#  1. It only special-cases wheels and legs. Every other ground type -
	#     tracked_treads, screw_drive, half_track, rocker_bogie,
	#     pontoon_wheels, hover_engine - gets hull_height/2 and no ride height
	#     at all, so its running gear starts at or below the ground plane.
	#  2. Its two constants read settings["size"], but wheels store
	#     "wheel_size" and legs store "leg_length" - "size" is never present,
	#     so both silently fall back to 1.0 and the lift ignores the tweak it
	#     is supposed to track.
	#  3. Even at its best it is a hand-tuned guess. module_placer.gd stopped
	#     guessing (see its own GROUND CONTACT block): measured against the
	#     reference hull, wheels floated 0.13 above the ground, half_track
	#     0.30, pontoon_wheels 0.28, and legs sank 0.31 THROUGH it.
	#
	# That formula was only ever reachable as a fallback for when there was no
	# running-gear slab to measure instead - and dropping the slab
	# (ModuleCatalog.needs_running_gear() is now always false, per Chris
	# 2026-08-02) made the fallback the only path, which is what re-exposed it.
	#
	# So: mirror module_placer.gd exactly, by calling the same static helper it
	# uses. The hull rises until the lowest piece of running gear sits on y=0,
	# which is the invariant the rest of the movement code assumes - a ground
	# unit's ORIGIN is its ground contact point, which is what lets both the
	# analytic terrain snap and is_on_floor() put it at the right height.
	if ModuleCatalog.locomotion_touches_ground(loc_type):
		var lowest := INF
		for child in hull.get_children():
			if not child.has_meta("module_data"):
				continue
			var child_data = child.get_meta("module_data")
			if child_data == null or child_data.category != "locomotion":
				continue
			var wb: AABB = VisualBuilderScript.measure_visual_bounds(child)
			if wb.size.length_squared() <= 0.0:
				continue
			lowest = minf(lowest, child.position.y + wb.position.y * child.scale.y)
		if lowest < INF:
			# Never BELOW the hull's own underside. The lift puts the lowest
			# running gear on the contact plane, but the hull is part of the
			# vehicle too: if a design's locomotion does not actually reach past
			# the hull's bottom face, lifting by the gear alone leaves the hull
			# itself dipping through the ground.
			#
			# In a battle that is not merely a cosmetic problem. A unit's
			# collision_mask includes layer 1 (ground), so a hull sunk into the
			# floor makes move_and_slide() spend every frame depenetrating it -
			# the same pathology battle_unit.gd documents for a flyer flown
			# inside a hill, where physics went from 2.38ms to 15.57ms and the
			# unit stopped going where it was sent.
			#
			# Found by the headless suite, not by inspection: several navigation
			# suites started reporting units that "barely moved" or were "stuck
			# against the building". Their fixture mounts a tracked_treads
			# module at local y=-0.4 inside a 1.0-tall hull, so the gear never
			# reaches the hull's own underside and the measured lift put the
			# hull bottom at -0.109.
			# hull_size is the catalog size already multiplied by hull_scale and
			# armor_bulk - the same figure the running-gear sizing above uses,
			# and what battle_unit.gd builds its hull collider from. Taking the
			# half-height from anywhere else is how module_placer.gd's copy of
			# this floor ended up reading a fallback catalog entry instead of
			# the hull in front of it.
			hull.position.y = maxf(-lowest, hull_size.y / 2.0)

	return hull

# Delegates to ModuleMirror so the reconstruct path and the live-placement
# path cannot drift apart again. This copy previously omitted the cull-mode
# compensation, so every mirrored module rendered inside-out once it was
# loaded, tested, or spawned into a match.
func _apply_mirror_flip_to(module: Node3D):
	ModuleMirrorScript.apply(module)
