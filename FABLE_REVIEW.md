# Independent Review — 2026-07-18 (Claude Fable 5)

A fresh, independent creative + functional assessment, commissioned by Chris. Written after reading
the design docs (DESIGN_VISION.md, PROGRESS.md, DECISIONS_NEEDED.md, the specs) and then reading the
actual GDScript against them — every claim below is grounded in specific code, with file references.
This deliberately does **not** defer to prior session conclusions; where I think a past call or a
shipped mechanic misses the mark, I say so.

**The one-paragraph verdict:** the Design Lab itself is in better shape than the Forged Battalion
worry suggests — continuous tweaks, live stats, symmetry, facet armor, and mount styles are real and
mostly wired. The place the differentiation test actually fails today is *combat resolution*: several
of the stats the sliders move are nullified or never consulted when units fight (auto-hit weapons make
speed/size defensively worthless; the threshold math makes every rapid-fire weapon deal literally zero
damage to any armored target; hull armor and hull size are free power with no cost or mobility price).
Two players' genuinely different designs converge not because the editor is shallow, but because the
simulation collapses their differences — and a few dominant choices (energy shielding, max thickness,
max hull size, max free sliders) mean the "right" build is solved. Fixing a handful of resolution-layer
issues would do more for build diversity than any amount of new content.

---

## 1. Enhancement opportunities — where the "genuine build diversity" bar is missed

Ordered by how much design space each one destroys.

### 1.1 Rapid-fire weapons deal zero damage to any armored hull — the threshold math cancels a third of the arsenal

Per-shot damage everywhere in [auto_weapon.gd](prototype/scripts/auto_weapon.gd) is `dps * fire_rate`
(damage per shot = DPS × shot interval), and [battle_unit.gd:982](prototype/scripts/battle_unit.gd:982)
negates any hit below the armor threshold. Run the actual numbers against the *default* hull armor
(hardened_steel, thickness 1.0 → kinetic threshold 15, thermal 5, energy 8):

| Weapon | dps × fire_rate = per shot | Threshold it faces | Result |
|---|---|---|---|
| rotary_cannon | 75 × 0.05 = **3.75** | 15 (kinetic) | zero, forever |
| heavy_machine_gun | 25 × 0.22 = **5.5** | 15 (kinetic) | zero |
| ciws | 10 × 0.06 = **0.6** | 15 (kinetic) | zero |
| heavy_laser | 80 × 0.05 = **4.0** | 8 (energy) | zero |
| flamethrower | 80 × 0.05 = **4.0** | 5 (thermal) | zero |
| pd_laser | 5 × 0.1 = **0.5** | 8 (energy) | zero |
| flak_cannon | 15 × 1.2 = **18** | 15 (kinetic) | barely penetrates thickness 1.0 only |

And the subsystem-strip branch doesn't save them: module damage is `max(0, amount - 5.0)`
([battle_unit.gd:961](prototype/scripts/battle_unit.gd:961)), so a 3.75-damage rotary shot does zero
there too. Concretely: the bundled `bulwark_mbt` (reactive 1.6 → kinetic threshold 16) is **completely
immune** to its own heavy_machine_gun, to rotary cannons, CIWS, lasers, and flamethrowers. No test
catches this because tests check that damage *resolves*, not that the sustained-fire archetype is
viable; the balance report scores raw DPS and can't see that the DPS never lands.

This single interaction deletes the entire "cheap swarm / sustained fire" corner of the design space
and inverts Damage_And_Armor_Model.md's own counter-triangle (swarm is supposed to beat super-heavies
through action economy — today small guns can't hurt *anything* with armor). **This is the highest-
leverage balance fix in the project.** Options, roughly in order of my preference: (a) make thresholds
bleed — e.g. sub-threshold hits deal 10–20% chip damage so ROF still grinds; (b) decouple per-shot
damage from fire interval for the ROF family (treat them as short bursts with a meaningful per-burst
packet); (c) lower thresholds sharply and make `reduction` carry more of the mitigation.

### 1.2 Hull armor material + thickness is free power, and energy_shielding is close to strictly dominant

The armor thickness slider (0.5–3.0) and material dropdown multiply hull HP in combat
([battle_unit.gd:162](prototype/scripts/battle_unit.gd:162)) and all thresholds — but:

- **Zero cost effect.** `blueprint_cost()` ([skirmish.gd:436](prototype/scripts/skirmish.gd:436)) sums
  hull catalog cost + module costs. Neither material nor thickness appears anywhere in any cost path.
  A medium_hull at thickness 3.0 + energy_shielding is 2,400 HP for the same 100M/20C as the 400 HP
  baseline.
- **Zero combat mobility effect.** `_recalculate_move_speed()`
  ([battle_unit.gd:306](prototype/scripts/battle_unit.gd:306)) sums *module* weights only. The
  `wt_mult × armor_thickness` weight increase exists **only in the Design Lab display**
  ([stat_calculator.gd:552](prototype/scripts/stat_calculator.gd:552)). Damage_And_Armor_Model.md
  promises thickness "drastically adds to weight and resource cost" — neither is true in combat.
- **energy_shielding dominates.** Design-lab multipliers: 2.0× HP at 0.5× (display) weight vs
  hardened_steel's 1.0×/1.0×. Threshold table ([damage_resolver.gd:37](prototype/scripts/damage_resolver.gd:37)):
  energy_shielding has the best kinetic threshold (20 vs steel's 15), best energy (35), and its
  reduction row (0.5/0.5/0.5/0.3) is best-or-near-best in every class. Reactive beats it only on
  explosive threshold, ablative only on thermal — and both at half the HP. Same price.

The correct answer for essentially every design is "energy_shielding, thickness 3.0." When a dropdown
has a correct answer, it isn't a choice — this is the Forged Battalion trap in its purest form, sitting
on the single most prominent pair of controls in the sidebar. Fix: per-material cost multipliers
(energy_shielding should be crystal-hungry), thickness scaling cost superlinearly, hull armor weight
feeding the real combat weight sum, and a real weakness for energy_shielding (kinetic is the thematic
candidate — "shields stop beams, not shells").

### 1.3 Hull scaling is free real estate with no upper bound

`hull_scale` affects the mesh, collision box, and mounting area — and nothing else. Combat `max_hp`
ignores it, weight ignores it, cost ignores it, and the gizmo clamps only the low end
(`max(0.1, ...)`, [gizmo_3d.gd:122](prototype/scripts/gizmo_3d.gd:122)) — there is no upper bound at
all. RTS_Unit_Designer_Concept.md explicitly specs the opposite ("size class dictates the upper and
lower bounds", "larger hull... increases the target profile and base weight"). And because weapons
auto-hit (1.5 below), the bigger target profile costs nothing. Net: stretching every hull to the
maximum you can stomach visually is strictly optimal — more mounting surface, free. This erases the
compact-vs-sprawling axis entirely. Fix: scale hull HP/weight/cost with volume (the code for this
exists — modules already do exactly this via `scale_multiplier`; the hull is the one thing that
doesn't), and clamp scale per size class as the concept doc says.

### 1.4 No evasion/miss mechanic — speed and size have zero defensive value

Every weapon fire path in auto_weapon.gd tweens a cosmetic visual to the target and then applies
damage unconditionally (`target.take_damage(...)` in the tween-finished callback). Nothing can dodge,
outrun, or be too small for anything. Traverse speed gates *acquisition* (must point within 10°), which
is real and good — but once aligned, a 4.5-second-reload howitzer cannot miss a scout doing 15 m/s.
The design docs lean heavily on evasion ("fast hover-drones drive circles around the heavy... the
turret physically cannot rotate fast enough") — half of that sentence is implemented (traverse), the
other half (the drone survives while circling) isn't, because the moment the turret *does* align, the
hit is guaranteed. Speed today buys map mobility only. For the differentiation test this is huge: "fast
and fragile" is not a viable identity if fast doesn't help you survive. Options: real projectiles with
collision (biggest change, best feel), or a hit-chance model from target speed + size + attacker
traverse state, applied in `_fire_at_target()`.

Related compressor: `move_speed = clamp(thrust/weight * 5, 2.0, 15.0)`
([battle_unit.gd:373](prototype/scripts/battle_unit.gd:373)) — every light design with decent thrust
hits the 15.0 ceiling, so two differently-built "fast scouts" often converge to *identical* top speed.
The clamp band is narrow enough (7.5×) that it eats a lot of the thrust/weight expressiveness the
locomotion tweaks feed into. Consider widening or soft-capping.

### 1.5 The tweak space: real tradeoffs exist, but several sliders are free wins and several are one-dial size knobs

Credit where due: some tweaks are genuinely well-shaped. `lens_aperture`/`containment`/`nozzle_width`/
`payload_size`/`rod_thickness` all multiply DPS while *dividing* fire_range and costing traverse — a
real reach-vs-punch tradeoff. Tread width trades capacity vs thrust vs terrain penalty. Leg count
trades stability vs agility. That's the right shape.

But audit the rest against "does this slider have a correct answer?":

- **`cooling_jacket`** (pd_laser): multiplies HP *and* DPS *and* only weight — no cost, no range or
  rate penalty ([module_data.gd](prototype/scripts/module_data.gd)). Max it, always.
- **`pressure_valve`** (flamethrower): multiplies DPS *and* range *and* fire speed; costs weight and
  traverse only. On any static defense — where weight is meaningless (foundations have no locomotion
  budget) — max it, always. The same "weight is the only price" problem applies to most DPS tweaks on
  every defense design: **the cost model whitelists only 5 tweak names** (`caliber, rail_length,
  seeker_size, payload_size, radar_dish` — [module_data.gd:72](prototype/scripts/module_data.gd:72));
  everything else changes resource cost by zero.
- **`barrel_count` / `tube_count` / `grid_size`**: multiply dps, weight, *and* cost by the same ratio —
  efficiency-invariant, so they're a pure "bigger or smaller" dial, not a tradeoff. Fine as size knobs,
  but they don't differentiate two players who both want "a big missile pod."

Recommendation: a systematic pass with one rule — **every tweak must appear in the cost model, and
every tweak must have at least one axis it makes *worse*.** The `test_no_dead_tweaks` guardrail was
the right idea at the "does it do anything" level; the next guardrail is "is there any reason not to
max it" — that could even be automated (score each tweak at min/max through the balance tool and flag
monotone winners).

### 1.6 Per-unit Energy rarely matters, and the drain weapons can't disable most targets

Only 3 of ~20 weapons cost energy to fire; everything else ignores the pool. `arc_projector` — the
dedicated "disable" weapon — drains a resource that, for the large majority of designs, *powers
nothing*: a target with no energy weapons loses nothing when drained to zero. The team-level pool's
only consequence anywhere is a 1.5× build-time penalty ([skirmish.gd:847](prototype/scripts/skirmish.gd:847)),
easily avoided. Two structural options: make energy power more subsystems (shield regeneration,
traverse motors, sensor range — then draining a tank actually degrades it), or accept it as a niche
weapon-family mechanic and stop presenting it as a third resource in the HUD. Right now it's in an
awkward middle where the Design Lab implies an energy-management axis that mostly doesn't exist.

### 1.7 Faction is per-blueprint in combat but per-match in the economy — and the Industrialists passive is cosmetic

Unit-level passives (hp_mult, dps_mult, speed_mult, detection...) read the *design's saved faction
tag* off hull meta; team-level passives (build time, metal discount, energy capacity) use the match
faction. The MatchSetup faction dropdown doesn't retag your designs, so a "Zealots" match can field an
army of units individually saved under five different factions, each keeping its own combat passive —
faction-shopping per design is the optimal play and the match-level choice is half-cosmetic. Pick one
scope and enforce it (my vote: match faction overrides blueprint tags at spawn — it makes the
pre-match choice meaningful and matches every RTS convention).

Separately: **Industrialists' "-20% armor weight" passive is consumed nowhere except the Design Lab
display** ([stat_calculator.gd:549](prototype/scripts/stat_calculator.gd:549) is the only real
consumer) — and since hull armor weight doesn't exist in combat at all (1.2), the *heavy armor
faction's* identity passive does literally nothing in a battle. This was logged as a known scope call
in DECISIONS_NEEDED.md; I think it was the wrong call to leave — it's the flagship faction's only
mechanic, and every other faction got a real hook.

### 1.8 Air units get a permanent armor-pierce bonus, and there is no real anti-air answer

Flying units cruise at y=4.0 ([battle_unit.gd:146](prototype/scripts/battle_unit.gd:146));
the elevation combat bonus triggers at a height advantage of 2.0
([damage_resolver.gd:21](prototype/scripts/damage_resolver.gd:21)). So every airborne attacker enjoys
the hill-holding 0.85× threshold pierce against every ground target, all the time — an unearned
+15% pierce for choosing wings, presumably an unintended interaction between two systems built in
different passes. Meanwhile the designated AA weapons (flak/ciws/pd_laser) are all in the
zero-damage-vs-armor family (1.1), and nothing else distinguishes air targeting (any weapon can shoot
air; "flak = AA" is flavor only). Air + terrain immunity + auto-hit + pierce bonus + no functional AA
is a stack of small advantages that likely makes airborne the dominant archetype. Worth a dedicated
balance pass: exempt air-to-ground from the elevation bonus, and give the PD family a real damage
identity vs airborne hulls.

---

## 2. Functionality gaps — structural, not "more content"

### 2.1 There is no design-versus-design game loop — the pitch's core loop stops at the player's half

The pitch: "your ability to prototype, adapt, and **counter enemy designs** is the primary driver of
victory." Today the opponent ([enemy_ai.gd](prototype/scripts/enemy_ai.gd), 133 lines) cycles through
6 static bundled blueprints, never designs or modifies anything, never reacts to what you field, never
places a building, and its wave logic is "every unit attacks the HQ on a timer." Nothing scans wreckage,
nothing surfaces enemy composition to the player, and the Operations/loadout/reinforcement
meta-structure from RTS_Unit_Designer_Concept.md (the thing that gives the Design Lab its *reason to
exist between matches*) has no implementation at all. The individual systems are far ahead of the loop
that's supposed to connect them. Two increments would change the game's character more than any
feature work: (a) an AI that picks counters — even a crude table ("player fielding armor → queue the
railgun design; player fielding air → queue flak") makes designs feel *seen*; (b) a post-match /
mid-match intel readout of enemy composition so the player's own counter-design loop has an input.

### 2.2 The interception/point-defense layer is disconnected in real matches

PD weapons intercept the `"missiles"` group — but weapon-fired missiles (guided_missile,
dual_stage_missile, missile_pod) are cosmetic tweened meshes never registered in that group
([auto_weapon.gd:870](prototype/scripts/auto_weapon.gd:870) ff.). Only `drone_unit` and the test
range's `incoming_missile` are interceptable. In a Skirmish, a CIWS escort protects against
essentially nothing, and (per 1.1) its gun can't hurt hulls either. One full leg of the intended
counter-triangle — "turtling with PD beats missiles/swarm" — isn't in the game. Making missile weapons
spawn real interceptable projectiles (the `incoming_missile.gd` template already exists and is cited as
such in the spec) is the fix, and it dovetails with the evasion work in 1.4.

### 2.3 No AoE anywhere in Skirmish

Mortars, howitzer, cluster_dispenser, flak — all resolve as single-target damage on the ordered target
(cluster splits its damage into 5 hits *on the same target*). The visuals scatter submunitions; the
sim doesn't. "AoE beats swarm" is the other missing leg of the counter-triangle, and it's also a
Design-Lab differentiation axis (blast radius as a tweakable) that currently can't exist. Even a
simple radius query around the impact point in the explosive weapons' hit callbacks would open this up.

### 2.4 Extra factories do nothing

`get_team_factory()` ([skirmish.gd:641](prototype/scripts/skirmish.gd:641)) returns the *first* living
manufactory of a tier; `_queue_player_unit` always queues there. Building a second Light Manufactory
— which the build bar explicitly sells as "parallel production capacity" — never receives a job. Same
for the AI (it skips production when the first factory's queue is full rather than using another).
Fix: pick the factory of the right tier with the shortest queue.

### 2.5 Subsystem stripping is RNG, not the targeted counterplay the docs promise

Damage_And_Armor_Model.md's swarm counter is *targeted* stripping ("target the radar dishes, treads").
Implementation: every hit has a flat 35% chance to hit a uniformly random module — including armor
plates and modules on the far side of the hull — with no player control and no directional gating
([battle_unit.gd:957](prototype/scripts/battle_unit.gd:957)). Two consequences: the tactical layer the
doc promises doesn't exist, and big-alpha weapons randomly dump 35% of their shots into a 100 HP
module while the hull takes nothing (the branch `return`s without hull damage) — a howitzer
"whiffing" a third of its shells into a wheel reads as phantom misses. Minimum fix: gate strippable
modules by the hit facet (the facet metadata already exists for armor); better: an attack-modifier
order or stance for targeting subsystems.

### 2.6 The Design Lab's headline stats are not the combat stats

The project's stated invariant — the visualization and the sim never drift — is broken at the top of
the stat panel:

- **Total HP**: sidebar shows Σ(module HP) × material × thickness
  ([stat_calculator.gd:551](prototype/scripts/stat_calculator.gd:551)); combat `max_hp` is *hull*
  HP × material × thickness with modules as separate strip pools
  ([battle_unit.gd:162](prototype/scripts/battle_unit.gd:162)). An empty medium_hull shows "Total HP:
  0.0" and spawns with 400. The two numbers measure different things and neither is what a player
  will experience.
- **Total Weight**: sidebar applies material/thickness/faction multipliers; combat speed uses the raw
  module sum (1.2). The overweight warning therefore fires against a different number than the one
  the overload penalty actually uses.

Given how much care went into keeping traverse arcs/firing arcs honest, these two headline labels are
the drift. Unify by extracting the combat formulas (hull HP calc, weight sum) into shared statics the
sidebar calls — the same move already made for `DamageResolver` thresholds.

### 2.7 No power-plant building, and base energy comes from your tanks

Team energy capacity is the HQ constant plus generator modules mounted on *units and defenses*
([skirmish.gd:224](prototype/scripts/skirmish.gd:224)). There's no generator *building*, so the C&C
loop the factions doc assumes (Expansionists' "energy-hungry defensive batteries") has no supply side
— and the actual optimal play (put a fusion_generator on a tank so your factories build faster; lose
the tank, lose the base's power) is thematically backwards. A simple Power Plant prefab would close
this, and it was already logged as a next-increment candidate on 2026-07-13 — it's the right one to
promote.

---

## 3. Bugs / problems found by reading the code

Highest player-facing impact first. Items 1.1, 1.8, 2.4, 2.6 above are also bugs by any reasonable
definition; not repeated here.

### 3.1 Weapons shoot through terrain, buildings, and other units

`_is_line_of_sight_blocked()` ([auto_weapon.gd:112](prototype/scripts/auto_weapon.gd:112)) only
returns "blocked" when the first ray hit belongs to the weapon's **own vehicle**. A hit on a rock,
urban building, hill, or intervening unit falls through to `return false` — clear to fire. So the
urban map's cover blocks *vision* and movement but not bullets: once any teammate spots a target,
every unit shoots it straight through walls, and damage applies unconditionally on the tween finish.
The vision system's careful LOS raycast (skirmish.gd `_has_line_of_sight`) makes this worse-looking,
not better — a building hides a unit until it's spotted from a flank, then everyone shoots through the
building. The fix is small: treat any non-target, non-self first hit as blocking (and exclude the
target's own colliders from "blocking").

Same function, opposite direction — this **confirms the open sponson question** logged 2026-07-17: the
vehicle's own Hull body is explicitly excluded from the ray (`own_colliders.append(hull.get_rid())`),
so a rear-facing sponson weapon can and will fire straight through its own hull. Other own *modules*
do block (they're caught by `is_ancestor_of`), but the hull itself never does.

### 3.2 Dragging a placed module to a different face leaves stale mount/facet state

`_update_module_placement()` ([module_placer.gd:1296](prototype/scripts/module_placer.gd:1296))
repositions and reorients during drag but never recomputes `mount_style`, `mount_normal`, or `facet`
metas, and never re-runs armor auto-fit/centering. Consequences: a weapon dragged from deck to side
keeps its pintle hardware and top-facet traverse gate; an armor plate dragged front→left keeps
`facet: "front"` — combat (`damage_resolver.resolve`) will then credit it to the wrong side of the
hull. Since directional armor is one of the project's marquee mechanics, silent wrong-facet plates
are a nasty trust bug. Re-run the placement-classification block from `_place_weapon()` on drag end.

### 3.3 Buildings can be stacked on top of each other

`_placement_validity()` ([skirmish.gd:927](prototype/scripts/skirmish.gd:927)) checks terrain and
base proximity but never building overlap, and the placement raycast uses mask 1 (ground only) while
buildings live on layer 8 — so the ghost happily sits inside an existing refinery and the click
places it there. Free defense-turtle stacking on one tile.

### 3.4 `get_module_data()` falls back to a *cannon* for unknown module ids

[module_catalog.gd:1315](prototype/scripts/module_catalog.gd:1315). Hulls got a proper
`hull_exists()` hard-fail in the modding pass, but a blueprint referencing an unknown *module*
type_id (hand-edited save, future mod, typo) silently reconstructs as a basic_cannon with cannon
stats. The same "refuse rather than silently corrupt" principle argued for hulls applies here.

### 3.5 `get_catalog()` rebuilds the full catalog dictionary on every call, including per-tick paths

Every `get_module_data()` call re-allocates the ~60-entry nested literal
([module_catalog.gd:10](prototype/scripts/module_catalog.gd:10)) — and it's called from genuinely hot
paths: `_is_line_of_sight_blocked()` runs per weapon per physics tick while engaged, `resolve()` per
hit, `_recalculate_terrain_speed_multiplier()` per unit per tick reaches it via `get_hull_draught`
etc. It also calls `HullLoader.get_hulls()` twice per invocation. Fine at 10 units; a real tax at 60.
One `static var _cache` would fix it — the hull half already caches, so the pattern exists in-file.

### 3.6 Threshold "Brute Force Rule" was never implemented

Damage_And_Armor_Model.md: overwhelming damage "punches straight through the mitigation multipliers."
`take_damage()` applies `amount * reduction` uniformly no matter how far above threshold the hit is.
Low priority on its own, but worth deciding deliberately — the doc treats it as a design pillar and
the current heavy-alpha meta (see 1.1) leans on reduction stacking.

### 3.7 Defense buildings never get their faction field set

`setup_defense()` reads faction into a local for vision but leaves `self.faction` at the default
([building.gd:33](prototype/scripts/building.gd:33)); `_get_construct_faction()` checks `c.faction`
*first* and finds "industrialists", so e.g. a Bayou Irregulars defense never gets its camouflage
detection bonus. The comment at building.gd:188 knows about the gap; the fix is one assignment.

### 3.8 Hull-scale dragging likely doesn't update authored hull meshes live

`_apply_scale_to_node()` ([gizmo_3d.gd:154](prototype/scripts/gizmo_3d.gd:154)) resizes the mesh only
`if mesh_inst.mesh is BoxMesh` — but all 15 hulls now load authored ArrayMeshes, whose visual scale is
set via `mesh_inst.scale` only in `update_hull_appearance()`/`reconstruct_vehicle()`, neither of which
runs during the drag. Reading the code, a scale-handle drag on an authored hull updates the collision
box (and stats) but not the visible mesh until some later rebuild. Flagged at medium confidence — I
couldn't run the editor to confirm — but if true it's very visible, and it's exactly the kind of thing
the screenshot discipline may have missed because verification shots tend to be taken *after* an
action completes (when a rebuild has run), not mid-drag.

### 3.9 Fog-hidden enemies are still click-targetable

Hidden constructs keep their collision layers; `_issue_order()`'s raycast will find them, and the
red attack marker confirms the hit — so right-click sweeping through fog reveals (and lets you
attack-order) unscouted units. Also, "Energy: 1/16" in the HUD reads as a stored quantity but is
actually a net-margin gauge (capacity − upkeep) — players will misread it; label it "Power" with a
net figure, C&C-style.

### 3.10 Blueprint files are trusted for cost

`blueprint_cost()` prefers the serialized `stats.cost_metal` baked into the save file over
recomputation. Single-player, so not urgent — but any hand-edited `user://blueprints/*.json` fields
units at arbitrary prices, and stale baked stats will also diverge from catalog rebalances (e.g. the
spigot_mortar/flamethrower price fixes don't apply to designs saved before them). Recompute from
catalog + tweaks at roster load instead.

---

## 4. What's genuinely working (so the criticism has a baseline)

- The mounting system (continuous pintle thresholds per weapon, facet classification, mount hardware,
  save/load of mount normals) is real, coherent, and single-sourced — the arc visualization sharing
  `get_traverse_limit_angle` with combat is exactly the right architecture.
- Locomotion is the best-differentiated axis in the game: 13 types with distinct capacity/thrust
  characters, a terrain-multiplier matrix with genuine identity (screw_drive's marsh bonus, legs on
  rock), real movement-paradigm differences (omni strafing, fixed-wing minimum airspeed, whole-vehicle
  aim), and count/width tweaks with actual sign-flipping tradeoffs. This is the part of the project
  that would pass the DESIGN_VISION differentiation test today.
- Directional armor with per-plate materials + slope multipliers + facet-aware AI (flanking, kiting)
  is a real simulation backbone most prototypes at this stage don't have.
- The verification culture (headless suite, screenshot discipline, `test_no_dead_tweaks`) is why the
  bug list above is mostly *systemic interactions* rather than local breakage.

## 5. If I had to pick five things to do next

1. **Fix the threshold/ROF interaction** (1.1) — it deletes a third of the arsenal and the swarm
   archetype with it.
2. **Price and weigh hull armor + hull scale in combat** (1.2, 1.3) — removes the two dominant
   free-power choices and makes the sidebar honest along the way (2.6).
3. **Add a miss/evasion model + real interceptable projectiles** (1.4, 2.2) — gives speed and PD their
   promised defensive value; both share the "real projectile" work.
4. **A counter-picking enemy AI + enemy-composition intel** (2.1) — the smallest version of the actual
   game loop the pitch describes.
5. **The weapon-fire LOS fix** (3.1) — small, high player-facing impact, and it makes the urban/cover
   maps mean what they look like they mean.
