# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Kitbash Command** — A prototype RTS where you design the units. Think Spore's vehicle creator meets Command & Conquer skirmishes. The prototype is a **Godot 4.7** project in `prototype/`.

## Running the Prototype

The prototype bundles its own Godot engine executables. Run from the `prototype/` directory:

```bash
cd prototype
./Godot_v4.7.1-stable_win64.exe          # run the game
./Godot_v4.7.1-stable_win64.exe -e       # open in the editor
```

The main menu links the full game loop:
1. **Design Lab** — Build blueprints on a 3D canvas. Drag parts from the left bin onto a hull, drag gizmo handles to stretch barrels/calibers (stats update live), pick armor material + thickness, toggle bilateral symmetry (M), rotate modules (R), and save to your Blueprint Library.
2. **Skirmish** — C&C-style battle. Harvest metal/crystal with harvesters, build Refineries/Factories, produce saved designs from the bottom build bar, place custom defense blueprints, destroy the enemy HQ.
3. **Test Range** — Drive your latest saved design against target dummies (some shoot back).

## Tests

**Always use the wrapper scripts** — the `.godot` import cache is gitignored and goes stale whenever a new autoload or `class_name` script lands, which breaks a direct `--headless --script run_tests.gd` run with a misleading `Identifier "X" not declared` error.

```bash
cd prototype
./run_tests.ps1   # Windows (PowerShell)
./run_tests.sh    # Linux/macOS/Git Bash
```

The wrapper reimports assets (regenerates the import cache) then runs the full headless test suite. The suite runs every registered test regardless of earlier failures and prints a full list of failing suite names at the end.

### Test Architecture

- `run_tests.gd` is only the driver — it owns the retry quarantine, the ordered manifest (`SUITE_ORDER`), the pass/fail tally, and the exit code.
- The 211 test suites live in `prototype/tests/` (split from the original 16,000-line monolith), grouped by area, all extending `tests/suite_base.gd`.
- `SUITE_ORDER` is explicit because several navmesh/Recast suites flake depending on what ran before them — the order is deliberately pinned rather than derived.
- To add a suite: write the function in an area file **and** add it to `SUITE_ORDER` in `run_tests.gd`.

### Test File Layout

| File | Suites | Covers |
|---|---|---|
| `test_terrain_and_maps.gd` | 38 | terrain build, navmesh, pathing, map JSON, spawn fairness |
| `test_economy_and_production.gd` | 34 | resources, harvesting, queues, manufactories, energy, repair |
| `test_weapons_and_damage.gd` | 35 | damage model, armor facets, arcs, ammo, missiles, LOS, sponson mounts |
| `test_designer_lab.gd` | 21 | clipping, gizmos, tweaks, symmetry, blueprints, mounting |
| `test_sim_and_stats.gd` | 18 | stat math, traits, combat sim, evasion, audio, parse checks |
| `test_locomotion.gd` | 18 | all locomotion types, layout fixtures, drivetrain, animation |
| `test_ai_and_win.gd` | 13 | enemy AI, waves, fog of war, team targeting, win condition |
| `test_ui_and_camera.gd` | 13 | theme, icons, overflow, dock/flyout, RTS camera, control groups |
| `test_base_building.gd` | 12 | placement legality, footprints, buildable area, ghost refunds |
| `test_hull_and_armor.gd` | 9 | hull greebles, decals, foundations, factions, materials |

### Quick Parse Check

After any bulk edit, verify every script still parses:

```bash
cd prototype
./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/compile_check_all.gd
```

## High-Level Architecture

### Core Systems

**Blueprint System** (`blueprint_manager.gd`, `module_catalog.gd`, `module_data.gd`)
- Blueprints are JSON saved to `user://blueprints/` with versioning (current: 2.0).
- `blueprint_manager.gd` handles serialize/deserialize, reconstruction into live vehicles, and the scratch vs. saved design split (scratch for test-range trips, saved only on explicit user Save).
- `module_catalog.gd` defines all hull types, weapon modules, locomotion types, armor materials, and their stats.

**Combat & Damage Model** (`damage_resolver.gd`, `battle/units/unit.gd`, `auto_weapon.gd`)
- **Damage classes**: kinetic, thermal, explosive, energy.
- **Armor materials**: hardened_steel, reactive_armor, ablative_ceramic, energy_shielding — each with per-class thresholds and reduction multipliers.
- **Threshold system**: hits below threshold deal chip damage (15% of reduced damage); brute-force hits (≥4× threshold) blend reduction toward 1.0.
- **Subsystem stripping**: 35% of hits target exposed modules; losing all locomotion immobilizes.
- **Directional armor**: armor modules only protect the facet facing the attacker.

**Unit Runtime** (`battle/units/unit.gd`)
- Generic team-aware combat unit built from blueprint via `BlueprintManager.reconstruct_vehicle()`.
- Handles armor/damage, subsystem stripping, movement orders, flying/naval/screw-drive locomotion, harvester economy loop.
- Fog-of-war: vision range from hull base + sensor modules; `fog_hidden` gates rendering and targetability.
- Navigation: uses `NavigationAgent3D` when a real Skirmish match controller exists; falls back to direct-line steering in tests.

**Design Lab** (`stat_calculator.gd`, `parts_menu.gd`, `gizmo_3d.gd`, `module_placer.gd`, `visual_builder.gd`)
- There is no `main_lab.gd`. `scenes/MainLab.tscn` is only the 3D world plus two UI sub-scenes: `UI_StatBlock.tscn` (script `stat_calculator.gd` — the right-hand stat/tweak rail) and `UI_PartsMenu.tscn` (script `parts_menu.gd` — the parts bin).
- 3D canvas for building blueprints. Drag parts from parts menu onto hull facets.
- Gizmo handles for stretching barrels/calibers (live stat updates), bilateral symmetry (M), free rotation (R).
- Clipping detection prevents overlapping modules.
- `module_placer.gd` computes locomotion station positions (10 types × 3 hull sizes) — golden fixture in `suite_base.gd` must match exactly.

**Skirmish Match Controller** (`skirmish.gd`, `match_config.gd`, `match_setup.gd`)
- RTS economy: metal/crystal harvested by harvester units, delivered to Refineries.
- Production queues at Factories/Manufactories (tiered, parallel queues with 0.75× bonus for second same-tier factory).
- Energy system: base from hull + generator modules; regenerates; spent by energy weapons; can be drained.
- Enemy AI: wave-based, counter-picks player composition, places defenses when HQ threatened.

**Terrain & Navigation** (`terrain_builder.gd`, `map_catalog.gd`)
- Maps are JSON (migrated from hardcoded constants). Heightmap-based terrain with 7 surface types.
- Multiple navmeshes: ground, water, deep water, amphibious (combined ground+water for screw-drive).
- Hull draught routes naval units onto deep_water_map vs water_map.

**Collision Geometry** (`module_volume.gd`, `hull_surface.gd`, `mesh_weld.gd`, `hull_collision_shapes.gd`)
- **`module_volume.gd` is the single source of a module's occupied space.** It measures each `MeshInstance3D` into a parallelepiped (centre + three half-edge vectors, so nested non-uniform scale shear survives) in module-local space, caches it on the node, and is invalidated by `VisualBuilder.build_visual()`. Both the Lab's click collider and the clipping test read it — they used to disagree, and the clip test was the one using `ModuleCatalog`'s authoring `size`.
- Design Lab clipping is a merged-AABB broad phase then a 15-axis **separating-axis test per mesh pair**. A module with no meshes at all falls back to its catalog box (`clip_boxes()`); `boxes()`/`bounds()` deliberately do not, because callers rely on "empty means it draws nothing".
- A battle module gets an **`Area3D` hit volume** (one box per visible mesh, capped at `BATTLE_MODULE_MAX_SHAPES`) on `BattleLayers.UNIT_MODULES`. Built before `bake_module_visual()` merges the sub-parts away. `Area3D` not `StaticBody3D`: it rides a moving unit, and `build_visual()` only spares `StaticBody3D` children when clearing.
- **Layers are the trap here.** `UNIT_MODULES` (128) is deliberately not the Lab's modules bit (2), which is in `auto_weapon`'s LOS mask — a hit volume must not double as an occluder. `HULL_SURFACE` (256) is deliberately not `hull_surface.gd`'s own default (16), which is `RESOURCE_NODES` in a match.
- Hull colliders are three tiers: the baked convex decomposition (`assets/models/hulls/<id>_collision.res`), else a single `create_convex_shape()` fit, else a box. See the Art Pipeline section for baking.

**UI System** (`ui_shell.gd`, `ui_dock.gd`, `ui_flyout.gd`, `ui_theme.gd`, `ui_tokens.gd`, `bomber_theme.tres`)
- Asymmetric command deck UI with animated cards, dock/flyout panels, control groups (assign/recall/double-tap recenter).
- Theme system with tokens for spacing, colors, typography. No decorative glyphs/emoji in UI text.

### Key Data Files

| File | Purpose |
|---|---|
| `scripts/module_catalog.gd` | All hull types, modules, locomotion, armor materials, weapon archetypes |
| `scripts/damage_resolver.gd` | ARMOR_TABLE, damage math (threshold, chip, brute-force, module strip) |
| `scripts/stat_calculator.gd` | Live stat computation from blueprint (weight, speed, range, DPS, etc.) |
| `scripts/drivetrain.gd` | Drivetrain analysis: weight capacity, overload penalty, top speed |
| `scripts/faction_catalog.gd` | Faction passives (Industrialists: −20% armor weight, Technocrats: +5% speed, etc.) |
| `data/loadout/` | Default player blueprints (JSON) |
| `data/enemy/` | Enemy AI rosters (JSON) |

## Development Commands

```bash
# Run the game
cd prototype && ./Godot_v4.7.1-stable_win64.exe

# Open editor
cd prototype && ./Godot_v4.7.1-stable_win64.exe -e

# Full test suite (reimports first)
cd prototype && ./run_tests.sh

# Parse check all scripts
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/compile_check_all.gd

# Regenerate ALL audio (SFX, vocalisations, comms, ambience; music is copied
# from Tracks/, not synthesised - see below)
# Needs: pip install numpy scipy soundfile
cd prototype && python tools/generate_audio.py
cd prototype && python tools/generate_audio.py --only cannon,click   # one bank
cd prototype && python tools/generate_audio.py --music-only
# Render the from-scratch procedural soundtrack instead of the curated Tracks/
# set (both exist; curated is what currently ships - see Audio Pipeline below):
cd prototype && python tools/generate_audio.py --music-only --procedural-music
# Then reimport so Godot writes the .import sidecars:
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import

# Regenerate procedural meshes (Blender)
cd prototype && ./UPBGE-0.30-windows-x86_64/blender.exe --background --python tools/blender/build_meshes.py
# Then reimport in Godot:
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import
```

## Art Pipeline

Everything is authored procedurally in Blender, not hand-modeled. **Two
separate scripts, and the split matters:**

| Script | Owns | Outputs |
|---|---|---|
| `tools/blender/build_vehicle_hulls.py` (+ `hull_forge.py`) | The 81 **vehicle hulls** — 8 manufacturers × 6 classes | `assets/models/hulls/*.glb` + matching `.json` sidecars (non-foundation) |
| `tools/blender/build_meshes.py` | Parts, foundations, buildings, terrain props | `assets/models/parts/*.glb`, the 13 `is_foundation: true` hulls, buildings |

`build_meshes.py`'s `generate_hulls()` is **retired and raises if called**. It
authored through an axis helper with determinant −1 and then applied a second
determinant −1 matrix *after* `recalc_face_normals`, so every hull it produced
shipped inside out. Do not resurrect it; see
[`prototype/docs/HULL_NAMING.md`](prototype/docs/HULL_NAMING.md) for the
measured Blender↔Godot axis chain, the two winding checks, and the rule that
**forward is local −Z**. Foundations and buildings are unaffected — they never
went through that path.

`visual_builder.gd` falls back to procedural primitives for any part not yet authored in Blender.

```bash
# Rebuild the vehicle hull catalogue, then reimport
cd prototype && "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender/build_vehicle_hulls.py
```

### Hull collision shells

Every hull ships a third file next to its mesh and sidecar:
`assets/models/hulls/<id>_collision.res` — the convex **decomposition** of its
welded shell, mounted by `unit_assembly._add_hull_collider()` as one
`CollisionShape3D` per piece. Without it a unit falls back to a single convex
fit, which fills deck wells, the gap under a tapered keel and the space between
sponsons. 34 of the 94 hulls split into 2–5 pieces; the other 60 are genuinely
convex and get one, i.e. no change.

```bash
# Re-derive collision for the whole roster WITHOUT touching hull geometry
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/bake_hull_roster.gd --quit -- --collision-only
```

Three things about this are non-obvious and were each found the hard way:

- **`--collision-only` exists so adding collision data never rewrites a hull
  mesh.** A full bake regenerates every `<id>.res` — a large binary diff, and it
  re-runs marching cubes on geometry that already shipped. It also enumerates a
  *different set*: the shipped roster is 94 Blender-authored `.glb` hulls with
  no assembly sources at all, so collision-only lists the OUT_DIR sidecars and
  resolves each mesh through `MeshAssetLoader.get_hull_mesh()` — the same
  precedence chain the game uses, which is what guarantees the shell matches
  what a unit spawns with.
- **The weld is mandatory and is not `SurfaceTool.index()`.** That dedupes on
  the whole vertex tuple, and a faceted hull's coincident corners carry
  different normals, so it merges nothing. `mesh_weld.gd` welds on position
  only; measured, it takes the roster from ~18% to 100% shared topology. Without
  it the decomposer has no vertex adjacency and hangs.
- **`max_concavity` defaults to 1.0, which silently does nothing.** At the
  default VHACD returns one piece for every hull in the roster — reproducing the
  single convex fit exactly. `DECOMP_MAX_CONCAVITY = 0.05` is where the real
  splits appear and stop changing. Also note there is no `Mesh.convex_decompose`
  in Godot 4.7.1; the only decomposition entry point in ClassDB is
  `MeshInstance3D.create_multiple_convex_collisions()`, which attaches a
  `StaticBody3D` of shapes rather than returning them.

Hull-specific gotcha when adding one: an element's **vertical extent must be a
function of the hull's height alone**. Deriving it from width makes the
`autofit()` envelope solve non-convergent, and `hull_forge.normalize()` raises
rather than silently squashing the hull.

**Orrin uses tumblehome** — the cross-section is wider at the bottom (full
underside) and narrower at the top (`mass_w * tumblehome_frac`, default 0.80).
The tumblehome slope is part of the outline, not a post-process.

**Prominent greebles (masts, spines, barbettes) are integrated as
cross-section peaks** for Orrin, Kestrel, Rackham, Calder and Pillar — each
peak is a 4-vertex mesa bump on top of the chassis, active only in a small
z range, with the peak vertices held in the outline at every z (collapsed
to a flat segment on the deck when not active) so the cross-section point
count stays constant for the loft. This kills the "floating detail" look
that bolted-on `add_chamfered_box()` greebles used to leave behind on the
drone tender, command car, prospector and similar hulls.

## Audio Pipeline

**All audio is procedural and generated by `tools/audio/`** — there are no
recorded samples anywhere in the project. `tools/generate_audio.py` is a thin
CLI over that package, which is layered strictly downward:

| Module | Owns |
|---|---|
| `tools/audio/dsp.py` | numpy/scipy primitives: oscillators, filters, envelopes, saturation, reverb, tape |
| `tools/audio/instruments.py` | Music patches (guitar, bass, brass, kit, modal metal) |
| `tools/audio/sequencer.py` | Tracker-style patterns and timing |
| `tools/audio/tracks/` | One module per song |
| `tools/audio/voice.py` | Formant synthesis — the vocalised ordnance AND the radio comms |
| `tools/audio/sfx.py` | Every non-music sound, and the manifest of what exists |
| `tools/audio/render.py` | File output and pruning |
| `tools/audio/curated_music.py` | Copies the shipped soundtrack in from `Tracks/` at the repo root (see below) |

**The shipped soundtrack is currently curated, not synthesised.** `Tracks/` at
the repo root holds externally-generated finished tracks; `curated_music.py`
maps 5 states to one file each and copies it into `assets/audio/music/`.
**Skirmish is a rotation pool of 8 tracks, not one file** — `audio_manager.gd`
auto-advances to a new track (never repeating consecutively) each time the
current one finishes, so a skirmish running longer than any single track
doesn't just loop. See `curated_music.py` for the full state→track mapping.
The from-scratch synthesis engine in `tools/audio/tracks/` (oscillators →
instruments → a tracker sequencer → mastering) is still complete and still
works — `generate_audio.py --procedural-music` renders it — but it is not the
default. **Provenance of the `Tracks/` files is unconfirmed** — see the ⚠ note
in `CREDITS.md` before shipping. One consequence of curated tracks being
single mixed masters with no stem split: `match_director.gd`'s combat-intensity
mixing (which raises a rhythm/lead layer under a real engagement) has nothing
to act on and just lets the current rotation track play — correct, just
without the dynamic layering the procedural engine provides.

**`assets/audio/audio_manifest.json` is the contract.** The generator writes it;
`audio_manager.gd` loads it at boot to build its variant banks. Adding a sound is
a one-line edit to `sfx.py`'s `manifest()` plus a re-run — **no GDScript change**.
This exists because the old hand-maintained `SFX_PATHS` dictionary drifted from
`ui_feedback.gd`'s role table and left eight UI roles silently playing nothing.

**Determinism is required.** Every generator takes a seed and re-running must
produce byte-identical output, or each regeneration becomes a multi-megabyte
binary diff. Do not introduce an unseeded `random()` anywhere in `tools/audio/`.

**The sincere/absurd split is enforced by module.** `CORE_DESIGN_LANGUAGE.md` §6
requires ordnance to be vocalised (absurd) and everything else — comms, engines,
interface, ambience — to be played straight. Ordnance banks come from
`voice.ORDNANCE`; everything authored in `sfx.py` is sincere. If a sound in
`sfx.py` wants to be funny, it is in the wrong module.

## Important Notes

- **Godot version**: 4.7.1 (bundled executables in `prototype/`, gitignored). The README mentions 4.3. A 4.3 pair may still be present from before the upgrade — **do not use it**: the project is authored for 4.4+ (126 `.uid` sidecars, `bomber_theme.tres` at `format=4`), and opening it in 4.3 downgrades `config/features` and can strip UIDs.
- **`compile_check_all.gd` is not a "quick" check** at this codebase's size. It loads 200+ interdependent scripts with `CACHE_MODE_IGNORE`, and has been observed running 20+ minutes without completing. Prefer `run_tests.ps1`. Also note Godot block-buffers stdout when piped, so a direct `--script` run shows no output until it exits — and needs `--quit`/`--path`, which the wrapper supplies.

### Art direction docs

| Document | Owns |
|---|---|
| `CORE_DESIGN_LANGUAGE.md` | Whole-game identity: philosophy, camera optics, environment, unit finish, motion, FX/audio split. Start here. |
| `VISUAL_ART_DIRECTION.md` | Faction material/shader parameters, the ten factions, per-terrain-type texture direction, weapon-module modelling rules. |
| `prototype/docs/UI_STYLE_GUIDE.md` | Interface chrome only — tokens, type scale, materials, elevation, motion. |
- **Test order matters**: `SUITE_ORDER` in `run_tests.gd` is pinned due to navmesh flakiness. Do not reorder.
- **Golden fixtures**: `suite_base.gd` contains frozen locomotion layout data. Any intentional placement change must update the fixture in its own commit with explanation.
- **No emoji/dingbats in UI text** — a standing rule, but note it is **not** currently enforced by anything. `ui_audit.gd` only checks panel overflow, offscreen controls, theme-resource validity, icon assets and cursor assets. Box-drawing and arrows are allowed (technical notation).
- **Blueprint version**: Only bumped when JSON schema changes could silently mis-load older saves (currently 2.0 after SDF/Marching-Cubes hull rebuild).
- **Scratch vs Saved designs**: "Test in Arena" writes a scratch file (`user://lab_scratch.json`), never a roster entry. Only explicit Save creates `user://blueprints/<id>.json`.