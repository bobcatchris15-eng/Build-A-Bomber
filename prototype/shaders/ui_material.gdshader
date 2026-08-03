shader_type canvas_item;
// The interface's large-surface material shader - dock bodies, screen
// backdrops, the radial bezel, anything too big for a 96px 9-slice plate to
// cover without showing its repeat.
//
// RELATIONSHIP TO THE OTHER TWO HALVES OF THIS SYSTEM:
//   * tools/generate_ui_plates.py bakes both the small 9-slice plates AND the
//     512px seamless FIELDS this shader samples. The field is the material's
//     actual character - weave, grain, stipple - and is shared with the
//     plates, so a canvas dock body and a canvas tooltip are visibly the same
//     cloth rather than two different guesses at cloth.
//   * tools/build_ui_theme.gd consumes the plates. This file consumes the
//     fields. Neither invents its own colour.
//
// GENERALISED FROM brushed_aluminum_panel.gdshader, which it replaces for new
// work. Two properties of that shader were hard-won and are preserved exactly;
// both are easy to regress and neither is visible in a single screenshot:
//
//   1. FEATURE SIZE IS IN PIXELS, NOT UV. The original bug was `noise2(UV *
//      7.0)`, whose feature size scaled with the node - on a fullscreen
//      backdrop that produced ~230px grime blobs, and on a narrow sidebar the
//      same material looked like a completely different one. Everything here
//      is driven from `panel_size` so a 320px dock and a 1600px backdrop show
//      the same physical grain. This is exactly the resolution-independence
//      problem VISUAL_ART_DIRECTION.md 2.4 raises for stretched hulls, in 2D.
//
//   2. CHROME IS NEUTRAL. The original multiplied the whole panel by the
//      player's faction colour at 0.55 strength, which broke the convention
//      RTS UI depends on - faction colour means "who owns this" when it
//      appears on a unit and cannot also be the wallpaper. It also meant the
//      interface's contrast ratios changed depending on who you picked.
//      `accent_tint` stays at zero strength unless a caller explicitly asks,
//      and the only legitimate caller is the faction-select preview swatch.

// The material field baked by generate_ui_plates.py. Set by
// UITheme.apply_material(); a null texture falls back to flat `base_color`,
// which keeps this usable in a headless test with no imported assets.
uniform sampler2D material_field : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_field = false;

// Pixel dimensions of the node. Callers push this via UITheme; the fallback is
// a sane mid-size panel so a material used without it looks reasonable rather
// than broken.
uniform vec2 panel_size = vec2(512.0, 512.0);

// Pixels of screen per pixel of field texture. 1.0 samples the 512px field at
// its authored scale. Raising it magnifies the grain; this is the ONLY knob
// that should ever change apparent material scale, and it is a physical
// property of the surface, not of the node.
uniform float field_scale : hint_range(0.25, 4.0) = 1.0;

uniform vec4 base_color : source_color = vec4(0.108, 0.106, 0.098, 1.0);

// Master weathering, mirroring the hull shader's parameter model so 2D chrome
// and 3D hulls speak one language (VISUAL_ART_DIRECTION.md section 2).
// wear = scuffing on exposed area, grime = soot collecting in recesses.
uniform float wear_amount : hint_range(0.0, 1.0) = 0.25;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.20;

// Identity wash. OFF by default - see note 2 above.
uniform vec4 accent_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;

// Corner falloff. Mild by default; at 0.55 the plate crushed to near-black at
// the edges and the grain stopped reading entirely.
uniform float vignette : hint_range(0.0, 1.0) = 0.30;

// Overall multiplier, for pushing one surface behind another without
// authoring a second field.
uniform float brightness : hint_range(0.0, 2.0) = 1.0;


float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
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
	// Work in pixels. Every frequency below is "features per pixel" and so is
	// independent of how large the node is.
	vec2 px = UV * panel_size;

	vec3 col = base_color.rgb;

	if (has_field) {
		// Divide by the field's authored size (512) so one field texel maps to
		// one screen pixel at field_scale 1.0 regardless of node dimensions.
		// Using UV here instead would stretch the weave to fit the panel,
		// which is the exact bug note 1 describes.
		vec2 field_uv = px / (512.0 * field_scale);
		col = texture(material_field, field_uv).rgb;
	}

	// Broad roll in the surface, ~400px features. The only large-scale
	// variation, and it stays subtle enough not to compete with the UI on top.
	float roll = noise2(px * 0.0025);
	col *= 0.95 + roll * 0.10;

	// Scuffed patches on exposed area, ~90px features.
	float patch = noise2(px * 0.011);
	float wear_mask = smoothstep(0.62 - wear_amount * 0.30, 0.98, patch);
	col = mix(col, col * 1.35, wear_mask * wear_amount * 0.5);

	// Grime collects in the opposite places to wear - low-lying, broader, and
	// it DARKENS. Driving both from one mask would just be contrast.
	float cav = noise2(px * 0.004 + vec2(17.3, 4.1));
	float grime_mask = smoothstep(0.55, 0.05, cav);
	col = mix(col, col * 0.62, grime_mask * grime_amount);

	col *= brightness;

	// Optional identity wash.
	col = mix(col, col * accent_tint.rgb * 1.35, tint_strength);

	// Corner falloff, so a panel on this separates without needing a shadow.
	vec2 c = UV - vec2(0.5);
	col *= 1.0 - dot(c, c) * vignette;

	COLOR = vec4(col, base_color.a);
}
