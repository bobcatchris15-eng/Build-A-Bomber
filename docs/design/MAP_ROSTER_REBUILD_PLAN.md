# Map Roster Rebuild — Full, Handsome Battlefields

## Context

The map roster reads thin, and the in-progress work stopped short of the reason
why. `docs/design/Map_Guidance.md` opens by naming the symptom — "10 flat,
mostly-dry maps where water is an occasional obstacle and the ground is one big
continuous sheet" — but the research below found the actual mechanism, and it is
not an asset shortage.

**The maps are empty because of a numbers bug, not a content gap.**
`world_scale.gd:27` sets `DEFAULT_WORLD_SCALE = 4.0`, and no map declares
otherwise, so every map runs at **4× its authored extents**. `open_plains` is
authored at half 210 and ships at half **840** — 2.82M units² of ground. Every
scatter pass in `terrain_visual_scatter.gd` is clamped, and at that area **every
single clamp is pinned at its ceiling**: grass wants `area/16` = 176,400 and
gets 14,000. That is one grass tuft per ~202 units² — **one tuft every ~14
units**, each roughly 2.6 units tall, standing alone in a circle of bare ground.
Authoring more content changes nothing until the clamps move.

The second mechanism compounds it. `terrain_greebles.gd:76` divides its base
counts by `prop_scale²`, which at the live 4.0 is a **÷16**: a rocky surface zone
gets `_scaled_count(3, 4.0)` = **0** large boulders and 1 small rock; a marsh gets
**0** driftwood logs.

And the third: **every one of the 60 authored terrain props ships with a flat,
untextured Principled BSDF** (`build_terrain_props.py:60`) — no UVs, no albedo,
no normal, no roughness — while the ground beneath them is a 512² photographic
PBR set blended three ways through a domain-warped noise shader. There is also
no `MultiMesh.use_colors` anywhere, so every instance of a given prop is
literally the same colour across the entire map.

The goal is a roster of **12–16 maps** that feel full and look markedly better
across elevation, ground surfacing, resource presentation, and dressing.

**Look references.** Units/buildings: Red Alert 2, C&C 3, Forged Battalion.
Terrain: Total War — Rome II, Shogun 2, Empire.

### Decisions taken

- **Roster grows to 12–16 maps.** `test_range.json` is untouched (it is a
  fixture with `disable_ambient_scatter: true` that the Design Lab's "Test in
  Arena" flow hard-depends on).
- **Look first.** No combat or economy changes. Schema grows only where dressing
  needs it.
- **Author:** new ground textures, terrain decals & detail maps, man-made set
  pieces. The Blender prop library is mid-build and needs finishing and
  *texturing*, not expansion.
- **Build to target density; do not gate on the current unit-CPU ceiling.**
- **The diorama rule wins.** `CORE_DESIGN_LANGUAGE.md` §3.1 stands: the
  environment is a 1:16 miniature, and *"never place a real-scale human-world
  object in frame."* Man-made set pieces are modelled as **scale-model kit** — no
  doors, no windows, no road markings, no fenceposts, no human-scale detail. The
  battlefield reads as a wargaming table, and the sincere-terrain /
  absurd-ordnance contrast the whole art direction is built on survives.
- **Keep world_scale at 4×** and fix the density, LOD and mesh defects underneath
  it rather than papering over them.

### One flagged concern, then we proceed

`docs/design/PERF_TESTING_RIG.md` measures **~2.4ms per unit per physics frame
headless** — ~7 units exhaust the 60fps budget before the renderer draws. Fix A
(30Hz physics) has already shipped (`match_rule_set.gd:136-141`), moving the
ceiling to ~14. Separately, `unit_assembly.gd:223` records an **empty scene
costing ~11.9ms of the 16.67ms budget**, and `perf_hud.gd:31` records **MSAA 4×
at ~31% of frame time on an empty map**. Building to target density is your call
and this plan does it — but Phase 1's LOD work is what makes that affordable,
and Phase 8 leaves a per-map perf record so the cost is a known number rather
than a surprise.

### Three existing violations to fix in passing

The diorama rule is already broken in shipped code, and holding the rule means
fixing these:

- `terrain_builder.gd:1970-1988` stamps **emissive window slits** on building
  obstacles — the §3.1 corollary, verbatim.
- `terrain_builder.gd:2016-2043` gives bridges **guard rails**.
- `build_terrain_props.py:627` authors `build_organic_cliff_strata` — *weathered
  strata* is the specific example §3.1 names as a disqualifier. Those 3 `.glb`s
  are referenced by no script at all; leave them unwired or re-author them.

---

## The plan

Nine phases. Each ends committable and independently verifiable, so a local
agent can grind through in order without holding the whole thing in context.

**Phases 1–3 deliver most of the visible gain and do not require authoring a
single new map.** Do not let the agent start on the roster before they land, or
every map gets built twice.

---

### Phase 1 — Density, variation and LOD (the root cause)

**Files:** `prototype/scripts/terrain_visual_scatter.gd`,
`prototype/scripts/terrain_greebles.gd`,
`prototype/scripts/terrain_builder.gd`

This is the highest effect-per-effort work in the plan.

1. **Raise the six clamps** at `terrain_visual_scatter.gd:293/346/388/427/464/505`.
   They were sized for a 1× world and ship at 4×. Make the ceilings scale-aware
   rather than absolute, so a bigger map gets proportionally more dressing
   instead of the same amount spread thinner.
2. **Fix `_scaled_count()`** (`terrain_greebles.gd:76`). The ÷`prop_scale²`
   currently zeroes out zone clutter entirely.
3. **Per-instance variation.** Enable `MultiMesh.use_colors` in
   `_add_multimesh_batch()` (`terrain_visual_scatter.gd:215`) and jitter hue,
   value and scale per instance. A few lines; kills the "same six objects
   everywhere" read.
4. **LOD.** Set `visibility_range_begin/end` per batch — none of the
   MultiMeshInstance3Ds have any, so all 14,000 grass tufts are submitted at max
   zoom-out. **This is what buys back the budget for (1).**
5. **Clustering.** Every scatter is uniform-random rejection sampling today.
   Cluster grass, shrubs and scree the way the ambient-tree pass already does —
   nature grows in patches, and clumping reads fuller than uniform density at the
   same instance count.
6. **Surface-normal alignment.** Only cliffs orient, and only in yaw
   (`:529-536`); everything else stands vertically on slopes.
7. **Cache height/slope in `scatter_all()`.** ~20,000 candidates each call
   `terrain_height_at()` + `slope_at()` (itself 4 more samples) = **~100k GDScript
   noise evaluations per map load**. `build_ground_visual_mesh()` already
   memoizes at `terrain_builder.gd:1557` — copy that.
8. **Chunk the ground visual mesh.** `GROUND_MESH_RESOLUTION = 3.0` is a flat
   unscaled constant: `scattered_peaks` at live half 2200 is **~2.15M quads /
   ~12.9M non-indexed verts through a single `SurfaceTool`**, one MeshInstance3D,
   no LOD, no frustum granularity. Chunk it and scale resolution with extent.
9. **Wire the orphans.** `cliff_corner_*.glb` (3) are authored and instantiated
   by nothing. Wire them. Leave `cliff_strata_*` alone per §3.1.
10. **Extend `terrain_greebles.gd` dispatch** to `gravel`, `forest` and `ice` —
    it only handles 4 of 7 surface types (`:38-43`), so three zone types are a
    silent no-op. Also: its props set **absolute Y**, so on any map with relief
    they float or sink. Snap to `terrain_height_at()`.

**Verify:** `probe_terrain_props.gd`, `probe_slope_rocks.gd`; load `open_plains`
and compare instance counts and frame time before/after.

---

### Phase 2 — Texture the props

**File:** `prototype/tools/blender/build_terrain_props.py` (`new_material()` at `:60`)

Give the 60 organic props real UVs and PBR maps. This closes the single largest
fidelity mismatch in the terrain layer — flat-shaded solids standing on
photographic ground.

Use **Blender 5.2** (`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`),
not the bundled UPBGE 3.0. Note `CLAUDE.md:171` is stale: it points at
`build_meshes.py`'s `generate_terrain_props()`, which is **dead code** —
the live path is `build_terrain_props.py`.

Hold `VISUAL_ART_DIRECTION.md` §4: terrain saturation sits **below** unit paint;
organic terrain is matte/painterly; the brushed-metal language is reserved for
man-made pieces.

**Verify:** `probe_terrain_props.gd` loads every pool through the real spawn
paths; visual check at RTS camera height.

---

### Phase 3 — Ground shader: splat, slope, wetness, macro

**Files:** `prototype/shaders/terrain_ground.gdshader`,
`terrain_builder.gd` (`build_ground_material_heightmap` `:1494`,
`_spawn_surface_zone` `:1703`, `_build_conforming_zone_mesh` `:1631`)

Keep the existing 3-variant domain-warped blend — it is good work solving a real
problem — and build on it.

1. **Make the surfacemap visible.** `get_surface_type_at()` (`:2466`) samples it
   for speed multipliers, but **nothing visual reads it**. Four maps ship
   surfacemaps whose painted types are invisible outside hand-authored rects.
   Sample it in the shader as a splat weight source.
2. **Then delete the zone-plane path.** `_spawn_surface_zone()` builds a
   conforming mesh lifted `ZONE_Y_LIFT = 0.03` with an 18% alpha edge fade —
   alpha-over, not a splat. The code says so itself at `:1676-1680` and scopes
   the real answer as future work. This is that work. Removes a transparency
   pass, N draw calls, and the floating-sticker look at once.
3. **Height-aware blending**, not linear `mix` — gravel should interlock into
   grass at the boundary. The most recognisable Total War terrain trait.
4. **Slope rules + triplanar.** A 60° face currently renders the same grassland
   texture, stretched. Force rock/scree above a slope threshold with triplanar
   projection. This also delivers §4's "elevated plateaus" mandate — warm
   rim-light and strata normal on vertical faces — which nothing implements.
5. **Wetness**, **macro colour variation**, **curvature AO**, and a
   **distance-based detail layer**, from the Phase 4 rasters.
6. Raise the variant ceiling: `MAX_TERRAIN_VARIANTS` is 8
   (`terrain_builder.gd:1405`) but the shader's `variant_count` caps at 3.

**Verify:** capture every map through `prototype/visual_regression/`; before/after.

---

### Phase 4 — Terrain generator: landforms and new rasters

**File:** `prototype/tools/terrain/build_terrain.py`

1. **Noise + erosion post-pass** — seeded fBM warp plus cheap hydraulic/thermal
   talus after features composite. Moves silhouettes from CAD to landscape.
   **Determinism is mandatory** (the file's existing contract): same input,
   byte-identical PNG, or every regeneration is a multi-megabyte binary diff.
2. **New primitives:** `river` (meandering spline channel), `terrace`
   (Shogun-style stepped agriculture), `crater`, `berm`, `road_cut`.
3. **New output rasters:** `<map>_splat.png` (per-pixel surface weights),
   `<map>_wetness.png` (distance transform from water edges),
   `<map>_macro.png` (low-frequency albedo tint), `<map>_curvature.png`.
   `Map_Guidance.md:364-379` already specs the wetness map.
4. **Fix the resolution ceiling.** `_sample_heightmap_bilinear()`
   (`terrain_builder.gd:381`) hardcodes **1 pixel per authored world unit** with
   no `dim / (2*half+1)` term — so at 4× that is **4 world units per texel**, and
   `--resolution N` silently produces a wrong map. Add an explicit
   pixels-per-unit that both the generator and the sampler read.
5. **Batch driver:** `--all` to regenerate every map's raster set.

**Verify:** regenerate `scattered_peaks` twice, diff for byte-identity; the B4/B5
heightmap suites still pass.

---

### Phase 5 — Ground texture library

**Tools:** numpy/PIL (already a `build_terrain.py` dependency), plus
`tools/generate_terrain_textures.gd` and `tools/check_texture_seam.gd` — an
objective seamlessness score that already exists for vetting plates. **Note:
GIMP and ImageMagick have zero footprint in this repo today**; Inkscape is
already driven via CLI by `tools/build_locomotion_decals.py`.

Variant discovery is by **file probe** (`_get_terrain_variants()` `:1407`) — so
dropping `<surface>_v4_albedo.png` into the folder adds variety with **zero code
change**. That makes this phase pure authoring.

- Fill `ice` to 3 variants (base only today); same for `blue_water`,
  `shallow_water`.
- Add types the roster needs: `dirt`/`ploughed`, `steppe_grass`, `dry_grass`,
  `mud`, `cobble`, `scree`, `volcanic`.
- A shared **detail/micro-normal** for Phase 3's distance layer, and a
  **height/displacement** channel for height-aware blending (pack into the
  roughness map's spare channels).

Hold the per-type mandates in `VISUAL_ART_DIRECTION.md` §4 — they are specific
and currently unimplemented. Especially: **snow and mud are two different looks**
(snow = warm-white with blue only in recesses; mud = dark, saturated, and
**glossy** — the one deliberate exception to matte terrain, because the gloss
*is* the "this will slow you down" cue).

Adding a surface type touches three places in lockstep: the
`surface_zones.surface_type` enum in `FIELD_SPEC` (`map_catalog.gd:467`),
`SURFACE_PALETTE` in both `terrain_builder.gd:418` **and**
`build_terrain.py:57`, and `TERRAIN_SPEED_MULTIPLIERS` in
`module_catalog.gd:3445` — miss the last and units silently get 1.0 on it.

---

### Phase 6 — Water and environment

**Files:** `prototype/scenes/Battle.tscn`, new `shaders/water.gdshader`,
`terrain_builder.gd` water spawn path (`:1746`, `:1767`, `:1792`), `FIELD_SPEC`

Water is the weakest area in the project: flat `PlaneMesh` at fixed `y=0.05`,
`StandardMaterial3D`, alpha 0.93. No shader, no animation, no foam, no depth
blend, no reflection, one draw call per body, and rect water doesn't conform to
terrain at all.

1. **Merge all water into one `ArrayMesh`** with one shared material.
   `Map_Guidance.md:328-339` has the pseudocode and costs it at 0.5 day.
2. **Real water shader** — depth-tinted colour, shoreline foam from
   `<map>_wetness.png`, scrolling normals, shadow casting off. §4 requires the
   shallow/deep boundary read as *"a soft-edged but clearly-valued transition
   line, not an ambiguous gradient — it's a hard gameplay boundary."*
3. **Per-map environment block** in `FIELD_SPEC` — sky/sun angle and colour, fog,
   ambient energy, exposure. There is **no per-map visual override of any kind
   today** beyond `ground_color`; every map shares one `WorldEnvironment` in
   `Battle.tscn:7-72`. A snow map and a marsh map must not share a sky.
4. **Height fog** for aerial perspective (`fog_enabled` is absent today).

Constrain to §3.2's lighting spec: high ambient, low directional, soft long
shadows, bright neutral grey sky, **avoid a strong single sun**. Read
`prototype/docs/RENDER_SETTINGS.md` first — it exists because `.tscn` files
cannot carry comments, and it records why each value is what it is.

---

### Phase 7 — Decals and miniature set pieces

**Reuse:** `vfx_effects.gd:363-388` `_ground_decal()` already builds Godot
`Decal` nodes with albedo + normal + ORM, `normal_fade = 0.55` and distance
fade. **Nothing in the terrain layer places a single decal** — every ground mark
today is combat-generated and temporary.

**Decals** (Inkscape → PNG, per the existing `build_locomotion_decals.py`
pattern): tyre ruts and track wear, puddles, tidelines, mud splatter, moss and
lichen patches, spoil staining around resource nodes, scorch. Add a `decals`
array to `FIELD_SPEC` (`center`, `half_extents`, `rotation`, `decal_type`,
`opacity`), every spatial field flagged `"scale": true`.

**Set pieces — in the miniature register.** New
`tools/blender/build_set_pieces.py`, copying `build_terrain_props.py`'s pattern.
The §3.1 test governs every piece: *"would a photograph of this object, with no
size reference in frame, be ambiguous about its size?"* So: **no doors, no
windows, no road markings, no fenceposts, no human-scale anything.**

What that leaves is still a lot — read as scale-model kit, not architecture:
low walls and revetments, embankments, culverts, blockhouse forms, tank traps,
spoil heaps, pipe runs, tanks and drums, gantries, rubble piles, wrecked-hulk
forms, jetties, breakwaters, causeways. Silhouette and massing do the work.

Extend `obstacles.type` beyond `["rock", "building"]` to the set-piece families
and **add a `rotation` field** — everything is axis-aligned today, which reads as
a grid. Add a `set_pieces` array for **non-blocking** dressing so density
doesn't carve the navmesh into confetti.

Per §4, man-made pieces get the **brushed-metal family, strictly neutral, no
faction tint** — which doubles as a passive "interactable" cue. Bridges
specifically: *"full brushed-aluminum treatment... hazard-stripe edge markings
from the shared decal library, NEUTRAL-tinted"* — they are a plain brown box
today (`terrain_builder.gd:2006`). Resource nodes get their own fixed
high-saturation industrial orange for economy legibility.

**Keep the all-or-nothing fallback contract:** if a `.glb` pool is missing, the
whole cluster degrades to primitives, never a mix.

---

### Phase 8 — The roster: 12–16 maps

Only now author maps. Build to **archetypes** so the roster has spread.
`Map_Guidance.md` §5.1 already designs four of these in detail — reuse it.

| # | Archetype | Signature |
|---|---|---|
| 1–2 | Open steppe / plains | Long sightlines, gentle rolls. Rome II open-field. |
| 3–4 | River valley | River + fords + bridges; crossing control. |
| 5–6 | Highland / terraced | Shogun terraces, escarpments, ridge fights. |
| 7–8 | Marsh / bayou | §5.1 "The Mire" / "Reed Bed". Leans on the existing terrain-speed rock-paper-scissors that no map exploits. |
| 9–10 | Coastal / archipelago | §5.1 "Chain Islands" / "Shattered Sea". |
| 11–12 | Settled / industrial | Phase 7's showcase. |
| 13–14 | Quarry / badlands | Spoil heaps, benched cuts, ore-rich. |
| 15–16 | Arid canyon / volcanic | Mesa, canyon chokes, hard palette contrast. |

**Per-map recipe:**
1. Author the JSON — extents, spawns, `base_zones`, resources, water, surface
   zones, decals, set pieces.
2. `python tools/terrain/build_terrain.py data/maps/<id>.json`
3. Reimport; **verify each new PNG's `.import` says `importer="image"` /
   `type="Image"`.** If Godot writes `importer="texture"`, `load(...) as Image`
   returns `null` and the map **silently falls back to the analytic path with no
   error**.
4. Load in-engine, screenshot at RTS camera height.
5. Add `test_map_<id>_smoke()` **and** its `SUITE_ORDER` row; run
   `check_suite_manifest.gd`.
6. Dress, screenshot again, record frame time and draw calls.

**Definition of done per map** — `suite_base.gd:200-363` `_smoke_test_map()` is
the real gate, and it is stricter than the lint alone:
- [ ] `MapCatalog.get_map(id)` validates clean.
- [ ] Enemy HQ auto-spawns inside its assigned `base_zone`.
- [ ] `hq`, `factory`, `refinery` for **both** spawns on unblocked ground.
- [ ] **Every** resource node ground-reachable from the nearer harvester spawn
      within `3.0 × world_scale`.
- [ ] HQ↔HQ mutually reachable within `12.0 × world_scale` (= 48 at 4×).
- [ ] `lint_spawn_fairness()` clean: ≥2 spawns, ≥2 resources within
      `0.6 × map_half_extents` of each HQ, pairwise distance CoV ≤ 0.35.
- [ ] The production loop still yields a unit.
- [ ] Heightmap regenerates byte-identically.
- [ ] `description` written — the player's only preview in `map_select.gd`.
- [ ] Visual-regression capture committed; perf numbers recorded.

**Retiring old maps:** `DEFAULT_MAP_ID = "lake_crossing"` is hardcoded at
`map_catalog.gd:60` — deleting that map makes every fallback resolve to `{}`.
Repoint it first. Ten per-map smokes at `test_terrain_and_maps.gd:398-465` and
their `SUITE_ORDER` rows go with their maps. `test_b7_open_plains_surfacemap_
covers_all_7_surface_types` requires a map exercising all 7 types — keep one.

---

### Phase 9 — Validation and the perf record

1. **New suites** for splat decode, the new feature primitives, decal placement,
   set-piece pool integrity, and a **pool-size-vs-files-on-disk assertion** —
   only ambient trees have one today (`:2606`), and the mismatch failure is
   silent.
2. **Per-map smoke** for every map in the roster.
3. **Visual regression** — one capture per map.
4. **Perf record** — extend the `probe_*.gd` pattern to emit per-map draw calls,
   triangle count, MultiMesh instance totals and frame time into a committed
   table. Not a gate; a number.

---

## Things that will bite the agent

Each of these is a documented failure mode in this repo that has already cost
someone a session.

**Build and test**
- **Always use the wrappers** — `./run_tests.ps1`, never a bare `--headless
  --script run_tests.gd`. The `.godot` cache is gitignored and goes stale the
  moment a new `class_name` lands, giving a misleading `Identifier "X" not
  declared`.
- **`compile_check_all.gd` is not quick** — 200+ scripts with
  `CACHE_MODE_IGNORE`, observed running 20+ minutes.
- Reimport after generating any asset:
  `./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import`
- **Never use the bundled Godot 4.3 binaries** — the project is 4.4+ authored;
  4.3 strips UIDs and downgrades `config/features`.
- Adding a test means editing **two** files (suite + `SUITE_ORDER`), then running
  `check_suite_manifest.gd`. **Do not reorder `SUITE_ORDER`** — the pinning is
  deliberate, several navmesh suites flake on what ran before them.
- There are **57** terrain/map suites, not 38 as `CLAUDE.md` states.

**Schema**
- **`FIELD_SPEC` is a closed schema at every nesting level** — an unknown key is
  a hard failure, and a failed map is refused entirely, after which `get_map(id)`
  silently falls back to `DEFAULT_MAP_ID`. A typo produces a *different map*, not
  an error the player sees.
- **There is no `world_scale` key in `FIELD_SPEC`** even though `world_scale.gd`
  reads one — so a map that declares it is rejected. Add the key when touching
  scale.
- **`"scale": true`** on every new spatial field, or it won't track world_scale.
  Balance numbers (ratios, amounts) stay unflagged — `resource_nodes.amount`
  deliberately is.

**Assets**
- **Pool-size constants live in three files** (`terrain_visual_scatter.gd:22-41`,
  `resource_node.gd:71-76`, `terrain_builder.gd:1878`). A size larger than what
  Blender exported rolls onto a missing `.glb` and **silently drops to a
  primitive with nothing logged**.
- Resource families must use the **canonical** id — `resource_ore_N.glb`, never
  `resource_metal_N.glb`; `ResourceCatalog.ALIASES` resolves one direction only.
- **Determinism** in `build_terrain.py` and every scatter pass — all are seeded
  off the map name and tested for it.
- Heightmap PNGs must be exactly `2 × map_half_extents + 1` px square.

**Landmines**
- **`tools/place_oil_wells.gd` will corrupt a map.** It reads through
  `MapCatalog.get_map()` — world_scale **already applied** — and writes those
  coordinates straight back to disk. Written when the default was 1.0; running it
  today multiplies every node position by 4. Fix it before use.
- **Async vs sync navmesh bake disagree on agent radius** — `_bake_nav_mesh()`
  uses `agent_radius = 1.0`, but `_bake_region_async()` (`:1077`) and
  `bake_pending_entry_async()` (`:1308`) hardcode **0.1**. The async path is what
  production load and mid-match rebake actually use.
- **Recast and large maps** — `map_half_extents ≤ 300` authored unless re-verified;
  `scattered_peaks` at 550 needed the cell-widening fixes. Every shoreline is
  geometry.
- **`prototype/scratch/.reimport_root/`** holds a stale pre-JSON copy of
  `map_catalog.gd`. Ignore it; it is on no load path.
- **Golden fixtures** in `suite_base.gd` — any intentional placement change lands
  in **its own commit** with an explanation.
- **No emoji or dingbats in UI text**, map names and descriptions included.

## Verification

```bash
cd prototype && ./run_tests.ps1
```

```bash
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import
```

```bash
cd prototype && python tools/terrain/build_terrain.py --all
```

```bash
cd prototype && ./Godot_v4.7.1-stable_win64.exe
```

End-to-end acceptance: every map loads, lints clean, reads visibly distinct from
its neighbours at RTS camera height, holds the §3.1 miniature rule, and has its
frame-time and draw-call numbers recorded.
