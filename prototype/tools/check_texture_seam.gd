extends SceneTree
# Objective seamlessness score for a candidate tileable texture.
#
# Context: hull surfaces are sampled TRIPLANAR in world space (hull meshes
# aren't UV-unwrapped - see shaders/hull_faction_material.gdshader), so the
# texture repeats many times across a single unit. A wrap-boundary mismatch
# therefore isn't a subtle artifact, it's a hard line ruled down the side of
# every vehicle in the match, at whatever period texture_scale works out to.
#
# The shared set in assets/textures/hull/ is baked by
# tools/generate_hull_surface_texture.gd from PERIODIC value noise and
# wrapping central differences, so in principle it tiles by construction. This
# checks that the guarantee actually holds rather than trusting it - the
# wrapping is spread across a lattice hash, a panel/rivet grid whose period has
# to divide TEX_SIZE, and a normal-map derivative pass, and any one of those
# losing its wrap (a panel size that no longer divides evenly, a clamped
# gradient) reintroduces a seam silently. It also still serves its original
# purpose: vetting an externally-sourced candidate plate BEFORE it goes in,
# since image generators do NOT guarantee that opposite edges match.
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
# Run (from prototype/):
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script tools/check_texture_seam.gd [-- <path> [<path> ...]]
# With no paths given it checks the whole shared hull surface set, which is the
# regression check to run after any edit to generate_hull_surface_texture.gd.

const HULL_TEX_DIR = "res://assets/textures/hull/"

# All three maps, not just the albedo. The normal and roughness maps are
# derived from the same height field but through their OWN passes (central
# differences for the normal, a separate per-pixel formula for roughness), so
# "the albedo wraps" does not imply the other two do - a gradient pass that
# clamped instead of wrapping would leave the albedo spotless and put a seam
# in the lighting response only.

# Ratio above which a seam is likely to be visible in game. Calibrated as a
# starting point, not a law - a texture at 1.8 with very low absolute deltas
# may still look fine, which is why absolute numbers are printed too.
const VISIBLE_SEAM_RATIO = 2.0

func _init():
	var args = OS.get_cmdline_user_args()
	var paths: Array = []
	if args.is_empty():
		var dir = DirAccess.open(HULL_TEX_DIR)
		if dir:
			for f in dir.get_files():
				if f.ends_with(".png"):
					paths.append(HULL_TEX_DIR + f)
		paths.sort()
	else:
		for a in args:
			paths.append(a)

	if paths.is_empty():
		print("No textures to check (looked in %s)." % HULL_TEX_DIR)
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
