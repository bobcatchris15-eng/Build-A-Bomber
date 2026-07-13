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
const ARMOR_PBR = {
	"hardened_steel": {"metallic": 0.8, "roughness": 0.2, "shield_mode": 0.0, "alpha": 1.0},
	"reactive_armor": {"metallic": 0.1, "roughness": 0.7, "shield_mode": 0.0, "alpha": 1.0},
	"ablative_ceramic": {"metallic": 0.0, "roughness": 0.5, "shield_mode": 0.0, "alpha": 1.0},
	"energy_shielding": {"metallic": 0.1, "roughness": 0.1, "shield_mode": 1.0, "alpha": 0.7},
}

static func build_hull_material(armor_material: String, faction: String) -> ShaderMaterial:
	var armor = ARMOR_PBR.get(armor_material, ARMOR_PBR["hardened_steel"])
	var vis = FactionCatalogScript.get_visual(faction)
	var mat = ShaderMaterial.new()
	mat.shader = HULL_SHADER
	mat.set_shader_parameter("base_color", vis.base_color)
	mat.set_shader_parameter("accent_color", vis.accent_color)
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
	return mat
