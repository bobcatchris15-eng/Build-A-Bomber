extends SceneTree
# Objective seamlessness score for a candidate tileable texture.
#
# Context: the faction albedos currently in assets/textures/factions/ are
# rendered hero images of metal plates - rounded corners, a drop shadow, a
# grey background border, and one large accent stripe. Triplanar projection
# can't carry composition like that, which is why hull SIDES read as
# stratified banding while the top looks fine. Replacing them means sourcing
# genuinely tileable swatches, and image generators do NOT guarantee that
# opposite edges match. This measures whether they actually do, instead of
# leaving it to eyeballing a thumbnail.
#
# Method: a texture tiles seamlessly iff the discontinuity across the wrap
# boundary is no worse than the discontinuity anywhere else in the image. So
# rather than reporting a raw edge difference (meaningless in isolation - a
# noisy texture has large differences everywhere), this compares:
#   seam_delta     = mean |pixel difference| across the wrap boundary
#   interior_delta = mean |pixel difference| between adjacent columns/rows
#                    sampled through the middle of the image
# and reports the RATIO. ~1.0 means the seam is indistinguishable from normal
# internal variation, i.e. genuinely seamless. Large values mean a visible
# join. The ratio is what makes the number comparable between a smooth swatch
# and a busy one.
#
# Run:
#   ./Godot_v4.3-stable_win64_console.exe --headless \
#       --script tools/check_texture_seam.gd --path . -- <path> [<path> ...]
# With no paths given it checks every faction albedo currently in the repo,
# which is useful as a baseline for how bad the present ones are.

const FACTION_DIR = "res://assets/textures/factions/"

# Ratio above which a seam is likely to be visible in game. Calibrated as a
# starting point, not a law - a texture at 1.8 with very low absolute deltas
# may still look fine, which is why absolute numbers are printed too.
const VISIBLE_SEAM_RATIO = 2.0

func _init():
	var args = OS.get_cmdline_user_args()
	var paths: Array = []
	if args.is_empty():
		var dir = DirAccess.open(FACTION_DIR)
		if dir:
			for f in dir.get_files():
				if f.ends_with("_albedo.png"):
					paths.append(FACTION_DIR + f)
		paths.sort()
	else:
		for a in args:
			paths.append(a)

	if paths.is_empty():
		print("No textures to check.")
		quit(1)

	print("%-38s %10s %10s %8s  %s" % ["TEXTURE", "SEAM", "INTERIOR", "RATIO", "VERDICT"])
	print("-".repeat(88))
	var worst := 0.0
	for p in paths:
		var img := _load_image(p)
		if img == null:
			print("%-38s  (failed to load)" % p.get_file())
			continue
		var r := _score(img)
		worst = maxf(worst, r.ratio)
		var verdict := "OK" if r.ratio < VISIBLE_SEAM_RATIO else "VISIBLE SEAM"
		print("%-38s %10.4f %10.4f %8.2f  %s" % [
			p.get_file(), r.seam, r.interior, r.ratio, verdict])
	print("-".repeat(88))
	print("Worst ratio: %.2f (threshold %.1f)" % [worst, VISIBLE_SEAM_RATIO])
	quit(0)

# Handles both res:// imported textures and loose files on disk, since
# candidate swatches will typically be checked BEFORE being imported into the
# project.
# Always reads the PNG bytes off disk, never load(). Using load() on a res://
# path returns Godot's IMPORTED copy from .godot/imported/, which is stale
# until a reimport runs - so immediately after a bake this reported the OLD
# texture's scores and looked like the bake had done nothing. This tool exists
# to judge source files, so it should read source files.
func _load_image(path: String) -> Image:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var img := Image.new()
	if img.load(abs_path) != OK:
		return null
	return img

func _score(img: Image) -> Dictionary:
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()

	# Wrap boundary: last column against first column, last row against first.
	var seam_total := 0.0
	for y in range(h):
		seam_total += _diff(img.get_pixel(w - 1, y), img.get_pixel(0, y))
	for x in range(w):
		seam_total += _diff(img.get_pixel(x, h - 1), img.get_pixel(x, 0))
	var seam := seam_total / float(w + h)

	# Interior reference: adjacent-column and adjacent-row differences sampled
	# across the image. Sampling several positions rather than just the centre
	# avoids being fooled by a texture that happens to be locally flat in the
	# middle (very common - generators like to put the "subject" centrally and
	# leave the edges busier).
	var interior_total := 0.0
	var interior_count := 0
	for frac in [0.2, 0.35, 0.5, 0.65, 0.8]:
		var cx := int(w * frac)
		var cy := int(h * frac)
		for y in range(h):
			interior_total += _diff(img.get_pixel(cx, y), img.get_pixel(mini(cx + 1, w - 1), y))
			interior_count += 1
		for x in range(w):
			interior_total += _diff(img.get_pixel(x, cy), img.get_pixel(x, mini(cy + 1, h - 1)))
			interior_count += 1
	var interior := interior_total / maxf(float(interior_count), 1.0)

	return {
		"seam": seam,
		"interior": interior,
		# Guard the degenerate case of a perfectly flat image (interior 0),
		# where any seam at all is infinitely worse in ratio terms.
		"ratio": seam / maxf(interior, 0.00001),
	}

func _diff(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
