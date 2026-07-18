extends SceneTree
# One-off migration tool (hull modding pass, 2026-07-18): dumps every
# category=="hull" entry out of the CURRENT hardcoded ModuleCatalog.get_catalog()
# as JSON sidecar files under res://assets/models/hulls/<id>.json, and also
# writes a golden snapshot to the scratchpad for post-migration regression
# diffing. Run once, before the hardcoded hull entries are deleted from
# module_catalog.gd. Not part of the shipped game.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script tools/export_hull_sidecars.gd

const ModuleCatalog = preload("res://scripts/module_catalog.gd")

# Fields written only when present/non-default, matching HULL_MODDING_PLAN.md
# §1's "optional fields missing -> apply existing getter defaults" contract -
# a sparse sidecar that omits a default-valued field must still round-trip
# to the exact same value via the loader's own defaulting, so it's safe (and
# more honest about what's actually authored vs. defaulted) to omit them here.
const OPTIONAL_DEFAULTS = {
	"dps": 0.0,
	"is_foundation": false,
	"base_energy": 0.0,
	"base_vision": 20.0,
	"draught": 0.5,
	"underside_y_bias": 0.0,
	"turreted_capable": true,
}

func _init():
	var catalog = ModuleCatalog.get_catalog()
	var golden = {}
	var count = 0
	DirAccess.make_dir_recursive_absolute("res://assets/models/hulls")
	for type_id in catalog.keys():
		var data = catalog[type_id]
		if data.get("category", "") != "hull":
			continue
		var out = {
			"name": data["name"],
			"hp": data["hp"],
			"weight": data["weight"],
			"metal": data["metal"],
			"crystal": data["crystal"],
			"size": [data["size"].x, data["size"].y, data["size"].z],
			"color": [data["color"].r, data["color"].g, data["color"].b, data["color"].a],
		}
		for key in OPTIONAL_DEFAULTS.keys():
			if data.has(key) and data[key] != OPTIONAL_DEFAULTS[key]:
				out[key] = data[key]

		golden[type_id] = out

		var json_string = JSON.stringify(out, "\t")
		var path = "res://assets/models/hulls/%s.json" % type_id
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(json_string)
			file.close()
			print("Wrote ", path)
			count += 1
		else:
			printerr("FAILED to write ", path)

	var golden_path = "user://hull_golden_snapshot.json"
	var gf = FileAccess.open(golden_path, FileAccess.WRITE)
	if gf:
		gf.store_string(JSON.stringify(golden, "\t"))
		gf.close()
		print("Wrote golden snapshot to ", ProjectSettings.globalize_path(golden_path))

	print("\nExported %d hull sidecars." % count)
	quit()
