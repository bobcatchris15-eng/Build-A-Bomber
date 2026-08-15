shader_type canvas_item;
// The deploy gate's heavy diffuse-glass layer.
//
// WHAT THIS IS. A fullscreen overlay that sits between the camera
// and the world during the build phase, and a frosted-glass
// backdrop for the DEPLOY button once the world is ready. The
// player's eye reads it as looking through a heavily frosted,
// darkened industrial visor at the map - the world is heavily
// diffused, softened, and dimmed with authentic glass refraction.

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float alpha : hint_range(0.0, 1.0) = 0.70;
uniform vec4 tint : source_color = vec4(0.075, 0.074, 0.068, 1.0);
uniform float blur_amount : hint_range(0.0, 2.0) = 1.0;
uniform float blur_radius : hint_range(0.0, 40.0) = 16.0;
uniform float frost_amount : hint_range(0.0, 0.5) = 0.20;
uniform float refraction_amount : hint_range(0.0, 0.03) = 0.007;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.40;

// 16-tap Poisson-disk sampling offsets
const vec2 POISSON_16[16] = vec2[](
	vec2(-0.326212, -0.405805),
	vec2(-0.840144, -0.073580),
	vec2(-0.695914,  0.457137),
	vec2(-0.203345,  0.620716),
	vec2( 0.962340, -0.194983),
	vec2( 0.473434, -0.480026),
	vec2( 0.519456,  0.767022),
	vec2( 0.185461, -0.893124),
	vec2( 0.507431,  0.064425),
	vec2( 0.896420,  0.412458),
	vec2(-0.321940, -0.932615),
	vec2(-0.791559, -0.597705),
	vec2( 0.057799,  0.228185),
	vec2(-0.160167, -0.193231),
	vec2( 0.134591,  0.923485),
	vec2(-0.528489,  0.136742)
);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	vec2 tex_size = vec2(textureSize(SCREEN_TEXTURE, 0));
	vec2 pixel_size = 1.0 / max(tex_size, vec2(1.0));

	// Fine frosted refraction jitter
	float n1 = noise(screen_uv * 180.0);
	float n2 = noise(screen_uv * 180.0 + vec2(37.1, 92.7));
	vec2 refract_offset = (vec2(n1, n2) - 0.5) * 2.0 * refraction_amount * frost_amount;
	vec2 base_uv = screen_uv + refract_offset;

	// Multi-tap Poisson blurred sampling with LOD weighting
	vec3 blurred = vec3(0.0);
	float total_weight = 0.0;
	float effective_radius = blur_radius * blur_amount;

	for (int i = 0; i < 16; i++) {
		vec2 sample_offset = POISSON_16[i] * effective_radius * pixel_size;
		float sample_jitter = hash21(screen_uv * 400.0 + POISSON_16[i]);
		vec2 jittered_uv = base_uv + sample_offset * (0.8 + 0.4 * sample_jitter);
		
		float lod = clamp(effective_radius * 0.20, 0.0, 2.5);
		vec3 s = textureLod(SCREEN_TEXTURE, jittered_uv, lod).rgb;
		blurred += s;
		total_weight += 1.0;
	}
	blurred /= total_weight;

	vec3 unblurred = texture(SCREEN_TEXTURE, screen_uv).rgb;
	vec3 world = mix(unblurred, blurred, clamp(blur_amount, 0.0, 1.0));

	// Deep industrial modal tint
	vec3 dimmed = world * tint.rgb * 1.15;

	// Surface frost micro-noise & grain texture
	float grain = hash21(floor(screen_uv * tex_size * 0.5));
	float surface_frost = 1.0 - frost_amount * 0.4 * (grain - 0.5);
	dimmed *= surface_frost;

	// Vignette around screen edges
	vec2 v_uv = screen_uv * (1.0 - screen_uv.yx);
	float vig = v_uv.x * v_uv.y * 15.0;
	vig = clamp(pow(vig, vignette_amount * 0.5), 0.0, 1.0);
	dimmed *= vig;

	COLOR = vec4(dimmed, alpha);
}
