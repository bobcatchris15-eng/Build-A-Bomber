extends SceneTree
# Converts Chris's Flow-generated per-faction material swatches (flat,
# text-free, evenly-lit 1024x1024 photos-of-painted-metal, staged at
# prototype/scratch/flow_source/{faction}.jpg) into the game's actual
# per-faction texture triplet (albedo/normal/roughness), replacing
# tools/generate_faction_textures.gd's fully-procedural output for these 10
# factions. Per Chris's direction: Flow's image becomes the real albedo;
# normal and roughness are DERIVED from it (not separately authored, Flow
# doesn't produce real PBR data) using the same height-field-from-luminance
# approach generate_faction_textures.gd already uses for its own bake, just
# driven by the photo's actual luminance instead of procedural noise.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script tools/process_flow_faction_textures.gd

const SRC_DIR = "res://scratch/flow_source/"
const OUT_DIR = "res://assets/textures/factions"
const TEX_SIZE = 1024

const FACTIONS = [
	"industrialists", "technocrats", "expansionists", "salvage_union",
	"crimson_concordat", "glacier_syndicate", "dune_runners",
	"ledger_combine", "bayou_irregulars", "aerodrome_cartel",
]

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for faction_id in FACTIONS:
		_process_one(faction_id)
	quit(0)

# Separable box blur (horizontal pass then vertical), wrapping at the
# texture edge - same reason everything else here wraps, this tiles
# triplanar so a blur seam at the edge would be as visible as any other
# discontinuity.
func _box_blur(field: Array, size: int, radius: int) -> Array:
	var h_pass = []
	h_pass.resize(size * size)
	for y in range(size):
		for x in range(size):
			var total = 0.0
			for k in range(-radius, radius + 1):
				total += field[y * size + ((x + k + size) % size)]
			h_pass[y * size + x] = total / float(radius * 2 + 1)
	var v_pass = []
	v_pass.resize(size * size)
	for y in range(size):
		for x in range(size):
			var total = 0.0
			for k in range(-radius, radius + 1):
				total += h_pass[((y + k + size) % size) * size + x]
			v_pass[y * size + x] = total / float(radius * 2 + 1)
	return v_pass

# Make an arbitrary image tile by mirror-blending its borders, in place.
#
# Why mirror-blend rather than the more commonly cited "offset by half and
# heal the cross seam": offset-and-heal needs an inpainting step to hide the
# seam it deliberately creates, and anything cheap enough to write here
# (blur, clone) leaves a smudged band. Mirror-blending instead makes the two
# opposite edges converge on the SAME value, so the match is exact by
# construction rather than by repair.
#
# The construction: within a band of `band` pixels at each edge, blend each
# pixel toward its mirror on the opposite edge, with the blend weight ramping
# from 0.5 exactly at the edge down to 0.0 at the inner limit of the band.
# At x=0 the result is 0.5*px(0) + 0.5*px(W-1); at x=W-1 it's
# 0.5*px(W-1) + 0.5*px(0). Those are identical, so column 0 and column W-1
# match exactly - which is precisely the definition of tiling in X. The ramp
# means the correction fades out smoothly rather than ending in a hard line
# of its own.
#
# Cost: the blend does soften detail within the band, so `band` is a
# trade-off - too wide and the edges visibly lose contrast against the middle,
# too narrow and the correction is abrupt. An eighth of the image is a
# reasonable default for these swatches, whose detail is small-scale and
# uniform enough to survive it.
# Static so it can be called without instantiating this script - it extends
# SceneTree (it's a --script entry point), and `.new()` on a SceneTree
# subclass spawns a second tree and hangs. Learned the hard way.
static func _make_seamless(img: Image, band: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	band = clampi(band, 1, mini(w, h) / 2 - 1)

	# --- Horizontal pass (fixes the left/right join) ---
	# Read from a snapshot so mirror lookups always see ORIGINAL pixels; if we
	# sampled the image being written, the second half of each row would blend
	# against values already modified by the first half.
	var src := img.duplicate() as Image
	for y in range(h):
		for i in range(band):
			var t := 0.5 * (1.0 - float(i) / float(band))
			# Left edge blends toward the right edge's mirror, and vice versa.
			img.set_pixel(i, y, src.get_pixel(i, y).lerp(src.get_pixel(w - 1 - i, y), t))
			img.set_pixel(w - 1 - i, y, src.get_pixel(w - 1 - i, y).lerp(src.get_pixel(i, y), t))

	# --- Vertical pass (fixes the top/bottom join) ---
	# Snapshot again, so this pass sees the horizontally-corrected image and
	# the corner regions end up consistent with both passes.
	src = img.duplicate() as Image
	for x in range(w):
		for i in range(band):
			var t := 0.5 * (1.0 - float(i) / float(band))
			img.set_pixel(x, i, src.get_pixel(x, i).lerp(src.get_pixel(x, h - 1 - i), t))
			img.set_pixel(x, h - 1 - i, src.get_pixel(x, h - 1 - i).lerp(src.get_pixel(x, i), t))

func _process_one(faction_id: String):
	var src_path = SRC_DIR + faction_id + ".jpg"
	var img = Image.load_from_file(ProjectSettings.globalize_path(src_path))
	if img == null:
		print("SKIP (failed to load): ", faction_id)
		return

	# Center-crop to square (Flow's swatches are already ~1024x1024, but be
	# defensive), then resize to the exact working size.
	var w = img.get_width()
	var h = img.get_height()
	var side = min(w, h)
	var crop_x = (w - side) / 2
	var crop_y = (h - side) / 2
	img.convert(Image.FORMAT_RGB8)
	var region_img = Image.create(side, side, false, Image.FORMAT_RGB8)
	region_img.blit_rect(img, Rect2i(crop_x, crop_y, side, side), Vector2i(0, 0))
	region_img.resize(TEX_SIZE, TEX_SIZE, Image.INTERPOLATE_LANCZOS)

	# Force the swatch to tile before anything downstream touches it.
	# Flow (like any image generator) does not edge-match: measured with
	# tools/check_texture_seam.gd, 6 of the 10 original swatches had clearly
	# visible seams, the worst at 11x the image's own internal variation.
	# Triplanar sampling tiles these textures across every hull face, so a
	# seam isn't a subtle artifact - it's a hard line repeating down the side
	# of every unit.
	_make_seamless(region_img, TEX_SIZE / 8)

	region_img.save_png(OUT_DIR + "/" + faction_id + "_albedo.png")

	# Height field = luminance (bright rivet highlights read as raised,
	# dark seam grooves read as recessed - a reasonable proxy since Flow
	# was prompted for flat, even lighting with no cast shadows of its
	# own, so luminance variation is mostly real surface detail, not
	# incidental scene lighting).
	var height_field = []
	var lum_field = []
	height_field.resize(TEX_SIZE * TEX_SIZE)
	lum_field.resize(TEX_SIZE * TEX_SIZE)
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var c = region_img.get_pixel(x, y)
			var lum = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			lum_field[y * TEX_SIZE + x] = lum
			height_field[y * TEX_SIZE + x] = lum

	# Blur the luminance field before deriving normals from it - Flow's
	# JPEG output has real per-pixel/block compression noise (and fine
	# photo grain) that adjacent-pixel derivatives amplify into a harsh,
	# regular banding pattern once triplanar-tiled across a hull (found via
	# a real in-engine screenshot: a coherent blue panel read as dozens of
	# thin horizontal stripes). A wide-radius box blur removes that
	# high-frequency noise while keeping genuine large-scale structure
	# (rivets, panel seams, the trim stripe) intact - those are tens of
	# pixels wide, well above the blur radius.
	var blurred_lum = _box_blur(lum_field, TEX_SIZE, 6)

	var normal_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var rough_img = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var strength = 3.5
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var x0 = (x - 1 + TEX_SIZE) % TEX_SIZE
			var x1 = (x + 1) % TEX_SIZE
			var y0 = (y - 1 + TEX_SIZE) % TEX_SIZE
			var y1 = (y + 1) % TEX_SIZE
			var dx = (blurred_lum[y * TEX_SIZE + x1] - blurred_lum[y * TEX_SIZE + x0]) * strength
			var dy = (blurred_lum[y1 * TEX_SIZE + x] - blurred_lum[y0 * TEX_SIZE + x]) * strength
			var n = Vector3(-dx, -dy, 1.0).normalized()
			normal_img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

			# Roughness heuristic: darker/recessed (seams, corrosion, dirt)
			# reads rougher; brighter (worn-bright edges, rivet heads,
			# clean paint) reads smoother - matches how these actually
			# behave physically. Local contrast (vs. a coarse blur
			# estimate via the 4 orthogonal neighbors) adds extra
			# roughness at detail edges, same spirit as the procedural
			# generator's seam/rivet roughness bumps.
			var lum = lum_field[y * TEX_SIZE + x]
			var neighbor_avg = (lum_field[y * TEX_SIZE + x0] + lum_field[y * TEX_SIZE + x1] + lum_field[y0 * TEX_SIZE + x] + lum_field[y1 * TEX_SIZE + x]) / 4.0
			var local_contrast = abs(lum - neighbor_avg)
			var r = clamp(0.75 - lum * 0.35 + local_contrast * 1.5, 0.05, 0.95)
			rough_img.set_pixel(x, y, Color(r, r, r))

	normal_img.save_png(OUT_DIR + "/" + faction_id + "_normal.png")
	rough_img.save_png(OUT_DIR + "/" + faction_id + "_roughness.png")
	print("Processed ", faction_id, " (", side, "x", side, " source -> ", TEX_SIZE, "x", TEX_SIZE, ")")
