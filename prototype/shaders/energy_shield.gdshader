shader_type spatial;
render_mode blend_add, cull_back, unshaded, depth_draw_never;

// The energy_shielding hull material's visible bubble.
//
// Chris's brief: "mostly transparent but for occasional crackles that pass
// through the ellipsoid it generates". So the base state is very nearly
// invisible - a faint fresnel rim so the volume reads as present at all -
// and the interest is in discrete arcs that TRAVEL across the surface rather
// than a uniform shimmer. A constantly-glowing bubble would read as a solid
// object and would fight every silhouette inside it.
//
// blend_add + depth_draw_never so the hull, its greebles and its modules all
// remain fully visible through it; the shield brightens what is behind it
// instead of hiding it. cull_back rather than disabled so we see one surface
// at a time and the far side does not double the brightness.

uniform vec4 shield_color : source_color = vec4(0.35, 0.72, 1.0, 1.0);
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.2;
uniform float base_opacity : hint_range(0.0, 0.5) = 0.055;
uniform float crackle_speed : hint_range(0.0, 4.0) = 0.9;
uniform float crackle_sharpness : hint_range(1.0, 64.0) = 46.0;
uniform float crackle_gain : hint_range(0.0, 4.0) = 0.85;
uniform float impact_flash : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;
varying vec3 v_normal_v;
varying vec3 v_view;

// Cheap 3D value noise. No texture, matching this project's "procedural, not
// hand-authored art" convention for everything shader-side.
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_local = VERTEX;
	v_normal_v = NORMAL;
	v_view = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), fresnel_power);

	// Two arc bands travelling in different directions. Taking a thin slice
	// of the noise (via pow on a ridge) is what makes them read as discrete
	// CRACKLES rather than as a general shimmer - the surface is dark almost
	// everywhere and briefly very bright along a moving filament.
	float t = TIME * crackle_speed;
	float n1 = vnoise(v_local * 3.1 + vec3(0.0, t, t * 0.6));
	float n2 = vnoise(v_local * 5.7 + vec3(-t * 0.8, t * 0.3, 0.0));
	float ridge1 = pow(1.0 - abs(n1 - 0.5) * 2.0, crackle_sharpness);
	float ridge2 = pow(1.0 - abs(n2 - 0.5) * 2.0, crackle_sharpness * 0.7);
	// Gated by a slow travelling envelope so arcs come in BURSTS with quiet
	// stretches between them. Without this the two ridges are always
	// somewhere on the surface and the shield reads as a permanent glowing
	// web rather than as something that occasionally crackles.
	float gate = smoothstep(0.35, 0.75, vnoise(v_local * 0.9 + vec3(t * 0.5, 0.0, -t * 0.35)));
	float crackle = clamp(ridge1 + ridge2 * 0.6, 0.0, 1.0) * crackle_gain * gate;

	// Occasional whole-surface pulses, so the shield does something even when
	// no arc happens to be crossing the visible face.
	float pulse = smoothstep(0.86, 1.0, vnoise(vec3(t * 0.35)));

	float a = base_opacity + fres * 0.30 + crackle + pulse * 0.10 + impact_flash;
	ALBEDO = shield_color.rgb * (0.25 + crackle * 1.4 + impact_flash * 2.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
