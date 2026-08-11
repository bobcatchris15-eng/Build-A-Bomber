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
// Damage-flash feedback (unit.gd's _flash_hull()) - briefly pushed to
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
// --- THREE-ZONE HULL LIVERY (2026-08-10, replaces the 10 premade factions) ---
// The player authors their own scheme now (scripts/livery.gd), and the hull
// half of it is three zones: everything below a belt line, everything above
// it, and a stripe. Each zone carries its own COLOUR and its own
// METALLIC/ROUGHNESS, because a colour alone cannot tell matte primer from
// anodised metal and that difference is most of what makes a livery look
// authored rather than tinted.
//
// This supersedes the 2026-07-29 stripe block that used to live here. That
// one was written but never wired into fragment() - it was waiting on
// tileable swatches and on local_bounds_y actually being plumbed. Both
// landed since (hull_material_builder.apply_local_bounds() is called from
// the hull build path), so the stripe is now real, and it grew two siblings.
//
// WHY THE ZONE SPLIT IS IN THE SHADER and not three materials: a hull is one
// mesh with per-surface armor/structural overrides already claiming both
// surface slots, and the zone boundary is a horizontal plane through the
// middle of a shape that the Design Lab lets the player stretch continuously.
// Only something evaluated per-fragment against the hull's own local bounds
// can hold a belt line straight through that.
// EVERY DEFAULT HERE IS A NO-OP, and that is deliberate. This shader is
// shared by paths that do not (yet) drive a livery at all - the Design Lab's
// unpainted scale-model finish, building_mesh.gd's team-tinted structures,
// any material built before hull_material_builder.gd sets these. Colours
// default to white because they MULTIPLY, metallic defaults to 1.0 because it
// SCALES the material-wide `metallic`, and livery_mix defaults to 0 so the
// roughness path below stays on the old `roughness` uniform outright. An
// unwired material therefore renders byte-identically to before this block
// existed, and a wired one is a pure override.
uniform vec4 zone_lower_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 zone_upper_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 stripe_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float zone_lower_metallic : hint_range(0.0, 1.0) = 1.0;
uniform float zone_lower_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float zone_upper_metallic : hint_range(0.0, 1.0) = 1.0;
uniform float zone_upper_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float zone_stripe_metallic : hint_range(0.0, 1.0) = 1.0;
uniform float zone_stripe_roughness : hint_range(0.0, 1.0) = 0.85;
// 0 = ignore the zone roughness entirely and use the material-wide
// `roughness` (which is what ARMOR_PBR sets per armor material); 1 = the
// player's chosen finishes drive it. hull_material_builder.gd raises this
// only on the paths that actually paint a livery.
uniform float livery_mix : hint_range(0.0, 1.0) = 0.0;
// Height of the belt line splitting lower from upper, as a 0-1 fraction of
// the hull's local vertical extent. Slightly below centre so the "upper"
// zone gets the larger share - it is the face the top-down RTS camera
// actually sees, so it is the one the player is really choosing.
uniform float zone_split : hint_range(0.0, 1.0) = 0.45;
// Softness of the belt line itself. Nonzero so it doesn't alias into a
// crawling line at RTS zoom-out, small so it still reads as a paint edge.
uniform float zone_split_softness : hint_range(0.0, 0.2) = 0.012;
uniform float stripe_enabled : hint_range(0.0, 1.0) = 1.0;
// STRIPE AXIS. 0.0 = a longitudinal racing stripe down the hull's centreline
// (banded on local X, running front-to-back over the top). 1.0 = a horizontal
// belt band at stripe_center (the 2026-07-29 behaviour).
//
// Longitudinal is the default because the other two zones are ALREADY a
// horizontal split: a height-banded stripe would just be a thicker version of
// the boundary between them, whereas a centreline stripe is a genuinely third
// direction and is what "a stripe down the middle" means on a vehicle.
uniform float stripe_axis : hint_range(0.0, 1.0) = 0.0;
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
// Same, for the X extent - the longitudinal stripe needs the hull's WIDTH to
// place a centreline band of consistent real-world width regardless of how
// wide the player stretched the chassis.
uniform vec2 local_bounds_x = vec2(-0.5, 0.5);

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
// toward black is what makes naive cel-shading look muddy. A neutral warm
// grey against the warm key light agrees with the world (warm dirt, warm
// metal) - the previous cool blue tint (0.42, 0.46, 0.62) was the
// "looks reflective" reading the gloss bug report caught. Cool shadow
// tints are the comic-print solution for printed paper; they read as
// reflection on a screen lit by a warm key.
uniform vec3 toon_shadow_tint : source_color = vec3(0.55, 0.50, 0.42);
// Floor on the darkest band, so unlit faces still read their faction color
// instead of going to silhouette. Terrain has no such floor, which further
// separates the two.
uniform float toon_shadow_floor : hint_range(0.0, 0.8) = 0.28;
// Hard specular blob (the classic comic highlight). Driven by ROUGHNESS so
// a glossy faction still reads glossier than a matte one. 0.5 -> 0.25
// (2026-08-10): at 0.5 the comic highlight on a top-facing hull face
// read as wet plastic, which the gloss bug report called out. 0.25
// keeps the highlight as a "this is a top-facing panel" cue without
// claiming "this is chrome". A glossy finish with high metallic still
// reads glossier than a matte one because the underlying PBR specular
// is unchanged; the toon blob is a comic-print addition on top.
uniform float toon_specular_strength : hint_range(0.0, 2.0) = 0.25;
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

	// THE LIVERY ZONES. tex_albedo is now pure tileable SURFACE (grain,
	// rivets, seams, wear) with no colour identity of its own - the identity
	// comes from the player's three hull zones, multiplied over that grain so
	// the paint sits ON the panel detail instead of replacing it.
	//
	// Normalized height within the hull's own local bounds, so a belt line
	// lands at the same proportion of the hull whatever the Design Lab
	// stretched it to.
	float zone_h = clamp((model_pos.y - local_bounds_y.x)
		/ max(local_bounds_y.y - local_bounds_y.x, 0.0001), 0.0, 1.0);
	float upper_mask = smoothstep(zone_split - zone_split_softness,
		zone_split + zone_split_softness, zone_h);

	// Stripe band. Longitudinal (default) measures distance from the hull's
	// own centreline in X; the horizontal variant bands on height instead.
	// mix() rather than a branch so both paths cost the same and neither can
	// diverge under a partially-derivative-dependent compiler.
	float zone_x = clamp((model_pos.x - local_bounds_x.x)
		/ max(local_bounds_x.y - local_bounds_x.x, 0.0001), 0.0, 1.0);
	float stripe_coord = mix(abs(zone_x - 0.5) * 2.0, abs(zone_h - stripe_center), stripe_axis);
	float stripe_half = max(stripe_width, 0.0001);
	float stripe_mask = (1.0 - smoothstep(stripe_half - stripe_softness,
		stripe_half + stripe_softness, stripe_coord)) * stripe_enabled;
	// Piping: a thin darker line just OUTSIDE the band, which is what stops a
	// painted stripe reading as a flat decal laid on top of the hull.
	float piping = (smoothstep(stripe_half - stripe_softness, stripe_half + stripe_softness, stripe_coord)
		- smoothstep(stripe_half + stripe_softness * 3.0, stripe_half + stripe_softness * 6.0, stripe_coord))
		* stripe_edge_darken * stripe_enabled;

	vec3 zone_albedo = mix(zone_lower_color.rgb, zone_upper_color.rgb, upper_mask);
	float zone_metallic = mix(zone_lower_metallic, zone_upper_metallic, upper_mask);
	float zone_roughness = mix(zone_lower_roughness, zone_upper_roughness, upper_mask);
	zone_albedo = mix(zone_albedo, stripe_color.rgb, stripe_mask);
	zone_metallic = mix(zone_metallic, zone_stripe_metallic, stripe_mask);
	zone_roughness = mix(zone_roughness, zone_stripe_roughness, stripe_mask);
	zone_albedo *= (1.0 - piping);

	// base_color/accent_color are kept live as neutral (white) multiplicative
	// tints on top - see the header comment for why (building.gd's team-color
	// override, damage overlay), which must still be able to tint a hull
	// whatever livery it wears.
	vec3 color = tex_albedo * zone_albedo * base_color.rgb * accent_color.rgb;

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

	// Metallic/roughness come from the ZONE the fragment is in, not from the
	// material-wide uniforms - that is what makes a satin-enamel upper over a
	// gunmetal lower read as two different finishes rather than two tints of
	// one. The `metallic`/`roughness` uniforms survive as a multiplier and an
	// offset respectively, which is how the armor-material character
	// (hull_material_builder.gd's ARMOR_PBR) still modulates the player's
	// choice instead of being overwritten by it.
	METALLIC = clamp(zone_metallic * metallic * (1.0 - edge_ink * 0.85), 0.0, 1.0);
	// Ink border reads matte, same as the baked texture's own ink seams - a
	// graphic ink line with a shiny specular highlight running through it
	// would look wrong, like a groove rather than a painted line.
	//
	// SATIN FLOOR. The 0.35 lower clamp is the shader-side half of
	// livery.gd's SATIN_ROUGHNESS_FLOOR, and it is not redundant with it:
	// roughness_bias and the tex_roughness term below can both push the final
	// value DOWN from whatever the finish authored, and without a floor here
	// a satin finish plus a negative bias plus a dark spot in the roughness
	// map lands back in the near-mirror range that caused the "whole game
	// looks glossy" regression. Clamping at the point of use is the only
	// place that cannot be routed around.
	float base_roughness = mix(roughness, zone_roughness, livery_mix);
	// The satin floor applies only where a livery is actually being painted.
	// energy_shielding deliberately sits at roughness 0.1 - it is an active
	// energy field, one of the few things in the game that IS supposed to read
	// as glossy (see hull_material_builder.gd's ARMOR_PBR note) - and a floor
	// that ignored livery_mix would clamp that away on every shielded hull.
	float rough_floor = mix(0.0, 0.35, livery_mix);
	ROUGHNESS = clamp(base_roughness + roughness_bias + (tex_roughness - 0.5) * 0.85 + edge_ink * 0.45, rough_floor, 1.0);
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
