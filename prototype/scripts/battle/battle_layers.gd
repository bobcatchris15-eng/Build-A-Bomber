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
# BIT 6, NOT BIT 5. Bit 5 (32) was already taken by smoke_volume.gd's
# SMOKE_COLLISION_LAYER, and the clash was silent and nasty in both directions:
#
#   * The vision LOS raycast masks TERRAIN + smoke and opts into areas, because
#     smoke has to deny scouting. With selection proxies on the same bit, that ray
#     hit every unit's own proxy - so NOTHING was ever visible to anyone, and the
#     fog read as "vision range is too small" rather than as a layer collision.
#   * A frustum drag-select masks SELECTION, so it would have returned smoke
#     clouds as selectable units.
#
# Exactly the failure mode the RESOURCE_NODES note above describes, one bit over
# and caught later. Bits in use: 1 terrain, 2 modules, 4 units, 8 buildings,
# 16 resource nodes, 32 smoke. 64 is the first free one.
const SELECTION := 1 << 6  # 64 - click/frustum proxy, nothing else

# Per-module hit volumes on a SPAWNED unit - the barrels, masts, sensors and
# wheels a shot can actually connect with, built from module_volume.gd so they
# match the silhouette instead of a catalog box.
#
# DELIBERATELY NOT `MODULES` (bit 2), even though that bit's own comment says
# "per-module bodies, for subsystem-strip hits". Bit 2 is the DESIGN LAB's click
# layer, and it is in auto_weapon's LOS mask (1 + 2 + 8 + smoke) so a weapon's
# own sibling mast blocks its shot. Putting battle module bodies there too would
# have made a THIRD unit's gun barrel block a shot that the same unit's HULL
# does not - units are on bit 4 and are omitted from that mask on purpose, to
# keep grouped formations from deadlocking. One layer for "geometry that exists
# to be hit", separate from "geometry that occludes", is the distinction the
# clash would have destroyed.
#
# Bits in use: 1 terrain, 2 lab modules, 4 units, 8 buildings, 16 resource
# nodes, 32 smoke, 64 selection. 128 is this one; 512 is the first free one.
const UNIT_MODULES := 1 << 7  # 128 - per-module hit volumes on a spawned unit

# The spawned hull's precise trimesh skin (hull_surface.gd), for damage and LOS
# rays that need the real surface normal rather than the convex movement fit.
#
# HullSurface's own default is bit 5 (16), which is fine in the Design Lab and
# is RESOURCE_NODES here - a hull left on it would come back from the
# right-click ore-patch pick, so every unit on the field would read as a
# harvestable node. Same class of silent clash as the SELECTION/smoke one above.
const HULL_SURFACE := 1 << 8  # 256 - precise hull skin on a spawned unit

# What a selection frustum query should collide with: proxies only. Not UNITS -
# hitting both would return each unit twice and make the caller dedupe.
const SELECTION_QUERY_MASK := SELECTION

# What a ground-picking ray (right-click to move) should collide with.
const GROUND_PICK_MASK := TERRAIN

# A right-click has to distinguish "the ground", "a unit", "a building" and "an
# ore patch" before it knows what the order even is, so it queries the union and
# decides from what it hit.
const ORDER_PICK_MASK := TERRAIN | BUILDINGS | RESOURCE_NODES
