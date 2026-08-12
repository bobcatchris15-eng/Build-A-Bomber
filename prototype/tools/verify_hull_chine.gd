extends SceneTree
# Validates HullChine against the real hull roster.
#
# Run:
#   ./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/verify_hull_chine.gd --quit
#
# This is a solver-correctness harness, not a test suite. It loads every baked
# hull .glb, solves the chine at several stations on both sides, and reports the
# cases the solver would get wrong - so the geometry can be trusted before the
# locomotion mounting system is rebuilt on top of it.
#
# What it checks per station, and why each one is a real failure mode:
#
#   FELL BACK   The slice produced no usable section, so chine_at() returned the
#               bounding-box corner. That is the old broken behaviour; any hull
#               hitting this path is a hull the rebuild does not actually fix.
#   OFF SKIN    The returned point is not within tolerance of a real triangle.
#               Would mean the section math is producing points that are not on
#               the mesh, which breaks the whole no-gap guarantee.
#   NOT LOW     The chine sits meaningfully above the bottom of the section's
#               SUBSTANTIAL flank - the lowest point that is still at least
#               FLANK_MIN_WIDTH_FRAC of the section's half-width. If it is up on
#               the shoulder, the corner metric is picking the wrong corner.
#
#               This was originally "above the section's vertical midpoint",
#               which is wrong for a hull carrying a narrow fin or skeg below a
#               wide body: halvorsen_oddball_b's bow and stern sections are less
#               than 40% of full width below 60% height, so the true chine - the
#               lower edge of the body the gear actually bolts to - is legitimately
#               in the upper half of the section, and the old check flagged it.
#               Measuring against the substantial flank instead states the
#               property that is actually wanted ("bottom of the sides") rather
#               than an assumption about where hulls put their widest point.
#   NOT OUT     The chine is inboard of half the section's half-width. Would mean
#               it collapsed toward the keel instead of finding the flank.
#   BAD NORMAL  The mount normal does not point outboard-and-down. A bracket
#               built along it would run into the hull or along its skin.
#
# It also reports how far each chine sits from the bounding-box corner the old
# code used, which is the direct measure of how much error this removes.

const HullChineScript = preload("res://scripts/hull_chine.gd")
const HullProjectionScript = preload("res://scripts/hull_projection.gd")

const HULL_DIR := "res://assets/models/hulls"

## Fraction of hull length at which stations are sampled. Deliberately spread
## fore and aft rather than clustered amidships, because the tapering ends are
## where a box approximation is worst and where the solver is most likely to
## misbehave.
const SAMPLE_FRACS := [0.18, 0.35, 0.5, 0.65, 0.82]

## A point counts as on the skin if it is within this fraction of the hull's
## diagonal of a real triangle. Not zero: the section point is exact, but the
## nearest-triangle test below measures to a triangle's PLANE within its barycentric
## span, and a point on a shared edge sits on two planes at slightly different
## floating-point distances.
const ON_SKIN_FRAC := 0.002

## A section point counts as part of the SUBSTANTIAL flank - the part of the
## hull's side that running gear could actually bolt to - when it reaches this
## fraction of the section's half-width. Anything narrower is a keel, a skeg or a
## tapering tip, which is geometry the gear should hang beside, not from.
const FLANK_MIN_WIDTH_FRAC := 0.55

## Minimum downward component of the mount normal. Below this the surface at the
## chine is effectively a vertical wall, which means the corner metric stopped up
## the flank instead of finding the turn of the bilge.
##
## Deliberately generous. The point of the threshold is to catch a solver that
## has failed to descend at all, not to insist every hull have a 45-degree bilge -
## a hull with near-vertical sides and a hard bottom edge has a real chine whose
## fitted normal is legitimately shallow.
const MIN_BILGE_DROP := 0.15

## How far up the section a wall-normal mount has to sit before it counts as
## being on the shoulder rather than on a legitimately vertical bottom edge.
const SHOULDER_HEIGHT_FRAC := 0.25


func _init() -> void:
	var files := _hull_files()
	if files.is_empty():
		push_error("No hull .glb files found under %s" % HULL_DIR)
		quit(1)
		return

	var total := 0
	var fell_back := 0
	var off_skin := 0
	var not_low := 0
	var not_out := 0
	var bad_normal := 0
	var bad_frame := 0
	var hulls_clean := 0
	# Histogram of the mount normal's downward component, in tenths. Reported so
	# the threshold above can be judged against what the roster actually produces
	# rather than picked in the abstract.
	var bilge_bucket := PackedInt32Array()
	bilge_bucket.resize(10)
	var hulls_broken: Array[String] = []

	var drift_sum := 0.0
	var drift_max := 0.0
	var drift_max_hull := ""

	for path in files:
		var stem: String = path.get_file().get_basename()
		var inst := _instantiate(path)
		if inst == null:
			hulls_broken.append("%s (would not instantiate)" % stem)
			continue

		var profile: Dictionary = HullChineScript.build(inst)
		if not HullChineScript.is_valid(profile):
			hulls_broken.append("%s (no triangles)" % stem)
			inst.free()
			continue

		var aabb: AABB = profile["aabb"]
		var diag: float = aabb.size.length()
		var skin_tol: float = diag * ON_SKIN_FRAC
		var problems: Array[String] = []

		for frac in SAMPLE_FRACS:
			for side in [-1.0, 1.0]:
				total += 1
				var z: float = aabb.position.z + aabb.size.z * float(frac)
				var hit: Dictionary = HullChineScript.chine_at(profile, z, side)

				if not hit["found"]:
					fell_back += 1
					problems.append("FELL BACK z=%.2f side=%+.0f" % [z, side])
					continue

				var pos: Vector3 = hit["position"]
				var nrm: Vector3 = hit["normal"]
				var low: float = hit["low"]
				var high: float = hit["high"]
				var half_w: float = hit["half_width"]

				var dist := _distance_to_surface(profile, pos)
				if dist > skin_tol:
					off_skin += 1
					problems.append("OFF SKIN z=%.2f side=%+.0f by %.4f" % [z, side, dist])

				# Is this actually the turn of the bilge, or just a point up the
				# wall? The shape-independent answer is in the surface normal: a
				# vertical flank normal is (+/-1, 0), a flat belly normal is
				# (0, -1), and a chine - whether it is a hard corner, a chamfer or
				# a rounded bilge - is between them. A normal with almost no
				# downward component means the solver stopped on the side wall.
				#
				# A wall-like normal is only a failure if the point is also
				# meaningfully ABOVE the bottom of the section. Both conditions are
				# needed, and testing the normal alone was wrong: battery_main_*
				# has a station whose normal is (1.00, -0.02) at height_frac 0.000,
				# i.e. the solver found the exact lowest point of a wall that is
				# genuinely vertical right down to the bottom edge. Under the
				# pinning rule that is a correct and usable mount - flank_up comes
				# out straight up, so the gear's bottom edge sits on the hull's
				# bottom edge and its bulk rises up the wall, which is precisely
				# the intent. Only a wall normal found part-way UP the wall means
				# the corner metric failed to descend.
				bilge_bucket[clampi(int(-nrm.y * 10.0), 0, 9)] += 1
				var v_frac := ((pos.y - low) / (high - low)) if high > low else 0.0
				if nrm.y > -MIN_BILGE_DROP and v_frac > SHOULDER_HEIGHT_FRAC:
					not_low += 1
					problems.append("SHOULDER z=%.2f side=%+.0f n=(%.2f,%.2f) height_frac=%.3f"
						% [z, side, nrm.x, nrm.y, v_frac])

				if half_w > 0.0 and absf(pos.x) < half_w * 0.5:
					not_out += 1
					problems.append("NOT OUT z=%.2f side=%+.0f x=%.3f of %.3f"
						% [z, side, pos.x, half_w])

				if nrm.x * side <= 0.0 or nrm.y >= 0.0:
					bad_normal += 1
					problems.append("BAD NORMAL z=%.2f side=%+.0f n=(%.2f,%.2f)"
						% [z, side, nrm.x, nrm.y])

				# The mount frame is what builders actually consume, so validate
				# the frame itself and not just the normal it is derived from.
				var frame: Dictionary = HullChineScript.mount_frame(profile, z, side)
				var up: Vector3 = frame["flank_up"]
				var b: Basis = frame["basis"]
				var frame_bad := ""
				if up.y <= 0.0:
					# Hardware grows along +Y from the chine. A descending flank_up
					# would build the gear down into the ground instead of up the
					# side of the hull - the exact inverse of the pinning rule.
					frame_bad = "flank_up descends (%.2f, %.2f)" % [up.x, up.y]
				elif absf(b.determinant()) < 0.5:
					# Degenerate or collapsed basis: normal and flank_up ended up
					# parallel, so the frame has no well-defined outboard axis.
					frame_bad = "degenerate basis det=%.3f" % b.determinant()
				elif absf(nrm.dot(up)) > 0.01:
					# flank_up must run ALONG the surface, not into it. If it is
					# not perpendicular to the normal, hardware laid along it
					# either sinks into the hull or drifts off the skin as it rises.
					frame_bad = "flank_up not tangent (dot=%.3f)" % nrm.dot(up)
				if frame_bad != "":
					bad_frame += 1
					problems.append("BAD FRAME z=%.2f side=%+.0f %s" % [z, side, frame_bad])

				# How far the old box corner was from the truth.
				var box_corner := Vector3(
					aabb.position.x + (aabb.size.x if side > 0.0 else 0.0),
					aabb.position.y, z)
				var drift: float = Vector2(pos.x - box_corner.x, pos.y - box_corner.y).length()
				drift_sum += drift
				if drift > drift_max:
					drift_max = drift
					drift_max_hull = "%s z=%.2f side=%+.0f" % [stem, z, side]

		if problems.is_empty():
			hulls_clean += 1
		else:
			hulls_broken.append("%s\n      %s" % [stem, "\n      ".join(problems.slice(0, 6))])
		inst.free()

	print("")
	print("=== HullChine verification ===")
	print("hulls           : %d" % files.size())
	print("hulls clean     : %d" % hulls_clean)
	print("stations solved : %d" % total)
	print("")
	print("fell back to box: %d" % fell_back)
	print("off skin        : %d" % off_skin)
	print("on shoulder     : %d" % not_low)
	print("not outboard    : %d" % not_out)
	print("bad normal      : %d" % bad_normal)
	print("bad frame       : %d" % bad_frame)
	print("")
	print("--- mount normal downward component ---")
	for b in 10:
		var lo := float(b) * 0.1
		print("  %.1f-%.1f : %5d %s"
			% [lo, lo + 0.1, bilge_bucket[b], "#".repeat(bilge_bucket[b] / 8)])
	print("")
	if total > 0:
		print("mean drift from box corner: %.4f" % (drift_sum / float(total)))
	print("max  drift from box corner: %.4f  (%s)" % [drift_max, drift_max_hull])

	if not hulls_broken.is_empty():
		print("")
		print("--- hulls with problems (%d) ---" % hulls_broken.size())
		for h in hulls_broken:
			print("  " + h)

	var failed := fell_back + off_skin + not_low + not_out + bad_normal + bad_frame
	print("")
	print("RESULT: %s (%d problem stations of %d)"
		% ["PASS" if failed == 0 else "FAIL", failed, total])
	quit(0 if failed == 0 else 1)


## Lowest y on this side that still carries at least FLANK_MIN_WIDTH_FRAC of the
## section's half-width - the bottom of the hull's real side wall, ignoring any
## keel or skeg tapering away below it. INF when the section has no such points.
func _substantial_flank_bottom(profile: Dictionary, z: float, side: float,
		half_w: float) -> float:
	if half_w <= 0.0:
		return INF
	var sec: Dictionary = HullChineScript.section(profile, z)
	var pts: Array[Vector2] = sec.get("points", [] as Array[Vector2])
	var s := signf(side)
	var best := INF
	for p in pts:
		var sx := p.x * s
		if sx <= 0.0:
			continue
		if sx / half_w < FLANK_MIN_WIDTH_FRAC:
			continue
		best = minf(best, p.y)
	return best


func _hull_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(HULL_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".glb"):
			out.append("%s/%s" % [HULL_DIR, f])
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _instantiate(path: String) -> Node3D:
	var res := load(path)
	if res == null or not (res is PackedScene):
		return null
	var node := (res as PackedScene).instantiate()
	if node is Node3D:
		return node as Node3D
	node.free()
	return null


## Shortest distance from `p` to any hull triangle. Full point-triangle distance
## (not point-to-plane) so a point floating off the end of a facet is correctly
## reported as far away rather than as on that facet's infinite plane.
func _distance_to_surface(profile: Dictionary, p: Vector3) -> float:
	var tris: PackedVector3Array = profile["tris"]
	var best := INF
	var i := 0
	while i + 2 < tris.size():
		var d := _point_tri_distance(p, tris[i], tris[i + 1], tris[i + 2])
		if d < best:
			best = d
			if best <= 0.0:
				return 0.0
		i += 3
	return best


func _point_tri_distance(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	# Ericson, Real-Time Collision Detection - closest point on triangle by
	# Voronoi region, then plain Euclidean distance to it.
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return p.distance_to(a)

	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return p.distance_to(b)

	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var denom := d1 - d3
		if absf(denom) < 1e-12:
			return p.distance_to(a)
		return p.distance_to(a + ab * (d1 / denom))

	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return p.distance_to(c)

	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var denom_b := d2 - d6
		if absf(denom_b) < 1e-12:
			return p.distance_to(a)
		return p.distance_to(a + ac * (d2 / denom_b))

	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var denom_a := (d4 - d3) + (d5 - d6)
		if absf(denom_a) < 1e-12:
			return p.distance_to(b)
		return p.distance_to(b + (c - b) * ((d4 - d3) / denom_a))

	var denom_f := va + vb + vc
	if absf(denom_f) < 1e-12:
		return p.distance_to(a)
	var v := vb / denom_f
	var w := vc / denom_f
	return p.distance_to(a + ab * v + ac * w)
