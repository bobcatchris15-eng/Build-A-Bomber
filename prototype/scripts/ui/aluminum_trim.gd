class_name AluminumTrim
extends RefCounted
# Brushed aluminum material for tab edges, slider tracks, trim elements.
# Clean, minimal wear - precision machined feel.

const UITheme = preload("res://scripts/ui_theme.gd")

static func apply(node: Control, overrides: Dictionary = {}) -> void:
	var defaults := {
		"wear": 0.08,
		"grime": 0.12,
		"scale": 0.9,
		"vignette": 0.15,
		"brightness": 1.0,
	}
	var merged = defaults.duplicate()
	for k in overrides:
		merged[k] = overrides[k]
	UITheme.apply_material(node, "moulded", merged)  # aluminum uses moulded material
	# Note: elevation handled by plate texture baked shadows, not StyleBoxFlat
