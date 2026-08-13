# Kitbash Command — Project Reference (Mavis)

A condensed field guide for working in this repo. Built from a full read of the
codebase; intended to be the first thing I look at when picking up a task here,
and to spare future-me the "what was the convention again?" loop.

The detailed long-form project doc lives in `CLAUDE.md`. This file is the
**practical** layer underneath it: how the code reads, where things live, what
patterns to follow, what to avoid. Treat the two as a pair.

---

## 1. What this is, in one paragraph

A Godot 4.7.1 prototype RTS where the player **designs** every unit (hull +
modules + locomotion + armor) in a 3D lab, then fields those designs in a
C&C-style Skirmish with an actual economy, harvester loop, base building,
production queues, fog of war, and a utility-based AI commander. Core loop
flows Main Menu → Design Lab → Skirmish (or Test Range) → After Action
Report → back to the Lab. Game version `1.6.3` per `project.godot`.

Project root: `prototype/`. Engine executables bundled in the same dir.
All paths below are relative to `prototype/` unless I say otherwise.

### 1.1 Current focus (as of 2026-08-10)

The interface. Chris is actively rebuilding the UI to feel **responsive,
fluid, and modern**, with the **architecture first and the aesthetics
layered on top**. The codebase already has a strong layered design
system in place (tokens → theme → primitives → screens, with
`ui_anim.gd` for shared motion) — see §6.7 through §6.9. When picking
up a task here, lean toward UI work first unless the user asks for
something specific; non-UI work is also fine, just be aware the UI
layer is the live area.

---

## 2. Coding style & philosophy

This codebase reads like documentation that happens to be executable. The
following is non-negotiable and shows up everywhere — match it when adding code.

### 2.1 Comments are architecture

- Comments explain **why** (decisions, tradeoffs, prior bugs), rarely **what**.
  When a number is non-obvious, the comment next to it says *why that number*.
  Example: `damage_resolver.gd:50-64` explains the *whole* history of why
  `CHIP_THROUGH_FACTOR = 0.15` exists, what bug it fixes, and what would
  regress if you changed it.
- Files open with a multi-line header comment describing what they own,
  what they replace, and how to think about them. See `blueprint_manager.gd`,
  `scene_router.gd`, `drivetrain.gd`, `audio_manager.gd`, `commander.gd`. **All
  four are template-level examples** of how to introduce a non-trivial file.
- When you split or refactor something, leave a short "what changed and why"
  note in the new file's header (see `suite_base.gd:1-21` for the textbook
  example).
- "WHAT THIS REPLACES, AND WHY" is a recurring section header — the team
  treats every rewrite as something that should explain its predecessor's
  failure mode, not just its own design.

### 2.2 Naming and formatting

- Files: `snake_case.gd`. Classes: `PascalCase`. Functions/vars: `snake_case`.
  Constants: `SCREAMING_SNAKE_CASE`. Signals: past-tense or event-named
  (`died`, `resources_delivered`, `settings_changed`, `load_progress`).
- Type-hint everything that crosses a meaningful boundary. Methods on the
  shared systems (Drivetrain, DamageResolver, ModuleCatalog) all have full
  type signatures; treat that as a sign they're meant to be reused as a
  contract.
- Prefer `static func` for shared math/lookup functions. The codebase has a
  clear pattern: `class_name X extends RefCounted` with only `static func`s
  is the shape of "shared system, no state" (Drivetrain, DamageResolver,
  GlobalConfig, FactionCatalog). Avoid making these `extends Node` or putting
  instance state on them.
- Use `preload(...)` for cross-script class references at the top of files
  (sometimes in `const`, sometimes local inside functions). Never `load` for
  things you need at parse time.

### 2.3 Single source of truth, no duplication

The codebase has been hammered on this. Specifically:

- **HP, weight, cost, drivetrain, damage resolution, speed, vision, range,
  energy** all have ONE function that computes them. Any time you see two
  versions of the same math, one of them is wrong — search for them and
  unify. See `drivetrain.gd`'s header for the canonical example of "this
  math used to live in two places; here's why that broke."
- Catalog-style data (modules, hulls, factions, armor materials, buildings,
  weapon fire profiles, maps) lives in dedicated `*_catalog.gd` files. The
  pattern is `class_name X extends RefCounted` with a `static var DATA` (or
  a method that returns it) and small `get_*` lookup helpers. **Don't scatter
  lookup logic — call the catalog.**
- Auto-derived stats go through functions like
  `ModuleCatalog.compute_hull_max_hp()` / `compute_hull_weight()` /
  `compute_hull_cost()`. These three are the canonical "what the sidebar
  shows must match what the sim uses" gate (see `module_catalog.gd:6-38`).

### 2.4 Constants, not magic numbers

Every balance number, threshold, multiplier, and tunable is a named `const`
with a comment explaining what it controls and why it's that value. When you
add a tunable, name it. The name + the comment **is** the balance design.

Hot examples:
- `damage_resolver.gd`: `CHIP_THROUGH_FACTOR`, `BRUTE_FORCE_RATIO`,
  `BRUTE_FORCE_MAX_BLEND`, `MODULE_STRIP_DAMAGE_FACTOR`,
  `ELEVATION_COMBAT_THRESHOLD`, `ELEVATION_COMBAT_PIERCE_MULTIPLIER`.
- `drivetrain.gd`: `BASE_THRUST`, `TW_GAIN`, `SPEED_FLOOR`,
  `OVERLOAD_EXPONENT`, plus per-locomotion-type constants. The header
  explains the 1.8 exponent choice in full.
- `module_catalog.gd`: `HULL_SCALE_MIN`, `HULL_SCALE_MAX`.
- `global_config.gd`: `weight_scale_factor`, `hp_scale_factor`,
  `dps_scale_factor`, `cost_scale_factor`, plus
  `enable_animated_monolithic_parts` feature flag.

### 2.5 Numerical determinism

- Rounding to nearest 0.5 happens at **compute time** via
  `GlobalConfig.round_to_half()` so display and combat math cannot drift
  (`global_config.gd:23-31`). Add any chained tweak-multiplier math through
  that helper, not raw floats.
- Audio: every generator is seeded; re-runs are byte-identical. Don't
  introduce unseeded randomness into `tools/audio/`.

### 2.6 No silent fallbacks

- A function that gets a config dict either tolerates missing fields via
  `.get(key, default)` (with the default documented) or it fails loudly.
  Example: `damage_resolver.get_material_threshold()` falls back to
  `hardened_steel` for an unknown material but logs nothing — the *fallback
  table* is the doc. Conversely, an unknown `damage_type` falls back to
  `explosive`, which was an actual bug (energy weapons resolved as explosive
  before the energy row was added; the comment at `damage_resolver.gd:26-36`
  is the postmortem).
- `ModuleCatalog.module_exists()` exists specifically so reconstructors
  can SKIP an unknown `type_id` instead of silently substituting
  `basic_cannon` (FABLE_REVIEW 3.4). Use it, don't use `get_module_data`
  for existence checks.
- `SettingsService.get()` errors on a missing key rather than inventing
  a value. The same principle: typos surface immediately.

### 2.7 Mutation via events, not polling

`SettingsService` exposes `signal settings_changed(key, value)` and tells
callers to subscribe, not to poll. `AudioManager` similar.
**Follow this.** Don't `get_settings().something` every frame.

---

## 3. Architecture at a glance

### 3.1 Top-level shape

```
MainMenu ──► MainLab (Design Lab)      ──► BlueprintLibrary
         ──► Skirmish / Battle / Test Range (lands on Battle.tscn via TestRangeLauncher)
         ──► MatchSetup / OperationsSetup / OperationsDraft
         ──► Loading (transitional)
         ──► AfterActionReport
```

`SceneRouter` (autoload) owns the transition overlay; every scene change
goes through it. **The overlay must live on the autoload, not on a scene** —
see `scene_router.gd:46-50` for why. Loading screen is pre-warmed and
walks preload targets one per frame to keep the window responsive, since
script compilation is the bottleneck (not disk I/O).

### 3.2 Autoloads (defined in `project.godot:23-35`)

| Autoload | File | Role |
|---|---|---|
| `WindowFit` | `scripts/window_fit.gd` | Window size/fit on boot |
| `SceneRouter` | `scripts/scene_router.gd` | Cross-scene transitions + fade overlay + prewarm |
| `TutorialManager` | `scripts/tutorial/tutorial_manager.gd` | First-run tutorial gating |
| `MatchConfig` | `scripts/match_config.gd` | Relay: Skirmish/Operations read player settings from here |
| `OperationsManager` | `scripts/operations_manager.gd` | Operations (iterative campaign) state |
| `DebugSettings` | `scripts/debug_settings.gd` | Dev cheat toggles |
| `CursorManager` | `scripts/cursor_manager.gd` | Crosshair/cursor state |
| `AudioManager` | `scripts/audio_manager.gd` | All sound (SFX, music, voice, ambience) |
| `SettingsService` | `scripts/core/settings_service.gd` | Persistent player settings + bus layout |
| `InputService` | `scripts/core/input_service.gd` | Keybinding table (separate from settings on purpose) |
| `SystemLayer` | `scripts/ui/system_layer.gd` | System-modal UI overlay (e.g. blocking dialogs) |

Autoload pattern is universal: `extends Node`, file-level `const` preloads,
`signal`s for events, `static const` for paths/names. New autoload? Use
this shape.

### 3.3 The blueprints & data flow

```
Design Lab (3D scene)
  └─ module_placer.gd (root script on MainLab.tscn)
       ├─► stat_calculator.gd  (UI_StatBlock.tscn, the right rail)
       └─► parts_menu.gd       (UI_PartsMenu.tscn, the parts bin)
              │
              ▼
   blueprint_manager.gd  ←→  user://blueprints/<id>.json   (saved roster)
                          ←→  user://lab_scratch.json      (in-progress design,
                                                            also the Test Range
                                                            read target via
                                                            TestRangeLauncher)
                          ←→  data/loadout/*.json          (shipped defaults)
                          ←→  data/enemy/*.json            (AI rosters)
```

Note: `user://blueprint.json` (legacy single-slot pointer) and the
`LEGACY_SLOT_PATH` it was reachable through were retired 2026-08-10
with the rest of the pre-unification battle path. The Test Range now
reads `user://lab_scratch.json` (the Design Lab's own scratch slot)
via `TestRangeLauncher`, which falls back to the most-recent-saved
named blueprint and then to the bundled Bulwark MBT.

- **Scratch vs. saved is enforced at the file level.** "Test in Arena"
  writes the scratch file only; a real Save creates the roster entry. See
  `blueprint_manager.gd:44-65` for the rule and the historical bug.
- `BlueprintManager.is_named()` is the gate that decides whether a design
  counts as "user-saved enough to put in the roster." A design with the
  placeholder name `Untitled Design` does NOT pass, by design.
- Blueprint JSON schema version is bumped only when a schema change could
  silently mis-load older saves. Current is **2.0** (bumped when the hull
  roster was rebuilt on SDF/Marching-Cubes).

### 3.4 The runtime battle path

```
MatchSetup.gd  ──►  MatchConfig (autoload)  ──►  Skirmish (battle controller)
                                                   │
       ┌───────────────────────────────────────────┤
       │                                           │
       ▼                                           ▼
   VisionService                          EconomyService
   (per-team visibility scan)             (resources, trickle, building costs)
       │                                           │
       │   ┌─────── per unit ───────┐               │
       ▼   ▼                       ▼               ▼
   battle/units/unit.gd     battle/buildings/    AI: battle/ai/commander.gd
   (constructed by              structure.gd     (utility-based: scored actions
    unit_assembly.gd)            + placement    every tick; reads same
                                 service         VisionService & EconomyService
                                                as the player — no privileged
                                                knowledge)
       │
       ▼
   battle/orders/order.gd (data) + battle/orders/order_service.gd
       │  Intent is data: IDLE / MOVE / ATTACK_MOVE / ATTACK / ATTACK_GROUND /
       │  HARVEST / HOLD. Old code had 5 parallel fields, now a single value
       │  type with a queue. Shift-queue = append.
       ▼
   battle/movement/steering.gd + flow_field/ + formation_service
   (per-tick, reads VisionService for engagement ranges,
    Drivetrain for speed, real nav for pathing when a match exists;
    direct-line fallback for synthetic tests)
```

**The rebuilt battle layer (`scripts/battle/`) is a fresh architecture** —
keep it on its own services pattern. The legacy `battle_unit.gd` and
`player_vehicle.gd` still ship for Test Range and AI compat, but new combat
work should go in `battle/units/unit.gd` + `damage_model.gd` +
`unit_assembly.gd` + `boost_controller.gd`.

### 3.5 Test Range path

`Battlefield.tscn` is its own world. Spawns the player's most-recently-saved
design against target dummies. Reads `user://blueprint.json` (legacy
single-slot pointer) — if you change blueprint storage, update
`blueprint_manager.gd`'s `LEGACY_SLOT_PATH` path here.

---

## 4. Data layout

### 4.1 Catalog files (the "static" data layer)

| File | Owns | Key shape |
|---|---|---|
| `module_catalog.gd` | Hulls, weapons, locomotion, armor materials, weapon fire profiles | `Dictionary` keyed by `type_id` |
| `hull_loader.gd` | Hulls specifically, lazily scanned from `assets/models/hulls/*.glb`+`*.json` and `user://mods/hulls/*` | Cached `Dictionary` |
| `faction_catalog.gd` | 10 factions: visual identity (13 shader params) + mechanical passives | `FACTIONS` dict; `get_passive()` for typed lookups |
| `map_catalog.gd` | Maps: terrain, resources, spawns, surface zones, hills | `Dictionary` per map; JSON-backed in `data/maps/` |
| `battle/economy/building_catalog.gd` | Static buildings: Refinery, Factory, Manufactory, defenses | Catalog + cost / prerequisite rules |
| `battle/economy/resource_catalog.gd` | Resource types (metal, crystal, lumber, oil) | Catalog + per-type rules |
| `dc_tables.gd`, `mc_tables.gd` | Damage / material coefficients tables | (specialized balance tables) |

**Add a new module type:** add the entry in `module_catalog.gd` (or
`hull_loader.gd` for a new hull), give it a Blender-authored `.glb` in
`assets/models/parts/` (or `hulls/`), re-run the build script under
`tools/blender/`, and reimport in Godot. **The `audio_manifest.json` is the
same kind of contract** for sound: add the entry in `tools/audio/sfx.py`'s
`manifest()` and re-run `generate_audio.py` — no GDScript change needed.

### 4.2 Authored data files

- `data/loadout/*.json` — default player blueprints (Bulwark MBT, Rattler
  Scout, Ore Trucker, Warden AA, etc.). These are the designs that ship
  with the game.
- `data/enemy/*.json` — enemy roster designs used by the AI.
- `data/hull_assemblies/*.json` — one per hull type. Each defines a CSG
  bake (smoothness, resolution, facet_angle, fit_percent, chamfer, mirror)
  and a list of **primitives** (BOX / SLOPE / RING) that compose the hull
  mesh. Sidecar fields (hp, weight, metal/crystal cost, base_energy, size,
  color) are read by `ModuleCatalog.compute_hull_*()`. The `_note` field
  on each primitive is documentation for the hull author — keep them.
- `data/maps/*.json` — map definitions (terrain PNG, surface PNG, hills,
  resource nodes, spawns, surface zones, obstacles, water areas). Migrated
  out of hardcoded constants (see `CLAUDE.md` and `map_catalog.gd`).
- `data/test_fixtures/terrain/` — fixed test terrain (PNG + JSON) used by
  navmesh/terrain suites. Reusing them is faster than authoring new ones.
- `Tracks/` (repo root) — externally-generated curated music. **Provenance
  unconfirmed — see CREDITS.md.** `tools/audio/curated_music.py` maps
  game states to these files. Skirmish rotates through a pool of 8 (never
  repeats back to back). Procedural alternative: `--procedural-music` flag.

### 4.3 Per-user storage (`user://`)

- `user://blueprints/<id>.json` — saved player designs (roster)
- `user://lab_scratch.json` — in-progress Design Lab design AND Test Range read target (via TestRangeLauncher)
- `user://settings.cfg` — `SettingsService` config
- `user://ui_layout.cfg` — UI dock collapsed state (own file, by design)
- `user://tutorial_seen.cfg` — single bool, tutorial gating
- `user://mods/hulls/` — player hull mods (scanned by `hull_loader.gd`)

---

## 5. Key files cheat sheet (for "where do I change X?")

| If you want to change... | Look here first |
|---|---|
| A weapon's damage / fire profile / range | `module_catalog.gd` (the `WEAPON_FIRE_PROFILES` block) |
| Armor material stats | `damage_resolver.gd` `ARMOR_TABLE` |
| Drivetrain / speed formula | `drivetrain.gd` (single source of truth) |
| Hull HP/weight/cost from volume scale | `global_config.gd` scale factors + `module_catalog.gd` `compute_hull_*` |
| A new armor material | `damage_resolver.gd` (table + helper) + `module_catalog.gd` (sidecar) |
| A new locomotion type | `module_placer.gd` `update_locomotion()` (the 540-line elif chain) — see the golden fixture warning below |
| A new building | `battle/economy/building_catalog.gd` + its GLB in `assets/models/buildings/` |
| A new map | `data/maps/<id>.json`; hot-reload via `map_catalog.gd` |
| A new faction | `faction_catalog.gd` `FACTIONS` (visual + passives) |
| Balance scalars (HP, weight, DPS, cost) | `global_config.gd` first; otherwise named constants on the system |
| Tutorial step | `scripts/tutorial/tutorial_steps.gd` + `tutorial_manager.gd` |
| Settings storage | `scripts/core/settings_service.gd` — add to the `DEFAULTS` dict |
| Key binding | `scripts/core/input_service.gd` (separate from settings on purpose) |
| Audio manifest | `tools/audio/sfx.py` `manifest()` — re-run `generate_audio.py` |
| Any UI spacing / colour | `scripts/ui_tokens.gd` (single source of truth) |

---

## 6. Important patterns to copy

### 6.1 Adding a `static` shared system

`class_name X extends RefCounted`, `const Y = preload(...)` at top, all
public methods `static func`, no state. Example: `drivetrain.gd`,
`damage_resolver.gd`, `faction_catalog.gd`, `module_catalog.gd`,
`global_config.gd`. New shared system? Match this shape.

### 6.2 Adding a "data" type

`class_name X extends RefCounted`, `enum Type { ... }`, plain `var`s
matching the enum. Immutable-ish (no setters), used as a value. Example:
`battle/orders/order.gd`.

### 6.3 Adding a "service" (battle layer)

Lives in `scripts/battle/<area>/`, `extends Node`, owns autoload-style
state, exposes `signal`s, depends on other services through preloads not
through `get_node`. Examples: `battle/economy/economy_service.gd`,
`battle/orders/order_service.gd`, `battle/vision/vision_service.gd`. **The
AI (`commander.gd`) reads the same services the player's HUD reads — that
constraint is enforced by construction**, not by code review.

### 6.4 Adding a screen

- Build the 3D world in `scenes/X.tscn` and reference it from `MainMenu.gd`
  (or from another screen, as `match_setup.gd` does to `MatchSetup.tscn`).
- Build the UI as separate `UI_*.tscn` sub-scenes with their own scripts
  (the `MainLab.tscn` ↔ `UI_StatBlock.tscn` / `UI_PartsMenu.tscn` split is
  the template).
- Use `UIShell.backdrop()` and `UIShell.stat_row()` for the
  out-of-match chrome. Don't roll your own margin frame — three screens
  already had off-grid margins before they were centralized
  (`ui_shell.gd:32-48`).
- All UI sizing comes from `scripts/ui_tokens.gd`. **No hardcoded
  colours, spacings, or type sizes in screen code** unless wrapped through
  the theme.

### 6.5 Adding a new test

1. Pick or create the right `tests/test_<area>.gd` (or a new one for a
   new area). The split is documented at `CLAUDE.md` (Test File Layout).
2. Function name = `test_<thing>`. Returns `bool` (true = pass).
3. Always `extends "res://tests/suite_base.gd"`. Use `tree`, `root`,
   `current_scene` — never call `get_tree()` from a test.
4. `await tree.process_frame` between setup and assertions when the
   subject uses `_ready()`.
5. If you add a brand-new test file, also add an entry to `SUITE_FILES`
   and to `SUITE_ORDER` in `run_tests.gd`. **Do not reorder** SUITE_ORDER
   — navmesh/Recast suites depend on prior state.
6. Run via the wrapper (`./run_tests.ps1` or `./run_tests.sh`); the
   wrapper reimports first. Direct `--script run_tests.gd` will trip on
   stale `class_name` UIDs.

### 6.6 Golden fixtures

`tests/suite_base.gd` holds frozen outputs (e.g. the locomotion layout
fixture, derived from `module_placer.gd:update_locomotion()`). **If you
intentionally change a fixture's underlying math, update the fixture in
its own commit with a comment explaining the delta** — never as a side
effect of a refactor. This rule has been in place since the locomotion
rebuild (LOCOMOTION_EXPANSION_PLAN §2.3).

### 6.7 The UI architecture (the layered stack)

The interface is treated as a stack with five layers. **The architecture
is the product.** Aesthetics sit on top of the architecture, never inside
it — the rule is "signal colour is for state, not decoration"
(`UI_STYLE_GUIDE.md §1.1`).

```
┌──────────────────────────────────────────────────────────┐
│  SCREENS      per-screen .tscn + .gd (match_setup,       │
│               main_menu, blueprint_library, …)           │
├──────────────────────────────────────────────────────────┤
│  PRIMITIVES   ui_shell, ui_dock, ui_flyout,              │
│               ui_radial_menu, ui_anim, ui_feedback       │
│               — reusable layout/animation/feedback       │
├──────────────────────────────────────────────────────────┤
│  THEME        ui_theme.gd (runtime material shader),     │
│               build_ui_theme.gd (static StyleBoxes),     │
│               bomber_theme.tres                          │
├──────────────────────────────────────────────────────────┤
│  TOKENS       ui_tokens.gd — palette, type, spacing,     │
│               radii, motion durations/easings. ONE dict. │
├──────────────────────────────────────────────────────────┤
│  AUDIT        ui_audit.gd — overflow / offscreen /       │
│               theme-validity checks; opt-out via meta    │
└──────────────────────────────────────────────────────────┘
```

When you change a screen, the discipline is:

1. **Use tokens, not literals.** Every colour, spacing, type size, and
   motion duration comes from `ui_tokens.gd`. A literal in a screen
   script is a regression.
2. **Use primitives, not raw Control nodes.** A collapsing panel is a
   `UIDock`, not a `PanelContainer` you wrote yourself. A popover is a
   `UIFlyout`, not a `Popup`. The primitives encode the gotchas
   (clipping, auto-flip, dismiss, anchor — see §7).
3. **Pick a material, not a colour.** `ui_theme.MATERIALS` is six
   surfaces (powdercoat / steel / moulded / canvas / carbon /
   fiberglass), each with its own shader defaults. The colour *follows*
   the material. If you're reaching for `Color.RED` to "draw attention"
   to something, you almost certainly want `SIGNAL_HAZARD` and a
   `moulded` or `fiberglass` plate — and a real reason (state, not
   decoration).
4. **Route SFX through `ui_feedback.gd`'s role table.** Audio manifests
   are the contract; the role table is what keeps a click sound
   consistently the click sound.
5. **Run `ui_audit` after layout changes.** It catches the
   container-propagates-minimum-size bug (§7) and other silent
   overflows.

### 6.8 The six "fluid UI" gotchas baked into the primitives

The dock, flyout, and anim library exist *because* of these. Knowing
them is the difference between fighting the engine and using it:

1. **A `Container` propagates its children's combined minimum size to
   the parent REGARDLESS of `clip_contents`.** A "collapsed" panel
   written as a `Container` with `clip_contents=true` is a panel that
   *isn't* collapsed — it still demands its full expanded width. The
   fix: collapse by driving `custom_minimum_size` on a plain `Control`
   clip wrapper, which is what `ui_dock.gd` does. The wrapper carries
   `ui_audit_clip_ok` meta so the audit knows the zero-size-window-
   around-full-content shape is deliberate.
2. **A `ScrollContainer` reports a `combined_minimum_size` of zero on
   the axis it scrolls.** A child that asks for the scroll container's
   size therefore gets zero on that axis. The dock body used to anchor
   `LEFT_WIDE` (or `TOP_WIDE` for a bottom dock) and silently rendered
   empty against a scroll container child. The fix is `PRESET_FULL_RECT`
   so the body just fills the clip wrapper.
3. **`theme_type_variation` is the way to skin a node without
   re-authoring StyleBoxes.** A `Button.new()` with
   `theme_type_variation = "TabButton"` picks up the theme's tab
   styling. Use this rather than building StyleBoxes in code.
4. **Godot 4.3 will not accept a script-local `enum` as the type of an
   `@export` property on a `class_name`'d script** — it resolves the
   type to two different names and refuses assignment. Type the storage
   as `int`, keep the enum for readability. `ui_dock.gd:74-78`.
5. **Auto-hide docks belong in the editor, not the match.** The
   `UIDock.auto_reveal` flag is opt-in and off by default. A dock that
   vanishes mid-fight costs the player the fight.
6. **Tween durations / easings live in tokens, not in call sites.**
   `ui_anim.gd` re-exports them under their old names, but the values
   themselves are on `UITokens` — change the duration once, every
   `slide_in()` picks it up. A hover transition that outlasts the
   theme's hover plate swap reads as two separate effects; this is
   the structural fix.

### 6.9 UI file ownership at a glance

| File | Owns | When to edit |
|---|---|---|
| `ui_tokens.gd` | All visual constants | Whenever the design language changes |
| `ui_theme.gd` | Runtime material shader, per-material defaults | New material vocabulary |
| `bomber_theme.tres` | Static StyleBoxes (the `resources/` one) | New control types or restyles |
| `tools/build_ui_theme.gd` | **Generates** the .tres | Same — re-run after token changes |
| `ui_shell.gd` | Screen scaffold (backdrop, margin, stat_row) | New shared out-of-match primitive |
| `ui_dock.gd` | Edge-anchored, collapsible panel (used by stat_calculator's right rail) | When the dock metaphor itself changes |
| `ui_flyout.gd` | Transient popover (used by the parts menu's search box and elsewhere) | When a new popover pattern emerges |
| `ui_anim.gd` | Motion library (slide, ring, press, counter roll-up) | New motion primitive |
| `ui_feedback.gd` | UI role → SFX binding | New UI sound or role |
| `ui_audit.gd` | Layout / theme / cursor audit | When a new class of layout bug emerges |
| `ui_radial_menu.gd` | The radial context ring | (rarely — it's a closed widget) |
| `ui_icons.gd` | Icon set | New icon |
| `ui_stamp.gd`, `tweak_callout.gd`, etc. | Screen-specific affordances | When the screen needs them |
| `ui_toolbox.gd` | The accordion tier-stack primitive (one shared widget; the four parts-menu toolboxes are NOT instances of this — they hand-roll the plate+header chrome) | New tier-stack behaviour |
| `ui_toolbox_plate.gd` | The chamfered metal plate drawn behind a toolbox's controls. **Shared chrome** (moved from `battle/hud/` 2026-08-10): used by both `production_hud.gd` (Skirmish) and `parts_menu.gd` (Design Lab) | Plate visual language changes |
| `ui_stamped_label.gd` | Lettering stamped into a metal plate and flooded with enamel. **Shared chrome** (moved from `battle/hud/` 2026-08-10) | Stamped-lettering tweaks |
| `parts_menu.gd` | The Design Lab's bottom toolboxes (4 families × sub-family drawers) + magnifying-glass search. Anchored full-rect with `mouse_filter=IGNORE`; the bar's children own their own clicks. | Parts catalog presentation changes |
| `part_button.gd` | The per-part card widget (drag source, custom tooltip card, weight label, accent stripe) | Per-part card changes |

### 6.10 Cross-toolbox accordion pattern

The four parts-menu toolboxes need "only one open at a time" behaviour, but
`UIToolbox` only knows how to accordion within its own set of tiers. The
**cross-toolbox coordinator** is the parent (`parts_menu.gd`'s
`_open_family_cross`): it walks the four family widgets, sets each one's
`is_open` flag, and uses `set_pressed_no_signal` to avoid the toggled-signal
loop that the standard accordion fights. Each family widget then re-lays
itself based on the flag, with a stagger animation when it opens.

The pattern, in three lines, is what every "N parallel widgets, only one
active" UI ends up needing:

```gdscript
for other_id in _family_widgets.keys():
    var w = _family_widgets[other_id]
    w["is_open"] = (other_id == tier_id)  # true for target, false for rest
    w["panel"].visible = w["is_open"]
    w["header"].set_pressed_no_signal(w["is_open"])  # NO SIGNAL or it loops
```

The `set_pressed_no_signal` is the load-bearing line. Without it, closing a
sibling re-enters this function through the sibling's own `toggled` handler
and the loop fights itself (the exact trap `UIToolbox.open()` at
`ui_toolbox.gd:99-101` records).

### 6.11 The parts-menu "search as flyout" pattern

The magnifying-glass + `UIFlyout` pattern for secondary controls:

1. A `Button` with `toggle_mode = true` and `_engrave()`-stripped styling
   (no text on the button — the lettering is a `StampedLabel` child, same
   as the family headers).
2. A `UIFlyoutScript.create(self, "Title")` for the popover.
3. The actual control (`LineEdit`, in this case) goes into
   `_flyout.body().add_child(...)`.
4. `toggled` on the button opens/closes the flyout: `open_from(btn, ABOVE)`
   so it doesn't fall off the bottom of the screen, and `close()` on
   toggle-off.
5. `flyout.closed` signal mirrors back to the button
   (`set_pressed_no_signal(false)`) so the toggle state stays in step with
   the actual flyout visibility.

The search "toolbox" in `parts_menu.gd` is the canonical example. It is
a **5th element in the bottom row**, treated as a peer of the four
family toolboxes: same `ToolboxPlate` chrome, same `StampedLabel`
lettering ("FIND"), same `HEADER_HEIGHT` hit target, same `BAR_GAP` from
its left neighbour. The only difference is the body — the search opens
a `UIFlyout` containing a `LineEdit`, rather than an inline sub-family
list. A `SEARCH_WIDTH` constant (72px) gives the StampedLabel room to
breathe at `HEADER_FONT_SIZE` (19) without making the right end of the
bar feel lopsided; "FIND" (4 letters) fits comfortably, "SEARCH" (6)
would crowd the chamfered corners.

This is the canonical way to handle "secondary control that doesn't need
to be visible all the time" in this codebase. The next time you find
yourself wanting to put a control "behind a button" in the design lab
or any other out-of-match screen, this is the pattern.

### 6.12 The right-panel "lazy label with move_child" pattern

The right `UI_StatBlock` rail (`stat_calculator.gd`) is a `VBoxContainer`
holding a mix of scene-declared widgets and labels created lazily by
`update_stats()` (drivetrain speed/load, power gen/storage/draw/net,
range/vision, boost, armor thresholds, tech requirements). The lazy
labels are created by `_build_*_readout()` functions called from
`update_stats()`'s first run.

**THE TRAP.** A lazy `Label.new()` followed by `_rail_vbox.add_child(l)`
adds the label to the END of the VBox. If the rail's VBox already has
the action buttons (Save, Test, Delete) below the stats, the lazy
labels land BELOW the action buttons — which is the opposite of where
the player expects to read them. The same trap exists for panels
(`PanelContainer`) and any other Control added lazily.

**THE PATTERN.** Every `_build_*_readout()` that adds to `_rail_vbox`
must end with a `move_child` chain that places the new label directly
AFTER the row it explains. The standard form is:

```gdscript
if dps_label and dps_label.get_parent() == _rail_vbox:
    var at := dps_label.get_index()
    _rail_vbox.move_child(new_label_1, at + 1)
    _rail_vbox.move_child(new_label_2, at + 2)
    # ... one move_child per new label, in display order
```

The `get_parent() == _rail_vbox` guard prevents a layout fire when the
label is detached (e.g. during a scene transition). The `get_index()`
captures the anchor's position BEFORE the first `move_child` (a
`move_child` reshuffles indices, so reading `get_index()` after the
first one would land at a different position than intended).

**THE FAILURE MODE.** `armor_threshold_label` was being created in
`update_stats()` but never `add_child`'d to `_rail_vbox` — it existed
as a Label object with the right text, but had no parent and so was
never rendered. `test_sim_and_stats.gd` reads its text and the test
passes, but no player ever sees it on screen. The fix is both the
`add_child` AND a `move_child` — without either, the label is either
invisible (no parent) or in the wrong place (end of VBox).

### 6.13 The warning panel pattern (stat_calculator.gd)

The right rail has three warning panels — OVERWEIGHT, POWER DEFICIT,
SPOTTER REQUIRED — all sharing the same shape. Built by one helper
(`_build_warning_panel(role)` in `stat_calculator.gd`) so the three
call sites cannot drift on the visual language.

The shape:

```
+-----------------------------------+
|  !  TITLE                         |   <- HeadingLabel in edge colour,
|  ----------------------------     |      with a leading "!" as the
|  detail text wraps here.         |      thematic icon. HSeparator
|                                   |      rule between title and
|                                   |      detail. Detail uses
+-----------------------------------+      TEXT_PRIMARY for contrast.
```

**The "!" prefix is the icon.** A leading ASCII "!" renders in the
same Source Sans Pro Bold face the rest of the title uses, so the
title reads as one typographic line — not as "icon + text" glued
together. The "!" is plain ASCII, not a glyph or emoji (the project
bans those in UI text per `UI_STYLE_GUIDE.md` §0).

**The HSeparator is the visual divider.** Without it, the title
(HeadingLabel) and the detail (HintLabel) had only 4px of VBox
separation and blurred into one block — the detail "overlaid" the
title in the user's words. The separator is the same one
`UIFlyout.set_title()` uses (`ui_flyout.gd:88-90`), so the rail
and the popover agree on what a "titled section" looks like.

**TEXT_PRIMARY, not TEXT_SECONDARY, for the detail.** The default
HintLabel colour is TEXT_SECONDARY (warm off-white). Against the
dim-amber fill of a hazard panel, the secondary text reads as muddy
and the warning fails its job. TEXT_PRIMARY is the brighter off-white
and has the contrast the warning actually needs to be readable.

**Three panels, one builder.** The `_build_warning_panel(role)`
helper returns `[PanelContainer, Label(title), Label(detail)]` and
the three call sites (`_build_drivetrain_readout`,
`_build_power_readout`, `_build_range_readout`) store those in
their own `_panel`/`_title`/`_detail` fields. Updating the panel
shape (adding an icon, changing the separator, adjusting the
colour) lands in one place rather than three.

**THE TRAP — `add_child` exactly once.** The helper returns a
panel but does not add it to a parent; the caller is responsible
for `_rail_vbox.add_child(_spotter_panel)`. A duplicated
`add_child` on the same panel fires `ERROR: ... already has a
parent` and only the FIRST add lands — the second is silently
no-op'd by Godot — so the warning shows up correctly but the
error spam in the log obscures the next real warning. Was found
in `_build_range_readout` (the spotter call site) where two
back-to-back `_rail_vbox.add_child(_spotter_panel)` lines had
been copy-pasted during a refactor; the duplicate showed as a
"Can't add child ... already has a parent" error on every
MainLab _ready. Single `add_child` is the fix.

### 6.14 The verdict panel (DesignVerdict → PhosphorPanel)

The verdict panel at the top of the right rail is a different animal
from the three warning panels in §6.13 — it's a `PhosphorPanel` (CRT
readout, shader-driven, white pixels get tinted with the tube colour)
rather than a regular `PanelContainer` with a StyleBox. The same
overlap problem it had was a different cause, and the fix uses a
different mechanism:

**The overlap (first attempt).** `PhosphorPanel.add_readout(text)`
wraps each Label in its own `MarginContainer` and adds it as a child
of the panel. The panel extends `PanelContainer`, which is supposed
to stack its children vertically. In practice it did not — every
readout landed at y=0, and the detail text drew ON TOP of the
headline (visible in the "UNARMED / No weapon fitted" overlap, where
the headline's amber pixels and the detail's white pixels occupied
the same row and the shader composited them into one unreadable
line). Adding an `HSeparator` between the readouts did not help,
because the PanelContainer was not laying out the children at all.

**The fix (second attempt).** Drop `add_readout()` entirely and
build the layout as a single `VBoxContainer` inside the panel. The
VBox is a known-good Container that reliably stacks its children
with explicit separation, and it gives full control over the
headline / separator / detail structure:

```gdscript
var stack := VBoxContainer.new()
stack.add_theme_constant_override("separation", Tokens.SPACE_XS)
_verdict_panel.add_child(stack)

_verdict_headline = Label.new()
_verdict_headline.theme_type_variation = "HeadingLabel"
_verdict_headline.add_theme_color_override("font_color", Color.WHITE)
stack.add_child(_verdict_headline)

var rule := HSeparator.new()
rule.add_theme_constant_override("separation", Tokens.SPACE_XS)
stack.add_child(rule)

_verdict_detail = Label.new()
_verdict_detail.theme_type_variation = "StatLabel"
_verdict_detail.add_theme_color_override("font_color", Color.WHITE)
_verdict_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
stack.add_child(_verdict_detail)
```

**Why the HSeparator works here.** Under the phosphor shader, any
white pixel gets tinted with the tube colour. The separator's
white pixels are no exception — they get tinted amber, so the rule
reads as part of the display's own glow rather than as a foreign
`StyleBoxFlat` smuggled in. Same goes for both Labels: their WHITE
font colour is what the shader needs to apply the tube colour, so
the headline and detail both come out in the same amber tint rather
than reading as two different surfaces.

**Why not the HSeparator in the PanelContainer.** It was the
"obvious" first attempt and it didn't work because the
PanelContainer was not laying out its children. The lesson: a
HSeparator between children of a Container fixes visual separation
only if the Container is actually stacking the children. If the
Container is broken (whatever the cause — minimum size, layout
flag, shader interference), the children are still at y=0 and the
separator sits on top of them. The VBox workaround is the reliable
fix because VBox is the simplest Container we have and it
religiously stacks.

**The "!" icon.** The verdict headline is the unprefixed label
("UNARMED", "OVER CAPACITY", "POWER DEFICIT" — `test_design_verdict.gd`
asserts on these exact strings). The "!" prefix is added in the
**consumer** (`_update_verdict()` in `stat_calculator.gd`), not in
`DesignVerdict.evaluate()` — because the test contract is the raw
data, not the display rendering, and a presentation concern should
not change a data contract. The two-space gap after the "!" prevents
it from merging with the first letter under the phosphor's tight
letter-spacing.

---

## 7. Gotchas and landmines (read before touching)

1. **Godot version: 4.7.1**, bundled. A 4.3 pair may still be in the dir
   — **do not use it.** Downgrades `config/features` and strips UIDs.
2. **`.uid` sidecars**: 126 of them. Don't delete them, don't regenerate
   by hand; the editor does it. If a `class_name` change is "not
   declared," run the wrapper.
3. **`compile_check_all.gd` is not actually quick** at this size; can run
   20+ minutes. Prefer `run_tests.ps1` for verification.
4. **Autoloads in `project.godot` are ordered**; later autoloads can
   `preload` earlier ones, not the reverse. Adding a new autoload? Put
   it last or near its dependencies.
5. **`compile_check_all.gd` and direct `--script run_tests.gd` need
   `--path` and `--quit`**, which is why the wrappers exist.
6. **Blueprint version bump is rare and deliberate.** Don't bump
   `CURRENT_BLUEPRINT_VERSION` to fix a display bug; only bump when a
   schema change could silently mis-load older saves. The postmortem on
   the 1.0→2.0 bump is at `blueprint_manager.gd:11-18`.
7. **`HullLoader.get_hulls()` is cached and identity-checked.**
   `ModuleCatalog._catalog_cache` invalidates when the hull dict is a
   different instance (used by `reset_cache_for_tests()`). Don't bypass
   that — return a copy, not the same dict.
8. **NavigationServer3D.Recast segfaults past a triangle count.** Use
   `terrain_builder.gd`'s `_nav_grid_cell()` and its `cell_size` formula.
   Changing either without re-running the maps can crash.
9. **Music is curated, not procedural** (see `CLAUDE.md` and CREDITS.md).
   `Tracks/` provenance is **TBD — do not ship without confirming.**
   Use `--procedural-music` to opt into the from-scratch engine.
10. **No emoji / decorative dingbats in UI text** (item 0 of the style
    guide). Box-drawing and arrows are fine. Not currently enforced by a
    test; it's a standing rule.
11. **`audio_manager.gd` is fully manifest-driven.** The
    `audio_manifest.json` is generated, not hand-edited. Add a sound to
    `tools/audio/sfx.py` `manifest()` and re-run the generator — do not
    edit the manifest or the GDScript.
12. **`SceneRouter` overlay must stay on the autoload**, not on any
    scene. Moving it would re-freeze scene transitions.
13. **Sincere / absurd split is enforced by module.** Ordnance
    vocalisations are in `tools/audio/voice.py` (absurd) and play on the
    SFX bus (so the Voice slider doesn't silence combat). Comms, engines,
    interface, ambience are in `sfx.py` (sincere) and play on the Voice
    bus. The rule is in `CORE_DESIGN_LANGUAGE.md §6`.
14. **Subsystem stripping math is now in `damage_resolver.gd`** (was
    duplicated across `battle_unit.gd` and `player_vehicle.gd` and
    silently broken - both of which are now retired, 2026-08-10, so
    the only live callers of this math are `battle/units/unit.gd` and
    `battle/buildings/structure.gd`). If you see a stripping
    calculation anywhere else, it's a bug.
15. **Stat rounding is at compute time** (`GlobalConfig.round_to_half`).
    Don't display-round after compute-rounding; the two should agree.
16. **Test order is pinned in `SUITE_ORDER`** (see `run_tests.gd:51`).
    Reorder and navmesh tests will flake.
17. **`visual_regression/captures/*.png` go stale silently.** The visual
    regression tool is windowed-only (Godot's headless dummy renderer
    cannot produce real frames), so a casual re-run is not on the
    test pipeline. After a UI rewrite, captures from the previous
    layout can keep sitting in `captures/` and **mislead** — they
    look like ground truth but reflect a layout that no longer
    exists in code. When in doubt, trash `captures/*.png` so the
    next windowed run regenerates them as new baselines instead of
    diff'ing against the dead layout.

---

## 8. Documentation map (where to find X)

- `CLAUDE.md` — long-form project doc: architecture, commands, layout.
- `README.md` — entry point, what the game is, how to run it.
- `PROGRESS.md` (279 KB) — dated changelog, newest first, written after
  every major chunk. **The single best on-ramp for "what happened
  recently."** Read the first few sections of any given day for context
  before touching the code it describes.
- `DECISIONS.md` — current state of plans (most archived plans are now
  "completed, needs documentation update").
- `CREDITS.md` — third-party asset attributions. **⚠ Tracks/ provenance
  TBD.**
- `docs/archive/` — completed implementation plans (HULL_BUILDER,
  HULL_MODDING, LOCOMOTION_EXPANSION, PERFORMANCE, SPEED_AND_NAVAL,
  VISUAL_AND_UX_POLISH, OPERATIONS, etc.). They still describe the design
  and are the right place to read intent.
- `docs/FABLE_REVIEW.md` — balance / design review that drove many of
  the dedup passes. Cited inline all over the codebase by its section
  numbers (e.g. `FABLE_REVIEW.md 3.5`, `FABLE_REVIEW.md 1.2`).
- `docs/DECISIONS_NEEDED.md`, `docs/UNIFIED_ROADMAP.md`,
  `docs/RTS_CORE_ROADMAP.md` — roadmap-level.
- `docs/HULL_MASSING_SPEC.md`, `docs/Damage_And_Armor_Model.md`,
  `docs/MOUNTING_AND_ARMOR_SPEC.md`, `docs/ENERGY_AND_BALANCE_SPEC.md`,
  `docs/DESIGN_VISION.md`, `docs/CORE_DESIGN_LANGUAGE.md`,
  `docs/VISUAL_ART_DIRECTION.md` — design-language specs cited in
  comments by filename + section.
- `prototype/docs/UI_STYLE_GUIDE.md` — UI tokens, type, materials, motion.
- `prototype/scratch/` — throwaway probe scripts and design-doc
  scratchpads. Don't ship; don't trust as ground truth; but the
  *logs* (e.g. `sponson_*.log`) are sometimes the only record of a
  specific reproduce.

---

## 9. Conventions I will follow

- Match the comment style on the file I'm editing. If a function has no
  header comment, add one in the same shape as its neighbours.
- Name every constant; comment every magic number.
- When I split a function or file, leave a one-line "what changed" note
  at the top of the new one.
- When I dedupe math between two callers, prefer to put the unified
  function in the **already-existing** shared-system file (e.g. put a new
  drivetrain formula in `drivetrain.gd`, not a new file).
- New tunables go in `GlobalConfig` only if they're global; otherwise
  on the relevant system as a named `const`.
- New tests go in the right `tests/test_<area>.gd`; new file + new
  `SUITE_FILES` entry + a `SUITE_ORDER` placement.
- Re-run the test wrapper (not raw `--script`) before declaring done.
- If I touch a golden fixture, that's its own commit with a comment.
- If I'm not sure where something lives, the `Key files cheat sheet`
  in §5 is the first lookup.

---

## 10. Quick "where do I start?" recipe

1. **Run the game:** `cd prototype && ./Godot_v4.7.1-stable_win64.exe`.
2. **Read CLAUDE.md end-to-end** if you haven't recently.
3. **Skim the latest few sections of PROGRESS.md** to see what's been
   touched.
4. **Pick the right area** via the test-file layout in CLAUDE.md or the
   cheat sheet in §5.
5. **Match the comment style** of the file I'm editing.
6. **Run the tests** via the wrapper before and after my change.
