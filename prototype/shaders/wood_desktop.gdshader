// Dark wood workbench desktop for the Armor Bay (paint station).
//
// What this replaces: the LabEnvironment cutting mat. The Armor Bay used to
// instance the same LabEnvironment.tscn as the Lab and HullBuilder, which
// gave it a green-and-white cutting mat with kraft model-kit boxes - a
// model-builder's bench. The redesign frames the armor bay as a paint
// station (armor is really just paint), so the floor becomes a dark stained
// wood desktop with faint paint smudges.
//
// The shader is the same basic recipe as cutting_mat.gdshader:
//   - World-space XZ as the pattern basis, so rotation/scale/replacement of
//     the mesh never distorts the grain direction.
//   - Anti-aliased via fwidth() so the grain stays legible across the orbit
//     range, including when DOF kicks in.
//   - Same 50u BoxMesh footprint, same y = -12 placement, so any downstream
//     code that referenced the mat as "the floor under the hull" still
//     finds it where it expects.
//
// Pattern breakdown:
//   1. Dark walnut base colour, very low albedo (a workshop bench)
//   2. Long-grain stripes along Z (the dominant board direction), parallel
//      and close together (~0.4u spacing), so the surface reads as planks
//      without drawing actual plank seams
//   3. Knot-like darker patches at randomised positions
//   4. Faint paint smudges - large low-saturation tinted blobs at scattered
//      positions, layered on top so the surface reads as "has been used"
//   5. A subtle warm vignette toward the edges (the lamp pools light centre)
//
// `paint_smudge_seed` is the per-instance randomised seed so that two
// paint stations don't render identically. The arm of randomness is wide
// enough (3 hash inputs) that adjacent instances look distinctly different
// at gameplay zoom.

shader_type spatial;

render_mode cull_back, depth_draw_opaque;

varying vec3 v_world_pos;

// Walnut base: low value, slightly warm. The whole palette is warm because
// the lighting is tungsten and the surrounding wood is warm - a cool base
// here would read as a different material entirely (plastic laminate).
uniform vec3 base_color : source_color = vec3(0.085, 0.060, 0.040);
uniform vec3 grain_dark : source_color = vec3(0.045, 0.030, 0.020);
uniform vec3 grain_light : source_color = vec3(0.140, 0.105, 0.075);
uniform vec3 knot_color : source_color = vec3(0.030, 0.020, 0.012);
uniform vec3 paint_smudge_a : source_color = vec3(0.420, 0.180, 0.110);
uniform vec3 paint_smudge_b : source_color = vec3(0.140, 0.290, 0.380);
uniform vec3 paint_smudge_c : source_color = vec3(0.350, 0.300, 0.080);

uniform float grain_spacing = 0.42;
uniform float grain_width = 0.08;
uniform float knot_scale = 6.5;
uniform float smudge_scale = 8.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.78;
uniform float paint_smudge_strength = 0.18;
uniform float vignette_strength = 0.35;
uniform vec2 desktop_half_size = vec2(25.0, 25.0);
uniform float paint_smudge_seed = 0.0;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}


// A blob centred at `center` with radius `r`, smoothly falling to zero
// at the edge. Used for both knots (small, dark) and paint smudges (large,
// faint, tinted).
float blob(vec2 p, vec2 center, float r) {
	float d = length(p - center);
	float aa = fwidth(d) * 1.5;
	return 1.0 - smoothstep(r - aa, r + aa, d);
}


void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz;

	// --- Long-grain stripes ---
	// Stripes run along Z (the board direction). abs(fract(p.x) - 0.5)
	// gives a saw-tooth wave along X; taking the closest-band distance
	// gives stripe centres every grain_spacing units.
	float grain_phase = abs(fract(p.x / grain_spacing) - 0.5) * grain_spacing;
	float grain_aa = fwidth(p.x) * 1.4;
	float grain_mask = 1.0 - smoothstep(0.0, grain_width + grain_aa, grain_phase);

	// Long-axis variation: a low-frequency sine along Z so the grain isn't
	// a perfect repetition of identical stripes. Multiplied into the dark
	// grain term so some bands are darker than others.
	float grain_warp = 0.5 + 0.5 * sin(p.y * 0.18 + p.x * 0.03);

	vec3 col = base_color;
	col = mix(col, grain_light, grain_mask * 0.45 * grain_warp);
	col = mix(col, grain_dark, grain_mask * 0.55 * (1.0 - grain_warp));

	// --- Knots: small dark patches at randomised positions ---
	// Quantise p to a knot grid so each knot is centred on a cell. The
	// hash gives a per-cell offset and radius so the knots don't form a
	// regular grid pattern.
	vec2 knot_cell = floor(p / knot_scale);
	vec2 knot_off = (hash22(knot_cell + 13.7) - 0.5) * knot_scale * 0.6;
	vec2 knot_center = (knot_cell + 0.5) * knot_scale + knot_off;
	float knot_r = 0.35 + hash21(knot_cell + 7.3) * 0.55;
	float knot = blob(p, knot_center, knot_r) * step(0.55, hash21(knot_cell + 91.2));
	col = mix(col, knot_color, knot * 0.85);

	// --- Paint smudges: large, faint, tinted ---
	// Three colours chosen to evoke a workshop that's seen a few jobs -
	// not a complete palette, just three tell-tale stains. Each smudge
	// is on its own hash-quantised grid so they don't collide with the
	// knots, and the per-instance seed (paint_smudge_seed) keeps two
	// paint-station instances looking different.
	float smudge_mask_total = 0.0;
	for (int i = 0; i < 3; i++) {
		vec2 seed_offset = vec2(float(i) * 17.3 + paint_smudge_seed,
				float(i) * 31.1 + paint_smudge_seed * 1.3);
		vec2 s_cell = floor((p + seed_offset) / smudge_scale);
		vec2 s_off = (hash22(s_cell + 5.7 + float(i)) - 0.5) * smudge_scale * 0.7;
		vec2 s_center = (s_cell + 0.5) * smudge_scale + s_off + seed_offset;
		float s_r = 1.6 + hash21(s_cell + 11.1 + float(i)) * 2.2;
		float s_present = step(0.62, hash21(s_cell + 23.5 + float(i)));
		float s = blob(p, s_center, s_r) * s_present;
		vec3 s_col = (i == 0) ? paint_smudge_a :
				(i == 1) ? paint_smudge_b : paint_smudge_c;
		col = mix(col, s_col, s * paint_smudge_strength);
		smudge_mask_total += s;
	}

	// --- Vignette: warm darkening toward the edges of the desktop ---
	// Simulates the desk lamp pooling light on the centre of the bench.
	vec2 edge_d = desktop_half_size - abs(p);
	float edge_min = min(edge_d.x, edge_d.y);
	float vignette = 1.0 - smoothstep(0.0, 8.0, edge_min) * vignette_strength;
	col *= vignette;

	ALBEDO = col;
	ROUGHNESS = roughness_value;
	// Wood is non-metallic; slight specular via low metallic term so the
	// matte lacquer still catches a hint of the key light.
	METALLIC = 0.0;
}