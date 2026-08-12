"""Tiny GLB inspector - dump vertex/face counts, AABB, and vertex
distribution. Used to compare legacy hull silhouettes against the
new parametric ones, and to detect floating greebles (vertices far
from the convex hull's face centroids).
"""
import json
import os
import struct
import sys


def parse_glb(path):
	with open(path, "rb") as f:
		data = f.read()
	# Header
	magic, version, length = struct.unpack("<III", data[:12])
	if magic != 0x46546C67:  # "glTF"
		raise ValueError("Not a GLB file")
	# Find BIN chunk magic (start of binary chunk) by literal search,
	# not by trusting the JSON chunk_len header. Blender's exporter
	# occasionally mis-reports the JSON chunk length (we've seen 1.3 GB
	# for a 6 KB JSON), and the JSON->BIN boundary has a few bytes of
	# padding that aren't always cleanly at a 4-byte boundary.
	bin_magic_off = data.find(b"BIN", 20)
	if bin_magic_off < 0:
		raise ValueError("No BIN chunk found in GLB")
	# The JSON's true end is the last `}` before the BIN chunk. Use
	# rfind on the raw bytes for the closing brace, then sanity-check
	# the slice by trying to parse it.
	candidate_end = data.rfind(b"}", 20, bin_magic_off) + 1
	json_text = data[20:candidate_end].decode("utf-8", errors="replace")
	try:
		g = json.loads(json_text)
	except json.JSONDecodeError:
		# Last resort: trim trailing non-printable bytes and re-try.
		trim = candidate_end
		while trim > 20 and not (32 <= data[trim - 1] < 127):
			trim -= 1
		json_text = data[20:trim].decode("utf-8", errors="replace")
		g = json.loads(json_text)
	# BIN chunk: 4 type bytes + 4 length bytes, then the payload.
	bin_type, bin_len = struct.unpack("<II", data[bin_magic_off:bin_magic_off + 8])
	bin_chunk = data[bin_magic_off + 8:bin_magic_off + 8 + bin_len]
	return g, bin_chunk


def get_buffer_view(g, accessor_idx):
	acc = g["accessors"][accessor_idx]
	bv = g["bufferViews"][acc["bufferView"]]
	return acc, bv


def read_vec3(g, bin_chunk, accessor_idx, target_count=None):
	"""Read a VEC3 accessor, return list of (x, y, z) tuples."""
	acc, bv = get_buffer_view(g, accessor_idx)
	offset = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
	count = acc["count"] if target_count is None else min(target_count, acc["count"])
	ctype = acc["componentType"]
	# 5126 = FLOAT, 5120 = BYTE, 5121 = UBYTE, 5122 = SHORT, 5123 = USHORT
	if ctype != 5126:
		return None  # only handle floats for now
	stride = bv.get("byteStride", 12)
	if stride < 12:
		stride = 12  # tight-packed is the spec default
	out = []
	for i in range(count):
		base = offset + i * stride
		end = base + 12
		if end > len(bin_chunk):
			return None  # buffer too short, abort
		x, y, z = struct.unpack("<fff", bin_chunk[base:end])
		out.append((x, y, z))
	return out


def inspect(path):
	g, bin_chunk = parse_glb(path)
	meshes = g.get("meshes", [])
	nodes = g.get("nodes", [])
	# Collect all position accessors across all primitives
	all_positions = []
	prim_counts = []
	for m in meshes:
		for p in m.get("primitives", []):
			attrs = p.get("attributes", {})
			pos_acc = attrs.get("POSITION")
			if pos_acc is not None:
				pts = read_vec3(g, bin_chunk, pos_acc)
				if pts is not None:
					all_positions.extend(pts)
					prim_counts.append(len(pts))
	if not all_positions:
		print("  (no POSITION data)")
		return
	# AABB
	xs = [p[0] for p in all_positions]
	ys = [p[1] for p in all_positions]
	zs = [p[2] for p in all_positions]
	ax, ay, az = min(xs), min(ys), min(zs)
	bx, by, bz = max(xs), max(ys), max(zs)
	sx, sy, sz = bx - ax, by - ay, bz - az
	print(f"  vertex count : {len(all_positions)}")
	print(f"  primitives   : {len(prim_counts)}  (vertex counts: {prim_counts})")
	print(f"  AABB         : [{ax:.2f}, {ay:.2f}, {az:.2f}] -> [{bx:.2f}, {by:.2f}, {bz:.2f}]")
	print(f"  size         : [{sx:.2f}, {sy:.2f}, {sz:.2f}]")
	# Floating-greeble heuristic: count vertices that are more than 0.05 units
	# away from any face centroid. This isn't a real convex-hull distance
	# test, but it catches the obvious "tiny box floating in space" cases
	# because a floating box's vertices cluster well off the main body.
	# Approximation: bucket vertices into a 0.5-unit grid, count clusters
	# far from the densest cluster.
	from collections import Counter
	buckets = Counter()
	for x, y, z in all_positions:
		key = (round(x / 0.5), round(y / 0.5), round(z / 0.5))
		buckets[key] += 1
	main_cluster_size = max(buckets.values())
	isolated = sum(1 for v in buckets.values() if v <= 2)
	print(f"  densest cell : {main_cluster_size} verts ({(100 * main_cluster_size / len(all_positions)):.1f}%)")
	print(f"  isolated cells: {isolated} of {len(buckets)} (sparse / potential floating greebles)")


if __name__ == "__main__":
	targets = sys.argv[1:] or [
		# New parametric hulls (PR 2)
		r"E:\Kitbash-Command\prototype\assets\models\hulls\block_main_meridian.glb",
		r"E:\Kitbash-Command\prototype\assets\models\hulls\plate_main_tidemark.glb",
		r"E:\Kitbash-Command\prototype\assets\models\hulls\pod_main_osterholm.glb",
		r"E:\Kitbash-Command\prototype\assets\models\hulls\carrier_main_meridian.glb",
		r"E:\Kitbash-Command\prototype\assets\models\hulls\skiff_heavy_meridian.glb",
		# Legacy references (in trash)
		r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\hex_pod_hull.glb",
		r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\carapace_hull.glb",
		r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\light_hull_mod_4a3.glb",
		r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\octaplate_hull.glb",
		r"C:\Users\Chris\.mavis\trash\pr1_retire_legacy_hulls\delta_plate_hull.glb",
	]
	for t in targets:
		if not os.path.exists(t):
			print(f"\n*** MISSING: {t}")
			continue
		print(f"\n=== {os.path.basename(t)} ===")
		inspect(t)
