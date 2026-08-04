# Gritty Instrument-Housing UI — Materials, Docks, Radial Tweaking

## Context

The game's premise is a straight-faced military-industrial world in which players bolt
absurd kitbashed contraptions together. `scripts/ui_tokens.gd` already states the correct
strategy for that split: *the interface is the serious half, a quiet credible instrument
housing so the saturated toy-like units read as the loud thing on screen.* The palette,
type scale and 4px grid in that file are right and stay.

Two things stop it from landing:

**1. The interface is flat color, not material.** `tools/build_ui_theme.gd` emits
`StyleBoxFlat` only — solid fills, hairline borders. There is exactly one real surface in
the whole UI (`shaders/brushed_aluminum_panel.gdshader`), and it is used only as a
backdrop behind everything. Nothing reads as steel, canvas, bakelite or powdercoat because
nothing has a surface.

**2. The design system reaches about half the screen — again.** The header comment in
`ui_tokens.gd` describes exactly this failure and the codebase has drifted back into it.
`scripts/parts_menu.gd:175-210` hand-rolls "heavy bakelite toggle" styleboxes that
duplicate what `build_ui_theme.gd` already builds for `Button`. `scripts/skirmish.gd` has
~12 inline `StyleBoxFlat.new()` sites. `scripts/tweak_callout.gd:22-35`,
`scripts/ui_stamp.gd:22-33`, and both `scenes/UI_PartsMenu.tscn` and
`scenes/UI_StatBlock.tscn` carry their own hardcoded panel styles. Local overrides beat the
theme, so these actively prevent the design system from reaching those controls.

**3. The Design Lab is two static rails around a dead viewport.** From
`progress_captures/2026-07-30/ui_pass12/main_lab.png`: a permanent 320px parts column of 25
identical text rows on the left, a permanent stat column on the right holding armor
material, faction, thickness, undo/redo and three saturated action buttons — all visible
always, whether or not they apply to anything selected. The 3D model, the actual subject,
gets the leftover middle.

**4. The tone rule is written down, followed in one file, and broken in the UI copy.**
`scripts/blueprint_namer.gd:6-13` states it exactly right: *"The joke is structural, not
written. Nothing in the word lists is trying to be funny on its own… the comedy comes from
the designation format treating whatever falls out with complete bureaucratic
seriousness."* That is the governing law and it should extend to every string in the game.
It currently doesn't — see item 0 below.

**Intended outcome:** a UI that feels like Cold War-era hardware — powdercoated steel
panels, bakelite switches, canvas-backed drawers, stencil placards — where chrome gets out
of the way by default (collapsing and auto-hiding docks), and controls appear next to the
thing they act on (contextual flyouts and the radial tweak ring) rather than being parked
permanently in a rail.

---

## Direction: six material classes

Every surface in the game gets assigned one of six materials. This is the vocabulary that
replaces "pick a background color."

| Class | Where it's used | Reads as |
|---|---|---|
| `POWDERCOAT` | Panel and dock bodies, HUD chrome | Matte olive-grey enamel over steel, faint orange-peel, bright top edge / dark bottom edge |
| `STEEL` | Frames, rails, splitters, toolbars, dividers | Brushed grain along the long axis, anisotropic sheen |
| `BAKELITE` | Buttons, tabs, toggles, radial ring items | Dark phenolic, molded radius, slight gloss, faint marbling |
| `CANVAS` | Drawer/flyout backing, tooltips, tooltip-adjacent soft surfaces | Woven duck weave, matte, takes a stencil well |
| `CARBON` | Primary action only, drag-handle grips | 2×2 twill, tight weave — **sparing, ≤2 places per screen** |
| `FIBERGLASS` | Hazard placards, warning/alert states | Translucent resin over glass mat, slightly milky |

Two rendering mechanisms, chosen per surface size:

- **9-slice textures** for small repeated widgets (buttons, tabs, fields, list rows). These
  live inside `StyleBoxTexture`, which means `Theme` can carry them — so reauthoring
  `build_ui_theme.gd` repaints every `Button`/`Panel`/`OptionButton` in the game at once
  with zero call-site edits. This is the highest-leverage change in the plan.
- **`canvas_item` shaders** for large continuous surfaces (dock bodies, backdrops, the
  radial ring bezel) where a tiled 9-slice would show its repeat. Resolution-independent,
  same approach `brushed_aluminum_panel.gdshader` already proved.

---

## Work items

### 0. Voice: play it completely straight

The battle system is cartoonishly ridiculous. The interface's entire job is to refuse to
acknowledge that. The contrast *is* the comedy, and it only works if the chrome never
winks — a UI that signals "we know this is funny" collapses the joke and takes the
seriousness of the world down with it. `blueprint_namer.gd`'s rule generalises to three
hard constraints:

- **No emoji, no decorative glyphs, no stars.** These are the joke written out loud, and
  they are also a consumer-software tell that fights every material in item 1. Current
  offenders: `main_menu.gd:106` (`"★ " + TITLE + " ★"`), `main_menu.gd:132-136` (⚔️🔧🗺️🎯🛠️
  on every nav item), `main_menu.gd:278`, `stat_calculator.gd:415` (`"★ SAVE BLUEPRINT"`),
  `stat_calculator.gd:1221` (`"🛠️ " + module name`), `ui_stamp.gd:41` (`"★ %s ★"`),
  `hull_builder.gd:1437`, `after_action_report.gd:214,231`, `skirmish.gd:1993`. Replace with
  the icons already registered in `scripts/ui_icons.gd` (there is a `wrench`, a `target`, a
  `hull`, a `weapon` — the registry exists and is unused at these sites) or with nothing.
- **Procurement-form register.** Labels read like equipment documentation, not like game
  menus: mass in kg, part numbers, threshold tables, "APPROVED FOR FIELD TEST". The
  existing `UIStamp` texts are the right voice; `parts_menu`'s "HARDWARE CATALOG" is right.
  `main_menu.gd:139`'s "PWR OFF / QUIT" is trying too hard — "QUIT" is funnier.
- **Stencil the absurd hardware as though it were certified.** A player's ludicrous
  contraption should get a stencilled designation, a mass figure, a faction stamp and an
  armor threshold table presented with total indifference. The stencil face
  (`StencilFont-Regular.ttf`, already wired to `DisplayLabel`/`TitleLabel`/`HeadingLabel`)
  and `VISUAL_ART_DIRECTION.md`'s decal library are the delivery mechanism.

**A regression to fix while here:** commit `1ba74b8` ("UI overhaul: title screen rebuild")
replaced the restrained typographic main menu visible in `ui_pass12/main_menu.png` with a
saturated green-phosphor CRT terminal — `main_menu.gd:108` sets a `Color(0.2, 1.0, 0.5)`
title, `:94` a green ticker, plus star-wrapped title, emoji nav, and inline `StyleBoxFlat`s
at `:140-149`. That palette appears nowhere in `ui_tokens.gd` and contradicts the warm-
neutral direction its header comment argues for at length. Green-terminal is also the most
over-used "military UI" shorthand there is; the tokens' warm powdercoat is both more
specific and more period-correct. Revert to the token palette and the `UIShell` structure.

`UIStamp` (`scripts/ui_stamp.gd`) keeps its own look — it is ink on paper, deliberately not
chrome — but should become an actual rubber stamp: no stars, hard stencil letterforms,
uneven ink coverage, rotated a few degrees, colored from `Tokens.SIGNAL_GO` /
`SIGNAL_ALERT` / `SIGNAL_HAZARD` instead of the literal saturated greens and reds passed in
at `stat_calculator.gd:821,833,955`.

### 1. Material plate generator — `tools/generate_ui_plates.py`

New procedural texture generator in the same idiom as the existing
`generate_effect_textures.py` / `tools/generate_icons.py` (PIL + numpy, both verified
present). Outputs to `prototype/assets/textures/ui/`.

Per material class, emit a 9-sliceable plate at 96×96 with a 12px margin, in four states —
`normal`, `hover`, `pressed`, `disabled` — plus a large 512×512 tileable field for the
shader fallback. 6 classes × 4 states = 24 plates + 6 fields.

Key detail (this is the one that will look wrong if skipped): the **corner and edge regions
must carry the bevel, and the center must be flat-tileable**, or 9-slice stretching smears
the highlight. Bake the top-edge highlight and bottom-edge shadow into the margin only.

Reuse the fbm/noise helpers already written in `generate_effect_textures.py` rather than
writing new ones.

Run once, commit the PNGs, then `Godot_v4.3-stable_win64_console.exe --headless --editor
--import` (same step `README.md` documents for `.glb`).

### 2. UI material shader — `prototype/shaders/ui_material.gdshader`

Generalise `brushed_aluminum_panel.gdshader` rather than replacing it. Keep its two hard-won
properties, both documented in its header comment and both easy to regress:

- Feature size driven by a `panel_size` uniform in **pixels**, not UV, so grain is the same
  physical size on a 320px dock and a fullscreen backdrop.
- Chrome stays neutral; `accent_tint` is a low-strength identity wash for the faction
  preview swatch only, never general chrome.

Add a `material_class` int uniform selecting between the six surfaces, plus `wear_amount`
and `grime_amount` dials mirroring `VISUAL_ART_DIRECTION.md`'s parameter model so the 2D
chrome and the 3D hulls speak the same language.

`scripts/ui_theme.gd:apply_backdrop()` already handles the `panel_size` push and the
`resized` reconnect correctly — extend that function with a class argument rather than
adding a second, competing applier.

### 3. Reauthor `tools/build_ui_theme.gd` around materials

The theme builder is regenerated, not hand-edited (`resources/bomber_theme.tres` is an
artifact — its header says so). Replace the `_flat()` helper's role with a
`_plate(material_class, state)` helper returning a `StyleBoxTexture` with correct
`texture_margin_*` and `content_margin_*`.

Assignments:
- `Panel` / `PanelContainer` / `CardPanel` / `HUDPanel` → `POWDERCOAT`
- `InsetPanel` → `CANVAS` (a recessed well backed with duck)
- `Button` / `OptionButton` / `MenuButton` / `TabButton` → `BAKELITE`
- `PrimaryButton` → `CARBON` with a `SIGNAL_GO` edge
- `DangerButton` → `FIBERGLASS` with a `SIGNAL_ALERT` edge (a hazard placard, not a red fill)
- `ListButton` → stays flat/borderless at rest; a long list must read as a list
- `HeaderPanel` → `STEEL` band, keeps its hazard underline

Preserve the existing physical press language — `border_width_bottom = 6` at rest flattening
to `2` with a `6` top on press, from `build_ui_theme.gd:189-203`. That already reads as a
switch being depressed; it just needs to sit on a material now.

**Two documented traps in that file that must survive the rewrite** (both cost real debugging
time before, both fail silently):
- `_register_variations()` must run **last**. `set_type_variation()` only takes on a theme
  type that already exists; called earlier it is discarded with no error.
- The setter is `set_type_variation()`; `set_type_variation_base()` does not exist and, in a
  `@tool MainLoop`, calling it does not abort the build — the theme saves "successfully" with
  variations missing.

Add `TabButton`, `ListButton` etc. plate entries to `VARIATION_BASES` as needed, and add the
new variation names to `UITheme.KNOWN_VARIATIONS` (`scripts/ui_theme.gd:80`) so typos keep
warning.

### 4. Dock primitive — `prototype/scripts/ui_dock.gd`

New reusable `Control` subclass. This is the "disappearing and collapsing docks" ask.

Three states, cycled by the header's chevron and by a keybind:
- **Expanded** — full body visible.
- **Railed** — collapsed to a ~40px icon strip; tab glyphs remain clickable, expanding on
  click. This is the old-IDE behaviour.
- **Hidden** — fully off-edge, leaving a thin grab tab. Hovering the screen edge slides it
  back in; it re-hides on mouse-out. **Auto-hide is opt-in per dock and OFF by default in
  Skirmish** — a dock that vanishes mid-fight costs the player the fight.

Also: edge-anchored (left/right/bottom), draggable splitter for width, `STEEL` frame with a
`POWDERCOAT` body, state persisted to `user://ui_layout.cfg`.

Reuse `scripts/ui_anim.gd`'s `DURATION_NORMAL` / `TRANS_STANDARD` for slide timing so docks
move on the same clock as everything else — do not hand-roll new tween timings.

Critical layout note, learned in `parts_menu.gd:389-408`: a collapsed container must be a
plain `Control` clip wrapper with `custom_minimum_size` driven directly, **not** a
`Container` with `clip_contents`. A `Container` propagates its children's combined minimum
size to its parent regardless of clipping, so a collapsed dock would still demand its full
expanded width. Set `ui_audit_clip_ok` meta on the clip wrapper (see `ui_audit.gd:11-25`
for why that opt-out is a stated flag and not inferred).

### 5. Contextual flyout primitive — `prototype/scripts/ui_flyout.gd`

The "menu subparts like an old IDE popping up contextually" ask. A transient panel anchored
either to a source `Control` (rect-relative, with automatic screen-edge flipping) or to a
screen point. Dismissed on outside-click or Esc. `CANVAS` backing, `STEEL` edge.

This is what lets things leave the permanent rails: armor material picker, faction picker,
blueprint namer, part detail card, debug/options — each becomes a flyout off a toolbar
button instead of a row parked in the sidebar forever.

### 6. Finish the radial tweak system (Design Lab)

The existing implementation is genuinely half-built, and in a specific way:
`stat_calculator.gd:1144-1161` computes an 8-point radial ring (`_callout_dirs`) and a
per-index `dist`, passes both into `TweakCallout._init()` — and `tweak_callout.gd:154-179`
**ignores both**, stacking satellites in left/right columns instead. The ring is the design
intent; the column stack is the placeholder.

Split it into the two things it's trying to be:

**a. Radial action ring** — on part selection, a compact ring of *actions* around the part:
rotate, mirror, detail, delete. Discrete choices, hold-and-flick or click. This is what
`ui_mockup_v2/style.css`'s `.radial-menu` sketches (N/E/S/W items, pop-in, info tag), ported
into Godot as a drawn `Control` with a machined `STEEL` bezel so it reads as an instrument
dial rather than a floating tooltip. `ui_anim.slide_in()` won't fit a scale pop — add one
`ring_pop()` to `ui_anim.gd` rather than hand-rolling at the call site.

**b. Callout constellation** — the live tweak sliders (barrel length, caliber, wheel size,
blade count) stay as leader-lined callouts, because each holds a continuous control that a
pie slice can't. Make `tweak_callout.gd` actually honour the `dir`/`dist` it already
receives:
- Place each satellite along its ring direction at `dist`.
- Resolve overlaps by pushing outward along the ray until clear, then re-run — not by
  falling back to a column.
- Clamp to the viewport rect; when a direction would go off-screen, reflect it across the
  hub before clamping so the leader line doesn't cross the model.
- Keep `_get_target_offset()` (`tweak_callout.gd:231-253`) as-is — pointing the "Barrel
  Length" line at the muzzle and "Caliber" at the breech is the detail that sells this as an
  engineering drawing, and it already works.

Restyle the callout panel to `CANVAS` with a hazard left-edge, replacing the inline
`StyleBoxFlat` at `tweak_callout.gd:22-35`.

This directly serves `DESIGN_VISION.md`'s stated test — continuous tweaks with live stat
feedback are the differentiator, so the tweak controls should be the most prominent
interaction in the Lab, not sidebar rows.

### 7. Apply — Design Lab (`scenes/MainLab.tscn`, `UI_PartsMenu.tscn`, `UI_StatBlock.tscn`)

- Parts catalog → left `UIDock`, railed by default, expanding on hover/click. Keep
  `parts_menu.gd`'s grouping, light-to-heavy sort, search, and count badges — that logic is
  good and the reasoning is documented at `parts_menu.gd:19-48`. **Delete** its inline
  bakelite styleboxes (`parts_menu.gd:175-210`) and drawer header colors
  (`parts_menu.gd:360-370`); both are now the theme's job.
- Stat block → right `UIDock`, railed by default, showing only the blueprint identity +
  headline stats. Armor material, faction, thickness move into flyouts off a top toolbar.
- New thin top toolbar: `STEEL`, holds undo/redo, mirror toggle, save/test/library, and the
  flyout triggers. Undo/redo belong on a toolbar, not stacked in a stat column.
- Delete the `PanelStyle_Parts` and `PanelStyle_Stats` sub-resources from the two `.tscn`
  files so the theme reaches them.

### 8. Apply — Skirmish HUD (`scripts/skirmish.gd`)

Replace the ~12 inline `StyleBoxFlat.new()` sites (lines ~1675, 1738, 1855, 1884, 2041,
2124, 2195, 2809, 3128, 3175) with theme variations. Build bar, queue panel and minimap
become docks — but **collapsible only, never auto-hiding**, and every clickable stays at or
above `Tokens.HIT_TARGET_MIN`. Real-time play is the one place where chrome disappearing on
its own is a defect rather than a feature.

### 9. Apply — shell screens

`match_setup.gd` and `operations_setup.gd` are the most coherent screens in the game —
they mainly need the materials from items 1–3, which arrive for free.

> Corrected 2026-08-04: this used to say these screens "already use
> `UIShell.build_screen()`", and also listed `map_select.gd`. Neither held —
> `build_screen()` had no call sites at all and has been removed along with the
> rest of the unused shell API (`ui_shell.gd` is now just `stat_row()`), and
> MapSelect was folded into `match_setup.gd`'s map dropdown. These two screens
> build their layouts directly, so the materials pass has to style them as they
> are rather than inheriting from a shared scaffold.

`main_menu.gd` needs the item-0 revert first (green CRT palette, stars, emoji, inline
styleboxes), then the dead middle third visible in `ui_pass12/main_menu.png` gets filled: a
`POWDERCOAT` plate carrying a stencilled unit designation, mass, faction stamp and armor
threshold table for the most recent design — data `main_menu.gd` already loads. Presenting
a "GoatHauler Mk VI" on a spec placard with total deadpan is the thesis of the whole
interface in one panel.

### 10. Sweep the remaining inline styles

`scripts/blueprint_library_panel.gd`, `scripts/debug_tuning_panel.gd`,
`scripts/fleet_comparison_panel.gd`, `scripts/after_action_report.gd` — same treatment as
items 7–9: delete local `StyleBoxFlat` overrides, adopt theme variations, strip decorative
glyphs per item 0.

---

## Critical files

| File | Change |
|---|---|
| `prototype/tools/generate_ui_plates.py` | **new** — material plate textures |
| `prototype/shaders/ui_material.gdshader` | **new** — generalised from `brushed_aluminum_panel.gdshader` |
| `prototype/scripts/ui_dock.gd` | **new** — collapsing/auto-hiding dock |
| `prototype/scripts/ui_flyout.gd` | **new** — contextual popup |
| `prototype/tools/build_ui_theme.gd` | reauthor around `StyleBoxTexture` |
| `prototype/scripts/ui_tokens.gd` | add material-class enum; palette unchanged |
| `prototype/scripts/ui_theme.gd` | extend `apply_backdrop()` with material class; extend `KNOWN_VARIATIONS` |
| `prototype/scripts/tweak_callout.gd` | honour `dir`/`dist`; overlap + edge resolution; themed panel |
| `prototype/scripts/stat_calculator.gd` | add radial action ring; move sidebar rows to flyouts |
| `prototype/scripts/parts_menu.gd` | strip inline styleboxes; host in a dock |
| `prototype/scripts/skirmish.gd` | strip ~12 inline styleboxes; dock the build bar |
| `prototype/scripts/main_menu.gd` | revert green-CRT regression to token palette; strip stars/emoji; spec-placard panel |
| `prototype/scripts/ui_stamp.gd` | real rubber stamp — stencil, ink bleed, signal colors, no stars |
| `prototype/scenes/UI_PartsMenu.tscn`, `UI_StatBlock.tscn` | drop embedded `StyleBoxFlat` sub-resources |

---

## Verification

1. **Regenerate assets**, in order — the theme references textures that must exist and be
   imported first:
   ```bash
   cd prototype && python tools/generate_ui_plates.py && ./Godot_v4.3-stable_win64_console.exe --headless --editor --import && ./Godot_v4.3-stable_win64_console.exe --headless --script tools/build_ui_theme.gd --quit-after 2
   ```

2. **Test suite** — must stay green, and `test_ui_no_overflow_or_offscreen` /
   `test_ui_audit_has_real_teeth` are the two that will actually catch dock and flyout
   layout mistakes:
   ```bash
   cd prototype && ./run_tests.ps1
   ```

3. **New coverage** to add to `run_tests.gd`: a dock cycles expanded → railed → hidden and
   back with the correct widths; a railed dock reports its rail width as minimum size, not
   its expanded width (the `Container` propagation trap in item 4); a flyout anchored near a
   screen edge stays inside the viewport rect; radial callouts around a selected module do
   not overlap each other and stay on-screen. Plus a **tone guard**: walk every `Control` in
   each screen and fail on any label/button text containing a character in the emoji or
   dingbat ranges. Cheap, and it stops item 0 from silently regressing the way `main_menu.gd`
   already did once.

4. **Visual capture** — screenshot `MainLab`, `MainMenu`, `MapSelect`, `MatchSetup` and
   `Skirmish` into `progress_captures/2026-08-02-ui-materials/` and compare against
   `progress_captures/2026-07-30/ui_pass12/`. The scratch capture scenes in
   `prototype/scratch/` are the existing pattern for this.

5. **Play it** — open the Design Lab, place a weapon, select it, and confirm the radial ring
   and the tweak callouts appear on the model rather than in a rail; confirm both docks rail
   away and the viewport gets the screen.
   ```bash
   cd prototype && ./Godot_v4.3-stable_win64.exe
   ```

---

## Sequencing

Item 0 first — it is a handful of string and color edits, it undoes a live regression, and
it settles the tone question before any pixel work is judged against it.

Then items 1–3 together — they are the foundation and they repaint every screen at once, so
their result should be reviewed before any layout work starts. Then 4–5 (the primitives),
then 6–7 (the Design Lab, the flagship), then 8–9 (HUD and shell), then 10 (the sweep).
Each of 6–10 is independently shippable.

Worth stating once, since it governs every judgement call below: **the interface never
acknowledges that the fleets are ridiculous.** It is a well-made instrument housing that
would look identical if the player were designing real ordnance. Everything funny on screen
should be something the player built, framed by chrome that treats it as routine.
