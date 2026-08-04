# Kitbash Command: Performance Plan (battle-scale simulation cost)

**Status (2026-07-26): P1 (a/b/c/d all landed), P2, and P4 (per-module
bake-at-spawn) landed; P3, P4d/e, P5 still planning.** Written after a
direct code audit (not speculation) in response to Chris's report that the
game becomes unplayable past ~5-6 units per battle, and his intuition that
it's rendering/mesh cost pinned to one core. The audit found the actual
bottleneck is upstream of rendering: an unthrottled O(N²) combat-targeting
scan on the single game-logic thread. Chunks are ordered by measured impact;
each is sized to land as one commit with its own `PROGRESS.md` entry, same
convention as `RTS_CORE_ROADMAP.md`. Every chunk is tagged **[Claude]** or
**[Qwen]** — see "Delegation" at the end for how that split works in
practice.

## Root cause, verified against the working tree

1. **`auto_weapon.gd:603-615`** — `_physics_process()` calls
   `_find_nearest_target()` (line 759) **every physics tick, for every
   weapon module on every unit, with no throttle at all.** This is the
   single biggest cost in the file.
2. **`_find_nearest_target()` → `_is_current_target_still_valid()` (line
   727) → `_is_los_blocked_to()` (line 273-333)** — even the "target is
   still fine, do nothing" fast path calls `_is_los_blocked_to()`, which:
   - builds a raycast exclude list by recursively walking **both** the
     weapon's own node tree and the **entire target vehicle's node tree**
     via `_get_colliders_recursive()` (line 206) — every hull part and
     every module's sub-mesh nodes, every single call;
   - then fires up to two synchronous `intersect_ray()` queries.
3. **When a target actually needs reacquiring**, `_find_nearest_target()`
   iterates `get_tree().get_nodes_in_group("damageable")` — every
   damageable thing in the match — calling the same tree-walk-plus-raycast
   LOS check on every in-range candidate (lines 771-824).
4. **Net scaling**: O(units × weapons) tree-walks/raycasts per tick in
   steady state, degrading toward O(units² × weapons) whenever many weapons
   lose their targets simultaneously (an alpha strike, a target dying, fog
   state flipping) — which produces exactly the non-linear "fine at 5,
   collapses past 6" shape Chris described, rather than a smooth slope.
5. **`battle_unit.gd:768-769` → `_share_energy_with_allies()` (line
   1408-1416)** — runs every physics tick, unthrottled, for any unit
   carrying a `logistics_tank` module, scanning
   `get_tree().get_nodes_in_group("units")`. The function's own comment
   (1404-1407) calls this "cheap enough... without needing a spatial
   partition" — true at 5 units, false at 30.
6. **The throttle pattern to fix both of the above already exists in this
   codebase** and just wasn't applied to these two call sites:
   `battle_unit.gd`'s own `_try_auto_engage()` uses
   `AUTO_ENGAGE_SCAN_INTERVAL = 0.5` with a countdown timer
   (`_auto_engage_scan_timer -= delta; if _auto_engage_scan_timer > 0.0:
   return`), and `skirmish.gd` throttles fog recalculation the same way
   via `FOG_TICK_INTERVAL = 0.3`.
7. **No threading anywhere** — zero `WorkerThreadPool`/`Thread.new()` usage
   in `prototype/scripts`, no physics-thread override in `project.godot`.
   Everything above runs serially on the main thread — this is the real
   shape of "pinned to one core," but the cause is the unthrottled
   simulation work, not the render pipeline.
8. **Rendering is a real but secondary contributor**: `visual_builder.gd`
   has 106 `material_override =` sites, each a freshly-allocated
   `StandardMaterial3D` via `_mesh_inst()` (line 70-81), which also sets
   `cull_mode = CULL_DISABLED` unconditionally (every part double-sided).
   A fully-loadout unit is on the order of 20-40 separate `MeshInstance3D`
   nodes, each independently materialed — no draw-call batching, no
   `MultiMesh`, no LOD, no occlusion culling anywhere in the project. This
   compounds the CPU cost above but doesn't explain the *cliff* on its own
   — it scales roughly linearly with unit count, not quadratically.
9. **Ruled out**: `terrain_builder.gd`'s heightmap/navmesh bake
   (`build_navmeshes`, `build_ground_visual_mesh`) runs once at match load,
   not per battle-frame.

## Chunks

### P1. Throttle + spatially-partition combat targeting/LOS — *one session; highest impact* [Claude]

**Status: all of P1a/b/c/d landed (2026-07-25/26).**

d) **[Landed]** Cache LOS on the fast path. `_is_current_target_still_valid()`
   used to call `_is_los_blocked_to()` every tick even when nothing about the
   geometry between shooter and target had changed - each call walks both
   node trees to build a raycast exclude list, then fires up to two
   raycasts, for every weapon, every tick. Added `_is_los_blocked_cached()`
   (a 150ms-TTL cache keyed on the current target) and switched the fast
   path to use it.

a) **[Landed]** Throttle reacquisition. `_find_nearest_target()`'s full
   grid/roster scan is now gated by `_reacquire_timer`/`REACQUIRE_INTERVAL`
   (0.2s), staggered per weapon via a random phase in `_ready()`. First
   attempted and reverted earlier in this same effort over a suspected
   regression (`test_target_dummies_actually_take_damage_in_test_range`
   failing under full-suite load); follow-up isolation runs found that test
   flaky on entirely unmodified `auto_weapon.gd` too (2 fails / 1 pass
   across 3 stock-code runs), so the throttle was never actually the cause.
   Re-implemented with the same design once that was understood. A
   `delta: float = -1.0` sentinel default keeps every direct/manual
   `run_tests.gd` caller (which calls this with no arguments) unthrottled
   and synchronous, unchanged.
b) **[Landed]** Cache the collider-exclusion list.
   `_get_colliders_recursive()`'s result is now cached on the walked node
   itself via `set_meta()` (self-cleaning - dies with the node, no leaked
   static-dict entries for freed vehicles) with a 1s TTL, via the new
   `_cached_colliders_for()` wrapper. A module lost mid-battle can leave one
   stale RID in a cached list for up to that TTL; Godot's raycast `exclude`
   array silently skips RIDs that no longer resolve to a live collider, so
   this is a harmless, bounded imprecision.
c) **[Landed]** Spatial broadphase for reacquisition.
   `skirmish.gd` now maintains `_damageable_grid` (a
   `Dictionary[Vector2i, Array]`, 20m cells), rebuilt on the same
   `FOG_TICK_INTERVAL` cadence as fog via a real `Timer`, with
   `get_nearby_damageable(pos, radius)` querying just the cells overlapping
   a circle. `auto_weapon.gd`'s new `_damageable_candidates()` duck-types
   against `current_scene.has_method("get_nearby_damageable")` (same
   pattern `_teams_allied()` already uses for `is_allied()`), falling back
   to the old whole-roster scan when no real Skirmish is running (Test
   Range, every headless test fixture) - zero behavior change there.

**Verify:** `run_tests.gd` full-suite pass (one flaky, unrelated failure
each run - confirmed pre-existing and unrelated via isolated re-runs, see
PROGRESS.md-equivalent notes above). Stress-tested via
`prototype/scratch/debug_single_test.gd` (temporary, not committed):
60 units total (10x the original "unplayable past 5-6" report) in active
combat sustained ~37ms average physics-process time per frame without
hanging or degrading - no crash, no freeze, real-time responsive throughout.
No isolated before/after delta was captured (would need reverting P1/P4 and
re-measuring, not done this pass), but this is a strong directional signal:
the same reported-broken scale now runs at 10x with headroom to spare.
in a skirmish and logs physics-frame time via
`Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)` before/after —
target is today's 5-6-unit frame cost sustained at 30+.

### P2. Throttle `battle_unit.gd`'s energy-share scan — *afternoon; needs P1a's interval decision* [Qwen once Claude specifies the exact pattern]

`_share_energy_with_allies()` (`battle_unit.gd:1408`) gets the identical
countdown-timer throttle as P1a, reusing `AUTO_ENGAGE_SCAN_INTERVAL`-style
plumbing already in the same file (this function lives in `battle_unit.gd`
right next to `_try_auto_engage`, which already has the pattern to copy
line-for-line). Purely mechanical once Claude names the constant and
interval — good first real qwen task once the trial run (see Deliverable 2
/ delegation workflow) is validated.

**Verify:** same stress test as P1; logistics-tank aura behavior unchanged,
just less frequent (energy-share amounts should scale the interval into the
per-call transfer so total sharing rate is unaffected — `delta` in the
existing call already does this correctly if the throttle is a pure
skip-frames pattern, confirm the accumulated `delta` between calls is
passed through, not a fixed per-call amount).

### P3. Investigate off-main-thread raycasting — *investigative; build only if P1 isn't enough* [Claude]

Research whether `PhysicsServer3D.space_get_direct_state()` queries are
safe to issue from a `WorkerThreadPool` task in Godot 4.3 (historically
constrained — direct space state is tied to the physics step). Likely
**unnecessary**: once P1c's spatial grid bounds the per-tick raycast count
to "nearby enemies only" instead of "the whole roster," the remaining cost
should be low enough that a second core isn't needed. Only pursue this if
the P1 stress test still shows physics-frame time climbing unacceptably
past ~40-50 units.

### P4. Mesh/material consolidation — *multi-session* [Claude]

**Status: landed 2026-07-26 (bake-at-spawn, per-module merge).** Chris
brought outside research proposing "bake modular geometry into merged
meshes at spawn time, keep the Design Lab fully editable" as the fix for
"performance is better but combat itself is still bad" — this is a
strengthened version of what this chunk originally proposed (material
pooling alone); implemented the fuller version instead:

a) **[Landed]** `visual_builder.gd`'s new `bake_module_visual(module)`
   merges a battle-spawned module's direct-child `MeshInstance3D` siblings
   into one `ArrayMesh` per distinct material via `SurfaceTool`
   (`surface_tool.append_from()`, iterating every surface of each source
   part, not just surface 0). Named animation pivots (`BarrelCluster`,
   `RotorBlades`, `WingPivot`, `PropBlades` — the same names
   `MONOLITHIC_ANIMATION_PIVOTS`/the procedural builders already use for
   independently-rotating parts) are left un-merged so rotary-cannon spin,
   rotor blades, etc. keep animating. Typically collapses 3-9 nodes per
   module down to 1-3.
b) **[Landed]** Wired into `blueprint_manager.gd`'s `reconstruct_vehicle()`
   — the single shared function both the Design Lab (`is_designer=true`)
   and every real battle spawn (`is_designer=false`: `battle_unit.gd`,
   `building.gd`, `skirmish.gd`'s preview, every `run_tests.gd`/
   `scratch/capture_*.gd` battle-spawn call) go through. Baking runs
   **only** when `not is_designer`, after `rebuild_visual()` and the
   mirror-flip step (both need the real, un-merged sub-part nodes). The
   Design Lab keeps every part as its own node — gizmo drag handles and
   per-part tweak deformation target them directly and would break if
   pre-merged.
c) **[Landed]** A material-pooling pass (the original a/b/c plan: cache
   `StandardMaterial3D` by `(color, emission, emission_energy)`, audit
   `CULL_DISABLED` per part type) is now largely subsumed by (a) — a
   merged module already shares one material per distinct color group, so
   there's nothing left to pool. Revisit only if profiling after (a) shows
   remaining draw-call pressure from cross-unit (not per-unit) material
   duplication.
d) **[Deferred]** Locomotion/running-gear baking. `wheels`/`tracked_treads`/
   `legs`/`helicopter_rotors` etc. build through a **separate** entry point
   (`build_running_gear()`, not `build_visual()`'s per-module loop) and
   weren't covered by (a)/(b) - per the earlier audit, this is one of the
   worst offenders (wheel hub × axle-count × 2 sides, each hub+driveshaft+
   gearbox). Same technique applies (merge static sub-parts, skip whichever
   named parts actually spin as the vehicle drives — needs its own audit of
   `build_running_gear()`'s node structure first, not yet done).
e) **[Deferred]** `MultiMeshInstance3D` for exactly-repeated geometry
   (wheel hubs, rotor blades, tread rollers) — lower priority than (d)
   since (d) alone already collapses most of the node count; MultiMesh
   only pays off further if the SAME mesh is repeated many times within
   one unit, which is rarer after baking.

**Verify:** `prototype/visual_regression/` baseline diff — these changes
must not visibly change how any unit looks, only how it's drawn. Confirmed:
full headless suite passes unchanged (`test_hull_decals`,
`test_hull_greebles`, and every spawn-pipeline test that walks a
battle-spawned hull's module tree all still pass, since baking only
replaces a module's *children*, never the module node itself that those
tests actually key off via `has_meta("module_data")`/`has_method(...)`).
Manual frame-time check with 20-30 units still recommended before calling
the performance work done for this session.

### P5. Shader cost pass on `hull_faction_material.gdshader` — *profile first, don't guess* [Claude]

Confirmed cost per fragment: 4× `noise3()` calls (8 `hash3()` evaluations
each), triplanar sampling of 3 textures × 3 axes (9 texture fetches), two
`fwidth()`-based edge signals, `cull_disabled` on every hull surface. Real,
but scales with pixel/hull-surface-area, not unit count — it degrades
resolution/fill-rate headroom gracefully rather than causing a cliff. Only
worth touching if a GPU profiler pass (Godot's built-in frame profiler,
after P1-P4 land) shows this is now the binding constraint. If so: bake the
procedural wear/grime/seam masks to a texture once per faction/material
combination instead of recomputing per-fragment per-frame, or drop an
octave of noise.

## Sequencing

**P1 → P2 → measure → P4 → measure → P3/P5 only if the stress test still
shows trouble.** P1 is expected to be the fix for "unplayable past 5-6
units" on its own, since it's the quadratic term; everything after it is a
compounding but secondary improvement, not a second cliff-fix.

| # | Chunk | Size | Depends on | Delegation | Status |
|---|---|---|---|---|---|
| 1 | P1d LOS-check caching | small | — | Claude | **Done** |
| 1b | P1a/b/c reacquisition throttle + collider cache + spatial grid | one session | — | Claude | **Done** |
| 2 | P2 throttle energy-share scan | afternoon | P1a's pattern (independent otherwise) | Qwen (Claude-specified) | **Done** |
| 3 | P3 off-main-thread raycasting investigation | investigative | P1 (measure first) | Claude | — |
| 4 | P4 mesh/material consolidation (per-module bake-at-spawn) | multi-session | — | Claude | **Done (a-c); d/e deferred** |
| 5 | P5 shader cost pass | afternoon | P1-P4 (profile first) | Claude | — |

## Delegation: Claude vs. qwen on this plan

Chunks tagged **[Claude]** involve correctness-sensitive judgment — spatial
grid design, cache-invalidation rules, LOS TTL tuning, threading
feasibility, shader/pixel-cost tradeoffs — and stay hands-on. Chunks tagged
**[Qwen]** are mechanical once Claude has written the exact pattern to
replicate (a throttle constant + copy-paste of an existing timer idiom; a
fixed material-cache-lookup substitution repeated 106 times) — well suited
to a local model grinding through a long, repetitive, low-ambiguity
transformation. Every qwen diff gets reviewed before it's committed, and
the headless suite runs after:

```
cd prototype && ./Godot_v4.3-stable_win64_console.exe --headless --script run_tests.gd --path .
```

expecting exit 0 and "ALL AUTOMATED TESTS PASSED SUCCESSFULLY!".

## Verification (applies to every chunk in this doc)

- Headless test suite must pass unchanged after any chunk lands.
- Stress test: 30-40 units per side in a live skirmish, physics-frame time
  via Godot's profiler, compared before/after against today's 5-6-unit
  baseline.
- Visual chunks (P4/P5) additionally require a clean
  `prototype/visual_regression/` baseline diff — no unit should look
  different, only render cheaper.
