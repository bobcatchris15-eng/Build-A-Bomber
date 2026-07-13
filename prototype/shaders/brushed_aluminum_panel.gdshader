shader_type canvas_item;
// Brushed-anodized-aluminum UI chrome: a 2D counterpart to the hull shader
// (hull_faction_material.gdshader) - same idea, same procedural-noise-
// instead-of-textures approach, applied to Control backgrounds instead of
// 3D meshes. Horizontal brush streaks + a faction color tint (anodizing
// dye) + procedural wear/grime patches that scale with the faction's own
// wear level, so the whole UI's chrome shifts color and roughs up
// depending on whichever faction is currently selected.

uniform vec4 faction_tint : source_color = vec4(0.6, 0.6, 0.65, 1.0);
uniform float wear_amount : hint_range(0.0, 1.0) = 0.3;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.55;

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
	// Brushed streaks run along Y at a high frequency, low frequency along
	// X - real brushed metal, a single direction of fine parallel scratches.
	float streak = noise2(vec2(UV.x * 4.0, UV.y * 260.0));
	float base_shade = 0.5 + streak * 0.14;

	// Wear/grime patches - coarse two-octave noise, same technique as the
	// hull shader's grunge mask.
	float grime = noise2(UV * 7.0) * 0.6 + noise2(UV * 17.0 + vec2(41.0, 7.0)) * 0.4;
	float wear_mask = smoothstep(1.0 - wear_amount - 0.2, 1.0 - wear_amount + 0.2, grime);

	vec3 metal = vec3(base_shade);
	vec3 tinted = mix(metal, metal * faction_tint.rgb * 1.5, tint_strength);
	vec3 grime_color = vec3(0.1, 0.09, 0.08);
	vec3 final_color = mix(tinted, grime_color, wear_mask * 0.65);

	COLOR = vec4(final_color, faction_tint.a);
}
