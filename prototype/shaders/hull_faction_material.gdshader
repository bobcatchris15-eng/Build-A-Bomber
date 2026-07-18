shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// Faction visual identity system - v2, built against VISUAL_ART_DIRECTION.md's
// parameter model (section 2). ONE shared hull material across every
// faction and every armor material: same mesh geometry always, differentiation
// entirely these shader parameters. No baked masks (no UV-unwrapped art, no
// curvature/AO bake pass per hull - the fragile Blender import pipeline this
// week made a real per-mesh bake pipeline too risky) - wear/grime/panel-line
// masks are all PROCEDURAL approximations instead (see each section below),
// deliberately trading a little physical precision for zero new asset
// dependencies. Logged as a judgment call in DECISIONS_NEEDED.md.
//
// World-space sampling (not raw local VERTEX) for every procedural mask:
// the Design Lab lets players continuously stretch hulls via hull_scale, and
// sampling noise from local/object-space VERTEX would keep the SAME number
// of noise cycles regardless of scale - meaning a stretched hull just shows
// a smeared/enlarged pattern instead of more repetitions (the exact failure
// mode VISUAL_ART_DIRECTION.md section 2 calls out). World-space position
// scales WITH the stretch, so noise cycles per world-unit stay constant and
// a bigger hull genuinely shows more grain/panel repetitions, not a blur.

uniform vec4 base_color : source_color = vec4(0.6, 0.6, 0.65, 1.0);
uniform vec4 accent_color : source_color = vec4(0.5, 0.5, 0.55, 1.0);
uniform vec4 detail_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.6;
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float anisotropy : hint_range(0.0, 1.0) = 0.3;
uniform float brush_scale : hint_range(0.5, 8.0) = 2.0;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.3;
uniform vec4 wear_color : source_color = vec4(0.3, 0.28, 0.25, 1.0);
uniform float grime_amount : hint_range(0.0, 1.0) = 0.2;
uniform float edge_highlight_strength : hint_range(0.0, 1.0) = 0.5;
uniform vec4 emissive_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emissive_strength : hint_range(0.0, 2.0) = 0.0;
// Camo-style large-patch base/accent blending (Bayou Irregulars' mottled
// two-tone green) instead of the default thin panel-seam trim - 0 for every
// other faction (accent only shows at seams), nonzero blooms accent into
// broad soft patches across the whole surface.
uniform float mottle_amount : hint_range(0.0, 1.0) = 0.0;
// decal_tint is part of the parameter model (VISUAL_ART_DIRECTION.md) for a
// shared stencil/hazard/mascot decal atlas - deliberately NOT wired to any
// visible effect yet, since a real decal atlas needs actual authored texture
// content (exactly the kind of hand-painted per-faction asset this whole
// system exists to avoid). Kept as a harmless placeholder uniform so
// faction data is future-proofed for when real decal art exists.
uniform vec4 decal_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Real per-faction surface texture (albedo/normal/roughness), generated
// procedurally per faction (tools/generate_faction_textures.gd) and sampled
// TRIPLANAR in world space - not the mesh's own UV0. Two reasons: (1) these
// hull meshes were never UV-unwrapped (the whole faction system up to now
// deliberately avoided needing UVs, given the fragile Blender pipeline), and
// (2) the Design Lab lets a player continuously stretch a hull via
// hull_scale - a conventional UV-mapped texture would visibly stretch right
// along with it, while triplanar (driven by world-space position, same as
// every procedural mask below) keeps a constant texel density regardless of
// scale, exactly like the existing procedural seam/grunge/grime masks
// already do. This is genuinely ADDITIVE to those masks, not a replacement:
// tex_albedo becomes the new base surface that base_color/accent_color tint,
// and wear/grime/edge-highlight/emissive/flash all still layer on top of it
// exactly as before.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float texture_scale : hint_range(0.02, 1.0) = 0.12;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.7;

// 0 = solid armor plating, 1 = translucent glowing energy shield (the glow
// tints to whichever faction is wearing it, via emissive_color).
uniform float shield_mode : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_base : hint_range(0.0, 1.0) = 1.0;
// Damage-flash feedback (battle_unit.gd's _flash_hull()) - briefly pushed to
// 1.0 and back on a hit.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
// Cel-shaded ink border strength (2026-07-17) - a bold, graphic edge/
// corner line, computed live from screen-space derivatives (see fragment()
// below), not a per-faction identity knob the way base_color/wear_amount
// etc. are - deliberately NOT exposed through hull_material_builder.gd,
// every material just uses this shared default. hint_range kept anyway so
// it's tunable from the inspector during art passes without a recompile.
uniform float edge_ink_strength : hint_range(0.0, 1.0) = 0.95;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash3(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

// Standard world-space triplanar blend weights (sharpened so the transition
// between planes is a fairly narrow band around each edge, not a mushy
// 33/33/33 blend everywhere).
vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 0.0001);
}

vec4 triplanar_sample(sampler2D tex, vec3 pos, vec3 w) {
	vec4 xaxis = texture(tex, pos.zy);
	vec4 yaxis = texture(tex, pos.xz);
	vec4 zaxis = texture(tex, pos.xy);
	return xaxis * w.x + yaxis * w.y + zaxis * w.z;
}

// Triplanar NORMAL mapping, done entirely in world space (no mesh
// TANGENT/UV0 involved at all - see the uniform block comment above for
// why). Each axis' sampled tangent-space normal is swizzled into the world
// axes that plane actually represents, sign-flipped to match which side of
// that axis the surface faces, then blended by the same weights as the
// albedo/roughness triplanar sample. Returns a WORLD-space normal, meant to
// be mixed with the existing geometric world_normal and converted to view
// space for Godot's `NORMAL` output (not `NORMAL_MAP`, which expects
// tangent space and a valid mesh TBN we don't have).
vec3 triplanar_normal(sampler2D tex, vec3 pos, vec3 n, vec3 w) {
	vec3 tx = texture(tex, pos.zy).rgb * 2.0 - 1.0;
	vec3 ty = texture(tex, pos.xz).rgb * 2.0 - 1.0;
	vec3 tz = texture(tex, pos.xy).rgb * 2.0 - 1.0;
	tx.z *= sign(n.x);
	ty.z *= sign(n.y);
	tz.z *= sign(n.z);
	vec3 world_nx = vec3(tx.z, tx.y, tx.x);
	vec3 world_ny = vec3(ty.x, ty.z, ty.y);
	vec3 world_nz = vec3(tz.x, tz.y, tz.z);
	return normalize(world_nx * w.x + world_ny * w.y + world_nz * w.z);
}

void fragment() {
	// Curvature/edge approximation: screen-space derivative of the world
	// normal is large at silhouette edges/corners and near-zero across flat
	// panel interiors - a real-time stand-in for a baked curvature map
	// (VISUAL_ART_DIRECTION.md's "Mask B"), needing no per-mesh bake pass.
	float edge_raw = length(fwidth(world_normal));
	float curvature = clamp(edge_raw * 4.0, 0.0, 1.0);
	// Blend a little organic noise into the pure-curvature signal so wear
	// doesn't look like a geometric edge-detect filter - real weathering is
	// patchy, not a clean outline.
	float grunge = noise3(world_pos * brush_scale * 3.0) * 0.5 + noise3(world_pos * brush_scale * 7.0 + vec3(41.0, 7.0, 91.0)) * 0.5;
	float wear_signal = clamp(curvature * 0.7 + grunge * 0.3, 0.0, 1.0);
	float wear_mask = smoothstep(1.0 - wear_amount - 0.2, 1.0 - wear_amount + 0.2, wear_signal);

	// Grime (VISUAL_ART_DIRECTION.md's "Mask A", cavity/AO-driven, opposite
	// spatial logic from wear - collects in recesses, not on exposed edges):
	// approximated as low curvature (flat/recessed, not a sharp edge) PLUS a
	// bias toward the lower part of the hull in local Y (splash-up grime
	// near ground contact) rather than a real cavity map.
	float grime_low_bias = clamp(1.0 - (VERTEX.y * 0.4 + 0.5), 0.0, 1.0);
	float grime_noise = noise3(world_pos * brush_scale * 2.0 + vec3(13.0, 5.0, 29.0));
	float grime_mask = clamp((1.0 - curvature) * grime_low_bias * grime_noise * 1.6, 0.0, 1.0) * grime_amount;

	// Panel-line/rivet grammar (shared "kit of parts" look across every
	// faction, VISUAL_ART_DIRECTION.md 1.3): a periodic world-space seam grid,
	// tinted by accent_color - this is also what carries accent_color's job
	// (trim/stripe tint) without needing a real baked trim mask. mottle_amount
	// overrides this with broad soft patches instead (Bayou Irregulars' camo).
	vec3 seam_coord = world_pos * (1.0 / max(brush_scale, 0.1));
	vec3 seam_frac = abs(fract(seam_coord) - 0.5);
	float seam_line = 1.0 - smoothstep(0.0, 0.06, min(min(seam_frac.x, seam_frac.y), seam_frac.z));
	float mottle_patch = smoothstep(0.35, 0.65, noise3(world_pos * brush_scale * 0.6));
	float accent_mask = mix(seam_line, mottle_patch, mottle_amount);

	// Real per-faction surface texture, triplanar in world space (see the
	// uniform block comment). tex_albedo averages ~0.5 gray by construction
	// (tools/generate_faction_textures.gd's base_gray values), so it's
	// doubled here to act as a neutral-centered light/dark modulation on
	// top of the tint below rather than darkening everything by half.
	vec3 geo_normal = normalize(world_normal);
	vec3 tri_w = triplanar_weights(geo_normal);
	vec3 tex_pos = world_pos * texture_scale;
	vec3 tex_albedo = triplanar_sample(albedo_tex, tex_pos, tri_w).rgb;
	float tex_roughness = triplanar_sample(roughness_tex, tex_pos, tri_w).r;

	vec3 color = mix(base_color.rgb, accent_color.rgb, accent_mask);
	color *= tex_albedo * 2.0;
	// Small structural bolt highlights at seam intersections, tinted by
	// detail_color - the "oversized bolt-heads at seams" goofy-but-safe
	// detail VISUAL_ART_DIRECTION.md 1.2 calls out, kept small (never
	// competing with base/accent for silhouette read).
	float bolt_dot = 1.0 - smoothstep(0.0, 0.04, length(seam_frac.xy));
	color = mix(color, detail_color.rgb, bolt_dot * 0.5);

	color = mix(color, wear_color.rgb, wear_mask);
	vec3 grime_color = vec3(0.08, 0.075, 0.07);
	color = mix(color, grime_color, grime_mask);

	// Cel-shaded ink border: a bold, graphic edge/corner line reinforcing
	// the same "ink panel-line" look already baked into tex_albedo
	// (generate_faction_textures.gd's own thick-seam technique - darken
	// hard toward near-black, don't just dip albedo a little), computed
	// live from screen-space derivatives instead of baked, so it survives
	// the Design Lab's hull_scale stretch and needs no per-object
	// authoring or per-mesh bake pass. Two signals, combined with max()
	// so either alone is enough to draw the line:
	//   - edge_raw (the same fwidth(world_normal) driving curvature above,
	//     but at a MUCH higher multiplier - a hard geometric edge is only
	//     1-2 screen pixels wide, and curvature's own *4.0 tuning for the
	//     wear mask left real box corners barely distinguishable from the
	//     baked seam grid in a direct pixel-level check, see
	//     DECISIONS_NEEDED.md) is a real geometric edge/corner detector -
	//     catches hard creases/corners regardless of view angle.
	//   - a world-space Fresnel rim catches SILHOUETTE edges the geometric
	//     signal alone can miss at a grazing angle (a gently rounded bevel
	//     edge viewed nearly edge-on has low curvature but a strong rim).
	// Deliberately a SHARP smoothstep band, unlike wear_mask's wide/soft
	// one - this needs to read as an intentional ink line, not another
	// weathering gradient. Blends toward an ABSOLUTE near-black (not a
	// fraction of the existing color) so it reads as real ink regardless
	// of how bright/saturated the underlying panel color is - a multiply-
	// based darken (the first version) was too easily lost against the
	// already-dark baked seam lines. Applied after wear/grime (the line
	// shows on top of whatever weathering state the surface is in) but
	// before the flash-red hit feedback, which still overrides everything.
	float edge_curvature = clamp(edge_raw * 12.0, 0.0, 1.0);
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fresnel_rim = pow(1.0 - clamp(dot(view_dir_world, geo_normal), 0.0, 1.0), 2.0);
	float edge_signal = max(edge_curvature, fresnel_rim * 0.85);
	float edge_ink = smoothstep(0.12, 0.4, edge_signal) * edge_ink_strength;
	color = mix(color, vec3(0.012), edge_ink);

	color = mix(color, vec3(1.0, 0.05, 0.05), flash_amount);
	ALBEDO = color;

	float exposed = clamp(wear_mask * edge_highlight_strength, 0.0, 1.0);
	METALLIC = clamp(mix(metallic, metallic * 0.3 + 0.5 * exposed, wear_mask) * (1.0 - edge_ink * 0.6), 0.0, 1.0);
	// Ink border reads matte, same as the baked texture's own ink seams
	// (generate_faction_textures.gd bumps roughness at its seam_mask too) -
	// a graphic ink line with a shiny specular highlight running through it
	// would look wrong, like a groove rather than a painted line.
	ROUGHNESS = clamp(mix(roughness, roughness + 0.5 - 0.3 * exposed, wear_mask) + grime_mask * 0.3 + (tex_roughness - 0.5) * 0.5 + edge_ink * 0.3, 0.0, 1.0);
	ANISOTROPY = anisotropy * (1.0 - wear_mask * 0.5) * (1.0 - edge_ink * 0.5);
	// Brush direction: lengthwise along the hull's own long axis, in
	// tangent space - Godot's default TANGENT for box/cylinder primitives
	// already runs along local X/U, which lines up with "nose to tail" for
	// every hull in this catalog.
	ANISOTROPY_FLOW = vec2(1.0, 0.0);

	// Texture-driven normal bump (rivets/panel grooves the mesh itself
	// doesn't model at this fine a scale), blended with the real geometric
	// normal and converted to view space - see triplanar_normal()'s comment
	// for why this writes NORMAL directly instead of NORMAL_MAP.
	vec3 tex_world_normal = triplanar_normal(normal_tex, tex_pos, geo_normal, tri_w);
	vec3 final_world_normal = normalize(mix(geo_normal, tex_world_normal, normal_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz);

	ALPHA = alpha_base;
	if (shield_mode > 0.5) {
		EMISSION = base_color.rgb * 0.6;
	} else if (emissive_strength > 0.0) {
		EMISSION = emissive_color.rgb * emissive_strength;
	}
}
