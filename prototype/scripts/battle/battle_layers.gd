class_name BattleLayers
extends RefCounted
# The physics layer vocabulary for the battle layer, in one place.
#
# WHY THIS FILE EXISTS. The old skirmish layer wrote bare integers at the point
# of use - `collision_layer = 4` in battle_unit.gd, `collision_mask = 1 + 2 + 8 +
# SmokeVolume.SMOKE_COLLISION_LAYER` in auto_weapon.gd - so the only way to learn
# what layer 2 meant was to grep for another site that happened to carry a
# comment. project.godot never named the layers either, so the editor's layer
# picker showed four unlabelled checkboxes.
#
# The numeric values MATCH the existing ones deliberately. The new battle layer
# reuses blueprint_manager.gd's reconstruct_vehicle() (hull on 1, module bodies
# on 2) and the damage/LOS raycasts in auto_weapon.gd, none of which are being
# rewritten - so renaming the bits would mean touching code the plan explicitly
# keeps. These are names for what is already true.
const TERRAIN := 1 << 0    # 1  - ground heightmap, obstacles, and vehicle hulls
const MODULES := 1 << 1    # 2  - per-module bodies, for subsystem-strip hits
const UNITS := 1 << 2      # 4  - the CharacterBody3D of a mobile unit
const BUILDINGS := 1 << 3  # 8  - static structures
# ALREADY IN USE by resource_node.gd, which sets `collision_layer = 16` as a bare
# literal. Named here rather than left implicit because SELECTION was originally
# assigned this bit, and the clash was invisible: a frustum select would return
# every ore patch inside the box, and only the has_meta("unit") filter downstream
# kept it from showing up as a bug. Right-clicking a node to send harvesters
# needs to pick this layer on purpose, so it gets a name.
const RESOURCE_NODES := 1 << 4  # 16

# NEW, and the reason this file is not just documentation.
#
# Selection is its own layer because a selection volume is not a physics volume.
# The unit's own body collider is a CONVEX HULL of the authored mesh
# (battle_unit.gd:245 - concave decomposition hangs on these meshes, so a convex
# fit is the best available), which means it is the wrong shape to click: it
# fills deck wells and the gaps between sponsons, and on a long-barrelled design
# it extends far past the part of the silhouette a player aims at.
#
# A dedicated axis-aligned proxy sized from the HULL rather than the whole
# assembly gives the frustum query a predictable box per unit, independent of
# what got bolted on. This is the same class of bug as the Design Lab's
# unclickable heavy_machine_gun (see PROGRESS.md 2026-08-04): a click collider
# derived from unrotated catalog dimensions does not match what is on screen.
const SELECTION := 1 << 5  # 32 - click/frustum proxy, nothing else

# What a selection frustum query should collide with: proxies only. Not UNITS -
# hitting both would return each unit twice and make the caller dedupe.
const SELECTION_QUERY_MASK := SELECTION

# What a ground-picking ray (right-click to move) should collide with.
const GROUND_PICK_MASK := TERRAIN

# A right-click has to distinguish "the ground", "a unit", "a building" and "an
# ore patch" before it knows what the order even is, so it queries the union and
# decides from what it hit.
const ORDER_PICK_MASK := TERRAIN | BUILDINGS | RESOURCE_NODES
