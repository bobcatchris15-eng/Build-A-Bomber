extends SceneTree
# Quick targeted compile check for a small set of files. Bypasses the
# res:// path walking the full version does - we only care whether the
# specific files I edited in this turn still parse.

const FILES := [
	"res://scripts/battle/vision/vision_service.gd",
	"res://scripts/battle/units/unit.gd",
	"res://scripts/battle/match_director.gd",
	"res://scripts/battle/ai/commander.gd",
	"res://scripts/battle/movement/flow_field_service.gd",
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
