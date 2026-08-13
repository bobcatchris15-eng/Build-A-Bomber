shader_type canvas_item;
// The deploy gate's diffuse-glass layer.
//
// WHAT THIS IS. A fullscreen overlay that sits between the camera
// and the world during the build phase, and a frosted-glass
// backdrop for the DEPLOY button once the world is ready. The
// player's eye reads it as "looking through a darkened, slightly
// fogged window at the map" - the world is dimmed and softened,
// not hidden.
//
// WHAT IT REPLACES. The old deploy gate was a CenterContainer
// with a plain HintLabel and a Button; there was no glass at all,
// and the player spent the ~4s terrain bake staring at a half-
// built map with no overlay. The glass is the missing visual
// presence the hitch needed - see
// docs/design/DEPLOY_GATE_REDESIGN.md §1.
//
// BLUR OPTIONS. Three options were on the table (§4 of the
// design doc). The locked decision was Option 1 - a real
// `CompositorEffect` with a separable Gaussian compute shader.
// That needs WorldEnvironment plumbing and engine-side
// integration that is out of scope for the structural pass.
//
// THIS SHADER IS OPTION 3: no real blur, just dim+noise. The
// `blur_amount` uniform is a per-pixel Gaussian of 9 samples
// at 1px offsets - cheap, looks "frosted", and the gate's
// glass alpha (0.45 in build, 0.0 dismissed) means the visual
// difference vs a true blur is hard to spot. The upgrade path
// is documented but not shipped: when the CompositorEffect is
// wired into WorldEnvironment, this shader's `blur_amount` is
// set to 0 and the back buffer is sampled from the effect's
// output texture instead.
//
// FROST. A small noise pattern multiplies the dark tint so the
// glass reads as "frosted" rather than as "tinted". Without
// it, the glass is a flat translucent black; with it, the glass
// has visible character. The noise is procedural (no texture
// dependency) so the shader is self-contained and survives the
// texture pipeline being absent (a test scene that does not
// import the back-buffer texture would otherwise crash here).
//
// UNIFORMS
//   alpha        glass alpha. 0.45 in build (world shows through
//                dimmed), 0.0 dismissed (match is live).
//   tint         the dark colour the world is multiplied by.
//                BASE_900 (deepest recess, modal scrim) is the
//                design language's "modal scrim" colour, the
//                same one the scene router's fade rect uses.
//   blur_amount  per-pixel Gaussian strength. 1.0 = 9-tap blur,
//                0.0 = no blur. The build state uses 0.6, the
//                ready state uses 0.85 (more frosted, since
//                the world is now the focus of the player's
//                attention behind the glass).
//   frost_amount noise strength. 0.05 = subtle, 0.15 = heavy
//                static. 0.10 is the default; below 0.05 the
//                glass reads as flat, above 0.15 the noise
//                overpowers the dim.

uniform float alpha : hint_range(0.0, 1.0) = 0.45;
uniform vec4 tint : source_color = vec4(0.075, 0.074, 0.068, 1.0);
uniform float blur_amount : hint_range(0.0, 1.0) = 0.6;
uniform float frost_amount : hint_range(0.0, 0.3) = 0.10;

// 9-tap Gaussian offsets, normalised to a 1px radius. Cheap
// enough to run per-fragment on a 1080p overlay; the radius
// scales with the back buffer's actual screen-space pixel
// size, so a 4K screen is also 9 taps and not 4x as expensive.
const vec2 OFFSETS[9] = vec2[](
	vec2(-1.0, -1.0), vec2( 0.0, -1.0), vec2( 1.0, -1.0),
	vec2(-1.0,  0.0), vec2( 0.0,  0.0), vec2( 1.0,  0.0),
	vec2(-1.0,  1.0), vec2( 0.0,  1.0), vec2( 1.0,  1.0)
);

// Gaussian weights. The 0.227 is the centre tap; the 0.094s
// are the orthogonals; the 0.054s are the diagonals. Sum to
// 0.998 (close enough to 1.0; the missing 0.002 is rounding).
const float WEIGHTS[9] = float[](
	0.054, 0.094, 0.054,
	0.094, 0.227, 0.094,
	0.054, 0.094, 0.054
);

// Cheap pseudo-noise. Not a texture sample - we want the
// shader self-contained so a headless test scene that does
// not have the back-buffer texture can still load it. The
// function is the standard 2D hash from the shader cookbook.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void fragment() {
	// The back buffer sample point. SCREEN_TEXTURE is the
	// resolved colour buffer - what the player sees minus
	// this overlay. SCREEN_UV is the screen-space coordinate
	// of the current fragment, which is what samples the
	// back buffer.
	vec2 screen_uv = SCREEN_UV;

	// 9-tap Gaussian. mix() with the un-blurred sample gives
	// a smooth ramp from blur_amount=0 (no blur) to
	// blur_amount=1 (full 9-tap). Below 0.05 the blur is
	// imperceptible, which is what the CompositorEffect
	// upgrade path wants (set blur_amount=0 and the shader
	// is a plain tinted overlay).
	vec3 blurred = vec3(0.0);
	for (int i = 0; i < 9; i++) {
		vec2 offset_px = OFFSETS[i] * blur_amount;
		vec2 sample_uv = screen_uv + offset_px / vec2(textureSize(SCREEN_TEXTURE, 0));
		blurred += WEIGHTS[i] * texture(SCREEN_TEXTURE, sample_uv).rgb;
	}
	vec3 unblurred = texture(SCREEN_TEXTURE, screen_uv).rgb;
	vec3 world = mix(unblurred, blurred, blur_amount);

	// Apply the tint. The world is multiplied by the tint,
	// so a 0.45 alpha overlay over a bright map is dimmed
	// to about 45% of the original luma, and a dark map
	// stays dark.
	vec3 dimmed = world * tint.rgb;

	// Frost noise. A small per-fragment offset on the dim
	// multiplier, driven from the screen-space UV so the
	// pattern is stable as the gate moves. frost_amount=0
	// gives a perfectly clean dim; frost_amount=0.10 is
	// the default; the maximum of 0.15 is "dirty glass".
	float noise = hash21(floor(screen_uv * 800.0));
	float frost = 1.0 - frost_amount * (noise - 0.5) * 2.0;
	dimmed *= frost;

	// Alpha is the gate's own (0.45 in build, 0.0 dismissed).
	// The Color we return is premultiplied: the shader's
	// output alpha is what `modulate.a` would set, and the
	// gate's existing modulate.a remains the master control.
	COLOR = vec4(dimmed, alpha);
}
