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

## Addendum, 2026-07-12: full directional armor + trait-based unit classes

Chris's follow-up call, after reviewing the phased-plan writeup: go as far as possible on BOTH the full armor phase list and the full trait/unit-class system, not just the cheap tiers.

**Armor, full phase list:**
1. Dedupe `take_damage()`'s armor math (was in `battle_unit.gd`, `player_vehicle.gd`, and `building.gd`) into one shared function.
2. Facet-level resolution — armor only protects the facet it's actually on, no raycast needed (cheap angle classification, same convention as placement).
3. Per-module armor material choice (a plate can be reactive on the front, ablative on the sides — not just one global hull material).
4. True angle-of-incidence sloped armor via raycast (real WWII-tank-style: a glancing hit is more survivable than a perpendicular one).
5. AI facing-awareness so flanking is something the *enemy* can also do to you in Skirmish, not just something a human player can exploit in Test Range.

**Traits/unit classes, full scope, with one hard constraint:**
- Formalize a composable trait system (`hovering`, `fixed_wing`, `rotary_wing`, `ground_contact`, `airborne`, `static`, `turreted_capable`, etc.) — tags that combine, not a rigid ship/land/air/building enum, so "helicopter that behaves like a ground vehicle at scale" and "three different fixed-wing archetypes" aren't forced into a box.
- **Explicit constraint: no hard-blocking.** A player can put treads on a naval hull if they want to. Traits compose and drive simulation behavior — whatever that produces, including janky/suboptimal outcomes — never validation logic that prevents "weird" combinations. This is a deliberate design philosophy, not a placeholder for validation to be added later; revisit only if it causes real problems in play.
- Generalize `frame_built` mounting from weapon-type-gated (railgun/howitzer only) to `turreted_capable`-trait-gated (any weapon, when the unit lacks independent-traverse capability).
- New movement models: fixed-wing flight (banking, stall speed, minimum airspeed) and naval (buoyancy/surface movement) — genuinely new `CharacterBody3D` behavior, not reskinned existing locomotion.
- New AI behavior: strafing/approach-and-peel-off for aircraft, distinct from the current ground-unit approach-and-engage pattern.
- New Blender-authored hull geometry for airframes/ships as needed — understood to be the most expensive and fragile part of this whole scope (same reimport pipeline risk flagged elsewhere in this doc).

## Addendum, 2026-07-21: flush-mount to facet, no more column/level/embed model

Directive #3 above (pintle-level-on-top / side-embed-with-sponson / inverted-bottom-pintle / frame-built exception) was the original design, but Chris has since abandoned it: almost every module now has an authored mesh with its own mounting post/base baked in (see `tools/blender`/TripoSG-generated parts), which made the procedurally-drawn column post + base plate (`visual_builder.gd`'s old `add_mount_hardware()`/`_build_pintle_base_plate()`) redundant and, worse, double-mounted.

**New model:** every weapon mount style (turret/frame_built/pintle) places the same way now - flush against whatever facet was clicked, with the whole module rotated (`Basis(Quaternion(Vector3.UP, local_normal))`) so its local-up (where the baked-in post's bottom sits, per `build_visual()`'s monolithic-mesh placement at local Y=0) lies flat against that facet's real surface normal, sloped or not. No outward column extrusion, no backward embed offset, no separately-drawn hardware.

`mount_style` (`get_mount_style()` in `module_catalog.gd`) still exists and still matters - but only for combat traverse (`get_traverse_limit_angle()`): frame_built weapons get zero independent traverse (whole vehicle aims), turret/pintle get full 360. It no longer has any bearing on how a weapon is visually placed.

**How to apply:** if a future weapon type ships without an authored mesh (still on the procedural-primitive fallback in `build_visual()`), it gets no mount-post geometry at all until one is authored - this was an accepted tradeoff, not an oversight.

## Addendum, 2026-08-04: sponsons return for near-vertical faces only

The 2026-07-21 flush-mount rule above was right about the *deck*, the *belly* and *slopes*, and wrong about *walls*. Measured directly, `_align_up_to()` on a near-vertical facet produced:

| Facet | Muzzle direction | |
|---|---|---|
| Top (+Y), belly (−Y) | horizontal | fine |
| Front (−Z) | `(0,−1,0)` | **straight into the ground** |
| Back (+Z) | `(0,+1,0)` | **straight at the sky** |
| Left/right (±X) | horizontal, but hull-*forward*, module rolled 90° | *accidentally* plausible |

The sides only looked acceptable by coincidence — rotating +Y onto ±X about Z leaves −Z untouched. They were still rolled, so local +Y pointed outboard, and `auto_weapon._within_elevation()` reads `basis.y` as "up": a side gun's elevation cone opened *sideways*, rejecting a level outboard target and accepting one directly overhead. It also visibly snapped upright on acquisition, because `_looking_at_safe()` builds the tracking basis with `Vector3.UP` and the two bases disagreed.

**New model, for near-vertical faces only.** The weapon is pushed *inboard* along the outboard axis so its body and its authored post end up inside the hull, and only the barrel protrudes, through an authored `sponson_blister.glb` housing. Its basis is `Basis.looking_at(outboard, Vector3.UP)` — muzzle outboard, +Y hull-up — so it sits level, elevates against the real horizon, and traverses about hull-up. Resting and tracking bases now agree, so the snap is gone.

**This does not reintroduce what 2026-07-21 deleted.** That was a procedural *column plus base plate* — a second mounting post under a mesh that already had one. The blister is neither: it is a housing around the aperture, and the weapon's own post is inside the hull, unseen and unduplicated. **If anyone adds a post, hub or base plate to `VisualBuilder._sponson_blister()`, that is the moment it becomes the thing that was removed.**

**Every mount style wall-mounts, including `turret` and `frame_built`.** A first pass admitted only `pintle`, reading directive #3's "the existing tank-cannon is already handled correctly - leave it as-is" as covering all facets. It does not: that line is about the **top deck**. On a wall `basic_cannon` was broken identically to everything else (muzzle into the ground on the front facet), and excluding it just left the bug in place. A tank cannon buried in a hull side firing through a housing is a casemate, which is the correct read. `frame_built` follows for the same reason — a railgun in the glacis should aim out of it — and keeps its zero traverse regardless, because `get_traverse_limit_angle()` tests `frame_built` before the sponson flag.

Still flush, deliberately: every non-weapon category (an armor plate *must* stay flush to the facet it auto-fits), the deck, the belly (directive #3's inverted pintle), and any slope above the per-weapon threshold.

**Indirect-fire weapons are REFUSED on vertical faces — a deliberate exception to the no-hard-blocking rule at `:58`.** Chris called this on 2026-08-04. There is no orientation that makes a lobbing weapon work off a wall: a housing and a narrowed arc deny it the sky it exists to use, and an intermediate attempt at levelling it on an open unhoused mount just relocated the problem. An artillery piece on a hull side is not an interestingly-janky emergent outcome of the kind `:58` protects; it is a nonsense one.

The exception is kept as narrow as possible so it does not become a precedent — `module_placer._placement_refusal_reason()` refuses exactly one combination: a weapon whose catalog says `sponson_capable: false`, on a face steep enough to require a sponson. The deck, a 45° glacis, direct-fire weapons on the same facet, and every genuinely weird trait combination `:58` is about all still go through. It is enforced on the build bar and on the drag path, and reports a reason rather than failing silently.

Note this partly reverses `module_placer.gd:573-579`, where a *previous* validation gate (foundations refusing locomotion) was deleted to honour `:58`. That deletion stands; this is a separate, argued exception, not a reopening of the general rule.

**The threshold revives `pintle_min_up_alignment`**, which had sat unread on 23 weapon entries since 2026-07-21 — now `ModuleCatalog.get_sponson_up_alignment()`. Its highest authored value is 0.55, so a 45° glacis (`dot(UP)=0.707`) stays flush for every weapon in the roster. **Known residual:** a glacis gun therefore still leans, muzzle 45° down. Raising thresholds to ~0.75 would fix it but contradicts the per-weapon reasoning in `DECISIONS_NEEDED.md:1224`; splitting base-tilt from body-level would fix it but is the abandoned base-plate model. Left deliberately, priced, not an oversight.

**Traverse narrowed, and this is a balance change.** A sponson cannot swing back through the hull it is buried in, so `get_traverse_limit_angle()` returns a 60° half-angle (120° sweep) for one, instead of unrestricted. That flag is passed explicitly and *not* derived from `facet` — facet is a dominant-axis label, and a 45° glacis mount is facet "front" too while being flush. Combat (`auto_weapon._ready`) and the Design Lab arc visualiser read the same `sponson` meta so they cannot drift.

## Known architecture constraint carried into this work

~~Hull placement/collision currently uses a single axis-aligned `BoxShape3D` per hull.~~ **Outdated as of 2026-08-04** — corrected here because it was load-bearing for the sponson work and would have argued against it.

Placement raycasts against a real **trimesh** of the authored hull silhouette: `hull_surface.gd:37` builds it with `create_trimesh_shape()`, `:51` sets `backface_collision = true`, and `module_placer.surface_raycast()` prefers that surface, falling back to the axis-aligned `BoxShape3D` only when a hull has no authored mesh. So a sloped glacis or a curved sponson flank yields a real, continuous surface normal, and `ModuleCatalog.classify_facet()` is a *classification of that continuous normal* into six labels — not an enumeration of six box faces. Armor fitting and centring still use the box's dimensions (`module_placer.gd`'s armor branch), which is where the box genuinely does remain the model.
