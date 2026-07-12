# Decisions Needed / Judgment Calls Log

Newest entries first. Each entry: the question, the default I'm proceeding with, and why. Anything marked **BLOCKING** means I stopped that thread entirely and need Chris's input before continuing it — everything else is "proceeding on best judgment, flagging for review."

---

## 2026-07-12 — Screenshot-diffing for visual regression testing: investigated, not built

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
