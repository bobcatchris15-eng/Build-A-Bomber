class_name BakelitePanel
extends RefCounted
# Bakelite material application for desk surfaces.
# Warm, slightly worn plastic - the commander's desk surface.

const UITheme = preload("res://scripts/ui_theme.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

static func apply(node: Control, overrides: Dictionary = {}) -> void:
	var defaults := {
		"wear": 0.15,
		"grime": 0.25,
		"vignette": 0.35,
		"brightness": 0.75,
		"scale": 1.0,
	}
	var merged = defaults.duplicate()
	for k in overrides:
		merged[k] = overrides[k]
	UITheme.apply_material(node, "bakelite", merged)
	# Desk surface is flush - no shadow
	var mat := node.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("enable_radar_sweep", false)
		mat.set_shader_parameter("show_range_rings", false)