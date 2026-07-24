shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

uniform float hp_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float segments : hint_range(1.0, 20.0) = 10.0;
uniform vec4 color_full : source_color = vec4(0.2, 0.9, 0.3, 1.0);
uniform vec4 color_mid : source_color = vec4(0.9, 0.8, 0.2, 1.0);
uniform vec4 color_low : source_color = vec4(0.9, 0.2, 0.2, 1.0);
uniform vec4 color_bg : source_color = vec4(0.05, 0.07, 0.1, 0.85);
uniform vec4 color_border : source_color = vec4(0.2, 0.25, 0.3, 0.9);
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV;

	// Border
	float border_x = step(uv.x, 0.03) + step(0.97, uv.x);
	float border_y = step(uv.y, 0.1) + step(0.9, uv.y);
	float is_border = clamp(border_x + border_y, 0.0, 1.0);

	// Segment ticks
	float seg_x = fract(uv.x * segments);
	float is_tick = step(seg_x, 0.08) * step(0.05, uv.x) * step(uv.x, 0.95);

	// HP Fill level
	float is_filled = step(uv.x, hp_ratio);

	// Color gradient based on HP ratio
	vec4 hp_color;
	if (hp_ratio > 0.5) {
		hp_color = mix(color_mid, color_full, (hp_ratio - 0.5) * 2.0);
	} else {
		hp_color = mix(color_low, color_mid, hp_ratio * 2.0);
	}

	// Apply damage flash (white blend)
	hp_color = mix(hp_color, vec4(1.0, 1.0, 1.0, 1.0), damage_flash * 0.7);

	vec4 final_color = color_bg;
	if (is_filled > 0.5 && is_tick < 0.5) {
		final_color = hp_color;
	}
	if (is_border > 0.5) {
		final_color = color_border;
	}

	ALBEDO = final_color.rgb;
	ALPHA = final_color.a;
}
