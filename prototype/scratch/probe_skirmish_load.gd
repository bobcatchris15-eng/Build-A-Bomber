extends SceneTree
# Scratch: where does the skirmish load actually spend its time?
#
# The freeze is being fixed by moving work off the main thread's critical
# path, but WHICH work matters: if the cost is in ResourceLoader, threaded
# loading solves it; if it's in Skirmish._ready() (terrain, navmesh bake,
# roster reconstruction), threaded resource loading changes nothing at all,
# because instantiation and _ready() run on the main thread regardless.
#
# Times the two halves separately, then the phases inside _ready() by
# monkey-timing the whole instantiate.

func _init():
	var t_all := Time.get_ticks_msec()

	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load("res://scenes/Skirmish.tscn")
	var t_load := Time.get_ticks_msec() - t0

	# Give it a map so it does representative work.
	var mc = root.get_node_or_null("MatchConfig")
	if mc and "selected_map_id" in mc:
		mc.selected_map_id = "lake_crossing"

	t0 = Time.get_ticks_msec()
	var inst = packed.instantiate()
	var t_inst := Time.get_ticks_msec() - t0

	# add_child is what actually fires _ready().
	t0 = Time.get_ticks_msec()
	root.add_child(inst)
	var t_ready := Time.get_ticks_msec() - t0

	print("ResourceLoader load() : %5d ms" % t_load)
	print("instantiate()         : %5d ms" % t_inst)
	print("add_child() -> _ready(): %5d ms   <-- blocks the main thread" % t_ready)
	print("TOTAL                 : %5d ms" % (Time.get_ticks_msec() - t_all))
	print("")
	print("If _ready() dominates, threaded ResourceLoader is the WRONG fix -")
	print("the work has to be split across frames or moved to a worker.")
	quit(0)
