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

const LiveryScript = preload("res://scripts/livery.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")

const CARD_TEXTURE_SIZE: int = 256
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

static func _add_card(container: Node3D, shape: String, color: Color, size: Vector2, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var card = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = size
	card.mesh = quad
	card.material_override = _make_cutout_material(shape, color)
	container.add_child(card)
	card.position = pos
	card.rotation = rot
	return card

# Surface-anchored card (hull_projection.gd). These greebles are MEANT to stick
# out past the silhouette, but they still have to be BOLTED TO something - the
# previous hardcoded positions were fractions of the declared catalog box at
# 0.8-0.95 * size.y, while a hull's recentred roof sits at 0.5 * size.y, so
# every antenna, net and banner hovered clear of the hull it was supposedly
# lashed to. Now the mount point is a real hit on the real skin.
#
# `stand` grows the card out of the surface along its normal (a scrap antenna)
# instead of lying it flat; `tilt` is applied in the surface's own frame,
# so a deliberately-crooked scrap antenna stays crooked relative to the panel
# it is welded to rather than to world axes.
static func _project_card(container: Node3D, surface: Dictionary, shape: String,
		color: Color, size: Vector2, anchor: Vector3, axis: Vector3,
		tilt: Vector3 = Vector3.ZERO, stand: bool = true,
		facing_hint: Vector3 = Vector3.RIGHT, emerge: float = 1.0) -> MeshInstance3D:
	var hit = HullProjectionScript.project(surface, anchor, axis)
	var normal: Vector3 = hit["normal"]
	var card = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = size
	card.mesh = quad
	card.material_override = _make_cutout_material(shape, color)
	container.add_child(card)
	var basis: Basis = HullProjectionScript.basis_standing(normal, facing_hint) if stand \
		else HullProjectionScript.basis_for_normal(normal)
	if tilt != Vector3.ZERO:
		basis = basis * Basis.from_euler(tilt)
	card.basis = basis
	# `emerge` controls how much of a standing card clears the surface: 1.0
	# puts its bottom edge exactly on the skin, 0.0 centres it so the lower
	# half is buried inside the hull.
	#
	# Full emergence is wrong for an alpha-cutout whose ink is not flush with
	# the quad's bottom edge - a scrap antenna's zigzag wanders across the
	# whole card, so lifting by a full half-height pushed the visible squiggle
	# clear of the hull and made the floating WORSE than the original hardcoded
	# placement, which had the card centred (and therefore half-buried) by
	# accident. Burying the base is what makes a cutout read as welded on.
	#
	# The lift runs along the card's OWN final +Y (post-tilt), not the raw
	# surface normal: lifting along the normal and then tilting rotates about
	# the card's centre, which swings the mount point back off the hull
	# (measured 0.17 on a 1.2-unit-tall scout).
	var lift: Vector3 = basis.y.normalized() * size.y * 0.5 * emerge if stand else Vector3.ZERO
	card.position = (hit["position"] + lift) * surface.get("position_scale", Vector3.ONE)
	return card

# Shared surface for a whole greeble pass, with the same origin-centred
# fallback box hull_decals.gd uses when there is no mesh to project onto.
static func _surface_for(hull: Node3D, hull_size: Vector3) -> Dictionary:
	var surface = HullProjectionScript.build_surface(hull)
	if surface["tris"].size() < 3:
		surface["aabb"] = AABB(-hull_size * 0.5, hull_size)
	return surface

static func _extents(surface: Dictionary, hull_size: Vector3) -> Vector3:
	if surface["tris"].size() >= 3:
		return (surface["aabb"] as AABB).size
	return hull_size

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

	# Built once and shared by every builder - gathering the hull's triangles is
	# the expensive part, and all five treated factions project against the
	# same skin.
	var surface = _surface_for(hull, hull_size)
	var comp = HullProjectionScript.attach_compensation(hull)
	container.scale = comp["container_scale"]
	surface["position_scale"] = comp["position_scale"]

	match faction:
		"salvage_union": _build_scrap(container, faction, hull_size, surface)
		"bayou_irregulars": _build_net(container, faction, hull_size, surface)
		"crimson_concordat": _build_pennants(container, faction, hull_size, surface)
		"aerodrome_cartel": _build_streamers(container, faction, hull_size, surface)
		"dune_runners": _build_barrels(container, hull_size, surface)
		_: pass # every other faction stays clean - no greebles at all

# Salvage Union: 3 jury-rigged scrap antennas/pipes at odd angles, scattered
# across the top and sides - deliberately irregular (varied rotation/scale),
# never all pointing the same way, matching "nothing's original equipment."
static func _build_scrap(container: Node3D, faction: String, hull_size: Vector3, surface: Dictionary):
	# Bright exposed-metal tone, not the faction's own dark worn paint color -
	# real scrap/scavenged fittings read as scavenged precisely because they
	# DON'T match the hull's own weathered finish. Using Salvage Union's own
	# base_color here (grey, close in tone to their heavily-worn near-black
	# hull) made the first pass nearly invisible against its own paint job.
	var color = Color(0.68, 0.64, 0.58)
	var ext = _extents(surface, hull_size)
	# Anchors are normalized roof coordinates now; the tilt is what keeps them
	# irregular, applied in each mount panel's own frame.
	var rigs = [
		{"anchor": Vector3(0.82, 1.0, 0.55), "rot": Vector3(0.1, 0.4, 0.3), "scale": 1.4},
		{"anchor": Vector3(0.12, 1.0, 0.28), "rot": Vector3(-0.15, -0.5, -0.2), "scale": 1.6},
		{"anchor": Vector3(0.55, 1.0, 0.12), "rot": Vector3(0.25, 0.8, 0.05), "scale": 1.2},
	]
	for r in rigs:
		# emerge 0.25: the zigzag cutout runs the full height of its card, so
		# most of it must stay below the roofline or the rig floats.
		_project_card(container, surface, "scrap", color,
			Vector2(ext.x * 0.25, ext.y * 1.1) * r.scale,
			r.anchor, Vector3.UP, r.rot, true, Vector3.RIGHT, 0.25)

# Bayou Irregulars: broad netting drapes over the top and one side - large,
# few cards (this is about breaking up the WHOLE silhouette, not scattered
# small detail), reading as camouflage netting thrown over the hull.
static func _build_net(container: Node3D, faction: String, hull_size: Vector3, surface: Dictionary):
	var color = LiveryScript.zone_color(faction, "hull_upper").darkened(0.1)
	var ext = _extents(surface, hull_size)
	# Netting is nearly hull-sized, so it is the one greeble that cannot be a
	# flat card at all: a single quad is tangent to the hull at exactly one
	# point, and at this size its far corners stand off at a visibly wrong
	# angle - which is why it read as a rigid billboard stuck on perpendicular
	# rather than as netting thrown over the hull. It gets a subdivided
	# conforming sheet whose every vertex is projected individually, so it
	# follows a curved airship or a stepped flank all the way across.
	_drape(container, surface, color, Vector3(0.5, 1.0, 0.55), Vector3.UP,
		ext.x * 1.05, ext.z * 0.55)
	_drape(container, surface, color, Vector3(1.0, 0.5, 0.5), Vector3.RIGHT,
		ext.z * 0.75, ext.y * 1.0)

static func _drape(container: Node3D, surface: Dictionary, color: Color,
		anchor: Vector3, axis: Vector3, extent_a: float, extent_b: float) -> void:
	var mesh = HullProjectionScript.conforming_sheet(surface, anchor, axis, extent_a, extent_b, 10)
	if mesh == null:
		return
	var drape = MeshInstance3D.new()
	drape.mesh = mesh
	drape.material_override = _make_cutout_material("net", color)
	container.add_child(drape)
	# The sheet's vertices are already in host space; the container carries the
	# inverse of the host's scale, so undo that for the geometry itself.
	drape.scale = surface.get("position_scale", Vector3.ONE)

# Crimson Concordat: two ceremonial banners hanging off the rear corners,
# trailing past the hull's actual tail - the "kill-marks and banners as
# doctrine" aesthetic made literal.
static func _build_pennants(container: Node3D, faction: String, hull_size: Vector3, surface: Dictionary):
	var color = LiveryScript.zone_color(faction, "hull_upper")
	var ext = _extents(surface, hull_size)
	# Banner height comes off the hull's HEIGHT, not its length. The old
	# ext.z * 0.55 made a heavy hull's pennant 4.4 units tall - taller than the
	# hull itself - so however it was anchored it draped past the bottom of the
	# vehicle and read as attached underneath. A flag is a fraction of the
	# thing it flies from.
	var banner_size = Vector2(ext.x * 0.22, ext.y * 0.8)
	# A banner hangs by gravity, so unlike the other greebles its orientation is
	# NOT surface-relative - only its masthead is. Project to find where the
	# rear roof corner actually is, raise a short mast above it, and hang the
	# banner from the TOP of that mast so it flies above the hull line.
	var mast_height: float = ext.y * 0.45
	for side in [-1.0, 1.0]:
		var hit = HullProjectionScript.project(surface,
			Vector3(0.5 + side * 0.38, 1.0, 0.9), Vector3.UP)
		var masthead: Vector3 = (hit["position"] as Vector3) + Vector3(0, mast_height, 0)
		_add_card(container, "pennant", color, banner_size,
			(masthead - Vector3(0, banner_size.y * 0.5, 0)) * surface.get("position_scale", Vector3.ONE),
			Vector3.ZERO)

# Aerodrome Cartel: two swept art-deco tailfins at the rear, raked back -
# streamers/glamour fins, not functional control surfaces.
static func _build_streamers(container: Node3D, faction: String, hull_size: Vector3, surface: Dictionary):
	var color = LiveryScript.zone_color(faction, "hull_upper")
	var ext = _extents(surface, hull_size)
	var fin_size = Vector2(ext.z * 0.5, ext.y * 0.7)
	# A tailfin is a VERTICAL surface running fore-aft, so the card lies in the
	# plane containing world up and the hull's long axis, just outboard of the
	# real flank - it must not "stand off" along the flank normal, which would
	# put the card's height axis sideways and lay the fin flat like a wing.
	# That mistake is what dropped these below the hull: the fin's own height
	# then extended downward through the vehicle instead of upward.
	for side in [-1.0, 1.0]:
		var axis := Vector3(side, 0.0, 0.0)
		var hit = HullProjectionScript.project(surface,
			Vector3(0.5 + side * 0.5, 0.75, 0.75), axis)
		var card = _add_card(container, "streamer", color, fin_size, Vector3.ZERO,
			Vector3.ZERO)
		# Rise from the flank so the fin's top clears the roofline, with its
		# lower part overlapping the hull - a fin sprouts from the body, it does
		# not hover beside it.
		var rise := Vector3(0, fin_size.y * 0.35, 0)
		var pos: Vector3 = (hit["position"] as Vector3) + rise
		card.basis = HullProjectionScript.basis_for_normal(hit["normal"]) * Basis.from_euler(Vector3(0, 0, side * 0.15))
		card.position = pos * surface.get("position_scale", Vector3.ONE)

# Dune Runners: water barrels lashed along the flanks - real cheap cylinder
# geometry, not a flat cutout card (a flat billboard wouldn't read as a
# solid strapped barrel from a rotating RTS camera the way an actual
# cylinder does, and a barrel is barely more expensive to build for real -
# see DECISIONS_NEEDED.md).
static func _build_barrels(container: Node3D, hull_size: Vector3, surface: Dictionary):
	var wood_color = Color(0.45, 0.32, 0.16)
	var band_color = Color(0.22, 0.19, 0.16)
	var ext = _extents(surface, hull_size)
	var radius = ext.y * 0.26
	var length = ext.y * 1.0
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
		# Lashed to the REAL flank: project inward from the side to find where
		# the hull skin actually is at this height, then sit the barrel just
		# outside it by its own radius. A tapered or curved flank now gets its
		# barrels tucked against it instead of held out at the bounding box.
		var flank = HullProjectionScript.project(surface,
			Vector3(0.5 + side * 0.5, 0.4, 0.56), Vector3(side, 0.0, 0.0))
		barrel.position = (flank["position"] + (flank["normal"] as Vector3) * radius * 0.85) \
			* surface.get("position_scale", Vector3.ONE)
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
