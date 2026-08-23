# Kitbash Command

A prototype RTS where **you design the units** — Spore's vehicle creator meets Command & Conquer skirmishes.

Design docs live under [`docs/`](docs/):

**Vision and direction** — [`docs/design/`](docs/design/)
- [DESIGN_VISION.md](docs/design/DESIGN_VISION.md) — the reference points (Spore, KSP's VAB) and **the differentiation test the Design Lab is judged against**. Read this first.
- [RTS_Unit_Designer_Concept.md](docs/design/RTS_Unit_Designer_Concept.md) — core vision & match flow
- [CORE_DESIGN_LANGUAGE.md](docs/design/CORE_DESIGN_LANGUAGE.md) — whole-game identity: camera optics, environment, unit finish, motion, the FX/audio split
- [VISUAL_ART_DIRECTION.md](docs/design/VISUAL_ART_DIRECTION.md) — material/shader parameters, per-terrain texture direction, weapon-module modelling rules
- [Factions_and_Buildings.md](docs/design/Factions_and_Buildings.md) — pre-fab base buildings and custom defenses
- [Map_Guidance.md](docs/design/Map_Guidance.md) — map authoring

**Specs** — [`docs/specs/`](docs/specs/)
- [Arsenal_Weapons_List.md](docs/specs/Arsenal_Weapons_List.md) — base weapon/module archetypes
- [Damage_And_Armor_Model.md](docs/specs/Damage_And_Armor_Model.md) — thresholds, damage classes, anti-heavy-meta counters
- [Design_Lab_UI_UX.md](docs/specs/Design_Lab_UI_UX.md) — designer UX (grab handles, arcs, clipping)
- [MOUNTING_AND_ARMOR_SPEC.md](docs/specs/MOUNTING_AND_ARMOR_SPEC.md), [HULL_MASSING_SPEC.md](docs/specs/HULL_MASSING_SPEC.md), [ENERGY_AND_BALANCE_SPEC.md](docs/specs/ENERGY_AND_BALANCE_SPEC.md), [ECONOMY_BALANCE.md](docs/specs/ECONOMY_BALANCE.md)

**Completed plans and historical reviews** are archived in [`docs/archive/`](docs/archive/). Interface chrome is specified separately in [`prototype/docs/UI_STYLE_GUIDE.md`](prototype/docs/UI_STYLE_GUIDE.md).

Running notes: [PROGRESS.md](PROGRESS.md) (dated log, newest first), [DECISIONS.md](DECISIONS.md) (active decisions and what is still pending), [GODOT_4_7_PITFALLS.md](GODOT_4_7_PITFALLS.md).

## Running the prototype

The prototype is a **Godot 4.7.1** project in [`prototype/`](prototype/). A copy of the engine is bundled (gitignored, so it will not be in a fresh clone):

```
cd prototype
./Godot_v4.7.1-stable_win64.exe          # run the game
./Godot_v4.7.1-stable_win64.exe -e       # open in the editor
```

> **Do not use the 4.3 executables.** A `Godot_v4.3-stable_win64.exe` pair may still be sitting in `prototype/` from before the engine upgrade. The project is authored for 4.4+ — it carries `.uid` sidecars and a `format=4` theme resource, and `project.godot` declares `config/features = ("4.7", ...)`. Opening it in 4.3 downgrades `config/features` and can strip UIDs. Delete the 4.3 pair if you have it.

## The game loop

The main menu is split into two sections, plus profile screens along the bottom.

**DEPLOY**
1. **SKIRMISH** — pick a map and a roster (12 slots), then a C&C-style battle. Harvest metal and crystal with harvesters, build Refineries / Manufactories / Power Plants / tech labs, produce your saved designs from the build bar, place custom defense blueprints, and destroy the enemy HQ.
2. **OPERATIONS** — a campaign of 3 to 12 engagements. Re-draft your roster between each one from your full blueprint library.
3. **PROVING GROUND** — field your current design against target dummies on a small dedicated test stage, driving it behind a chase camera.

**DESIGN**
4. **DESIGN LAB** — build blueprints on a 3D canvas. Drag parts from the bin onto a hull, drag gizmo handles to stretch barrels and calibers (stats update live), toggle bilateral symmetry (M), rotate modules (R), pick ammo and armor, and save to your Blueprint Library. Start from a **vehicle hull** for units or a **foundation** (Pillbox/Tower) for static defenses.
5. **BLUEPRINT LIBRARY** — browse, manage and preview saved designs.
6. **HULL AUTHORING** — shape new hull forms from primitives (SDF / marching-cubes bake).

**Profile** — **LIVERY** authors your own paint scheme (five zones, each with a colour and a PBR finish; purely cosmetic — see [`prototype/scripts/livery.gd`](prototype/scripts/livery.gd)). **RECORDS** and **SYSTEM** sit alongside it. Escape opens the pause menu and settings from anywhere.

On a first run the menu shows a single card instead: a 15-step guided tutorial that walks you through building a vehicle and fielding it.

### Skirmish controls

| Input | Action |
|---|---|
| Left-click / drag | Select unit(s) |
| Right-click | Move / attack target / send harvester to a resource node |
| Ctrl + right-click | Attack ground |
| WASD / arrows / middle-drag | Pan camera |
| Mouse wheel | Zoom |
| Esc | Pop the most specific open thing — placement, then selection, then the pause menu |

### Design notes reflected in the sim

- **Damage classes** (kinetic / thermal / explosive / energy) vs **armor materials** with per-class thresholds. A hit below threshold is chipped to 15%; a hit at 4x threshold or more starts punching through the reduction multiplier.
- **Directional armor** — an armor module only protects the facet actually facing the attacker.
- **Subsystem stripping** — a share of hits land on exposed modules; losing all locomotion immobilizes a unit.
- **Parametric tweaks** carry into combat: barrel length extends range but slows traverse, caliber trades rate of fire for per-shot punch, weight slows turrets.
- **Energy** is a real resource — generated by hull and generator modules, drawn by energy weapons, and drainable to brownout.
- **Fog of war** — vision comes from the hull baseline plus sensor modules; holding high ground pays off in both sight and armor penetration.
- A default loadout ships in `prototype/data/loadout/` and the enemy AI's roster in `prototype/data/enemy/`, both in the same JSON blueprint format the Design Lab saves to `user://blueprints/`.

> Faction *passives* no longer exist. Ten hand-authored factions each pairing a visual identity with a mechanical bonus were replaced by the player-authored Livery, which is cosmetic only — so two identical designs fight identically whatever colours they wear. Every stat now comes from what you actually built.

## Checks

**There is no automated test suite.** The headless suite (`run_tests.ps1` / `run_tests.sh` / `tests/`) was deleted on 2026-08-10 during the battle-system unification; see [PROGRESS.md](PROGRESS.md) for that call. Verification today is:

1. **Parse checks** after edits — targeted via `prototype/tools/compile_check_changed.gd`, full tree via `compile_check_all.gd` (slow: loads 200+ interdependent scripts, observed 20+ min):

   ```
   cd prototype
   ./Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/compile_check_all.gd
   ```

2. **Headless probe scripts** in `prototype/tools/probe_*.gd` — one-off SceneTree scripts that boot a slice of the game (navmesh, economy, AI, placement…) and print findings. This is the de-facto regression harness.

3. **Manual playtest** for anything visual/interactive.

Note: the `.godot` import cache is gitignored and goes stale whenever a new autoload or `class_name` script lands, which breaks headless runs with a misleading `Identifier "X" not declared`. Reimport first with `--headless --editor --import`.

## Art pipeline

Hulls and weapon/locomotion parts are authored **procedurally in Blender** rather than hand-modeled, so the whole kit can be regenerated or extended from one script:

```
cd prototype
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender/build_vehicle_hulls.py   # vehicle hulls -> assets/models/hulls/
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender/build_meshes.py          # parts, foundations, buildings
```

`build_vehicle_hulls.py` (with `hull_forge.py`) writes `assets/models/hulls/*.glb` plus a matching `.json` sidecar per hull and its convex collision decomposition. `build_meshes.py` writes `assets/models/parts/*.glb` (barrels, breeches, drums, domes, missiles, wheels, legs, rings — assembled by `visual_builder.gd` per weapon type, tweak-deformable), the foundation hulls, and buildings. Its old `generate_hulls()` is retired — see [`prototype/docs/HULL_NAMING.md`](prototype/docs/HULL_NAMING.md) for the Blender↔Godot axis chain and the rule that **forward is local −Z**. `visual_builder.gd` falls back to procedural primitives for any part not yet authored.

The shared hull surface texture set (panel seams, rivets, grain, corrosion — pure value, no hue, so livery zone colours multiply over it cleanly) is generated separately:

```
cd prototype
./Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tools/generate_hull_surface_texture.gd
```

After regenerating anything, reimport once so Godot picks up the new files:

```
cd prototype
./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import
```

## Audio

All sound effects, ordnance vocalisations, radio comms and ambience are **original and fully procedural** — generated from source by `prototype/tools/generate_audio.py` over the synthesis package in `prototype/tools/audio/`. No samples, no soundfonts, no impulse responses. Regeneration is deterministic and byte-identical.

```
cd prototype
python tools/generate_audio.py                   # everything (needs numpy, scipy, soundfile)
python tools/generate_audio.py --only cannon     # one bank
```

The **shipped soundtrack is curated, not synthesised** — finished tracks copied in from `Tracks/` at the repo root. A complete from-scratch procedural soundtrack engine also exists and still works (`--music-only --procedural-music`). See the provenance note in [CREDITS.md](CREDITS.md) before sharing builds.
