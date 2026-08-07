extends SceneTree
# METAL vs CRYSTAL, separately.
#
# The cost-unit model (metal + 2*crystal) says the economy is balanced. It also
# assumes the two pools are interchangeable, and they are not - you cannot pay a
# metal bill with crystal. This prints the two draws and the two incomes side by
# side, because the AI is stalling at 0 metal while sitting on 155 crystal.

const DesignCostingScript = preload("res://scripts/battle/economy/design_costing.gd")
const MapCatalogScript = preload("res://scripts/map_catalog.gd")


func _init():
	print("=== PER-POOL DRAW (one production line) ===")
	print("  %-24s %6s %8s %7s %9s %9s" % ["design", "metal", "crystal", "time", "metal/s", "cryst/s"])
	var total_m := 0.0
	var total_c := 0.0
	var n := 0
	for name in ["rattler_scout", "bulwark_mbt", "warden_aa", "breaker_td",
			"ore_trucker", "tide_corvette", "raptor_striker", "longarm_spg"]:
		var path := "res://data/loadout/%s.json" % name
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var d = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var cost: Vector2i = DesignCostingScript.blueprint_cost(d)
		var t: float = DesignCostingScript.build_time_for_cost(cost)
		total_m += float(cost.x) / t
		total_c += float(cost.y) / t
		n += 1
		print("  %-24s %6d %8d %7.1f %9.2f %9.2f"
			% [str(d.get("name", name)), cost.x, cost.y, t, float(cost.x) / t, float(cost.y) / t])
	print("  %-24s %6s %8s %7s %9.2f %9.2f" % ["MEAN", "", "", "", total_m / n, total_c / n])

	print("")
	print("=== WHAT THE MAPS OFFER ===")
	for map_id in MapCatalogScript.get_map_ids():
		var m: Dictionary = MapCatalogScript.get_map(map_id)
		var metal_amt := 0
		var crystal_amt := 0
		for node_data in m.get("resource_nodes", []):
			if str(node_data.get("type", "metal")) == "crystal":
				crystal_amt += int(node_data.get("amount", 0))
			else:
				metal_amt += int(node_data.get("amount", 0))
		var total: float = float(metal_amt + crystal_amt)
		if total <= 0.0:
			continue
		print("  %-22s metal %6d (%2.0f%%)   crystal %6d (%2.0f%%)"
			% [map_id, metal_amt, 100.0 * metal_amt / total, crystal_amt, 100.0 * crystal_amt / total])
	quit(0)
