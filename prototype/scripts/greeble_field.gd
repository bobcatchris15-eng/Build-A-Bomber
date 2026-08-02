extends RefCounted
class_name GreebleField
# A general engine for scattering REPEATING AUTHORED MESH greebles across a
# hull's surface, driven entirely by a data spec.
#
# WHY THIS EXISTS RATHER THAN A FOURTH BESPOKE GREEBLE SCRIPT
# ---------------------------------------------------------------------------
# This project already had hull_greebles.gd and hull_decals.gd, and adding
# armour-material plating as a third hand-written placer would have made the
# next one a fourth. Those two are also both CARD systems - alpha-cutout
# quads, one hand-written builder function per faction - which is the wrong
# tool for surface plating: a bolt field is a hundred small solid objects
# conforming to a curved skin, not four textured quads.
#
# So the placement logic lives here once, and everything a caller wants to
# vary is DATA:
#
#   {
#     "part": "armor_stud_bolt",   # authored .glb, instanced at TRUE size
#     "spacing": 0.55,             # world units between instances
#     "faces": ["top","left",...], # which hull facets to cover
#     "tint": Color(...),
#     "jitter": 0.25,              # 0-1 randomness in the lattice
#     "align_to_normal": true,
#     "yaw_random": true,
#     "scale": 1.0,                # UNIFORM only - see below
#     "max_instances": 160,
#   }
#
# THE RULES IT ENFORCES, WHICH ARE THE WHOLE POINT
# ---------------------------------------------------------------------------
# 1. Instances are placed at their AUTHORED SIZE and never stretched. Density
#    scales with hull size; the greeble does not. This is the same rule the
#    structural pieces follow, and for the same reason - a stretched bolt head
#    is a smear. `scale` is uniform-only, deliberately: there is no per-axis
#    scale argument to reach for.
# 2. Count is derived from AREA and spacing, then hard-capped. A large hull
#    gets more bolts, not bigger ones, and can never get so many that it
#    tanks the frame rate.
# 3. Everything shares ONE material per (part, tint) pair, so a hundred bolts
#    are still one draw call's worth of material state - the same identity
#    sharing part_materials.gd relies on for bake_module_visual's merge.
#
# WHAT IT DELIBERATELY DOES NOT REPLACE
# ---------------------------------------------------------------------------
# hull_greebles.gd's alpha-cutout cards extend PAST the hull silhouette on
# purpose (netting, pennants, scrap antennas - a deliberate exception logged
# in DECISIONS_NEEDED.md). That is a genuinely different job from surface
# plating that conforms to the skin, and forcing both through one system
# would make both worse. They can migrate here if they ever want to be real
# geometry; nothing here assumes they will.

const HullProjectionScript = preload("res://scripts/hull_projection.gd")
const MeshAssetLoader = preload("res://scripts/mesh_asset_loader.gd")

# Facet name -> outward normal in hull-local space.
const FACE_NORMALS := {
	"top": Vector3.UP,
	"bottom": Vector3.DOWN,
	"left": Vector3.LEFT,
	"right": Vector3.RIGHT,
	"front": Vector3.FORWARD,
	"back": Vector3.BACK,
}

# Hard ceiling regardless of what a spec asks for. A 700-weight dreadnought
# hull with a 0.35 spacing would otherwise ask for several thousand meshes.
const ABSOLUTE_MAX_INSTANCES := 220

static var _material_cache: Dictionary = {}

static func _material_for(tint: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var key = "%d_%d_%d_%.2f_%.2f" % [int(tint.r * 32), int(tint.g * 32), int(tint.b * 32), metallic, roughness]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = metallic
	mat.roughness = roughness
	_material_cache[key] = mat
	return mat

# Scatters one spec's greebles into `container`. `surface` is a
# HullProjection surface dict; `hull_size` is the fallback extent when the
# hull has no gathered triangles (headless tests, primitive hulls).
static func scatter(container: Node3D, surface: Dictionary, hull_size: Vector3, spec: Dictionary) -> int:
	var mesh: Mesh = MeshAssetLoader.get_part_mesh(spec.get("part", ""))
	if mesh == null:
		# A missing authored asset must degrade to "no greebles", never to an
		# error or to a fallback box - a hull covered in placeholder cubes is
		# worse than a clean hull.
		return 0

	# Work in the hull's ACTUAL bounding box, not just its size. Laying the
	# lattice out around the ORIGIN assumes the hull is centred there, which
	# most authored hulls are not - their mesh sits at an offset - so greebles
	# were placed around a point the hull is not at, and any ray that then
	# missed fell back to an origin-relative guess and left one floating.
	var box: AABB = AABB(-hull_size * 0.5, hull_size)
	if surface.has("aabb") and surface["tris"].size() >= 3:
		box = surface["aabb"] as AABB
	var extents: Vector3 = box.size.maxf(0.2)
	var centre: Vector3 = box.position + box.size * 0.5

	var spacing: float = maxf(0.15, float(spec.get("spacing", 0.6)))
	var jitter: float = clampf(float(spec.get("jitter", 0.25)), 0.0, 1.0)
	var uniform_scale: float = maxf(0.05, float(spec.get("scale", 1.0)))
	var align: bool = bool(spec.get("align_to_normal", true))
	var yaw_random: bool = bool(spec.get("yaw_random", false))
	var tint: Color = spec.get("tint", Color(0.5, 0.5, 0.5))
	var mat := _material_for(tint, float(spec.get("metallic", 0.6)), float(spec.get("roughness", 0.5)))
	var cap: int = mini(int(spec.get("max_instances", 120)), ABSOLUTE_MAX_INSTANCES)

	# Deterministic per (part, hull size) so a hull does not reshuffle its own
	# rivets every time the Design Lab rebuilds its visual.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s_%.2f_%.2f_%.2f" % [spec.get("part", ""), extents.x, extents.y, extents.z])

	# Transforms are accumulated and handed to ONE MultiMeshInstance3D at the
	# end rather than each becoming its own MeshInstance3D. 150 rivets as 150
	# nodes is 150 draw calls and 150 scene-tree children on every hull in the
	# battle; as a multimesh it is one of each. Nothing here varies per instance
	# except the transform, which is exactly the case MultiMesh exists for.
	var xforms: Array[Transform3D] = []
	var placed := 0
	for face in spec.get("faces", ["top"]):
		if placed >= cap:
			break
		if not FACE_NORMALS.has(face):
			continue
		var normal: Vector3 = FACE_NORMALS[face]
		# The two in-plane axes for this facet, and the facet's own extent.
		var u := Vector3.RIGHT if absf(normal.x) < 0.5 else Vector3.FORWARD
		var v := normal.cross(u).normalized()
		u = v.cross(normal).normalized()
		var span_u = absf(u.dot(extents))
		var span_v = absf(v.dot(extents))
		var nu = maxi(1, int(span_u / spacing))
		var nv = maxi(1, int(span_v / spacing))

		for i in range(nu):
			for j in range(nv):
				if placed >= cap:
					break
				# Lattice position in facet space, inset from the edges so
				# greebles never hang off a corner.
				var tu = ((float(i) + 0.5) / float(nu) - 0.5) * 0.86
				var tv = ((float(j) + 0.5) / float(nv) - 0.5) * 0.86
				tu += rng.randf_range(-jitter, jitter) / float(nu) * 0.5
				tv += rng.randf_range(-jitter, jitter) / float(nv) * 0.5

				# Start the ray comfortably OUTSIDE the box and cast inward,
				# so it can never begin inside the hull and miss.
				var standoff = extents.dot(normal.abs()) * 0.5 + 1.0
				var anchor = centre + u * (tu * span_u) + v * (tv * span_v) + normal * standoff
				var hit = HullProjectionScript.raycast(surface, anchor, -normal)
				if not hit["hit"]:
					# No surface under this lattice cell - a concave hull, or a
					# facet the mesh does not occupy. SKIP rather than guess a
					# position: a greeble hovering off the hull is much worse
					# than a slightly sparser field.
					continue
				var surf_n: Vector3 = hit["normal"]
				# Nudge out along the normal so the base sits ON the skin
				# rather than z-fighting it.
				var pos: Vector3 = hit["position"] + surf_n.normalized() * 0.004

				var basis := Basis.IDENTITY
				if align:
					# basis_STANDING, not basis_for_normal. basis_for_normal
					# aligns local +Z to the surface - the CARD convention, a
					# quad lying flat in XY - but these greebles are authored
					# rising along +Y, so that convention laid every one of
					# them flat on its side. basis_standing aligns +Y to the
					# normal, which is how they are actually authored.
					basis = HullProjectionScript.basis_standing(surf_n)
				if yaw_random:
					basis = basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				xforms.append(Transform3D(basis.scaled(Vector3.ONE * uniform_scale), pos))
				placed += 1

	if placed == 0:
		return 0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = placed
	for k in range(placed):
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	# The same transforms, kept on the node. MultiMesh's buffer lives in the
	# RenderingServer, and the headless dummy renderer discards it - so
	# get_instance_transform() reads back identity and there is no way to
	# assert from a test that a greeble seated flat on the hull rather than
	# floating perpendicular off it, which is exactly the class of bug that
	# shipped here twice. A few hundred Transform3Ds is a rounding error next
	# to the mesh they place.
	mmi.set_meta("greeble_transforms", xforms)
	container.add_child(mmi)
	mmi.name = "Field_" + str(spec.get("part", "greeble"))
	return placed

# Places a small fixed number of instances at named corners rather than in a
# field - for things there should be exactly four of (shield emitters), where
# a density-driven lattice would be wrong.
static func place_at_corners(container: Node3D, surface: Dictionary, hull_size: Vector3,
							 spec: Dictionary, upper_only: bool = true) -> int:
	var mesh: Mesh = MeshAssetLoader.get_part_mesh(spec.get("part", ""))
	if mesh == null:
		return 0
	# Work in the hull's ACTUAL bounding box, not just its size. Laying the
	# lattice out around the ORIGIN assumes the hull is centred there, which
	# most authored hulls are not - their mesh sits at an offset - so greebles
	# were placed around a point the hull is not at, and any ray that then
	# missed fell back to an origin-relative guess and left one floating.
	var box: AABB = AABB(-hull_size * 0.5, hull_size)
	if surface.has("aabb") and surface["tris"].size() >= 3:
		box = surface["aabb"] as AABB
	var extents: Vector3 = box.size.maxf(0.2)
	var centre: Vector3 = box.position + box.size * 0.5

	var mat := _material_for(spec.get("tint", Color(0.4, 0.5, 0.6)),
							 float(spec.get("metallic", 0.7)), float(spec.get("roughness", 0.3)))
	var uniform_scale: float = maxf(0.05, float(spec.get("scale", 1.0)))
	var inset: float = clampf(float(spec.get("inset", 0.80)), 0.1, 1.0)
	var placed := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var anchor = centre + Vector3(sx * extents.x * 0.5 * inset,
				extents.y * 0.5 + 1.0,
				sz * extents.z * 0.5 * inset)
			var hit = HullProjectionScript.raycast(surface, anchor, Vector3.DOWN)
			var surf_n: Vector3 = hit["normal"] if hit["hit"] else Vector3.UP
			var pos: Vector3 = hit["position"] if hit["hit"] else Vector3(anchor.x, centre.y + extents.y * 0.5, anchor.z)
			var inst = MeshInstance3D.new()
			inst.mesh = mesh
			inst.material_override = mat
			# Nudged out along the normal so the base sits ON the skin.
			inst.position = pos + surf_n.normalized() * 0.004
			# Same standing convention as scatter() - see its note.
			inst.basis = HullProjectionScript.basis_standing(surf_n)
			inst.scale = Vector3.ONE * uniform_scale
			container.add_child(inst)
			placed += 1
	return placed
