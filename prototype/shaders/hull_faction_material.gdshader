shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// Faction visual identity system: ONE shared hull material, driven by two
// independent inputs - faction (paint color + wear/patina level) and armor
// material (metallic/roughness "what is this plating made of" character,
// plus shield_mode for energy_shielding). Same mesh geometry across every
// faction always (per Chris's explicit direction) - differentiation is
// entirely these shader parameters, no separate textures/assets needed.
// Wear is procedural (object-space value noise), not a texture map, so this
// scales to any hull mesh without needing UV-unwrapped art.

uniform vec4 faction_color : source_color = vec4(0.6, 0.6, 0.65, 1.0);
uniform vec4 wear_color : source_color = vec4(0.3, 0.28, 0.25, 1.0);
uniform float wear_amount : hint_range(0.0, 1.0) = 0.3;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.4;
// 0 = solid armor plating, 1 = translucent glowing energy shield (replaces
// the old fixed-blue energy_shielding look - the shield glow now tints to
// whichever faction is wearing it).
uniform float shield_mode : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_base : hint_range(0.0, 1.0) = 1.0;
uniform float noise_scale : hint_range(1.0, 40.0) = 6.0;
// Damage-flash feedback (battle_unit.gd's _flash_hull()/player_vehicle.gd's
// equivalent) - briefly pushed to 1.0 and back on a hit, replacing the old
// "swap albedo_color to RED and back" approach that only worked on
// StandardMaterial3D. Same visual result (a hull flashes bright red for
// ~0.12s when hit), just driven by a uniform instead of mutating a color.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

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
	float n = noise3(VERTEX * noise_scale);
	float n2 = noise3(VERTEX * noise_scale * 2.3 + vec3(91.7, 12.3, 5.5));
	float grunge = clamp(n * 0.6 + n2 * 0.4, 0.0, 1.0);
	float wear_mask = smoothstep(1.0 - wear_amount - 0.18, 1.0 - wear_amount + 0.18, grunge);

	vec3 base = mix(faction_color.rgb, wear_color.rgb, wear_mask);
	base = mix(base, vec3(1.0, 0.05, 0.05), flash_amount);
	ALBEDO = base;
	METALLIC = mix(metallic_base, metallic_base * 0.35, wear_mask);
	ROUGHNESS = mix(roughness_base, min(roughness_base + 0.5, 1.0), wear_mask);
	ALPHA = alpha_base;
	if (shield_mode > 0.5) {
		EMISSION = faction_color.rgb * 0.6;
	}
}
