# Kitbash Command — UI Style Guide
_Distilled from the current main_menu.gd, ui_tokens.gd, ui_theme.gd, and build_ui_theme.gd implementation._
_Last updated: 2026-08-04_

---

## 1 · Design Philosophy

**The interface is an instrument housing, not a feature.**

The units are cartoonish and loud; the terrain is realistic and grounded. The UI's job is to be a quiet, credible piece of military equipment so the saturated, toy-like vehicles on screen stay the loud thing. If the chrome competes for saturation, both lose.

Three principles follow from that:

1. **Signal colour is for state, not decoration.** Amber is not a design choice for a button you like; it means *attention is required here*. Red means damage or a destructive action. Green means ready. Blue-grey means informational only. These rules must not break.
2. **Material, not colour, conveys surface identity.** Panels don't feel like panels because they're a dark rectangle; they feel like panels because they're finished in powdercoat, bakelite, or canvas. Colour follows from the material's light response.
3. **Readability over atmosphere.** The original theme ran a worn typewriter face at 13 px in a 24-row parts list. Beautiful in a screenshot, unreadable in play. The stencil face is now reserved for display headings only.

---

## 2 · Palette

All colours live in `scripts/ui_tokens.gd`. No screen should hardcode a colour literal not from that file.

### 2.1 Base (warm neutral)

The base is a **warm dark**, not the blue-black default sci-fi palette. Warm greys read further from the cool sky and water of the battlefield, so chrome separates from the world instead of blending into it.

| Token | Value (linear) | Use |
|---|---|---|
| `BASE_900` | `#13130F` | deepest recess, modal scrim |
| `BASE_800` | `#1C1B18` | panel body |
| `BASE_700` | `#252420` | raised control body |
| `BASE_600` | `#33312C` | hover fill, raised edge |
| `BASE_500` | `#4A473E` | borders, dividers |
| `BASE_400` | `#676358` | disabled text, hairlines |

### 2.2 Text

Off-white, not pure white. Pure white on warm dark reads as a blown-out highlight and vibrates at small sizes.

| Token | Value | Use |
|---|---|---|
| `TEXT_PRIMARY` | `#EFE9E5` | default body and heading text |
| `TEXT_SECONDARY` | `#ADA899` | labels, hints, metadata |
| `TEXT_DISABLED` | `#6F6B62` | unavailable controls |

### 2.3 Signal colours

**Deliberately few.** Each one means exactly one thing everywhere it appears.

| Token | Value | Meaning — never reuse for decoration |
|---|---|---|
| `SIGNAL_HAZARD` | `#E0AA2E` (amber) | attention, selection, active indicator, warnings |
| `SIGNAL_ALERT` | `#C84432` (red) | damage, failure, destructive actions |
| `SIGNAL_GO` | `#668249` (olive green) | ready, affordable, confirmed |
| `SIGNAL_INFO` | `#607FA8` (steel blue) | informational only — never an action cue |

**Dimmed variants** (for fills that sit under text):

| Token | Use |
|---|---|
| `SIGNAL_HAZARD_DIM` | amber fill behind amber-edged controls |
| `SIGNAL_ALERT_DIM` | red fill behind red-edged controls |
| `SIGNAL_GO_DIM` | green fill for progress and resource bars |

---

## 3 · Material Vocabulary

Six named surfaces, each with one job. Callers say what something is **made of**; appearance follows from that without per-call colour choices.

| Material | Texture feel | Where it belongs |
|---|---|---|
| `powdercoat` | Matte aluminium with fine grain | Panel and dock bodies, HUD chrome |
| `steel` | Brushed bare sheet, slightly cooler | Frames, rails, splitters, toolbars, backdrop |
| `bakelite` | Heavy moulded phenolic | Buttons, tabs, toggles, radial ring |
| `canvas` | Matte woven cloth | Drawer/flyout backing, tooltips, callouts |
| `carbon` | Dark carbon weave | Primary action only — at most two per screen |
| `fiberglass` | Slightly translucent laminate | Hazard placards, alert states |

Material textures are 9-sliced PNGs in `assets/textures/ui/`. The bevel is in a 12 px margin ring; the centre is flat and tileable. `build_ui_theme.gd` maps these onto StyleBoxTexture entries. **Do not apply material directly to a control's `material` property unless you have a specific runtime reason** (e.g. the backdrop shader).

### 3.1 Material defaults

Each material carries sensible defaults for `wear`, `grime`, `scale`, and `vignette` in `UITheme.MATERIAL_DEFAULTS`. Override only when the specific use-case demands it — the defaults are tuned for consistency across the whole interface.

### 3.2 The backdrop rule

The backdrop is STEEL at 0.42 brightness. Everything laid on top of it must be ABOVE that brightness. A panel at the same luminance as its backdrop has nowhere to sit — it reads as one flat field regardless of the border between them.

---

## 4 · Typography

The type scale is fixed. Do not introduce arbitrary font sizes; choose the nearest step.

| Token | Size | Face | Use |
|---|---|---|---|
| `FONT_DISPLAY` | 40 px | Stencil (Special Elite) | Title screen wordmark only |
| `FONT_TITLE` | 24 px | Stencil | Screen-level titles |
| `FONT_HEADING` | 17 px | Stencil | Panel/section headers |
| `FONT_BODY` | 15 px | UI sans (default) | All normal reading text |
| `FONT_SMALL` | 13 px | UI sans | Secondary/hint text |
| `FONT_MICRO` | 11 px | Monospace | Dense tabular readouts, footnotes |

**Face allocation:**
- **Stencil (Special Elite):** display/title/heading only. Large, short, carrying the aesthetic tone. At body size it becomes unreadable mush.
- **UI sans (Inter or similar):** everything else. Clean, legible, fast to parse.
- **Monospace:** numeric readouts that need tabular alignment (`HUDValueLabel`, `StatLabel`). Prevents a resource counter from changing width as it ticks.

### 4.1 Theme variations (the full registry)

Set `theme_type_variation` — do not override individual font/color properties unless you're adjusting a *specific instance* from its type default.

| Variation | Base class | Notes |
|---|---|---|
| `DisplayLabel` | Label | 40 px stencil, primary text colour |
| `TitleLabel` | Label | 24 px stencil, primary text colour |
| `HeadingLabel` | Label | 17 px stencil, **amber** (`SIGNAL_HAZARD`) |
| `HintLabel` | Label | 13 px sans, secondary text colour |
| `HUDValueLabel` | Label | 17 px monospace, primary text colour |
| `StatLabel` | Label | 13 px monospace, secondary text colour |
| `CardPanel` | PanelContainer | Powdercoat, SPACE_XL/LG padding — for free-floating cards |
| `HeaderPanel` | PanelContainer | BASE_700 fill + 2 px amber bottom rule — for titled bands |
| `HUDPanel` | PanelContainer | Powdercoat pressed — recessed in-match chrome |
| `InsetPanel` | PanelContainer | Canvas pressed — drawer/list wells |
| `DockPanel` | PanelContainer | Powdercoat, SPACE_SM padding — sidebar docks |
| `DockRail` | PanelContainer | Steel, XS padding — thin rail strips |
| `FlyoutPanel` | PanelContainer | Canvas, MD padding — floating overlays |
| `CalloutPanel` | PanelContainer | Canvas, XS padding — annotation callouts |
| `PrimaryButton` | Button | Carbon tinted go-green — one per screen maximum |
| `DangerButton` | Button | Fiberglass tinted alert-red — destructive actions |
| `TabButton` | Button | Bakelite — inactive tabs are PRESSED, active tab lifts |
| `ListButton` | Button | Flat/borderless at rest, hazard left edge when selected |

---

## 5 · Spacing

**4 px base grid.** Every margin and gap must be one of the tokens below.

| Token | Value | Typical use |
|---|---|---|
| `SPACE_XS` | 4 px | tight gutter, icon padding |
| `SPACE_SM` | 8 px | element separation, inner card padding |
| `SPACE_MD` | 12 px | standard padding inside panels |
| `SPACE_LG` | 20 px | section separation |
| `SPACE_XL` | 32 px | screen-level margins, modal card padding |

**Minimum hit target:** `HIT_TARGET_MIN = 32 px`. Nothing interactive should be smaller during real-time play.

**Toolbar height:** `TOOLBAR_HEIGHT = 44 px`. The Design Lab top toolbar owns this slot; no dock or panel should begin above it.

---

## 6 · Geometry

Near-square corners. Stamped and machined panels have a barely-broken edge — 2 px is enough to prevent aliasing without reading as "consumer-software soft".

| Token | Value | Use |
|---|---|---|
| `RADIUS_PANEL` | 2 px | panel and card corners |
| `RADIUS_CONTROL` | 2 px | button and input corners |
| `BORDER_HAIRLINE` | 1 px | standard borders, dividers |
| `BORDER_EMPHASIS` | 2 px | active states, focus rings, accent rules |

---

## 7 · Layout Structure — Main Menu

The current main menu establishes a pattern the other out-of-match screens should follow.

```
┌─────────────────────────────────────────────────────────┐
│  CONSOLE BAR  (HeaderPanel, full-width, SPACE_LG gap)   │
│  "DESIGN BUREAU / CONSOLE 04"   STATUS   CYCLE INFO     │
├──────────────────┬──────────────┬───────────────────────┤
│  LEFT COLUMN     │  3D VIEWPORT │  STATUS COLUMN        │
│  520 px fixed    │  (flexible)  │  460 px fixed         │
│                  │              │                        │
│  KITBASH COMMAND │  SubViewport │  SPECIFICATION PLACARD│
│  tagline         │  background  │  (CardPanel)           │
│                  │  TURNTABLE   │                        │
│  ┌ Destination ┐ │              │  stat_row × N         │
│  │ Card × 6   │ │              │  (HintLabel / StatLabel│
│  └────────────┘ │              │   pairs)               │
│                  │              │                        │
│  EXIT BUREAU btn │              │                        │
└──────────────────┴──────────────┴───────────────────────┘
```

**Destination card anatomy:**

```
[ 5px amber gutter | TITLE (HeadingLabel) / desc (HintLabel) | BADGE (HintLabel, dark plate) ]
```

- Normal state: dark fill (`BASE 12–15%`) + subtle border (`BASE_400`, ~95% alpha)
- Hover state: slightly lifted fill + amber border (left edge 6 px, others 2 px)
- Pressed state: warm amber-tinted fill + amber border
- The `indicator` (amber 5 px vertical bar at left) shows/hides on hover — not a full border change, just the strip going from `alpha 0 → 1`

**3D showcase:**
- Full-bleed SubViewport behind all 2D chrome. ACES filmic tonemapping, SSAO, bloom.
- Studio grey background (`#626669`), warm key light (`#FFF5E0` at 1.35 energy), cool rim (`#A5BFDA` at 0.85 energy).
- Models rendered in scale-model plastic: `Color(0.38, 0.44, 0.37)`, metallic 0, roughness 0.8.
- Auto-cycles every 30 seconds through saved blueprints then hull chassis fallbacks.

---

## 8 · Interaction & State

**Focus:** A flat `SIGNAL_HAZARD` hairline (2 px) overlay — no fill change. Focus is interface state, not a change of the control's material.

**Hover:** Lift the fill one step (BASE_700 → BASE_600) or switch to the material's "hover" plate. Do not change the signal colour or introduce a new colour; hover is not meaningful state — it is a readiness cue.

**Pressed/Selected:** Invert the bevel (switch to the "pressed" plate) so the control reads as physically moving down. Tabs invert the direction — inactive tabs are PRESSED (sunk), the active tab LIFTS.

**Disabled:** The material's "disabled" plate (held darker, muted bevel) plus `TEXT_DISABLED` font colour. Icons dim alongside the control.

---

## 9 · What This Guide Does Not Cover

- **3D art direction** (hull materials, faction colours, terrain shaders) — see `VISUAL_ART_DIRECTION.md`
- **HUD layout during battle** — the HUD has its own geometry constraints; this guide covers out-of-match screens
- **Animation and audio feedback** — handled in `ui_anim.gd` and `audio_manager.gd`; not specified here
