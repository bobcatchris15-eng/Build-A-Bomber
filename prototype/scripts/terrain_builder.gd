extends Node
class_name TerrainBuilder
const TerrainGreeblesScript = preload("res://scripts/terrain_greebles.gd")
const WorldScaleScript = preload("res://scripts/world_scale.gd")
# Turns a MapCatalog map Dictionary into: baked NavigationServer3D ground/
# water maps, decorative terrain meshes (water planes, rock-cluster
# obstacles), and pure query functions (terrain_height_at / is_position_
# blocked) that skirmish.gd and battle_unit.gd consult for Y-positioning,
# buildability, and (indirectly, via real Y coordinates) vision/combat
# elevation bonuses.
#
# Ground navmesh technique: the 160x160 (or whatever map_half_extents
# says) area is walked in GRID_CELL-sized quads, and any cell overlapping
# a water/obstacle footprint is simply omitted. RTS_CORE_ROADMAP.md B6
# retired the old rect elevation_zones/ramp system entirely (real
# elevation now comes from a heightmap - see height_at()'s own header
# comment) - every map has real per-cell slope rejection instead of a
# hand-authored single-direction ramp.

const GRID_CELL: float = 4.0

# RTS_CORE_ROADMAP.md B8: NavigationServer3D's Recast baker doesn't just
# get slow past a triangle-count threshold, it SEGFAULTS outright -
# confirmed empirically at scattered_peaks' 550 half-extent with the flat
# GRID_CELL=4.0 (151,250 ground triangles alone). Keeps the grid's total
# triangle count roughly constant regardless of map size by widening the
# cell for anything bigger than the ~300 half-extent every map up to
# twin_bridges already used successfully - GRID_CELL itself is untouched
# (and this returns exactly GRID_CELL) for every map at or under that
# size, so this is zero-risk for the 9 maps that already worked.
# CORE_DESIGN_LANGUAGE.md §3.2 / Chunk 14: this formula is a pure function
# of `half`, which itself now grows under world_scale (map_half_extents is
# a FIELD_SPEC-flagged field - see _apply_world_scale() in map_catalog.gd).
# No separate re-tuning turned out to be needed: source-triangle grid cell
# scales LINEARLY with half beyond the ~300 knee, so triangle count per
# axis (half / grid_cell) converges toward a constant (~75) as half grows
# without bound, rather than growing with it. A map that's 16x bigger
# because world_scale=16 costs the SAME source-triangle budget as a map
# that's 16x bigger because someone authored it that size by hand - the
# formula can't tell the difference, which is exactly the point.
static func _nav_grid_cell(map_def: Dictionary) -> float:
	var half: float = map_def.get("map_half_extents", 80.0)
	return max(GRID_CELL, half / 75.0)

# RTS_CORE_ROADMAP.md B8: even AFTER _nav_grid_cell() brought scattered_peaks'
# source triangle count back down to twin_bridges' working scale, the bake
# still segfaulted - the actual cause was Recast's internal voxel grid,
# sized from NavigationMesh.cell_size (Godot's own default: 0.25), not from
# triangle count at all. At 550 half-extent (1100 world units) that's a
# ~4400x4400 voxel heightfield; confirmed empirically that cell_size=1.0
# bakes successfully in ~500ms. Every map at or under 300 half-extent
# (twin_bridges' size, the largest that already worked) keeps EXACTLY
# Godot's own 0.25 default - zero behavior change for the 9 original maps.
#
# 2026-07-31 (performance): the "zero behavior change for the 9 original
# maps" conservatism above was costing more than it was protecting. Recast's
# cost is O(voxels), i.e. quadratic in 1/cell_size, and at 0.25 a 480-unit
# map (lake_crossing) bakes a 1920x1920 heightfield. Measured on that map
# with scratch/probe_nav_cell_size.gd:
#
#   cell_size   grid        bake      nav polys (lake / highland)
#   0.25        1920x1920   1585 ms   62 / 544
#   0.50         960x960     346 ms   56 / 144
#   1.00         480x480     106 ms   48 /  80
#
# That 1.5s is paid TWICE per rebake (ground + amphibious), and
# skirmish.gd rebakes on every building placement and every building death -
# a measured 3.2s main-thread freeze per placement, which is the "placing a
# building freezes the game" report. It is also ~3.5s of the ~6.4s cold
# match load that makes Windows mark the process Not Responding.
#
#
# 2026-07-31 (performance): DELIBERATELY LEFT AT 0.25 after trying to widen
# it, because widening buys speed by spending pathing correctness, and there
# turned out to be a way to get the speed without paying that. Recorded here
# so the next person doesn't re-run the same experiment:
#
#   flat 1.0          4 tests fail - plateau ramp unreachable, a resource
#                     node unreachable, repath-around-building broken
#   flat 0.5          plateau ramp still unreachable (max_y 1.0 vs 2.5)
#   scaled by size    plateau fixed, but a unit's path then cut straight
#                     THROUGH lake_crossing's lake instead of detouring
#
# Measured per-surface bake cost, for reference (probe_nav_cell_size.gd):
# 0.25 -> 1585ms, 0.5 -> 346ms, 1.0 -> 106ms. Tempting, and wrong: the
# navmesh is what stops units driving into lakes and off plateaus.
#
# The freeze it was meant to fix is solved instead by
# rebake_ground_and_amphibious_async() below, which moves Recast off the
# main thread entirely - full resolution, no stall. Cost stays high, but
# it is no longer paid where the player can feel it.
# CORE_DESIGN_LANGUAGE.md §3.2 / Chunk 14: same self-bounding property as
# _nav_grid_cell() above, and for the same reason - a pure function of
# `half`, which now grows with world_scale automatically (Chunk 12). The
# voxel grid dimension is 2*half/cell_size; beyond the 300 knee that's
# 2*half / (0.25 + (half-300)*0.003), which converges to 2/0.003 =~ 667
# voxels per axis as half -> infinity, REGARDLESS of how large half gets -
# it does not keep growing the way a naive fixed cell_size would. Verified
# directly (not just algebraically) by
# test_scattered_peaks_navmesh_bakes_cleanly_at_world_scale_4 below:
# scattered_peaks is the map that originally segfaulted the baker at its
# native 550 half-extent, and it still bakes cleanly at 4x that.
static func _nav_cell_size(map_def: Dictionary) -> float:
	var half: float = map_def.get("map_half_extents", 80.0)
	if half <= 300.0:
		return 0.25
	return 0.25 + (half - 300.0) * 0.003

# Bridge deck height above water/ground level - just enough to read as a
# real raised structure (and to keep the deck mesh visibly above the water
# plane's own y=0.05) without needing an approach ramp of its own; bridges
# sit flush with the surrounding ground on both banks.
const BRIDGE_DECK_HEIGHT: float = 0.6

# --- Heightmap terrain ---
#
# height_at(map_def, x, z) is the ONE source of truth for continuous
# ground elevation. It combines three things:
#   - low-amplitude deterministic noise everywhere (real, but subtle rolling
#     ground rather than perfectly dead-flat terrain)
#   - "hills": [{center, radius, height, falloff}] - a radially-symmetric
#     smoothstep bump
#   - "water_blobs": [{center, radius, irregularity, depth, shore_blend}] -
#     an organic (non-rectangular) lake shape: a per-angle radius wobble
#     defines the coastline, and the ground dips smoothly below sea level
#     inside it, blending back to 0 over `shore_blend` units past the edge.
# A map with terrain.heightmap set (RTS_CORE_ROADMAP.md B4) REPLACES all
# three with a bilinear sample of the baked heightmap PNG instead - see
# height_at()'s own header comment for the exact precedence.
#
# Every map gets the noise pass "for free" now that the ground is a real
# subdivided mesh instead of one flat box (see build_ground_visual_mesh())
# - a mismatch between a bumpy navmesh/height query and a visually flat
# ground would look like units floating/sinking, so the two MUST move
# together, which is exactly what this single function-plus-mesh-generator
# pairing guarantees.
const GROUND_NOISE_AMPLITUDE: float = 0.4
const GROUND_NOISE_FREQUENCY: float = 0.035
const MAX_WALKABLE_SLOPE: float = 0.7 # ~35 degrees

static var _noise_cache: Dictionary = {}

# CORE_DESIGN_LANGUAGE.md §3.2: at a larger world scale, ground undulation
# needs a longer wavelength to stay the same size RELATIVE to the (also
# larger) greeble dressing scattered on top of it - otherwise the terrain
# itself would look like it shrank while everything standing on it grew.
# Frequency is inverted (lower frequency = longer wavelength) so a bigger
# world_scale stretches the noise out rather than compressing it. The
# world_scale is folded into the cache key (not just used to build the
# FastNoiseLite once) so a map can genuinely change scale between calls -
# not that anything does yet at DEFAULT_WORLD_SCALE=1.0, but the naive
# single-entry-per-map-name cache would otherwise silently keep serving a
# stale frequency from before a scale change.
static func _get_noise(map_def: Dictionary) -> FastNoiseLite:
	var scale = WorldScaleScript.for_map(map_def)
	var map_name: String = map_def.get("name", "default")
	var key: String = "%s@%s" % [map_name, scale]
	if _noise_cache.has(key):
		return _noise_cache[key]
	var n = FastNoiseLite.new()
	n.seed = hash(map_name)
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = GROUND_NOISE_FREQUENCY / scale
	_noise_cache[key] = n
	return n

# --- Heightmap-backed elevation (RTS_CORE_ROADMAP.md B4) ---
#
# tools/terrain/build_terrain.py's counterpart: bilinear-samples the
# 16-bit heightmap PNG a map's "terrain" block points at, instead of the
# noise+hills+water_blobs analytic path above. Flag-gated on
# map_def.terrain.heightmap actually being set - highland_chokepoint/
# twin_summits do (B6, migrated off the old elevation_zones/ramp system);
# the other 6 bundled maps don't, so they keep the analytic path.
#
# Encoding MUST exactly mirror build_terrain.py's encode_heightmap():
# normalized = pixel / 32767.5 - 1.0 (range [-1, 1]), world height =
# normalized * height_scale. Pixel (px, pz) <-> world (px - half, pz -
# half) at 1 pixel/world-unit (PIXELS_PER_UNIT in the Python script).
const HEIGHT_PIXEL_HALF_RANGE: float = 32767.5

static var _heightmap_cache: Dictionary = {}
static var _surfacemap_cache: Dictionary = {}

# null (not false) signals "no heightmap for this map" vs. "load failed" -
# both fall back to the old analytic path identically, but a null cache
# entry lets a failed load be retried instead of permanently wedged.
static func _get_heightmap_image(map_def: Dictionary) -> Image:
	var terrain: Dictionary = map_def.get("terrain", {})
	var path: String = terrain.get("heightmap", "")
	if path == "":
		return null
	if _heightmap_cache.has(path):
		return _heightmap_cache[path]
	# load(), not Image.load_from_file() - the latter reads the raw PNG off
	# disk directly, which only exists in a dev checkout. In an exported
	# build only the imported resource ships in the .pck, so load_from_file()
	# silently returns null there (every heightmap/surfacemap .import sidecar
	# is importer="image"/type="Image" specifically so this load() resolves
	# to a real Image in both dev and export, not a CompressedTexture2D).
	var img = load(path) as Image
	_heightmap_cache[path] = img # caches the null on failure too - avoids re-attempting a broken path every single tick
	return img

static func _get_surfacemap_image(map_def: Dictionary) -> Image:
	var terrain: Dictionary = map_def.get("terrain", {})
	var path: String = terrain.get("surfacemap", "")
	if path == "":
		return null
	if _surfacemap_cache.has(path):
		return _surfacemap_cache[path]
	var img = load(path) as Image
	_surfacemap_cache[path] = img
	return img

# Test-only: forces the next _get_heightmap_image()/_get_surfacemap_image()
# call to reload from disk instead of reusing a cached Image - production
# never needs this (a map's heightmap is static for the process lifetime),
# but the automated suite runs everything in one process.
static func reset_heightmap_cache_for_tests() -> void:
	_heightmap_cache = {}
	_surfacemap_cache = {}
	# _corner_height_cache is derived from height_at(), which reads
	# _heightmap_cache - so it is exactly as stale as the caches above and
	# has to be dropped with them. A test that regenerates a fixture's
	# heightmap PNG and rebakes would otherwise keep baking the OLD
	# elevation, silently, with no error to show for it.
	_corner_height_cache = {}

# Clamped addressing at the edges (roadmap's own noted risk: without this,
# a unit standing exactly on the map boundary would sample past the image
# and jitter) - matches Image's own get_pixel() bounds, just done manually
# since bilinear needs the 4 neighbor pixels, one of which can be
# out-of-bounds by exactly 1 at the extreme edge.
# CORE_DESIGN_LANGUAGE.md §3.2 (Chunk 19): the heightmap PNG is a BAKED
# asset - build_terrain.py wrote it once at 1 pixel per world_scale=1.0
# world unit, for the map's ORIGINAL half_extents. It does not, and cannot,
# re-bake itself just because world_scale changed. `world_scale` maps the
# (already-scaled, per _apply_world_scale) incoming half_extents/x/z back
# down to the ORIGINAL space the pixel grid was actually authored in -
# without this, a scaled map's half_extents massively overshoots the real
# image bounds and every sample clamps to the edge, reading whatever
# happens to be there instead of the real terrain.
static func _sample_heightmap_bilinear(img: Image, half_extents: float, x: float, z: float, world_scale: float = 1.0) -> float:
	var dim = img.get_width()
	var original_half = half_extents / world_scale
	var original_x = x / world_scale
	var original_z = z / world_scale
	# World -> pixel space (float, sub-pixel precision for the bilinear lerp).
	var fx = clamp(original_x + original_half, 0.0, float(dim - 1))
	var fz = clamp(original_z + original_half, 0.0, float(dim - 1))
	var x0 = int(floor(fx))
	var z0 = int(floor(fz))
	var x1 = min(x0 + 1, dim - 1)
	var z1 = min(z0 + 1, dim - 1)
	var tx = fx - x0
	var tz = fz - z0

	var h00 = _decode_heightmap_pixel(img.get_pixel(x0, z0))
	var h10 = _decode_heightmap_pixel(img.get_pixel(x1, z0))
	var h01 = _decode_heightmap_pixel(img.get_pixel(x0, z1))
	var h11 = _decode_heightmap_pixel(img.get_pixel(x1, z1))
	var h0 = lerp(h00, h10, tx)
	var h1 = lerp(h01, h11, tx)
	return lerp(h0, h1, tz)

# build_terrain.py packs the 16-bit pixel value into R (high byte) + G (low
# byte) of an ordinary RGBA8 PNG - Godot's Image.load_from_file() does NOT
# reliably preserve a true 16-bit-grayscale PNG (verified empirically: it
# silently collapsed to 8-bit with every pixel saturating to 1.0), so this
# is the standard byte-split workaround, not the naive single-channel read.
static func _decode_heightmap_pixel(color: Color) -> float:
	var high_byte = round(color.r * 255.0)
	var low_byte = round(color.g * 255.0)
	var pixel16 = high_byte * 256.0 + low_byte
	return pixel16 / HEIGHT_PIXEL_HALF_RANGE - 1.0

# Nearest-sample (not bilinear - a surface TYPE can't be interpolated)
# palette index -> name. Must match build_terrain.py's SURFACE_PALETTE
# order exactly.
const SURFACE_PALETTE: Array = ["", "marsh", "rocky", "snow_mud", "sand", "gravel", "forest", "ice"]

# Same "baked asset, not re-derived" reasoning as _sample_heightmap_
# bilinear() above - see that function's comment.
static func _sample_surfacemap(img: Image, half_extents: float, x: float, z: float, world_scale: float = 1.0) -> String:
	var dim = img.get_width()
	var original_half = half_extents / world_scale
	var original_x = x / world_scale
	var original_z = z / world_scale
	var px = int(round(clamp(original_x + original_half, 0.0, float(dim - 1))))
	var pz = int(round(clamp(original_z + original_half, 0.0, float(dim - 1))))
	var index = int(round(img.get_pixel(px, pz).r * 255.0))
	if index < 0 or index >= SURFACE_PALETTE.size():
		return ""
	return SURFACE_PALETTE[index]

static func _hill_contribution(hill: Dictionary, x: float, z: float) -> float:
	var c: Vector3 = hill.center
	var dist = Vector2(x - c.x, z - c.z).length()
	var radius: float = hill.get("radius", 10.0)
	var falloff: float = hill.get("falloff", 15.0)
	var height: float = hill.get("height", 8.0)
	if dist <= radius:
		return height
	if dist >= radius + falloff or falloff <= 0.0:
		return 0.0
	var t = (dist - radius) / falloff
	var s = t * t * (3.0 - 2.0 * t) # smoothstep, 0 at radius -> 1 at radius+falloff
	return height * (1.0 - s)

# Deterministic per-blob coastline wobble - a couple of harmonics gives a
# smooth organic curve (not a perfect circle, not jagged/noisy), seeded from
# the blob's own center so it's stable across reloads without needing to
# store an authored polygon.
static func _water_blob_radius_at_angle(blob: Dictionary, theta: float) -> float:
	var base: float = blob.get("radius", 10.0)
	var irregularity: float = blob.get("irregularity", 0.25)
	var s: float = float(hash(blob.get("center", Vector3.ZERO)) % 1000) * 0.01
	var wobble = sin(theta * 3.0 + s) * 0.6 + sin(theta * 5.0 + s * 1.7) * 0.4
	return base * (1.0 + irregularity * wobble * 0.5)

static func _point_in_water_blob(blob: Dictionary, x: float, z: float) -> bool:
	var c: Vector3 = blob.center
	var dx = x - c.x
	var dz = z - c.z
	var theta = atan2(dz, dx)
	return Vector2(dx, dz).length() <= _water_blob_radius_at_angle(blob, theta)

static func _water_blob_height_contribution(blob: Dictionary, x: float, z: float) -> float:
	var c: Vector3 = blob.center
	var dx = x - c.x
	var dz = z - c.z
	var dist = Vector2(dx, dz).length()
	var theta = atan2(dz, dx)
	var edge = _water_blob_radius_at_angle(blob, theta)
	var blend: float = blob.get("shore_blend", 4.0)
	var depth: float = blob.get("depth", 1.2)
	if dist <= edge:
		return -depth
	if dist >= edge + blend or blend <= 0.0:
		return 0.0
	var t = (dist - edge) / blend
	var s = t * t * (3.0 - 2.0 * t) # smoothstep, 0 at edge -> 1 at edge+blend
	return -depth * (1.0 - s)

# The single continuous elevation query - noise everywhere, plus authored
# hills/water_blobs layered on top (or a real heightmap replacing all
# three - see below). Deliberately does NOT know about water_areas/
# bridges; terrain_height_at() below still owns that logic entirely,
# falling back to this function only where none of those apply.
# The highest the terrain can reach on this map, without sampling it.
#
# Exists for the fog shroud, which is a flat plane and therefore has to be
# placed above EVERY piece of ground or the ground renders through it. The
# shroud constant used to be 0.4, silently equal to GROUND_NOISE_AMPLITUDE -
# it was not "a small offset", it was exactly the terrain maximum, and the
# equality was never written down. Chunk 9 scaled the noise and left the
# shroud behind, so hilltops punched through the fog in elevation-shaped
# patches, and any heightmap map (height_scale 20, scaled) was far worse.
#
# Deliberately an upper BOUND rather than a measured maximum: cheap, stable,
# and erring high only lifts the shroud slightly.
static func max_height(map_def: Dictionary) -> float:
	var scale: float = WorldScaleScript.for_map(map_def)
	if _get_heightmap_image(map_def):
		# Heightmap samples are normalized 0..1, so height_scale IS the ceiling.
		return float(map_def.get("terrain", {}).get("height_scale", 20.0))
	var h: float = GROUND_NOISE_AMPLITUDE * scale
	for hill in map_def.get("hills", []):
		h += absf(float(hill.get("height", 0.0)))
	return h


static func height_at(map_def: Dictionary, x: float, z: float) -> float:
	# RTS_CORE_ROADMAP.md B4/B6: a real heightmap FULLY REPLACES the
	# analytic noise+hills+water_blobs path below (not layered on top of
	# it - a map authoring real terrain.features doesn't also want
	# procedural noise added in). Flag-gated on map_def.terrain.heightmap
	# actually being set - highland_chokepoint/twin_summits do (B6); the
	# other 6 bundled maps don't, so they still take the analytic path.
	var heightmap_img = _get_heightmap_image(map_def)
	if heightmap_img:
		var half: float = map_def.get("map_half_extents", 80.0)
		var height_scale: float = map_def.get("terrain", {}).get("height_scale", 20.0)
		# height_scale is itself a FIELD_SPEC-flagged field (already scaled
		# by _apply_world_scale, on purpose - a taller map should have
		# taller hills) - only the PIXEL SAMPLING position needs the
		# world_scale correction below, not the height magnitude.
		return _sample_heightmap_bilinear(heightmap_img, half, x, z, WorldScaleScript.for_map(map_def)) * height_scale

	var h = _get_noise(map_def).get_noise_2d(x, z) * GROUND_NOISE_AMPLITUDE * WorldScaleScript.for_map(map_def)
	for hill in map_def.get("hills", []):
		h += _hill_contribution(hill, x, z)
	for blob in map_def.get("water_blobs", []):
		h += _water_blob_height_contribution(blob, x, z)
	return h

static func _slope_at(map_def: Dictionary, x: float, z: float) -> float:
	const D = 0.5
	var h0 = height_at(map_def, x, z)
	var hx = height_at(map_def, x + D, z)
	var hz = height_at(map_def, x, z + D)
	return Vector2((hx - h0) / D, (hz - h0) / D).length()

const WATER_BLOB_SEGMENTS: int = 24

static func _water_blob_polygon(blob: Dictionary) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in range(WATER_BLOB_SEGMENTS):
		var theta = (float(i) / WATER_BLOB_SEGMENTS) * TAU
		var r = _water_blob_radius_at_angle(blob, theta)
		pts.append(Vector2(cos(theta) * r, sin(theta) * r))
	return pts

# Triangle fan from the blob's center out to its (organic) boundary ring, at
# a fixed Y - used both for the flat water navmesh faces and the visual
# water mesh. Winding follows the same low-to-high-angle sweep already
# proven to bake correctly for the rect water/ground quads elsewhere in
# this file (Recast silently drops a triangle whose winding doesn't match
# its walkable-surface convention) - increasing theta is the same
# rotational sense as those quads' x0->x1/z0->z1 sweep.
static func _water_blob_fan_verts(blob: Dictionary, y: float) -> PackedVector3Array:
	var c: Vector3 = blob.center
	var poly = _water_blob_polygon(blob)
	var verts = PackedVector3Array()
	for i in range(poly.size()):
		var p0 = poly[i]
		var p1 = poly[(i + 1) % poly.size()]
		verts.append(Vector3(c.x, y, c.z))
		verts.append(Vector3(c.x + p0.x, y, c.z + p0.y))
		verts.append(Vector3(c.x + p1.x, y, c.z + p1.y))
	return verts

# --- Geometry helpers ---

static func _rect_from(center: Vector3, half_extents: Vector2) -> Dictionary:
	return {"x0": center.x - half_extents.x, "x1": center.x + half_extents.x,
		"z0": center.z - half_extents.y, "z1": center.z + half_extents.y}

static func _rect_overlaps(cx0: float, cx1: float, cz0: float, cz1: float, rect: Dictionary) -> bool:
	return cx0 < rect.x1 and cx1 > rect.x0 and cz0 < rect.z1 and cz1 > rect.z0

static func _point_in_rect(pos: Vector3, rect: Dictionary) -> bool:
	return pos.x >= rect.x0 and pos.x <= rect.x1 and pos.z >= rect.z0 and pos.z <= rect.z1

static func _add_nav_quad(verts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3):
	verts.append(a); verts.append(b); verts.append(c)
	verts.append(a); verts.append(c); verts.append(d)

# Organic water_blobs can't be tested with the same rect-overlap check the
# rest of this file uses - a grid cell counts as "on" a blob if its CENTER
# point falls inside the blob's per-angle radius. At GRID_CELL (4.0)
# resolution against a blob typically tens of units across, a center-point
# sample tracks the true organic boundary closely enough that the resulting
# navmesh hole reads as a real coastline, not a blocky approximation.
static func _cell_on_water_blob(x0: float, x1: float, z0: float, z1: float, map_def: Dictionary) -> bool:
	var blobs = map_def.get("water_blobs", [])
	if blobs.is_empty(): return false
	var cx = (x0 + x1) / 2.0
	var cz = (z0 + z1) / 2.0
	for blob in blobs:
		if _point_in_water_blob(blob, cx, cz):
			return true
	return false

# Obstacles/elevation always block ground faces; water normally does too,
# EXCEPT where a bridge crosses it - bridges carve a walkable strip straight
# through the water hole so ground units get a real, narrow crossing point
# flanked by water on both sides (a genuine tactical chokepoint), rather than
# being a flag that just turns water off entirely. Not used by
# _build_amphibious_faces() - water there is already walkable for every
# amphibious unit, so a bridge carve-out would be a no-op - and deliberately
# NOT used by _build_deep_water_faces()/water_map either, so naval units keep
# floating and passing freely underneath, same as a real bridge over a river.
static func _collect_bridges(map_def: Dictionary) -> Array:
	var bridges = []
	for b in map_def.get("bridges", []):
		bridges.append(_rect_from(b.center, b.half_extents))
	return bridges

static func _cell_on_bridge(x0: float, x1: float, z0: float, z1: float, bridges: Array) -> bool:
	for b in bridges:
		if _rect_overlaps(x0, x1, z0, z1, b):
			return true
	return false

# --- Navmesh source geometry ---
#
# Flat (Y=0 baseline, real Y only for bridges) for a map with no
# heightmap - real per-vertex noise across a ~240-half-extent map pushed a
# single Recast bake from milliseconds to 10+ seconds (unacceptable at 4
# navmeshes per match start), and neither navmesh Y precision nor Recast's
# own slope-walkability check are actually consumed anywhere for that path
# - every unit/building's real on-screen Y comes from a fresh
# terrain_height_at() query every tick, never from a navmesh path point's
# Y - so staying flat loses nothing gameplay depends on. A heightmap-
# backed map (RTS_CORE_ROADMAP.md B4/B5) samples REAL corner heights
# instead and REJECTS any cell whose slope exceeds MAX_WALKABLE_SLOPE - an
# O(1) image lookup per corner, not the expensive noise+hill/blob loop
# stack, so the same bake-time problem doesn't apply.
# Corner-height grid, computed once per (map, grid) and reused.
#
# _build_ground_faces() samples height_at() at all four corners of every grid
# cell. Adjacent cells share corners, so every interior corner was being
# resampled four times: on highland_chokepoint (a 150x150 grid) that is
# ~90,000 bilinear heightmap samples, measured at 469ms of a 676ms rebake
# once _nav_cell_size() had brought the Recast bake itself down to ~90ms.
#
# Caching across calls (not just within one) is what makes the mid-match
# rebake cheap, and it is safe because terrain height is immutable for the
# life of a match - height_at() reads the map's heightmap/hills/noise, none
# of which change. Only the building holes change between rebakes, and those
# are applied separately below as rect tests, never through this grid.
#
# Float64 (not 32) deliberately: these values feed the max_slope >
# MAX_WALKABLE_SLOPE comparison, and a cell sitting exactly on that
# threshold should not flip walkability because the cache rounded it.
static var _corner_height_cache: Dictionary = {}

static func _corner_heights(map_def: Dictionary, half: float, cell: float) -> Dictionary:
	# Keyed on the heightmap PATH as well as the name: two map dicts can
	# share a name (or have none at all - test fixtures and inline dicts
	# like {"map_half_extents": 300.0} are common in run_tests.gd) while
	# describing completely different elevation, and silently serving one
	# map's heights for another would be near-impossible to diagnose from
	# the symptom (a subtly wrong navmesh).
	var terrain: Dictionary = map_def.get("terrain", {})
	var key = "%s:%s:%s:%s" % [map_def.get("name", ""), terrain.get("heightmap", ""), half, cell]
	if _corner_height_cache.has(key):
		return _corner_height_cache[key]
	# Exactly the boundary sequence the while-loops below walk (v = min(v +
	# cell, half), terminating at half), so corner i is always grid line i.
	var coords := PackedFloat64Array()
	var v := -half
	coords.append(v)
	while v < half:
		v = min(v + cell, half)
		coords.append(v)
	var n := coords.size()
	var heights := PackedFloat64Array()
	heights.resize(n * n)
	for i in range(n):
		for j in range(n):
			heights[i * n + j] = height_at(map_def, coords[i], coords[j])
	var out := {"heights": heights, "n": n}
	_corner_height_cache[key] = out
	return out

# CORE_DESIGN_LANGUAGE.md §3.2 (2026-08-08 playtest): _nav_grid_cell()'s
# formula (Chunk 14) deliberately widens the terrain SOURCE quad size as
# map_half_extents grows, to keep triangle count bounded on huge maps - a
# self-bounding choice proven safe for OPEN terrain. It was not, until now,
# tested against small clustered features: at open_plains' world_scale=4
# quad size (~11.2 units), a single building's few-metre footprint touching
# ANY part of a quad OMITS THE ENTIRE QUAD (see the loop below - "blocked"
# skips emitting it at all), and a compact base's several buildings each
# swallowing a full quad can MERGE into a hole many times larger than the
# buildings themselves. Confirmed live: a harvester's own compacted spawn
# point ended up stranded in a ~20-unit hole next to its base, with
# NavigationAgent3D permanently stuck offering the same near-spawn waypoint
# (tools/probe_navmesh_grid.gd maps the exact shape). Below this threshold,
# a coarse quad that touches a hard hole is re-tested at fine resolution
# instead of omitted wholesale, so a small building only removes the area
# it actually occupies.
#
# 1.0, not 2.0. At 2.0 the re-test still rounded every hole OUTWARD by up to
# two units, which is not a rounding error at this scale - it is larger than
# the margin the exit_offset and dock_bay constants were tuned against. Every
# manufactory's exit_position() measured 1.0-2.5 units INSIDE the baked hole
# (tools/probe_factory_exit.gd), so a factory-built unit spawned off-mesh,
# accepted its move order, turned to face it, and then circled forever with
# no valid path start.
const HOLE_SUBDIVISION_CELL: float = 1.0

static func _build_ground_faces(map_def: Dictionary, extra_holes: Array = []) -> PackedVector3Array:
	var verts = PackedVector3Array()
	var half: float = map_def.get("map_half_extents", 80.0)
	var water_holes = []
	for w in map_def.get("water_areas", []):
		water_holes.append(_rect_from(w.center, w.half_extents))
	var hard_holes = []
	for o in map_def.get("obstacles", []):
		hard_holes.append(_rect_from(o.center, o.half_extents))
	# RTS_CORE_ROADMAP.md C1: extra_holes are building footprints ({center,
	# half_extents}, same rect shape obstacles already use) - a live
	# building blocks the ground navmesh exactly like a map-authored
	# obstacle does. Empty for the initial map-load bake; populated by
	# skirmish.gd's dynamic rebake on building placed/destroyed.
	for eh in extra_holes:
		hard_holes.append(_rect_from(eh.center, eh.half_extents))
	var bridges = _collect_bridges(map_def)
	var has_blobs = not map_def.get("water_blobs", []).is_empty()
	var heightmap_img = _get_heightmap_image(map_def)
	var cell = _nav_grid_cell(map_def)
	# Only the heightmap branch below reads corner heights, so only build
	# (or fetch) the shared grid when there is a heightmap to sample.
	var corner_heights := PackedFloat64Array()
	var corner_n := 0
	if heightmap_img:
		var grid = _corner_heights(map_def, half, cell)
		corner_heights = grid["heights"]
		corner_n = grid["n"]

	var xi = 0
	var x = -half
	while x < half:
		var x1 = min(x + cell, half)
		var zi = 0
		var z = -half
		while z < half:
			var z1 = min(z + cell, half)
			var hard_blocked = false
			for h in hard_holes:
				if _rect_overlaps(x, x1, z, z1, h):
					hard_blocked = true
					break
			if hard_blocked and cell > HOLE_SUBDIVISION_CELL:
				# See HOLE_SUBDIVISION_CELL's own comment. Flat Y=0 sub-
				# quads even on a heightmap map - a small, known imprecision
				# right at a building edge, far preferable to omitting the
				# whole coarse quad the building only clips a corner of.
				_emit_subdivided_ground_quad(verts, x, x1, z, z1, hard_holes, water_holes, bridges, has_blobs, map_def)
				z = z1
				zi += 1
				continue
			var blocked = hard_blocked
			if not blocked:
				for w in water_holes:
					if _rect_overlaps(x, x1, z, z1, w) and not _cell_on_bridge(x, x1, z, z1, bridges):
						blocked = true
						break
			if not blocked and has_blobs and _cell_on_water_blob(x, x1, z, z1, map_def):
				blocked = true
			if not blocked and heightmap_img:
				# Grid line xi is world x, xi+1 is world x1 (see
				# _corner_heights() - it walks the same sequence).
				var h00 = corner_heights[xi * corner_n + zi]
				var h10 = corner_heights[(xi + 1) * corner_n + zi]
				var h01 = corner_heights[xi * corner_n + zi + 1]
				var h11 = corner_heights[(xi + 1) * corner_n + zi + 1]
				var max_slope = max(
					max(abs(h10 - h00), abs(h01 - h00)),
					max(abs(h11 - h10), abs(h11 - h01))
				) / cell
				if max_slope > MAX_WALKABLE_SLOPE:
					blocked = true
				else:
					_add_nav_quad(verts, Vector3(x, h00, z), Vector3(x1, h10, z), Vector3(x1, h11, z1), Vector3(x, h01, z1))
			elif not blocked:
				# Deliberately flat (not height_at()) - see this function's
				# header comment for why the navmesh SOURCE geometry stays
				# flat even though the visual mesh and every gameplay Y
				# query (terrain_height_at()) are real heightmap-driven.
				_add_nav_quad(verts, Vector3(x, 0, z), Vector3(x1, 0, z), Vector3(x1, 0, z1), Vector3(x, 0, z1))
			z = z1
			zi += 1
		x = x1
		xi += 1
	return verts

# Re-tests a single coarse quad at HOLE_SUBDIVISION_CELL resolution instead
# of omitting it wholesale - see _build_ground_faces()'s header comment for
# why. Deliberately re-runs the SAME hard_holes/water_holes/blob checks the
# coarse loop already ran, just at finer granularity within this one quad,
# so a fine sub-cell not actually touching any hole still gets emitted.
static func _emit_subdivided_ground_quad(verts: PackedVector3Array, x0: float, x1: float, z0: float, z1: float,
		hard_holes: Array, water_holes: Array, bridges: Array, has_blobs: bool, map_def: Dictionary) -> void:
	var sub = HOLE_SUBDIVISION_CELL
	var sx = x0
	while sx < x1:
		var sx1 = min(sx + sub, x1)
		var sz = z0
		while sz < z1:
			var sz1 = min(sz + sub, z1)
			var blocked = false
			for h in hard_holes:
				if _rect_overlaps(sx, sx1, sz, sz1, h):
					blocked = true
					break
			if not blocked:
				for w in water_holes:
					if _rect_overlaps(sx, sx1, sz, sz1, w) and not _cell_on_bridge(sx, sx1, sz, sz1, bridges):
						blocked = true
						break
			if not blocked and has_blobs and _cell_on_water_blob(sx, sx1, sz, sz1, map_def):
				blocked = true
			if not blocked:
				_add_nav_quad(verts, Vector3(sx, 0, sz), Vector3(sx1, 0, sz), Vector3(sx1, 0, sz1), Vector3(sx, 0, sz1))
			sz = sz1
		sx = sx1

# Same grid-quad sweep as _build_ground_faces(), but water is walkable
# terrain here instead of a hole - only real obstacles block it. This is
# what makes screw_drive locomotion (the amphibious auger-drum type)
# genuinely different from a plain ground unit: it can path straight
# across a lake in one continuous route instead of being confined to
# ground_nav_map like every other ground/legged type. water_blobs are
# deliberately NOT excluded here either, for the same reason water_areas
# never was - amphibious units cross water freely.
static func _build_amphibious_faces(map_def: Dictionary, extra_holes: Array = []) -> PackedVector3Array:
	var verts = PackedVector3Array()
	var half: float = map_def.get("map_half_extents", 80.0)
	var holes = []
	for o in map_def.get("obstacles", []):
		holes.append(_rect_from(o.center, o.half_extents))
	# RTS_CORE_ROADMAP.md C1: same building-footprint holes as
	# _build_ground_faces() above - a screw_drive unit can cross open
	# water, but not through a building sitting on land.
	for eh in extra_holes:
		holes.append(_rect_from(eh.center, eh.half_extents))
	var cell = _nav_grid_cell(map_def)

	var x = -half
	while x < half:
		var x1 = min(x + cell, half)
		var z = -half
		while z < half:
			var z1 = min(z + cell, half)
			var blocked = false
			for h in holes:
				if _rect_overlaps(x, x1, z, z1, h):
					blocked = true
					break
			if blocked and cell > HOLE_SUBDIVISION_CELL:
				# Same fix as _build_ground_faces() - see that function's
				# header comment. A screw_drive unit hits the exact same
				# building-swallows-a-whole-coarse-quad failure on land.
				_emit_subdivided_ground_quad(verts, x, x1, z, z1, holes, [], [], false, map_def)
			elif not blocked:
				_add_nav_quad(verts, Vector3(x, 0, z), Vector3(x1, 0, z), Vector3(x1, 0, z1), Vector3(x, 0, z1))
			z = z1
		x = x1
	return verts

# Deep-draught-only water: the same water_areas footprint as water_map,
# grid-swept (like _build_ground_faces()) so shallow_water_areas sub-
# regions can be carved out as holes - a deep-draught hull (heavy_
# cruiser_hull) literally cannot float there, the real physical
# impossibility the task called out as worth an actual navmesh block
# rather than just a speed penalty. Shallow-draught naval hulls
# (small_boat_hull, naval_hull) keep using the unmodified water_map, which
# still includes these areas.
static func _build_deep_water_faces(map_def: Dictionary) -> PackedVector3Array:
	var verts = PackedVector3Array()
	var shallow_holes = []
	for sw in map_def.get("shallow_water_areas", []):
		shallow_holes.append(_rect_from(sw.center, sw.half_extents))
	var cell = _nav_grid_cell(map_def)
	for w in map_def.get("water_areas", []):
		var rect = _rect_from(w.center, w.half_extents)
		var x = rect.x0
		while x < rect.x1:
			var x1 = min(x + cell, rect.x1)
			var z = rect.z0
			while z < rect.z1:
				var z1 = min(z + cell, rect.z1)
				var blocked = false
				for h in shallow_holes:
					if _rect_overlaps(x, x1, z, z1, h):
						blocked = true
						break
				if not blocked:
					_add_nav_quad(verts, Vector3(x, 0, z), Vector3(x1, 0, z), Vector3(x1, 0, z1), Vector3(x, 0, z1))
				z = z1
			x = x1
	return verts

# Shared by build_navmeshes() below AND rebake_ground_and_amphibious() (C1's
# dynamic rebake) - one place that knows how to turn source verts into a
# baked NavigationMesh, so the two bakers can't silently drift apart on
# cell_size/agent settings.
# CORE_DESIGN_LANGUAGE.md §3.2 (2026-08-08 playtest): NavigationMesh.
# agent_max_climb was never set here, leaving it at Godot's own default
# (0.25) - fine at cell_size 0.25 (quantizes to exactly 1 cell), silently
# LETHAL once cell_size grows past 0.25 (Chunk 14's self-bounding formula
# widens it well beyond that on any map bigger than 300 half-extent). Recast
# quantizes agent_max_climb to whole cell_height units, FLOORING - confirmed
# via the engine's own "agent_max_climb is floored to cell_height voxel
# units" warning, and at cell_size 1.87 (open_plains, world_scale=4) that
# floors 0.25 all the way to ZERO. A navmesh baked with zero climb tolerance
# treats every tiny bit of terrain noise (GROUND_NOISE_AMPLITUDE, itself
# real and present) as an impassable micro-cliff, fragmenting connectivity
# right around wherever a unit happens to be standing - which reproduced
# exactly as "units sit in place and go in a circle" (a live NavigationAgent3D
# permanently stuck offering the same near-start corner - see tools/probe_
# nav_scale_stall.gd) despite a raw NavigationServer3D.map_get_path() query
# between the same two points succeeding, because that query doesn't hit the
# SAME connectivity holes the agent's own local corridor search does. Scaled
# with cell_size (not left flat) so it always survives the floor - 1.5 cells
# of headroom regardless of how large a map's cell_size grows.
const AGENT_MAX_CLIMB_CELLS: float = 1.5

# CORE_DESIGN_LANGUAGE.md §3.2 (2026-08-08 playtest): cell_HEIGHT used to
# just mirror cell_SIZE, which was fine while both were the same small
# number (0.25 at world_scale=1) but silently broke vertical precision once
# _nav_cell_size() started widening cell_size for big maps (Chunk 14 - a
# deliberate, correct choice for HORIZONTAL triangle count, never meant to
# also degrade vertical accuracy). Confirmed live: on a flat, non-heightmap
# map the navmesh source geometry is deliberately Y=0 (see
# _build_ground_faces()'s own comment), yet every query near a scaled-up
# map returned Y~3.74 - exactly 2x cell_height at world_scale=4's cell_size
# (1.87) - Recast's vertical voxelisation quantizing the flat ground up by
# whole cell_height steps. That put the baked navmesh surface several units
# above where a real unit's body actually stands (terrain_height_at() drives
# the unit's real Y, and does NOT share this quantization), and the
# resulting vertical mismatch was enough to make NavigationAgent3D's 3D-aware
# path queries misbehave near real bases even though the horizontal geometry
# (proven separately, see the HOLE_SUBDIVISION_CELL fix above) was already
# correct. Decoupled from cell_size and kept fixed, small, and world_scale-
# independent - vertical precision has no reason to get coarser just
# because the map got wider.
const NAV_CELL_HEIGHT: float = 0.25

static func _bake_nav_mesh(verts: PackedVector3Array, cell_size: float) -> NavigationMesh:
	var nav_mesh = NavigationMesh.new()
	nav_mesh.cell_size = cell_size
	nav_mesh.cell_height = NAV_CELL_HEIGHT
	nav_mesh.agent_max_climb = cell_size * AGENT_MAX_CLIMB_CELLS
	nav_mesh.agent_radius = 0.1
	var source = NavigationMeshSourceGeometryData3D.new()
	source.add_faces(verts, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	return nav_mesh

# RTS_CORE_ROADMAP.md C1: dynamic navmesh for buildings blocking movement.
# Re-bakes ONLY ground+amphibious (the two surfaces a building actually
# footprints on - water/deep_water are never affected by a building
# placement) against the SAME region RIDs build_navmeshes() already
# created, via region_set_navigation_mesh() rather than region_create() -
# reuses the existing region/map RIDs instead of leaking new ones every
# time a building goes up or down. extra_holes is the live building
# footprint list (skirmish.gd's job to gather from the "buildings" group).
static func rebake_ground_and_amphibious(map_def: Dictionary, extra_holes: Array, ground_region: RID, amphibious_region: RID) -> void:
	var cell_size = _nav_cell_size(map_def)
	var ground_verts = _build_ground_faces(map_def, extra_holes)
	NavigationServer3D.region_set_navigation_mesh(ground_region, _bake_nav_mesh(ground_verts, cell_size))
	var amphibious_verts = _build_amphibious_faces(map_def, extra_holes)
	NavigationServer3D.region_set_navigation_mesh(amphibious_region, _bake_nav_mesh(amphibious_verts, cell_size))

# Async twin of rebake_ground_and_amphibious(), for the MID-MATCH rebake.
#
# Even after _nav_cell_size() dropped the per-surface Recast bake from
# ~1585ms to ~327ms, a placement still stalled the main thread for ~766ms
# (two surfaces plus face generation) - short of a freeze, but well past a
# dropped frame, and paid on every building placed or destroyed.
#
# Recast itself is the bulk of that and does not need to run on the main
# thread: NavigationServer3D.bake_from_source_geometry_data_async() hands it
# to a worker and invokes the callback when the mesh is ready. What stays
# synchronous here is only the GDScript face generation (~70-100ms with the
# corner-height cache), because it walks map_def and has to see a consistent
# snapshot of the building holes.
#
# The INITIAL map-load bake deliberately keeps using the synchronous version
# above: units spawn and take their first orders within a frame or two of
# _ready(), so a navmesh that arrives "soon" instead of "now" would let the
# very first path query run against an empty region. Load already blocks;
# the mid-match rebake is the one that must not.
#
# on_ready is invoked once BOTH surfaces have finished baking, so callers
# can repath units against a fully-updated navmesh rather than a half-
# updated one.
static func rebake_ground_and_amphibious_async(map_def: Dictionary, extra_holes: Array, ground_region: RID, amphibious_region: RID, on_ready: Callable = Callable()) -> void:
	var cell_size = _nav_cell_size(map_def)
	var ground_verts = _build_ground_faces(map_def, extra_holes)
	var amphibious_verts = _build_amphibious_faces(map_def, extra_holes)
	# Shared countdown so on_ready fires exactly once, after the second of
	# the two bakes lands (order between them is not guaranteed).
	var remaining = {"n": 2}
	_bake_region_async(ground_region, ground_verts, cell_size, remaining, on_ready)
	_bake_region_async(amphibious_region, amphibious_verts, cell_size, remaining, on_ready)

static func _bake_region_async(region: RID, verts: PackedVector3Array, cell_size: float, remaining: Dictionary, on_ready: Callable) -> void:
	var nav_mesh = NavigationMesh.new()
	nav_mesh.cell_size = cell_size
	# See _bake_nav_mesh()'s comments (both NAV_CELL_HEIGHT and
	# agent_max_climb) - the same fixes are needed here, since this is the
	# SECOND, independent NavigationMesh construction site (the async
	# mid-match rebake path for buildings going up/down), not a call through
	# the other one.
	nav_mesh.cell_height = NAV_CELL_HEIGHT
	nav_mesh.agent_max_climb = cell_size * AGENT_MAX_CLIMB_CELLS
	nav_mesh.agent_radius = 0.1
	var source = NavigationMeshSourceGeometryData3D.new()
	source.add_faces(verts, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data_async(nav_mesh, source, func():
		NavigationServer3D.region_set_navigation_mesh(region, nav_mesh)
		remaining["n"] -= 1
		if remaining["n"] <= 0 and on_ready.is_valid():
			on_ready.call())

static func build_navmeshes(map_def: Dictionary, extra_holes: Array = []) -> Dictionary:
	# RTS_CORE_ROADMAP.md B8: a NavigationServer3D MAP has its own
	# cell_size/cell_height (default 0.25, independent of whatever a
	# NavigationMesh RESOURCE assigned to one of its regions uses) -
	# region_set_navigation_mesh() silently REJECTS the mesh (real error,
	# not just a warning) if the two don't match, which a region-to-map
	# association check alone doesn't reveal (that stays "valid" even when
	# the mesh assignment itself was refused). Caught via the real Skirmish
	# scene, not the isolated bake-only repro that first found the
	# original segfault - that repro never created a map/region at all, so
	# it couldn't have surfaced this.
	var cell_size = _nav_cell_size(map_def)
	var ground_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(ground_map, cell_size)
	NavigationServer3D.map_set_cell_height(ground_map, NAV_CELL_HEIGHT)
	NavigationServer3D.map_set_active(ground_map, true)
	var water_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(water_map, cell_size)
	NavigationServer3D.map_set_cell_height(water_map, NAV_CELL_HEIGHT)
	NavigationServer3D.map_set_active(water_map, true)
	var amphibious_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(amphibious_map, cell_size)
	NavigationServer3D.map_set_cell_height(amphibious_map, NAV_CELL_HEIGHT)
	NavigationServer3D.map_set_active(amphibious_map, true)
	var deep_water_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(deep_water_map, cell_size)
	NavigationServer3D.map_set_cell_height(deep_water_map, NAV_CELL_HEIGHT)
	NavigationServer3D.map_set_active(deep_water_map, true)

	var ground_verts = _build_ground_faces(map_def, extra_holes)
	var ground_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(ground_region, ground_map)
	NavigationServer3D.region_set_navigation_mesh(ground_region, _bake_nav_mesh(ground_verts, cell_size))

	var water_verts = PackedVector3Array()
	for w in map_def.get("water_areas", []):
		var rect = _rect_from(w.center, w.half_extents)
		_add_nav_quad(water_verts, Vector3(rect.x0, 0, rect.z0), Vector3(rect.x1, 0, rect.z0),
			Vector3(rect.x1, 0, rect.z1), Vector3(rect.x0, 0, rect.z1))
	for blob in map_def.get("water_blobs", []):
		water_verts.append_array(_water_blob_fan_verts(blob, 0.0))
	var water_region: RID = RID()
	if water_verts.size() > 0:
		water_region = NavigationServer3D.region_create()
		NavigationServer3D.region_set_map(water_region, water_map)
		NavigationServer3D.region_set_navigation_mesh(water_region, _bake_nav_mesh(water_verts, cell_size))

	var amphibious_verts = _build_amphibious_faces(map_def, extra_holes)
	var amphibious_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(amphibious_region, amphibious_map)
	NavigationServer3D.region_set_navigation_mesh(amphibious_region, _bake_nav_mesh(amphibious_verts, cell_size))

	var deep_water_verts = _build_deep_water_faces(map_def)
	var deep_water_region: RID = RID()
	if deep_water_verts.size() > 0:
		deep_water_region = NavigationServer3D.region_create()
		NavigationServer3D.region_set_map(deep_water_region, deep_water_map)
		NavigationServer3D.region_set_navigation_mesh(deep_water_region, _bake_nav_mesh(deep_water_verts, cell_size))

	return {"ground_map": ground_map, "water_map": water_map, "amphibious_map": amphibious_map, "deep_water_map": deep_water_map,
		"ground_region": ground_region, "water_region": water_region, "amphibious_region": amphibious_region, "deep_water_region": deep_water_region}


# Same as build_navmeshes(), but WITHOUT baking: every map and region RID is
# created and wired up, and the source geometry for each surface is returned
# unbaked in "pending" so the caller can bake them one at a time with a frame
# yielded in between.
#
# WHY, given rebake_ground_and_amphibious_async() already exists. The async
# API is the right tool mid-match, where the old navmesh stays usable until
# the new one lands. It is the wrong tool at match load, because there IS no
# previous navmesh - units spawn and take their first orders within a frame
# or two of _ready(), and a path query against a region with no mesh yet
# silently fails. So the load path still bakes to completion before the match
# starts; it just stops doing all four surfaces inside a single frame.
#
# The cost is unchanged (~4s on lake_crossing, four surfaces at ~1s each).
# What changes is that the main thread ticks between them, so the window
# keeps pumping messages instead of going four seconds without one - which is
# what made Windows grey the title bar and report Not Responding.
#
# Each pending entry is {"region": RID, "verts": PackedVector3Array, "label":
# String}; feed them to bake_pending_entry() in order.
static func build_navmeshes_deferred(map_def: Dictionary, extra_holes: Array = []) -> Dictionary:
	var cell_size = _nav_cell_size(map_def)
	var ground_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(ground_map, cell_size)
	NavigationServer3D.map_set_cell_height(ground_map, NAV_CELL_HEIGHT)
	NavigationServer3D.map_set_active(ground_map, true)
	var water_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(water_map, cell_size)
	NavigationServer3D.map_set_cell_height(water_map, NAV_CELL_HEIGHT)
	NavigationServer3D.map_set_active(water_map, true)
	var amphibious_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(amphibious_map, cell_size)
	NavigationServer3D.map_set_cell_height(amphibious_map, NAV_CELL_HEIGHT)
	NavigationServer3D.map_set_active(amphibious_map, true)
	var deep_water_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(deep_water_map, cell_size)
	NavigationServer3D.map_set_cell_height(deep_water_map, NAV_CELL_HEIGHT)
	NavigationServer3D.map_set_active(deep_water_map, true)

	var pending: Array = []

	var ground_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(ground_region, ground_map)
	pending.append({"region": ground_region, "verts": _build_ground_faces(map_def, extra_holes), "label": "Surveying ground"})

	var water_verts = PackedVector3Array()
	for w in map_def.get("water_areas", []):
		var rect = _rect_from(w.center, w.half_extents)
		_add_nav_quad(water_verts, Vector3(rect.x0, 0, rect.z0), Vector3(rect.x1, 0, rect.z0),
			Vector3(rect.x1, 0, rect.z1), Vector3(rect.x0, 0, rect.z1))
	for blob in map_def.get("water_blobs", []):
		water_verts.append_array(_water_blob_fan_verts(blob, 0.0))
	var water_region: RID = RID()
	if water_verts.size() > 0:
		water_region = NavigationServer3D.region_create()
		NavigationServer3D.region_set_map(water_region, water_map)
		pending.append({"region": water_region, "verts": water_verts, "label": "Charting waterways"})

	var amphibious_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(amphibious_region, amphibious_map)
	pending.append({"region": amphibious_region, "verts": _build_amphibious_faces(map_def, extra_holes), "label": "Marking fording points"})

	var deep_water_verts = _build_deep_water_faces(map_def)
	var deep_water_region: RID = RID()
	if deep_water_verts.size() > 0:
		deep_water_region = NavigationServer3D.region_create()
		NavigationServer3D.region_set_map(deep_water_region, deep_water_map)
		pending.append({"region": deep_water_region, "verts": deep_water_verts, "label": "Sounding deep water"})

	return {"ground_map": ground_map, "water_map": water_map, "amphibious_map": amphibious_map, "deep_water_map": deep_water_map,
		"ground_region": ground_region, "water_region": water_region, "amphibious_region": amphibious_region, "deep_water_region": deep_water_region,
		"pending": pending, "cell_size": cell_size}

static func bake_pending_entry(entry: Dictionary, cell_size: float) -> void:
	NavigationServer3D.region_set_navigation_mesh(entry["region"], _bake_nav_mesh(entry["verts"], cell_size))

# --- Visuals ---

static func spawn_visuals(map_def: Dictionary, parent: Node3D):
	# CORE_DESIGN_LANGUAGE.md §3.1/§3.2: every greeble call below gets the
	# map's resolved world scale, so a pebble stands in for a boulder at the
	# ratio the map actually declares (WorldScaleScript.for_map() falls back
	# to DEFAULT_WORLD_SCALE=1.0 for any map without a "world_scale" key -
	# today's exact, unchanged appearance until that default itself moves).
	var prop_scale = WorldScaleScript.for_map(map_def)
	for w in map_def.get("water_areas", []):
		_spawn_water_plane(w, parent, prop_scale)
	for blob in map_def.get("water_blobs", []):
		_spawn_water_blob(blob, parent, prop_scale)
	for o in map_def.get("obstacles", []):
		_spawn_obstacle(o, parent)
	for s in map_def.get("surface_zones", []):
		_spawn_surface_zone(s, parent, prop_scale)
	for sw in map_def.get("shallow_water_areas", []):
		_spawn_shallow_water_marker(sw, parent, prop_scale)
	for b in map_def.get("bridges", []):
		_spawn_bridge(b, parent)
	_spawn_grassland_clutter(map_def, parent, prop_scale)

# Real baked ground textures (see tools/generate_terrain_textures.gd) tiled
# across each surface_zone's real-world footprint, replacing the old flat
# albedo_color patches - one texture set per surface_type, cached the same
# way HullMaterialBuilder caches per-faction textures (this runs once per
# zone per map load, cheap either way, but no reason to reload the same 3
# PNGs for every zone that shares a surface_type). Every zone plus the
# shallow_water marker also gets non-collidable ground clutter scattered by
# TerrainGreebles - see that file for why real 3D props, not flat cards.
const TERRAIN_TEXTURE_DIR = "res://assets/textures/terrain/"
# Texture repeats once per this many world units - fixed, not derived from
# zone size, since (unlike a Design Lab hull) these zones are static map
# geometry that's never scaled at runtime; a plain tiled UV is enough.
const TERRAIN_TILE_WORLD_SIZE: float = 6.0

static var _terrain_texture_cache: Dictionary = {}
# surface_type -> Array of variant suffixes that actually exist on disk
# (always includes "" for the procedural bake). Probed once per surface.
static var _terrain_variant_cache: Dictionary = {}

# Every surface type has a base bake ({surface}_albedo.png) plus however many
# photographic variants tools/process_flow_terrain_textures.gd has produced
# ({surface}_v1_albedo.png and up). Zones pick between them so that a map
# isn't one identical 6-unit tile stamped out end to end - at RTS zoom the
# camera holds dozens of repeats at once, and the regularity of the grid is
# far more obvious than any individual tile's quality.
#
# The list is DISCOVERED rather than declared, so dropping new variant PNGs in
# (or deleting ones that don't work out) changes the amount of variety with no
# code change here.
#
# Variant 0 (suffix "", the procedural bake from
# tools/generate_terrain_textures.gd) is used ONLY when no photographic
# variant exists. It is deliberately NOT mixed in alongside them: a side-by-
# side grid capture of all four variants per surface made the quality gap
# obvious - the procedural marsh reads as blue blobs on green and the
# procedural snow_mud as pen scribbles, next to actual photographic ground.
# Blending them together doesn't average to something in between, it just
# drags a good surface back toward the clip-art one and reintroduces the
# regular procedural pattern the blend exists to hide. So it stays as the
# guaranteed-present fallback for surfaces no plate has been produced for
# (blue_water, shallow_water, ice), and nothing more.
const MAX_TERRAIN_VARIANTS = 8

static func _get_terrain_variants(surface_type: String) -> Array:
	if _terrain_variant_cache.has(surface_type):
		return _terrain_variant_cache[surface_type]
	var found: Array = []
	for n in range(1, MAX_TERRAIN_VARIANTS + 1):
		var suffix = "_v%d" % n
		if ResourceLoader.exists(TERRAIN_TEXTURE_DIR + surface_type + suffix + "_albedo.png"):
			found.append(suffix)
	if found.is_empty():
		found = [""]
	_terrain_variant_cache[surface_type] = found
	return found

# Deterministic variant choice from a world position. Seeded from the zone's
# own centre rather than a global RNG for the same reason the coastline wobble
# above is: map geometry has to look identical every time a map loads, or a
# saved game / rejoined match would repaint the ground. Quantised to whole
# units first so floating-point noise in a zone centre can't flip the choice
# between two runs.
static func _variant_for_position(surface_type: String, x: float, z: float) -> String:
	var variants = _get_terrain_variants(surface_type)
	if variants.size() <= 1:
		return ""
	var seed_val = hash("%s:%d:%d" % [surface_type, int(round(x)), int(round(z))])
	return variants[abs(seed_val) % variants.size()]

static func _get_terrain_textures(surface_type: String, variant: String = "") -> Dictionary:
	var key = surface_type + variant
	if _terrain_texture_cache.has(key):
		return _terrain_texture_cache[key]
	var base = TERRAIN_TEXTURE_DIR + surface_type + variant
	var textures = {
		"albedo": load(base + "_albedo.png"),
		"normal": load(base + "_normal.png"),
		"roughness": load(base + "_roughness.png"),
	}
	_terrain_texture_cache[key] = textures
	return textures

# `tile_scale` multiplies TERRAIN_TILE_WORLD_SIZE - CORE_DESIGN_LANGUAGE.md
# §3.2: at a larger world scale, the ground texture's own texel density has
# to grow along with the greeble dressing sitting on top of it (see Chunk 5-
# 8 above), or the texture would read as shrinking relative to everything
# else. Callers that already resolved a prop_scale for their greeble calls
# (Chunk 7) pass the same value here - one resolved scale per call site, not
# two independently-drifting ones.
static func _build_terrain_material(surface_type: String, footprint: Vector2, tint: Color = Color.WHITE, variant: String = "", tile_scale: float = 1.0) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	var tex = _get_terrain_textures(surface_type, variant)
	mat.albedo_texture = tex.albedo
	mat.albedo_color = tint
	mat.roughness_texture = tex.roughness
	mat.roughness = 1.0
	mat.normal_enabled = true
	mat.normal_texture = tex.normal
	var tile_size = TERRAIN_TILE_WORLD_SIZE * tile_scale
	mat.uv1_scale = Vector3(footprint.x / tile_size, footprint.y / tile_size, 1.0)
	return mat

# The baseline ground plane's material - called by skirmish.gd for the map-
# wide Ground box mesh (everywhere that isn't a special surface_zone/water/
# obstacle/elevation footprint). Unlike the 5 special-case types, this one
# gets a real per-map TINT on top of the baked "grassland" texture: each
# map's own ground_color (map_catalog.gd) used to be the ONLY visual
# variation between maps' baseline ground, and dropping that entirely in
# favor of one identical texture everywhere would flatten a real (if
# subtle) piece of per-map identity. lightened() first so multiplying by
# the baked texture's own mid-tone albedo doesn't compound into something
# far darker than either color alone.
static func build_ground_material(ground_color: Color, footprint: Vector2) -> StandardMaterial3D:
	return _build_terrain_material("grassland", footprint, ground_color.lightened(0.55))

# Same baked grassland texture as build_ground_material(), but for
# build_ground_visual_mesh()'s dense heightmap mesh, which bakes its own
# absolute-world-position UVs directly into the mesh (see that function) -
# no footprint-relative uv1_scale needed on the material itself.
#
# This one uses the multi-variant blend shader rather than a plain
# StandardMaterial3D, because it's the single worst repetition offender in the
# game: one 6-unit tile stretched over the entire map. See
# shaders/terrain_ground.gdshader for why the blend is a fade driven by
# low-frequency noise rather than a hard per-patch choice.
#
# Returns Material, not StandardMaterial3D - callers assign it straight to
# material_override, which is typed Material anyway.
const GROUND_BLEND_SHADER = preload("res://shaders/terrain_ground.gdshader")

static func build_ground_material_heightmap(ground_color: Color) -> Material:
	return build_blended_surface_material("grassland", ground_color.lightened(0.55))

# Builds a variant-blending material for any surface type. Falls back to
# whatever variants actually exist - a surface with only its procedural bake
# gets variant_count 1 and behaves exactly as before, so this is safe to point
# at a surface no photographic plate has been produced for yet.
static func build_blended_surface_material(surface_type: String, tint: Color = Color.WHITE) -> Material:
	var variants = _get_terrain_variants(surface_type)
	var mat = ShaderMaterial.new()
	mat.shader = GROUND_BLEND_SHADER
	var count = mini(variants.size(), 3)
	mat.set_shader_parameter("variant_count", count)
	for i in range(count):
		var tex = _get_terrain_textures(surface_type, variants[i])
		mat.set_shader_parameter("albedo_%d" % i, tex.albedo)
		mat.set_shader_parameter("normal_%d" % i, tex.normal)
		mat.set_shader_parameter("rough_%d" % i, tex.roughness)
	mat.set_shader_parameter("ground_tint", tint)
	return mat

# Skirmish refinement pass: replaces the old flat single BoxMesh "Ground"
# node with a real subdivided surface whose every vertex samples height_at()
# - this is what makes the visual ground, the navmesh, and every unit/
# building's Y-snap all agree on the same terrain instead of a flat plane
# hiding a bumpy navmesh underneath it (which would look like floating/
# sinking units). Returns both the renderable mesh AND a matching
# HeightMapShape3D so weapon-LOS raycasts and click-to-ground order/
# placement raycasts (which hit this same collider, see skirmish.gd's
# _raycast_ground()/_has_line_of_sight()) resolve against the real surface
# too, not a stale flat one.
#
# Two different sample resolutions on purpose: the collision heightmap
# samples every 1 world unit (HeightMapShape3D's native, cheapest-correct
# resolution - a 300-unit map is still only ~90k samples, built once at
# scene setup) while the visual mesh uses a coarser GROUND_MESH_RESOLUTION
# grid (fewer triangles to render/light). Both sample the exact same
# height_at() function, so the difference between them is sub-unit smoothing
# imperceptible at gameplay camera distances, not a real mismatch.
const GROUND_MESH_RESOLUTION: float = 3.0
# Collision heightmap sample spacing, in world units. Kept coarser than the
# visual mesh on purpose: HeightMapShape3D always spaces samples exactly 1
# LOCAL unit apart (no separate "cell size" it exposes), so covering a big
# map at 1 WORLD unit per sample means a literal quadratic map_half_extents^2
# blowup in GDScript-side height_at() calls at scene load - harmless at the
# old ~80-120 half-extent range, but genuinely slow (tens of seconds per
# match, times every Skirmish instance the test suite spins up) once maps
# grew to the ~200-240 range. Instead, sample every COLLISION_STEP world
# units and stretch the collision shape's OWN node scale (X/Z only, Y stays
# 1.0 so real height values are untouched) to cover the full map - see
# build_ground_visual_mesh()'s returned "collision_scale", applied by
# skirmish.gd to the CollisionShape3D node. A few world units of horizontal
# collision resolution is imperceptible for raycasts (weapon LOS, click-to-
# ground) against terrain this gently undulating.
const COLLISION_HEIGHTMAP_STEP: float = 3.0

static func build_ground_visual_mesh(map_def: Dictionary) -> Dictionary:
	var half: float = map_def.get("map_half_extents", 80.0)

	# height_at() is genuinely expensive at scale (noise sample + hill/blob
	# loops) and every interior grid corner is shared by up to 4 quads in
	# this non-indexed triangle list - memoizing within this one build call
	# cuts the visual mesh's height_at() calls by roughly 4x for free.
	var h_cache: Dictionary = {}
	var _h = func(hx: float, hz: float) -> float:
		var key = Vector2(hx, hz)
		if h_cache.has(key): return h_cache[key]
		var v = height_at(map_def, hx, hz)
		h_cache[key] = v
		return v

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x = -half
	while x < half:
		var x1 = min(x + GROUND_MESH_RESOLUTION, half)
		var z = -half
		while z < half:
			var z1 = min(z + GROUND_MESH_RESOLUTION, half)
			var a = Vector3(x, _h.call(x, z), z)
			var b = Vector3(x1, _h.call(x1, z), z)
			var c = Vector3(x1, _h.call(x1, z1), z1)
			var d = Vector3(x, _h.call(x, z1), z1)
			for v in [a, b, c, a, c, d]:
				st.set_uv(Vector2(v.x, v.z) / TERRAIN_TILE_WORLD_SIZE)
				st.add_vertex(v)
			z = z1
		x = x1
	st.generate_normals()
	var mesh = st.commit()

	var samples = int(half * 2.0 / COLLISION_HEIGHTMAP_STEP) + 1
	var height_data = PackedFloat32Array()
	height_data.resize(samples * samples)
	for row in range(samples):
		var wz = -half + row * COLLISION_HEIGHTMAP_STEP
		for col in range(samples):
			var wx = -half + col * COLLISION_HEIGHTMAP_STEP
			height_data[row * samples + col] = height_at(map_def, wx, wz)
	var shape = HeightMapShape3D.new()
	shape.map_width = samples
	shape.map_depth = samples
	shape.map_data = height_data

	return {"mesh": mesh, "shape": shape, "samples": samples, "collision_scale": Vector3(COLLISION_HEIGHTMAP_STEP, 1.0, COLLISION_HEIGHTMAP_STEP)}

static func _spawn_surface_zone(zone: Dictionary, parent: Node3D, prop_scale: float = 1.0):
	var mesh_inst = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	var footprint = Vector2(zone.half_extents.x * 2.0, zone.half_extents.y * 2.0)
	plane.size = footprint
	mesh_inst.mesh = plane
	var surface_type = zone.get("surface_type", "")
	mesh_inst.material_override = _build_terrain_material(
		surface_type, footprint, Color.WHITE,
		_variant_for_position(surface_type, zone.center.x, zone.center.z), prop_scale)
	parent.add_child(mesh_inst)
	mesh_inst.global_position = Vector3(zone.center.x, 0.03, zone.center.z)

	TerrainGreeblesScript.scatter(zone, parent, prop_scale)

# A lighter, sandier-toned marker over the shallow sub-area of a water
# zone (drawn on top of the main water plane, slightly higher Y) - purely
# a visual cue that this patch is shallow-draught-only; the real
# passability distinction lives in the deep_water_map navmesh (see
# build_navmeshes()).
static func _spawn_shallow_water_marker(zone: Dictionary, parent: Node3D, prop_scale: float = 1.0):
	var mesh_inst = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	var footprint = Vector2(zone.half_extents.x * 2.0, zone.half_extents.y * 2.0)
	plane.size = footprint
	mesh_inst.mesh = plane
	var mat = _build_terrain_material("shallow_water", footprint, Color.WHITE, "", prop_scale)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.8)
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)
	mesh_inst.global_position = Vector3(zone.center.x, 0.06, zone.center.z)

	TerrainGreeblesScript.scatter_shallow_water(zone, parent, prop_scale)

# Baseline deep water - the baked "blue_water" texture (deeper, more
# desaturated, subtle current/glint - see generate_terrain_textures.gd)
# replaces the old flat albedo_color, with a HIGHER alpha than
# shallow_water's marker (0.93 vs 0.8) so it deliberately reads more
# opaque/deep rather than shallow_water's see-through/sandy-bed look, per
# the two types' whole point of contrast.
static func _spawn_water_plane(water: Dictionary, parent: Node3D, prop_scale: float = 1.0):
	var mesh_inst = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	var footprint = Vector2(water.half_extents.x * 2.0, water.half_extents.y * 2.0)
	plane.size = footprint
	mesh_inst.mesh = plane
	var mat = _build_terrain_material("blue_water", footprint, Color.WHITE, "", prop_scale)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.93)
	mat.emission_enabled = true
	mat.emission = Color(0.06, 0.13, 0.22)
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)
	mesh_inst.global_position = Vector3(water.center.x, 0.05, water.center.z)

	TerrainGreeblesScript.scatter_blue_water(water, parent, prop_scale)

# Organic counterpart to _spawn_water_plane() - a real triangle-fan mesh
# matching the blob's per-angle coastline (same geometry the navmesh hole
# and terrain dip use, see _water_blob_fan_verts()) instead of a rectangular
# PlaneMesh, so the visible water shape actually reads as a natural lake
# rather than a blocky rectangle. UVs are baked directly from absolute
# world position (no per-mesh footprint to scale against, unlike a
# PlaneMesh's built-in 0..1 UV), same tiling density as every other terrain
# material via TERRAIN_TILE_WORLD_SIZE.
static func _spawn_water_blob(blob: Dictionary, parent: Node3D, prop_scale: float = 1.0):
	var verts = _water_blob_fan_verts(blob, 0.05)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		st.set_uv(Vector2(v.x, v.z) / (TERRAIN_TILE_WORLD_SIZE * prop_scale))
		st.add_vertex(v)
	st.generate_normals()

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	var tex = _get_terrain_textures("blue_water")
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = tex.albedo
	mat.roughness_texture = tex.roughness
	mat.roughness = 1.0
	mat.normal_enabled = true
	mat.normal_texture = tex.normal
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.93)
	mat.emission_enabled = true
	mat.emission = Color(0.06, 0.13, 0.22)
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)

	TerrainGreeblesScript.scatter_blue_water({"center": blob.center, "half_extents": Vector2(blob.get("radius", 10.0), blob.get("radius", 10.0))}, parent, prop_scale)

static func _spawn_obstacle(obstacle: Dictionary, parent: Node3D):
	var obstacle_type = obstacle.get("type", "rock")
	var collider_height = 3.0
	if obstacle_type == "building":
		collider_height = _spawn_building_obstacle(obstacle, parent)
	else:
		collider_height = _spawn_rock_obstacle(obstacle, parent)

	# Real collision (same "Ground only" layer as the flat terrain) so units
	# physically can't clip through even if steering pushes them off-path,
	# and the build-placement raycast can't resolve a spot inside the
	# footprint to a flat position either - belt-and-suspenders on top of
	# the navmesh hole and the explicit is_position_blocked() reject. This
	# is also what makes obstacles (rock clusters AND buildings alike) real
	# COVER, not just movement blockers: auto_weapon.gd's own line-of-sight
	# raycast already checks this same collision_layer (1) for weapon fire,
	# and skirmish.gd's fog-of-war vision check now does too (see
	# _recalc_fog_of_war()'s LOS raycast) - a tall obstacle on this layer
	# blocks both automatically, no obstacle-type-specific wiring needed.
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(obstacle.half_extents.x * 2.0, collider_height, obstacle.half_extents.y * 2.0)
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = Vector3(obstacle.center.x, collider_height / 2.0, obstacle.center.z)

# A rough rock cluster filling the footprint - primitive meshes, not a new
# Blender asset (avoids the fragile import pipeline for pure decoration).
# Seeded from position so a given map's obstacles always look the same run
# to run (deterministic for screenshot verification). Returns the collider
# height _spawn_obstacle() should use for this obstacle.
static func _spawn_rock_obstacle(obstacle: Dictionary, parent: Node3D) -> float:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(obstacle.center)
	for i in range(5):
		var rock = MeshInstance3D.new()
		var box = BoxMesh.new()
		var size = Vector3(rng.randf_range(1.2, 2.4), rng.randf_range(1.0, 2.2), rng.randf_range(1.2, 2.4))
		box.size = size
		rock.mesh = box
		var mat = StandardMaterial3D.new()
		var shade = rng.randf_range(0.35, 0.5)
		mat.albedo_color = Color(shade, shade * 0.95, shade * 0.9)
		mat.roughness = 0.95
		rock.material_override = mat
		parent.add_child(rock)
		var ox = rng.randf_range(-obstacle.half_extents.x * 0.7, obstacle.half_extents.x * 0.7)
		var oz = rng.randf_range(-obstacle.half_extents.y * 0.7, obstacle.half_extents.y * 0.7)
		rock.global_position = Vector3(obstacle.center.x + ox, size.y / 2.0, obstacle.center.z + oz)
		rock.rotation.y = rng.randf_range(0, TAU)
	return 3.0

# A single boxy building filling the footprint - flat walls, a flat roof
# cap, and a few window-slit/AC-unit greebles, deliberately a different
# silhouette from the rock cluster's jumble of boulders (a single solid
# structure, not a pile of debris) since it's meant to read as real urban
# cover, not decoration. Taller than a rock cluster by default (real
# buildings are taller than a rock pile, and a taller collider makes the
# vision/weapon LOS-blocking this enables much more visually legible).
static func _spawn_building_obstacle(obstacle: Dictionary, parent: Node3D) -> float:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(obstacle.center)
	var height = obstacle.get("building_height", rng.randf_range(5.0, 8.0))

	var walls = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(obstacle.half_extents.x * 2.0, height, obstacle.half_extents.y * 2.0)
	walls.mesh = box
	var mat = StandardMaterial3D.new()
	var shade = rng.randf_range(0.32, 0.42)
	mat.albedo_color = Color(shade * 0.9, shade * 0.92, shade)
	mat.roughness = 0.8
	walls.material_override = mat
	parent.add_child(walls)
	walls.global_position = Vector3(obstacle.center.x, height / 2.0, obstacle.center.z)

	var roof = MeshInstance3D.new()
	var roof_box = BoxMesh.new()
	roof_box.size = Vector3(obstacle.half_extents.x * 2.05, 0.3, obstacle.half_extents.y * 2.05)
	roof.mesh = roof_box
	var roof_mat = StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.25, 0.24, 0.24)
	roof_mat.roughness = 0.9
	roof.material_override = roof_mat
	parent.add_child(roof)
	roof.global_position = Vector3(obstacle.center.x, height + 0.15, obstacle.center.z)

	# Window-slit greebles on the two long faces - purely cosmetic, no
	# collision of their own (the single wall box above already owns it).
	var rows = int(height / 1.6)
	var cols = 3
	for row in range(rows):
		for col in range(cols):
			var window = MeshInstance3D.new()
			var wbox = BoxMesh.new()
			wbox.size = Vector3(0.6, 0.7, 0.05)
			window.mesh = wbox
			var wmat = StandardMaterial3D.new()
			wmat.albedo_color = Color(0.55, 0.6, 0.45)
			wmat.emission_enabled = true
			wmat.emission = Color(0.4, 0.42, 0.3)
			window.material_override = wmat
			parent.add_child(window)
			var wx = obstacle.center.x + (col - (cols - 1) / 2.0) * (obstacle.half_extents.x * 2.0 / (cols + 1))
			var wy = 1.2 + row * 1.6
			window.global_position = Vector3(wx, wy, obstacle.center.z + obstacle.half_extents.y + 0.03)
	return height

# A raised deck spanning the bridge's full footprint (real geometry, not
# just a color patch - it's the visual proof the navmesh carve-out actually
# corresponds to a walkable structure) plus two low guard-rail strips along
# the long edges. The crossing axis is whichever of half_extents is larger
# (a bridge is always longer than it is wide), so the rails run parallel to
# travel regardless of whether the map orients the crossing along X or Z.
static func _spawn_bridge(bridge: Dictionary, parent: Node3D):
	var c: Vector3 = bridge.center
	var he: Vector2 = bridge.half_extents
	var deck_h: float = bridge.get("deck_height", BRIDGE_DECK_HEIGHT)

	var deck = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(he.x * 2.0, deck_h, he.y * 2.0)
	deck.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.42, 0.32)
	mat.roughness = 0.8
	deck.material_override = mat
	parent.add_child(deck)
	deck.global_position = Vector3(c.x, deck_h / 2.0, c.z)

	var long_axis_x = he.x >= he.y
	var rail_h = 0.5
	var rail_thickness = 0.3
	for side in [-1.0, 1.0]:
		var rail = MeshInstance3D.new()
		# add_child BEFORE assigning global_position, matching the deck above.
		# The rails used to be added at the end of this loop body, after their
		# global_position was set - and a Node3D outside the tree has no global
		# transform, so each assignment logged "Condition !is_inside_tree() is
		# true" and was applied to the LOCAL position instead. That happened to
		# land the rails correctly anyway, purely because `parent` here is the
		# Skirmish scene root (terrain_builder.spawn_visuals(current_map, self)),
		# which sits at the origin with an identity transform - so local and
		# global coincided. Reordering is therefore visually identical today;
		# it removes two spurious errors per bridge at map load and the latent
		# trap that the moment terrain is ever parented under an offset node,
		# the rails would silently jump while the deck stayed put.
		parent.add_child(rail)
		var rail_box = BoxMesh.new()
		if long_axis_x:
			rail_box.size = Vector3(he.x * 2.0, rail_h, rail_thickness)
			rail.mesh = rail_box
			rail.global_position = Vector3(c.x, deck_h + rail_h / 2.0, c.z + side * (he.y - rail_thickness / 2.0))
		else:
			rail_box.size = Vector3(rail_thickness, rail_h, he.y * 2.0)
			rail.mesh = rail_box
			rail.global_position = Vector3(c.x + side * (he.x - rail_thickness / 2.0), deck_h + rail_h / 2.0, c.z)
		var rail_mat = StandardMaterial3D.new()
		rail_mat.albedo_color = Color(0.35, 0.32, 0.28)
		rail_mat.roughness = 0.7
		rail.material_override = rail_mat

# Sparse grassland ground clutter (grass tufts/rocks/brush) scattered
# across the WHOLE map's baseline ground - deliberately not per-area-dense
# like the small surface_zone scatters (see terrain_greebles.gd's own
# comment on why: hundreds of props across a 100+ half-extent map would be
# a real, pointless cost). Count is capped low and rejects any point that
# would land somewhere already visually claimed by something else: water/
# obstacles/ramps (is_position_blocked - covers the common cases), bridges
# (not covered by is_position_blocked, real decking shouldn't have grass
# tufts through it), any surface_zone's own footprint (already gets its
# OWN dedicated texture+greebles - stacking grassland clutter on top would
# look like two terrain treatments fighting), and a fixed radius around
# every start structure/resource node (keeps HQs/factories/harvester spots
# visually clear). A point that survives all that still gets its real
# terrain_height_at() Y, not an assumed 0 - a scattered point can legally
# land on an elevation zone's plateau TOP (is_position_blocked deliberately
# doesn't exclude that - see that function's own comment), and a grass
# tuft placed at y=0 under a raised plateau would look buried.
const GRASSLAND_CLUTTER_AVOID_RADIUS: float = 7.0

static func _spawn_grassland_clutter(map_def: Dictionary, parent: Node3D, prop_scale: float = 1.0):
	var half: float = map_def.get("map_half_extents", 80.0)
	var area = (half * 2.0) * (half * 2.0)
	var count = clamp(int(area / 2000.0), 20, 50)

	var avoid_points: Array = []
	# RTS_CORE_ROADMAP.md B3: player_start/enemy_start became a spawns
	# array - same "every position field in each start group" collection,
	# just skipping the new "id" string field.
	for spawn in map_def.get("spawns", []):
		for key in spawn.keys():
			if key == "id": continue
			avoid_points.append(spawn[key])
	for r in map_def.get("resource_nodes", []):
		avoid_points.append(r.position)

	var bridge_rects = _collect_bridges(map_def)
	var surface_rects = []
	for s in map_def.get("surface_zones", []):
		surface_rects.append(_rect_from(s.center, s.half_extents))

	var rng = RandomNumberGenerator.new()
	rng.seed = hash(map_def.get("name", "grassland"))
	var placed = 0
	var attempts = 0
	while placed < count and attempts < count * 8:
		attempts += 1
		var pos = Vector3(rng.randf_range(-half * 0.94, half * 0.94), 0, rng.randf_range(-half * 0.94, half * 0.94))
		if is_position_blocked(map_def, pos):
			continue
		var rejected = false
		for rect in bridge_rects:
			if _point_in_rect(pos, rect):
				rejected = true
				break
		if not rejected:
			for rect in surface_rects:
				if _point_in_rect(pos, rect):
					rejected = true
					break
		if not rejected:
			for a in avoid_points:
				if Vector2(pos.x - a.x, pos.z - a.z).length() < GRASSLAND_CLUTTER_AVOID_RADIUS:
					rejected = true
					break
		if rejected:
			continue
		pos.y = terrain_height_at(map_def, pos)
		TerrainGreeblesScript.place_grassland_prop(pos, rng.randi(), parent, prop_scale)
		placed += 1

	# CORE_DESIGN_LANGUAGE.md §2.1/§7.1: tall clutter (TerrainGreebles.
	# _place_tall_brush()) is only legal OFF the playable surface - the map's
	# outer edge margin (beyond the 0.94 band the sprinkle above stays
	# within) or a position a steep slope has already made unreachable
	# (is_position_blocked() true for that reason, not because it's water or
	# an obstacle, where nothing should render at all). Unit readability
	# during a fight is a gameplay requirement, so this pass deliberately
	# never lands on the interior navigable surface the loop above sprinkles
	# short props across - full-height brush there would let a unit vanish
	# behind foliage mid-engagement.
	var tall_rng = RandomNumberGenerator.new()
	tall_rng.seed = hash(map_def.get("name", "grassland")) + 1
	var tall_placed = 0
	var tall_attempts = 0
	while tall_placed < count and tall_attempts < count * 8:
		tall_attempts += 1
		var pos = Vector3(tall_rng.randf_range(-half, half), 0, tall_rng.randf_range(-half, half))
		if _is_over_water_or_obstacle(map_def, pos):
			continue
		var on_edge = absf(pos.x) > half * 0.94 or absf(pos.z) > half * 0.94
		var steep_slope = not on_edge and is_position_blocked(map_def, pos)
		if not (on_edge or steep_slope):
			continue
		var rejected = false
		for rect in bridge_rects:
			if _point_in_rect(pos, rect):
				rejected = true
				break
		if rejected:
			continue
		pos.y = terrain_height_at(map_def, pos)
		TerrainGreeblesScript.place_grassland_prop(pos, tall_rng.randi(), parent, prop_scale, true)
		tall_placed += 1

# --- Queries (pure functions, no Node dependency - callable from tests
# directly against a MapCatalog dictionary) ---

# The single source of truth for "what Y should something at this XZ sit
# at" - consulted for building placement, unit spawn positions, and every
# moving ground unit's per-tick Y snap. Because it's the ONLY place Y gets
# set for elevated terrain, vision (fog-of-war distance check) and combat
# (damage_resolver's hit_origin/defender Y comparison) automatically react
# to real elevation differences without needing their own map awareness -
# they just compare whatever Y values units/buildings already carry.
static func terrain_height_at(map_def: Dictionary, pos: Vector3) -> float:
	for b in map_def.get("bridges", []):
		if _point_in_rect(pos, _rect_from(b.center, b.half_extents)):
			return b.get("deck_height", BRIDGE_DECK_HEIGHT)
	# Real continuous terrain (noise + any authored hills/water_blobs, or a
	# real heightmap - see height_at()'s own header comment) for everywhere
	# a bridge deck doesn't apply.
	return height_at(map_def, pos.x, pos.z)

# Water, obstacles, and (on a heightmap-backed map) steep slopes are all
# "can't stand/build here" - a plateau's flat TOP is deliberately walkable
# (legitimate, valuable buildable high ground - the whole point of holding
# it), only the slope leading up to it can exceed MAX_WALKABLE_SLOPE.
# Surface terrain type at a point ("" if not inside any surface_zones entry -
# plain ground). Purely a speed-multiplier lookup (see ModuleCatalog.
# get_terrain_speed_multiplier()) consulted every physics tick by
# battle_unit.gd, NOT a navmesh/passability concern - unlike water/
# obstacles/elevation, surface_zones never appear in _collect_holes() or
# any navmesh build, since every locomotor type CAN physically enter marsh/
# rock/mud/sand, just at a different speed. Overlapping zones resolve to
# whichever is listed first (maps are expected to keep these non-
# overlapping in practice; not worth a more elaborate blend for a cosmetic-
# adjacent terrain-flavor system).
static func get_surface_type_at(map_def: Dictionary, pos: Vector3) -> String:
	# RTS_CORE_ROADMAP.md B4: a surfacemap FULLY REPLACES the rect
	# surface_zones lookup below (build_terrain.py bakes surface_zones
	# INTO the surfacemap at generation time - see its build_surfacemap(),
	# same first-listed-wins overlap rule - so this isn't a second,
	# divergent source of truth once a map actually has one). Flag-gated:
	# none of the 8 bundled maps set terrain.surfacemap yet.
	var surfacemap_img = _get_surfacemap_image(map_def)
	if surfacemap_img:
		var half: float = map_def.get("map_half_extents", 80.0)
		return _sample_surfacemap(surfacemap_img, half, pos.x, pos.z, WorldScaleScript.for_map(map_def))

	for z in map_def.get("surface_zones", []):
		if _point_in_rect(pos, _rect_from(z.center, z.half_extents)):
			return z.get("surface_type", "")
	return ""

# Water only (no obstacles/slope) - RTS_CORE_ROADMAP.md B9's minimap bake
# wants "is this cell water" for its blue tint, not "is this cell
# unwalkable" (an obstacle or over-slope cell should still read as its
# normal ground color on the minimap, just with a blip/prop on top of it).
static func is_water_at(map_def: Dictionary, x: float, z: float) -> bool:
	var pos = Vector3(x, 0, z)
	for w in map_def.get("water_areas", []):
		if _point_in_rect(pos, _rect_from(w.center, w.half_extents)):
			return true
	for blob in map_def.get("water_blobs", []):
		if _point_in_water_blob(blob, x, z):
			return true
	return false

# Water or an obstacle footprint, with no slope check - split out of
# is_position_blocked() so the grassland-clutter tall/short decor split
# (see _spawn_grassland_clutter()'s CORE_DESIGN_LANGUAGE.md §3.1 comment)
# can ask "is this actually submerged/occupied" separately from "is this
# unreachable because of slope" - grass shouldn't ever render floating on
# water or poking through a building regardless of which decor tier it's
# in, but a steep slope is exactly the terrain tall brush is FOR.
static func _is_over_water_or_obstacle(map_def: Dictionary, pos: Vector3) -> bool:
	for w in map_def.get("water_areas", []):
		if _point_in_rect(pos, _rect_from(w.center, w.half_extents)):
			return true
	for o in map_def.get("obstacles", []):
		if _point_in_rect(pos, _rect_from(o.center, o.half_extents)):
			return true
	for blob in map_def.get("water_blobs", []):
		if _point_in_water_blob(blob, pos.x, pos.z):
			return true
	return false

static func is_position_blocked(map_def: Dictionary, pos: Vector3) -> bool:
	if _is_over_water_or_obstacle(map_def, pos):
		return true
	# RTS_CORE_ROADMAP.md B4: a heightmap makes slope-blocking meaningful
	# everywhere, not just near authored hills (_slope_at() calls
	# height_at(), which already checks the heightmap first internally).
	var has_heightmap = _get_heightmap_image(map_def) != null
	if (has_heightmap or not map_def.get("hills", []).is_empty()) and _slope_at(map_def, pos.x, pos.z) > MAX_WALKABLE_SLOPE:
		return true
	return false
