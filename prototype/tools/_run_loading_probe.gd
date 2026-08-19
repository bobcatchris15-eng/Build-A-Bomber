extends SceneTree
# One-shot driver for probe_loading_screen_interface.gd.
const Probe = preload("res://tools/probe_loading_screen_interface.gd")


func _init() -> void:
	var probe: Node = Probe.new()
	root.add_child(probe)
	# Generous frame count: the loading screen's _ready awaits two
	# process_frame ticks before calling run_load(); run_load then
	# walks the warm list and ends up awaiting deploy_requested, which
	# never fires in this minimal harness. 30 frames is enough to
	# settle the contracts that don't depend on world_ready (the
	# Control check, process_mode, method presence, signal shape,
	# DEPLOY button presence, LoadingPreview self-instantiation).
	for _i in range(30):
		await process_frame
	quit(0)
