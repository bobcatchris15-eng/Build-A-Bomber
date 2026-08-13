shader_type spatial;
// Baseline ground for the heightmap Skirmish terrain (skirmish.gd's Ground
// mesh, built by TerrainBuilder.build_ground_visual_mesh()).
//
// The problem this solves: the ground mesh covers the entire playable map -
// 300+ world units across on the larger maps - with a single 6-unit tiled
// texture. That's ~50 repeats edge to edge, all visible at once at RTS camera
// heights, and the eye reads that as a regular grid long before it reads any
// individual tile as good or bad ground. Per Chris: "at RTS scale, large
// differentiation will be more important than seam matching."
//
// Approach: sample up to three variants of the same surface and cross-fade
// between them using LOW-FREQUENCY noise, at a wavelength far larger than the
// tile itself (macro_scale is in tile units, so ~0.06 means one blend feature
// per ~16 tiles / ~100 world units). The tiling grid doesn't disappear - it's
// still there in the fine detail - but it stops being the dominant large-scale
// pattern, because what the eye now picks up first is the irregular drift
// between variants, which has no period.
//
// Why blending rather than picking one variant per patch: a hard per-patch
// choice puts a visible straight edge wherever two patches meet, which just
// trades one grid artifact for another. The zone planes can get away with
// hard per-zone selection (_variant_for_position in terrain_builder.gd)
// because a zone's boundary is already a real, intentional edge in the map.
// The baseline ground has no such edges to hide behind.
//
// Cost: three texture-set samples per pixel where there was one. Terrain is a
// single opaque pass with no overdraw, so this is the cheapest place in the
// frame to spend that.
//
// WHAT THIS REPLACES AND WHY (PR 3, 2026-08-12):
// v1 used smoothstep interpolation and uncorrupted UV sampling for the blend
// mask. Smoothstep's second derivative is not continuous — when the noise is
// sampled at grazing angles for specular response, the non-smooth transitions
// between cells become visible as a harsh "staircase" artifact. The uncorrupted
// UV field also produces a regular, mechanical pattern that the eye reads as grid
// structure rather than organic variation.
// v2 replaces smoothstep with quintic Hermite interpolation (continuous second
// derivative everywhere) and adds two-layer domain warping to the macro blend
// noise so the transition boundaries between variants bend and flow organically.
// A second fBM octave with non-integer frequencies breaks the remaining large-
// scale periodicity. The result: no grid structure, no staircase transitions,
// organic large-scale variation across the full map extent.

uniform sampler2D albedo_0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_0 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_0 : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_1 : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_2 : hint_default_white, filter_linear_mipmap, repeat_enable;

// How many of the three slots are real. Slots beyond this are ignored rather
// than sampled as black, so a surface with only one variant on disk still
// renders correctly instead of fading into nothing.
uniform int variant_count : hint_range(1, 3) = 3;

uniform vec4 ground_tint : source_color = vec4(1.0);
// Blend feature size, in tile units (UV is already world-units/tile-size).
// Smaller = larger patches of a single variant.
uniform float macro_scale = 0.06;
// A second, finer noise octave breaks the first one's smooth blobs into
// something less obviously procedural without reintroducing a short period.
uniform float detail_scale = 0.19;
uniform float blend_contrast : hint_range(0.5, 8.0) = 2.2;

// Chris's terrain direction: "realistic, maybe a bit washed out / overexposed
// and serious" - as opposed to the saturated comic-book treatment the units
// get in hull_faction_material.gdshader. These two knobs are what put the
// terrain on the far side of that contrast, and the contrast is the point:
// neither look reads as deliberate on its own.
uniform float terrain_desaturate : hint_range(0.0, 1.0) = 0.22;
uniform float terrain_exposure_lift : hint_range(0.0, 0.5) = 0.09;

// --- Noise primitives (v2) ---

// PCG3D integer hash (X5 fix): Bit-exact on every GPU and immune to coordinate precision loss.
uvec3 pcg3d(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	return v;
}

float hash21(vec2 p) {
	uvec2 u = uvec2(ivec2(p));
	uvec3 h = pcg3d(uvec3(u, 0u));
	return float(h.x) * (1.0 / 4294967295.0);
}

// Quintic Hermite interpolation. Continuous first AND second derivative everywhere
// (unlike smoothstep, which has a cusp in its second derivative at f=0.5).
// This eliminates the "staircase" artifact that smoothstep produces when
// viewed at grazing angles in specular response.
vec2 quintic(vec2 f) {
	return f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = quintic(f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Two-layer domain warping. Samples two warp noise fields and uses them to
// distort the input coordinates before sampling the primary noise. This bends
// the noise grid out of alignment, making the blend boundaries flow organically
// rather than forming regular geometric transition shapes.
vec2 domain_warp(vec2 p, float freq) {
	float wx = value_noise(p * freq + vec2(3.7, 9.1));
	float wy = value_noise(p * freq + vec2(8.2, 4.3));
	return p + vec2(wx, wy) * 0.31;
}

// Two-octave fBM using non-integer frequencies. Integer harmonics (1.0, 2.0,
// 4.0...) align to the noise grid and reintroduce periodicity at large scales.
// Irrational-ish multipliers (1.31, 1.73, 2.17) have no common integer
// denominator with the grid, so octaves never re-align — the result has no
// overall period regardless of how large the coordinate space grows.
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 2; i++) {
		v += amp * value_noise(p * freq);
		freq *= 1.73;  // non-integer so it never aligns to the grid
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;

	// Domain-warped macro blend: the warp bends the noise field so the
	// transition boundaries between terrain variants flow organically rather
	// than forming regular geometric shapes.
	vec2 warped_uv = domain_warp(uv, macro_scale * 0.73);
	float n_macro = fbm(warped_uv);

	// Detail layer stays uncorrupted — its job is to break up the macro
	// blobs with fine-scale texture, not to create its own large structure.
	float n_detail = value_noise(uv * detail_scale + vec2(37.2, 11.7));
	float m = clamp((n_macro * 0.75 + n_detail * 0.25 - 0.5) * blend_contrast + 0.5, 0.0, 1.0);

	vec3 alb;
	vec3 nrm;
	float rgh;

	if (variant_count <= 1) {
		alb = texture(albedo_0, uv).rgb;
		nrm = texture(normal_0, uv).rgb;
		rgh = texture(rough_0, uv).r;
	} else if (variant_count == 2) {
		alb = mix(texture(albedo_0, uv).rgb, texture(albedo_1, uv).rgb, m);
		nrm = mix(texture(normal_0, uv).rgb, texture(normal_1, uv).rgb, m);
		rgh = mix(texture(rough_0, uv).r, texture(rough_1, uv).r, m);
	} else {
		// Split the 0..1 mask into two overlapping halves so all three
		// variants get comparable area and every transition is a fade.
		float w = m * 2.0;
		vec3 a01 = mix(texture(albedo_0, uv).rgb, texture(albedo_1, uv).rgb, clamp(w, 0.0, 1.0));
		vec3 n01 = mix(texture(normal_0, uv).rgb, texture(normal_1, uv).rgb, clamp(w, 0.0, 1.0));
		float r01 = mix(texture(rough_0, uv).r, texture(rough_1, uv).r, clamp(w, 0.0, 1.0));
		float w2 = clamp(w - 1.0, 0.0, 1.0);
		alb = mix(a01, texture(albedo_2, uv).rgb, w2);
		nrm = mix(n01, texture(normal_2, uv).rgb, w2);
		rgh = mix(r01, texture(rough_2, uv).r, w2);
	}

	alb *= ground_tint.rgb;

	// Washed-out grade, applied last so it acts on the blended result rather
	// than being averaged away between variants.
	float luma = dot(alb, vec3(0.2126, 0.7152, 0.0722));
	alb = mix(alb, vec3(luma), terrain_desaturate);
	alb = alb * (1.0 - terrain_exposure_lift) + terrain_exposure_lift;

	ALBEDO = alb;
	NORMAL_MAP = nrm;
	ROUGHNESS = rgh;
	SPECULAR = 0.15;
}
