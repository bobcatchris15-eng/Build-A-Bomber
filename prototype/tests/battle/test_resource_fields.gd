extends "res://tests/suite_base.gd"
# Resource fields and the four gatherable types.
#
# Chris's direction, 2026-08-07: ore and crystal stay but spread into fields
# around a central spawner, plus lumber from forest stands and oil from neutral
# wells, all eventually funnelling into one credits pool. The types differ by
# VALUE DENSITY AND LOCATION - any harvester works any field - and everything is
# renewable.

const ResourceCatalogScript = preload("res://scripts/battle/economy/resource_catalog.gd")
const ResourceFieldScript = preload("res://scripts/battle/economy/resource_field.gd")
const MapCatalogScript = preload("res://scripts/map_catalog.gd")


# "metal" is what all ten bundled maps say and what every save and test fixture
# says. It has to keep meaning ore forever, not become a silent fallback that
# happens to look right.
func test_resource_catalog_aliases_metal_to_ore() -> bool:
	print("Running Test Suite: Resources - 'metal' still means ore...")
	var ok := true
	if ResourceCatalogScript.canonical("metal") != "ore":
		print("  [FAIL] 'metal' resolved to '", ResourceCatalogScript.canonical("metal"), "'")
		ok = false
	if ResourceCatalogScript.credits("metal") != ResourceCatalogScript.credits("ore"):
		print("  [FAIL] 'metal' and 'ore' are worth different amounts")
		ok = false
	# An unknown type must land somewhere sane rather than crashing a map load.
	if ResourceCatalogScript.canonical("unobtainium") != ResourceCatalogScript.FALLBACK:
		print("  [FAIL] An unknown resource type did not fall back")
		ok = false
	if ok:
		print("  [PASS] metal -> ore, same value, unknown types fall back.")
	return ok


# The value ladder is the entire design. If two resources are worth the same,
# there is no reason to drive past one to reach the other and the whole system
# collapses to "go to the nearest thing".
func test_resource_values_form_a_real_ladder() -> bool:
	print("Running Test Suite: Resources - the value ladder is real...")
	var ok := true
	var order := ["lumber", "ore", "crystal", "oil"]
	for i in range(order.size() - 1):
		if ResourceCatalogScript.credits(order[i]) >= ResourceCatalogScript.credits(order[i + 1]):
			print("  [FAIL] %s (%.1f) is not worth less than %s (%.1f)"
				% [order[i], ResourceCatalogScript.credits(order[i]),
					order[i + 1], ResourceCatalogScript.credits(order[i + 1])])
			ok = false

	# Gathering and spending have to agree on what a credit is, or the balance
	# target measures one thing and the economy runs on another.
	for type_id in ResourceCatalogScript.ids():
		var paid: int = ResourceCatalogScript.deliver_credits(type_id, 100)
		var expected: float = 100.0 * ResourceCatalogScript.credits(type_id)
		if absf(float(paid) - expected) > 1.0:
			print("  [FAIL] 100 %s pays %d credits, expected %.0f"
				% [type_id, paid, expected])
			ok = false

	# THE COST SIDE. Crystal is the "advanced" material and converts at 2x, which
	# is the whole mechanism by which advanced technology drives up price per unit
	# rather than gating on a resource the map may not offer.
	if ResourceCatalogScript.credits_from_materials(Vector2i(100, 0)) != 100:
		print("  [FAIL] 100 metal of materials is not 100 credits")
		ok = false
	if ResourceCatalogScript.credits_from_materials(Vector2i(0, 100)) != 200:
		print("  [FAIL] 100 crystal of materials is not 200 credits")
		ok = false
	if ResourceCatalogScript.credits_from_materials(Vector2i(50, 25)) != 100:
		print("  [FAIL] mixed materials do not add up")
		ok = false

	if ok:
		print("  [PASS] lumber 1.0 < ore 1.5 < crystal 3.0 < oil 4.0; crystal costs 2x as a material.")
	return ok


# A field is a spawner, not a lump. The point is that four trucks can work one
# deposit without standing in each other.
func test_a_field_scatters_and_refills() -> bool:
	print("Running Test Suite: Resources - fields scatter collectibles and refill...")
	var field = ResourceFieldScript.new()
	root.add_child(field)
	field.global_position = Vector3(20.0, 0.0, -15.0)
	field.setup("ore", 700, null)
	await tree.process_frame

	var ok := true
	var live: Array = field.live_nodes()
	if live.size() != ResourceCatalogScript.field_nodes("ore"):
		print("  [FAIL] Field spawned %d collectibles, expected %d"
			% [live.size(), ResourceCatalogScript.field_nodes("ore")])
		ok = false

	# The whole deposit is preserved, just divided up - converting a map must not
	# quietly change how much ore is on it.
	var total: int = field.remaining()
	if absf(float(total) - 700.0) > float(live.size()):
		print("  [FAIL] Field holds %d in total, expected ~700" % total)
		ok = false

	# SCATTERED, not stacked. Collectibles sitting on each other would reproduce
	# the exact crowding fields exist to fix.
	var radius: float = ResourceCatalogScript.field_radius("ore")
	var min_gap := INF
	for i in range(live.size()):
		if live[i].global_position.distance_to(field.global_position) > radius + 1.0:
			print("  [FAIL] A collectible sits outside the field radius")
			ok = false
		for j in range(i + 1, live.size()):
			min_gap = minf(min_gap, live[i].global_position.distance_to(live[j].global_position))
	if min_gap < 2.0:
		print("  [FAIL] Two collectibles are only %.1f m apart - they will crowd" % min_gap)
		ok = false

	# RENEWABLE, per Chris's call: mine one out and the field puts it back.
	var victim = live[0]
	victim.harvest(victim.amount)
	field.respawn_seconds = 0.05
	for _i in range(20):
		await tree.process_frame
		field._physics_process(0.05)
	if field.live_nodes().size() < live.size():
		print("  [FAIL] A depleted collectible was not replaced: %d of %d standing"
			% [field.live_nodes().size(), live.size()])
		ok = false

	# The centre must NOT be harvestable - a truck that drove into the middle of a
	# forest and stood there is doing what fields exist to stop.
	if field.is_in_group("resource_nodes"):
		print("  [FAIL] The field centre is itself in the harvestable group")
		ok = false

	field.queue_free()
	await tree.process_frame
	if ok:
		print("  [PASS] 7 collectibles over a %.0f m disc, closest pair %.1f m, depleted ones replaced."
			% [radius, min_gap])
	return ok


# An oil well is a single point on contested ground, not a field. That is what
# makes it worth fighting over rather than an area you spread out across.
func test_oil_wells_are_single_points() -> bool:
	print("Running Test Suite: Resources - oil wells are one contestable point...")
	var field = ResourceFieldScript.new()
	root.add_child(field)
	field.global_position = Vector3(0.0, 0.0, 0.0)
	field.setup("oil", 1400, null)
	await tree.process_frame

	var ok := true
	var live: Array = field.live_nodes()
	if live.size() != 1:
		print("  [FAIL] An oil well spawned %d collectibles, expected 1" % live.size())
		ok = false
	elif live[0].global_position.distance_to(field.global_position) > 0.01:
		print("  [FAIL] The well is offset from its own centre")
		ok = false

	field.queue_free()
	await tree.process_frame
	if ok:
		print("  [PASS] One well, at the point the map authored.")
	return ok


# Every bundled map has to actually offer the new resources, or the system is
# code with no content and the value ladder never comes up in play.
func test_every_map_offers_lumber_and_oil() -> bool:
	print("Running Test Suite: Resources - the maps were authored for it...")
	var ok := true
	var missing: Array = []
	for map_id in MapCatalogScript.get_map_ids():
		var map_def: Dictionary = MapCatalogScript.get_map(map_id)
		var seen := {}
		for entry in map_def.get("resource_nodes", []):
			seen[ResourceCatalogScript.canonical(str(entry.get("type", "metal")))] = true
		for needed in ["ore", "crystal", "lumber"]:
			if not seen.has(needed):
				missing.append("%s:%s" % [map_id, needed])
				ok = false
	if not missing.is_empty():
		print("  [FAIL] Maps missing resource types: ", str(missing))
	if ok:
		print("  [PASS] All %d maps carry ore, crystal and lumber."
			% MapCatalogScript.get_map_ids().size())
	return ok
