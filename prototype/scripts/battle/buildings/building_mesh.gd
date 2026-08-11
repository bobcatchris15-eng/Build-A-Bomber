extends RefCounted
# Authored building art for the battle layer.
#
# WHY IT WAS MISSING. structure.gd's header says the boxes are a deliberate
# placeholder "until Chris replaces every building mesh with authored art
# later". That comment was already stale when it was written: assets/models/
# buildings/ has a GLB for every catalog kind (six originally, plus the three
# tech-tree labs) and the old runtime has been loading them since
# building.gd:615. The battle layer simply never looked.
#
# LIFTED FROM building.gd RATHER THAN REWRITTEN, because the fiddly part is not
# loading the scene - it is that an authored mesh has its own arbitrary size and
# origin, and the footprint in the catalog is gameplay truth. Collision, docking
# bays, navmesh carving and placement legality all key off that footprint, so the
# art is fitted to it rather than the other way round. Getting that backwards
# gives you a refinery whose visible walls do not match the box harvesters dock
# against.
#
# It lives here, in the battle layer, rather than being imported from
# building.gd, because building.gd is scheduled for deletion in the retirement
# commit and a dependency on it would block that.

const HullMaterialBuilder = preload("res://scripts/hull_material_builder.gd")
const LiveryScript = preload("res://scripts/livery.gd")
const HullDecalsScript = preload("res://scripts/hull_decals.gd")

const MODEL_DIR := "res://assets/models/buildings/%s.glb"


# Builds the visual for `kind` under `parent`, fitted to `footprint`.
# Returns the node added, or null if this kind has no authored art - the caller
# is expected to fall back to a box, so a missing GLB degrades to the old look
# rather than to an invisible building.
static func build(parent: Node3D, kind: String, footprint: Vector3,
		faction: String, team: int) -> Node3D:
	var path := MODEL_DIR % kind
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	inst.name = "BuildingMesh"

	var box := _aabb_of(inst)
	# A degenerate AABB means the GLB imported without usable geometry. Scaling
	# the footprint by 1/0 would put the building at infinity, where it renders
	# as nothing and reads exactly like the missing-mesh case it is.
	if box.size.x < 0.01 or box.size.y < 0.01 or box.size.z < 0.01:
		inst.queue_free()
		return null

	var fit := Vector3(
		footprint.x / box.size.x,
		footprint.y / box.size.y,
		footprint.z / box.size.z)
	inst.scale = fit
	# Sits ON the ground with its centre over the anchor: the footprint box is
	# authored from y=0 up, and a GLB's own origin is wherever the artist left it.
	inst.position = Vector3(0, footprint.y * 0.5, 0) \
		- (box.position + box.size * 0.5) * fit

	_apply_material(inst, faction, team)
	HullDecalsScript.apply_decals(inst, faction, footprint * 1.5)
	# NOT finished here. apply_decals() adds further MeshInstance3Ds with their
	# own materials, so a finish applied at this point misses every one of them -
	# measured: 50 structure materials at roughness 0.60 / specular 0.50 sailed
	# past it. structure.gd applies the finish once, after the whole building
	# exists.
	parent.add_child(inst)
	return inst


static func _aabb_of(node: Node3D) -> AABB:
	var meshes: Array = []
	_collect(node, meshes)
	var out := AABB()
	var first := true
	for mi in meshes:
		if mi.mesh == null:
			continue
		var m: AABB = mi.mesh.get_aabb()
		m.position = mi.transform * m.position
		m.size = mi.transform.basis * m.size
		if first:
			out = m
			first = false
		else:
			out = out.merge(m)
	if first:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return out


static func _collect(node: Node, into: Array) -> void:
	if node is MeshInstance3D:
		into.append(node)
	for child in node.get_children():
		_collect(child, into)


# Argument order is (armor_material, faction). Passing these swapped is a silent
# failure in both directions - the armor lookup misses and returns hardened_steel,
# the faction lookup misses and returns DEFAULT_FACTION - so every building
# renders plausibly while ignoring both inputs. building.gd shipped that bug for
# months; the order is spelled out here so this copy does not reintroduce it.
static func _apply_material(node: Node, faction: String, team: int) -> void:
	var mat := HullMaterialBuilder.build_hull_material(faction)
	if team != 0 and mat is ShaderMaterial:
		var tint: Color = LiveryScript.zone_color(faction, "hull_upper").lerp(
			Color(0.85, 0.2, 0.2), 0.45)
		mat.set_shader_parameter("base_color", tint)
	_assign(node, mat)


static func _assign(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_assign(child, mat)
