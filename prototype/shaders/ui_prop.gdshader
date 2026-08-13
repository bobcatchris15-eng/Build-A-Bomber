shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Tactile UI Prop Shader (Phase 2 & 3 of Tactile Interface Programme)
// Consumes baked albedo, ORM (Occlusion, Roughness, Metallic) and height maps.

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D texture_orm : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D texture_height : hint_default_black, filter_linear_mipmap, repeat_disable;

uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
uniform float roughness_scale : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_scale : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec4 alb = texture(texture_albedo, UV);
	vec4 orm = texture(texture_orm, UV);

	ALBEDO = alb.rgb * albedo_tint.rgb;
	AO = orm.r;
	ROUGHNESS = clamp(orm.g * roughness_scale, 0.03, 1.0);
	METALLIC = clamp(orm.b * metallic_scale, 0.0, 1.0);

	if (emission_energy > 0.0) {
		EMISSION = emission_color.rgb * emission_energy;
	}
}
