# Speed as a real, affectable stat (and the naval drives go)

> **Update 2026-08-09: Completed.** (All tasks in this plan have been fully implemented to satisfaction. This document is retained for historical context.)

## Context

Speed is currently the least interesting number a design has. Three things cause that:

1. **The band is narrow and low.** `base_top_speed` runs 4.0â€“18.0, but the ground types are
   bunched into 6.0â€“13.0 and everything mainline sits between 6.5 and 12.0. Two very different
   chassis feel the same on the field.
2. **Nothing a player bolts on makes a unit faster.** Weight, armour and modules only ever
   *cost* speed. There is no "go faster" decision anywhere in the Design Lab.
3. **Most of the speed system is dead in the live battle.** `Drivetrain.analyze()` is the shared
   source of truth, but the live runtime (`BattleUnitV2`) reads the wrong key out of it and never
   computes terrain speed at all â€” so overload penalties, underload bonuses, faction speed
   passives, and the entire 7-surface Ã— 10-locomotor terrain table have no effect in Skirmish.

Separately, the three pure-naval drives are dead weight in the roster: naval units and naval
building never got real design attention, so they carry balance cost, catalog surface and test
surface for a theatre the game does not play. They come out as part of this pass.

The outcome we want: a tighter roster of chassis that genuinely feel different, a family of parts
that buy speed at a real price, and a battle runtime where all of it actually shows up.

### What exists today (read before editing)

| Concern | Where |
|---|---|
| Single source of truth for weight/thrust/capacity/speed | `prototype/scripts/drivetrain.gd` â€” `analyze()` at :323 |
| Per-chassis ceilings, thrust coefficients, terrain table | `prototype/scripts/module_catalog.gd` â€” `base_top_speed` per entry, `get_base_top_speed()` :3087, `TERRAIN_SPEED_MULTIPLIERS` :3187 |
| Design Lab stat rail | `prototype/scripts/stat_calculator.gd` â€” `_update_drivetrain_readout()` :1449, `TWEAK_SPECS` :129 |
| Shared design analysis (Lab + roster cards) | `prototype/scripts/design_stats.gd` |
| Live battle unit | `prototype/scripts/battle/units/unit.gd` â€” `_recalculate_move_speed()` :300, `_apply_movement()` speed line :531 |
| Test Range / old runtime | `prototype/scripts/battle_unit.gd` â€” `_recalculate_move_speed()` :525, `_recalculate_terrain_speed_multiplier()` :587 |
| Locomotion station geometry | `prototype/scripts/locomotion_layout.gd`, `prototype/scripts/module_placer.gd` |
| Parts-bin grouping | `prototype/scripts/parts_menu.gd` â€” `_tier_for()` :394 |
| Tweak â†’ weight/cost scaling lists | `prototype/scripts/module_data.gd` â€” `get_weight()` :63, `get_cost()` |
| Procedural part geometry | `prototype/scripts/visual_builder.gd` |
| Authored meshes | `prototype/tools/blender/build_meshes.py` |

Two hooks already exist and are **currently dead**: `drivetrain.gd:401-406` reads
`weight_capacity_bonus` and `thrust_bonus` off any catalog entry, and no entry defines either.
The new parts use them rather than inventing a parallel path.

---

## 1. Remove the naval drives

Delete `naval_propeller`, `hydrofoil` and `water_jet`. Scope is **drives and blueprints only** â€”
the water navmeshes, hull draught and `is_naval` branches stay in place (unused but working),
because the amphibious drives (`screw_drive`, `pontoon_wheels`, `air_cushion_skirt`) still route
onto the combined navmesh and keep their water-crossing niche. Those three are ground/hover units
first and are unaffected.

Call sites, by file:

| File | What goes |
|---|---|
| `module_catalog.gd` | the three catalog entries, their `TERRAIN_EXEMPT_TRAITS` prose, `LOCOMOTION_TWEAK_SPECS` entries |
| `drivetrain.gd` | their `TWEAK_RESPONSE` rows (:205-217 naval_propeller, :254-263 hydrofoil/water_jet) |
| `locomotion_layout.gd`, `module_placer.gd` | station layouts |
| `visual_builder.gd` | `_build_naval_propeller` / `_build_hydrofoil` / `_build_water_jet` and their `LOCOMOTION_MODULAR_TYPES` + `_attach_moving_parts` entries |
| `stat_calculator.gd` | `TWEAK_SPECS` entries and tweak-label plumbing |
| `battle_unit.gd` | naval-specific movement references |
| `data/loadout/tide_corvette.json`, `data/enemy/tide_corvette.json` | deleted; remove from any roster/wave manifest that names them |
| `tests/` | `test_locomotion.gd` (13 refs), `test_sim_and_stats.gd`, `test_ai_and_win.gd` |

**Golden fixture:** `tests/suite_base.gd:145/157/169` carries frozen `naval_propeller` station
data. Per CLAUDE.md this must be updated **in its own commit** with an explanation â€” do the
fixture edit as a standalone commit ("naval drives removed, so their frozen stations go with
them") rather than folding it into the tuning commit.

`buoyant_envelope` (AGP Loiter Drive) carries a `buoyant` trait but is **airborne** â€” it stays.

---

## 2. Light tuning

**`prototype/scripts/drivetrain.gd`**

- `TW_GAIN` 10.0 â†’ **11.0**. Lifts every power-limited design ~10% and pushes more designs up
  against their chassis ceiling, which is what makes step 3 below legible. Update the constant's
  comment with the reason.

**`prototype/scripts/module_catalog.gd`** â€” retune `base_top_speed` on each surviving locomotion
entry. Every value rises; the fast end rises more, so the spread widens and the ground band goes
from 6.0â€“13.0 to 6.5â€“16.0.

| Locomotor | old | new |
|---|---|---|
| buoyant_envelope | 4.0 | 4.5 |
| rocker_bogie | 6.0 | 6.5 |
| legs | 6.5 | 7.0 |
| screw_drive | 6.5 | 8.0 |
| pontoon_wheels | 7.5 | 8.5 |
| tracked_treads | 8.0 | 9.0 |
| half_track | 8.5 | 10.0 |
| ornithopter_wing | 9.0 | 10.5 |
| anti_grav_plate | 10.5 | 12.0 |
| helicopter_rotors | 11.0 | 13.0 |
| wheels | 12.0 | 15.0 |
| air_cushion_skirt | 12.5 | 15.0 |
| hover_engine | 13.0 | 16.0 |
| fixed_wing_engine | 18.0 | 22.0 |

`BASE_TOP_SPEED_DEFAULT` stays 18.0. Each entry's existing reasoning comment gets a line noting
the retune, in the style already used on `screw_drive` and `rocker_bogie`.

Ordering constraints asserted by `test_sim_and_stats.gd:782-791` (fixed_wing > wheels >
tracked_treads > legs, buoyant < legs) all hold. `screw_drive` is raised more than its
neighbours to preserve the wheels/screw ice ratio that
`test_terrain_types_differentiate_locomotion` depends on.

**Watch item:** faster units turn wider. `unit.gd` derives `slow_radius` from
`move_speed / TURN_RATE` (TURN_RATE = 2.6). At 22 m/s the radius is ~8.5 m. If fixed-wing designs
start orbiting their destination in playtest, raise `TURN_RATE` â€” do not shrink `slow_radius`,
per the comment at `unit.gd:519-528`.

---

## 3. Fix the live battle runtime

Without this, nothing above or below is visible in Skirmish.

**`prototype/scripts/battle/units/unit.gd`**

- `_recalculate_move_speed()` :304 â€” read `dt["move_speed"]`, not `dt["top_speed"]`. `move_speed`
  is combat speed (overload/underload multipliers + faction passives applied); `top_speed` is the
  clean design figure. `battle_unit.gd:553` already reads the right one.
- Add `_recalculate_terrain_speed_multiplier()`, ported from `battle_unit.gd:587-621` â€” the
  controller-side dependency already exists (`match_director.gd:390 get_surface_type_at()`), and
  it is duck-typed so tests with no controller fall through to 1.0. Call it from
  `_physics_process()` alongside `_tick_power()`. This turns on the tread-width modifier and the
  Glacier Syndicate passive in the live battle too.

Both fixes are a handful of lines; the value is that they make the whole existing speed system
real in the mode people actually play.

---

## 4. Propulsion parts â€” passive

New catalog keys read by `Drivetrain.analyze()`, extending the loop at `drivetrain.gd:396-406`:

| Key | Effect |
|---|---|
| `thrust_bonus` | already read (dead today) â€” adds flat thrust |
| `weight_capacity_bonus` | already read (dead today) â€” adds flat capacity |
| `top_speed_mult` | **new** â€” multiplies `chassis_top_speed` before the `min()` at :434 |
| `capacity_mult` | **new** â€” multiplies total capacity before `load_ratio` is derived |

`top_speed_mult` is the load-bearing addition: thrust alone does nothing to a design already
sitting on its chassis ceiling, which is most of the roster after step 2. Raising the ceiling is
the only way a "go faster" part can help a light scout.

Bonuses scale by the module's own tweak-driven mass â€” `data.get_weight() / data.base_weight` â€”
so a bigger turbo makes more thrust *and* weighs more, with no new scaling table. Product of all
`top_speed_mult` values, clamped by a new documented `MAX_CHASSIS_SPEED_MULT` (1.6) so stacking
six gearboxes is not the answer to everything.

`analyze()` returns two new keys for the Lab: `chassis_speed_mult` and a `boost` summary dict.

### The parts

All are `category: "module"` with a new `role: "Propulsion"`, so they need **no new category
plumbing** (the placer, legality gate and stat code treat them as ordinary modules â€” a hull
carrying only a turbo is correctly still an illegal build). Add `"Propulsion"` to
`MODULE_ROLE_ORDER` before `"Power"`, and route it to the existing **Drives** toolbox with a
one-line `DRIVE_ROLES` check in `parts_menu.gd:394 _tier_for()`.

Every tweak name below is **reused** from `module_data.gd`'s existing scaling lists, so weight
and cost scaling work with no new plumbing â€” the convention `stat_calculator.gd:216` documents.

| id | Name | Effect | Cost of it | Tweaks |
|---|---|---|---|---|
| `turbocharger` | Turbocharger | `thrust_bonus: 90` | Weight. Does nothing once you're at the ceiling â€” the Lab already says so via `capacity_limited` | `turbine_compression`, `intake_size` |
| `overdrive_gearbox` | Overdrive Gearbox | `top_speed_mult: 1.18` | `capacity_mult: 0.85` â€” tall gearing, less pulling force. The pure trade | `motor_size` |
| `hub_motor_array` | Electric Hub Motors | `thrust_bonus: 70`, `top_speed_mult: 1.08` | `POWER_DRAW` entry of 5.0/s, shed on brownout â€” ties speed to the power budget that already exists | `motor_size`, `coil_count` |

---

## 5. Propulsion parts â€” burst

A new `boost` block on a catalog entry:

```gdscript
"boost": {"speed_mult": 1.45, "duration": 5.0, "cooldown": 14.0,
          "energy_per_sec": 6.0, "charges": 0}   # charges 0 = unlimited
```

| id | Name | Boost | Tweaks |
|---|---|---|---|
| `nitrous_injector` | Coolant Injection | Ã—1.45 for 5 s, 14 s cooldown, drains energy while lit | `drum_size` (bottle), `pressure_valve` |
| `booster_rack` | Solid-Fuel Booster Rack | Ã—2.2 for 2.5 s, **3 charges, no recharge** â€” heavy, absurd, finite. The wild card | `nozzle_count`, `motor_length` |

**New file: `prototype/scripts/battle/units/boost_controller.gd`** (RefCounted, one per unit,
same shape as `economy/harvester_fsm.gd` â€” the reason it is not inlined into `unit.gd` is the one
that file's own header gives). Owns charges, cooldown, remaining duration, and the auto-engage
rule. Both runtimes instantiate it; neither duplicates the rule.

Auto-engage (no new input plumbing, no micro â€” per the decision to keep this automatic):

- unit has a destination and remaining distance > `MIN_RUN_DISTANCE` (25 m), **and**
- heading throttle is high â€” do not light a booster mid-turn, **and**
- no live enemy inside `attack_range`, **and**
- for energy-fed boosts: buffer above the brownout threshold.

Disengages on arrival, on contact, on duration expiry, or on brownout.

**Applied in `unit.gd:531`** (and the matching line in `battle_unit.gd:1349`), multiplying the
final steering speed alongside `terrain_speed_multiplier`. Deliberately **not** folded into
`Drivetrain.analyze()` â€” that is the design-time analysis, and a burst that inflated the quoted
top speed would make the Lab's number a lie. The Lab shows it as its own row instead.

Feedback: a `VFXBurst` exhaust plume while a boost is live (`scripts/vfx_burst.gd`), so a
boosting unit reads at RTS camera distance.

---

## 6. Design Lab readout

`stat_calculator.gd:1449 _update_drivetrain_readout()` gains:

- the chassis-ceiling line reports the *modified* ceiling when `chassis_speed_mult != 1.0`, so an
  Overdrive Gearbox is visible in the number it changes;
- a Boost row when the design carries a boost part: `Boost: x2.2 for 2.5s (3 charges)`.

`design_stats.gd` passes the two new drivetrain keys through, so roster cards and
`fleet_comparison_panel.gd` get them for free. `TWEAK_SPECS` in `stat_calculator.gd:129` gains an
entry per new part.

---

## 7. Art â€” authored meshes

`visual_builder.gd` falls through to its generic module box for unknown ids, so the parts are
placeable and testable immediately. Authored geometry is the finishing pass, done in Blender:

```bash
cd prototype && "C:/Users/Chris/Downloads/UPBGE-0.30-windows-x86_64/blender.exe" --background --python tools/blender/build_meshes.py
```

then reimport:

```bash
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import
```

**The rule each part must follow: the detail being tweaked is the detail that visually scales.**
Not the whole module. That means authoring each part as separate pieces in
`assets/models/parts/`, the same way `recoilless_breech` and `recoilless_tube` are two files, and
having `visual_builder.gd` scale only the piece the tweak names:

| Part | Tweak | What thickens/grows on screen |
|---|---|---|
| `turbocharger` | `turbine_compression` | the compressor housing snail, not the plumbing |
| | `intake_size` | the intake trunk diameter alone |
| `overdrive_gearbox` | `motor_size` | the gearcase bell and output shaft |
| `hub_motor_array` | `motor_size` | the hub can diameter |
| | `coil_count` | number of stator segments instanced around the hub |
| `nitrous_injector` | `drum_size` | bottle length/diameter |
| | `pressure_valve` | the feed line thickens and the regulator body grows |
| `booster_rack` | `nozzle_count` | tubes instanced N times across the rack |
| | `motor_length` | tube length only, rack frame unchanged |

---

## Verification

```bash
cd prototype && ./run_tests.ps1
```

New suites in `tests/test_locomotion.gd`, each registered in `SUITE_ORDER` in `run_tests.gd`
(append at the end â€” the order is pinned, do not reorder existing entries):

1. `test_chassis_top_speeds_are_spread_and_ordered` â€” the retuned band: every value rose, the
   archetype ordering holds, and the fastest/slowest ratio widened.
2. `test_propulsion_modules_change_drivetrain_output` â€” a turbo raises thrust, a gearbox raises
   the ceiling and lowers capacity, and `MAX_CHASSIS_SPEED_MULT` caps a stack of six.
3. `test_boost_controller_engages_and_expires` â€” engages on a long run, refuses mid-turn and near
   an enemy, burns charges, respects cooldown.
4. `test_live_runtime_uses_combat_speed_and_terrain` â€” a `BattleUnitV2` built overloaded moves
   slower than its `top_speed`, and the same unit covers measurably less ground on `snow_mud`
   than on `gravel`. This is the regression guard for Â§3 and the one that would have caught the
   original defect.

Existing suites to watch: `test_terrain_types_differentiate_locomotion`,
`test_locomotor_base_top_speed_is_a_real_per_type_ceiling`, the overload/underload suites in
`test_sim_and_stats.gd`, and every suite that named a naval drive (Â§1).

Then in the game:

```bash
cd prototype && ./Godot_v4.7.1-stable_win64.exe
```

- **Design Lab** â€” the Drives bin no longer lists the three naval types, and Propulsion appears
  as a fourth drawer. Build a wheeled scout, confirm the quoted top speed rose. Add an Overdrive
  Gearbox: ceiling up, load percentage up. Add a Turbocharger to an overloaded hauler: speed up.
  Add a Booster Rack: the Boost row appears. Drag each new part's tweaks and confirm only the
  named detail changes size.
- **Test Range** â€” drive the scout; it should feel quicker, and the booster should visibly fire
  on a long straight run.
- **Skirmish** â€” send a mixed group across a map with surface zones. Post-Â§3, wheeled units
  should visibly bog in snow_mud and pull ahead on gravel, which they do not do today.

### Commit shape

1. Naval drives removed (code, blueprints, tests).
2. `suite_base.gd` golden fixture updated â€” **its own commit**, per CLAUDE.md.
3. Speed tuning (`TW_GAIN`, `base_top_speed` band).
4. Live-runtime speed fixes + regression suite.
5. Propulsion parts (catalog, drivetrain keys, Lab readout, boost controller).
6. Authored Blender meshes for the new parts.
