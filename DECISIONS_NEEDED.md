# Decisions Needed / Judgment Calls Log

Newest entries first. Each entry: the question, the default I'm proceeding with, and why. Anything marked **BLOCKING** means I stopped that thread entirely and need Chris's input before continuing it — everything else is "proceeding on best judgment, flagging for review."

---

## 2026-07-12 — Real pathfinding + naval terrain: built, plus a real bug found while verifying it end-to-end

**Not blocking — fixed immediately, not just logged.**

Built real NavigationServer3D-based pathfinding (previously deferred, see the "Unit AI scope" entry above — Chris explicitly greenlit it this pass along with giving the map real water terrain). Two separate navigation maps (ground/water, not Godot's single default map) since ground and naval units need to route against completely different geometry: a rectangular lake (`LAKE_CENTER=(18,0,0)`, half-extents 7x7) now exists on the Skirmish map with a visible blue water plane, baked as a hole in the ground navmesh and as the water navmesh's only walkable area. `battle_unit.gd` gets a `NavigationAgent3D` per non-flying unit (flying/fixed-wing skip it entirely — open air, nothing to route around), assigned to the correct map via `is_naval`; `_steer_towards()` now asks the agent for the next path point instead of steering straight at the final destination when an agent is present, falling back to straight-line steering for every synthetic test/context with no real match controller (duck-typed via `get_ground_nav_map()`/`get_water_nav_map()` on the parent).

**A real bug found while verifying this end-to-end, not just via unit tests:** all 54 tests passed (including two dedicated pathfinding tests checking navmesh queries and nav_agent map assignment) and NavigationServer3D path queries worked correctly in isolation — but a first windowed capture showed a unit given `order_move()` not translating at all. Root cause turned out to be unrelated to the new pathfinding code: `battle_unit.gd`'s `_recalculate_move_speed()` only counts locomotion by scanning the hull's children for a module with `category == "locomotion"` — it does NOT look at the top-level `"locomotion": {type_id, settings}` blueprint field (that field only feeds `locomotion_type`/`locomotion_settings`, used for movement-trait/count_contrib lookups, not the has-locomotion check itself). Real saved blueprints always carry both, because `serialize_hull()` serializes every hull child with `module_data` into `"modules"` — which includes the locomotion part, since the Design Lab's `update_locomotion()` places it as an actual module child. But the synthetic test blueprints used throughout `run_tests.gd` (and my own first diagnostic script) only ever set the top-level field with `"modules": []`, so `has_locomotion` was false and `move_speed` silently computed to `0.0` — a test-fixture gap, not a gameplay bug. Confirmed by rebuilding the diagnostic blueprint with a real `tracked_treads` module entry alongside the top-level field: movement worked immediately, correctly detouring around the lake.

**Fixed/added:** a new end-to-end test (`test_unit_order_move_actually_navigates_around_the_lake`) using a blueprint shaped like a real saved one (locomotion module included), asserting both real movement (>5 units of travel) and that the path never enters the lake bounds — this is deliberately a stronger check than the two nav_agent-assignment-only tests already had, specifically so this class of bug (individually-correct pieces that don't add up to actual movement) can't hide again. Did NOT go back and retrofit the dozens of other pre-existing test blueprints across `run_tests.gd` that use the top-level-field-only shorthand — they don't exercise `move_speed`/real movement, so the shorthand is harmless for what they actually check, and a blanket rewrite is out of scope for this pass. Windowed-screenshot verified in a real Skirmish match — `progress_captures/2026-07-12/pathfinding/` shows a unit hugging the lake's edge mid-transit and fully past it at the end, never inside the water.

**Verified:** 55/55 tests green (1 new, per above).

---

## 2026-07-12 — Fog-of-war: asymmetric (player-only), two-state, not the fuller version

**Not blocking.**

Built real fog-of-war from scratch (no prior infrastructure existed at all - see PROGRESS.md). Two scope cuts worth flagging explicitly rather than leaving implicit:

**Asymmetric - the enemy AI keeps full omniscient targeting.** Fog only ever hides ENEMY constructs from the PLAYER (rendering + the player's own weapons' targeting); the player's own units are never hidden from the enemy AI. A fully symmetric fog (AI also can't see/target unscouted player units) is more "real" and would be the natural next step, but risks making the AI feel broken - unable to find a harvester it should intercept, slow to react to a real threat - in ways I can't verify by feel without an interactive playtest pass. This is also a lower-risk default: a broken/too-generous player experience is annoying, a broken/too-blind AI can make the whole mode feel unfinished.

**Two-state (currently-visible / hidden), not three-state.** Some RTS games have a third "explored but not currently visible" state - a scouted area stays dimly revealed (terrain/last-known-position visible) even after vision moves away, rather than snapping back to fully hidden. This implementation snaps back to fully hidden the instant a construct leaves vision range. The three-state version is a real, reasonable enhancement but needs its own persistent per-tile/per-construct "have I ever seen this" state, which is more infrastructure than the core mechanic needed to ship.

**Why worth building at all despite the scope cuts:** Technocrats' "+15% sensor/radar vision" passive has been unimplementable since this project started (confirmed via an earlier gap-analysis pass) for lack of anything to modify - this closes that gap for real, and gives `sensor_suite`'s flavor text ("pushes back fog of war") actual mechanical teeth for the first time.

---

## 2026-07-12 — Correction: "energy" damage_class had no real armor-table row at all, silently fell back to explosive

**Not blocking - fixed immediately, correction to an earlier claim.**

A previous entry in this log ("Energy weapons: didn't reclassify existing thermal weapons") claimed tesla_coil/arc_projector/ion_cannon "give the previously-dead Energy armor damage-type threshold its first real use." That was wrong. `damage_resolver.gd`'s `ARMOR_TABLE` never actually had an `"energy"` key for any material - only `kinetic`/`thermal`/`explosive`. `get_material_threshold()`'s fallback (`row.get(damage_type, row["explosive"])`) meant every weapon dealing `damage_class == "energy"` was silently resolving as EXPLOSIVE damage instead, with no error or warning. Found while scoping today's energy-weapon-reclassification work, when I went looking for the real energy thresholds to compare against and discovered there weren't any.

Separately, but for the same root cause: the Design Lab sidebar's "Armor Thresholds: K: _, T: _, E: _" label had its own hardcoded `e_base` table in `stat_calculator.gd`, completely disconnected from `damage_resolver.gd` - and its values were an exact copy of the EXPLOSIVE thresholds, just mislabeled as Energy. This predates this session entirely; it's not something the energy-weapon work introduced.

**Fixed:** real `"energy"` row added to `ARMOR_TABLE` for all four materials (energy_shielding gets the strongest energy defense, matching its name; hardened_steel/reactive_armor are weak against it; ablative_ceramic is moderate). `stat_calculator.gd`'s sidebar now reads K/T/E directly from `DamageResolver.get_material_threshold()` instead of a second hardcoded table, so it can't drift again. New test (`test_energy_damage_class_reclassification`) asserts energy resolves to a genuinely distinct threshold from explosive.

---

## 2026-07-12 — Visual regression pass: one false alarm (clipping working correctly), one real bug (Energy deficit at match start)

**Not blocking - both resolved during the pass itself, not left open.**

Per Chris's explicit instruction to actually hunt for regressions with the new screenshot-diff tool rather than just wire it up, I reviewed all 5 first-run captures by eye:

1. **`mainlab_armor_facet_fitting` initially showed a giant solid red block instead of visible armor plates.** Traced to `check_all_clipping()` correctly flagging genuine overlapping armor geometry - my test scenario placed two full-facet-covering armor plates (right+mirrored-left, plus back) on the Design Lab's small default hull (interceptor_hull, not the medium_hull I'd assumed), which legitimately overlap near the hull's corners. This is the existing clipping-detection system working exactly as designed, not a rendering bug. Fixed by simplifying the test scenario to a single non-overlapping top-facet plate; confirmed it now renders correctly.
2. **`skirmish_hud` showed "⚡ Energy: 0/0 (DEFICIT: builds slower!)" in the very first frame of a brand new match**, before the player has done anything. Root cause: no generator modules exist at match start (nobody's built one yet), so team Energy capacity was 0, while the 3 starting static buildings (HQ/Factory/Refinery) already owe upkeep (9.0 total) - every match started in automatic deficit, applying the 1.5x factory build-speed penalty for the entire early game by default, regardless of anything the player does. This was a genuine, unintended consequence of the Energy design landing earlier this session, only caught because the visual QA pass actually looked at the HUD in a fresh match rather than just checking the mechanism worked in isolation.

**Fix:** `skirmish.gd` gained `ENERGY_HQ_BASELINE_CAPACITY = 10.0` - the HQ has its own baseline power plant, offsetting default starting upkeep so a fresh match begins at a small surplus (1.0) instead of an immediate, unearned deficit warning. Generators remain a genuine optional upgrade (more energy for energy weapons, more upkeep tolerance for extra static buildings) rather than a mandatory tax just to avoid a penalty nobody caused. New headless test (`test_no_energy_deficit_at_match_start`) guards this doesn't silently regress.

**Why this matters beyond the specific fix:** this is the exact class of bug the screenshot-diff tool was built to catch that the cheap headless UI-audit checks structurally can't - not a layout/overflow problem, but "the numbers are technically correct and nothing crashed, but what a player actually sees on first glance is wrong." Worth Chris knowing the visual QA pass earned its cost on the very first real run.

---

## 2026-07-12 — Found and fixed a real pre-existing bug: repair_array/drone_carrier never actually fired in real gameplay

**Not blocking - fixed immediately, not just logged.**

While verifying the repair_array/drone_carrier fixes with a test that goes through the REAL `setup()`/`reconstruct_vehicle()` spawn pipeline (rather than my other synthetic tests, which manually attach `auto_weapon.gd` to a bare `Node3D` - a shortcut that works for testing the weapon's internal logic but silently bypasses how it actually gets attached in a real match), I found that `_setup_weapons()` and its two equivalents (`battlefield.gd`, `building.gd`) all gate script-attachment on `data.category == "weapon"` - and `repair_array`/`drone_carrier` are both catalogued as `category: "module"` (like `resource_harvester`/`sensor_suite`/`logistics_tank`, which correctly don't need the script since they're driven by other systems). This meant **neither module has ever actually fired/healed/targeted anything in real Skirmish or Test Range play** - the elaborate type_id-specific handling already built for them in `auto_weapon.gd` (fire_range/fire_rate/color, muzzle-flash suppression, unique fire functions) has been dead code since it was written, because the script attachment gate silently excluded them the whole time.

**Fixed:** new `ModuleCatalog.needs_combat_script(type_id)` (category=="weapon" OR type_id in [repair_array, drone_carrier]), single source of truth used by all three spawn paths. New test specifically exercises the real pipeline (not a manually-scripted synthetic node) so this exact class of bug can't silently reappear.

**Why worth flagging distinctly:** this predates this session's work entirely - it's not something my repair/drone fixes introduced, it's a bug that made the ORIGINAL (fake) repair_array/drone_carrier implementations unreachable too. Worth Chris knowing this was silently broken since whenever these modules were first added, not just today.

---

## 2026-07-12 — repair_array's heal rate reuses the generic "dps" catalog field

**RESOLVED 2026-07-12 (same day) — built the real heal_rate field.** Chris asked for this specifically. `module_data.gd` gained `base_heal_rate`/`get_heal_rate()` (its own getter, reusing `welder_count`'s existing scaling shape rather than dps's), `module_catalog.gd`'s repair_array entry is back to an honest `dps: 0.0` with a separate `heal_rate: 30.0`, `auto_weapon.gd`'s `_fire_repair_array_beam()` now calls `heal_rate * fire_rate`, and the Design Lab's floating stat popup shows "Heal Rate: X/s" instead of "DPS: X" for modules with a nonzero heal rate. `tools/balance_report.gd` also gained a `HEAL_RATE_WEIGHT` so repair_array scores fairly instead of via a leftover dps number. Original reasoning kept below for context on why the dps-reuse was a reasonable stopgap at the time.

**Not blocking.**

Fixing repair_array's real heal logic needed SOME numeric rate for `repair_hp(dps * fire_rate)` to use. Rather than inventing a parallel `heal_rate` stat field (its own catalog key, its own ModuleData getter, its own tweak-scaling plumbing in three places) just to keep it out of the "Total DPS" aggregate, I reused the existing `dps` field/pipeline - it already has weight/cost/tweak scaling fully wired (the `welder_count` tweak already multiplies it, matching the doc's "adding more arms speeds up construction exponentially").

**Cost of this shortcut:** repair_array's heal-per-second rate is now also summed into the Design Lab's "Total DPS" stat, mislabeling a heal as damage output on any hull that mounts one. Cosmetic, not a mechanics bug - the actual repair behavior in combat is correct.

**Why I judged this acceptable:** support modules already show `0.0` DPS harmlessly everywhere else; making repair_array's rate visible-but-mislabeled is a smaller wart than a whole parallel stat pipeline built just to avoid one misleading number in a sidebar. Flagging as a clean future fix (add a real `heal_rate` field, exclude `category != "weapon"` modules from the DPS sum) if the mislabeling ever actually confuses a player.

---

## 2026-07-12 — Energy weapons: didn't reclassify existing thermal weapons to "energy" damage_class

**RESOLVED 2026-07-12 (same day) — reclassified `heavy_laser`/`plasma_lobber`/`pd_laser`, with the concrete swing logged below.** Chris explicitly greenlit this in a later batch, asking me to use the balance tooling to check it carefully first.

**What "using the balance tooling" actually meant here:** `tools/balance_report.gd` scores cost-efficiency (dps/hp/energy vs metal/crystal/weight) - damage_class isn't part of that formula at all, so re-running it on these three weapons shows no change (correctly - reclassification doesn't touch their dps or cost). The tool confirmed there's nothing to see on THAT axis. The real risk Chris was pointing at is armor-matchup swings, which needed a different check: comparing `damage_resolver.gd`'s ARMOR_TABLE thermal row against a real energy row, which **didn't exist until this pass** - `get_material_threshold()` silently fell back to the EXPLOSIVE row for any unrecognized damage_type, so these three weapons (and the earlier tesla_coil/arc_projector/ion_cannon) were actually resolving as explosive damage this whole time, and the Design Lab's "E:" armor-threshold label had always been a mislabeled copy of the explosive value, not a real energy number. Fixed both first (see the `damage_resolver.gd`/`stat_calculator.gd` changes), then did the real matchup analysis:

| Material | Thermal (old) | Energy (new) | Effect on heavy_laser/plasma_lobber/pd_laser |
|---|---|---|---|
| hardened_steel | 5.0 thresh, 0.9 reduction | 8.0 thresh, 0.85 reduction | Roughly a wash, very slightly weaker |
| reactive_armor | 10.0, 0.8 | 8.0, 0.85 | Slightly stronger |
| ablative_ceramic | 25.0, 0.3 | 15.0, 0.6 | **Meaningfully stronger** - was the best anti-thermal material (r=0.3), now lets through 2x the damage (r=0.6) |
| energy_shielding | 20.0, 0.5 | 35.0, 0.3 | **Meaningfully weaker** - was an average defense, now specifically hard-counters these weapons (higher threshold + r=0.3) |

**Why I did it anyway despite the real swing:** the swing is thematically *correct*, not just numerically different - `ablative_ceramic` (heat-ablative material) has no real reason to be the best defense against a directed-energy laser, and `energy_shielding` (a material literally named for this) had no mechanical reason to be merely average against them. The old thermal classification was masking a real design gap: materials weren't actually differentiated by damage type the way the game's own fiction implies. Logging the concrete before/after numbers here so Chris can feel out whether the swing is too strong once he can playtest it - this is exactly the kind of change I'd want caught in an interactive pass, not reverted blind.

**Deliberately NOT touched:** `flamethrower` (fire/fuel-based, not directed energy - correctly stays thermal), `drone_carrier` (drone-strike damage has no strong energy identity either way). `ENERGY_DAMAGE_CLASS_TYPES` (auto_weapon.gd) is kept explicitly separate from `ENERGY_WEAPON_TYPES` - these three reclassified weapons deal energy damage but do NOT cost the shooter's own Energy pool to fire or drain the target's; only tesla_coil/arc_projector/ion_cannon have that capacitor mechanic. Mixing the two would have been a much bigger change than "which armor threshold this resolves against."

Original reasoning for deferring kept below for context on why the aggregate-only version was the reasonable starting scope at the time.

**Not blocking.**

The armor system already had an "Energy" damage-type threshold (`E:` in the Design Lab sidebar, `energy_shielding` armor material) since early this week, but nothing in `auto_weapon.gd` ever actually set `damage_class = "energy"` - it was cosmetic-only. The three new energy weapons (tesla_coil/arc_projector/ion_cannon) now use it for real.

**Default I'm proceeding with:** left `heavy_laser`, `plasma_lobber`, `pd_laser`, `flamethrower`, `drone_carrier`, and everything else that currently falls into the `damage_class = "thermal"` catch-all exactly where it was, rather than reclassifying anything with "laser" or "plasma" in the name to "energy" for thematic consistency.

**Why:** reclassifying an existing weapon's damage_class silently changes its effectiveness against every armor material's existing threshold table - a real balance change to weapons that have been live all week, made unattended, with no way to interactively verify the new numbers feel right. Chris asked for new energy-drain weapons, not a damage-type audit of the existing arsenal. Flagging as a reasonable follow-up for a session where balance can be iterated on interactively - see also the balance-tooling section of ENERGY_AND_BALANCE_SPEC.md.

---

## 2026-07-12 — Unit AI scope: whole-vehicle-aim + kiting + new-roster entries built; real pathfinding and naval terrain routing deferred

**Not blocking.**

Chris's scoping guidance named four things: facet-aware flanking extended to ranged positioning/kiting/retreat, whether fixed-wing/naval AI needs more depth, turreted-vs-frame-built whole-vehicle-aim, and mixed AI compositions. I sequenced by concreteness and direct connection to work already built this week, in this order:

1. **Frame-built whole-vehicle-aim** — the most concrete gap: `get_mount_style()` already classified some weapons as `frame_built` ("whole vehicle aims, not the weapon") but nothing enforced it — the weapon still independently traversed within its arc. Fixed at the root (`get_traverse_limit_angle()` now mount-aware) plus the AI consequence (`battle_unit.gd` turns the whole hull in place). See PROGRESS.md for detail.
2. **Kiting** — distance-based standoff only (back off once an enemy closes past 45% of attack_range), not the more ambitious "detect I'm exposing my weak facet to the attacker and reposition" version. The latter would need per-frame self-facet-vs-attacker-bearing computation on top of the existing target-facet flanking logic — a real feature, but a second layer past what fit in this pass. Logged as the natural next depth increment on kiting, not abandoned. **RESOLVED 2026-07-12 (later same day) — built.** `battle_unit.gd`'s kiting now always repositions to keep its own STRONGEST facet toward the attacker while retreating (`_kite_reposition()`, reusing the same per-facet threshold estimate `_weakest_facet_normal()` already used for flanking, generalized via a new `_facet_thresholds()` helper). Real bug found and fixed along the way: an initial version tried to hand off from repositioning to plain `_steer_towards()` once the good facet was achieved, but `_steer_towards()` has its own, conflicting idea of what to face (the travel direction) and immediately undid the positioning - simplified to always use the self-stabilizing reposition logic instead of two competing steering modes. See `test_facet_aware_kiting`.
3. **Mixed AI compositions** — the roster already had 4 varied archetypes (not one-unit-type spam), so the real gap was narrower than the phrasing suggested: none of them exercised this week's new movement types. Closed that specific gap with two new blueprints rather than redesigning the roster system itself.

**What I did NOT build, and why:**

- **Real pathfinding / obstacle avoidance (NavigationServer3D, baked navmeshes, `NavigationAgent3D`).** Checked the actual Skirmish map: it's a flat, mostly open 160×160 ground plane with scattered resource-node props, not a maze of buildings units would path around. The current straight-line/flank-point steering already produces reasonable-looking movement on this terrain. Building a full navmesh-baking + per-unit-agent pipeline is a genuinely large subsystem (bake step, agent avoidance radii, dynamic re-bake if buildings get placed mid-match) for a benefit that's currently mostly theoretical given the map's actual geometry. If maps grow more complex (maze-like chokepoints, dense building placement blocking direct paths), this becomes worth it — flagging as the trigger condition rather than a fixed timeline. **RESOLVED 2026-07-12 (later same day) — built.** Chris explicitly greenlit this and gave the map real water terrain to route around (see the new "Real pathfinding + naval terrain" entry below for the full build and a real bug that surfaced and got fixed along the way).
- **Naval terrain-aware routing (water vs. land).** There is no water/land distinction anywhere in the map — naval units are purely Y-locked to a fixed waterline (`y≈0.3`) regardless of what's underneath them, a pre-existing simplification from when `naval_propeller` was first built (Traits B3). "Route around land, stay on water" has no map data to route against; building it now would mean inventing a fictional water-boundary system nobody asked for yet, not implementing the feature described. This is a map/world-building gap, not an AI gap — worth flagging separately if naval combat becomes a real focus. **RESOLVED 2026-07-12 (later same day) — built.** Same pass as above — a real lake now exists on the map with its own navmesh.
- **Deeper fixed-wing strafing AI.** The existing orbit-and-strafe pattern (built earlier this week) already produces the core "can't hover, passes through and comes back around" behavior. Chris's question was "does it need more depth" rather than a specific ask — I judged the existing baseline reasonable for now (a real AI-controlled fixed-wing unit now exists to exercise it, see `raptor_striker.json`) and didn't add altitude-varying passes, formation flying, or break-off-under-fire behavior, which would be genuine new scope rather than a bug fix. Flagging as available future depth, not a gap in what exists.

---

## 2026-07-12 — Screenshot-diffing for visual regression testing: investigated, not built

**RESOLVED 2026-07-12 (same day) — built.** Chris greenlit it this pass. See PROGRESS.md's "Screenshot-diff testing built + real visual QA pass" entry for what shipped, and for two real bugs the QA pass itself found (one turned out to be the clipping-detection system correctly doing its job, the other was a genuine Energy-deficit-at-match-start bug, fixed). Original cost/benefit reasoning below kept for context.

**Not blocking.**

Chris explicitly asked me not to default to the most expensive version of visual-bug detection without laying out the cost/benefit. The two cheap, headless-feasible techniques (panel-overflow detection, off-screen-control detection) are built and already found a real bug. Screenshot-diffing is the natural next tier — it would catch things the cheap checks structurally can't (a missing/wrong texture, actual pixel-level layout drift, a mesh clipping through UI) — but:

**Cost:** needs windowed rendering (confirmed via memory/this week's own experience: headless Godot's dummy renderer doesn't rasterize), so it can't live in the fast headless suite — it needs its own slower windowed pass. It also needs a maintained baseline-image directory (checked into git or stored separately) and a tolerance threshold tuned to avoid false positives from legitimate minor rendering variance (anti-aliasing, driver differences).

**Default I'm proceeding with:** not building it now. Logged as an available, well-understood option rather than attempted speculatively.

---

## 2026-07-12 — Removed the pre-existing "no locomotion on foundations" hard-block

**Not blocking.**

`_place_weapon_from_ui` had a pre-existing gate (from earlier in the week, before today's trait-system direction) that rejected locomotion placement on foundation hulls, matching Factions_and_Buildings.md's "defenses don't need locomotion" framing. Chris's new instruction is explicit and general: "traits/hulls/locomotion must never hard-block each other... not from validation logic that prevents 'weird' combinations."

**Default I'm proceeding with:** removed the gate. A foundation can now have locomotion placed on it — a mobile pillbox is exactly the kind of "janky or suboptimal" emergent outcome Chris said is acceptable, possibly desirable. Updated `test_foundation_design_lab_parity()` to assert the opposite of what it used to (locomotion succeeds, not rejected).

**Why flagged rather than silently done:** this changes *established* behavior from earlier in the week, not just "declining to add a new block" — worth a clear record that it was a deliberate, instructed change, not an oversight, in case Chris wants to reconsider once he sees mobile foundations in practice.

---

## 2026-07-12 — New airframe/ship hull geometry (Traits B5) deferred

**RESOLVED 2026-07-12 (later same day) — built, plus two more new hull types beyond just airframe/ship.** Chris explicitly greenlit a larger hull-library expansion this pass. See the "Hull library expansion" entry below for what shipped (`naval_hull`, `flying_wing_hull`, `sponson_hull`) and how each was verified. Original reasoning kept below for context on why this was deferred at the time.

**Not blocking.**

`fixed_wing_engine` and `naval_propeller` (new locomotion types, Traits B3) work correctly on the existing 7 hulls today — tested `fixed_wing_engine` on `light_hull` and `naval_propeller` on `heavy_hull`, both function with procedural part visuals and no placement issues, since no-hard-blocking means any hull accepts any locomotion.

**Default I'm proceeding with:** not authoring new purpose-built airframe/ship hull silhouettes this session. Same reasoning as every other new-art decision this week (the deferred "Fortress Wall" foundation type, 6 of 7 hulls still lacking custom deform rigging): new Blender-authored geometry needs the headless-import pipeline, which is fragile enough (see the memory gotcha about isolated-copy imports) that I don't want to risk it unattended without being able to iterate on how it actually looks. The mechanics (traits, movement models, mounting) all work today without it — this is a visual layer on top of working systems, not a blocker for them.

**Why this is lower-risk to defer than the armor/trait work:** unlike the movement-model code (which needed to exist for the mechanics to be real), a purpose-built jet/ship silhouette is purely cosmetic — the generic hulls already carry the new locomotion types functionally correctly.

---

## 2026-07-12 — Visual regression baselines updated for the grown hull palette

**Not blocking.**

Final-verification pass for this whole batch ran the windowed `visual_regression` suite (built earlier this week) as a broader QA sweep beyond the headless test suite. 4 of 5 MainLab scenarios failed (~3.47% pixel diff, just over the 2% tolerance) - traced to exactly what you'd expect: the hull palette grew from 7 to 11 buttons this batch (`fortress_wall_foundation`, `naval_hull`, `flying_wing_hull`, `sponson_hull`), shifting pixels in that region of every MainLab screenshot. Confirmed this is expected content growth, not a bug, by inspecting the captures directly (palette renders correctly, no overflow - matching the already-passing headless `test_ui_overflow_audit` for the same scene) and cross-checking against `skirmish_hud` (unaffected, still passed at 1.594% diff - proof the diff tool itself didn't get less strict).

**Fixed:** updated the 4 affected baselines to the new captures. This is the intended use of baseline updates (documented in `run_visual_regression.gd`'s own header) - a deliberate, verified UI change, not silently suppressing a real regression.

---

## 2026-07-12 — Hull library expansion: 3 new hull types, built and verified one at a time

**Not blocking.**

Chris asked for genuinely new hull geometry, not just deform handles on the existing 7: "some ship-like hulls..., a blended-wing-body type hull, and hulls with more interesting base geometry to build on top of — things like built-in sponson stubs already part of the hull silhouette." Built three, each authored/imported/screenshot-verified individually before starting the next (per Chris's explicit instruction, same discipline as the nose-taper work):

- **`naval_hull`** — pointed bow, flat transom stern, shallow-draft keel below the waterline, raised bridge superstructure, porthole greebles. `naval_propeller` previously had nothing purpose-built to sit on (it worked on any generic wedge hull, e.g. `heavy_hull`, floating at a fixed waterline) - this gives it a real boat silhouette.
- **`flying_wing_hull`** — swept delta/manta-ray planform, no distinct fuselage-vs-wing break (a shallow dorsal blend ridge instead of the wedge hulls' raised spine). Confirmed via a top-down screenshot showing a clean swept-delta outline, distinct from every wedge-based hull.
- **`sponson_hull`** — heavier ground hull with two box-like sponson blisters fused onto the mid-body sides, baked into the base mesh rather than being mount-time hardware. **First attempt was too subtle to read as intended**: initial version used only convex-hull point placement (narrow fore/aft, wider mid-band), which produced a smooth continuous taper - visually just a chamfered octagon, not a distinct "stub." Caught via the mandatory screenshot check before moving to the next hull (exactly why the one-at-a-time verification discipline matters). Fixed by keeping a narrower slab-sided core hull and fusing two separate box volumes onto its sides at the mid-body band - now reads as a real stepped protrusion, confirmed in a second round of screenshots.

**Balance check:** ran `tools/balance_report.gd` after adding all three - `naval_hull` (0.77), `flying_wing_hull` (0.75), `sponson_hull` (0.74) all land inside the existing mobile-hull cluster's value/cost range (0.72-0.80 across light/medium/heavy/interceptor/assault), no outliers flagged. Stats were hand-targeted to this range before running the tool (matching each new hull's weight class to a comparable existing hull), then confirmed rather than discovered after the fact.

**Verified:** 56/56 tests green (no new hull-specific test suite - the existing generic mechanisms, category/is_foundation-driven palette population, build-legality gate, and balance report all picked up the 3 new catalog entries automatically with no code changes needed, same as Fortress Wall). Two rounds of windowed screenshots per hull (isometric + top-down/end-on) in `progress_captures/2026-07-12/new_hulls/`.

**Not done this pass:** extending the per-hull custom deform rigging (currently only `interceptor_hull` has it) to any of these 3 new hulls, or to the 6 pre-existing hulls that still lack it - Chris's sequencing note said the new hull library should exist before deform work extends to it, not that this pass needed to do both. Logged as the natural next step whenever deform rigging work resumes.

---

## 2026-07-12 — Per-hull custom deform rigging built for interceptor_hull only, other 6 hulls deferred

**Not blocking — Chris explicitly authorized scoping this and logging tradeoffs (MOUNTING_AND_ARMOR_SPEC.md #4).**

"Per-hull-type custom deform rigging that reshapes different parts of that specific hull differently" is, done exhaustively, a bespoke-rigging task for all 7 hull/foundation types — each needs its own thought about which regions make sense to deform and how. That's a much bigger scope than fits in one pass alongside everything else today.

**What I built:** a genuine proof-of-concept on `interceptor_hull` — a "Nose Taper" slider that reshapes just the nose region of the *actual authored mesh* via `MeshDataTool` (runtime per-vertex editing, region-selected by local Z position, with linear falloff so it blends into the untouched hull body), not a swap between preset shapes and not a second mesh layered on top. This is the real technique the other 6 hulls would use too, once someone decides what "the interesting region to deform" means for each of them (e.g. pillbox_foundation's dome height, assault_hull's front glacis angle).

**Also fixed along the way, not just for this feature:** `blueprint_manager.gd`'s `reconstruct_vehicle()` never used the authored `.glb` hull meshes at all — every loaded/battle-spawned hull was a plain `BoxMesh` regardless of type, meaning the nice hull shapes only ever showed up in the Design Lab. Found because the nose taper would otherwise have been invisible the moment a design was saved or fielded. Fixed to match `update_hull_appearance()`'s mesh-selection logic, and the taper now survives the full save → reconstruct → battle-spawn round-trip (verified with a test).

**Why not all 7:** each hull needs a real design decision about what "the interesting region" is, not just mechanical repetition of the same code pattern — doing that well for 6 more hulls without being able to interactively iterate on how each one looks isn't a good use of unattended time. Flagging as the natural next step once someone can look at each hull and decide.

**Updated 2026-07-12 (later same day):** the hull/foundation count this applies to grew from 7 to 11 (`fortress_wall_foundation`, `naval_hull`, `flying_wing_hull`, `sponson_hull` added - see their own entries). Still only `interceptor_hull` has deform rigging; the other 10 remain candidates. Not extended to the new ones this pass - Chris's own sequencing note said the library should exist before deform work extends to it, not that one pass needed to do both.

---

## 2026-07-12 — Face-based mounting implemented generically, not as bespoke visuals per weapon type

**Not blocking.**

MOUNTING_AND_ARMOR_SPEC.md #3 describes distinct visual treatments per hull face (pintle-mounted and level on top, embedded-with-sponson on sides/front/back, inverted-pintle on bottom). A fully faithful version would give each of the ~20 weapon types its own bespoke mesh construction for each mounting style — 3x the existing per-type visual code in `visual_builder.gd`.

**Default I'm proceeding with:** a generic, type-agnostic treatment layer — facet classification decides a `mount_style`, which drives (a) how far the weapon embeds into the hull along the surface normal, and (b) a generic add-on mesh (pintle post or sponson collar) layered on top of whatever the weapon's own existing type-specific visual already builds. This delivers the real mechanical/visual differentiation (a side-mounted weapon looks embedded, not surface-glued; a top-mounted one sits on a visible post) without a much larger bespoke-art pass. `basic_cannon` (turret) and `gauss_railgun`/`heavy_howitzer` (frame_built) get their explicit exceptions as directed.

**Why not the bespoke version:** it's a legitimate next step, but it's an art-authoring scope, not a mechanics scope — consistent with Chris's own instruction elsewhere that art/mesh polish beyond mechanics is a later conversation.

---

## 2026-07-12 — Armor "mass distribution" example in DESIGN_VISION.md conflicts with an existing, deliberate design decision

**RESOLVED 2026-07-12 (same day) — Chris confirmed the spatial/module side of this tension directly.** See MOUNTING_AND_ARMOR_SPEC.md #2: armor is now placed as a facet-fitting module, superseding the hull-level-only approach this entry defaulted to. Left the original reasoning below for context on why it was ambiguous in the first place.

`DESIGN_VISION.md` (from this week's conversation) uses "how armor mass is distributed" as an example of the kind of continuous tweak that should let two players' builds diverge. But [Damage_And_Armor_Model.md](Damage_And_Armor_Model.md) — an existing repo doc, presumably from an earlier deliberate design pass — explicitly rejects individual/spatial armor plate placement: *"Placing individual armor plates manually is tedious, often results in visually messy designs, and slows down the player. To solve this, base armoring is handled at the Hull level rather than as individual placeable modules."*

**Superseded default:** hull-level Armor Material × Armor Thickness only, no spatial placement. No longer in effect.

---

## 2026-07-12 — Armor-module combat integration scoped to aggregate (non-directional), not full per-facet hit resolution

**RESOLVED 2026-07-12 (same day) — superseded.** The later armor pass built exactly the full directional version this entry scoped away from: `damage_resolver.gd`'s `resolve()` grew optional `defender`/`hit_origin` params that classify which facet actually faces the attacker and resolve armor/threshold against only that facet's covering plate (falling back to aggregate when either is omitted), plus a real raycast-based sloped-armor angle-of-incidence multiplier (`compute_slope_multiplier()`) and AI flanking that targets a defender's actual weakest facet. See `test_directional_armor_facet_resolution`, `test_per_module_armor_material`, `test_sloped_armor_angle_of_incidence`, `test_ai_flanking_targets_weakest_facet`. Original reasoning kept below for context on why the aggregate-only version was the reasonable starting scope at the time.

**Not blocking.**

Implementing MOUNTING_AND_ARMOR_SPEC.md #2 (armor as a facet-fitting module) for real combat effect would ideally mean: a hit from a given direction resolves against the armor module actually covering that facet. Building that properly requires threading hit-direction (attacker position relative to defender, or the weapon's aim vector) through `battle_unit.gd`'s `take_damage(amount, damage_type)`, which currently takes no direction/position argument at all and is called from multiple sites across combat/AI code. That's the same underlying gap as the "directional/facing armor thresholds" item logged earlier today (still not implemented) — this isn't a new problem, it's the same one, now more visible because the new armor system makes it matter more.

**Default I'm proceeding with:** armor modules contribute an aggregate (not directional) threshold/reduction bonus to `take_damage()`, on top of the existing hull-level material+thickness baseline — computed from the sum of placed armor modules' own `get_hp()` (which already scales with the facet area they auto-fit, via the existing volume-based `ModuleData` formula, so a bigger plate = a bigger bonus). This means armor modules are NOT cosmetic — placing more of them measurably helps in combat — without taking on the larger, riskier project of rewiring `take_damage()`'s call signature across the whole combat system unattended.

**Why not the full directional version:** changing a core combat function's signature that's called from multiple sites, unattended, without being able to playtest-verify the balance, is a bigger risk than the value justifies this pass. Logging it as the natural next step once someone can iterate on it interactively.

---

## 2026-07-12 — Directional/facing armor thresholds are documented but not implemented (deprioritized this week)

**RESOLVED 2026-07-12 (same day) — built.** Same-day armor pass implemented real directional/facing thresholds via `damage_resolver.gd`'s facet-aware `resolve()` plus a genuine raycast-based sloped-armor angle-of-incidence check — see the resolution note on the "Armor-module combat integration scoped to aggregate" entry above for the specifics and test names. The counter-play Damage_And_Armor_Model.md describes ("drive circles around the heavy unit, attack the weaker rear armor") is now real, and AI flanking (`_weakest_facet_normal`/`_compute_flank_point` in `battle_unit.gd`) exploits it too. Original reasoning kept below for context on why this was deprioritized at the time it was written.

**Not blocking — deferred, not forgotten.**

Damage_And_Armor_Model.md's counter-play section explicitly describes weaker rear armor as a real mechanic: *"drive circles around the heavy unit... attack the weaker rear armor (directional thresholds)."* Grepping `battle_unit.gd`'s damage/threshold code found only a single uniform threshold per damage class — no facing/hit-angle logic exists.

**Default I'm proceeding with:** not implementing this. It's a combat-simulation feature, not a Design Lab mechanic, and Chris's instructions this week are explicitly Design-Lab-mechanics-first ("ahead of pure visual/mesh polish" — this is arguably behind even that). Logging it so it isn't lost, not touching it.

---

## 2026-07-12 — Firing arc visualization (Design_Lab_UI_UX.md) is unimplemented; deferring behind tweak-depth work

**RESOLVED 2026-07-12 (same day) — implemented.** Chris moved this from deferred to explicit priority (MOUNTING_AND_ARMOR_SPEC.md #1); see PROGRESS.md's "Item 1 shipped" entry for what was built.

---

## 2026-07-12 — Keeping freeform module placement (not adding grid-snap)

**RESOLVED 2026-07-12 (same day) — doc updated to match.** Chris confirmed freeform is the final direction and asked for the grid-snap concept to be struck from Design_Lab_UI_UX.md itself, not just left as a decision-log note describing a doc tension. Done - the doc's "Surface Grid" section now describes freeform placement directly and explains why the earlier grid draft was superseded. Original reasoning kept below for context.

**Not blocking.**

Design_Lab_UI_UX.md also specifies a hex/square surface grid that constrains placement to snap points. The current implementation is fully freeform (raycast-based placement anywhere on the hull surface, constrained only by collision/clipping checks). Adding grid-snap would be a regression relative to DESIGN_VISION.md's Spore-style continuous-placement spirit and the differentiation test (freeform position is itself a differentiation axis — where exactly a weapon sits affects its arc/exposure).

**Default I'm proceeding with:** leaving placement freeform, not adding grid-snap. Flagging the doc tension (Design_Lab_UI_UX.md predates DESIGN_VISION.md) rather than silently ignoring the older doc.

---

## 2026-07-12 — Only 2 of the example foundation types exist (no "Fortress Wall")

**RESOLVED 2026-07-12 (later same day) — built.** Chris explicitly greenlit new Blender-authored art this pass. `fortress_wall_foundation` added to `module_catalog.gd` (category "hull", `is_foundation: true`, HP 1100/metal 140/crystal 10 - tankier per-slot than the pillbox, cheaper than the tower, deliberately lower vision (14) since it's a rampart, not a watchtower) and authored via a new `build_wall_hull()` in `tools/blender/build_meshes.py` - a battered (wider-at-base) wall face topped with 5 alternating battlement merlons, plus arrow-slit and rivet-row greebles, silhouetted deliberately differently from both the pillbox (octagonal domed bunker) and tower (tiered stack). Imported via the isolated-copy procedure from the memory gotcha (found two already-hung `--headless --editor --import` processes from earlier in the session holding the real project - didn't touch them, imported into a temp copy instead and copied just the new `.import`/`.godot/imported/*`/`uid_cache.bin` artifacts back). Windowed-screenshot verified in the Design Lab (`progress_captures/2026-07-12/fortress_wall/`) before considering it done, same caution as the nose-taper work. New test (`test_fortress_wall_foundation_spawns_correctly`) confirms it reconstructs via the real spawn pipeline with a working mesh, real HP/vision, and passes the build-legality gate. Because the palette and every generic system (build-legality, balance report, foundation parity mechanics) already key off `category`/`is_foundation` rather than a hardcoded type_id list, this was a pure content addition - no other script needed a matching update. Original reasoning for deferring kept below for context.

**Not blocking.**

Factions_and_Buildings.md names "Pillbox, Tower, Fortress Wall" as example bunker types; only `pillbox_foundation` and `tower_foundation` exist in `module_catalog.gd`. Wednesday's parity audit confirmed everything that DOES exist has full design-lab parity with vehicle hulls (placement/mirror/rotate/undo/serialize — verified with a new automated test, `test_foundation_design_lab_parity()`), so this isn't a functionality gap, just a content-count gap.

**Default I'm proceeding with:** not authoring a third foundation type this week. The doc's phrasing ("e.g., ...") reads as illustrative rather than a strict 3-type requirement, and adding a new hull means new Blender-authored geometry (`tools/blender/build_meshes.py`) plus the headless-import pipeline, which is fragile enough (see the memory gotcha about isolated-copy imports) that I don't want to risk it unattended without being able to windowed-screenshot-verify the result carefully. Flagging as a good candidate for a future session with more art-pass time, per Chris's own instruction that art/mesh polish beyond mechanics is "a later conversation."
