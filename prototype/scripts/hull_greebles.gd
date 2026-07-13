extends RefCounted
class_name HullGreebles
# Alpha-cutout greeble/fin cards - cheap, non-collidable decorative geometry
# that extends PAST the hull's real mesh/collision silhouette on purpose
# (per Chris's explicit ask - a deliberate, faction-specific exception to
# the "goofy lives in detail-scale, never silhouette-scale" rule from
# VISUAL_ART_DIRECTION.md 1.2, logged in DECISIONS_NEEDED.md). Only 5 of
# the 10 factions get this treatment; every other faction's apply_greebles()
# call is a no-op (an empty "HullGreebles" container, zero children).
#
# Alpha-cutout textures are generated procedurally at runtime (a small
# Image drawn pixel-by-pixel, wrapped in an ImageTexture) rather than
# hand-painted PNG assets - this project has zero texture files anywhere
# and the Blender import pipeline has been the single most fragile part of
# it all week; a runtime-generated cutout shape needs no import step and no
# external file at all, staying consistent with the rest of the faction
# system's "shader/procedural, not hand-authored art" approach. Each shape
# is generated ONCE and cached (the shape is faction-INDEPENDENT - only the
# tint color varies by faction, same "shared library, just re-tinted"
# pattern the design doc already established for hull paint).

const FactionCatalogScript = preload("res://scripts/faction_catalog.gd")

const CARD_TEXTURE_SIZE: int = 48
static var _texture_cache: Dictionary = {}

static func _get_cutout_texture(shape: String) -> ImageTexture:
	if _texture_cache.has(shape):
		return _texture_cache[shape]
	var img = Image.create(CARD_TEXTURE_SIZE, CARD_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match shape:
		"scrap": _draw_scrap(img)
		"net": _draw_net(img)
		"pennant": _draw_pennant(img)
		"streamer": _draw_streamer(img)
	var tex = ImageTexture.create_from_image(img)
	_texture_cache[shape] = tex
	return tex

# Jagged bent antenna/pipe silhouette - a thick zigzag line (Salvage Union's
# jury-rigged scrap bits sticking out at odd angles).
static func _draw_scrap(img: Image):
	var n = img.get_width()
	var joints = [0.15, 0.55, 0.35, 0.75, 0.2]
	for x in range(n):
		var u = float(x) / n
		var seg = clamp(int(u * (joints.size() - 1)), 0, joints.size() - 2)
		var t = u * (joints.size() - 1) - seg
		var center_v = lerp(joints[seg], joints[seg + 1], t)
		var half_thick = 0.09
		for y in range(n):
			var v = float(y) / n
			if abs(v - center_v) <= half_thick:
				img.set_pixel(x, y, Color(1, 1, 1, 1))

# Diagonal lattice - actual draped camo-netting cutout (Bayou Irregulars).
static func _draw_net(img: Image):
	var n = img.get_width()
	var freq = 7.0
	var line_width = 0.16
	for x in range(n):
		for y in range(n):
			var u = float(x) / n
			var v = float(y) / n
			var d1 = abs(fposmod((u + v) * freq, 1.0) - 0.5)
			var d2 = abs(fposmod((u - v) * freq, 1.0) - 0.5)
			if d1 < line_width or d2 < line_width:
				img.set_pixel(x, y, Color(1, 1, 1, 1))

# A hanging ceremonial banner: full-width body, tapering to a point at the
# bottom (Crimson Concordat).
static func _draw_pennant(img: Image):
	var n = img.get_width()
	for y in range(n):
		var v = float(y) / n
		var half_width = 0.42
		if v > 0.5:
			half_width = 0.42 * (1.0 - clamp((v - 0.5) / 0.5, 0.0, 1.0))
		for x in range(n):
			var u = float(x) / n
			if abs(u - 0.5) <= half_width:
				img.set_pixel(x, y, Color(1, 1, 1, 1))

# A swept, gently S-curved tapering fin/streamer (Aerodrome Cartel's
# art-deco tailfin flourish).
static func _draw_streamer(img: Image):
	var n = img.get_width()
	for x in range(n):
		var u = float(x) / n
		var center_v = 0.5 + sin(u * PI) * 0.22
		var half_width = 0.16 * (1.0 - u * 0.75)
		for y in range(n):
			var v = float(y) / n
			if abs(v - center_v) <= half_width:
				img.set_pixel(x, y, Color(1, 1, 1, 1))

static func _make_cutout_material(shape: String, color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = _get_cutout_texture(shape)
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED # visible from both sides - no back-face pop as the hull turns
	mat.roughness = 0.75
	return mat

static func _add_card(container: Node3D, shape: String, color: Color, size: Vector2, pos: Vector3, rot: Vector3):
	var card = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = size
	card.mesh = quad
	card.material_override = _make_cutout_material(shape, color)
	container.add_child(card)
	card.position = pos
	card.rotation = rot

# Removes any previously-attached greebles (so faction changes in the
# Design Lab don't accumulate duplicates) and rebuilds from scratch. A
# no-op container (zero children) for the 5 untreated factions.
static func apply_greebles(hull: Node3D, faction: String, hull_size: Vector3):
	var old = hull.get_node_or_null("HullGreebles")
	if old:
		hull.remove_child(old)
		old.queue_free()
	var container = Node3D.new()
	container.name = "HullGreebles"
	hull.add_child(container)

	match faction:
		"salvage_union": _build_scrap(container, faction, hull_size)
		"bayou_irregulars": _build_net(container, faction, hull_size)
		"crimson_concordat": _build_pennants(container, faction, hull_size)
		"aerodrome_cartel": _build_streamers(container, faction, hull_size)
		"dune_runners": _build_barrels(container, hull_size)
		_: pass # every other faction stays clean - no greebles at all

# Salvage Union: 3 jury-rigged scrap antennas/pipes at odd angles, scattered
# across the top and sides - deliberately irregular (varied rotation/scale),
# never all pointing the same way, matching "nothing's original equipment."
static func _build_scrap(container: Node3D, faction: String, hull_size: Vector3):
	# Bright exposed-metal tone, not the faction's own dark worn paint color -
	# real scrap/scavenged fittings read as scavenged precisely because they
	# DON'T match the hull's own weathered finish. Using Salvage Union's own
	# base_color here (grey, close in tone to their heavily-worn near-black
	# hull) made the first pass nearly invisible against its own paint job.
	var color = Color(0.68, 0.64, 0.58)
	var rigs = [
		{"pos": Vector3(hull_size.x * 0.32, hull_size.y * 0.85, hull_size.z * 0.1), "rot": Vector3(0.1, 0.4, 0.3), "scale": 1.4},
		{"pos": Vector3(-hull_size.x * 0.38, hull_size.y * 0.8, -hull_size.z * 0.22), "rot": Vector3(-0.15, -0.5, -0.2), "scale": 1.6},
		{"pos": Vector3(hull_size.x * 0.05, hull_size.y * 0.95, -hull_size.z * 0.38), "rot": Vector3(0.25, 0.8, 0.05), "scale": 1.2},
	]
	for r in rigs:
		_add_card(container, "scrap", color, Vector2(hull_size.x * 0.25, hull_size.y * 1.1) * r.scale, r.pos, r.rot)

# Bayou Irregulars: broad netting drapes over the top and one side - large,
# few cards (this is about breaking up the WHOLE silhouette, not scattered
# small detail), reading as camouflage netting thrown over the hull.
static func _build_net(container: Node3D, faction: String, hull_size: Vector3):
	var color = FactionCatalogScript.get_visual_color(faction).darkened(0.1)
	_add_card(container, "net", color, Vector2(hull_size.x * 1.05, hull_size.z * 0.55), Vector3(0, hull_size.y * 0.85, hull_size.z * 0.1), Vector3(-0.4, 0, 0))
	_add_card(container, "net", color, Vector2(hull_size.z * 0.75, hull_size.y * 1.3), Vector3(hull_size.x * 0.52, hull_size.y * 0.3, 0), Vector3(0, PI / 2.0, 0))

# Crimson Concordat: two ceremonial banners hanging off the rear corners,
# trailing past the hull's actual tail - the "kill-marks and banners as
# doctrine" aesthetic made literal.
static func _build_pennants(container: Node3D, faction: String, hull_size: Vector3):
	var color = FactionCatalogScript.get_visual_color(faction)
	var banner_size = Vector2(hull_size.x * 0.22, hull_size.z * 0.55)
	for side in [-1.0, 1.0]:
		var anchor = Vector3(side * hull_size.x * 0.38, hull_size.y * 0.9, hull_size.z * 0.42)
		_add_card(container, "pennant", color, banner_size, anchor + Vector3(0, -banner_size.y / 2.0, 0), Vector3(0, 0, 0))

# Aerodrome Cartel: two swept art-deco tailfins at the rear, raked back -
# streamers/glamour fins, not functional control surfaces.
static func _build_streamers(container: Node3D, faction: String, hull_size: Vector3):
	var color = FactionCatalogScript.get_visual_color(faction)
	var fin_size = Vector2(hull_size.z * 0.5, hull_size.y * 0.9)
	for side in [-1.0, 1.0]:
		var anchor = Vector3(side * hull_size.x * 0.42, hull_size.y * 0.85, hull_size.z * 0.3)
		_add_card(container, "streamer", color, fin_size, anchor, Vector3(0, PI / 2.0, side * 0.15))

# Dune Runners: water barrels lashed along the flanks - real cheap cylinder
# geometry, not a flat cutout card (a flat billboard wouldn't read as a
# solid strapped barrel from a rotating RTS camera the way an actual
# cylinder does, and a barrel is barely more expensive to build for real -
# see DECISIONS_NEEDED.md).
static func _build_barrels(container: Node3D, hull_size: Vector3):
	var wood_color = Color(0.45, 0.32, 0.16)
	var band_color = Color(0.22, 0.19, 0.16)
	var radius = hull_size.y * 0.26
	var length = hull_size.y * 1.0
	for side in [-1.0, 1.0]:
		var barrel = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = length
		barrel.mesh = cyl
		var mat = StandardMaterial3D.new()
		mat.albedo_color = wood_color
		mat.roughness = 0.85
		barrel.material_override = mat
		container.add_child(barrel)
		barrel.position = Vector3(side * (hull_size.x * 0.5 + radius * 0.85), hull_size.y * 0.32, hull_size.z * 0.12)
		barrel.rotation_degrees = Vector3(90, 0, 0) # lying on its side, axis running fore-aft along the hull's flank
		for band_offset in [-0.32, 0.32]:
			var band = MeshInstance3D.new()
			var torus = TorusMesh.new()
			torus.inner_radius = radius * 0.92
			torus.outer_radius = radius * 1.08
			band.mesh = torus
			var band_mat = StandardMaterial3D.new()
			band_mat.albedo_color = band_color
			band_mat.roughness = 0.6
			band.material_override = band_mat
			barrel.add_child(band)
			# No extra rotation needed - band is a CHILD of barrel, so it
			# already inherits barrel's 90-degree tip via the parent
			# transform; in barrel's own local space the cylinder's axis is
			# still local Y, exactly matching TorusMesh's default normal.
			band.position = Vector3(0, length * band_offset, 0)
