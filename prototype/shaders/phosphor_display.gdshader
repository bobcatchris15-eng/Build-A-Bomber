shader_type canvas_item;
// The L2 phosphor display layer: a CRT readout, for anything showing LIVE data.
//
// WHERE THIS FITS. Three layers make up the interface's surfaces and each has
// one job (see UX_REDESIGN_PLAN.md section 8):
//   L1 equipment  ui_material.gdshader + the 9-slice plates - panels, buttons
//   L2 phosphor   THIS - glass, scanlines, emission. Live telemetry only.
//   L3 placard    stamped/engraved labels - the furniture around the glass
//
// THE RULE THIS SHADER ENCODES: phosphor means live. Static text never goes on
// the glass; a label belongs stamped into the L1 bezel around it. Break that and
// the layer stops carrying information and becomes decoration.
//
// FOUR THINGS THAT ARE EASY TO GET WRONG HERE, all learned from
// ui_material.gdshader's own header and all invisible in a single screenshot:
//
//   1. SCANLINE PITCH IS IN SCREEN PIXELS, NOT UV. This is the big one. A
//      scanline term written as `sin(UV.y * 200.0)` has a frequency that scales
//      with the control, so a 180px minimap and a 600px telemetry rail get
//      different line counts - and at some sizes the lines land near the pixel
//      grid and moire into broad banding. Driven from SCREEN_PIXEL_SIZE, the
//      pitch is physically constant, which is what a real shadow mask is. It
//      also means the effect survives the 80%-150% UI scale range Phase 9 adds.
//
//   2. BLOOM COMES OFF LIT PIXELS ONLY. Blooming the whole quad washes the
//      glass grey and destroys the black level that makes a tube read as a tube.
//      The glow is sampled from the source's own luminance.
//
//   3. THE UNLIT PHOSPHOR IS NOT BLACK. It is a very dark version of the tube's
//      own emission colour. A neutral grey "off" state reads as a dead LCD.
//      Same reasoning as ui_tokens.gd's warm-shadow note.
//
//   4. FLICKER MUST BE NEARLY IMPERCEPTIBLE. Real refresh flicker at the
//      amplitude people remember is a migraine at desk distance for hours. This
//      is deliberately an order of magnitude subtler than "authentic", and it is
//      disabled entirely under reduced motion - see PhosphorPanel's wiring.

// The tube's emission colour. Set from Tokens.PHOSPHOR_AMBER (Design Lab) or
// PHOSPHOR_GREEN (battle). Never from the signal palette - phosphor is a
// substrate, not a state.
uniform vec4 lit_color : source_color = vec4(1.0, 0.690, 0.0, 1.0);
uniform vec4 unlit_color : source_color = vec4(0.220, 0.145, 0.020, 1.0);
uniform vec4 glass_color : source_color = vec4(0.031, 0.043, 0.035, 1.0);

// Distance between scanline centres, in screen pixels. 3.0 is the tuned value;
// below ~2.0 the lines alias badly at fractional UI scales.
uniform float scanline_pitch : hint_range(1.0, 8.0) = 3.0;
uniform float scanline_depth : hint_range(0.0, 1.0) = 0.28;

uniform float bloom_strength : hint_range(0.0, 2.0) = 0.55;
uniform float bloom_radius_px : hint_range(0.0, 6.0) = 2.0;

// Barrel-ish darkening toward the edges. This is the CHEAP half of a curved
// tube: actually distorting the UVs would misregister the text against the L1
// bezel drawn around it, which reads as a layout bug rather than as curvature.
// Corner falloff alone carries the read.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;

uniform float flicker_amount : hint_range(0.0, 0.1) = 0.012;
uniform float flicker_speed : hint_range(0.0, 200.0) = 87.0;

// Fine vertical aperture-grille striping. Much subtler than the scanlines and
// on the other axis, so together they read as a mask rather than as stripes.
uniform float grille_depth : hint_range(0.0, 0.5) = 0.08;

// --- Cold-War Radar / PPI Sweep Mode ---
uniform bool enable_radar_sweep = false;
uniform float sweep_speed : hint_range(0.1, 5.0) = 0.8;
uniform bool show_range_rings = false;


float luminance(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);

	// --- Emission ------------------------------------------------------------
	float excite = luminance(src.rgb) * src.a;

	// --- Radar PPI Sweep Simulation ---
	if (enable_radar_sweep) {
		vec2 d_center = UV - vec2(0.5);
		float dist = length(d_center) * 2.0;
		float angle = atan(d_center.y, d_center.x);
		float sweep_phase = fract(TIME * sweep_speed * 0.18);
		float angle_phase = fract((angle + 3.14159265) / 6.2831853);
		float sweep_diff = fract(sweep_phase - angle_phase);
		float sweep_beam = exp(-sweep_diff * 12.0) * float(dist <= 1.0);
		excite = max(excite * (0.3 + 0.7 * sweep_beam), sweep_beam * 0.35);

		// Tactical range rings
		if (show_range_rings && dist <= 1.0) {
			float ring1 = abs(dist - 0.33);
			float ring2 = abs(dist - 0.66);
			float ring3 = abs(dist - 0.98);
			float ring_signal = smoothstep(0.015, 0.0, min(min(ring1, ring2), ring3));
			excite += ring_signal * 0.15;
		}
	}

	// --- Bloom from lit pixels only -----------------------------------------
	vec2 r = SCREEN_PIXEL_SIZE * bloom_radius_px;
	float glow = 0.0;
	glow += luminance(texture(TEXTURE, UV + vec2(r.x, 0.0)).rgb);
	glow += luminance(texture(TEXTURE, UV - vec2(r.x, 0.0)).rgb);
	glow += luminance(texture(TEXTURE, UV + vec2(0.0, r.y)).rgb);
	glow += luminance(texture(TEXTURE, UV - vec2(0.0, r.y)).rgb);
	glow *= 0.25 * bloom_strength;

	float energy = clamp(excite + glow, 0.0, 1.5);

	// --- Scanlines, in SCREEN pixels ----------------------------------------
	float line_phase = FRAGCOORD.y / max(scanline_pitch, 0.5);
	float scan = 1.0 - scanline_depth * (0.5 + 0.5 * cos(line_phase * 6.2831853));

	// Vertical grille
	float grille_phase = FRAGCOORD.x / max(scanline_pitch, 0.5);
	float grille = 1.0 - grille_depth * (0.5 + 0.5 * cos(grille_phase * 6.2831853));

	// --- Flicker -------------------------------------------------------------
	float flicker = 1.0 - flicker_amount * (0.5 + 0.5 * sin(TIME * flicker_speed));

	// --- Compose -------------------------------------------------------------
	vec3 base = mix(glass_color.rgb, unlit_color.rgb, 0.35);
	vec3 col = base + lit_color.rgb * energy;

	col *= scan * grille * flicker;

	// --- Vignette ------------------------------------------------------------
	vec2 d = UV - vec2(0.5);
	float vig = 1.0 - vignette_strength * dot(d, d) * 4.0;
	col *= clamp(vig, 0.0, 1.0);

	COLOR = vec4(col, COLOR.a);
}
