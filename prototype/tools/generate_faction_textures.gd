extends SceneTree
# Generates real per-faction albedo/normal/roughness texture maps, entirely
# procedurally, headlessly, in pure Godot (Image + hand-rolled periodic value
# noise) - no Blender, no external tools, no hand-authored art. This matches
# hull_greebles.gd's existing precedent (procedural Image generation instead
# of hand-painted assets) but PRE-BAKES to PNGs once rather than generating
# at runtime every load, since these are much higher-resolution (256x256 vs
# greebles' 48x48 cutouts) and a per-pixel GDScript loop at that size is too
# slow to repeat every game boot.
#
# Every noise/pattern function below is built on a PERIODIC lattice (the hash
# wraps at a period that evenly divides TEX_SIZE) specifically so the result
# tiles seamlessly - these textures are sampled triplanar in world space
# (hull_faction_material.gdshader), so a visible seam at the wrap point would
# show up constantly as hulls scale/stretch through the Design Lab's
# hull_scale slider.
#
# Re-run after changing FACTION_TEX_PARAMS below:
#   ./Godot_v4.3-stable_win64_console.exe --headless --script tools/generate_faction_textures.gd

const OUT_DIR = "res://assets/textures/factions"
const TEX_SIZE = 256

# panel_size/rivet_spacing must evenly divide TEX_SIZE (256) so the grid
# wraps cleanly at the texture edge - each is a period, not raw pixels.
# overlay_style: "" none, "patch" salvage-style mismatched rectangular
# plates, "blotch" soft organic camo patches, "frost" icy speckle highlights.
# base_gray is fixed at 0.5 for every faction on purpose, not a per-faction
# knob - the shader (hull_faction_material.gdshader) renormalizes the
# sampled texture as `tex_albedo * 2.0` so it modulates base_color/
# accent_color as a neutral-centered light/dark map. That renormalization
# only nets to ~1.0 when the texture's own average IS 0.5; an earlier
# version varied base_gray per faction (0.38-0.7) as a brightness
# "personality," which silently broke the assumption - technocrats'
# base_gray=0.68 rendered as a blown-out, nearly solid accent_color hull
# with the pale base_color barely readable, caught via a real screenshot
# comparison, not a hunch. All the actual per-faction distinctiveness
# comes from the STRUCTURAL parameters below (panel size, rivets,
# corrosion, streaks, overlays) - brightness didn't need to vary too.
const FACTION_TEX_PARAMS = {
	"industrialists": {
		"seed": 101, "panel_size": 64, "seam_width": 3, "panel_variance": 0.05,
		"rivet_spacing": 32, "rivet_radius": 3.0,
		"grain_strength": 0.10, "corrosion_amount": 0.30, "streak_amount": 0.08,
		"overlay_style": "", "overlay_amount": 0.0, "base_gray": 0.5,
	},
	"technocrats": {
		"seed": 202, "panel_size": 32, "seam_width": 1, "panel_variance": 0.02,
		"rivet_spacing": 0, "rivet_radius": 0.0,
		"grain_strength": 0.03, "corrosion_amount": 0.02, "streak_amount": 0.25,
		"overlay_style": "", "overlay_amount": 0.0, "base_gray": 0.5,
	},
	"expansionists": {
		"seed": 303, "panel_size": 32, "seam_width": 4, "panel_variance": 0.08,
		"rivet_spacing": 64, "rivet_radius": 2.5,
		"grain_strength": 0.18, "corrosion_amount": 0.5, "streak_amount": 0.05,
		"overlay_style": "", "overlay_amount": 0.0, "base_gray": 0.5,
	},
	"salvage_union": {
		"seed": 404, "panel_size": 32, "seam_width": 2, "panel_variance": 0.06,
		"rivet_spacing": 32, "rivet_radius": 2.0,
		"grain_strength": 0.15, "corrosion_amount": 0.4, "streak_amount": 0.05,
		"overlay_style": "patch", "overlay_amount": 0.7, "base_gray": 0.5,
	},
	"crimson_concordat": {
		"seed": 505, "panel_size": 32, "seam_width": 2, "panel_variance": 0.04,
		"rivet_spacing": 64, "rivet_radius": 2.0,
		"grain_strength": 0.1, "corrosion_amount": 0.15, "streak_amount": 0.3,
		"overlay_style": "", "overlay_amount": 0.0, "base_gray": 0.5,
	},
	"glacier_syndicate": {
		"seed": 606, "panel_size": 32, "seam_width": 1, "panel_variance": 0.03,
		"rivet_spacing": 0, "rivet_radius": 0.0,
		"grain_strength": 0.05, "corrosion_amount": 0.03, "streak_amount": 0.25,
		"overlay_style": "frost", "overlay_amount": 0.5, "base_gray": 0.5,
	},
	"dune_runners": {
		"seed": 707, "panel_size": 32, "seam_width": 2, "panel_variance": 0.06,
		"rivet_spacing": 64, "rivet_radius": 2.0,
		"grain_strength": 0.2, "corrosion_amount": 0.45, "streak_amount": 0.05,
		"overlay_style": "", "overlay_amount": 0.0, "base_gray": 0.5,
	},
	"ledger_combine": {
		"seed": 808, "panel_size": 16, "seam_width": 1, "panel_variance": 0.02,
		"rivet_spacing": 0, "rivet_radius": 0.0,
		"grain_strength": 0.02, "corrosion_amount": 0.0, "streak_amount": 0.2,
		"overlay_style": "", "overlay_amount": 0.0, "base_gray": 0.5,
	},
	"bayou_irregulars": {
		"seed": 909, "panel_size": 64, "seam_width": 2, "panel_variance": 0.05,
		"rivet_spacing": 32, "rivet_radius": 2.0,
		"grain_strength": 0.15, "corrosion_amount": 0.3, "streak_amount": 0.05,
		"overlay_style": "blotch", "overlay_amount": 0.55, "base_gray": 0.5,
	},
	"aerodrome_cartel": {
		"seed": 1010, "panel_size": 32, "seam_width": 2, "panel_variance": 0.04,
		"rivet_spacing": 16, "rivet_radius": 2.0,
		"grain_strength": 0.08, "corrosion_amount": 0.1, "streak_amount": 0.3,
		"overlay_style": "", "overlay_amount": 0.0, "base_gray": 0.5,
	},
}

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for faction_id in FACTION_TEX_PARAMS.keys():
		_generate_faction_textures(faction_id, FACTION_TEX_PARAMS[faction_id])
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
# Returns {"albedo": float 0-1, "height": float, "roughness": float 0-1}

static func _eval_surface(x: int, y: int, p: Dictionary) -> Dictionary:
	var seed = p.seed
	var panel_size = p.panel_size
	var albedo = p.base_gray
	var height = 0.0
	var roughness = 0.55

	# Panel grid: per-panel brightness jitter (hashed on panel INDEX, not raw
	# pixel, so it's periodic at panel_size and wraps cleanly) + seam groove.
	var lx = x % panel_size
	var ly = y % panel_size
	var panels_across = TEX_SIZE / panel_size
	var panel_i = (x / panel_size) % panels_across
	var panel_j = (y / panel_size) % panels_across
	var panel_jitter = (_hash_periodic(panel_i, panel_j, panels_across, seed) - 0.5) * 2.0 * p.panel_variance
	albedo += panel_jitter

	var seam_dist = min(lx, min(panel_size - lx, min(ly, panel_size - ly)))
	var seam_mask = clamp(1.0 - float(seam_dist) / float(max(p.seam_width, 1)), 0.0, 1.0)
	albedo -= seam_mask * 0.15
	height -= seam_mask * 0.4
	roughness += seam_mask * 0.1

	# Rivets: small raised domes at a separate (usually finer) grid.
	if p.rivet_spacing > 0:
		var rx = x % p.rivet_spacing
		var ry = y % p.rivet_spacing
		var dx = min(rx, p.rivet_spacing - rx)
		var dy = min(ry, p.rivet_spacing - ry)
		var rivet_dist = sqrt(float(dx * dx + dy * dy))
		var rivet_mask = clamp(1.0 - rivet_dist / max(p.rivet_radius, 0.1), 0.0, 1.0)
		albedo += rivet_mask * 0.12
		height += rivet_mask * 0.6
		roughness -= rivet_mask * 0.2

	# Fine grain (isotropic noise) - breaks up flatness on every faction.
	var grain = _periodic_noise2d(float(x) / 8.0, float(y) / 8.0, TEX_SIZE / 8, seed + 1) - 0.5
	albedo += grain * p.grain_strength
	height += grain * p.grain_strength * 0.3

	# Directional brushed streaks: long bands running along local X (the
	# hull's nose-to-tail axis, matching the runtime shader's own
	# ANISOTROPY_FLOW = vec2(1,0) convention) - high frequency in Y, only a
	# tiny X contribution so the bands are elongated, not perfectly straight.
	if p.streak_amount > 0.0:
		var streak = _periodic_noise2d(float(x) * 0.04, float(y) / 3.0, TEX_SIZE / 3, seed + 2) - 0.5
		albedo += streak * p.streak_amount * 0.3
		roughness -= abs(streak) * p.streak_amount * 0.1

	# Corrosion/pitting: coarse noise thresholded into dark, rough speckle.
	if p.corrosion_amount > 0.0:
		var corr_noise = _periodic_noise2d(float(x) / 16.0, float(y) / 16.0, TEX_SIZE / 16, seed + 3)
		var corr_mask = smoothstep(1.0 - p.corrosion_amount, 1.0, corr_noise)
		albedo -= corr_mask * 0.25
		height -= corr_mask * 0.3
		roughness += corr_mask * 0.3

	# Overlay: salvage's mismatched rectangular patches, bayou's organic
	# camo blotches, or glacier's icy speckle highlights.
	if p.overlay_style == "patch":
		var patch_grid = 64
		var pi = (x / patch_grid) % (TEX_SIZE / patch_grid)
		var pj = (y / patch_grid) % (TEX_SIZE / patch_grid)
		var patch_hash = _hash_periodic(pi, pj, TEX_SIZE / patch_grid, seed + 4)
		if patch_hash < p.overlay_amount:
			albedo += (patch_hash - 0.5) * 0.3
			roughness += 0.1
	elif p.overlay_style == "blotch":
		var blotch_noise = _periodic_noise2d(float(x) / 24.0, float(y) / 24.0, TEX_SIZE / 24, seed + 5)
		var blotch_mask = smoothstep(0.5 - p.overlay_amount * 0.3, 0.5 + p.overlay_amount * 0.3, blotch_noise)
		albedo += (blotch_mask - 0.5) * 0.2
	elif p.overlay_style == "frost":
		var frost_noise = _periodic_noise2d(float(x) / 6.0, float(y) / 6.0, TEX_SIZE / 6, seed + 6)
		var frost_mask = smoothstep(1.0 - p.overlay_amount * 0.5, 1.0, frost_noise)
		albedo += frost_mask * 0.35
		roughness -= frost_mask * 0.25

	return {
		"albedo": clamp(albedo, 0.0, 1.0),
		"height": height,
		"roughness": clamp(roughness, 0.05, 0.95),
	}

func _generate_faction_textures(faction_id: String, params: Dictionary):
	var albedo_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var rough_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var height_field = []
	height_field.resize(TEX_SIZE * TEX_SIZE)

	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var s = _eval_surface(x, y, params)
			albedo_img.set_pixel(x, y, Color(s.albedo, s.albedo, s.albedo))
			rough_img.set_pixel(x, y, Color(s.roughness, s.roughness, s.roughness))
			height_field[y * TEX_SIZE + x] = s.height

	# Normal map from the height field via central differences, wrapping at
	# the texture edge (same reason as the periodic noise above - this tiles
	# via triplanar sampling, so the gradient must wrap too, not clamp).
	var normal_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var strength = 2.5
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

	albedo_img.save_png(OUT_DIR + "/" + faction_id + "_albedo.png")
	normal_img.save_png(OUT_DIR + "/" + faction_id + "_normal.png")
	rough_img.save_png(OUT_DIR + "/" + faction_id + "_roughness.png")
