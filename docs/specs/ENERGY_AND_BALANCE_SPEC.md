# Energy & Balance Spec

Written 2026-07-12, alongside the implementation it describes. Covers: the Energy resource, the repair-array/drone-carrier fixes, the build-legality gate, the new Energy-tied combat mechanics, and the balance/cost-model approach. Read this before touching any of the systems it names — it's the reasoning, not just the changelog (PROGRESS.md has the changelog).

## 1. Why Energy needs two layers, not one

The existing docs describe Energy two different ways that don't collapse into a single mechanic without a decision:

- `Factions_and_Buildings.md`: *"Assuming a 3-Resource Economy: e.g., Metal, Crystal, and Energy"* and *"static buildings... do not drain from the global Energy resource pool"* — this reads as a **team-wide banked resource**, parallel to Metal/Crystal, that buildings continuously consume.
- Chris's direct instruction this pass: *"a hull has a base energy pool, and generator modules increase max energy above that base"* — this reads as a **per-unit capacity stat**, parallel to HP, that's a placeable-module design choice on an individual vehicle.

Both are real and both are buildable without contradicting each other, because they operate at different scopes:

**Per-unit Energy pool** (the primary mechanic, and the one with actual combat teeth):
- Every hull/foundation catalog entry gets a new `base_energy` stat.
- A new module category, `"generator"` ("gennies"), adds to `max_energy` when mounted — exactly parallel to how armor modules add to a facet's threshold rather than being a fixed hull-level number.
- `current_energy` regenerates over time, is spent by firing energy-classed weapons, and can be drained by enemy energy-drain weapons (see §4) or boosted by a nearby logistics module's sharing aura (see §5).
- This is what makes Energy "a real placeable-module design choice, not just a number" — you can build a glass-cannon energy platform (big gennies, sustain-fire) or a unit that can only alpha-strike once before its capacitor is dry.

**Team-level Energy economy** (the HUD-visible third resource):
- `economy[team].energy` (current) and `economy[team].energy_capacity` (generated) join `metal`/`crystal` in the resource dict and HUD line.
- `energy_capacity` is a **live, recomputed figure** — the sum of every generator module currently mounted on that team's active units and buildings — not a one-time grant. Losing a generator-equipped unit measurably shrinks your team's energy capacity.
- Static buildings/foundations drain a fixed per-building upkeep from the team pool every tick, simply for existing (this is what makes the Expansionists passive — *their* static buildings don't drain — meaningful for the first time).
- **Deliberate scope decision:** Energy is NOT a spendable currency for buying units/buildings (no `cost_energy` field, `can_afford`/`spend`/`blueprint_cost` keep their existing 2-resource signatures). Making it a third spendable currency would mean widening every cost-related call site across `skirmish.gd`, `blueprint_manager.gd`, and every roster/UI cost string — a much larger, more invasive refactor for a feature Chris didn't actually ask for (he asked for the pool/generator mechanic, not an energy price tag on every unit). Instead, when a team's Energy pool is in deficit (upkeep draining faster than generator capacity replenishes), that team's factories build **50% slower** — a real, felt consequence without the invasive refactor. Logged as a judgment call, not hidden.

**Naming collision, flagged explicitly:** the armor system already has an "Energy" damage-type threshold (`K:`/`T:`/`E:` in the Design Lab sidebar, `energy_shielding` armor material) that is completely unrelated to this resource — and, discovered during research, was previously *dead*: nothing in `auto_weapon.gd` ever set `damage_class = "energy"`, so that threshold row was cosmetic-only. This pass gives it real meaning (see §4 — energy-drain and the new Tesla/arc weapons deal `"energy"` damage_class), which is a nice side benefit, but the two concepts — **Energy (the resource pool)** and **energy-type damage (an armor threshold category)** — must stay clearly distinguished in code comments and UI copy. Referred to throughout as "the Energy pool/resource" vs. "energy damage" respectively.

## 2. Technocrats' vision passive — explicitly NOT addressed this pass

Confirmed via research: there is no fog-of-war, no vision-radius, no sight-range concept anywhere in the codebase. "+15% sensor/radar vision, pushing back the fog of war" requires building that entire subsystem from scratch — full-map visibility today has no gate on it at all, so there's nothing to push back. This is unrelated to Energy and is not touched in this pass. Logged in DECISIONS_NEEDED.md as its own gap, per Chris's explicit instruction not to assume Energy work fixes it.

## 3. Repair Array & Drone Carrier — what "real" means for each

**Repair Array:** currently calls `target.take_damage(...)` on whatever `_find_nearest_target()` returns, and since it only ever returns *hostiles* (team-mode targeting unconditionally skips same-team candidates) and its catalog `dps` is `0.0`, it is a beam that cosmetically welds an enemy for zero effect. Real fix needs two independent pieces: (a) an ally-targeting mode in `auto_weapon.gd` (new bool flag, e.g. `targets_allies`, set from a catalog field, that inverts the team filter and adds an HP-deficit filter), and (b) a real heal call (`repair_target(amount)`, duck-typed like `take_damage`) instead of `take_damage`.

**Drone Carrier:** currently spawns two throwaway `MeshInstance3D` prisms, tweens them to an orbit point and back, and applies damage in the tween's `finished` callback — there is no persistent drone entity, no independent physics, no AI. `incoming_missile.gd` is the right template (a standalone `Node3D` with its own `_physics_process`, homing/state logic, group self-registration, `queue_free()` lifecycle) — a real drone gets its own script, spawns as an actual scene node with a target and a return-to-carrier state machine, and can be shot down by point-defense like a missile can (reusing the existing "shootable projectile" pattern rather than inventing a new one). Also needs the two missing `TWEAK_SPECS` entries the doc already promises (Hangar Size → drone count, Launch Catapult → launch cooldown) which currently don't exist anywhere in code.

## 4. New Energy-tied combat mechanics

- **Energy-drain weapons**: deal `damage_class = "energy"`. On hit, instead of (or alongside, tweak-dependent) HP damage, call `drain_energy(amount)` on the target (duck-typed, mirrors `take_damage`), which subtracts from `current_energy` (clamped to 0, never goes negative, never restores HP). A target at 0 energy simply can't fire its own energy-classed weapons until it regens or gets a logistics boost — a real soft-disable, not a damage multiplier reskin.
- **Silly weapons embraced per Chris's go-ahead**: a Tesla Coil (chain-arcs between nearby enemies, `energy` damage_class) and an Arc Projector (short-range continuous energy-drain beam) round out the energy weapon family alongside a more grounded "Ion Cannon" (long-range single-target energy-drain/damage hybrid). These are fun-forward, not hyper-realistic, matching the explicit invitation.
- **Logistics sharing aura**: `logistics_tank` (previously a pure stat-bearing module with a `tank_capacity` tweak that did nothing functionally) gains real behavior — each tick, it finds friendly units within a radius and boosts their energy regen rate for that tick, scaled by the logistics module's own size/tank_capacity. This is the "not just self-sufficiency" support mechanic Chris asked for: it does nothing for the unit carrying it beyond existing capacity, its value is entirely in what it gives nearby allies.

## 5. Build-legality gate

A design is illegal (blocked from queue/build in a match) if:
- No hull/foundation present at all, OR
- Zero weapon-category modules AND zero recognized support/utility modules (repair_array, drone_carrier, resource_harvester, sensor_suite, logistics_tank, any generator) — i.e., it does *nothing*, not even a legitimate non-combat role, OR
- No locomotion AND the hull is not a foundation (`ModuleCatalog.is_foundation()`) — i.e., it's a mobile-hull-shaped brick that can never move because the player forgot legs, not a deliberately static structure.

Checked at the same point `blueprint_cost()` already walks `modules[]` (natural reuse of that iteration), surfaced via the existing `_flash_status()` toast in Skirmish and the existing sidebar-Title-swap idiom in the Design Lab (both patterns already established for the pre-existing clipping-check gate — this follows the same shape, not a new UI pattern).

## 6. Balance / cost-model approach

Chris asked for a defensible cost-per-stat-point model, not just a mechanical-correctness check, and to flag where it's shaky. The approach: a headless scoring tool (`prototype/scratch`-adjacent but kept as a permanent `tools/` script, not throwaway) that, for every catalog entry, computes a **value score** from its stats (weighted sum: DPS, HP, energy_capacity, utility flags for support modules) and a **cost score** from Metal+Crystal (+ weight as a soft tax, since heavier parts already have an in-fiction cost via speed), then reports **value-per-cost** ratios so outliers (a weapon that's strictly better than another for less cost, a generator that's not worth its weight) are visible as a ranked list, not buried in a spreadsheet nobody opens. Full reasoning and the actual weight choices are in §7 of this doc once implemented — flagging now that DPS/HP/support-utility are fundamentally different currencies and the weighting between them is a judgment call, not a derived truth; treat the tool's output as a starting point for human tuning, not an authority.

## 7. Balance tooling: what was actually built and found

`prototype/tools/balance_report.gd` (headless, run with `Godot...exe --headless --script tools/balance_report.gd`) scores every catalog entry:

```
value = dps*3.0 + hp*0.3 + energy_capacity*1.2 + energy_regen*4.0
cost  = metal + crystal*2.0 + weight*0.05
ratio = value / cost
```

Grouped by category, sorted by ratio, flagged when a ratio is >1.5x or <0.5x its category's own average. The weights are a judgment call (documented in the tool's own header) - DPS is weighted highest since it's a weapon's primary purpose, HP a secondary survivability bonus, Crystal counts double since it starts scarcer than Metal (150 vs 450 in the default economy) and Weight gets a small tax since it already costs speed in-fiction.

**Findings acted on** (first real pass, not exhaustive - see below for what wasn't touched and why): three weapon-category outliers were nudged based on the tool's own numbers, not gut feel:
- `spigot_mortar` had the highest raw DPS in the game (130) at less than half the Metal+Crystal cost of comparable weapons - value/cost 6.31 against a 2.86 category average. Cost raised (metal 50→65, crystal 5→15); DPS/HP untouched.
- `flamethrower` was similarly cheap for its output (5.49 ratio). Cost raised (metal 25→35, crystal 10→15).
- `ion_cannon` (this pass's own new weapon) was the single worst value/cost weapon in the entire catalog (1.03) even before accounting for its energy-drain utility, which this cost model can't see at all - its heavy Crystal cost was effectively double-penalizing a flagship weapon that's supposed to be a real alternative to gauss_railgun/plasma_lobber. Crystal cost lowered (90→65).

Re-running the tool after these three changes: `spigot_mortar` 6.31→4.15, `flamethrower` 5.49→3.87 (no longer flagged), `ion_cannon` 1.03→1.27. Deliberately stopped here rather than chasing every flagged entry to the category average - three changes I can reason about concretely is more trustworthy than a dozen changes made mechanically without being able to playtest the result.

**Deliberately NOT touched, and why** (the model said "outlier" but the number is misleading, not the balance):
- Point-defense specialists (`pd_laser` 0.37, `ciws` 0.72, `flak_cannon` 1.02) score low because their real value is *interception capability against missiles*, not raw DPS against normal targets - the model has no way to represent that. Buffing their DPS to satisfy a value/cost formula would break their actual role.
- Utility modules with `dps: 0` (`resource_harvester` 0.22, `sensor_suite` 0.19) score near-zero because the model only understands DPS/HP - their real value (economy throughput, hypothetically vision once that system exists) isn't captured at all.
- Locomotion and hull entries score almost entirely on HP, since neither DPS nor a "mobility" stat exists in the model - `anti_grav`'s low score (0.09) reflects that airborne/hovering capability isn't represented, not that it's overpriced.
- Foundations (`pillbox_foundation` 3.00, `tower_foundation` 2.10) score high because they're pure-HP defensive structures by design - that's the intended tradeoff (stationary, no locomotion cost), not an accident.

**What's shaky, flagged explicitly (per Chris's ask) rather than hidden:** the tool's own printed output states this every run - locomotion/hull scores are low-confidence (HP-only), energy weapons' true cost-to-use (capacitor drain limiting sustained fire) isn't captured by a one-time Metal/Crystal price, and `repair_array`'s heal-rate-as-"dps" overstates its raw value next to an equal-DPS weapon (healing is situational, damage isn't). This is a tool for surfacing candidates for a human to reason about, not an authority that should be trusted blindly - see `_report_category()`'s own header comment.

**Verified:** `test_balance_report_covers_every_catalog_entry()` is a regression guard (the tool stays callable and produces finite, non-negative numbers as the catalog grows) - not a balance-correctness test, since balance is a playtest-feel judgment, not a mechanical property.

---

*(See PROGRESS.md for the implementation log and DECISIONS_NEEDED.md for judgment calls made along the way.)*
