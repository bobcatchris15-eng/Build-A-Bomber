extends RefCounted
class_name TerrainGreebles
# Real 3D ground-clutter props scattered across surface_zones/shallow_water_
# areas - the terrain-scatter counterpart to hull_greebles.gd's faction
# detail cards. Deliberately uses real primitive geometry (cylinders, boxes,
# spheres), not hull_greebles.gd's flat alpha-cutout cards: an RTS camera
# orbits/pans around scattered ground clutter across a much wider range of
# viewing angles than it ever sees a hull silhouette from, and terrain
# already has real-geometry precedent (terrain_builder.gd's rock-cluster
# obstacles, HullGreebles' own dune_runners water barrels) - a flat card
# would visibly pop/flatten out at a grazing camera angle in a way a real
# mesh doesn't. No Blender asset pipeline needed either, same reasoning as
# every other decoration in this file's neighborhood: cheap primitives are
# plenty for small background clutter.
#
# Every scatter_*() call is purely decorative - no StaticBody3D, no navmesh
# awareness. Surface zones stay fully walkable by every locomotor at their
# get_terrain_speed_multiplier() penalty (see terrain_builder.gd's own
# comment on this); clutter that physically blocked movement would silently
# turn a speed penalty into a hard obstacle, which is not what surface_zones
# means to model. Seeded deterministically from zone.center (same
# hash(position)-as-seed convention TerrainBuilder's own rock/obstacle
# decorations already use) so a given map always scatters identically
# run to run - required for the screenshot-based verification convention
# this project uses.

static func scatter(zone: Dictionary, parent: Node3D):
	match zone.get("surface_type", ""):
		"marsh": _scatter_marsh(zone, parent)
		"rocky": _scatter_rocky(zone, parent)
		"snow_mud": _scatter_snow_mud(zone, parent)
		"sand": _scatter_sand(zone, parent)

static func scatter_shallow_water(zone: Dictionary, parent: Node3D):
	_scatter_tide_pool_rocks(zone, parent)

static func _seeded_rng(center: Vector3) -> RandomNumberGenerator:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(center)
	return rng

static func _rand_point(rng: RandomNumberGenerator, zone: Dictionary, margin: float = 0.85) -> Vector2:
	var ox = rng.randf_range(-zone.half_extents.x * margin, zone.half_extents.x * margin)
	var oz = rng.randf_range(-zone.half_extents.y * margin, zone.half_extents.y * margin)
	return Vector2(ox, oz)

static func _flat_material(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

# Marsh/swamp: reed tufts (thin tapered stalks standing in small clumps,
# swaying angle varied per stalk) plus a couple of half-sunk driftwood logs -
# the two most legible "this ground is wet and choked with growth" cues at
# RTS camera distance, per the task's own suggested vocabulary.
static func _scatter_marsh(zone: Dictionary, parent: Node3D):
	var rng = _seeded_rng(zone.center)
	var reed_color = Color(0.28, 0.34, 0.16)
	var wood_color = Color(0.24, 0.19, 0.13)

	for cluster_i in range(7):
		var p = _rand_point(rng, zone)
		var stalk_count = rng.randi_range(3, 5)
		for i in range(stalk_count):
			var reed = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			var height = rng.randf_range(0.9, 1.6)
			cyl.top_radius = 0.03
			cyl.bottom_radius = 0.07
			cyl.height = height
			reed.mesh = cyl
			reed.material_override = _flat_material(reed_color.lightened(rng.randf_range(-0.08, 0.08)), 0.75)
			parent.add_child(reed)
			var jitter = Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
			reed.global_position = Vector3(zone.center.x + p.x + jitter.x, height / 2.0, zone.center.z + p.y + jitter.y)
			reed.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0, TAU), rng.randf_range(-0.15, 0.15))

	for i in range(3):
		var p = _rand_point(rng, zone, 0.7)
		var log_inst = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		var length = rng.randf_range(1.6, 2.8)
		var radius = rng.randf_range(0.12, 0.2)
		cyl.top_radius = radius
		cyl.bottom_radius = radius * 0.85
		cyl.height = length
		log_inst.mesh = cyl
		log_inst.material_override = _flat_material(wood_color.lightened(rng.randf_range(-0.05, 0.05)), 0.9)
		parent.add_child(log_inst)
		log_inst.global_position = Vector3(zone.center.x + p.x, radius * 0.6, zone.center.z + p.y)
		log_inst.rotation = Vector3(0, rng.randf_range(0, TAU), PI / 2.0 + rng.randf_range(-0.08, 0.08))

# Rocky: upgraded boulder jumble - a few larger boulders for real value-
# contrast (VISUAL_ART_DIRECTION.md's "hard and blocky at a glance") plus
# the original smaller rock bumps, all non-collidable (unlike terrain_
# builder.gd's real rock-cluster OBSTACLES, this ground stays walkable).
static func _scatter_rocky(zone: Dictionary, parent: Node3D):
	var rng = _seeded_rng(zone.center)

	for i in range(3):
		var p = _rand_point(rng, zone, 0.6)
		var boulder = MeshInstance3D.new()
		var box = BoxMesh.new()
		var size = Vector3(rng.randf_range(0.9, 1.5), rng.randf_range(0.7, 1.1), rng.randf_range(0.9, 1.5))
		box.size = size
		boulder.mesh = box
		var shade = rng.randf_range(0.28, 0.4)
		boulder.material_override = _flat_material(Color(shade, shade * 0.95, shade * 0.88), 0.95)
		parent.add_child(boulder)
		boulder.global_position = Vector3(zone.center.x + p.x, size.y / 2.0, zone.center.z + p.y)
		boulder.rotation.y = rng.randf_range(0, TAU)

	for i in range(10):
		var p = _rand_point(rng, zone)
		var rock = MeshInstance3D.new()
		var box = BoxMesh.new()
		var size = Vector3(rng.randf_range(0.3, 0.7), rng.randf_range(0.2, 0.5), rng.randf_range(0.3, 0.7))
		box.size = size
		rock.mesh = box
		var shade = rng.randf_range(0.3, 0.45)
		rock.material_override = _flat_material(Color(shade, shade * 0.95, shade * 0.88), 0.95)
		parent.add_child(rock)
		rock.global_position = Vector3(zone.center.x + p.x, size.y / 2.0, zone.center.z + p.y)
		rock.rotation.y = rng.randf_range(0, TAU)

# Snow/mud: rounded snowdrift mounds (flattened spheres) plus dark, glossy
# mud-rut streaks lying flush with the ground - the streaks are flat rather
# than raised (a "worn-through" patch, not a bump) to match the baked
# texture's own recessed mud channels instead of fighting them.
static func _scatter_snow_mud(zone: Dictionary, parent: Node3D):
	var rng = _seeded_rng(zone.center)
	var snow_color = Color(0.85, 0.84, 0.8)
	var mud_color = Color(0.18, 0.13, 0.09)

	for i in range(5):
		var p = _rand_point(rng, zone)
		var mound = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		var radius = rng.randf_range(0.5, 1.0)
		sphere.radius = radius
		sphere.height = radius * 1.1
		mound.mesh = sphere
		mound.material_override = _flat_material(snow_color.lightened(rng.randf_range(-0.04, 0.04)), 0.7)
		mound.scale = Vector3(1.0, 0.45, 1.0)
		parent.add_child(mound)
		mound.global_position = Vector3(zone.center.x + p.x, radius * 0.45 * 0.5, zone.center.z + p.y)

	for i in range(3):
		var p = _rand_point(rng, zone, 0.7)
		var rut = MeshInstance3D.new()
		var box = BoxMesh.new()
		var length = rng.randf_range(1.8, 3.2)
		box.size = Vector3(0.35, 0.04, length)
		rut.mesh = box
		var mat = _flat_material(mud_color.lightened(rng.randf_range(-0.03, 0.03)), 0.2)
		rut.material_override = mat
		parent.add_child(rut)
		rut.global_position = Vector3(zone.center.x + p.x, 0.03, zone.center.z + p.y)
		rut.rotation.y = rng.randf_range(0, TAU)

# Soft sand: long, low ripple ridges (echoing the baked texture's own dune
# shape at a larger physical scale) plus a couple of sun-bleached rock
# fragments - sparse, since a dune field's whole silhouette point is
# "smooth and mostly empty," not busy.
static func _scatter_sand(zone: Dictionary, parent: Node3D):
	var rng = _seeded_rng(zone.center)
	var sand_ridge_color = Color(0.7, 0.61, 0.42)
	var bleached_color = Color(0.68, 0.63, 0.56)

	for i in range(4):
		var p = _rand_point(rng, zone, 0.65)
		var ridge = MeshInstance3D.new()
		var box = BoxMesh.new()
		var length = rng.randf_range(2.5, 4.5)
		box.size = Vector3(length, 0.18, rng.randf_range(0.8, 1.4))
		ridge.mesh = box
		ridge.material_override = _flat_material(sand_ridge_color.lightened(rng.randf_range(-0.03, 0.05)), 0.9)
		parent.add_child(ridge)
		ridge.global_position = Vector3(zone.center.x + p.x, 0.06, zone.center.z + p.y)
		ridge.rotation.y = rng.randf_range(0, TAU)

	for i in range(2):
		var p = _rand_point(rng, zone)
		var rock = MeshInstance3D.new()
		var box = BoxMesh.new()
		var size = Vector3(rng.randf_range(0.25, 0.5), rng.randf_range(0.2, 0.35), rng.randf_range(0.25, 0.5))
		box.size = size
		rock.mesh = box
		rock.material_override = _flat_material(bleached_color.lightened(rng.randf_range(-0.04, 0.04)), 0.85)
		parent.add_child(rock)
		rock.global_position = Vector3(zone.center.x + p.x, size.y / 2.0, zone.center.z + p.y)
		rock.rotation.y = rng.randf_range(0, TAU)

# Shallow water: tide-pool rocks poking above the surface - some fully
# exposed, some barely breaking the waterline - a wet, glossy dark rock
# finish (unlike the matte rocky-terrain boulders) since these really do
# sit wet at the water's edge.
static func _scatter_tide_pool_rocks(zone: Dictionary, parent: Node3D):
	var rng = _seeded_rng(zone.center)
	var wet_rock_color = Color(0.22, 0.24, 0.23)

	for i in range(6):
		var p = _rand_point(rng, zone, 0.8)
		var rock = MeshInstance3D.new()
		var box = BoxMesh.new()
		var size = Vector3(rng.randf_range(0.4, 0.9), rng.randf_range(0.3, 0.7), rng.randf_range(0.4, 0.9))
		box.size = size
		rock.mesh = box
		var mat = _flat_material(wet_rock_color.lightened(rng.randf_range(-0.03, 0.05)), 0.35)
		rock.material_override = mat
		parent.add_child(rock)
		# Vary how much of each rock breaks the waterline - some barely
		# poke through (mostly submerged), others stand clear of it.
		var exposure = rng.randf_range(0.25, 0.75)
		rock.global_position = Vector3(zone.center.x + p.x, size.y * exposure - size.y / 2.0 + 0.06, zone.center.z + p.y)
		rock.rotation.y = rng.randf_range(0, TAU)
