extends SceneTree
const Suite = preload("res://tests/test_designer_lab.gd")
func _init():
	var s = Suite.new()
	s.tree = self
	s.root = root
	for i in range(2):
		var ok: bool = await s.test_no_dead_tweaks()
		print(">>> run %d: %s" % [i + 1, "PASS" if ok else "FAIL"])
	quit(0)
