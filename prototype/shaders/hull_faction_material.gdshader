shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Faction visual identity system - v3 (2026-07-26): faction differentiation
// moved from live per-fragment shader computation to PRE-BAKED per-faction
// textures (tools/generate_faction_textures.gd), per Chris's explicit
// direction. v2 (see git history) computed base/accent color-blocking, the
// wear/grime masks, and the camo mottle pattern procedurally every fragment,
// every frame, for every faction - 4 noise3() calls (32 hash evaluations
// each) plus 9 triplanar texture fetches, on every hull surface in the
// match. None of that is view/light-dependent, so none of it needs to be
// live: it's baked into albedo_tex once per faction now, and this shader
// just samples it. Real per-frame remaining cost: one triplanar sample set,
// the edge-ink cel-shading line (genuinely needs live fwidth/fresnel), and
// whatever ANISOTROPY the armor material still wants.
//
// base_color/accent_color remain LIVE, simple multiplicative tints (default
// white = no change) rather than being removed outright - building.gd uses
// them to re-tint an already-faction-textured building toward a team color
// for enemy-owned structures, independent of faction identity. Damage-state
// visual feedback (progressive wear as a unit takes battle damage) is a
// natural future use of this same live-uniform mechanism, deliberately not
// built yet - the baked texture is the STATIC faction-personality wear/grime
// level; a live damage overlay would be an ADDITIONAL effect layered on top,
// not a replacement for this bake.

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.6;
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float anisotropy : hint_range(0.0, 1.0) = 0.3;
// Per-faction surface-finish bias (pristine/glossy factions negative,
// grungy/matte factions positive) - armor_material (ARMOR_PBR) sets the
// baseline "what is this plating made of" roughness shared by every
// faction; this is the faction's OWN finish character layered on top, e.g.
// Technocrats reading glossier than Salvage Union even in the same armor.
// Was previously only expressed via a weak ±0.25 nudge from tex_roughness
// (see fragment() below) - too subtle to read as "different factions have
// different finishes," mostly lost under the shared normal-map bump look.
uniform float roughness_bias : hint_range(-0.3, 0.3) = 0.0;
uniform vec4 emissive_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emissive_strength : hint_range(0.0, 2.0) = 0.0;

// Real per-faction surface texture (albedo/normal/roughness) - now the
// SOLE source of faction color/wear/grime/panel identity, not just a grain
// detail layer multiplied under a separately-computed base/accent tint (see
// header comment). Triplanar in world space for the same reason as before:
// hull meshes aren't UV-unwrapped, and the Design Lab's continuous hull_scale
// stretch needs constant texel density, not a stretched UV-mapped image.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float texture_scale : hint_range(0.02, 1.0) = 0.12;
// The Design Lab's hull_scale slider and the armor-thickness "bulk" factor
// both stretch a hull via MeshInstance3D.scale, non-uniformly (different
// factors per axis) - model_pos (below) is VERTEX, the mesh's PRE-scale
// local position, so without this the texture's sampled density never
// reflected that stretch: a hull stretched more on one axis than another
// showed visibly different tiling/aspect between faces dominated by
// different axes (Chris: "they stretch/deform differently on the sides
// vs the top/bottom"). Set from the node's own `scale` property
// (hull_material_builder.gd) - multiplying it into model_pos before
// texture_scale restores consistent world-space texel density on every
// face regardless of which axis a given face's plane is dominated by,
// while still moving WITH the mesh (unlike world_pos, which caused a
// "texture slides as the unit moves" bug - see model_pos's own comment).
uniform vec3 mesh_scale = vec3(1.0, 1.0, 1.0);
// Lowered from 0.7 - at full strength the shared rivet/panel-line bump
// pattern (similar density across every faction) visually dominated over
// the baked paint color, especially under strong key lighting (lots of
// small specular highlights reading as "grey bumpy metal" before "faction
// paint"). Texture detail is still very much present at 0.45, just no
// longer competing with ALBEDO for what the eye reads first.
uniform float normal_strength : hint_range(0.0, 2.0) = 0.45;

// 0 = solid armor plating, 1 = translucent glowing energy shield (the glow
// tints to whichever faction is wearing it, via emissive_color).
uniform float shield_mode : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_base : hint_range(0.0, 1.0) = 1.0;
// Damage-flash feedback (battle_unit.gd's _flash_hull()) - briefly pushed to
// 1.0 and back on a hit.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
// Cel-shaded ink border strength - a bold, graphic edge/corner line,
// computed live from screen-space derivatives (see fragment() below), not a
// per-faction identity knob. Shared default, every material uses this.
uniform float edge_ink_strength : hint_range(0.0, 1.0) = 0.95;

varying vec3 world_pos;
varying vec3 world_normal;
// Object-local vertex position for triplanar texture sampling - moves WITH
// the mesh so the baked texture stays painted onto the hull surface instead
// of sliding as the unit moves.
varying vec3 model_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	model_pos = VERTEX;
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
// TANGENT/UV0 involved - see the uniform block comment above for why).
vec3 triplanar_normal(sampler2D tex, vec3 pos, vec3 n, vec3 w) {
	vec3 tx = texture(tex, pos.zy).rgb * 2.0 - 1.0;
	vec3 ty = texture(tex, pos.xz).rgb * 2.0 - 1.0;
	vec3 tz = texture(tex, pos.xy).rgb * 2.0 - 1.0;
	tx.z *= sign(n.x);
	ty.z *= sign(n.y);
	tz.z *= sign(n.z);
	vec3 world_nx = vec3(tx.z, tx.y, tx.x);
	vec3 world_ny = vec3(ty.x, ty.z, ty.y);
	vec3 world_nz = vec3(tz.x, tz.y, tz.x);
	return normalize(world_nx * w.x + world_ny * w.y + world_nz * w.z);
}

void fragment() {
	vec3 geo_normal = normalize(world_normal);
	vec3 tri_w = triplanar_weights(geo_normal);
	// model-local (not world - fixes texture sliding), scaled by the node's
	// own non-uniform mesh_scale so texel density stays consistent across
	// faces regardless of hull-stretch axis - see mesh_scale's own comment.
	vec3 tex_pos = model_pos * mesh_scale * texture_scale;

	vec3 tex_albedo = triplanar_sample(albedo_tex, tex_pos, tri_w).rgb;
	float tex_roughness = triplanar_sample(roughness_tex, tex_pos, tri_w).r;

	// tex_albedo carries full faction identity now (color, wear, grime,
	// panel lines, trim) baked in by generate_faction_textures.gd.
	// base_color/accent_color are neutral (white) multiplicative tints by
	// default - see header comment for why they're kept live rather than
	// removed (building.gd's team-color override, future damage overlay).
	vec3 color = tex_albedo * base_color.rgb * accent_color.rgb;

	// Cel-shaded ink border: a bold, graphic edge/corner line reinforcing
	// the same "ink panel-line" look already baked into tex_albedo -
	// computed live from screen-space derivatives so it survives the Design
	// Lab's hull_scale stretch and needs no per-object authoring. Two
	// signals, combined with max() so either alone is enough to draw the
	// line: a geometric edge/corner detector (catches hard creases/corners
	// regardless of view angle) and a world-space Fresnel rim (catches
	// SILHOUETTE edges the geometric signal alone can miss at a grazing
	// angle).
	float edge_curvature = clamp(length(fwidth(world_normal)) * 20.0, 0.0, 1.0);
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fresnel_rim = pow(1.0 - clamp(dot(view_dir_world, geo_normal), 0.0, 1.0), 1.5);
	float edge_signal = max(edge_curvature, fresnel_rim);
	float edge_ink = smoothstep(0.05, 0.32, edge_signal) * edge_ink_strength;
	color = mix(color, vec3(0.0), edge_ink);

	color = mix(color, vec3(1.0, 0.05, 0.05), flash_amount);
	ALBEDO = color;

	METALLIC = clamp(metallic * (1.0 - edge_ink * 0.85), 0.0, 1.0);
	// Ink border reads matte, same as the baked texture's own ink seams - a
	// graphic ink line with a shiny specular highlight running through it
	// would look wrong, like a groove rather than a painted line.
	// roughness_bias (per-faction finish character) and a stronger
	// tex_roughness weight (0.5 -> 0.85 - the baked texture's own roughness
	// map already differs per faction via corrosion/grain/overlay density,
	// it just wasn't weighted enough to read) both push surface FINISH to
	// vary by faction, the same way ALBEDO already does, not just by armor
	// material.
	ROUGHNESS = clamp(roughness + roughness_bias + (tex_roughness - 0.5) * 0.85 + edge_ink * 0.45, 0.0, 1.0);
	ANISOTROPY = anisotropy * (1.0 - edge_ink * 0.85);
	// Brush direction: lengthwise along the hull's own long axis, in
	// tangent space - Godot's default TANGENT for box/cylinder primitives
	// already runs along local X/U, which lines up with "nose to tail" for
	// every hull in this catalog.
	ANISOTROPY_FLOW = vec2(1.0, 0.0);

	// Texture-driven normal bump (rivets/panel grooves the mesh itself
	// doesn't model at this fine a scale), blended with the real geometric
	// normal and converted to view space.
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
