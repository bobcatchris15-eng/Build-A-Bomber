# Operations — Phase 5 Plan

Completing the battle-layer rebuild. Written 2026-08-06.

## Where this sits

The rebuilt battle layer (`prototype/scripts/battle/`) is Phases 0–4 complete
plus the AI. The remaining phase is **Operations**: the meta-game that turns one
match into a campaign.

Chris's framing, which changes the shape of this from the original plan:

> The battle mode should really just be three to ten instances of the skirmish
> with the roster changes between.
>
> My intent was for this to be replacing the existing skirmish mode, and then
> that leaves the battle / operations a pretty small tack-on.

So **Battle replaces Skirmish**, and Operations is a loop around it — not a
separate mode, and not a wrapper around the legacy runtime. That makes Phase 5
genuinely small, but it moves the weight onto the retirement it depends on.

---

## What is already done

Landed and verified this session, so the plan does not re-plan them:

- **Roster selection** honours `MatchConfig`: hand-picked designs, else the
  player's newest *named* saved designs, else bundled defaults as filler, capped
  at 12, with a harvester guaranteed. Factions and starting resources too.
- **Starting force** is one harvester per side plus HQ, refinery and all three
  manufactories — parity with the mode this replaces.
- **Shared default pool** (`data/loadout/`, 16 designs) including five authored
  here: Warden AA, Breaker TD, Sentinel SAM Turret, Bastion Gun Turret, Rampart
  Bunker.
- **Defences are buildable**, not decorative: `Structure.setup_from_blueprint()`
  reconstructs a foundation design and arms it through the same
  `attach_weapons()` the unit path uses.

---

## The real prerequisite: retirement

Operations is small *only if* it wraps one runtime. Today there are two, and they
are separate implementations — which this session proved the hard way: harvesters
were fixed in the rebuild while the identical bug sat untouched in the legacy
runtime Chris was actually playing, because the legacy delivery radius was a flat
4.5 m that a 5.5 m hull could not physically reach.

**Retire the legacy runtime before building Operations, not after.** Writing a
campaign against two runtimes means every Operations feature gets built twice, or
gets built against the one that is about to be deleted.

Retirement is gated on parity. What is still missing:

| Gap | Why it blocks |
|---|---|
| **Player ghost placement** | A player-queued structure completes and parks its line forever — `_on_structure_ready` deliberately leaves player jobs unclaimed because the placement UI does not exist. The AI has a siting path; the player has nothing. |
| **Build bar → roster** | `production_hud` needs to offer the 12 roster designs, which is what makes roster selection mean anything. |
| **Squads never observed fighting** | Wired and unit-tested; never watched through an engagement. |
| **AI economy stalls** | See below — the opponent currently never fields a combat unit. |

Then one commit: delete `skirmish.gd`, `enemy_ai.gd`, `production_queue.gd`,
`building.gd`, repoint the SKIRMISH menu entry at `Battle.tscn`, and retire the
59 superseded suites — naming in the commit message which balance decisions moved
where, so the OpenRA benchmarking is not silently lost.

### Known defect to fix first

The AI reaches three harvesters and then sits at 0 metal doing nothing,
never fielding a combat unit. Measured over 7200 ticks. Income *is* arriving
(harvesters deliver; metal ticks 0 → 47 → 0), so the money is being consumed as
fast as it lands. Two changes made this session did not fix it — a queue-depth
self-throttle (`AI_MAX_QUEUE_DEPTH`) and scaling the harvester target to dock
bays (`HARVESTERS_PER_REFINERY`) — which means the cause is **not** yet
identified and the next step is to instrument the production queue directly
rather than tune further. An opponent that never attacks makes Operations
pointless, so this is a blocker, not polish.

---

## Phase 5 proper

Small, once the above is done.

### 1. Persistence

Nothing currently survives quitting except blueprints. Campaign state needs a
home.

**Use JSON to `user://`, not `.tres` Resources.** The research pass proposed
nested `Resource` + `ResourceSaver` with `FLAG_BUNDLE_RESOURCES`; that solves a
problem this codebase does not have. Blueprints are already JSON at schema v2.0
with a deliberate scratch-vs-saved split, and `data/loadout/` and `data/enemy/`
are load-bearing JSON. One serialisation format.

`user://operations/<id>.json`, holding: itinerary, current round, per-round
result, the player's drafted roster, and the combat log below.

### 2. The loop

`operations_manager.gd` already has the itinerary and `record_stage_result()` /
`advance_to_next_stage()` — and all three of those have **zero call sites**
outside the file. The work is wiring, not writing:

- Register it as an autoload (it is currently instantiated into `/root` by
  `operations_setup.gd`, which is why nothing else can reach it).
- On match end, `match_ended` → `record_stage_result()` → after-action report →
  draft screen → `advance_to_next_stage()` → next match.
- Wire `after_action_report.gd`. It is fully written and completely orphaned,
  and its `is_operation` flag is already the seam this needs.

### 3. Drafting

`roster_picker.gd` is 573 lines of working 12-slot drag-and-drop, currently used
only pre-match. Between rounds it becomes the draft screen. The one addition is
showing what the opponent fielded last round, because that is what makes
re-drafting a decision rather than a chore.

### 4. Counter-drafting

Record what each side actually fielded per round into the combat log. At draft
time the AI reads it and biases its roster.

The scoring already exists: `Commander.design_fills_role()` reads roles off a
design's mounted modules, so it can classify designs it has never seen —
including ones the player built. Counter-drafting is `enemy_roster` selection by
the same considerations, not new AI.

Keep the handicap honest: a difficulty-scaled income trickle is the only
concession, as now. The AI must keep reading the same services the player's HUD
does.

---

## Verification

Per the standing rule: new suites in `tests/battle/`, registered in
`SUITE_ORDER`, pure functions tested directly.

- Round-trip a campaign through save/load and assert the roster and log survive.
- Assert `advance_to_next_stage()` is actually reached from a match ending —
  the current failure mode is silence, not an error.
- Assert counter-drafting responds: feed a log of all-air and assert the AI's
  drafted roster gains anti-air.

```bash
cd prototype && ./run_tests.ps1
```

Baseline is **12 pre-existing failures** (mesh, navmesh and Design Lab suites
that arrived with the Mark II / support-module commits). Anything above that is
new.

And then the gate no test answers — play three rounds end to end:

```bash
cd prototype && ./Godot_v4.7.1-stable_win64.exe
```

---

## Order of work

1. Fix the AI economy stall (blocker — instrument the queue, do not tune).
2. Player ghost placement + build bar wired to the roster.
3. Play a full match. Watch squads fight.
4. Retirement commit.
5. Persistence → loop → drafting → counter-drafting.

Steps 1–4 are the bulk. Step 5 is the "small tack-on".
