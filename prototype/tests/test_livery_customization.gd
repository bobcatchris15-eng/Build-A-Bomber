extends "res://tests/suite_base.gd"

const LiveryScript = preload("res://scripts/livery.gd")
const HullMaterialBuilderScript = preload("res://scripts/hull_material_builder.gd")
const HullDecalsScript = preload("res://scripts/hull_decals.gd")

func test_livery_data_roundtrip_and_patterns() -> bool:
	print("Running Test Suite: Livery - Data Roundtrip, Patterns & Finishes...")

	# 1. Test Pattern IDs and Finishes
	var pat_ids := LiveryScript.pattern_ids()
	if pat_ids.size() < 13:
		print("  [FAIL] Expected at least 13 pattern types, got: ", pat_ids.size())
		return false
	
	for pid in ["none", "stripe", "dual_stripe", "chevrons", "hazard", "hex_grid", "digital_camo", "splinter_camo", "tiger_camo", "nose_dip", "half_split", "gradient"]:
		if not pat_ids.has(pid):
			print("  [FAIL] Missing expected pattern id: ", pid)
			return false

	var fin_ids := LiveryScript.finish_ids()
	if fin_ids.size() < 18:
		print("  [FAIL] Expected at least 18 finish types, got: ", fin_ids.size())
		return false

	# 2. Test Presets Integrity
	for p_key in LiveryScript.PRESETS.keys():
		var p: Dictionary = LiveryScript.PRESETS[p_key]
		if not p.has("name") or not p.has("pattern_type") or not p.has("hull_upper") or not p.has("hull_lower"):
			print("  [FAIL] Malformed preset: ", p_key)
			return false
		var pat_type: String = p["pattern_type"]
		if not LiveryScript.PATTERNS.has(pat_type):
			print("  [FAIL] Preset %s references unknown pattern: %s" % [p_key, pat_type])
			return false

	# 3. Test Serialization / Deserialization JSON roundtrip
	var sample_livery := {
		"pattern": {
			"type": "dual_stripe",
			"scale": 1.45,
			"angle": 45.0,
			"softness": 0.02,
		},
		"weathering": 0.75,
		"decal": {
			"icon": "star_compass",
			"badge": "circle",
			"serial": "789",
			"show_hazard": false,
		},
		"hull_upper": {"color": Color(0.8, 0.2, 0.3), "finish": "carbon_fibre"},
		"hull_lower": {"color": Color(0.1, 0.15, 0.2), "finish": "cerakote"},
		"hull_stripe": {"color": Color(0.9, 0.8, 0.1), "finish": "anodised"},
		"weapon_action": {"color": Color(0.3, 0.3, 0.3), "finish": "brushed_steel"},
		"weapon_barrel": {"color": Color(0.1, 0.1, 0.1), "finish": "gunmetal"},
	}

	var json_data = LiveryScript.to_json(sample_livery)
	var restored = LiveryScript.from_json(json_data)

	if restored["pattern"]["type"] != "dual_stripe":
		print("  [FAIL] Expected pattern dual_stripe, got: ", restored["pattern"]["type"])
		return false
	if absf(restored["pattern"]["scale"] - 1.45) > 0.001:
		print("  [FAIL] Scale mismatch after roundtrip: ", restored["pattern"]["scale"])
		return false
	if absf(restored["weathering"] - 0.75) > 0.001:
		print("  [FAIL] Weathering mismatch: ", restored["weathering"])
		return false
	if restored["decal"]["icon"] != "star_compass" or restored["decal"]["serial"] != "789":
		print("  [FAIL] Decal mismatch after roundtrip: ", restored["decal"])
		return false

	print("  [PASS] Livery schema serialization, patterns, finishes, and presets verified successfully.")
	return true


func test_hull_material_builder_shader_uniforms() -> bool:
	print("Running Test Suite: Livery - Hull Material Builder Shader Uniforms...")

	# Seed cache with custom livery
	var test_id := "test_unit_livery"
	LiveryScript._cache[test_id] = {
		"pattern": {
			"type": "hex_grid",
			"scale": 1.8,
			"angle": 30.0,
			"softness": 0.01,
		},
		"weathering": 0.60,
		"decal": {
			"icon": "blade",
			"badge": "none",
			"serial": "404",
			"show_hazard": true,
		},
		"hull_upper": {"color": Color(0.2, 0.6, 0.9), "finish": "galvanised"},
		"hull_lower": {"color": Color(0.1, 0.1, 0.1), "finish": "rubberised"},
		"hull_stripe": {"color": Color(1.0, 0.5, 0.0), "finish": "anodised"},
		"weapon_action": {"color": Color(0.4, 0.4, 0.4), "finish": "cast_iron"},
		"weapon_barrel": {"color": Color(0.2, 0.2, 0.2), "finish": "phosphate"},
	}

	var mat: ShaderMaterial = HullMaterialBuilderScript.build_hull_material(test_id)
	if mat == null or mat.shader == null:
		print("  [FAIL] Failed to build ShaderMaterial for hull")
		return false

	# Verify uniforms assigned to shader
	var p_type = mat.get_shader_parameter("pattern_type")
	if p_type != LiveryScript.pattern_id_int("hex_grid"):
		print("  [FAIL] Expected pattern_type %d, got %s" % [LiveryScript.pattern_id_int("hex_grid"), str(p_type)])
		return false

	var p_scale = mat.get_shader_parameter("pattern_scale")
	if absf(float(p_scale) - 1.8) > 0.001:
		print("  [FAIL] Expected pattern_scale 1.8, got ", p_scale)
		return false

	var w_val = mat.get_shader_parameter("weathering")
	if absf(float(w_val) - 0.60) > 0.001:
		print("  [FAIL] Expected weathering 0.60, got ", w_val)
		return false

	var surf_upper = mat.get_shader_parameter("zone_upper_surface")
	if surf_upper != LiveryScript.finish_surface_type("galvanised"):
		print("  [FAIL] Expected galvanised surface type %d, got %s" % [LiveryScript.finish_surface_type("galvanised"), str(surf_upper)])
		return false

	# Clean up cache
	LiveryScript.invalidate(test_id)

	print("  [PASS] HullMaterialBuilder correctly binds procedural pattern, surface types, and weathering uniforms.")
	return true
