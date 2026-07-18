"""
Hull modding pass (2026-07-18): authors ONE small, deliberately distinctive
test hull mesh and exports it directly to user://mods/hulls (the real
filesystem path below - NOT res://assets/models/hulls) to prove the full
moddability pipeline end-to-end: a modder drops a .glb + .json sidecar into
this folder with zero code changes and it shows up in-game.

Run headlessly with UPBGE's bundled Blender:
  UPBGE-0.30-windows-x86_64\\blender.exe --background --python tools\\blender\\build_test_mod_hull.py

Deliberately NOT part of build_meshes.py (which only ever writes to
assets/models/hulls, the built-in/shipped directory) - this script's whole
point is authoring something that lives in the OTHER directory, so it stays
separate rather than adding a res://-vs-user:// branch to the shipped tool.
"""

import bpy
import bmesh
import math
import os

# Real filesystem path for user://mods/hulls (Godot maps user:// to
# %APPDATA%\Godot\app_userdata\<project name>\ on Windows) - see
# hull_loader.gd's MOD_DIR const and blueprint_manager.gd's existing
# user://blueprints/ precedent for the same mapping.
MOD_HULLS_DIR = r"C:\Users\Chris\AppData\Roaming\Godot\app_userdata\Build-A-Bomber Prototype\mods\hulls"
HULL_ID = "prospectors_folly_hull"

os.makedirs(MOD_HULLS_DIR, exist_ok=True)


def GV(x, y, z):
	"""Godot-space (x, y_up, z_depth) -> raw Blender-space tuple (see build_meshes.py's own header comment)."""
	return (x, z, y)


def clear_scene():
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.object.delete(use_global=False)
	for block in list(bpy.data.meshes):
		if block.users == 0:
			bpy.data.meshes.remove(block)
	for block in list(bpy.data.materials):
		if block.users == 0:
			bpy.data.materials.remove(block)


def build_prospectors_folly():
	# A deliberately odd, unmistakable silhouette so it reads as "obviously
	# not a built-in hull" in a screenshot: a wide low base deck with a
	# narrow tower stacked off-center on top, like a jury-rigged prospector's
	# rig bolted onto a wagon bed - nothing else in the roster looks like
	# this. Godot-space size ends up (3.2, 2.6, 4.0) to match the sidecar's
	# authored "size" field.
	bm = bmesh.new()

	# Base deck: wide, low, long.
	base = bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=GV(3.2, 0.7, 4.0), verts=base["verts"])
	bmesh.ops.translate(bm, vec=GV(0, 0.35, 0), verts=base["verts"])

	# Tower: narrow, tall, off-center toward the rear (+Z) and to one side
	# (+X) - the "off-center jury-rig" look that makes this shape instantly
	# distinguishable from every symmetric built-in hull.
	tower = bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=GV(0.9, 1.9, 0.9), verts=tower["verts"])
	bmesh.ops.translate(bm, vec=GV(0.75, 0.7 + 0.95, 1.1), verts=tower["verts"])

	mesh = bpy.data.meshes.new(HULL_ID)
	bm.to_mesh(mesh)
	bm.free()
	mesh.update()

	obj = bpy.data.objects.new(HULL_ID, mesh)
	bpy.context.collection.objects.link(obj)

	# Loud, unmistakable "this is a mod" color - nothing in the built-in
	# roster (all steel/gray/olive/brown tones) is neon purple.
	mat = bpy.data.materials.new(HULL_ID + "_mat")
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf:
		bsdf.inputs["Base Color"].default_value = (0.7, 0.1, 0.9, 1.0)
		bsdf.inputs["Metallic"].default_value = 0.3
		bsdf.inputs["Roughness"].default_value = 0.5
	obj.data.materials.append(mat)

	return obj


def export_glb(obj, filepath):
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		use_selection=True,
		export_format='GLB',
		export_yup=True,
		export_apply=True
	)
	print("Exported: " + filepath)


clear_scene()
obj = build_prospectors_folly()
export_glb(obj, os.path.join(MOD_HULLS_DIR, HULL_ID + ".glb"))
print("Done.")
