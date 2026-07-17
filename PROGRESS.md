# Progress Log

Dated entries, newest first. Written after every major chunk of work as a checkpoint for anyone (Chris, or a fresh session) picking this up cold.

---

## 2026-07-17 — Hull massing punch-list resumed: light_hull + heavy_hull finished (items 2-3), moving through the rest of the roster

Picked up `HULL_MASSING_SPEC.md`'s prioritized punch-list where a prior session left off (medium_hull, item 1, was already committed). Items 2 and 3 (`heavy_hull`, `light_hull`) were already converted to `build_afv_hull()` in the working tree with rebuilt `.glb`s but uncommitted and under-verified - reviewed the parameter choices against the spec (all correct), re-verified with wider/side/extreme-stretch screenshots (`progress_captures/2026-07-13/afv_hulls/`), and committed both separately. light_hull now reads low/sleek/scout-car; heavy_hull reads tall/blunt/slab-sided with a real recessed engine-deck louver grate and turret ring. Headless tests green throughout. Full reasoning in `DECISIONS_NEEDED.md`.

Continuing top-down through the spec's punch-list (items 4-15: assault_hull, sponson_hull, naval_hull, heavy_cruiser_hull, interceptor_hull, fuselage_hull, small_boat_hull, flying_wing_hull, airship_hull, then the three static-defense embrasure items).

---

## 2026-07-17 (cont'd) — assault_hull converted (item 4): dozer plate fused into the tub/glacis seam

`build_afv_hull` with a low-casemate parameter set (`tub_frac=0.55, upper_w=0.82`, no `turret_ring` since the hull's own greebles already add one) rather than medium_hull's turret-platform read. The real content move: the front dozer plate used to float as a separate box in front of the old wedge nose - now sized/positioned to span the tub's actual nose height (computed from `tub_frac`), so it visually fuses into the tub/glacis seam as one layered frontal assembly instead of a bolted-on-looking bump. Kept the existing appliqué plates and turret ring/hatch untouched (already good per the spec).

Also built `scratch/rebuild_single_hull.py`, a reusable single-hull rebuild helper (extracts and re-runs one hull's `export_and_cleanup(...)` call by name out of `generate_hulls()`) to replace hand-copying each hull's params into a new throwaway script - keeps each hull's rebuild/commit properly scoped instead of touching the whole library. Verified with wide/side/extreme-stretch screenshots; headless tests green. Full reasoning in `DECISIONS_NEEDED.md`.

---

## 2026-07-17 (cont'd 2) — sponson_hull converted (item 5): folded the old standalone builder into build_afv_hull

`build_afv_hull`'s own `fender_frac`/`fender_height_frac` params already do exactly what `build_sponson_hull`'s hand-rolled blister boxes did, so this pass folded sponson_hull into a pure `build_afv_hull` parameter call (`fender_frac=1.15, fender_height_frac=0.38, upper_w=0.7`) instead of writing a second variant - gets it the tub/upper core split the spec asked for, plus a real, clearly-distinct sponson shelf (still the widest side-mount real estate in the ground roster), plus a real tier-1 bevel the old builder never actually applied (an incidental fix, not something specifically requested). `build_sponson_hull()` itself left in the file unused, since it's still a documented reference precedent for the fused-blister technique. Verified with wide/side/extreme-stretch screenshots; headless tests green. Full reasoning in `DECISIONS_NEEDED.md`.

---

## 2026-07-17 (cont'd 3) — naval_hull converted (item 6): real layered bridge superstructure

`build_ship_hull` gains a `superstructure_tiers` param that stacks N fused boxes of decreasing footprint (technique #1) instead of one flat bridge block - `naval_hull` now gets `superstructure_tiers=3` plus a `forecastle` freeboard step, reading as a genuine stepped destroyer bridge alongside the existing funnel/foremast, not a single box with greebles. `superstructure_tiers=1` (the default) reproduces the old single-box bridge exactly, so `small_boat_hull`/`heavy_cruiser_hull` are unaffected until their own punch-list items. Also added a `quarterdeck` param (unused for now, reserved for `heavy_cruiser_hull`'s item). Verified with wide/side/extreme-stretch screenshots; headless tests green. Full reasoning in `DECISIONS_NEEDED.md`.

---

## 2026-07-13 (new session, cont'd 5) — Shared decal/stencil atlas (hazard stripes, serial stencils, mascot icons) for all 10 factions

Built VISUAL_ART_DIRECTION.md section 1.4's shared decal library: hazard chevrons, stencil serial numbers, and a small per-faction mascot icon, wired to `decal_tint` (mirrors `detail_color`) and rendering on every faction's units - unlike last commit's greeble cards (5 factions only, deliberately silhouette-scale), decals apply to all 10 factions uniformly and stay genuinely small/detail-scale.

### The build

New `hull_decals.gd`, same procedural-at-runtime approach as the greeble cards: every shape (including the stencil serial number's actual digits, via a tiny hand-encoded 3x5 pixel font) is drawn into a small `Image` and cached - no hand-painted assets, no Blender pipeline dependency. Mascot icons were deliberately simplified to plain geometric crests (gear/hex/star/snowflake/diamond/cross/blade/leaf) rather than illustrated mascot creatures, per Chris's own invitation to simplify anything that would need real art quality - a detailed mascot at 48x48px procedural resolution would come out an unrecognizable blob.

### A real bug, found by actually looking at the screenshot

Every decal was invisible in-game despite the debug inspector confirming completely correct node/material/texture setup. Root cause: decals sat only 0.03 units above the hull's *nominal* catalog height, but the real authored `.glb` mesh has a small ridge detail proud of that nominal size - so the decal was physically buried under real geometry on most hulls. Fixed with a more generous proportional clearance, matching the greeble cards' already-successful approach. Also switched decal texture sampling to nearest-neighbor (linear filtering was blurring the small cutout shapes into soft blobs).

### Verification

93/93 automated tests green (1 new). Windowed screenshots across all 10 factions confirm mascot icons, hazard stripes, and stencil serials all actually render, read as genuinely different shapes per faction, and stay clearly detail-scale rather than fighting the silhouette.

---

## 2026-07-13 (new session, cont'd 4) — Alpha-cutout greeble/fin cards for 5 factions

Follow-up to a technical Q&A with Chris about whether the material system could fake silhouette-extending detail (it can't - normal maps/roughness/anisotropy only affect shading, never the true mesh outline) versus what would need real (cheap, non-collidable) extra geometry (alpha-cutout cards, same technique games use for cheap foliage). Chris green-lit building it for 5 specific factions.

### The build

New `hull_greebles.gd`: alpha-cutout textures are generated PROCEDURALLY at runtime (a small `Image` drawn pixel-by-pixel, wrapped in an `ImageTexture`) rather than hand-painted assets - zero new dependency on the Blender import pipeline, consistent with the rest of the faction system. 4 shapes (scrap zigzag, camo net lattice, hanging pennant, swept streamer fin), each generated once and cached, tinted per-faction like everything else.

- **Salvage Union** - 3 jagged scrap-antenna zigzags scattered across the roof at odd angles, in a high-contrast exposed-metal tone (their own dark worn paint color made the first pass nearly invisible).
- **Bayou Irregulars** - 2 broad camo-netting cards (top + side), breaking up the whole silhouette.
- **Crimson Concordat** - 2 hanging ceremonial banners trailing off the rear corners, past the hull's actual tail.
- **Aerodrome Cartel** - 2 swept art-deco tailfins, raked back.
- **Dune Runners** - 2 real water-barrel cylinders (not flat cards - a barrel needs to read as a solid volume from every angle) lashed along the flanks.

Every other faction (Industrialists/Technocrats/Expansionists/Glacier Syndicate/Ledger Combine) gets a genuinely empty greeble container - a deliberate, explicit exception to VISUAL_ART_DIRECTION.md's "goofy lives in detail-scale, never silhouette-scale" rule for these 5 specifically, not a reversal of it for all 10 (full reasoning in `DECISIONS_NEEDED.md`).

Wired into both hull-construction call sites (`blueprint_manager.gd`'s `reconstruct_vehicle()`, `module_placer.gd`'s `update_hull_appearance()`), scaled off the hull's real current footprint so a stretched/shrunk hull's greebles resize proportionally.

### Verification

92/92 automated tests green (1 new - every untreated faction confirmed empty, every treated faction confirmed exact expected child count/geometry type, re-theming replaces rather than accumulates, real spawn-pipeline check). Windowed screenshots: all 5 treated factions side by side with clearly distinct silhouette-extending shapes, all 5 untreated factions confirmed clean, individual close-ups of each treated faction.

---

## 2026-07-13 (new session, cont'd 3) — Rebuild against VISUAL_ART_DIRECTION.md + size-tiered manufactories

Chris commissioned a dedicated design pass (a design-focused agent, no code access) against the exact faction/UI brief from the previous session. Saved verbatim as `VISUAL_ART_DIRECTION.md` at the repo root, then used it as the concrete reference for a real rework - not just a read-and-file-away.

### Shader rework (commit 609c93c)

Rewrote `hull_faction_material.gdshader` to the doc's 13-parameter model (base/accent/detail color, metallic/roughness/anisotropy/brush_scale, wear/grime, edge highlight, emissive, mottle). Real technical fixes along the way, not just parameter renames:
- **World-space sampling fix** - the first version's noise used local/object-space `VERTEX`, which doesn't stretch when a Design Lab hull_scale slider stretches the hull, meaning the pattern would smear/enlarge instead of repeating more (exactly the failure mode the doc warns about). Fixed with a `world_pos` vertex-shader varying; verified with a real screenshot showing a 3x-stretched hull's panel-line grid repeating 3 times, not blurring.
- **Curvature-approximated wear** (`fwidth(world_normal)`) instead of pure noise - reads as edges/corners weathering first, like the doc's baked-curvature-mask intent, without needing a real per-mesh bake pipeline (deliberately skipped given how fragile the Blender import pipeline has been all week - see DECISIONS_NEEDED.md).
- A world-space panel-line/rivet grid gives every faction the shared "kit of parts" look, doubling as where `accent_color` shows.
- Godot's built-in `ANISOTROPY`/`ANISOTROPY_FLOW` shader outputs give the brushed-metal directional highlight.

### Faction roster replaced with the design-approved 7 (same commit)

Swapped last commit's invented 7 factions (Scavengers/Zealots/Nomads/Cartel/Engineers/Berserkers/Cybernetics) for the doc's real 7: **Salvage Union** (-10% metal cost), **Crimson Concordat** (weapon DPS ramps up as the unit nears death - a genuinely new per-tick mechanic in `auto_weapon.gd`), **Glacier Syndicate** (negates half of any active terrain speed penalty), **Dune Runners** (+15% harvest rate), **Ledger Combine** (-15% build time), **Bayou Irregulars** (shrinks the distance at which enemies can spot this unit - a new per-construct-faction hook in `skirmish.gd`'s fog-of-war), **Aerodrome Cartel** (+15% speed, airborne units only).

Found and fixed a real UI regression along the way: 10 factions' longer names (vs. the old 3) tipped the Design Lab sidebar's faction dropdown 4px past its fixed width - caught by the existing UI overflow audit test, fixed with `clip_text`.

### Size-tiered manufactories (commit 6aedf86)

Chris corrected an earlier land/sea/air shipyard/airfield idea in favor of production gated by hull WEIGHT tier instead - a small boat and a light ground hull both only need the Light Manufactory. New `ModuleCatalog.get_hull_size_tier()` splits the 12 mobile hulls into even light/medium/heavy groups (breakpoints and full mapping in `DECISIONS_NEEDED.md`); the single old "factory" prefab became 3 (`light_manufactory`/`medium_manufactory`/`heavy_manufactory`), all pre-built at match start (not an unlockable progression - see decision log for why), with real tier-gated production in both the player's build-bar flow and `enemy_ai.gd`. Caught and fixed a real balance side-effect: starting static buildings grew from 3 to 5, which silently pushed every match into Energy deficit at frame one until `ENERGY_HQ_BASELINE_CAPACITY` was retuned (10 -> 16).

### Verification

91/91 automated tests green across all three pieces (rewrote the faction-specific tests for the new parameter names/faction ids/mechanics, added a dedicated manufactory-tier test). Windowed screenshots: all 10 factions' identical hull mesh with distinct paint/wear/trim, the stretch-invariance proof, and the 3-manufactory base cluster with its build-bar buttons.

Other building variety Chris flagged (generator/power-plant, radar/comms, repair depot) logged as real next-increment candidates in `DECISIONS_NEEDED.md` rather than built this pass.

---

## 2026-07-13 (new session, cont'd 2) — Faction visual identity system + 10-faction expansion

Big pivot from Chris: from mechanics-only work into real visual polish, plus expanding the faction roster from 3 to 10. Three pieces, each committed separately.

### 1. Shader-based faction material system (commit 1e17628)

New `shaders/hull_faction_material.gdshader` - ONE spatial shader shared across every faction and every armor material, replacing two identical StandardMaterial3D-per-armor-material blocks that had been copy-pasted between `blueprint_manager.gd` and `module_placer.gd`. Faction (paint color + procedural wear/patina, no texture assets - a value-noise grunge mask instead) and armor material (metallic/roughness/shield character) are independent shader parameters, consolidated behind one shared `hull_material_builder.gd`. Chris's explicit steer: avoid hand-authored per-faction art given how fragile the Blender import pipeline has been all week - a shader took that risk off the table entirely. `energy_shielding`'s glow now tints to whichever faction wears it instead of a hardcoded blue, a nice side-unification.

**Real regression found and fixed while verifying:** `battle_unit.gd`'s `_flash_hull()` and `player_vehicle.gd`'s equivalent both assumed the hull's `material_override` was a `StandardMaterial3D` and read/wrote `.albedo_color` directly for the "flash red on hit" feedback - silently broken (null-property errors) the instant hulls switched to the new ShaderMaterial. Fixed with a `flash_amount` shader uniform and a material-type branch in both call sites.

### 2. 10-faction roster (same commit)

New `faction_catalog.gd` is the single source of truth (visual identity + mechanical passive) for all 10 factions, replacing scattered `if faction == "technocrats": ...` branches duplicated across 6 files. 7 new factions, each with one small real bonus hooked into the actual gameplay system it touches (not just a Design Lab stat preview): **Scavengers** (-10% metal cost, baked into roster entries once faction is known), **Zealots** (+10% weapon DPS / -10% max HP, in `auto_weapon.gd`/`battle_unit.gd`'s real HP calc), **Nomads** (+15% harvester extraction per tick), **Cartel** (+8% weapon fire_range), **Engineers** (-15% factory build time, both player and enemy_ai queue paths), **Berserkers** (+10% speed / -10% vision), **Cybernetics** (+20% Energy capacity). `Factions_and_Buildings.md` documents all 7 in the existing Aesthetic/Passive Bonus/Playstyle format.

### 3. Brushed-aluminum UI chrome (commit 6c2d5ca)

New `shaders/brushed_aluminum_panel.gdshader` (2D counterpart to the hull shader, same procedural-noise approach) + `ui_theme.gd`'s single `apply_brushed_panel()` helper, applied to MainMenu/MapSelect backgrounds, the Design Lab sidebar panel, the Skirmish HUD's top info bar + build bar, and MatchSetup's background (which live-retints the instant the player changes their faction dropdown selection - the clearest possible proof the theme is faction-driven).

### Verification

89/89 automated tests green (3 new this batch: a material/shader test proving all 10 factions share one shader with correct params including a real reconstructed hull, a UI-theme test proving live re-theming through a real dropdown interaction, and a mechanical-bonus test proving Zealots/Cartel/Cybernetics/Scavengers' passives through real spawned units and team economy calls - not just catalog numbers). Windowed screenshots: 5 factions' identical `medium_hull` mesh side by side with visibly distinct paint+wear, and 6 screen/faction combinations showing the UI chrome shift color.

Scope calls (why battlefield.gd's separate HP formula wasn't touched, why UI theming stopped at panel backgrounds rather than re-skinning every widget, why the pre-existing industrialists armor-weight bonus's real-vs-cosmetic scope was left alone) logged in `DECISIONS_NEEDED.md`.

---

## 2026-07-13 (new session, cont'd) — Full Skirmish pre-match settings flow

Second half of this session's batch: a real pre-match settings screen, not just the Design Lab's per-vehicle faction dropdown.

### What changed

- **`match_config.gd`** (the existing map-selection autoload) gained `player_faction`/`enemy_faction`/`selected_blueprint_paths`/`ai_difficulty`/`starting_metal`/`starting_crystal`, every one with an "unset" sentinel that reproduces the exact old hardcoded behavior.
- **`skirmish.gd`** reads all of these the same defensive way `selected_map_id` already was - a faction override skips the old "derive from `roster[0]`'s own faction tag" heuristic; `selected_blueprint_paths` replaces the automatic "newest 8 saved designs" heuristic when non-empty (bundled defaults still fill remaining roster slots either way); starting resources override the flat 450/150 default.
- **`enemy_ai.gd`** gained real AI Difficulty scaling (Easy/Normal/Hard) - production/wave timers and the pity-resource trickle all scale by a real multiplier, not a cosmetic label. See DECISIONS_NEEDED.md for why "configurable enemy/team count" got scoped down to this instead of true N-team support.
- **New `MatchSetup.tscn`/`match_setup.gd`** - `MapSelect.tscn`'s map button now routes here instead of straight to `Skirmish.tscn`. 4 dropdowns (Your Faction/Enemy Faction/AI Difficulty/Starting Resources) plus a real scrollable Blueprint Library checklist (the player's actual saved designs, pulled via `blueprint_manager.gd`'s own `list_blueprints()`) with checkboxes - check none to keep the old automatic roster behavior, check specific ones to import exactly those. "Start Match" writes every selection into `MatchConfig` and continues to `Skirmish.tscn`, same relay pattern the map choice already used.

### Verification

86/86 automated tests green (1 new - a single consolidated test proving every MatchConfig override field actually reaches a real Skirmish instance, including a deterministically-created test blueprint proving the import mechanism works regardless of the real environment's saved-design folder contents, and `enemy_ai.gd`'s own timers measurably changing under "hard"). Windowed screenshot of the new `MatchSetup.tscn` screen confirms every control renders and the Back/Start Match buttons stay visible regardless of blueprint list length (learned from `MapSelect.tscn`'s earlier overflow bug - this screen's button row was built outside the scrolling list from the start, not retrofitted).

This wraps both halves of the batch Chris queued (map variety + pre-match settings). Full session total: 86/86 tests, 8 skirmish maps, 3 new terrain mechanisms (bridges/urban buildings/vision LOS), and a real pre-match settings flow.

---

## 2026-07-13 (new session) — Map variety batch: bridges, urban buildings, real vision LOS, 4 new maps

Picked up after a prior session got stuck on a blocking prompt with no one able to dismiss it (Chris was traveling). Checked first whether the map/terrain "bridges and cities can be data" exploration that session had reportedly confirmed was ever committed: it wasn't - `git log`, `PROGRESS.md`, and `DECISIONS_NEEDED.md` all show the batch ending at Batch E item 5 (omni_wheels), with nothing about bridges/cities anywhere, no stash, no uncommitted script changes. That analysis (if it happened at all) never left the stuck session's own context - starting the batch fresh here, not recovering anything.

### New terrain mechanisms (commit 82f6419)

- **Bridges** - a new `map_catalog.gd` "bridges" field carves a walkable strip through a `water_areas` hole in the ground navmesh only (naval/amphibious/deep-water maps untouched - boats still float and pass underneath, same as a real river bridge). Real deck+railing visual; `terrain_height_at()` reports the deck height so crossing units don't render underwater.
- **Urban buildings** - `obstacles` gained a `type` field (`"rock"` default / `"building"`) - the latter a single boxy structure with a flat roof and window greebles, real taller collider, distinct silhouette from the existing boulder-jumble rock clusters.
- **Real vision line-of-sight** - `skirmish.gd`'s fog-of-war was pure distance math with zero occlusion check, ever. Added a real raycast (`_has_line_of_sight()`, collision layer 1 - the same layer `auto_weapon.gd`'s weapon-fire LOS check already used) so obstacles/buildings are now genuine cover for VISION too, not just movement/weapons - a free upgrade for every existing rock-cluster obstacle on every existing map, not just the new city map.

3 new tests (81 total after this commit).

### Four new maps, one at a time, each screenshot-verified

- **Twin Bridges** (commit 6432b84) - the new LARGEST map (half_extents=100). A river spans the map's entire width edge-to-edge with exactly two bridges crossing it, well apart - a genuine multi-lane bottleneck distinct from `highland_chokepoint`'s single hill-lane design.
- **Twin Summits** (commit f961879) - "two contested points" as its own pattern, not a rehash of `highland_chokepoint`'s one dominant hill: two separate hills, each closer to one side's own territory, fair only as a mirrored pair.
- **Close Quarters** (commit 62b9788) - the new SMALLEST map (half_extents=45). Two rock walls split it into a real 3-lane bottleneck (west/center/east), distinct from highland's 2-lane design. Deliberately resource-sparse - built for early aggression, not economic buildup.
- **Urban Sprawl** (commit b802059) - an 8-building street grid between the two bases using the new "building" obstacle type; real cover blocking movement, weapons, AND sightlines. A resource sits in the central plaza specifically because it's hidden from both bases until scouted.

Each map got its own smoke test (legal start points, every resource reachable, HQs mutually reachable, factory production works) plus real windowed top-down + in-scene screenshots before moving to the next, same discipline as the original 4-map batch. Final count: 85/85 automated tests green, 8 maps total in the roster.

Judgment calls (bridge naval passability, LOS eye-height approximation, is_position_blocked left blocking bridge decks for building placement, why these 4 specific maps) logged in `DECISIONS_NEEDED.md`.

---

## 2026-07-13 — Batch E item 5 (final): omni_wheels with real lateral strafing - Batch E complete

Chris's batch, item 5 (last item): real mecanum/omni-wheel locomotion - genuine sideways movement, not just a new mesh, requiring real steering code changes.

### The build

New locomotion type `omni_wheels` (mecanum-style wheel visual with diagonal rollers) plus a new `is_omni` flag/trait that gates a branch in `battle_unit.gd`'s `_steer_towards()`: every other locomotion type couples facing to travel direction (rotates the hull, then moves along its own forward); the omni branch sets velocity directly toward the destination and never touches hull rotation - reusing the decoupled-rotation-vs-velocity pattern `_kite_reposition()` already established for facet-aware kiting. Stat-wise it's a tradeoff, not an upgrade: lower thrust/capacity than plain wheels and a worse terrain-multiplier row across the board - the strafing capability is the payoff.

**Verified:**
- Full suite: **78/78 green** (1 new: spawns an omni unit and a plain wheels unit side by side, orders both to a purely-sideways destination, and proves the omni unit holds its facing (<0.05 rad rotation change) while genuinely out-pacing the wheeled unit (which has to turn first) toward the same target over the same tick count - a real behavioral proof, not a visual-only check).
- Visual: `progress_captures/2026-07-13/omni_wheels/` - diagonal roller ring distinct from a plain wheel_hub.

**Batch E is now complete** - all 5 items (hull-relative locomotion scaling, wheels/legs/treads tweak mechanics, ornithopter wings, rhomboid treads, omniwheels) shipped and verified. Final wrap-up (full suite re-run, doc review) next.

**Commit checkpoint:** see git log.

---

## 2026-07-13 — Batch E item 4: rhomboid_treads, a new MkIV full-body-loop track type

Chris's batch, item 4: WWI Mark IV-style tank track where the loop wraps up and over the entire body, not just flanking the bottom sides like `tracked_treads`.

### The build

New locomotion type `rhomboid_treads` - a procedural loop of 22 track-link plates traced around an ellipse tall enough to genuinely extend above/below the hull, plus idler drums at the fore/aft turning points. Mounted centered on hull height (not `tracked_treads`' low bias). Gave it its own stat profile too, not just new geometry: higher weight capacity (900 vs 700) but a below-default thrust coefficient (95 vs 150) - tougher but slower, plus better marsh/snow_mud terrain handling and worse rocky handling than `tracked_treads`. Reuses the width-tweak tradeoff mechanism built for tracked_treads earlier this batch.

**Verified:**
- Full suite: **77/77 green** (1 new: real spawn count, direct stat comparison proving the tougher-but-slower tradeoff, terrain-multiplier comparison).
- Visual: `progress_captures/2026-07-13/rhomboid_treads/` - clearly towers above the hull vs. `tracked_treads` staying flush.

**Commit checkpoint:** see git log.

---

## 2026-07-13 — Batch E item 5: ornithopter_wing, a new flapping-flight locomotion type

Chris's batch, item 5: flapping-wing flight, distinct from `fixed_wing_engine` (prop/jet) and `buoyant_envelope` (airship), same "no aerodynamic lift simulation" standing rule.

### The build

New locomotion type `ornithopter_wing` (judgment call: own type, not a variant/module - see DECISIONS_NEEDED.md), `traits: ["airborne", "flapping_wing"]` (no `"fixed_wing"`, so it reuses the existing simple hover-arrival movement `helicopter_rotors`/`hover_engine`/`anti_grav` already share - no new physics code needed). Bat/pterosaur-style angled membrane visual with a `WingPivot` node that `battle_unit.gd` oscillates each physics tick for a real flapping motion.

**Verified:**
- Full suite: **76/76 green** (1 new: real spawn count + trait check + scripted flap-oscillation check).
- Visual: `progress_captures/2026-07-13/ornithopter_wing/` - reads as a distinctly bat-like silhouette on `flying_wing_hull`, clearly differentiated from the other two flight types.

**Commit checkpoint:** see git log.

---

## 2026-07-13 — Batch E items 2-4: wheels/legs/treads tweaks now have real, tradeoff-shaped stat effects

Chris's batch, items 2-4: axle-count, leg-count, and tread-width tweaks needed to actually move stats, not just geometry.

### What was found

Wheels' axle-count was already fully wired (visual + stat). Legs' leg-count was visual-only (no stat effect). Treads' width boosted thrust and capacity together - not the "wider=more capacity/narrower=faster" tradeoff asked for.

### The fix

Split the shared `count_contrib` in `battle_unit.gd`'s `_recalculate_move_speed()` into separate `thrust_contrib`/`capacity_contrib` per type. Legs: more legs = more capacity, fewer legs = more thrust (agility tradeoff). Treads: width still drives capacity, but now ALSO drives thrust inversely (narrower = faster) and modulates the terrain-multiplier penalty directly (wider = less severe marsh/snow/sand penalty).

**Verified:**
- Full suite: **75/75 green** (1 new test - real spawned-instance counts via `module_placer.gd`, plus light-load/heavy-load stat scenarios proving the tradeoff actually flips the speed ranking depending on load, plus a terrain-multiplier check).
- Visual: `progress_captures/2026-07-13/tweak_mechanics/` - wheels 2 vs 8, legs 2 vs 8, treads width 0.5 vs 2.5.

**Commit checkpoint:** see git log.

---

## 2026-07-13 — Batch E item 1: locomotion visuals now scale relative to hull size

Chris's next batch, item 1: fix the scale mismatch flagged (not fixed) in the visual bug pass below - locomotion visuals were built at a fixed absolute size regardless of the hull they're mounted to (giant legs on `flying_wing_hull`, tiny `helicopter_rotors` on `heavy_cruiser_hull`).

### The fix

Two hull-relative scale factors computed once per `update_locomotion()` call in `module_placer.gd`, benchmarked against `medium_hull`'s size (`ModuleCatalog.REFERENCE_HULL_SIZE`): a **height factor** for parts that should track ground clearance (wheel radius, leg length), and a **footprint factor** for parts that should track overall bulk (rotor span, hover/anti-grav pad size, engine pod size, prop size). Both clamped to `[0.45, 2.25]`. `tracked_treads`/`screw_drive` already scaled their length off real hull Z and didn't need this.

### Bug surfaced and fixed along the way

The verification check caught `helicopter_rotors` rendering falsely clipping-red on a wide hull - a pre-existing latent bug (locomotion_group clipping exemption is assigned after the per-instance clipping checks already ran during placement) that bigger hull-relative parts made much more likely to actually trigger. Fixed with one more `check_all_clipping()` call at the end of `update_locomotion()`, after the group meta is set.

**Verified:**
- Full suite: **74/74 green** (1 pre-existing test's hardcoded expected leg scale updated to the new hull-relative value - not a regression, see the comment on `test_design_to_battle_integration`).
- Numeric: scale factors read directly off spawned instances for 3 hull types matched hand-calculated expectations exactly.
- Visual: `progress_captures/2026-07-13/hull_relative_scaling/` - legs on `medium_hull` vs `flying_wing_hull`, rotors on `medium_hull` vs `heavy_cruiser_hull`.

**Commit checkpoint:** see git log.

---

## 2026-07-13 — Systematic visual bug pass: locomotion mounting gaps fixed on ship/airship hulls

Chris asked for a real, systematic visual audit across the module/hull library (not spot-checking) - locomotion orientation, mounting gaps, floating parts, checked broadly across hull x locomotion combinations since the no-hard-gating philosophy means players can and will try unusual pairings.

### Method

Rendered 24 locomotion x hull combinations in one windowed pass (every locomotion type on its natural hull + deliberately weird cross-combos) and actually reviewed every screenshot, not just the placement math.

### What was found

Both `wheels`/`legs`/`hover_engine`/`anti_grav` (underside-mounted locomotion) and `naval_propeller` (stern-mounted) assume a hull's visual mesh fills its collision box symmetrically - true for every wedge/box hull, false for the 3 ship hulls (whose keel intentionally sits shallower than the box and doesn't reach the true stern edge) and `airship_hull` (an ellipsoid, narrower at the sides than the box implies). Locomotion mounted on these 4 hulls floated visibly below/behind the real mesh. Notably, this hit `naval_propeller` on `naval_hull` - the hulls' own NATURAL, purpose-built pairing - not just nonsensical combos.

### The fix

A new `underside_y_bias` catalog field (0.0 default, nonzero only on the 4 affected hulls, values derived from `build_ship_hull`'s own keel-depth constant for the 3 ship hulls) raises the underside mount point to match where the hull's real mesh actually is. `naval_propeller`'s stern position moved off the exact box edge to where the keel still has real depth. Iterated the naval_propeller fix twice against real renders before it looked properly attached.

### Also checked, found clean

Weapon/module mounting on the newer hull surfaces (naval hulls' sloped bow, airship's curved envelope, fuselage's cylindrical body) - already correct, since the pintle base-plate system was built around real surface normals from the start.

### Deliberately not fixed (logged, not silently dropped)

Locomotion visuals having a fixed absolute size regardless of hull dimensions causes real proportion mismatches on extreme hull sizes (giant legs on paper-thin wings, tiny rotors on a huge cruiser) - a genuine visual issue but a different category (scale, not gap/orientation), and fixing it properly would mean retrofitting every locomotion visual's scale logic - out of scope for this pass. Also didn't chase pixel-perfect attachment on combos nobody would seriously design around (wheels on a boat/blimp) once they were "no longer floating in obvious empty space."

### Verification

74/74 tests green (1 new - a real end-to-end check that wheels/naval_propeller mount measurably differently than the old buggy formula, through the actual `module_placer.gd` code path). Before/after screenshots for every fixed combo in `progress_captures/2026-07-13/visual_bug_pass/`.

Full reasoning in `DECISIONS_NEEDED.md`.

---

## 2026-07-13 (cont'd 2) — Final verification: terrain variety batch

Wraps up the terrain variety batch (surface speed multipliers + hull-draught shallow water blocking - see the two entries below this one).

**Full regression pass:** 73/73 automated tests green, including 6 new tests added across this batch - the core marsh/rocky/snow_mud/sand differentiation (real physics-tick movement comparison), the deep-water navmesh block (raw path-connectivity check), and the `battle_unit.gd` routing check (`heavy_cruiser_hull` vs. `small_boat_hull` land on different nav maps through the real `setup()` path).

**All 5 terrain pieces verified with real in-game screenshots** (not just passing tests) - marsh, rocky, snow_mud, and sand on `open_plains`, shallow water on `coastal_strand` - camera positioned over each zone in the actual running Skirmish scene, one at a time.

No blocking issues. Every piece Chris asked for is implemented: marsh/swamp (favors screw_drive, punishes wheels/treads), rocky (favors legs), deep snow/mud (bogs wheels hard, treads handle it), soft sand (wheels struggle, treads/legs better, hover/anti-grav structurally immune), and hull-draught shallow water (a real navmesh block, not a speed penalty, since Chris specifically called out that distinction).

---

## 2026-07-13 (cont'd) — Terrain variety made real: zones added to open_plains + coastal_strand

Second half of the terrain variety batch - the mechanism from the previous entry now lives in two real, playable maps instead of just synthetic tests.

### open_plains gets marsh/rocky/snow_mud/sand

Placed as two diagonal pairs out toward the map edges (`|x| >= 39`), clear of the existing resource cluster and both bases - the overall 4-zone arrangement is 180-degree point-symmetric (matching this map's existing fairness convention) while each player still has one of every terrain type within reach, not just a mirrored copy of a single type. Rocky terrain gets small non-collidable rock-bump decorations on top of its color patch so it visually reads as genuinely uneven ground, not just a tinted rectangle.

### coastal_strand gets a shallow coastal shelf

A `shallow_water_areas` strip along the immediate shoreline (real bathymetry logic - shallow near shore, deep further out) blocks `heavy_cruiser_hull` from the last ~10 units of water before the beach entirely, while `small_boat_hull`/`naval_hull`/amphibious `screw_drive` can work right up to the shore.

### Verification

Both map smoke tests (which already check resource reachability, legal start points, HQ connectivity, factory production) still pass unchanged with the new zones added, confirming they don't interfere with anything already there. All 5 pieces (marsh, rocky, snow_mud, sand, shallow water) confirmed visually with real in-game Skirmish screenshots, camera positioned over each zone in turn. 73/73 tests green (unchanged from the mechanism entry - map content doesn't need its own dedicated tests, the mechanism-level tests already cover the underlying behavior).

Screenshots: `progress_captures/2026-07-13/terrain_variety/`.

---

## 2026-07-13 — Terrain variety mechanism: surface speed multipliers + hull-draught shallow-water blocking

New batch: build out terrain types that genuinely differentiate locomotor types (marsh/rocky/snow_mud/sand) plus hull-draught-based shallow water passability. This entry covers the core mechanism; real map zones + screenshots are a following entry.

### Surface speed multipliers (marsh/rocky/snow_mud/sand)

New `surface_zones` map data shape (`{center, half_extents, surface_type}`), a pure-function query (`TerrainBuilder.get_surface_type_at()`), and a per-locomotor-type x per-surface-type multiplier table (`ModuleCatalog.TERRAIN_SPEED_MULTIPLIERS`/`get_terrain_speed_multiplier()`). `battle_unit.gd` recomputes a `terrain_speed_multiplier` every physics tick from the unit's current position and applies it wherever velocity is actually set - `move_speed` itself (the design-time stat) is untouched. Airborne locomotion types never consult this at all (they already skip ground navigation via `is_flying`), which is the actual mechanism behind "hover/anti-grav ignore terrain."

Tuned per real-world handling: marsh favors `screw_drive` (1.1x, a genuine bonus) and punishes `wheels` (0.25x); rocky favors `legs` (1.1x) over `wheels` (0.35x); snow_mud and sand both favor `tracked_treads` (0.8x/0.85x) hardest over `wheels` (0.2x/0.3x).

### Hull-draught shallow water blocking

A genuinely different mechanic per Chris's framing - a new `deep_water_map` (built alongside the existing ground/water/amphibious maps) treats `shallow_water_areas` as real navmesh holes, so a deep-draught hull has NO route through shallow water at all, not just a speed penalty. New `draught` catalog field on the 3 naval hulls (`small_boat_hull` 0.35, `naval_hull` 0.9, `heavy_cruiser_hull` 1.8) and a `SHALLOW_WATER_DRAUGHT_THRESHOLD` (1.0) - only `heavy_cruiser_hull` exceeds it and gets routed to the blocked map.

### Verification

Real physics-tick movement comparison (140 ticks, same pattern the existing lake-crossing pathfinding test already used), not catalog-number checks alone - caught and fixed a real test-methodology bug along the way (a synthetic unit with no floor collision free-falls indefinitely, which measurably distorted movement distance until the test's fake controller also got a flat-ground `terrain_height_at()`). Draught blocking verified both at the raw navmesh level (a shallow strip splitting a lake has no deep-water route across) and the real `battle_unit.gd` routing level. 73/73 tests green (4 new).

Full reasoning (including why marsh stays a speed penalty rather than a hard block, unlike shallow water) in `DECISIONS_NEEDED.md`.

---

## 2026-07-13 (cont'd 2) — Final verification: air/sea hull + module library expansion

Wraps up the air/sea library batch (4 hulls, 2 locomotion types, 6 mobility modules - see the two entries below this one).

**Full integration check**, not just the individual per-piece verifications: `airship_hull` + `buoyant_envelope` locomotion + `wing` + `ship_screw` modules placed together through the real Design Lab UI path in one design, confirming all three new-this-batch systems (buoyant/amphibious locomotion, mobility-bonus modules, the new hull) compose without conflict - 2 locomotion children (the buoyant_envelope pair) and 2 other module children (wing, ship_screw) all present simultaneously, real aggregated stats (155 HP, 96 weight, 95 metal/40 crystal). Screenshot: `progress_captures/2026-07-13/final_air_sea_batch/airship_buoyant_wing_screw.png`.

**Final regression pass:** 70/70 automated tests green, including all 3 new tests added across this batch - per-hull verification didn't need dedicated tests (it's pure content), but every new mechanic did: the amphibious navmesh (a real path-length comparison proving water is genuinely crossable), the two new locomotion types' catalog differentiation (buoyant_envelope's thrust/capacity character vs. fixed_wing_engine, screw_drive's real spawn + trait composition), and the mobility-module capacity/thrust bonuses (an intentionally overloaded baseline so the bonus shows through unclamped).

No blocking issues across the whole batch. Total new catalog entries this batch: 4 hulls, 2 locomotion types, 6 modules - 12 new placeable parts, all real spawn-pipeline verified.

---

## 2026-07-13 (cont'd) — Air/sea library expansion, part 2: 6 new mobility modules

Second half of the air/sea batch: attachable mobility modules that hook into the weight-capacity/thrust systems built two sessions ago, rather than full locomotion types.

### The 6 modules

- **`wing`** - flat swept panel, no aerodynamic simulation (explicitly out of scope per the task) - grants a flat `weight_capacity_bonus` (150) to whatever it's attached to.
- **`thruster`** - generic jet/rocket nacelle (no visible blades), `thrust_bonus` 60.
- **`propeller_prop`** / **`pusher_prop`** - share one mesh-building function (`_build_propeller`, a `pusher: bool` flag flips which end of local Z the hub/blades face), same `thrust_bonus` (70) - the ask was a visually distinct orientation, not a different mechanic.
- **`paddle_wheel`** - steamship-style side-mounted disc with radiating paddle blades, `thrust_bonus` 65.
- **`ship_screw`** - a genuinely twisted/pitched blade propeller (each blade rotated about its own length axis before the radial sweep), `thrust_bonus` 75 - checked first whether this would just be `naval_propeller` under a different name; it isn't (naval_propeller's existing visual is flat blades, not pitched, and it's the primary locomotion choice rather than a stackable module).

### Mechanical hook

`battle_unit.gd`'s `_recalculate_move_speed()` now reads `weight_capacity_bonus`/`thrust_bonus` off ANY module (not just `category == "locomotion"`), scaled by the module's own size - a flat additive bonus on top of whatever the primary locomotion already provides, not gated to airborne/naval hulls only.

### Verification

New test proves a real, unclamped `move_speed` change from each bonus type using an intentionally overloaded baseline (so the effect isn't hidden behind the speed formula's clamp ceiling) - a `wing` measurably reduces the overload penalty, `thruster`/`propeller_prop` measurably add raw thrust. All 6 modules confirmed visually distinct up close. 70/70 tests green.

Full reasoning (including the `ship_screw` vs. `naval_propeller` differentiation check) in `DECISIONS_NEEDED.md`. Screenshots: `progress_captures/2026-07-13/new_mobility_modules/`.

---

## 2026-07-13 — Air/sea hull + locomotion library expansion, part 1: 4 new hulls, buoyant airship drive, amphibious screw drive

New batch: expand the hull/module library with an air and sea theme. This entry covers the hull and locomotion half; modules (wings, thrusters, props, paddle wheels, ship screws) are a following entry.

### 4 new hulls

- **`small_boat_hull`** - a fast patrol boat, naval_hull's smaller/sleeker sibling (sharper bow, ~55% the footprint).
- **`heavy_cruiser_hull`** - naval_hull's bigger/heavier sibling, layered superstructure, twin funnels, real warship bulk.
- **`fuselage_hull`** - a traditional plane: tapered fuselage tube + a separate attached wing slab, genuinely different from `flying_wing_hull`'s single blended-wing-body convex hull (no fuselage/wing break at all).
- **`airship_hull`** - a rigid dirigible: cigar/teardrop gasbag envelope, slung gondola on struts, tail fin cross. The only hull silhouette in the roster implying buoyant lift.

All four built via `tools/blender/build_meshes.py` (two new builder functions, `build_fuselage_hull`/`build_airship_hull`, plus two new size variants of the existing `build_ship_hull`), balance-checked (all land in the existing 0.69-0.86 hull value/cost band, no outliers), and verified one at a time with real 3/4-angle screenshots. See DECISIONS_NEEDED.md for a real "is it a bug?" detour on `heavy_cruiser_hull`'s first render (it wasn't a bug - the Design Lab's default camera angle just isn't representative).

### Buoyant airship locomotion

New `buoyant_envelope` locomotion type, deliberately NOT a reskin of `fixed_wing_engine` - an airship's lift is buoyancy, not thrust, so it gets its own catalog character: very high `base_weight_capacity` (1100, highest in the roster) and a new low `thrust_coefficient` (55.0). This required generalizing `battle_unit.gd`'s previously-hardcoded universal `150.0` thrust constant into a per-locomotion-type catalog lookup (`ModuleCatalog.get_thrust_coefficient()`), mirroring the `base_weight_capacity` pattern - every existing locomotion type is unaffected (same 150.0 default).

### Amphibious screw-drive locomotion

New `screw_drive` locomotion type - a real historical screw-propelled vehicle (twin helical auger drums, new authored Blender part) that drives on land AND crosses water using the same drums. This needed a genuinely new capability, not just a flag: `terrain_builder.gd` now bakes a third navmesh (`amphibious_map`, alongside the existing ground/water maps) where water is walkable terrain instead of a hole, and `screw_drive` carries a new `"amphibious"` trait that routes it there via a duck-typed `get_amphibious_nav_map()` (same pattern as the existing ground/water getters). Verified with a real path-length comparison proving the amphibious map lets a unit cross a lake directly while the ground-only map is forced into a detour - not just "no error was thrown."

### Verification

69/69 tests green (5 new this entry). A real RID leak this work introduced (a test that calls `build_navmeshes()` directly, bypassing Skirmish's own cleanup, hadn't been updated for the new amphibious map/region) was caught and fixed the same way past navmesh leaks in this project have been - by the test suite itself, not silently. Screenshots: `progress_captures/2026-07-13/new_air_sea_hulls/` and `progress_captures/2026-07-13/new_locomotion/`.

---

## 2026-07-13 (cont'd 2) — Final verification: pintle correction + traverse/range/weight batch

Wraps up the four-item batch Chris queued while the angled-pintle-mount work was mid-flight: the per-weapon-type pintle correction, traverse rate differentiation, range tweak coverage, and vehicle weight capacity - see the three entries below this one for each item's own detail.

**Full regression pass:** 66/66 automated tests green (headless), including the 2 new tests added this batch (`test_weapon_traverse_and_range_differentiation`, `test_weight_vs_locomotion_capacity_penalty`) plus the earlier pintle-correction test, none of which existed before this batch started.

**Live-game sanity check**, not just the test harness: spawned an `interceptor_hull` with a `ciws` and a `mortar_array` through the real Design Lab UI placement path (not synthetic mocks) at the same sloped-nose angle used for the original pintle-correction proof, confirming the whole pipeline - catalog data, mount-style resolution, weapon stat computation, and the Design Lab's own sidebar stats (Total HP/Weight/Cost/DPS) - still renders and computes correctly after touching three core shared scripts (`module_catalog.gd`, `auto_weapon.gd`, `battle_unit.gd`) that basically everything else in the game reads from. Screenshot: `progress_captures/2026-07-13/final_batch_verify/interceptor_ciws_mortar.png`.

No new blocking issues. All four items are code-complete, tested, documented, and committed.

---

## 2026-07-13 (cont'd) — Vehicle Weight now actually matters: per-locomotor-type capacity + overload speed penalty

Weight was a displayed stat with zero gameplay effect until now. Chris's ask: a per-locomotor-type formula for how much weight it's built for, with excess weight slowing the unit - heavier/tougher locomotion tolerates more before the penalty.

### What changed

- **`base_weight_capacity`** - new catalog field on all 8 locomotion types, reasoned from real-world load-bearing character: `naval_propeller` highest (800, buoyancy), `tracked_treads` (700, built for heavy armor), `legs` (500), `anti_grav` (450), `fixed_wing_engine` (380), `wheels` (350, fast but not built for heavy loads), `hover_engine` (300), `helicopter_rotors` lowest (250, real helicopters have a strict max-takeoff-weight).
- **`battle_unit.gd::_recalculate_move_speed()`** now sums a `total_weight_capacity` across whatever locomotion is actually present, scaled by the same size/count factors already used for `motor_thrust` (a 6-wheel setup or wider tread already carries more capacity, consistent with it already producing more thrust). If total vehicle weight exceeds that sum, a penalty multiplier applies on top of the existing thrust/weight speed formula: no penalty at or under capacity, `clamp(1.0 - (overload_ratio-1.0)*0.6, 0.25, 1.0)` beyond it (50% over costs 30% speed, 100% over costs 60%, floored at 25% so overload is punishing but never fully immobilizing).

### Verification

New test builds mock units (same "control the exact fields the function reads" approach as the existing `test_traverse_limit`) proving the differentiation directly: identical 400kg weapon added to a 50kg `wheels` chassis (450kg vs. 350 capacity) produces a real, measured penalty against the unpenalized formula prediction; the same weapon on a 120kg `tracked_treads` chassis (520kg vs. 700 capacity) produces zero penalty - the exact "heavier locomotion tolerates more" behavior that was asked for. 66/66 tests green.

Full per-locomotor reasoning and the penalty-curve judgment call logged in `DECISIONS_NEEDED.md`.

---

## 2026-07-13 — Weapon traverse rate is now per-type, and range/traverse tweak coverage is genuinely wired up

New batch from Chris: differentiate weapon traversal rates per type (tweaks should meaningfully move it, not just nudge it within a narrow uniform curve), and audit/fix weapon range differentiation.

### Audit first

`fire_range`'s BASE values were already well-differentiated per weapon type (9.0-50.0 across the roster) - Chris's suspicion there didn't hold up. The real gaps: (1) roughly half the weapon roster's own player-facing tweaks (cross-checked against `stat_calculator.gd`'s `TWEAK_SPECS`) had zero wiring to range at all - `gauss_railgun`'s only tweak never touched its own range; (2) `traverse_speed` was a single uniform `clamp(200.0/weight, 0.6, 6.0)` formula with no type-specific input whatsoever - two weapons of similar weight but opposite real-world handling (a point-defense tracker vs. a mortar) traversed identically.

### What changed

- **`traverse_agility`** - new catalog field per weapon type (multiplier, default 1.0), reasoned the same way `pintle_min_up_alignment` was: point-defense fastest (ciws 1.8), light autoguns quick (~1.2-1.3), guided missiles moderate (~0.8-0.9, since the warhead self-corrects), indirect/ballistic-arc weapons slowest (~0.5-0.6). Applied on top of the weight-driven base formula, which was widened from `clamp(0.6, 6.0)` to `clamp(0.4, 8.0)` to give the multiplier real room to differentiate.
- **Tweak-to-traverse coverage generalized** - previously only `barrel_length`/`elevation` moved traverse_speed directly; now every "part gets physically bigger" tweak does (`ModuleCatalog.LINEAR_SCALE_WEAPON_TWEAKS`, the same set `module_data.gd` already treats as weight-scaling), preserving the existing double-dip pattern rather than replacing it.
- **Tweak-to-range coverage extended** - 6 more tweak names wired into `fire_range` where physically sensible (`caliber`, `rail_length`, `seeker_size`, `ascent_thruster`, `pressure_valve`, `fuse_setting`), each reasoned individually; count-type and non-reach tweaks deliberately left alone.

### Verification

New test isolates each fix from its confounds: ciws vs. mortar_array at identical weight get different traverse speeds (proves the type multiplier, not weight, is responsible); `gauss_railgun`'s `rail_length` now measurably extends range (a tweak with zero other stat connection, so a clean proof); `heavy_machine_gun`'s `drum_size` now costs MORE traverse than the weight formula alone would predict (computed and compared against an explicit weight-only baseline). 65/65 tests green.

Full per-type reasoning logged in `DECISIONS_NEEDED.md`.

---

## 2026-07-12 (cont'd 16) — Pintle eligibility is now per-weapon-type, not one uniform angle rule

Follow-up correction from Chris on the angled-pintle work below: the sponson/pintle boundary shouldn't be a single geometric threshold applied to every weapon - some weapons realistically tolerate a pintle mount on a much steeper slope than others.

### What changed

`module_catalog.gd` gained a new catalog field, `pintle_min_up_alignment`, set per weapon type_id (17 weapons individually reasoned about, ranging 0.15 for compact/self-contained guns like `heavy_machine_gun` and `rotary_cannon` up to 0.55 for ballistic-arc weapons like `mortar_array` and `spigot_mortar` that need a near-level base to aim their arc). `get_mount_style_for_normal()` reads this via a new `ModuleCatalog.get_pintle_min_up_alignment(type_id)` accessor instead of the old flat constant, which is kept as `PINTLE_MIN_UP_ALIGNMENT_DEFAULT` for any weapon without an explicit entry.

### Verification

New test asserts `heavy_machine_gun` and `mortar_array` land on opposite mount styles at the identical slope - direct proof the system differentiates by weapon type rather than just having plausible-looking numbers. Also tightened a pre-existing test vector in `test_angled_pintle_mount()` that was uncomfortably close to the new `heavy_machine_gun` threshold. 64/64 tests green. Screenshot showing a machine gun pintle-mounted next to a mortar sponson-mounted, same hull, same slope, in `progress_captures/2026-07-12/pintle_per_weapon_type/`.

Full reasoning per weapon type logged in `DECISIONS_NEEDED.md`.

---

## 2026-07-12 (cont'd 15) — Angled pintle mount: gun-on-a-stand now works on sloped surfaces, not just a flat top

Design correction from Chris after seeing the pintle mount demo: it should work on angled surfaces too - a sloped glacis plate (interceptor_hull's nose was the example), not just a mathematically flat deck.

### What changed

Previously, `module_placer.gd` only skipped weapon reorientation (keeping it "level") when the placement normal was within ~0.03 degrees of dead vertical - anything else fell through to the generic surface-alignment code and tilted the WHOLE weapon to match the slope. Now: `module_catalog.gd` has a new continuous check, `get_mount_style_for_normal()` - any surface with `dot(normal, UP) >= 0.3` (surfaces sloped up to ~72.5 degrees from horizontal) resolves to a pintle-style mount and the weapon stays level; only the last ~17.5 degrees approaching a true vertical wall still falls back to the embedded sponson. The old discrete `get_mount_style(type_id, facet, hull_type_id)` stays as a thin wrapper (still used by `get_traverse_limit_angle()`, which only needs the turret/frame_built gate) delegating to the new function via a representative normal.

The tilt itself now lives in a new base plate (`visual_builder.gd`'s `_build_pintle_base_plate()`) instead of the weapon: `Quaternion(Vector3.UP, surface_normal)` orients a greebled disc (bolt ring + raised center hub) to match the real local surface, embedded slightly backward into the hull skin rather than floating flush against it. The post and weapon are completely unaffected by this tilt - the post stays local-space vertical (unchanged code), and since the weapon's own rotation is never touched for a pintle-eligible mount, "local vertical" for the post is also world-vertical.

### Persistence

Added `mount_normal` alongside the existing `mount_style` in both `serialize_hull()` and `reconstruct_vehicle()` - without it, a saved glacis-mounted weapon would silently flatten back to a level plate on reload, since `rebuild_visual()` had no other source for the original placement angle.

**Verified:** 64/64 tests green (1 new - continuous-threshold checks at 45°/near-vertical/pure-side, a real angled placement staying level with a correctly-tilted-and-embedded plate, the post remaining unrotated, and the tilt surviving a save/reconstruct round-trip). Windowed screenshots of a rotary_cannon mounted on interceptor_hull's sloped nose in `progress_captures/2026-07-12/angled_pintle_mount/`.

---

## 2026-07-12 (cont'd 14) — Four Skirmish maps built on the new architecture, each verified one at a time

Built the actual map content on top of the multi-map architecture from the previous entry: `open_plains`, `highland_chokepoint`, and `coastal_strand` (new), plus `lake_crossing` (the original map, re-verified on the refactored code path). Each map covers a genuinely different play pattern rather than being a palette swap, per Chris's instruction.

### The four maps

- **Open Plains** - no water, no elevation, no obstacles, tighter (70 vs 80 half-extents), resources pulled toward the contested center. The "nothing to hide behind" baseline.
- **Lake Crossing** - unchanged (a single lake splits the map; naval-vs-ground routing).
- **Highland Chokepoint** - landlocked, a single dominant hill (real vision + combat bonus for holding it) flanked by rock walls that narrow the map to two lanes. The hill uses two `elevation_zones` sharing one footprint (north ramp + south ramp) so both teams get equally fair access to the top.
- **Coastal Strand** - water runs the full length of one edge instead of sitting centrally, giving naval units real open water; the most obstacle-dense of the four, including a rock cluster sitting squarely on the direct HQ-to-HQ line.

### Symmetry, chosen per map

`lake_crossing`/`open_plains`/`highland_chokepoint` mirror every position through the map origin (180-degree point symmetry) since their terrain is itself point-symmetric. `coastal_strand` mirrors north/south instead, since its terrain is deliberately asymmetric east-west (water only borders one side) - point symmetry there would have put a "safe" resource in the ocean.

### Two more real bugs, found by the verification process itself

1. **`highland_chokepoint`'s smoke test failed on the first run** - the player factory's start position turned out to sit on the hill's ramp footprint, which `is_position_blocked()` correctly rejects. The bug was in my own hand-calculation of how far the ramp's *padded* footprint reaches (see the previous entry's Recast-winding-fix `RAMP_PAD`) - grid-snapping always rounds the padding boundary *outward*, so the real blocked zone is noticeably bigger than a naive estimate. Fixed by pushing that map's base positions back with real margin, confirmed by the automated smoke test rather than more hand math.
2. **The map-select screen silently overflowed off both the top and bottom of the viewport** once all 4 maps existed - invisible with just 1 map present, since a screen-centered `VBoxContainer` only overflows symmetrically once its content actually exceeds the viewport height. No automated test covers this screen. Caught by the mandatory screenshot check before calling the batch done; fixed with a `ScrollContainer`, the same pattern the build bar already uses.

### Verification, one map at a time

Each map got its own top-down + in-scene windowed screenshot pair, plus a real scripted smoke test (`_smoke_test_map()`) - legal/unblocked start points, every resource node reachable by ground navmesh from its own side, the two HQs mutually reachable (no map accidentally splits the navmesh into disconnected islands), and a real factory build-queue production check - before moving to the next map, per Chris's one-at-a-time instruction.

**Verified:** 63/63 tests green (4 new this entry - the per-map smoke tests; the terrain-architecture tests were added in the previous entry). Screenshot set for all four maps plus the final map-select screen in `progress_captures/2026-07-12/maps/`.

---

## 2026-07-12 (cont'd 13) — Multi-map architecture built (terrain data + navmesh integration + elevation vision/combat bonus)

New batch from Chris: build out a variety of distinct Skirmish maps, with real elevation/water/obstacle variation that actually affects vision, combat, and pathing - not palette swaps. Since there was only ever one hardcoded map, this pass built the underlying architecture first; the actual map content is being built one at a time on top of it (see forthcoming per-map entries).

### The architecture

`map_catalog.gd` - a plain Dictionary catalog of maps (same convention as `module_catalog.gd`), each entry describing water areas, obstacles, elevation zones, resource nodes, and player/enemy start points. `terrain_builder.gd` - the shared code that turns a map Dictionary into: baked `NavigationServer3D` ground/water maps (a generalized multi-hole grid, replacing the old single-lake-specific 4-band technique), decorative terrain meshes, and two pure query functions - `terrain_height_at()` and `is_position_blocked()` - that are now the single source of truth for elevation Y and buildability. `skirmish.gd` was refactored to read from a `current_map` dictionary (defaulting to the original map, `lake_crossing`, kept byte-identical for backward compatibility) instead of hardcoded constants.

### Elevation

Discrete raised rectangular plateaus with one ramp each, not a full heightmap - real navmesh consequence (a unit must actually route through the ramp to reach the top; the other three sides are a hard cliff, no bridging geometry). Y-positioning is analytic (`terrain_height_at()`, lerped each tick for moving ground units) rather than physical collision, specifically to avoid rotated-`CollisionShape3D` ramp math and `CharacterBody3D` stair-stepping risk. Holding a plateau now gives a real vision bonus (fog-of-war) and a real combat bonus (`damage_resolver.gd` lowers the defender's effective armor threshold when shot from meaningfully higher ground) - both driven directly off real Y coordinates, no map-awareness needed in either system.

### A real bug, found and fixed

Verifying the ramp actually let a unit reach the plateau (not just "bakes without error") surfaced a genuine bug: Recast was silently dropping the ramp's baked triangles because of a winding-direction mismatch specific to "south"/"west" ramps, where the ramp's outer edge has a smaller coordinate than its inner edge. Traced via several wrong hypotheses (slope angle, climb height, region-size filtering) before isolating it to plain triangle winding with a minimal single-quad repro. Fixed and now covered by a test that exercises all 4 ramp directions.

### Map selection

A `MatchConfig` autoload carries the player's map choice from a new `MapSelect.tscn` screen (MainMenu's "Skirmish" button now routes there first) into `Skirmish.tscn` - read defensively, so every existing headless test that instantiates `Skirmish.tscn` directly keeps using the default map unchanged.

**Verified:** 60/60 tests green (4 new: pure terrain-query correctness, all-4-directions ramp connectivity, elevation vision+combat bonus, and water/obstacle build-placement rejection). Windowed-screenshot verified the map-select screen renders correctly.

**Next:** building the actual map content (3 new maps beyond `lake_crossing`) one at a time on this architecture, each with its own screenshot + smoke-test verification pass before moving to the next.

---

## 2026-07-12 (cont'd 12) — Hull library expansion: naval, blended-wing-body, and sponson hulls

Chris's ask was explicit: not just deform handles on the existing 7 hulls, but genuinely new base geometry - "some ship-like hulls..., a blended-wing-body type hull, and hulls with more interesting base geometry... like built-in sponson stubs already part of the hull silhouette." Built one at a time, each fully authored/imported/screenshot-verified before starting the next, per Chris's explicit caution.

### naval_hull

Pointed bow, flat stern, shallow-draft keel, bridge superstructure, portholes. Gives `naval_propeller` a real boat to sit on - it previously worked correctly on any generic wedge hull (e.g. `heavy_hull`), floating at a fixed waterline with no visual distinction from a land vehicle.

### flying_wing_hull

Swept delta/manta-ray planform authored as a single blended silhouette (no fuselage-vs-wing break, a shallow dorsal ridge instead of the wedge hulls' raised spine). Top-down screenshot confirms a clean swept-delta outline.

### sponson_hull

Heavier ground hull with two box-like sponson blisters fused onto the mid-body sides. **First version was visually too subtle** - built purely from convex-hull point placement (narrower fore/aft, wider mid-band), which just produced a smooth taper reading as a chamfered octagon, not a distinct stub. Caught by the mandatory screenshot check before moving to the next hull. Fixed by keeping a narrower slab-sided core and fusing two separate box volumes onto the sides at the mid-body band instead - now reads as a genuine stepped protrusion.

### Balance and verification

Stats hand-targeted to match each new hull's weight class against existing hulls, then confirmed (not discovered) via `tools/balance_report.gd`: `naval_hull` 0.77, `flying_wing_hull` 0.75, `sponson_hull` 0.74 value/cost - all inside the existing mobile-hull range (0.72-0.80), no outliers. Every generic hull-aware system (Design Lab palette, build-legality gate, balance report) picked up all 3 new catalog entries automatically - no code changes needed beyond the catalog entries themselves, same as Fortress Wall.

**Verified:** 56/56 tests green. Two rounds of windowed screenshots per hull (isometric + top-down) in `progress_captures/2026-07-12/new_hulls/`, including the sponson before/after that shows the caught-and-fixed silhouette issue.

**Not done:** extending per-hull deform rigging (still only `interceptor_hull`) to these 3 or the 6 pre-existing hulls without it - out of scope for "build the library," logged as the natural next increment.

---

## 2026-07-12 (cont'd 11) — Fortress Wall: the third foundation type named in Factions_and_Buildings.md

Previously deferred twice (see DECISIONS_NEEDED.md) for needing new Blender-authored geometry through the fragile headless-import pipeline. Greenlit this pass.

### The build

`module_catalog.gd` gained `fortress_wall_foundation` (category "hull", `is_foundation: true`) - a long, low rampart rather than a squat bunker (`pillbox_foundation`) or a tall tiered tower (`tower_foundation`): 1100 HP, 140 metal / 10 crystal, base_vision 14 (a wall doesn't see far the way a watchtower does). `tools/blender/build_meshes.py` gained `build_wall_hull()` - a battered wall face (wider at the base than the top, like a real rampart) topped with 5 alternating battlement merlons, plus arrow-slit and rivet-row greebles for detail - deliberately a different silhouette from both existing foundations.

### Import, carefully

Found two already-hung `--headless --editor --import` processes from earlier this session still holding the real project (visible via `tasklist`/process inspection) - exactly the scenario the existing memory gotcha warns about. Didn't touch them: imported into an isolated temp copy of the project instead (`--path <tmp> --headless --editor --import`), then copied just the new asset's `.import` sidecar, its `.godot/imported/*` cache entries, and `uid_cache.bin` back into the real project. Verified the mesh actually loads at runtime with a small headless probe before moving on.

### Why this was low-risk despite being new art

Every system that needs to know about hull/foundation types already keys off `category`/`is_foundation` rather than a hardcoded type_id list - the Design Lab's hull palette, the build-legality gate, the balance report, and the foundation-parity mechanics (placement/mirror/rotate/undo/serialize) all picked up the new entry automatically. This was a pure content addition, not a code-path change.

**Verified:** 56/56 tests green (1 new: `test_fortress_wall_foundation_spawns_correctly`, exercising the real spawn pipeline - mesh load, HP, vision, build-legality). Windowed-screenshot verified in the Design Lab - `progress_captures/2026-07-12/fortress_wall/` shows the wall's battlement silhouette from two angles, same visual-verification discipline as the nose-taper work.

---

## 2026-07-12 (cont'd 10) — Real pathfinding (NavigationServer3D) + a lake for naval terrain to route around

Previously deferred (see DECISIONS_NEEDED.md's "Unit AI scope" entry) since the map was flat and open with nothing to path around. Greenlit this pass, along with adding real water terrain.

### The map now has water

A rectangular lake (`LAKE_CENTER=(18,0,0)`, half-extents 7x7) added to `skirmish.gd`, with a visible blue semi-transparent water plane. Two separate `NavigationServer3D` maps are baked at match start (raw low-level API, not `NavigationRegion3D` nodes, specifically so ground and water can be two genuinely different navigable areas rather than one shared default map): the ground navmesh has the lake baked out as a hole (4-quad band around it), the water navmesh covers only the lake's interior.

### Per-unit navigation

`battle_unit.gd` gains a `NavigationAgent3D` for every non-flying unit (`_setup_navigation()`, called from `setup()`), assigned to the ground or water map based on the unit's `is_naval` trait. Flying/fixed-wing units skip this entirely - open air has nothing to route around. `_steer_towards()` now asks the agent for its next path point and steers toward that instead of the raw destination whenever an agent is present, falling back to the old straight-line steering for any context without a real match controller (duck-typed via `get_ground_nav_map()`/`get_water_nav_map()` on the parent) - every existing synthetic test that builds a `battle_unit` outside a real `Skirmish` scene keeps working unchanged.

### A real bug found (and fixed) while verifying this end-to-end

All unit tests passed first try, including two dedicated pathfinding tests (direct `NavigationServer3D.map_get_path()` queries proving the ground map detours around the lake and the water map covers its interior; nav_agent-to-map assignment for ground/naval/flying units). But a first windowed capture showed a unit given `order_move()` not moving at all. Root cause was NOT the new pathfinding code - it was a pre-existing gap in how `_recalculate_move_speed()` detects locomotion: it only counts a hull child module tagged `category == "locomotion"`, never the blueprint's top-level `"locomotion": {type_id, settings}` field (which only feeds movement-trait lookups). Real saved blueprints always carry both - the Design Lab's `update_locomotion()` places locomotion as an actual module child, and `serialize_hull()` serializes every such child into `"modules"`. But the synthetic test blueprints used throughout `run_tests.gd` (mine included) only ever set the top-level field with an empty `"modules": []`, so `move_speed` silently computed to `0.0` in that specific fixture shape - a test-fixture gap that happened to never matter until a test actually needed real movement to occur. Full root-cause trace and the fix logged in DECISIONS_NEEDED.md.

**Verified:** 55/55 tests green (1 new: `test_unit_order_move_actually_navigates_around_the_lake`, using a blueprint shaped like a real saved one, asserting both real movement and that the path never enters the lake bounds). Windowed-screenshot verified in a real match - `progress_captures/2026-07-12/pathfinding/` shows a unit hugging the lake's edge mid-transit and fully past it at the end.

---

## 2026-07-12 (cont'd 9) — Fog-of-war built from scratch, Technocrats' vision passive finally means something

No prior infrastructure existed for this at all - confirmed by an earlier gap-analysis pass this week. Built real vision-radius + fog-of-war:

### Vision stat

`base_vision` added to every hull/foundation catalog entry, `vision_bonus` added to `sensor_suite` (previously pure stat-flavor text - "Pushes back fog of war... Mast Height: Drastically increases line-of-sight" with nothing behind it). Per-unit `vision_range` computed the same "hull base + module bonus" shape as Energy (`_recalculate_vision()` in `battle_unit.gd`, mirrored in `building.gd` for defense structures; prefab buildings get a flat default). Technocrats' faction passive (+15% vision, `Factions_and_Buildings.md`) applied on top - the first time this passive has ever had anything to modify.

### The fog itself

Deliberately **one-directional**: `skirmish.gd`'s periodic scan (`_recalc_fog_of_war()`, every 0.3s) only ever toggles visibility on ENEMY constructs, never the player's own - this is a single shared 3D scene, not per-client rendering, so hiding player units whenever they left an enemy's vision would make them vanish from the player's own screen too, which isn't what fog-of-war means. `set_fog_visible()` on `battle_unit.gd`/`building.gd` toggles `.visible` (cascades to mesh/HP bar/everything) and sets a `fog_hidden` flag that `auto_weapon.gd`'s targeting now checks - an enemy that hasn't been scouted can't be auto-targeted, not just invisible cosmetically.

**Deliberate scope cut, logged not hidden:** the enemy AI keeps its existing omniscient targeting - fog only gates the player's own experience (what renders, what the player's own weapons can hit). A fully symmetric fog (AI also can't see/target unscouted player units) would be more "real" but risks making the AI feel broken (can't find harvesters, doesn't react to threats) without being able to interactively verify the balance. Also not built: the fuller "explored but not currently visible, stays dimly revealed" tier some RTS games have - this is "currently visible only," a simpler two-state model.

**Verified:** 50/50 tests green (3 new: vision computation including the Technocrats passive, a full hide/reveal/never-hide-own-team integration test against a real Skirmish scene, and a targeting-exclusion test). Also windowed-screenshot verified in a real match - `progress_captures/2026-07-12/fog_of_war/` shows an enemy unit literally not rendered until a player scout's vision reaches it.

**Commit checkpoint:** see git log.

---

## 2026-07-12 (cont'd 8) — Facet-aware kiting (with a real mid-implementation bug found and fixed)

Kiting now factors in facet strength, not just distance, per Chris's ask.

### What shipped

`battle_unit.gd`'s kiting always repositions to keep its own STRONGEST facet toward the attacker while retreating, instead of a plain straight-back retreat that turns to face the travel direction and leaves whichever facet ends up opposite entirely to chance. Reused the existing per-facet-threshold estimate (`_weakest_facet_normal()`, built for target-flanking) by generalizing it into a new `_facet_thresholds()` helper callable on any hull+modules, then added `_my_facet_extremes()` (self-analysis) and `_kite_reposition()` (rotate toward presenting the strongest facet + strafe directly away from the attacker, decoupled rotation/translation).

### A real bug found mid-implementation, not just in review

First version tried to be clever: only reposition while the CURRENTLY-facing facet was the weakest, with a "sticky" flag to keep committing through a turn once started, then hand off to plain retreat once the strongest facet was achieved. Traced with a debug print through the real headless test environment (a standalone scratch probe gave garbage results - the CharacterBody3D never properly entered a physics-ready tree state outside the established test harness, a good reminder that "reproduce in isolation" isn't always faster than instrumenting the real path) and found the handoff itself was the bug: the moment repositioning correctly achieved the target facet and switched to `_steer_towards()` for the retreat, that function immediately started rotating toward ITS OWN idea of the correct heading (the travel direction), undoing the just-achieved positioning within a few frames - the unit would end up facing directly away from the attacker (exposing its back) regardless of which facet was actually strongest.

Fixed by simplifying rather than patching: `_kite_reposition()` recomputes its target every frame from whichever facet is currently strongest, so it's self-stabilizing once achieved - there's no need for a second competing steering mode at all. Always using it for kiting (no more branching on "is the weakest facet currently exposed") also handles the case where every facet is equal (no armor modules) sensibly: "strongest" becomes an arbitrary tie-break (front), which just means facing the attacker while backing away - a reasonable default, not a regression from the old plain retreat.

**Verified:** 47/47 tests green (1 new - `test_facet_aware_kiting`, which sets up a hull with a reinforced right-facet plate, positions the weak front facet toward the attacker, and confirms the unit both increases distance AND ends up presenting its strongest facet, not just whichever one a plain retreat would have produced).

**Commit checkpoint:** see git log.

---

## 2026-07-12 (cont'd 7) — Doc cleanup, repair_array heal_rate, energy damage-type reclassification (found + fixed a deeper bug)

Start of a new batch. First pass: documentation hygiene, then two of the "rest of the open items."

### DECISIONS_NEEDED.md reconciled against what actually shipped

Chris asked for a real pass, not just the one example he named. Found the armor-related entries were genuinely stale: "Armor-module combat integration scoped to aggregate (non-directional)" and "Directional/facing armor thresholds are documented but not implemented" were both written before the same-day armor pass, which built exactly the directional/facet-aware resolution they'd scoped away from (confirmed via `damage_resolver.gd`'s `resolve()` signature and the four directional-armor tests). Both marked RESOLVED with what shipped. Everything else checked against current code state - the rest were still accurate as written.

### Grid-snap struck from Design_Lab_UI_UX.md

The doc's "Surface Grid" section described a hex/square snap-grid that was never built and isn't going to be (freeform placement is the confirmed final direction). Rewrote the section to describe freeform placement directly, with a note on why the earlier grid draft was superseded, instead of leaving the doc silently wrong. Also fixed an adjacent inaccuracy while in there: the "Key Stats" line listed "Damage Thresholds (Kinetic/Thermal/Explosive)" - the real third category is Energy, not Explosive.

### repair_array gets a real heal_rate stat

Previously reused the generic `dps` field as a stopgap (logged as a known wart). `module_data.gd` gained `base_heal_rate`/`get_heal_rate()` (own getter, reuses `welder_count`'s existing scaling), `repair_array`'s catalog entry is back to an honest `dps: 0.0`, and the Design Lab's floating stat popup shows "Heal Rate: X/s" instead of "DPS: X" for modules with one. `tools/balance_report.gd` also gained a dedicated `HEAL_RATE_WEIGHT`.

### Energy damage_class reclassification - and a deeper bug found while checking it

Chris asked me to use the balance tool to check this carefully first. Doing that surfaced something the tool couldn't see but the check itself revealed: `damage_resolver.gd`'s `ARMOR_TABLE` never had a real `"energy"` row at all - every weapon dealing `damage_class == "energy"` (including this session's own tesla_coil/arc_projector/ion_cannon) was silently resolving as EXPLOSIVE damage via a fallback, and the Design Lab's "E:" armor-threshold label was a separately-hardcoded, mislabeled copy of the explosive value. Both predate today; not introduced by the energy-weapon work, just not caught until now.

Fixed with a genuine energy row per material (energy_shielding gets the strongest defense against it, matching its name) and made `stat_calculator.gd` read K/T/E directly from `DamageResolver` instead of a second hardcoded table. Then did the real reclassification analysis: `heavy_laser`/`plasma_lobber`/`pd_laser` reclassified from `thermal` to `energy` - a real, meaningful swing (notably stronger vs `ablative_ceramic`, notably weaker vs `energy_shielding`), logged with the concrete before/after numbers in DECISIONS_NEEDED.md rather than applied silently. `flamethrower`/`drone_carrier` deliberately left alone (no real energy identity). The three reclassified weapons stay outside `ENERGY_WEAPON_TYPES` - they deal energy damage but don't cost/drain the Energy resource, keeping that mechanic scoped to this session's three new weapons only.

**Verified:** 47/47 tests green (2 new this chunk). Visual regression: baselines updated to reflect the corrected (no longer mislabeled) Energy threshold display - confirmed by screenshot the sidebar now reads "E: 8.0" for hardened_steel instead of the old "E: 10.0" (which was silently the explosive value).

**Commit checkpoint:** see git log.

---

## 2026-07-12 (cont'd 6) — Build-legality gate, balance tooling, screenshot-diff testing (found 2 real bugs)

Final three pieces of the big Energy/balance/modules batch. (Between this and the previous entry, also fixed a real pre-existing bug found while verifying the repair/drone work - `_setup_weapons()` never attached auto_weapon.gd to repair_array/drone_carrier in real gameplay at all, only in synthetic tests - see the DECISIONS_NEEDED.md entry and commit `7faa28b`.)

### Build-legality gate

`ModuleCatalog.validate_build_legality(blueprint_data)`: a design needs a hull, a weapon or a legitimate support/utility purpose (generator, repair_array, drone_carrier, resource_harvester, sensor_suite, logistics_tank), and locomotion or intentional staticness (a foundation hull) - otherwise it's rejected before resources are spent, with a clear reason shown via the existing `_flash_status()` toast. Wired into both unit-queue and defense-placement paths in Skirmish, plus defensively into the enemy AI's roster filtering.

### Balance tooling

New `tools/balance_report.gd` (headless, run standalone) scores every catalog entry's value-per-cost (weighted dps/hp/energy vs metal/crystal/weight), grouped by category, flagging outliers relative to their category average. Actually used it, not just built it: three real outliers got cost adjustments (`spigot_mortar`, `flamethrower` - both way underpriced for their output; `ion_cannon` - this pass's own new weapon, the single worst value/cost weapon in the entire catalog even before counting its energy-drain utility). Deliberately did NOT chase every flagged entry - point-defense specialists and utility modules score low because the model can't see their real value (interception, economy throughput), and "fixing" that would break their actual role. Full reasoning and the exact before/after numbers are in ENERGY_AND_BALANCE_SPEC.md #7.

### Screenshot-diff testing, greenlit and built - then actually used to find bugs

New `scripts/screenshot_diff.gd` (pixel comparison, 6% per-channel / 2% of sampled pixels tolerance - tuned to absorb anti-aliasing/font-hinting noise without missing real regressions, headlessly unit-tested against synthetic images) plus `visual_regression/run_visual_regression.gd`, a windowed harness covering 5 scenarios: empty Design Lab UI, module placement, armor facet-fitting, the floating module-stat popup, and the Skirmish HUD. Baselines checked into `visual_regression/baselines/`.

Per Chris's explicit instruction not to just wire it up and move on, I reviewed the first-run captures by eye and found two things:
- The armor-facet scenario initially rendered as a giant red block - traced to the *existing* clipping-detection system correctly flagging genuinely overlapping armor plates in my test scenario (wrong assumed hull size), not a bug. Fixed the scenario, confirmed clean rendering.
- **A real bug**: the Skirmish HUD showed "Energy: 0/0 (DEFICIT: builds slower!)" in the very first frame of a brand new match, before the player has done anything - every match started in automatic Energy deficit (no generators built yet, but static buildings already owe upkeep), applying the factory build-speed penalty for the whole early game by default. Fixed with a baseline HQ power-plant contribution (`ENERGY_HQ_BASELINE_CAPACITY`); a fresh match now starts at a small surplus instead. New headless test guards this specifically.

Full reasoning for both findings in DECISIONS_NEEDED.md.

**Verified:** 46/46 tests green (headless suite). Visual regression: 5/5 scenarios pass against their baselines after the fixes above.

**Commit checkpoint:** see git log. This closes out the big Energy/balance/modules batch - all 8 items from the original ask are done (Energy resource, repair array, drone carrier, build-legality gate, energy drain weapons + silliness, logistics sharing, balance tooling, screenshot-diff testing) plus the stat-rounding fix.

---

## 2026-07-12 (cont'd 5) — Repair array + drone carrier fixed for real, 3 new energy weapons, logistics sharing aura

Second chunk of the big Energy/balance/modules batch (see ENERGY_AND_BALANCE_SPEC.md for the design reasoning; the Energy resource itself + stat rounding landed in the previous checkpoint). This chunk: the two "fake" modules, and the new Energy-tied combat mechanics.

### Repair/Construction Array: real heal, real ally-targeting

Previously `_fire_repair_array_beam()` called `take_damage()` on whatever `_find_nearest_target()` returned - and since team-mode targeting unconditionally skips same-team candidates, it could never select an ally at all, and its catalog `dps` was `0.0` besides. It was a beam that cosmetically "welded" a hostile for zero effect.

- `ModuleCatalog.targets_allies(type_id)`: new single-source-of-truth flag (only `repair_array` sets it).
- `auto_weapon.gd`'s `_find_nearest_target()` grew an ally-targeting branch: same-team, HP-deficit (`hp < max_hp`) candidates, inverted from every other weapon's hostile-only filter.
- `battle_unit.gd`/`player_vehicle.gd`/`building.gd` all gained `repair_hp(amount)` (duck-typed like `take_damage`) - `_fire_repair_array_beam()` now calls that instead of `take_damage`.
- Catalog `dps` for repair_array is now `30.0`, reused as a heal-per-second rate (not damage) - known minor wart, logged in DECISIONS_NEEDED.md, that this also feeds the generic "Total DPS" aggregate.

### Drone Carrier Bay: real autonomous drones, not tweened meshes

`_fire_drone_swarm()` used to spawn two throwaway `MeshInstance3D` prisms, tween them to an orbit point and back, and apply damage in the tween's `finished` callback - no persistent entity, no independent physics, no AI. New `scripts/drone_unit.gd` is a real standalone node (modeled on `incoming_missile.gd`'s shape): its own `_physics_process` state machine (LAUNCH → ATTACK → RETURN), registers in the `"missiles"` group so existing point-defense code can shoot it down mid-flight, single lump-sum damage hit on arrival (not a per-frame tick, which would have rolled subsystem-stripping dozens of times per pass). Also added the two `TWEAK_SPECS` entries ("Hangar Size" → drone count, "Launch Catapult" → launch cooldown) that were documented in Arsenal_Weapons_List.md but never existed in code at all.

### Three new energy weapons + a little silliness

`tesla_coil` (a genuinely silly one per Chris's explicit invitation - a zigzag chain-lightning bolt visual and a literal wound-coil mesh, not a straight beam), `arc_projector` (the dedicated pure energy-drain "disable" weapon, minor HP damage), `ion_cannon` (the grounded energy heavy-hitter, full damage + drain). All three cost the firing unit's own `current_energy` per shot (a real capacitor-empty gate - the weapon just can't fire without charge) and drain the target's energy pool on hit. This also gives the previously-dead "Energy" armor damage-type threshold (shown in the Design Lab sidebar since early this week, never actually used by any weapon) its first real meaning - deliberately did NOT reclassify existing thermal weapons (heavy_laser etc.) to avoid silently changing their established balance.

### Logistics Tank: real energy-sharing aura

Previously a pure stat-bearing module (its `tank_capacity` tweak scaled weight/cost but did nothing functionally). Now shares surplus energy with nearby allies (15-unit radius) every physics tick, scaled by tank_capacity - "not just self-sufficiency" per Chris's instruction, it does nothing for its own carrier beyond existing capacity.

**Verified:** 5 new tests (41/41 total green): base-pool+generator capacity, repair-targets-allies-not-enemies, drone-carrier-spawns-real-independently-flying-entities, energy-weapons-spend-and-drain-and-cant-fire-empty, logistics-aura-boosts-allies-only.

**Commit checkpoint:** see git log.

---

## 2026-07-12 (cont'd 4) — Unit AI phase 1: whole-vehicle-aim, kiting, new-movement-type enemy roster

Chris's green light: "start real work on unit AI, pathfinding, and attack behavior — for both player-controlled and enemy units." Scoped this to the concrete, well-bounded pieces that directly extend today's mounting/trait work into actual combat behavior, rather than attempting full pathfinding in one pass (see DECISIONS_NEEDED.md for why).

### Frame-built weapons now really are fixed to the hull, and the AI drives accordingly

Found a real gap while reviewing `auto_weapon.gd`: `get_mount_style()` already classified `gauss_railgun`/`heavy_howitzer` (and anything on a non-turreted-capable hull) as `"frame_built"` — meant to mean "built into the vehicle frame, whole vehicle aims, not the weapon" — but `get_traverse_limit_angle()` never knew about mount style at all, so a frame_built weapon still independently traversed within its own arc like a turret. That contradicted the concept the mounting system was built to express.

- `ModuleCatalog.get_traverse_limit_angle()` grew optional `facet`/`hull_type_id` params (mirrors `get_mount_style()`'s signature); when supplied and the mount resolves to `frame_built`, it returns `0.0`. Omitting them keeps the old weapon-type-only angle, so any call site that doesn't yet know its mount context is unaffected.
- `auto_weapon.gd` now passes its own `facet` meta + parent hull's `type_id` into that call, and skips the independent-aim slerp entirely when the resulting angle is ~0 — the weapon just stays at `resting_transform`, so its `global_transform` tracks the hull's own facing 1:1.
- `battle_unit.gd` caches `has_frame_built_weapon` at setup (reusing the angle `auto_weapon.gd` already computed, not re-deriving mount style). In the ATTACK order, once in range, a frame_built unit now keeps turning its whole hull toward the target (`_turn_toward()`, a stationary-rotation variant of the existing `_steer_towards()`) instead of just stopping wherever it happened to be facing on arrival.
- The Design Lab's firing-arc visualization (`module_placer.gd`'s `_build_firing_arc`) now passes the same facet/hull_type context, so a frame_built weapon shows a collapsed (effectively zero-width) arc instead of a wedge that was never actually true to combat — keeping the documented "never drift apart" invariant between the visualization and the sim.
- Verified both with a unit test (`test_frame_built_whole_vehicle_aim`) and visually: `progress_captures/2026-07-12/ai_phase1/before_whole_vehicle_aim.png` vs `after_whole_vehicle_aim.png` — a railgun tank starts facing away from a target placed 90° off its nose, and after a few seconds of the ATTACK order has visibly rotated in place to bring the fixed barrel to bear.

### Ranged units now back off when something closes past their comfortable range

Previously every unit (turreted or not, artillery or not) used the same "approach to 90% of attack_range, then stand still" pattern — a long-range unit that got closed on (or that started an engagement already close) had no way to reopen distance and just traded at melee range, giving up the advantage its weapon range was supposed to provide.

- New branch in `battle_unit.gd`'s ATTACK order: when a **turreted** (not frame_built — see below) unit's target is closer than `KITE_STANDOFF_FRACTION` (0.45) of `attack_range`, it steers away from the target instead of holding position. The turret keeps tracking/firing independently of hull facing the whole time, since that's how independent traverse already works.
- Frame_built units explicitly do **not** kite — retreating would point their fixed weapon away from the only thing it can hit. They hold and turn instead (previous section).
- Simplification, logged rather than hidden: the retreat steers via the same code as normal movement, which turns to face the direction of travel — it does not attempt to reverse while keeping a strong facet toward the threat. Real added value (avoiding getting stuck at melee range) without inventing a new reverse-driving primitive this pass.
- Verified with `test_ranged_unit_kiting()`.

### New enemy roster entries exercise the new movement models in real AI play

The existing enemy roster (`data/enemy/*.json`) already fielded 4 varied unit archetypes, not one-unit-type spam — but none of them used this week's new `fixed_wing_engine`/`naval_propeller` locomotion types, so the strafing-run and surface-lock AI built earlier this week had only ever run in synthetic tests, never a real AI-controlled Skirmish unit.

- `data/enemy/raptor_striker.json`: `interceptor_hull` + `fixed_wing_engine` + nose-mounted `rotary_cannon` — a strafing fighter.
- `data/enemy/tide_corvette.json`: `heavy_hull` + `naval_propeller` (×2) + `basic_cannon` + `flak_cannon` — a surface unit.
- Both are picked up automatically (enemy roster is directory-scanned, no registration code needed) and confirmed via `test_enemy_roster_new_movement_archetypes()` plus a headless Skirmish sim (`sim_ai_phase1.gd`, since deleted per the usual scratch-cleanup practice) that force-queued both plus a player-side frame_built unit and ran 190 real physics ticks with no errors. Also screenshotted: `progress_captures/2026-07-12/ai_phase1/new_enemy_roster_raptor_corvette.png`.

**Not built this pass** — see DECISIONS_NEEDED.md for the reasoning on each: real pathfinding/obstacle-avoidance (NavigationServer3D), naval terrain-aware routing (no water/land distinction exists in the map at all yet), and further depth on fixed-wing strafing AI beyond the existing orbit pattern.

**Verified:** Full suite: **36/36 green** (33 pre-existing + 3 new this pass). Headless Skirmish sim: 190 physics ticks, no crashes, correct trait derivation on both new archetypes.

**Commit checkpoint:** see git log.

---

## 2026-07-12 (cont'd 3) — Gap analysis, headless UI-bug detection (found + fixed a real bug), starting AI/pathfinding

Chris asked for three things: an honest gap analysis against all 6 design docs, a green light to start real unit AI/pathfinding/attack-behavior work, and an investigation (build-if-feasible) into automated visual/UI bug detection. Full gap analysis and feasibility findings are in the conversation transcript / relayed to Chris directly — summary of what shipped from it:

### UI overflow/off-screen detection: built, and it immediately found a real bug

Verified two techniques empirically against the real game UI (not assumed):
- **The naive approach doesn't work here.** Comparing a `Label`'s own `.size` to its own `get_minimum_size()` is meaningless in this codebase, because the UI is `VBoxContainer`-heavy and auto-sizing — a control's size trivially always equals its own minimum. Proved this by trying it and watching it fail a forced sanity check.
- **The real signal:** compare a genuinely fixed-size ancestor (a `ScrollContainer` anchored to a real screen region) against its content's natural combined minimum size. Also learned (the hard way, debugging a false-negative in my own sanity test) that Godot enforces an internal floor where most Container types can never have `.size` smaller than their own minimum — `ScrollContainer` is specifically the exception, which is *why* the real bug below used one.
- New `scripts/ui_audit.gd`: `find_overflowing_panels()` and `find_offscreen_controls()`, both pure functions, no windowed rendering needed, fast enough for the existing suite.
- **Found a real, pre-existing bug on the first real run:** the "Armor Thresholds: K: 15.0, T: 5.0, E: 10.0" label needs 305px but its panel is 210px wide — this is the exact text-clipping artifact visible in several of today's *own* verification screenshots that I never flagged as a bug. Fixed with `autowrap_mode = AUTOWRAP_WORD_SMART` (wraps to 2 lines instead of a fixed truncation width, so it stays correct as threshold values grow more digits). Verified visually — `progress_captures/2026-07-12/ui_overflow_fix/`.
- Two new tests: `test_ui_no_overflow_or_offscreen()` (regression-guards the real `MainLab.tscn` scene, now clean) and `test_ui_audit_has_real_teeth()` (sanity-checks the tool itself against an injected overflow and an injected off-screen control, so a future refactor can't silently turn it into a no-op).
- **Screenshot-diffing was investigated but not built** — it needs windowed rendering (headless Godot doesn't rasterize), a maintained baseline-image directory, and tolerance for legitimate rendering variance. Logged as a documented option, not the default, per Chris's explicit instruction not to default to the most expensive version.

**Verified:** Full suite: **34/34 green.**

**Commit checkpoint:** see git log.

---

## 2026-07-12 (cont'd 2) — New direction: full directional armor + trait-based unit classes, no hard gating

Chris reviewed the phased-plan writeup and gave the call: go as far as possible on both the full armor phase list (including sloped-armor raycast math and AI facing-awareness) and the full trait system (including new movement models and strafing AI), not just the cheap tiers. Explicit constraint: **traits/hulls/locomotion must never hard-block each other** — a player can put treads on a naval hull if they want; bad combinations should produce janky emergent behavior, not a validation wall. This is now the priority, sequenced as: Armor (dedupe → facet resolution → per-module material → sloped armor → AI facing) then Traits (formalize → generalize mounting → new movement models → new AI → new hull art).

### Armor Phase 1 (dedupe) + Phase 2 (facet-level resolution) shipped

**Phase 1:** `take_damage()`'s armor math was duplicated identically across THREE places (`battle_unit.gd`, `player_vehicle.gd`, and — found while doing this — `building.gd`'s defense structures, which is why this was worth doing before building on top of it: it had already drifted once today). Extracted into `damage_resolver.gd`'s `DamageResolver.resolve()`, a single source of truth all three now call. Verified behavior-preserving (identical HP numbers before/after). Bonus find: `building.gd` never got the armor-module aggregate bonus at all — a real parity gap between vehicles and defenses, fixed as part of the same pass.

**Phase 2:** Armor is now genuinely directional, not just aggregate.
- `ModuleCatalog.classify_facet()`: moved the facet-classification logic (previously private to `module_placer.gd`'s placement code) to a shared location so combat can use the exact same convention.
- Armor modules now store which facet they're mounted on (`facet` meta, persisted through save/load same as `mount_style`).
- `DamageResolver.resolve()` grew optional `defender`/`hit_origin` params: when both are given, it classifies which facet actually faces the attacker and only counts armor modules covering *that* facet — armor on the far side of the hull no longer helps. Omitting either (AoE, or callers that don't care) falls back to the old aggregate-everything behavior, so nothing breaks that doesn't opt in.
- `take_damage()`'s signature grew an optional `hit_origin` parameter (defaults to `null`, fully backward compatible) across all three implementations, plus `auto_weapon.gd` (17 call sites, one per weapon type) and `incoming_missile.gd` now pass their own `global_position` as the hit origin.

**Verified:**
- New test `test_directional_armor_facet_resolution()`: confirms a front-only armor plate protects against a hit from the front but NOT an identical hit from the back, and confirms omitting `hit_origin` still falls back to aggregate.
- Full skirmish simulation re-run clean after the 17-call-site change in `auto_weapon.gd`.
- Full suite: **27/27 green.**

**Commit checkpoints:** see git log.

### Armor Phase 3: per-module material choice

A placed armor plate can now carry its own material (Hardened Steel / Reactive / Ablative / Energy Shielding), independent of the hull's global material — a front plate can be reactive while the sides are ablative.

- New "Plate Material" dropdown in the per-module tweak popup, shown for `armor` category regardless of whether the type has `TWEAK_SPECS` entries (armor_plating has none). Stored in the existing `tweaks` dict (`tweaks["material"]`), so it rides the existing save/load path with zero new persistence code.
- `DamageResolver.resolve()`: when a hit resolves to a facet with a covering plate, if that plate has its own material set, its threshold/reduction table **replaces** the hull baseline for that hit (the attack strikes the plate, not the bare hull under it) — the plate's HP still adds its flat bonus on top, same as phase 2. No material set → falls back to phase 2's behavior (hull baseline + flat bonus). No hit direction at all → phase 1's aggregate behavior, unchanged.

**Verified:**
- New test `test_per_module_armor_material()`: a hardened-steel hull with an energy-shielding front plate resolves a front hit using energy shielding's threshold (not the hull's), while a back hit (uncovered facet) still uses the hull's own hardened-steel baseline.
- Visual: `progress_captures/2026-07-12/armor_material_ui/` — the new per-plate dropdown, distinct from the existing hull-level Armor Material control.
- Full suite: **28/28 green.**

### Armor Phase 4: true angle-of-incidence sloped armor (raycast)

Real ballistics: a shot that grazes a surface at a shallow angle is more survivable than one that hits square-on, independent of what material or plate is there.

- `DamageResolver.compute_slope_multiplier(defender, hit_origin)`: casts a real ray from the attacker to the defender's hull collider (Layer 1, same convention used everywhere else) and reads the *actual* surface normal at impact — not an analytical shortcut off the facet's canonical axis. Effective threshold = base / cos(angle), the standard sloped-armor formula, clamped so a razor-thin grazing angle doesn't produce an absurd multiplier.
- Deliberately raycasts against real collision geometry rather than computing the angle analytically (which would give an identical result today, since hull collision is currently a single axis-aligned box — see the "Known architecture constraint" in MOUNTING_AND_ARMOR_SPEC.md). This means the moment hull collision ever becomes mesh-accurate (a genuinely sloped glacis plate, say), this system starts reflecting that automatically, with no code changes needed here.
- Applied to `threshold` only, not `reduction` — slope is about whether a hit penetrates at all, not how much of the damage that does get through is mitigated.

**Verified:**
- New test `test_sloped_armor_angle_of_incidence()`: a real `StaticBody3D` + `BoxShape3D` collider, two shots at the same face — one dead-on, one from an oblique angle. The oblique hit resolves to threshold 18.3 vs. the perpendicular hit's 15.0, matching the hand-calculated expected value (15.0 × 1/cos(35°) ≈ 18.3) almost exactly.
- Full skirmish simulation re-run clean with real raycasts firing on every hit; ~27s runtime for a 110s simulated battle, no meaningful performance regression. (HQ survival numbers shift run-to-run now, since slope depends on actual unit positioning/geometry rather than a pure lookup — expected, not a bug.)
- Full suite: **29/29 green.**

### Armor Phase 5: AI facing-awareness — flanking matters in Skirmish, not just Test Range

Closes out the full armor phase list. Previously nothing evaluated target facing at all — units walked straight at whatever they were attacking. Now attacking units path toward the target's *weakest* facet instead.

- `battle_unit.gd` gains `_weakest_facet_normal(target)`: estimates each of the 4 horizontal facets' effective kinetic threshold (hull baseline, or a covering plate's own material+HP if one exists — the same resolution `DamageResolver` would use for a real hit) and returns the world-space direction of the weakest one. Top/bottom deliberately excluded — not meaningful for ground-based steering to "approach from above."
- `_compute_flank_point(target)` turns that into an actual waypoint the existing `_steer_towards()` steers toward, replacing the old "walk straight at `target.global_position`" behavior in the `ATTACK` order.
- Duck-typed target lookup (`_get_target_hull`) works for both `battle_unit.gd` (`hull_node`) and `building.gd` (`defense_hull`) targets.
- **Applies to both teams equally** — same steering code runs for player-issued and AI-issued attack orders, no AI-only special case. A player who manually attacks a heavily-armored-front enemy will also path toward its weak side automatically.

**Verified:**
- New test `test_ai_flanking_targets_weakest_facet()`: a target with a heavily armored front resolves its weakest facet to something other than front, and the computed flank point is directionally biased away from the armored side.
- Full skirmish simulation re-run clean with real units now flanking during combat.
- Full suite: **30/30 green.**

**This completes the full armor phase list** (dedupe → facet resolution → per-module material → sloped armor → AI facing), per Chris's "go as far as possible on both fronts" direction. Moving to the trait/unit-class system next.

### Traits B1 + B2: composable trait system, generalized mounting

- `ModuleCatalog.get_traits(hull, locomotion)`: unions traits from whatever hull+locomotion combo is actually present (`ground_contact`, `high_speed`, `airborne`, `rotary_wing`, `hovering`, `fixed_wing`, `naval`, `buoyant`, `static` derived from `is_foundation`). Composable tags, not a rigid ship/land/air/building enum — matches Chris's helicopter/jet/AC-130 example directly.
- **No validation, anywhere, by explicit instruction.** A pre-existing gate (`_place_weapon_from_ui` rejected locomotion on foundation hulls) was removed as part of applying this consistently — a mobile pillbox is now a legitimate, if odd, thing a player can build. Logged as a deliberate judgment call in DECISIONS_NEEDED.md since it changes established (not new) behavior.
- `ModuleCatalog.is_turreted_capable(hull)`: defaults `true` for every hull that exists today (unchanged mounting behavior). `get_mount_style()` generalized: when a hull isn't turreted-capable, *everything* mounts `frame_built` (including `basic_cannon`, previously the hardcoded exception) — nothing should carry independent-traverse hardware on a unit that structurally can't traverse weapons independently.

### Traits B3 + B4: new movement models + strafing AI

Genuinely new movement paradigms, not reskinned existing locomotion — built together since the strafing AI behavior is implemented as part of the fixed-wing steering function itself.

- Two new locomotion catalog entries: `fixed_wing_engine` (traits: `airborne`, `fixed_wing`, `high_speed`) and `naval_propeller` (traits: `buoyant`, `naval`). Procedural visuals (nacelle pod + intake ring; propeller housing + blade cluster) — no new Blender-authored geometry (see B5 below).
- `battle_unit.gd`'s `is_flying`/new `is_fixed_wing`/`is_naval` are now derived from `ModuleCatalog.get_traits()` at `setup()` time instead of a hardcoded `locomotion_type == "helicopter_rotors"` string check. **Side benefit:** this was a real, if minor, pre-existing bug — `anti_grav` was already tagged conceptually as true hovering flight in the design docs ("ignores terrain completely") but never actually got altitude/flight behavior before, since the old check only matched `helicopter_rotors` by name. It does now.
- New `_steer_fixed_wing()`: genuinely different from `_steer_towards()` — never arrives-and-stops (`move_speed` acts as minimum airspeed, matching real stall-speed behavior), and banks/rolls into turns proportional to turn sharpness instead of just yawing flat like a tank pivoting.
- Naval units are surface-locked (fixed low waterline, immune to gravity/floor detection) rather than using ground physics — there's no terrain-height/water system in this prototype, so "the surface" is a fixed Y.
- **Strafing AI (B4):** for `ATTACK` orders, fixed-wing units continuously orbit the target at `attack_range * 1.5` instead of approaching and stopping (which a plane can't do) — the orbiting flight path naturally produces repeated firing passes as it swings back within weapon range, distinct from the ground-unit approach-and-engage pattern. Applies to both teams' units equally, same as the armor-phase-5 flanking behavior.

**Verified:**
- New test `test_fixed_wing_and_naval_movement()`: confirms a fixed-wing unit never drops below minimum airspeed even when "arrived" at its destination, confirms a sharp turn produces a real bank/roll angle, and confirms a naval unit settles at the fixed waterline regardless of starting altitude/gravity.
- Updated `test_foundation_design_lab_parity()`: previously asserted locomotion was rejected on foundations; now asserts the opposite, since that gate was removed.
- Visual: `progress_captures/2026-07-12/new_locomotion/` — both new locomotion types render correctly on existing hulls.
- Full suite: **32/32 green.**

### B5 (new Blender-authored hull geometry for airframes/ships): deferred

Consistent with every other new-art decision this week (the extra foundation type, 6 of 7 hull deforms) — the mechanics work today on the *existing* 7 hulls (I tested `fixed_wing_engine` on `light_hull` and `naval_propeller` on `heavy_hull`, both work correctly with no dedicated airframe/ship silhouette needed, since no-hard-blocking means any hull accepts any locomotion). Purpose-built hull *shapes* for aircraft/ships are a visual layer on top of working mechanics, not a blocker for the mechanics themselves. Logged in DECISIONS_NEEDED.md.

---

## 2026-07-12 (cont'd) — New scope from Chris: mounting/armor/hull-tweak rework

Chris reviewed the beta report and gave new direction covering 4 areas (firing arcs, armor-as-module, face-based weapon mounting, per-hull deform rigging). Written up in full in [MOUNTING_AND_ARMOR_SPEC.md](MOUNTING_AND_ARMOR_SPEC.md) — this supersedes the "keep armor hull-level-only" decision logged 2026-07-12 earlier today. Treating this as the priority for the rest of the sprint, sequenced by risk/dependency rather than the order it was listed in.

### Item 1 shipped: real firing arc visualization

Previously a fixed decorative cone (always the same size, always blue, not derived from anything). Now:
- `ModuleCatalog.get_traverse_limit_angle(type_id)` extracted as a single source of truth, shared between `auto_weapon.gd` (actual combat behavior) and the new visualization — they can't drift apart, which matters since the whole point is showing players what will actually happen in a fight.
- The arc is a real wedge spanning the weapon's actual traverse limit, built from per-segment raycasts against the hull and other modules. Segments read blue where clear, red where blocked — matching Design_Lab_UI_UX.md's "Radar Sweep" spec exactly (previously just aspirational text).
- Stays live: rebuilds via `_refresh_firing_arc()` hooked into `check_all_clipping()`, which already runs after every placement/rotation/drag/tweak mutation, so the arc updates without needing changes at each individual call site.

**Verified:**
- New test `test_firing_arc_visualization()`: places a 360°-traverse cannon with a mast directly in its forward line, confirms both red (blocked) and blue (clear) segments exist, and confirms segment count matches the expected full-circle sweep.
- Visual: `progress_captures/2026-07-12/firing_arc/` — top-down and angled screenshots show a small red wedge exactly where the mast blocks line of sight, rest of the 360° disc blue.
- Full suite: **19/19 green.**

**Commit checkpoint:** see git log.

---

### Item 2 shipped: free-form rotation ring (replaces 90°-only snap)

MOUNTING_AND_ARMOR_SPEC.md #3: rotation should be free-form via a grab-handle ring, Spore/KSP style — done ahead of the face-based mounting work since that depends on it.

- New `gizmo_rotate_ring.gd` + a `HandleRotate` torus node added to `Gizmo3D.tscn`. Converts continuous mouse drag around the ring into a per-frame angle delta (not an absolute angle — this means it doesn't need to reconcile reference frames, just `rotate_object_local(UP, delta)` each frame).
- `gizmo_3d.gd`'s `_on_rotated()` applies the delta, updates `yaw_offset` meta (same bookkeeping the old 90° system used, so save/load/undo all keep working unchanged), and mirrors the rotation to the module's symmetry counterpart at `-delta` — same convention the old system used, just continuous instead of stepped.
- The old R-key / "Rotate 90°" button still exist as a quick-align convenience — this adds free rotation, it doesn't remove the snap option.
- Ring only appears for weapon/module categories (matches where the X/Z scale handles already applied) — hidden for hull, locomotion, and armor, none of which make sense to freely yaw-rotate as a placed part.

**Verified:**
- New test `test_free_rotation_ring()`: applies a deliberately non-90°-divisible angle (0.37 rad), confirms the module rotates by exactly that delta (proving it isn't secretly still snapping), `yaw_offset` tracks it, and the mirrored counterpart rotates by `-delta`.
- Visual: `progress_captures/2026-07-12/rotation_ring/` — gold ring visible around the selected cannon alongside the existing scale handles.
- Full suite: **20/20 green.**

**Commit checkpoint:** see git log.

---

### Item 3 shipped: armor becomes a facet-fitting module

MOUNTING_AND_ARMOR_SPEC.md #2 — resolves the hull-level-only vs. spatial-armor tension from earlier today. Genuinely surprising discovery mid-implementation: `_place_weapon`'s "Auto-scale armor to fit facet" block **already existed in the codebase**, computing the correct target dimensions per facet — but it was dormant (armor was hidden from the parts menu since Tuesday) and had two real bugs that would have surfaced the moment it was exposed to a player:
1. It scaled the plate to match the facet's dimensions but never repositioned it to the facet's center — a plate clicked off-center would auto-fit to full size while poking out past the hull edge.
2. Mirroring was unconditional (inherited from the generic weapon-mirroring path), so a top/bottom/front/back plate — already centered on the symmetry plane — would get an identical duplicate stacked exactly on top of itself. Only left/right plates have a real mirror position.

**Shipped:**
- Un-hid `armor_plating` from the parts menu (reverses Tuesday's exclusion, now safe since the feature is complete).
- Fixed both bugs above: plates now center on their facet regardless of click position, and mirroring only fires for left/right facets.
- **Combat integration, deliberately scoped down** (see DECISIONS_NEEDED.md "Armor-module combat integration scoped to aggregate"): armor modules add an aggregate threshold/reduction bonus to `take_damage()` in both `battle_unit.gd` (Skirmish) and `player_vehicle.gd` (Test Range) — proportional to the modules' own `get_hp()`, which already scales with facet area via the existing volume-based `ModuleData` formula. Full per-facet directional hit resolution would need `take_damage()`'s signature changed to carry hit-direction, called from multiple sites — judged too large a change to make unattended without playtesting the balance, so logged as a follow-up rather than attempted.

**Verified:**
- New test `test_armor_module_facet_fitting()`: places a top-facet plate (clicked off-center) and confirms it auto-fits to the hull's exact footprint, centers regardless of click position, and does NOT mirror. Places a side-facet plate and confirms it DOES mirror to the opposite side.
- New test `test_armor_module_combat_bonus()`: confirms a hit that would normally punch through the baseline threshold is negated once an armor module's bonus applies. Ran 5x to confirm the subsystem-stripping RNG branch doesn't introduce flakiness (both possible branches converge on the same outcome by construction).
- Visual: `progress_captures/2026-07-12/armor_module/` — top plate exactly matches hull footprint, side plates visible as mirrored strips on both edges.
- Full suite: **22/22 green.**

**Commit checkpoint:** see git log.

---

### Item 4 shipped: face-based weapon mounting

MOUNTING_AND_ARMOR_SPEC.md #3. **Scoping choice, logged upfront:** implemented as a generic, type-agnostic treatment layer (facet classification → mount style → position/hardware adjustment) rather than bespoke per-weapon-type visual reconstruction for all ~20 weapon types — the latter would be a much larger art-authoring undertaking than fits this pass with consistent quality. The mechanical differentiation (embed depth, mount hardware, the frame-built/turret exceptions) is real and type-agnostic; a fully bespoke sponson/turret mesh per weapon type is a natural future art pass, not attempted here.

- `ModuleCatalog.get_mount_style(type_id, facet)`: single source of truth. `basic_cannon` → `"turret"` (existing enclosed-turret visual, explicitly left unchanged per Chris's instruction). `gauss_railgun`/`heavy_howitzer` → `"frame_built"` (embedded deep into the hull, no extra hardware — the whole vehicle aims, not the weapon). Top facet → `"pintle_top"`. Bottom facet → `"pintle_bottom"` (inverted pintle). Everything else (front/back/left/right) → `"sponson"`.
- `module_placer.gd`: new `_classify_hull_facet()` helper (reused pattern from armor's facet classification). Sponson and frame-built weapons get pushed inward along the surface normal (embed depth scaled by mount style) so they read as embedded rather than surface-mounted.
- `visual_builder.gd`: new `add_mount_hardware()` adds a generic pintle-post (top/bottom) or sponson collar ring (side/front/back) on top of whatever the weapon's own type-specific visual already builds — turret and frame-built styles get nothing extra.
- **Real bug caught mid-implementation, not by a test but by looking at the screenshot:** placing a module dead-center (local x ≈ 0 — a very natural placement for a "frame_built" railgun/howitzer on the front/back centerline) mirrored it onto its own exact position, producing a fully-overlapping duplicate that read as a false clipping-red flag. This is the *same underlying bug class* as the armor mirror-centering fix earlier today, but the earlier fix only covered the `armor` category — generalized the fix to any module placed on the centerline, since the failure mode isn't mount-style-specific.
- **Persistence caught proactively (before it could bite):** `visual_builder.gd`'s `rebuild_visual()` — called on every gizmo tweak-drag frame — clears all `MeshInstance3D` children and rebuilds from scratch. Mount hardware would have silently vanished on the first tweak of a mounted weapon. Fixed by storing `mount_style` as module metadata (and persisting it through save/load in `blueprint_manager.gd`) so `rebuild_visual()` and `reconstruct_vehicle()` both know to re-add it.

**Verified:**
- New test `test_face_based_weapon_mounting()`: confirms `basic_cannon`/`gauss_railgun` get their exception treatment (no hardware), a top-facet weapon gets `pintle_top` hardware, a side-facet weapon gets `sponson` hardware and is embedded inward from the clicked point, and mount hardware survives a `rebuild_visual()` call (the tweak-drag persistence risk above).
- New test `test_centerline_placement_does_not_self_mirror()`: regression-guards the dead-center mirror-overlap fix.
- Visual: `progress_captures/2026-07-12/mounting/` — pintle stand visible under the top-mounted weapon, sponson collar visible for the side-mounted weapon, railgun correctly shows its normal purple emissive color (not clipping-red) after the centerline fix.
- Full suite: **24/24 green.**

**Commit checkpoint:** see git log.

---

### Item 5 shipped: hull tweakability beyond uniform scaling

MOUNTING_AND_ARMOR_SPEC.md #4, the final item.

- **Overall SIZE control: verified, not built.** The existing hull gizmo already provides independent X/Y/Z scale handles (confirmed working throughout every test today) — this already satisfies "an overall size scale control for the whole hull."
- **Per-hull custom deform rigging: proof-of-concept for `interceptor_hull` only** (see DECISIONS_NEEDED.md for why the other 6 are deferred — this needs a real design decision per hull about what region is interesting to deform, not just mechanical repetition). Added a "Nose Taper" slider that reshapes just the nose region of the *actual authored mesh* via `MeshDataTool` — genuine runtime per-vertex editing (region-selected by local Z position with linear falloff into the untouched hull body), not a preset-shape swap or a second mesh layered on top. New `hull_deform.gd`.
- **Real bug found and fixed along the way:** `blueprint_manager.gd`'s `reconstruct_vehicle()` never used the authored `.glb` hull meshes at all — every loaded blueprint or battle-spawned unit rendered as a plain box regardless of hull type, meaning the nice hull shapes only ever appeared in the Design Lab. Found because it would have made the nose taper invisible outside the Design Lab. Fixed to match the Design Lab's own mesh-selection logic — this improves the visual fidelity of every hull type in Skirmish/Test Range, not just interceptor_hull.

**Verified:**
- New test `test_hull_nose_taper()`: confirms the deform produces a different mesh resource, confirms `MeshAssetLoader`'s shared cached mesh is never mutated (deform always returns a fresh copy), and confirms the taper survives serialize → reconstruct_vehicle → battle-spawn.
- Visual: `progress_captures/2026-07-12/nose_taper/` — default vs. 0.35x sharp taper vs. 1.4x flared, clearly distinct silhouettes, no mesh corruption/artifacts.
- Full suite: **25/25 green.**

**Commit checkpoint:** see git log.

---

## 2026-07-12 — v1.0-beta tagged (Sun-Thu work completed in one continuous session)

Chris asked me to push through as much of the week's plan as possible in a single extended session rather than waiting on cron cycles that turned out not to be available in this environment. Completed the full Sunday-through-Thursday plan; tagging `v1.0-beta` here rather than padding out Friday/Saturday with manufactured busywork, since the actual beta bar (defined in the original plan) is met:

- ✅ Full Design Lab loop: hull select/scale, all 6 locomotion archetypes (now all actually tweakable — 3 of 6 were silently non-functional at the start of this session), weapon/module placement + tweaking (now verified catalog-wide — no dead tweaks), symmetry, save/load.
- ✅ Skirmish playable start to finish (verified via headless sim: economy, AI waves, HQ destruction, game-over).
- ✅ Test Range functional (untouched this week, continuously regression-checked by the full suite).
- ✅ Damage/armor model intact (untouched this week except removing a menu item that contradicted its own design doc).
- ✅ Every part/hull archetype has a coherent, distinct authored mesh (audited Tuesday — coverage was already 100%, no gaps to fill).

**Test suite grew from 11 to 18 suites this week**, every new one added because a real bug was found, not for coverage's sake. Full list of what shipped is in the dated entries below (Sun/Mon/Tue/Wed/Thu). `DECISIONS_NEEDED.md` has 6 logged judgment calls, none blocking, all with reasoning for whoever picks this up next.

---

## 2026-07-12 (Thu) — Integration pass: full design→battle pipeline verified

**Shipped:**
- Ran the existing `scratch/sim_skirmish.gd` headless probe (~110s of simulated Skirmish time) against the real bundled rosters — economy ticks, enemy AI launches waves, HQ damage/destruction and game-over all fire correctly with the week's changes in place. No script errors.
- New test `test_design_to_battle_integration()`: designs a unit combining three of this week's fixes at once (legs at a non-default size, `gauss_railgun`'s now-working `rail_length` gizmo tweak, `sensor_suite`'s now-correctly-targeted `mast_height` tweak), serializes it, and reconstructs it through the *exact* code path Skirmish/Battlefield use to spawn real battle units (`reconstruct_vehicle(..., is_designer=false)`) — confirming none of this week's fixes are designer-only and silently lost on spawn.
- **Safety note:** this test deliberately avoids calling `save_blueprint()` — that writes to `user://blueprints/`, Chris's real save directory with ~30 real saved designs in it. Used `serialize_hull()` + `reconstruct_vehicle()` directly instead (the same underlying code save/load calls) to prove the pipeline without touching disk. Verified via file timestamps that no blueprint files were created or modified by this session.

**Verified:**
- Full suite: **18/18 green.**

**Commit checkpoint:** see git log.

---

## 2026-07-12 (Wed) — Foundation/defense design-lab parity: confirmed, not built

**Audit finding (third day in a row the "gap" turned out mostly not to exist):** placement, tweaking, mirroring, undo/redo, and blueprint serialization are all hull-type-agnostic code paths — the only foundation-specific special case anywhere in the codebase is a single locomotion block in `module_placer.gd`. Everything else (gizmo drag, TWEAK_SPECS sliders, symmetry, undo history, save/load) already applies identically to a `pillbox_foundation`/`tower_foundation` hull as to a vehicle hull, confirmed by cross-referencing every `is_foundation` usage in the codebase (there are exactly 3, one of which is the deliberate locomotion block).

**Verified, not fixed** (nothing was broken):
- New test `test_foundation_design_lab_parity()`: places a pillbox foundation, confirms locomotion is correctly rejected, places a mirrored weapon pair, rotates, undoes, and serializes — all matching vehicle-hull behavior.
- Visual spot-check of the bundled `gatling_pillbox.json` loadout (octagonal bunker + twin rotary gatling turrets) in `progress_captures/2026-07-12/hull_variety_qa/verify_shot_2.png` — coherent, no clipping, no broken meshes.
- Full suite: **17/17 green.**

**Found and deferred (logged in [DECISIONS_NEEDED.md](DECISIONS_NEEDED.md)):** Factions_and_Buildings.md names a third example foundation type ("Fortress Wall") that doesn't exist in the catalog. Not fixing this week — it needs new Blender-authored geometry and the headless-import pipeline is fragile enough that I don't want to risk it unattended, and it reads as illustrative example text rather than a hard requirement.

**Commit checkpoint:** see git log.

---

## 2026-07-12 (Tue) — Mesh/part kit audit: coverage is actually complete; fixed real quality bugs instead

**Audit finding (another pleasant surprise): there are no missing part meshes.** Cross-referenced every `_part("...")` call in `visual_builder.gd` against the authored `.glb` files in `assets/models/parts/` and `assets/models/hulls/` — every weapon/module type that requests an authored mesh has one, and all 7 hull/foundation catalog entries have a matching hull mesh. The planned "gap-fill" premise didn't hold up, so today's work shifted to quality/consistency issues found via a visual QA sweep instead of new mesh authoring.

**Shipped:**
1. **`armor_plating` removed from the placeable parts menu.** It's a leftover catalog entry (category "armor") that was still clickable in the Modules tab despite Damage_And_Armor_Model.md's explicit, deliberate decision to keep armor hull-level-only (logged in [DECISIONS_NEEDED.md](DECISIONS_NEEDED.md) yesterday). It had no tweaks and no dedicated visual — exposing it just contradicted the documented design and confused the parts bin. No bundled loadout referenced it, so this was safe to hide with zero save-compat risk.
2. **Sensor mast dish was absurdly disproportionate** — a fixed 0.7-radius disc (1.4 diameter) mounted on a module with a 0.5-wide footprint, nearly 3x oversized. Screenshotted during the hull-variety QA pass (`progress_captures/2026-07-12/hull_variety_qa/`) and was obviously wrong at a glance. Now scales with the module's own footprint.
3. **The "Radar Mast Height" slider was mislabeled** — it scaled the *dish's* thickness (`children[1]`), not the *mast's* height (`children[0]`). The slider visibly did something (the flat dish got very slightly thicker) so it wasn't obviously broken, but it didn't do what its label said, and didn't move the dish to match. This is exactly the kind of "looks tweakable but isn't" bug the DESIGN_VISION.md differentiation test is meant to catch. Fixed to scale the mast and reposition the dish to ride its top.

**Verified:**
- New test `test_sensor_mast_tweak_and_proportions()`: checks dish radius stays proportional to module footprint, and that `mast_height` scales the mast (not the dish) with the dish correctly repositioned. Caught a real scope bug of my own while writing it — `_apply_tweak_deformations()` didn't have `base_size` in scope, a straight compile error, fixed by threading it through as a parameter.
- Extended `scratch/VisualVerify.tscn` to cover all 7 hull types (previously 5) for a full-coverage visual sweep, screenshots in `progress_captures/2026-07-12/hull_variety_qa/`.

**Follow-on finding (same session, same bug class, bigger scope):** finding one mislabeled tweak (sensor mast) prompted checking whether *any* tweak across the whole catalog does literally nothing. It's a direct test of DESIGN_VISION.md's differentiation goal at the single-tweak level. Found and fixed three:
- `cluster_dispenser`'s "Dispersion Matrix Size" was **completely dead** — no visual case existed in `visual_builder.gd`'s deform switch at all, and `dispersion` wasn't in `module_data.gd`'s weight/dps/cost whitelists either. Slider moved, number changed, nothing else happened. Now scales the dispenser's footprint and contributes to weight.
- `gauss_railgun`'s "Electromagnetic Rail Length" was **silently dead specifically in the authored-mesh path** (which is the path actually used, since `rail_array.glb` exists) — the deform loop assumed a multi-child procedural layout that only exists in the never-taken fallback branch. Fixed to branch on child count.
- `heavy_howitzer`'s "elevation" and `flak_cannon`'s "fuse_setting" had visuals but zero stat effect (missing from `module_data.gd`'s weight whitelist) — added.
- Wrote `test_no_dead_tweaks()`: a systematic regression test that pushes every numeric tweak in `TWEAK_SPECS` to its max value and asserts it changes *either* the visual mesh transforms *or* weight/dps/cost. This is now a standing guardrail against this entire bug class, not just the three instances found today.
- Full suite: **16/16 green.**

**Commit checkpoint:** see git log.

---

## 2026-07-12 (Mon) — Undo/Redo implemented (was entirely missing)

Design_Lab_UI_UX.md's Top Bar spec explicitly lists "Undo/Redo" as part of the Admin Tools row, but there was zero implementation of it — no history stack, no keybinding, no button.

**Shipped:** full snapshot-based undo/redo.
- `blueprint_manager.gd`: extracted the dict-building half of `save_blueprint()` into a new `serialize_hull(hull)` function (no file I/O, no clipping-gate) so it can be reused for both saving and in-memory undo snapshots.
- `module_placer.gd` (the MainLab root controller): `push_undo_snapshot()` / `undo()` / `redo()` / `can_undo()` / `can_redo()`. Undo tears down the current hull and reconstructs it from the previous snapshot via the existing `reconstruct_vehicle()` path (same code used for loading saved blueprints — reused, not reinvented). History capped at 50 entries.
- Snapshot is pushed at the *start* of a mutation (module placement, deletion, rotation, drag-move, gizmo tweak-drag, hull-scale drag, armor material/thickness, faction change) so one undo = one user-visible action, not one-per-frame. Slider-based tweaks hook `drag_started` (not `value_changed`) for the same reason.
- Bound to Ctrl+Z / Ctrl+Y (and Ctrl+Shift+Z), plus Undo/Redo buttons added to the stat panel UI.

**Verified:**
- New test `test_undo_redo()` in `run_tests.gd`: place → undo → redo, asserting module count at each step.
- Real-scene integration smoke test (not just synthetic test scaffolding) via `scratch/MainLabSmoke.tscn`: placed a railgun pair + wheels on a real hull, called `undo()`/`redo()` on the actual running MainLab scene, screenshotted all three states. Confirms the real UI buttons render and the absolute `/root/MainLab` node-path lookups used by `gizmo_3d.gd` actually resolve outside of synthetic tests. See `progress_captures/2026-07-12/undo_redo_integration/` — wheels visibly present → gone after undo → back after redo, with HP/weight/DPS stat panel numbers updating correctly at each step (640/448/220 → 240/288/220 → back).
- Full suite: **13/13 green.**

**Also shipped today:** Design Lab camera was orbit+zoom only — Design_Lab_UI_UX.md explicitly specs "rotate, pan, and zoom" but pan didn't exist, so there was no way to recenter on a large hull without zooming out. Added middle-drag pan (matches the Skirmish camera's documented convention), distance-scaled. Pan math pulled into a pure `_compute_pan_delta()` function and unit tested directly — headless Godot can't simulate held mouse-button state via `Input.parse_input_event` (confirmed empirically: `is_mouse_button_pressed` stayed false after a parsed press event), so a real end-to-end input test wasn't possible; the math itself is fully covered instead. Suite now **14/14 green.**

**Commit checkpoint:** see git log.

---

## 2026-07-12 (Sun) — Design Lab audit vs DESIGN_VISION.md + first fixes

**Audit finding (the headline surprise): the Design Lab is much closer to the Spore/KSP vision than the "Forged Battalion trap" worry assumed.** Most weapons already have real continuous tweak parameters (caliber, barrel length, drum size, etc. — see `stat_calculator.gd`'s `TWEAK_SPECS`), wired to both a 3D gizmo-drag interface (`gizmo_3d.gd`) *and* a slider popup, with live stat feedback (HP/weight/cost/DPS recompute per-frame) and working bilateral symmetry (`mirrored_counterpart` propagates tweak changes to the mirror twin, confirmed at both tweak-time and placement-time in `module_placer.gd`). This is not a discrete-swap-only system.

**Real gaps found and fixed today:**
1. **Three locomotion types had non-functional or missing tweak sliders.** `legs` and `anti_grav` had a "size" slider in the UI that updated internal settings but `update_locomotion()` never read the value — moving the slider did nothing. `hover_engine` had no tweak UI at all. Only `wheels`/`tracked_treads`/`helicopter_rotors` (3 of 6 locomotion archetypes) actually responded to their sliders. This directly failed the DESIGN_VISION.md differentiation test: two players could not have diverged on leg length, anti-grav ring size, or hover pad size no matter what they did. **Fixed** — all three now scale correctly and feed into `ModuleData.scale_multiplier` (so weight/HP/cost respond too), verified visually (see `progress_captures/2026-07-12/locomotion_tweak_fix/`) and with a new automated test.
2. **Three weapons (`mortar_array`, `cluster_dispenser`, `missile_pod`) had slider-based tweaks but no 3D gizmo-drag mapping** — tweakable via the popup, but not via the tactile "grab the part and pull" interaction the vision doc calls out as core to the Spore feel. **Fixed** — added axis mappings in `gizmo_handle.gd`'s `get_tweak_for_axis`.

**Gaps found and explicitly NOT fixed this week (see [DECISIONS_NEEDED.md](DECISIONS_NEEDED.md) for full reasoning):**
- Armor "mass distribution" (DESIGN_VISION.md's own example) conflicts with an existing, deliberate anti-tedium design decision in Damage_And_Armor_Model.md that rejects spatial armor placement. Kept the existing hull-level material×thickness system; flagged the doc conflict rather than picking a side.
- Directional/facing armor thresholds are documented as intended but unimplemented — deferred as a combat-model (not Design Lab) concern.
- Firing-arc cone visualization from Design_Lab_UI_UX.md is unimplemented — deferred as a stretch goal behind tweak-depth work.
- Grid-snap placement from Design_Lab_UI_UX.md was never built; current freeform placement is being kept deliberately since it better serves DESIGN_VISION.md's differentiation goal.

**New test added:** `test_locomotion_tweak_parity()` in `run_tests.gd` — regression-guards the legs/anti_grav/hover_engine fix and the three new gizmo axis mappings.

**Verified:**
- Full suite: **12/12 green** (was 11 suites; added 1). Combat-sim HP numbers shifted slightly (1720→1650 vs baseline 1720→1656) — expected, since the locomotion fix changes computed stats for any roster/loadout unit using legs/anti_grav/hover with non-default size settings.
- Visual: `progress_captures/2026-07-12/locomotion_tweak_fix/` — 6 screenshots (3 types × size 1.0/2.0) confirm the fix visually.

**Commit checkpoint:** see git log.

---

## 2026-07-12 (Sat) — Day 0: Setup

**Shipped:**
- Initialized git repo at `E:\Build-A-Bomber` (was not previously under version control). `.gitignore` excludes bundled engine binaries (Godot exe/zip, UPBGE ~777MB) and the `.godot/` cache — these are large, static, and regenerable, so keeping them out of git keeps checkpoints fast.
- Baseline commit `c6f472f` captures the entire prototype as it stood before this session's changes — the revert target if anything goes sideways.
- Created `PROGRESS.md` (this file) and `DECISIONS_NEEDED.md` for judgment-call tracking.
- `DESIGN_VISION.md` already existed from prior conversation (Chris's Spore/KSP reference points + the Forged-Battalion-trap differentiation test) — this now drives the Sunday audit.

**Verified:**
- Full headless test suite (`run_tests.gd`, 11 suites) — **all green** at baseline. This is the reference point for "did I break anything."

**Next:** Sunday Design Lab audit against `DESIGN_VISION.md` — specifically checking discrete-swap-only vs. continuous tweakables, and whether symmetry-aware editing is real.
