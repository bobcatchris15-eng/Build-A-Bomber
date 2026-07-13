shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// Faction visual identity system - v2, built against VISUAL_ART_DIRECTION.md's
// parameter model (section 2). ONE shared hull material across every
// faction and every armor material: same mesh geometry always, differentiation
// entirely these shader parameters. No baked masks (no UV-unwrapped art, no
// curvature/AO bake pass per hull - the fragile Blender import pipeline this
// week made a real per-mesh bake pipeline too risky) - wear/grime/panel-line
// masks are all PROCEDURAL approximations instead (see each section below),
// deliberately trading a little physical precision for zero new asset
// dependencies. Logged as a judgment call in DECISIONS_NEEDED.md.
//
// World-space sampling (not raw local VERTEX) for every procedural mask:
// the Design Lab lets players continuously stretch hulls via hull_scale, and
// sampling noise from local/object-space VERTEX would keep the SAME number
// of noise cycles regardless of scale - meaning a stretched hull just shows
// a smeared/enlarged pattern instead of more repetitions (the exact failure
// mode VISUAL_ART_DIRECTION.md section 2 calls out). World-space position
// scales WITH the stretch, so noise cycles per world-unit stay constant and
// a bigger hull genuinely shows more grain/panel repetitions, not a blur.

uniform vec4 base_color : source_color = vec4(0.6, 0.6, 0.65, 1.0);
uniform vec4 accent_color : source_color = vec4(0.5, 0.5, 0.55, 1.0);
uniform vec4 detail_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.6;
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float anisotropy : hint_range(0.0, 1.0) = 0.3;
uniform float brush_scale : hint_range(0.5, 8.0) = 2.0;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.3;
uniform vec4 wear_color : source_color = vec4(0.3, 0.28, 0.25, 1.0);
uniform float grime_amount : hint_range(0.0, 1.0) = 0.2;
uniform float edge_highlight_strength : hint_range(0.0, 1.0) = 0.5;
uniform vec4 emissive_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emissive_strength : hint_range(0.0, 2.0) = 0.0;
// Camo-style large-patch base/accent blending (Bayou Irregulars' mottled
// two-tone green) instead of the default thin panel-seam trim - 0 for every
// other faction (accent only shows at seams), nonzero blooms accent into
// broad soft patches across the whole surface.
uniform float mottle_amount : hint_range(0.0, 1.0) = 0.0;
// decal_tint is part of the parameter model (VISUAL_ART_DIRECTION.md) for a
// shared stencil/hazard/mascot decal atlas - deliberately NOT wired to any
// visible effect yet, since a real decal atlas needs actual authored texture
// content (exactly the kind of hand-painted per-faction asset this whole
// system exists to avoid). Kept as a harmless placeholder uniform so
// faction data is future-proofed for when real decal art exists.
uniform vec4 decal_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 0 = solid armor plating, 1 = translucent glowing energy shield (the glow
// tints to whichever faction is wearing it, via emissive_color).
uniform float shield_mode : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_base : hint_range(0.0, 1.0) = 1.0;
// Damage-flash feedback (battle_unit.gd's _flash_hull()) - briefly pushed to
// 1.0 and back on a hit.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash3(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

void fragment() {
	// Curvature/edge approximation: screen-space derivative of the world
	// normal is large at silhouette edges/corners and near-zero across flat
	// panel interiors - a real-time stand-in for a baked curvature map
	// (VISUAL_ART_DIRECTION.md's "Mask B"), needing no per-mesh bake pass.
	float curvature = clamp(length(fwidth(world_normal)) * 4.0, 0.0, 1.0);
	// Blend a little organic noise into the pure-curvature signal so wear
	// doesn't look like a geometric edge-detect filter - real weathering is
	// patchy, not a clean outline.
	float grunge = noise3(world_pos * brush_scale * 3.0) * 0.5 + noise3(world_pos * brush_scale * 7.0 + vec3(41.0, 7.0, 91.0)) * 0.5;
	float wear_signal = clamp(curvature * 0.7 + grunge * 0.3, 0.0, 1.0);
	float wear_mask = smoothstep(1.0 - wear_amount - 0.2, 1.0 - wear_amount + 0.2, wear_signal);

	// Grime (VISUAL_ART_DIRECTION.md's "Mask A", cavity/AO-driven, opposite
	// spatial logic from wear - collects in recesses, not on exposed edges):
	// approximated as low curvature (flat/recessed, not a sharp edge) PLUS a
	// bias toward the lower part of the hull in local Y (splash-up grime
	// near ground contact) rather than a real cavity map.
	float grime_low_bias = clamp(1.0 - (VERTEX.y * 0.4 + 0.5), 0.0, 1.0);
	float grime_noise = noise3(world_pos * brush_scale * 2.0 + vec3(13.0, 5.0, 29.0));
	float grime_mask = clamp((1.0 - curvature) * grime_low_bias * grime_noise * 1.6, 0.0, 1.0) * grime_amount;

	// Panel-line/rivet grammar (shared "kit of parts" look across every
	// faction, VISUAL_ART_DIRECTION.md 1.3): a periodic world-space seam grid,
	// tinted by accent_color - this is also what carries accent_color's job
	// (trim/stripe tint) without needing a real baked trim mask. mottle_amount
	// overrides this with broad soft patches instead (Bayou Irregulars' camo).
	vec3 seam_coord = world_pos * (1.0 / max(brush_scale, 0.1));
	vec3 seam_frac = abs(fract(seam_coord) - 0.5);
	float seam_line = 1.0 - smoothstep(0.0, 0.06, min(min(seam_frac.x, seam_frac.y), seam_frac.z));
	float mottle_patch = smoothstep(0.35, 0.65, noise3(world_pos * brush_scale * 0.6));
	float accent_mask = mix(seam_line, mottle_patch, mottle_amount);

	vec3 color = mix(base_color.rgb, accent_color.rgb, accent_mask);
	// Small structural bolt highlights at seam intersections, tinted by
	// detail_color - the "oversized bolt-heads at seams" goofy-but-safe
	// detail VISUAL_ART_DIRECTION.md 1.2 calls out, kept small (never
	// competing with base/accent for silhouette read).
	float bolt_dot = 1.0 - smoothstep(0.0, 0.04, length(seam_frac.xy));
	color = mix(color, detail_color.rgb, bolt_dot * 0.5);

	color = mix(color, wear_color.rgb, wear_mask);
	vec3 grime_color = vec3(0.08, 0.075, 0.07);
	color = mix(color, grime_color, grime_mask);
	color = mix(color, vec3(1.0, 0.05, 0.05), flash_amount);
	ALBEDO = color;

	float exposed = clamp(wear_mask * edge_highlight_strength, 0.0, 1.0);
	METALLIC = clamp(mix(metallic, metallic * 0.3 + 0.5 * exposed, wear_mask), 0.0, 1.0);
	ROUGHNESS = clamp(mix(roughness, roughness + 0.5 - 0.3 * exposed, wear_mask) + grime_mask * 0.3, 0.0, 1.0);
	ANISOTROPY = anisotropy * (1.0 - wear_mask * 0.5);
	// Brush direction: lengthwise along the hull's own long axis, in
	// tangent space - Godot's default TANGENT for box/cylinder primitives
	// already runs along local X/U, which lines up with "nose to tail" for
	// every hull in this catalog.
	ANISOTROPY_FLOW = vec2(1.0, 0.0);

	ALPHA = alpha_base;
	if (shield_mode > 0.5) {
		EMISSION = base_color.rgb * 0.6;
	} else if (emissive_strength > 0.0) {
		EMISSION = emissive_color.rgb * emissive_strength;
	}
}
