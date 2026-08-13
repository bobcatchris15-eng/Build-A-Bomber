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

varying vec3 v_view_dir_tangent;
varying vec3 v_world_normal;

void vertex() {
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;

	// Tangent-space basis for POM raymarching
	vec3 n = normalize(NORMAL);
	vec3 t = normalize(TANGENT);
	vec3 b = normalize(BINORMAL);
	mat3 tbn = mat3(t, b, n);

	// Orthographic or perspective view direction in model space -> tangent space
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 view_dir_model = (inverse(MODEL_MATRIX) * vec4(view_dir_world, 0.0)).xyz;
	v_view_dir_tangent = tbn * view_dir_model;
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

	// World normal dust mixing
	float up_facing = smoothstep(0.55, 0.95, dot(normalize(v_world_normal), vec3(0.0, 1.0, 0.0)));
	vec3 final_albedo = mix(alb.rgb * albedo_tint.rgb, dust_color.rgb, up_facing * dust_intensity * (1.0 - orm.r * 0.4));
	float final_roughness = clamp(orm.g * roughness_scale + up_facing * dust_intensity * 0.20, 0.03, 1.0);

	ALBEDO = final_albedo;
	AO = orm.r;
	ROUGHNESS = final_roughness;
	METALLIC = clamp(orm.b * metallic_scale, 0.0, 1.0);

	if (emission_energy > 0.0) {
		EMISSION = emission_color.rgb * emission_energy;
	}
}
