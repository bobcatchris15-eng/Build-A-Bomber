extends SceneTree
# Scratch probe: what does Godot 4.3's Theme actually expose for type
# variations? Assuming the method name cost a full debug cycle.

func _init():
	var t = Theme.new()
	print("--- Theme methods matching 'variation'/'type' ---")
	for m in t.get_method_list():
		var n: String = m["name"]
		if "variation" in n or "type" in n:
			var args := []
			for a in m["args"]:
				args.append("%s: %s" % [a["name"], type_string(a["type"])])
			print("  %s(%s)" % [n, ", ".join(args)])
	quit(0)
