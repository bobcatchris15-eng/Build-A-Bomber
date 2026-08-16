extends SceneTree
# Reads a battle log and prints a perf-investigation report.
# Usage: Godot --headless --script tools/analyze_perf_log.gd -- <log_path>

const LOG_PATH := "res://../logs/"  # placeholder, real one passed via arg

var _events: Array = []
var _section_totals: Dictionary = {}
var _section_max: Dictionary = {}
var _section_count: Dictionary = {}
var _hitches: Array = []
var _spawns: Array = []
var _structure_built: Array = []


func _init():
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("Usage: -- <log_path>")
		quit(1)
		return
	_load(args[0])
	_report()
	quit(0)


func _load(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("could not open %s" % path)
		quit(1)
		return
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed == null:
			continue
		_events.append(parsed)
	f.close()


func _report() -> void:
	# Section totals from the section events (one record per (frame, section, us)).
	for e in _events:
		match e.get("event", ""):
			"section":
				var name: String = e.get("name", "?")
				var us: int = int(e.get("us", 0))
				_section_totals[name] = int(_section_totals.get(name, 0)) + us
				_section_max[name] = maxi(int(_section_max.get(name, 0)), us)
				_section_count[name] = int(_section_count.get(name, 0)) + 1
			"hitch":
				_hitches.append(e)
			"unit_spawn":
				_spawns.append(e)
			"structure_built":
				_structure_built.append(e)

	# Per-section: total ms, mean ms, max ms.
	print("=== SECTIONS (sorted by total ms) ===")
	print("%-26s %12s %10s %10s %8s" % ["section", "total ms", "mean ms", "max ms", "frames"])
	var section_rows: Array = []
	for name in _section_totals:
		var total: int = _section_totals[name]
		var max_us: int = _section_max[name]
		var count: int = _section_count[name]
		section_rows.append({
			"name": name,
			"total_ms": float(total) / 1000.0,
			"mean_ms": float(total) / float(maxi(1, count)) / 1000.0,
			"max_ms": float(max_us) / 1000.0,
			"count": count,
		})
	section_rows.sort_custom(func(a, b): return a["total_ms"] > b["total_ms"])
	for r in section_rows:
		print("%-26s %12.1f %10.3f %10.2f %8d"
			% [r["name"], r["total_ms"], r["mean_ms"], r["max_ms"], r["count"]])

	# Hitch distribution: count by dominant, with the worst in each bucket.
	print("")
	print("=== HITCHES (frames >= 100ms) BY DOMINANT SECTION ===")
	var by_dominant: Dictionary = {}
	for h in _hitches:
		var d: String = h.get("dominant", "<untimed>")
		by_dominant[d] = by_dominant.get(d, 0) + 1
	var dom_rows: Array = []
	for d in by_dominant:
		dom_rows.append([d, by_dominant[d]])
	dom_rows.sort_custom(func(a, b): return a[1] > b[1])
	for r in dom_rows:
		print("  %-22s %5d" % [r[0], r[1]])

	# Top 20 worst hitches in detail.
	print("")
	print("=== TOP 20 WORST HITCHES (by frame_ms) ===")
	_hitches.sort_custom(func(a, b): return float(a.get("frame_ms", 0)) > float(b.get("frame_ms", 0)))
	for i in range(mini(20, _hitches.size())):
		var h = _hitches[i]
		print("  frame %5d  %7.1f ms  dom=%-14s dom_ms=%7.1f  units=%s structs=%s miss=%s"
			% [h.get("frame", -1), float(h.get("frame_ms", 0)),
				h.get("dominant", "<untimed>"), float(h.get("dominant_ms", 0)),
				h.get("units_alive", "?"), h.get("structures_alive", "?"),
				h.get("missiles_alive", "?")])

	# Spawns / structures - which frames did they happen.
	print("")
	print("=== UNIT SPAWNS (frame, name, kind) ===")
	for s in _spawns:
		print("  frame %5d  team=%d  name=%-30s  kind=%s"
			% [s.get("frame", -1), int(s.get("team", -1)),
				s.get("name", "?"), s.get("kind", "?")])
	print("")
	print("=== STRUCTURES BUILT: %d total ===" % _structure_built.size())
	# Group by frame-of-build into 10-frame buckets to see if there's a burst.
	var bucket: Dictionary = {}
	for s in _structure_built:
		var fr: int = int(s.get("frame", 0))
		var b: int = fr / 30
		bucket[b] = bucket.get(b, 0) + 1
	var b_rows: Array = []
	for b in bucket:
		b_rows.append([b, bucket[b]])
	b_rows.sort_custom(func(a, b2): return a[0] < b2[0])
	for r in b_rows:
		print("  frame %4d-%4d  count=%d" % [r[0] * 30, r[0] * 30 + 29, r[1]])

	# Find the FRAME with the maximum "untimed gap" = frame_ms - sum_of_sections.
	# For this, I need to group sections by frame and pair with hitches.
	print("")
	print("=== UNTIMED GAP ANALYSIS (worst 15 frames where frame_ms - section_sum is largest) ===")
	var per_frame_sections: Dictionary = {}
	for e in _events:
		if e.get("event", "") == "section":
			var fr: int = int(e.get("frame", 0))
			per_frame_sections[fr] = int(per_frame_sections.get(fr, 0)) + int(e.get("us", 0))
	var gap_rows: Array = []
	for h in _hitches:
		var fr: int = int(h.get("frame", -1))
		if fr < 0:
			continue
		var section_us: int = int(per_frame_sections.get(fr, 0))
		var frame_us: int = int(float(h.get("frame_ms", 0)) * 1000.0)
		var gap: int = frame_us - section_us
		gap_rows.append([fr, float(h.get("frame_ms", 0)), section_us / 1000.0, gap / 1000.0])
	gap_rows.sort_custom(func(a, b2): return a[3] > b2[3])
	for i in range(mini(15, gap_rows.size())):
		var r = gap_rows[i]
		print("  frame %5d  total=%7.1f ms  section_sum=%7.1f ms  untimed_gap=%7.1f ms"
			% [r[0], r[1], r[2], r[3]])

	# Find frames where the unit section was huge, and cross with hitch events.
	print("")
	print("=== FRAMES WHERE unit.move_and_slide EXCEEDED 20ms (top 15) ===")
	var move_slide: Array = []
	for e in _events:
		if e.get("event", "") == "section" and e.get("name", "") == "unit.move_and_slide":
			var us: int = int(e.get("us", 0))
			if us > 20000:
				move_slide.append([int(e.get("frame", 0)), us / 1000.0])
	move_slide.sort_custom(func(a, b2): return a[1] > b2[1])
	for r in move_slide.slice(0, mini(15, move_slide.size())):
		print("  frame %5d  %7.2f ms" % [r[0], r[1]])

	print("")
	print("=== FRAMES WHERE units (whole section) EXCEEDED 30ms (top 15) ===")
	var units_section: Array = []
	for e in _events:
		if e.get("event", "") == "section" and e.get("name", "") == "units":
			var us: int = int(e.get("us", 0))
			if us > 30000:
				units_section.append([int(e.get("frame", 0)), us / 1000.0])
	units_section.sort_custom(func(a, b2): return a[1] > b2[1])
	for r in units_section.slice(0, mini(15, units_section.size())):
		print("  frame %5d  %7.2f ms" % [r[0], r[1]])

	# Map of frame -> units_alive (from hitch events only).
	print("")
	print("=== UNITS_ALIVE PROGRESSION (from hitch log snapshots) ===")
	var unit_progression: Array = []
	for h in _hitches:
		unit_progression.append([int(h.get("frame", -1)),
			h.get("units_alive", -1),
			h.get("structures_alive", -1)])
	unit_progression.sort_custom(func(a, b2): return a[0] < b2[0])
	var last: Array = []
	for r in unit_progression:
		if last.is_empty() or r[1] != last[last.size() - 1][1] or r[2] != last[last.size() - 1][2]:
			last.append(r)
	for r in last:
		print("  frame %5d  units=%s  structs=%s" % [r[0], r[1], r[2]])
