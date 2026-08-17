# ArmorPaintVisual: turns an armor plan into the skins you can see on a hull.
#
# No class_name / no `extends`, matching hull_facets.gd and hull_surface.gd.
#
# WHY THE GEOMETRY IS REBUILT RATHER THAN SAVED. A painted facet's skin is the
# hull's own triangles, lifted by a z-fighting epsilon and cut by the type's
# pattern. That is GEOMETRY: it is not expressible as a node scale, and it is
# not in the blueprint JSON. The previous system tried to carry it as a placed
# module and lost it on every save - node scale went to (1,1,1) because the mesh
# carried the extent, and reloading rebuilt the authored 2 x 0.275 x 2 plate at
# that scale. A design's armor silently stopped fitting the moment it was saved,
# and no unit ever fought with the armor its designer drew. Deriving it from the
# facet id at build time means there is nothing to go stale.
#
# ONE NODE PER PAINTED FACET, all parented to a single `ArmorPaint` holder so a
# repaint is one free_children() rather than a hunt through the hull's modules.

const HullFacets = preload("res://scripts/hull_facets.gd")
const ModuleCatalog = preload("res://scripts/module_catalog.gd")
const PartMaterials = preload("res://scripts/part_materials.gd")

const HOLDER_NAME := "ArmorPaint"

# Per-material SHIFTS, applied to the hull's own colour rather than replacing
# it. The armor ROLE (part_materials' "armor", livery zone hull_upper) supplies
# metallic/roughness/wear.
#
# THESE USED TO BE ABSOLUTE TINTS and it looked wrong. The role's `tint` weight
# is 0.95, so a flat grey swatch almost entirely overrode the base colour: on a
# pale green livery hull the armor rendered as near-black mottled patches - a
# bolted-on billboard, which is precisely the read this whole system exists to
# remove. Armor is meant to look like a slightly different SECTION OF THE HULL,
# so the hull's colour is the starting point and the material only bends it.
#
# BLEND is how far toward the material's character the hull colour moves. Low on
# purpose: enough that reactive reads warmer than ablative side by side, not so
# much that the vehicle looks two-tone.
const MATERIAL_BLEND := 0.22
const MATERIAL_SHIFTS := {
	# value multiplier, hue direction (the colour the material leans toward)
	"hardened_steel": {"value": 0.92, "toward": Color(0.55, 0.57, 0.60)},
	"reactive_armor": {"value": 0.88, "toward": Color(0.62, 0.42, 0.36)},
	"ablative_ceramic": {"value": 1.08, "toward": Color(0.78, 0.76, 0.70)},
	"carbon_fiber": {"value": 0.78, "toward": Color(0.30, 0.31, 0.33)},
	"titanium_plate": {"value": 1.02, "toward": Color(0.66, 0.65, 0.68)},
	# Retained so a design that still carries it (a hull-global choice, or a
	# pre-Armor-Bay save) renders. Not paintable - see the Bay's material list.
	"energy_shielding": {"value": 0.96, "toward": Color(0.45, 0.60, 0.72)},
}
const FALLBACK_HULL_TINT := Color(0.52, 0.54, 0.50)


# Rebuilds every painted skin on `hull` from its `armor_plan` meta.
# `mesh_inst` is the hull's own MeshInstance3D - the same one the surface body
# traces, so the skin sits on the surface that is actually drawn.
static func rebuild(hull: Node3D, mesh_inst: MeshInstance3D) -> int:
	if not is_instance_valid(hull):
		return 0
	clear(hull)
	if mesh_inst == null or mesh_inst.mesh == null:
		return 0

	var plan: Dictionary = hull.get_meta("armor_plan", {})
	if plan.is_empty() or bool(plan.get("empty", true)):
		return 0
	var hull_type := str(plan.get("hull_type", ""))
	var facets: Dictionary = plan.get("facets", {})
	if facets.is_empty():
		return 0

	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	hull.add_child(holder)

	# The hull's own albedo is the base every painted facet starts from, so armor
	# reads as the same vehicle with a different surface rather than as a patch
	# of somebody else's paint.
	var hull_tint := _hull_albedo(mesh_inst)

	var built := 0
	for fid in facets.keys():
		var entry: Dictionary = facets[fid]
		var type_id := str(entry.get("type_id", ""))
		var frame := HullFacets.facet_frame(hull_type, int(fid), mesh_inst.transform)
		if not bool(frame.get("valid", false)):
			continue
		var cat: Dictionary = ModuleCatalog.get_module_data(type_id)
		var mesh := HullFacets.build_plate(mesh_inst, hull_type, int(fid), type_id,
			cat.get("size", Vector3.ONE), frame["center"], frame["basis"],
			str(entry.get("material", "hardened_steel")), float(entry.get("thickness", 1.0)))
		if mesh == null:
			continue

		var inst := MeshInstance3D.new()
		inst.name = "Armor_%d" % int(fid)
		inst.mesh = mesh
		# build_plate returns the skin already in the facet's frame, so the node
		# carries that frame and NOTHING else. Any inherited scale or offset here
		# is the bug that made these read as floating slabs.
		inst.transform = Transform3D(frame["basis"], frame["center"])
		inst.material_override = _armor_material(
			str(entry.get("material", "")), hull_tint)
		inst.set_meta("armor_facet_id", int(fid))
		holder.add_child(inst)
		built += 1
	return built


# The hull's rendered albedo, so armor can be derived from it. Checks the
# override first (what the livery/faction shader path actually sets) and falls
# back through the surface material, then to a neutral hull grey-green.
static func _hull_albedo(mesh_inst: MeshInstance3D) -> Color:
	var mat: Material = mesh_inst.material_override
	if mat == null and mesh_inst.mesh != null and mesh_inst.mesh.get_surface_count() > 0:
		mat = mesh_inst.get_active_material(0)
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_color
	if mat is ShaderMaterial:
		var v = (mat as ShaderMaterial).get_shader_parameter("albedo_color")
		if v == null:
			v = (mat as ShaderMaterial).get_shader_parameter("base_color")
		if v is Color:
			return v
	return FALLBACK_HULL_TINT


# The armor surface material, built HERE rather than taken from
# PartMaterials.get_material("armor", tint).
#
# WHY NOT THE SHARED ROLE. That role was tuned when armor was a bolt-on plate -
# a separate piece of hardware that was SUPPOSED to read as distinct from the
# hull. Its base is a dark grey and its `wear` is 0.70, which together swamp
# whatever tint the caller passes: rendered on a pale livery hull, a painted
# facet came out as a near-black mottled patch no matter what colour was
# requested. Confirmed by render, not by reasoning - the tint was being passed
# correctly and the result was still black.
#
# Armor is now a surface treatment on the hull's own skin, so it starts from the
# hull's albedo and differs by FINISH (metallic/roughness) and by relief. The
# role is left untouched because energy_barrier_projector and the greeble pass
# still use it for actual bolt-on hardware.
#
# Cached per (material, tint): a hull paints up to ~20 facets and they would
# otherwise each allocate an identical StandardMaterial3D.
static var _mat_cache: Dictionary = {}

# Per-material surface signature. `pattern` selects the shader branch, `cell`
# is the feature size IN METRES (UVs are metres of facet surface), `relief` how
# hard the normal is pushed, `seam` the groove width as a fraction of a cell.
#
# Read these as a family: steel is the flat reference, ceramic and carbon are
# fine, reactive and titanium are coarse. If two materials ever need to be told
# apart at gameplay zoom, cell size is the knob that matters - relief only
# changes how hard the light catches, and past about 1.5 it reads as noise.
const MATERIAL_FINISH := {
	"hardened_steel": {"metallic": 0.45, "roughness": 0.58, "pattern": 0, "cell": 0.50, "relief": 0.15, "seam": 0.06},
	"reactive_armor": {"metallic": 0.20, "roughness": 0.70, "pattern": 1, "cell": 0.42, "relief": 0.45, "seam": 0.07},
	"ablative_ceramic": {"metallic": 0.05, "roughness": 0.80, "pattern": 2, "cell": 0.22, "relief": 0.40, "seam": 0.10},
	"carbon_fiber": {"metallic": 0.25, "roughness": 0.35, "pattern": 3, "cell": 0.07, "relief": 0.30, "seam": 0.06},
	"titanium_plate": {"metallic": 0.72, "roughness": 0.40, "pattern": 4, "cell": 0.85, "relief": 0.40, "seam": 0.035},
	"energy_shielding": {"metallic": 0.30, "roughness": 0.45, "pattern": 2, "cell": 0.40, "relief": 0.70, "seam": 0.08},
}

const ARMOR_SHADER = preload("res://shaders/armor_surface.gdshader")


static func _armor_material(material_id: String, hull_tint: Color) -> ShaderMaterial:
	var key := "%s|%.3f_%.3f_%.3f" % [material_id, hull_tint.r, hull_tint.g, hull_tint.b]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var f: Dictionary = MATERIAL_FINISH.get(material_id, MATERIAL_FINISH["hardened_steel"])
	var mat := ShaderMaterial.new()
	mat.shader = ARMOR_SHADER
	mat.set_shader_parameter("albedo", _tint_for(material_id, hull_tint))
	mat.set_shader_parameter("metallic_amount", float(f["metallic"]))
	mat.set_shader_parameter("roughness_amount", float(f["roughness"]))
	mat.set_shader_parameter("pattern_id", int(f["pattern"]))
	mat.set_shader_parameter("cell", float(f["cell"]))
	mat.set_shader_parameter("relief", float(f["relief"]))
	mat.set_shader_parameter("seam", float(f["seam"]))
	_mat_cache[key] = mat
	return mat


static func clear_material_cache() -> void:
	_mat_cache.clear()


static func _tint_for(material_id: String, hull_tint: Color) -> Color:
	var shift: Dictionary = MATERIAL_SHIFTS.get(material_id, MATERIAL_SHIFTS["hardened_steel"])
	var toward: Color = shift["toward"]
	var out := hull_tint.lerp(toward, MATERIAL_BLEND)
	var v := float(shift["value"])
	return Color(clampf(out.r * v, 0.0, 1.0), clampf(out.g * v, 0.0, 1.0),
		clampf(out.b * v, 0.0, 1.0), 1.0)


static func clear(hull: Node3D) -> void:
	if not is_instance_valid(hull):
		return
	var existing = hull.get_node_or_null(HOLDER_NAME)
	if existing:
		hull.remove_child(existing)
		existing.queue_free()
