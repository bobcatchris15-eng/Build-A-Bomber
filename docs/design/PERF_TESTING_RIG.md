# Performance Testing Rig — Kitbash Command

## What Exists and What It Found

The probe suite has already done significant diagnosis. Here's the map of what landed:

| Probe | What it measured | Key finding |
|---|---|---|
| `probe_perf_scaling.gd` | Frame time vs unit count (1→48) | **Linear** scaling — no O(n²) |
| `probe_perf_attribution.gd` | System-level disable/ablate | 16 units in headless: 60ms total, no renderer. **Unit physics is the entire budget.** |
| `probe_unit_tick_breakdown.gd` | Named sections via `BattleProfiler` | `unit.gd::_physics_process` owns the cost |
| `probe_perf_drift.gd` | Node count, orphans, projectiles, signal connections over 300s | **No leak.** Plateau confirmed. |
| `probe_unit_render_cost.gd` | Draw calls, material objects, material uniqueness | ~22 material objects per unit vs 19 genuinely distinct — material cache already helps |
| `probe_spawn_cache.gd` | Duplicated hull vs freshly built hull | Metadata, HP, weapons, colliders all identical — **cache is safe** |
| `perf_hud.gd` | In-match live readout (F3) | Frame ms (mean/p95/worst), hitch counts, munitions |

### The Diagnosis So Far

**Confirmed good:**
- Neighbour grid (8m spatial hash) prevents O(n²) separation checks — linear scaling confirmed
- Hull duplication cache eliminates the 1047ms reconstruct_vehicle() cost on repeat spawns
- Materials are shared across duplicates
- No memory leak over 300s of headless simulation

**Confirmed bad:**
- **~2.4ms per unit per physics frame, headless.** At 16.67ms frame budget (60fps), ~7 units exhaust the CPU before the renderer gets anything. Chris's report of "under 10 FPS with 6-8 engaged units" is exactly this — and it tracks with the 7-unit headless ceiling.

**Still unknown:**
- The per-unit cost is inside `unit.gd::_physics_process`, but the **internal breakdown is incomplete**. `probe_unit_tick_breakdown.gd` exists but the named sections inside `_apply_movement()` → `_steer()` are not all wired to `BattleProfiler`.
- NavigationServer3D cost is **not attributed separately**. A path query costs what the server charges — it doesn't show up in GDScript timing.
- Weapon targeting (auto_weapon.gd) is partially timed (`weapons` section) but the inner loop — `_find_target()`, `_is_los_blocked_to()` — isn't broken out per call.

---

## The Testing Rig Architecture

The rig should answer three questions, in order:

1. **Is it growing?** Does per-unit cost scale with unit count (load) or is there a cliff (structural)?
2. **Where is it?** Which subsystem owns the cost at the 60fps budget boundary?
3. **Why is it there?** What specifically in that subsystem — algorithm, engine call, allocation — causes the per-unit cost?

Each stage narrows the aperture. Skipping stages wastes time chasing the wrong thing.

```
Stage 1: Baseline            →  probe_perf_scaling.gd output, extended to 64 units
Stage 2: System attribution  →  disable/ablate, already mostly done
Stage 3: Per-unit breakdown  →  wire BattleProfiler to every tick section
Stage 4: Engine cost         →  Godot --profiling, NavigationServer3D
Stage 5: Decision             →  fix or defer
```

---

## Stage 1: Baseline at Scale

**What:** Run `probe_perf_scaling.gd` at unit counts beyond what Chris played (48 → 64, then 96), plus add two new measurements.

**New probes to write:**

### `probe_tick_variance.gd`
**Question answered:** Is the per-unit cost stable, or does it spike with combat activity?

The current scaling probe measures steady-state movement (units spawned, then settled). But Chris's problem was "under 10 FPS" during **engagement** — combat causes projectile spawns, hit effects, death, respawn pressure. A steady-state moving unit is cheap; a unit in active combat is not the same load.

```gdscript
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_tick_variance.gd

const UNIT_COUNT := 16
const BATTLE_SECONDS := 120  # Two minutes of actual combat
const SETTLE_FRAMES := 120
const WARMUP_FRAMES := 60
```

Measures: per-frame time, binned by what the battle was doing at that moment (idle / moving / combat / death). Requires the director to emit a `phase` signal the probe can read.

**If variance is high:** The per-unit number from scaling is an average that masks the real worst-case. Fix priority shifts to reducing spike amplitude (e.g. pooling projectiles) rather than reducing the mean.

**If variance is flat:** Confirms the cost is structural, not situational.

### `probe_gdkernel_overhead.gd`
**Question answered:** Is the per-unit cost GDScript, or is it Godot's own kernel (scene tree walks, signal dispatch, group membership)?

```gdscript
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_gdkernel_overhead.gd

const UNIT_COUNTS := [1, 2, 4, 8, 16, 24, 32]
```

Two passes:
1. Units with `_physics_process` bodies intact (normal)
2. Same units, but their `_physics_process` returns immediately on line 1 (zero work)

The delta is pure kernel overhead — scene tree, groups, signals. If it's > 20% of the total, the unit structure itself is the problem, not the tick logic.

---

## Stage 2: System Attribution — Already Done, Verify

`probe_perf_attribution.gd` already disabled `unit.gd`, `auto_weapon.gd`, and the director tick. The results are documented in the file header.

**Recommended additions:**

### `probe_vision_cost.gd`
**Question answered:** Is the vision service (O(viewers × targets)) burning CPU?

The vision service runs at 3.3Hz (`TICK_INTERVAL = 0.3`), not every frame. But at 16+ units per team, that's 32 units scanning each other's positions every 0.3s, plus the shroud mesh update. This is invisible in a headless probe that only measures frame time, because the cost is amortized.

```gdscript
# Run: Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#          --script tools/probe_vision_cost.gd
```

Two passes:
1. Normal vision service
2. Vision service `_physics_process` stubbed to `return` immediately

Delta = vision cost.

**Also check:** The shroud mesh update in `vision_service.gd` — it rebuilds a grid mesh every tick if visibility changed. Even with 3.3Hz scan, if the mesh rebuild is unconditional, it burns every frame the scan runs.

### `probe_navserver_cost.gd`
**Question answered:** How much does NavigationServer3D charge per unit per frame?

NavigationAgent3D queries are engine calls — they don't show up in GDScript timing. You need Godot's built-in `--profiling` output.

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path . \
    --script tools/probe_navserver_cost.gd \
    --profiling --profiling-file nav_cost.csv
```

The probe spawns units with move orders, then exits. Parse the CSV for `NavigationServer3D` rows. Key metrics: `physics_process_usec` per frame, broken down by agent.

---

## Stage 3: Per-Unit Breakdown

**What needs wiring:** `BattleProfiler` sections inside `unit.gd::_physics_process`.

Current wiring (from unit.gd:494):
- `unit.gd::_physics_process` → `units` (parent bucket)
- Inside it: `unit.move_and_slide` → `unit.move_and_slide`

**Missing sections that need profiling tokens:**

```gdscript
# In unit.gd _physics_process(), around line 494:
func _physics_process(delta: float) -> void:
    if is_dead: return
    var _t := Profiler.start()
    _tick_power(delta)                                    # +profiler
    _recalculate_terrain_speed_multiplier()                # +profiler
    _advance_orders()                                      # +profiler
    _tick_economy(delta)                                   # +profiler (harvester only)
    var boost_mult := 1.0
    if boost_controller != null:
        boost_mult = boost_controller.tick(delta)
    _update_boost_vfx(delta, boost_mult > 1.0)
    _apply_movement(delta, boost_mult)                    # already in tick_breakdown?
    _apply_vertical(delta)
    var _s := Profiler.start()
    move_and_slide()
    Profiler.stop("unit.move_and_slide", _s)
    Profiler.stop("units", _t)
```

And inside `_apply_movement()`:

```gdscript
# Inside unit.gd _apply_movement(), need to add:
func _apply_movement(delta: float, boost_mult: float) -> void:
    var _t := Profiler.start()
    _steer(delta)           # Profiler.start("unit.steer")
    _update_separation()    # Profiler.start("unit.separation") — calls director.neighbour_positions()
    _apply_throttle(...)    # Profiler.start("unit.throttle")
    Profiler.stop("unit.movement", _t)
```

**Why `neighbour_positions()` matters specifically:** It's the bridge from unit-local math to the director's spatial index. If that's where O(n²) hides despite the grid, this is where it shows up.

### `probe_tick_wire_all.gd`
Writes all the missing `Profiler.start()`/`Profiler.stop()` calls to a staging file, applies them to unit.gd, runs `probe_unit_tick_breakdown.gd` with the full coverage, then diffs the output.

```bash
# Run with full profiler wiring:
Godot_v4.7.1-stable_win64_console.exe --headless --path . \
    --script tools/probe_tick_wire_all.gd
```

Output: Same breakdown as `probe_unit_tick_breakdown.gd`, but every named section inside the tick is visible.

---

## Stage 4: GPU and Renderer

Even at 7 units headless the frame is already over budget — the renderer isn't the primary problem. But it's additive, and knowing the renderer number closes the full budget equation.

### `probe_renderer_cost.gd`
**Question answered:** What does the renderer add at 8 units vs 16 units vs empty map?

```gdscript
# Run: Godot_v4.7.1-stable_win64_console.exe --path . \
#          --script tools/probe_renderer_cost.gd
```

Three passes, same battle scene:
1. Empty map — renderer baseline
2. 8 units — renderer at Chris's problem threshold
3. 16 units — renderer at double that

Uses `--headless` for passes 1-2 (renderer cost excluded) and `--rendering-method forward_plus` with the actual scene for pass 3. Diffs give the GPU contribution.

**Also check:** `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` and `Performance.RENDER_TOTAL_OBJECTS_IN_FRAME` per unit — already in `perf_hud.gd`, confirm the probe can reproduce it headlessly.

### MSAA and scaling cost

The perf_hud comment notes: "at 1920x1080+ with msaa_3d=2 (4x), MSAA alone measured ~31% of frame time on an empty map." This is already documented. Confirm with a probe:

```gdscript
# probe_msaa_cost.gd
# Compare: msaa_3d = 0 vs 2 vs 4 at 8 units
```

---

## Stage 5: The Decision

Once Stages 1-4 are done, you'll have a complete budget:

```
Frame budget: 16.67ms (60fps)

+ unit physics (per-unit × unit count)     = ?
+ nav queries (engine, not GDScript)      = ?
+ vision service (3.3Hz scan)             = ?
+ renderer (draw calls, MSAA, shadows)    = ?
+ director tick (economy, orders)         = ?
+ weapon targeting (per weapon per frame)  = ?
+ munition/projectile update              = ?
                                              ─────
= headless frame time                     = should match probe_perf_scaling
```

From that, the fix options are ranked:

### Fix A: Tick-rate budget
If per-unit cost is truly linear (confirmed) but the coefficient is too high, run the physics tick at 30Hz instead of 60Hz. Units move in discrete jumps; at 4m/tick for a 12m/s unit, that's 3 ticks to cross a vehicle length. Visually acceptable for an RTS, halves the per-unit cost immediately.

Implementation: `Engine.physics_ticks_per_second = 30` in project settings or per-scene.

**Tradeoff:** Input latency doubles. For an RTS, which is not a reaction game, this is usually fine. Confirmation requires a live playtest.

### Fix B: Reduce per-unit coefficient
If the breakdown shows a specific hotspot — steering math, nav agent queries, move_and_slide — the coefficient is reducible without changing the tick rate.

Common causes and fixes:

| Suspect | Fix |
|---|---|
| NavigationAgent3D path queries every frame | Cache path, only requery when destination changes or agent is off-path |
| `_recalculate_terrain_speed_multiplier()` | Cache, invalidate only on terrain type change |
| `move_and_slide()` with many collision shapes | Reduce per-unit collider count (convex decomposition is already baked) |
| Signal connections per unit | Batch connect (one signal → array of units) |

### Fix C: Parallel unit ticking
CharacterBody3D cannot be ticked off-thread in Godot 4.x (they are main-thread only). But the logic INSIDE the tick — steering math, separation, order state — is pure data transformation and can be batched.

Pattern: Collect all units → run tick logic on all of them in a tight loop (no scene tree access) → apply results back to each unit.

This reduces scene tree overhead (one tree walk for N units instead of N tree walks) and is how Godot's own ECS-adjacent patterns work.

**Tradeoff:** Requires refactoring `_physics_process` to separate "query state" from "mutate state." Significant but clean.

### Fix D: Batch weapons
`auto_weapon.gd::_physics_process` runs per weapon mount, per unit, per frame. A unit with 3 weapons = 3 separate `_physics_process` calls. Weapons share the same targeting logic — batch the targeting pass and distribute results.

**Tradeoff:** Weapons need to know about each other (target deduplication, firing arc conflicts). Adds coupling.

### Fix E: Renderer optimisation
Not the primary problem (headless is already over budget), but additive. MSAA 4x is documented at 31% of empty-map frame time. Drop to 2x or 0. Deferred decals, shader LOD, instanced rendering for repeated geometry (wheels, track links) are all standard RTS approaches.

---

## Probe Run Order

```
Week 1 (diagnostic):
  1. probe_perf_scaling.gd     →  confirm linear, get per-unit coefficient
  2. probe_tick_variance.gd    →  combat vs idle variance
  3. probe_gdkernel_overhead.gd →  scene tree / group cost

Week 2 (attribution):
  4. probe_vision_cost.gd      →  vision service
  5. probe_navserver_cost.gd   →  --profiling nav CSV
  6. probe_unit_tick_breakdown.gd →  full BattleProfiler coverage

Week 3 (confirmation):
  7. probe_renderer_cost.gd    →  GPU contribution
  8. probe_msaa_cost.gd       →  MSAA impact
```

---

## The 7-Unit Ceiling — What It Means

Chris's 10 FPS at 6-8 units tracks exactly with the headless measurement: ~7 units consume the 16ms physics budget headless. The renderer gets what remains — which, if MSAA is at 4x, is approximately nothing.

The ceiling isn't a Godot bug. It's a per-unit coefficient problem. With 30Hz ticking (Fix A), that ceiling moves to ~14 units, which is a typical Skirmish mid-game count. That alone might be the answer.

---

## What to Build Next

If I had to pick one thing to build first: **`probe_tick_variance.gd`**. It answers whether the problem is the steady-state tick (Fix A or B) or the combat spike (MunitionPool already exists — check its hit rate).

If you want me to build any of these probes, or to wire up the missing `BattleProfiler` tokens in `unit.gd`, say the word. I can also write the Godot `--profiling` CSV parser to make `probe_navserver_cost.gd` readable.
