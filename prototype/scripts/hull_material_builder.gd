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
const ARMOR_PBR = {
	"hardened_steel": {"metallic": 0.55, "roughness": 0.42, "shield_mode": 0.0, "alpha": 1.0},
	"reactive_armor": {"metallic": 0.1, "roughness": 0.7, "shield_mode": 0.0, "alpha": 1.0},
	"ablative_ceramic": {"metallic": 0.0, "roughness": 0.5, "shield_mode": 0.0, "alpha": 1.0},
	"energy_shielding": {"metallic": 0.1, "roughness": 0.1, "shield_mode": 1.0, "alpha": 0.7},
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

static func build_hull_material(armor_material: String, faction: String) -> ShaderMaterial:
	var armor = ARMOR_PBR.get(armor_material, ARMOR_PBR["hardened_steel"])
	var vis = FactionCatalogScript.get_visual(faction)
	var mat = ShaderMaterial.new()
	mat.shader = HULL_SHADER
	# Lightened 2026-07-18 alongside metallic being brought down (see
	# ARMOR_PBR's own comment) - guarantees a real, reliable brightness
	# gap against build_structural_material()'s darkened(0.62) even with
	# metallic's diffuse-suppression working against it. Applies to every
	# hull's armor material uniformly, including the un-migrated single-
	# surface fallback (apply_hull_materials()) - a harmless, arguably
	# fitting side effect there too (armor reading a bit brighter/more
	# premium), and moot in practice since every hull in the current
	# roster already has a real 2-surface split.
	mat.set_shader_parameter("base_color", vis.base_color.lightened(0.28))
	mat.set_shader_parameter("accent_color", vis.accent_color.lightened(0.28))
	mat.set_shader_parameter("detail_color", vis.detail_color)
	mat.set_shader_parameter("anisotropy", vis.anisotropy)
	mat.set_shader_parameter("brush_scale", vis.get("brush_scale", 2.0))
	mat.set_shader_parameter("wear_amount", vis.wear_amount)
	mat.set_shader_parameter("wear_color", vis.wear_color)
	mat.set_shader_parameter("grime_amount", vis.grime_amount)
	mat.set_shader_parameter("edge_highlight_strength", vis.edge_highlight_strength)
	mat.set_shader_parameter("emissive_color", vis.emissive_color)
	mat.set_shader_parameter("emissive_strength", vis.emissive_strength)
	mat.set_shader_parameter("mottle_amount", vis.get("mottle_amount", 0.0))
	mat.set_shader_parameter("decal_tint", vis.get("detail_color", Color.WHITE))
	mat.set_shader_parameter("metallic", armor.metallic)
	mat.set_shader_parameter("roughness", armor.roughness)
	mat.set_shader_parameter("shield_mode", armor.shield_mode)
	mat.set_shader_parameter("alpha_base", armor.alpha)
	var faction_id = faction if FactionCatalogScript.FACTIONS.has(faction) else FactionCatalogScript.DEFAULT_FACTION
	var textures = _get_faction_textures(faction_id)
	mat.set_shader_parameter("albedo_tex", textures.albedo)
	mat.set_shader_parameter("normal_tex", textures.normal)
	mat.set_shader_parameter("roughness_tex", textures.roughness)
	return mat

# Structural/base-plating material (2026-07-17, Approach A multi-region
# rollout - see DECISIONS_NEEDED.md) - the majority, non-armor surface of a
# hull: matte/satin, reads as workmanlike structural plate rather than
# polished armor. Deliberately reuses the SAME shader and the SAME
# per-faction color/wear/grime/texture data as build_hull_material() - no
# new per-faction texture set, no new FactionCatalog fields, exactly
# preserving the "one parametric shader x N factions, zero combinatorial
# texture re-authoring" property this system has always had. Only the PBR
# response differs: low metallic, high roughness, and anisotropy knocked
# way down (the anodized-brushed-metal streak is specifically the HARD
# ARMOR plate's signature look now, not a whole-hull default - see
# hull_faction_material.gdshader's ANISOTROPY line). Deliberately ignores
# armor_material/ARMOR_PBR entirely: structural plating doesn't change
# composition based on which armor package is bolted on, same as a real
# vehicle's hull monocoque staying the same steel regardless of add-on
# armor kit.
#
# 2026-07-17 cont'd: pushed further toward matte (metallic 0.15->0.04,
# roughness 0.82->0.93, anisotropy multiplier 0.25->0.08) after Chris's
# follow-up that the armor/structural split didn't read strongly enough in
# the first-pass screenshots. Also darkens base_color/accent_color via
# Color.darkened() - a straight RGB scalar multiply toward black, which
# preserves HUE exactly and only reduces value, per Chris's explicit "value/
# saturation separation, not hue" ask - so structural reads as a genuinely
# duller/darker version of the SAME faction color family, not a different
# faction's paint job. detail_color (small stencil/bolt accents) is left
# untouched on purpose - those should stay legible regardless of which
# region they land on.
#
# 2026-07-18: darken amount raised again, 0.16 -> 0.62, after a rigorous
# pixel-level check (not a visual read) proved 0.16 was nowhere near
# enough - two identical boxes, one per material, side by side under
# identical lighting, sampled dead center of each flat face (deliberately
# far from any specular highlight or edge) came back within ~0.007
# average RGB of each other, indistinguishable to the eye. That check also
# exposed WHY: metallic/roughness differences are fundamentally VIEW- and
# LIGHT-ANGLE-DEPENDENT (a shinier material only looks brighter where a
# highlight actually lands; everywhere else, a HIGH-metallic surface can
# look darker than a low-metallic one, since metals have near-zero diffuse
# reflectance) - so the metallic/roughness gap alone, however wide, cannot
# be trusted to read consistently regardless of camera/light angle. Color
# VALUE is the only lever that's angle-independent (a darker diffuse
# albedo reads darker under any lighting), hence pushing it hard here
# rather than trying to further chase the PBR angle-dependent route.
static func build_structural_material(faction: String) -> ShaderMaterial:
	var vis = FactionCatalogScript.get_visual(faction)
	var mat = ShaderMaterial.new()
	mat.shader = HULL_SHADER
	mat.set_shader_parameter("base_color", vis.base_color.darkened(0.62))
	mat.set_shader_parameter("accent_color", vis.accent_color.darkened(0.62))
	mat.set_shader_parameter("detail_color", vis.detail_color)
	mat.set_shader_parameter("anisotropy", vis.anisotropy * 0.08)
	mat.set_shader_parameter("brush_scale", vis.get("brush_scale", 2.0))
	mat.set_shader_parameter("wear_amount", vis.wear_amount)
	mat.set_shader_parameter("wear_color", vis.wear_color)
	mat.set_shader_parameter("grime_amount", vis.grime_amount)
	mat.set_shader_parameter("edge_highlight_strength", vis.edge_highlight_strength)
	mat.set_shader_parameter("emissive_color", vis.emissive_color)
	mat.set_shader_parameter("emissive_strength", vis.emissive_strength)
	mat.set_shader_parameter("mottle_amount", vis.get("mottle_amount", 0.0))
	mat.set_shader_parameter("decal_tint", vis.get("detail_color", Color.WHITE))
	mat.set_shader_parameter("metallic", 0.04)
	mat.set_shader_parameter("roughness", 0.93)
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
	var armor_mat = build_hull_material(armor_material, faction)
	var surface_count = mesh_inst.mesh.get_surface_count() if mesh_inst.mesh else 1
	if surface_count <= 1:
		mesh_inst.set_surface_override_material(0, armor_mat)
		return
	var structural_mat = build_structural_material(faction)
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
