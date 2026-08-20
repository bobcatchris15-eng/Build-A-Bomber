extends SceneTree
# SKIRMISH_PERF_TROUBLESHOOTING.md §5 Track E, §12.
#
# Reads the current render settings and reports what would change under each
# of the four Track E sweeps. Does NOT modify any file; the intent is for the
# user to apply the changes in the Godot editor or by hand-editing
# project.godot, and re-run the playtest.
#
# Usage:
#   Godot --headless --script tools/probe_track_e.gd
#
# The probe is read-only. It is the "what do I need to flip" companion to
# the perf_hud's "what is currently set" read in-match.

const MSAA := {"0": "off", "1": "2x", "2": "4x", "3": "8x"}


func _init() -> void:
	print("=== Track E current settings ===\n")
	var config := ConfigFile.new()
	var err := config.load("res://project.godot")
	if err != OK:
		print("could not load res://project.godot (err=%d)" % err)
		quit(1)
		return

	# MSAA 3D (rendering section).
	var msaa_val: int = int(config.get_value("rendering", "anti_aliasing/quality/msaa_3d", 1))
	var msaa_str: String = "%d (%s)" % [msaa_val, MSAA.get(str(msaa_val), "?")]
	print("  anti_aliasing/quality/msaa_3d")
	print("    current:    %s" % msaa_str)
	print("    track E:    0 (off). 4x->2x already shipped, 2x->off is the next step")
	print("")

	# 3D scaling (rendering section).
	var scale_val: float = float(config.get_value("rendering", "rendering/scaling_3d/scale", 1.0))
	print("  rendering/scaling_3d/scale")
	print("    current:    %.2f" % scale_val)
	print("    track E:    0.75 - separates fill cost from geometry cost")
	print("")

	# Window vsync (display section, Godot 4.7 stores it on the window
	# resource, not [application]).
	var vsync_val: int = int(config.get_value("display", "window/vsync/vsync_mode", 1))
	var vsync_str: String = ["disabled", "enabled", "adaptive"][vsync_val] if vsync_val < 3 else "?"
	print("  display/window/vsync/vsync_mode")
	print("    current:    %d (%s)" % [vsync_val, vsync_str])
	print("    track E:    0 (disabled) - to see true frame time, not the 60 Hz cap")
	print("")

	# Light cap (node-level @export on the LightCap node in Battle.tscn).
	var light_cap_max := 16
	var light_cap_bypass := false
	var scene_path := "res://scenes/Battle.tscn"
	if FileAccess.file_exists(scene_path):
		var packed: PackedScene = load(scene_path)
		if packed != null:
			var inst := packed.instantiate()
			if inst != null:
				var lc := inst.get_node_or_null("LightCap")
				if lc != null:
					light_cap_max = int(lc.max_lights)
					light_cap_bypass = bool(lc.bypass)
				inst.free()
	print("  scripts/light_cap.gd (LightCap node on Battle)")
	print("    current:    max_lights=%d bypass=%s" % [light_cap_max, str(light_cap_bypass)])
	print("    track E:    max_lights=0 to confirm lighting is the cost. 16 is the baseline.")
	print("")
	print("=== Run a playtest, then probe_track_e to confirm what shipped ===")
	quit(0)
