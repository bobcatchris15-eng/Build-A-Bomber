extends SceneTree
# Turns Chris's Flow-generated terrain plates (prototype/scratch/flow_terrain/
# *.jpg) into extra VARIANTS of the existing baked terrain texture sets, so a
# surface type is no longer one single tile repeated across the whole map.
#
# Why variants rather than one better tile: at RTS zoom the camera sees a very
# large number of repeats of the same 6-world-unit tile at once, and the eye
# picks out the repetition as a grid long before it picks out any individual
# seam. Chris's direction was explicit - "at RTS scale, large differentiation
# will be more important than seam matching on terrain maps and buildings" -
# so this optimises for making neighbouring patches look DIFFERENT, and
# deliberately does not run the mirror-blend seam pass that
# process_flow_hull_texture.gd applies to hulls.
#
# Variant numbering: variant 0 is the existing fully-procedural bake from
# generate_terrain_textures.gd, which keeps its unsuffixed filename
# ({surface}_albedo.png) and is therefore untouched by this tool - it stays
# the guaranteed-present fallback. This tool writes variants 1..N as
# {surface}_v{n}_albedo.png alongside it. terrain_builder.gd discovers
# whatever exists and picks per-zone; adding or deleting files here changes
# the amount of variety with no code edit.
#
# The derived variants (2, 3) exist because Flow gave us ONE plate per surface
# and one extra variant per surface is barely more varied than none. Rotating
# by 90/180 degrees changes which direction the plate's large-scale features
# run, and the tonal shift changes its overall value, which together read as
# genuinely different ground at RTS distance even though they share a source.
# This is a stopgap for source-image scarcity, not a substitute for it - more
# distinct Flow plates dropped into SRC_DIR will beat any amount of
# re-mixing, and the VARIANT_RECIPES table is where they'd be wired in.
#
# Run: ./Godot_v4.3-stable_win64_console.exe --headless --script tools/process_flow_terrain_textures.gd

const SRC_DIR = "res://scratch/flow_terrain/"
const OUT_DIR = "res://assets/textures/terrain"
# Larger than generate_terrain_textures.gd's procedural TEX_SIZE of 256: these
# start life as real photographic plates with detail worth keeping, and unlike
# the procedural bake there's no per-pixel GDScript cost that scales with it
# beyond this one offline run.
const TEX_SIZE = 512

# Which Flow plate feeds which of terrain_builder.gd's surface types. Several
# surfaces legitimately share a source - "mud" is a reasonable base for both
# marsh and snow_mud's churned ground, and the per-surface tint below is what
# keeps them from reading as the same material.
#
# tint multiplies the plate's albedo, pulling a generic photo toward the
# palette VISUAL_ART_DIRECTION.md section 4 specifies for that surface, so the
# variants sit in the same colour family as the procedural variant 0 they'll
# be shuffled against. Without it a raw photo variant next to a palette-baked
# one reads as an obvious patch of the wrong texture.
# A first pass mapped gravel -> the "concrete" plate, which turned out to be
# rust-streaked metal decking rather than concrete and read as a wrecked
# hangar floor, not ground. It also gave marsh and snow_mud the same mud plate
# with only a mild tint between them, and in the variant grid they came out
# near-indistinguishable. Both are corrected here: gravel now derives from the
# rock plate (crushed stone and rock are genuinely the same material at
# different scales, which the zoom in VARIANT_RECIPES exploits), and marsh vs
# snow_mud are pushed much further apart tonally - marsh dark and green-brown
# wet, snow_mud pale and desaturated.
# Per-surface knobs beyond the shared source plate:
#   sat_bias  scales the recipe's saturation - the main lever separating two
#             surfaces that share a plate
#   lift      adds toward white AFTER tinting. Needed because a multiply can
#             only ever darken: snow_mud was given a >1.0 tint on a first pass
#             and still came out grey tarmac, since multiplying a dark mud
#             photo by 1.1 is nowhere near enough to make it read as snow.
#             Lift is what actually raises the black point.
#   zoom_bias multiplies the recipe's zoom. This is what keeps rocky and
#             gravel apart - they're the same rock plate, and in the first
#             grid they were indistinguishable, because tint and saturation
#             alone don't change what a material IS. Gravel viewed from
#             further out (smaller zoom -> more stones in frame, each smaller)
#             reads as crushed aggregate; rocky viewed closer reads as broken
#             bedrock. Same photo, genuinely different ground.
const SURFACE_SOURCES = {
	"marsh": {"src": "mud", "tint": Color(0.66, 0.74, 0.52), "sat_bias": 1.1, "lift": 0.0, "zoom_bias": 1.0},
	"snow_mud": {"src": "mud", "tint": Color(0.95, 0.96, 1.0), "sat_bias": 0.3, "lift": 0.42, "zoom_bias": 1.0},
	"sand": {"src": "sand", "tint": Color(1.0, 0.96, 0.82), "sat_bias": 1.0, "lift": 0.0, "zoom_bias": 1.0},
	"grassland": {"src": "scrubland", "tint": Color(0.88, 0.95, 0.78), "sat_bias": 1.0, "lift": 0.0, "zoom_bias": 1.0},
	# zoom_bias direction is easy to get backwards: SMALLER zoom crops a
	# smaller region and blows it up, so smaller = magnified = fewer, bigger
	# stones. rocky wants big broken bedrock (small bias), gravel wants fine
	# crushed aggregate (large bias, clamped to the full plate).
	"rocky": {"src": "rock", "tint": Color(0.94, 0.91, 0.87), "sat_bias": 0.95, "lift": 0.0, "zoom_bias": 0.45},
	"gravel": {"src": "rock", "tint": Color(0.84, 0.84, 0.86), "sat_bias": 0.55, "lift": 0.06, "zoom_bias": 1.6},
	"forest": {"src": "scrubland", "tint": Color(0.5, 0.68, 0.44), "sat_bias": 1.15, "lift": 0.0, "zoom_bias": 1.0},
}

# variant number -> transform applied to the source plate.
#   zoom:   crop this fraction of the plate and blow it back up to full size.
#           This is the strongest differentiator available from a single
#           source, because it changes the apparent SCALE of the ground -
#           coarse gravel vs fine grit is the same photo at two zooms, and
#           the eye reads that as different material rather than as a repeat.
#   rotate: quarter-turns, changes the direction large features run
#   flip:   horizontal mirror, breaks up any directional bias rotation alone
#           leaves intact
#   value:  multiplies overall brightness (lighter/darker patch of ground)
#   sat:    scales saturation toward/away from grey
#
# The first grid capture showed rotate+tone alone was not enough - variants
# 2 and 3 were near-copies of variant 1, because rotating a statistically
# uniform texture doesn't change how it reads. Zoom is what actually
# separates them. This is still a workaround for having one source plate per
# surface; more distinct Flow plates would beat it.
const VARIANT_RECIPES = [
	{"n": 1, "zoom": 1.0, "rotate": 0, "flip": false, "value": 1.0, "sat": 1.0},
	{"n": 2, "zoom": 0.45, "rotate": 1, "flip": true, "value": 0.82, "sat": 0.8},
	{"n": 3, "zoom": 0.7, "rotate": 2, "flip": false, "value": 1.14, "sat": 1.25},
]

# Terrain is matte - see generate_terrain_textures.gd's 2026-07-17 note about
# the whole game reading too glossy. Photographic plates carry their own
# specular highlights baked in, so the derived roughness is clamped high
# rather than allowed the full range the faction pipeline uses.
const ROUGH_MIN = 0.72
const ROUGH_MAX = 0.98

func _init():
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var made := 0
	for surface in SURFACE_SOURCES:
		var spec: Dictionary = SURFACE_SOURCES[surface]
		var src_path: String = SRC_DIR + spec["src"] + ".jpg"
		var img = Image.load_from_file(ProjectSettings.globalize_path(src_path))
		if img == null:
			print("SKIP (no source): %s <- %s" % [surface, src_path])
			continue
		img.convert(Image.FORMAT_RGB8)
		var square := _center_square(img)
		for recipe in VARIANT_RECIPES:
			_write_variant(surface, square, spec, recipe)
			made += 1
	print("Wrote %d terrain variants to %s" % [made, OUT_DIR])
	quit(0)

func _center_square(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var side: int = mini(w, h)
	var out := Image.create(side, side, false, Image.FORMAT_RGB8)
	out.blit_rect(img, Rect2i((w - side) / 2, (h - side) / 2, side, side), Vector2i(0, 0))
	out.resize(TEX_SIZE, TEX_SIZE, Image.INTERPOLATE_LANCZOS)
	return out

func _write_variant(surface: String, square: Image, spec: Dictionary, recipe: Dictionary) -> void:
	var tint: Color = spec["tint"]
	var sat_bias := float(spec["sat_bias"])
	var lift := float(spec["lift"])
	var albedo := square.duplicate() as Image

	# Zoom first, while the source is still at full resolution - cropping
	# after a rotate would work too, but doing it here means the Lanczos
	# upscale operates on original pixels rather than resampled ones.
	var zoom := clampf(float(recipe["zoom"]) * float(spec["zoom_bias"]), 0.05, 1.0)
	if zoom < 0.999:
		var crop_side: int = maxi(int(TEX_SIZE * zoom), 8)
		var off: int = (TEX_SIZE - crop_side) / 2
		var cropped := Image.create(crop_side, crop_side, false, Image.FORMAT_RGB8)
		cropped.blit_rect(albedo, Rect2i(off, off, crop_side, crop_side), Vector2i(0, 0))
		cropped.resize(TEX_SIZE, TEX_SIZE, Image.INTERPOLATE_LANCZOS)
		albedo = cropped

	for _i in range(int(recipe["rotate"])):
		albedo.rotate_90(CLOCKWISE)
	if bool(recipe["flip"]):
		albedo.flip_x()

	var value := float(recipe["value"])
	var sat := float(recipe["sat"]) * sat_bias
	var lum_field: Array = []
	lum_field.resize(TEX_SIZE * TEX_SIZE)
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var c := albedo.get_pixel(x, y)
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			# Saturation first, then tint, then value - tinting a desaturated
			# pixel is what actually moves it into the target palette, whereas
			# desaturating an already-tinted one would undo the tint.
			var g := Color(
				lerp(lum, c.r, sat), lerp(lum, c.g, sat), lerp(lum, c.b, sat))
			g = Color(
				clampf(g.r * tint.r * value + lift, 0.0, 1.0),
				clampf(g.g * tint.g * value + lift, 0.0, 1.0),
				clampf(g.b * tint.b * value + lift, 0.0, 1.0))
			albedo.set_pixel(x, y, g)
			lum_field[y * TEX_SIZE + x] = lum

	var suffix := "_v%d" % int(recipe["n"])
	albedo.save_png("%s/%s%s_albedo.png" % [OUT_DIR, surface, suffix])

	# Normal/roughness derived from the plate's own luminance, same
	# height-field-from-luminance approach as the faction pipeline. No blur
	# pass here: that one exists to kill JPEG block noise that the faction
	# shader's hard-thresholded toon specular turns into salt-and-pepper, and
	# terrain uses a plain StandardMaterial3D whose smooth specular response
	# doesn't amplify fine noise the same way. Terrain also WANTS visible
	# fine grain - it's what stops a 6-unit tile reading as flat plastic.
	var normal_img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var rough_img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var strength := 2.0
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var x0 := (x - 1 + TEX_SIZE) % TEX_SIZE
			var x1 := (x + 1) % TEX_SIZE
			var y0 := (y - 1 + TEX_SIZE) % TEX_SIZE
			var y1 := (y + 1) % TEX_SIZE
			var dx: float = (lum_field[y * TEX_SIZE + x1] - lum_field[y * TEX_SIZE + x0]) * strength
			var dy: float = (lum_field[y1 * TEX_SIZE + x] - lum_field[y0 * TEX_SIZE + x]) * strength
			var n := Vector3(-dx, -dy, 1.0).normalized()
			normal_img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

			# Darker (damp, recessed, shadowed grit) reads rougher than
			# brighter (dry, exposed, worn) - the same physical reasoning the
			# faction pipeline uses, compressed into the matte-only band.
			var lum: float = lum_field[y * TEX_SIZE + x]
			var r := clampf(ROUGH_MAX - lum * 0.26, ROUGH_MIN, ROUGH_MAX)
			rough_img.set_pixel(x, y, Color(r, r, r))

	normal_img.save_png("%s/%s%s_normal.png" % [OUT_DIR, surface, suffix])
	rough_img.save_png("%s/%s%s_roughness.png" % [OUT_DIR, surface, suffix])
	print("  %s%s" % [surface, suffix])
