class_name UIPropRegistry
extends RefCounted
# The single source of truth for the prop-id -> mesh mapping used by
# UIPropStage and its clients (StampedButton, MeshIcon, and any future
# 3D-prop Control). Phases 2 and 3 add per-prop texture sets onto these
# entries without changing this interface; the registry stays a small
# data table rather than growing into a mesh-loading service.
#
# WHY A REGISTRY INSTEAD OF A LOAD-IN-PLACE LOOKUP: the stage has to know
# the mesh BEFORE the attached control's first draw, so it can size the
# world transform to the mesh's authored extent. A "go look at the disk"
# call inside attach() would be fine for one prop but would also couple
# the stage to ResourceLoader's failure modes. Centralising the lookup
# keeps the stage ignorant of resource loading, and keeps a missing prop
# id as a single push_warning() the caller can react to.
#
# DETERMINISM: every prop_id resolves to one entry. The mapping is
# deliberately a const dict, not a function of anything that varies at
# runtime. A reimported asset, an in-memory edit, a save override -
# none of them may change what "push_button" resolves to.

# The seven entries the hardware clients need in Phase 1. StampedButton
# uses `push_button`; MeshIcon uses the other six (toggle, rotary,
# rocker, knurled_dial, dzus_fastener, latch). Mesh paths are the actual
# filenames under prototype/assets/models/ui/. natural_size is the mesh's
# authored extent in pixels at scale 1.0; UIPropStage divides the host
# control's pixel size by it to derive a mesh scale, so the mesh fills
# the control regardless of how the Blender author chose to scale the
# mesh. Phase 2 will tune natural_size per prop by measuring the baked
# texture coverage against the mesh's projected silhouette; today's
# values are the visual targets the field is being aimed at, not
# measurements of the .glb.
const ENTRIES := {
	"push_button": {
		"mesh_path": "res://assets/models/ui/ui_push_button.glb",
		"natural_size": Vector2(100.0, 44.0),
		"albedo_path": "res://assets/textures/ui/props/push_button_albedo.png",
		"orm_path": "res://assets/textures/ui/props/push_button_orm.png",
		"height_path": "res://assets/textures/ui/props/push_button_height.png",
	},
	"toggle": {
		"mesh_path": "res://assets/models/ui/ui_toggle_switch.glb",
		"natural_size": Vector2(40.0, 40.0),
		"albedo_path": "res://assets/textures/ui/props/toggle_albedo.png",
		"orm_path": "res://assets/textures/ui/props/toggle_orm.png",
		"height_path": "res://assets/textures/ui/props/toggle_height.png",
	},
	"rotary": {
		"mesh_path": "res://assets/models/ui/ui_rotary_selector.glb",
		"natural_size": Vector2(40.0, 40.0),
		"albedo_path": "res://assets/textures/ui/props/rotary_albedo.png",
		"orm_path": "res://assets/textures/ui/props/rotary_orm.png",
		"height_path": "res://assets/textures/ui/props/rotary_height.png",
	},
	"rocker": {
		"mesh_path": "res://assets/models/ui/ui_rocker_switch.glb",
		"natural_size": Vector2(40.0, 40.0),
		"albedo_path": "res://assets/textures/ui/props/rocker_albedo.png",
		"orm_path": "res://assets/textures/ui/props/rocker_orm.png",
		"height_path": "res://assets/textures/ui/props/rocker_height.png",
	},
	"knurled_dial": {
		"mesh_path": "res://assets/models/ui/ui_knurled_dial.glb",
		"natural_size": Vector2(40.0, 40.0),
		"albedo_path": "res://assets/textures/ui/props/knurled_dial_albedo.png",
		"orm_path": "res://assets/textures/ui/props/knurled_dial_orm.png",
		"height_path": "res://assets/textures/ui/props/knurled_dial_height.png",
	},
	"dzus_fastener": {
		"mesh_path": "res://assets/models/ui/ui_dzus_fastener.glb",
		"natural_size": Vector2(40.0, 40.0),
		"albedo_path": "res://assets/textures/ui/props/dzus_fastener_albedo.png",
		"orm_path": "res://assets/textures/ui/props/dzus_fastener_orm.png",
		"height_path": "res://assets/textures/ui/props/dzus_fastener_height.png",
	},
	"latch": {
		"mesh_path": "res://assets/models/ui/ui_latch.glb",
		"natural_size": Vector2(40.0, 40.0),
		"albedo_path": "res://assets/textures/ui/props/latch_albedo.png",
		"orm_path": "res://assets/textures/ui/props/latch_orm.png",
		"height_path": "res://assets/textures/ui/props/latch_height.png",
	},
}


# PER-BUTTON TEXTURE VARIANTS (D1: "textures can be unique per button").
#
# Every id here reuses ui_push_button.glb - the shared mesh - and differs only
# in its baked texture set, which tools/generate_ui_props.py seeds from the id
# string. That is the whole of D1: one mesh, unique wear per button.
#
# The ids are slugs of the button legends. StampedButton derives the same slug
# from its own `legend` at attach time, so a call site opts in by naming its
# button, not by passing a prop id. THE TWO SLUG RULES MUST STAY IDENTICAL -
# lowercase, non-alphanumeric runs collapse to "_", leading/trailing "_"
# stripped. See _slugify() below and StampedButton._variant_prop_id().
#
# Kept as a flat slug list rather than 22 hand-written ENTRIES blocks because
# every field except the texture paths is identical to push_button's, and
# duplicating mesh_path 22 times is 22 chances to point one at the wrong .glb.
# _variant_entry() composes the full entry on demand.
#
# THIS LIST MUST MATCH generate_ui_props.py's BUTTON_LEGEND_SLUGS. A slug here
# with no baked texture resolves to missing files; a baked texture with no slug
# here is never reached. test_ui_prop_stage.gd asserts both directions.
const BUTTON_VARIANT_SLUGS: Array = [
	"back", "back_to_main_menu", "design_lab", "abandon_operation",
	"begin_operation", "commit_livery", "deploy", "randomise", "return",
	"start_match",
	"patrol", "attack_move", "stop", "set_rally", "aggressive",
	"return_fire", "hold", "hold_fire", "wedge", "line", "column", "spread",
]

const BUTTON_VARIANT_PREFIX := "btn_"
const BUTTON_VARIANT_BASE := "push_button"


# Lowercase, non-alphanumeric runs to "_", trimmed. Must agree exactly with
# StampedButton._variant_prop_id() and with the Python slugs baked into the
# texture filenames.
static func slugify(text: String) -> String:
	var out := ""
	var last_was_sep := true  # true so a leading separator is dropped
	for i in text.length():
		var c := text[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			last_was_sep = false
		elif not last_was_sep:
			out += "_"
			last_was_sep = true
	return out.trim_suffix("_")


# The composed entry for a button variant: push_button's mesh and extent, the
# variant's own textures.
static func _variant_entry(prop_id: String) -> Dictionary:
	var base: Dictionary = ENTRIES[BUTTON_VARIANT_BASE]
	return {
		"mesh_path": base["mesh_path"],
		"natural_size": base["natural_size"],
		"albedo_path": "res://assets/textures/ui/props/%s_albedo.png" % prop_id,
		"orm_path": "res://assets/textures/ui/props/%s_orm.png" % prop_id,
		"height_path": "res://assets/textures/ui/props/%s_height.png" % prop_id,
	}


# Is this prop_id one of the per-button variants?
static func is_button_variant(prop_id: String) -> bool:
	if not prop_id.begins_with(BUTTON_VARIANT_PREFIX):
		return false
	return BUTTON_VARIANT_SLUGS.has(prop_id.substr(BUTTON_VARIANT_PREFIX.length()))


# The variant prop_id for a legend, or "" if that legend has no baked set.
# Callers fall back to BUTTON_VARIANT_BASE on "".
static func variant_id_for_legend(legend: String) -> String:
	var slug := slugify(legend)
	if slug.is_empty() or not BUTTON_VARIANT_SLUGS.has(slug):
		return ""
	return BUTTON_VARIANT_PREFIX + slug


# Returns the entry for a prop_id, or an empty Dictionary if the id is
# unknown. The empty-dict-on-miss is the documented silent fallback for
# the headless test path: a screen under test can pass any string and
# get a no-op back rather than a hard error. Real screens and the stage
# both check has() first and would refuse to attach on a miss.
#
# NOT NAMED get(): Object.get() exists and the override resolves to it,
# not to a static method on this class. The Godot 4 warning ("The method
# 'get' overrides a method from native class 'Object'") is treated as
# a parse error under this project's settings.
static func entry_for(prop_id: String) -> Dictionary:
	if ENTRIES.has(prop_id):
		return ENTRIES[prop_id]
	if is_button_variant(prop_id):
		return _variant_entry(prop_id)
	push_warning("UIPropRegistry: no entry for prop_id '%s' (known: %s)" % [prop_id, str(ids())])
	return {}


# Predicate: is this prop_id registered? Use before attach() when the
# caller cannot recover from a missing prop.
static func has(prop_id: String) -> bool:
	return ENTRIES.has(prop_id) or is_button_variant(prop_id)


# Lists every registered prop_id - the seven base props plus every
# per-button variant. Useful for tests and for the Phase 12 audit
# ("every UI prop has a baked texture set").
static func ids() -> Array:
	var out: Array = ENTRIES.keys()
	for slug in BUTTON_VARIANT_SLUGS:
		out.append(BUTTON_VARIANT_PREFIX + slug)
	return out


# Reverse lookup: mesh path -> prop_id. MeshIcon needs this so a caller
# that sets `mesh_path = "res://.../ui_toggle_switch.glb"` ends up
# attached to the stage under the right prop_id without having to
# know the registry's internal naming. The mapping is derived from
# ENTRIES at script load time so the two never drift - adding a new
# prop to ENTRIES makes it discoverable here for free.
#
# NOT a const because the derivation would re-run on every engine
# boot, and the const-derivation pattern ({} = ...) is the same cost
# in disguise. A static var computed once on first read is cheaper
# than a const and just as correct.
static var _PATH_TO_ID: Dictionary = {}


static func prop_id_for_path(path: String) -> String:
	if _PATH_TO_ID.is_empty():
		for prop_id in ENTRIES:
			_PATH_TO_ID[ENTRIES[prop_id]["mesh_path"]] = prop_id
	return String(_PATH_TO_ID.get(path, ""))
