extends SceneTree
# Balance report (ENERGY_AND_BALANCE_SPEC.md #6): computes a value-per-cost
# score for every catalog entry, grouped by category, and flags outliers -
# a defensible starting point for balance tuning, not an authority. Run
# with:
#   Godot_v4.3-stable_win64_console.exe --headless --script tools/balance_report.gd
#
# DPS and HP and Energy capacity are fundamentally different currencies -
# the weights below (DPS_WEIGHT, HP_WEIGHT, etc.) are a judgment call, not
# a derived truth. Treat the output as "here's what the numbers currently
# imply," not "here's the correct answer."

const ModuleCatalog = preload("res://scripts/module_catalog.gd")

# Value weights: how much each stat "counts" toward a module's combat/
# utility value. DPS is weighted highest since it's the primary driver of
# a weapon's purpose; HP is a secondary survivability bonus (mounted
# modules die to subsystem-stripping, so a tankier module module is worth
# something even at equal DPS). Energy stats use their own weights since
# they're not directly comparable to DPS/HP at all.
const DPS_WEIGHT: float = 3.0
# Slightly below DPS_WEIGHT - healing is situational (only matters when
# something's already hurt) where damage always counts, per the "shaky
# areas" note this tool already prints. Added once repair_array got its
# own dedicated heal_rate stat (previously reused dps, which accidentally
# gave it full DPS_WEIGHT - this is more honest, not less generous).
const HEAL_RATE_WEIGHT: float = 2.5
const HP_WEIGHT: float = 0.3
const ENERGY_CAPACITY_WEIGHT: float = 1.2
const ENERGY_REGEN_WEIGHT: float = 4.0

# Cost weights: Crystal starts scarcer than Metal (150 vs 450 in the
# default Skirmish economy) and is used more sparingly across the catalog,
# so it counts double toward "true cost." Weight already has an in-fiction
# cost via speed reduction (recalculate_move_speed divides thrust by total
# weight) - a small tax acknowledges it without double-counting.
const CRYSTAL_WEIGHT: float = 2.0
const WEIGHT_TAX: float = 0.05

func _init():
	print("\n==============================================")
	print("    BUILD-A-BOMBER BALANCE REPORT")
	print("==============================================\n")

	var catalog = ModuleCatalog.get_catalog()
	var by_category = {}
	for type_id in catalog.keys():
		var data = catalog[type_id]
		var category = data.get("category", "module")
		if not by_category.has(category):
			by_category[category] = []
		by_category[category].append({"type_id": type_id, "data": data})

	for category in by_category.keys():
		_report_category(category, by_category[category])

	print("\n--- Known-shaky areas (flagged, not fixed) ---")
	print("* Locomotion/hull value-per-cost is inherently hard to quantify:")
	print("  their real value is mobility/capacity, not a stat this model captures.")
	print("  Their scores below are HP-only and should be read as low-confidence.")
	print("* Energy weapons have a real cost dimension this model doesn't capture:")
	print("  capacitor drain (energy_cost_per_shot in auto_weapon.gd) limits how")
	print("  long a weapon can sustain fire, independent of its Metal/Crystal price.")
	print("  A cheap-to-build energy weapon that drains the capacitor instantly")
	print("  isn't actually cheap to USE - this report can't see that tradeoff.")
	print("* repair_array now has its own heal_rate stat (HEAL_RATE_WEIGHT, set")
	print("  slightly below DPS_WEIGHT since healing is situational and damage")
	print("  isn't) - still an estimate, not a measured playtest value.")

	quit(0)

# Extracted as a static function (not inlined in _report_category) so
# run_tests.gd can call it directly as a regression smoke-check without
# running this whole script as the SceneTree main loop.
static func compute_score(data: Dictionary) -> Dictionary:
	var value = data.get("dps", 0.0) * DPS_WEIGHT + data.get("hp", 0.0) * HP_WEIGHT
	value += data.get("heal_rate", 0.0) * HEAL_RATE_WEIGHT
	value += data.get("energy_capacity", 0.0) * ENERGY_CAPACITY_WEIGHT
	value += data.get("energy_regen", 0.0) * ENERGY_REGEN_WEIGHT
	var cost = float(data.get("metal", 0)) + float(data.get("crystal", 0)) * CRYSTAL_WEIGHT + data.get("weight", 0.0) * WEIGHT_TAX
	var ratio = value / cost if cost > 0.001 else 0.0
	return {"value": value, "cost": cost, "ratio": ratio}

func _report_category(category: String, entries: Array):
	print("### ", category.to_upper(), " ###")
	var scored = []
	for e in entries:
		var s = compute_score(e.data)
		scored.append({"type_id": e.type_id, "value": s.value, "cost": s.cost, "ratio": s.ratio})

	scored.sort_custom(func(a, b): return a.ratio > b.ratio)

	var avg_ratio = 0.0
	for s in scored:
		avg_ratio += s.ratio
	avg_ratio /= max(1, scored.size())

	for s in scored:
		var flag = ""
		if s.ratio > avg_ratio * 1.5:
			flag = "  <-- high value/cost, consider a cost or nerf pass"
		elif avg_ratio > 0.001 and s.ratio < avg_ratio * 0.5:
			flag = "  <-- low value/cost, consider a buff or discount"
		print("  %-22s value=%6.1f  cost=%6.1f  value/cost=%5.2f%s" % [s.type_id, s.value, s.cost, s.ratio, flag])
	print("  (category average value/cost: %.2f)\n" % avg_ratio)
