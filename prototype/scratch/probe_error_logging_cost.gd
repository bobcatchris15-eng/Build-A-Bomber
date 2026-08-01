extends SceneTree
# Scratch: a single global_position write costs a flat ~40ms regardless of
# sibling count and even on a detached parent (probe_global_position_cost.gd).
# No transform maths is that expensive, and the cost being FLAT rules out any
# tree-walk explanation.
#
# The tell is in the probe output itself: those writes emit
#   ERROR: Condition "!is_inside_tree()" is true. Returning: Transform3D()
# and project.godot sets:
#   [debug] file_logging/enable_file_logging=true
#   file_logging/log_path="user://godot_master.log"
#
# Hypothesis: the ~40ms is not the transform write at all - it is Godot
# writing one line to the log file (and flushing it) per emitted error. If
# so, the terrain/spawn/build-animation stalls are all "code that emits engine
# errors in a loop", and the errors are the cost, not the work.
#
# This times: a silent operation, an operation that emits one engine error,
# and an explicit push_error - then reports the per-error delta.
#
# Usage: ./Godot_v4.3-stable_win64_console.exe --script scratch/probe_error_logging_cost.gd --path .

const N := 20

func _init():
	var log_path: String = ProjectSettings.get_setting("debug/file_logging/log_path", "<unset>")
	print("file_logging enabled : %s" % ProjectSettings.get_setting("debug/file_logging/enable_file_logging", false))
	print("log_path             : %s" % log_path)
	var abs_log := ProjectSettings.globalize_path(log_path)
	print("log size before      : %d bytes" % _file_size(abs_log))
	print("")

	# Detached node: reading/writing global_position emits an engine error.
	var detached = Node3D.new()
	var child = Node3D.new()
	detached.add_child(child)

	var t := Time.get_ticks_usec()
	for i in range(N):
		child.position = Vector3(1, 2, 3)
	print("  %-32s %9.3f ms / %d = %8.4f ms each" % ["position (no error emitted)", (Time.get_ticks_usec() - t) / 1000.0, N, (Time.get_ticks_usec() - t) / 1000.0 / N])

	t = Time.get_ticks_usec()
	for i in range(N):
		child.global_position = Vector3(1, 2, 3)
	var per_err := (Time.get_ticks_usec() - t) / 1000.0 / N
	print("  %-32s %9.3f ms / %d = %8.4f ms each" % ["global_position (1 error each)", (Time.get_ticks_usec() - t) / 1000.0, N, per_err])

	t = Time.get_ticks_usec()
	for i in range(N):
		push_error("probe: deliberate error %d" % i)
	print("  %-32s %9.3f ms / %d = %8.4f ms each" % ["push_error()", (Time.get_ticks_usec() - t) / 1000.0, N, (Time.get_ticks_usec() - t) / 1000.0 / N])

	t = Time.get_ticks_usec()
	for i in range(N):
		print_verbose("probe: plain print %d" % i)
	print("  %-32s %9.3f ms / %d = %8.4f ms each" % ["print_verbose()", (Time.get_ticks_usec() - t) / 1000.0, N, (Time.get_ticks_usec() - t) / 1000.0 / N])

	print("")
	print("log size after       : %d bytes" % _file_size(abs_log))
	detached.free()
	quit(0)

func _file_size(p: String) -> int:
	var f = FileAccess.open(p, FileAccess.READ)
	if not f:
		return -1
	var s = f.get_length()
	f.close()
	return s
