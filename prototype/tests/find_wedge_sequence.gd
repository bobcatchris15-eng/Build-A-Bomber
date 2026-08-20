extends SceneTree

func _init():
	var v_bfl := Vector3(-0.5, -0.5, -0.5) # bottom front left (tip)
	var v_bfr := Vector3( 0.5, -0.5, -0.5) # bottom front right (tip)
	var v_bbl := Vector3(-0.5, -0.5,  0.5) # bottom back left
	var v_bbr := Vector3( 0.5, -0.5,  0.5) # bottom back right
	var v_tbl := Vector3(-0.5,  0.5,  0.5) # top back left
	var v_tbr := Vector3( 0.5,  0.5,  0.5) # top back right

	var faces = [
		{"name": "Bottom", "norm": Vector3(0, -1, 0), "quad": [v_bbl, v_bbr, v_bfr, v_bfl]},
		{"name": "Back",   "norm": Vector3(0, 0, 1),  "quad": [v_bbl, v_tbl, v_tbr, v_bbr]},
		{"name": "Slope",  "norm": Vector3(0, 1, -1).normalized(), "quad": [v_bfr, v_tbr, v_tbl, v_bfl]},
		{"name": "Left",   "norm": Vector3(-1, 0, 0), "tri":  [v_bfl, v_bbl, v_tbl]},
		{"name": "Right",  "norm": Vector3(1, 0, 0),  "tri":  [v_bfr, v_tbr, v_bbr]}
	]
	
	for f in faces:
		var n: Vector3 = f["norm"]
		if f.has("quad"):
			var q = f["quad"]
			# Test tri 1: (q[0], q[1], q[2])
			var n1 = (q[2] - q[0]).cross(q[1] - q[0]).normalized()
			var n2 = (q[3] - q[0]).cross(q[2] - q[0]).normalized()
			print("%s: n1 dot=%.2f, n2 dot=%.2f" % [f["name"], n1.dot(n), n2.dot(n)])
		elif f.has("tri"):
			var t = f["tri"]
			var n1 = (t[2] - t[0]).cross(t[1] - t[0]).normalized()
			print("%s: tri dot=%.2f" % [f["name"], n1.dot(n)])
	quit(0)
