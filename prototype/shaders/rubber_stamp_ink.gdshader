shader_type canvas_item;
// Ink dropout for the rubber-stamp overlay (scripts/ui_stamp.gd).
//
// A rubber stamp is the ONE surface in this interface that is not chrome. It is
// ink pressed onto paper by hand, and the thing that sells it is that the
// coverage is never complete: the pad is unevenly loaded, the block rocks
// slightly as it lands, and the result is a solid mark with pinholes in it and
// thin patches along one edge. A flat, evenly-filled rectangle with a crisp
// border reads as a UI panel that happens to be red, which is what the previous
// version was.
//
// So this does exactly two things, both subtractive:
//   1. PINHOLES - fine high-frequency dropout across the whole mark.
//   2. ROCK - one broad low-frequency gradient that starves ink toward a
//      randomised edge, as though the stamp was pressed harder on one side.
//
// Both are driven from `stamp_seed` so two stamps in a row never land
// identically - a repeated identical "defect" reads as a texture bug rather
// than as handling.
//
// Feature size is in PIXELS via `stamp_size`, not UV, for the same reason
// brushed_aluminum_panel.gdshader works that way: a stamp over a long text
// string and a stamp over a short one must have the same grain, and UV-driven
// noise would scale the pinholes with the mark.

uniform vec2 stamp_size = vec2(420.0, 90.0);
uniform float stamp_seed = 0.0;
// 0 = perfect coverage (shader is a no-op), 1 = badly starved pad.
uniform float ink_wear : hint_range(0.0, 1.0) = 0.55;

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + stamp_seed);
	p += dot(p, p + 78.233);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec4 col = COLOR * texture(TEXTURE, UV);
	vec2 px = UV * stamp_size;

	// 1. Pinholes. ~3px features. smoothstep rather than step so the holes
	//    have a soft shoulder - a hard-edged hole reads as a dead pixel.
	float speck = noise2(px * 0.33);
	float pinholes = smoothstep(0.28, 0.62, speck + (1.0 - ink_wear) * 0.5);

	// 2. Rock. One broad gradient across the mark, its direction chosen from
	//    the seed so it isn't always the same corner going light.
	float ang = hash2(vec2(stamp_seed, 7.31)) * 6.2831;
	vec2 dir = vec2(cos(ang), sin(ang));
	float across = dot(UV - vec2(0.5), dir) + 0.5;
	float rock = mix(1.0, smoothstep(-0.15, 0.85, across), ink_wear * 0.7);

	col.a *= clamp(pinholes * rock, 0.0, 1.0);
	COLOR = col;
}
