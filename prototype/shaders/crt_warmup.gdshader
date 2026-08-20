shader_type canvas_item;
render_mode blend_mix;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float scanline_pitch = 3.0;
uniform vec3 warm_color = vec3(1.0, 0.69, 0.0);
uniform float bloom_intensity = 0.3;
uniform vec3 glass_color = vec3(0.031, 0.043, 0.035);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float scan = sin(UV.y * SCREEN_PIXEL_SIZE.y * scanline_pitch * 100.0) * 0.05;
	float vignette = 1.0 - length(UV - 0.5) * 0.5;
	float bloom = smoothstep(0.0, 1.0, progress) * bloom_intensity * (1.0 - UV.y);
	vec3 base = mix(glass_color, tex.rgb, progress);
	COLOR = vec4(base + warm_color * bloom + scan, tex.a * progress * vignette);
}