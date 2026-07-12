class_name ScreenshotDiff
# Pixel-diffing utility for visual regression testing (DECISIONS_NEEDED.md's
# "screenshot-diffing: investigated, not built" entry - greenlit and built
# this pass). Pure comparison logic only; capturing the actual screenshots
# needs windowed rendering (headless Godot's dummy renderer doesn't
# rasterize - confirmed earlier this week), so that lives in a separate
# windowed harness (visual_regression/run_visual_regression.gd). This class
# itself is headlessly testable against synthetic Image objects.

# Two-tier tolerance, both needed to avoid crying wolf on legitimate
# rendering variance (anti-aliasing, font hinting, minor driver jitter)
# while still catching real regressions (a missing texture, a moved panel,
# a mesh clipping through UI):
#   channel_tolerance - how far a single pixel's channel (0..1) can drift
#                        before it's considered "different" at all.
#   max_diff_fraction  - what fraction of the image's pixels are allowed to
#                        exceed channel_tolerance before the images are
#                        considered a mismatch.
static func compare_images(img_a: Image, img_b: Image, channel_tolerance: float = 0.06, max_diff_fraction: float = 0.02) -> Dictionary:
	if img_a.get_size() != img_b.get_size():
		return {
			"match": false,
			"reason": "size mismatch: %s vs %s" % [img_a.get_size(), img_b.get_size()],
			"diff_fraction": 1.0,
			"diff_pixel_count": -1,
			"total_pixels": -1,
		}

	var w = img_a.get_width()
	var h = img_a.get_height()
	var total = w * h
	var diff_count = 0

	# Sampling stride keeps this fast on large screenshots (1280x720 = ~921k
	# pixels) without materially weakening the check - visual regressions
	# worth catching (a missing panel, a wrong-colored region, an offset
	# element) span many contiguous pixels, not a handful of isolated ones,
	# so a 1-in-4 grid sample still reliably detects them.
	var stride = 2
	var sampled = 0
	for y in range(0, h, stride):
		for x in range(0, w, stride):
			sampled += 1
			var pa = img_a.get_pixel(x, y)
			var pb = img_b.get_pixel(x, y)
			var dr = abs(pa.r - pb.r)
			var dg = abs(pa.g - pb.g)
			var db = abs(pa.b - pb.b)
			if dr > channel_tolerance or dg > channel_tolerance or db > channel_tolerance:
				diff_count += 1

	var diff_fraction = float(diff_count) / float(max(1, sampled))
	return {
		"match": diff_fraction <= max_diff_fraction,
		"reason": "" if diff_fraction <= max_diff_fraction else "%.2f%% of sampled pixels exceeded tolerance (allowed %.2f%%)" % [diff_fraction * 100.0, max_diff_fraction * 100.0],
		"diff_fraction": diff_fraction,
		"diff_pixel_count": diff_count,
		"total_pixels": sampled,
	}

# Convenience wrapper for file-based comparison (the actual regression-test
# use case: a freshly-captured PNG against a checked-in baseline PNG).
static func compare_files(path_a: String, path_b: String, channel_tolerance: float = 0.06, max_diff_fraction: float = 0.02) -> Dictionary:
	var img_a = Image.new()
	var err_a = img_a.load(path_a)
	if err_a != OK:
		return {"match": false, "reason": "could not load %s (error %d)" % [path_a, err_a], "diff_fraction": 1.0, "diff_pixel_count": -1, "total_pixels": -1}
	var img_b = Image.new()
	var err_b = img_b.load(path_b)
	if err_b != OK:
		return {"match": false, "reason": "could not load %s (error %d)" % [path_b, err_b], "diff_fraction": 1.0, "diff_pixel_count": -1, "total_pixels": -1}
	return compare_images(img_a, img_b, channel_tolerance, max_diff_fraction)
