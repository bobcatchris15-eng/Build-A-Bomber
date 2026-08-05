# Kitbash Command — UI Implementation Plan
_Companion to UI_STYLE_GUIDE.md. Describes what is already done, what is outstanding, and the priority order for completing it._
_Last updated: 2026-08-04_

---

## Status: What Is Already In Place

The following pieces of the design system are fully implemented and should not be re-invented or worked around:

| System | File(s) | Status |
|---|---|---|
| Token palette | `scripts/ui_tokens.gd` | ✅ Complete |
| Theme builder | `tools/build_ui_theme.gd` | ✅ Complete |
| Generated theme | `resources/bomber_theme.tres` | ✅ Built, checked in |
| Runtime material applicator | `scripts/ui_theme.gd` | ✅ Complete |
| Layout helpers | `scripts/ui_shell.gd` | ✅ (`stat_row` only) |
| Main menu | `scripts/main_menu.gd` | ✅ Complete |
| Blueprint library screen | `scripts/blueprint_library_screen.gd` | ✅ Complete |
| Hull Material Builder | `scripts/hull_material_builder.gd` | ✅ Complete |

**The theme builder is the canonical method for adding new panel/button/label styles.** Do not add StyleBoxFlat overrides inline in screen scripts for anything that should be globally consistent. Add a variation to `build_ui_theme.gd` and rebuild.

---

## Priority 1 — Screen Consistency Sweep

The Design Lab, Skirmish HUD, and Match Setup screens all pre-date the current design system. They were partially updated but still contain:

- Hardcoded colour literals not from `ui_tokens.gd`
- `apply_brushed_panel` calls that are now no-ops (deprecated in `ui_theme.gd`) but still mark intent that was never followed through
- Font sizes set per-control instead of through the type scale

### 1a · Design Lab (`scenes/MainLab.tscn` + `scripts/stat_calculator.gd`)

**Issues:**
- Top toolbar uses hardcoded `BASE_700`-ish flat fill rather than a `HeaderPanel`
- Part catalogue panel on the left is a plain `Panel` — should be `DockPanel`
- Several inline `StyleBoxFlat` builds in `stat_calculator.gd` for the stat readout rows — should use `InsetPanel` + `stat_row()` from `UIShell`
- Build action buttons (Confirm, Mirror, Delete) use saturated red/green literals — should use `DangerButton` / `PrimaryButton` / default `Button` theme variations respectively
- The tweak slider row labels use `FONT_BODY` (15 px) in a dense context where `FONT_SMALL` (13 px) / `HintLabel` is appropriate

**Target state:**
- Toolbar → `HeaderPanel` variation, TOOLBAR_HEIGHT = 44 px
- Left parts dock → `DockPanel` variation
- Stats column → `CardPanel` with `stat_row()` calls
- All build/confirm/cancel buttons → appropriate theme variations, no colour literals

**File changes required:**
- `scripts/stat_calculator.gd` — remove inline styleboxes; assign theme_type_variations
- `scenes/MainLab.tscn` — check any in-scene panel node overrides

---

### 1b · Skirmish HUD (`scripts/skirmish.gd` + `scripts/battlefield.gd`)

**Issues:**
- Resource counters are plain Labels — should be `HUDValueLabel` (monospace, so counts don't reflow)
- Action bar buttons carry per-instance colour overrides — should use `PrimaryButton` / `DangerButton` / `TabButton`
- HP bars styled inline — should match `ProgressBar` theme entry (SIGNAL_GO_DIM fill + SIGNAL_GO edge)
- Command panel uses alpha transparency to "blend with the battlefield" — this predates the material pass; a `HUDPanel` (pressed powdercoat) is opaque enough to read and dark enough not to compete

**Target state:**
- All counters → `HUDValueLabel`
- Action bar → themed `Button` / `PrimaryButton` variations
- HP/resource bars → engine `ProgressBar` with themed fill
- Command panel → `HUDPanel` variation

**File changes required:**
- `scripts/skirmish.gd` — remove inline styleboxes; correct label variations
- `scripts/battlefield.gd` — same

---

### 1c · Match Setup / Operations Setup (`scripts/match_setup.gd`, `scripts/operations_setup.gd`)

**Issues:**
- Both screens build layouts from scratch without reusing `UIShell.stat_row()` for their key/value displays
- Map preview panel is a SubViewportContainer with no panel wrapper — the viewport bleeds edge to edge with no chrome separating it from the controls beside it
- Faction dropdown uses `style_option_button()` which is now a no-op; relies entirely on theme, but the theme's OptionButton style was not tested against this context

**Target state:**
- All key/value readout rows → `UIShell.stat_row()`
- Map preview → wrap in `InsetPanel` so there is a recessed well around the SubViewport
- Faction/map dropdowns → verify `OptionButton` theme entry renders correctly

**File changes required:**
- `scripts/match_setup.gd`
- `scripts/operations_setup.gd`

---

## Priority 2 — Material Texture Authoring

The theme builder references plate PNGs that do not yet exist:

```
assets/textures/ui/plate_powdercoat_normal.png
assets/textures/ui/plate_powdercoat_hover.png
assets/textures/ui/plate_powdercoat_pressed.png
assets/textures/ui/plate_powdercoat_disabled.png
assets/textures/ui/plate_bakelite_*.png
assets/textures/ui/plate_steel_*.png
assets/textures/ui/plate_canvas_*.png
assets/textures/ui/plate_carbon_*.png
assets/textures/ui/plate_fiberglass_*.png
```

`build_ui_theme.gd` degrades gracefully to a flat `StyleBoxFlat` when these are missing (by design), so the game runs. But the physical material language — the whole reason the interface should feel like machined equipment rather than a game menu — does not land without them.

### 2a · Plate authoring spec (for `tools/generate_ui_plates.py` or manual authoring)

Each plate is `128 × 128` px, 9-sliced with a **12 px margin**. The margin contains the bevel and outline; the centre is flat and tileable.

| State | Bevel direction | Fill brightness | Border |
|---|---|---|---|
| `normal` | Top-left lit (material sits proud) | Material mid | 1 px BASE_500 |
| `hover` | Top-left lit, brighter | +10% over normal | 1 px BASE_400 |
| `pressed` | Bottom-right lit (inverted) | Material mid | 1 px BASE_500 |
| `disabled` | No bevel | -20% from normal | 1 px BASE_600 |

Per-material tonal targets:

| Material | Normal fill (approx) | Texture feel |
|---|---|---|
| `powdercoat` | `BASE_800` (0.108) | Fine matte grain, slight sheen at bevel |
| `bakelite` | `BASE_700` (0.145) | Heavier grain, strong bevel highlight |
| `steel` | `BASE_700` (0.145, cooler tint) | Directional brushed lines |
| `canvas` | `BASE_800` (0.108, cloth weave) | Matte, no specular bevel |
| `carbon` | `BASE_900` (0.075) | Tight diagonal weave, satin catch |
| `fiberglass` | `BASE_800` + slight warmth | Subtle laminate lines |

### 2b · Field textures for runtime shader

Separate from the plate PNGs, the `UITheme.apply_material()` shader path reads per-material field textures:

```
assets/textures/ui/field_powdercoat.png
assets/textures/ui/field_steel.png
assets/textures/ui/field_bakelite.png
assets/textures/ui/field_canvas.png
assets/textures/ui/field_carbon.png
assets/textures/ui/field_fiberglass.png
```

These are tileable greyscale noise/grain maps read by `shaders/ui_material.gdshader`. The game runs without them (the shader falls back to flat base colour), but the backdrop and any `apply_material()` call sites will be flat until they exist.

---

## Priority 3 — Font Assets

The theme builder expects:

```
assets/fonts/UIFont-Regular.ttf     ← clean UI sans (Inter, Outfit, or similar)
assets/fonts/UIFont-Bold.ttf
assets/fonts/MonoFont-Regular.ttf   ← monospace (Roboto Mono, JetBrains Mono, etc.)
assets/fonts/StencilFont-Regular.ttf ← worn stencil (Special Elite recommended)
```

The builder degrades to engine defaults when fonts are missing, so functionality is maintained. However, without the correct font files:
- `DisplayLabel` / `TitleLabel` / `HeadingLabel` fall back to the engine sans, losing the stencil tone entirely
- `StatLabel` / `HUDValueLabel` fall back to the engine proportional font, causing numeric readouts to reflow

**Recommended sources (all OFL-licensed):**
- UI sans: **Inter** (rsms.me/inter) or **Outfit** (Google Fonts)
- Monospace: **JetBrains Mono** (jetbrains.com/mono)
- Stencil: **Special Elite** (Google Fonts) — already referenced in build_ui_theme.gd comments

---

## Priority 4 — New Screen Shells

When any new screen is added, it should follow this scaffold:

```gdscript
func _ready() -> void:
    # 1. Full-bleed steel backdrop
    var bg = ColorRect.new()
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)
    UITheme.apply_backdrop(bg)

    # 2. Margin frame
    var frame = MarginContainer.new()
    frame.set_anchors_preset(Control.PRESET_FULL_RECT)
    frame.add_theme_constant_override("margin_left", Tokens.SPACE_XL)
    frame.add_theme_constant_override("margin_right", Tokens.SPACE_XL)
    frame.add_theme_constant_override("margin_top", Tokens.SPACE_LG)
    frame.add_theme_constant_override("margin_bottom", Tokens.SPACE_LG)
    add_child(frame)

    # 3. Root VBox
    var root = VBoxContainer.new()
    root.add_theme_constant_override("separation", Tokens.SPACE_LG)
    frame.add_child(root)

    # 4. Console bar (HeaderPanel)
    _build_console_bar(root)

    # 5. Content columns / panels (CardPanel, InsetPanel, DockPanel as needed)
    _build_content(root)
```

---

## Priority 5 — Audit & Remove Stale Workarounds

As part of the design system maturing, several temporary workarounds should be tracked and cleaned up:

| Location | Workaround | Clean-up action |
|---|---|---|
| `scripts/stat_calculator.gd` | Inline StyleBoxFlat for stat rows | Replace with `InsetPanel` + `UIShell.stat_row()` |
| `scripts/main_menu.gd` | `_create_industrial_button_style()` helper builds per-instance styleboxes for destination cards | Move to theme as a `NavCard` variation in `build_ui_theme.gd` |
| `scripts/blueprint_library_screen.gd` | Duplicate of `_apply_unpainted_scale_model_material()` | Extract to a shared helper in `visual_builder.gd` or `hull_material_builder.gd` |
| `tools/build_ui_theme.gd` | `_plate()` degrades to flat StyleBoxFlat silently | Add a visible "running in degraded mode" notice to each build so the degradation is obvious, not invisible |
| Multiple screens | `UITheme.apply_brushed_panel()` call sites (now a no-op wrapper) | After material textures land and backdrop is verified, remove the wrapper and call `apply_backdrop()` directly |

---

## Rebuild Commands

After any change to `ui_tokens.gd` or `build_ui_theme.gd`, rebuild the theme:

```powershell
.\Godot_v4.7.1-stable_win64_console.exe --headless --script tools/build_ui_theme.gd --quit-after 2
```

After any change to hull assembly JSONs, rebuild the hull meshes:

```powershell
.\Godot_v4.7.1-stable_win64_console.exe --headless --script tools/bake_hull_roster.gd
```

---

## Open Questions

1. **Plate authoring pipeline:** Should `generate_ui_plates.py` be a Python script that produces PNGs programmatically, or are the plates hand-authored in Aseprite/Photoshop? The current code references `generate_ui_plates.py` but that file does not exist in the repo. Decision needed before Priority 2 work begins.

2. **NavCard theme variation vs. inline style:** The destination cards in the main menu use `_create_industrial_button_style()` helpers rather than a registered theme variation. The motivation was the asymmetric left border width (6 px left, 2 px others), which StyleBoxFlat expresses easily but a plate texture cannot. Options: (a) keep the inline approach for this one control, (b) register a `NavCard` variation with a flat stylebox fallback, (c) use a custom shader on the nav card buttons.

3. **Font licensing:** Before shipping any build to players, confirm the exact font files and their licence terms. SIL OFL permits bundling in commercial products; other licences may not.
