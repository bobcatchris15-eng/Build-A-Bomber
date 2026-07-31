extends SceneTree
# Scratch: eyeball the generated designations. A name generator is one of
# the few things where the only real test is reading the output.

const BlueprintNamer = preload("res://scripts/blueprint_namer.gd")
const BlueprintManager = preload("res://scripts/blueprint_manager.gd")

func _init():
	print("--- 24 rolls ---")
	for n in BlueprintNamer.generate_batch(24):
		print("  ", n)
	# Every generated name must clear the save gate, or Roll would hand the
	# player something the Save button then refuses.
	var bad := 0
	for n in BlueprintNamer.generate_batch(400):
		if not BlueprintManager.is_named(n):
			bad += 1
			print("  REJECTED BY GATE: '", n, "'")
	print("names rejected by is_named(): ", bad, " (must be 0)")
	quit(0)
