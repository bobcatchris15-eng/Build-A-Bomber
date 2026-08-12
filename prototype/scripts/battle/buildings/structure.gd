class_name Structure
extends StaticBody3D
# A base building: HQ, refinery, manufactory, power plant.
#
# Thinner than the 687-line building.gd it replaces, because the things that file
# also did - production queues, energy bookkeeping, repair, placement legality -
# are services now. What is left is genuinely per-building: where it is, how much
# of it is left, where units come out, and where harvesters dock.
#
# GEOMETRY IS A PLACEHOLDER, inherited deliberately from the old implementation.
# Chris is replacing every building mesh with authored art later, so this pass is
# data and wiring only and the boxes are on purpose.

const BuildingCatalogScript = preload("res://scripts/battle/economy/building_catalog.gd")
const LayersScript = preload("res://scripts/battle/battle_layers.gd")
const DamageModelScript = preload("res://scripts/battle/units/damage_model.gd")
const UnitAssemblyScript = preload("res://scripts/battle/units/unit_assembly.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const LiveryScript = preload("res://scripts/livery.gd")
const BuildingMeshScript = preload("res://scripts/battle/buildings/building_mesh.gd")
const BattleFinishScript = preload("res://scripts/battle/battle_finish.gd")

signal died(structure)

var kind: String = "hq"
var team: int = 0
var max_hp: float = 1000.0
var hp: float = 1000.0
var is_dead: bool = false
var footprint := Vector3(5, 3, 5)

# Set only on blueprint-built defences: the reconstructed hull carrying the
# weapon modules. Null on every catalog building.
var defense_hull: Node3D = null
# Longest weapon reach, for the AI's siting decisions. Zero on anything unarmed.
var attack_range: float = 0.0

# How far this building sees, which is what lifts fog around a base.
#
# THIS WAS MISSING ENTIRELY and buildings lifted no fog at all. VisionService
# reads `vision_range` off anything in the `damageable` group and defaults to 0.0
# for anything that does not declare one - a deliberately quiet default, because
# not everything damageable is an observer - so structures counted as things to
# be SEEN and never as things that SEE. A base that does not light its own ground
# is the symptom; a missing property is the cause.
#
# 15.0 is the old runtime's own default (building.gd:94), carried over rather
# than reinvented. Per-kind overrides come from the catalog so an HQ or a sensor
# building can out-see a power plant without special-casing anything here.
const DEFAULT_VISION_RANGE := 15.0
var vision_range: float = DEFAULT_VISION_RANGE

# bay index -> the unit holding it, or null. Fixed length, allocated at setup
# from the catalog, so a refinery's capacity is authored data rather than an
# emergent property of how many harvesters happen to be nearby.
var _bays: Array = []
var _bay_offsets: Array = []

var _mesh: MeshInstance3D = null


func _ready() -> void:
	add_to_group("structures")
	add_to_group("damageable")


func setup(structure_kind: String, structure_team: int) -> void:
	kind = structure_kind
	team = structure_team
	set_meta("team", team)
	collision_layer = LayersScript.BUILDINGS
	collision_mask = 0

	var stats := BuildingCatalogScript.get_stats(kind)
	max_hp = stats.get("hp", 1000.0)
	hp = max_hp
	footprint = stats.get("size", Vector3(5, 3, 5))
	vision_range = stats.get("vision_range", DEFAULT_VISION_RANGE)

	_bay_offsets = BuildingCatalogScript.dock_bays_for(kind)
	_bays.resize(_bay_offsets.size())
	_bays.fill(null)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = footprint
	col.shape = box
	col.position = Vector3(0, footprint.y * 0.5, 0)
	add_child(col)

	# Authored art first, box second. Every catalog kind has a GLB in
	# assets/models/buildings/ and the old runtime has been using them all along;
	# the fallback stays because a kind added to the catalog before its model is
	# authored should appear as a grey box rather than as nothing at all.
	if BuildingMeshScript.build(self, kind, footprint,
			LiveryScript.PLAYER_ID, team) == null:
		_mesh = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = footprint
		_mesh.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = stats.get("color", Color(0.6, 0.6, 0.6))
		mat.roughness = 0.85
		_mesh.material_override = mat
		_mesh.position = Vector3(0, footprint.y * 0.5, 0)
		add_child(_mesh)

	_add_dock_pads()
	_add_selection_proxy()
	# LAST, once every mesh this building will ever have exists - the GLB, its
	# decals, the fallback box. The finish walks what is there when it runs, so
	# calling it any earlier silently skips whatever is added afterwards.
	BattleFinishScript.apply(self)


# A DEFENCE built from a player blueprint rather than a catalog entry.
#
# This is what makes a turret design mean anything. Everything else a base builds
# is a catalog kind with a box mesh; a defence is a design the player authored in
# the Lab on a foundation hull, so it has to be reconstructed the way a unit is -
# real hull geometry, real modules - and then armed, or it is a decorative box
# that cannot shoot.
#
# It stays a Structure rather than becoming a unit: it has no locomotion, it
# occupies a footprint, it carves the navmesh, and it dies like a building. The
# only thing it borrows from the unit path is assembly.
func setup_from_blueprint(blueprint: Dictionary, structure_team: int, bp_manager: Node) -> bool:
	kind = "defense"
	team = structure_team
	set_meta("team", team)
	collision_layer = LayersScript.BUILDINGS
	collision_mask = 0

	defense_hull = bp_manager.reconstruct_vehicle(blueprint, self, false, blueprint.get("faction", ""))
	if defense_hull == null:
		return false

	var hull_type: String = blueprint.get("hull_type", "bunker_main_meridian")
	var thickness: float = blueprint.get("armor_thickness", 1.0)
	var material: String = blueprint.get("armor_material", "hardened_steel")
	var hull_scale: Vector3 = Vector3.ONE
	if defense_hull.has_meta("hull_scale"):
		hull_scale = defense_hull.get_meta("hull_scale")
	max_hp = ModuleCatalog.compute_hull_max_hp(hull_type, thickness, material, hull_scale)
	hp = max_hp

	var catalog: Dictionary = ModuleCatalog.get_module_data(hull_type)
	footprint = catalog.get("size", Vector3(3, 2, 3))
	# A turret sees off its own foundation hull, the way a vehicle sees off its
	# hull - so a design with a sensor mast on it spots further, and a picket
	# turret is worth placing forward for what it reveals as well as what it
	# shoots. Falls back to the flat structure default for a hull the catalog has
	# no base vision for.
	vision_range = maxf(ModuleCatalog.get_base_vision(hull_type), DEFAULT_VISION_RANGE)
	# Defences dock nothing, so they publish no bays. Leaving the array unsized
	# would have reserve_bay() report a turret as a valid delivery point.
	_bay_offsets = []
	_bays.clear()

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = footprint
	col.shape = box
	col.position = Vector3(0, footprint.y * 0.5, 0)
	add_child(col)

	# The guns. Same script-swap the unit path uses, so a turret fires by exactly
	# the same rules a tank does and needs no defence-specific weapon code.
	attack_range = UnitAssemblyScript.attach_weapons(defense_hull)
	_add_selection_proxy()
	# Defences are built from a player blueprint, so they carry the same hull and
	# module materials a unit does and need the same battlefield finish. Omitting
	# it here left turrets glossy while the tanks beside them were not.
	BattleFinishScript.apply(self)
	return true


# Structures are clickable for the same reason units are, and through the same
# Ground-level parking bays, so where a harvester unloads is something you can
# SEE rather than an invisible offset in the catalog. Read as the apron of a
# grain elevator: a dark slab per bay with a lighter kerb around it.
#
# Purely decorative - no collision and no navmesh hole. A pad marks walkable
# ground, so giving it either would carve away the exact surface the harvester
# has to stand on to use it.
const DOCK_PAD_SIZE := Vector3(7.0, 0.08, 9.0)
const DOCK_PAD_KERB := 0.6

func _add_dock_pads() -> void:
	if _bay_offsets.is_empty():
		return
	for offset in _bay_offsets:
		var bay: Vector3 = offset
		# The pad's long axis points at the building, so it reads as a bay you
		# reverse into rather than a square patch.
		var facing_x: bool = absf(bay.x) > absf(bay.z)
		var pad_size := DOCK_PAD_SIZE
		if facing_x:
			pad_size = Vector3(DOCK_PAD_SIZE.z, DOCK_PAD_SIZE.y, DOCK_PAD_SIZE.x)

		var kerb := MeshInstance3D.new()
		var kerb_mesh := BoxMesh.new()
		kerb_mesh.size = pad_size + Vector3(DOCK_PAD_KERB * 2.0, -0.02, DOCK_PAD_KERB * 2.0)
		kerb.mesh = kerb_mesh
		var kerb_mat := StandardMaterial3D.new()
		kerb_mat.albedo_color = Color(0.62, 0.60, 0.54)
		kerb_mat.roughness = 0.95
		kerb.material_override = kerb_mat
		kerb.position = Vector3(bay.x, 0.03, bay.z)
		add_child(kerb)

		var pad := MeshInstance3D.new()
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = pad_size
		pad.mesh = pad_mesh
		var pad_mat := StandardMaterial3D.new()
		pad_mat.albedo_color = Color(0.17, 0.17, 0.19)
		pad_mat.roughness = 0.98
		pad.material_override = pad_mat
		pad.position = Vector3(bay.x, 0.07, bay.z)
		add_child(pad)


# mechanism - a proxy on the selection layer carrying a back-reference. Clicking
# a manufactory is how the radial menu for its queue is raised.
func _add_selection_proxy() -> void:
	var area := Area3D.new()
	area.name = "SelectionProxy"
	area.collision_layer = LayersScript.SELECTION
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.set_meta("structure", self)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = footprint
	col.shape = box
	col.position = Vector3(0, footprint.y * 0.5, 0)
	area.add_child(col)
	add_child(area)


# --- Dock bays ---------------------------------------------------------------

func bay_count() -> int:
	return _bays.size()


func bay_position(index: int) -> Vector3:
	if index < 0 or index >= _bay_offsets.size():
		return global_position
	return global_position + (_bay_offsets[index] as Vector3)


# Claims a free bay for `unit`, or returns -1 if all are taken.
#
# Idempotent: a unit that already holds a bay gets the same one back rather than
# a second. Without that, a harvester re-asking on any state re-entry would leak
# reservations until the refinery permanently reported itself full.
func reserve_bay(unit: Node) -> int:
	for i in range(_bays.size()):
		if _bays[i] == unit:
			return i
	for i in range(_bays.size()):
		# A reservation held by a freed unit is reclaimed here rather than
		# needing the dying unit to have cleaned up. Deaths happen in any order.
		if _bays[i] == null or not is_instance_valid(_bays[i]):
			_bays[i] = unit
			return i
	return -1


func release_bay(unit: Node) -> void:
	for i in range(_bays.size()):
		if _bays[i] == unit:
			_bays[i] = null
			return


# --- Unit exit ---------------------------------------------------------------

# Where a finished unit appears. Mirrored for team 1 so both bases eject toward
# the middle of the map rather than one of them ejecting into its own back wall.
func exit_position() -> Vector3:
	var offset: Vector3 = BuildingCatalogScript.get_stat(kind, "exit_offset", Vector3(0, 0.5, 6.0))
	if team != 0:
		offset.z = -offset.z
	return global_position + offset


# --- Damage ------------------------------------------------------------------

# Same three-argument contract as BattleUnitV2, because auto_weapon.gd does not
# know or care which one it hit - it duck-types anything in the `damageable`
# group. A one-argument version here is a runtime error on every shell that lands
# on a building.
#
# Structures take the damage-class reduction but NOT the facet or subsystem
# rules: a building has no armour facets to flank and no modules to strip, so
# there is nothing for those to act on. Routing through the resolver anyway is
# what keeps a thermal weapon good against buildings and a kinetic one mediocre,
# instead of every gun doing flat damage to bases.
func take_damage(amount: float, damage_type: String = "kinetic", hit_origin = null) -> void:
	if is_dead:
		return

	var resolved := DamageModelScript.resolve(null, [], damage_type, self, hit_origin)
	hp = maxf(0.0, hp - DamageModelScript.hull_damage(amount, resolved.x, resolved.y))
	if hp > 0.0:
		return

	is_dead = true
	# Every held bay is freed, or harvesters queued on a dead refinery wait
	# on a reservation that will never come.
	_bays.fill(null)
	died.emit(self)
	queue_free()


func repair_hp(amount: float) -> void:
	if is_dead or hp >= max_hp:
		return
	hp = minf(max_hp, hp + amount)


# --- Fog of war --------------------------------------------------------------
#
# Structures are THREE-state, unlike units. A building the player has seen once
# stays drawn where it was after it leaves vision, because a base does not move
# and forgetting it would be a lie the player can trivially disprove. Only a
# never-seen building is hidden outright.
var fog_hidden: bool = false
var fog_ever_seen: bool = false


func set_fog_visible(value: bool) -> void:
	fog_hidden = not value
	if value:
		fog_ever_seen = true
	visible = value or fog_ever_seen
