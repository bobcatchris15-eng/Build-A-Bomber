# Build-A-Bomber

A prototype RTS where **you design the units** — Spore's vehicle creator meets Command & Conquer skirmishes.

Design docs live at the repo root:
- [RTS_Unit_Designer_Concept.md](RTS_Unit_Designer_Concept.md) — core vision & match flow
- [Arsenal_Weapons_List.md](Arsenal_Weapons_List.md) — the base weapon/module archetypes
- [Damage_And_Armor_Model.md](Damage_And_Armor_Model.md) — thresholds, damage classes, anti-heavy-meta counters
- [Design_Lab_UI_UX.md](Design_Lab_UI_UX.md) — designer UX (grab handles, arcs, clipping)
- [Factions_and_Buildings.md](Factions_and_Buildings.md) — factions, pre-fab base buildings, custom defenses

## Running the prototype

The prototype is a **Godot 4.3** project in [`prototype/`](prototype/). A copy of the engine is bundled:

```
cd prototype
./Godot_v4.3-stable_win64.exe          # run the game
./Godot_v4.3-stable_win64.exe -e       # open in the editor
```

The main menu links the full game loop:

1. **🔧 Design Lab** — build blueprints on a 3D canvas. Drag parts from the left bin onto a hull, drag gizmo handles to stretch barrels/calibers (stats update live), pick armor material + thickness, toggle bilateral symmetry (M), rotate modules (R), and save to your Blueprint Library. Start from a **vehicle hull** for units or a **foundation** (Pillbox/Tower) for static defenses.
2. **⚔️ Skirmish** — C&C-style battle. Harvest metal/crystal with harvester units, build Refineries/Factories near your base, produce your saved designs from the bottom build bar, place your custom defense blueprints, and destroy the enemy HQ before its waves overrun yours.
3. **🎯 Test Range** — drive your latest saved design against target dummies (some shoot back).

### Skirmish controls

| Input | Action |
|---|---|
| Left-click / drag | Select unit(s) |
| Right-click | Move / attack target / send harvester to a resource node |
| WASD / arrows / middle-drag | Pan camera |
| Mouse wheel | Zoom |
| Esc | Cancel placement / clear selection |

Bottom bar: buildings first (Factory, Refinery), then your unit blueprints (queued at your Factory), then 🛡 defense blueprints (click, then click ground near your base to place).

### Design notes reflected in the sim

- **Damage classes** (kinetic/thermal/explosive) vs **armor materials** with per-class thresholds — hits below a threshold are fully negated.
- **Subsystem stripping** — 35% of hits land on exposed modules; losing all locomotion immobilizes a unit.
- **Parametric tweaks** carry into combat: barrel length extends range but slows traverse, weight slows turrets, etc.
- **Faction passives** — Industrialists: −20% armor weight; Technocrats: +5% speed; Expansionists: HQ resource trickle.
- A default loadout ships in `prototype/data/loadout/` and the enemy AI's roster in `prototype/data/enemy/`, all in the same JSON blueprint format the Design Lab saves (`user://blueprints/`).

## Tests

Headless test suite (11 suites: stat math, clipping, damage model, firing arcs, stripping, team targeting, economy/production, win condition):

```
cd prototype
./Godot_v4.3-stable_win64_console.exe --headless --script run_tests.gd
```

## Art pipeline

Hulls and weapon/locomotion parts are authored procedurally in Blender (via the bundled `UPBGE-0.30-windows-x86_64/blender.exe`) rather than hand-modeled, so the whole kit can be regenerated or extended from one script:

```
cd prototype
./UPBGE-0.30-windows-x86_64/blender.exe --background --python tools/blender/build_meshes.py
```

This writes `assets/models/hulls/*.glb` (one greebled chassis/foundation per `module_catalog.gd` hull entry — vents, hatches, rivets, antennae, corner gussets, tiered towers, domed bunkers) and `assets/models/parts/*.glb` (barrels, breeches, drums, domes, missiles, wheels, legs, rings — assembled by `visual_builder.gd` per weapon type, tweak-deformable, with a coordinate convention documented at the top of `build_meshes.py`). `visual_builder.gd` falls back to the old procedural primitives for any part not yet authored. After regenerating, run `Godot_v4.3-stable_win64_console.exe --headless --editor --import` once so Godot picks up the new/changed `.glb` files.
