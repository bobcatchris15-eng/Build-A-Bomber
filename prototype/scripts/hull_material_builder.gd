extends RefCounted
class_name HullMaterialBuilder
# Shared hull material construction - replaces two previously near-identical
# copy-paste StandardMaterial3D blocks (blueprint_manager.gd's
# reconstruct_vehicle() and module_placer.gd's update_hull_appearance()),
# and is the actual implementation of the faction visual identity system
# (VISUAL_ART_DIRECTION.md): same ShaderMaterial/shader for every faction
# and every armor material, entirely parameterized - no per-faction or
# per-material mesh/texture assets needed.

const FactionCatalogScript = preload("res://scripts/faction_catalog.gd")
const HULL_SHADER = preload("res://shaders/hull_faction_material.gdshader")
const VisualTuningScript = preload("res://scripts/visual_tuning.gd")

# The 4 existing armor materials' PBR character, unchanged in substance from
# the old hardcoded StandardMaterial3D blocks (hardened_steel's shiny-metal
# roughness/metallic, reactive_armor's matte green, ablative_ceramic's dull
# pale ceramic, energy_shielding's translucent glow) - only the ALBEDO COLOR
# moved to being faction-driven instead of a fixed per-material color, since
# color is now what distinguishes ownership, not armor type.
#
# hardened_steel's roughness raised 0.2 -> 0.42 (2026-07-17, root-caused a
# "whole game looks glossy" report): under real-camera screenshots this
# combined with the hull shader's own ANISOTROPY term (hull_faction_
# material.gdshader) into a blown-out, near-mirror streak on every hull's
# top/near face - anisotropic GGX's peak brightness AND sharpness both
# scale up sharply as roughness drops, so a "shiny metal" value that looked
# reasonable in isolation became a wet-chrome hotspot once anisotropy was
# layered on top. 0.42 keeps hardened_steel the shiniest/most metallic of
# the 4 armor types (still well below reactive_armor's 0.7) while actually
# reading as "brushed anodized aluminum" (VISUAL_ART_DIRECTION.md 1.3's
# "soft/broad highlight, not a sharp wet-looking one") rather than polished
# chrome. The other 3 materials were NOT touched - reactive_armor/
# ablative_ceramic were already reasonably matte, and energy_shielding's
# low roughness is an intentional "active energy field" glow, one of the
# few things that's supposed to read as glossy.
#
# hardened_steel's metallic nudged 0.8 -> 0.88 (2026-07-17, widening the
# armor/structural contrast per Chris's follow-up that the split didn't
# read strongly enough) - metallic alone (not roughness, which is what
# actually drove the anisotropic hotspot bug above) gives a bit more
# specular "pop" without reopening that exact regression, since anisotropic
# GGX's peak sharpness is roughness-driven, not metallic-driven.
#
# 2026-07-18: metallic brought back DOWN, 0.88 -> 0.55, after a rigorous
# pixel-level check proved the 0.88 value was actively counterproductive:
# sampled dead-center of a flat armor-material face under plain ambient
# light (no specular highlight landing there), armor read DARKER than
# structural despite having a lighter raw base_color - a real PBR
# behavior, not a bug: diffuse reflectance scales with (1-metallic), so a
# near-pure-metal surface has almost NO diffuse contribution and looks
# black everywhere except where a highlight or bright reflection actually
# lands. That's fine for a hero shot with the light in the right place,
# but not for "reads as armor from any angle," which is the actual ask.
# 0.55 keeps a real diffuse contribution alive while staying well above
# structural's 0.04, so the color/value gap (see build_structural_
# material()'s own note) reads reliably instead of being fought by metallic
# suppression. base_color/accent_color also lightened in build_hull_
# material() below to compensate further - see that function's comment.
#
# 2026-07-18 cont'd: nudged back up 0.55 -> 0.65 once the color-value gap
# (the actually-reliable lever, see build_structural_material()'s note)
# was pushed hard enough to stand on its own - metallic 0.65 gives the
# "premium brushed metal" specular pop real weight WHEN a highlight lands,
# without threatening the diffuse floor the way 0.88 did, now that
# lightened() compensates by a larger amount too. Chris's explicit
# direction this round: "don't be conservative, push it until it's
# unmistakable" - so every knob in this file that has real headroom
# without reopening the anisotropic-hotspot regression (see the roughness
# comment above - that ONE value stays put) got pushed further, not just
# nudged.
const ARMOR_PBR = {
	"hardened_steel": {"metallic": 0.65, "roughness": 0.42, "shield_mode": 0.0, "alpha": 1.0},
	"reactive_armor": {"metallic": 0.1, "roughness": 0.7, "shield_mode": 0.0, "alpha": 1.0},
	"ablative_ceramic": {"metallic": 0.0, "roughness": 0.5, "shield_mode": 0.0, "alpha": 1.0},
	# alpha 0.7 -> 0.94. At 0.7 a shielded hull was see-through, and combined
	# with the old shield_mode emission it rendered as a white blob with a
	# vehicle vaguely inside it. The translucency was standing in for a shield
	# that did not exist yet; it does now (armor_greebles.gd's ellipsoid), so
	# the hull can go back to being a hull. Not fully opaque - a slight
	# translucency still reads as "this plating is partly field, not metal".
	"energy_shielding": {"metallic": 0.1, "roughness": 0.1, "shield_mode": 1.0, "alpha": 0.94},
}

const TEXTURE_DIR = "res://assets/textures/factions/"
# Cached per-faction (texture load is a real disk hit, and build_hull_material
# runs once per module/hull instance - every mounted weapon on a design calls
# this too, see reconstruct_vehicle()) - a battleship-sized design with a
# dozen modules shouldn't reload the same 3 PNGs a dozen times.
static var _texture_cache: Dictionary = {}

static func _get_faction_textures(faction: String) -> Dictionary:
	if _texture_cache.has(faction):
		return _texture_cache[faction]
	var base = TEXTURE_DIR + faction
	var textures = {
		"albedo": load(base + "_albedo.png"),
		"normal": load(base + "_normal.png"),
		"roughness": load(base + "_roughness.png"),
	}
	_texture_cache[faction] = textures
	return textures

# Converts a hull's real-world face size into a texture_scale that tiles
# roughly once per face - these hull meshes aren't UV-unwrapped (the
# triplanar approach exists specifically so the Design Lab's continuous
# hull_scale stretch doesn't distort a UV-mapped texture, see the shader's
# own header comment), so there's no real per-face UV space to map one
# tile onto directly. This is the practical alternative: texture_scale is
# the reciprocal of a representative face dimension, so a small hull's
# small faces and a large hull's large faces both land close to one tile,
# instead of one fixed density making small hulls over-tile and large
# hulls under-tile (or vice versa).
const _DEFAULT_TEXTURE_WORLD_SIZE = 3.0
static func _texture_scale_for_size(world_size: float) -> float:
	return clamp(1.0 / max(world_size, 0.1), 0.05, 1.0)

static func build_hull_material(armor_material: String, faction: String, texture_world_size: float = _DEFAULT_TEXTURE_WORLD_SIZE) -> ShaderMaterial:
	var armor = ARMOR_PBR.get(armor_material, ARMOR_PBR["hardened_steel"])
	var mat = ShaderMaterial.new()
	mat.shader = HULL_SHADER
	# Faction identity is carried ENTIRELY by the baked texture now
	# (tools/generate_faction_textures.gd or, for the 10 real factions,
	# tools/process_flow_faction_textures.gd) - no live per-fragment
	# computation reads FactionCatalog data at all here anymore. This was
	# a deliberate walk-back from an earlier version of this v3 rewrite
	# that kept anisotropy/roughness_bias/emissive live per-faction -
	# found via a real bug: Ledger Combine's emissive_strength=0.4 with a
	# saturated green emissive_color painted the ENTIRE hull surface in a
	# flat green glow, drowning out its actual blue/white/green-stripe
	# texture (Chris's live screenshot: "solid minecraft emerald... I
	# don't see the swatch on the hull"). Emissive/anisotropy/roughness
	# variation belongs in the texture bake (already possible - the
	# generator bakes directional shading) or a future explicit VFX pass,
	# not a blanket live uniform with no spatial mask.
	# The `anisotropy` write that used to sit here is gone (2026-07-29): the
	# shader no longer exposes it, since the toon light() pass replaced the
	# brushed-aluminum PBR surface language wholesale. See the shader's own
	# note where that uniform was removed.
	# See _texture_scale_for_size()'s comment - sized per-hull now rather
	# than a single fixed constant (which either over- or under-tiled
	# depending on hull size; tuning story in git history).
	mat.set_shader_parameter("texture_scale", _texture_scale_for_size(texture_world_size))
	mat.set_shader_parameter("metallic", armor.metallic)
	mat.set_shader_parameter("roughness", armor.roughness)
	mat.set_shader_parameter("shield_mode", armor.shield_mode)
	mat.set_shader_parameter("alpha_base", armor.alpha)
	var faction_id = faction if FactionCatalogScript.FACTIONS.has(faction) else FactionCatalogScript.DEFAULT_FACTION
	var textures = _get_faction_textures(faction_id)
	mat.set_shader_parameter("albedo_tex", textures.albedo)
	mat.set_shader_parameter("normal_tex", textures.normal)
	mat.set_shader_parameter("roughness_tex", textures.roughness)
	# Livery stripe - the faction's accent color, drawn procedurally by the
	# shader instead of being baked into the albedo. See the shader's
	# stripe_color block for why: a baked stripe is large-scale COMPOSITION,
	# and composition can't survive triplanar projection (it was the cause of
	# the "sides look stratified, top looks fine" bug). accent_color has sat
	# unused in faction_catalog.gd since the v3 bake took over faction
	# identity - this puts it back to work as the thing it's named for.
	var visual = FactionCatalogScript.get_visual(faction_id)
	mat.set_shader_parameter("stripe_color", visual.get("accent_color", Color(1.0, 0.75, 0.1)))
	# Inherit whatever the live tuning sliders are currently set to. Without
	# this, anything built AFTER a slider moved (production, respawns, every
	# Design Lab rebuild) would silently revert to the shader defaults - see
	# visual_tuning.gd's header for why the store exists at all.
	VisualTuningScript.apply(mat)
	return mat

# The stripe is positioned against the hull's own local vertical extent, so
# the material needs to know that extent. Kept as a separate call because the
# AABB usually isn't known at build_hull_material() time - callers typically
# build the material first and assign it to a MeshInstance3D after, at which
# point mesh.get_aabb() is available. Anything that never calls this falls
# back to the shader's unit-height default and still renders a sane stripe.
static func apply_local_bounds(mat: ShaderMaterial, bounds_y: Vector2) -> void:
	if mat == null:
		return
	# Guard a degenerate/zero-height AABB - flat plane meshes and some greeble
	# parts hit this, and a zero span would divide-by-zero in the shader.
	if absf(bounds_y.y - bounds_y.x) < 0.0001:
		bounds_y = Vector2(-0.5, 0.5)
	mat.set_shader_parameter("local_bounds_y", bounds_y)

# Structural/base-plating material - the majority, non-armor surface of a
# hull: matte/satin, reads as workmanlike structural plate rather than
# polished armor. Reuses the SAME per-faction texture as build_hull_
# material() (no new per-faction texture set) - only the PBR response
# differs (low metallic, high roughness, anisotropy near zero - the
# anodized-brushed-metal streak is specifically the HARD ARMOR plate's
# signature look, not a whole-hull default) plus a flat darkening multiply
# via base_color.
#
# The pre-v3 shader darkened base_color/accent_color by 0.8 (see git history
# for the tuning story - value/darkness was found to be the only angle-
# independent way to make the armor/structural split read reliably) BEFORE
# that color went through its own separate live per-fragment recomputation
# (wear/grime/rivets/seams, ending in a `tex_albedo * 2.0` renormalization).
# That 0.8 factor doesn't carry over 1:1 here: albedo_tex is now the FINAL,
# already fully-shaded/baked color (rivet highlights, seam ink, directional
# shading, all baked in) - multiplying that a second time by a 0.8-darkened
# grey compounds into near-black rather than "a bit duller than armor" (a
# real regression caught via the faction lineup capture - most hulls
# rendered nearly black except a few small armor-plate surfaces). 0.3 is a
# lighter starting point tuned against the NEW baked-texture pipeline;
# still a plain grey multiply (preserves the texture's hue exactly, only
# scales value), just proportioned for a texture that's already "finished"
# rather than a raw color about to go through more shading.
static func build_structural_material(faction: String, texture_world_size: float = _DEFAULT_TEXTURE_WORLD_SIZE) -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = HULL_SHADER
	mat.set_shader_parameter("base_color", Color(1.0, 1.0, 1.0, 1.0).darkened(0.3))
	# Fixed, faction-independent - see build_hull_material()'s comment for
	# why emissive is no longer faction-driven at all (the `anisotropy`
	# write formerly here was dropped with the uniform itself).
	mat.set_shader_parameter("texture_scale", _texture_scale_for_size(texture_world_size))
	mat.set_shader_parameter("metallic", 0.015)
	mat.set_shader_parameter("roughness", 0.97)
	# No livery stripe on structural plating. The stripe is faction TRIM - it
	# belongs on the hull's outer paneling, not on girders, frames and filler
	# blocks. Leaving it on would also band every small structural part at its
	# own local mid-height, producing a scatter of unrelated stripes across a
	# design rather than one continuous line around the hull.
	mat.set_shader_parameter("stripe_enabled", 0.0)
	VisualTuningScript.apply(mat)
	mat.set_shader_parameter("shield_mode", 0.0)
	mat.set_shader_parameter("alpha_base", 1.0)
	var faction_id = faction if FactionCatalogScript.FACTIONS.has(faction) else FactionCatalogScript.DEFAULT_FACTION
	var textures = _get_faction_textures(faction_id)
	mat.set_shader_parameter("albedo_tex", textures.albedo)
	mat.set_shader_parameter("normal_tex", textures.normal)
	mat.set_shader_parameter("roughness_tex", textures.roughness)
	return mat

# Single entry point for both hull-spawn call sites (blueprint_manager.gd's
# reconstruct_vehicle(), module_placer.gd's update_hull_appearance()) -
# centralizing the surface-index convention in ONE place so the two
# call sites can't drift apart on which slot means what.
#
# Convention: surface 0 = structural/matte (the majority of the hull),
# surface 1+ = hard armor (any number of armor-plate surfaces, e.g. a
# separate glacis + separate side-skirt group, all get the same armor
# material - armor doesn't need to vary WITHIN one hull). A hull whose
# authored mesh has only ONE surface (every hull not yet re-authored with
# a second material slot, or the plain BoxMesh fallback for a hull with no
# authored asset at all) gets the armor material on that single surface -
# matching this system's PRE-EXISTING look exactly, so un-migrated hulls
# don't silently change appearance mid-rollout.
#
# Uses set_surface_override_material() per surface, NOT material_override -
# material_override unconditionally overrides every surface of a mesh
# instance, which would make a second material slot invisible even if
# Blender authored one. Explicitly clears material_override too, since
# this function may run repeatedly on the same MeshInstance3D (e.g. every
# Design Lab faction/armor change) and a stale override would otherwise
# keep masking the real per-surface materials.
static func apply_hull_materials(mesh_inst: MeshInstance3D, armor_material: String, faction: String) -> void:
	mesh_inst.material_override = null
	# Real world-space face size (mesh-local AABB extents x the node's own
	# scale, since the Design Lab's hull_scale slider and armor_bulk both
	# apply via MeshInstance3D.scale, not a mesh rebuild) - see
	# _texture_scale_for_size()'s comment. Falls back to the fixed default
	# if there's no mesh yet (shouldn't happen in practice, this function
	# is always called with a real hull mesh already assigned).
	var texture_world_size = _DEFAULT_TEXTURE_WORLD_SIZE
	if mesh_inst.mesh:
		var extents = mesh_inst.mesh.get_aabb().size * mesh_inst.scale
		texture_world_size = (extents.x + extents.y + extents.z) / 3.0
	var armor_mat = build_hull_material(armor_material, faction, texture_world_size)
	# Corrects for non-uniform hull_scale/armor_bulk stretch - see the
	# shader's mesh_scale uniform comment. texture_world_size above already
	# folds mesh_inst.scale into the AVERAGE tiling density; this instead
	# corrects the PER-AXIS distortion between faces dominated by different
	# axes, which an average alone can't fix.
	armor_mat.set_shader_parameter("mesh_scale", mesh_inst.scale)
	var surface_count = mesh_inst.mesh.get_surface_count() if mesh_inst.mesh else 1
	if surface_count <= 1:
		mesh_inst.set_surface_override_material(0, armor_mat)
		return
	var structural_mat = build_structural_material(faction, texture_world_size)
	structural_mat.set_shader_parameter("mesh_scale", mesh_inst.scale)
	mesh_inst.set_surface_override_material(0, structural_mat)
	for surf in range(1, surface_count):
		mesh_inst.set_surface_override_material(surf, armor_mat)

# Sets flash_amount on every per-surface ShaderMaterial override a hull has
# (both structural and armor slots, if present) - battle_unit.gd's
# _flash_hull() and player_vehicle.gd's equivalent hit-flash used to read
# mesh_inst.material_override directly, which is ALWAYS null for a hull
# now that apply_hull_materials() uses per-surface overrides instead (see
# that function's own comment) - a direct material_override read would
# silently no-op every hit-flash without this fix. Centralized here since
# this file already owns the surface-index convention.
static func flash_hull(mesh_inst: MeshInstance3D, amount: float) -> void:
	if not mesh_inst or not mesh_inst.mesh:
		return
	for surf in range(mesh_inst.mesh.get_surface_count()):
		var mat = mesh_inst.get_surface_override_material(surf)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("flash_amount", amount)


# ---------------------------------------------------------------------------
# UNPAINTED SCALE-MODEL FINISH
# ---------------------------------------------------------------------------
# Strips a reconstructed vehicle back to a single flat grey-green plastic, the
# look of an unpainted injection-moulded kit. Used wherever a design is being
# SHOWN rather than fought - the main menu turntable, the Blueprint Library
# preview, roster thumbnails.
#
# Why not just use the faction material: on a showcase turntable the faction
# paint is noise. The player is evaluating the SHAPE they built, and ten
# factions' worth of livery on the same silhouette makes shapes harder to
# compare, not easier. Flat plastic is also the honest metaphor - this is the
# kit before it is painted.
#
# Lived as a verbatim duplicate in main_menu.gd and blueprint_library_screen.gd,
# which is exactly the copy-paste this file was created to end. The colour is
# the one already documented in UI_STYLE_GUIDE.md's 3D showcase section, so it
# had two sources of truth as well as two implementations.
#
# HullGreebles is skipped deliberately: it is a decorative surface-detail child
# that carries its own material, and overriding it flattens the greebling that
# gives the silhouette its read.
const SCALE_MODEL_ALBEDO = Color(0.38, 0.44, 0.37)

static func build_scale_model_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SCALE_MODEL_ALBEDO
	mat.metallic = 0.0
	mat.roughness = 0.8
	return mat


static func apply_scale_model_finish(node: Node, mat: StandardMaterial3D = null) -> void:
	if node.name == "HullGreebles":
		return
	if mat == null:
		mat = build_scale_model_material()
	if node is GeometryInstance3D:
		node.material_override = mat
		node.material_overlay = null
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			node.set_surface_override_material(i, mat)
	for child in node.get_children():
		apply_scale_model_finish(child, mat)
