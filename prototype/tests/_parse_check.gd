extends SceneTree

# Per-file parse check across every file the barrel_length + protectedness +
# armor cleanup touched in this session (commits 7cb6ee0 .. 79cc971).
# Surfaces any inference / type errors that survive commit.
const FILES := [
	"res://scripts/auto_weapon.gd",
	"res://scripts/lab_document.gd",
	"res://scripts/module_catalog.gd",
	"res://scripts/module_data.gd",
	"res://scripts/ui/tweak_stations.gd",
	"res://scripts/visual_builder.gd",
	"res://scripts/weapon_range.gd",
	"res://tools/author_default_designs.gd",
	"res://scripts/hull_facets.gd",  # reported error, not touched by us
	"res://scripts/blueprint_manager.gd",  # dep of hull_facets via lab_document
]

func _init() -> void:
	var failed := 0
	for path in FILES:
		# Use ResourceLoader.load with CACHE_MODE_IGNORE so a previous failure
		# in the engine's compile cache doesn't mask a fresh parse result.
		var script: GDScript = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if script == null:
			print("[FAIL] %s" % path)
			failed += 1
		else:
			print("[OK]   %s" % path)
	if failed > 0:
		print("PARSE FAILED: %d file(s)" % failed)
		quit(1)
	else:
		print("ALL OK")
		quit(0)
