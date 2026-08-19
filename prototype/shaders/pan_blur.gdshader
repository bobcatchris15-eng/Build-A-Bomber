shader_type canvas_item;
//
// PAN BLUR: a fullscreen overlay that produces the "background sliding
// left" effect when entering or leaving the Armor Bay.
//
// WHAT IT IS. A canvas_item shader that samples the framebuffer with a
// horizontal directional blur, parameterised by a `progress` uniform
// (0..1) and a `direction` uniform (-1 for "background slides left to
// imply turning right", +1 for the reverse). The overlay sits on a
// CanvasLayer BELOW SceneRouter's fade at 128, so the SceneRouter fade
// still hides the scene swap and this just adds the motion cue on top.
//
// WHY DIRECTIONAL SAMPLING, NOT A POST-PROCESS BLUR. A uniform Gaussian
// blur applied to the whole frame looks like a soft focus, not a pan.
// A pan is a ONE-AXIS smear - the eye reads the unidirectional sample
// spread as motion in that direction. We sample 12 taps along X with
// weights that fall off at the edges of the kernel, scaled by the
// `progress` uniform so the smear grows as the overlay fades in and
// shrinks as it fades out. At rest (progress = 0, alpha = 0) the
// overlay is invisible and the framebuffer passes through.
//
// TAP COUNT. 12 is the sweet spot for a noticeable smear without the
// per-pixel cost of a 32-tap kernel - the eye reads more taps as more
// motion, but 12 already looks like a fast pan and beyond that the
// cost is invisible quality. Poisson disk would give a more even
// coverage, but the smear has to look like a LINEAR smear, so taps are
// along X only.
//
// COVERAGE STRATEGY. Two passes were considered:
//   * Sample SCREEN_TEXTURE at jittered X offsets: adds motion blur
//     but the offset range has to be at least half the screen width
//     for the smear to read as "the world is moving".
//   * Use SCREEN_UV (which moves with the control) and sample the
//     texture with the inverse UV: this lets us also SLIDE the
//     sampled frame, so the background visibly travels left while
//     blurring. The combined effect is "the world is sliding past the
//     window with a smear on it", which is exactly the pan cue we want.
// We do the second, with the screen UV offset by a small amount per
// tap so the blur is over the original scene, not over itself.
//
// Edge fade: at the LEFT edge of the screen during a forward pan,
// there's no further-back framebuffer to sample from - the smear
// would draw black pixels there. Sampling the nearest in-frame pixel
// instead gives a soft fade-out at the leading edge, so the overlay
// doesn't read as having a hard left border.
//
// USAGE. The overlay script (pan_transition.gd) tweens `progress` from
// 0 to 1 and back, and tints `tint` from a low value to the design's
// BASE_900 mid-transition so the world is darkened as well as blurred.
// SceneRouter's fade runs on top to hide the scene swap, which is what
// keeps the slide visually consistent across the actual change-of-scene.

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
// -1 = world slides left (forward pan, into the paint station)
// +1 = world slides right (reverse pan, back to the build bench)
// `direction` is a reserved word in Godot 4.7.1's shader parser so
// the uniform is named `pan_direction` instead. No `: float` type
// hint here - Godot 4.7.1's parser rejects the redundant form
// (`Expected valid type hint after ':'` when `: float` follows
// `uniform float`).
uniform float pan_direction = -1.0;
uniform float max_blur_pixels : hint_range(4.0, 64.0) = 28.0;
uniform float max_slide_pixels : hint_range(8.0, 200.0) = 80.0;
uniform vec4 tint : source_color = vec4(0.075, 0.074, 0.068, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.55;
uniform float alpha : hint_range(0.0, 1.0) = 0.0;


// 12-tap linear sampling along X. Weights sum to 1 and form a Gaussian-
// ish falloff so the smear has soft edges, not a hard band.
const float TAPS = 12.0;

float gaussian_weight(float x) {
	// x in [-1, 1]
	return exp(-x * x * 2.5);
}


void fragment() {
	vec2 screen_uv = SCREEN_UV;
	vec2 tex_size = vec2(textureSize(SCREEN_TEXTURE, 0));
	vec2 pixel_size = 1.0 / max(tex_size, vec2(1.0));

	float p = clamp(progress, 0.0, 1.0);
	float blur_pixels = max_blur_pixels * p;
	float slide_pixels = max_slide_pixels * p;

	// Total weight for normalising the sum of the Gaussian taps.
	float total_w = 0.0;
	for (int i = 0; i < int(TAPS); i++) {
		float t = (float(i) - (TAPS - 1.0) * 0.5) / ((TAPS - 1.0) * 0.5);
		total_w += gaussian_weight(t);
	}

	vec3 blurred = vec3(0.0);
	for (int i = 0; i < int(TAPS); i++) {
		float t = (float(i) - (TAPS - 1.0) * 0.5) / ((TAPS - 1.0) * 0.5);
		float w = gaussian_weight(t);

		// Tap X offset in pixels. pan_direction reverses the smear axis
		// so the same shader plays forward or reverse.
		float dx_pixels = t * blur_pixels * pan_direction;
		vec2 offset = vec2(dx_pixels * pixel_size.x, 0.0);

		// Per-tap slide: each tap samples at a slightly different X so
		// the blur is sampling the SLIDING frame, not a static one.
		// Only the central tap is at the nominal slide; the others are
		// pulled toward it so the smear carries the slide with it.
		float slide_factor = 1.0 - abs(t) * 0.35;
		float slide_dx_pixels = slide_pixels * pan_direction * slide_factor;
		vec2 sample_uv = screen_uv + vec2(slide_dx_pixels * pixel_size.x, 0.0) + offset;

		// Edge fade: if sample_uv.x is out of [0, 1], fade its weight
		// to zero so we don't read past the framebuffer edge. clamp()
		// would draw a hard band of the edge pixel; this fades the tap
		// weight instead.
		float edge_w = 1.0 - smoothstep(0.0, 0.02, abs(sample_uv.x - 0.5) * 2.0 - 0.98);
		edge_w = clamp(edge_w, 0.0, 1.0);

		vec3 s = texture(SCREEN_TEXTURE, sample_uv).rgb;
		blurred += s * w * edge_w;
	}
	blurred /= total_w;

	// Unblurred base for the centre of the smear, so the overlay doesn't
	// fully desaturate the world during the slow start/end of the pan.
	vec3 base = texture(SCREEN_TEXTURE, screen_uv).rgb;
	float mix_amount = clamp(p * 1.4, 0.0, 1.0);
	vec3 world = mix(base, blurred, mix_amount);

	// Tint toward the design's deep recess colour. Linear interpolation
	// toward tint.rgb at tint_strength, so a partial overlay still has
	// the world visible through it but darkened.
	vec3 darkened = mix(world, tint.rgb, tint_strength * p);

	// Modulate alpha by progress so the overlay eases in/out smoothly.
	COLOR = vec4(darkened, alpha);
}