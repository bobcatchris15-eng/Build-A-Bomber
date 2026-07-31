shader_type canvas_item;
// Painted sheet-metal backdrop for menu screens. The 2D counterpart to the
// hull shader's surface language, but deliberately much quieter: this sits
// BEHIND the interface, and anything it does that draws the eye is a defect.
//
// TWO BUGS THIS REWRITE FIXES, both visible in the 2026-07-30 ui_baseline
// captures:
//
// 1. The noise was driven by raw UV, so its feature size scaled with the
//    node. On a fullscreen 1600x900 ColorRect, `noise2(UV * 7.0)` produced
//    grime blobs ~230px across - the huge smeared grey clouds behind every
//    menu. Feature size now comes from `panel_size` (pixels), so the grain
//    is the same physical size on a 320px sidebar and a fullscreen backdrop.
//    Exactly the resolution-independence problem VISUAL_ART_DIRECTION.md
//    §2.4 calls out for stretched hulls, in 2D.
//
// 2. `mix(metal, metal * faction_tint * 1.5, ...)` at 0.55 strength repainted
//    the entire UI chrome in the player's faction color. That breaks a
//    convention RTS UI depends on: faction/team color must mean "who owns
//    this" when it appears on a unit, and it cannot also be the wallpaper.
//    It also meant the interface's contrast ratios changed depending on who
//    the player picked - Technocrat white chrome and Bayou swamp-green
//    chrome are not the same UI. Chrome is now neutral by default, and
//    `accent_tint` is a small, low-strength identity wash meant for a
//    faction-select preview, not for general use.

uniform vec4 accent_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.3;
// Pixel dimensions of the node this material is on. Callers set it via
// UITheme.apply_backdrop(); the fallback is a sane mid-size panel so a
// material used without it still looks reasonable rather than broken.
uniform vec2 panel_size = vec2(512.0, 512.0);

// Base plate color, deliberately DARKER than UITokens.BASE_800 (the panel
// body). The first pass at this used the same value as the panels, and the
// menu cards had nothing to sit on - a panel and its background at equal
// luminance read as one flat field regardless of the border between them.
// The backdrop is the floor; everything else is above it.
uniform vec4 base_color : source_color = vec4(0.052, 0.051, 0.047, 1.0);

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
	// Work in pixels, not UV. Every frequency below is "features per pixel"
	// and therefore independent of how large the node is.
	vec2 px = UV * panel_size;

	// Fine horizontal brush grain: ~1.5px period vertically, stretched long
	// horizontally. Amplitude is low - this should be felt as texture, not
	// seen as stripes.
	float grain = noise2(vec2(px.x * 0.012, px.y * 0.66));

	// Broad roll in the plate, ~400px features. This is the only large-scale
	// variation, and it stays subtle enough not to compete with UI on top.
	float roll = noise2(px * 0.0025);

	// Patchy weathering, ~90px features.
	float patch = noise2(px * 0.011);
	float wear_mask = smoothstep(0.62 - wear_amount * 0.30, 0.98, patch);

	vec3 col = base_color.rgb;
	col *= 0.94 + roll * 0.12;          // gentle unevenness in the paint
	col += (grain - 0.5) * 0.035;       // brush grain
	col = mix(col, col * 0.72, wear_mask * 0.5);  // scuffed patches

	// Optional identity wash. Off by default (tint_strength 0.0).
	col = mix(col, col * accent_tint.rgb * 1.35, tint_strength);

	// Vignette: pulls the corners down so a centered card separates from the
	// plate without needing a drop shadow. Kept mild - at 0.55 it crushed
	// the plate to near-black at the edges and the grain stopped reading.
	vec2 c = UV - vec2(0.5);
	col *= 1.0 - dot(c, c) * 0.30;

	COLOR = vec4(col, base_color.a);
}
