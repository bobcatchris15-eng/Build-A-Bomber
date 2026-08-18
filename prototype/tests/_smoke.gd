extends SceneTree

# Behavioral smoke for the barrel_length re-exposure:
#   1. gauss_railgun / coil_gun / guided_missile now have "barrel_length"
#      (renamed from rail_length / engine_length).
#   2. The 7 added weapons now have "barrel_length" in their TWEAK_SPECS.
#   3. The "rail_length" / "engine_length" tweak names are gone from
#      lab_document.gd's TWEAK_SPECS (the player no longer sees them).
#   4. ModuleData treats barrel_length as a linear-scale stat (weight +
#      cost) for the basic_cannon weapon.
const LabDocument = preload("res://scripts/lab_document.gd")
const ModuleDataScript = preload("res://scripts/module_data.gd")

func _has_bl(specs: Array) -> bool:
	for spec in specs:
		if spec.get("name", "") == "barrel_length":
			return true
	return false

func _has(specs: Array, name: String) -> bool:
	for spec in specs:
		if spec.get("name", "") == name:
			return true
	return false

func _init() -> void:
	var renames := ["gauss_railgun", "coil_gun", "guided_missile"]
	var adds := ["cluster_dispenser", "flamethrower", "ion_cannon", "particle_lance", "arc_projector", "microwave_emitter", "spigot_mortar"]
	var failed := 0

	for weapon in renames:
		var specs: Array = LabDocument.TWEAK_SPECS.get(weapon, [])
		if not _has_bl(specs):
			print("[FAIL] %s missing barrel_length" % weapon)
			failed += 1
		if _has(specs, "rail_length"):
			print("[FAIL] %s still has rail_length" % weapon)
			failed += 1
		if _has(specs, "engine_length"):
			print("[FAIL] %s still has engine_length" % weapon)
			failed += 1

	for weapon in adds:
		var specs: Array = LabDocument.TWEAK_SPECS.get(weapon, [])
		if not _has_bl(specs):
			print("[FAIL] %s missing new barrel_length" % weapon)
			failed += 1

	# behavioral: a basic_cannon with barrel_length > 1.0 should weigh more
	var d1 := ModuleDataScript.new()
	d1.type_id = "basic_cannon"
	d1.base_hp = 100.0
	d1.base_weight = 50.0
	d1.cost_metal = 10
	d1.cost_crystal = 0
	d1.tweaks = {"barrel_length": 1.0}
	var w1 := d1.get_weight()
	var c1 := d1.get_cost()

	var d2 := ModuleDataScript.new()
	d2.type_id = "basic_cannon"
	d2.base_hp = 100.0
	d2.base_weight = 50.0
	d2.cost_metal = 10
	d2.cost_crystal = 0
	d2.tweaks = {"barrel_length": 2.0}
	var w2 := d2.get_weight()
	var c2 := d2.get_cost()

	if not (w2 > w1 and c2.x > c1.x):
		print("[FAIL] barrel_length scaling: w %s->%s, c.metal %s->%s" % [w1, w2, c1.x, c2.x])
		failed += 1

	if failed > 0:
		print("SMOKE FAILED: %d check(s)" % failed)
		quit(1)
	else:
		print("ALL OK: 3 renames + 7 adds present, rail_length/engine_length gone, barrel_length scales stat")
		quit(0)
