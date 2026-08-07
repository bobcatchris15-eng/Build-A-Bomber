# Operations Loop — Immediate Plan

Written 2026-08-07, immediately after the retirement commit. Supersedes the
"Order of work" section of `OPERATIONS_PLAN.md`, whose steps 1–4 are now done.

---

## 0. DONE — and the diagnosis below was wrong

**Resolved 2026-08-07.** The ten map smokes did not fail on the production step.
They failed one step earlier, on resource reachability, and the cause was not in
the helper's migrated code at all: `suite_base._smoke_test_map()` waited on
`world_is_ready` and then queried the ground navmesh immediately.

`NavigationServer3D` applies `map_create` / `map_set_active` /
`region_set_navigation_mesh` as **queued commands**, flushed on its own sync
pass. In headless, `match_director._setup_terrain()` takes the blocking bake
path with no awaits, so `_ready()` finishes inside `add_child()` and
`world_is_ready` is already true zero frames later — with the map created but
not published. Every `map_get_path()` then returned an **empty array**, which
the helper correctly reported as "resource node is not reachable".

The tell: the *first* map in a process passed and every one after it failed,
purely because the first had spent a frame elsewhere.

Measured (`tools/probe_nav_sync.gd`, since deleted — numbers preserved in
`suite_base._await_nav_map`'s comment): the polygons land on the **second**
iteration bump, ~8 frames in. Neither `map_is_active` nor a non-empty region
list means the map can be pathed on. Ten call sites in
`test_terrain_and_maps.gd` were waiting a hardcoded one or two frames — a
number that happened to work on the machine it was written on.

`_await_nav_map()` now waits for the real condition. Result: **21 → 6 failing
suites**. The five "pre-existing" heightmap/navmesh failures
(`test_b5`, `test_b6`, `test_b8`, `test_b10`,
`test_bridges_carve_a_real_ground_crossing_through_water`) were the same bug and
are green too — they were never map defects.

The migrated production check is **correct and passing**; it did not need
deleting. The remaining 6 failures are the genuine set: sensor mast, modular
assembly meshes, locomotion golden fixture, design-to-battle integration, module
drag, UI glyphs.

<details>
<summary>Original (incorrect) diagnosis, kept for the record</summary>

### FIRST: ten failing map-smoke suites (blocker, ~1 hour)

**Do this before anything else.** The retirement commit left the tree at
**20/204 suites failing** against a like-for-like baseline of 10, and every one
of the ten new failures is the same migration:

```
test_map_open_plains_smoke        test_map_twin_summits_smoke
test_map_lake_crossing_smoke      test_map_close_quarters_smoke
test_map_highland_chokepoint_smoke test_map_urban_sprawl_smoke
test_map_coastal_strand_smoke     test_map_scattered_peaks_smoke
test_map_twin_bridges_smoke       test_map_ore_basin_smoke
```

They share one helper, `tests/suite_base.gd::_smoke_test_map()`, which was
migrated from `Skirmish.tscn` to `Battle.tscn` rather than being deleted with the
other 62 legacy suites — these ten validate the **maps** (spawn legality,
resource reachability, HQ-to-HQ connectivity, fairness lint), which is not a
property of any one match controller and was worth keeping.

**What is already verified working**, so do not re-investigate it — a standalone
probe against `open_plains` confirmed all of the following through the migrated
code path:

```
ready=true after 3 frames   map_id=open_plains   name=Open Plains
hqs=2   roster=13   ground_nav_map_valid=true
harvester found=true  name=Scrapper Ore Trucker
```

So the scene loads, `world_is_ready` fires, both HQs spawn, the navmesh RID is
valid and the harvester blueprint is found. **The remaining suspect is the last
step of the helper — the production check.** It was rewritten from
`factory.queue_unit(harv_bp, 0.05)` to:

```gdscript
battle.production.enqueue_unit(battle.PLAYER_TEAM, harv_bp, 0, 0, 0.05, queue_name)
```

Two things about that are unverified and are where to look first:

1. **`ProductionService` may require a live contributor** for the queue. The
   legacy call went through a specific factory node; the new one goes to a global
   per-tier queue that only advances when a contributing manufactory exists. If
   the tier `queue_for_design()` picks has no contributor on that map, the job
   never advances and the unit count never rises.
2. **Zero cost may not mean free.** Passing `0, 0` for metal/crystal with
   drip-fed production may behave differently from a legacy build with an
   explicit `build_time`.

Instrument `production.status(PLAYER_TEAM, queue_name)` inside the helper and
print it — the readout already distinguishes `empty`, `stalled`, `done` and
"no contributor", which should name the cause in one run.

If the production check turns out to be the wrong assertion for the new runtime,
**delete that step rather than contorting it**: the other five checks in the
helper are the ones that are actually about the map, and "a unit can be built"
is already covered by the `tests/battle/` production suites.

</details>

---

## What the retirement commit actually did

- Deleted `skirmish.gd`, `enemy_ai.gd`, `production_queue.gd`, `building.gd`,
  and `scenes/Skirmish.tscn`.
- Removed **62** suites that tested the legacy implementation, and their
  `SUITE_ORDER` entries. 266 → 204 suites.
- Migrated `_smoke_test_map()` to `Battle.tscn` (see above).
- The menu now has one **SKIRMISH** card, pointing at `MatchSetup.tscn`, which
  launches `Battle.tscn`. The `BATTLE (REBUILD)` card is gone.
- `MatchConfig.target_scene` — added earlier this session only so one setup
  screen could serve two runtimes — was **removed**, not left as a dead seam.
- `operations_setup.gd`, `scene_router.gd`'s `WARM_SOURCES`, and the visual
  regression harness all repointed.

### Coverage genuinely lost

The 62 deleted suites were not all redundant. `tests/battle/` does **not** yet
cover, at the depth the legacy suites did:

- base-building placement legality edge cases (10 suites),
- production queue economics — parallel queues, the 0.75× second-factory bonus,
  refunds on contributor death (26 suites),
- wave composition and counter-picking in the old AI (6 suites).

Some of this is genuinely obsolete — it tested `production_queue.gd`, which no
longer exists. Some is not. **When Operations work touches the economy, budget
time to re-cover the second bullet against `ProductionService`.**

---

## 1. Persistence — DONE 2026-08-07

JSON to `user://operations/<id>.json`, versioned (`SAVE_VERSION = 1`). A save
whose version has moved on is **refused, not half-applied** — `from_dict()`
returns false and leaves the manager alone, because a silently mis-loaded
campaign is worse than one that admits it cannot be restored.

Holds the itinerary, current stage, difficulty, the drafted roster, and the
combat log. Written on every state change (`start_new_operation`,
`record_stage_result`, `advance_to_next_stage`, `set_player_roster`), so there
is no "save" the player can forget to press. `list_saved()` enumerates them
newest-first, which is what a Continue Operation entry will read.

## 2. The loop — DONE 2026-08-07

`OperationsManager` is an autoload now. `record_stage_result()` and
`advance_to_next_stage()` have call sites at last:

- `match_director._show_after_action_report()` records the result and passes a
  real `is_operation` — it was hardcoded `false`, which is the single line that
  made an Operation one match with a different setup screen.
- The report's "Next Engagement" advances the pointer and routes to the draft
  screen. **Advancing is the player's choice**, made there rather than at match
  end, so a lost engagement leaves the campaign where it was until they say so.
- `_stage_result()` records who won, how long it took, the per-design rows, and
  **what each side fielded** — the last is the only moment both compositions are
  still in one place, and it is what section 4 reads.

### A bug this turned up

`after_action_report.gd:66` assigned `Label.alignment`, which does not exist
(`BoxContainer` has it; `Label` has `horizontal_alignment`). It raised at
runtime and **aborted `_build_ui()` on that line, every time** — so the report
has never rendered past its header: no per-design table, no iterate button, no
way out but the escape key. Found by an end-to-end probe looking for the
campaign's "Next Engagement" button and finding no button at all. This is why
seams get a probe and not only unit tests.

### Setup screen — DONE 2026-08-07

`operations_setup.gd` is now Match Settings plus an itinerary, not a read-only
3-stage card list:

- **3–12 engagements** via SpinBox, bounded by `OperationsManager.MIN/MAX_ENGAGEMENTS`.
- **Per-engagement map choice**, one dropdown per round, with a `Random` entry
  resolved to a concrete map at start (so a random itinerary is genuinely
  different each run, not the default map repeated).
- **Player *and* enemy faction**, matching `match_setup.gd`'s controls and its
  `technocrats` default.
- **The same 12-slot `RosterPicker`** the skirmish setup uses, replacing the flat
  CheckBox list — the exact control that screen already replaced, for the same
  reasons.
- **Difficulty is a ramp, not a flat setting**: the chosen tier is where the
  operation *ends*; the first third runs one tier easier. Shown per row.

Two smells fixed on the way: the screen constructed a throwaway
`OperationsManager` to read the itinerary and then a *second* one into `/root`
(the defaults are a static call now), and `total_stages` was a stored field that
a custom itinerary left stale at 3 (it is derived from the itinerary now).

Covered by four suites in `tests/battle/test_operations_setup.gd` — count range,
random/hand-picked map resolution, resize preserving picks, and the ramp.
Headless cannot press buttons, so they assert `build_itinerary()`, the screen's
output contract, rather than driving input.

## 3. Drafting — DONE 2026-08-07

`scenes/OperationsDraft.tscn` / `operations_draft.gd`, between every engagement:

- The same 12-slot `RosterPicker`, **opening on last round's roster** via the new
  `fill_from()` (the inverse of `ordered_paths()`). Between rounds the common
  case is keeping what worked; an empty default would make holding a roster more
  work than changing it. A design deleted from the library since last round
  leaves a gap rather than a slot that looks filled and fields nothing.
- **What the opponent fielded**, plus your own per-design built/kills/lost. This
  is the whole point — re-drafting blind is a chore, re-drafting against a known
  composition is the decision the operation is built on.
- Deploy writes the *next* engagement's map and difficulty. Factions are not
  rewritten: they were chosen once, for the operation.
- Design Lab and Abandon Operation, since iterating between rounds is the
  premise.

## 4. Counter-drafting (~half a day) — THE ONLY PART LEFT

**Half of it is done.** The recording exists: `record_stage_result()` writes
`player_designs` / `enemy_designs` per round and `fielded_history()` hands them
back. What is missing is the *reading* — `match_director._load_roster()` still
builds `enemy_roster` from the bundled defaults every engagement, identically,
so the opponent fields the same army in round 6 as in round 1 no matter what beat
it.

The scoring exists: `Commander.design_fills_role()` reads roles off a design's
mounted modules, so it can classify designs it has never seen, including ones the
player built. This is `enemy_roster` selection by the same considerations, not
new AI.

Keep the handicap honest — a difficulty-scaled income trickle is the only
concession. The AI reads the same services the player's HUD does.

**Test:** feed a log of all-air and assert the drafted roster gains anti-air.

---

## Known issues carried forward (not blockers)

Measured this session, in priority order:

| Issue | Measurement | Status |
|---|---|---|
| `units` `_physics_process` | 5.25 ms/frame mean, largest steady-state cost | untouched |
| Navmesh face generation | 365 ms per placement, main thread | async bake done; face gen still sync |
| `place_structure` | 393 ms | untouched |
| Economy tuning | ~5–6.7 metal/s income vs ~20 metal/s build draw; queues stalled 40–66% | needs a balance target |
| Draw calls | ~31 per unit, no batching | untouched |

Profiling harness is `tools/profile_battle_run.gd` (`-- [seconds] [on|off]`).
Instrumentation overhead measured at 0.05 ms/frame (0.3%), so its numbers can be
read as real.

`test_target_dummies_actually_take_damage_in_test_range` is a **flake, not a
regression**. Measured 1/4 passing run completely alone, which matches
`run_tests.gd`'s own note that it "fails even run completely alone, a real
timing race". Two quarantine attempts is not enough retries for a suite that
passes a quarter of the time, so it will surface in a full run now and again.
Worth fixing at the source rather than by adding attempts.

Baseline as of 2026-08-07: **6 failing of 211**. Sensor mast, modular assembly
meshes, locomotion golden fixture, design-to-battle integration, module drag, UI
glyphs. All six are Design Lab / mesh suites and none are navmesh-related — the
"four heightmap/navmesh suites" that used to sit in this list were the
navigation-sync bug in section 0 and are green.
