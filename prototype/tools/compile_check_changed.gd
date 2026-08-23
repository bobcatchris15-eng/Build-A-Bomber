extends SceneTree
# Quick targeted compile check for a small set of files. Bypasses the
# res:// path walking the full version does - we only care whether the
# specific files I edited in this turn still parse.

const FILES := [
	"res://scripts/module_catalog.gd",
	"res://scripts/battle/battle_logger.gd",
	"res://scripts/battle/battle_profiler.gd",
	"res://scripts/battle/match_director.gd",
	"res://scripts/auto_weapon.gd",
	"res://scripts/core/input_service.gd",
	"res://scripts/perf_hud.gd",
	"res://scripts/drone_unit.gd",
	"res://scripts/battle/buildings/building_mesh.gd",
	"res://scripts/ambient_scatter.gd",
	"res://scripts/battle/units/unit.gd",
	"res://scripts/battle/ai/commander.gd",
	"res://scripts/match_rule_set.gd",
	"res://scripts/deploy_gate.gd",
	"res://scripts/terrain_builder.gd",
	"res://scripts/battle/buildings/structure.gd",
	"res://scripts/battle/perf_toast.gd",
	"res://scripts/battle/buildings/placement_service.gd",
	"res://scripts/incoming_missile.gd",
	"res://scripts/weapon_missile.gd",
	"res://scripts/proximity_mine.gd",
	"res://scripts/decoy_contact.gd",
	"res://scripts/deployed_sentry.gd",
	"res://scripts/resource_node.gd",
	"res://scripts/battle/economy/resource_field.gd",
]

func _init():
	var failed: Array = []
	for f in FILES:
		var res = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null:
			failed.append(f)
			print("[FAIL] %s" % f)
		else:
			print("[OK]   %s" % f)
	if failed.is_empty():
		print("[PASS] all %d files compiled." % FILES.size())
		quit(0)
	else:
		print("[FAIL] %d file(s) failed to compile." % failed.size())
		quit(1)
