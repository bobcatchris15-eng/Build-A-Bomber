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

# Chris is still actively developing against the always-solvent sandbox
# economy - default stays TRUE per RTS_CORE_ROADMAP.md's explicit "do NOT
# flip the default." Only becomes a real test of drip-feed/refund economy
# (Phase D1) when a test deliberately sets this false for its own run.
var infinite_player_resources: bool = true

var reveal_all_fog: bool = false
var instant_build: bool = false
