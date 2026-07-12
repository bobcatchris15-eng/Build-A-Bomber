# Decisions Needed / Judgment Calls Log

Newest entries first. Each entry: the question, the default I'm proceeding with, and why. Anything marked **BLOCKING** means I stopped that thread entirely and need Chris's input before continuing it — everything else is "proceeding on best judgment, flagging for review."

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

**Not blocking.**

Fixing repair_array's real heal logic needed SOME numeric rate for `repair_hp(dps * fire_rate)` to use. Rather than inventing a parallel `heal_rate` stat field (its own catalog key, its own ModuleData getter, its own tweak-scaling plumbing in three places) just to keep it out of the "Total DPS" aggregate, I reused the existing `dps` field/pipeline - it already has weight/cost/tweak scaling fully wired (the `welder_count` tweak already multiplies it, matching the doc's "adding more arms speeds up construction exponentially").

**Cost of this shortcut:** repair_array's heal-per-second rate is now also summed into the Design Lab's "Total DPS" stat, mislabeling a heal as damage output on any hull that mounts one. Cosmetic, not a mechanics bug - the actual repair behavior in combat is correct.

**Why I judged this acceptable:** support modules already show `0.0` DPS harmlessly everywhere else; making repair_array's rate visible-but-mislabeled is a smaller wart than a whole parallel stat pipeline built just to avoid one misleading number in a sidebar. Flagging as a clean future fix (add a real `heal_rate` field, exclude `category != "weapon"` modules from the DPS sum) if the mislabeling ever actually confuses a player.

---

## 2026-07-12 — Energy weapons: didn't reclassify existing thermal weapons to "energy" damage_class

**Not blocking.**

The armor system already had an "Energy" damage-type threshold (`E:` in the Design Lab sidebar, `energy_shielding` armor material) since early this week, but nothing in `auto_weapon.gd` ever actually set `damage_class = "energy"` - it was cosmetic-only. The three new energy weapons (tesla_coil/arc_projector/ion_cannon) now use it for real.

**Default I'm proceeding with:** left `heavy_laser`, `plasma_lobber`, `pd_laser`, `flamethrower`, `drone_carrier`, and everything else that currently falls into the `damage_class = "thermal"` catch-all exactly where it was, rather than reclassifying anything with "laser" or "plasma" in the name to "energy" for thematic consistency.

**Why:** reclassifying an existing weapon's damage_class silently changes its effectiveness against every armor material's existing threshold table - a real balance change to weapons that have been live all week, made unattended, with no way to interactively verify the new numbers feel right. Chris asked for new energy-drain weapons, not a damage-type audit of the existing arsenal. Flagging as a reasonable follow-up for a session where balance can be iterated on interactively - see also the balance-tooling section of ENERGY_AND_BALANCE_SPEC.md.

---

## 2026-07-12 — Unit AI scope: whole-vehicle-aim + kiting + new-roster entries built; real pathfinding and naval terrain routing deferred

**Not blocking.**

Chris's scoping guidance named four things: facet-aware flanking extended to ranged positioning/kiting/retreat, whether fixed-wing/naval AI needs more depth, turreted-vs-frame-built whole-vehicle-aim, and mixed AI compositions. I sequenced by concreteness and direct connection to work already built this week, in this order:

1. **Frame-built whole-vehicle-aim** — the most concrete gap: `get_mount_style()` already classified some weapons as `frame_built` ("whole vehicle aims, not the weapon") but nothing enforced it — the weapon still independently traversed within its arc. Fixed at the root (`get_traverse_limit_angle()` now mount-aware) plus the AI consequence (`battle_unit.gd` turns the whole hull in place). See PROGRESS.md for detail.
2. **Kiting** — distance-based standoff only (back off once an enemy closes past 45% of attack_range), not the more ambitious "detect I'm exposing my weak facet to the attacker and reposition" version. The latter would need per-frame self-facet-vs-attacker-bearing computation on top of the existing target-facet flanking logic — a real feature, but a second layer past what fit in this pass. Logged as the natural next depth increment on kiting, not abandoned.
3. **Mixed AI compositions** — the roster already had 4 varied archetypes (not one-unit-type spam), so the real gap was narrower than the phrasing suggested: none of them exercised this week's new movement types. Closed that specific gap with two new blueprints rather than redesigning the roster system itself.

**What I did NOT build, and why:**

- **Real pathfinding / obstacle avoidance (NavigationServer3D, baked navmeshes, `NavigationAgent3D`).** Checked the actual Skirmish map: it's a flat, mostly open 160×160 ground plane with scattered resource-node props, not a maze of buildings units would path around. The current straight-line/flank-point steering already produces reasonable-looking movement on this terrain. Building a full navmesh-baking + per-unit-agent pipeline is a genuinely large subsystem (bake step, agent avoidance radii, dynamic re-bake if buildings get placed mid-match) for a benefit that's currently mostly theoretical given the map's actual geometry. If maps grow more complex (maze-like chokepoints, dense building placement blocking direct paths), this becomes worth it — flagging as the trigger condition rather than a fixed timeline.
- **Naval terrain-aware routing (water vs. land).** There is no water/land distinction anywhere in the map — naval units are purely Y-locked to a fixed waterline (`y≈0.3`) regardless of what's underneath them, a pre-existing simplification from when `naval_propeller` was first built (Traits B3). "Route around land, stay on water" has no map data to route against; building it now would mean inventing a fictional water-boundary system nobody asked for yet, not implementing the feature described. This is a map/world-building gap, not an AI gap — worth flagging separately if naval combat becomes a real focus.
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

**Not blocking.**

`fixed_wing_engine` and `naval_propeller` (new locomotion types, Traits B3) work correctly on the existing 7 hulls today — tested `fixed_wing_engine` on `light_hull` and `naval_propeller` on `heavy_hull`, both function with procedural part visuals and no placement issues, since no-hard-blocking means any hull accepts any locomotion.

**Default I'm proceeding with:** not authoring new purpose-built airframe/ship hull silhouettes this session. Same reasoning as every other new-art decision this week (the deferred "Fortress Wall" foundation type, 6 of 7 hulls still lacking custom deform rigging): new Blender-authored geometry needs the headless-import pipeline, which is fragile enough (see the memory gotcha about isolated-copy imports) that I don't want to risk it unattended without being able to iterate on how it actually looks. The mechanics (traits, movement models, mounting) all work today without it — this is a visual layer on top of working systems, not a blocker for them.

**Why this is lower-risk to defer than the armor/trait work:** unlike the movement-model code (which needed to exist for the mechanics to be real), a purpose-built jet/ship silhouette is purely cosmetic — the generic hulls already carry the new locomotion types functionally correctly.

---

## 2026-07-12 — Per-hull custom deform rigging built for interceptor_hull only, other 6 hulls deferred

**Not blocking — Chris explicitly authorized scoping this and logging tradeoffs (MOUNTING_AND_ARMOR_SPEC.md #4).**

"Per-hull-type custom deform rigging that reshapes different parts of that specific hull differently" is, done exhaustively, a bespoke-rigging task for all 7 hull/foundation types — each needs its own thought about which regions make sense to deform and how. That's a much bigger scope than fits in one pass alongside everything else today.

**What I built:** a genuine proof-of-concept on `interceptor_hull` — a "Nose Taper" slider that reshapes just the nose region of the *actual authored mesh* via `MeshDataTool` (runtime per-vertex editing, region-selected by local Z position, with linear falloff so it blends into the untouched hull body), not a swap between preset shapes and not a second mesh layered on top. This is the real technique the other 6 hulls would use too, once someone decides what "the interesting region to deform" means for each of them (e.g. pillbox_foundation's dome height, assault_hull's front glacis angle).

**Also fixed along the way, not just for this feature:** `blueprint_manager.gd`'s `reconstruct_vehicle()` never used the authored `.glb` hull meshes at all — every loaded/battle-spawned hull was a plain `BoxMesh` regardless of type, meaning the nice hull shapes only ever showed up in the Design Lab. Found because the nose taper would otherwise have been invisible the moment a design was saved or fielded. Fixed to match `update_hull_appearance()`'s mesh-selection logic, and the taper now survives the full save → reconstruct → battle-spawn round-trip (verified with a test).

**Why not all 7:** each hull needs a real design decision about what "the interesting region" is, not just mechanical repetition of the same code pattern — doing that well for 6 more hulls without being able to interactively iterate on how each one looks isn't a good use of unattended time. Flagging as the natural next step once someone can look at each hull and decide.

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

**Not blocking.**

Implementing MOUNTING_AND_ARMOR_SPEC.md #2 (armor as a facet-fitting module) for real combat effect would ideally mean: a hit from a given direction resolves against the armor module actually covering that facet. Building that properly requires threading hit-direction (attacker position relative to defender, or the weapon's aim vector) through `battle_unit.gd`'s `take_damage(amount, damage_type)`, which currently takes no direction/position argument at all and is called from multiple sites across combat/AI code. That's the same underlying gap as the "directional/facing armor thresholds" item logged earlier today (still not implemented) — this isn't a new problem, it's the same one, now more visible because the new armor system makes it matter more.

**Default I'm proceeding with:** armor modules contribute an aggregate (not directional) threshold/reduction bonus to `take_damage()`, on top of the existing hull-level material+thickness baseline — computed from the sum of placed armor modules' own `get_hp()` (which already scales with the facet area they auto-fit, via the existing volume-based `ModuleData` formula, so a bigger plate = a bigger bonus). This means armor modules are NOT cosmetic — placing more of them measurably helps in combat — without taking on the larger, riskier project of rewiring `take_damage()`'s call signature across the whole combat system unattended.

**Why not the full directional version:** changing a core combat function's signature that's called from multiple sites, unattended, without being able to playtest-verify the balance, is a bigger risk than the value justifies this pass. Logging it as the natural next step once someone can iterate on it interactively.

---

## 2026-07-12 — Directional/facing armor thresholds are documented but not implemented (deprioritized this week)

**Not blocking — deferred, not forgotten.**

Damage_And_Armor_Model.md's counter-play section explicitly describes weaker rear armor as a real mechanic: *"drive circles around the heavy unit... attack the weaker rear armor (directional thresholds)."* Grepping `battle_unit.gd`'s damage/threshold code found only a single uniform threshold per damage class — no facing/hit-angle logic exists.

**Default I'm proceeding with:** not implementing this. It's a combat-simulation feature, not a Design Lab mechanic, and Chris's instructions this week are explicitly Design-Lab-mechanics-first ("ahead of pure visual/mesh polish" — this is arguably behind even that). Logging it so it isn't lost, not touching it.

---

## 2026-07-12 — Firing arc visualization (Design_Lab_UI_UX.md) is unimplemented; deferring behind tweak-depth work

**RESOLVED 2026-07-12 (same day) — implemented.** Chris moved this from deferred to explicit priority (MOUNTING_AND_ARMOR_SPEC.md #1); see PROGRESS.md's "Item 1 shipped" entry for what was built.

---

## 2026-07-12 — Keeping freeform module placement (not adding grid-snap)

**Not blocking.**

Design_Lab_UI_UX.md also specifies a hex/square surface grid that constrains placement to snap points. The current implementation is fully freeform (raycast-based placement anywhere on the hull surface, constrained only by collision/clipping checks). Adding grid-snap would be a regression relative to DESIGN_VISION.md's Spore-style continuous-placement spirit and the differentiation test (freeform position is itself a differentiation axis — where exactly a weapon sits affects its arc/exposure).

**Default I'm proceeding with:** leaving placement freeform, not adding grid-snap. Flagging the doc tension (Design_Lab_UI_UX.md predates DESIGN_VISION.md) rather than silently ignoring the older doc.

---

## 2026-07-12 — Only 2 of the example foundation types exist (no "Fortress Wall")

**Not blocking.**

Factions_and_Buildings.md names "Pillbox, Tower, Fortress Wall" as example bunker types; only `pillbox_foundation` and `tower_foundation` exist in `module_catalog.gd`. Wednesday's parity audit confirmed everything that DOES exist has full design-lab parity with vehicle hulls (placement/mirror/rotate/undo/serialize — verified with a new automated test, `test_foundation_design_lab_parity()`), so this isn't a functionality gap, just a content-count gap.

**Default I'm proceeding with:** not authoring a third foundation type this week. The doc's phrasing ("e.g., ...") reads as illustrative rather than a strict 3-type requirement, and adding a new hull means new Blender-authored geometry (`tools/blender/build_meshes.py`) plus the headless-import pipeline, which is fragile enough (see the memory gotcha about isolated-copy imports) that I don't want to risk it unattended without being able to windowed-screenshot-verify the result carefully. Flagging as a good candidate for a future session with more art-pass time, per Chris's own instruction that art/mesh polish beyond mechanics is "a later conversation."
