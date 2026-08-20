class_name FoldedPaperPanel
extends RefCounted
# Folded paper/canvas material for slide-up drawers.
# Matte, slightly grimey paper texture with subtle vignette.

const UITheme = preload("res://scripts/ui_theme.gd")

static func apply(node: Control, overrides: Dictionary = {}) -> void:
	var defaults := {
		"wear": 0.06,
		"grime": 0.30,
		"scale": 0.7,
		"vignette": 0.12,
		"brightness": 0.85,
	}
	var merged = defaults.duplicate()
	for k in overrides:
		merged[k] = overrides[k]
	UITheme.apply_material(node, "canvas", merged)
	# Note: elevation handled by plate texture baked shadows, not StyleBoxFlat