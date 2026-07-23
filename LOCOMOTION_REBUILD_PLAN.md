# Locomotion Modules — Modular Rebuild & Running-Gear Refinement

Status snapshot (updated 2026-07-23): **Phase 1 (removal) is complete. Phase 2
(Blender parts) is substantially complete — most locomotion sub-parts across all
10 kept types are authored and in the parts library, plus the wheels-specific
`wheel_driveshaft`/`wheel_gearbox` running-gear parts (see Phase 4). Phase 3
(running gear) is done for wheels only, still generic/slab for the other 4
running-gear types. Phase 4 (visual builders + tweak plumbing) is DONE and
battle-tested for `wheels` — treat it as the reference implementation; the other
9 types still run on their pre-rebuild procedural/monolithic paths and need the
same treatment. Phase 5 (spec-driven UI) is DONE for `wheels` specifically (NOT
via the generic spec-driven system originally envisioned — see Phase 5 notes,
there's a real design fork here worth reading before continuing).** This file is
the resumable spec for finishing the remaining 9 types — written so a fresh
session can pick up without re-deriving the architecture or re-discovering the
bugs already found and fixed once on wheels.

**Next up when resuming: `tracked_treads`**, using the wheels implementation as
the template (see Phase 4 for the full list of non-obvious bugs that pattern
already ran into once — expect several of them to recur for treads/legs/rotors/
etc. since they share the same `update_locomotion()`/popup/mirroring
infrastructure).

## Context (why this change)

The Design Lab builds a unit from modules in three categories: weapons, utility, and
**locomotion**. Weapons/utility were recently rebuilt so each renders as an assembly of
**multiple component GLB sub-parts** whose shape responds to per-type **tweak** sliders/toggles
(caliber, barrel count, tube count…). Locomotion was left behind: every locomotion type still
renders (rendered) as a single monolithic authored `.glb`, and its "tweaks" were a bespoke
1-size + 1-count panel that only uniformly scaled the whole blob or changed how many copies
were placed; five types had no tweaks at all.

Chris wants locomotion brought to parity: **remove** rhomboid tracks / omni wheels / anti-grav
rings (DONE), and **rebuild the remaining 10 types** as multi-part meshes tweakable per type
(wheels by wheel size / axle count / wheels-per-axle; helicopter rotors by blade count / blade
length / optional duct; sensible per-type tweaks for the rest). He also wants the **running
gear** chassis that ground locomotion spawns to be **smaller, less obtrusive, and more
geometrically detailed per type** than the current full-footprint slab.

**Confirmed decisions:** (1) rebuild **all 10** kept types this pass; (2) running gear =
**per-type tailored mounts**; (3) construction = **authored GLB sub-parts built in Blender**
(matching the weapon pipeline).

Project is **Godot 4.3 / GDScript**. Core files under `prototype/scripts/`.

## Architecture facts (verified during exploration — still true post-Phase-1)

- **Monolithic gate.** `VisualBuilder.build_visual()` (`prototype/scripts/visual_builder.gd`,
  currently around line ~129-211 post-edits — re-check line numbers, they've shifted from the
  Phase-1 deletions) loads a whole-module `<type_id>.glb` and returns early unless `type_id` is
  in a 17-weapon exclusion list (search for the ternary near `_part(type_id)`). Every locomotion
  type has a monolithic GLB, so it takes the early return — the procedural locomotion builders
  (`_build_wheels`, `_build_tracked_treads`, `_build_helicopter_rotors`, `_build_hover_engine`,
  `_build_legs`, `_build_fixed_wing_engine`, `_build_ornithopter_wing`, `_build_naval_propeller`,
  `_build_buoyant_envelope`, `_build_screw_drive`; dispatched near the bottom of `build_visual`)
  are currently **dead fallback code**. **IMPORTANT: line numbers throughout this doc were
  accurate before Phase 1's deletions shifted everything below each edit — re-grep for symbol
  names, don't trust absolute line numbers from here on.**
- **Weapon pattern to copy.** Schema `TWEAK_SPECS` in `stat_calculator.gd` (grep for
  `const TWEAK_SPECS`); UI `_generate_custom_tweaks`; flow: widget → `data.tweaks[name]` →
  `_on_tweak_changed` → `VisualBuilder.rebuild_visual` → `build_visual(...tweaks)`. Assembly
  reads `tweaks.get(name,default)` and scales/positions/**repeats** sub-parts. Helpers in
  `visual_builder.gd`: `_part()`, `_mesh_inst()`, `_fit_scale()`, `_build_tapered_blade_mesh()`.
  No shared repeat helper exists yet (see Phase 4 — `_repeat_along_axis()` / `_ring_of()` to add).
- **Placement.** `module_placer.update_locomotion()` places multiple single-instance modules
  along the hull and mirrors L/R via `_apply_mirror_flip`. `_place_weapon()` calls
  `VisualBuilder.build_visual(...)` currently with **no tweaks dict** — this needs to change
  (Phase 4).
- **Save/load & battle.** `blueprint_manager.reconstruct_vehicle` re-spawns each saved instance
  from `mod.tweaks`/position and does **not** re-run `update_locomotion`. So per-instance
  geometry tweaks **must be written into each instance's `ModuleData.tweaks` at placement time**
  to survive save/load/battle. Battle stats read `locomotion_settings` `count`/`width` for
  thrust/capacity (`battle_unit.gd`, search `thrust_contrib`/`capacity_contrib`) and sidebar
  capacity (`stat_calculator.gd`, search `capacity_contrib`).
- **Running gear.** `VisualBuilder.build_running_gear()` is one `BoxMesh` slab; sized by
  `ModuleCatalog.get_running_gear_size()` from constants `RUNNING_GEAR_XZ_INSET` (=0.95) etc.
  **Battle grounding reads `get_running_gear_size()` directly, not the visual mesh**
  (`battle_unit.gd`, search `RunningGearCollisionShape3D`) — so the visual can be redesigned
  freely as long as the returned `StaticBody3D` stays named `"RunningGear"` with a box collider
  whose bounds equal `get_running_gear_size()`.
- **Blender pipeline.** `prototype/tools/blender/build_meshes.py` → `generate_parts()` (near the
  end of the file, before the hull-generation section which is commented out) authors each
  single-mesh kit GLB via `export_and_cleanup(build_X(...), PARTS_DIR, "name")`. Existing
  locomotion kit builders: `build_wheel` (has `spokes`, `groove_depth` params already), also
  `build_leg_segment`, `build_hover_ring`, `build_tread_plate`, `build_screw_drum`. Run headless:
  `UPBGE-0.30-windows-x86_64\blender.exe --background --python tools\blender\build_meshes.py`
  (run from `prototype/`). `MeshAssetLoader.get_part_mesh()` returns only the **first**
  MeshInstance3D in a GLB → **each authored GLB must be a single joined object**; multi-piece
  mounts are composed at runtime from several `_part()` calls in GDScript, never as one
  multi-object GLB.
- **Shared bmesh helpers already in `build_meshes.py`** (reuse these, don't reinvent): `add_box`,
  `add_cyl_y` (vertical), `add_cyl_axis` (horizontal, along Godot x or z), `add_ring` (torus),
  `greeble_bolt_ring`, `bevel_sharp_edges`, `hull_reference_dim`, `tiered_bevel_width`,
  `make_object_from_bmesh`, `finalize` (single material), `finalize_dual` (two material slots —
  not needed for these small kit parts). Coordinate convention: `GV(x,y,z)` / `GS(sx,sy,sz)`
  convert Godot-space args to raw Blender-space; every helper already takes Godot-space
  coordinates, so author calls exactly like the existing `build_wheel`/`build_screw_drum` code.
- **Saved loadouts safe.** `data/loadout/*.json` use only `wheels` + `tracked_treads`; no removed
  type was referenced — already verified true.

## Design model (resolves the instance-vs-single-module question)

Keep the **existing instance-based placement**. A "type" still spawns N module instances along
the hull (wheels/legs per axle-position × 2 sides, rotors/props/pads per unit). This preserves
mirroring, physics, blueprint save/load, and the existing stat math with minimal change. Two
tweak *roles*:

- **Placement counts** (`num_axles`, `leg_count`, `rotor_units`, `pad_count`, `prop_count`,
  `drum_count`) → number of instances spawned by `update_locomotion` (as today's `count` does).
- **Per-instance geometry** (`wheel_size`, `wheels_per_axle`, `blade_count`, `blade_length`,
  `duct`, `road_wheel_count`, `foot_size`, `fan_blades`, `rib_count`, `kort_nozzle`, …) → sub-part
  count/scale/visibility **inside one instance's `build_visual`**, exactly like weapon
  `barrel_count`. These are written to each instance's `ModuleData.tweaks` so they survive
  save/load/battle.

This keeps stat coupling honest without double-counting: base weight/capacity/thrust already
scale by instance count; only per-instance clusters (e.g. `wheels_per_axle`) add a small
multiplier.

Authored-GLB caveat: baked GLBs suit **discrete instancing** (N blades/wheels), **scaling**
(scale the instance), and **toggles** (show/hide an authored part). Continuous shape morphs
(screw `helix_turns`) need authored **variant meshes** or are dropped — flagged per type below.

---

## Progress

### ✅ Phase 1 — Remove `omni_wheels`, `rhomboid_treads`, `anti_grav` (COMPLETE)

All done, uncommitted in the working tree. Changes made:
- `module_catalog.gd`: deleted the 3 catalog entries; removed them from
  `LOCOMOTION_TYPES_USING_RUNNING_GEAR` and `TERRAIN_SPEED_MULTIPLIERS`.
- `module_placer.gd`: deleted `default_locomotion_settings` entries and the 3
  `update_locomotion` branches; cleaned the dead ground-seat `elif` references.
- `visual_builder.gd`: deleted the 3 dispatch cases and the 3 `_build_X` functions
  (`_build_omni_wheels`, `_build_rhomboid_treads`, `_build_anti_grav`).
- `stat_calculator.gd`: deleted the 3 panel branches and the 3 `_apply_tweaks` branches
  (this whole panel gets replaced wholesale in Phase 5 anyway); updated the capacity-readout
  type lists.
- `battle_unit.gd`: dropped `omni_wheels`/`rhomboid_treads` references; **removed the entire
  `is_omni` machinery** (declaration, trait derivation, and the strafing branch in
  `_steer_towards`) since no remaining type carries the `"omni"` trait.
- `blueprint_manager.gd`: cleaned the dead ground-seat `elif` references (historical comment
  left in place, harmless).
- `run_tests.gd`: removed the 2 suite-call registrations; deleted
  `test_rhomboid_treads_spawns_and_differentiates_from_tracked_treads()` and
  `test_omni_wheels_can_strafe_sideways_without_turning()` entirely; fixed
  `test_locomotion_tweak_parity` (loop list + comment + PASS string, now just
  `["legs", "hover_engine"]`); fixed `test_trait_system_composability` (swapped
  `"anti_grav"` → `"hover_engine"` in the `get_traits()` call — both carry `"hovering"` so the
  assertion still holds).
- **Assets removed**: `git rm` on `omni_wheels.glb`, `rhomboid_treads.glb`, `anti_grav.glb`,
  `antigrav_ring.glb` (+ their `.glb.import` sidecars).
- `tools/blender/build_meshes.py`: deleted the `antigrav_ring` manifest line in
  `generate_parts()` (the `build_hover_ring` function itself stays — still used for
  `hover_ring`).
- Scratch scripts (`prototype/scratch/verify_locomotion_tweaks.gd`,
  `prototype/scratch/lab_interaction_probe.gd`): updated to drop the removed types (optional
  tidiness, done anyway since it was cheap).

**Verification NOT yet run** for Phase 1 in isolation — recommend running `run_tests.gd`
headless once Phase 1 is committed/before starting Phase 2, to catch any missed reference
before piling more changes on top:
```
cd prototype
Godot_v4.3-stable_win64_console.exe --headless --script run_tests.gd --path .
```

### ✅ Phase 2 — Author new GLB sub-parts (Blender) — SUBSTANTIALLY COMPLETE

Nearly every part listed below has been authored into `build_meshes.py` and
registered in `generate_parts()` — confirmed present in
`prototype/assets/models/parts/` with matching `.glb.import` sidecars (reimport
already run). Builder functions: `build_wheel_axle_bar`, `build_rotor_mast`,
`build_rotor_hub`, `build_rotor_blade`, `build_rotor_duct_ring`,
`build_drive_sprocket`, `build_leg_foot`, `build_hover_fan`, `build_hover_skirt`,
`build_engine_nacelle`, `build_engine_fan`, `build_exhaust_cone`,
`build_wing_shoulder`, `build_wing_membrane`, `build_wing_rib`,
`build_prop_housing`, `build_kort_nozzle`, `build_cruise_nacelle`,
`build_outrigger_strut`, `build_tail_fin`, `build_rg_susp_beam`,
`build_rg_axle_stub`, `build_rg_track_frame`, `build_rg_road_bogie`,
`build_rg_hip_socket`, `build_rg_screw_cradle`, `build_locomotion_mount_box`
(exported as `rg_mount_box`, generic multi-type running-gear mount), plus the
wheels-specific `build_wheel_driveshaft`/`build_wheel_gearbox` added in Phase 4
(see below - NOT the generic `rg_mount_box`, wheels has its own dedicated pair
now). **`wheel_axle_bar` itself ended up unused** — the wheels running-gear
redesign in Phase 4 went a different direction (driveshaft+gearbox instead of
an axle bar) and never called `_part("wheel_axle_bar")`; harmless (procedural-
fallback convention means an unused authored part is just dead weight, not a
bug) but worth knowing before assuming it's wired up somewhere.

Screw drum variants (`screw_drum_t2..t5`) were NOT authored — `screw_drive`'s
`helix_turns` tweak was dropped per the plan's own fallback clause (kept
`screw_drum`'s single authored `turns=3.0`, scale-only tweaks). Not yet verified
whether the LOCOMOTION_TWEAK_SPECS entry for `screw_drive` (see Phase 5) still
lists `helix_turns` — check before wiring that type's UI.

Build + reimport workflow, already run once for the parts above and safe to
re-run any time more parts are added (procedural fallbacks mean a half-finished
library never breaks anything):
```
cd prototype
UPBGE-0.30-windows-x86_64\blender.exe --background --python tools\blender\build_meshes.py
Godot_v4.3-stable_win64_console.exe --path . --headless --editor --import --quit
```

**Actual outcome for wheels — a real fork from the original plan below, read
this before starting treads/legs/screw/hover:** `VisualBuilder.build_running_gear()`
was deliberately left untouched (still just a `StaticBody3D` + `CollisionShape3D`,
zero visual mesh — it only exists for grounding/raycast, exactly as Phase 1 left
it). The "running gear" visual for wheels is NOT a shared hull-level chassis part
at all; it's built as **part of each wheel module's own visual**, inside
`_build_wheels()` (`visual_builder.gd`) — a `wheel_driveshaft` box running from
the hull mount point down to a `wheel_gearbox` box, per wheel-cluster instance
(so it naturally scales/repositions with `wheel_size` and mirrors correctly with
the module). This reads better for wheels (a wheel-specific mount that moves
with each wheel, not a shared beam spanning the whole axle row) but it means
**the original per-type `build_running_gear()` `match type_id:` plan below is
still valid for treads/legs/screw/hover** (their running gear genuinely is a
shared per-side or per-hull chassis, not per-instance) — just don't assume
wheels already proves that pattern out; it went a different, arguably simpler
route. Decide per-type which pattern fits before implementing each one.

Original plan (still the right shape for treads/legs/screw/hover):
- Keep `ModuleCatalog.get_running_gear_size()` return **unchanged** (collider/grounding box) so
  all mount offsets, hull re-seat, and battle physics stay consistent. Add visual-only fraction
  constants so the *authored visual* is smaller than the collider box (e.g. beam span ≈ 0.6×,
  height ≈ 0.7×). This is the "smaller/less obtrusive" knob with zero grounding risk.
- Change `VisualBuilder.build_running_gear(parent, dims, color, layer=1, type_id="")` to
  `match type_id:` and assemble per-type authored mounts (`_part("rg_*")`, positioned within
  `dims`, procedural slab fallback if a GLB is missing). **Always** append the box collider
  sized to `dims` and keep the node named `"RunningGear"`, `collision_mask=0`, honoring the
  `layer` arg (0 in battle — preserves the "bouncing off its own chassis" fix).
- Per-type: treads = side track-frame + road-wheel bogies + drive sprocket (parts already
  authored: `rg_track_frame`, `rg_road_bogie`, `drive_sprocket`); legs = hip girdle + sockets
  (`rg_hip_socket`); screw = cradle bearings (`rg_screw_cradle`);
  **hover_engine = collider-only** (no visual — removes the slab, keeps grounding box).
  `rg_susp_beam`/`rg_axle_stub` were authored for the originally-planned wheels beam-and-stub
  mount but are now unused, since wheels went the per-instance driveshaft/gearbox route instead
  — repurpose them for treads/legs if they fit, or leave them as spare parts.
- Callers: pass `type_id` through at the two `build_running_gear(...)` call sites in
  `module_placer.gd` (inside `update_locomotion`) and `blueprint_manager.gd` (inside
  `reconstruct_vehicle`); `battle_unit.gd`'s `RunningGearCollisionShape3D` construction and the
  teardown-by-name in `module_placer.gd` are unaffected (they never touch the visual).
- Kept running-gear set after Phase-1 removals: `wheels, tracked_treads, legs, screw_drive,
  hover_engine` (already reflected in `LOCOMOTION_TYPES_USING_RUNNING_GEAR`).

### ✅ Phase 4 — Rebuild locomotion visual builders + tweak plumbing — DONE for `wheels`, shared infra benefits all 10

The dispatch-level fixes below are NOT per-type — they fix a bug that was silently
breaking **every** locomotion type, not just wheels, so treads/legs/rotors/etc.
inherit the fix for free. The per-type `_build_X()` body work (last bullet) is
still only done for `wheels`.

- **Monolithic gate — DONE, and it was hiding a real bug.** `build_visual()`
  (`visual_builder.gd`) now has a dedicated `LOCOMOTION_MODULAR_TYPES` const
  (the 10 kept types) checked and dispatched **before** the giant weapon
  `if/elif/.../else` chain, with an explicit `return` — not folded into the
  older `MODULAR_ASSEMBLY_TYPES` set the monolithic-mesh gate uses. Turned out
  this mattered a lot: previously every locomotion type_id fell all the way
  through that weapon chain (since none of them ever matched a weapon branch)
  and landed in its final `else: Fallback: Simple box mesh for armor and basic
  parts` — an extra, unwanted, uncolored `BoxMesh` sized to the catalog's flat
  base size, added to EVERY locomotion instance before `_build_wheels()`/etc.
  ever got to add the real parts. Reported by Chris as "a box outboard of them
  and above, no chamfered edges" — it wasn't a failed mount attempt, it was
  this stray fallback box. The same dispatch call also wasn't passing `tweaks`
  through to most `_build_X()` calls (only `base_size` and sometimes
  `base_color`), so `wheel_size`/`blade_length`/etc. tweaks never reached the
  actual geometry at all — fixed in the same pass, now every `_build_X(parent,
  base_size, base_color, tweaks)` call gets all four args.
- **`_repeat_along_axis()` / `_ring_of()` helpers** — already existed in
  `visual_builder.gd` from before this session; `_build_wheels()` uses
  `_repeat_along_axis` for the `wheels_per_axle` cluster. Not yet exercised by
  any of the other 9 types' rebuilds (that work hasn't happened yet).
- **Tweaks threading** — `_place_weapon()` already took a `tweaks:Dictionary={}`
  param and set `data.tweaks = tweaks.duplicate()` (pre-existing). The actual
  gap was `update_locomotion()`'s wheels branch building a `geo_tweaks` dict
  and passing it to `_place_weapon()` correctly, but the DOWNSTREAM
  `build_visual()` dispatch (see monolithic-gate bullet above) dropping it on
  the floor before it ever reached `_build_wheels()`. Both ends are fixed now.
- **Wheels placement/geometry — DONE, final design differs from the original
  plan.** No `wheel_axle_bar` (authored but unused — see Phase 2 note). Each
  wheel-cluster instance renders `wheels_per_axle` `wheel_hub` copies via
  `_repeat_along_axis`, PLUS a `wheel_driveshaft` box running from the hull
  mount point down to a `wheel_gearbox` box near the wheel hub (both scaled by
  `wheel_size`) — went through several iterations before landing right:
  1. First pass reused the generic `rg_mount_box` at the wrong scale — too
     small/plain, didn't read as anything.
  2. Authored dedicated `wheel_driveshaft`/`wheel_gearbox` parts, but
     positioned them at the SAME local X as the wheel itself — they rendered
     entirely *inside* the wheel's own disc volume, invisible from every
     angle (confirmed by isolating a single wheel module with no hull).
  3. Fixed the overlap by offsetting the wheel outboard from the mount
     column — but the driveshaft box was authored pointing the wrong
     direction (extending +Y instead of -Y), so rotating it just swung it
     sideways-and-up instead of down toward the wheel; had to re-author it
     spanning Y=0 (top/pivot) to Y=-1 (bottom).
  4. Wheel hub orientation was backwards — `wheel_hub.glb`'s hub-cap/lug-bolt
     detail is authored at the mesh's outward (+Y) end, but
     `rotation.z = +PI/2` pointed that face inboard; flipped to `-PI/2`.
  5. Chris flagged the assembly as floating past the hull's silhouette and the
     driveshaft "sloping down not up into the hull" — brought the whole
     cluster inboard (smaller `hub_x_offset`), and switched the driveshaft to
     anchor at its BOTTOM (a fixed point near the gearbox) with the TOP
     computed backward from length+angle, so a longer/shallower shaft
     naturally reaches further inboard toward the hull's centerline before
     piercing the hull mesh, instead of barely grazing the mount edge.
  6. Finally: pulled `hub_x_offset` slightly negative so the wheel hub itself
     visibly overlaps into the gearbox rather than just sitting adjacent
     (Chris asked for this twice before it actually landed).
  **Current constants, all in `_build_wheels()` (`visual_builder.gd`):**
  `hub_x_offset = -0.05*wheel_size`, `gearbox_x = -0.24*wheel_size`,
  driveshaft `shaft_len = 1.0*wheel_size` at `55°` from vertical anchored at
  `(gearbox_x + 0.05*wheel_size, wheel_y, 0)`. Take these as a *starting point*
  for treads/legs, not gospel — they were tuned by eye against one specific
  hull/wheel_size combination.
- **Animation pivots** — `_build_helicopter_rotors`/`_build_naval_propeller`/
  `_build_buoyant_envelope`/`_build_ornithopter_wing` already build their named
  pivot nodes (`RotorBlades`/`PropBlades`/`WingPivot`) as part of their
  multi-part assembly. **Not verified this session** — nobody has actually
  driven these types through `update_locomotion()` and confirmed spin/flap
  animation still finds the pivot by name post-rebuild, or checked whether
  `battle_unit.gd`'s `get_child(0)` assumption (R1 below) was ever actually
  fixed. Check before assuming this is solid.
- **Per-instance vs. per-hull tweak dispatch — the real hard part, learned the
  hard way (see the whole "Non-obvious bugs" subsection below).** Every
  locomotion type needs its own answer to: which tweaks are "placement count"
  (respawn required) vs. "per-instance geometry" (cheap in-place rebuild, no
  respawn) — wheels' `wheel_size`/`wheels_per_axle` vs. `num_axles` is the
  worked example. Get this split right per-type before wiring the UI, or
  you'll reproduce the smoothness/lockup/mirror bugs below.

#### Non-obvious bugs found + fixed while building the wheels tweak system (expect several of these to recur on the next type)

These were NOT hypothetical/anticipated — every one was found via a real
Chris report or a real simulated-input test that reproduced it, in roughly the
order below. All fixes are in place and covered by regression scripts under
`prototype/scratch/verify_wheels_*.gd` (see Verification section).

1. **Stray fallback box** — see "Monolithic gate" above.
2. **Tweaks never reached geometry** — see "Tweaks threading" above.
3. **Double-scaling.** `module_placer.gd`'s `update_locomotion()` was applying
   each per-instance tweak (`tread_width`, `blade_length`, `pad_size`,
   `leg_length`, etc.) to the **outer module node's own `.scale`**, ON TOP of
   `_build_X()` already baking that same tweak into each sub-part's scale
   internally. Only `wheels` had already been updated to leave the outer node
   at `Vector3.ONE` (matching the correct pattern); the other 8 types were
   still on the old convention and got fixed in the same pass. Also
   double-counted in `module_data.gd`'s weight/cost math via
   `scale_multiplier` (which duplicated what the direct-tweak-read whitelist
   already did) — `scale_multiplier` is now left at `Vector3.ONE` /
   hull-relative-factors-only for these types.
4. **Slider drag felt "laggy"/did nothing until release, and dragging count
   would lock up the game.** Root cause: `update_locomotion()` fully
   destroys and respawns EVERY instance of a type (unlike a weapon's
   `rebuild_visual()`, which rebuilds one node in place) — calling it on
   every `value_changed` tick during a drag reselects an arbitrary respawned
   instance each tick, which relocates the floating tweak popup (it tracks
   the selected module's 3D→2D screen position every frame). A real
   mouse-drag test showed the slider settling on a near-random final value
   because the panel kept jumping out from under the cursor mid-drag.
   **Fix, and the actual architecture to copy for the next type:** split each
   type's tweaks into "size-like" (never changes instance count — always
   route through the new `update_locomotion_geometry_tweak(type_id,
   tweak_key, value)` in `module_placer.gd`, which just updates each existing
   instance's `data.tweaks` and calls `VisualBuilder.rebuild_visual()` in
   place, no respawn, cheap enough for every tick) vs. "count-like" (changes
   how many instances exist — must go through the full `update_locomotion()`
   respawn, kept **debounced to `drag_ended`**, not `value_changed`, via a
   `_loco_slider_dragging` flag in `stat_calculator.gd`).
5. **The lockup itself, separately from the debounce.** Even debounced to
   drag-end, adjusting the count slider was locking up the running game.
   Real cause: `module_placer.gd`'s `_deselect_module()` did
   `if selected_module: for child in selected_module.get_children(): ...`
   with no `is_instance_valid()` guard. A count-changing respawn
   `queue_free()`s the old (currently-selected) instance, then
   `_apply_tweaks()` `call_deferred()`s a reselect of a new one; by the time
   that deferred call reaches `_deselect_module()`, `selected_module` is a
   stale-but-non-null reference to an already-freed node — `.get_children()`
   on it throws, and with the editor's debugger attached (the normal Play
   session) an uncaught script error pauses the whole running game. Fixed
   with a proper `is_instance_valid()` guard in both `_select_module()` and
   `_deselect_module()`.
6. **Count worked going up but never back down; the dually (wheels-per-axle)
   slider silently did nothing.** Both were the SAME bug: `_apply_tweaks()`'s
   post-respawn reselect logic searched `hull.get_children()` for "first
   child matching `type_id`" — but `queue_free()`'d old instances stay in
   that list (just marked for deletion) until end-of-frame, and since they
   were added earlier than their replacements they sorted FIRST. The reselect
   reliably grabbed a doomed old instance; `on_module_selected()` then
   crashed calling `.has_meta()` on it once actually freed, leaving
   `current_selected_module` permanently pointing at garbage until the player
   manually reselected — silently no-op'ing every tweak after the first
   respawn. Fixed by skipping `child.is_queued_for_deletion()` in that search,
   plus a defensive `is_instance_valid()` check in `on_module_selected()`.
7. **Live-adjusting a mirrored (left-side) wheel's size put its
   driveshaft/gearbox on the wrong side.** `_apply_mirror_flip()` doesn't
   scale the module — it individually mirrors each of the module's CHILDREN's
   own transforms, once, at initial placement, marking them `_mirrored`. The
   new cheap `update_locomotion_geometry_tweak()` path (bug #4's fix) calls
   `VisualBuilder.rebuild_visual()`, which destroys and recreates those
   children — un-mirrored, since nothing re-ran the mirror step. Fixed by
   re-calling `_apply_mirror_flip(child)` after every rebuild, for instances
   carrying the `scale_flip_x` meta.
8. **Wheels became hard to click ("needing to be clicked very very close to
   dead center").** The click-target collider (`_place_weapon()`'s generic
   `StaticBody3D`/`CollisionShape3D`) is sized to the catalog's fixed base
   size and centered on the module's origin — but the actual wheel render is
   offset from that origin (`hub_x_offset`) and scaled by `wheel_size` (up to
   2.5×), so for anything but the exact default size the clickable box and
   the visible wheel barely overlapped. Added a wheels-specific collider
   sized/positioned from `wheel_size`/`wheels_per_axle`, generously (not
   pixel-exact). **Also has to be kept in sync inside
   `update_locomotion_geometry_tweak()`** — `rebuild_visual()` deliberately
   skips `StaticBody3D` children when rebuilding a module's mesh (so the
   collider survives visual rebuilds), which means nothing resizes it
   automatically when `wheel_size` changes live; it's updated by hand in that
   function now.

**Takeaway for the next type:** budget real time for bugs #4-8 even though
they look done for wheels — they're all in shared infrastructure
(`update_locomotion`, `_apply_tweaks`, `_select_module`,
`_apply_mirror_flip`, the click-target collider) that every locomotion type
routes through, but several of them (the collider mismatch, the mirror-lost-
on-rebuild) only manifest once a type actually HAS a `hub_x_offset`-style
asymmetric sub-part and a live-updatable size tweak — they won't show up
until you're deep into wiring the UI, not during the visual-builder work.

### ✅ Phase 5 — Wheels tweak UI + stats — DONE, but via a DIFFERENT design than planned below (real fork, read before continuing)

**The generic spec-driven system this phase originally called for was never
adopted.** `module_catalog.gd` already contains a complete, ready-to-use
`LOCOMOTION_TWEAK_SPECS` const (all 10 types, matching grammar to weapons'
`TWEAK_SPECS`) and a `get_locomotion_contribs(type_id, settings) ->
{thrust, capacity}` helper — both appear to be scaffolding from an earlier,
separate, interrupted session (found mid-way through this session, already
sitting in the codebase, not written by the wheels work described here).
**Neither is called from anywhere.** They're dead code. The wheels UI actually
shipped is bespoke, not spec-driven:

- **UI location**: NOT a dynamic container generated from a spec. Wheels reuses
  the pre-existing scene-defined `SizeContainer`/`CountContainer` HSliders
  (`UI_StatBlock.tscn`) plus one new dynamically-built `wheels_per_axle`
  slider (`stat_calculator.gd::_ready()`, no scene node for it existed). All
  three are **reparented once, at `_ready()`, into the floating
  `popup_tweaks_container`** — the same popup weapon tweaks use — instead of
  staying in the right-hand sidebar `LocomotionTweaks` panel (Chris: tweaks
  should "pop up in the main area... mirroring the weapon module behavior").
  The sidebar `LocomotionTweaks` node itself is now permanently hidden and
  effectively vestigial; its scene nodes weren't deleted (reparenting was
  simpler/lower-risk than editing `UI_StatBlock.tscn`), just emptied out.
  Because these three widgets are **persistent** (reused across selections,
  not freed/rebuilt each time like weapon tweaks), `on_module_selected()`'s
  popup-clearing sweep has an explicit exemption for them — don't remove that
  guard when adding more locomotion widgets, or the sliders get destroyed the
  first time any non-locomotion module is selected.
- **Size vs. Count architecture** (this is the part worth generalizing to the
  other 9 types, even though the UI itself stayed bespoke): `_on_size_value_changed`
  and `_on_wheels_per_axle_changed` route through the new, cheap,
  never-respawns `update_locomotion_geometry_tweak()` — smooth on every drag
  tick, matching weapon-tweak feel exactly (verified: wheel mesh scale changes
  visibly mid-drag, well before mouse-up). `_on_count_value_changed` stays on
  the full `update_locomotion()` respawn, **debounced to `drag_ended`** (not
  every `value_changed` tick) via a `_loco_slider_dragging` flag — this is
  the exact "debounce to drag-end if laggy" contingency this phase's original
  plan (below) already called out, now confirmed necessary, not hypothetical.
  A `LOCOMOTION_SIZE_KEY` const in `stat_calculator.gd` maps `type_id` →
  which settings key the shared Size slider writes (`wheel_size`,
  `tread_width`, `blade_length`, `leg_length`, `pad_size`) — reuse/extend that
  map rather than duplicating the size-vs-count split logic per type.
- **Stat coupling — done for wheels, NOT via `get_locomotion_contribs()`.**
  `module_data.gd`'s `get_weight()`/`get_cost()` whitelist already had
  `wheel_size`/`wheels_per_axle`/etc. Weight-capacity (which DIDN'T scale with
  wheel count before this session, per Chris's explicit ask that more wheels
  should carry more load) is now computed inline in both
  `stat_calculator.gd` (Design Lab live preview) and `battle_unit.gd` (real
  battle stats) as `(num_axles * wheels_per_axle) / 4.0`, duplicated in both
  places rather than centralized — the plan's `get_locomotion_contribs()`
  idea would be the right fix for that duplication, but its EXISTING formula
  (found already in `module_catalog.gd`) uses a hardcoded `*100.0` flat rate
  instead of each type's own catalog `base_weight_capacity`, which doesn't
  match how every other locomotion type's capacity is computed — don't wire
  it in as-is without reconciling that mismatch first (would silently
  rebalance capacity for every type at once, untested).
  Also found and fixed a real gap while touching this:
  `blueprint_manager.gd::reconstruct_vehicle()` (the actual battle-spawn path)
  never set `locomotion_type`/`locomotion_settings` meta on the hull at all —
  turned out harmless for `battle_unit.gd` specifically (it reads those
  straight from `blueprint_data` in its own `setup()`, not via hull meta) but
  the meta is now set anyway for consistency, in case anything else ends up
  reading it off a battle-reconstructed hull.
- **Back-compat** — done: every settings read in `module_placer.gd`/
  `visual_builder.gd` for wheels falls back `settings.get("wheel_size",
  settings.get("size", 1.0))` style; old saved blueprints storing `size`/
  `count` still work.

Original plan for reference (still describes the *shape* of a real fix for
the sidebar-vs-popup and spec-driven-generation questions, if that direction
is revisited for the other 9 types instead of repeating wheels' bespoke
per-type wiring 9 more times):
- Add `LOCOMOTION_TWEAK_SPECS` (same grammar as `TWEAK_SPECS`) — **already exists**,
  see above, just unused; audit it against wheels' actual final key names
  (`num_axles` not `count`, etc.) before trusting it for another type.
- Generalize the locomotion panel: build sliders/CheckButtons from the schema at
  selection time (reuse `_generate_custom_tweaks`'s widget-construction code).
  Route control changes → assemble a fresh `settings` dict → `root.update_locomotion(type_id, settings)`
  for count-like tweaks, `root.update_locomotion_geometry_tweak(type_id, key, value)` for
  size-like ones (now that this split/these functions exist).
  Remove the (now-vestigial, emptied-not-deleted) static `SizeContainer`/`CountContainer`
  scene nodes from `UI_StatBlock.tscn` for real, and their dedicated handlers in
  `stat_calculator.gd`, if a fully generic system replaces them.

### Per-type tweak specs (target design — implement in Phase 4/5)

| type | tweaks (name: range) | placement count | notes |
|---|---|---|---|
| wheels | ✅ IMPLEMENTED — wheel_size 0.5–2.5, num_axles 4–8 (step 2), wheels_per_axle 1–2 | num_axles (total across both sides; see Phase 5) | ranges tightened from the original spec's 2–8/1–3 to match Chris's exact ask (4-8 total wheels, dually not triple) |
| helicopter_rotors | blade_count 2–8, blade_length 0.5–2.0, duct bool, rotor_units 1–4 | rotor_units | user-specified; duct = `rotor_duct_ring` toggle |
| tracked_treads | tread_width 0.5–2.5, road_wheel_count 3–8, drive_sprocket bool | 2 | width key→tread_width (keep back-compat fallback to old `width` key) |
| legs | leg_length 0.5–2.5, leg_count 2–8, foot_size 0.5–2.0 | leg_count×… | leg_count keeps existing `count` semantics (rename key, same meaning) |
| hover_engine | pad_size 0.5–2.5, pad_count 2–4, skirt bool | pad_count | collider-only running gear (Phase 3) |
| fixed_wing_engine | nacelle_size 0.5–2.5, fan_blades 4–10, afterburner bool | 2 | afterburner = emissive exhaust |
| ornithopter_wing | wingspan 0.5–2.5, rib_count 2–6, wing_sweep 0.5–1.5 | 2 | keep `WingPivot` name |
| naval_propeller | prop_size 0.5–2.5, blade_count 2–6, prop_count 1–4, kort_nozzle bool | prop_count | keep `PropBlades` name |
| buoyant_envelope | motor_size 0.5–2.5, prop_blades 2–4, tail_fins bool | 2 | |
| screw_drive | drum_width 0.5–2.5, drum_count 1–2, (helix_turns 2–5 optional) | drum_count | helix_turns optional — only if authored variants (Phase 2) are built |

## Risks (carry forward into Phases 2-6)

- **R1 Rotor/prop spin** — after rebuild the animated pivot is no longer reliably
  `get_child(0)`; switch `battle_unit.gd` spin-lookup code to by-name (`get_node_or_null`)
  for every branch, not just the one that already does it. **Still open / not verified this
  session** — the named pivots exist in the builders (see Phase 4) but nobody has confirmed
  `battle_unit.gd`'s lookup side actually matches.
- **R2 Save/load key rename** — old blueprints store `size`/`count`; add back-compat fallback
  reads (and/or consider rebuilding locomotion via `update_locomotion` on blueprint load instead
  of trusting saved per-instance state, if desync issues surface). **Done for wheels** — every
  read falls back through `settings.get("wheel_size", settings.get("size", 1.0))` style chains.
- **R3 Stat double-count** — only per-instance clusters (`wheels_per_axle`, `blade_count`, etc.)
  go in the `module_data.gd` tweak whitelist; placement count already multiplies base stats via
  instance count, so don't also scale by placement-count tweaks in `module_data.gd`. **Done for
  wheels**, confirmed via the double-scaling bug fix in Phase 4's bug list (item 3) — that bug
  was this exact risk materializing for the OTHER 8 types (not wheels, which had already been
  fixed), caught and fixed in the same pass.
- **R4 Grounding** — never change `ModuleCatalog.get_running_gear_size()`'s return, the
  `"RunningGear"` node name, or the box collider; keep `collision_layer=0` in battle (already
  correct in existing code — don't regress it when refactoring `build_running_gear`).
  Unaffected by the wheels work (wheels' driveshaft/gearbox live on the module itself, not on
  `build_running_gear`'s output — see Phase 3's "actual outcome" note).
- **R5 Single-mesh GLB** — each authored part must be one joined object (`make_object_from_bmesh`
  on a single `bm`); compose multi-piece mounts/assemblies at runtime via multiple `_part()`
  calls, never as a multi-object GLB (the loader only reads the first `MeshInstance3D`).
- **R6 Reimport lag** — keep procedural `else:` fallbacks in every new/rewritten builder function
  until the `.glb.import` sidecars are actually generated for the new parts (Godot editor reimport
  step) — this is already the existing convention throughout `visual_builder.gd`, just make sure
  every NEW `_part("...")` call added in Phase 4 also gets a procedural fallback branch. Note
  `_part()` is actually STRICT now (asserts/hard-fails if a part fails to load, per Chris's
  explicit ask - "if it's failing to load the meshes I want it to fail, not paper over it") -
  the procedural `else:` fallback branches that remain in `_build_wheels()` etc. are for when a
  part was simply never authored yet, not as a silent-failure safety net.
- **R7 Freed-instance access after a respawn** (new, found this session) — any code that holds a
  `Node3D` reference across a locomotion respawn (`selected_module`, `current_selected_module`,
  a reselect search over `hull.get_children()`) MUST either use `is_instance_valid()` before
  touching it, or filter out `is_queued_for_deletion()` children when searching for a fresh
  instance. Two separate real bugs from this exact class this session (Phase 4 bug list items
  5 and 6) — check any new code that reselects/reacts after `update_locomotion()`.
- **R8 Mirror flip is per-child, not per-module** — `_apply_mirror_flip()` mirrors each of a
  module's children's own transforms individually (marking them `_mirrored`), it does NOT scale
  the module itself. Any code path that rebuilds a mirrored module's children after initial
  placement (e.g. a cheap in-place tweak rebuild) MUST re-call `_apply_mirror_flip(module)`
  afterward if `module.get_meta("scale_flip_x", false)`, or the rebuilt children silently
  un-mirror. See Phase 4 bug list item 7.
- **R9 Click-target collider doesn't auto-track visual changes** — `build_visual()`/
  `rebuild_visual()` deliberately skip `StaticBody3D` children when clearing/rebuilding a
  module's mesh (so the collider survives visual rebuilds), which means a per-type click-target
  override (like wheels') has to be updated BY HAND wherever that type's size-like tweaks get
  applied live, or the clickable box drifts away from the rendered geometry after the first
  drag. See Phase 4 bug list item 8.

## Verification (run from `prototype/`)

1. **Author meshes** (only needed if new/changed parts):
   `UPBGE-0.30-windows-x86_64\blender.exe --background --python tools\blender\build_meshes.py`
   → confirm new `.glb` files appear in `assets/models/parts/`. Note the script currently
   regenerates the ENTIRE parts library on every run (not incremental) — expect every `.glb` to
   get a fresh export timestamp, not just the ones you touched.
2. **Reimport**:
   `Godot_v4.3-stable_win64_console.exe --path . --headless --editor --import --quit`
   → `.glb.import` sidecars regenerate for the new files.
3. **Automated tests**:
   `Godot_v4.3-stable_win64_console.exe --headless --script run_tests.gd --path .`
   → expect exit code 0 and `ALL AUTOMATED TESTS PASSED SUCCESSFULLY!` near the end of output.
   Ignore `ERROR: Parameter "m" is null. at: mesh_get_surface_count` spam throughout — that's
   the headless dummy renderer being unable to load meshes, unrelated/pre-existing noise, not a
   real failure signal. The suite occasionally has one genuinely flaky, timing-sensitive test
   (an AI-kiting-behavior standoff-distance check) unrelated to locomotion work — rerun once
   before concluding a failure there is real.
4. **Real-input regression scripts (`prototype/scratch/verify_wheels_*.gd`)** — written this
   session specifically because several of the bugs above (drag-jank, the lockup, the
   count-only-goes-up bug, the mirror loss) were INVISIBLE to both the automated suite and to
   calling handler functions directly — they only reproduced under REAL simulated mouse-drag
   input via `Input.parse_input_event()` in a non-headless run. Treat these as the actual
   regression suite for this class of bug, and write equivalent ones for the next type before
   considering it done:
   - `verify_wheels_tweak_ui.gd` (headless OK) — drives the real UI sliders via their handler
     functions, checks resulting settings + spawned mesh count.
   - `verify_wheels_real_drag.gd`, `verify_wheels_smooth_and_no_crash.gd`,
     `verify_wheels_count_down_and_dually.gd`, `verify_wheels_mirror_survives_rebuild.gd`,
     `verify_wheels_click_target.gd` — real `InputEventMouseButton`/`InputEventMouseMotion`
     drags on the actual slider controls; **must run WITHOUT `--headless`** (needs a real
     viewport). Run via `./Godot_v4.3-stable_win64_console.exe --script scratch/verify_X.gd --path .`
   - `capture_wheel_isolated.gd`, `capture_wheel_driveshaft.gd` — visual screenshot captures
     (also non-headless) for eyeballing geometry/proportions; output under
     `prototype/progress_captures/`.
5. **Visual**: launch `res://scenes/MainLab.tscn`, place each of the 10 kept types, drag every
   tweak control, and confirm geometry changes on-screen and that the running gear reads as a
   distinct per-type mount (not the old slab). For wheels specifically this is now DONE and
   iterated to Chris's satisfaction; for the other 9 types this is still the actual bar to clear.

## Next concrete step when resuming

**Pick up `tracked_treads` next** (Chris's stated next target). Before writing any new geometry:

1. Read `_build_tracked_treads()` (`visual_builder.gd`), the `tracked_treads` branch of
   `update_locomotion()` (`module_placer.gd`), and its `LOCOMOTION_TWEAK_SPECS` entry
   (`module_catalog.gd`, currently unused dead code but the field names are a reasonable
   starting point: `tread_width`, `road_wheel_count`, `drive_sprocket` bool) to establish current
   state before proposing tweak changes — this mirrors how the wheels round started.
2. Apply the wheels lessons proactively instead of rediscovering them:
   - Split tweaks into size-like (`tread_width` → route through
     `update_locomotion_geometry_tweak()`, no respawn) vs. count-like (none currently planned for
     treads — `road_wheel_count` changes SUB-PART count within the existing 2 instances via
     `_repeat_along_axis`, not instance count, so it may ALSO belong on the no-respawn path,
     unlike wheels' `num_axles`; confirm this before wiring the UI).
   - If any tweak DOES need a respawn, debounce it to `drag_ended`, not `value_changed`.
   - Whichever sub-parts render asymmetric/offset geometry (anything like wheels'
     `hub_x_offset`), make sure the click-target collider override and the
     `_apply_mirror_flip()` re-application (R7/R8/R9 above) are both handled from the start,
     not bolted on after Chris reports them.
3. `tracked_treads` running gear: per Phase 3's "actual outcome" note, decide whether it should
   follow wheels' per-instance pattern (driveshaft/gearbox baked into `_build_tracked_treads()`
   itself) or the original shared-`build_running_gear()`-per-type-match plan — treads' running
   gear is arguably more of a shared side chassis (a track frame spanning the whole tread run)
   than a per-wheel mount, which leans toward the original plan; authored parts
   (`rg_track_frame`, `rg_road_bogie`, `drive_sprocket`) already exist for that route.
