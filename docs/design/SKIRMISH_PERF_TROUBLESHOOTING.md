# Skirmish / Battle Performance — Troubleshooting Plan

**Written:** 2026-08-19
**Supersedes:** the Stage 1–5 program in [`PERF_TESTING_RIG.md`](PERF_TESTING_RIG.md).
That document is still accurate about *what the probes are*, but its diagnosis
("unit physics is the entire budget", "the renderer isn't the primary problem")
was measured **before** Fix A, before the DOF removal, and before munitions were
instrumented. Today's log contradicts both conclusions. Read this first.

---

## 1. What the rig already has (do not rebuild any of it)

| Surface | Where | How you use it |
|---|---|---|
| Live overlay | `scripts/perf_hud.gd` | **F3** in a match. Frame mean/p95/worst, hitch counts, draws, munitions, MSAA/vsync/scale |
| In-the-moment dump | `match_director._dump_perf_now()` | **F4** in a match → `user://logs/dump_manual_*.log` |
| Section timing | `scripts/battle/battle_profiler.gd` | 21 named sections, per-frame totals, percentiles, `hitch_blame()` |
| Structured log | `scripts/battle/battle_logger.gd` | On by default. Opt out with `KITBASH_LOG_PROFILING=0` or `MatchRuleSet.log_profiling = false` |
| Log reader | `tools/analyze_perf_log.gd` | `--headless --script tools/analyze_perf_log.gd -- <log_path>` |
| A/B harness | `tools/profile_battle_run.gd` | Same match twice, profiler on then off, differences the distributions |
| Ablation | `tools/probe_perf_attribution.gd` | Disables a script's `_physics_process` by path and re-times |
| ~25 more probes | `tools/probe_*.gd` | scaling, drift, tick variance, gdkernel overhead, vision cost, render cost, per-hitch probes |

Logs land in `%APPDATA%\Godot\app_userdata\Kitbash Command Prototype\logs\`.

**Stage 3 of the old plan is done.** `unit.gd`'s tick is fully wired:
`unit.tick_power`, `unit.terrain_speed`, `unit.advance_orders`,
`unit.tick_economy`, `unit.steer_nav`, `unit.separation`,
`unit.move_and_slide`, all under the `units` parent bucket. Munitions
(`missiles`, `mines`, `sentries`, `decoys`, `drones`) and `resource_node` are
instrumented too. Don't re-wire these.

**Fix A landed, partially.** `MatchRuleSet.skirmish()` and `.operations()` set
`physics_ticks_per_second = 30` (`match_rule_set.gd:246,280`).
`test_range()` does not, so **Test Range runs at 60 Hz and is not a valid perf
proxy for Skirmish** in either direction.

---

## 2. The evidence we already have: 2026-08-19 skirmish log

`logs/battle_2026-08-19T14-13-08_skirmish.log` — `lake_crossing`,
industrialists vs technocrats, 133 s, 1947 frames, 1920×1080, msaa_3d = 4x,
vsync on.

### Frame distribution

```
frames 1858   mean 55.14   p50 1.86   p95 60.95   p99 421.14   worst 35601 ms
over 33ms: 859      over 100ms: 69
```

### Hitch blame (`hitch_blame(100)`)

| Section | Hitches >100 ms | Worst frame |
|---|---|---|
| `<untimed>` | 36 | 35601 ms |
| `commander` | 32 | 352 ms |
| `production` | 1 | 266 ms |

### Section totals

| Section | Total ms | Mean ms | Worst ms | Frames |
|---|---|---|---|---|
| `commander` | 8048.2 | 4.332 | 446.4 | 1858 |
| `place_structure` | 1557.0 | 44.487 | 179.4 | 35 |
| `hud_minimap` | 625.8 | 3.038 | 6.9 | 206 |
| `units` | 546.7 | 0.294 | 2.1 | 1857 |
| `vision` | 345.2 | 1.675 | 40.2 | 206 |
| `production` | 344.7 | 0.186 | 211.3 | 1858 |
| `resource_field` | 172.0 | 0.093 | 0.4 | 1857 |
| everything else (14 sections) | ~462 | — | — | — |
| **sum instrumented** | **12102.6** | | | |

**Instrumented share: 9.1 % of a 133-second match.** 91 % of wall clock falls
outside every section.

### The three multi-second stalls

| Wall time | Frame | Duration |
|---|---|---|
| t = 0.6 s | 1 | 18391 ms |
| t = 27.8 s | 44 | 23151 ms |
| t = 65.7 s | 90 | 35601 ms |

77 seconds of stall inside the first 66 seconds — the first 90 physics frames
span 65.7 s. Steady state only begins around t ≈ 70 s, after which ~1857 frames
run in ~67 s (≈ 28 ticks/s, i.e. 30 Hz holding).

### Steady state (t > 70 s)

66 hitches over 100 ms, **median 301 ms, worst 896 ms**. `commander` is the
largest named contributor.

### What this log cannot tell us

`units_spawned: 2`, `unit_deaths: 0`, `structures_built: 36`. This was a
**base-building session with essentially no combat.** The `units` and `weapons`
numbers here say nothing about the original "under 10 FPS at 6–8 engaged units"
report. Track D exists for exactly that reason.

---

## 3. Three traps in reading these numbers

**3.1 `mean` and `p50` disagree by 30× because these are physics-tick
intervals, not render-frame times.** `Profiler.end_frame()` is called from the
director's `_physics_process`, so the interval it records is tick-to-tick wall
time. p50 = 1.86 ms with mean = 55 ms is the signature of the engine running
**catch-up bursts**: several physics steps back-to-back (~1.9 ms each, because
the sim genuinely is cheap), then one long interval that swallows the render.
Read `worst`, `p99` and `over_100ms`. Ignore `mean`.

**3.2 The 33 ms threshold is meaningless at 30 Hz.** A healthy 30 Hz tick *is*
33.3 ms. `over_33ms: 859` conflates normal ticks with real stalls. Use the
100 ms counters, or make the threshold derive from
`Engine.physics_ticks_per_second`.

**3.3 The `dominant` field on per-hitch log lines is unreliable.**
`BattleProfiler.hitch_blame()` applies `DOMINANCE_SHARE = 0.5` before naming a
culprit; `match_director.gd:3293`'s `log_hitch()` call passes
`Profiler.last_dominant` raw, with no share test. In this log that named
`production` (0.0 ms) as dominant on the 35601 ms frame, and `units` (0.2 ms)
as dominant on a 458 ms frame. **Per-hitch `dominant` values in existing logs
should be discarded**; only the `profiler_summary` blame table is trustworthy.

---

## 4. Defects found while reading the code — fix these before measuring again

Each one either corrupts a measurement or hides one. All are small.

1. **`log_hitch`'s dominant has no dominance test** (§3.3).
   `match_director.gd:3292-3294`. Apply the same `DOMINANCE_SHARE` gate
   `hitch_blame()` uses, or log the share alongside the name.

2. **`engine_ticks_per_second` is snapshotted before it is set.**
   `_evaluate_logging_flags()` → `BattleLogger.begin_match()` runs at
   `match_director.gd:361`; the tick rate is assigned at `:394`. So
   `MATCH_BEGIN` records **60 even when the match runs at 30**, and today's log
   showing 60 is *not* evidence that Fix A failed. Move the snapshot after the
   assignment, or re-log the resolved rate. Until then, confirm the rate from
   the `[match_director] physics_ticks_per_second = 30` stdout line instead.

3. **`project.godot`'s MSAA block is malformed.** Commit `f998adc7` wrote `#`
   comment lines into a Godot ConfigFile; the editor re-saved them collapsed
   into a single quoted key:

   ```
   "2D MSAA is enabled while there is no 2D contentwarningatboot.#Cheapfix,freeperfheadroom.anti_aliasing/quality/msaa_2d"=0
   ```

   The intended `anti_aliasing/quality/msaa_2d=0` no longer exists, so the value
   falls back to the engine default — which happens to be 0, so the intent
   survives by luck. Delete the junk key and set it plainly. Use `;` for
   comments in `project.godot`, not `#`.

4. **`navmesh_dispatch` and `navmesh_callback` recorded zero frames** across a
   match that built 36 structures, and `navmesh` totalled 2.9 ms. Either the
   urgent-rebake path from `38fd3f61` never fires on structure placement, or it
   runs somewhere those tokens don't cover. Answer this before drawing any
   conclusion about navmesh cost — right now we have no measurement at all.

5. **`build_phase` log spam.** 308 events, with `"Surveying terrain"` repeated
   ~20× at an identical timestamp. Harmless to perf, but it pads a 2.5 MB log
   and makes the build timeline unreadable. Dedupe on (label, fraction).

---

## 5. The plan

Five tracks. **A and B are where the time actually is; do them first.** Tracks
are independent — nothing below blocks anything else.

### Track A — the 77 seconds of `<untimed>` stall (highest value)

**Question.** What runs during the 18.4 s / 23.2 s / 35.6 s stalls, all of which
land in `<untimed>` with the sim idle?

Because they occur at t = 0.6 s, 27.8 s and 65.7 s — not just at load — this is
not simply world-build cost. Leading candidates, in order of prior plausibility
for this codebase:

- **Shader / pipeline compilation on first use.** Forward+ compiles on demand.
  A 35 s stall mid-match is the classic shape.
  `tools/probe_shroud_shader_compiles.gd` already exists for one instance of this.
- **Synchronous resource load** — a hull `.glb`, a `_collision.res`, or a
  texture set pulled in the first time a design or structure kind appears.
- **Navmesh bake on the main thread** (see defect 4 — currently unmeasured).
- **Terrain prop / ambient scatter instantiation** on first reveal.

**How to measure.**

1. Re-run with `--verbose` and correlate engine stdout timestamps against the
   three stall frames. Godot logs shader compiles and resource loads there; the
   BattleLogger sees neither.
2. Decompose `<untimed>`: wrap the director's own `_process` (not just
   `_physics_process`), and add explicit sections around `ResourceLoader.load`
   call sites in the battle path and around the navmesh bake dispatch.
3. Check whether the stalls correlate with the *first* instance of a given
   structure or unit kind — `structure_built` events are already in the log and
   can be joined on frame number.

**What the answers mean.**

- *Correlates with first-instance-of-a-kind* → precompile / prewarm. A shader
  warmup pass during the deploy gate plus a preload of the roster's meshes kills
  it outright.
- *Correlates with navmesh* → move the bake off-thread or coarsen it.
- *No correlation, cost spread across the frame* → suspect the renderer and go
  to Track E.

### Track B — the `commander` re-decide spike

**Question.** Why does one AI decision cost up to 446 ms?

`Commander.tick()` is gated (`DECISION_INTERVAL = 2.0`,
`MIN_DECISION_INTERVAL = 0.5`), so the 8048 ms total is concentrated in roughly
66–266 re-decides across the match — **about 30–120 ms per decision, worst
446 ms, every 0.5–2 s.** That cadence matches a "hitchy every second or so" feel
exactly, and `hitch_blame` credits it with 32 of the 69 frames over 100 ms.

`tick()` splits cleanly into `read_state()` → `decide()` → `_execute()`, and
`_execute()` reaches `_world.ai_build_structure()` →
`match_director._ai_placement_site()`, the 192-candidate placement loop that
commit `1e6d1d4e` already had to hoist lookups out of. `read_state()` walks every
unit on both teams and calls `is_visible_to_team()` per enemy unit.

**How to measure.** Add three sections — `commander.read_state`,
`commander.decide`, `commander.execute` — plus a fourth inside
`_ai_placement_site()`. This is a ten-line change and it converts the single
largest named cost from a bucket into an answer. **Do this before optimising
anything in the commander.**

**Fix candidates, once attributed.**

- Placement search dominates → cache the candidate grid; invalidate on
  structure/terrain change rather than rebuilding per decision.
- `read_state()` dominates → it recomputes derived counts the director could
  maintain incrementally (the economy already does this for income).
- Neither dominates and cost is spread → amortise the decision across frames
  (score N candidates per tick, commit when the pass completes). A 2 s decision
  cadence has ample budget to spend 60 frames deciding.

### Track C — `place_structure` at 44 ms mean

**Question.** 35 invocations, mean 44.5 ms, worst 179 ms — every structure
placement is a visible hitch, and a base-building match does 36 of them.

This has history: `tools/probe_building_construction_hitch.gd` exists and was
updated twice. Re-run it, then bisect `place_structure` internally (footprint
legality → terrain prop displacement → mesh build → collider → navmesh hole →
visibility range). `_displace_terrain_props()` and
`_apply_structure_visibility_range()` both walk nodes and are prime suspects.

Note the interaction with Track B: the AI commander triggers placements, so a
commander decision and a structure placement can land on the same frame,
compounding into the 300 ms+ range.

### Track D — the case this log never exercised: actual combat

**Question.** Is the original "under 10 FPS at 6–8 engaged units" report still
reproducible after Fix A, the DOF removal, and the munition instrumentation?

The old 2.4 ms-per-unit figure came from a headless 16-unit measurement at 60 Hz
with the pre-Fix-A tick. Today's `units` bucket is 0.294 ms mean — but with
**two** units and no combat. Neither number describes the case Chris originally
reported. **Do not act on either until this is re-measured.**

**How to measure.** Existing tools, in this order:

1. `tools/profile_battle_run.gd` — 300 s scripted run with harvesters, squads and
   waves; run it twice (profiler on / off) as designed.
2. `tools/probe_perf_scaling.gd` — re-run the 1→48 sweep at 30 Hz and compare
   against the archived 60 Hz curve. Confirms whether the per-unit coefficient
   actually halved.
3. `tools/probe_tick_variance.gd` — steady-state vs combat variance, the specific
   gap the old plan named as most valuable and which today's log still leaves open.

Then reproduce by hand: a real Skirmish, F3 on, drive to 8+ engaged units, F4 at
the moment it feels bad. **Turn vsync off for this** — it pins the readout to
60.0 and hides everything under 16.7 ms.

### Track E — the presentation baseline (upgraded from the old plan's Stage 4)

The old plan deprioritised the renderer on the grounds that headless was already
over budget. **Today's log inverts that argument:** physics ticks complete in
~1.9 ms median and the entire instrumented sim is 9.1 % of wall clock, yet frames
still take hundreds of ms. Whatever owns the remainder is mostly not GDScript.

**Measure, in this order (each is one setting and a re-run):**

1. `msaa_3d` 4x → 2x → off. `perf_hud.gd`'s header documents MSAA at ~31 % of
   frame time on an *empty* map; nothing since should have changed that.
2. vsync off, to see the true frame time rather than the 60 Hz cap.
3. `scaling_3d_scale` at 0.75, to separate fill cost from geometry cost.
4. `hud_minimap` at 3.04 ms mean over 206 frames — it runs about 1 frame in 9 and
   costs 3 ms when it does. That is a large slice of a 30 Hz budget for a
   minimap; check whether the shroud image rebuild is gated on
   `VisionService.shroud_version` (the field exists precisely so it can be).
5. `vision` worst 40.2 ms on a 3.3 Hz tick — one bad vision tick alone blows a
   30 Hz frame. Bisect `tick()` vs `_update_shroud()`.

---

## 6. Instrumentation to add before the next capture

Ordered by measurement value per line changed:

1. `commander.read_state` / `commander.decide` / `commander.execute` sections (Track B).
2. A section inside `_ai_placement_site()` (Tracks B + C).
3. Sections around battle-path `ResourceLoader.load` calls and the navmesh bake
   dispatch (Track A, defect 4).
4. The director's `_process` as well as `_physics_process`, so per-frame
   non-physics work stops landing in `<untimed>`.
5. Fix `log_hitch`'s dominant (defect 1) and the `engine_ticks_per_second`
   snapshot (defect 2).
6. Derive the hitch threshold from the tick rate instead of the 33 ms / 100 ms
   constants (§3.2).

---

## 7. Regression guard

`tests/battle/test_battle_perf.gd` currently holds two collision-mask tests and
**no frame-budget assertion at all**, so nothing in the suite would catch a perf
regression.

Add one headless suite that spawns a fixed unit count on a fixed map, runs a fixed
number of ticks, and asserts a **generous** ceiling on the instrumented sim total
— not on wall-clock frame time, which is machine-dependent and would flake.
Assert on `BattleProfiler.sections()` sums, which are deterministic in shape if
not in exact value. A guard that only catches a 3× blowup is still worth having;
a tight one will flake and get deleted.

---

## 8. Suggested run order

```
Day 1   Fix defects 1-3 and 5 (§4). Add instrumentation items 1-2, 5 (§6).
        Re-run the same Skirmish and capture a clean log.
        -> Track B is answered or narrowed in one capture.

Day 2   --verbose run correlated against stall frames (Track A).
        Add instrumentation item 3, re-capture.
        -> the 77 seconds is named.

Day 3   Track E's five sweeps. Cheap, mechanical, and one of them probably
        moves steady state on its own.

Day 4   Track D: profile_battle_run.gd x2, probe_perf_scaling.gd,
        probe_tick_variance.gd. Establishes whether the combat case is still
        a problem after Fix A.

Day 5   Track C, then the regression guard (§7).
```

---

## 9. Open questions

1. **Was the 2026-08-19 session the one that felt bad?** 36 structures, 2 units,
   no deaths reads as a base-building test rather than a fight. If the bad feel
   was during combat, that session is unlogged and Track D moves to the front.
2. **Did the multi-second stalls present as freezes?** A 35 s stall is not
   something you'd miss — if it was a freeze, Track A is the whole story and
   everything else is secondary. If the session looked normal, the stall
   measurement itself is suspect and should be re-validated first.
3. **Is 30 Hz visibly acceptable?** Fix A is live in Skirmish and Operations. If
   unit motion looks steppy, that constrains every fix below it.
4. **What is the target?** "60 fps at 16 engaged units on this machine" and
   "30 fps with no hitch over 100 ms" imply very different work. The plan above
   is written for the second.

---

# 10. Log review — 2026-08-19 playtest set

625 battle logs were written today. Nearly all are harness runs; **7 are real
playtests**. The §6 instrumentation landed between captures, so the later logs
are far more informative than the 14-13-08 one §2 is based on. Instrumented
share went **9.1 % → 78 %**.

**The reference capture is `battle_2026-08-19T19-57-23_skirmish.log`** —
lake_crossing, 258.8 s, 30 Hz, 15 units, 59 structures, 1920×1080, msaa 4x,
vsync on. It is the only log today with a realistic unit count. Everything
below comes from it unless stated.

## 10.1 Headline: the real frame rate

Derived from `render_frame` (the director's `_process`, which is an empty
timing probe) and the physics section counts:

```
rendered frames  1172 over 258.8 s  =   4.53 fps
physics ticks    3768 over 258.8 s  =  14.56 Hz   (target 30)
```

The sim is running at **half real-time** and the screen at **4.5 fps**. Since
`_process` itself measures 0.001 ms mean, the gap between instrumented physics
work and wall clock is the renderer. Track E is confirmed, not speculative.

## 10.2 Headline: `unit.move_and_slide` scales superlinearly

Per-30-second buckets, cost per physics frame:

| Units alive | `units` ms/frame | `move_and_slide` ms/frame | per unit (`units`) |
|---|---|---|---|
| 2 | 0.36 | 0.02 | 0.18 ms |
| 7 | 5.21 | 3.55 | 0.74 ms |
| 15 | 124.40 | 61.27 | **8.29 ms** |

**Per-unit cost rises ~46× between 2 and 15 units.** That is not linear, and it
contradicts `probe_perf_scaling.gd`'s archived "linear, no O(n²)" finding. The
likely reason the probe missed it: it spawns units on a ring at spread
positions, while real play clusters them into squads — and `move_and_slide`
cost is a function of how many *other* bodies each sweep touches.

`move_and_slide` alone is 44.0 s of the 258.8 s match (17 %), 68 % of the
`units` bucket. Everything else inside the unit tick is noise by comparison
(`terrain_speed` 0.14 ms, `tick_economy` 0.10 ms, `separation` 0.06 ms,
`advance_orders` 0.02 ms).

**This is the original "under 10 FPS at 6–8 engaged units" report, reproduced
and localised.** It is collision geometry, not GDScript.

## 10.3 `navmesh_sync_rebake` — 29 s of a 259 s match

`TerrainBuilder.rebake_ground_amphibious_tiles_sync()`, called 107 times for
59 structures, **mean 272 ms, worst 626 ms**, all synchronous on the main
thread. 11 % of the match, and the dominant section on the worst steady-state
hitches (880 ms, 871 ms, 761 ms). Roughly two rebakes per structure placed.

## 10.4 `commander.execute` — 250 ms per call, mostly unattributed

Track B's prediction was half right. The cost is entirely in `_execute`
(17 746 ms) — `read_state` is 26.7 ms total and `decide` is 4.1 ms total, so
those are solved and need no further work. But the placement search is *not*
the culprit either: `ai_placement_site` is only 180.7 ms total (3.3 ms mean).

Of `commander.execute`'s 250 ms mean, nested `place_structure` (47.9 ms) and
`ai_placement_site` (3.3 ms) account for ~51 ms. **~200 ms per call is still
unnamed**, inside `ai_build_structure` / `ai_build_unit` / `ai_build_defence`.

Note these sections **nest** — `commander.execute` contains `place_structure`
which contains `battle_resource_load` — so the 78 % instrumented figure
double-counts. Top-level-only, it is ~54 %.

## 10.5 Correction to §2 and §5 Track A: the early "stalls" are probably idle gaps

§2 read three multi-second `<untimed>` stalls as compute. That looks wrong.
In the reference log the equivalents land on **frames 1, 44 and 86** — and the
14-13-08 log has the same shape at **frames 1, 44 and 90**. Identical frame
indices across two independent sessions, with `units_alive: 0` and no section
time recorded, is the signature of *wall clock passing while the director is
not ticking* (deploy gate, HQ placement, camera intro) — not of a stall.

The frame-1 value is definitely an artifact: it reads 189 003 ms in a
258.8 s match, i.e. the profiler's `_frame_start` baseline predates the match.

**Discard frame-1 hitch values, and treat frames 44/86 as idle gaps until
proven otherwise.** Confirm cheaply by watching whether the deploy gate is on
screen at those moments. This demotes Track A from "highest value" to a
30-minute confirmation.

## 10.6 Load time: terrain mesh is the whole of it

Across all 631 runs with build phases:

```
time-to-Ready   p50 15.7 s   p95 44.9 s   max 83.6 s
```

Essentially all of it is one phase, **"Sculpting terrain mesh"** — mean 21.2 s,
max 81.9 s. Every other phase is under 0.4 s. By map (median):

| Map | Median | Map | Median |
|---|---|---|---|
| scattered_peaks | 55.8 s | coastal_strand | 19.4 s |
| lake_crossing | 27.8 s | twin_summits | 12.3 s |
| ore_basin | 20.2 s | highland_chokepoint | 11.1 s |
| twin_bridges | 20.0 s | urban_sprawl | 10.9 s |
| open_plains | 19.8 s | close_quarters | 9.8 s |

**But 7 runs built lake_crossing in ~3 s** — the same map that medians 27.8 s.
Checked and ruled out as explanations: concurrent processes, viewport size,
time of day, warming over the day (it gets *slower* late: 36.1 s, 34.4 s).
All 7 fast runs are real playtests. **Finding out what makes those 3 s is the
highest-value load-time question** — a 9× speedup already exists in the code
path and something is failing to take it.

## 10.7 Log hygiene

- 625 logs in one day, ~600 of them harness runs on `scattered_peaks`
  (identical 3 units / 2 structures / ~70 frames). They swamp the directory and
  the real playtests are hard to find. Give suite runs
  `log_profiling = false`, or a distinct filename prefix.
- The `build_phase` duplicate spam (§4.5) is still present — 308 events per
  run, with one label repeated ~20× at an identical timestamp.
- `render_frame` is deliberately an empty section. Worth a comment in the log
  reader so a future reader doesn't mistake 0.001 ms for a broken measurement.

## 10.8 Revised priority order

Superseding §8. Ranked by measured cost, cheapest decisive experiment first.

1. **`unit.move_and_slide` collider cost** (§10.2) — 17 % of the match and the
   cause of the original report. Experiment: force every battle unit to a
   single capsule/box collider, re-run the same playtest, compare the
   `units` bucket at 15 units. One afternoon, and it either confirms collision
   geometry or eliminates it. Suspects, in order: the multi-piece convex hull
   decomposition (`<id>_collision.res`, 2–5 shapes on 34 hulls), the per-module
   `Area3D` hit volumes on `UNIT_MODULES`, and unit-vs-unit sweep pairs.
2. **`navmesh_sync_rebake`** (§10.3) — 11 % of the match, trivially reducible.
   Coalesce the ~2-per-structure rebakes into one, debounce across a build
   burst, or move it off the main thread.
3. **The renderer** (§10.1) — 4.5 fps rendered while the sim runs at 14.5 Hz.
   Run §5 Track E's five sweeps; they are mechanical and one of them likely
   moves this a lot (msaa 4x at 1920×1080 is the leading suspect).
4. **`commander.execute`'s missing 200 ms** (§10.4) — one more instrumentation
   pass inside the three `ai_build_*` functions.
5. **Terrain build fast path** (§10.6) — find why 7 runs did in 3 s what
   normally takes 28 s.
6. **`production` at 4.27 ms every frame** (worst 429 ms) — high for a
   bookkeeping tick; it reached 9.2 s per 30 s window late in the match.
7. **Confirm the idle-gap reading** (§10.5) before spending anything on Track A.
8. Log hygiene (§10.7), then the regression guard (§7) — now writable against
   real numbers: assert the `units` bucket stays under ~2 ms/unit/frame at 16
   units.
