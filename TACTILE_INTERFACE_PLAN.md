# Kitbash Command — Tactile Interface Programme

_A phased implementation plan for the interface, derived from three research
documents at the repo root and from a decision session with Chris on 2026-08-13._
_Written against the working tree at `0de6fd6` plus uncommitted changes._

---

## How to read this document

This plan is written to be executed by a coding agent working unattended. It is
organised so that any phase can be picked up cold:

- **Part 0** is the standing rules. Read it before touching anything, every session.
- **Part 1** is the decision register. These are settled. Do not re-litigate them,
  do not "improve" on them, and do not silently substitute a different approach
  because one looks easier once you are in the code. If a decision turns out to be
  unimplementable as stated, stop and write the reason into Part 6 rather than
  picking an alternative.
- **Part 2** is verified current state. Everything asserted there was read in the
  tree, not remembered. Do not rebuild anything listed as built.
- **Part 3** is the target architecture — the new modules and their boundaries.
- **Part 4** is the phases. Each is independently shippable and has an explicit
  done-when list.
- **Part 5** is the toolchain with exact commands.
- **Part 6** is sequencing, risk and the residual open items.

**What this supersedes.** `UX_REDESIGN_PLAN.md` (deleted at `0de6fd6`, recoverable
via `git show 0de6fd6:UX_REDESIGN_PLAN.md`). Its Phase 0 (InputMap, InputService,
SettingsService, SystemLayer) and much of its Phase 1 landed and are recorded as
built in Part 2. Its unbuilt phases are absorbed here, re-scoped against the three
research documents. `prototype/docs/UI_STYLE_GUIDE.md` and
`prototype/docs/UI_IMPLEMENTATION_PLAN.md` remain authoritative for tokens,
materials, type, elevation and motion — **this plan extends them and never
contradicts them.** Where this plan adds a material or a variation, it is added
through `tools/build_ui_theme.gd`, never inline.

**Source documents.** Three research briefs at the repo root:

| File | Subject | Note |
|---|---|---|
| `UIUX Design Paradigms.txt` | Fitts/Steering/CD-gain, marking menus, gizmo ergonomics, RTS command-card canon, cross-pollination | The interaction spine of this plan |
| `New Text Document.txt` | "Architecting Tactile, Diegetic 3D Interfaces in Godot 4.7" | Misnamed. This is the tactile-interface brief |
| `Godot_4.7_procedural_research.txt` | Procedural materials, anti-flatness, POM, triplanar, PLU/AgX/SDFGI | Half of it already landed — see Part 2 |
| `Tactile, Diegetic 3D Interfaces in Godot 4.7.txt` | **0 bytes.** A failed save. Its content is `New Text Document.txt` | Delete it, or rename `New Text Document.txt` over it |

---

# Part 0 — Standing rules

These are not negotiable and they apply to every phase.

### 0.1 Branch and commit discipline

- **One branch per phase**, named `ui/phase-NN-slug` (e.g. `ui/phase-01-prop-stage`).
- Small commits inside the branch. Each commit must leave the tree parsing.
- **`./run_tests.ps1` must be green before every commit.** Not before every push —
  before every commit. The suite is slow; that is the price of a legible
  regression surface, and the old plan's post-mortem on the input migration is
  the reason this rule exists.
- Merge to `master` only when the phase's **Done when** list is fully satisfied.
- Chris works this repo concurrently. Never assume the working tree is yours.
  `git status` output that you did not create belongs to him — do not revert,
  stash or commit it.

### 0.2 Verification commands

```bash
cd prototype && ./run_tests.ps1
```

That wrapper reimports assets first. Do **not** run `--headless --script run_tests.gd`
directly — the `.godot` import cache is gitignored, goes stale whenever a new
autoload or `class_name` lands, and the failure presents as a misleading
`Identifier "X" not declared`.

For a fast targeted parse check after a bulk edit:

```bash
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/parse_check_some.gd --quit --path .
```

Do **not** use `tools/compile_check_all.gd`. It loads 200+ interdependent scripts
with `CACHE_MODE_IGNORE` and has been observed running 20+ minutes without
finishing.

`--quit` and `--path .` are not optional on a headless run; without them the
process finishes its work and never exits. Godot block-buffers stdout when piped,
so a direct `--script` run shows nothing until it terminates.

### 0.3 Things that must not move

- **`SUITE_ORDER` in `run_tests.gd` is pinned** because several navmesh/Recast
  suites flake depending on what ran before them. Append; never reorder.
- **The golden locomotion fixture in `tests/suite_base.gd`** is frozen. Any
  intentional placement change gets its own commit with an explanation. This plan
  should not touch it at all — if a change here moves it, you have made a mistake.
- **`.tscn` files must contain no comments.** Godot's text scene format does not
  support them; a `#` inside a `[node]` block is a hard parse error that took out
  Battle.tscn and cascaded into every headless suite. Reasoning goes in
  `prototype/docs/RENDER_SETTINGS.md`.
- **No theme overrides inline in screen scripts** for anything that should be
  globally consistent. A local override beats the theme, so an inline style
  actively holds the design system out of that control. Add a variation to
  `tools/build_ui_theme.gd` and rebuild.
- **Nothing re-derives stats.** `DesignStats.analyze()` makes the same calls
  `unit.gd` makes. `stat_calculator.gd` has twice had to delete a local
  re-derivation that drifted. Widgets format; they do not compute.
- **No emoji or dingbats in UI text.** Box-drawing and arrows are permitted as
  technical notation. This is currently unenforced — Phase 12 enforces it.

### 0.4 Determinism

Every generator in `tools/` takes a seed and must produce byte-identical output on
a rerun, or each regeneration becomes a multi-megabyte binary diff. This already
holds for `generate_ui_plates.py` and the audio pipeline. It must hold for
everything this plan adds.

**Specific trap for Phase 2:** Python's built-in `hash()` is salted per process
unless `PYTHONHASHSEED` is set. Never use it to seed a per-prop texture. Use
`zlib.crc32(prop_id.encode("utf-8"))` or `hashlib.sha256`, both of which are
stable across runs, platforms and interpreter versions.

### 0.5 The layer discipline rule

The interface has five material registers. **Any given control belongs to exactly
one.** A phosphor readout does not get a stamped label on the glass — the label is
stamped into the equipment bezel around it. The workbench layer never appears
above the equipment layer. Annotation only ever draws on top, and only while
teaching.

| Layer | Register | Status |
|---|---|---|
| **L0 Workbench** | Hobby desk — cutting mat, cardboard, kraft, cork, chipboard | Assets exist, unregistered. **Phase 4** |
| **L1 Equipment** | Cold-war hardware — powdercoat, steel, bakelite, canvas, carbon, fiberglass, toolbox | Built |
| **L2 Phosphor** | CRT — amber (Lab) and green (battle) | Built (`PhosphorPanel`, `phosphor_display.gdshader`) |
| **L3 Placard** | Stamped/engraved — dymo, engraved alu, stamped steel, hazard chevron | Built (`ui_stamp.gd`, `ui_stamped_label.gd`, `ui_toolbox_plate.gd`) |
| **L4 Annotation** | Instruction booklet — pencil, marker, exploded views | Not built. Out of scope for this plan |

---

# Part 1 — Decision register

Settled with Chris, 2026-08-13. **Locked.**

| # | Decision | Consequence |
|---|---|---|
| **D1** | **Hybrid diegetic, weighted toward tactile controls.** Buttons are a *reused mesh* with *unique textures per button*. No 3D bureau room, no camera-flythrough menus. | Phases 1–3. This is not new architecture — `ui_stamped_button.gd` already does exactly this with `ui_push_button.glb`; its own header names the HD texture pass as an unfinished directive. This plan finishes it and fixes how it renders. |
| **D2** | **One shared 3D UI viewport per screen**, not one per button. | Phase 1. The largest architectural item in the plan. |
| **D3** | **Button textures: hybrid.** Procedural per-prop base for the long tail, hand-authored maps for hero controls. | Phases 2 and 3. |
| **D4** | **Command card is the primary battle command surface**; marking menu is the expert overlay. | Phases 7 and 8. |
| **D5** | **WASD and QE stay camera-only** (pan and rotate). Bindable command keys are the number row, `RFGT`, `ZXCV`. Play style is camera + mouse first. | Phase 8. **This resolves a live collision** — see Part 2.4. |
| **D6** | **Command card is 3 rows x 4 columns.** Row 1 = `R F G T`, row 2 = `Z X C V`, row 3 = mouse-only overflow. Number row stays control groups. | Phase 8. |
| **D7** | **L0 workbench ships everywhere out-of-match.** Menu, Lab, Library, Records, Match/Operations setup. In-match stays pure equipment. | Phase 4. |
| **D8** | **Selection aggregates by blueprint/design.** "12 x Wasp Mk II, 4 x Bulwark", each with the design's real rendered silhouette. Ctrl+Shift+click drops a whole design from selection. | Phase 9. |
| **D9** | **Marking menu is a full stroke menu** — press, drag, release, with delayed reveal (~200 ms). A fast flick never draws the ring. Shared widget across Lab and battle. | Phase 7. |
| **D10** | **The hull gets no grab handles.** Gizmo handles are for modules only. | Phase 5. |
| **D11** | **Hull scale becomes fixed size classes.** Continuous hull scaling is removed. | Phase 5. All bundled designs already carry `hull_scale = 1.0`, so this needs no schema change and no blueprint version bump. |
| **D12** | **Gizmo ergonomics: hollow negative arrows, precision modifier, dynamic planar handles.** Infinite-axis projection is **not** adopted. | Phase 5. |
| **D13** | **Module action ring: centred on the module, inner radius sized to clear its projected silhouette, tracks the camera, wedge order fixed (wedge 0 at 12 o'clock), persistent until the module is deselected.** | Phase 6. Replaces today's haphazard behaviour in `tweak_callout_manager.gd`. |
| **D14** | **All four remaining procedural-material techniques are scheduled**: POM/deep parallax on UI hardware, PCG3D integer hashing, world-normal dust/grime mixing, dFdx/dFdy normal reconstruction. | Phases 2 and 3. |
| **D15** | **Lab cross-pollination: both.** Aggregated module selection with sub-group deselect, *and* a Lab command card sharing the battle card's geometry. | Phase 10. |
| **D16** | **Toolchain available:** Blender 5.2, Python 3 with numpy/scipy/Pillow, Inkscape CLI, GIMP CLI. | Part 5. |
| **D17** | **Branch per phase; `run_tests.ps1` green before every commit.** | Part 0.1. |

---

# Part 2 — Verified current state

Everything below was read in the tree. Do not rebuild any of it.

### 2.1 Built and correct — extend, never replace

| System | Files | Note |
|---|---|---|
| Design tokens | `scripts/ui_tokens.gd` | Palette, type scale, 4 px grid, elevation tiers, motion timings, **and an L2 phosphor block**. Reasoning recorded inline |
| Theme builder + theme | `tools/build_ui_theme.gd`, `resources/bomber_theme.tres` | 23 registered variations. One rebuild repaints the game |
| Runtime material applicator | `scripts/ui_theme.gd` | `MATERIALS` at line 28 is the registration list |
| Plate/field pipeline | `tools/generate_ui_plates.py` | Procedural, fixed seed. Plates are 128x128 RGBA: 96x96 body inside a 16 px transparent pad carrying the baked elevation shadow. 9-slice frame is `MARGIN + PAD = 28` |
| Coupled feedback | `scripts/ui_feedback.gd` | `wire(ctrl, role)` binds audio and motion in one call so they cannot drift |
| Scene routing | `scripts/scene_router.gd` | Fade on an autoload-owned overlay, warm-load lists, deploy gate |
| Composable chrome | `ui_dock.gd`, `ui_toolbox.gd`, `ui_shell.gd`, `ui_flyout.gd` | Real reusable widgets. The dock persists layout to `user://ui_layout.cfg` |
| L2 phosphor | `scripts/ui/phosphor_panel.gd`, `shaders/phosphor_display.gdshader` | Amber = Lab, green = battle. Honours `reduced_motion` by killing only the flicker |
| L3 placard | `ui_stamp.gd`, `ui_stamped_label.gd`, `ui_toolbox_plate.gd` | Stamped/engraved surfaces |
| Input foundation | `scripts/core/input_service.gd` (autoload), `[input]` in `project.godot` | 46 actions defined. Rebinding infrastructure present |
| Settings | `scripts/core/settings_service.gd`, `scripts/ui/settings_panel.gd` | Full: display, audio (4 buses), controls, accessibility (`reduced_motion`, `ui_scale`, `colourblind_mode`, `captions`) |
| System layer | `scripts/ui/system_layer.gd` (autoload) | Escape stack, pause, settings, quit |
| Spec placard | `scripts/ui/spec_placard.gd` | **One** spec widget, four fixed detail levels (FRONT_DESK / LAB / BATTLE / RECORD). Already wired to battle selection at `battle_hud.gd:225` |
| 3D UI props | `scripts/ui/mesh_icon.gd`, `scripts/ui_stamped_button.gd`, `tools/blender/build_ui_props.py` | Shared meshes, per-variant materials. `MeshIcon` already uses `UPDATE_ONCE` |
| Render pipeline | `Battle.tscn` etc., `prototype/docs/RENDER_SETTINGS.md` | **AgX tonemapping, SDFGI, SSIL, physical light units, tilt-shift DOF all landed** in `b2340f4` |
| Shader technique | `shaders/hull_faction_material.gdshader` | Triplanar with correct tangent reconstruction |
| Shader technique | `shaders/terrain_ground.gdshader` | Two-layer domain warping, quintic Hermite interpolation |

**Consequence for the research docs:** roughly half of `Godot_4.7_procedural_research.txt`
is already implemented. Do not re-derive AgX, SDFGI, SSIL, PLU, triplanar
reconstruction or domain warping. What remains of that document is D14.

### 2.2 Built but stub-quality — rewrite in place

| File | State |
|---|---|
| `scripts/ui/command_card.gd` | 71 lines. A 3x3 grid with **5 hardcoded buttons**, no icons, no hotkey display, no action registry, no production integration. Fires `InputEventAction` at the global input map |
| `scripts/battle/alert_service.gd` | Post/expire/jump only. No minimap ping, no audio routing, no edge-marker wiring |
| `scripts/ui_radial_menu.gd` | A genuine, well-drawn instrument dial — but click-select only. No stroke, no delayed reveal, no eyes-free path. Used by `tweak_callout_manager.gd` (Lab) and `production_hud.gd` (battle) |

### 2.3 Authored but dead

`assets/textures/ui/field_cutting_mat.png`, `field_cardboard.png`, `field_kraft.png`,
`field_chipboard.png`, `field_cork.png` exist on disk. `ui_theme.gd:28` registers
only `["powdercoat", "steel", "bakelite", "canvas", "carbon", "fiberglass", "toolbox"]`.
**The entire L0 workbench layer is unwired.** These are fields only (512x512 RGB) with
no plates, which is correct — L0 is a backdrop register, not a control register.

### 2.4 Live defects this plan fixes

| Ref | Defect | Fixed by |
|---|---|---|
| **X1** | **`cmd_attack_move` and `cam_pan_left` are both bound to physical key A. `cmd_stop` and `cam_pan_down` are both bound to physical key S.** Verified in `project.godot` `[input]`: `cam_pan_left` and `cmd_attack_move` both carry `physical_keycode: 65`; `cam_pan_down` and `cmd_stop` both carry `physical_keycode: 83` | Phase 8 (D5) |
| **X2** | `StampedButton` gives every button its own `SubViewport` on `UPDATE_WHEN_VISIBLE` — a full 3D scene, camera and light per button, re-rendering every frame. `MeshIcon` chose `UPDATE_ONCE` for exactly this reason and says so in its header | Phase 1 (D2) |
| **X3** | The module tweak ring is created fresh per selection in `tweak_callout_manager.gd:60` and lerp-tracks the module's unprojected origin, with an inner radius that has no relationship to the module's size — so it lands over the part it is meant to act on | Phase 6 (D13) |
| **X4** | `gizmo_3d.gd` implements none of the five documented gizmo ergonomics, and applies handles to the Hull (`_apply_scale_to_node`'s Hull branch) | Phase 5 (D10, D12) |
| **X5** | `terrain_ground.gdshader:82` uses `fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123)`. Float sine hashing loses precision at large coordinates and is not bit-exact across GPUs | Phase 2 (D14) |
| **X6** | No selection panel. `SelectionService` emits `selection_changed(units)` at `selection_service.gd:39`; only `battle_hud.gd` and the stub command card subscribe, and neither aggregates | Phase 9 (D8) |
| **X7** | Attack-move arming is text-only. `match_director.gd:3175` flashes `"ATTACK-MOVE: RIGHT-CLICK A DESTINATION"` into a hint label. `assets/cursors/cursor_attack.png` exists and `cursor_manager.gd` has a working `set_cursor(type)` — the cursor simply never changes | Phase 8 |

**X1 is the only binding collision in the project.** Verified by extracting every
`[input]` action with its physical keycodes and modifier flags:

- `cmd_attack_move` = A (bare) collides with `cam_pan_left` = A
- `cmd_stop` = S (bare) collides with `cam_pan_down` = S
- **Every `lab_*` action that shares a key is modifier-guarded** — `lab_duplicate`
  is Ctrl+D, `lab_save` is Ctrl+S, `lab_undo` Ctrl+Z, `lab_redo` Ctrl+Y and
  Ctrl+Shift+Z. `lab_rotate` (R) and `lab_mirror` (M) are bare but do not collide,
  because `designer_camera.gd` drives the Lab camera from mouse buttons only and
  binds no `cam_*` key. **There is no Lab collision. Do not "fix" one.**

### 2.4a Two findings from the deleted plan that are now stale

Both were true when `UX_REDESIGN_PLAN.md` was written and have since been fixed.
They are recorded here so nobody schedules the work twice.

- **The permanent on-screen keyboard cheat sheet is gone.** `match_director.gd` no
  longer draws a fixed two-line keymap. The only survivor is the transient arming
  flash at `:3175`, which is X7 above and is a different problem.
- **The DEBUG button is gone from the shipping HUD.** `battle_hud.gd` contains no
  DEBUG button. `admin_menu` is now constructed behind
  `enable_admin_menu = rule_set.enable_admin_menu and is_debug`
  (`match_director.gd:3108`), so the cheat menu is already debug-gated.

### 2.5 Carried forward from `UI_IMPLEMENTATION_PLAN.md` Priority 7

1. Rename the `bakelite` material key — it is a misnomer since the surface was
   re-authored as moulded ABS. Touches 4 PNG filenames, `build_ui_theme.gd`,
   `ui_theme.gd`'s `MATERIALS`/`MATERIAL_DEFAULTS`, `generate_ui_plates.py` and the
   style guide. **Folded into Phase 4** as a mechanical sweep in its own commit.
2. Restructure the telemetry rail into toolbox tiers. **Folded into Phase 10.**
3. Promote `tools/probe_scene_loads.gd` into `SUITE_ORDER`. **Folded into Phase 12.**
4. `ui_audit.gd` does not enforce the no-emoji rule. **Folded into Phase 12.**

### 2.6 In-flight work — route around it

Chris has uncommitted changes to `parts_menu.gd` (-/+339 lines), `lab_toolbar.gd`
(+117), `module_placer.gd` (+144), `ui_theme.gd`, `generate_ui_plates.py` (+117,
adding the `toolbox` material) and several scenes. **Phases 5, 6 and 10 touch these
files.** Before starting any of them, `git pull` / re-read the current file rather
than working from this document's line references.

---

# Part 3 — Target architecture

### 3.1 New modules

| Module | File | Owns | Phase |
|---|---|---|---|
| `UIPropStage` | `scripts/ui/ui_prop_stage.gd` | One SubViewport per screen holding every 3D UI prop. Ortho camera, shared light rig, dirty-driven rendering, control-rect to mesh-transform mapping | 1 |
| `UIPropRegistry` | `scripts/ui/ui_prop_registry.gd` | Prop id to (mesh, material set) lookup. The single place that knows a button id maps to `ui_push_button.glb` plus `props/btn_deploy_*.png` | 1 |
| `MarkingMenu` | `scripts/ui/marking_menu.gd` | Press-drag-release stroke menu with delayed reveal. Distinct from `UIRadialMenu` | 7 |
| `ModuleActionRing` | `scripts/ui/module_action_ring.gd` | Persistent silhouette-sized ring around a selected Lab module | 6 |
| `CommandRegistry` | `scripts/battle/orders/command_registry.gd` | The action set for a selection: id, label, icon, hotkey action, enabled predicate. Feeds the command card, the marking menu and the tutorial identically | 8 |
| `SelectionPanel` | `scripts/battle/hud/selection_panel.gd` | Design-aggregated portraits with counts and sub-group operations | 9 |
| `PointerGain` | `scripts/core/pointer_gain.gd` | The speed-dependent C/D transfer function, shared by both cameras and every drag manipulator | 11 |

### 3.2 The UIPropStage contract

This is the load-bearing idea of Phases 1 to 3, so it is stated precisely.

**One `SubViewport` per screen.** Inside it:

- One `Camera3D` in **orthographic** projection, `size` set to the viewport's pixel
  height, positioned on +Z looking down -Z. This makes the mapping from a
  `Control`'s screen rect to a world transform a direct affine one:

  ```
  world_x = (rect.position.x + rect.size.x * 0.5) - viewport_size.x * 0.5
  world_y = -((rect.position.y + rect.size.y * 0.5) - viewport_size.y * 0.5)
  world_z = elevation_tier_offset
  ```

  Perspective was rejected: it breaks the 1:1 rect mapping and would force every
  layout to be projected, which is the rewrite D2 is trying to avoid.

- One `DirectionalLight3D` key **from the top-left**, plus a dim fill. The key
  direction is not arbitrary: every plate PNG in `assets/textures/ui/` is authored
  with its bevel lit from the top-left and its shadow offset straight down
  (`ui_tokens.gd`, elevation block). A 3D light that disagrees with the 2D bevels
  makes both read as texture noise.

- One `WorldEnvironment`, transparent background, **AgX** tonemapping. Note that
  `MeshIcon` currently uses ACES — unify on AgX so the chrome matches the game's
  own pipeline after `b2340f4`.

**Controls keep everything they own.** Layout, hit-testing, focus order, keyboard
navigation and every existing test that clicks a `Button` stay with the native
`Control`. The stage only draws. `StampedButton` already blanks its own theme
styleboxes in `_init` so the theme's material does not double-paint; keep that.

**Rendering is dirty-driven.** `render_target_update_mode = UPDATE_ONCE`, with the
stage calling `request_render()` when any registered prop changes state, when a
control resizes, or when the viewport resizes. A static screen costs nothing.

**Elevation becomes real.** Props sit at a z-offset per elevation tier and the
shared key light casts real contact shadows. For any control hosted on the stage,
**disable the baked plate shadow** — the transparent pad in the plate PNG must not
double up with a real cast shadow.

### 3.3 The depth trap (read before Phase 3)

An orthographic camera looking straight down -Z at a flat face produces a constant
view vector perpendicular to that face. **Parallax occlusion mapping contributes
nothing there** — the raymarch offset is zero. This is not a reason to abandon POM;
it is a constraint on where POM goes.

The resolution: the shared button mesh carries **real geometric relief** — a
chamfered rim and a dished top. Those sloped regions present genuine grazing angles
to the ortho camera, and that is where POM earns its cost: engraved legends, knurl,
recessed screw heads and part-number stamps on the chamfer and dish. The flat
centre of the dish is where the enamel legend goes and needs no parallax.

Do not "fix" this by tilting the camera. That reintroduces the projection problem
D2 exists to avoid. If a specific prop needs more grazing angle, rotate **the prop's
mesh**, not the camera.

---

# Part 4 — The phases

Twelve phases. Each ships independently. Dependencies are stated explicitly; where
none is stated, the phase can move.

---

## Phase 1 — UIPropStage

**Goal.** Replace per-button SubViewports with one shared 3D UI viewport per screen.

**Depends on.** Nothing.

**Files.**
- New: `scripts/ui/ui_prop_stage.gd`, `scripts/ui/ui_prop_registry.gd`
- Rewrite: `scripts/ui_stamped_button.gd` (composition changes; public API must not)
- Rewrite: `scripts/ui/mesh_icon.gd` (becomes a stage client)
- Touch: every screen that hosts a `StampedButton` or `MeshIcon` — currently
  `lab_toolbar.gd`, `settings_panel.gd`, plus the out-of-match screens listed in
  `ui_stamped_button.gd`'s header

**Method.**

1. Build `UIPropStage` as a `Control` that creates and owns its `SubViewport`,
   camera, light rig and environment per Part 3.2. It is added once per screen,
   typically by `UIShell.backdrop()` or the screen's `_ready()`.
2. API surface, deliberately small:
   - `attach(control: Control, prop_id: String) -> int` — returns a handle
   - `detach(handle: int) -> void`
   - `set_prop_state(handle: int, state: String) -> void` — `normal`/`hover`/`pressed`/`disabled`
   - `set_prop_variant(handle: int, variant: String) -> void`
   - `request_render() -> void`
3. The stage connects to each attached control's `item_rect_changed` and updates
   that prop's transform, then marks dirty. It does **not** poll in `_process`.
4. `UIPropRegistry` maps `prop_id` to `{mesh_path, material_set}`. In Phase 1 the
   material set is the existing procedural variant material; Phase 2 replaces it
   with baked per-prop textures without changing this interface.
5. Rewrite `StampedButton` to attach to the nearest ancestor stage instead of
   building its own viewport. **Its public API — `Variant` enum, `MIN_WIDTH`,
   `set_hd_material_override()`, the legend — must not change**, because every
   out-of-match screen calls it.
6. Fallback path: if no `UIPropStage` ancestor exists (headless tests, a screen not
   yet migrated), `StampedButton` falls back to its theme stylebox and logs nothing.
   Headless never rasterizes a viewport, so tests must not depend on the 3D render.

**Tools.** Godot only. No asset work.

**Tests.** New suite `tests/test_ui_prop_stage.gd`, appended to `SUITE_ORDER`:
- rect-to-world mapping is exact at the four viewport corners and at centre
- attach/detach leaves no orphan `MeshInstance3D`
- a state change marks the stage dirty exactly once
- a screen with N buttons creates exactly one `SubViewport`
- `StampedButton` with no stage ancestor still renders and still reports its size

**Done when.**
- No screen creates more than one `SubViewport` for UI props
- `grep -c SubViewport.new` across `scripts/ui*` returns only the stage and the
  legitimate 3D-to-2D thumbnail paths (`blueprint_thumbnail.gd`, `part_thumbnail.gd`,
  `visual_builder.gd`, `main_menu.gd`, `battle_hud.gd`'s vision use)
- A frame-budget probe on the settings screen and the Design Lab toolbar shows the
  stage rendering zero frames while idle
- Full suite green

**Traps.**
- `SubViewportContainer` consumes mouse input based on its `mouse_filter`. The stage's
  container must be `MOUSE_FILTER_IGNORE` or every button underneath goes dead. This
  is the exact failure `New Text Document.txt` describes in its input-routing table.
- Do not give the stage's props both a baked plate shadow and a real cast shadow.

---

## Phase 2 — Procedural prop textures and the hash swap

**Goal.** Every button gets a unique, deterministic, reproducible texture set.

**Depends on.** Phase 1.

**Files.**
- New: `tools/generate_ui_props.py`
- Modify: `tools/generate_ui_plates.py` (share its noise/wear primitives; do not
  duplicate them)
- New assets: `assets/textures/ui/props/<prop_id>_{albedo,orm,height}.png`
- Modify: `shaders/terrain_ground.gdshader`, `shaders/ui_material.gdshader`
- New: `shaders/ui_prop.gdshader`

**Method.**

1. **Per-prop seeding.** `seed = zlib.crc32(prop_id.encode("utf-8"))`. Never
   Python's `hash()` — see Part 0.4.
2. **Outputs per prop**, 256x256 unless a hero prop needs more:
   - `albedo` — body colour, enamel legend field, manufacturer mark
   - `orm` — occlusion in R, roughness in G, metallic in B. Channel packing is what
     both research briefs recommend and it cuts texture fetches by three
   - `height` — the POM heightfield consumed in Phase 3
3. **What varies per prop:** wear pattern and intensity, grime accumulation, the
   angular offset of the machining swirl, screw-head positions on the chamfer,
   part-number stamp position and content. **What does not vary:** the body colour
   family (that comes from `Variant`), the dish geometry (that is the mesh), the
   luminance band. A button must still land in the material luminance stack
   documented in `UI_IMPLEMENTATION_PLAN.md` Priority 2 — control bodies at ~0.154,
   strictly above the panel body they sit on.
4. **Roughness carries the most variation.** A constant roughness value is the
   single largest tell of a synthetic surface; `Godot_4.7_procedural_research.txt`
   is explicit about this. Clamp generated roughness to a floor of 0.02–0.05 to
   avoid GGX singularities under a strong key light.
5. **PCG3D hash swap (X5).** Replace `hash21`'s `fract(sin(...))` in
   `terrain_ground.gdshader` and any float-sine hash in `ui_material.gdshader` with
   an integer PCG hash:

   ```glsl
   uvec3 pcg3d(uvec3 v) {
       v = v * 1664525u + 1013904223u;
       v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
       v ^= v >> 16u;
       v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
       return v;
   }
   ```

   Integer math is bit-exact on every GPU and immune to the coordinate-magnitude
   precision loss that produces blocky dissolve and cross-driver flicker. Verify
   with `tools/check_texture_seam.gd` and by eye at extreme map coordinates.
6. **`ui_prop.gdshader`** is a spatial shader consuming albedo/ORM/height. In this
   phase it is a plain PBR shader; Phase 3 adds the parallax and derivative work.

**Tools.**

```bash
cd prototype && python tools/generate_ui_props.py
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import --quit --path .
```

Rerunning the generator with no source change must produce a zero-line diff.

**Tests.** Extend `tests/test_ui_and_camera.gd`:
- every `prop_id` in `UIPropRegistry` resolves to three existing texture files
- two different prop ids produce different albedo bytes
- the same prop id produces identical bytes across two generator runs (assert on a
  checked-in hash manifest, not by re-running Python from GDScript)

**Done when.**
- Every button in the game has a distinct texture set
- `generate_ui_props.py` is idempotent
- No `fract(sin(` remains in any `.gdshader` under `shaders/`
- Full suite green

---

## Phase 3 — Depth and wear

**Goal.** The button layer stops looking like a render of hardware and starts
looking like hardware.

**Depends on.** Phase 2.

**Files.** `shaders/ui_prop.gdshader`, `tools/blender/build_ui_props.py`,
hero texture assets.

**Method.**

1. **Parallax occlusion mapping.** Raymarch the heightfield in tangent space.
   Interpolate between the sample before and after intersection to kill
   stair-stepping. Scale the layer count from `dot(NORMAL, VIEW)` between a min and
   max. Offset UVs feed *all* subsequent samples — albedo, ORM, normal.
   **Read Part 3.3 first.** POM goes on the chamfer, the dish slope, engraved
   legends, knurl and screw recesses. It does nothing on the flat dish centre and
   should not be paid for there.
2. **POM self-shadowing.** A second raymarch from the intersection point toward the
   key light; if it hits the heightfield before escaping, darken the fragment. This
   is what makes a recessed screw read as recessed rather than as a dark circle.
3. **No silhouette POM.** `discard`-based SPOM is not needed — button silhouettes
   come from the mesh, which has real geometry.
4. **dFdx/dFdy normal reconstruction.** Where wear height is generated in-shader
   rather than sampled, derive the normal from screen-space derivatives instead of
   sampling the noise three times. Cross the derivatives against the vertex normal
   to build the surface gradient and perturb the base normal.
5. **World-normal dust mixing.** `dot(world_normal, vec3(0,1,0))` through a
   `smoothstep` gives an up-facing mask. Blend a dust albedo and a raised roughness
   into up-facing surfaces; blend grime into down-facing crevices. Because the mask
   is computed in world space against the *final* normal (which includes the POM
   perturbation), dust catches on the microscopic ridges rather than sitting as a
   flat overlay — that is the whole point of doing it after POM rather than before.
   Keep dust subtle on interface chrome: this is equipment in service, not
   abandoned equipment.
6. **Hero props (D3).** Hand-author maps for: `DEPLOY`, `SAVE`, `TEST`, `DISCARD`,
   the five production queue headers, and the main-menu destination cards. Model the
   detail in Blender (`build_ui_props.py`), bake albedo/ORM/height, composite in GIMP.
   These load through the same `UIPropRegistry` entry shape as procedural props —
   no call site changes, no second code path.

**Tools.**

```bash
cd prototype && "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender/build_ui_props.py
cd prototype && python tools/generate_ui_props.py
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import --quit --path .
```

**Tests.** Shader compilation is covered by scene-load probes. Add to
`tests/test_ui_and_camera.gd`: every hero prop id resolves to authored (not
generated) assets, and the registry reports which pipeline produced each.

**Done when.**
- A button at the edge of a panel shows visible parallax on its chamfer as the
  layout shifts
- Screws and engraved legends self-shadow against the key light
- Dust reads on up-facing surfaces and recalculates correctly if a prop is rotated
- Hero props are visibly a step above the procedural tail without looking like a
  different material system
- Frame budget on the busiest screen has not regressed measurably from Phase 1

**Traps.**
- POM cost scales with layer count *and* fill rate. The stage renders at UI
  resolution and only when dirty, which is what makes this affordable — do not move
  the stage to continuous rendering to "make it smoother".
- Do not add POM to `ui_material.gdshader` (the 2D canvas_item large-surface
  shader). It has no view vector to march along.

---

## Phase 4 — The L0 workbench layer

**Goal.** The out-of-match interface sits on a hobby desk.

**Depends on.** Nothing. Can run in parallel with 1–3.

**Files.** `scripts/ui_theme.gd`, `tools/build_ui_theme.gd`,
`tools/generate_ui_plates.py`, `scripts/ui_shell.gd`, every out-of-match screen.

**Method.**

1. Register `cutting_mat`, `cardboard`, `kraft`, `cork`, `chipboard` in
   `ui_theme.gd`'s `MATERIALS` (line 28) and give each an entry in
   `MATERIAL_DEFAULTS` (wear/grime/scale/vignette). The fields already exist; no new
   art is required to start.
2. **Field-only, no plates.** L0 is a backdrop register. Do not generate
   `plate_cutting_mat_*.png` — a workbench material on a *control* is a category
   error under the layer discipline rule (Part 0.5).
3. Add `UIShell.workbench(node, material)` alongside the existing `backdrop()`.
   Out-of-match screens call it instead of `backdrop()`. In-match screens keep
   `backdrop()` (steel).
4. **The brightness rule still governs.** `UI_STYLE_GUIDE.md` §3.2: the backdrop is
   the floor of the luminance stack and everything laid on it must sit above it.
   A cutting mat is a mid-green; a kraft field is a mid-tan. Both are *brighter*
   than the steel backdrop they replace, so panel and control luminances must be
   re-checked against them or the equipment layer will sink into the desk. Expect to
   darken the L0 fields' applied brightness rather than to raise the panels.
5. **Dressing, at the edges.** Beyond the field, add sparse dressing cutouts — a
   scalpel, a sprue offcut, a paint-pot ring, a steel rule — as decorative
   `TextureRect`s at `MOUSE_FILTER_IGNORE`, anchored to screen corners. **Never
   under body text, never above the equipment plane.**
6. **Fold in the `bakelite` rename** (Part 2.5 item 1) as a separate commit on this
   branch: 4 PNG filenames, `build_ui_theme.gd`, `ui_theme.gd`, `generate_ui_plates.py`,
   `UI_STYLE_GUIDE.md`. Suggested key: `moulded`.

**Tools.**

```bash
cd prototype && python tools/generate_ui_plates.py
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/build_ui_theme.gd --quit-after 2 --path .
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import --quit --path .
```

**Tests.** Extend `tests/test_ui_and_camera.gd`: every registered material has a
field asset; no L0 material has plate assets; every out-of-match screen calls
`workbench()` and no in-match screen does.

**Done when.**
- All five L0 materials registered and applied out-of-match
- In-match chrome is untouched
- Contrast between the equipment layer and the workbench field has been checked on
  every out-of-match screen
- `bakelite` renamed everywhere, in its own commit
- Full suite green

**Risk.** This is the single most likely way the plan makes the game look worse.
The mitigation is the discipline rule and the contrast check, both of which are
enforced in Phase 12. If a screen looks noisy, the answer is to reduce the field's
applied brightness and drop dressing — not to abandon the layer.

---

## Phase 5 — Lab manipulation: hull, handles, gizmo

**Goal.** Stop the hull being a manipulable object; make module handles usable.

**Depends on.** Nothing. **Conflicts with Chris's in-flight `module_placer.gd`
changes — re-read the file before starting.**

**Files.** `scripts/gizmo_3d.gd`, `scripts/gizmo_handle.gd`,
`scripts/gizmo_rotate_ring.gd`, `scenes/Gizmo3D.tscn`, `scripts/module_placer.gd`,
`scripts/stat_calculator.gd`, `scripts/blueprint_manager.gd`,
`scripts/module_catalog.gd`.

**Method.**

1. **Remove the hull from the gizmo entirely (D10).** The gizmo is attached in
   `_ready()` via `target_module = get_parent()`; make attachment refuse a node named
   `Hull`. Delete the Hull branch of `_apply_scale_to_node()` (roughly
   `gizmo_3d.gd:252–355`) and the `child_start_positions` bookkeeping that exists
   only to serve it.
2. **Fixed hull size classes (D11).** `hull_scale` stays in the blueprint schema and
   stays readable — **do not bump the blueprint version, do not migrate saves.** All
   24 bundled designs already carry `{1.0, 1.0, 1.0}` (verified). What changes:
   - Nothing writes a non-unity `hull_scale` any more
   - `HULL_SCALE_MIN`/`HULL_SCALE_MAX` (`module_catalog.gd:16–17`) become the clamp
     applied on *load* of any legacy blueprint, not on a live control
   - The eight consumers (`auto_weapon.gd:276`, `placement_service.gd:141`,
     `structure.gd:141`, `design_costing.gd:34`, `unit_assembly.gd:142`,
     `blueprint_manager.gd:102/670`, `module_placer.gd`) keep working untouched
   - Size class comes from the hull catalogue entry, as it already does for the
     81-hull roster
3. **Hollow negative arrows (D12).** In `gizmo_handle.gd`, compare the handle's world
   axis against the camera forward each frame the camera moves. When the axis points
   away from the camera, swap the arrowhead material to an unfilled outline. **The
   collision shape does not change** — that is the entire trick: identical hit
   target, instant orientation read, no camera-grinding.
4. **Precision modifier (D12).** Hold the precision modifier during a handle drag to
   scale the cursor-to-value transfer down (start at 5x reduction). Bind a new
   InputMap action `manip_precision` rather than hardcoding a key. This matters here
   more than in a generic 3D tool because these drags write real stat values —
   `gizmo_3d.gd`'s `get_tweak_for_axis()` maps an axis drag to caliber, barrel
   length, lens aperture and so on.
5. **Dynamic planar handles (D12).** Add three planar quads between axis pairs.
   Visibility and hit-box scale with how face-on the plane is to the camera; a plane
   viewed edge-on hides. Route them through `get_tweak_for_axis()` for both
   contributing axes, applying each axis's tweak proportionally.
6. **Not adopted:** infinite axis projection. Chris excluded it.

**Tools.** Godot only.

**Tests.** Extend `tests/test_designer_lab.gd`:
- attaching a gizmo to a node named `Hull` is refused
- `blueprint_manager` round-trips a legacy blueprint with `hull_scale = 1.5` and
  clamps it on load without corrupting geometry
- arrowhead fill state flips when the camera crosses the axis plane, and the
  collision shape's extents are unchanged across that flip
- precision modifier held produces exactly 1/5 the tweak delta of the same drag

**Done when.**
- No manipulator appears on the hull
- No code path writes a non-unity `hull_scale`
- All three adopted ergonomics work
- Locomotion golden fixture unchanged
- Full suite green

**Trap.** `gizmo_3d.gd:363` (`_on_drag_ended`) rebuilds `HullSurface` and re-runs
locomotion layout specifically because a hull scale drag invalidated both. With hull
scaling gone, check whether those calls are still needed for module drags — they are
cheap but not free, and running a full locomotion respawn after every module tweak
would be a regression.

---

## Phase 6 — The module action ring

**Goal.** The Lab's per-module actions appear predictably and never cover the module.

**Depends on.** Phase 5. **Conflicts with in-flight `module_placer.gd` work.**

**Files.** New `scripts/ui/module_action_ring.gd`; modify
`scripts/tweak_callout_manager.gd`, `scripts/ui_radial_menu.gd`.

**Method.**

1. Extract the ring *drawing* from `ui_radial_menu.gd` (the bezel, index ring, ticks,
   wedge dividers, hub and legend plate — roughly lines 241–392) into a shared
   `ring_draw.gd` helper so `ModuleActionRing`, `MarkingMenu` (Phase 7) and the
   production ring all render identically. **The drawing is good; do not redesign it.**
2. **Silhouette-sized inner radius (D13).** On selection, compute the module's
   projected screen-space AABB by unprojecting its 3D bounding box corners. Set
   `RING_INNER` to that AABB's half-diagonal plus a clearance margin, and
   `RING_OUTER` to `RING_INNER + band_width` with a constant band. Recompute on
   camera move, damped so it does not pulse. Clamp to a sane min and max so a tiny
   bolt does not get a 20 px ring and a large hull section does not get one that
   fills the screen.
3. **Fixed wedge order.** Wedge 0 is always at 12 o'clock and a given action always
   occupies the same wedge index for a given module *class*. Do not compact the ring
   when an action is unavailable — draw the wedge disabled. A radial menu whose wedge
   positions shift with context cannot build muscle memory, which is the only reason
   to use one.
4. **Persistent until deselect (D13).** The ring opens on selection and stays. It
   does not close on invoke. Invoking an action updates the ring's enabled states in
   place. It closes on deselection, on the module being deleted, or on Escape.
5. Keep the existing camera tracking and the distance fade (`max_zoom_distance`,
   matched to `TweakCallout`), and keep `_has_point()` limiting input to the annulus —
   without it the ring's bounding square swallows viewport clicks.
6. Keep the hub as a dead zone. With a persistent ring the hub is no longer a cancel
   target, so repurpose it: show the hovered action's legend, and the module
   designation on the plate below, exactly as today.

**Tools.** Godot only.

**Tests.** New suite `tests/test_module_action_ring.gd`:
- inner radius always exceeds the module's projected AABB half-diagonal, over a
  sweep of camera angles and module sizes
- wedge index for a given action id is stable across selections of different modules
  of the same class
- ring survives invoking an action and updates enabled states
- ring frees itself when its target is freed

**Done when.**
- Selecting any module opens a ring that never overlaps it
- The ring persists across actions
- Action direction is stable
- Full suite green

---

## Phase 7 — The marking menu

**Goal.** One stroke-driven menu, shared by the Lab and the battlefield.

**Depends on.** Phase 6 (for the extracted `ring_draw.gd`).

**Files.** New `scripts/ui/marking_menu.gd`; modify `scripts/battle/match_director.gd`,
`scripts/battle/hud/production_hud.gd`.

**Method.**

1. `MarkingMenu` is a **distinct widget** from `UIRadialMenu` and `ModuleActionRing`.
   They share drawing, not behaviour. Do not try to make one widget do all three —
   persistent-and-tracking and transient-and-stroke are opposite lifecycles.
2. **The interaction (D9):**
   - Press the invoke input. Record the origin. Start a reveal timer.
   - If released before `REVEAL_DELAY` (200 ms, a token in `ui_tokens.gd`) **and**
     displacement exceeds `MIN_STROKE` (24 px), commit the wedge matching the stroke
     direction. **The ring is never drawn.** This is the eyes-free expert path and it
     is the entire justification for the widget.
   - If held past `REVEAL_DELAY`, draw the ring with `UIAnim.ring_pop()` — the one
     sanctioned overshoot in the whole interface — centred on the origin.
   - Release inside a wedge commits. Release inside the hub cancels. Release outside
     the outer radius still commits the wedge whose angular sector contains the
     cursor: the target is an infinitely expanding sector, not a bounded rectangle,
     and that unbounded target width is why the mechanism is fast.
3. **Fixed slot count per context.** Always draw the same number of wedges for a
   given context, disabling unavailable ones. Same reasoning as Phase 6 point 3.
4. **Invoke binding.** New InputMap action `marking_menu` (a modifier + mouse button,
   not a bare button — a bare button would fight unit selection and camera drag).
   `InputService` owns it; the tutorial reads the binding from there rather than
   hardcoding a key in a hint string.
5. **Battle integration.** The marking menu is the *secondary* surface (D4). Its
   wedges are populated from the same `CommandRegistry` the command card uses
   (Phase 8) — one action set, two presentations, so they cannot disagree.
6. **Lab integration.** The Lab's transient verbs (place, duplicate, view mode) go on
   the marking menu; the per-module actions stay on the persistent ring from Phase 6.

**Tools.** Godot only.

**Tests.** New suite `tests/test_marking_menu.gd`:
- press, move 40 px right, release at 120 ms commits the east wedge and never sets
  `visible = true`
- press, hold 300 ms draws the ring
- release inside the hub cancels
- release beyond the outer radius commits the correct sector
- a stroke shorter than `MIN_STROKE` released early cancels rather than committing a
  random wedge
- wedge angular assignment for a given action id is identical between the card and
  the menu

**Done when.**
- A fast flick issues a command with no visual menu
- A slow hold reveals the ring
- Lab and battle use one widget
- Full suite green

---

## Phase 8 — Command card and command bindings

**Goal.** A discoverable, positional, on-screen command surface — and the resolution
of the A/S binding collision.

**Depends on.** Nothing hard; Phase 7 shares `CommandRegistry`.

**Files.** Rewrite `scripts/ui/command_card.gd`; new
`scripts/battle/orders/command_registry.gd`; modify `project.godot` `[input]`,
`scripts/core/input_service.gd`, `scripts/battle/match_director.gd`,
`scripts/battle/hud/battle_hud.gd`.

**Method.**

1. **Fix X1 first, in its own commit.** `cmd_attack_move` is on physical key A, which
   `cam_pan_left` also holds; `cmd_stop` is on S, which `cam_pan_down` also holds. Per
   D5, WASD and QE are camera-only. Remove the A and S bindings from the command
   actions. They are re-bound as card cells below.
2. **New InputMap actions**, eight of them: `card_r`, `card_f`, `card_g`, `card_t`,
   `card_z`, `card_x`, `card_c`, `card_v`. Row 3 gets no default bindings.
3. **`CommandRegistry`** builds the action set for a selection:
   `{id, label, icon, hotkey_action, enabled_predicate, row, col}`. It is the single
   source consumed by the command card, the marking menu and the tutorial. Nothing
   else may define what commands exist.
4. **Card geometry (D6):** 3 rows x 4 columns, 12 cells.
   - Row 1 -> `R F G T`
   - Row 2 -> `Z X C V`
   - Row 3 -> mouse-only overflow, no default bindings
   - Number row is **not** used by the card; it stays control-group recall
5. **Default placement. Five of the eight cells are already bound correctly** — the
   existing InputMap happens to fit the `RFGT`/`ZXCV` grid almost exactly, so only the
   two colliding actions actually move. **Do not reassign anything that already sits
   on a card key.**

   | Cell | Key | Command | Current binding | Change |
   |---|---|---|---|---|
   | 1,1 | R | Patrol | `cmd_patrol` = R | none |
   | 1,2 | F | Attack-move | `cmd_attack_move` = **A** | **move to F** (fixes X1) |
   | 1,3 | G | Stop | `cmd_stop` = **S** | **move to G** (fixes X1) |
   | 1,4 | T | Set rally | `cmd_set_rally` = T | none |
   | 2,1 | Z | Stance: aggressive | `cmd_stance_aggressive` = Z | none |
   | 2,2 | X | Stance: return fire | `cmd_stance_return_fire` = X | none |
   | 2,3 | C | Hold position | `cmd_hold` = C | none |
   | 2,4 | V | Stance: hold fire | — | new |

   F for attack-move rather than R: with the left hand resting on WASD for camera, F
   is one index-finger step right of D, which is the best key still free. R already
   belongs to patrol and to `lab_rotate`, and moving the most-used command onto the
   most-contested key to gain nothing is not a trade. **The card is data-driven — if
   Chris prefers attack-move on R, swapping two `CommandRegistry` rows is the whole
   change.**

   `cmd_jump_alert` (Space), `cmd_idle_worker`, `cmd_select_all_army` and the
   `cmd_group_*` set stay off the card. They are global navigation, not per-selection
   commands, and putting them in a positional grid would imply they act on the
   selection.

6. **Cells are positional and stable.** A command occupies the same cell across
   selections wherever it exists at all; an unavailable command renders as a disabled
   cell, not a gap. Positional binding is worthless if position moves.
7. **Cells display their key**, read from `InputService`, never hardcoded, so a
   rebind is reflected on the card without a second source of truth.
8. **Give attack-move a cursor (X7).** `match_director.gd:3175` flashes
   `"ATTACK-MOVE: RIGHT-CLICK A DESTINATION"` into a label and that is the only
   feedback that the mode is armed. `assets/cursors/cursor_attack.png` exists and
   `cursor_manager.gd` exposes a working `set_cursor(type)`. Arming a targeted
   command sets the cursor; disarming restores it. Keep the flash text as well —
   with captions enabled it is the accessible channel — but the cursor is the primary
   cue, because the player is looking at the battlefield, not at a hint label.
9. **Cells are `StampedButton`s on the screen's `UIPropStage`** (Phase 1), so the
   card is physical hardware rather than flat cells. The command-card bezel is a
   Blender-authored 9-slice.

> **Two items the deleted plan scheduled here are already done** — the permanent
> on-screen cheat sheet no longer exists, and the HUD's DEBUG button is gone with
> `admin_menu` debug-gated at `match_director.gd:3108`. See Part 2.4a. Do not
> schedule either.

**Tools.** Godot; Inkscape for the command glyph set; Blender for the bezel.

```bash
# glyphs
inkscape --export-type=png --export-width=64 assets/svg/cmd_*.svg
cd prototype && python tools/generate_icons.py
```

**Tests.** New suite `tests/test_command_card.gd`:
- **no InputMap action shares a physical keycode with any `cam_*` action** — this is
  the regression guard for X1 and it should outlive this phase
- every `CommandRegistry` entry has a distinct (row, col)
- a command's cell is identical across two different selections that both offer it
- the displayed key text matches `InputService`'s current binding after a rebind
- pressing `card_r` and clicking cell (1,1) produce the same order

**Done when.**
- No command action collides with a camera action, asserted by a test that outlives
  this phase
- The card shows real bindings and updates on rebind
- Arming attack-move changes the cursor
- Full suite green

---

## Phase 9 — The selection panel

**Goal.** When you select your units, the game shows you the designs you made.

**Depends on.** Phase 8 (registry), Phase 1 (stage) for the chrome.

**Files.** New `scripts/battle/hud/selection_panel.gd`; modify
`scripts/battle/hud/battle_hud.gd`, `scripts/battle/orders/selection_service.gd`
(read-only — it already emits what is needed).

**Method.**

1. Pure subscriber to `selection_service.selection_changed(units)`
   (`selection_service.gd:39`). **No service change is required.**
2. **Aggregate by blueprint/design (D8).** Group key is the design id; label is the
   design name. Render one row per design: silhouette portrait, count, aggregate
   health bar.
3. **Portraits** come from `blueprint_thumbnail.gd`, which already exists, cached per
   design id for the match. Do not render a portrait per unit.
4. **Sub-group operations**, per the RTS canon in `UIUX Design Paradigms.txt`:
   - Click a group -> select only that design
   - Shift+click -> remove one unit of that design
   - Ctrl+Shift+click -> remove the whole design group
   - Double-click -> select all of that design on screen
5. **Sub-group priority.** When a heterogeneous selection is made, the command card
   and `SpecPlacard` show the *primary*. Assign a priority per design derived from
   its modules: designs with active abilities outrank plain combat designs, which
   outrank harvesters. Where several equal candidates exist, prefer the one nearest
   the cursor. This removes a whole layer of micromanagement and it is the mechanism
   `SpecPlacard` already half-implements by taking `selected[0]`.
6. `SpecPlacard` at `Level.BATTLE` stays, showing the primary group's design. The
   panel and the placard are adjacent and never disagree because both read the same
   primary.
7. **Wire `AlertService` while here.** It exists and does almost nothing. Give it:
   minimap ping on `alert_posted`, an `EdgeMarker` for off-screen events (the widget
   exists at `scripts/ui/edge_marker.gd`), an audio cue through
   `UIFeedback`/`AudioManager` (`sfx_warning_banner` and `sfx_radio_static` are
   committed and currently only reachable as UI button roles), and a jump-to-event
   binding.

**Tools.** Godot only.

**Tests.** New suite `tests/test_selection_panel.gd`:
- selecting 12 of design A and 4 of design B produces exactly two rows with counts
  12 and 4
- Ctrl+Shift+click on row A leaves 4 units selected, all design B
- primary selection follows the documented priority
- a design whose last unit dies removes its row without disturbing the others
- portrait cache creates one thumbnail per design, not per unit

**Done when.**
- Selecting a mixed army shows aggregated design rows
- Sub-group deselect works with both modifiers
- Alerts ping the minimap and mark the screen edge
- Full suite green

---

## Phase 10 — Lab cross-pollination

**Goal.** The Lab and the battlefield share one interaction vocabulary.

**Depends on.** Phases 6, 8, 9. **Conflicts with in-flight `parts_menu.gd` and
`lab_toolbar.gd` work — re-read both before starting.**

**Files.** `scripts/module_placer.gd`, `scripts/drag_drop_manager.gd`,
`scripts/stat_calculator.gd`, `scripts/telemetry_rail.gd`, new
`scripts/ui/module_selection_panel.gd`.

**Method.**

1. **Box-select modules on the hull.** Drag a rectangle in the Lab viewport to select
   multiple modules. This is the mechanic `UIUX Design Paradigms.txt` argues should
   travel from RTS to the modelling tool, and it is genuinely missing.
2. **Aggregated module rows.** "6 x Autocannon, 2 x Sensor Mast, 1 x Generator", with
   the same modifier grammar as Phase 9: Shift+click removes one, Ctrl+Shift+click
   removes the type. Reuse `selection_panel.gd`'s row widget; do not write a second one.
3. **Lab command card.** Same 3x4 geometry, same `RFGT`/`ZXCV` rows, populated from a
   Lab command set: mirror, rotate, delete, duplicate, and the view modes. Sharing the
   geometry is the point — a player who learns the battle card already knows where the
   Lab's verbs live.
4. **Restructure the telemetry rail into toolbox tiers** (Part 2.5 item 2). The
   `DOCUMENT` tier was added *above* the existing rail rather than re-homing it,
   because the readouts are positioned by index (`move_child(x, at + n)`) and
   re-parenting would silently reorder them. **This needs its own commit and its own
   verification pass** — assert the rail's readout order before and after.

**Tools.** Godot only.

**Tests.** Extend `tests/test_designer_lab.gd`:
- box-select over three modules selects exactly three
- Ctrl+Shift+click on an aggregated row deselects that whole type
- Lab and battle command cards report identical (row, col) geometry
- telemetry rail readout order is unchanged after the tier restructure

**Done when.**
- Multi-module selection works with the same grammar as battle
- Both cards share geometry
- Rail restructured with order verified
- Locomotion golden fixture unchanged
- Full suite green

---

## Phase 11 — Unified pointer and camera feel

**Goal.** The camera and the cursor feel identical in both halves of the game.

**Depends on.** Phase 5 (the precision modifier is the same transfer function).

**Files.** New `scripts/core/pointer_gain.gd`; modify `scripts/designer_camera.gd`,
`scripts/rts_camera.gd`, `scripts/gizmo_handle.gd`,
`scripts/core/settings_service.gd`, `scripts/ui/settings_panel.gd`.

**Method.**

1. **`PointerGain`** implements a speed-dependent control/display transfer function:
   a monotonic curve that damps high-velocity ballistic movement (so a fast sweep does
   not overshoot) and adds granularity to slow movement (so precise work does not need
   a sensitivity change). `UIUX Design Paradigms.txt` measures these at up to 24%
   faster than a constant gain, and the mechanism is the same one the Phase 5 precision
   modifier rides on — the modifier just shifts the curve.
2. **One function, both cameras.** `designer_camera.gd` (orbit) and `rts_camera.gd`
   (pan/rotate/zoom) both route through it. Zoom increments, deceleration smoothing
   and rotation rate come from the same tokens, so orbiting a model and panning a
   battlefield share a feel. This is the cheapest cohesion win in the whole plan and
   the player will never consciously notice it, which is the point.
3. Expose curve strength as a setting alongside the existing `camera_pan_speed`,
   `camera_rotate_speed` and `invert_zoom` keys in `settings_service.gd`.
4. `rts_camera.gd` currently polls `Input.is_key_pressed()` in `_process()` rather
   than consuming events — which is the root cause of X1. Migrate it to InputMap
   actions while here.

**Tests.** Extend `tests/test_ui_and_camera.gd`: the gain curve is monotonic, has no
discontinuity at the damping knee, and returns identical output for identical input
from both camera call sites.

**Done when.**
- Both cameras route through `PointerGain`
- `rts_camera.gd` consumes actions rather than polling keys
- The setting exists and takes effect live
- Full suite green

---

## Phase 12 — Enforcement

**Goal.** Make the rules in this document mechanically checkable so they do not erode.

**Depends on.** All prior phases.

**Files.** `scripts/ui_audit.gd`, `run_tests.gd`, `tools/probe_scene_loads.gd`,
`prototype/docs/UI_STYLE_GUIDE.md`, `prototype/docs/UI_IMPLEMENTATION_PLAN.md`.

**Method.**

1. **No-emoji enforcement** (Part 2.5 item 4). `ui_audit.gd` checks overflow,
   offscreen controls, theme validity, icons and cursors — not this, despite
   `CLAUDE.md` having claimed it did. Add a Unicode-range check over every `Label`,
   `Button` and `RichTextLabel` text in every scene. Box-drawing and arrows stay
   permitted.
2. **Layer discipline check.** Assert that no L0 material is applied to a control
   descended from a panel, and that no phosphor surface has a stamped label as a
   direct child.
3. **Luminance stack check.** Assert the material stack stays strictly ascending from
   backdrop to control body, including the new L0 fields from Phase 4. This is the
   check that would have caught bakelite sitting at `BASE_900` — buttons darker than
   their panels, which no bevel can rescue.
4. **Binding collision check.** Promote the Phase 8 test into the audit: no command
   action may share a physical keycode with a camera action.
5. **Promote `tools/probe_scene_loads.gd` into `SUITE_ORDER`** (Part 2.5 item 3). No
   suite currently instantiates `MainLab.tscn`, which is why a crash on the Design
   Lab's primary load path was invisible to an otherwise-green 211-suite run.
   `SUITE_ORDER` is order-sensitive — append, and give this its own commit.
6. **Update the docs.** `UI_STYLE_GUIDE.md` gains sections for L0, the prop stage and
   the marking menu. `UI_IMPLEMENTATION_PLAN.md` gains the built/outstanding status of
   everything here. Both are written against the tree, with file references — the
   standing lesson from that document's own preamble is that a plan describing
   intentions rather than the tree rots silently.

**Done when.**
- `ui_audit.gd` enforces emoji, layer discipline, luminance and binding collisions
- `probe_scene_loads` is in `SUITE_ORDER`
- Both docs updated against the tree
- Full suite green

---

# Part 5 — Toolchain

All four confirmed available (D16).

| Tool | Invocation | Used by |
|---|---|---|
| **Godot 4.7.1** | `cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless ... --quit --path .` | Everything |
| **Blender 5.2** | `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender/<script>.py` | Phases 3, 8 |
| **Python 3** (numpy, scipy, Pillow) | `cd prototype && python tools/<script>.py` | Phases 2, 3, 4 |
| **Inkscape CLI** | `inkscape --export-type=png --export-width=N in.svg` | Phase 8 glyphs |
| **GIMP CLI** | `gimp -i -b '(script-fu ...)' -b '(gimp-quit 0)'` | Phase 3 hero compositing |

### Standing command reference

```bash
# Full test suite (reimports first) - required green before every commit
cd prototype && ./run_tests.ps1

# Fast targeted parse check
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/parse_check_some.gd --quit --path .

# Rebuild the theme after ui_tokens.gd or build_ui_theme.gd changes
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/build_ui_theme.gd --quit-after 2 --path .

# Regenerate UI plates and fields
cd prototype && python tools/generate_ui_plates.py

# Regenerate per-prop button textures (new in Phase 2)
cd prototype && python tools/generate_ui_props.py

# Rebuild UI prop meshes
cd prototype && "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender/build_ui_props.py

# Reimport after any asset regeneration - required, or Godot has no .import sidecars
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import --quit --path .
```

### Existing generators worth reading before writing a new one

`tools/generate_ui_plates.py` (plates and fields), `tools/generate_icons.py`
(glyphs), `tools/generate_cursors.py`, `tools/blender/build_ui_props.py` (the six
existing UI prop meshes plus `ui_push_button.glb`), `tools/blender/hull_forge.py`
(the loft/normalise pattern), `tools/audio/` (the layered-package pattern this
plan's texture pipeline should imitate).

---

# Part 6 — Sequencing, risk, open items

### Sequencing

```
Phase 1  Prop stage ────┬── Phase 2  Prop textures ── Phase 3  Depth and wear
                        │
Phase 4  Workbench L0 ──┤   (independent, can run any time)
                        │
Phase 5  Lab handles ───┴── Phase 6  Module ring ─── Phase 7  Marking menu ──┐
                                                                             │
Phase 8  Command card ───────────────────────────────────────────────────────┤
                                                                             │
Phase 9  Selection panel ────────────────────────────────────────────────────┤
                                                                             │
Phase 10 Lab cross-pollination ──────────────────────────────────────────────┤
Phase 11 Pointer gain ───────────────────────────────────────────────────────┤
Phase 12 Enforcement ────────────────────────────────────────────────────────┘
```

**Phase 1 must go first among 1–3** — 2 and 3 both assume the stage exists.
**Phase 4 is fully independent** and is the best phase to run when another is
blocked. **Phase 8 is the highest single-phase value in the plan** — it fixes the
project's only live input collision, gives the game a discoverable command surface
it currently does not have at all, and gives targeted commands a cursor. It is also
the cheapest of the large phases, because five of its eight bindings are already
correct. If only one phase ever ships, ship that one. **Phase 12 must go last.**

### Risks

| Risk | Mitigation |
|---|---|
| **The shared prop stage breaks input on migrated screens.** `SubViewportContainer` consuming mouse events is the documented failure mode in the research brief | Container is `MOUSE_FILTER_IGNORE`; controls keep hit-testing. Phase 1 tests assert a button under the stage is still clickable |
| **POM contributes nothing under an ortho camera** | Part 3.3. Relief lives in the mesh; POM lives on the sloped regions. Do not tilt the camera to compensate |
| **The workbench layer becomes visual noise.** The most likely way this plan makes the game worse | Layer discipline rule, contrast re-check on every screen, Phase 12 enforcement. If a screen reads noisy, dim the field — do not abandon the layer |
| **Phase 5 destabilises the Lab.** `module_placer.gd` owns a golden fixture and is mid-rework by Chris | Re-read the file before starting. The fixture must not move; if it does, you have made a mistake, not a change |
| **Two marking-menu-shaped widgets diverge** | `ModuleActionRing` and `MarkingMenu` share `ring_draw.gd` and nothing else. Different lifecycles, deliberately different files |
| **The command card and marking menu disagree about what commands exist** | Both read `CommandRegistry`. Nothing else may define a command |
| **Chris's in-flight work collides** | Phases 5, 6 and 10 touch files he is actively editing. Branch per phase, re-read before starting, never revert his changes |

### Residual open items — decide before the phase that needs them

1. **Precision modifier key.** Phase 5 binds a new `manip_precision` action; the
   default key is not chosen. Shift is the conventional answer, and Ctrl is a poor
   candidate because the Lab already uses Ctrl+D/S/Z/Y. Check Shift against the
   Lab's existing raw-modifier reads in `drag_drop_manager.gd` and `module_placer.gd`
   before defaulting to it — those files predate the InputMap and poll modifiers
   directly, so a grep for `shift_pressed` is the check, not a grep for an action.
2. **Marking menu invoke binding.** Phase 7 needs a modifier + mouse-button
   combination that does not fight drag-select, camera drag or order issuing.
3. **Row 3 of the command card.** D6 leaves it mouse-only. If it turns out to need
   keys, the natural candidates are Shift+`RFGT` — but that is a decision, not a
   default.
4. **Hero prop list.** Phase 3 proposes DEPLOY, SAVE, TEST, DISCARD, five production
   queue headers and the menu destination cards. Confirm before authoring, since each
   hero prop is real Blender and GIMP time.
5. **Font licensing.** Still open from `UI_IMPLEMENTATION_PLAN.md`. Not blocking any
   phase here, but it blocks shipping a build. SIL OFL permits bundling in commercial
   products; other licences may not.
6. **Records screen.** The deleted plan proposed persisting `after_action_report.bp_stats`
   per blueprint as a service record, and `SpecPlacard` already has a `RECORD` detail
   level built for it with no caller. It is deliberately **not** scheduled here — it is
   a feature, not interface work. It remains the strongest single reason to reopen the
   Lab, and it is cheap because the data is already collected and thrown away.

### Housekeeping

- `Tactile, Diegetic 3D Interfaces in Godot 4.7.txt` is 0 bytes. Its content is in
  `New Text Document.txt`. Rename or delete.
- Consider moving the four research briefs into `docs/research/` so the repo root
  stays legible.
