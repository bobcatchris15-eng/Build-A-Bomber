// Gravitic lens: the visible distortion under an anti-grav plate.
//
// Chris asked for "an effect that it looks like it's bending light under
// them". Real bending, not a painted swirl - this samples what is actually
// behind the quad and displaces the lookup radially, so the terrain, the
// vehicle's own shadow and anything driving past all warp as they pass under
// the plate. A texture could not do that; it has to read the screen.
//
// unshaded + no depth write: it is a lens, not a surface. Lit or depth-writing
// it would make the disc itself visible as an object, which is the one thing a
// distortion field must not be.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 0.2) = 0.055;
uniform float ripple_speed = 1.6;
uniform vec4 tint : source_color = vec4(0.30, 0.62, 0.95, 1.0);

void fragment() {
	// Radial coordinate from the disc's centre.
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Falls to zero at the rim so the distortion has no visible edge - a hard
	// cutoff is what makes this kind of effect read as a decal.
	float falloff = clamp(1.0 - r, 0.0, 1.0);
	falloff *= falloff;

	// Two things displace the sample: a steady inward pull that grows toward
	// the centre (the "well"), and a travelling ripple so it is alive even
	// when the vehicle is still.
	float ripple = sin(r * 18.0 - TIME * ripple_speed) * 0.35;
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0);
	vec2 offset = dir * (strength * falloff * (1.0 + ripple));

	vec3 bent = texture(SCREEN_TEXTURE, SCREEN_UV - offset).rgb;
	// A faint cool cast, so the field has a colour without hiding what is
	// behind it.
	vec3 col = mix(bent, bent * tint.rgb * 1.35, 0.16 * falloff);
	ALBEDO = col;
	ALPHA = falloff;
}
