extends SceneTree
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")
const HullLoader = preload("res://scripts/hull_loader.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")

const CONVERTED = ["light_hull","medium_hull","heavy_hull","assault_hull","flying_wing_hull","airship_hull"]
const UNCONVERTED = ["pillbox_foundation","tower_foundation","fortress_wall_foundation"]
const PRIMITIVE_HULLS = ["the_cube","the_orb","the_rod","the_slab"]

func _init() -> void:
	HullLoader.reset_cache_for_tests()
	var all_ok := true
	var total := 0

	print("=== converted (must resolve to baked .res) ===")
	for id in CONVERTED:
		var m: Mesh = MeshAssetLoader.get_hull_mesh(id)
		var cat := ModuleCatalog.get_module_data(id)
		if m == null:
			print("  %-20s FAIL: no mesh" % id); all_ok = false; continue
		var tris := m.get_faces().size() / 3
		total += tris
		var fit := ModuleCatalog.get_hull_mesh_fit(id, m)
		var rot: Vector3 = fit["rotation"]
		var shape := m.create_trimesh_shape()
		var ok := true
		if not ModuleCatalog.hull_exists(id): ok = false
		if m.get_surface_count() != 1: ok = false
		if rot.length() > 0.01: ok = false
		if shape == null or shape.get_faces().is_empty(): ok = false
		if not cat.has("hp") or float(cat["hp"]) <= 0.0: ok = false
		print("  %-20s %5d tris  fit_rot=%s  fit_scale=(%.2f,%.2f,%.2f)  hp=%s size=%s  %s" % [
			id, tris, "identity" if rot.length() < 0.01 else str(rot),
			fit["scale"].x, fit["scale"].y, fit["scale"].z,
			cat.get("hp"), cat.get("size"), "OK" if ok else "FAIL"])
		if not ok: all_ok = false

	print("=== unconverted (must still load their Blender .glb) ===")
	for id in UNCONVERTED:
		var m: Mesh = MeshAssetLoader.get_hull_mesh(id)
		var tris := (m.get_faces().size() / 3) if m else 0
		total += tris
		var ok := m != null and tris > 0 and ModuleCatalog.hull_exists(id)
		print("  %-28s %5d tris  %s" % [id, tris, "OK" if ok else "FAIL"])
		if not ok: all_ok = false

	print("=== primitive_shape hulls (no mesh file by design) ===")
	for id in PRIMITIVE_HULLS:
		var m: Mesh = MeshAssetLoader.get_hull_mesh(id)
		var ok := m != null and ModuleCatalog.hull_exists(id)
		print("  %-20s %s  %s" % [id, m, "OK" if ok else "FAIL"])
		if not ok: all_ok = false

	print("")
	print("roster total: %d tris (old Blender roster was 4628)" % total)
	print("RESULT: ", "PASS" if all_ok else "FAIL")
	quit(0 if all_ok else 1)
