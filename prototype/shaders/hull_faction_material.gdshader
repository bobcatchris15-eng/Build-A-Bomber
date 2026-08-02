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
// NOTE (2026-07-29): the `anisotropy` uniform and its ANISOTROPY /
// ANISOTROPY_FLOW writes were REMOVED here. VISUAL_ART_DIRECTION.md 1.3
// built faction identity on a brushed-anodized-aluminum surface language
// whose whole point was a view-dependent anisotropic streak - that is a
// physically-lit effect, and it cannot coexist with the toon light() pass
// below, which replaces Godot's PBR response outright. Chris's call was
// explicit: drop brushed aluminum in favour of the comic-book look. Section
// 1.3 of that doc is now superseded and should be revised.
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
// Ink line WIDTH, as the upper bound of the smoothstep applied to the edge
// signal (the lower bound stays fixed). Higher = the signal saturates
// sooner = a fatter, more graphic line. Separated from edge_ink_strength
// (which is opacity) because "bold comic outline" and "subtle panel crease"
// are different asks and were previously conflated into one knob.
uniform float ink_width : hint_range(0.05, 0.9) = 0.32;
// Ink is deliberately NOT pure black - a slightly warm-neutral very dark
// tone reads as printed ink rather than as a hole in the render, and keeps
// the line from flattening into the shadow bands below.
uniform vec3 ink_color : source_color = vec3(0.04, 0.035, 0.05);
// Converts geometric curvature (1/metres - see fragment()) into the 0-1 edge
// signal. Low enough that a flat panel with a normal-mapped rivet bump
// doesn't register, high enough that a real hull crease does.
uniform float ink_curvature_gain : hint_range(0.005, 1.0) = 0.06;
// The fresnel/silhouette half of the edge signal is separately scalable -
// it's inherently distance-invariant (pure view-angle), so at RTS zoom it's
// the term actually still drawing an outline once curvature has thinned out.
uniform float ink_rim_strength : hint_range(0.0, 1.0) = 0.55;

// --- Procedural livery stripe (2026-07-29) ---
// Replaces the accent stripe that used to be BAKED into each faction's
// albedo texture. That was the root cause of the "sides look stratified,
// top looks fine" problem: the baked texture carried large-scale
// COMPOSITION (one wide stripe at a fixed place in the image), and
// composition cannot survive triplanar projection. The top face samples the
// hull's two large dimensions and sees the whole image, but the side faces
// sample a dimension that's only a fraction as tall, so they only ever
// showed a thin horizontal SLICE of that stripe, tiled - reading as
// stratified banding rather than as paint.
//
// Drawing the stripe here instead fixes it properly: it's positioned by the
// hull's own normalized local height, so it wraps all four sides at one
// consistent height like real painted trim, at a real-world width that
// doesn't depend on the texture's aspect or the hull's proportions. The
// baked textures become pure tileable SURFACE (grain, rivets, seams, wear)
// with no composition, which is what triplanar actually wants.
uniform vec4 stripe_color : source_color = vec4(1.0, 0.75, 0.1, 1.0);
// DEFAULT OFF until the tileable faction swatches land. The stripe is the
// second half of a two-part fix - it only makes sense once the baked albedo
// has had its own composition (the wide accent band) REMOVED, otherwise a
// hull carries both the baked stripe and this one. Two things still to do
// before flipping this on:
//   1. local_bounds_y must actually be plumbed from the mesh AABB (see
//      hull_material_builder.apply_bounds_from_mesh, written but not yet
//      called anywhere) - on the default unit-height bounds the stripe
//      smears into a broad band instead of a trim line.
//   2. side_mask needs a harder gate: these hulls have sloped upper faces
//      where tri_w.y is partial, so the stripe currently bleeds onto them
//      rather than staying on the vertical sides.
uniform float stripe_enabled : hint_range(0.0, 1.0) = 0.0;
// Height of the stripe's centre as a 0-1 fraction of the hull's local
// vertical extent. 0.5 = midline; a little above centre usually reads best
// on a vehicle.
uniform float stripe_center : hint_range(0.0, 1.0) = 0.62;
uniform float stripe_width : hint_range(0.0, 0.5) = 0.11;
// Soft edge on the stripe, in the same normalized units. Small but nonzero
// so the band doesn't alias into a shimmering line at RTS zoom-out.
uniform float stripe_softness : hint_range(0.0, 0.2) = 0.015;
// Thin darker piping either side of the main band - reads as masked-off
// paint edges and stops the stripe from looking like a flat decal.
uniform float stripe_edge_darken : hint_range(0.0, 1.0) = 0.45;
// The hull's local-space vertical bounds (min, max) BEFORE mesh_scale, i.e.
// in the same space as model_pos. Set from the mesh AABB by
// hull_material_builder.gd; the default covers a unit-height mesh so an
// unplumbed material still renders a sane stripe rather than nothing.
uniform vec2 local_bounds_y = vec2(-0.5, 0.5);

// --- Toon / comic-book lighting (Chris, 2026-07-29) ---
// Tone target: units are the cartoon objects, terrain stays photoreal - the
// contrast between the two IS the effect, so this shader (hulls/modules
// only) goes toon while terrain keeps its StandardMaterial3D PBR. This
// deliberately extends VISUAL_ART_DIRECTION.md 1.2's "goofy lives at detail
// scale" rule: silhouette and color-blocking stay serious, but the RENDER
// treatment is now allowed to be graphic.
//
// NOTE: defining light() below replaces Godot's PBR response entirely for
// this material. METALLIC and ANISOTROPY no longer drive the lit result
// (they're left set for reflection-probe/SSR consistency); the brushed
// anisotropic streak the art doc calls for is therefore much weaker than
// under PBR. That's an accepted, deliberate trade - toon banding and a
// physically-correct anisotropic highlight are mutually exclusive looks.
// toon_bands: how many discrete light steps. 2 = hard comic, 4 = soft cel.
uniform float toon_bands : hint_range(1.0, 6.0) = 3.0;
// Width of the blend at each band boundary, in band-fraction units. 0.0 =
// razor-hard steps (aliases badly at distance), ~0.08 keeps the step
// crisp while staying stable when a unit is small on screen.
uniform float toon_softness : hint_range(0.0, 0.5) = 0.06;
// Shadowed bands get tinted rather than just darkened - flat multiplication
// toward black is what makes naive cel-shading look muddy. A cool tint
// against the warm key light is the standard comic-print solution.
uniform vec3 toon_shadow_tint : source_color = vec3(0.42, 0.46, 0.62);
// Floor on the darkest band, so unlit faces still read their faction color
// instead of going to silhouette. Terrain has no such floor, which further
// separates the two.
uniform float toon_shadow_floor : hint_range(0.0, 0.8) = 0.28;
// Hard specular blob (the classic comic highlight). Driven by ROUGHNESS so
// a glossy faction still reads glossier than a matte one.
uniform float toon_specular_strength : hint_range(0.0, 2.0) = 0.5;
// Saturation multiplier on the baked faction albedo. The pre-baked textures
// were authored for a PBR response; under banded lighting they read washed
// out, so the "saturated comic color" half of the brief is a push here
// rather than a re-bake of all 10 faction texture sets.
uniform float color_saturation : hint_range(0.0, 2.5) = 1.35;
// Lifts the darkest input tones so banding has room to work - pure PBR
// albedo tends to sit low, which crushes the bottom band.
uniform float color_lift : hint_range(0.0, 0.5) = 0.06;

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

	// Comic-color grade, applied BEFORE the ink line so the line itself
	// isn't saturated along with the paint. Luma weights are Rec.709.
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, color_saturation);
	color = color * (1.0 - color_lift) + color_lift;
	color = clamp(color, vec3(0.0), vec3(1.0));

	// Cel-shaded ink border: a bold, graphic edge/corner line reinforcing
	// the same "ink panel-line" look already baked into tex_albedo -
	// computed live from screen-space derivatives so it survives the Design
	// Lab's hull_scale stretch and needs no per-object authoring. Two
	// signals, combined with max() so either alone is enough to draw the
	// line: a geometric edge/corner detector (catches hard creases/corners
	// regardless of view angle) and a world-space Fresnel rim (catches
	// SILHOUETTE edges the geometric signal alone can miss at a grazing
	// angle).
	// Geometric curvature in 1/metres, NOT raw per-pixel normal derivative.
	// This matters and was a real bug (found 2026-07-29 in the first toon
	// capture): fwidth(world_normal) alone measures normal change PER PIXEL,
	// which has no scale invariance - as a unit shrinks on screen, more
	// geometry falls under each pixel, fwidth grows, and the detector
	// saturates to 1.0 across the WHOLE surface rather than just at edges.
	// At RTS camera height every unit was therefore being flood-filled solid
	// ink, which crushed the faction colors to near-black and made both
	// toon_bands and ink_width completely inert (the sweeps showed no
	// difference at any value - that's what gave it away).
	// Dividing by fwidth(world_pos) converts "normal change per pixel" into
	// "normal change per world unit", i.e. actual curvature: a hard box edge
	// stays enormous, a flat panel stays near zero, and neither depends on
	// how far away the camera is.
	vec3 d_normal = fwidth(world_normal);
	vec3 d_pos = fwidth(world_pos);
	float curvature = length(d_normal) / max(length(d_pos), 0.0001);
	float edge_curvature = clamp(curvature * ink_curvature_gain, 0.0, 1.0);
	vec3 view_dir_world = normalize(CAMERA_POSITION_WORLD - world_pos);
	// Exponent raised 1.5 -> 3.0 so the rim stays tight to the actual
	// silhouette. At 1.5 it bled a wide dark band well onto surfaces facing
	// the camera, which contributed to the same everything-goes-black
	// problem the curvature term caused.
	float fresnel_rim = pow(1.0 - clamp(dot(view_dir_world, geo_normal), 0.0, 1.0), 3.0) * ink_rim_strength;
	float edge_signal = max(edge_curvature, fresnel_rim);
	// ink_width is the smoothstep's upper bound (was a hardcoded 0.32) so
	// line weight is tunable per material without touching strength/opacity.
	// max() guards against an inverted range if ink_width is dialled below
	// the fixed lower bound.
	float edge_ink = smoothstep(0.05, max(ink_width, 0.06), edge_signal) * edge_ink_strength;
	color = mix(color, ink_color, edge_ink);

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
	// Texture-driven normal bump (rivets/panel grooves the mesh itself
	// doesn't model at this fine a scale), blended with the real geometric
	// normal and converted to view space.
	vec3 tex_world_normal = triplanar_normal(normal_tex, tex_pos, geo_normal, tri_w);
	vec3 final_world_normal = normalize(mix(geo_normal, tex_world_normal, normal_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz);

	ALPHA = alpha_base;
	if (shield_mode > 0.5) {
		// Was base_color.rgb * 0.6, which combined with the 0.7 alpha in
		// ARMOR_PBR to render an energy-shielded hull as a blown-out white
		// ghost - you could not see the vehicle you had built at all.
		//
		// That hack existed because the shield had no physical presence: the
		// hull ITSELF had to carry the whole "this is shielded" read. It now
		// projects a real crackling ellipsoid (armor_greebles.gd +
		// energy_shield.gdshader) with four emitters at its upper corners, so
		// the hull underneath only needs to look faintly energised - the
		// field is the bubble, not the paint.
		EMISSION = base_color.rgb * 0.12;
	} else if (emissive_strength > 0.0) {
		EMISSION = emissive_color.rgb * emissive_strength;
	}
}

// Quantize a 0-1 lighting term into `toon_bands` discrete steps, with a
// controllable blend width at each boundary. A naive floor() gives razor
// steps that alias violently once a unit is only a few pixels tall at RTS
// zoom-out (rts_camera.gd goes to 240m), which is exactly the range this
// game spends most of its time in - hence the smoothstep at each boundary
// rather than a hard floor.
float toon_quantize(float t) {
	float bands = max(toon_bands, 1.0);
	float scaled = clamp(t, 0.0, 1.0) * bands;
	float idx = floor(scaled);
	float f = scaled - idx;
	float w = max(toon_softness, 0.001);
	return (idx + smoothstep(0.5 - w, 0.5 + w, f)) / bands;
}

// Custom toon lighting. Replaces PBR entirely for hull/module surfaces -
// terrain and everything else in the scene keeps StandardMaterial3D PBR, and
// that contrast between cartoon units and a photoreal stage is the whole
// point of the treatment (Chris: "slight cartoonish / comic book look
// against the more serious landscapes").
void light() {
	vec3 N = normalize(NORMAL);
	vec3 L = normalize(LIGHT);

	// Half-lambert (remapped to 0-1) rather than raw clamped N·L: it keeps
	// the terminator off the exact 90-degree line, so a band boundary
	// doesn't sit permanently along a unit's midline under a fixed-angle
	// key light - which, with an RTS camera that never changes sun angle,
	// would otherwise be a static stripe baked across every unit.
	float ndotl = dot(N, L) * 0.5 + 0.5;
	float banded = toon_quantize(ndotl);

	// Lift the darkest band off zero and tint it, instead of multiplying
	// toward black - flat darkening is what makes cheap cel-shading read
	// muddy, and it would also destroy faction color legibility on the
	// unlit side of every unit.
	float lit = mix(toon_shadow_floor, 1.0, banded);
	vec3 shadow_tinted = mix(toon_shadow_tint, vec3(1.0), banded);

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * lit * shadow_tinted;

	// Hard specular blob. ROUGHNESS still drives the exponent so a glossy
	// faction (Ledger Combine, Technocrats) keeps a tighter, smaller
	// highlight than a matte one (Dune Runners, Salvage Union) - that's the
	// surviving half of the per-faction finish differentiation the brushed
	// anisotropy used to carry.
	vec3 H = normalize(L + normalize(VIEW));
	float spec_power = mix(64.0, 4.0, clamp(ROUGHNESS, 0.0, 1.0));
	float spec = pow(max(dot(N, H), 0.0), spec_power);
	// Quantized to a single hard-edged highlight rather than a smooth
	// falloff - the comic "shine mark".
	float spec_blob = smoothstep(0.25, 0.25 + max(toon_softness, 0.02) * 2.0, spec);
	// Matte surfaces get a dimmer blob as well as a broader one, so a
	// weathered faction doesn't end up with the same hot shine mark as a
	// showroom-pristine one.
	float gloss_gain = mix(0.3, 1.0, 1.0 - clamp(ROUGHNESS, 0.0, 1.0));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * spec_blob * toon_specular_strength * gloss_gain;
}
