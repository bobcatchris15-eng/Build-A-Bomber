class_name HUDSkin
extends RefCounted
# Surface descriptors for the battle HUD's flat panels.
# Provides optional texture/noise overlays for Cold-War CIC instrument feel.
#
# Phase 1: Pure flat fills (current high-performance default).
# Phase 2: Enables subtle instrument panel noise/grain without modifying layout code.

static func panel_noise() -> Texture2D:
	return null

static func edge_glow() -> Texture2D:
	return null

static func scan_overlay() -> Texture2D:
	return null
