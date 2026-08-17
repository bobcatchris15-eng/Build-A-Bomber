shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// CULL_DISABLED IS LOAD-BEARING, not a default anyone picked.
//
// The facet skin's triangles do not reliably come out front-facing: they are
// clipped and fan-triangulated from the hull's own faces, and the hull roster is
// wound INWARD (see HullFacets._signed_volume). part_materials.gd:443 has
// carried CULL_DISABLED for exactly this reason for every part it builds.
//
// Building the armor material by hand without it made every painted facet
// VANISH - not dark, not subtle, absent - which read for two rounds as "the
// pattern is too faint" and sent me tuning relief amplitudes on geometry that
// was never being rasterised at all.

// ARMOR SURFACE: what makes one armor material recognisable as itself.
//
// COLOUR CANNOT CARRY THIS. The player's livery repaints the whole vehicle, so
// a material identified by its tint is identified by nothing the moment anyone
// picks a scheme. So the signature lives in the NORMAL and in roughness: a
// pattern you read by how it catches light, which survives any albedo.
//
// This replaced a geometry approach that cut and raised real tiles. That did
// produce the right shape - triangle counts scaled exactly as specified - but
// rendered invisible, because only the tile TOPS were emitted and a set of
// parallel quads at slightly different heights has no vertical face for light
// to hit. Doing it in the normal costs no triangles and cannot have that bug.
//
// UV is in METRES of facet surface (hull_facets._shell_uv), so a 0.5m block is
// 0.5m on every panel of every hull regardless of facet size.

uniform vec4 albedo : source_color = vec4(0.5, 0.52, 0.5, 1.0);
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.45;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.58;
// 0 steel, 1 reactive, 2 ceramic, 3 carbon, 4 titanium
uniform int pattern_id : hint_range(0, 4) = 0;
uniform float cell : hint_range(0.02, 2.0) = 0.5;
uniform float relief : hint_range(0.0, 3.0) = 1.0;
// Width of a seam as a fraction of a cell.
uniform float seam : hint_range(0.005, 0.3) = 0.06;

// Signed distance to the nearest edge of the cell containing `p`, in cell
// units: 0 at a seam, 0.5 at a tile centre.
float edge_distance(vec2 p) {
	vec2 f = fract(p) - 0.5;
	vec2 d = 0.5 - abs(f);
	return min(d.x, d.y);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

// Height field. The normal is its gradient, taken numerically so each pattern
// only has to describe its own shape.
float height_at(vec2 uv) {
	if (pattern_id == 0) {
		// Rolled steel: almost flat, with a faint directional mill grain so it
		// is not perfectly featureless.
		return sin(uv.y * 22.0) * 0.02;
	} else if (pattern_id == 1) {
		// Reactive: staggered blocks with deep seams and a domed face, the
		// classic ERA brick.
		vec2 g = uv / cell;
		g.x += 0.5 * floor(mod(g.y, 2.0));
		float e = edge_distance(g);
		float face = smoothstep(0.0, seam * 2.5, e);
		float dome = 1.0 - pow(1.0 - clamp(e * 2.0, 0.0, 1.0), 2.0);
		return face * (0.75 + 0.25 * dome);
	} else if (pattern_id == 2) {
		// Ablative ceramic: small square tiles, flat faces, tight grout.
		float e = edge_distance(uv / cell);
		return smoothstep(0.0, seam * 1.6, e);
	} else if (pattern_id == 3) {
		// Carbon fibre: a 2x2 twill. Two interleaved sine bundles, one per
		// axis, alternating which is on top per cell.
		vec2 g = uv / cell;
		float check = mod(floor(g.x) + floor(g.y), 2.0);
		float warp = sin(fract(g.x) * 3.14159);
		float weft = sin(fract(g.y) * 3.14159);
		return mix(weft * 0.9, warp * 0.9, check);
	}
	// Titanium: large panels, sharp seams, subtly uneven panel heights so the
	// seams catch light along their whole length.
	vec2 g = uv / cell;
	float e = edge_distance(g);
	float panel = smoothstep(0.0, seam, e);
	float bias = hash21(floor(g)) * 0.12;
	return panel * (0.88 + bias);
}

void fragment() {
	ALBEDO = albedo.rgb;
	METALLIC = metallic_amount;

	// Numerical gradient of the height field. The epsilon is in metres and is
	// kept well below the smallest pattern (carbon's weave) so fine detail is
	// not averaged away.
	float eps = 0.004;
	float h = height_at(UV);
	float hx = height_at(UV + vec2(eps, 0.0));
	float hy = height_at(UV + vec2(0.0, eps));
	vec3 n = normalize(vec3((h - hx) * relief / eps, (h - hy) * relief / eps, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Seams read as slightly rougher than faces - dirt and wear collect there,
	// and the roughness break makes the pattern legible even in flat light
	// where the normal alone would not show.
	ROUGHNESS = clamp(roughness_amount + (1.0 - h) * 0.18, 0.0, 1.0);
}
