"""Inspect the legacy hull series (Mod4, carapace, hexapod) to
understand their actual vertex distribution and structural character.
Used as design reference for the family redesign per Chris's
2026-08-11 feedback: "look at the Mod4 series, the carapace series,
the hexapod series from the previous catalogue."
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inspect_glb import parse_glb, get_buffer_view, read_vec3


def dump_legacy(path):
	if not os.path.exists(path):
		print(f"  MISSING: {path}")
		return
	g, bin_chunk = parse_glb(path)
	meshes = g.get("meshes", [])
	# Collect vertex + face counts per primitive
	print(f"\n=== {os.path.basename(path)} ===")
	for mi, m in enumerate(meshes):
		for pi, p in enumerate(m.get("primitives", [])):
			attrs = p.get("attributes", {})
			mode = p.get("mode", 4)  # 4 = TRIANGLES
			pos_acc = attrs.get("POSITION")
			norm_acc = attrs.get("NORMAL")
			ind_acc = p.get("indices")
			pos_count = 0
			ind_count = 0
			if pos_acc is not None:
				pos_count = g["accessors"][pos_acc]["count"]
			if ind_acc is not None:
				ind_count = g["accessors"][ind_acc]["count"]
			print(f"  prim {mi}.{pi}: verts={pos_count}  indices={ind_count}  mode={mode}  "
				f"mat={p.get('material', 0)}  has_normal={'NORMAL' in attrs}")
			# For a 84-vert hull, dump vertex distribution along each axis
			if pos_acc is not None and pos_count <= 200:
				pts = read_vec3(g, bin_chunk, pos_acc)
				if pts:
					xs = sorted({round(p[0], 2) for p in pts})
					ys = sorted({round(p[1], 2) for p in pts})
					zs = sorted({round(p[2], 2) for p in pts})
					print(f"    X coords: {xs}")
					print(f"    Y coords: {ys}")
					print(f"    Z coords: {zs}")


targets = [
	# Hexapod series (hex cross-section family)
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\hex_pod_hull.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\hex_pod_hull_heavy.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\hex_pod_hull_light.glb",
	# Carapace series (angular armored family)
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\carapace_hull.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\carapace_hull_heavy.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\carapace_hull_light.glb",
	# Mod4 series (basic blocky family)
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\scout_hull_mod_4a2.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\light_hull_mod_4a3.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\medium_hull_mod_4a4.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\heavy_hull_mod_4a5.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\transport_hull_mod_4a6.glb",
	# Other useful references
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\octaplate_hull.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\delta_plate_hull.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\crawler_hull.glb",
	r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\spire_hull.glb",
]
for t in targets:
	dump_legacy(t)
