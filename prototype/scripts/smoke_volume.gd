extends Area3D

# Persistent sightline-blocking smoke cloud, spawned by any weapon firing
# "smoke" ammo (ModuleCatalog.AMMO_TYPES) and by the dedicated
# smoke_discharger. This is the one genuinely new subsystem the ammo pass
# needed - everything else reuses machinery that already existed.
#
# WHY AN Area3D ON ITS OWN LAYER (and not a StaticBody3D on layer 1):
# layer 1 is "ground/obstacles", which is exactly what both LOS systems
# already raycast against, so putting smoke there would have been the
# one-line version. But layer 1 is also what unit movement collides with -
# a smoke cloud would have become a solid wall that vehicles physically
# bounce off, which is obviously wrong. An Area3D never participates in
# movement resolution, and a dedicated layer means nothing else in the
# project can be accidentally affected by smoke, or smoke by it. The cost
# is that every query that should see smoke must opt in explicitly, by
# adding SMOKE_COLLISION_LAYER to its mask AND setting
# collide_with_areas = true (Area3D hits are off by default). The three
# call sites that opt in:
#   - auto_weapon.gd  _is_los_blocked_to()  - weapons can't acquire or fire
#                                             through a cloud
#   - skirmish.gd     _has_line_of_sight()  - fog of war can't see through it
#   - weapon_missile.gd                     - guided rounds lose lock in it
#
# Lifecycle is deliberately self-contained (own timer, own queue_free) so a
# cloud outlives the weapon, the vehicle, and the blueprint that made it -
# it is a thing in the world, not a visual effect owned by a gun.

const MunitionPool = preload("res://scripts/munition_pool.gd")

# Layer 32. Layers already in use: 1 ground/obstacles, 2 modules,
# 4 units (and, in the separate Design Lab context, gizmos), 8 buildings,
# 16 mounting surfaces + resource nodes.
const SMOKE_COLLISION_LAYER := 32

# A cloud reaches full opacity/full blocking over BLOOM_TIME rather than
# instantly - a screen you can duck behind the very frame the round lands
# would make smoke a panic button rather than a plan. It then holds, then
# thins out over FADE_TIME.
const BLOOM_TIME: float = 0.6
const FADE_TIME: float = 2.5

var radius: float = 5.0
var lifetime: float = 12.0

var _age: float = 0.0
var _puffs: Array[MeshInstance3D] = []
var _shape: CollisionShape3D = null

# `radius` and `lifetime` must be set before add_child() - _ready() sizes the
# collision shape and the visual from them immediately.
static func spawn(parent: Node, pos: Vector3, cloud_radius: float, cloud_lifetime: float) -> Area3D:
	var smoke = new()
	smoke.radius = cloud_radius
	smoke.lifetime = cloud_lifetime
	parent.add_child(smoke)
	smoke.global_position = pos
	return smoke

func _ready():
	add_to_group("smoke_volumes")
	# Blocks nothing physically and detects nothing itself - it exists purely
	# to be found by the three raycasts listed in the header above.
	collision_layer = SMOKE_COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true

	_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = radius
	_shape.shape = sphere
	add_child(_shape)

	# Visual: a handful of overlapping translucent spheres rather than one
	# big ball, so it reads as a churning cloud instead of a bubble. Sizes
	# and offsets are jittered per puff, and the whole group scales up
	# during the bloom.
	var puff_count = clamp(int(radius * 1.5), 4, 10)
	for i in range(puff_count):
		var puff = MeshInstance3D.new()
		puff.mesh = MunitionPool.unit_sphere()
		# Quantised so MunitionPool's material cache converges on a small
		# fixed set instead of minting a new material per puff - the same
		# reasoning as auto_weapon.gd's flame colour quantisation.
		var grey = snappedf(randf_range(0.55, 0.75), 0.05)
		puff.material_override = MunitionPool.alpha(Color(grey, grey, grey + 0.02, 0.5))
		add_child(puff)
		var off = Vector3(
			randf_range(-1.0, 1.0), randf_range(-0.35, 0.5), randf_range(-1.0, 1.0)
		).normalized() * randf_range(0.0, radius * 0.55)
		puff.position = off
		puff.set_meta("base_scale", radius * randf_range(0.7, 1.15))
		puff.set_meta("drift", Vector3(randf_range(-0.12, 0.12), randf_range(0.02, 0.14), randf_range(-0.12, 0.12)))
		_puffs.append(puff)

	_update_visual(0.0, 0.0)

func _process(delta):
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	# Bloom in, hold, thin out. The collision shape tracks the bloom so the
	# cloud's blocking radius genuinely grows with the visual, then stops
	# blocking a little before it visually vanishes (a wisp shouldn't hide
	# a tank).
	var bloom = clamp(_age / BLOOM_TIME, 0.0, 1.0)
	var remaining = lifetime - _age
	var fade = clamp(remaining / FADE_TIME, 0.0, 1.0)
	var presence = bloom * fade

	if _shape and _shape.shape is SphereShape3D:
		_shape.shape.radius = max(radius * presence, 0.01)
	_shape.disabled = presence < 0.25

	_update_visual(delta, presence)

# Puffs shrink/grow with the cloud's presence and drift slowly, so a settled
# cloud still feels alive. The fade-out is carried by SCALE, not by alpha:
# MunitionPool hands out SHARED material instances, so writing alpha onto
# puff.material_override here would fade every other cloud (and every other
# alpha visual keyed to the same colour) along with this one.
func _update_visual(delta: float, presence: float):
	for puff in _puffs:
		if not is_instance_valid(puff):
			continue
		puff.scale = Vector3.ONE * (puff.get_meta("base_scale") * max(presence, 0.01))
		if delta > 0.0:
			puff.position += puff.get_meta("drift") * delta

# Whether `point` is inside any live smoke cloud. Used by weapon_missile.gd
# for lock-breaking, where a full raycast is the wrong question - a missile
# cares whether its TARGET is concealed, not whether some cloud happens to
# sit on the line between them.
static func is_point_obscured(tree: SceneTree, point: Vector3) -> bool:
	for s in tree.get_nodes_in_group("smoke_volumes"):
		if not is_instance_valid(s):
			continue
		if s._shape and s._shape.disabled:
			continue
		var r = s._shape.shape.radius if (s._shape and s._shape.shape is SphereShape3D) else s.radius
		if s.global_position.distance_to(point) <= r:
			return true
	return false
