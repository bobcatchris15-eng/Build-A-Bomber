# Kitbash Command — UI Implementation Plan

_Companion to UI_STYLE_GUIDE.md. What is done, what is outstanding, and what is deliberately not being done._
_Last updated: 2026-08-05_

> **This document was substantially wrong before this revision, and that cost real time.** It claimed the plate textures, field textures, the plate generator and the font files did not exist — all four were present. Its Priority 1a targeted `main_lab.gd`, a file that has never existed. Two of its three open questions were already answered by code in the repo, and one of its Priority 5 clean-ups had already been done. Anyone following it would have re-authored finished assets and hunted for phantom files.
>
> The lesson worth keeping: **a plan that describes intentions rather than the tree rots silently.** Every claim below is stated against a file that was checked. Where something is asserted as done, it is because it was verified, not because it was scheduled.

---

## Status: What Is Already In Place

Fully implemented. Do not re-invent or work around any of these.

| System | File(s) | Notes |
|---|---|---|
| Token palette | `scripts/ui_tokens.gd` | Colour, type, spacing, geometry, **elevation**, **motion** |
| Theme builder | `tools/build_ui_theme.gd` | 23 registered variations |
| Generated theme | `resources/bomber_theme.tres` | Built, checked in |
| Runtime material applicator | `scripts/ui_theme.gd` | `apply_material` / `apply_backdrop` / `apply_faction_preview` |
| Material plates | `assets/textures/ui/plate_*.png` | 24 files, **128×128 RGBA** |
| Material fields | `assets/textures/ui/field_*.png` | 6 files, 512×512 RGB |
| Plate generator | `tools/generate_ui_plates.py` | Procedural, fixed seed |
| Fonts | `assets/fonts/*.ttf` | All four present |
| Motion library | `scripts/ui_anim.gd` | slide/fade/hover/stagger/flash/shake |
| Feedback layer | `scripts/ui_feedback.gd` | Audio **and** motion in one call |
| Toolbox widget | `scripts/ui_toolbox.gd` | Collapsible tiers with accordion |
| Dock widget | `scripts/ui_dock.gd` | Edge dock, collapses to a small metallic box |
| Layout helpers | `scripts/ui_shell.gd` | `stat_row`, `backdrop`, `screen_frame` |
| Scene transitions | `scripts/scene_router.gd` | `goto()` fades every screen change |

**The theme builder is the canonical way to add a style.** Never add a `StyleBoxFlat` override inline in a screen script for anything that should be globally consistent — a local override *beats* the theme, so an inline style actively holds the design system out of that control. Add a variation and rebuild.

---

## Priority 1 — Screen Consistency Sweep — **DONE**

Every out-of-match screen plus the Skirmish HUD has been swept. What that meant in practice:

- `modulate = Color(...)` literals replaced with theme variations or `font_color` overrides. `modulate` was the wrong mechanism regardless of value: it multiplies the whole subtree and cannot brighten.
- Off-scale font sizes normalised. Several were near-misses on real tokens — an ad-hoc amber where `SIGNAL_HAZARD` was meant, a saturated web green for `SIGNAL_GO`'s deliberately desaturated olive.
- `UIFeedback.wire()` on interactive controls; `stagger_in` on lists and grids.

### 1a · Design Lab — **DONE**

**There is no `main_lab.gd`.** `scenes/MainLab.tscn` is the 3D world plus two UI sub-scenes: `UI_StatBlock.tscn` (`stat_calculator.gd`, the right rail) and `UI_PartsMenu.tscn` (`parts_menu.gd`, the catalogue). Every file reference in the previous version of this section was wrong.

Current state:

- **Left dock** — `parts_menu.gd` in a `UIDock`, holding a `UIToolbox` of four tiers: Hulls / Weapons / Support / Drives. Each tier holds category drawers; each drawer holds part cards. Accordion at both levels.
- **Right dock** — `stat_calculator.gd` in a `UIDock`, with a `UIToolbox` `DOCUMENT` tier for the design name and Save / Library / Discard, above the telemetry rail.
- **Top bar** — `HeaderPanel` band of transparent info slots (HULL / PARTS / FACTION) plus the global buttons. Slots read from the same `DesignStats` result the telemetry rail uses, so the two cannot disagree.

**Three `StyleBoxFlat` builds in `stat_calculator.gd` are correct and must stay** (the load-bar fill and the two warning panels). They are the documented state-indicator exception: there is no theme-side way to say "this bar is in its bad state", and `StyleBoxTexture` carries no colour channel to vary. See the comment above `_load_fill_style()`.

> **Trap, recorded because it bit once.** `Tokens.TOOLBAR_HEIGHT` is what both docks inset their top by, but it does **not** constrain the toolbar: a `PanelContainer` cannot render shorter than its content's combined minimum size, so `offset_bottom` is a floor the buttons can exceed. When button padding grew, the bar became 64 px while the docks still inset by 44, and the top 20 px of each collapsed rail covered the bottom 20 px of the toolbar — exactly the band holding UNDO/REDO and SAVE/TEST, which became unclickable. It presents as an input bug, not a layout one. `_verify_toolbar_height()` now warns at runtime if it recurs.

### 1b · Skirmish HUD — **DONE (chrome only)**

Counters are `HUDValueLabel`, the top bar is `HUDPanel`, panels carry variations, and there are zero per-control font-size overrides. Feedback is wired on the build bar, the tab bar and the menu button; `value_flash` fires on resource jumps and on power-state transitions.

**Scope boundary — do not "fix" these.** They convey battlefield state, not chrome, and changing them alters gameplay readability:

> `GHOST_COLOR_VALID` / `GHOST_COLOR_INVALID`, the fog shroud fills, `MINIMAP_*` and the terrain colour map, 3D `albedo_color` assignments, order markers, and the game-over scrim.

`battlefield.gd` was listed here previously; its only UI is a return button, now routed through `SceneRouter.goto()`.

### 1c · Match Setup / Operations Setup — **DONE**

Match Setup's roster picker was rebuilt as drag-and-drop (`roster_picker.gd`) — see Priority 6.

Two claims in the previous version were wrong: **neither screen has a map-preview SubViewport** to wrap in an `InsetPanel` (that referred to the deleted `MapSelect` screen; the map is now a dropdown on Match Setup). And `style_option_button()` was already a no-op stub; it has since been deleted along with the other dead wrappers.

---

## Priority 2 — Material Textures — **DONE**

Plates and fields are generated by `tools/generate_ui_plates.py` with a fixed seed, so a rerun is a no-op in the diff. **The authoring spec below supersedes the previous one, which described the plates as 96×96 RGB with a flat 12 px margin.**

Plates are **128×128 RGBA**: a 96×96 opaque body inside a **16 px transparent pad** carrying the baked elevation shadow. The 9-slice frame is therefore `MARGIN + PAD = 28 px`.

> **Why the shadow is baked into the PNG.** `StyleBoxFlat` has shadow properties; `StyleBoxTexture` has none, and every panel variation is texture-backed. Godot draws exactly one stylebox per control state, so a shadow-only box cannot be stacked behind. The texture is the only place a shadow can live.
>
> **The part that must not be forgotten:** `build_ui_theme.gd` sets `expand_margin_* = PLATE_PAD` so the box draws *outside* the control rect. Without it every panel shrinks by 16 px per side and every alignment in every screen shifts.

| State | Brightness | Bevel |
|---|---|---|
| `normal` | ×1.00 | top-lit, strength 1.00 |
| `hover` | ×1.28 | top-lit, strength 1.30 |
| `pressed` | ×0.74 | **bottom-lit** (inverted), 1.10 |
| `disabled` | ×0.62 | top-lit, 0.30 |

Bevel *strength* rises with state, not just brightness: a hover that only brightens reads as a lighting change on a flat card, while one that also sharpens the chamfer reads as the control catching more light.

### Material luminance stack

This is load-bearing and was wrong for a long time. The button material — originally `bakelite`, now `moulded` — sat at 0.075, which is exactly `BASE_900`, the value reserved for the deepest recess. Buttons were therefore *darker than the panels they sat on*, and no bevel can make that read as raised. It also flattened every state: ×1.18 of 0.075 moves the absolute value by 0.014, which is invisible.

| Surface | Material | Luminance |
|---|---|---|
| backdrop | steel field × 0.42 | 0.084 |
| panel body | `powdercoat` | 0.103 |
| flyout / tooltip | `canvas` | 0.121 |
| **control body** | `moulded` | **0.154** |
| alert placard | `fiberglass` | 0.156 |
| rails, frames | `steel` | 0.206 |
| primary action | `carbon` | 0.107 |

The stack must stay strictly ascending from backdrop to control. `carbon` sits low because it is the dark premium material, but it was raised from 0.072 for a related reason: once moulded rose, a `BASE_900` carbon made `PrimaryButton` the *darkest* control on screen, so the primary action receded behind every ordinary button.

### A note on the `moulded` key

The surface is injection-moulded ABS / powdercoated aluminium, not phenolic. It stays distinct from `powdercoat` by **frequency, not amplitude** — powdercoat is sprayed over brushed metal so it keeps an anisotropic substrate grain and a broad thickness roll, while this is moulded and has neither.

**The key was renamed from `bakelite` in Phase 4** — see the Tactile Interface Programme, Phase 4.

---

## Priority 3 — Font Assets — **DONE**

All four files are present. Licensing is still open — see Open Questions.

---

## Priority 4 — New Screen Shells — **USE THE HELPERS**

The hand-written scaffold that was here is replaced by `UIShell`:

```gdscript
func _ready() -> void:
    UIShell.backdrop(self)                  # full-bleed steel, MOUSE_FILTER_IGNORE
    var frame := UIShell.screen_frame(self) # canonical margins
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", Tokens.SPACE_LG)
    frame.add_child(root)
    # ... content, then:
    UIFeedbackScript.wire_tree(root)        # hover + press, audio + motion
```

`screen_frame()` exists because the frame had drifted to **three different margin sets across four screens**, two of them off the 4 px grid. That had a visible consequence: the loading screen's content sat further in than the screen it transitions to, so the frame appeared to jump on arrival.

> **`UIShell` is deliberately small, and its history is the reason.** It once had `build_screen`, `column`, `field`, `action` and `select_row`. Only `stat_row` was ever adopted; the other five were deleted with zero call sites. **Do not add a helper here until a second screen needs it** — both current additions shipped with all their call sites migrated in the same change.

---

## Priority 5 — Stale Workarounds — **DONE**

| Workaround | Outcome |
|---|---|
| `stat_calculator.gd` inline stat-row styleboxes | Not a workaround. The three survivors are the documented state exception — see 1a |
| `main_menu.gd` `_create_industrial_button_style()` | Deleted. Now the `NavCard` variation |
| Duplicate `_apply_unpainted_scale_model_material()` | Extracted to `HullMaterialBuilder.apply_scale_model_finish()` |
| `_plate()` degrades silently | Already fixed before this plan was written — `_plate_texture()` calls `push_error` |
| `apply_brushed_panel()` no-op wrapper | Deleted, with `style_option_button()` and `style_slider()`. All call sites migrated; `test_ui_and_camera.gd` retargeted at `apply_backdrop` |

Also removed: `UITheme.variation()`, a typo-validating helper with **zero** call sites against 104 direct `theme_type_variation` assignments. Worth reviving only if it gets adopted.

---

## Priority 6 — Interaction Work — **DONE**

Not in the original plan, but the substance of the AAA polish pass.

- **Scene transitions.** `SceneRouter.goto()` is the single entry point and self-routes: scenes with a `WARM_SOURCES` entry get the loading screen, everything else swaps directly. The fade overlay lives on the **autoload** — a rect owned by the outgoing scene is freed mid-animation, and one owned by the incoming scene cannot cover the gap before that scene exists. `CanvasLayer` at layer 128 so it covers 3D viewports.
- **Feedback.** `UIFeedback.wire(ctrl, role)` attaches hover sound, hover lift, press sound and press squash in one call. They share the call because they must fire together; wiring them separately is how they drift.
- **Audio roles.** `default` → click, `confirm` → `radio_ack`, `select`, `place`, `reject` → error, `danger` → `warning_banner`. The four radio SFX were committed but unregistered — dead assets until this pass.
- **Roster drag-and-drop.** `roster_picker.gd` replaces a CheckBox list that could express neither the order designs are fielded in nor the roster cap. Slot position *is* the order now; previously it was library sort order, so which designs survived `roster.slice(0, 12)` was incidental.
- **Real stats on cards.** `design_stats.gd` — `DesignStats.analyze(hull)` makes the same `Drivetrain` / `WeaponRange` / `ModuleCatalog` calls `unit.gd` makes on the unit it spawns. **Nothing is re-derived**, because `stat_calculator.gd` has twice had to delete a local re-derivation that drifted: a capacity calculation that knew 4 locomotion types of 17, and an armour table showing the explosive threshold labelled as energy.

---

---

## Priority 7 — Tactile Interface Programme (Phases 1–12) — **DONE**

1. **L0 Workbench Layer (Phase 4):** 5 desk backdrop materials (`cutting_mat`, `cardboard`, `kraft`, `cork`, `chipboard`) generated and registered.
2. **UIPropStage & StampedButton (Phases 1 & 8):** Single shared SubViewport 3D hardware stage powering physical stamped buttons and switches.
3. **Procedural Prop Textures & Depth/Wear (Phases 2 & 3):** Deterministic 256x256 albedo/ORM/height generation (`tools/generate_ui_props.py`), PCG3D integer hash swap in shaders, Parallax Occlusion Mapping (POM) raymarching with tangent-space normals, and world-normal equipment dust.
4. **Lab Gizmo & Planar Handles (Phase 5):** Hull excluded from gizmo manipulation (`D10`), dynamic face-on planar handles (`PlanarXY`, `PlanarXZ`, `PlanarYZ`) with angle culling (`D12`), and precision modifier (5x reduction).
5. **Machined Radials (Phases 6 & 7):** Shared `RingDraw` rendering library, silhouette-sized `ModuleActionRing` (`D13`) framing 3D modules, and transient stroke-driven `MarkingMenu` (`D9`, `D14`) with fast-flick and slow-hold paths.
6. **Command Card & Selection Panels (Phases 8, 9, 10):** 3x4 positional command card backed by `CommandRegistry` and `SelectionPanel` with design aggregation and RTS sub-group grammar. The Phase 10 multi-module aggregation was scoped as `ModuleSelectionPanel` but never built; the lab uses single-module selection via `LabToolbar`.
7. **Unified Pointer & Camera Feel (Phase 11):** Monotonic `PointerGain` transfer function unified across `DesignerCamera` orbit and `RTSCamera` middle-drag pan.
8. **Enforcement Audits (Phase 12):** `UIAudit` extended with no-emoji verification and keybinding collision assertions; scene load probing integrated into `run_tests.gd`.

---

## Rebuild Commands

```bash
# After ui_tokens.gd or build_ui_theme.gd changes
./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/build_ui_theme.gd --quit-after 2 --path .

# After editing generate_ui_plates.py
python tools/generate_ui_plates.py
./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import --quit --path .
```

`--quit` and `--path` are not optional on a headless run; without them the process finishes its work and never exits. Godot also block-buffers stdout when piped, so a direct `--script` run shows nothing until it terminates.

**Verification:** use `run_tests.ps1`. `tools/compile_check_all.gd` is not a "quick" check at this size — it loads 200+ interdependent scripts with `CACHE_MODE_IGNORE` and has run 20+ minutes without finishing. `tools/parse_check_some.gd` takes explicit paths for a fast targeted check.

---

## Open Questions

1. ~~Plate authoring pipeline~~ — **resolved.** `tools/generate_ui_plates.py` exists and is the pipeline. Procedural with a fixed seed, so the committed PNGs are reproducible.

2. ~~NavCard variation vs. inline style~~ — **resolved as option (b).** `NavCard` is registered, deliberately as a **flat** stylebox rather than a plate: its identity is an asymmetric left gutter that thickens on hover, and `StyleBoxTexture` has no border properties at all. The one place a flat stylebox is the right answer.

3. **Font licensing** — still open. Confirm the exact files and licence terms before shipping a build. SIL OFL permits bundling in commercial products; other licences may not.

4. **Does the elevation system reach the plate-backed variations well enough?** Shadows are baked per `(material, state)`, so every variation sharing a plate shares a tier. That holds today. If a future variation needs a different tier from another variation on the same plate, the plate filenames must carry the tier too — see `SHADOW_ASSIGNMENT` in the generator.
