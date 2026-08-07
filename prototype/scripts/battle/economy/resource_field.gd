extends Node3D
# A resource FIELD: a central point that scatters collectible nodes around it and
# replaces them as they are worked out.
#
# WHAT THIS REPLACES. One node was one lump of ore sitting at one coordinate,
# which made a "field" a single point that four trucks queued at and shoved over.
# Chris's direction, 2026-08-07: ore and crystal stay, but spread out into fields
# around a central node that spawns the collectible objects. So the map entry is
# now a SPAWNER and the things harvesters drive to are its children.
#
# THE MAP SCHEMA DID NOT CHANGE. Every existing `resource_nodes` entry - position,
# type, amount - becomes a field centre, with the scatter shape read from
# ResourceCatalog per type. That keeps ten bundled maps and the spawn-fairness
# lint working untouched, and means a map author still authors one line per
# deposit rather than nine.
#
# RENEWABLE, per Chris's call: a depleted collectible is removed and the field
# puts a fresh one back after `respawn_seconds`. The field itself never runs out.
# Income is therefore a function of how many trucks you run against how many
# collectibles a field can keep standing - holding more ground means more
# simultaneous work sites, not a bigger lump.

const ResourceNodeScript = preload("res://scripts/resource_node.gd")
const ResourceCatalogScript = preload("res://scripts/battle/economy/resource_catalog.gd")

# The centre is not harvestable and is deliberately NOT in the resource_nodes
# group - a harvester that drove to the middle of a forest and stood in it would
# be doing exactly what fields exist to stop.
var resource_type: String = "ore"
var field_radius: float = 9.0
var node_count: int = 7
var per_node_amount: int = 150
var respawn_seconds: float = 35.0

var _world = null
var _slots: Array = []      # per-slot: {position, node, timer}
var _rng := RandomNumberGenerator.new()


func setup(type_id: String, total_amount: int, world) -> void:
	resource_type = ResourceCatalogScript.canonical(type_id)
	_world = world
	field_radius = ResourceCatalogScript.field_radius(resource_type)
	node_count = maxi(1, ResourceCatalogScript.field_nodes(resource_type))
	respawn_seconds = ResourceCatalogScript.respawn_seconds(resource_type)
	# The map's `amount` is the whole deposit; it is split across the scatter so
	# converting a map costs nothing in total ore. A field of nine trees each
	# holding a ninth of the stand is the same stand.
	per_node_amount = maxi(1, int(round(float(total_amount) / float(node_count))))

	# Deterministic per position, so a map's fields look the same every load and
	# a spawn-fairness result is reproducible. Seeded off the centre rather than
	# randomize() for exactly that reason.
	_rng.seed = hash(Vector2(global_position.x, global_position.z))

	add_to_group("resource_fields")
	_build_slots()


# Scatter positions, computed once. A golden-angle spiral rather than uniform
# random: random scatter clumps, and a clump of collectibles is the crowding
# problem fields exist to solve.
func _build_slots() -> void:
	_slots.clear()
	if node_count <= 1 or field_radius <= 0.0:
		_slots.append({"position": global_position, "node": null, "timer": 0.0})
		_spawn_into(0)
		return

	const GOLDEN_ANGLE := 2.39996323
	for i in range(node_count):
		# sqrt keeps the disc evenly covered instead of piling everything at the
		# rim, and the jitter stops the spiral reading as a machine-made pattern.
		var r: float = field_radius * sqrt(float(i + 0.5) / float(node_count))
		var theta: float = float(i) * GOLDEN_ANGLE + _rng.randf_range(-0.25, 0.25)
		var offset := Vector3(cos(theta) * r, 0.0, sin(theta) * r)
		var pos: Vector3 = global_position + offset
		if _world != null and _world.has_method("terrain_height_at"):
			pos.y = _world.terrain_height_at(pos)
		_slots.append({"position": pos, "node": null, "timer": 0.0})
		_spawn_into(i)


func _spawn_into(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	var slot: Dictionary = _slots[index]
	var node = ResourceNodeScript.new()
	add_child(node)
	node.global_position = slot["position"]
	node.setup(resource_type, per_node_amount)
	slot["node"] = node
	slot["timer"] = 0.0


func _physics_process(delta: float) -> void:
	for i in range(_slots.size()):
		var slot: Dictionary = _slots[i]
		var node = slot["node"]
		# A collectible that has been mined out frees its slot. The individual
		# node's own regrowth still applies while it is standing - this is the
		# coarser "the field puts a new one back" layer on top.
		if is_instance_valid(node) and node.amount > 0:
			continue
		if is_instance_valid(node):
			node.queue_free()
			slot["node"] = null
		slot["timer"] += delta
		if slot["timer"] >= respawn_seconds:
			_spawn_into(i)


# Live collectibles. Used by tests and by the minimap, which draws the field's
# footprint rather than one dot per tree.
func live_nodes() -> Array:
	var out: Array = []
	for slot in _slots:
		if is_instance_valid(slot["node"]) and slot["node"].amount > 0:
			out.append(slot["node"])
	return out


func remaining() -> int:
	var total := 0
	for node in live_nodes():
		total += node.amount
	return total
