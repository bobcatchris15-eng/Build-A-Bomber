extends SceneTree
# ONE neutral hull surface texture set, replacing the ten per-faction ones.
#
# WHAT THIS REPLACES. tools/generate_faction_textures.gd baked ten complete
# 1024x1024 albedo/normal/roughness sets - 60 files, 31 MB - one per faction,
# because faction COLOUR lived in the albedo. With the factions gone and the
# player authoring their own livery (scripts/livery.gd), colour is a shader
# uniform per zone, so a per-faction bake has nothing left to vary: all ten
# differed only in hue and in a couple of overlay styles.
#
# So this bakes the part that was always shared - the SURFACE. Panel seams,
# rivets, grain, corrosion and streaks, in pure VALUE with no hue at all, on a
# near-white base so the hull shader's zone colours multiply over it cleanly:
#
#     colour = tex_albedo * zone_albedo
#
# A neutral texture is what makes that multiply correct. Bake any colour into
# the albedo and every livery gets tinted by it, which is exactly the trap the
# per-faction bake fell into from the other direction.
#
# Run (from prototype/):
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script tools/generate_hull_surface_texture.gd

const OUT_DIR = "res://assets/textures/hull"
const TEX_SIZE = 1024

# Structural parameters only - there is deliberately no colour here. Values
# carried over from the old industrialists entry, which was the most "generic
# fabricated steel" of the ten and therefore the right neutral baseline.
const PANEL_SIZE := 64          # period, must divide TEX_SIZE so the grid wraps
const SEAM_WIDTH_FRAC := 0.10   # fraction of PANEL_SIZE
const PANEL_VARIANCE := 0.06
const RIVET_SPACING := 32
const RIVET_RADIUS_FRAC := 0.14
const SUB_RIVET_SPACING := 32
const SUB_RIVET_RADIUS_FRAC := 0.05
const GRAIN_STRENGTH := 0.05
const FINE_GRAIN_STRENGTH := 0.04
const CORROSION_AMOUNT := 0.10
const STREAK_AMOUNT := 0.05
const SEED := 101

# Baked directional shading direction, matching the old generator so hulls
# keep the same pre-rendered-sprite read.
const LIGHT_DIR = Vector3(-0.45, -0.65, 0.6)


func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_generate()
	print("Generated neutral hull surface texture set in ", OUT_DIR)
	quit(0)


# --- Periodic value noise (tiles seamlessly at `period` lattice cells) ------

static func _hash_periodic(ix: int, iy: int, period: int, seed_val: int) -> float:
	var px = ((ix % period) + period) % period
	var py = ((iy % period) + period) % period
	var h = (px * 374761393 + py * 668265263 + seed_val * 2246822519) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 1274126177
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return float(h) / float(0x7FFFFFFF)


static func _periodic_noise2d(x: float, y: float, period: int, seed_val: int) -> float:
	var ix = int(floor(x))
	var iy = int(floor(y))
	var fx = x - ix
	var fy = y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var n00 = _hash_periodic(ix, iy, period, seed_val)
	var n10 = _hash_periodic(ix + 1, iy, period, seed_val)
	var n01 = _hash_periodic(ix, iy + 1, period, seed_val)
	var n11 = _hash_periodic(ix + 1, iy + 1, period, seed_val)
	return lerp(lerp(n00, n10, fx), lerp(n01, n11, fx), fy)


# Per-pixel surface, returning a VALUE multiplier (not a colour), a height for
# the normal map, and a roughness. Everything modulates brightness only - a
# panel that is grubbier is darker, never browner - so the result is a pure
# surface mask the livery paints through.
static func _eval(x: int, y: int) -> Dictionary:
	var value := 1.0
	var height := 0.0
	var rough := 0.62

	# Panel grid: each panel gets its own slight value offset, and the seams
	# between them are darker and recessed.
	var panel_x := int(x / PANEL_SIZE)
	var panel_y := int(y / PANEL_SIZE)
	var panel_period := int(TEX_SIZE / PANEL_SIZE)
	var panel_jitter = _hash_periodic(panel_x, panel_y, panel_period, SEED) - 0.5
	value += panel_jitter * PANEL_VARIANCE * 2.0
	height += panel_jitter * 0.05

	var in_x = float(x % PANEL_SIZE) / float(PANEL_SIZE)
	var in_y = float(y % PANEL_SIZE) / float(PANEL_SIZE)
	var seam = minf(minf(in_x, 1.0 - in_x), minf(in_y, 1.0 - in_y))
	# Per-panel seam variation (2026-08-10). The fixed SEAM_WIDTH_FRAC plus
	# fixed 0.13 darkening made every seam the same width and the same
	# darkness, which at the livery's render scale read as a perfect
	# chessboard rather than as panelled metal. Per-panel variation in
	# both width and darken breaks the grid into "irregular plating".
	var panel_seed := _hash_periodic(
		int(x / PANEL_SIZE), int(y / PANEL_SIZE),
		int(TEX_SIZE / PANEL_SIZE), SEED + 41)
	var this_seam_width := SEAM_WIDTH_FRAC * (0.35 + panel_seed * 1.3)
	var this_seam_darken := 0.10 * (0.5 + panel_seed * 1.8)
	if seam < this_seam_width:
		var t = 1.0 - seam / this_seam_width
		value *= 1.0 - this_seam_darken * t
		height -= 0.55 * t
		rough += 0.12 * t

	# Rivets: two scales, the coarse row on the panel edge lattice and a finer
	# infill, both as raised bumps in the height field.
	for spacing_radius in [[RIVET_SPACING, RIVET_RADIUS_FRAC], [SUB_RIVET_SPACING, SUB_RIVET_RADIUS_FRAC]]:
		var spacing: int = spacing_radius[0]
		var radius: float = spacing_radius[1] * float(spacing)
		var cx = (int(x / spacing) * spacing) + spacing * 0.5
		var cy = (int(y / spacing) * spacing) + spacing * 0.5
		var d = Vector2(float(x) - cx, float(y) - cy).length()
		if d < radius:
			var t = 1.0 - d / radius
			height += 0.85 * t * t
			value *= 1.0 + 0.03 * t
			rough -= 0.05 * t

	# Grain: two octaves of value noise, the coarse one also displacing the
	# height slightly so the surface is not perfectly flat between rivets.
	var g = _periodic_noise2d(float(x) / 24.0, float(y) / 24.0, int(TEX_SIZE / 24), SEED + 7)
	var fg = _periodic_noise2d(float(x) / 5.0, float(y) / 5.0, int(TEX_SIZE / 5), SEED + 13)
	value *= 1.0 + (g - 0.5) * GRAIN_STRENGTH * 2.0
	value *= 1.0 + (fg - 0.5) * FINE_GRAIN_STRENGTH * 2.0
	height += (g - 0.5) * 0.12
	rough += (fg - 0.5) * 0.10

	# Corrosion patches and vertical streaking, both darkening only.
	var corr = _periodic_noise2d(float(x) / 60.0, float(y) / 60.0, int(TEX_SIZE / 60), SEED + 23)
	if corr > 0.58:
		var t = (corr - 0.58) / 0.42
		value *= 1.0 - CORROSION_AMOUNT * t
		rough += 0.18 * t
	var streak = _periodic_noise2d(float(x) / 9.0, float(y) / 140.0, int(TEX_SIZE / 9), SEED + 31)
	value *= 1.0 - STREAK_AMOUNT * clampf(streak - 0.5, 0.0, 1.0)

	# LARGE-SCALE BREAKUP (2026-08-10). A low-frequency value layer that
	# breaks the panel grid - large patches of slightly-brighter and
	# slightly-darker regions that read as worn-paint variation rather
	# than as a tiling artifact.
	var macro = _periodic_noise2d(float(x) / 256.0, float(y) / 256.0,
		int(TEX_SIZE / 256), SEED + 47)
	value *= 1.0 + (macro - 0.5) * 0.06

	# TIGHT VALUE RANGE, and this is the number that matters most. The first
	# bake clamped to [0, 1.6] with strong seam/rivet/corrosion modulation, and
	# with the livery's zone colour multiplied over it the result read as a
	# black-and-white CHEQUERBOARD rather than as panelled metal - the texture
	# was competing with the paint instead of sitting under it. Surface detail
	# has to be legible without becoming the pattern you see first. Widened
	# slightly (0.78-1.12 -> 0.72-1.14) so the new per-panel seam variation
	# does not get clipped back into a regular grid by the clamp.
	return {"value": clampf(value, 0.72, 1.14), "height": height, "roughness": clampf(rough, 0.05, 1.0)}


func _generate() -> void:
	var albedo_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var rough_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var normal_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var height_field := []
	var value_field := []
	height_field.resize(TEX_SIZE * TEX_SIZE)
	value_field.resize(TEX_SIZE * TEX_SIZE)

	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var s = _eval(x, y)
			value_field[y * TEX_SIZE + x] = s.value
			height_field[y * TEX_SIZE + x] = s.height
			rough_img.set_pixel(x, y, Color(s.roughness, s.roughness, s.roughness))

	# Normal map + baked directional shading from the same height field, via
	# central differences that WRAP at the edge (this tiles through triplanar
	# sampling, so the gradient has to wrap rather than clamp).
	var strength := 3.0
	var light_dir := LIGHT_DIR.normalized()
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var x0 = (x - 1 + TEX_SIZE) % TEX_SIZE
			var x1 = (x + 1) % TEX_SIZE
			var y0 = (y - 1 + TEX_SIZE) % TEX_SIZE
			var y1 = (y + 1) % TEX_SIZE
			var dx = (height_field[y * TEX_SIZE + x1] - height_field[y * TEX_SIZE + x0]) * strength
			var dy = (height_field[y1 * TEX_SIZE + x] - height_field[y0 * TEX_SIZE + x]) * strength
			var n = Vector3(-dx, -dy, 1.0).normalized()
			normal_img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

			# Baked shading, but MUCH gentler than the per-faction bake's
			# 0.35-1.7 range. That range was tuned when the albedo already
			# carried the faction's own paint colour and the bake was the only
			# thing giving it form. Here the same multiplier would be applied
			# on top of a live per-zone colour AND the shader's own toon
			# lighting, and at 1.7 it blew the lighter livery colours out to
			# white. 0.72-1.24 keeps the pre-rendered-sprite read without
			# fighting the paint.
			var ndotl = n.dot(light_dir)
			var shade = clampf(0.86 + (ndotl * 0.5 + 0.5) * 0.26, 0.8, 1.12)
			var v = clampf(float(value_field[y * TEX_SIZE + x]) * shade, 0.0, 1.0)
			albedo_img.set_pixel(x, y, Color(v, v, v))

	albedo_img.save_png(OUT_DIR + "/hull_surface_albedo.png")
	normal_img.save_png(OUT_DIR + "/hull_surface_normal.png")
	rough_img.save_png(OUT_DIR + "/hull_surface_roughness.png")
