class_name DesignCosting
extends RefCounted
# What a design costs to build, and how long it takes.
#
# Same formulas as the old runtime's skirmish.gd:1277-1307, moved out of the
# match controller so the build bar, the AI and the production queue can all ask
# without one of them holding a reference to the whole match. That coupling is
# why the old build bar could only exist inside skirmish.gd.
#
# The numbers are unchanged. Hull cost includes armour material, thickness and
# hull scale - all three used to be free, which made a maximum-armour super-heavy
# cost the same as a bare one.

const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")
const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")


static func blueprint_cost(data: Dictionary) -> Vector2i:
	var hull_type: String = data.get("hull_type", "medium_hull")
	var sc: Dictionary = data.get("hull_scale", {"x": 1.0, "y": 1.0, "z": 1.0})
	var hull_cost: Vector2i = ModuleCatalog.compute_hull_cost(
		hull_type,
		data.get("armor_thickness", 1.0),
		data.get("armor_material", "hardened_steel"),
		Vector3(sc.x, sc.y, sc.z))
	var metal: int = hull_cost.x
	var crystal: int = hull_cost.y
	for mod in data.get("modules", []):
		var type_id: String = mod.get("type_id", "")
		# An unknown module is skipped by reconstruct_vehicle() too, so charging
		# for it would bill the player for something that never gets built.
		if not ModuleCatalog.module_exists(type_id):
			continue
		var cat: Dictionary = ModuleCatalog.get_module_data(type_id)
		var md = ModuleDataScript.new()
		md.type_id = type_id
		md.cost_metal = cat.metal
		md.cost_crystal = cat.crystal
		md.tweaks = mod.get("tweaks", {})
		var mod_scale: Dictionary = mod.get("scale", {"x": 1.0, "y": 1.0, "z": 1.0})
		md.scale_multiplier = Vector3(mod_scale.x, mod_scale.y, mod_scale.z)
		var cost: Vector2i = md.get_cost()
		metal += cost.x
		crystal += cost.y
	return Vector2i(metal, crystal)


# Crystal counts double: it is the scarcer resource, so a crystal-heavy design
# should cost tempo as well as money.
static func build_time_for_cost(cost: Vector2i) -> float:
	return clampf((cost.x + cost.y * 2) * 0.05, 3.0, 40.0)


# Which of the five queues a unit design comes off, from its hull's weight tier.
static func queue_for_design(data: Dictionary) -> String:
	var tier: String = ModuleCatalog.get_hull_size_tier(data.get("hull_type", "medium_hull"))
	return BuildingCatalogScript.queue_for_hull_tier(tier)
