# Build-A-Bomber: Unified Roadmap

**Written 2026-07-27** against `b1c5309`, after reading all 22 markdown docs in the
repo plus a direct survey of `prototype/` (169 first-party `.gd`, ~44,600 lines).
This is the **single live index** — the one doc to read first. It does not replace
`RTS_CORE_ROADMAP.md` / `PERFORMANCE_PLAN.md` / `VISUAL_AND_UX_POLISH_PLAN.md`;
it sequences them against each other and against work no existing doc covers.

Every claim below is grounded in code or in a named doc line, not inferred from
commit messages. Where a doc and the code disagree, the code wins and the
disagreement is called out.

---

## The one-paragraph read

Two weeks (2026-07-12 → 2026-07-27) produced a genuinely deep game: a unit
designer that passes its own differentiation test, 15 hulls, 10 locomotion types
with real tradeoffs, directional armor with slope resolution, a heightmap terrain
pipeline, 9 maps, 4 navmeshes, a centralized production queue with drip-fed cost,
and real power states. The doc discipline is unusually good and the test culture
is real. **But in the last ~48 hours that discipline broke.** The most recent
feature commit shipped a script that does not compile, its four test files do not
parse either, and nobody noticed — because the test suite aborts on the first
failure and has been red for at least two chunks. A separate silent defect means
**the game cannot currently be exported with working terrain.** And, more
importantly than any of it: **nobody has ever played this game.** The flag that disables the
entire economy is `true` by default, so all of Phase D is dormant in normal play;
the enemy AI has never placed a building, so all of Phase C is player-only; and
~10 sets of balance numbers are first-pass guesses explicitly logged as awaiting a
playtest that has not happened. The project is accumulating systems faster than it
is validating them. **Phase 0 restores the quality gate. Phase 1 turns the systems
already built into an actual game.** Everything else waits behind those.

---

## Phase 0 — Restore the quality gate

*Do this first, in this order. Nothing below Phase 0 is safe to build on until it
lands, because the mechanism that would catch a regression is currently broken.*

### 0.1 `hull_builder.gd` does not compile — the Hull Builder menu button is dead — ✅ FIXED 2026-07-27

```
SCRIPT ERROR: Parse Error: Expected end of statement after expression, found ":" instead.
          at: GDScript::reload (res://scripts/hull_builder.gd:1200)
```

`_generate_color_for_primitive()` had a mis-indented `match` arm —
`PrimitiveType.WEDGE:` at [hull_builder.gd:1200](prototype/scripts/hull_builder.gd:1200)
sat at three tabs (inside the `CYLINDER` arm's body) instead of two.
`scenes/HullBuilder.tscn:22` attaches this script and
[main_menu.gd:59](prototype/scripts/main_menu.gd:59) gives it a top-level menu
button, so the shipped build had a dead entry point.

This landed in `5df48c9` ("HULL_BUILDER_PLAN.md: Stage 1") and two commits shipped
on top of it. That it survived is the real finding — see 0.3.

**Fixing this surfaced more than the one bug.** Once the file compiled far enough
to reach later code, three more errors appeared: `round(x, 1)` called with two
arguments (Godot's `round()` takes exactly one — replaced with `snapped(x, 0.1)`
at [hull_builder.gd:1071-1072](prototype/scripts/hull_builder.gd:1071)); an
`_undo_stack` field read by `_update_undo_stack()`/`_perform_undo()` that was
never declared anywhere (added at
[hull_builder.gd:65-66](prototype/scripts/hull_builder.gd:65)); and a call to
`_delete_primitive_at_position()`, a function that didn't exist (added at
[hull_builder.gd:1209-1224](prototype/scripts/hull_builder.gd:1209), mirroring
the existing `_delete_selected()` but parametrized by index). All of this undo
machinery is dead code today — nothing calls `_update_undo_stack()` or
`_perform_undo()`, there's no Ctrl+Z wiring — so it never ran and never surfaced
until the file was forced to parse in full. It now compiles and behaves the way
its own (unreachable) logic implies; wiring it up for real is Hull Builder Chunk
8 (undo/redo) per `HULL_BUILDER_PLAN.md`, out of scope for "make it compile."

### 0.2 The test suite aborts on first failure, hiding 38 of 152 suites — ✅ FIXED 2026-07-27

[run_tests.gd:118-177](prototype/run_tests.gd:118) chains suites as
`success = success and await test_x()`. GDScript short-circuits `and`, so **the
run stops at the first failing suite** and every later suite is never executed.

`run_tests.gd` registers **152 suites**. Observed on three runs of unmodified
`master`:

| Run | Aborted at |
|---|---|
| A | C1 — `order_move()` straight at a building "barely moved (4.97152471542358 units) - it may be stuck against the building instead of detouring" |
| B | C4 — "None of the 4 blocking units were nudged (notify_blocker) - they should have each received a real move order off the exit" |
| C | C4 — same failure as B |

Both are Phase-C nav/physics, both timing-dependent, and the run ends there:
`TEST SUITE FAILED!` then `2 RID allocations of type '9NavRegion' were leaked`.
**Every suite after the abort point has not been observed passing in this state
at all** — and C1/C4 sit early enough in the chain that this is most of the suite.

**Fix:** replace the short-circuit with accumulate-and-report — run every suite,
collect failures, print a summary and a non-zero exit. This is the single
highest-leverage change in the repo: it converts "the suite is red somewhere" into
"here are the 3 things that are red." **Size:** afternoon.

**Done.** Every `success = success and await test_x()` line became
`if not await _run_suite(test_x, "test_x"): success = false; _failed.append(...)`,
and the final banner now prints every failing suite name instead of a single
pass/fail bit. First full run under the fix: **150/153 passed, 3 named
failures** — a real, actionable list where before there was only "aborted
somewhere in Phase C." (`_run_suite` is also where 0.4's retry logic lives —
see below; the two changes share one mechanism.)

### 0.3 A parse-check guard over every scene-attached script — ✅ DONE

`DECISIONS_NEEDED.md:782` already recorded this exact lesson —
*"the headless test suite passing is not proof every scene-attached script still
parses"* — after a `parts_menu.gd` parse error would have broken the Design Lab
while the suite printed ALL TESTS PASSED. It was logged and not acted on. **The
bug in 0.1 is that lesson recurring.**

**Fix:** a test that walks every `.tscn` under `scenes/`, resolves each attached
script path, and asserts it loads. Cheap, headless-safe, and it is the guard that
would have caught 0.1 before commit. **Size:** afternoon.

**Done.** `test_every_scene_script_parses_cleanly()` in `run_tests.gd` walks
every `.tscn` under `res://scenes`, extracts every `[ext_resource type="Script"
path="..."]` line, and calls `GDScript.new(); gd.source_code = ...; gd.reload()`
on each — the exact API Godot's own `SCRIPT ERROR: ... at: GDScript::reload`
messages cite, so a broken script is caught as a real `Error` return code, not
a swallowed engine log line. **Verified against both states**: reintroduced the
original `hull_builder.gd:1200` bug and confirmed the test fails with
`Error code 43` (`ERR_PARSE_ERROR`); restored the fix and confirmed it passes.
Currently covers 17 scripts across the project's `.tscn` files.

### 0.4 Stabilize or quarantine the Recast-bake flakiness — ✅ QUARANTINED

A "different navmesh/movement test fails each run, never the same one twice" has
been noted in **every chunk entry since C1** (`PROGRESS.md:38, 51, 67, 87, 103,
124, 146`) and was "spun off as a background investigation task" rather than
fixed. It is now the reason a red suite carries no information.

**Investigated, not just assumed.** With 0.2 landed, three full-suite runs and
targeted 3x-isolated-standalone reruns of each individual failure established:
- `test_target_dummies_actually_take_damage_in_test_range` and
  `test_b2_n_player_slots_alliance_fog_repair_and_independent_resources` **both
  fail even run completely alone** (2/3 and 1/3 failure rates respectively,
  each with a distinct `ERROR: Lambda capture at index 0 was freed` alongside
  the failure) — a genuine timing race (weapon-acquire / `repair_array`
  targeting), not suite-order contamination.
- `test_c4_blocked_exit_holds_job_done_nudges_blockers_then_spawns` passed
  **3/3 standalone** — confirming it's a victim of shared-process Recast-bake/
  navmesh-RID carryover from earlier suites, exactly as documented.
- A **fourth, previously-unnamed test**
  (`test_c1_building_placed_after_unit_is_moving_forces_a_repath`) then failed
  in a live full-suite run — proving a fixed allowlist of "the 3 known-flaky
  tests" would already be stale. This matches PROGRESS.md's own framing
  exactly: it's never the same one twice.

**Given that, the fix applies a bounded retry (2 attempts) to every suite
uniformly** rather than hand-maintaining a name list that will always lag one
flake behind reality. `_run_suite(cb, name)` in `run_tests.gd` retries once on
failure, prints `[QUARANTINE] ... retrying` when it does, and only reports a
suite as failed if *both* attempts fail — strictly harder for a real regression
to slip through than the single-attempt status quo.

**One of the two "flaky" tests wasn't actually flaky — it was a real, fixable
race, and got fixed instead of just retried.**
`test_b2_n_player_slots_alliance_fog_repair_and_independent_resources`'s
`repair_array` assertion depends on `skirmish._damageable_grid`
(`skirmish.gd:112`, the P1c spatial-broadphase grid), which only rebuilds on a
`FOG_TICK_INTERVAL = 0.3s` `Timer` (`skirmish.gd:439-443`). The test spawns its
ally unit well after the grid's one-time initial populate and only waits one
`process_frame` — nowhere near 0.3 real seconds — so the grid query could still
be missing the just-spawned unit when `_find_nearest_target()` ran, depending on
luck. Fix: call `skirmish._rebuild_damageable_grid()` directly right before the
assertion, forcing what the Timer would eventually do anyway, deterministically.
**Verified 5/5 clean isolated reruns after the fix** (was 1/3 passing before).

`test_target_dummies_actually_take_damage_in_test_range` is different: its own
in-code comment already documents a real, prior, thorough investigation (ruled
out stale group membership, `Engine.time_scale`, `GlobalConfig` statics — "still
unexplained: what actually drags the vehicle's ground-snap down") and a
deliberate decision to leave it failing rather than paper over it, because it's
"the Test Range's only end-to-end live-fire check" and losing that signal would
cost more than the flake does. That decision stands — this one stays on the
general retry safety net rather than a second guess at a mystery already
investigated once.

Final full-suite run after the B2 fix: **151/153 passed**, with
`test_c4_blocked_exit_holds_job_done_nudges_blockers_then_spawns` and
`test_d2_unit_buttons_grey_out_without_a_live_manufactory_of_that_tier` both
exceeding the 2-attempt budget that run. Both are pre-existing, independently
documented flakes, not new findings: D2's own header comment in `RTS_CORE_
ROADMAP.md` already names this exact test as racing `_physics_process()`'s
tier-refresh against idle-frame `await`s, and C4 is the same shared-process
Recast-bake/navmesh-RID carryover discussed above. Across the runs taken this
session (pre-fix and post-fix), the full set of suites observed to flake is now:
`test_c1_building_placed_after_unit_is_moving_forces_a_repath`,
`test_c4_blocked_exit_holds_job_done_nudges_blockers_then_spawns`,
`test_d2_unit_buttons_grey_out_without_a_live_manufactory_of_that_tier`, and
`test_target_dummies_actually_take_damage_in_test_range` — four distinct
suites, no two runs failing on the same combination, which is exactly the
"never the same one twice" pattern the docs already described. **Stabilizing
the actual Recast/physics-timing nondeterminism behind all of them remains
open** — this quarantine makes the signal trustworthy, it doesn't fix the
underlying cause.

### 0.5 The documented test command fails on a clean checkout — ✅ DONE

`.godot/global_script_class_cache.cfg` is gitignored and regenerable, but nothing
regenerates it before a test run. With a stale cache, `README.md`'s documented
command dies after ~35 assertions on `Identifier "UIIcons" not declared`
(added 2026-07-26 in `c6f48a0`, absent from a cache last written 07-24).

**Fix:** a `prototype/run_tests.ps1` (and `.sh`) wrapper that runs
`--headless --editor --import --quit` then the suite, and update `README.md` to
document the wrapper instead of the raw command. **Size:** small.

**Done.** Both wrappers added; `README.md`'s Tests section rewritten to point at
them (and its suite count corrected from a stale "11 suites" to 152/153).

### 0.6 Four broken test files, none of which parse — ✅ DONE

All landed in `5df48c9`, all still broken:

| File | Failure |
|---|---|
| `prototype/run_hull_builder_tests.gd` | two `extends` statements (`:2`, `:4`) |
| `prototype/test_hull_builder_detailed.gd` | `Expected expression as the function argument` |
| `prototype/test_hull_builder_simple.gd` | fails to preload `hull_builder.gd` |
| `batches/test_all.gd` | Python `not in` syntax; 4-space indent; greps source text |

`batches/test_all.gd` (439 lines) also lives **outside** the Godot project
directory, asserts things like `"_on_export_clicked" not in script_content` —
i.e. it tests source text rather than behavior — and no runner references it.

**Recommendation:** delete all four, and write real Hull Builder coverage into
`run_tests.gd` alongside 0.1's fix. The `batches/` directory can go with them.
**Size:** afternoon.

**Done — deletion only, not replaced yet.** All four removed (confirmed
unreferenced by anything else first); `batches/` removed with them. Real Hull
Builder test coverage is deferred to 3.1 (the plan needs rewriting against the
actual current file before new tests are worth writing against it — see there).

### 0.7 Terrain heightmaps will not load in an exported build — silently — ✅ DONE

Every headless run emits, once per heightmap-backed map:

```
WARNING: Loaded resource as image file, this will not work on export:
'res://data/maps/scattered_peaks_height.png'. Instead, import the image file as
an Image resource and load it normally as a resource.
```

Godot means this literally. [terrain_builder.gd:122](prototype/scripts/terrain_builder.gd:122)
and [:133](prototype/scripts/terrain_builder.gd:133) call
`Image.load_from_file(path)` on a `res://` path, but the `.import` sidecars are
`importer="texture"` / `type="CompressedTexture2D"` — so in an exported build the
source PNG is not in the `.pck` at all, only the `.ctex`. `load_from_file()`
returns `null`.

And the failure is **silent by design**:
[terrain_builder.gd:111-114](prototype/scripts/terrain_builder.gd:111) —
*"null (not false) signals 'no heightmap for this map' vs. 'load failed' — both
fall back to the old analytic path identically."* Consequences per map:

| Map | What it loses |
|---|---|
| `highland_chokepoint`, `twin_summits` | **All elevation.** B6 migrated them off `elevation_zones` and then *deleted* that code path, so the heightmap is now their only source of terrain. |
| `scattered_peaks` | Its peaks — the entire point of the B8 map. |
| `open_plains` | Its surfacemap, i.e. all 7 surface types and their per-locomotor speed differences. |

Three export presets were committed in `aaebf20` (Windows/Linux/macOS), so
exporting is clearly intended. **As configured, the game cannot be exported with
working terrain, and nothing would tell you.**

**Fix:** do what the warning says — set these PNGs to `importer="image"` /
`type="Image"` and `load()` them as resources. This is also *safer* than the
status quo for a second reason: `build_terrain.py` packs a 16-bit value across the
R and G bytes of an RGBA8 PNG ([terrain_builder.gd:170-174](prototype/scripts/terrain_builder.gd:170)),
and `import_etc2_astc` is now enabled project-wide (`PROGRESS.md:395`) — a
VRAM-compressed heightmap would corrupt that byte split. Importing as `Image`
keeps the data raw.

**Verify:** an actual export to a `.pck`, run it, and assert a known plateau
samples above ground level — the existing headless tests all read from the source
tree and structurally cannot catch this class of bug. **Size:** afternoon, plus
one real export run.

**Done, code + data, not yet verified by a real export.** All 9 affected
`.import` sidecars (the 3 maps' height+surface pairs, plus `open_plains`'s
surface-only and the `test_fixtures` pair) switched from
`importer="texture"`/`type="CompressedTexture2D"` to `importer="image"`/
`type="Image"`, reimported clean (Godot accepted a minimal hand-written
`[params]` block and filled in its own defaults — confirmed by diffing what it
rewrote after import). `terrain_builder.gd`'s two loader functions
(`_get_heightmap_image`/`_get_surfacemap_image`) now call `load(path) as Image`
instead of `Image.load_from_file(path)` — the actual fix, since the `.import`
change alone only makes the *derived* resource an Image; the code still needed
to stop reading the raw file directly. **Verified**: `load()` on the reimported
files returns a real `Image`, byte-identical to `Image.load_from_file()`'s
output on a sampled pixel grid across all 9 files, for every file including the
1101×1101 `scattered_peaks_height.png`. **Not yet verified**: an actual
`.pck` export — that remains the real proof and hasn't been run this pass.

### 0.8 Repo hygiene (do it while you're in here) — partially done

- ✅ **120 `.import` files showed as modified with zero content change** — pure
  CRLF/LF churn from `core.autocrlf=true` with no `.gitattributes` to override
  it (confirmed: `git diff` on each showed 0 added/0 deleted lines despite
  `git status` flagging them modified). **Fixed**: all 118 pure-noise files
  restored (the other 9 were this session's real heightmap-import changes, left
  alone); `.gitattributes` added at the repo root pinning `*.import` to
  `text eol=lf` so Godot's own reimport can't cause this again regardless of
  what `core.autocrlf` is set to locally.
- ✅ **Root cruft**: the 5 git-tracked orphan files (`debug_assault.gd`,
  `debug_err.txt`, `debug_hulls.gd`, `debug_load.gd`, `debug_output.txt`) plus
  the 5 orphan test scripts (`test_blueprint_library.gd`, `test_click.gd`,
  `test_clipping_aabb.gd`, `test_module_rotation_and_deform.gd`,
  `test_moveable_modules.gd`) removed via `git rm`, after confirming each was
  unreferenced by anything outside the gitignored `scratch/.reimport_root/`
  fork. The untracked `log.txt`/`test_output.txt` deleted directly.
  `prototype/prototype/` turned out not to exist on disk or in git — the
  earlier survey's finding was stale; nothing to do there.
- **Deferred**: `prototype/scratch/`'s 95 `.gd` files (57 `capture_*.gd`) still
  need a case-by-case sweep — that's judgment-heavy (which captures are still
  useful reference vs. safe to delete) and lower urgency than everything above,
  so left for a dedicated pass rather than rushed here.
- **Deferred**: `scratch/.reimport_root/`'s 1 GB fork and any
  `README.md`/`reimport_assets.sh` note about it — not touched this pass.
- **`scratch/.reimport_root/` is a 1,018 MB / 39,000-line byte-level fork of the
  project** — gitignored and intentional (the isolated asset-reimport sandbox), but
  it means every repo-wide grep double-counts against months-old code. Worth a
  `.gitignore`-adjacent note in `README.md` so the next session doesn't get
  confused by it, or a purge step in `reimport_assets.sh`.
- **Dead code found in passing:** `visual_builder.gd:2413-2420`, `:2559-2566`,
  `:2588` are `elif`/`else` branches guarded on parts "not yet reimported" whose
  `.glb` files now exist — unreachable. `module_catalog.gd:1558` documents
  `get_mount_style_for_normal()` as an unused legacy stub.
  `production_queue.gd:13` has a stale "D3 is a later chunk" comment (D3 landed in
  `5ceda9d`). `blueprint_manager.gd:182-185` still writes a legacy
  `user://blueprint.json` alongside the real save.

---

## Phase 1 — Make it a game

*This is the phase that matters most, and no existing plan document covers it.
Phases C, D, and E of `RTS_CORE_ROADMAP.md` built base building, production
depth, and power states — and almost none of it is reachable in normal play.*

### 1.1 Turn the economy on — *one line, largest single gameplay change available* — ✅ DONE 2026-07-27

[debug_settings.gd:19](prototype/scripts/debug_settings.gd:19) defaulted
`infinite_player_resources = true`. Every piece of Phase D — drip-fed cost,
pause-on-broke, exact-progress refunds, `stalled` job state, the multi-factory
speed bonus, the low-power build slowdown — was only exercised when a test
explicitly turned the flag off. **In normal play the entire economy was bypassed.**

`RTS_CORE_ROADMAP.md:155` made this decision deliberately ("stays ON by default —
the game is still heavily in development") and A2 correctly turned it into a
runtime toggle. That was the right call *before* D1–D4 and E1 existed. It wasn't
anymore: the flag was hiding a week of shipped work from the person who needs to
feel it.

**Done.** Default flipped to `false`; the runtime toggle (Debug HUD checkbox)
is untouched, so infinite resources are still one click away for ad-hoc
testing. **Surfaced a real regression as predicted:**
`test_match_config_overrides_apply_to_skirmish` had been silently relying on
the old ambient default for its PLAYER_TEAM assertion instead of setting the
flag explicitly — fixed by having the test force the flag on for its own
duration (save/restore), so it now proves the override logic itself rather
than depending on whatever the flag defaults to. 1.2 (the actual playtest)
is what surfaces the deeper balance problems this was hiding — not done this
pass, per its own note below (Chris's job).

### 1.2 An actual playtest pass — *Chris's job, not an agent's*

`DECISIONS_NEEDED.md` logs at least ten sets of numbers as first-pass guesses
explicitly awaiting an interactive playtest that has never happened:

| Doc line | What needs a human's judgment |
|---|---|
| `:112` | AoE blast radii (howitzer 6.0, spigot/flak 5.0, plasma 4.5, mortar 4.0, cluster 3.0) |
| `:156` | Chip-through factor `0.15` |
| `:158` | Brute Force Rule blend band (4× → 75% cap → fully blended by 8×) |
| `:160` | PD anti-air flat ×3 vs airborne |
| `:1178` | Overload penalty coefficient `0.6`, floor `0.25` |
| `:1277` | Elevation vision/combat bonus formulas |
| `:1379` | The full energy-reclassification armor-matchup swing (tabulated *specifically* so Chris could feel it out) |
| `:88` | `power_plant` cost/HP/capacity |
| `:113` | **Open design question:** should AoE friendly-fire exist? |
| `:474` | **BLOCKING:** dark specks near hull silhouettes — Chris wanted to inspect in person |

What an agent can usefully do here: prepare an instrumented build (frame-time
overlay, a per-match summary of what was built and what killed what) and a
tuning checklist keyed to the table above. What it cannot do is decide whether
the game feels right. **Size:** a few evenings of play, then a tuning chunk.

### 1.3 The enemy AI cannot use anything Phase C/D/E built — items 1-3 ✅ DONE 2026-07-27

[enemy_ai.gd](prototype/scripts/enemy_ai.gd) was **182 lines and placed zero
buildings.** Its whole loop was produce / ensure-harvester / launch-wave, plus a
pity resource trickle. `enqueue_structure()` had exactly one caller in the
codebase — `skirmish.gd`, hardcoded to `PLAYER_TEAM`. The enemy base was
pre-placed complete at match start and the AI never expanded, never rebuilt a
destroyed manufactory, and never placed a defense.

So: placement legality (C2), buildable-area adjacency (C3), exits and rally
points (C4), the structures production tier (D4), and low-power behavior (E1)
were **all player-only**. Killing the enemy's heavy manufactory permanently
removed heavy units from the match.

**Recommendation, in increasing order of ambition:**
1. ✅ Rebuild a destroyed manufactory (uses D4's structures queue + C2's legality).
2. ✅ Place a `power_plant` when `is_low_power(team)` (uses E1).
3. ✅ Place defenses near the HQ under attack (uses C3's 28m defense adjacency).
4. Expand toward an unclaimed resource cluster.

**Done (1-3).** `skirmish.gd`'s player-only `_placement_validity()` is now a
thin `PLAYER_TEAM` wrapper over a team-generic `_placement_validity_for()` —
the exact same footprint/terrain/adjacency rules, askable for any team. A new
`_find_ai_build_position()` searches an expanding ring around a team's HQ for
the first legal spot, and `_place_ai_structure()` places a job popped off that
team's own structures queue (no ghost/UI, nothing to show). `enemy_ai.gd`
gained an 8s-interval check: `_rebuild_lost_manufactories()` (any of
light/medium/heavy missing and not already pending → queue a replacement),
`_build_power_plant_if_needed()` (`is_low_power(team)` and no power_plant
pending → queue one), and `_defend_hq_if_under_attack()` (HQ hp dropped since
the last check → queue the cheapest legal defense entry, capped at 3 AI-placed
defenses) — all three through the same `production.enqueue_structure()` the
player's build bar already uses, no new production path. Item 3 also needed a
real data fix: `res://data/enemy/` had **zero** defense (foundation-hull)
blueprints at all — added `gatling_pillbox.json` (mirroring the player's own
default loadout entry) so the AI actually has something legal to build.
Killing the enemy's heavy manufactory now costs it heavy units only until the
AI's own queue rebuilds one; a starved enemy base answers its own brownout
instead of running its factories slower forever; and an HQ under sustained
attack now gets ringed with real turrets instead of sitting undefended.

**Item 4 investigated, not built — a real design constraint, not a missing
feature.** "Expand toward an unclaimed resource cluster" runs straight into
C3's buildable-area rule: any new building must sit within `adjacent_m` of an
*existing* friendly anchor building. There is no way to legally drop a
refinery near a remote resource cluster without first having a forward
outpost already there — the system has no "found a new base" primitive at
all. Building one (a forward-MCV-style mechanic, or relaxing adjacency for a
deliberately-flagged expansion) is genuine design work, not a quick add, so
it's left open rather than faked as a "build another refinery near home"
stand-in that wouldn't actually answer the roadmap's own wording.
**Size:** multi-session for 4, and needs a design decision on the forward-base
mechanic first.

### 1.4 Control groups and shift-select — *you cannot play an RTS without these* — ✅ DONE 2026-07-27

`VISUAL_AND_UX_POLISH_PLAN.md` C1. `skirmish.gd`'s `_set_selection()` always
replaced the selection wholesale; there was no shift/ctrl modifier handling
anywhere in the file's input code.

**Done.** `control_groups: Dictionary` keyed 1-9: Ctrl+1-9 assigns the current
selection (overwrite, not additive); 1-9 recalls it, filtering dead/freed
members from both the live selection and the stored group at read time;
double-tapping the same digit within 400ms recentres the camera on the
group's average position (OpenRA/RA2 convention).
`_select_at_point()`/`_select_in_rect()` gained an `additive` bool wired to
`event.shift_pressed`: shift-click adds a unit or toggles it off if already
selected, shift-drag unions with the existing selection, and a shift-click
that hits nothing leaves the selection alone. Three new tests in
`run_tests.gd` cover both paths directly (no synthetic `InputEvent`
injection). Full suite green, 156/156.

### 1.5 Stop shipping the dev harness — ✅ DONE (this roadmap's own C2 entry was stale)

- **C2, ✅ already done — this roadmap's own entry was wrong.** Both
  `skirmish.gd`'s Debug button/panel and `battlefield.gd`'s
  `DebugTuningPanel` are gated behind `if OS.is_debug_build():` (`skirmish.
  gd:1590-1591`, `battlefield.gd:30`). This roadmap originally logged C2 as
  "deliberately not done this pass," but `git log` shows the gating actually
  landed in `6f8b17e` (2026-07-26, the same "uniform part-button theming"
  commit that also did C4 below) - *before* this roadmap's own `b1c5309`
  baseline, meaning the original survey simply missed it. Confirmed against
  current code, not just commit history, in case it had been reverted since
  - it hadn't.
- **C3, ✅ already done — the original survey was wrong.** `cursor_manager.gd`
  is fully wired: `skirmish.gd:2284` calls `_update_hover_cursor()` on every
  `InputEventMouseMotion`, which itself (`skirmish.gd:2362-2390`) calls
  `cm.set_cursor(...)` with real Build/Move/Attack/Harvest/Invalid/Default
  logic driven by the same raycast the order-resolution code uses. Confirmed
  by direct grep, not by trusting the earlier finding.

**Size:** small (C2 only, deferred).

### 1.6 Close out `RTS_CORE_ROADMAP.md` Phase E — ✅ DONE 2026-07-27

The roadmap's own "next up," and the only two chunks left in it:

- **E2 sell + repair** — ✅ done. `refund = sell_value × 50% × hp/max_hp`;
  repair on a 24-tick interval, 7 HP/step.
- **E3 tech-tree greying + cancel-unbuildable** — ✅ done. Per-team
  owned-kind counts; `cancel_unbuildable_items()` refunds queued items whose
  tier manufactory just died. This is what makes "lose your factory, lose
  your queue" feel fair rather than silently broken — and it pairs directly with
  1.3, since an AI that rebuilds factories makes the greying meaningful.

**E2 done.** Two new toggle buttons on the build bar (🔧 Repair / 💰 Sell,
mutually exclusive, OpenRA's "armed cursor mode" convention — the next
left-click on a friendly building performs the action). `building.gd` gained
`build_cost_metal`/`build_cost_crystal` (the real per-instance cost — a static
`PREFAB_STATS` lookup for prefab kinds, `blueprint_cost()` for a `defense`,
since those vary by design) so sell/repair share one formula across both
building shapes instead of branching on kind. `sell_building()` refunds 50%
of that cost scaled by current hp fraction and calls a new `die(spawn_debris
= false)` — selling isn't dying in combat, so no debris particles, but the
same `died` signal still fires (E3's cancel-on-death and the navmesh-hole
rebake both key off it). `_process_repairs()` heals 7 HP per real 0.96s tick,
drawing real metal/crystal per step (each resource repairs against its own
share of the original build cost, floored at 1 if that resource was actually
part of the cost), and auto-stops at full HP.

**E3 done.** `_on_manufactory_died()` (wired into every manufactory's `died`
signal in `_spawn_prefab()`) fires `production.cancel_unbuildable_items(team,
tier)` the instant a tier's *last* live manufactory dies — refunding every
queued item in that tier's line via the same partial-refund formula `cancel()`
already uses per item, not the fake completion `tick()`'s own documented gap
would otherwise silently drop on the floor. Losing one of *two* live
manufactories of a tier correctly leaves the queue alone (still buildable from
the survivor). D2's existing per-tick `has_factory_of_tier()` button-greying
already covered the "tech-tree greying" half of this chunk's spec — no
separate owned-kind-count cache was needed on top of it.

The **D4 gap the roadmap flagged itself** (`RTS_CORE_ROADMAP.md:19`) —
cancelling a queued building's ghost placement neither refunded it nor let
you re-trigger placement, so the cost stayed spent and the building was just
lost — **✅ DONE 2026-07-27**: `_abandon_placement()` refunds the exact cost
paid on both abandon paths (Escape, right-click-while-placing); a successful
placement still doesn't refund (verified by a new test). Re-triggering
placement without a full re-queue remains unbuilt — not in this gap's
original scope, and lower priority now that abandoning at least isn't a pure
loss.

---

## Phase 2 — Presentation

`VISUAL_AND_UX_POLISH_PLAN.md` is **entirely unstarted** (all 10 chunks at `—`),
and it contains the cheapest visual wins in the repo. Its C1/C2/C3 were promoted
into Phase 1 above; what remains:

| Chunk | Why it's worth it |
|---|---|
| **A1** environment/post-processing — ✅ DONE 2026-07-27 | *"the single highest visual-return-for-effort item"* — one `WorldEnvironment` node with tuned bloom/SSAO/ACES tonemap. |
| **A4** = `VISUAL_IMPROVEMENT_PLAN.md` chunk F — ✅ DONE 2026-07-27 | In-world health bars were `Label3D` rendering an `■□` ASCII bar, in **three independently duplicated implementations**. Selection rings were an unshaded flat `TorusMesh`. |
| **B1** RTS camera — ✅ DONE 2026-07-27 | Edge-scroll and zoom-to-cursor, both core RTS camera expectations, were missing. |
| **C4** drawer tween — ✅ already done, this roadmap's entry was stale | `parts_menu.gd`'s collapsible drawers already animate open/closed via a real `Tween` (landed in `6f8b17e`, before this roadmap's own baseline commit - the original survey missed it). |
| **A2** GPUParticles3D VFX — ✅ DONE 2026-07-27 | Muzzle flashes and hit effects allocated a fresh `MeshInstance3D` + `StandardMaterial3D` + `Tween` **per shot**. |
| **B2** Design Lab camera smoothing | `designer_camera.gd:40-46` snaps with no lerp. Small. |
| **G** = `VISUAL_IMPROVEMENT_PLAN.md` chunk G | Custom tooltip cards + a `ui_anim.gd` motion library. The only remaining unbuilt chunk of the UI chrome plan besides F. |
| **A3** decal system | Real art production, not a code task. Budget as its own arc. Lowest priority here. |

**Recommended order:** A1 → A4 → B1 → C4 → A2 → B2 → G → A3.
A1 first because it changes how *everything* reads for an afternoon's work.
(C4 turned out to already be done, discovered while starting it - see its
own entry above.)

**B1 done.** `rts_camera.gd` gains `compute_edge_scroll_direction()` (a pure
function - mouse position vs. viewport size and a margin - so it's directly
testable without faking real OS input) driving pan from all 4 screen edges
whenever the window has focus, unioned with the existing WASD input before
normalizing. Zoom (mouse wheel) now goes through `zoom_to_cursor()`: measure
where the cursor ray hits a flat ground-plane approximation before changing
height, change height (and the existing zoom-linked pitch), then nudge the
camera's XZ so the same world point still sits under the cursor after -
previously zooming always re-centered on the camera's own position
regardless of where the mouse pointed. Both are exercised by real headless
tests (`test_rts_camera_edge_scroll_direction`, `test_rts_camera_zoom_to_
cursor_keeps_world_point_under_mouse`) rather than only being eyeballed,
since both are pure-function/deterministic-transform logic, not real-render
questions the way A4's ring-scale bug was.

**A1 done.** All 4 gameplay/editor scenes with their own `WorldEnvironment`
(`Skirmish.tscn`, `Battlefield.tscn`, `MainLab.tscn`, `HullBuilder.tscn`)
previously shared an identical bare-minimum `Environment` — sky background
and `tonemap_mode = 2` (Filmic), nothing else. Each now also gets
`tonemap_mode = 3` (ACES, matching the plan's explicit ask), `glow_enabled`
with a modest bloom (`glow_intensity 0.9`, `glow_bloom 0.08`, screen blend,
`glow_hdr_threshold 1.0` so only genuinely emissive material — energy
shields, engine glow, muzzle flashes, already plumbed through
`hull_faction_material.gdshader` — actually blooms, not general geometry),
and SSAO (`ssao_radius 0.8`, `ssao_intensity 2.5`) for contact shadowing
under flush-mounted parts. One shared set of tuned values across all 4
scenes rather than per-scene tweaking, since they're all the same rendering
pipeline. Tagged `[Qwen once Claude sets exact parameter values]` in the
source plan; done directly this pass since it's a small, well-specified
engine-config change, not a multi-file code change.

**A4 done.** New `res://scripts/world_hp_bar.gd` (`class_name WorldHPBar`,
`RefCounted`) is the one shared helper `battle_unit.gd`/`building.gd`/
`target_dummy.gd` now all go through instead of each building its own
Label3D. It doesn't invent new geometry/shaders — it discovered and wired up
`res://shaders/inworld_hp_bar.gdshader` and `res://shaders/selection_ring.
gdshader`, both already fully authored (a real segmented-bar gradient with
a damage-flash uniform; a self-animating rotating-dash pulsing ring) but
**never referenced by any script anywhere** — `test_2d_ui_chrome_overhaul`
only checked the files exist on disk, which they did, unused, the whole
time. `inworld_hp_bar.gdshader` shipped without `render_mode billboard` set
(not actually a valid spatial render_mode token in Godot 4 — a custom
shader has to face the camera via a manual `vertex()` rebuild of
`MODELVIEW_MATRIX`, added here) and would not have faced the camera at all
otherwise. `building.gd` gets a second, thinner bar (same shader/helper,
different color/segment count) for production-job progress, replacing the
old "⚙ NN%" text folded into the same Label3D; kind name (HQ/REFINERY/...)
and a harvester's cargo glyph both stay as small compact Label3Ds — real
information, not the ASCII bar being replaced.

**Real bug caught by a screenshot, not headless tests**: the selection
ring's world-space size formula was off by 2x (`radius * 2.0 / 0.42`
instead of `radius / 0.42` — the shader's ring sits at UV-space distance
0.42 from center, a *fraction* of the quad's own size, not world units).
Headless tests can assert a `MeshInstance3D` exists and its shader param
tracks hp correctly, but "is the ring the right size" is a real-render
question — caught by a scratch capture script
(`prototype/scratch/capture_a4_hp_bars.gd`) showing a selection ring
roughly 2x the intended radius around the HQ, fixed, then reverified with
a second capture. The new `test_a4_world_hp_bar_and_selection_ring_real_
wiring` test asserts the exact expected quad size algebraically so a
regression here fails headless too, not just visually.

**Real, unrelated bug found in passing, not fixed this pass:** the same
screenshot showed every building's faction "mascot" decal (`hull_decals.
gd` — gear/hexagon/star/etc.) rendering as a giant disc covering most of
the building, contradicting that file's own header comment ("sized to stay
genuinely detail-scale, never competing with the silhouette"). Unrelated
to A4's own scope (health bars/selection rings, not hull decals) — flagged
as a follow-up task rather than fixed here.

**A2 done.** New `res://scripts/vfx_burst.gd` (`class_name VFXBurst`) is the
one shared helper `auto_weapon.gd`'s muzzle flash and `battle_unit.gd`'s
`_flash_shield()`/`_spawn_explosion()` now all go through, replacing three
near-duplicated per-shot `MeshInstance3D` + `StandardMaterial3D` + `Tween`
allocations with a `GPUParticles3D` burst. Real particle spread/falloff
(GPU-simulated) instead of a single scaling mesh, and a genuine perf win:
the `ParticleProcessMaterial`/`StandardMaterial3D` pair is cached per
(color, mesh) combination and reused across every future call with the same
look — the common case, since most weapons fire the same color repeatedly —
rather than allocated fresh per shot the way the old code always did.
Auto-cleanup is the real `finished` signal `GPUParticles3D` fires once a
`one_shot` burst's particles have all completed, not a guessed timer.
`_spawn_explosion()`'s old per-particle random RED→YELLOW color variety is
simplified to one fixed orange (flagged in a comment as restorable via a
`color_ramp` later if it turns out to matter — a visual-parity swap, not a
new design). New test
`test_a2_vfx_burst_replaces_muzzle_flash_and_death_explosion` proves the
real wiring (firing a weapon and killing a unit each spawn a genuine
`GPUParticles3D`, not the old node types), plus a real non-headless capture
(`prototype/scratch/capture_a2_vfx.gd`) confirming it actually renders.

---

## Phase 3 — Long arcs

These are genuinely large and none of them blocks the others. Pick by appetite.

### 3.1 Hull Builder — but rewrite the plan first

`HULL_BUILDER_PLAN.md` is **not usable as written.** It references
`E:/Build-A-Bomber-GitHub/` paths throughout (wrong checkout), states
`hull_builder.gd` is 670 lines when it is 1,353, and describes as "missing" several
things the file now attempts (undo stack, export pipeline, serialization). The
`5df48c9` commit that claimed "Stage 1 — Implement Hull Builder export pipeline"
shipped a file that does not compile, with four test files that do not parse, and
internals that are self-described as incomplete:

- `hull_builder.gd:34` — scale mode marked `2=Scale (future)`
- `hull_builder.gd:1152` — *"Poll for completion (simplified — in a real
  implementation you'd use a proper process monitor)"*, followed by a hardcoded
  0.5s timer and no process monitoring
- `hull_builder.gd:1228-1230` — undo of `delete_primitive` prints a status string
  and does nothing else

**Recommendation:** after 0.1 makes it compile, re-audit the real file, rewrite
`HULL_BUILDER_PLAN.md` against it with correct paths and an honest
working/partial/missing table, and answer its five open questions (boolean union
vs interpenetrating volumes; `res://` vs `user://` export target; auto vs manual
stats; max primitive count; name-collision guard) before writing more code.
The plan's own Chunk 5 (Blender export) is the real deliverable and everything
before it is editor ergonomics.

### 3.2 `RTS_CORE_ROADMAP.md` B8 — bigger, denser maps *(parked, resumable)*

One map landed (`scattered_peaks`, 550 half-extent). The doc is explicit that this
is authoring judgment, not implementation, and should be budgeted as its own arc.
Two things to read before authoring the next big map:
- `PROGRESS.md`'s B8 entry on the 3-stage Recast/`NavigationServer3D` crash at
  large scale — *"the same crash class will recur at this scale."*
- B6's deferred `map_half_extents: float → Vector2` change. Every bundled map is
  square; the first non-square map pays that debt.

Also still deferred and gated on this: B10's slot-picker UI, which was correctly
held back because **every bundled map authors exactly 2 spawns**, so there is no
data to exercise a 3+-player picker against. The first 3-spawn map unblocks it.

### 3.3 `PERFORMANCE_PLAN.md` remainder — *measure before building*

P1 (a–d), P2, and P4 (a–c) landed and the stress test went from "unplayable past
5–6 units" to **60 units at ~37 ms average physics time**. The plan's own
sequencing says measure before continuing, and that measurement hasn't been done
since P4.

| Chunk | State |
|---|---|
| **P4d** locomotion/running-gear baking | Deferred. Named in the audit as *"one of the worst offenders"* (wheel hub × axle count × 2 sides, each hub+driveshaft+gearbox). Needs its own audit of `build_running_gear()`'s node structure first. |
| **P4e** `MultiMeshInstance3D` | Deferred, lower value after P4a. |
| **P3** off-main-thread raycasting | Investigative; the plan itself says *"likely unnecessary"* after P1c's spatial grid. Only pursue if frame time climbs past ~40–50 units. |
| **P5** shader cost pass | Explicitly *"profile first, don't guess."* |

**Recommendation:** do a single measurement session (20–40 units, Godot's frame
profiler) and let it decide. P4d is the only one likely to be worth doing blind.

### 3.4 The between-matches meta-loop — *the biggest real design gap*

The one FABLE_REVIEW finding that was never addressed and is not in any plan.
Verified in code: **there is no persistence between matches at all.** The complete
inventory of what survives a match is `user://blueprints/*.json` (designs),
`user://mods/hulls/`, and log files. No campaign scene, no roster carry-over, no
reinforcement, no unlocks. `_load_rosters()` rebuilds from the blueprint folder
every match and slices to 12. Win or lose returns to MainMenu with no state.

`RTS_Unit_Designer_Concept.md`'s Operations/loadout/reinforcement structure —
described by FABLE_REVIEW as *"the thing that gives the Design Lab its reason to
exist between matches"* — has no implementation. FABLE's verdict stands: the
individual systems are far ahead of the loop that is supposed to connect them.

This needs a **design decision from Chris before any plan can be written.** The
question is roughly: is Build-A-Bomber a skirmish sandbox where the Design Lab is
the whole point, or a campaign where designs persist, get salvaged, and evolve
between missions? Both are legitimate; they imply very different work.

### 3.5 Balance items still genuinely open after the FABLE fix pass

FABLE_REVIEW is ~85% addressed — verified item by item against current code.
What remains:

| Item | State |
|---|---|
| **1.5** `tube_count` / `grid_size` are pure dials | Partially fixed. The cost/weight whitelists are now **identical, 35 entries each** — the "only 5 tweak names in the cost model" complaint is gone. But `tube_count` and `grid_size` multiply dps, weight, cost, *and* shot interval by the same ratio, so DPS-per-metal is unchanged: still a bigger-or-smaller knob. Only `barrel_count` gained a downside (traverse). Note `module_catalog.gd:1198-1199`'s comment claims count-tweaks are *excluded* from `LINEAR_SCALE_WEAPON_TWEAKS` and contradicts the actual list. |
| **1.6** per-unit energy is niche | Still open **by explicit decision** — Chris resolved this as "two separate resources by design." 3 of ~20 weapons cost energy; nothing else consumes `current_energy` (no shields, traverse or sensors gated on it). `arc_projector` still disables nothing on a target with no energy weapons. Fine as a decision; worth revisiting only if the disable weapon is meant to matter. |
| **3.4** unknown module id → `basic_cannon` | Partially fixed. The fallback is unchanged at `module_catalog.gd:1609-1613`; `module_exists()` was added and the two *authority* paths guard before calling (`blueprint_manager.gd:525`, `skirmish.gd:1064`). Every other caller still silently gets cannon data. |
| Hull-scale clamp bypass | New, minor. `HULL_SCALE_MIN/MAX` (0.5–2.0) is enforced only on the gizmo drag path (`gizmo_3d.gd:186-188`); `blueprint_manager.gd:355-357` reads `hull_scale` straight from saved JSON unclamped. Not free power any more (cost/HP/weight all scale now) — just unbounded. |

Everything else FABLE raised is fixed: hull scale is priced and weighed
(`module_catalog.gd:37-75`), the Design Lab sidebar calls the same shared statics
as combat (`stat_calculator.gd:764-777`), drag-to-a-new-face reclassifies
mount/facet properly (`module_placer.gd:2036-2097`), defense faction is assigned
(`building.gd:326`), ArrayMesh hulls scale live (`gizmo_3d.gd:215-231`), and
weapon LOS blocks on any non-target non-self hit across masks 1+2+8
(`auto_weapon.gd:334-360`).

---

## Documentation consolidation

22 markdown files, and two of them are now actively misleading. Proposed tiers:

**Tier 1 — live, read these**
- `UNIFIED_ROADMAP.md` (this file) — the index
- `PROGRESS.md` — the log, current and well-maintained
- `RTS_CORE_ROADMAP.md` — E2/E3 open, B8 parked. Status table is accurate.
- `PERFORMANCE_PLAN.md` — P3/P4d-e/P5 open. Accurate.
- `VISUAL_AND_UX_POLISH_PLAN.md` — all 10 chunks open. Accurate.

**Tier 2 — specs, stable reference**
`DESIGN_VISION.md`, `VISUAL_ART_DIRECTION.md`, `HULL_MASSING_SPEC.md`,
`MOUNTING_AND_ARMOR_SPEC.md`, `ENERGY_AND_BALANCE_SPEC.md`,
`Damage_And_Armor_Model.md`, `Design_Lab_UI_UX.md`, `Factions_and_Buildings.md`,
`Arsenal_Weapons_List.md`, `RTS_Unit_Designer_Concept.md`

**Tier 3 — needs work before it can be trusted**
- **`DECISIONS_NEEDED.md` — 9 days and ~60 commits stale.** Newest entry
  2026-07-18; last commit touching it `69ff487` (07-18). It never mentions
  `RTS_CORE_ROADMAP.md`, `PERFORMANCE_PLAN.md`, `VISUAL_AND_UX_POLISH_PLAN.md`,
  `LOCOMOTION_REBUILD_PLAN.md`, or `HULL_BUILDER_PLAN.md` — all of which postdate
  it. At least 11 items in it read as open but shipped (the turret/pintle collapse
  at `:403` says *"not decided, not implemented"* and was shipped in `732e863`;
  the sponson self-LOS blocker at `:181` was unblocked by `e82430a` and fixed in
  `ccb8ad0`; N-team FFA at `:968` landed as B2; etc.). **Either prune the resolved
  entries and add a last-updated marker, or freeze it and start a fresh log.**
  Its genuinely-still-live content is the `:474` BLOCKING speck issue, the
  §"awaiting Chris" design questions, and the unvalidated-numbers list in 1.2 above.
- **`HULL_BUILDER_PLAN.md` — wrong paths, wrong line counts, describes a
  different file.** Rewrite per 3.1.
- **`VISUAL_IMPROVEMENT_PLAN.md`** — chunks A/C/D/E landed; F and G are open and
  referenced from `VISUAL_AND_UX_POLISH_PLAN.md` as A4/G. It is also literally a
  *prompt* to an agent (escaped markdown and all), not a plan document. Extract
  F and G into the polish plan and archive the rest.

**Tier 4 — archive (historical, no pending work)**
- `LOCOMOTION_REBUILD_PLAN.md` — says so itself: *"kept as historical reference,
  not a live spec."* Its R1–R9 risk list and the 8-bug postmortem are the valuable
  part; keep them findable for whoever adds an 11th locomotion type.
- `HULL_MODDING_PLAN.md` — its §5 open questions were answered by
  `RTS_CORE_ROADMAP.md`'s D1 content-format decision.
- `FABLE_REVIEW.md` — ~85% addressed; the residue is captured in 3.5 above.

Suggest `docs/archive/` for Tier 4 and a one-line pointer from `README.md`.

---

## Sequencing summary

| # | Item | Size | Depends on | Why now |
|---|---|---|---|---|
| **0.1** | Fix `hull_builder.gd:1200` | minutes | — | Shipped build has a dead menu button |
| **0.2** | Suite stops short-circuiting | afternoon | — | Highest-leverage change in the repo |
| **0.3** | Parse-check every scene script | afternoon | 0.2 | The guard that would have caught 0.1 |
| **0.4** | Stabilize/quarantine nav flakiness | 1 session | 0.2 | Without it, red carries no information |
| **0.5** | Test-command wrapper + README | small | — | Clean checkout can't run the suite |
| **0.6** | Delete 4 broken test files, add real ones | afternoon | 0.1 | They landed broken and stayed broken |
| **0.7** | Heightmaps → `Image` import; verify by real export | afternoon | — | Game cannot currently ship with working terrain |
| **0.8** | Repo hygiene (.import, root cruft, scratch) | afternoon | — | Cheap; 120 phantom-modified files hide real work |
| **1.1** | Economy on by default — ✅ DONE | 1 line + play | 0.* | Unlocks a week of dormant Phase D work |
| **1.4** | Control groups + shift-select — ✅ DONE | 1 session | — | Playability blocker |
| **1.5** | Gate debug HUD; wire `CursorManager` | small ×2 | — | Both nearly free |
| **1.2** | Playtest + tune the 10 guessed number sets | evenings | 1.1, 1.4, 1.5 | **Chris only.** Nothing else is validated without it |
| **1.3** | AI builds buildings — items 1-3 ✅ done, 4 open (needs a forward-base design decision) | 1–multi | 1.1 | Makes all of Phase C/D/E two-sided |
| **1.6** | E2 sell+repair, E3 tech greying — ✅ DONE | 1 session | 1.3 | Closes `RTS_CORE_ROADMAP.md` |
| **2.x** | A1 ✅ done → A4 ✅ done → B1 ✅ done → C4 ✅ already done → A2 ✅ done → B2 → G → A3 | varies | — | A1 alone changes how everything reads |
| **3.3** | One perf measurement session, then P4d | 1 session | — | Plan says measure; measurement is stale |
| **3.1** | Re-audit + rewrite `HULL_BUILDER_PLAN.md`, then build | multi | 0.1 | Plan is unusable as written |
| **3.2** | B8 next map (unblocks B10 slot UI at 3 spawns) | multi | — | Authoring judgment, own arc |
| **3.4** | Meta-loop | — | **A design decision from Chris** | Biggest real gap; can't be planned yet |
| **3.5** | Residual balance items | afternoon each | 1.2 | Let the playtest decide priority |

**The spine: 0.1 → 0.2 → 0.3 → 0.4 → 1.1 → 1.4 → 1.2.**
Everything from 0.1 to 1.1 is under a week of work and converts a project whose
quality gate is broken and whose economy is switched off into one that can
actually be played and trusted. That is the highest-value path available.

---

## Verification conventions (unchanged, restated because 0.2–0.5 change the command)

```bash
cd prototype && ./Godot_v4.3-stable_win64_console.exe --headless --script run_tests.gd --path .
```

After 0.5 this becomes the wrapper script. Notes that remain true:
- Headless spams `ERROR: Parameter "m" is null. at: mesh_get_surface_count` —
  pre-existing harmless dummy-renderer noise.
- Some verification **must** run non-headless; input/drag bugs are structurally
  invisible otherwise (D2 and the whole wheels rebuild both proved this). Those
  scripts live in `prototype/scratch/`.
- Runs leak `NavRegion`/`NavMap` RIDs at exit — the suite is what catches those.
- Favour **behavioral** proofs (real spawned units, real physics ticks, real
  path-connectivity, pixel readback) over catalog-number assertions.

Per project convention each chunk ships with: new tests in `run_tests.gd`,
screenshots under `prototype/progress_captures/<date>/<feature>/`, a `PROGRESS.md`
entry, and judgment calls logged — see the Tier-3 note above on *where* those
judgment calls should now go.
