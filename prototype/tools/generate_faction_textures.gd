extends SceneTree
# Generates real per-faction albedo/normal/roughness texture maps, entirely
# procedurally, headlessly, in pure Godot (Image + hand-rolled periodic value
# noise) - no Blender, no external tools, no hand-authored art. This matches
# hull_greebles.gd's existing precedent (procedural Image generation instead
# of hand-painted assets) but PRE-BAKES to PNGs once rather than generating
# at runtime every load, since these are much higher-resolution (1024x1024)
# and a per-pixel GDScript loop at that size is too slow to repeat every game
# boot.
#
# v3 (2026-07-26): faction COLOR identity moved here from the live shader
# (hull_faction_material.gdshader) per Chris's explicit direction - v1/v2
# baked structural detail (panels, rivets, corrosion, directional shading)
# into a near-grayscale texture and left color/wear/grime to be computed
# per-fragment every frame from FactionCatalog's base_color/accent_color/
# wear_color/grime_amount. Real color science stayed the same (paint body =
# base_color, trim/seams = accent_color, wear/corrosion exposes wear_color),
# it just moved from "every fragment, every frame, every faction" to "once,
# per faction, at asset-build time" - the shader now just samples the
# result. Re-run this after changing FactionCatalog's visual data OR the
# structural params below:
#   ./Godot_v4.3-stable_win64_console.exe --headless --script tools/generate_faction_textures.gd

const FactionCatalogScript = preload("res://scripts/faction_catalog.gd")

const OUT_DIR = "res://assets/textures/factions"
const TEX_SIZE = 1024

# Structural/detail params only now - COLOR (base/accent/wear) comes from
# FactionCatalog.get_visual() below, the single source of truth for what a
# faction's paint job actually looks like (shared with anything else that
# still reads FactionCatalog directly, e.g. building.gd's team-tint).
# panel_size/rivet_spacing must evenly divide TEX_SIZE so the grid wraps
# cleanly - each is a period, not raw pixels. seam_width_frac/rivet_radius_
# frac are fractions of panel_size, so boldness reads consistently
# regardless of TEX_SIZE. overlay_style: "" none, "patch" salvage-style
# mismatched rectangular plates (lerped toward wear_color per patch,
# randomized strength - "some panels rustier than others"), "blotch" soft
# organic two-tone camo (lerped between base_color/accent_color - Bayou
# Irregulars' actual camo pattern, not just a brightness wobble), "frost"
# icy speckle highlights (lerped toward wear_color, which is already
# frost-white for Glacier Syndicate in FactionCatalog).
const FACTION_TEX_PARAMS = {
	"industrialists": {
		"seed": 101, "panel_size": 64, "seam_width_frac": 0.16, "panel_variance": 0.06,
		"rivet_spacing": 32, "rivet_radius_frac": 0.22,
		"sub_rivet_spacing": 16, "sub_rivet_radius_frac": 0.10,
		"grain_strength": 0.10, "fine_grain_strength": 0.04,
		"corrosion_amount": 0.35, "streak_amount": 0.08,
		"overlay_style": "", "overlay_amount": 0.0, "trim_band": [0.42, 0.58],
	},
	"technocrats": {
		"seed": 202, "panel_size": 32, "seam_width_frac": 0.08, "panel_variance": 0.02,
		"rivet_spacing": 0, "rivet_radius_frac": 0.0,
		"sub_rivet_spacing": 0, "sub_rivet_radius_frac": 0.0,
		"grain_strength": 0.03, "fine_grain_strength": 0.01,
		"corrosion_amount": 0.02, "streak_amount": 0.25,
		"overlay_style": "", "overlay_amount": 0.0, "trim_band": [0.46, 0.54],
	},
	"expansionists": {
		"seed": 303, "panel_size": 32, "seam_width_frac": 0.2, "panel_variance": 0.08,
		"rivet_spacing": 64, "rivet_radius_frac": 0.24,
		"sub_rivet_spacing": 16, "sub_rivet_radius_frac": 0.08,
		"grain_strength": 0.18, "fine_grain_strength": 0.06,
		"corrosion_amount": 0.55, "streak_amount": 0.05,
		"overlay_style": "", "overlay_amount": 0.0, "trim_band": [0.4, 0.6],
	},
	"salvage_union": {
		"seed": 404, "panel_size": 32, "seam_width_frac": 0.18, "panel_variance": 0.07,
		"rivet_spacing": 32, "rivet_radius_frac": 0.2,
		"sub_rivet_spacing": 8, "sub_rivet_radius_frac": 0.06,
		"grain_strength": 0.15, "fine_grain_strength": 0.08,
		"corrosion_amount": 0.45, "streak_amount": 0.05,
		"overlay_style": "patch", "overlay_amount": 0.7, "trim_band": [0.38, 0.5],
	},
	"crimson_concordat": {
		"seed": 505, "panel_size": 32, "seam_width_frac": 0.14, "panel_variance": 0.05,
		"rivet_spacing": 64, "rivet_radius_frac": 0.2,
		"sub_rivet_spacing": 8, "sub_rivet_radius_frac": 0.08,
		"grain_strength": 0.1, "fine_grain_strength": 0.03,
		"corrosion_amount": 0.2, "streak_amount": 0.3,
		"overlay_style": "", "overlay_amount": 0.0, "trim_band": [0.44, 0.56],
	},
	"glacier_syndicate": {
		"seed": 606, "panel_size": 32, "seam_width_frac": 0.1, "panel_variance": 0.03,
		"rivet_spacing": 0, "rivet_radius_frac": 0.0,
		"sub_rivet_spacing": 0, "sub_rivet_radius_frac": 0.0,
		"grain_strength": 0.05, "fine_grain_strength": 0.02,
		"corrosion_amount": 0.03, "streak_amount": 0.25,
		"overlay_style": "frost", "overlay_amount": 0.5, "trim_band": [0.45, 0.55],
	},
	"dune_runners": {
		"seed": 707, "panel_size": 32, "seam_width_frac": 0.14, "panel_variance": 0.06,
		"rivet_spacing": 64, "rivet_radius_frac": 0.2,
		"sub_rivet_spacing": 16, "sub_rivet_radius_frac": 0.10,
		"grain_strength": 0.2, "fine_grain_strength": 0.07,
		"corrosion_amount": 0.5, "streak_amount": 0.05,
		"overlay_style": "", "overlay_amount": 0.0, "trim_band": [0.4, 0.6],
	},
	"ledger_combine": {
		"seed": 808, "panel_size": 16, "seam_width_frac": 0.09, "panel_variance": 0.02,
		"rivet_spacing": 0, "rivet_radius_frac": 0.0,
		"sub_rivet_spacing": 0, "sub_rivet_radius_frac": 0.0,
		"grain_strength": 0.02, "fine_grain_strength": 0.01,
		"corrosion_amount": 0.0, "streak_amount": 0.2,
		"overlay_style": "", "overlay_amount": 0.0, "trim_band": [0.47, 0.53],
	},
	"bayou_irregulars": {
		"seed": 909, "panel_size": 64, "seam_width_frac": 0.14, "panel_variance": 0.06,
		"rivet_spacing": 32, "rivet_radius_frac": 0.2,
		"sub_rivet_spacing": 8, "sub_rivet_radius_frac": 0.06,
		"grain_strength": 0.15, "fine_grain_strength": 0.07,
		"corrosion_amount": 0.35, "streak_amount": 0.05,
		"overlay_style": "blotch", "overlay_amount": 0.55, "trim_band": [0.4, 0.55],
	},
	"aerodrome_cartel": {
		"seed": 1010, "panel_size": 32, "seam_width_frac": 0.14, "panel_variance": 0.04,
		"rivet_spacing": 16, "rivet_radius_frac": 0.22,
		"sub_rivet_spacing": 8, "sub_rivet_radius_frac": 0.08,
		"grain_strength": 0.08, "fine_grain_strength": 0.03,
		"corrosion_amount": 0.12, "streak_amount": 0.3,
		"overlay_style": "", "overlay_amount": 0.0, "trim_band": [0.43, 0.57],
	},
}

# Fixed "sun" direction for the baked-shading pass, in the same (x, y, out-
# of-surface) convention as the normal-map encoding below - upper-left-ish
# and tilted toward the viewer, the classic RTS-sprite key light angle.
const LIGHT_DIR = Vector3(-0.45, -0.65, 0.6)

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for faction_id in FACTION_TEX_PARAMS.keys():
		var vis = FactionCatalogScript.get_visual(faction_id)
		_generate_faction_textures(faction_id, FACTION_TEX_PARAMS[faction_id], vis)
		print("Generated textures for ", faction_id)
	quit(0)

# --- Periodic value noise (tiles seamlessly at `period` lattice cells) ---

static func _hash_periodic(ix: int, iy: int, period: int, seed: int) -> float:
	var px = ((ix % period) + period) % period
	var py = ((iy % period) + period) % period
	var h = (px * 374761393 + py * 668265263 + seed * 2246822519) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 1274126177
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return float(h) / float(0x7FFFFFFF)

static func _periodic_noise2d(x: float, y: float, period: int, seed: int) -> float:
	var ix = int(floor(x))
	var iy = int(floor(y))
	var fx = x - ix
	var fy = y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var n00 = _hash_periodic(ix, iy, period, seed)
	var n10 = _hash_periodic(ix + 1, iy, period, seed)
	var n01 = _hash_periodic(ix, iy + 1, period, seed)
	var n11 = _hash_periodic(ix + 1, iy + 1, period, seed)
	var nx0 = lerp(n00, n10, fx)
	var nx1 = lerp(n01, n11, fx)
	return lerp(nx0, nx1, fy)

# --- Per-pixel surface evaluation shared by albedo/height/roughness ---
# Returns {"albedo": Color, "height": float, "roughness": float 0-1}. Color
# starts from the faction's real base_color/accent_color/wear_color (vis)
# and gets built up structurally exactly the way the old live shader used
# to combine them per-fragment - trim band = accent_color, corrosion/wear =
# wear_color, everything else modulates VALUE (multiply), never hue, so a
# panel jitter/grain/streak reads as "same paint, uneven surface" rather
# than a competing color. This is the RAW/pre-shading color - the baked
# directional-shading pass in _generate_faction_textures() multiplies over
# it afterward.

static func _eval_surface(x: int, y: int, p: Dictionary, vis: Dictionary) -> Dictionary:
	var seed = p.seed
	var panel_size = p.panel_size
	var base_color: Color = vis.base_color
	var accent_color: Color = vis.accent_color
	var wear_color: Color = vis.wear_color

	var color = base_color
	var height = 0.0
	var roughness = 0.55
	var value_mult = 1.0 # multiplicative brightness modulation, preserves hue

	# Panel grid: per-panel brightness jitter (hashed on panel INDEX, not raw
	# pixel, so it's periodic at panel_size and wraps cleanly) + a thick
	# ink-style seam groove - lerped hard toward near-black at the seam
	# core (not just a subtract) so it reads as bold painted linework, not
	# a subtle material dip.
	var lx = x % panel_size
	var ly = y % panel_size
	var panels_across = TEX_SIZE / panel_size
	var panel_i = (x / panel_size) % panels_across
	var panel_j = (y / panel_size) % panels_across
	var panel_jitter = (_hash_periodic(panel_i, panel_j, panels_across, seed) - 0.5) * 2.0 * p.panel_variance
	value_mult += panel_jitter

	var seam_width = max(panel_size * p.seam_width_frac, 1.0)
	var seam_dist = min(lx, min(panel_size - lx, min(ly, panel_size - ly)))
	var seam_mask = clamp(1.0 - float(seam_dist) / seam_width, 0.0, 1.0)
	seam_mask = pow(seam_mask, 0.6) # sharpen the falloff - more ink-line, less soft groove
	color = color.lerp(Color(0.04, 0.04, 0.04), seam_mask)
	height -= seam_mask * 1.1
	roughness += seam_mask * 0.15

	# Rivets: bold raised domes with a real drop-shadow crescent (offset
	# opposite the bake light direction), not just a flat highlight dot.
	if p.rivet_spacing > 0:
		var rivet_radius = p.rivet_spacing * p.rivet_radius_frac
		var rx = x % p.rivet_spacing
		var ry = y % p.rivet_spacing
		var dx = min(rx, p.rivet_spacing - rx)
		var dy = min(ry, p.rivet_spacing - ry)
		var rivet_dist = sqrt(float(dx * dx + dy * dy))
		var rivet_mask = clamp(1.0 - rivet_dist / max(rivet_radius, 0.1), 0.0, 1.0)
		value_mult += rivet_mask * 0.35
		height += rivet_mask * 1.6
		roughness -= rivet_mask * 0.25

		var shadow_dx = float(dx) - rivet_radius * 0.55
		var shadow_dy = float(dy) - rivet_radius * 0.55
		var shadow_dist = sqrt(shadow_dx * shadow_dx + shadow_dy * shadow_dy)
		var shadow_mask = clamp(1.0 - shadow_dist / (rivet_radius * 0.85), 0.0, 1.0) * (1.0 - rivet_mask)
		value_mult -= shadow_mask * 0.4

	# Sub-rivets: smaller secondary fasteners for richer detail.
	if p.sub_rivet_spacing > 0:
		var sub_rivet_radius = p.sub_rivet_spacing * p.sub_rivet_radius_frac
		var srx = x % p.sub_rivet_spacing
		var sry = y % p.sub_rivet_spacing
		var sdx = min(srx, p.sub_rivet_spacing - srx)
		var sdy = min(sry, p.sub_rivet_spacing - sry)
		var sub_dist = sqrt(float(sdx * sdx + sdy * sdy))
		var sub_mask = clamp(1.0 - sub_dist / max(sub_rivet_radius, 0.1), 0.0, 1.0)
		value_mult += sub_mask * 0.22
		height += sub_mask * 0.8
		roughness -= sub_mask * 0.12

	# Fine grain: high-frequency isotropic noise for micro-surface texture.
	if p.fine_grain_strength > 0.0:
		var fine_grain = _periodic_noise2d(float(x) / 3.0, float(y) / 3.0, TEX_SIZE / 3, p.seed + 10) - 0.5
		value_mult += fine_grain * p.fine_grain_strength
		roughness += abs(fine_grain) * p.fine_grain_strength * 0.2

	# Fine grain (isotropic noise) - breaks up flatness on every faction.
	var grain = _periodic_noise2d(float(x) / 8.0, float(y) / 8.0, TEX_SIZE / 8, seed + 1) - 0.5
	value_mult += grain * p.grain_strength
	height += grain * p.grain_strength * 0.3

	# Directional brushed streaks: long bands running along local X (the
	# hull's nose-to-tail axis, matching the runtime shader's ANISOTROPY_FLOW
	# = vec2(1,0) convention) - high frequency in Y, only a tiny X
	# contribution so the bands are elongated, not perfectly straight.
	if p.streak_amount > 0.0:
		var streak = _periodic_noise2d(float(x) * 0.04, float(y) / 3.0, TEX_SIZE / 3, seed + 2) - 0.5
		value_mult += streak * p.streak_amount * 0.3
		roughness -= abs(streak) * p.streak_amount * 0.1

	color = Color(clamp(color.r * value_mult, 0.0, 1.0), clamp(color.g * value_mult, 0.0, 1.0), clamp(color.b * value_mult, 0.0, 1.0))

	# Corrosion/pitting: coarse noise thresholded into wear_color speckle -
	# THE primary carrier of each faction's wear personality now (Salvage
	# Union grungy, Technocrats pristine, Glacier frost-pale, etc.) - lerps
	# toward wear_color rather than just darkening, so worn areas show the
	# faction's actual exposed-material color, not generic soot.
	if p.corrosion_amount > 0.0:
		var corr_noise = _periodic_noise2d(float(x) / 16.0, float(y) / 16.0, TEX_SIZE / 16, seed + 3)
		var corr_mask = smoothstep(1.0 - p.corrosion_amount, 1.0, corr_noise)
		color = color.lerp(wear_color, corr_mask * 0.75)
		height -= corr_mask * 0.5
		roughness += corr_mask * 0.35

	# Overlay: salvage's mismatched rectangular patches, bayou's organic
	# two-tone camo blotches, or glacier's icy speckle highlights.
	if p.overlay_style == "patch":
		var patch_grid = 64
		var pi = (x / patch_grid) % (TEX_SIZE / patch_grid)
		var pj = (y / patch_grid) % (TEX_SIZE / patch_grid)
		var patch_hash = _hash_periodic(pi, pj, TEX_SIZE / patch_grid, seed + 4)
		if patch_hash < p.overlay_amount:
			# Randomized-per-patch wear strength - "some panels are salvage
			# from a rustier wreck than others."
			color = color.lerp(wear_color, patch_hash * 0.6)
			roughness += 0.1
	elif p.overlay_style == "blotch":
		var blotch_noise = _periodic_noise2d(float(x) / 24.0, float(y) / 24.0, TEX_SIZE / 24, seed + 5)
		var blotch_mask = smoothstep(0.5 - p.overlay_amount * 0.3, 0.5 + p.overlay_amount * 0.3, blotch_noise)
		color = color.lerp(accent_color, blotch_mask)
	elif p.overlay_style == "frost":
		var frost_noise = _periodic_noise2d(float(x) / 6.0, float(y) / 6.0, TEX_SIZE / 6, seed + 6)
		var frost_mask = smoothstep(1.0 - p.overlay_amount * 0.5, 1.0, frost_noise)
		color = color.lerp(wear_color, frost_mask * 0.7)
		roughness -= frost_mask * 0.25

	# Trim/color-blocking band: a horizontal painted stripe (global Y
	# position, so it forms one continuous belt per texture tile) - THE
	# primary accent_color carrier now (previously just a brightness cue for
	# a separately-computed live accent tint). Bold two-tone paint job per
	# the reference sprites.
	var v = float(y) / TEX_SIZE
	var band_lo = p.trim_band[0]
	var band_hi = p.trim_band[1]
	var band_mask = smoothstep(band_lo - 0.015, band_lo, v) * (1.0 - smoothstep(band_hi, band_hi + 0.015, v))
	color = color.lerp(accent_color, band_mask * 0.88)

	return {
		"albedo": color,
		"height": height,
		"roughness": clamp(roughness, 0.05, 0.95),
	}

func _generate_faction_textures(faction_id: String, params: Dictionary, vis: Dictionary):
	var albedo_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var rough_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var height_field = []
	var raw_albedo_field = []
	height_field.resize(TEX_SIZE * TEX_SIZE)
	raw_albedo_field.resize(TEX_SIZE * TEX_SIZE)

	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var s = _eval_surface(x, y, params, vis)
			raw_albedo_field[y * TEX_SIZE + x] = s.albedo
			rough_img.set_pixel(x, y, Color(s.roughness, s.roughness, s.roughness))
			height_field[y * TEX_SIZE + x] = s.height

	# Normal map + baked directional shading, both derived from the same
	# height field via central differences (wrapping at the texture edge -
	# tiles via triplanar sampling so the gradient must wrap too, not
	# clamp). The baked-shading multiplier is what gives the pre-rendered-
	# sprite look: real light/dark falloff painted into the albedo itself,
	# on top of (not instead of) the real-time shader's own dynamic
	# lighting response later.
	var normal_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var strength = 3.0
	var light_dir = LIGHT_DIR.normalized()
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

			# Strong contrast range (0.35 - 1.7, not a gentle nudge) so
			# upper-facing panels read as genuinely lit and recesses/rivet
			# undersides read as genuinely shadowed, matching the baked-
			# lighting look of a pre-rendered sprite. Applied per-channel so
			# it modulates VALUE of the now-real faction color, not hue.
			var ndotl = n.dot(light_dir)
			var shade = clamp(0.35 + (ndotl * 0.5 + 0.5) * 1.35, 0.3, 1.7)
			var raw = raw_albedo_field[y * TEX_SIZE + x]
			var final_color = Color(clamp(raw.r * shade, 0.0, 1.0), clamp(raw.g * shade, 0.0, 1.0), clamp(raw.b * shade, 0.0, 1.0))
			albedo_img.set_pixel(x, y, final_color)

	albedo_img.save_png(OUT_DIR + "/" + faction_id + "_albedo.png")
	normal_img.save_png(OUT_DIR + "/" + faction_id + "_normal.png")
	rough_img.save_png(OUT_DIR + "/" + faction_id + "_roughness.png")
