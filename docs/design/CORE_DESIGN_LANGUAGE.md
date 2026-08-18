# Kitbash Command — Core Design Language

_The umbrella art-direction document: what the game is trying to look and feel like, and why._

**Scope, and what lives elsewhere.** This document owns the *whole-game* identity — philosophy, camera optics, environment, unit finish, motion, and the FX/audio split. It deliberately does **not** restate the deep specifications that already exist, because two sources of truth is how this project's docs drifted before:

| For | See |
|---|---|
| Faction material parameters, shader mask set, the ten factions, per-terrain-type texture direction, weapon-module modelling rules | [VISUAL_ART_DIRECTION.md](VISUAL_ART_DIRECTION.md) |
| Interface chrome — palette tokens, type scale, materials, elevation, motion | [prototype/docs/UI_STYLE_GUIDE.md](prototype/docs/UI_STYLE_GUIDE.md) |
| Hull massing and silhouette rules | [HULL_MASSING_SPEC.md](HULL_MASSING_SPEC.md) |

Where this document and those disagree, that disagreement is called out explicitly in **§7 Unresolved Tensions** rather than silently resolved.

---

## 1. Core Philosophy: Deadpan Absurdity

The aesthetic identity relies entirely on the sharp contrast between a gritty, hyper-realistic Cold War theater and the cartoonishly bold, toy-like nature of the combatants. The environment treats the war with absolute sincerity; the units and soundscape break the tension.

**The rule that makes this work:** exactly one side of any given pairing is allowed to be funny. Never both, never neither.

| Channel | Register | Rationale |
|---|---|---|
| Terrain, weather, lighting | Sincere | The straight man. If the world winks, nothing lands. |
| Unit colour and proportion | Absurd | The punchline. |
| Unit *construction quality* | Sincere | A sloppy kitbash reads as a bug, not a joke — see §4. |
| Visual effects | Sincere | §6. |
| Audio | Absurd | §6. |
| Interface chrome | Sincere | Already codified: the UI is "an instrument housing, not a feature." |

**Failure mode to watch for.** The joke dies from *both* directions. If the environment gets cartoony, the contrast collapses and it reads as a generic stylised game. If the units get realistic, it reads as a budget milsim. Every asset review should ask which side of the split the asset is on, and whether it is fully committed to that side.

---

## 2. Camera & Optics: The Macro Lens

The camera enforces the sub-1-unit miniature scale of the world through strictly applied optical effects.

- **Tilt-Shift Depth of Field:** the visual field maintains a sharp horizontal focal band across the active gameplay area. Foreground and background edges are heavily blurred to simulate a macro photography lens.
- **Proximity:** the camera angle sits close to the terrain, emphasising the massive relative scale of environmental ground textures.

### 2.1 Specifics

The focal band, not a radial blur, is the whole effect. A uniform blur outside a centre circle reads as a vignette; a *horizontal band* of sharpness with blur above and below is what the eye reads as a shifted lens plane. In Godot this is `CameraAttributesPractical`'s near and far DOF working together, with both distances tracking the camera's own distance to the focal plane so the band stays locked to the gameplay area as you zoom.

The reference implementation already exists in [designer_camera.gd:28-41](prototype/scripts/designer_camera.gd) — near and far blur both enabled, distances derived from the camera's current distance ±4 units, and a deliberately small `dof_blur_amount` of 0.08. Its own comment names the intent: "Miniature scale tilt-shift lens blur."

**Keep the blur amount low.** 0.08 is not timidity. A strong blur at RTS zoom destroys unit readability, and unit readability is a gameplay requirement, not an aesthetic preference. The miniature cue comes from the *presence of a focal falloff at all* — real macro photography has a shallow depth of field because it is close, and the brain infers "close" from the falloff regardless of its strength.

**Proximity has a hard ceiling.** The optical trick cannot survive an arbitrary zoom-out: past a certain height there is no plausible lens that sees that much ground at that depth of field, and the miniature read inverts into a map view. [rts_camera.gd](prototype/scripts/rts_camera.gd) currently allows `min_height` 10 → `max_height` 240 with pitch derived from height. The macro language holds at the low end and does not at 240 — see §7.

---

## 3. Environment: Macro-Realism

The battlefield provides a highly detailed, serious staging ground for the miniature units.

- **Biomes:** Midwest North America and Eastern European landscapes. Heavy focus on mud, slushy snow, marshlands, and dense ground-level brush.
- **Fidelity:** environments use hyper-realistic, physically based rendering.
- **Scale Anchoring:** environmental debris reflects the micro-scale of the units. Pebbles function as boulders; patches of marsh grass function as dense forests; tire tracks act as deep trenches.
- **Lighting:** atmospheric conditions mimic serious war cinematography. Heavy overcast skies, flat diffused natural light, and moody shadows.

### 3.1 Scale anchoring is the load-bearing idea

This is the single most important environmental rule, because it is what sells the miniature read when the camera is not moving. Every piece of environmental dressing must be a **real-world small object standing in for a real-world large one**:

| Plays the role of | Is actually |
|---|---|
| Boulder / rock outcrop | A pebble, with pebble-scale surface detail |
| Dense forest | A clump of marsh grass or moss |
| Deep trench / ravine | A tire track pressed into mud |
| Riverbed | A puddle with a debris tideline |
| Cliff face | A broken kerbstone or a shovel cut in soil |

The test: **would a photograph of this object, with no size reference in frame, be ambiguous about its size?** If the answer is no — if it has detail that only exists at boulder scale, like lichen zoning or weathered strata — it breaks the illusion and should be re-authored at pebble scale.

Corollary: **never place a real-scale human-world object in frame.** A door, a window, a road marking or a fencepost instantly resolves the scale ambiguity and the miniature read dies. Urban structures, which [VISUAL_ART_DIRECTION.md §4](VISUAL_ART_DIRECTION.md) covers, are the risk area here — they should read as *models of buildings*, and their detail frequency must be authored to match.

### 3.2 The ratio is 1:16, and it is the environment that moves

§3.1 says units are miniature relative to their surroundings; this section commits to the actual number and to *which side of the equation implements it*.

**The ratio.** Units are 1:16 scale models — a mock battle in a backyard, where the yard is a real yard. This is not a loose "small-ish" cue; it is a fixed multiplier applied consistently to every piece of environmental dressing, so the substitution table in §3.1 holds at a specific, checkable size rather than an art-direction feeling.

**The inversion.** The intuitive implementation is shrinking units to a literal 1:16 scale inside the map sizes that exist today. That is the one version the engine actively refuses. Godot's Recast navmesh baker sizes its voxel grid from `NavigationMesh.cell_size`, and voxel count scales as `(extent / cell_size)²` — [terrain_builder.gd](prototype/scripts/terrain_builder.gd)'s own header records hard-won empirical numbers: `cell_size` 0.25 on a 480-unit map already bakes a 1920×1920 voxel grid in ~1585 ms, and the baker **segfaults outright** past a further threshold. A unit shrunk to roughly 0.4 m needs a cell size around 0.06 to stay resolvable at the same fidelity — about 256× the voxels of a setting already measured as unshippable. Physics margins, near-plane precision and particle scales are likewise tuned against today's absolute sizes.

So the implementation runs the other way: **the environment is scaled up by 16×, and units, blueprints, combat math, `stat_calculator`, and `drivetrain` are left exactly as they are.** The picture is identical either way — a unit is 1:16 relative to a pebble regardless of which side of the ratio moved — but only this direction is buildable. It also means the battlefield genuinely gains 16× the space in unit-lengths, not just a rescaled look: a flank is a real commitment, and fog of war is genuinely blinding at ordinary vision ranges.

`prototype/scripts/world_scale.gd` is the single source of truth for the multiplier, applied to map geometry, terrain dressing, and the various derived grids (navmesh, flow fields, vision, fog) that would otherwise need 256× the cells to keep pace.

**The wall is fidelity, not cost.** `tools/probe_streaming_wall.gd` swept `scattered_peaks` (the largest bundled map) from world_scale 4 through 16 and confirmed the self-bounding grid formulas in `terrain_builder.gd`/`flow_field.gd` do exactly what they were built for: bake time stays flat (~210 ms), voxel dimension stays flat (~675²), flow-field cell count stays flat (1.21M) at every scale up to 16× on a map whose half-extent reaches 35 km. Nothing segfaults and nothing gets slower. What changes is the cell itself — `cell_size` grows from ~26 to ~105 units across that sweep, and at 105 units a single voxel is wider than most buildings on the map. The navmesh stays cheap by getting too coarse to resolve gameplay-scale detail, not by running out of budget. That coarseness is exactly what produced the exit-position and dock-bay bugs fixed at world_scale=4 (a few units off-mesh); at 16× the same mechanism would be measured in tens of units. Tiling the navmesh (rather than one map-wide bake) is what buys fidelity back without paying the cost back — it is a precision fix, not a performance one.

### 3.2 Lighting specifics

"Heavy overcast, flat diffused" is a deliberate constraint, not a mood note. It does three jobs at once:

1. **It is the sincere register.** Dramatic golden-hour lighting is cinematic in a way that flatters; overcast is the light of actual documentary war photography.
2. **It protects unit readability.** Flat ambient light means unit paint reads at its authored saturation everywhere on the map, rather than half the battlefield being in warm light and half in cool shadow. Given faction identity is carried *entirely* by colour (§4), inconsistent lighting would directly damage a gameplay signal.
3. **It suppresses specular noise.** Overcast means a broad, low-intensity light source, which keeps the brushed-aluminium anisotropic highlight from firing hard across every unit at once.

Concretely: high ambient contribution, low directional intensity, soft long shadows rather than hard short ones, and a sky that is a bright neutral grey rather than a gradient blue. **Avoid a strong single sun.** "Moody shadows" here means *soft occlusion in recesses and under hulls* — the job of SSAO and contact shadows — not long dramatic cast shadows.

There are currently no HDRI sky assets in the project; skies are procedural. That is sufficient for overcast and is probably the right call, since a photographic HDRI would bring its own baked-in sun direction and time of day.

---

## 4. Unit Design: The Polished Kitbash

Player-assembled units stand out against the drab environment through vibrant colours and unified construction.

- **Unified Surfaces:** despite chaotic modular combinations, the final unit presents as a professionally finished model. Seams, attachment points and structural disparities are covered and smoothed.
- **Vibrant Palettes:** unit colourings are cartoonishly bright and bold, ensuring high readability against mud and snow.
- **Dynamic Damage:** units feature several distinct, dynamic levels of visible damage as they take hits.
- **Faction Coding:** faction identity relies exclusively on applied colour schemes and swappable 2D details (decals, logos, camouflage patterns). Shape language and silhouettes are ignored for faction identification, because the player customises them.

### 4.1 Why "polished" is the hard requirement

This is the requirement most likely to be lost, because it is the one that costs work. A kitbash assembled from arbitrary player choices *wants* to look like parts jammed together. The design language says it must instead look like **an injection-moulded model kit of an absurd vehicle** — the absurdity is in the design, never in the manufacturing.

Practically, every module attachment needs a **transition element** that reads as intentional: a collar, a bolted flange, a fairing, a weld fillet, a rubber boot. The existing structural hull-extender modules (block, dome, slab, wedge, girder, I-beam) and the sponson/pintle mount conventions are the systemic version of this, and mount kits are already authored per locomotion type for the same reason.

The [VISUAL_ART_DIRECTION.md](VISUAL_ART_DIRECTION.md) "kit-of-parts grammar" rule is the other half: consistent panel lines, rivet rows and structural bolts across *all* factions, which reinforces "same engineering, different livery" and makes any two random modules look like they came from the same factory.

### 4.2 Faction coding is a settled decision with consequences

Identity by colour and decal only — never silhouette — is already committed to across the codebase, and it is the correct call given the Design Lab exists: a player can build a Technocrat unit shaped like anything, so shape can never be a reliable faction signal.

Two consequences worth stating:

- **The team-colour problem is real and unsolved.** If faction paint *is* the identity channel, two players on the same faction have no remaining material signal for "mine vs theirs." [VISUAL_ART_DIRECTION.md §1.6](VISUAL_ART_DIRECTION.md) proposes a separate low-saturation team marker layered on top. This remains the right approach and is not yet built.
- **This is why UI chrome is not faction-tinted.** The interface deliberately stopped repainting itself in faction colour, precisely so faction colour keeps meaning "who owns this unit." That decision is enforced by a test.

### 4.3 Dynamic damage

"Several distinct levels" should be **discrete stages, not a continuous blend**, for the same reason armour thresholds are discrete: the player needs to read remaining durability at a glance during a fight. Suggested three stages beyond pristine — scorched/scraped, panels torn and substructure visible, and structurally failing with smoke — each a clear silhouette-preserving read at RTS zoom.

Damage must be **additive over the faction material, never replacing it**: a heavily damaged unit must still be identifiably its faction's colour, or damage state and ownership start fighting for the same channel.

---

## 5. Animation & Physics: Rigid Miniatures

Unit movement emphasises their lightweight, plastic nature over the heavy machinery they represent.

- **Toy Physics:** units move with the stiff, abrupt motion of plastic models or lightweight remote-controlled toys.
- **Weightlessness:** vehicles lack suspension-driven momentum. They start, stop and turn sharply, ignoring the inertia typical of heavy military hardware.

### 5.1 Specifics

The cue is **absence**, which makes this cheap to implement and easy to break by accident. What must *not* be present:

- No acceleration or deceleration curve worth noticing — velocity changes should be near-instant.
- No body roll into turns, no pitch on stopping, no squat under acceleration.
- No suspension travel absorbing terrain; a wheel riding over a bump moves the whole hull.
- No settling, bobbing or overshoot after a stop.

What *should* be present, because it is what makes rigid motion read as a toy rather than as a bug:

- **Rotating parts still spin.** Wheels, treads, rotors and screw drums turn — a toy has moving parts, it just has no springs. This animation already exists per locomotion type.
- **Articulated running gear still articulates,** because it is geometry, not physics. A rocker-bogie's arms pivot to follow terrain in the way a toy's do — visibly mechanical, not damped.
- **Direction changes are instant but not teleported.** The unit rotates fast; it does not slide.

This is a genuine tension with the existing drivetrain model — see §7.

---

## 6. FX & Audio: The Sincere/Absurd Split

The effects systems split in entirely opposite directions to reinforce the core juxtaposition.

- **Visual Effects (Sincere):** explosions, muzzle flashes, smoke trails and terrain impacts are hyper-realistic. Weapon fire produces high-fidelity smoke plumes and kicks up realistic mud.
- **Audio Effects (Absurd):** mechanical and environmental audio is paired with overtly comedic, vocalised combat sounds. Heavy weaponry and gunfire feature literal human voice recordings ("pew pew", "kapow") instead of actual ordnance recordings.

### 6.1 The split is per-channel, not per-event

The same cannon shot is simultaneously a photoreal muzzle bloom with real smoke physics *and* a person saying "kapow." Both, at once, is the joke. Neither channel is allowed to hedge toward the other: a stylised puff of smoke, or a vocalisation with reverb and bass layered under it to make it "feel weighty," both kill it.

### 6.2 Audio taxonomy

Not everything is vocalised. The line runs between **ordnance** and **everything else**:

| Vocalised (absurd) | Real (sincere) |
|---|---|
| Gunfire, cannon shots, missile launches | Engine and motor loops |
| Explosions and impacts | Tread clatter, servo whine, hydraulics |
| Weapon charge-up / energy weapons | Radio chatter and comms static |
| | Environmental ambience — wind, rain, mud |
| | Interface feedback |

Radio chatter belongs firmly on the sincere side and is a strong tonal asset: a calm, clipped, professional voice reporting an engagement, over which the actual weapons go "pew pew," is the whole thesis in one moment. The project already has `sfx_radio_ack`, `sfx_radio_static` and `sfx_order_ping` available for exactly this.

**Performance direction for the vocalisations:** deadpan and committed, recorded dry and close. Not a comedian doing a bit — a person doing the sound effect *sincerely*, the way a child playing with models does. Wry, not zany. Pitch and timbre should still differentiate weapon classes so the audio remains informative: a heavy cannon is a low "kaPOW", a machine gun a rapid clipped "pewpewpew", so the player can still identify what is shooting without looking.

---

## 7. Unresolved Tensions

These are places where this document conflicts with the codebase or with another design document. They are recorded rather than resolved, because each needs a deliberate decision.

**7.1 Tilt-shift exists only in the Design Lab.** RESOLVED 2026-08-18 (PR 4 of the right-rail programme). [rts_camera.gd](prototype/scripts/rts_camera.gd) now carries the full tilt-shift band: `dof_blur_far_enabled = true` on the `CameraAttributesPractical_bt` resource in `Battle.tscn`, plus `_apply_dof_distances()` in `rts_camera.gd` (lines 75-84) which updates the far distance to `height + 30` and the transition width from 10 to 50 as the camera zooms. The transition lerp is the load-bearing piece — without it, the 20-unit transition was wider than the visible area at min zoom and imperceptible at max zoom, and the band read as either "everything is blurred" or "no blur at all". A regression test (`test_rts_camera_dof_band_widens_with_height` in `tests/test_ui_and_camera.gd`) pins the widening and the endpoint values. Near-blur is deliberately skipped (same reason as `designer_camera.gd`'s comment at line 13-15: a near-blur band on a panning camera reads as a doubled image).

**7.2 The battle camera zooms far past where the macro language holds.** `max_height` is 240 against a `min_height` of 10. Either the optical effect is accepted as fading out at high zoom (in which case say so, and make the DOF band widen with height so it degrades gracefully), or maximum zoom is reduced. Silently doing neither means the game looks like two different games at the two ends of the zoom range.

**7.3 "Weightlessness" contradicts the drivetrain model.** [drivetrain.gd](prototype/scripts/drivetrain.gd) implements weight capacity, an overload penalty and weight-derived top speed, and the locomotion work authored suspension struts and articulated rocker-bogies. Those are *simulation* commitments about mass mattering. §5 is a *visual* commitment about mass being invisible. These can coexist — mass affects the numbers, never the animation curve — but only if stated deliberately, because the natural instinct when adding polish is to animate the physics you already simulate. **Recommendation: keep the simulation, forbid the visual tell.** Weight changes how fast a unit goes, never how it eases into going there.

**7.4 The terrain palette exceeds the stated biomes.** §3 names Midwest North America and Eastern Europe — mud, slush, marsh, brush. The implemented `SURFACE_PALETTE` is `marsh, rocky, snow_mud, sand, gravel, forest, ice`. `sand` sits outside those biomes entirely, and [VISUAL_ART_DIRECTION.md §4](VISUAL_ART_DIRECTION.md) specifies a soft-sand terrain type while the faction roster includes the desert-nomad Dune Runners. Either the biome statement widens to include arid theatres, or sand and the Dune Runners' framing need revisiting. This is a content-scope decision, not an art one.

**7.5 Weapon audio was conventional. RESOLVED.** The ordnance set is now vocalised, per §6.2. It was not re-*recorded* — it is synthesised, by a source-filter (formant) model in `prototype/tools/audio/voice.py`: a Rosenberg glottal pulse train through a cascade of moving formant resonators, with plosive bursts and post-release aspiration on a separate noise branch. That is how speech synthesis worked for decades before sample concatenation, and short isolated prosodic utterances — "pyoo", "ka-PAOW" — are its easy case.

Choosing synthesis over a recording session was not only a convenience. It keeps the whole soundtrack on the same procedural footing as the meshes, icons and textures, it makes the *performance* a parameter (pitch contour, effort, breath, glide width are all in source and diffable), and it yields 6–8 seeded variants per weapon class for free, which is what actually defeats repetition fatigue on a sound the player hears thousands of times.

The prototype-on-one-weapon instruction was followed: the basic cannon was built and auditioned first, because it fires often enough to expose repetition fatigue immediately. The first pass read as too subtle — a parallel formant bank was cancelling the very formant ratios that carry vowel identity — and the fix was architectural (cascade rather than parallel) rather than cosmetic.

Pitch and timbre still differentiate weapon class so the audio stays *informative*: a 78 Hz "ka-POW" and a 400 Hz "pyoo" are distinguishable before either parses as a word.

**7.6 Menu lighting is not overcast.** The main menu's 3D showcase uses a warm key light at 1.35 energy against a cool rim — a deliberate studio-product-photography look for displaying the player's designs. That is arguably correct and *should* differ from the battlefield: it is a model on a turntable, not a unit in a war. Worth confirming as intentional rather than leaving it to read as an inconsistency.
