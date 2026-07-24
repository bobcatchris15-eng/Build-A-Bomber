shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform vec4 selection_color : source_color = vec4(0.2, 0.9, 0.4, 1.0);
uniform float ring_width : hint_range(0.01, 0.4) = 0.08;
uniform float dash_count : hint_range(0.0, 32.0) = 16.0;
uniform float rotation_speed = 1.5;
uniform float pulse_speed = 3.0;

void fragment() {
	vec2 center_uv = UV - vec2(0.5);
	float dist = length(center_uv);
	float angle = atan(center_uv.y, center_uv.x);

	// Ring bounds
	float inner_r = 0.42 - ring_width;
	float outer_r = 0.42;
	float in_ring = step(inner_r, dist) * step(dist, outer_r);

	// Rotating dashes
	float dash = sin(angle * dash_count + TIME * rotation_speed);
	float dash_mask = step(0.0, dash);

	// Pulse glow
	float pulse = 0.8 + 0.2 * sin(TIME * pulse_speed);

	float alpha = in_ring * dash_mask * pulse;
	ALBEDO = selection_color.rgb;
	ALPHA = alpha * selection_color.a;
}
