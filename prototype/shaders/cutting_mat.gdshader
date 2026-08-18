// Self-healing cutting mat for the Design Lab / Hull Builder floor.
//
// What the mat is doing in the scene: it sits well BELOW the floating
// hull (LabEnvironment places it at y = -20 by default) and the
// camera's DOF eats it heavily. The mat only needs to be a recognisable
// cutting-mat pattern at the periphery of the player's vision - it's
// not a focal point. The point of the shader is "this is obviously a
// cutting mat, even blurred": dark green base, white measuring grid,
// white corner-to-corner diagonals.
//
// Pattern breakdown:
//   1. 1u white sub-grid (the "centimetre" lines, 0.5u inside a major)
//   2. 5u white major grid (the "five-centimetre" lines, slightly thicker)
//   3. White centre crosshair through the origin
//   4. Two long white diagonals from corner to corner (the Olfa-style 45s)
//   5. Red border band just inside the mat edge
// All line widths are anti-aliased via fwidth() so the pattern stays
// legible across the whole orbit range, including when DOF kicks in.
//
// Pattern is driven by the fragment's WORLD-space XZ (populated in
// vertex() as a varying), not UV. That means the mat still reads as a
// mat if the box is later rotated, scaled, or replaced with a different
// mesh - the grid stays aligned to the world axes.

shader_type spatial;

render_mode cull_back, depth_draw_opaque;

varying vec3 v_world_pos;

uniform vec3 base_color : source_color = vec3(0.04, 0.16, 0.05);
uniform vec3 line_color : source_color = vec3(0.90, 0.90, 0.90);
uniform vec3 major_line_color : source_color = vec3(0.97, 0.97, 0.97);
uniform vec3 diagonal_color : source_color = vec3(0.88, 0.88, 0.88);
uniform vec3 center_color : source_color = vec3(0.95, 0.95, 0.95);
uniform vec3 edge_color : source_color = vec3(0.78, 0.18, 0.18);
uniform float minor_width = 0.025;
uniform float major_width = 0.045;
uniform float center_width = 0.07;
uniform float diagonal_width = 0.05;
uniform float edge_inset = 0.6;
uniform float mat_half_size = 12.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz;

	// Minor grid: 1u spacing, faint
	vec2 grid_minor = abs(fract(p) - 0.5);
	float minor_d = min(grid_minor.x, grid_minor.y);
	float minor_aa = fwidth(p.x) + fwidth(p.y);
	float minor_mask = 1.0 - smoothstep(0.0, minor_width + minor_aa, minor_d);

	// Major grid: every 5u, slightly brighter
	vec2 p_major = p / 5.0;
	vec2 grid_major = abs(fract(p_major) - 0.5);
	float major_d = min(grid_major.x, grid_major.y);
	float major_aa = fwidth(p_major.x) + fwidth(p_major.y);
	float major_mask = 1.0 - smoothstep(0.0, major_width + major_aa, major_d);

	// Centre crosshair through (0, 0)
	vec2 center_d = abs(p);
	float center_min = min(center_d.x, center_d.y);
	float center_mask = 1.0 - smoothstep(0.0, center_width + fwidth(p.x), center_min);

	// Corner-to-corner diagonals. The two 45s are the Olfa trademark.
	// |x - y| / sqrt(2) is the perpendicular distance to y = x;
	// |x + y| / sqrt(2) is the perpendicular distance to y = -x.
	float diag_nwse = abs(p.x - p.y) * 0.70710678;
	float diag_nesw = abs(p.x + p.y) * 0.70710678;
	float diag_d = min(diag_nwse, diag_nesw);
	float diag_aa = fwidth(p.x) + fwidth(p.y);
	float diag_mask = 1.0 - smoothstep(0.0, diagonal_width + diag_aa, diag_d);

	// Red border band just inside the mat edge. edge_d measures how far
	// we are from the nearest edge along the dominant axis; when it
	// gets close to edge_inset, the band lights up.
	float edge_d = mat_half_size - max(abs(p.x), abs(p.y));
	float edge_mask = 1.0 - smoothstep(edge_inset - 0.12, edge_inset, edge_d);

	vec3 col = base_color;
	col = mix(col, line_color, minor_mask * 0.55);
	col = mix(col, major_line_color, major_mask);
	col = mix(col, center_color, center_mask * 0.55);
	col = mix(col, diagonal_color, diag_mask * 0.7);
	col = mix(col, edge_color, edge_mask * 0.75);

	ALBEDO = col;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
