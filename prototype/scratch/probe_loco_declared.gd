extends SceneTree
# Standalone mirror of test_every_locomotion_type_is_fully_declared, so this
# specific check costs seconds instead of a full 188-suite run.
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const Layout = preload("res://scripts/locomotion_layout.gd")

func _init() -> void:
	await process_frame
	var catalog: Dictionary = ModuleCatalog.get_catalog()
	var bad := 0
	var n := 0
	for type_id in catalog:
		if catalog[type_id].get("category", "") != "locomotion":
			continue
		n += 1
		if not Layout.has_layout(type_id):
			print("NO LAYOUT: ", type_id); bad += 1
		var specs: Array = ModuleCatalog.LOCOMOTION_TWEAK_SPECS.get(type_id, [])
		if specs.size() < 2:
			print("TOO FEW TWEAKS: ", type_id, " ", specs.size()); bad += 1
		var base = ModuleCatalog.get_locomotion_contribs(type_id, {})
		if base["capacity"] <= 0.0:
			print("NO CAPACITY: ", type_id); bad += 1
		for spec in specs:
			var probe := {}
			if spec.get("type", "") == "bool":
				probe[spec["name"]] = not bool(spec.get("default", false))
			else:
				probe[spec["name"]] = float(spec.get("max", 2.0))
			var moved = ModuleCatalog.get_locomotion_contribs(type_id, probe)
			if abs(moved["thrust"] - base["thrust"]) <= 0.0001 and abs(moved["capacity"] - base["capacity"]) <= 0.0001:
				print("COSMETIC TWEAK: ", type_id, ".", spec["name"]); bad += 1
		var traits: Array = catalog[type_id].get("traits", [])
		var exempt := false
		for t in traits:
			if t in ModuleCatalog.TERRAIN_EXEMPT_TRAITS:
				exempt = true
		if exempt:
			continue
		var flat := true
		for surface in ModuleCatalog.TERRAIN_SPEED_MULTIPLIERS:
			if not ModuleCatalog.TERRAIN_SPEED_MULTIPLIERS[surface].has(type_id):
				print("NO TERRAIN ROW: ", type_id, "/", surface); bad += 1
			elif abs(float(ModuleCatalog.TERRAIN_SPEED_MULTIPLIERS[surface][type_id]) - 1.0) > 0.01:
				flat = false
		if flat and not (type_id in ModuleCatalog.TERRAIN_INTENTIONALLY_FLAT):
			print("FLAT TERRAIN: ", type_id); bad += 1
	print("checked %d locomotion types, %d problems" % [n, bad])
	quit()
