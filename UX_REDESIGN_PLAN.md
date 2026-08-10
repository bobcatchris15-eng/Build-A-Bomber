# Kitbash Command — Interaction Design Audit & Redesign Plan

_An audit of the interaction design of the whole interface, and a phased plan to redesign it._
_Written 2026-08-09 against the tree at `987f83f`._

**How this document relates to the others.**

| Document | Owns | This document's relationship |
|---|---|---|
| `CORE_DESIGN_LANGUAGE.md` | Whole-game identity, the sincere/absurd split | **Subordinate to it.** Every tonal call here is derived from §1 and §6 |
| `prototype/docs/UI_STYLE_GUIDE.md` | Chrome tokens, type, materials, elevation, motion | **Extends it.** Phase 1 adds three material layers; everything else obeys it as written |
| `prototype/docs/UI_IMPLEMENTATION_PLAN.md` | What is built vs outstanding in the theme system | **Absorbs its Priority 7.** Its four open items are folded into phases below |
| `VISUAL_ART_DIRECTION.md` | 3D materials, factions, terrain | Untouched |
| `Design_Lab_UI_UX.md` | Original Lab concept | Superseded by Phase 4 |

**A warning taken from `UI_IMPLEMENTATION_PLAN.md`'s own preamble:** a plan that describes intentions rather than the tree rots silently. Every claim in Part I below is stated against a file that was read, with a line reference where one exists. Where something is asserted as missing, it is because a search returned nothing, not because it was not noticed.

---

# Part I — Audit

## 1. What is already good, and must not be rebuilt

This is a more mature interface than a prototype usually has, and the failure mode for a redesign at this stage is throwing away a working design system because the screens built on it are wrong. They are separable problems.

| System | Where | Verdict |
|---|---|---|
| Design token set | `prototype/scripts/ui_tokens.gd` | Excellent. Palette, type scale, 4px grid, elevation tiers, motion timings, all with the reasoning recorded inline. Keep entirely |
| Theme builder + generated theme | `tools/build_ui_theme.gd`, `resources/bomber_theme.tres` | 23 registered variations, one rebuild repaints the game. Keep. Extend only through it |
| Material plate pipeline | `tools/generate_ui_plates.py` | Procedural, fixed seed, reproducible. 24 plates + 6 fields. Keep and extend |
| Coupled feedback | `scripts/ui_feedback.gd` | `wire(ctrl, role)` binds audio and motion in one call so they cannot drift. This is the right primitive and most projects never build it |
| Scene routing | `scripts/scene_router.gd` | Fade on an autoload-owned overlay, derived warm-load lists, `world_ready` handshake, DEPLOY gate. Genuinely well-engineered |
| Composable widgets | `ui_dock.gd`, `ui_toolbox.gd`, `ui_radial_menu.gd`, `ui_shell.gd` | Real reusable chrome. The dock persists its own layout to `user://ui_layout.cfg` |
| Tutorial engine | `scripts/tutorial/` | Data-driven step table, condition vocabulary validated by a test, scene-gated. The *engine* is right; the *content* is half a game short |
| Single-source stats | `scripts/design_stats.gd` | `DesignStats.analyze()` makes the same calls `battle_unit.gd` makes. Nothing re-derived. Keep this rule absolutely |
| Per-design after-action stats | `scripts/after_action_report.gd` | Tracks kills, damage dealt/taken by class, credits spent **per blueprint**. Better than most shipped RTS. Under-exploited — see Phase 6 |

**The design system is not the problem. The information architecture is.**

---

## 2. Findings

Severity: **S1** blocks a new player or ships something broken; **S2** materially degrades play; **S3** costs polish or future velocity.

### 2.1 Structural / navigation

**F1 · S1 · There is no InputMap. At all.**
`project.godot` has no `[input]` section. A search for `is_action_pressed` across `scripts/` returns zero hits. All input is raw keycodes spread across eight files: `battle/match_director.gd`, `rts_camera.gd`, `module_placer.gd`, `hull_builder.gd`, `ui_flyout.gd`, `ui_radial_menu.gd`, `battle/movement/flow_field_service.gd`, `debug_tuning_panel.gd`.

This is the single highest-leverage defect in the project. It makes rebinding impossible, makes controller support impossible, makes a keybinding reference screen impossible to keep truthful, and it has already forced a bad gameplay decision — see F2.

**F2 · S1 · The battle uses non-standard command keys, and the code says why.**
`battle/match_director.gd:1932` carries this comment verbatim: *"NOT A AND S, THE CONVENTIONAL BINDINGS. rts_camera.gd polls WASD directly in `_process()` via `Input.is_key_pressed()` rather than consuming input events, so a command bound to A or S fires AND pans the camera."* Attack-move is therefore **Q** and stop is **E**.

Every RTS player alive has A-move and S-stop in their fingers. The workaround is a direct consequence of F1.

**F3 · S1 · The battlefield permanently displays a two-line keyboard cheat sheet.**
`match_director.gd:2206-2211` draws `"DRAG SELECT | RMB MOVE | SHIFT+RMB QUEUE | Q ATTACK-MOVE | E STOP\nZ AGGRESSIVE | X RETURN FIRE | C HOLD | CTRL+1-9 SET GROUP | 1-9 RECALL"` as a fixed label under the top strip. Its own comment: *"because they are not the conventional ones and nothing else in the build documents them yet."*

A permanent on-screen keymap is an interface admitting it failed to teach itself.

**F4 · S1 · No settings screen exists.** No scene, no service, no persisted preference file beyond `user://ui_layout.cfg` (dock state) and `user://tutorial_seen.cfg`. There is no way for a player to change master/SFX/music volume, window mode, resolution, graphics quality, camera edge-scroll, or anything else. `assets/audio` has 20 SFX and one music track and no volume control over either.

**F5 · S1 · Pause is the cheat menu.**
`match_director.gd:1959` — Escape opens `admin_menu`, which is `scripts/battle/hud/admin_menu.gd`: infinite resources, instant build, reveal fog, plus Main Menu and Quit. There is no pause menu. There is no pause at all during a match (`SceneRouter._deploy_gate()` is the only place `get_tree().paused` is ever set).

**F6 · S1 · A DEBUG button sits in the shipping HUD.**
`battle/hud/battle_hud.gd:152-161` adds a `DEBUG` button to the always-on top strip, tooltipped *"Open Debug Menu & Cheats (Infinite Resources, Instant Build, Reveal Fog)"*, immediately beside the resource readout.

**F7 · S2 · The main menu is seven equal-weight siblings with no hierarchy.**
`main_menu.gd:41-94`: TUTORIAL, DESIGN LAB, BLUEPRINT LIBRARY, HULL AUTHORING, OPERATIONS, SKIRMISH, PROVING GROUND — identical cards, identical size, one flat column. Problems compounding:

- A new player is shown seven doors and no model of the loop.
- **HULL AUTHORING is a CAD authoring tool** (`hull_builder.gd`, 2480 lines of SDF/marching-cubes primitive modelling) presented as a peer of "play a battle."
- BLUEPRINT LIBRARY and DESIGN LAB are two halves of one activity, listed apart.
- PROVING GROUND is the *verb* "test this design", listed as a *place*.
- TUTORIAL is card #1 **and** `tutorial_manager.offer_first_run()` exists — two entry points to the same thing.

**F8 · S3 · A stale comment describes a menu card that no longer needs to exist.**

_This finding was originally written as "two reachable battle implementations, S2". That was wrong, and the correction is recorded rather than silently edited because the wrong version would have caused real parity work to be scheduled._

There is **one** battle implementation. `scripts/skirmish.gd` no longer exists — `tests/suite_base.gd:306` records *"MIGRATED FROM Skirmish.tscn TO Battle.tscn with the retirement of the legacy"*, and `match_setup.gd:300` states *"Battle.tscn is the match runtime. It used to be Skirmish.tscn."* All three entry points (`match_setup.gd:305`, `operations_setup.gd:368`, `operations_draft.gd:262`) route to `Battle.tscn`, and every battle suite and probe instantiates it.

The only residue is the orphaned comment at `main_menu.gd:89-93`, which describes a "listed BESIDE Skirmish" card for a rebuilt layer that has since simply *become* Skirmish. Delete the comment. No parity work, no menu ambiguity.

**F9 · S2 · Navigation is a hub-and-spoke with no cross-links.**
Every screen returns to the main menu. Lab to Library is a round trip through home; Library to Skirmish likewise. There is no persistent global chrome — each of the ten screens builds its own header from scratch. `ui_shell.gd` is deliberately three functions (`backdrop`, `screen_frame`, `stat_row`) and its own comment forbids growing it speculatively, which was correct then and is the constraint to revisit now.

### 2.2 The battle layer

**F10 · S1 · There is no selection panel.**
`SelectionService` exists (`battle/orders/selection_service.gd`) and drives control groups and orders. It **already emits `selection_changed(units: Array)`** at `:39`, so a panel would be a pure subscriber requiring no service change. Nothing subscribes. A search for `selection_panel`, `unit_card`, `portrait`, `_build_selection` across `scripts/battle/` returns nothing. When you select a unit you get a green drag rectangle and a world-space HP bar.

In a game whose entire premise is *"you design the units"*, not showing the player the design they just clicked is the largest missed opportunity in the build. This is where the player's own work should be reflected back at them — name, silhouette, armour facets, weapons, current orders.

**F11 · S2 · No alert or event system.** No minimap ping on attack, no screen-edge direction indicator, no jump-to-event key, no idle-harvester cycle, no "unit under attack" audio cue routed anywhere. `sfx_warning_banner` and `sfx_radio_static` exist and are wired only to UI button roles.

**F12 · S2 · Attack-move arming is text-only.** `match_director._set_armed()` writes `"ATTACK-MOVE: RIGHT-CLICK A DESTINATION"` into a hint Label. The cursor does not change, though `assets/cursors/cursor_attack.png` exists and `cursor_manager.gd` is present.

**F13 · S2 · Production and command are two unrelated interaction models.** `production_hud.gd` (745 lines) is a set of sliding CRT toolboxes on one edge with a radial menu; commands are keys with no on-screen surface at all. There is no command card, so there is no discoverable way to issue any order.

**F14 · S3 · CRT styling is a local one-off.** `production_hud.gd:142-146` hardcodes `CRT_BLACK`, `CRT_GREEN`, `CRT_GREEN_DIM`, `CRT_FONT`, `CRT_FONT_SIZE`. These are exactly the phosphor-display language the art brief asks for, implemented once, privately, outside the token system.

### 2.3 The Design Lab

**F15 · S2 · The telemetry rail reports numbers, not verdicts.** The right rail shows structure, weight, cost, DPS, drivetrain load. It is accurate and single-sourced (good), but it asks the player to be an engineer. A parametric tool leads with the *constraint state* — Fusion 360 says "Fully Constrained" in two words before it shows you a dimension.

**F16 · S2 · No pre-commit feedback.** Dragging a part in tells you what changed only after it is placed and you re-read the rail. There is no hover-preview of a part's effect on the design.

**F17 · S2 · No history surface.** Undo and Redo are two toolbar buttons (`stat_calculator.gd:2754-2755`). There is no visible stack, no scrubbable build order, no branch point. The single defining affordance of a parametric studio is absent.

**F18 · S2 · No design lineage or comparison.** `blueprint_library_screen.gd` has rename, duplicate, delete, preview. `fleet_comparison_panel.gd` exists but compares fleets, not variants. There is no "Mk II of this", no A/B, no diff, no record of what a design was derived from.

**F19 · S3 · Only one view mode.** The Lab shows a lit 3D model. It cannot show armour facets by material, weapon arcs, weight distribution, or mount points as a display mode — all of which are data the game already computes and all of which are far more legible than a table.

**F20 · S3 · Document state is invisible.** Scratch vs saved is a real and well-reasoned distinction (`blueprint_manager.gd`), but the screen never says which one you are in or whether you have unsaved changes.

### 2.4 Onboarding

**F21 · S1 · The tutorial ends before the game starts.**
`tutorial/tutorial_steps.gd` is 15 well-written steps across two scenes: `MainLab.tscn` and `Battlefield.tscn` (the proving ground). The final step's body says *"From the main menu: Skirmish is a single battle, Operations is a run of three to twelve..."* — and that is the entire instruction for the RTS. There is no step for base building, harvesting, production, power, fog, control groups, or stances.

A player completes the tutorial and is dropped into a real-time strategy game with a two-line label in the corner (F3).

**F22 · S2 · No contextual help anywhere.** No tooltips on the telemetry readouts, no glossary for "threshold" / "chip damage" / "brute force" / "draught" / "amphibious" — all of which are load-bearing mechanics in `damage_resolver.gd` and `terrain_builder.gd`. No first-time-use callouts on any screen except the tutorial's own.

### 2.5 Sensory layers

**F23 · S2 · The audio set is 20 procedural WAVs.** `tools/generate_audio.py` synthesises everything from sine/noise/sweep primitives. That was the right call to get sound in at all, and it is now the ceiling. One music track. No ambience. No engine loops, no tread clatter, no servo whine — all of which `CORE_DESIGN_LANGUAGE.md` §6.2 lists as required on the sincere side. And §7.5 already flags the whole ordnance set as needing re-recording as vocalisations.

**F24 · S2 · Six UI audio roles for the entire game.** `default / confirm / select / place / reject / danger`. No distinction between a toggle, a dial detent, a drawer opening, a plate sliding, a latch, or a mode change. Everything mechanical sounds the same.

**F25 · S2 · No logo, no wordmark, no boot identity.** The title is a `Label` with `theme_type_variation = "DisplayLabel"` reading `"KITBASH COMMAND"` (`main_menu.gd:25`). No mark, no icon, no splash, no favicon-equivalent for the exported build.

**F26 · S2 · The hobby-desk layer does not exist.** The brief asks for sprues, cutting mats, x-acto knives, glue, paint bottles and cardboard showing at the edges. `assets/textures/ui/` contains six materials, all of them *equipment* materials: powdercoat, steel, bakelite, canvas, carbon, fiberglass. Nothing in the interface references the model-kit world the game is about.

This is the largest gap between the stated aesthetic and the built one, and it is also the cheapest to close — it is a backdrop layer, not a rework.

**F27 · S3 · Font licensing unresolved.** Four TTFs present; `UI_IMPLEMENTATION_PLAN.md` Open Question 3 has been open since the file was written.

### 2.6 Accessibility

**F28 · S1 · Nothing.** No colourblind provision (and the whole system leans on four signal colours — amber/red/green/blue — with red-green as the two most load-bearing), no text scaling, no reduced-motion option, no captions for the radio chatter that §6.2 wants to carry tonal weight, no remapping (F1), no hold-vs-toggle preferences. `HIT_TARGET_MIN = 32` exists as a token and is advisory only.

### 2.7 Verification gaps

**F29 · S2 · No screen ever loads in a test.** `UI_IMPLEMENTATION_PLAN.md` Priority 7.3 records this: no suite instantiates `MainLab.tscn`, which is why a crash on the Design Lab's primary load path was invisible to an otherwise-green 211-suite run. `tools/probe_scene_loads.gd` exists and is not in `SUITE_ORDER`.

**F30 · S3 · `ui_audit.gd` does not enforce the no-emoji rule** despite `CLAUDE.md` having claimed it did. It checks overflow, offscreen controls, theme validity, icons and cursors.

---

## 3. Root cause

Three things, and they explain nearly every finding above.

**The interface was built screen-first.** Each screen is a well-made object; no one ever drew the map of how a player moves between them. That produces a flat main menu (F7), no cross-links (F9), no persistent chrome (F9), and a tutorial that stops at a scene boundary (F21).

**Input was never abstracted, so interaction design has been constrained by implementation accident.** F1 causes F2 causes F3, and it also causes F4 and F28 to be unimplementable rather than merely unimplemented.

**The visual system is finished and the sensory system is not.** Materials, elevation and motion are specified to a professional standard. Sound has six roles and twenty procedural files (F23, F24); the aesthetic's most distinctive layer — the hobby desk — has zero assets (F26); there is no logo (F25).

---

# Part II — Research digest

The two genres this game sits between have both solved their interaction problems thoroughly, and neither solution is currently applied.

## 4. RTS interaction canon — what to take

**The command card, and why it is positional.**
StarCraft II's 3×5 grid is the most-copied RTS interface element ever made, and the reason is not the grid. It is that **position is the hotkey**. In grid layout, "the top-left command" is always Q whatever the unit is; the player learns a *spatial* map, not fifteen alphabetic mnemonics per unit type. Company of Heroes, Zero-K, Beyond All Reason and Age of Empires IV all converged on the same thing.

For Kitbash Command this is decisive, because the units are *player-authored* and therefore have no fixed ability list. A positional grid is the only scheme that can stay learnable when a unit's abilities are emergent from its modules. It also permanently resolves F2: commands live on the grid, the camera lives on edge-scroll plus arrows plus middle-drag, and nothing collides.

**The selection panel is the game's mirror.**
SC2 shows a wireframe and per-unit health; Company of Heroes shows squad composition, veterancy and the vehicle's facing armour; Homeworld shows fleet composition. All three answer *"what did I just click and what can it do."*

Kitbash Command has a stronger version available than any of them: the selected unit is **a thing the player designed**, and the game already computes its armour facets by material, its weapon arcs, its drivetrain load and its per-class thresholds. The selection panel should be a live version of the Design Lab's specification placard. This is the highest-value single addition in this document.

**Alerts are a three-channel system.** Every mature RTS pairs (1) a minimap ping, (2) an audio cue distinct from combat noise, and (3) a jump-to-event key — usually Spacebar. Without the third, the first two are stress rather than information. `sfx_radio_static` and `sfx_warning_banner` already exist for channel 2.

**Idle-worker cycling is a load-bearing convenience.** F1 in SC2, and Beyond All Reason's idle-builder counter. The economy in `battle/economy/` produces idle harvesters and does not surface them.

**Context cursors carry the modal state.** Company of Heroes and Homeworld change the cursor to tell you what a click will do *before* you commit. `cursor_manager.gd` and seven cursor PNGs exist; the attack-move armed state uses a text label instead (F12).

**Command & Conquer's sidebar is the game's own claimed DNA.** A persistent vertical production rail where structures and units are always one click away, and placement is a ghost that follows the cursor. `production_hud.gd`'s sliding toolboxes are a variant of this and are the right instinct; they need to be joined to a command surface rather than being the only surface.

**Pause is a first-class screen, not a debug affordance.** Resume, Objectives, Settings, Restart, Concede, Quit. Debug lives behind a key that is not Escape and behind a build flag.

## 5. Parametric design studio canon — what to take

The Design Lab is a CAD tool with a game attached, and CAD solved this UI thirty years ago.

**The four-quadrant document layout.** Fusion 360, Onshape, Blender and Figma all converge: **left = browser/catalog, right = inspector/properties, top = document actions, bottom = timeline/history.** The Lab has three of four — `parts_menu.gd` left, `stat_calculator.gd` right, toolbar top. **The missing quadrant is the bottom timeline**, and it is the one that makes a tool feel parametric rather than merely modal (F17).

**Constraint state before dimensions.** Fusion's sketch editor tells you "Fully Constrained" in two words before showing a single number. Onshape flags an over-defined sketch in colour. The equivalent verdicts here are already computable from `Drivetrain` and `DesignStats`: OVER CAPACITY, UNDER-ARMOURED FOR CLASS, NO FORWARD ARC, UNPOWERED, CLIPPING. Lead with the verdict; keep the numbers beneath it (F15).

**Live preview before commit.** Grasshopper previews the geometry a node will produce before you wire it; Onshape's feature dialogs update the model live and cancel cleanly. Hovering a part card should ghost its effect onto the telemetry as signed deltas (F16). This is the single change that would most improve the Lab's teaching power, because it converts the stat rail from a report into a feedback loop.

**Configurations, versions and derivation.** Fusion Configurations, Onshape Versions and Branches. A design should know what it was derived from, and the library should be able to show two variants side by side and diff them (F18). "Mk II" is the natural game-facing name.

**Display modes are analysis tools.** Blender's viewport shading modes, CAD section views, FEA colour maps. A design has at least four legible analytical views available from data that already exists: armour facets by material, weapon arcs and dead zones, weight distribution and centre of mass, mount points and free facets (F19).

**Inference must be visible.** Snapping that happens invisibly reads as the tool taking control. CAD draws the inference line. When a module snaps to a facet, highlight the facet; when mirror is on, ghost the mirrored part before the drop; when a mount kit will be inserted, show it.

**The document model must be legible.** Unsaved-changes indicator, autosave, recovery. Scratch vs saved is already correct in the data layer and invisible in the UI (F20).

## 6. Where the two canons meet — and why that is the game

The tutorial should teach one loop, not two toolsets: **design a thing, field it, read the report, revise it.**

That loop already exists in the code — `blueprint_manager` scratch designs, `after_action_report.bp_stats` keyed by blueprint name, `iterate_requested(blueprint_name)` on the AAR. What is missing is that the interface never *narrates* it. The AAR emits `iterate_requested` and the main menu never mentions that the button exists.

The unifying design decision for this whole plan:

> **The specification placard is one component, rendered in four places.** The main menu turntable, the Design Lab telemetry rail, the battle selection panel, and the after-action report all show the same design's specification, in the same layout, with the same fields. It is the same widget with different data sources and different levels of detail.

That single component turns four unrelated screens into one continuous conversation about the player's designs, and it is what will make the game feel authored rather than assembled.

---

# Part III — Target architecture

## 7. Information architecture

Replace the flat seven-card menu with **three activities and one workshop**, plus a global system layer.

```
BOOT
 └── FRONT DESK  (main menu — the bureau's front office)
      │
      ├── [ DEPLOY ]  ─────────► the reason to open the game
      │      ├── Skirmish        one battle, pick map/faction/roster
      │      ├── Operations      3-12 engagements, re-draft between
      │      └── Resume          only shown when a run is in progress
      │
      ├── [ DESIGN ] ──────────► the workshop
      │      ├── Design Lab      assemble a blueprint
      │      ├── Blueprint Library  browse, compare, derive
      │      ├── Proving Ground  a VERB reachable from both of the above
      │      └── Hull Authoring  advanced; behind a disclosure
      │
      ├── [ RECORDS ] ─────────► the thing that makes iteration a loop
      │      ├── Design dossiers per-blueprint lifetime combat record
      │      └── Operation log   past runs
      │
      └── [ SYSTEM ]  ─────────► Settings, Controls, Credits, Quit
```

Four rules that follow:

1. **Proving Ground is a verb, not a destination.** It is a button on the Lab toolbar (it already is) and on every Library card. It leaves the menu.
2. **Hull Authoring is behind a disclosure** in DESIGN, labelled as advanced. It is a CAD tool for making new base hulls; it is not a peer of "play a battle."
3. **Tutorial is not a menu item.** It is the first-run state of DEPLOY and DESIGN, plus a "Replay training" entry under SYSTEM. One entry point, not two (F7).
4. **RECORDS is new, and it is what closes the loop.** `after_action_report.bp_stats` is already collected per blueprint and thrown away at the end of the match. Persisting it gives every design a service record, which is the strongest possible motivation to open the Lab again.

**Cross-links, so the hub is not a bottleneck (F9):**

| From | Direct link to |
|---|---|
| Design Lab | Library, Proving Ground, Skirmish (draft this design) |
| Library | Lab (edit / derive), Proving Ground, Records (this design's dossier) |
| After-action report | Lab (iterate on the worst performer), Records, next stage |
| Any screen | System layer (Escape), Front Desk (persistent home affordance) |

## 8. The five material layers

The existing six materials are all *equipment*. The brief needs three more registers, each with one job, stacked back-to-front:

| Layer | Register | What it is | Where it appears | Status |
|---|---|---|---|---|
| **L0 Workbench** | Hobby desk, sincere | Self-healing cutting mat, cardboard, sprue frames, tool shadows, paint pot rings, scalpel, spilled cement | Behind everything, at the **edges only**. Never under body text | **New — Phase 1** |
| **L1 Equipment** | Cold-war hardware, sincere | powdercoat, steel, bakelite, canvas, carbon, fiberglass | Panels, docks, buttons | **Built** |
| **L2 Phosphor** | CRT display, sincere | P3 amber and P1 green phosphor: scanlines, bloom, persistence smear, curvature vignette, refresh flicker | Anything showing **live data**: telemetry, minimap, queues, selection panel, radar | **Partial — one-off in `production_hud.gd`, promote in Phase 1** |
| **L3 Placard** | Stamped/engraved, sincere | Engraved metal labels, dymo tape, hazard chevrons, rating plates, stencil, knurl, DZUS fasteners, inbuilt handles | Titles, mode labels, warnings, section headers | **Partial — `ui_stamp.gd`, `stamped_label.gd`, `toolbox_plate.gd` exist. Systematise** |
| **L4 Annotation** | Instruction booklet, sincere | Pencil, marker, kit-instruction line art, exploded views, step numbers in circles, arrow callouts | Tutorial, tooltips, first-run coaching | **New — Phase 7** |

**The layer discipline rule, which is what keeps this from becoming noise:**

> Any given control belongs to exactly one layer. A phosphor readout does not get a stamped label *on the glass*; the label is stamped into the L1 bezel around it. A workbench texture never appears above L1. Annotation only ever draws on top of everything, and only during teaching.

The layers also express the tone split cleanly: **L0 and L4 are where the game admits it is about toys; L1, L2 and L3 play it completely straight.** The joke is the juxtaposition of a cutting mat under a military fire-control console — exactly the same structure as photoreal smoke over a person saying "kapow."

## 9. Module boundaries

Six new or promoted modules. Each is independently testable and none reaches into a screen.

| Module | File | Owns |
|---|---|---|
| `InputService` | `scripts/core/input_service.gd` (autoload) | InputMap actions, profiles, rebinding, persistence, conflict detection, the single source for "what key is this action" |
| `SettingsService` | `scripts/core/settings_service.gd` (autoload) | All preferences, `user://settings.cfg`, audio bus routing, `settings_changed` signal |
| `SystemLayer` | `scripts/ui/system_layer.gd` (autoload CanvasLayer) | Escape stack, pause, Settings, Controls, Credits, Quit. Above scenes, below `SceneRouter`'s fade |
| `SpecPlacard` | `scripts/ui/spec_placard.gd` | The one specification widget, four detail levels, four data sources |
| `CommandCard` | `scripts/ui/command_card.gd` | Positional 3×5 grid, action registry, hotkey display driven by `InputService` |
| `AlertService` | `scripts/battle/alert_service.gd` | Event queue, minimap ping, edge indicator, audio cue, jump-to-event |

Plus one promotion: **`ui_tokens.gd` gains a phosphor block** (P3/P1 colours, scanline pitch, persistence decay, bezel inset) so `production_hud.gd`'s private constants and every future display read the same values (F14).

**Autoload budget note.** `SceneRouter`, `TutorialManager` and `AudioManager` are already autoloads. Three more is defensible because all three are genuinely global (input, settings, the Escape stack), but `SystemLayer` must be strictly presentational and must not accumulate game logic.

---

# Part IV — The phases

Eleven phases. Each is one unified segment, each ships independently, and each leaves the game in a better state than it found it. Dependencies are stated; where none is stated, the phase can move.

---

## Phase 0 — Foundations: input, settings, and the system layer

**Segment:** the plumbing every other phase needs, plus the two screens the player has been missing entirely.
**Fixes:** F1, F2, F3 (partially), F4, F5, F6, F28 (partially), F29.
**Depends on:** nothing. **Blocks:** Phases 2, 5, 7, 9.

### Interaction design

**Escape is a stack, not a toggle.** `match_director.gd:1959` already implements this correctly for the battle (placement → selection → menu). Generalise it: Escape pops the most specific open thing, and only opens the System Layer when there is nothing left to pop. This becomes the universal rule across all screens.

**The System Layer** is a single overlay, identical everywhere, drawn on an autoload `CanvasLayer` just below `SceneRouter`'s fade (layer 120 against the router's 128). Contents adapt to context:

```
  ┌─ SYSTEM ─────────────────────────────────┐   ← L3 engraved placard header
  │                                          │
  │   RESUME                                 │   ← only in a match; pauses the tree
  │   SETTINGS                               │
  │   CONTROLS                               │
  │   OBJECTIVES         (in a match)        │
  │   ─────────────────────────────────      │
  │   CONCEDE MATCH      (in a match)        │   ← DangerButton
  │   RETURN TO FRONT DESK                   │
  │   QUIT                                   │
  │                                          │
  │  build 1.6.3                             │   ← L2 phosphor micro-readout
  └──────────────────────────────────────────┘
```

**Settings, four tabs**, each a `UIToolbox` tier so it reuses built chrome:

| Tab | Contents |
|---|---|
| DISPLAY | Window mode, resolution, VSync, frame cap, render scale, quality preset, tilt-shift strength (see `CORE_DESIGN_LANGUAGE.md` §7.1-7.2) |
| AUDIO | Master / SFX / Music / Voice / UI, each on a real audio bus. Test button per slider |
| CONTROLS | Full rebinding, grouped by context (Global / Battle / Lab). Conflict detection inline. "Reset to defaults" per group. Camera pan speed, edge-scroll on/off + zone width, invert zoom |
| GAME | Tutorial hints on/off, replay training, reduced motion, UI scale, colourblind mode, damage-number verbosity, autosave interval |

**Controls screen is the fix for F3.** Once the keymap is real data and there is a screen that renders it, the permanent on-screen cheat sheet can be deleted and replaced with a first-30-seconds coaching overlay (Phase 7) plus a `?` toggle.

**Debug relocation (F6).** The `DEBUG` button leaves the top strip. The admin menu remains, bound to F10 and backtick as it already is (`match_director.gd:1956`), and is gated behind `OS.is_debug_build()` or a `--cheats` command-line flag so an exported build does not carry it.

### Architecture

1. **Author the InputMap** in `project.godot`. Roughly 55 actions in three groups:
   - `ui_*` — Godot's built-ins, kept.
   - `cam_*` — `cam_pan_up/down/left/right`, `cam_zoom_in/out`, `cam_rotate`, `cam_recenter`, `cam_follow`.
   - `cmd_*` — `cmd_move`, `cmd_attack_move`, `cmd_stop`, `cmd_hold`, `cmd_patrol`, `cmd_stance_aggressive/return_fire/hold`, `cmd_group_1..9`, `cmd_group_assign`, `cmd_idle_worker`, `cmd_jump_alert`, `cmd_select_all_army`, `cmd_grid_1..15`.
   - `lab_*` — `lab_mirror`, `lab_rotate`, `lab_delete`, `lab_undo`, `lab_redo`, `lab_cancel`, `lab_view_1..4`, `lab_save`, `lab_test`.
   - `sys_*` — `sys_menu`, `sys_screenshot`, `sys_perf`, `sys_console`.

2. **Migrate all eight raw-keycode call sites.** `rts_camera.gd:152-155` is the important one: it must move from `Input.is_key_pressed(KEY_W)` to `Input.get_vector("cam_pan_left", "cam_pan_right", "cam_pan_up", "cam_pan_down")`. That single change frees A and S and lets Phase 5 restore conventional bindings.

3. **`SettingsService`** as an autoload with typed getters, `user://settings.cfg`, defaults in one dictionary, and a `settings_changed(key, value)` signal. Create four real audio buses (Master, SFX, Music, Voice) and route `AudioManager` through them — it currently plays everything on the default bus.

4. **`InputService`** wraps `InputMap` mutation, serialises overrides to `user://input.cfg`, exposes `binding_label(action) -> String` so every hint in the game renders the *current* key rather than a hardcoded letter.

5. **Promote `tools/probe_scene_loads.gd` into `SUITE_ORDER`** (F29). Every scene must survive `_ready()`. `SUITE_ORDER` is order-sensitive — this lands in its own commit as the plan already notes.

### Assets

| Tool | Asset |
|---|---|
| Inkscape | Slider thumb, checkbox on/off, radio, dropdown chevron, tab underline, conflict-warning glyph, keycap frame (9-slice) for rendering bindings |
| Blender | Rendered orthographic sprite sheet: toggle switch (up/down), rotary selector (8 detents), rocker switch, knurled dial, DZUS fastener, latch. These become the Settings controls and are the phase's signature texture |
| Audacity | `ui_toggle_throw`, `ui_dial_detent`, `ui_slider_tick`, `ui_menu_open` (plate slide), `ui_menu_close`, `ui_pause` (tape-stop), `ui_unpause` |
| GIMP | Keycap plate texture, 9-sliced, in bakelite to match L1 |

### Done when

- No `KEY_` constant remains in gameplay code (`debug_tuning_panel.gd` may keep its own).
- Every action is rebindable, conflicts are detected, and rebinds survive a restart.
- Escape opens the System Layer from every scene; the tree pauses in a match.
- Volume sliders audibly work on four separate buses.
- `probe_scene_loads` is in `SUITE_ORDER` and green.
- No `DEBUG` button in a release build.

---

## Phase 1 — Identity and the material layers

**Segment:** the game's visual signature — logo, glyphs, and the three missing material registers.
**Fixes:** F14, F25, F26, F27.
**Depends on:** nothing. **Blocks:** Phases 2, 4, 5, 6, 7 all consume these.

### Interaction design

This phase is mostly authoring, but it makes three interaction commitments:

**Phosphor means live.** Anything rendered on an L2 phosphor display is *live telemetry that is currently true*. Static text is never phosphor. This gives the player a reliable read on what is a reading versus what is a label, which matters enormously in a HUD.

**Amber and green are not decorative.** P3 amber (`#FFB000`) is the **design/lab** register; P1 green (`#33FF33`) is the **battle/command** register. A player glancing at a screenshot knows which half of the game they are in. Both are display-substrate colours and are *outside* the signal palette — they never mean "warning" or "go", which stay with `SIGNAL_HAZARD` and `SIGNAL_GO` on L1 chrome.

**The workbench is peripheral vision only.** L0 never sits under body text, never above 25% opacity where it meets a panel, and is always further from the camera than L1 in the elevation stack. It reads at the edges and in the gutters, exactly as the brief describes: "showing around the edges."

### Architecture

1. **`ui_tokens.gd` gains a phosphor block:** `PHOSPHOR_AMBER`, `PHOSPHOR_GREEN`, `PHOSPHOR_DIM` (unlit trace), `PHOSPHOR_GLASS` (the dark substrate), `SCANLINE_PITCH`, `PERSISTENCE_DECAY`, `BEZEL_INSET`. `production_hud.gd`'s five private constants are deleted and re-sourced.

2. **`shaders/phosphor_display.gdshader`** — a single shader for all L2 surfaces: scanline modulation at a fixed pixel pitch (must not scale with the control, or it moires), bloom on lit pixels only, per-pixel persistence smear on value change, barrel-distorted vignette, and a very low-amplitude refresh flicker. Parameters exposed for pitch, tint, persistence and curvature.

3. **`PhosphorPanel`, `PhosphorLabel`, `PhosphorGauge`, `PhosphorBezel`** registered as theme variations in `build_ui_theme.gd`.

4. **`tools/generate_ui_plates.py` extended** with the L0 workbench field textures and the L3 placard plates, same fixed-seed discipline so the diff stays reproducible.

5. **Font decision (F27):** resolve licensing and, if needed, replace. Recommended target set, all SIL OFL:
   - Display/stencil: a genuine stencil face rather than Special Elite's typewriter (which reads as *paperwork*, not as *stamped metal*). **Big Shoulders Stencil** or **Saira Stencil One**.
   - UI sans: **Inter** or **IBM Plex Sans** — Plex is the better tonal fit, being an industrial-heritage face.
   - Mono: **IBM Plex Mono** for tabular readouts.
   - Phosphor: a dedicated pixel/terminal face for L2 only — **VT323** or **Departure Mono**. This matters: a smooth sans on a scanlined CRT is the tell that kills the effect.

### Assets

**Inkscape — vector, becomes SVG in `assets/icons/`:**

| Set | Contents |
|---|---|
| Wordmark | "KITBASH COMMAND" as an engraved metal rating plate: stencil face, punched mounting holes at four corners, chamfered edge, part-number line beneath. Horizontal lockup + stacked lockup + mark-only |
| Mark | A single glyph usable at 32px: recommend a sprue gate feeding into a chevron — the kit and the military in one form. Needs to work in one colour |
| Command glyphs (~24) | move, attack-move, stop, hold, patrol, guard, rally, repair, sell/salvage, follow, formation-line, formation-wedge, formation-box, stance-aggressive, stance-return-fire, stance-hold, load, unload, deploy, undeploy, self-destruct, ping, waypoint, cancel |
| Analysis glyphs (8) | armour-facet view, arc view, mass view, mount view, section, measure, ghost, compare |
| Damage-class glyphs (4) | kinetic, thermal, explosive, energy — currently text-only in the placard |
| Locomotion glyphs (17) | one per type in `module_catalog.gd`; the parts menu currently uses text |
| Hazard decals (12) | chevron stripe tile, radiation, high-voltage, crush, hot-surface, no-step, lift-point, mass-limit plate, "THIS SIDE UP", inspection stamp, batch number frame, dymo-tape strip |
| Kit pictograms (10) | hand-drag, click, right-click, scroll, rotate, hold, keyboard, step-number circle, arrow-callout, magnifier-detail — the L4 annotation vocabulary |
| Cursors (6 new) | attack-move, patrol, repair, rally, deploy, no-entry — joining the seven in `assets/cursors/` |

**Blender — orthographic renders to sprite atlas:**

- Machined hardware sprite sheet: chamfered plate corner, knurled dial, inbuilt recessed handle, hinge, latch, DZUS quarter-turn fastener, hex bolt, Phillips screw, rivet row, wire grommet. These are what make L1 read as *machined* rather than as *drawn*.
- CRT bezel: a modelled screen bezel with a real chamfer and four fasteners, rendered as a 9-slice frame for `PhosphorBezel`.
- Sprue frame: a runner with unclipped parts and visible gates, rendered top-down at high resolution for the L0 layer and the loading screen.
- Turntable base for the main menu, replacing `main_menu.gd:261-273`'s `CylinderMesh` — a machined, graduated, bolted turntable is a far better first impression than a grey cylinder.
- Boot-sequence prop: the wordmark plate as a real 3D object, bolted to a panel, lit by a single practical lamp coming up to temperature.

**GIMP / `generate_ui_plates.py` — raster:**

- L0 fields (512², seamless): self-healing cutting mat (the grid is the point), corrugated cardboard, kraft card, chipboard, cork.
- L0 dressing (loose PNGs with alpha, placed at edges): scalpel, sprue nippers, tweezers, glue tube with a dried bead, three paint pots, a paint-pot ring stain, sanding stick, masking-tape strip, a curl of sprue offcut, a thumbprint.
- L3 plates: engraved aluminium label, stamped steel label, dymo tape, hazard-chevron band, all as 9-slice with the existing 128² / 16px-pad convention.
- L2 substrate: dark phosphor glass field with a subtle dust-and-fingerprint layer, plus the scanline lookup texture.

**AI-generated images (where they beat hand-authoring):**
The L0 layer is the right place for these, because it wants photographic detail no one should hand-paint. Brief per image, all shot top-down, flat overcast light, no visible branding, 4K:

1. A green self-healing cutting mat, worn, with cut scores. Straight-on, evenly lit, tileable centre.
2. A grey styrene sprue runner with unclipped tank parts and visible gates, on a plain surface, top-down.
3. Hobby tools scattered on a bench: scalpel, nippers, tweezers, files. Top-down, hard shadows, plenty of empty space.
4. Three enamel paint pots, one open, with ring stains on cardboard. Top-down.
5. A corrugated cardboard sheet, torn edge, top-down, evenly lit.
6. A 1960s military equipment rack panel, engraved labels, chamfered edges, knurled dials — as *reference* for the L1/L3 authoring, not as a shipped asset.

Trace anything that becomes a glyph in Inkscape; ship the photographic ones as textures only, and only on L0.

### Done when

- `PHOSPHOR_*` tokens exist; `production_hud.gd` holds no private colour constants.
- The phosphor shader renders correctly at three UI scales without moiré.
- The wordmark exists in three lockups plus a 32px mark, and appears on the boot screen and the Front Desk.
- L0 appears behind the Front Desk and the Lab and is invisible behind body text.
- Fonts are licence-cleared and recorded in `CREDITS.md`.

---

## Phase 2 — Menus and navigation

**Segment:** the Front Desk, the shell every out-of-match screen shares, and the routes between them.
**Fixes:** F7, F8, F9.
**Depends on:** Phase 0 (System Layer), Phase 1 (identity, L0, L3).

### Interaction design

**The Front Desk.** Not a list of scenes — a room, with the player's most recent design on the turntable and three doors.

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │  KITBASH COMMAND        [wordmark plate, L3]      BUREAU / CONSOLE 04  │
 ├──────────────────────┬─────────────────────────────┬───────────────────┤
 │                      │                             │                   │
 │   DEPLOY             │                             │  ┌─ SPEC ──────┐  │
 │   ▸ Skirmish         │      turntable, L1 base     │  │             │  │
 │   ▸ Operations       │      current design         │  │ SpecPlacard │  │
 │   ▸ Resume run       │      L0 workbench behind    │  │  (L2 glass) │  │
 │                      │                             │  │             │  │
 │   DESIGN             │                             │  └─────────────┘  │
 │   ▸ Design Lab       │                             │                   │
 │   ▸ Blueprint Library│                             │  LAST ENGAGEMENT  │
 │   ▸ Hull Authoring ⌄ │                             │  [L2 phosphor]    │
 │                      │                             │                   │
 │   RECORDS            │                             │  ROSTER  7 / 15   │
 │                      │                             │                   │
 ├──────────────────────┴─────────────────────────────┴───────────────────┤
 │  [ SYSTEM ]                                    ◂ ▸  cycle showcase     │
 └────────────────────────────────────────────────────────────────────────┘
```

Three changes carry most of the value:

1. **Three groups instead of seven peers.** Each group is a stamped L3 section header; entries are the existing `NavCard`. Group headers are not clickable — no submenu navigation, no state to get lost in. Everything stays one click deep.
2. **The turntable shows *your latest design*, not a hull chassis.** `main_menu.gd:151-177` currently mixes saved blueprints with eight fallback hull types. Lead with the most recently modified blueprint and hold it; cycle only on request or after a long idle. A returning player should see their own work, not a stock chassis.
3. **The placard is `SpecPlacard`** — the same component that will render in the Lab, the battle, and the AAR (§6).

**First run** replaces the DEPLOY and DESIGN groups with a single card: *"BUILD YOUR FIRST VEHICLE — fifteen guided steps."* No seven-door problem, because on the first run there is one door. Everything else appears once training is done or explicitly skipped.

**The shared shell.** Every out-of-match screen gets the same three-band frame from a new `UIShell.screen_shell()`:

```
 ┌ TITLE BAND ────────────────────────────────────────────┐  L3 engraved
 │ ◂ BACK   BUREAU / DESIGN LAB          [contextual] [≡] │  breadcrumb + system
 ├────────────────────────────────────────────────────────┤
 │ CONTENT                                                │
 ├────────────────────────────────────────────────────────┤
 │ ACTION BAR    hints           [secondary] [PRIMARY]    │  primary always bottom-right
 └────────────────────────────────────────────────────────┘
```

Consistency here is worth more than cleverness: back is always top-left, the primary action is always bottom-right, the system menu is always top-right, and the breadcrumb always says where you are. Currently none of those is true twice in a row.

**Cross-links** per the table in §7, rendered as a "GO TO" affordance in the title band's contextual slot.

**Resolve F8.** Delete the orphaned comment at `main_menu.gd:89-93`. The SKIRMISH card already routes to the one battle runtime via MatchSetup; nothing else is needed.

### Architecture

- `main_menu.gd` becomes `front_desk.gd`; `DESTINATIONS` becomes a nested group structure with a `first_run_only` / `hidden_until` predicate per entry.
- `UIShell` grows `screen_shell()`, `title_band()`, `action_bar()` — and only these three, all with every call site migrated in the same commit, per the file's own standing rule.
- A `NavigationRegistry` (small, data only) holds the route table so cross-links are declared in one place rather than as five scattered `router.goto()` literals.
- `SceneRouter.goto()` gains an optional `from` for breadcrumb and back-target resolution.

### Assets

| Tool | Asset |
|---|---|
| Blender | The machined turntable base (Phase 1) placed and lit; a bolted section-header plate for group headings |
| Inkscape | Breadcrumb separator, back chevron, "go to" glyph, disclosure chevron for Hull Authoring, group-header rule cap |
| Audacity | `ui_screen_enter` / `ui_screen_exit` (a soft relay clunk, paired to the router fade), `ui_group_expand`, `ui_turntable_index` (a detent as the turntable steps) |
| GIMP | The Front Desk L0 backdrop composite — mat, sprue, tools, arranged so the centre third is clear for the turntable |

### Done when

- The Front Desk shows three groups, the player's latest design on the turntable, and a live spec placard.
- First run shows exactly one card.
- All eight out-of-match screens use `screen_shell()`; back, primary and system are in identical positions on each.
- At least six cross-links work, and Lab → Library → Lab does not pass through the Front Desk.
- Exactly one battle mode is reachable from the menu.

---

## Phase 3 — The sound design pass — **DONE**

**Segment:** every sound in the game, and the mix.
**Fixes:** F23, F24, and `CORE_DESIGN_LANGUAGE.md` §7.5 — all closed.
**Depends on:** Phase 0 (audio buses).

**Delivered:** 66 variant banks / 213 files, all procedurally generated by
`tools/audio/`; 6 music states in 8 Ogg files; a rewritten `audio_manager.gd`
with variant banks, pooled 3D voices, voice limiting, a music state machine with
crossfades, combat-intensity stem mixing, looping engine emitters, surface
ambience and Voice-bus routing. Music is now actually reachable — `play_music()`
had zero callers in the entire project before this pass.

**One brief was revised.** The music register below originally read "cold-war —
brass, low strings, tape-saturated, no synthwave", and the direction given for
this pass was Frank Klepacki. Those reconcile rather than collide: *Hell March*
is an industrial rhythm section **with** cold-war brass over it, and both
descriptions agree on tape saturation and on rejecting synthwave. The adopted
register is **industrial rock rhythm section, cold-war brass and low strings
carrying the hook, tape-saturated**, and the table below has been updated to
say so rather than leaving the doc disagreeing with the shipped assets.

### Interaction design

`CORE_DESIGN_LANGUAGE.md` §6 is unusually clear and this phase is mostly execution against it. Two additions.

**The UI audio role set expands from six to fourteen**, because the interface is about to have real mechanisms in it and a rotary selector must not sound like a hyperlink:

| Role | Sound | Fires on |
|---|---|---|
| `hover` | soft contact | any hover (unchanged, never varies) |
| `default` | detent click | ordinary press |
| `confirm` | radio ack | committing |
| `select` | select tick | picking from a set |
| `place` | seat/snap | putting a thing in the world or a slot |
| `reject` | dead buzz | refused input; pair with `shake` |
| `danger` | warning banner | destructive |
| `toggle_on` / `toggle_off` | switch throw, two directions | latched state |
| `dial` | rotary detent | stepped value |
| `drawer` | rail slide + soft stop | toolbox/dock open |
| `plate` | metal plate seat | panel arrival |
| `latch` | quarter-turn fastener | mode commit, dock lock |
| `mode` | relay clunk | view-mode or major mode change |

The relevant constraint from the style guide holds: **interface audio is on the sincere side.** No comedy on a button.

**Vocalised ordnance, per §6.2 and §7.5.** Prototype on **one** weapon and playtest before committing the set — that instruction is already in the design language and is worth honouring. Recommended prototype: the basic cannon, because it fires often enough to expose repetition fatigue immediately. Record 6-8 variants of each vocalisation so nothing repeats identically, and layer the *visual* channel photoreal to compensate, exactly as §6.1 requires.

### Architecture

- `AudioManager` gains bus routing, per-category volume from `SettingsService`, a variant-picker (round-robin with no immediate repeat), a distance/occlusion model for 3D SFX, and voice-limit ducking so twelve simultaneous cannons do not clip.
- A **music state machine**: front-desk bed, lab bed, tension, combat, victory, defeat, with crossfades on state change. One track cannot carry a whole game.
- **Ambience beds** per surface type from `terrain_builder.gd`'s seven surfaces, faded by camera height so the macro-lens read has an audio equivalent.

### Assets

**Fully procedural — this is what was actually built, and it differs from the plan above.** There is no Audacity stage and no foley. `tools/generate_audio.py` became a thin CLI over a real synthesis package, `tools/audio/`, layered `dsp → instruments → sequencer → tracks` with `voice` and `sfx` alongside. Everything ships as the generator's direct output.

The reasoning that changed the recommendation: hand-treating in a DAW makes the committed `.wav` the source of truth and the script a historical curiosity, which is the state every other asset pipeline in this repo deliberately avoids. Keeping it end-to-end procedural means a tonal change is a diffable one-line edit plus a re-run, variants are free (seeded, 3–8 per key), and there is no third-party licensing surface anywhere in the shipped audio. It also made the ordnance vocalisations possible without a recording session — see `CORE_DESIGN_LANGUAGE.md` §7.5.

| Group | Files |
|---|---|
| UI mechanisms (~20) | Foley these: a real toggle switch, a rotary dial, a drawer rail, a quarter-turn fastener, a metal plate set down. Close-mic, dry, no reverb |
| Radio (~12) | ack ×4, negative ×2, static bed loop, squelch open, squelch close, alert klaxon, low-power warning, unit-lost tone. Record a calm, clipped, professional read and band-pass to 300-3400 Hz |
| Ordnance vocalisations (~40) | Per weapon class in `module_catalog.gd`, 6-8 variants each. Deadpan, dry, close, committed. Pitch and timbre differentiate class so audio stays informative — low "kaPOW" for heavy cannon, clipped rapid "pewpewpew" for MG |
| Mechanical (sincere, ~25) | Engine loops ×4 by class, tread clatter, wheel roll, servo whine, hydraulic hiss, rotor wash, screw churn, turret traverse start/loop/stop |
| Impact & destruction (~15) | Armour ping (below-threshold chip), penetration, module loss, immobilisation, catastrophic kill. These need to be *readable* — the player should hear the difference between a bounce and a penetration |
| Construction (~10) | Foundation set, build loop, build complete, unit rollout, harvester dock, harvester full, repair loop |
| Ambience (~9) | Wind ×3 intensity, rain, marsh, forest, ice creak, distant artillery bed, plus a room tone for the Lab |
| Music (6 states, 8 files) | Front desk, lab, skirmish, operations, victory, defeat. **Industrial rock rhythm section, cold-war brass and low strings carrying the hook, tape-saturated.** All in A phrygian. Skirmish renders as three sample-locked stems (bed / rhythm / lead) mixed live by combat intensity, which replaces the separate "tension" and "combat" tracks this table originally listed — a continuous ramp beats crossfading between two pieces |

**AI-image note:** none needed here.

### Done when

- ~~Fourteen UI roles are wired and audibly distinct.~~ Sixteen, in fact — the fourteen specified plus `ui_menu_open` / `ui_menu_close` for the system layer. Eight of them had been mapped in `ui_feedback.gd` to files that did not exist and were silently playing nothing.
- ~~No sound repeats identically within four plays.~~ Banks carry 2–7 variants and the picker never returns the same index twice consecutively; asserted by `test_audio_system`.
- ~~One weapon's vocalisation has been playtested and the tone confirmed before the rest are recorded.~~ The basic cannon was built and auditioned first, exactly as instructed; the first pass was judged too subtle and the formant bank was rearchitected from parallel to cascade before the set was generated.
- ~~Music transitions on state without a hard cut.~~ 1.6 s crossfade between states, 2.2 s for intensity stems.
- ~~All five volume sliders do what they say.~~ Four sliders (Master/Effects/Music/Voice). The Voice audition was auditioning through the *SFX* bus and now routes via `play_voice`; Music deliberately has no one-shot audition because it demonstrates itself live.

**Not in this pass:** the `AlertService` (minimap ping, screen-edge marker, jump-to-event) is a separate item under Phase 5. The audio channel it needs exists — `radio_structure_lost`, `radio_unit_lost`, `radio_low_power`, `warning_banner` — and the structure-lost and unit-lost cues are already wired in `match_director.gd`.

---

## Phase 4 — The Design Lab as a parametric studio

**Segment:** `MainLab.tscn`, `parts_menu.gd`, `stat_calculator.gd`, `module_placer.gd`, `gizmo_3d.gd`.
**Fixes:** F15, F16, F17, F18, F19, F20.
**Depends on:** Phase 0 (input actions), Phase 1 (L2 phosphor for the telemetry rail).

### Interaction design

Complete the four-quadrant layout (§5) and convert the stat rail from a report into a feedback loop.

```
 ┌ TOOLBAR ─────────────────────────────────────────────────────────────────┐
 │ ◂  DESIGN LAB  ·  "Mudlark Mk II" *      HULL PARTS COST   ⟲ ⟳  ⧉ SAVE ▶ │
 ├──────────┬───────────────────────────────────────────────┬───────────────┤
 │          │                                               │  ┌─────────┐  │
 │ CATALOG  │                                               │  │ VERDICT │  │  L2
 │          │             3D CANVAS                         │  │ OVER    │  │
 │ [search] │                                               │  │ CAPACITY│  │
 │          │        view: SOLID / ARMOUR / ARCS /          │  └─────────┘  │
 │ ▾ HULLS  │              MASS / MOUNTS                    │               │
 │ ▾ WEAPONS│                                               │  TELEMETRY    │
 │ ▾ SUPPORT│                                               │  weight  1240 │
 │ ▾ DRIVES │                                               │       +180 ▲  │  ← live delta
 │          │                                               │  speed   18.2 │
 │          │                                               │        -3.1 ▼ │
 ├──────────┴───────────────────────────────────────────────┴───────────────┤
 │ ⊞ ▸ hull ▸ wheels ▸ cannon ▸ armour ▸ sensor ▸ ●                        │  ← NEW: timeline
 └──────────────────────────────────────────────────────────────────────────┘
```

**1 · The verdict block (F15).** Top of the rail, on L2 phosphor amber, one line of plain language before any number:

> `OVER CAPACITY — 1240 kg on 1060 kg of drive. Top speed cut 32%.`
> `NO REARWARD ARC — nothing covers the rear 90 degrees.`
> `BALANCED — within capacity, all facets armoured, forward and flank arcs covered.`

Every verdict is computed from data `DesignStats` and `Drivetrain` already produce. **Nothing is re-derived** — that rule from `UI_IMPLEMENTATION_PLAN.md` Priority 6 is non-negotiable and has already cost this project twice.

**2 · Hover-preview deltas (F16).** Hovering a catalog card ghosts the part onto the hull *and* renders signed deltas beside every affected telemetry row, in `SIGNAL_GO` / `SIGNAL_ALERT`. Release without dropping and everything reverts. This is the Grasshopper/Onshape pattern and it is the single change that most improves the Lab's teaching power, because the player learns the design space by *browsing* it rather than by trial and error.

**3 · The build timeline (F17).** A horizontal strip along the bottom, one chip per operation, scrubbable. Clicking a chip previews the design at that point; committing there truncates the future with a confirmation. This is Fusion 360's timeline, and it is the affordance that makes the Lab read as a design tool rather than a menu.

It also gives the tutorial a natural surface: the timeline *is* a record of the steps the player took, in the same visual language as a kit instruction sheet.

**4 · Display modes (F19).** Four analytical views on `lab_view_1..4`, all from existing data:

| Mode | Renders |
|---|---|
| SOLID | Current lit view (default) |
| ARMOUR | Facets tinted by material and effective thickness; thresholds per damage class on hover |
| ARCS | Weapon coverage as translucent wedges on the ground plane; dead zones in `SIGNAL_ALERT` |
| MASS | Centre of mass marker, per-module mass as sphere size, drive capacity as a ring |
| MOUNTS | Free facets highlighted, occupied ones dimmed, mount kits shown as the transition geometry they are |

**5 · Design lineage (F18).** A blueprint records `derived_from` and `revision`. "Derive Mk II" is a first-class action in the Lab and the Library. The Library gains a compare mode: two designs side by side with a telemetry diff column. This is what turns a flat list of saves into a design history.

**6 · Document state (F20).** The title band shows the design name, an asterisk when dirty, and `SCRATCH` vs `LIBRARY` as an L3 stamped chip. Autosave to `user://lab_recovery.json` every 30 s; offer recovery on next entry if it is newer than the scratch file.

**7 · Visible inference.** Facet highlight on drag-hover, mirror ghost before drop, mount-kit preview, clipping shown as a red intersection volume rather than only refused at save time.

### Architecture

- **`LabDocument`** — a new model object owning modules, undo stack, dirty flag, derivation metadata, and emitting `changed(reason)`. `module_placer.gd` currently owns the undo stack alongside placement logic; separating them is what makes the timeline possible at all.
- **`DesignVerdict`** — pure function over a `DesignStats` result returning an ordered list of verdicts with severity. Trivially unit-testable, zero scene dependencies. This is the phase's most testable piece and should be written first.
- **`LabViewMode`** — an enum plus one overlay renderer per mode, each reading the live hull and owning no state.
- **`stat_calculator.gd` is 3036 lines and does too much.** Split: `TelemetryRail` (display), `LabToolbar` (document actions), `DesignVerdict` (analysis), `LabDocument` (state). The file's own history shows it has twice had to delete drifting local re-derivations — the size is the reason.
- Blueprint schema gains `derived_from`, `revision`, `created`, `notes`. Per the standing rule, **bump the blueprint version only if an older save could silently mis-load** — additive optional fields do not require it.

### Assets

| Tool | Asset |
|---|---|
| Inkscape | Timeline chip frames (one per operation class), the five view-mode glyphs, delta arrows ▲▼, derive/compare/diff glyphs, the dirty-state asterisk as a stamped mark |
| Blender | Mount-kit preview geometry (already partly authored — `build_mount_kits.py`); a machined graduated ring for the mass-view drive-capacity indicator; a proper Lab platform with a graduated turntable edge and jig fixtures |
| GIMP | L2 phosphor field for the telemetry rail; the arc-wedge gradient texture; the clipping-intersection hatch pattern |
| Audacity | `lab_part_hover` (a light preview tick), `lab_part_seat` (a satisfying plastic snap — this one sound will be heard more than any other in the game and deserves real foley), `lab_mirror_toggle`, `lab_view_mode` (relay clunk), `lab_timeline_scrub` (per-chip detent), `lab_verdict_bad` (a low relay drop), `lab_save_stamp` (a genuine rubber-stamp thud) |

**The part-seat sound is worth calling out.** It is the core verb of the game's core screen. Foley it properly: real styrene parts clicking into a real socket, close-miked, three or four variants by part mass.

### Done when

- The verdict block leads the rail and every verdict is derived, never re-derived.
- Hovering a part shows deltas; releasing reverts cleanly with no residue.
- The timeline scrubs, previews and truncates with confirmation.
- All five view modes render from live data.
- A design can be derived, and two designs can be compared with a diff.
- Dirty state is visible and recovery works after a forced quit.

---

## Phase 5 — The battle command layer

**Segment:** the in-match HUD — selection, commands, alerts, production.
**Fixes:** F2 (fully), F3 (fully), F10, F11, F12, F13.
**Depends on:** Phase 0 (input actions — this phase is blocked without them), Phase 1 (L2 green phosphor), Phase 4 (`SpecPlacard`).

### Interaction design

```
 ┌──────────────────────────────────────────────────────────────┬─────────┐
 │ 1,240 cr  +30/s   ▓▓▓▓▓░░ POWER      12:04                   │ MINIMAP │
 └──────────────────────────────────────────────────────────────┤ [L2 grn]│
                                                                 │         │
   ◂ alert edge marker                                           └─────────┘
                                                                 ┌─────────┐
                            BATTLEFIELD                          │ QUEUES  │
                                                                 │ (exists)│
                                                                 └─────────┘
 ┌── SELECTION ──────────────────────────┬── COMMAND CARD ──────────────────┐
 │ ┌────┐  MUDLARK MK II   ×4            │ ┌───┬───┬───┬───┬───┐            │
 │ │ ▣  │  ▓▓▓▓▓▓▓░░ 71%                 │ │MOV│ATK│STP│HLD│PAT│  Q W E R T │
 │ └────┘  kinetic 12 · thermal 4        │ ├───┼───┼───┼───┼───┤            │
 │  facets ◤◥◣◢   arcs ◜◝                │ │AGR│RTF│HLD│   │   │  A S D F G │
 │  ORDER: attack-move → (142, 88)       │ ├───┼───┼───┼───┼───┤            │
 │  [subgroup tabs ▸ ▸ ▸ ]               │ │   │   │   │   │RAL│  Z X C V B │
 └───────────────────────────────────────┴─┴───┴───┴───┴───┴───┴────────────┘
```

**1 · The selection panel (F10) — the flagship of this phase.**
`SpecPlacard` at battle detail level, showing: the design's name and a rendered silhouette, aggregate health across the selection, armour facets with live damage state, weapon complement and current arcs, current order and stance, and subgroup tabs when the selection is mixed.

The player is looking at **their own design**, alive and damaged, in the same layout the Lab showed it in. That continuity is the whole product thesis made visible, and it costs one shared widget.

**2 · The command card (F13) — and the fix for F2 and F3.**
A 3×5 positional grid, bottom-right, hotkeys `cmd_grid_1..15` defaulting to `QWERT / ASDFG / ZXCVB`. Position is the binding. The card is populated from the selection's actual capabilities — which is exactly what a game with player-authored units needs, since no two designs have the same ability set.

With `rts_camera.gd` migrated to `cam_pan_*` actions in Phase 0, the conventional bindings are free again. Provide two default profiles in Settings → Controls: **Grid** (positional, recommended) and **Classic** (A-move, S-stop, H-hold, P-patrol, arrows and edge-scroll for camera). Both ship; neither is hardcoded.

The permanent on-screen keymap label (`match_director.gd:2206`) is deleted. The command card *is* the documentation, with each cell rendering its live binding from `InputService.binding_label()`.

**3 · The alert system (F11).** `AlertService` with three channels per event: a minimap ping with a decaying ring, a screen-edge directional marker, and a routed audio cue. `cmd_jump_alert` (default Space) jumps the camera to the most recent unhandled alert; pressing it again cycles older ones. Event types: under attack, structure lost, unit lost, production complete, harvester idle, low power, insufficient resources, enemy spotted.

`cmd_idle_worker` (default F1) cycles idle harvesters with a persistent count badge.

**4 · Context cursors (F12).** `cursor_manager.gd` drives the cursor from hover target and armed mode: attack over an enemy, move over ground, invalid over unreachable, deploy in placement mode, repair over a damaged friendly. The attack-move armed state changes the cursor, not just a label.

**5 · Placement clarity.** Building placement already ghosts. Add: footprint on the terrain conformed to slope, red hatching for illegal ground, a buildable-radius ring, and range/arc preview for defensive structures before the click.

**6 · Production and command unify.** `production_hud.gd`'s CRT toolboxes stay — they are good and they are the C&C sidebar DNA. They move to the same L2 green register as the rest of the battle chrome, and gain queue hotkeys and shift-queue-five.

### Architecture

- `CommandCard` widget: an action registry keyed by grid position, populated by querying the selection, hotkeys resolved through `InputService`.
- `SelectionService` gains `signal selection_changed(units)` and subgroup computation, so the panel is a pure subscriber and the service never learns what a HUD is.
- `AlertService` as a node under the director: a bounded event queue, dedup within a time window per type and location, and severity ordering.
- `match_director.gd` is 2200+ lines and builds its own HUD inline (`:2180-2235`). Extract `BattleHUDAssembly` so the director orchestrates the match and the HUD assembles itself.
- Delete the bindings Label. Delete the DEBUG button (Phase 0 already moved the menu behind a flag).

### Assets

| Tool | Asset |
|---|---|
| Inkscape | 15 command-card cell frames (normal/hover/pressed/disabled/cooldown), the 24 command glyphs from Phase 1 placed into cells, alert-type glyphs ×8, edge-marker arrow, idle-worker badge, subgroup tab shapes, minimap ping ring |
| Blender | Command-card bezel as a modelled panel with recessed cells and a chamfered rim — this is the most-looked-at piece of chrome in the game and deserves modelled depth rather than a drawn bevel |
| GIMP | L2 green phosphor field for the minimap and selection panel; the minimap fog and ping overlays; placement hatch |
| Audacity | `cmd_issue` (order confirm), `cmd_reject`, `alert_under_attack`, `alert_structure_lost`, `alert_production_ready`, `alert_low_power`, `ping`, `jump_to_alert`, `group_assign`, `group_recall`, `subgroup_cycle`. Route all alerts through the radio voice so they land on the sincere side |
| Animation | Minimap ping expansion, edge-marker pulse, command-cell press, selection-panel arrival slide, alert-badge count-up |

### Done when

- Selecting any unit shows its design, health, armour facets, weapons, order and stance.
- The command card populates from the selection and every cell shows its live binding.
- Both control profiles work; the on-screen keymap label is gone.
- Alerts ping, mark the edge, sound, and are jumpable.
- The cursor communicates the pending action in every mode.
- No debug affordance in a release build.

---

## Phase 6 — Pre-match, draft, and after-action

**Segment:** `MatchSetup`, `OperationsSetup`, `OperationsDraft`, `AfterActionReport`, plus the new Records screen.
**Fixes:** the unexploited value in F-none-specifically — this phase is where §6's loop gets closed.
**Depends on:** Phase 2 (shell), Phase 4 (`SpecPlacard`, lineage).

### Interaction design

**Match setup becomes a briefing, not a form.** `match_setup.gd` is currently four `OptionButton` dropdowns plus the roster picker. The dropdowns are fine; the framing is not. Reskin as a mission briefing document on L3 placard over L0 workbench: map as a real preview rather than a dropdown label, opposition described in prose the AI actually honours, and the roster shown as the kit box it is.

`roster_picker.gd` is already drag-and-drop with baked thumbnails and slot-position-as-order — genuinely good work. Add: a fleet-composition readout (`fleet_comparison_panel.gd` already exists), a counter-pick hint at higher difficulties, and a warning when the roster has no answer to a class.

**The draft between operation stages gains stakes.** Show what the last engagement cost, which designs performed, and what the next map favours. `OperationsDraft` currently re-runs the roster picker; it should read as consequence.

**The after-action report becomes the design report card.** `after_action_report.gd` already collects per-blueprint kills, damage dealt, damage taken by class, and credits spent. That is better data than most shipped RTS have. Present it as a verdict per design, in the same `SpecPlacard` layout, with:

- Best and worst performer called out by name.
- Damage-taken-by-class breakdown pointing at an armour choice: *"Mudlark Mk II took 71% of its damage as thermal. It is running hardened steel."*
- A one-click **ITERATE** that opens the Lab on that design pre-derived as Mk II. The signal already exists (`iterate_requested`); wire it and make it the primary action.

**Records (new).** Persist `bp_stats` across matches. Each design gets a dossier: sorties, kills, losses, damage profile, cost efficiency, lineage tree. This is what makes designing a second version feel earned rather than arbitrary, and it costs a JSON file plus a screen.

### Architecture

- `DesignRecord` service: appends match results to `user://records/<blueprint_id>.json`; aggregates on read.
- `after_action_report.gd` (284 lines) splits presentation from the stats model so Records can reuse the model.
- `SpecPlacard` gains a `RECORD` detail level.
- Operations state (`operations_manager.gd`) surfaces a resumable run to the Front Desk's DEPLOY group.

### Assets

| Tool | Asset |
|---|---|
| GIMP / AI | Kit-box art frames for roster cards — the design's silhouette on a box front with a stamped part number. This is the strongest single visual idea available to the game and belongs here |
| Inkscape | Report-card grade stamps (PASS / MARGINAL / LOSS as rubber stamps), damage-class breakdown bar glyphs, lineage-tree connectors, medal/service-record marks |
| Blender | Map preview renders — one orthographic hero render per map in `map_catalog.gd`, replacing the dropdown label |
| Audacity | `report_stamp` (rubber stamp on paper), `report_reveal` (per-row paper slide), `victory_fanfare` / `defeat_sting` reworked from the current procedural ones |

### Done when

- Match setup shows a real map preview and a composition readout.
- The AAR names a best and worst performer and explains the damage profile in a sentence.
- ITERATE opens the Lab on a pre-derived Mk II.
- Records persists across sessions and a design's dossier is reachable from the Library.

---

## Phase 7 — Onboarding: the instruction booklet

**Segment:** the tutorial, contextual help, and the glossary.
**Fixes:** F21, F22, F3's residue.
**Depends on:** Phases 0, 2, 4, 5 — this teaches the redesigned interface, so it must come after it.

### Interaction design

**The framing device: the tutorial is a model kit instruction booklet.** This is the L4 annotation layer and it is the game's best available onboarding metaphor — numbered steps in circles, exploded-view line art, arrow callouts, a parts manifest, and a paper stock that sits over the interface like a folded sheet on a workbench. It is *exactly* what a kitbash game's tutorial should look like, and it lets instruction be visually separate from chrome without inventing a new register.

**Three tracks, not one:**

| Track | Steps | Teaches |
|---|---|---|
| **ASSEMBLY** (existing, revised) | ~15 | The Lab and the Proving Ground. Add the timeline, the verdict block, and hover-deltas from Phase 4 |
| **DEPLOYMENT** (new) | ~14 | The battle: camera, selection, the command card, harvesting, refineries, power, factories, production, placement, fog, stances, control groups, alerts, win condition |
| **CAMPAIGN** (new, short) | ~5 | Operations: the itinerary, the re-draft, attrition, reading the AAR, iterating a design |

Each track is independently replayable from Settings → Game.

**Contextual coaching replaces the permanent keymap (F3).** In the first three minutes of a player's first match, a small L4 card appears beside the relevant element the first time it becomes relevant — the first time a harvester goes idle, the first time power goes low, the first time an enemy is spotted. Each is dismissible and never shown again. This is the correct replacement for a fixed cheat sheet: teaching at the moment of need, then getting out of the way.

**A glossary (F22).** Every mechanical term in the game has a definition and can be reached by hovering it: threshold, chip damage, brute force, facet, draught, amphibious, arc, capacity, overload, tier, subgroup. `damage_resolver.gd` and `terrain_builder.gd` already implement all of these in ways the player currently has to infer.

**Tooltips on every telemetry readout**, explaining what the number means and what changes it.

### Architecture

- `tutorial_steps.gd` becomes three tables; `tutorial_manager.gd` gains a track concept. The existing condition vocabulary (`ADVANCE_IDS`) extends with battle conditions: `harvester_returned`, `refinery_built`, `unit_produced`, `group_assigned`, `enemy_engaged`, `structure_placed`.
- The existing test that asserts `ADVANCE_IDS` and the manager's switch agree must be extended to all three tables — it is the guard against stranding a player on a step forever, which is the worst failure this feature has.
- `Glossary` as a data file plus a hover-resolver that any label can opt into via metadata.
- `tutorial_overlay.gd` gains the L4 booklet rendering: paper stock, step-number circles, callout arrows drawn to the spotlight target.

### Assets

| Tool | Asset |
|---|---|
| Inkscape | The entire L4 vocabulary: step-number circles 1-20, callout arrows (straight/curved/elbowed), the ten kit pictograms from Phase 1, an exploded-view connector line style, a parts-manifest table frame, a "DO NOT" cross mark |
| GIMP / AI | Instruction-sheet paper stock: off-white, slightly translucent, fold creases, a faint printing misregistration. One AI-generated reference of a 1970s model kit instruction sheet is the right input here; trace the layout conventions, do not ship the image |
| Blender | Exploded-view renders of a reference vehicle for the ASSEMBLY track — parts separated along assembly axes with connector lines, rendered as line art. This is a striking asset and it is nearly free given the hulls and parts already exist as GLBs |
| Audacity | `booklet_page` (paper turn), `booklet_open`, `booklet_close`, `step_complete` (a soft pencil tick), `coach_appear` (very quiet — coaching must not startle) |

### Done when

- Three tracks exist, are independently replayable, and each has a passing table-integrity test.
- A new player can go from launch to winning a skirmish without external help.
- The permanent keymap label is gone and contextual coaching has replaced it.
- Every mechanical term resolves in the glossary; every telemetry row has a tooltip.

---

## Phase 8 — Motion, animation, and world-space UI

**Segment:** everything that moves — UI transitions, world markers, and the build/deploy/fire/move animation set.
**Depends on:** Phases 4, 5 for the surfaces it animates.

### Interaction design

`ui_anim.gd` and the motion tokens are good and stay. This phase extends motion into the world, where the game currently has almost none.

**The animation principle, from `CORE_DESIGN_LANGUAGE.md` §5 and §7.3:** *mass affects the numbers, never the animation curve.* Weight changes how fast a unit goes; it never changes how it eases into going there. Rigid, abrupt, toy-like — but with rotating parts genuinely rotating and articulated gear genuinely articulating. The recommendation in §7.3 is already the right one: keep the simulation, forbid the visual tell.

**World-space UI, which the game currently lacks almost entirely:**

| Element | Behaviour |
|---|---|
| Selection markers | A stamped bracket that conforms to terrain, scales with unit footprint, not a flat circle |
| Order markers | Move/attack/rally waypoints drawn on the ground with connecting lines, fading on arrival |
| Rally lines | From a factory to its rally point, dashed, animated toward the destination |
| Health bars | Existing `world_hp_bar.gd`; add facet damage as segment tinting so directional armour is visible in the world |
| Build progress | A ring on the structure, plus scaffold geometry that retracts |
| Range and arc preview | On selection of a defensive structure, and during placement |
| Damage numbers | Optional, verbosity-controlled from Settings |

**Structure construction** should read as a model being assembled, not as an object fading in: foundation stamps down, scaffold rises, panels seat in sequence, scaffold retracts, a final settle. `build_buildings.py` already authors the meshes; this is animation over existing geometry.

**Unit rollout** from a factory: doors, the unit emerging, a beat of it settling on its drive, then it accepts orders. This one beat does enormous work for making production feel physical.

### Architecture

- `ui_anim.gd` gains `count_to` (numeric roll for resources), `bar_fill`, `marker_place`, `marker_expire`.
- A `WorldMarkers` service owning all ground-projected UI so markers are pooled rather than instanced per order.
- Animation state on `unit.gd` driven by order state, not by physics velocity — this is what enforces the §5 rule structurally rather than by discipline.

### Assets

| Tool | Asset |
|---|---|
| Blender | Scaffold geometry per building footprint; factory door rig; per-locomotion deploy/undeploy where applicable; turret traverse and elevation rigs; muzzle-recoil action per weapon class |
| GIMP | Ground-decal textures: selection bracket, waypoint stamp, rally dash, range ring, arc wedge, build-progress ring |
| Inkscape | Damage-number type treatment, marker glyph set |
| Audacity | Covered by Phase 3's construction and mechanical groups |

### Done when

- Every order produces a visible world marker with a matching sound.
- Construction reads as assembly; rollout has its settle beat.
- Selection brackets conform to terrain.
- No animation curve reveals unit mass.

---

## Phase 9 — Accessibility and options depth

**Segment:** making the game playable by more people.
**Fixes:** F28.
**Depends on:** Phases 0, 1, 2, 5.

### Interaction design

**Colourblind provision is not optional here**, because the design system deliberately leans on four signal colours and two of them are red and green — the exact pair most commonly confused. Three mitigations, all needed:

1. **Shape redundancy.** Every signal-coloured state also carries a shape: hazard gets a chevron, alert gets a cross, go gets a check, info gets a dot. This is the strongest of the three and helps everyone.
2. **Palette variants** for deuteranopia, protanopia and tritanopia, swapping `SIGNAL_ALERT` and `SIGNAL_GO` to a blue/orange pair. Because everything reads from `ui_tokens.gd`, this is a token swap and a theme rebuild — the architecture already supports it, which is a real dividend of the token work.
3. **Team-colour independence.** `CORE_DESIGN_LANGUAGE.md` §4.2 already flags the team-colour problem as real and unsolved. A separate low-saturation team marker layered over faction paint solves both that and colourblind team identification.

**Everything else:**

| Provision | Detail |
|---|---|
| UI scale | 80% / 100% / 125% / 150%, applied via theme scale, verified by `ui_audit.gd` for overflow at every step |
| Reduced motion | Disables `hover_lift`, `ring_pop`, `shake`, `stagger_in`; keeps functional transitions. Motion tokens go to near-zero rather than animations being branched around |
| Captions | For radio chatter and alerts — required, since §6.2 puts real tonal weight on the voice channel |
| Hold vs toggle | For every modal input: drag-select, camera rotate, attack-move arming |
| Input timing | Adjustable double-tap window, no timing-critical input anywhere |
| Pause anywhere | Already delivered by Phase 0; confirm it works in every mode |
| Contrast | A high-contrast theme variant, again as a token swap |

### Architecture

- `ui_tokens.gd` palette constants become a swappable profile, resolved once at theme build. `build_ui_theme.gd` emits one `.tres` per profile; `SettingsService` selects.
- `ui_audit.gd` extended: run every screen at every UI scale and every palette, assert no overflow and no offscreen control.

### Assets

Inkscape: the four shape-redundancy marks, caption-frame styling, high-contrast icon variants where the standard stroke weight fails.

### Done when

- Three colourblind palettes plus high-contrast ship and are verified by the audit tool.
- Every signal state carries a shape as well as a colour.
- All four UI scales pass overflow audit on all ten screens.
- Reduced motion is honoured everywhere.
- Radio and alerts are captioned.

---

## Phase 10 — Enforcement

**Segment:** the tooling that keeps all of the above from decaying.
**Fixes:** F29 (completes), F30.

Small phase, high leverage. Every previous phase adds a rule; this is what makes the rules survive contact with future changes.

| Check | Enforces |
|---|---|
| Screen smoke test (Phase 0) in `SUITE_ORDER` | Every scene survives `_ready()` |
| Token literal scan | No colour literal in a screen script that is not in `ui_tokens.gd` — with the documented state-indicator exceptions allowlisted by file and line |
| Emoji/dingbat scan (F30) | The standing rule, currently claimed and unenforced. `tools/strip_ui_glyphs.py` exists; make it a check rather than a fixer |
| Binding-label scan | No hardcoded key letter in any user-facing string; all must come from `InputService.binding_label()` |
| Audit matrix | `ui_audit.gd` across screens × UI scales × palettes |
| Material layer check | No L0 texture used above L1; no phosphor variation on static text |
| Feedback coverage | Every `Button` in a screen tree has been through `UIFeedback.wire()` |
| Tutorial table integrity | Extended to all three tracks |
| Placard consistency | `SpecPlacard`'s four detail levels render the same field set in the same order |

---

# Part V — Sequencing, risk, and open decisions

## Sequencing

```
Phase 0  Foundations ───┬──────────────────────────────────────────┐
                        │                                          │
Phase 1  Identity ──────┼───┬──────┬───────┬──────────┐            │
                        │   │      │       │          │            │
Phase 2  Menus ─────────┘   │      │       │          │            │
                            │      │       │          │            │
Phase 3  Sound ─────────────┘      │       │          │            │
                                   │       │          │            │
Phase 4  Design Lab ───────────────┴───┬───┤          │            │
                                       │   │          │            │
Phase 5  Battle ───────────────────────┴───┼──────────┤            │
                                           │          │            │
Phase 6  Pre/post-match ───────────────────┘          │            │
                                                      │            │
Phase 7  Onboarding ──────────────────────────────────┘            │
                                                                   │
Phase 8  Motion ───────────────────────────────────────────────────┤
Phase 9  Accessibility ────────────────────────────────────────────┤
Phase 10 Enforcement ──────────────────────────────────────────────┘
```

**Phase 0 must go first and must go alone.** It touches eight files' input handling and every subsequent phase assumes it. Landing it mixed with anything else makes the regression surface impossible to reason about.

**Phase 1 and Phase 3 can run in parallel with anything** — they are largely asset authoring against a stable interface.

**Phase 7 must go last of the content phases.** Writing a tutorial for an interface you are about to redesign is the most reliable way to write it twice.

## Risks

| Risk | Mitigation |
|---|---|
| **The input migration breaks the 211-suite run.** `rts_camera.gd` and `module_placer.gd` are both exercised by existing suites | Migrate one file per commit, full suite between each. The camera is the risky one |
| **The workbench layer becomes visual noise.** The single most likely way this plan makes the game worse | The layer discipline rule in §8 is load-bearing: L0 at the edges only, never under text, never above 25% where it meets a panel. Enforce in Phase 10 |
| **Vocalised ordnance does not land.** `CORE_DESIGN_LANGUAGE.md` §7.5 already flags the tonal risk | Prototype exactly one weapon, playtest, then decide. That instruction is already written down; honour it |
| **`SpecPlacard` becomes a god-widget** serving four screens badly | Four explicit detail levels with a fixed field set per level, tested. If a fifth caller wants a fifth level, that is the signal to split |
| **Phase 4 destabilises the Lab.** `stat_calculator.gd` is 3036 lines and `module_placer.gd` owns a golden fixture | Extract `DesignVerdict` first (pure, testable, zero scene deps), then `LabDocument`, then split the rail. The `suite_base.gd` locomotion fixture must not move; any intentional change gets its own commit with explanation, per the standing rule |
| **Scope.** This is a large plan | Every phase ships independently and improves the game on its own. Phases 0, 2 and 5 alone would transform it |

## Open decisions

These need answers and are not mine to make:

1. ~~**Which battle implementation ships (F8)?**~~ — **resolved by investigation.** There is only one: `battle/match_director.gd` behind `Battle.tscn`. The legacy `skirmish.gd` was already retired. Phase 5 targets it unambiguously, and `SelectionService` already emits `selection_changed(units)` (`battle/orders/selection_service.gd:39`), so the new selection panel is a pure subscriber with no service extraction needed.
2. **Font licensing (F27).** Still open from `UI_IMPLEMENTATION_PLAN.md`. Phase 1 replaces the stencil face on tonal grounds anyway — worth resolving both at once.
3. **How far does Records go?** A per-design service record is cheap and high-value. A full campaign meta-progression is a different game. Phase 6 assumes the former.
4. **Voice talent for the vocalisations and radio.** `CORE_DESIGN_LANGUAGE.md` §6.2 asks for "a person doing the sound effect sincerely." That is a casting decision, and the radio voice in particular sets the game's tone more than any visual asset will.
5. **Does the tilt-shift reach the battle camera (§7.1, §7.2)?** Not strictly a UI question, but Phase 0's Settings screen needs to know whether there is a slider for it.

---

# Appendix — Master asset register

Counts are estimates for scoping, not commitments.

| Tool | Category | Count | Phases |
|---|---|---|---|
| **Inkscape** | Command glyphs | 24 | 1, 5 |
| | Analysis / view-mode glyphs | 13 | 1, 4 |
| | Damage-class + locomotion glyphs | 21 | 1 |
| | Hazard decals and placards | 12 | 1 |
| | Kit pictograms (L4) | 10 | 1, 7 |
| | Cursors | 6 | 1, 5 |
| | Wordmark and mark lockups | 4 | 1 |
| | Control chrome (sliders, tabs, keycaps) | 12 | 0 |
| | Command-card cell states | 5 | 5 |
| | Report stamps and lineage marks | 8 | 6 |
| | Shape-redundancy marks | 4 | 9 |
| **Blender** | Machined hardware sprite sheet | ~10 | 1 |
| | CRT bezel 9-slice | 1 | 1 |
| | Sprue frame render | 2 | 1 |
| | Turntable base + Lab platform | 2 | 1, 4 |
| | Boot-sequence prop | 1 | 1 |
| | Command-card bezel | 1 | 5 |
| | Map hero renders | 1 per map | 6 |
| | Exploded-view instruction renders | ~6 | 7 |
| | Scaffold / door / traverse / recoil rigs | ~12 | 8 |
| **GIMP + `generate_ui_plates.py`** | L0 workbench fields | 5 | 1 |
| | L0 dressing cutouts | ~12 | 1 |
| | L3 placard plates (9-slice, 4 states) | 16 | 1 |
| | L2 phosphor substrate + scanline LUT | 3 | 1 |
| | Ground decals | ~8 | 8 |
| | Kit-box card frames | ~4 | 6 |
| | Instruction paper stock | 3 | 7 |
| **Audacity** | UI mechanisms | ~20 | 0, 2, 4 |
| | Radio and alerts | ~12 | 3, 5 |
| | Ordnance vocalisations | ~40 | 3 |
| | Mechanical (sincere) | ~25 | 3 |
| | Impact and destruction | ~15 | 3 |
| | Construction | ~10 | 3 |
| | Ambience | ~9 | 3 |
| | Music | ~7 | 3 |
| **AI-generated** | L0 photographic references and textures | 6 | 1 |
| | Instruction-sheet layout reference | 1 | 7 |
| | Kit-box art references | ~4 | 6 |

**A note on the AI-generated set.** Use it for the L0 photographic layer and for reference, not for anything that must be consistent across many instances. Glyphs, plates and anything 9-sliced should stay procedural or vector — the existing `generate_ui_plates.py` and `generate_icons.py` pipelines are reproducible and diff-friendly, and that property is worth more than the time an image model saves.
