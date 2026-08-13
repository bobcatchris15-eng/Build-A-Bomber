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
	if not ENTRIES.has(prop_id):
		push_warning("UIPropRegistry: no entry for prop_id '%s' (known: %s)" % [prop_id, str(ENTRIES.keys())])
		return {}
	return ENTRIES[prop_id]


# Predicate: is this prop_id registered? Use before attach() when the
# caller cannot recover from a missing prop.
static func has(prop_id: String) -> bool:
	return ENTRIES.has(prop_id)


# Lists every registered prop_id. Useful for tests and for the audit
# tool Phase 12 will add ("every UI prop has a baked texture set").
static func ids() -> Array:
	return ENTRIES.keys()


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
