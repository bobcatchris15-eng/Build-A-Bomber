extends SceneTree
# Builds the default roster THROUGH THE REAL PLACEMENT PIPELINE.
#
# Replaces tools/generate_default_roster.gd, which is retired. That one built a
# bare StaticBody3D with a BoxShape3D and put every weapon at
# `y = box.size.y / 2.0`. A hull's visible body is an SDF/marching-cubes mesh that
# slopes and dips, so the box top is above the real surface almost everywhere -
# weapons floated and treads read as detached. Measured against a Lab-authored
# design on landing_craft_hull (box half-height 1.20), three parts all on facet
# "top" sat at y = 0.60, 0.05 and 0.00.
#
# WHAT THIS DOES DIFFERENTLY - and it is the whole difference:
#
#   1. Builds the hull with placer._place_hull_from_ui(), the same call the Design
#      Lab uses. That is what creates the PhysicsMesh and the precise surface
#      collision body; the old generator explicitly bypassed it ("Force place hull
#      manually to bypass UI-specific things") and so had no surface to hit.
#   2. Finds each mount point with placer.surface_raycast(), whose own comment says
#      it "traces the precise hull surface first and only falls back to the
#      bounding box if that misses, so a dropped module sits on the hull you can
#      see rather than on its bounding shell". This script only chooses (x, z);
#      the hull decides y and the surface normal.
#   3. Places locomotion with placer.update_locomotion(), so stations come from
#      locomotion_layout.gd per hull rather than from a hardcoded table.
#
# Everything derived - stats, weights, costs, per-module tweaks, kit anchors,
# assembly scales - therefore comes from the real code. Nothing here fabricates a
# number that the catalog or the placer owns.
#
# LAYOUT CONVENTIONS, taken from Chris's three hand-authored designs:
#   * Weapons in symmetric pairs at +/-x where the role allows it.
#   * Main armament forward of centre, support and launchers aft.
#   * Designations are alphanumeric and faintly absurd - "ScrubMarshal No. 33",
#     "SpadeRammer Mk XII", "MarshSled M86".
#   * industrialists / hardened_steel unless a design has a reason to differ.
#
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/author_default_roster.gd

const OUT_DIR := "res://assets/blueprints/default_roster/"

# `mounts` are (x, z) only. y and the normal come from the hull surface.
const ROSTER := [
	{
		"name": "GravelGulper No. 7",
		"role": "resource gathering",
		"hull": "block_main_meridian_a",
		"loco": "wheels",
		# num_axles is TOTAL WHEEL STATIONS, not axle pairs: locomotion_layout.gd's
		# wheels spec is SIDE_PAIRS, so 8 gives four stations a side. It is also the
		# Lab's slider maximum, which suits a hauler. The spec sets count_even, so an
		# odd value silently snaps down - and the Lab's MINIMUM is 4, so anything
		# below that is a design the player could not build.
		"loco_settings": {"wheel_size": 1.1, "num_axles": 8, "wheels_per_axle": 2},
		"armor": "hardened_steel", "thickness": 0.8,
		"mounts": [
			# The extractor sits amidships over the load bed; a harvester is
			# defined by carrying one at all (battle_unit.gd sets is_harvester
			# from this type_id), so there is exactly one.
			{"type": "resource_harvester", "x": 0.0, "z": 0.4},
			{"type": "sensor_suite", "x": 0.0, "z": -1.9},
			{"type": "heavy_machine_gun", "x": 0.9, "z": -1.2},
		],
	},
	{
		"name": "PatchWagon Mk IV",
		"role": "field repair",
		"hull": "block_main_meridian_a",
		"loco": "wheels",
		"loco_settings": {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 2},
		"armor": "hardened_steel", "thickness": 1.0,
		"mounts": [
			{"type": "repair_array", "x": 0.0, "z": 0.6},
			{"type": "smoke_discharger", "x": -1.0, "z": -1.6},
			{"type": "smoke_discharger", "x": 1.0, "z": -1.6},
		],
	},
	{
		"name": "BogHammer M60",
		"role": "main battle tank",
		"hull": "block_heavy_meridian_a",
		"loco": "tracked_treads",
		"loco_settings": {"tread_width": 1.6},
		"armor": "hardened_steel", "thickness": 1.4,
		"mounts": [
			# Main gun forward of centre, per the convention in Chris's designs.
			# barrel_count 3 is inside basic_cannon's own tweak range (1-4), so the
			# Lab can reproduce it on its Barrel Count slider.
			{"type": "basic_cannon", "x": 0.0, "z": -1.0,
				"tweaks": {"barrel_count": 3.0, "caliber": 1.2, "barrel_length": 1.3}},
			# The gatling. rotary_cannon is the multi-barrel rotary in this catalog;
			# its own barrel_count runs 3-9 and defaults to 6, which is left alone.
			{"type": "rotary_cannon", "x": 1.1, "z": 0.9},
			# Close-in weapon system, aft on the opposite flank so the two support
			# mounts cover different quarters instead of stacking.
			{"type": "ciws", "x": -1.1, "z": 0.9},
		],
	},
	{
		"name": "SkySwatter No. 9",
		"role": "anti-air",
		"hull": "block_scout_meridian_a",
		"loco": "wheels",
		# 4, not 2. Two stations is ONE axle - a vehicle balanced on a single pair of
		# wheels - and it is below stat_calculator.gd's count_slider.min_value of 4,
		# so the Lab could not produce or even represent it.
		"loco_settings": {"wheel_size": 1.0, "num_axles": 4, "wheels_per_axle": 2},
		"armor": "hardened_steel", "thickness": 0.9,
		"mounts": [
			{"type": "aa_autocannon", "x": -0.6, "z": 0.3},
			{"type": "aa_autocannon", "x": 0.6, "z": 0.3},
			{"type": "sensor_suite", "x": 0.0, "z": -1.2},
		],
	},
	{
		"name": "LobToad M77",
		"role": "artillery",
		"hull": "block_main_meridian_a",
		"loco": "tracked_treads",
		"loco_settings": {"tread_width": 1.3},
		"armor": "hardened_steel", "thickness": 1.1,
		"mounts": [
			{"type": "mortar_array", "x": -0.9, "z": 1.1},
			{"type": "mortar_array", "x": 0.9, "z": 1.1},
			{"type": "sensor_suite", "x": 0.0, "z": -1.7},
		],
	},
	{
		"name": "PeepSnipe M12",
		"role": "recon",
		"hull": "wedge_scout_meridian_a",
		"loco": "rocker_bogie",
		"loco_settings": {},
		"armor": "hardened_steel", "thickness": 0.6,
		"mounts": [
			{"type": "sensor_suite", "x": 0.0, "z": 0.7},
			{"type": "coil_gun", "x": 0.0, "z": -0.7},
		],
	},
]


func _init():
	var ModulePlacerScript = load("res://scripts/module_placer.gd")
	var BlueprintManagerScript = load("res://scripts/blueprint_manager.gd")

	var world := Node3D.new()
	root.add_child(world)

	var placer = ModulePlacerScript.new()
	world.add_child(placer)
	var bm = BlueprintManagerScript.new()
	world.add_child(bm)

	var written := 0
	var failed := 0

	for spec in ROSTER:
		var name := str(spec["name"])
		var id := "bp_default_" + name.to_lower().replace(" ", "_").replace(".", "").replace("-", "_")
		print("\nauthoring %s (%s)" % [name, spec["role"]])

		placer.clear_hull()
		# The REAL hull path - builds the PhysicsMesh and the precise surface body.
		placer._place_hull_from_ui(str(spec["hull"]))
		if placer.hull == null:
			print("  [FAIL] hull %s did not place" % spec["hull"])
			failed += 1
			continue

		placer.hull.set_meta("armor_material", str(spec["armor"]))
		placer.hull.set_meta("armor_thickness", float(spec["thickness"]))
		placer.hull.set_meta("faction", "industrialists")
		placer.hull.set_meta("blueprint_id", id)
		placer.hull.set_meta("blueprint_name", name)
		if placer.has_method("update_hull_appearance"):
			placer.update_hull_appearance()

		# Two physics frames before any raycast: the surface collision body was
		# only just added, and PhysicsServer does not know about it until it has
		# stepped. Raycasting immediately returns nothing and silently falls back
		# to the bounding box - which is the exact failure this script exists to
		# avoid, so it would fail invisibly.
		await physics_frame
		await physics_frame

		placer.update_locomotion(str(spec["loco"]), spec["loco_settings"])
		await physics_frame

		var hull_size: Vector3 = placer.hull.get_meta("base_hull_size", Vector3.ONE)
		var placed := 0
		for mount in spec["mounts"]:
			var mx := float(mount["x"])
			var mz := float(mount["z"])
			# Straight down from clear of the hull, onto whatever surface is there.
			var origin: Vector3 = placer.hull.global_position \
				+ Vector3(mx, hull_size.y * 2.0 + 4.0, mz)
			var hit = placer.surface_raycast(origin, Vector3.DOWN, 1000.0)
			if hit.is_empty():
				print("  [FAIL] %s: no surface under (%.2f, %.2f)" % [mount["type"], mx, mz])
				failed += 1
				continue
			# Per-mount tweaks go through the placer's own tweaks argument, so the
			# module's stats, mesh and cost are all derived from them by the real
			# code. Every value used here is inside that weapon's own declared
			# tweak range in stat_calculator.gd's TWEAK_SPECS, which is what makes
			# the design reproducible on the Lab's sliders.
			var mount_tweaks: Dictionary = mount.get("tweaks", {})
			var node = placer._place_weapon(
				str(mount["type"]), hit["position"], hit["normal"], false, mount_tweaks)
			if node == null:
				print("  [FAIL] %s: placement refused at (%.2f, %.2f) - clipping?"
					% [mount["type"], mx, mz])
				failed += 1
				continue
			placed += 1
			print("    %-20s -> y=%.3f facet=%s" % [
				mount["type"], node.position.y, str(node.get_meta("facet", "?"))])
			await physics_frame

		var data: Dictionary = bm.serialize_hull(placer.hull)
		data["id"] = id
		data["name"] = name

		var f = FileAccess.open(OUT_DIR + id + ".json", FileAccess.WRITE)
		if f == null:
			print("  [FAIL] could not write %s" % id)
			failed += 1
			continue
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		written += 1
		print("  wrote %s.json (%d modules placed)" % [id, placed])

	print("\n%d written, %d failure(s)." % [written, failed])
	quit(0 if failed == 0 else 1)
