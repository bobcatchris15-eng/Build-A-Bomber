shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Tactile UI Prop Shader with Parallax Occlusion Mapping (POM) & Self-Shadowing (Phase 3)
// Real relief on chamfers/dishes, screen-space derivative normals, and world-space dust.

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D texture_orm : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D texture_height : hint_default_black, filter_linear_mipmap, repeat_disable;

uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
uniform float roughness_scale : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_scale : hint_range(0.0, 2.0) = 1.0;

// POM parameters (Part 3.3 & Phase 3)
uniform float height_scale : hint_range(0.0, 0.2) = 0.035;
uniform int min_layers : hint_range(4, 32) = 8;
uniform int max_layers : hint_range(8, 64) = 24;

// World-normal dust mixing (subtle realistic equipment dust)
uniform vec4 dust_color : source_color = vec4(0.52, 0.49, 0.45, 1.0);
uniform float dust_intensity : hint_range(0.0, 1.0) = 0.10;

// POM SELF-SHADOWING. Direction FROM the surface TO the key light, in world
// space. Supplied by UIPropStage, which owns the key DirectionalLight3D and is
// therefore the only thing that knows where it points - a hardcoded default
// here would silently disagree with the rig the moment the rig is re-aimed.
// The default matches the stage's current key rotation so a material built
// without the parameter still shadows in a plausible direction rather than
// from straight ahead (which produces no shadow at all).
uniform vec3 key_light_direction = vec3(0.42, 0.67, 0.61);
uniform float self_shadow_strength : hint_range(0.0, 1.0) = 0.65;
uniform int shadow_layers : hint_range(0, 32) = 12;

varying vec3 v_view_dir_tangent;
varying vec3 v_light_dir_tangent;
varying vec3 v_world_normal;

void vertex() {
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;

	// Tangent-space basis for POM raymarching
	vec3 n = normalize(NORMAL);
	vec3 t = normalize(TANGENT);
	vec3 b = normalize(BINORMAL);
	mat3 tbn = mat3(t, b, n);

	// Orthographic or perspective view direction in model space -> tangent space
	mat4 inv_model = inverse(MODEL_MATRIX);
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 view_dir_model = (inv_model * vec4(view_dir_world, 0.0)).xyz;
	v_view_dir_tangent = tbn * view_dir_model;

	// Same transform for the key light, so the shadow march below runs in the
	// same space as the view march and needs no per-fragment basis rebuild.
	vec3 light_dir_model = (inv_model * vec4(normalize(key_light_direction), 0.0)).xyz;
	v_light_dir_tangent = tbn * light_dir_model;
}

vec2 parallax_mapping(vec2 uv, vec3 view_dir) {
	float vz = max(abs(view_dir.z), 0.08);
	float num_layers = mix(float(max_layers), float(min_layers), vz);
	float layer_depth = 1.0 / num_layers;
	float current_layer_depth = 0.0;
	vec2 p = view_dir.xy * height_scale / vz;
	vec2 delta_uv = p / num_layers;

	vec2 current_uv = uv;
	float current_depth_value = 1.0 - texture(texture_height, current_uv).r;

	for (int i = 0; i < 64; i++) {
		if (float(i) >= num_layers) break;
		if (current_layer_depth >= current_depth_value) break;
		current_uv -= delta_uv;
		current_depth_value = 1.0 - texture(texture_height, current_uv).r;
		current_layer_depth += layer_depth;
	}

	// Parallax Occlusion interpolation between adjacent steps to eliminate stepping artifacts
	vec2 prev_uv = current_uv + delta_uv;
	float after_depth = current_depth_value - current_layer_depth;
	float before_depth = (1.0 - texture(texture_height, prev_uv).r) - current_layer_depth + layer_depth;
	float weight = after_depth / (after_depth - before_depth + 1e-6);
	return mix(current_uv, prev_uv, clamp(weight, 0.0, 1.0));
}

// POM SELF-SHADOWING.
//
// Marches from the intersection point back toward the key light. Any sample
// that rises above the ray's height occludes it, so the fragment is in the
// shadow of its own relief. Without this a recessed screw head reads as a dark
// circle painted on a flat face; with it, the recess casts, which is what
// actually sells the depth under a moving light.
//
// Returns 1.0 for fully lit, down to (1.0 - self_shadow_strength) for fully
// occluded. A light at or below the surface plane (light.z <= 0) returns 1.0
// rather than marching: there is no above-surface path for the ray to take,
// and marching anyway produces a hard terminator artifact along the chamfer.
float parallax_self_shadow(vec2 uv, vec3 light_dir) {
	if (shadow_layers <= 0 || self_shadow_strength <= 0.001) {
		return 1.0;
	}
	float lz = light_dir.z;
	if (lz <= 0.05) {
		return 1.0;
	}

	float surface_height = texture(texture_height, uv).r;
	float layer_depth = (1.0 - surface_height) / float(shadow_layers);
	vec2 delta_uv = (light_dir.xy * height_scale / lz) / float(shadow_layers);

	float occlusion = 0.0;
	vec2 current_uv = uv;
	float current_height = surface_height;

	for (int i = 0; i < 32; i++) {
		if (i >= shadow_layers) break;
		current_uv += delta_uv;
		current_height += layer_depth;
		float sampled = texture(texture_height, current_uv).r;
		if (sampled > current_height) {
			// Weight nearer blockers more heavily - a ridge right beside the
			// crevice casts a darker shadow than one several steps away.
			float weight = (sampled - current_height) * (1.0 - float(i) / float(shadow_layers));
			occlusion = max(occlusion, weight);
		}
	}

	return 1.0 - clamp(occlusion * 2.0, 0.0, 1.0) * self_shadow_strength;
}

void fragment() {
	vec2 uv = UV;
	if (height_scale > 0.001) {
		uv = parallax_mapping(UV, normalize(v_view_dir_tangent));
	}

	vec4 alb = texture(texture_albedo, uv);
	vec4 orm = texture(texture_orm, uv);

	// Screen-space derivative normal perturbation from height map
	float h_center = texture(texture_height, uv).r;
	float h_dx = dFdx(h_center);
	float h_dy = dFdy(h_center);
	vec3 bump_normal = normalize(vec3(-h_dx * 8.0, -h_dy * 8.0, 1.0));
	NORMAL = normalize(TANGENT * bump_normal.x + BINORMAL * bump_normal.y + NORMAL * bump_normal.z);

	float shadow = parallax_self_shadow(uv, normalize(v_light_dir_tangent));

	// WORLD NORMAL DUST MIXING, against the PERTURBED normal rather than the
	// vertex one. NORMAL is in view space at this point, so it goes back
	// through INV_VIEW_MATRIX to reach world space. Using v_world_normal here
	// (the flat geometric normal) would settle dust as an even wash across a
	// whole face; using the perturbed normal makes it catch on the individual
	// ridges the height map just carved, which is the entire reason to compute
	// the mask after POM instead of before it.
	vec3 perturbed_world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up_facing = smoothstep(0.55, 0.95, dot(perturbed_world_normal, vec3(0.0, 1.0, 0.0)));
	vec3 final_albedo = mix(alb.rgb * albedo_tint.rgb, dust_color.rgb, up_facing * dust_intensity * (1.0 - orm.r * 0.4));
	float final_roughness = clamp(orm.g * roughness_scale + up_facing * dust_intensity * 0.20, 0.03, 1.0);

	ALBEDO = final_albedo;
	AO = orm.r * shadow;
	ROUGHNESS = final_roughness;
	METALLIC = clamp(orm.b * metallic_scale, 0.0, 1.0);

	if (emission_energy > 0.0) {
		EMISSION = emission_color.rgb * emission_energy;
	}
}
