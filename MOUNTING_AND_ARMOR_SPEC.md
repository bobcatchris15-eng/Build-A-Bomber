# Mounting & Armor Spec (from Chris, 2026-07-13)

This document exists so this direction survives across sessions. It supersedes the "keep armor hull-level-only" default logged in `DECISIONS_NEEDED.md` on 2026-07-12 — that tension is now resolved by directive #2 below. Read this before touching placement, mounting, or armor code.

## Priority

This is now the priority for the remaining days of the autonomous sprint, ahead of "buffer/polish." Sequenced by risk/dependency (see "Implementation sequencing" below), not necessarily the order Chris listed them in.

## 1. Firing arc visualization — implement it

Previously logged as documented-but-unbuilt (Design_Lab_UI_UX.md's "Radar Sweep" cone + red blind-spot indication) and deferred. It is now in scope, not deferred.

## 2. Armor becomes a module

Resolves the hull-level-only vs. spatial tension flagged 2026-07-12.
- Armor is placed as a module on a specific **facet/side of the hull** (not a global hull-level material+thickness slider).
- It **auto-scales to exactly fit** the facet/side it's deployed on.
- **Mirroring/symmetry applies to armor modules** the same as every other module.

## 3. Weapon/device mounting differs by hull face

- **Top:** pintle/gimbal mounted. The pintle's *base* snaps to the angle of the hull facet under it, but the weapon sitting on top of the pintle reads as visually level regardless of that facet's angle.
- **Sides / front / back:** the weapon is embedded into the hull body, with only the muzzle(s) projecting out through a sponson — implies the weapon's body rotates *inside* the hull when traversing, not on top of it.
- **Bottom:** inverse of top — the pintle snaps to the hull *above* the weapon instead of below it. Chris called this out as especially useful for helicopter rotor mounts in the current setup.
- **Exceptions:** railgun and howitzer-type weapons (at most hull sizes) are built directly into the frame — the whole vehicle orients to aim, not the weapon. The existing tank-cannon (enclosed turret) is already handled correctly — leave it as-is.
- **Placement rotation:** free-form via a grab-handle ring control (Spore/KSP style), not snapped to fixed angles.

## 4. Hull tweakability beyond uniform scaling

- An overall SIZE scale control for the whole hull (already exists as 2-3 axis scale — keep).
- **Per-hull-type custom deform handles** that reshape *different parts of that specific hull differently* (Spore creature-creator style — a handle might raise one section, expand one area more than another). This means per-hull-type custom deform rigging, not one generic tool. Chris explicitly authorized scoping/sequencing this and logging tradeoffs in `DECISIONS_NEEDED.md` rather than doing full bespoke rigging for all 7 hull types up front.

---

## Implementation sequencing & scoping decisions

*(filled in as work proceeds — see DECISIONS_NEEDED.md for the reasoning behind each choice, this section just tracks the plan)*

1. Firing arc visualization — self-contained, additive, no architecture changes needed.
2. Free-form rotation ring — needed by both armor and the face-based mounting scheme, do before them.
3. Armor-as-module with facet-fit + mirroring.
4. Face-based weapon mounting (top pintle-level / side sponson-embed / bottom inverted-pintle / railgun+howitzer frame-built exceptions).
5. Hull SIZE scale control confirmation + per-hull custom deform rigging (scoped incrementally, see DECISIONS_NEEDED.md).

## Known architecture constraint carried into this work

Hull placement/collision currently uses a single axis-aligned `BoxShape3D` per hull (see `module_placer.gd`), regardless of the hull's actual authored mesh silhouette (which can be wedged/aerodynamic/octagonal). "Facet" for both armor-fitting and mount-leveling purposes means one of that box's 6 axis-aligned faces, not the true sloped mesh surface, unless/until a mesh-accurate placement system is built. This is a deliberate scope simplification, not an oversight — flagged here so it isn't mistaken for one later.
