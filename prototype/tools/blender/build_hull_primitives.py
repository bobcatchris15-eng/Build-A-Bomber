"""
Hull Builder primitive kit generator.
Run headlessly with UPBGE's bundled Blender:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python tools\\blender\\build_hull_primitives.py

Produces one small unit-sized .glb per shape in
assets/models/hull_primitives/*.glb - the expanded "Lego kit" of basic
polygonal solids for the in-game Hull Builder (hull_builder.gd), on top of
the 6 shapes it already builds natively via Godot's own primitive meshes
(box/sphere/cylinder/wedge/cone/torus - unchanged, not duplicated here).

Every shape here is authored to fit within (or close to) a unit box
(roughly -0.5..0.5 on each axis) so it drops into hull_builder.gd's existing
convention where a primitive's per-instance `scale` alone controls its final
size - no per-type radius/height fields needed on the Godot side, matching
sdf_mesh_baker.gd's primitive_sdf(), which evaluates each shape's SDF in
this exact same unit space.

COORDINATE CONVENTION - copied from build_meshes.py (kept self-contained
here rather than importing that file, since importing it would execute its
own full hull/parts build pipeline as a side effect):
  Blender is authored Z-up. The glTF exporter's Y-up conversion maps
  Godot_X = Blender_X, Godot_Y = Blender_Z, Godot_Z = Blender_Y. GV()/GS()
  below take Godot-space (x, y_up, z_depth) and swap to raw Blender coords,
  so every build_*() function here is written purely in Godot X/Y/Z terms.

Self-imposed shape list (see hull_builder.gd's PrimitiveType enum, which
this script's output is registered against):
  slope        - box with one top-front edge beveled (Lego roof-slope read)
  frustum      - box tapered to a smaller top footprint (also doubles as
                 the base geometry a fully-tapered top_scale=0 pyramid would
                 use, but PYRAMID itself is built natively in Godot via a
                 4-sided CylinderMesh, not here)
  chamfer_box  - box with all edges bevelled (cast-armor-block read)
  half_cylinder- flat-bottomed half-round trough/canopy shell
  hemisphere   - flat-bottomed dome (turret hatch / sensor blister)
  i_beam       - I-beam structural section, extruded along Z
  l_beam       - L-angle bracket section, extruded along Z
  fender       - open half-torus arch (wheel-arch/mudguard read)
  canopy       - hemisphere elongated along Z (cockpit/turret bubble read)
  ring         - flat annulus/washer (turret ring collar), distinct from
                 the existing round-cross-section TORUS primitive

CAPSULE and HEX_PRISM/PYRAMID are deliberately NOT built here - Godot's own
CapsuleMesh and a 6- or 4-sided radial CylinderMesh already express those
exactly, so routing them through Blender/glTF would just be a slower,
harder-to-maintain reimplementation of something the engine already does
natively (same principle the original 6 primitives already followed).
"""

import bpy
import bmesh
import math
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "hull_primitives")
os.makedirs(OUT_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Self-contained helpers (deliberately duplicated from build_meshes.py's
# versions rather than imported - see module docstring)
# ---------------------------------------------------------------------------

def clear_scene():
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.object.delete(use_global=False)
	for block in list(bpy.data.meshes):
		if block.users == 0:
			bpy.data.meshes.remove(block)
	for block in list(bpy.data.materials):
		if block.users == 0:
			bpy.data.materials.remove(block)


def GV(x, y, z):
	"""Godot-space (x, y_up, z_depth) -> raw Blender-space tuple."""
	return (x, z, y)


def GS(sx, sy, sz):
	"""Godot-space (width, height, depth) size -> raw Blender-space size."""
	return (sx, sz, sy)


def new_material(name, color, metallic=0.6, roughness=0.4):
	mat = bpy.data.materials.get(name)
	if mat is None:
		mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf:
		bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
		bsdf.inputs["Metallic"].default_value = metallic
		bsdf.inputs["Roughness"].default_value = roughness
	return mat


def make_object_from_bmesh(bm, name):
	mesh = bpy.data.meshes.new(name + "_mesh")
	bm.to_mesh(mesh)
	bm.free()
	mesh.update()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(obj)
	return obj


def finalize(obj, name, color=(0.7, 0.7, 0.75), metallic=0.5, roughness=0.4):
	obj.name = name
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.shade_smooth()
	try:
		obj.data.use_auto_smooth = True
		obj.data.auto_smooth_angle = math.radians(35)
	except Exception:
		pass
	mat = new_material(name + "_mat", color, metallic, roughness)
	if obj.data.materials:
		obj.data.materials[0] = mat
	else:
		obj.data.materials.append(mat)


def export_and_cleanup(obj, filename):
	path = os.path.join(OUT_DIR, filename + ".glb")
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(
		filepath=path,
		use_selection=True,
		export_format='GLB',
		export_yup=True,
		export_apply=True
	)
	print("Exported: " + path)
	mesh_data = obj.data
	bpy.data.objects.remove(obj, do_unlink=True)
	if mesh_data and mesh_data.users == 0:
		bpy.data.meshes.remove(mesh_data)


def finish_bm(bm):
	"""Safety net used by every custom build_*() below - fixes winding/normal
	direction automatically regardless of manual vertex order (there is no
	interactive viewport to check normals visually in a headless batch run),
	and triangulates so no non-planar quad (e.g. frustum's slanted sides)
	ever reaches the exporter."""
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	bmesh.ops.triangulate(bm, faces=bm.faces[:])


def extrude_profile(bm, profile_2d, half_len):
	"""Extrudes a closed 2D (Godot X,Y) polygon loop along Godot Z by
	+-half_len: side walls between corresponding points on the two end
	rings, plus an N-gon cap at each end. The loop is treated as implicitly
	closed (last point connects back to the first) whether that's a genuine
	polygon corner (I-beam, L-beam) or, for an open-arc profile like the
	half-cylinder's D-shape, the flat edge across the arc's two ends."""
	front_verts = [bm.verts.new(GV(x, y, -half_len)) for (x, y) in profile_2d]
	back_verts = [bm.verts.new(GV(x, y, half_len)) for (x, y) in profile_2d]
	n = len(profile_2d)
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new([front_verts[i], front_verts[j], back_verts[j], back_verts[i]])
	bm.faces.new(list(reversed(front_verts)))
	bm.faces.new(back_verts)
	return front_verts, back_verts


def _dome_rings(bm, radius, z_stretch, segments, rings):
	"""Shared vertex-ring builder for hemisphere/canopy: a flat-bottomed
	dome, base ring at Godot Y = -radius (so it sits flush with a unit box's
	floor like every other primitive), apex at Y = 0. z_stretch elongates
	the Z axis only, turning the symmetric dome into a canopy/bubble shape."""
	center_y = -radius
	rings_verts = []
	for i in range(rings):
		phi = (math.pi / 2.0) * i / rings
		r_xy = radius * math.cos(phi)
		y = center_y + radius * math.sin(phi)
		ring = []
		for j in range(segments):
			ang = 2.0 * math.pi * j / segments
			ring.append(bm.verts.new(GV(r_xy * math.cos(ang), y, r_xy * math.sin(ang) * z_stretch)))
		rings_verts.append(ring)
	apex = bm.verts.new(GV(0, center_y + radius, 0))

	for i in range(rings - 1):
		for j in range(segments):
			j2 = (j + 1) % segments
			a, b = rings_verts[i][j], rings_verts[i][j2]
			c, d = rings_verts[i + 1][j2], rings_verts[i + 1][j]
			bm.faces.new([a, b, c, d])

	last_ring = rings_verts[-1]
	for j in range(segments):
		j2 = (j + 1) % segments
		bm.faces.new([last_ring[j], last_ring[j2], apex])

	bm.faces.new(list(reversed(rings_verts[0])))


# ---------------------------------------------------------------------------
# Shape builders
# ---------------------------------------------------------------------------

def build_slope(name="slope"):
	bm = bmesh.new()
	ret = bmesh.ops.create_cube(bm, size=1.0)
	verts = ret['verts']
	# Top-front edge in raw Blender coords: GV swaps (godot y,z) -> (raw z,y),
	# so "top" (godot Y=+0.5) is raw.z==+0.5 and "front"/nose (godot Z=-0.5)
	# is raw.y==-0.5.
	edge_verts = [v for v in verts if abs(v.co.z - 0.5) < 1e-4 and abs(v.co.y + 0.5) < 1e-4]
	edges = [e for e in bm.edges if all(v in edge_verts for v in e.verts)]
	if edges:
		bmesh.ops.bevel(bm, geom=edges, offset=0.35, segments=1, affect='EDGES')
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.72, 0.72, 0.76))
	export_and_cleanup(obj, name)


def build_frustum(name="frustum", top_scale=0.5):
	bm = bmesh.new()
	ret = bmesh.ops.create_cube(bm, size=1.0)
	verts = ret['verts']
	top_verts = [v for v in verts if v.co.z > 0]  # raw.z = godot.y (up)
	for v in top_verts:
		v.co.x *= top_scale  # raw.x = godot.x
		v.co.y *= top_scale  # raw.y = godot.z
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.7, 0.7, 0.75))
	export_and_cleanup(obj, name)


def build_chamfer_box(name="chamfer_box", bevel_amt=0.12):
	bm = bmesh.new()
	ret = bmesh.ops.create_cube(bm, size=1.0)
	verts = ret['verts']
	edges = [e for e in bm.edges if all(v in verts for v in e.verts)]
	bmesh.ops.bevel(bm, geom=edges, offset=bevel_amt, segments=2, affect='EDGES')
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.68, 0.68, 0.73), metallic=0.6, roughness=0.35)
	export_and_cleanup(obj, name)


def build_half_cylinder(name="half_cylinder", radius=0.5, segments=20):
	bm = bmesh.new()
	cy = -radius  # flat side at Godot Y = -0.5, apex at Y = 0
	profile = []
	for i in range(segments + 1):
		theta = math.pi - (math.pi * i / segments)  # pi -> 0
		x = radius * math.cos(theta)
		y = cy + radius * math.sin(theta)
		profile.append((x, y))
	extrude_profile(bm, profile, half_len=0.5)
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.7, 0.72, 0.76), metallic=0.15, roughness=0.3)
	export_and_cleanup(obj, name)


def build_i_beam(name="i_beam", flange_thick=0.15, web_half_width=0.15):
	hh = 0.5
	hw = 0.5
	ft = flange_thick
	wh = web_half_width
	profile = [
		(-hw, hh), (hw, hh), (hw, hh - ft),
		(wh, hh - ft), (wh, -hh + ft),
		(hw, -hh + ft), (hw, -hh), (-hw, -hh),
		(-hw, -hh + ft), (-wh, -hh + ft),
		(-wh, hh - ft), (-hw, hh - ft),
	]
	bm = bmesh.new()
	extrude_profile(bm, profile, half_len=0.5)
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.5, 0.5, 0.55), metallic=0.55, roughness=0.45)
	export_and_cleanup(obj, name)


def build_l_beam(name="l_beam", thick=0.18):
	hh = 0.5
	hw = 0.5
	profile = [
		(-hw, hh), (-hw + thick, hh), (-hw + thick, -hh + thick),
		(hw, -hh + thick), (hw, -hh), (-hw, -hh),
	]
	bm = bmesh.new()
	extrude_profile(bm, profile, half_len=0.5)
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.5, 0.5, 0.55), metallic=0.55, roughness=0.45)
	export_and_cleanup(obj, name)


def build_fender(name="fender", major_r=0.4, minor_r=0.12, major_segments=16, minor_segments=10):
	bm = bmesh.new()
	rings = []
	for i in range(major_segments + 1):
		theta = math.pi * i / major_segments  # 0..pi, arch over Godot Y>=0
		cx = major_r * math.cos(theta)
		cy = major_r * math.sin(theta)
		ring = []
		for j in range(minor_segments):
			ang = 2.0 * math.pi * j / minor_segments
			rx = cx + minor_r * math.cos(ang) * math.cos(theta)
			ry = cy + minor_r * math.cos(ang) * math.sin(theta)
			rz = minor_r * math.sin(ang)
			ring.append(bm.verts.new(GV(rx, ry, rz)))
		rings.append(ring)
	for i in range(major_segments):
		for j in range(minor_segments):
			j2 = (j + 1) % minor_segments
			a, b = rings[i][j], rings[i][j2]
			c, d = rings[i + 1][j2], rings[i + 1][j]
			bm.faces.new([a, b, c, d])
	bm.faces.new(list(reversed(rings[0])))
	bm.faces.new(rings[-1])
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.55, 0.55, 0.6), metallic=0.5, roughness=0.5)
	export_and_cleanup(obj, name)


def build_hemisphere(name="hemisphere", radius=0.5, segments=18, rings=8):
	bm = bmesh.new()
	_dome_rings(bm, radius, z_stretch=1.0, segments=segments, rings=rings)
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.75, 0.76, 0.8), metallic=0.1, roughness=0.25)
	export_and_cleanup(obj, name)


def build_canopy(name="canopy", radius=0.5, z_stretch=1.35, segments=18, rings=8):
	bm = bmesh.new()
	_dome_rings(bm, radius, z_stretch=z_stretch, segments=segments, rings=rings)
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.55, 0.7, 0.82), metallic=0.05, roughness=0.15)
	export_and_cleanup(obj, name)


def build_ring(name="ring", outer_r=0.5, inner_r=0.3, half_h=0.15, segments=24):
	bm = bmesh.new()
	outer_top, outer_bot, inner_top, inner_bot = [], [], [], []
	for i in range(segments):
		ang = 2.0 * math.pi * i / segments
		cx, cz = math.cos(ang), math.sin(ang)
		outer_top.append(bm.verts.new(GV(outer_r * cx, half_h, outer_r * cz)))
		outer_bot.append(bm.verts.new(GV(outer_r * cx, -half_h, outer_r * cz)))
		inner_top.append(bm.verts.new(GV(inner_r * cx, half_h, inner_r * cz)))
		inner_bot.append(bm.verts.new(GV(inner_r * cx, -half_h, inner_r * cz)))
	for i in range(segments):
		j = (i + 1) % segments
		bm.faces.new([outer_top[i], outer_top[j], inner_top[j], inner_top[i]])
		bm.faces.new([inner_bot[i], inner_bot[j], outer_bot[j], outer_bot[i]])
		bm.faces.new([outer_bot[i], outer_bot[j], outer_top[j], outer_top[i]])
		bm.faces.new([inner_top[i], inner_top[j], inner_bot[j], inner_bot[i]])
	finish_bm(bm)
	obj = make_object_from_bmesh(bm, name)
	finalize(obj, name, color=(0.6, 0.6, 0.65), metallic=0.65, roughness=0.4)
	export_and_cleanup(obj, name)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

clear_scene()
build_slope()
build_frustum()
build_chamfer_box()
build_half_cylinder()
build_i_beam()
build_l_beam()
build_fender()
build_hemisphere()
build_canopy()
build_ring()
print("Hull primitive kit build complete: " + OUT_DIR)
