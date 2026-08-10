extends Node
# Autoload singleton (RTS_CORE_ROADMAP.md A2): dev toggles that used to be
# hardcoded consts (skirmish.gd's old INFINITE_PLAYER_RESOURCES_FOR_TESTING),
# now surfaced in a real debug/options panel (skirmish.gd's "Debug" HUD
# button) instead of requiring a source edit + relaunch to flip.
#
# Read defensively (get_node_or_null("/root/DebugSettings")) by every
# gameplay script that consults these - same pattern match_config.gd already
# established - so headless tests that instantiate Skirmish.tscn directly,
# with no autoload registered in that boot path, keep the old hardcoded
# defaults below unchanged. Persists across scene changes (menu <-> skirmish)
# since autoloads live under /root for the whole process lifetime, so a
# toggle flipped mid-match survives a restart.

# Flipped to false (UNIFIED_ROADMAP.md Phase 1.1): with this on by default,
# every piece of Phase D (drip-fed cost, pause-on-broke, exact-progress
# refunds, multi-factory speed bonus, low-power build slowdown) was dormant
# in normal play - the whole economy only ever ran under an explicit test
# override. Still a real runtime toggle, still surfaced in the Debug HUD
# panel (skirmish.gd's Debug button) so it can be flipped back on for
# ad-hoc testing without a source edit.
var infinite_player_resources: bool = false

var reveal_all_fog: bool = false
var instant_build: bool = false

# Cross-instance reference set in _init(), not _enter_tree(). A gameplay service
# constructed and add_child()'d while the SceneTree is still inside its OWN
# _init() (the exact shape run_tests.gd's headless boot uses) never fires
# _enter_tree() for children added at that point - a genuine Godot timing quirk,
# confirmed by direct probing - and Engine.get_main_loop() also returns null for
# that same window, so the usual get_node_or_null("/root/DebugSettings") lookup
# cannot work either. _init() runs unconditionally the moment the node is
# constructed, so it is the one hook guaranteed to fire in time.
static var active: Node = null


func _init() -> void:
	active = self


static func get_active() -> Node:
	return active
