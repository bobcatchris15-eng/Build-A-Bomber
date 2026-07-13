# Decisions Needed / Judgment Calls Log

Newest entries first. Each entry: the question, the default I'm proceeding with, and why. Anything marked **BLOCKING** means I stopped that thread entirely and need Chris's input before continuing it — everything else is "proceeding on best judgment, flagging for review."

---

## 2026-07-13 (new session, cont'd 3) — Rebuilding against VISUAL_ART_DIRECTION.md + size-tiered manufactories

**Not blocking.**

**No baked curvature/AO masks - procedural approximations instead.** VISUAL_ART_DIRECTION.md's section 2 calls for masks "baked ONCE per mesh/module" (curvature/edge-wear, cavity/AO, panel/trim). Given this week's Blender import pipeline has repeatedly been the most fragile part of this project (hung `--headless --editor --import` processes, axis-convention bugs, needing an isolated-copy workaround), adding a real per-mesh bake step for every existing hull was the one piece of this doc I deliberately didn't implement literally. Instead: wear uses `fwidth(world_normal)` (a screen-space curvature proxy - genuinely high at edges/corners, near-zero on flat panels, needing zero new assets) blended with noise for organic patchiness; grime uses a "low local-Y + noise" proxy instead of a real cavity map; panel-lines/trim use a world-space periodic seam grid instead of a baked trim mask. This keeps the doc's INTENT (wear concentrates on edges, not randomly; a shared "kit of parts" grammar; trim gets its own color) while adding zero new Blender-pipeline risk. Logged explicitly since it's the one place I diverged from the doc's literal mechanism, not just its parameter names.

**decal_tint is a wired-but-inert placeholder.** The doc's shared stencil/hazard/mascot decal atlas needs real authored texture content (exactly the kind of hand-painted per-faction asset the whole shader system exists to avoid) - kept the uniform in the parameter model for forward-compatibility but it currently does nothing visually. Flagging so it isn't mistaken for a bug later.

**World-space (not local/object-space) sampling for every procedural mask - a real bug caught by actually testing the stretch case**, not just reading the doc's warning. First implementation used raw `VERTEX` (local mesh space) for noise input; local space doesn't change when a Node's `scale` is applied via `MODEL_MATRIX`, so a stretched hull would have shown the SAME pattern enlarged/smeared, not more repetitions - the exact failure mode the doc calls out. Fixed with a `world_pos` vertex-shader varying (`MODEL_MATRIX * VERTEX`) and confirmed with a real screenshot (`stretch_invariance.png`) showing a 3x-stretched hull's panel-line grid repeating 3 times, not smearing into one blur.

**Team-color problem (doc section 1.6) - not implemented this pass.** The doc correctly flags that faction-only identity gives two same-faction players no way to tell units apart. A real fix (a separate `team_color` parameter/decal layered on top) is a genuine scope addition beyond "rebuild the shader against the doc" - not attempted here, logged as the clear next increment if/when actual multiplayer or same-faction-vs-same-faction matches become relevant (currently every match is exactly 2 teams, each free to pick ANY of the 10 factions independently per MatchSetup, so this can already happen today).

**7 invented factions from the previous commit were fully replaced, not kept alongside.** Chris's design-doc pass produced the "real" 7 (Salvage Union/Crimson Concordat/Glacier Syndicate/Dune Runners/Ledger Combine/Bayou Irregulars/Aerodrome Cartel) to replace my earlier placeholder guesses (Scavengers/Zealots/Nomads/Cartel/Engineers/Berserkers/Cybernetics) - not additive, since the roster is meant to stay at exactly 10. 3 of the 7 needed genuinely new mechanics (Crimson Concordat's live low-HP dps ramp, Glacier Syndicate's terrain-penalty reduction, Bayou Irregulars' detection-range reduction) rather than reusing what I'd already built; the other 4 renamed/reflavored mechanics I'd already implemented and tested (metal cost discount, build-time reduction, harvest rate, and a NEW airborne-only speed check for Aerodrome Cartel, since none of the original 7 had an "only applies to flying units" bonus).

## 2026-07-13 (new session, cont'd 3) — Size-tiered manufactories: hull mapping, and why "start with all 3" instead of unlockable progression

**Not blocking.**

**Exact hull -> tier mapping** (weight breakpoints: light &le;150, medium &le;400, heavy &gt;400 - chosen to split the current 12 mobile hulls into even 4/4/4 groups, not a domain-specific rule):

| Tier | Hulls (weight) |
|---|---|
| Light | interceptor_hull (65), light_hull (100), small_boat_hull (130), flying_wing_hull (140) |
| Medium | fuselage_hull (210), medium_hull (250), airship_hull (260), naval_hull (380) |
| Heavy | assault_hull (500), sponson_hull (650), heavy_cruiser_hull (680), heavy_hull (800) |

Foundations (pillbox/tower/fortress_wall_foundation) aren't tiered at all (`get_hull_size_tier()` returns `""`) - static defenses are placed directly via the Armory/build-placement flow, never queued from any manufactory, so a production tier is meaningless for them. Deliberately cross-domain by design, per Chris's explicit correction: `small_boat_hull` (naval) and `flying_wing_hull` (air) share the Light tier with `interceptor_hull` (ground); `heavy_cruiser_hull` (naval) shares Heavy with `heavy_hull` (ground). `assault_hull` (500) landing in Heavy despite sitting numerically closer to `naval_hull` (380) than to `sponson_hull` (650) is the one slightly-arguable case from a pure quartile-split - kept it there since 500 is still well clear of the 400 breakpoint and "assault" reads as a heavy-hitter class thematically anyway.

**Every match starts with all 3 manufactory tiers already built, rather than the player unlocking Medium/Heavy over time.** Chris's framing implied a real "which manufactory can you use right now" gameplay question, which could support either an unlockable-progression read or a "always-available, just costs more to build extras" read. Went with the latter for two concrete reasons: (1) `enemy_ai.gd` has never placed new buildings of any kind (it only ever produces units from buildings that already exist) - giving the AI a real "build a bigger manufactory when affordable" decision would be a genuinely new, untested AI capability, a much bigger and riskier addition than the tier-gating mechanic itself; starting with all 3 sidesteps that entirely while still making the tier-gate real (production of a given tier genuinely requires that specific building to exist and stay alive). (2) Every one of the 8 already-verified map start positions stays legal unchanged - the Light Manufactory keeps the map's exact original `factory` spawn point, Medium/Heavy are placed at fixed offsets from it, verified against all 8 maps' smoke tests rather than assumed safe.

**A real balance side-effect, caught by the existing "no Energy deficit at match start" test, not just noticed by eye:** starting static buildings grew from 3 (hq/factory/refinery) to 5 (hq/refinery/3 manufactories), pushing baseline upkeep from 9.0 to 15.0 against the old `ENERGY_HQ_BASELINE_CAPACITY` of 10.0 - every match would have silently started in Energy deficit. Retuned to 16.0 (preserving the original ~1.0 headroom margin, just against the new 5-building baseline) rather than leaving the old value and hoping it didn't matter.

**Other base-building variety Chris flagged (generator/power-plant building, radar/comms building tied to vision, repair depot) - deliberately NOT built this pass, logged here rather than silently dropped.** All three are real, well-scoped candidates for a future increment (a generator building would need its own PREFAB_STATS entry + Energy-capacity contribution, similar shape to how defense buildings already contribute capacity; a radar building is nearly a copy of the vision-bonus pattern `sensor_suite`/Technocrats already established; a repair depot would need a stationary-heal-aura mechanic distinct from the existing mobile `repair_array` module). Prioritized finishing the shader rework + faction replacement + the explicitly-corrected manufactory-tier system solidly (with real tests/screenshots for each) over starting 3 more new building types in the same pass - per Chris's own "use your judgment on what's worth building now vs. logging for later."

---

## 2026-07-13 (new session, cont'd 2) — Faction visual identity + 10-faction expansion: scope calls

**Not blocking.**

**Applied the faction shader material to the ENTIRE hull mesh as one uniform paint job, not per-part tinting.** `reconstruct_vehicle()`/`update_hull_appearance()` set `material_override` on just the hull's own `MeshInstance3D` (one node) - I didn't touch `visual_builder.gd`'s ~35 module-building functions, which still give weapons/locomotion/etc. their own hardcoded per-part `StandardMaterial3D` colors (barrel=black, wheel=silver, etc.), unrelated to faction. This means a vehicle's HULL BODY shows faction paint, but its bolted-on parts keep their existing individual look - a deliberate middle ground between "faction changes nothing visually except one flat tint" and "faction repaints literally every rivet," and far lower-risk than touching visual_builder.gd's 2000+ lines of individually-authored module materials this late in the week, per Chris's explicit "given how fragile this pipeline has been" framing.

**UI theming stopped at panel BACKGROUNDS, not individual widgets.** `apply_brushed_panel()` targets Panel/PanelContainer/ColorRect background nodes only - Buttons, OptionButtons, Labels, CheckBoxes all keep Godot's default engine theme on top of the brushed backdrop (visible in the Design Lab sidebar screenshot, where the panel's brushed texture is only visible at the edges around the buttons). Re-skinning every individual Control type project-wide would be a much bigger, real UI-framework undertaking (a proper Theme resource with per-faction StyleBoxes for every control type) - out of scope for "brushed anodized aluminum background textures for UI panels," which is what was actually asked for. Flagging this as the natural next increment if Chris wants the faction identity to extend to button chrome too.

**`battlefield.gd`'s separate, pre-existing move-speed/HP formulas got the same table-driven `speed_mult` generalization as `battle_unit.gd`, but NOT the new `hp_mult` (Zealots).** `battlefield.gd` is the Test Range scene's own independent copy of these formulas (not shared code with `battle_unit.gd`/Skirmish) - already a known pre-existing duplication, not something introduced this pass. Generalizing the existing technocrats speed check there was a one-line parity fix; adding a brand new passive (`hp_mult`) to a second, secondary code path that isn't exercised by any of my new tests felt like it would either go unverified or double the test surface for a scope Chris didn't specifically ask to extend (Test Range balance parity). Zealots' HP penalty is real and tested in the main Skirmish path; Test Range specifically is a known gap, logged here rather than silently piecemeal-patched.

**The pre-existing Industrialists armor-weight bonus turned out to be Design-Lab-preview-only, not applied to real battle weight** - discovered while generalizing it to `FactionCatalog.get_passive()`. `stat_calculator.gd`'s `wt_mult` only feeds the sidebar's displayed "Total Weight" stat; the REAL weight used in `battle_unit.gd`'s move-speed calc sums each MODULE's own `get_weight()` (no hull weight, no faction awareness) - hull armor thickness's only real gameplay effect is on HP, not weight/speed. This is a pre-existing gap unrelated to anything asked this pass - I preserved the exact existing (cosmetic-only) behavior via the table lookup rather than trying to fix it, since "does Industrialists' bonus actually do anything in real battle" wasn't part of this ask and fixing it would risk changing established balance without a real request to do so. Flagging it here so it doesn't get rediscovered as a mystery bug later.

**Scavengers'/Engineers' team-level bonuses (`metal_cost_mult`, `build_time_mult`) key off the MATCH's chosen `player_faction`/`enemy_faction`** (same level as the existing Expansionists upkeep/trickle passives), while Zealots/Cartel/Nomads/Berserkers/Cybernetics's bonuses (`hp_mult`, `dps_mult`, `range_mult`, `harvest_rate_mult`, `speed_mult`, `vision_mult`) key off each INDIVIDUAL vehicle's own faction tag (same level as the existing Industrialists/Technocrats bonuses) - deliberately following whichever precedent already existed for that TYPE of bonus rather than picking one level for everything. Team economy concepts (build cost, build time, Energy capacity) naturally belong to the team; per-unit combat/mobility stats naturally belong to whatever faction that specific vehicle was designed under (a player could in principle field a mixed-faction roster, each unit keeping its own designed-in bonus).

---

## 2026-07-13 (new session, cont'd) — Pre-match settings flow: "configurable enemy/team count" scoped down to AI difficulty

**Not blocking.**

Chris's ask included "configurable enemy/team count" alongside faction selection, blueprint import, AI difficulty, and starting resources. Checked the architecture before committing to scope: `skirmish.gd`'s `PLAYER_TEAM`/`ENEMY_TEAM` are hardcoded to exactly 0/1 everywhere - `economy`/`energy_pool` are Dictionaries keyed by those two literal constants (not a generic per-team array), fog-of-war (`_recalc_fog_of_war()`) is written as "player constructs vs. enemy constructs" (two fixed groups, not N), there's exactly one `EnemyAI` instance and one pair of HQs, and every `MapCatalog` map has exactly one `player_start`/`enemy_start` pair (no third/fourth start position exists anywhere in map data). Genuinely supporting a 3rd+ team/opponent would mean reworking the economy/energy/fog-of-war data shape to a per-team array, spawning N `EnemyAI` instances, and adding N start positions to every map (all 8 of them) - a real architecture change, not a pre-match-screen feature, and far outside what a "settings flow" pass should touch.

**Scoped down to AI Difficulty (Easy/Normal/Hard) instead** - a real, if narrower, answer to "make the single opponent configurable." `enemy_ai.gd` already had exactly the right hooks (three timers plus a pity-resource trickle) to scale meaningfully: Hard produces/attacks ~35% faster and recovers from a bad economy check nearly twice as fast; Easy is proportionately slower/more forgiving. This is a genuine gameplay difference (verified by asserting `produce_interval`/`wave_interval` actually differ after `setup()`), not a cosmetic label.

**True N-team/FFA support is the natural next big increment** if Chris wants it - flagging it here explicitly rather than silently under-delivering on the literal ask.

**Faction "Auto" as the actual default, not a specific faction**, for BOTH player and enemy dropdowns conceptually (though the enemy dropdown's initial `OptionButton.selected` is set to "Technocrats" for a friendlier first impression rather than defaulting to the "Auto" index) - "Auto" reproduces the exact old behavior (derive from `roster[0]`'s own faction tag) byte-for-byte, so a player who never touches this screen's dropdowns gets identical behavior to before this pass existed.

**Blueprint Library import replaces the "top 8 newest" heuristic entirely when non-empty, not additively** - if the player checks 3 specific designs, exactly those 3 (plus bundled defaults filling remaining roster slots, same as before) go in, not those 3 PLUS the top-8-newest. Leaving zero checked reproduces the old automatic heuristic exactly. This felt like the more honest reading of "importing... into their match roster" - a deliberate selection, not an additional filter on top of the automatic one.

**Starting Resources as 3 named presets (Standard/Low/High), not a free-text numeric field** - avoids input validation/sanitization work for a settings screen, and "Standard" maps to the sentinel `-1` (use Skirmish's own hardcoded default) rather than a hardcoded copy of 450/150, so a future balance change to those defaults doesn't silently desync from this screen's "Standard" preset.

**Verified:** 86/86 automated tests green (1 new - a single consolidated test proving every MatchConfig override field actually reaches a real `Skirmish` instance: both factions, a deterministically-named imported blueprint appearing in the roster, starting metal/crystal on both teams, and `enemy_ai.gd`'s own timers measurably changing under "hard"). Windowed screenshot of the new `MatchSetup.tscn` screen confirms all 4 dropdowns, the real scrollable Blueprint Library checklist (pulling the user's actual saved designs), and the Back/Start Match buttons stay visible (not the same off-screen-overflow bug `MapSelect.tscn` had before its `ScrollContainer` fix - this screen's button row lives outside the scrolling list from the start).

---

## 2026-07-13 (new session) — Map variety batch: what survived from the stuck session, and the new mechanism/map judgment calls

**Not blocking.**

**Nothing from the previous (stuck) session's map/bridges/cities exploration was recovered or reused.** Checked `git log`, `PROGRESS.md`, `DECISIONS_NEEDED.md`, `git stash list`, and the working tree for any trace of the "map_catalog.gd/terrain_builder.gd can support bridges and cities almost entirely as data" analysis that session reportedly reached - found nothing anywhere. Whatever conclusions it reached lived only in that session's own context, which a fresh session has no access to. Built the bridge/building mechanisms from scratch by reading the current `terrain_builder.gd`/`map_catalog.gd` directly rather than trying to reconstruct the prior session's reasoning.

**Bridges don't block naval/amphibious passability underneath.** A bridge's navmesh carve-out only touches `_build_ground_faces()` - `water_map`/`deep_water_map`/`amphibious_map` are untouched, so naval units float and pass freely under a bridge, same as a real river bridge. Considered making bridges a hard block for naval units (real bridges have physical pylons a ship could plausibly hit), but that would need bridges to ALSO carve holes into water_map, which is more invasive for a benefit (blocking a boat under a bridge) nobody asked for - kept the simpler, more permissive default.

**`is_position_blocked()` still treats a bridge's footprint as blocked** (it's still literally inside a `water_areas` rect) even though the ground navmesh now lets units walk across it - deliberately NOT special-cased to allow building placement on a bridge deck. A factory or refinery sitting on a narrow river crossing is a strange, fragile thing to allow by default with zero use case driving it; if this turns out to matter (e.g. wanting a defense turret guarding a bridge), it's a small follow-up (exempt bridge rects from the water check in `is_position_blocked()` specifically), not a redesign.

**Vision LOS raycast uses a fixed eye-height offset (1.5), not each construct's real height**, mirroring `auto_weapon.gd`'s own existing "+0.5" target-center convention for its weapon-fire LOS check rather than inventing a more precise (and more expensive) per-construct height lookup. Good enough for "does a building genuinely hide what's behind it," not meant to model precise sightlines over a crouching-height wall.

**Obstacles (ALL of them, not just new city buildings) now block vision, not just movement/weapons** - a deliberate generalization rather than a city-map-only special case, since existing rock-cluster obstacles are already real `StaticBody3D` colliders on the exact same collision layer (1) `auto_weapon.gd`'s weapon-fire LOS check already uses. Making vision consistent with that existing convention was more principled than inventing a separate "which obstacles count as vision-blockers" flag - and it's a free improvement to `highland_chokepoint`'s rock walls and `coastal_strand`'s rock clusters too, not scoped narrowly to `urban_sprawl`.

**Why these 4 specific new maps** (`twin_bridges`/`twin_summits`/`close_quarters`/`urban_sprawl`), out of everything the task listed (larger map, smaller map, multi-lane bottleneck, two contested points, a bridge chokepoint, an urban map): rather than building 6 near-duplicate maps for 6 bullet points, paired up orthogonal traits that reinforce each other - `twin_bridges` is simultaneously the larger map AND the bridge chokepoint AND a multi-lane bottleneck (two lanes, via two bridges); `close_quarters` is simultaneously the smaller map AND a second, differently-shaped multi-lane bottleneck (three lanes, via rock walls, no water). `twin_summits` and `urban_sprawl` each cover their one remaining ask (two contested points, city cover) without needing a forced pairing. Four maps this way cover every bullet point Chris listed with genuinely distinct play patterns, not padding.

**Scope not attempted this pass:** true N-player/FFA team count (see the next entry, logged separately since it belongs to the pre-match-settings half of this batch).

---

## 2026-07-13 — Omniwheels: decoupling velocity from facing at the `_steer_towards()` level, and what "facing a fixed direction" means for a MOVE order

**Not blocking.**

Batch E item 5 (final item), the one Chris flagged as needing real steering code changes, not just a new mesh. Found the right seam by first reading `_kite_reposition()` (built earlier this project for facet-aware kiting) - it ALREADY rotates the hull toward one direction while setting velocity toward a completely different one (retreat direction vs. best-facet-facing direction), which is exactly the decoupling primitive omni movement needed. Reused that pattern rather than inventing a new one.

**The change:** a new `is_omni` flag (derived from a new `"omni"` trait, same mechanism as `is_flying`/`is_naval`/etc.) gates a branch inside `_steer_towards()` - every other ground/hover locomotion type slerps the hull's rotation toward the travel direction and then moves along its own local forward (facing and velocity are the same vector, structurally coupled). The omni branch instead sets velocity directly from the raw (nav-agent-adjusted) direction to the destination and **never touches hull rotation at all**.

**What "facing a fixed direction" means here:** for a plain MOVE order, an omni unit holds whatever heading it already had before the order was given - it doesn't rotate to face the destination, and it doesn't rotate to face the direction of travel either. This is the literal real-world mecanum behavior (a warehouse robot can strafe sideways down an aisle while its front-mounted sensor keeps facing forward) and matches Chris's test description exactly ("facing a fixed direction"). ATTACK-order kiting/flanking logic was left untouched - an omni unit in combat still uses the existing facet-aware kiting system, which already has its own (different) facing logic; this pass only changed plain-MOVE steering, which was the explicit ask.

**Stat/terrain tradeoff, not a pure upgrade:** `omni_wheels` gets a below-default `thrust_coefficient` (130 vs 150) and lower `base_weight_capacity` (300 vs wheels' 350), plus a worse terrain-multiplier row than plain `wheels` across all 4 surface types (real mecanum wheels have a smaller/harder contact patch from the diagonal rollers, and are notoriously bad off-road) - the strafing capability itself is the payoff, not an all-around stat upgrade over plain wheels.

**Verified mechanically, not just visually** (per Chris's explicit ask): a scripted test spawns an omni unit and a plain wheels unit side by side, orders both to a destination directly perpendicular to their shared starting facing, runs 60 physics ticks, and asserts (a) the omni unit's rotation barely changes (<0.05 rad) while the plain wheels unit's does substantially (>0.3 rad - it has to turn to face the target), (b) the omni unit makes real measured lateral progress, and (c) the omni unit actually outpaces the wheeled unit toward that sideways target over the same tick count, since the wheeled unit burns part of its ticks turning. All three passed on the real steering code path, not a mocked one.

**Verified:** 78/78 tests green (1 new, the strafing-comparison test above). Mecanum-look visual (a ring of diagonal rollers around the hub, distinct from a plain wheel_hub) in `progress_captures/2026-07-13/omni_wheels/`.

---

## 2026-07-13 — MkIV rhomboid treads: procedural loop geometry, mount point, and a genuine tougher-but-slower/terrain tradeoff

**Not blocking.**

Batch E item 4: a WWI Mark IV-style full-body track loop, distinct from `tracked_treads`' flat plate-plus-rollers. Built as a new locomotion type `rhomboid_treads` rather than a `tracked_treads` variant, since it needed its own catalog stats (see below) as well as its own visual.

**Visual:** `_build_rhomboid_treads()` traces 22 track-link plates around an ellipse in the local Y-Z plane (catalog `size` deliberately much taller than `tracked_treads`' - `Vector3(1.1, 2.6, 6.5)` vs `(1.0, 0.8, 3.0)` - so the loop genuinely extends above and below the hull, not just flush with its underside), plus two idler drums at the fore/aft turning points echoing the real tank's pointed "track horns." Mounted in `module_placer.gd` centered on the hull's vertical middle (not `tracked_treads`' low/underside bias), since the loop's own geometry already provides the vertical reach. Verified visually: screenshots in `progress_captures/2026-07-13/rhomboid_treads/` show it towering well above the hull top compared to `tracked_treads` staying flush - the actual "wraps the entire body" ask, not just a reskinned tread.

**Not just a reskin mechanically either** - gave it real stat differentiation instead of matching `tracked_treads`' numbers with new geometry: higher `base_weight_capacity` (900 vs 700 - literally the biggest, heaviest ground locomotor in the roster now) but a below-default `thrust_coefficient` (95 vs the 150 default `tracked_treads` uses), reflecting a real Mark IV's ~4mph top speed - tougher but slower, a genuine tradeoff rather than a strict upgrade. Terrain multipliers also differentiate it from `tracked_treads`: better on marsh/snow_mud (the real Mark IV's whole reason for existing was crossing WWI trench mud), worse on rocky terrain (a long, heavy, low-clearance loop is less nimble scrambling over rock than a shorter track run).

Reused `tracked_treads`' width tweak mechanically (same `thrust_contrib`/`capacity_contrib`/terrain-multiplier-modulation formula from the wheels/legs/treads batch, just extended to also match `rhomboid_treads`) rather than inventing a separate tweak system, since the same "wider=more capacity/less speed" logic applies equally well here.

**Verified:** 77/77 tests green (1 new: real spawn count via `module_placer.gd`, a direct stat comparison proving it's genuinely slower-but-tougher than `tracked_treads` at both light and heavy load, and a terrain-multiplier comparison proving the marsh-better/rocky-worse differentiation is real).

---

## 2026-07-13 — Ornithopter wings: new locomotion type (not a variant/module), no "fixed_wing" trait

**Not blocking.**

Batch E item 5 left the "own locomotion type vs. flapping variant of an existing one" call to my judgment. Went with a **new locomotion type** (`ornithopter_wing`), not a variant flag on `fixed_wing_engine` or a new attachable module, because it needs to be a primary propulsion CHOICE a player picks (like `fixed_wing_engine`/`buoyant_envelope`/`helicopter_rotors` already are) rather than an add-on stacked on top of one - matching how the existing three airborne types are structured, and avoiding a special-case branch inside `fixed_wing_engine`'s already-complex banking/minimum-airspeed movement code.

**Mechanically**, gave it `traits: ["airborne", "flapping_wing"]` - deliberately WITHOUT `"fixed_wing"`, so `battle_unit.gd`'s existing `is_fixed_wing` derivation makes it fall through to the same simple hover-arrival movement as `helicopter_rotors`/`hover_engine`/`anti_grav`, not fixed_wing_engine's banking/minimum-airspeed paradigm. This directly matches Chris's framing ("functions similarly to existing flight locomotion mechanically... a genuinely different visual/flavor propulsion option") - no new movement code needed, no aerodynamic simulation added (standing rule intact).

**Visually**, a bat/pterosaur-style angled membrane (shoulder joint + dihedral-swept panel + tapered tip + rib struts) under a `WingPivot` node, deliberately different from both `fixed_wing_engine` (a plain cylindrical engine nacelle, no wing surface at all) and the flat rectangular `_build_wing` add-on module. `battle_unit.gd`'s per-physics-tick update oscillates `WingPivot.rotation.x` with a sine wave (real flapping motion, not a static pose or a continuous spin like the rotor animation) - verified this is a genuine over-time effect, not baked into the mesh, with a scripted before/after rotation check.

base_weight_capacity (300) sits between `helicopter_rotors` (250, strict hover budget) and `fixed_wing_engine` (380, airspeed-assisted) - a flapping wing generates real lift like a fixed wing but less efficiently than one built for sustained forward flight.

**Verified:** 76/76 tests green (1 new: real placement via `module_placer.gd` spawns exactly 2 instances each with a `WingPivot`, trait check confirms airborne-without-fixed_wing, and a scripted before/after rotation check proves the flap animation genuinely changes over time). Screenshots in `progress_captures/2026-07-13/ornithopter_wing/` - `flying_wing_hull` in particular reads as a distinctly bat/pterosaur-like silhouette, clearly differentiated from the other two flight types.

---

## 2026-07-13 — Wheels/legs/treads tweaks: what was already real, what needed a genuine thrust-vs-capacity tradeoff, and the exact tradeoff shape chosen

**Not blocking.**

Batch E items 2-4. Before changing anything I checked what already existed, since Chris's ask ("make locomotor tweaks actually do something, not just exist as sliders") implied these might be inert - they weren't all inert.

**Wheels' axle-count tweak was already fully real** - `module_placer.gd`'s wheels branch already spawns `count/2` pairs (visual), and `battle_unit.gd`'s `_recalculate_move_speed()` already scaled both thrust and capacity by `count/4.0` (stat). No functional gap here; just added a regression test (`test_locomotion_tweaks_have_real_visual_and_stat_effects`) to lock that in before touching the shared formula for the other two.

**Legs' leg-count was half-real** - visually already spawned more/fewer legs, but had NO `count_contrib` case in the thrust/capacity formula at all (fell through to the default `1.0`, meaning leg count had zero stat effect beyond the incidental "more instances = more raw weight" side effect). **Tracked_treads' width was also half-real** - already drove BOTH thrust and capacity up together via a single shared `count_contrib = width`, which isn't the tradeoff Chris asked for ("wider = more capacity... narrower = faster").

**Fix:** split the single `count_contrib` into separate `thrust_contrib`/`capacity_contrib` per locomotion type. Wheels/helicopter_rotors keep the old shared-scale-up behavior (no tradeoff intended there). Legs: `capacity_contrib = count/4.0` (more legs = broader stance = more load-bearing), `thrust_contrib = 1.0 + (4.0-count)/8.0` (fewer legs = less coordination overhead = more agile - count=2 gives 1.25x thrust, count=8 gives 0.5x). Treads: `capacity_contrib = width` (kept as-is), `thrust_contrib = 1.0 + (1.0-width)*0.5` (narrower = lighter/faster, width=0.5 gives 1.25x thrust, width=2.5 gives 0.25x). Also modulates the terrain-multiplier system directly for treads specifically (the "better on soft terrain" half of the ask) - `terrain_speed_multiplier += (width-1.0)*0.25`, clamped to `[0.15, 1.2]` so a max-width tread is notably better on marsh/snow/sand but not terrain-immune.

**Why this tradeoff shape and not a different one:** picked numbers that make the tradeoff show up as a REAL rank-order flip depending on load, not just "line goes up, line goes down" - verified by testing both a light-load scenario (thrust wins, fewer legs/narrower treads faster) and a heavy-load scenario (capacity wins, more legs/wider treads faster despite lower thrust_contrib) and confirming the winner actually flips between them. That's the concrete evidence the tradeoff is real and not just two numbers moving in opposite directions without ever mattering.

**Verified:** 75/75 tests green (1 new: spawns via the real `module_placer.gd` path to confirm wheel/leg counts and tread width actually change spawned-instance counts/scale, plus 8 direct `battle_unit` stat assertions across light-load/heavy-load scenarios for all three types, plus a terrain-multiplier check for tread width on marsh). Screenshots in `progress_captures/2026-07-13/tweak_mechanics/` (wheels 2 vs 8, legs 2 vs 8, treads width 0.5 vs 2.5).

---

## 2026-07-13 — Hull-relative locomotion scaling: reference hull, per-part axis choice, and a clipping bug it surfaced

**Not blocking.**

Batch E item 1: fixed the scale mismatch flagged (not fixed) in the last visual bug pass - locomotion visuals (wheels/legs/rotors/hover pads/anti-grav/engine pods/props) were built purely from their OWN catalog `size` field, with zero dependency on the hull they're mounted to. Giant legs on `flying_wing_hull`, tiny `helicopter_rotors` on `heavy_cruiser_hull`, etc.

**Fix:** two hull-relative multipliers computed once per `update_locomotion()` call, benchmarked against `medium_hull`'s own size (`ModuleCatalog.REFERENCE_HULL_SIZE = (4.0, 1.0, 6.0)` - the hull every part's absolute size was originally eyeballed against, so this is a no-op there):
- **height factor** (`hull_size.y / 1.0`) applied to parts whose scale should track ground clearance/hull height: wheel radius, leg length (Y-axis only - leg thickness stays as-authored, since the "giant legs" complaint was specifically about length, not girth).
- **footprint factor** (`sqrt(hull_x * hull_z / (4*6))`) applied to parts whose scale should track overall hull bulk: helicopter_rotors span, hover_engine/anti_grav pad size, fixed_wing_engine/buoyant_envelope pod size, naval_propeller size.

Both clamped to `[0.45, 2.25]` so an extreme hull still gets a legible part instead of vanishing or ballooning absurdly. `tracked_treads`/`screw_drive` were left alone - they already scale their length off real hull Z via the existing `tread_length/catalog.size.z` ratio, and their remaining fixed-size axis (thickness) wasn't the complaint.

**Verified two ways**, not just eyeballing renders: a numeric check (`leg.scale.y`/`rotor.scale` read directly off spawned instances for `medium_hull`/`flying_wing_hull`/`heavy_cruiser_hull`) confirmed the factors compute and apply exactly as designed (e.g. `heavy_cruiser_hull` legs: scale.y=1.9, matching its own height stat exactly), plus screenshots in `progress_captures/2026-07-13/hull_relative_scaling/` showing the size difference.

**Bug surfaced along the way, fixed same pass:** the numeric check caught `helicopter_rotors` count=4 on `heavy_cruiser_hull` rendering all 4 blades bright clipping-red despite not actually overlapping once mounted. Root cause pre-dates this fix: `update_locomotion()` places every instance of a multi-part locomotion type one at a time via `_place_weapon()` (which runs its own `check_all_clipping()` after each placement), but only assigns the `locomotion_group` meta that EXEMPTS same-group instances from clipping AFTER all instances already exist as hull children - so the last instance's placement-time clipping check can flag a same-group pair red before the exemption is in place, and nothing re-checks afterward. This was always latent (same architecture for wheels/legs), just needed parts big enough to actually produce a transient AABB overlap during placement to become visible - which the scaling fix's bigger rotors/legs on bigger hulls made much more likely. Fixed by calling `check_all_clipping()` once more at the end of `update_locomotion()`, after the group meta is set; confirmed via a scripted check that `clipping_detected` flips from `true` (mid-placement, stale) to `false` (post-group-assignment, correct) on the exact repro case.

**Verified:** 74/74 tests green (1 pre-existing test's hardcoded expected scale value updated to account for the new hull-relative factor, not a functional regression - see the comment on `test_design_to_battle_integration`'s legs assertion).

---

## 2026-07-13 — Systematic visual bug pass: real gaps found on ship/airship hulls, plus what I deliberately left alone

**Not blocking.**

**Method:** rendered 24 locomotion x hull combinations (every locomotion type on its natural hull plus deliberately weird cross-combos - wheels on a boat, legs on a flying wing, naval_propeller on a ground hull, etc.) in one windowed pass, then actually looked at every screenshot rather than trusting the placement math. This is the right way to catch this class of bug - the underlying formulas all looked reasonable on paper; the problem only showed up as pixels.

**Root cause found:** `module_placer.gd`'s underside-mount locomotion (wheels/legs/hover_engine/anti_grav) and `naval_propeller`'s stern mount both assume a hull's visual mesh fills its collision box symmetrically - true for every wedge/box-ish hull (medium_hull, sponson_hull, interceptor_hull, etc.), false for the 3 ship hulls (`build_ship_hull`'s keel intentionally dips to only `-0.6 * halfHeight`, not the box's full `-halfHeight`, and doesn't reach the true stern edge at all - it fairs up to the deck well before `z=hz`) and `airship_hull` (an ellipsoid's Y-extent shrinks well before its box edge). Locomotion mounted from the naive box-relative formula floated visibly below/behind the actual mesh on all 4.

**This affected the NATURAL pairing, not just weird combos** - `naval_propeller` on `naval_hull` (purpose-built for each other) showed the same detached-stern gap as `wheels` on a boat. That's what made this a real bug worth fixing carefully, not just a "someone tried something silly" cosmetic footnote.

**Fix: a per-hull `underside_y_bias` catalog field** (0.0 default, nonzero only on the 4 affected hulls) added to the mount Y calculation, plus moving `naval_propeller`'s Z position off the exact stern edge (`hull_size.z*0.36` instead of `/2.0`) and its Y closer to the keel's real depth. Values for the 3 ship hulls are exact (`0.4 * halfHeight`, derived directly from `build_ship_hull`'s own keel-depth constant); `airship_hull`'s is an approximation (a curved ellipsoid doesn't have one exact "gap" the way a hard-edged keel taper does) - explicitly not worth exact-fitting given wheels/legs on a dirigible is a nonsensical combo to begin with. The bar I used throughout: "no longer floating in obvious empty space," not "physically perfect attachment on every conceivable combo" - iterated the naval_propeller fix twice against real renders (first pass reduced but didn't fully close the gap) rather than accepting a partial fix on the natural-pairing case specifically.

**Deliberately NOT fixed, and why:**
- **Locomotion proportions on extreme hull sizes** (legs looking gigantic on the paper-thin `flying_wing_hull`/`fuselage_hull`; `helicopter_rotors`/treads looking tiny on `heavy_cruiser_hull`) - a real visual issue, but a different category than what was asked (a *scale* mismatch from locomotion visuals having a fixed absolute size regardless of hull dimensions, not a gap/orientation/floating bug). Retrofitting every locomotion visual to scale with hull proportions is a substantially bigger job than this pass's scope. Flagging it here rather than silently leaving it out of the write-up.
- **wheels/legs/hover_engine/anti_grav on naval_hull/airship_hull specifically** - after the bias fix these are much closer to the hull but not pixel-perfect (a wheel's tire still shows a sliver of visible gap on the ship hulls). Given these are combos nobody would seriously design around (a boat on wheels, a dirigible on legs), "meaningfully closer, no longer looking broken" was the target, not exact geometric matching - chasing the last few percent for a combo this nonsensical isn't a good use of further iteration.

**Weapon/module mounting checked separately** on the newer hull surfaces (naval hulls' sloped bow, airship's curved envelope, fuselage's cylindrical body) - came back clean; the pintle base-plate system (built and tested during the earlier mounting work) already handles non-flat surfaces correctly since it was designed around a real surface normal from the start, unlike the locomotion placement code's box-relative assumption.

**Verified:** 74/74 tests green (1 new) - a real end-to-end check that wheels/naval_propeller mount measurably differently (higher / off the exact stern edge) than the old buggy formula would produce, run through the actual `module_placer.gd` code path, not just asserting the catalog field exists. Before/after screenshots for every fixed combo in `progress_captures/2026-07-13/visual_bug_pass/`.

---

## 2026-07-13 — Terrain variety mechanism: speed multipliers vs. hard blocks, and where the line falls

**Not blocking.**

Chris's framing already drew most of the line: speed multipliers for marsh/rocky/snow_mud/sand (passable-but-harder), a real navmesh block only for shallow-water-vs-draught ("genuinely different mechanic... about hull-level draught"), with marsh-as-impassable-for-heavy-locomotion floated as optional ("if it feels right"). Decision: **kept marsh (and rocky/snow_mud/sand) as pure speed multipliers, no hard blocks, for any locomotor type.** Reasoning: a wheeled vehicle bogging down to 25% speed in a marsh is a real, provable penalty; a wheeled vehicle being LITERALLY UNABLE to enter marsh would be a hard-gate on a "weird but not impossible" design, which is exactly what the standing no-hard-gating philosophy (traits compose, never block a combination) argues against. A deep-draught hull floating in shin-deep water is a real physical impossibility (it would run aground); a heavy tank slogging through a swamp at a crawl is not - that distinction is why draught got the navmesh treatment and terrain type didn't.

**Mechanism: a per-tick multiplier, not a baked-in stat.** `move_speed` (recomputed only when the design changes - weight/thrust/tweaks) stays untouched; a new `terrain_speed_multiplier` is recomputed every physics tick from the unit's CURRENT position and applied only where velocity is actually set. This was the only correct option - a unit's terrain multiplier has to change as it physically crosses zone boundaries mid-match, unlike every other move_speed input which is fixed per-design.

**Airborne locomotion types get no explicit multiplier rows at all** (helicopter_rotors/hover_engine/anti_grav/fixed_wing_engine/buoyant_envelope) - not because they're all listed at 1.0, but because `is_flying` units skip ground navigation and the terrain-multiplier recompute entirely already (`_recalculate_terrain_speed_multiplier()` returns early). This is what "hover/anti-grav ignore terrain" means mechanically - a structural consequence of them already not touching the ground, not a special case bolted on for this task.

**Draught default (0.5, under the shallow-water threshold) for any hull without an explicit "draught" field** - deliberately permissive: if someone bolts `naval_propeller` onto a non-naval hull (already possible, no-hard-gating), that hull is NOT blocked from shallow water by default. Only the 3 purpose-built naval hulls carry real draught numbers; `heavy_cruiser_hull`'s (1.8) is the only one that actually exceeds the threshold (1.0) and gets the hard block.

**Verified with real physics-tick movement, not catalog-number comparisons alone**, per Chris's explicit ask: a synthetic test spawns two units with different locomotion, orders both across a fixed surface type, runs 140 real physics ticks each (matching the exact `_physics_process()`+`move_and_slide()` pattern the existing lake-crossing pathfinding test already established), and compares actual distance covered. Hit a real methodology bug while building this: a synthetic unit with no floor collision free-falls under gravity indefinitely (no `terrain_height_at()` method on the bare test double to lerp Y toward), and that unbounded fall measurably dampened horizontal `move_and_slide()` distance in a way that shrank the measured differentiation ratio far below the catalog multiplier ratio - fixed by giving the test's fake controller a flat-ground `terrain_height_at()` too, matching how every real unit's Y is actually handled (lerped, never gravity-fallen). Draught blocking is verified two ways: a raw navmesh path-connectivity check (a shallow strip splitting a lake in half has literally no deep-water route across it) and a full `battle_unit.gd` routing check (`heavy_cruiser_hull` vs. `small_boat_hull` land on different nav maps through the real `setup()` path). 73/73 tests green (4 new).

---

## 2026-07-13 — Six new mobility modules: wing/thruster/prop/pusher-prop/paddle-wheel/ship-screw

**Not blocking.**

**Mechanical design - a flat additive bonus, not a scaled-per-locomotor-type one.** The weight-capacity/thrust-coefficient systems from two sessions ago are keyed per LOCOMOTION type (the vehicle's primary movement paradigm). These six are ATTACHABLE modules (placed like any weapon, stackable, not a primary choice) - giving them the same per-type-scaled treatment would be overengineered for what's conceptually "one more part bolted on." Instead: `weight_capacity_bonus`/`thrust_bonus` catalog fields, added flatly to the vehicle's existing totals in `battle_unit.gd`'s `_recalculate_move_speed()`, scaled only by the module's own size (`child.scale.x * child.scale.z`, same convention as everything else in that loop) - not gated to only apply on airborne/naval hulls (no-hard-gating philosophy: a wing bolted onto a tank is silly but harmless, not blocked).

**`ship_screw` vs. `naval_propeller`'s existing visual - genuinely different, not a rename.** Checked before building anything: `naval_propeller`'s existing visual (`_build_naval_propeller`) is a housing + 3 flat rectangular blades - a reasonable stern-mount silhouette, but not an actual pitched/twisted screw. `ship_screw` gets a real distinguishing feature: each blade is rotated around its own length axis (`blade.rotation.x = 0.5` before the radial sweep) for a genuine twisted-blade look, and it's a stackable MODULE rather than the primary locomotion choice - two real differences, not just a new name on the same mesh.

**`propeller_prop`/`pusher_prop` share one mesh-building function, differing only by a `pusher: bool` flag** that flips which end of the local Z axis the hub/blades sit on - the "visually distinct placement/orientation" the task asked for, achieved with zero extra mount-system code (the module's own forward-facing convention already does the work; only the authored geometry's own facing direction changes).

**Verified:** balance_report.gd flags several of these as "low value/cost, consider a buff or discount" - checked against the ALREADY-EXISTING `fixed_wing_engine` locomotion entry, which the same tool flags identically (0.20 vs. e.g. thruster's 0.23) - the tool's own header already notes locomotion/mobility value-per-cost is inherently hard to quantify (it doesn't weigh capacity/thrust bonuses at all, only hp/dps/heal_rate), so this is a known, already-accepted limitation for this whole category of item, not a new outlier needing a special pass. Mechanically verified with a real overload scenario: a wheeled unit loaded past its own capacity is genuinely slow (overload-penalized); the same unit with a `wing` attached shows a real, unclamped `move_speed` increase (capacity raised, penalty reduced) and the same with `thruster`/`propeller_prop` (raw thrust increase) - not just "a bigger number appeared somewhere," a real speed change traced through the actual formula. All 6 modules confirmed visually distinct up close. 70/70 tests green (1 new).

---

## 2026-07-13 — Air/sea hull batch: sizing (heavy_cruiser_hull's near-black first render), and the airship's locomotion pairing

**Not blocking.**

**heavy_cruiser_hull rendered near-solid-black on first verification.** Traced through two wrong hypotheses (inverted normals from the convex-hull greebles, a genuine mesh defect) before finding the real cause: the Design Lab's camera starts on a fixed dead-on axis (`designer_camera.gd`'s `_ready()` - `position=Vector3(0,0,_distance)` with zero initial orbit), not an isometric 3/4 angle. That reads fine for compact/roughly-cubic hulls but produces a near-silhouette, heavily backlit view for a long pointed-bow ship hull once it's big enough to fill more of the frame - confirmed by orbiting the verification camera to a real 3/4 angle, which revealed properly-lit, correctly-shaded geometry with zero mesh changes. Kept the resulting size reduction anyway (13.0 → 10.5 length) since a hull that only reads correctly after a manual orbit is a worse default first impression than a slightly smaller one, even though the underlying geometry was never actually broken. Logged here so a future verification pass doesn't re-diagnose the same "is it a bug?" question from scratch - **the Design Lab's default camera angle is not representative of a hull's real appearance; always orbit before judging shading/darkness.**

**airship_hull's locomotion pairing - reused fixed_wing_engine, or built something new?** Chris explicitly asked me to reason this through rather than default silently. A rigid airship's lift comes from displacing air with a lighter-than-air gasbag - fundamentally different physics from every other airborne locomotion in the roster (helicopter_rotors/hover_engine/anti_grav/fixed_wing_engine all use an engine/rotor actively fighting gravity for lift). Reusing fixed_wing_engine would have been the zero-effort choice, but it would make the airship mechanically indistinguishable from any other plane despite looking totally different - a missed opportunity given the weight_capacity and motor_thrust systems built two sessions ago exist precisely to let a locomotion type express real character. Built a new type instead, `buoyant_envelope`: very high `base_weight_capacity` (1100, highest in the roster - buoyancy scales generously with envelope size) paired with a NEW `thrust_coefficient` catalog field (55.0, vs. every existing type's implicit-then-explicit 150.0 default) reflecting that an airship's actual engines are small cruise/steering motors, not the source of lift. This required generalizing `battle_unit.gd`'s previously-hardcoded `150.0` thrust constant into a per-type catalog lookup (`ModuleCatalog.get_thrust_coefficient()`), mirroring the `base_weight_capacity` pattern from the weight-capacity work - a small, well-contained generalization that makes the airship's "slow but can carry a lot" character fall out of the existing formula rather than needing a special case. Every pre-existing locomotion type is unaffected (falls through to the same 150.0 default they always used).

**Verified:** all 4 hulls confirmed visually one at a time (orbited 3/4 view + close-up per hull) after the camera-angle lesson above. `buoyant_envelope`/`screw_drive` both confirmed to actually spawn matched left/right pairs through the real `update_locomotion()` UI path (a first attempt silently spawned nothing - `update_locomotion()` turned out to be an explicit per-type-id placement chain, not a generic "any locomotion category" system, so both new types needed their own placement branch same as every existing locomotion type). 69/69 tests green (3 new).

---

## 2026-07-13 — screw_drive amphibious pathing: a real third navmesh, not a flag

**Not blocking.**

Chris's ask was for a "genuinely amphibious" locomotion type, not a reskinned ground unit. The existing pathfinding system is a strict binary: `is_naval` picks `water_nav_map` (water only, everything else is a hole) or `ground_nav_map` (everything except water/obstacles/elevation) exclusively - there was no way for a single continuous path to cross both. Rather than bolt on a "don't treat water as blocking" flag (which wouldn't actually let `NavigationAgent3D` route across it, since the water rectangle simply isn't in `ground_nav_map`'s baked geometry at all), built a genuine third navmesh in `terrain_builder.gd`: `_build_amphibious_faces()` walks the same grid-quad sweep as the ground map but only treats real obstacles and elevation-zone footprints as holes - water is walkable terrain here. `screw_drive` carries a new `"amphibious"` trait (not `"naval"` - it's not buoyant/surface-locked like a ship, it drives normally on land) which routes it onto this map via a new duck-typed `get_amphibious_nav_map()` on the match controller, same pattern as the existing ground/water getters.

**Not folded into `is_naval`/naval trait**, deliberately: a screw-drive vehicle isn't surface-locked or buoyant, it's a ground vehicle that also happens to cross water - conflating the two would mean it inherits naval's fixed-waterline Y-behavior (`battle_unit.gd`'s `is_naval` branch), which is wrong for a vehicle that should drive at normal ground level (`terrain_height_at()` already returns flat ground level for anything that isn't an elevation zone, water included, so no extra Y-handling was needed once the navmesh itself was real).

**Verified with a path-length comparison, not just "no error was thrown":** on a synthetic map with a lake splitting two points, the amphibious map's path crosses in ~one direct line (within 10% of straight-line distance) while the ground-only map's path (if one exists at all, since the lake doesn't reach the map edge) is forced into a meaningfully longer detour - concrete proof the two maps are genuinely different terrain, not two names for the same baked mesh. Also caught and fixed a real RID leak this same change introduced: `test_terrain_builder_navmesh_ramp_connects()` calls `build_navmeshes()` directly (bypassing `Skirmish._exit_tree()`'s cleanup) and only freed the ground/water RIDs it knew about before this change - the new amphibious map/region leaked 4 of each across that test's 4 ramp-direction iterations until its manual cleanup list was updated to match. 69/69 tests green (2 new, including the leak fix's own regression coverage).

---

## 2026-07-13 — Weight now actually matters: per-locomotor-type capacity, and the overload penalty curve

**Not blocking.**

Chris's ask: the vehicle Weight stat is displayed but has zero gameplay effect - build a per-locomotor-type "how much weight this is built for" formula, with excess weight slowing the unit down, heavier/tougher locomotion tolerating more before the penalty kicks in.

**Capacity values, real-world load-bearing intuition** (matching the reasoning style already used for `pintle_min_up_alignment`/`traverse_agility`): `naval_propeller` highest (800 - buoyancy carries the load, ships routinely haul far more than any ground/air vehicle), `tracked_treads` (700 - literally what tanks use to carry heavy armor), `legs` (500 - a mech walker's legs bear real structural load, closer to treads than wheels), `anti_grav` (450 - repulsor tech rather than aerodynamic/ground-effect lift, more forgiving of extra weight than true hovering/flight), `fixed_wing_engine` (380 - lift scales with airspeed/wing area, more payload-tolerant than rotary/hover lift but still a real aircraft weight budget), `wheels` (350 - light and fast but handles poorly overloaded, like a real overloaded car), `hover_engine` (300 - ground-effect lift is weight-sensitive), `helicopter_rotors` lowest (250 - real helicopters have a notoriously strict max-takeoff-weight, the most weight-sensitive locomotion in the roster).

**Capacity scales with the same size/count factors as thrust**, not just a flat per-type number - a 6-wheel setup or a wider tread already produces more `motor_thrust` in the existing formula (`battle_unit.gd`), so its weight capacity scales the same way (`ModuleCatalog.get_base_weight_capacity(type_id) * child.scale.x * child.scale.z * count_contrib`), reusing the exact `count_contrib` logic already computed for thrust rather than inventing a second, possibly-inconsistent scaling rule.

**Penalty curve**: no penalty at or under capacity. Beyond it, `overload_multiplier = clamp(1.0 - (overload_ratio - 1.0) * 0.6, 0.25, 1.0)` - so 50% over capacity costs 30% of speed, 100% over costs 60%, floored at 25% of normal speed so a badly overloaded design is punishing but never literally frozen in place (a unit that can't move at all from overload alone would read as a bug, not a balance mechanic, and `has_locomotion=false` already owns the "genuinely can't move" case elsewhere in this same function). 0.6 as the penalty-per-100%-over coefficient and the 0.25 floor are both judgment calls, not derived from anything in the design docs - reasonable enough to feel like a real cost without needing a live-balance pass to validate exact numbers, which is out of scope here.

**Verified with mock units built the same way `test_traverse_limit` mocks a weapon** (direct field control rather than the full blueprint-reconstruction pipeline, so the test can compute exact expected numbers): a 400kg weapon pushes a 50kg `wheels` chassis (450 total vs. 350 capacity) into a real, provable penalty (compared against the unpenalized thrust/weight formula directly, not just "got slower," since added weight already slows a unit via the pre-existing thrust/weight ratio on its own); the SAME 400kg weapon on a 120kg `tracked_treads` chassis (520 vs. 700 capacity) gets zero penalty - direct proof that heavier locomotion tolerates more excess weight before the mechanic kicks in, the core of what was asked. 66/66 tests green (1 new).

---

## 2026-07-13 — Weapon traverse rate and range: what was actually broken vs. already fine, and how the fix was scoped

**Not blocking.**

Audit of `auto_weapon.gd` before touching anything, per Chris's own framing ("confirm whether it's a real gap or was already fine"):

**Range was already meaningfully differentiated at the base-stat level** - every weapon type_id has its own hardcoded `fire_range` (9.0 flamethrower to 50.0 heavy_howitzer), not a uniform number. Chris's suspicion here didn't hold up as stated. The REAL gap was tweak coverage: cross-referencing `stat_calculator.gd`'s `TWEAK_SPECS` (the actual player-facing sliders) against `auto_weapon.gd`'s range-modifier block showed roughly half the weapon roster's own tweaks had zero connection to their range at all - `gauss_railgun`'s only tweak (`rail_length`) didn't touch its own range, `heavy_machine_gun`/`rotary_cannon`'s tweaks (`drum_size`/`motor_size`/`barrel_count`) didn't either, nor did `flak_cannon`'s `fuse_setting` (which is literally an engagement-range control on a real proximity-fused shell) or `tesla_coil`'s `caliber`. Fixed by wiring six more tweak names into the range formula (`caliber`, `rail_length`, `seeker_size`, `ascent_thruster`, `pressure_valve`, `fuse_setting`), each reasoned individually for why it plausibly affects reach - NOT a blanket "connect everything," since some tweaks genuinely shouldn't move range (`drum_size`/`motor_size` are ammo capacity and spin torque, not reach; `dispersion` is spread pattern, not distance; `cooling_jacket` is sustained-fire capacity, not reach) and forcing a connection there would be arbitrary rather than reasoned.

**Traverse speed was the real, confirmed gap.** `traverse_speed = clamp(200.0/weight, 0.6, 6.0)` was a single formula with NO type-specific input at all - two weapons of similar weight but wildly different real-world handling (ciws vs. mortar_array, both ~90kg - one a reflexive point-defense tracker, one a slow ballistic-arc lobber) traversed identically. Fixed with a new catalog field, `traverse_agility` (multiplier, default 1.0), reasoned per weapon type using the same real-world-handling logic already established for `pintle_min_up_alignment`: point-defense weapons fastest (ciws 1.8, pd_laser 1.6 - need to snap onto small fast targets), light autoguns quick (heavy_machine_gun 1.3, flamethrower 1.25), guided munitions moderate (missiles ~0.8-0.9, since the warhead corrects course after launch so the launcher itself doesn't need to snap-track), precision energy weapons deliberate (~0.75-0.8), indirect/ballistic-arc weapons slowest (mortars/lobbers ~0.5-0.6, matching their pintle-tolerance reasoning - an arc weapon needs a controlled aim, not a fast one). The base weight-formula clamp was widened from (0.6, 6.0) to (0.4, 8.0) so the multiplier has real headroom instead of being squashed back into the old narrow band.

**Tweak-to-traverse coverage was also narrow** - only `barrel_length`/`elevation` (2 tweak names) nudged traverse_speed directly, meaning most weapons' actual tweaks only affected traverse indirectly through the weight formula. Generalized to a shared list, `ModuleCatalog.LINEAR_SCALE_WEAPON_TWEAKS` (every "one part gets physically bigger" tweak name, reusing the exact set `module_data.gd`'s `get_weight()` already treats as size-scaling - deliberately excluding count-type tweaks like `multi_barrel`/`barrel_count`/`tube_count`/`grid_size`, which mean "more copies" not "one bigger part" and so should only affect traverse through weight, not an extra direct penalty). This preserves the existing double-dip pattern that `barrel_length`/`elevation` already had (tweak affects weight AND gets an explicit extra traverse divisor) rather than inventing a new mechanism, just generalizes it from 2 weapons to all of them.

**Verified with a test that isolates each fix from its confounds**, not just "numbers moved": (1) ciws vs. mortar_array at the identical weight get different traverse speeds - proves the per-type multiplier, not weight, is responsible; (2) `gauss_railgun`'s `rail_length` tweak now measurably extends its `fire_range`, which has zero other connection to weight/traverse in the codebase, so this is a clean proof of the new code; (3) `heavy_machine_gun`'s `drum_size` tweak now reduces traverse_speed by MORE than the weight-driven formula alone would predict (computed and compared against the weight-only baseline explicitly, since `drum_size` also scales weight and a naive before/after comparison wouldn't distinguish the old effect from the new one). 65/65 tests green (1 new).

---

## 2026-07-12 — Pintle eligibility made per-weapon-type instead of one uniform angle threshold

**Not blocking.**

Chris's correction to the angled-pintle work above: whether a weapon pintle-mounts on a sloped surface or falls back to sponson shouldn't be one geometric threshold (`dot(normal, UP) >= 0.3`) applied uniformly to every weapon - it's a per-weapon-type judgment call. Replaced the flat `PINTLE_MIN_UP_ALIGNMENT` constant with a catalog field, `pintle_min_up_alignment`, set individually per weapon type_id in `module_catalog.gd` (renamed the old constant to `PINTLE_MIN_UP_ALIGNMENT_DEFAULT`, kept only as a fallback for any weapon missing the field). `get_mount_style_for_normal()` now reads the threshold via `ModuleCatalog.get_pintle_min_up_alignment(type_id)` instead of the constant.

**The actual per-type reasoning**, grouped by why a weapon tolerates (or doesn't) a steep pintle angle:

- **0.15 (most permissive - works on steep slopes):** `heavy_machine_gun`, `rotary_cannon`, `flamethrower`, `ciws`, `pd_laser` - compact, self-contained weapons with no long recoil path or delicate internal mechanism that cares about being level; a pintle gun on a stand is realistically fine even close to a near-vertical mount.
- **0.2:** `arc_projector` - compact emitter, same reasoning, slightly more conservative since it's a heavier housing.
- **0.25:** `guided_missile`, `dual_stage_missile` - guided munitions correct their own flight path after launch, so the launch rail doesn't need to be level; more tolerant than an unguided weapon would be.
- **0.3 (the old uniform default, now just the middle of the range):** left as the default for any weapon without an explicit entry.
- **0.3-0.35:** `flak_cannon` (0.3, bulkier point-defense piece), `missile_pod` (0.35, unguided multi-tube - each tube's launch angle matters more without post-launch correction).
- **0.4:** `tesla_coil`, `ion_cannon`, `heavy_laser` - tall, heavy, precision-aimed weapons where a steep mount starts to look and behave wrong.
- **0.45-0.55 (least permissive - needs a near-level base):** `cluster_dispenser` (0.45, lobs on an arc), `plasma_lobber` (0.5), `mortar_array` and `spigot_mortar` (0.55) - all ballistic-arc/indirect-fire weapons where the mount's own level base is part of how the arc is aimed; these fall back to sponson well before the old uniform 0.3 threshold would have allowed a pintle mount.

`basic_cannon` (turret override), `gauss_railgun`/`heavy_howitzer` (frame_built override), and `drone_carrier`/`repair_array` (category="module", never reach this code path) don't get a field - the threshold is meaningless for them since their mount style is decided earlier in the function.

**Verified:** added a test asserting `heavy_machine_gun` and `mortar_array` resolve to opposite mount styles (`pintle_top` vs `sponson`) at the *same* moderate slope (`dot≈0.4`) - the concrete proof the system is now genuinely per-type rather than uniform, not just individually-plausible numbers. 64/64 tests green. Also fixed a pre-existing fragile assertion in `test_angled_pintle_mount()` whose "near-vertical" test vector computed to `dot≈0.1498`, dangerously close to rotary_cannon's new 0.15 threshold - moved it further from vertical (`dot≈0.05`) so it can't accidentally start failing from an unrelated future tweak to that weapon's threshold. Screenshot confirming both mount styles side by side on the same hull at the same angle in `progress_captures/2026-07-12/pintle_per_weapon_type/`.

---

## 2026-07-12 — Angled pintle mount: where exactly the sponson/pintle boundary sits, and how the tilt is expressed

**Not blocking.**

Chris's correction: a pintle-style mount (weapon level, sitting on a stand) should work on sloped surfaces like a glacis plate, not just an exactly-flat top - the tilt should live in a new angled base plate, not the weapon itself. Two real judgment calls in implementing this:

**Where the sponson/pintle boundary sits.** Replaced `classify_facet()`'s discrete top/bottom/else check (which only fired within ~0.03 degrees of dead vertical) with a continuous threshold: `dot(normal, UP) >= 0.3`, i.e. `cos(~72.5°)`. That means a surface can be sloped as steeply as ~72.5 degrees from horizontal and still get the pintle treatment (angled plate, vertical post, level weapon); only the last ~17.5 degrees approaching a genuinely vertical wall falls back to sponson. Chosen deliberately permissive per Chris's own framing ("anything with a meaningful upward-facing component... is a candidate," "near-vertical side wall probably still wants sponson") - I didn't try to reverse-engineer the interceptor hull's exact glacis angle to calibrate this precisely; the threshold is a judgment call about where "gun on a stand" stops making visual sense, not a measurement.

**Applied symmetrically to pintle_bottom too**, not just the top/glacis case Chris described. He didn't ask for this explicitly, but leaving the underside on the old exact-flat-only check while the top became continuous would have been an inconsistent, arbitrary asymmetry in the same mechanism - a sloped belly plate gets the same angled-base-plate treatment as a sloped glacis, for the same reason.

**Mechanism:** the plate's orientation is `Quaternion(Vector3.UP, surface_normal)` - the shortest-arc rotation from "flat, facing up" to the real local surface normal. This is deliberately a single formula rather than a flat-case/tilted-case branch: when the normal IS up, the quaternion is identity and the plate is flat, exactly matching the pre-existing behavior - so the fix didn't need to special-case backward compatibility with every already-working flat-top mount, it just generalizes to cover it. The weapon's own transform never gets reoriented for a pintle-eligible surface (previously it always tilted to match any non-exactly-flat normal) - the tilt is fully absorbed by the new base plate, which also embeds slightly backward along the surface normal (Chris's "no gap/floating" note) and carries a ring of bolt greebles plus a raised hub.

**Persistence:** added `mount_normal` to the saved-blueprint module dict (alongside the existing `mount_style`) - without it, `reconstruct_vehicle()` would default back to `Vector3.UP` on reload and silently flatten a saved glacis-mounted weapon's plate back to level, since `rebuild_visual()` has no other way to recover the original placement angle.

**Verified:** 64/64 tests green (1 new - `test_angled_pintle_mount()`, covering the continuous threshold at 45°/near-vertical/pure-side angles, a real placement staying level with a correctly-tilted+embedded plate, the post remaining unrotated, and the tilt surviving a save/reconstruct round-trip). Windowed screenshots of a rotary_cannon mounted on `interceptor_hull`'s sloped nose in `progress_captures/2026-07-12/angled_pintle_mount/` - the wide shot shows it in context on the sloped nose, the close-up shows the tilted plate distinctly (visibly non-circular from this angle, unlike the flat-top case) with the post and bolt ring visible.

---

## 2026-07-12 — Four maps built: count, symmetry approach per map, and two more real bugs found while verifying

**Not blocking.**

Built 4 maps total on the new architecture (`lake_crossing` - the original, kept as the default/compatibility anchor - plus 3 new ones). Chris's instruction was "however many maps feels like a good starting set... aim for genuinely different play patterns." Landed on 4 as covering the explicitly-named patterns without padding the count with near-duplicates:

- **`open_plains`** - no water, no elevation, no obstacles, tighter (70 vs 80 half-extents), resources pulled toward center. Deliberately the "nothing to hide behind" map, a clean baseline contrast to the other three.
- **`lake_crossing`** - unchanged from before, kept as-is.
- **`highland_chokepoint`** - landlocked (fulfills "some maps with no water at all"), one dominant contested hill with rock walls narrowing the map to two flanking lanes.
- **`coastal_strand`** - water along one full edge rather than centered (fulfills "some coastal"), the most obstacle-dense of the four.

**Symmetry approach chosen per map's own geometry, not one universal rule.** `lake_crossing`/`open_plains`/`highland_chokepoint` all use 180-degree point symmetry (mirror every position through the map origin) since their terrain is itself point-symmetric. `coastal_strand` uses a north/south (Z-axis) mirror instead, since its terrain is deliberately NOT east-west symmetric (water only borders one side) - point-symmetry would have put one team's "safe" resource in the water. Judgment call: match the fairness mechanism to the map's actual shape rather than forcing every map through the same symmetry formula.

**A real bug found verifying `highland_chokepoint`, not just eyeballing it:** the automated smoke test (built for exactly this purpose) caught the player factory spawning ON the hill's ramp footprint - blocked, illegal terrain. My manual math for how far the ramp's footprint extends past its nominal `ramp_width`/`height` undercounted the effect of `terrain_builder.gd`'s grid-snap padding (RAMP_PAD, added while fixing the Recast winding bug logged in the entry below) - the padded/snapped ramp rect reaches noticeably further than a naive "width + 2×pad" estimate suggests, because snapping always rounds *outward* to the nearest grid line. Fixed by pushing that map's base positions further from center (z=32→40) with real margin, not by relying on hand-calculation again. This is exactly the class of bug the smoke test exists to catch before it ships as "the enemy can't build a factory on this map."

**A second real bug found via the mandatory screenshot check, not the smoke test:** the map-select screen (`map_select.gd`) looked fine with 1 map present but silently ran content off *both* the top and bottom of a 720px viewport once all 4 existed - a `VBoxContainer` centered on screen overflows symmetrically around its center once content exceeds the viewport, unlike a top-anchored one which only overflows downward (so it's easy to miss until there's enough content to push past center in both directions). The automated tests have no way to catch this class of bug (`test_ui_overflow_audit` only covers `MainLab.tscn`) - only the screenshot did. Fixed with a `ScrollContainer` around the map list, same pattern the build bar (`skirmish.gd`) already uses for its own overflow risk.

**Verified per-map, one at a time as instructed:** each map got its own windowed top-down + in-scene screenshot pair, plus a real scripted smoke test (`_smoke_test_map()` in run_tests.gd) checking start points are on legal/unblocked terrain, every resource node is reachable by ground navmesh from its own side's harvester spawn, the two HQs are mutually reachable (no map accidentally splits the navmesh into disconnected islands), and the factory build queue actually produces a unit - before moving on to the next map.

---

## 2026-07-12 — Multi-map architecture: data shape, elevation approach, and a real Recast winding bug found while verifying it

**Not blocking.**

Chris asked for a genuine multi-map architecture (not a second hardcoded scene) with real terrain variation - elevation that matters for vision/combat, water, and obstacles that actually constrain pathing. Several judgment calls along the way:

**Map data as a plain Dictionary (`map_catalog.gd`), not a typed Resource.** Every other piece of catalog/blueprint data in this codebase (`module_catalog.gd`, saved blueprints, the enemy roster) is a plain Dictionary - a `MapDefinition` Resource class would be more "properly Godot," but would be the one inconsistent piece of catalog data in the project. Staying consistent means new maps are diffable/testable the same way new hulls or weapons already are, and the existing `TerrainBuilder`/`MapCatalog` split (data vs. the code that turns it into a scene) mirrors `ModuleCatalog`/`visual_builder.gd` already.

**`lake_crossing` kept byte-for-byte identical to the old hardcoded map, chosen as the default.** Two existing tests (`test_navmesh_routes_around_the_lake`, `test_unit_order_move_actually_navigates_around_the_lake`) hardcode knowledge of the old `LAKE_CENTER`/`LAKE_HALF_EXTENTS` values in their own pass/fail checks. Rather than rewriting those tests to be map-agnostic (real work, and it would mean the very first map-architecture test coverage is itself less specific), the original map became `map_catalog.gd`'s `"lake_crossing"` entry with identical geometry and is `MapCatalog.DEFAULT_MAP_ID` - every pre-existing test that instantiates `Skirmish.tscn` directly (no map selection) gets exactly the map it was already written against, unchanged.

**Elevation as discrete rectangular plateau+ramp zones, not a real heightmap.** A full arbitrary-terrain heightmap system (deforming the whole ground mesh, matching collision to it) is a much bigger undertaking touching rendering, collision, and every existing flat-ground assumption in the physics code. Discrete zones (a flat raised rectangle + one ramp bridging it to ground level) deliver the actual ask - real elevation, real pathing consequence, real vision/combat effect - using the same "rectangular zone with real gameplay consequence" shape the lake/obstacles already use, at a fraction of the risk.

**Elevation Y-positioning is analytic (`terrain_height_at()`), not physical collision.** Seriously considered giving plateaus/ramps real `CollisionShape3D`s so gravity would naturally rest units at the right height, matching how the flat ground already works. Rejected: a ramp would need a rotated `BoxShape3D` per direction (real trig, four cases) and `CharacterBody3D` has no built-in stair-stepping, so a physically-collided ramp risked getting units stuck or jittering at the slope transition - a correctness risk for a purely cosmetic/positional concern. Instead every ground unit's Y gets smoothly lerped toward `terrain_height_at(position)` each tick when a real match controller is present (duck-typed, same pattern as `get_ground_nav_map()`), completely decoupled from gravity/`is_on_floor()`. This one function is also the ENTIRE reason vision and combat elevation bonuses work at all - they just read real Y coordinates off units/buildings, no map awareness needed in `damage_resolver.gd` or the fog-of-war code.

**A real bug found and fixed while verifying the ramp actually connects to the plateau, not just baking without errors:** all-green unit tests plus a windowed capture weren't enough here - path queries onto a plateau were silently resolving to the nearest *disconnected* point near the ramp instead of using it, with no error anywhere. Traced through several wrong hypotheses (slope angle, `agent_max_climb`, `region_min_size`, cell height) via isolated single-quad repro scripts before finding the actual cause: Recast silently drops a baked triangle whose winding doesn't match its walkable-surface convention - not documented anywhere I could find, confirmed empirically. The existing grid/lake quads all happen to sweep in the matching direction; a "south" or "west" ramp (where the ramp's outer/ground-level edge has a *smaller* coordinate than its inner/plateau edge) reverses that sweep and silently produced zero baked polygons. Fixed in `terrain_builder.gd`'s `_ramp_quads()` by detecting the reversed case and swapping the width corners to restore the matching winding - now covered by `test_terrain_builder_navmesh_ramp_connects()`, which exercises all 4 directions specifically so this can't regress silently for just one of them again.

**Elevation vision/combat bonuses are universal formulas keyed off real height, not per-map-authored multipliers.** `vision *= 1 + min(height, 12) * 0.02` and a flat threshold-piercing bonus (`* 0.85`) past a 2-unit height *difference* between attacker and defender - both live in code (`skirmish.gd`, `damage_resolver.gd`), not in `map_catalog.gd`'s per-zone data. This means every map's hills behave consistently (a 10-unit hill is always worth roughly the same tactical value) rather than needing individual tuning per map, and it's simpler to balance-check. Flagging the exact numbers as a first-pass estimate, same spirit as the balance-report weights - reasonable defaults, not something verified through actual play yet.

**Build placement also gets a new "too close to enemy territory" check (20m).** Wasn't strictly asked for as its own item, but Chris's requirement that start areas be "clear of ... other players' territory" implied placement should respect that too, not just base-spawn positions - and the existing 28m-from-friendly-building rule had no equivalent check against the enemy at all. Low risk: existing map start-point separation makes this essentially unreachable on `lake_crossing`, but matters on tighter maps.

**Also fixed as a pre-existing gap, not a new-map-specific bug:** nothing previously stopped a player from placing a building inside the lake at all - `_try_place_building()`'s only check was distance-from-friendly-building, with zero terrain awareness. Now checks `TerrainBuilder.is_position_blocked()` first.

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
