# Locomotion â€” Expansion & Systems Upgrade Plan

> **Update 2026-08-09: Completed.** (All tasks in this plan have been fully implemented to satisfaction. This document is retained for historical context.)

Status: **PLANNED, not started.** Written 2026-08-01 at Chris's request, to be
picked up in a later session. Chris has approved both open questions up front:

1. **Do the systems pass (Phase 0/1) first, as a standalone commit**, before any
   new locomotion type is authored. â€” APPROVED
2. **7 new locomotion types** (10 â†’ 17) is the agreed scope. â€” APPROVED
3. **Rearchitect the placement system** for robustness/flexibility â€” added
   2026-08-01, see Â§2. Findings verified against source; recommendation is to
   land it *before* the new types, since it turns "add a type" from an `elif`
   branch in a 540-line function into a data declaration.

Companion doc: `LOCOMOTION_REBUILD_PLAN.md` (historical, 2026-07-24). That file
describes the *rebuild* â€” turning each monolithic locomotion `.glb` into a
multi-part tweakable assembly. It is complete. This file describes the *next*
pass: filling in the systems the rebuild left thin, and widening the roster the
way the weapons roster was widened.

This is the locomotion equivalent of the weapons expansion documented in
`Arsenal_Weapons_List.md` â€” same method: survey, close the systemic gaps first,
then add archetypes to bring each role group up to a consistent depth, with
authored meshes and regression tests per addition.

---

## 1. Survey of what exists (verified 2026-08-01)

Ten locomotion types in `prototype/scripts/module_catalog.gd:1168-1361`.

| type_id | traits | base_weight_capacity | thrust_coef | in terrain table? |
|---|---|---|---|---|
| `wheels` | ground_contact, **high_speed** | 350 | (default) | âœ… |
| `tracked_treads` | ground_contact | 700 | (default) | âœ… |
| `legs` | ground_contact | 500 | (default) | âœ… |
| `hover_engine` | hovering | 300 | (default) | âŒ |
| `helicopter_rotors` | airborne, **rotary_wing**, hovering | 250 | (default) | âŒ |
| `fixed_wing_engine` | airborne, fixed_wing, **high_speed** | 380 | (default) | âŒ |
| `ornithopter_wing` | airborne, flapping_wing | 300 | 120 | âŒ |
| `buoyant_envelope` | airborne, buoyant | 1100 | 55 | âŒ |
| `naval_propeller` | buoyant, naval | 800 | (default) | âŒ |
| `screw_drive` | ground_contact, amphibious | 600 | 110 | âœ… |

**Domain split: 3 ground / 1 hover / 4 air / 1 naval / 1 amphibious.** Air is
the deepest group in a game whose primary theatre is ground. This is the
headline imbalance.

### The four systemic gaps

**G1 â€” `TERRAIN_SPEED_MULTIPLIERS` covers 4 of 10 types.**
`module_catalog.gd:2424`. Rows exist for `wheels`, `tracked_treads`, `legs`,
`screw_drive` across marsh / rocky / snow_mud / sand / gravel / forest / ice.
The other six fall back to `1.0` on every surface â€” they have **no terrain
character at all**. This table is the single strongest differentiator in the
locomotion system, and it is 40% populated. Filling it in improves the ten
types that already ship, before a single new one is added.

**G2 â€” dead traits.** `high_speed` and `rotary_wing` are declared in the
catalog and read *nowhere*. `battle_unit.gd` consumes only `airborne`,
`amphibious`, `fixed_wing`, `naval`. `parts_menu.gd` consumes `naval`,
`buoyant`, `ground_contact`, `hovering` for its Ground/Naval/Hovering/Air
grouping only. So `flapping_wing` is also decorative. Either wire them or
delete them â€” right now they read like implemented behaviour and are not.

**G3 â€” `get_locomotion_contribs()` returns `capacity = 0.0` for five types**
(`helicopter_rotors`, `fixed_wing_engine`, `ornithopter_wing`,
`naval_propeller`, `buoyant_envelope`). Those types' tweaks move thrust but
never payload, so a bigger rotor cluster makes you faster and not stronger.
Compare the ground types, where every tweak moves both. Intentional or not,
it means half the roster's sliders carry half the consequence.

**G4 â€” tweak depth is uneven, and one pair is a literal duplicate.**
`LOCOMOTION_TWEAK_SPECS:2521`. `ornithopter_wing` has 2 sliders and only
`wingspan` feeds a stat (`wing_sweep` is cosmetic). `screw_drive` has 2.
`hover_engine` has 2. Meanwhile `helicopter_rotors` has 4 and `wheels` has 3,
all consequential. `naval_propeller` and `buoyant_envelope` ship a
byte-identical spec (documented as deliberate at the time â€” shared pylon-prop
rebuild â€” but it means picking between them is a stats choice with no design
choice attached).

### Mesh cost (from `prototype/scratch/probe_polycount.gd`)

Locomotion parts range from **3,792 tris (`tracked_treads`, the single
heaviest part in the whole 259-part project)** down to **12 tris
(`rotor_blade`)**. Also heavy: `screw_drum` Ã—3 variants @ 1,596 each,
`rotor_duct_ring` 1,112, `screw_drive` 936, `wheel_hub` 656. Also trivial:
`hover_skirt` 92, `leg_foot` 88, `naval_propeller` 120.

Two orders of magnitude of variance with no relationship to how prominent or
how instanced the part is â€” `wheel_hub` at 656 is drawn 4â€“48 times per unit;
`rotor_blade` at 12 is drawn 2â€“32. This is the same uneven-detail-standard
situation the weapons roster had before its pass. Note that the **baked-module
LOD fix (`ff757ef`)** already takes most of the sting out of this at distance;
what remains is a close-up authoring-consistency issue, not a perf emergency.

---

## 2. Architecture review â€” the placement system

Chris's ask, 2026-08-01: *"look at and consider rearchitecting the locomotion
placement system to be more robust and flexible."* This section is the result of
reading the actual code path. **Conclusion: yes, and it should happen before the
seven new types are authored, not after.** Every finding below is verified
against the source, with line numbers.

### 2.1 What the system is today

Placement lives in **`module_placer.gd:676-1219`, `update_locomotion()`** â€” a
single ~540-line function that is, structurally, an
`if type_id == "wheels": â€¦ elif type_id == "tracked_treads": â€¦` chain with one
branch per locomotion type. Each branch does the same six things in its own
hand-written way:

1. pull tweak values out of `settings` (with two or three fallback key spellings)
2. compute a mount pattern (side pairs, an ellipse, a stern row, a corner pair)
3. build a `geo_tweaks` dictionary of loose float keys for the mesh builder
4. call `_place_weapon()` per instance
5. reset `scale` / `rotation` / `scale_multiplier` by hand
6. conditionally `_apply_mirror_flip()` and append to `spawned_wheels`

Steps 4â€“6 are near-identical in all ten branches and are copy-pasted ten times.
Step 2 is the only genuinely per-type part.

### 2.2 The five architectural problems

**A1 â€” Adding a type means editing a 540-line function.** Seven new types
(Â§4) means seven more `elif` branches, taking `update_locomotion()` past 800
lines. There is no registration point, no data table, no interface â€” the
knowledge that "wheels come in side pairs along Z" exists only as imperative
code inside a branch. This is the single biggest flexibility cost.

**A2 â€” Collider geometry math is written three times and has already drifted.**
For `wheels`, the click-target box is computed in:
- `_place_weapon()` at `module_placer.gd:1245-1249` (initial placement)
- `update_locomotion_geometry_tweak()` at `module_placer.gd:648-657` (live drag)
- and is *derived from* `_build_wheels()` at `visual_builder.gd:3556`, which is
  the real source of truth for where the wheel actually renders

Same for `tracked_treads` (`1250-1271` and `658-673`) and `legs` (`1272+`). The
in-code comments document this drifting before â€” "needing to be clicked very
close to dead center", and the tracked-tread collider staying "a tiny ~2.5-unit
box while the actual rendered loop spans the full hull length". The fix each
time was to copy the builder's math into the placer again. **Three copies of one
formula, kept in sync by hand, is the defect generator here** â€” and only three
of ten types have overrides at all, so the other seven have colliders that are
simply wrong in the same way, just unreported.

**A3 â€” The "reach vector" convention is real but unspelled.** Six types tell
their mesh builder where the hull is, and they do it four different ways:

| type | keys passed |
|---|---|
| `helicopter_rotors` | `mount_side`, `mount_reach_x`, `mount_reach_y` (no Z) |
| `hover_engine`, `fixed_wing_engine`, `naval_propeller`, `buoyant_envelope` | `mount_reach_x/y/z` |
| `screw_drive` | `mount_reach_fore_x/y/z` **and** `mount_reach_aft_x/y/z` |
| `wheels`, `tracked_treads`, `legs`, `ornithopter_wing` | none â€” plus one-off keys like `leg_stance_reach`, `leg_hull_centerline_y`, `target_length` |

All of it travels as untyped floats in a `Dictionary`, so a typo'd key is a
silent default, not an error. This is one concept â€” *"here is the vector from my
origin back to the hull's center"* â€” that deserves one name and one shape.

**A4 â€” Nothing re-runs the layout when the hull changes.** `update_locomotion()`
has exactly two call sites: initial placement (`module_placer.gd:567`) and
stat_calculator's count-tweak respawn (`stat_calculator.gd:1476`).
`gizmo_3d.gd:210-260` handles hull rescale â€” it updates `hull_scale`, the mesh,
the collider, the stats and the clipping check, **but never touches locomotion.**
Since every branch computes its positions from `hull_size` (`x_offset`,
`z_limit`, `drum_length`, the ellipse radiiâ€¦), resizing a hull after choosing
locomotion leaves wheels spaced for the hull you *used* to have. Verified by
call-site inspection; worth a repro before the fix lands, but the code path is
unambiguous.

**A5 â€” The blueprint round-trip bakes the layout instead of re-deriving it.**
`blueprint_manager.gd` saves locomotion instances as ordinary modules with baked
`position`/`rotation` (`:733+`), and on load rebuilds them generically â€”
`update_locomotion()` never runs. So the reconstruct path has to re-implement
the parts of it that aren't baked, and does: running-gear construction and the
hull lift are duplicated at `blueprint_manager.gd:706-731`. That duplicate has
drifted â€” it reads `settings.get("size", 1.0)` where the placer reads
`settings.get("wheel_size", â€¦) * hull_height_factor`, and `size` is no longer a
tweak key at all. (Currently harmless: all five types that could reach that
branch are in `LOCOMOTION_TYPES_USING_RUNNING_GEAR`, so it's **dead code in both
files** â€” but it is exactly the shape of drift that A2 keeps producing, and it
should be deleted rather than left to be re-activated by a new type.)

Secondary: `locomotion_group` stores an `Array[Node]` in the meta of every
member, cyclically. Freed members leave stale entries, already worked around
with an `is_instance_valid` guard at `module_placer.gd:1605`.

### 2.3 Proposed architecture

The shape that fits what's actually there â€” not a rewrite, a **factoring**. The
`_build_X()` mesh builders in `visual_builder.gd` stay exactly as they are; this
is entirely about the placer side.

**(1) A `LocomotionLayout` resource, one per type, declared as data.**
New file `prototype/scripts/locomotion_layout.gd`. Each type declares its mount
pattern instead of coding it:

```gdscript
# Pattern kinds, covering all 10 current types and all 7 planned ones:
#   SIDE_PAIRS   - N stations per side along Z          (wheels, legs, tracked_treads, half_track, rocker_bogie, ornithopter_wing)
#   RING_XZ      - N stations round a plan-view ellipse (hover_engine, air_cushion_skirt, anti_grav_plate)
#   RING_XY      - N stations round a nose-on ellipse   (fixed_wing_engine)
#   STERN_ROW    - N stations in a row aft of the hull  (naval_propeller, buoyant_envelope, water_jet)
#   CORNER_SPAN  - one span per side, fore+aft anchored (screw_drive, hydrofoil)
#   ROOF_PAIRS   - N stations per side above the hull   (helicopter_rotors)
```

with per-type fields for the offsets those patterns need (`clearance`,
`z_span_fraction`, `mounts_to`: `HULL_SKIN` | `RUNNING_GEAR` | `STERN`, and the
count/size tweak key names). `wheels` becomes ~12 lines of data; `screw_drive`,
the gnarliest branch today, becomes ~16.

**(2) One generic placement loop.** `update_locomotion()` shrinks to: resolve
the layout â†’ clear old parts â†’ build running gear if wanted â†’ ask the layout for
`Array[MountStation]` â†’ loop, calling the same `_place_weapon()` + reset +
mirror + append it does now, **once**. The ten copies of steps 4â€“6 collapse to
one. Target: ~120 lines total, down from 540.

**(3) A typed `MountStation`.** `{ position: Vector3, normal: Vector3,
reach: Vector3, index: int, side: float, mirror: bool }` â€” replacing the
`mount_reach_x/y/z` float soup of A3. `visual_builder.gd`'s builders keep
reading loose keys for now (a shim writes them from the struct), so this is a
non-breaking change; the shim can be retired builder-by-builder afterward.
`screw_drive`'s fore/aft pair becomes a `CORNER_SPAN` station carrying two
reaches, named rather than spelled out six times.

**(4) Collider sizing moves next to the mesh that defines it.** Kill A2 by
having each `_build_X()` return (or stamp as meta) the AABB it actually built,
and have `_place_weapon()` size the click target from *that* instead of from a
per-type `if` in the placer. This deletes all three copies of the wheels /
treads / legs math and fixes the seven types that never got an override. This is
the highest-value item in the whole section and is worth doing even if nothing
else here is.

**(5) `refresh_locomotion()` â€” idempotent re-layout.** A no-argument entry point
that re-reads `locomotion_type` / `locomotion_settings` off the hull meta and
re-runs the layout. Called from `gizmo_3d.gd`'s hull-rescale handler (fixes A4),
from hull-type change, and from blueprint load *instead of* the duplicated
running-gear block (fixes A5). Locomotion then stops being persisted as baked
positions and starts being persisted as what it actually is: a type + a settings
dict, re-derived on load. Blueprint compatibility: keep reading baked positions
for old saves, ignore them when `locomotion.type_id` is present and known.

### 2.4 Why this is worth doing before Â§4, not after

Adding seven types to the current structure means writing seven more copies of
steps 4â€“6, seven more `geo_tweaks` dictionaries in whatever spelling seems right
that day, and â€” since only three of ten types have collider overrides today â€”
seven more modules whose click targets don't match their meshes. The factoring
turns each new type into **one data declaration plus its `_build_X()`**, which
is the same shape the weapons expansion had once its catalog-driven path existed.
The rearchitecture pays for itself at roughly the third new type.

### 2.5 Tests for the rearchitecture

- `test_every_locomotion_type_has_a_layout()` â€” every catalog locomotion id
  resolves to a `LocomotionLayout`; fails loudly for a type added without one.
- `test_locomotion_layout_is_deterministic_and_hull_relative()` â€” lay out each
  type against a small, a reference, and a large hull; assert every station is
  outside the hull's own collision box (the class of bug that buried
  `naval_propeller` inside the hull), and that no two stations of a type
  coincide.
- `test_locomotion_colliders_match_their_meshes()` â€” for every type and a
  sweep of tweak values, assert each instance's `StaticBody3D` box contains the
  rendered sub-part AABB within a tolerance. This is the regression test A2 has
  never had, and it would have caught all three historical drift bugs.
- `test_hull_rescale_relays_out_locomotion()` â€” place wheels, rescale the hull
  2Ã—, assert the outermost station moved. Pins A4.
- `test_locomotion_survives_a_blueprint_round_trip()` â€” save/load a design of
  each type, assert station positions match the freshly-placed ones. Pins A5.

### 2.6 Risks specific to the rearchitecture

- **R5 â€” behavioural drift during the factoring.** Ten branches carry a lot of
  hard-won hand-tuning (the comments in `update_locomotion()` are a changelog of
  visual bugs). Mitigation: **capture golden station positions for all ten types
  at three hull sizes before touching anything**, as a test fixture; the
  factoring must reproduce them exactly. Any intentional change gets made after,
  as its own commit.
- **R6 â€” scope creep into `visual_builder.gd`.** The builders are 1,400+ lines
  of working geometry. Item (3)'s shim exists specifically so this pass does not
  touch them. Hold that line.
- **R7 â€” blueprint compatibility.** Item (5) changes what locomotion means on
  disk. Old saves must keep loading; add a fixture blueprint per type from
  *before* the change and assert it still reconstructs.

---

## 3. Phase 0 â€” Systems pass (do this first, standalone commit)

No new types. Nothing new authored. Purely making the existing ten behave like
a designed system. This is the highest value-per-line work in the whole plan.

**0.1 â€” Fill out `TERRAIN_SPEED_MULTIPLIERS` to all 10 types.** Proposed rows,
to be tuned; the principle is that every locomotor must be clearly *good* at
something and clearly *bad* at something:

```
"hover_engine":       marsh 1.15, rocky 0.55, snow_mud 1.1,  sand 1.15, gravel 1.0,  forest 0.45, ice 1.2
"helicopter_rotors":  all 1.0 EXCEPT forest 0.85            (rotor clearance)
"fixed_wing_engine":  all 1.0                               (flat by design â€” document it)
"ornithopter_wing":   all 1.0 EXCEPT forest 0.9
"buoyant_envelope":   all 1.0                               (flat by design)
"naval_propeller":    n/a on land â€” see 0.2
```

The airborne types being *near*-flat is correct and should stay; the point is
that it becomes an explicit, commented design statement instead of an
accidental `1.0` fallback. `hover_engine` is the one that genuinely needs real
numbers â€” ground-effect lift ignoring marsh/snow but hating rocky is the whole
character of the thing and it currently has none.

**0.2 â€” Decide the naval/land question.** `naval_propeller` never touches the
terrain table because it never touches land. Either give it an explicit
`{}`-with-comment entry, or add a `TERRAIN_APPLIES_TO` guard so the fallback is
intentional rather than incidental. Prefer the explicit entry â€” cheaper, and it
makes the table a complete inventory.

**0.3 â€” Trait cleanup.** Three options per dead trait; recommendation in bold:
- `high_speed` â†’ **wire it**: a flat speed bonus + a turn-rate penalty in
  `battle_unit.gd`, so "fast but can't corner" becomes a real tradeoff that
  `wheels` and `fixed_wing_engine` share.
- `rotary_wing` â†’ **wire it** to the existing rotor-spin animation branch in
  `battle_unit.gd` (which currently does a by-name `get_node_or_null()` lookup â€”
  see R1 in the rebuild plan). Trait-driven is more robust than name-driven.
- `flapping_wing` â†’ **keep as pure flavour**, but comment it as such.

**0.4 â€” Give the five capacity-less types a capacity term** in
`get_locomotion_contribs()`, so every locomotion tweak moves both thrust and
payload. Suggested: rotors `units * blades/4 * length * 60`, fixed-wing
`count/2 * compression * 80`, ornithopter `wingspan * 70`, naval
`count/2 * pitch * 120`, envelope `count/2 * pitch * 90`. Numbers to be
balance-checked against the existing `base_weight_capacity` values so the
totals don't blow past `naval_propeller`'s 800/`buoyant_envelope`'s 1100.

**0.5 â€” Differentiate `naval_propeller` vs `buoyant_envelope` tweaks.** Keep
the shared pylon-prop geometry (that rebuild was right), but add one
type-unique slider each: naval gets **`kort_nozzle` (bool)** â€” thrust up,
top speed down; envelope gets **`envelope_volume`** â€” capacity up, thrust
efficiency down. One slider each is enough to make them distinct decisions.

**0.6 â€” Tests.** Add to `prototype/run_tests.gd`:
- `test_every_locomotion_type_has_terrain_character()` â€” iterate all catalog
  locomotion ids; assert each has a `TERRAIN_SPEED_MULTIPLIERS` entry, and that
  the entry is not uniformly 1.0 unless it is in a documented flat-by-design
  allowlist.
- `test_every_declared_locomotion_trait_is_consumed()` â€” collect traits from
  the catalog, grep-equivalent assert each appears in a consumer set. Prevents
  G2 recurring.
- `test_every_locomotion_tweak_moves_a_stat()` â€” for each type, for each tweak,
  perturb it from default and assert either thrust, capacity, weight or cost
  changes. Catches cosmetic-slider drift like `wing_sweep`.

---

## 4. Phase 1 â€” Roster expansion (10 â†’ 17)

Target shape, mirroring the weapons roster's role-group depth:

| domain | now | target | additions |
|---|---|---|---|
| Ground | 3 | **5** | half-track, rocker-bogie |
| Hover | 1 | **3** | air-cushion skirt, anti-grav plate |
| Naval | 1 | **3** | hydrofoil, water-jet |
| Amphibious | 1 | **2** | pontoon wheels |
| Air | 4 | 4 | â€” (already deepest) |

Each new type ships with: a full terrain row, **3+ tweaks that all feed
`get_locomotion_contribs()`**, authored multi-part meshes following the rebuild
plan's conventions, and a catalog comment explaining what decision it exists to
offer. Nothing is added that is merely a stat reshuffle of an existing type.

### Ground

**`half_track`** â€” the explicit compromise slot. Wheels' gravel/road speed with
tracks' marsh tolerance, at a capacity between the two. Historically obvious
(Sd.Kfz. 251, M3), and it makes the wheels-vs-treads decision a spectrum instead
of a binary.
- capacity ~500, terrain: marsh 0.4, rocky 0.5, snow_mud 0.6, sand 0.55,
  gravel 1.1, forest 0.5, ice 0.45
- tweaks: `bogie_count`, `front_axle_size`, `tread_width`
- parts: reuses `wheel_hub` + `tread_*`; only a new fender/frame piece needed.

**`rocker_bogie`** â€” the terrain specialist. Slow everywhere, near-immune to
rocky/forest penalties. High capacity, low thrust. The answer to a map whose
best ground is broken ground.
- terrain: rocky 1.15, forest 1.0, marsh 0.5, gravel 0.8
- tweaks: `bogie_pairs`, `arm_length`, `wheel_size`
- parts: `rg_*` prefixed parts already exist in the asset list â€” check reuse
  before authoring.

### Hover

**`air_cushion_skirt`** â€” a real hovercraft, not a sci-fi pad. Big footprint,
crosses water *and* marsh at full speed, punished hard on rocky/forest. Should
carry `amphibious` so it routes onto the combined navmesh.
- terrain: marsh 1.2, snow_mud 1.15, sand 1.1, ice 1.25, rocky 0.4, forest 0.35
- tweaks: `skirt_diameter`, `lift_fan_count`, `plenum_pressure`

**`anti_grav_plate`** â€” the crystal-expensive terrain-agnostic option. Flat 1.0
everywhere (the one type where flat is the *point*), low capacity, high cost.
The rebuild removed an earlier anti-grav ring; this reintroduces it as a
designed sink for crystal rather than as a free upgrade.
- tweaks: `plate_count`, `field_strength`, `stabilizer_ring` (bool)

### Naval

**`hydrofoil`** â€” fast, poor capacity, high draught penalty so it can't work
shallow water. Gives the naval group a speed/fragility axis it entirely lacks.
- interacts with `HULL_DRAUGHT_DEFAULT` / `SHALLOW_WATER_DRAUGHT_THRESHOLD`
- tweaks: `foil_span`, `strut_height`, `foil_count`

**`water_jet`** â€” the inverse: shallow-capable, high thrust, efficiency falls
off sharply when loaded. Pairs against the hydrofoil as deep-fast vs
shallow-strong.
- tweaks: `intake_size`, `nozzle_count`, `reverser` (bool)

### Amphibious

**`pontoon_wheels`** â€” a light counterpart to the heavy `screw_drive`. Cheap,
low capacity, mediocre on both land and water but blocked by neither. The
scout-tier amphibious option.
- tweaks: `pontoon_size`, `axle_count`, `paddle_vanes` (bool)

---

## 5. Phase 2 â€” Mesh consistency pass

Runs after Phase 1, or interleaved per-type. Not urgent â€” `ff757ef`'s LOD
regeneration on baked modules already handles the distance case, so this is
about **close-up authoring consistency**, not framerate.

**Direction set by Chris, 2026-08-01: "feel free to re-author the existing
models to higher detail to maintain a throughline."** So this pass levels the
roster *up*, not down. The old framing â€” decimate the heavy parts to a budget â€”
is superseded: `ff757ef` removed the performance argument for it, and cutting
`tracked_treads` down to meet `rotor_blade` would flatten the whole locomotion
group below the standard the reworked weapons now set.

- **The target is the reworked-weapons standard**, not a triangle ceiling. The
  M230 and AMR passes are the reference for what a part should read like at
  Design Lab zoom.
- **Bring the floor up.** `rotor_blade` @ 12 tris, `leg_foot` @ 88,
  `hover_skirt` @ 92 and `naval_propeller` @ 120 are flat placeholders next to
  `tracked_treads` @ 3,792. These get real geometry: blade twist and taper, a
  segmented foot pad with a real sole, a skirt with actual profile.
- **Leave the heavy parts alone** unless the density is bevel-segment bulk that
  buys nothing at silhouette scale â€” the `bevel_segments=1` check from the armor
  greeble pass, applied as a *quality* question rather than a budget one.
- **Watch instance counts, not totals.** `wheel_hub` is drawn 4â€“48Ã— per unit and
  `rotor_blade` 2â€“32Ã—; detail added there multiplies. The LOD regeneration
  handles distance, so the constraint is authoring time and close-up read, but
  a part instanced 48Ã— still deserves more scrutiny than a one-off gearbox.
- Re-run `prototype/scratch/probe_polycount.gd` before and after; record the
  totals in `PROGRESS.md` the way the weapons pass did. Expect the locomotion
  total to **rise**, and note that as intended rather than as a regression.

---

## 6. Sequencing & commits

1. **Commit A â€” systems pass.** Phase 0 entire (0.1â€“0.6). No new types, no new
   art. Full `run_tests.gd` run must be green (note: `test_target_dummies_
   actually_take_damage` is a documented known failure from 2026-07-21, and the
   lake-pathfinding suite flakes under CPU contention â€” kill stale Godot
   processes before judging a run).
2. **Commit B â€” golden-layout fixture.** Â§2.5's station-position test written
   against the *current* code, capturing all 10 types at 3 hull sizes. Pure
   test addition, no production change. This is the safety net for Commit C and
   must land first (R5).
3. **Commit C â€” placement factoring.** Â§2.3 items (1)(2)(3): `LocomotionLayout`,
   the generic loop, `MountStation` + the loose-key shim. Commit B's golden
   values must reproduce **exactly** â€” no visual changes ride along.
4. **Commit D â€” collider sourcing + re-layout.** Â§2.3 items (4)(5): colliders
   sized from the built mesh's real AABB, `refresh_locomotion()` wired into
   `gizmo_3d.gd`'s rescale and into blueprint load, duplicated running-gear
   block in `blueprint_manager.gd` deleted. This one *does* change behaviour
   (A2/A4/A5 are bugs), so the golden fixture gets updated deliberately here
   with each delta explained in the commit message.
5. **Commit E â€” ground pair.** `half_track`, `rocker_bogie` + tests. First real
   exercise of the new layout data path â€” if either needs a code change rather
   than a data declaration, the factoring missed a pattern; fix it here.
6. **Commit F â€” hover pair.** `air_cushion_skirt`, `anti_grav_plate` + tests.
7. **Commit G â€” naval pair.** `hydrofoil`, `water_jet` + tests. Includes the
   draught interaction, which is the riskiest single item in the plan.
8. **Commit H â€” `pontoon_wheels`** + tests.
9. **Commit I â€” mesh consistency pass** + `PROGRESS.md` catch-up.

Direct to `master` each time, per standing project convention. Staging must stay
selective: the tree carries pre-existing untracked `prototype/scratch/probe_*.gd`
and `scratch/*.png` captures, plus another session's in-flight UI-stamp work
(`ui_stamp.gd`, `main_menu.gd`, `stat_calculator.gd`, `parts_menu.gd`,
`drag_drop_manager.gd`) that must **not** be swept into these commits.

## 7. Risks

- **R1 â€” navmesh count.** `air_cushion_skirt` and `pontoon_wheels` both want
  amphibious routing; confirm `terrain_builder.gd`'s `build_navmeshes()` and
  `skirmish.gd:1561-1574`'s accessors need no new map, only reuse of the
  existing amphibious one. Expected fine, but check before authoring.
- **R2 â€” draught.** `hydrofoil` is the first locomotor that would be *excluded*
  from water it can see. Verify how `SHALLOW_WATER_DRAUGHT_THRESHOLD` is
  enforced at pathing time; if it isn't, this becomes a real feature and the
  hydrofoil should be deferred to its own commit rather than bundled.
- **R3 â€” 17 types vs UI.** `parts_menu.gd` groups locomotion into 4 buckets.
  17 entries across 4 buckets may need the drawer-collapse work another session
  is currently doing. Coordinate before Commit B.
- **R4 â€” balance drift.** Phase 0.4 adds capacity to five types that had none;
  that moves every existing airborne blueprint's numbers. Re-check the
  overload-penalty curve in `get_base_weight_capacity()` after 0.4 lands, and
  expect to retune `base_weight_capacity` constants alongside it.

