Design an implementation plan for the \*\*2D UI chrome overhaul\*\* of a Godot 4.3 RTS at C:\\Misc\\Build-A-Bomber\\prototype. Report a detailed, concrete plan — file paths, resource names, function signatures, sequencing. Do NOT modify anything.



\## Established facts from exploration (trust these, verify only what you need to design against)



\*\*Engine/project:\*\* Godot 4.3 stable, Forward+. `prototype/project.godot` is minimal (41 lines): viewport 1280x720, `window/stretch/mode="canvas\_items"`, `aspect="expand"`. NO `\[gui]` section, NO `gui/theme/custom`, NO anti-aliasing keys (MSAA fully off), NO default environment. One autoload: `MatchConfig="\*res://scripts/match\_config.gd"`. NO `\[input]` section at all — every input is raw `InputEventKey` keycodes in `\_unhandled\_input`.



\*\*There is no Theme resource anywhere in the project. There are zero `.tres`/`.res` files at all.\*\* Every stylebox, font size and color is either a `.tscn` `\[sub\_resource]` or built inline in GDScript.



\*\*There are no fonts.\*\* Everything renders in Godot 4.3's bundled default font. Sizes in use: 12,14,15,16,18,20,22,34,40,64 via `theme\_override\_font\_sizes/font\_size` and `add\_theme\_font\_size\_override`.



\*\*There is no custom mouse cursor.\*\* Zero hits for `Input.set\_custom\_mouse\_cursor`, `DisplayServer.cursor\_set\_\*`, `mouse\_default\_cursor\_shape`, `Input.mouse\_mode`. The OS arrow is used everywhere, including over the battlefield.



\*\*There are no UI textures/icons.\*\* No `TextureRect`, `TextureButton`, `TextureProgressBar`, no 9-patch. All "icons" are emoji in Button/Label text: `🏭 ⛽ ⚡ 💰 💎 🛡 ⚙ ⛏ 🔧 ⚔️ 🎯 🚪 ◀ ▶ ↶ ↷ 🔄 ■ □ 🏆 💀`. The default font has no color-emoji coverage so these fall back per-platform.



\*\*`prototype/icon.svg` is the untouched Godot placeholder\*\* (a `#478cbf` rect). `export\_presets.cfg` sets `application/icon\_path=""` on all three presets.



\### The only shared theming API

`prototype/scripts/ui\_theme.gd` (50 lines, `class\_name UITheme`, extends RefCounted):

\- `apply\_brushed\_panel(node: CanvasItem, faction: String, tint\_strength := 0.55)` — stamps a `ShaderMaterial` wrapping `res://shaders/brushed\_aluminum\_panel.gdshader` onto any CanvasItem's `.material`, feeding `faction\_tint`/`wear\_amount`/`tint\_strength` from `faction\_catalog.gd`. Reuses the existing material on re-theme.

\- `style\_option\_button(btn)`, `style\_slider(slider)` — small StyleBoxFlat overrides; both carry comments noting they were silently no-ops until a Godot-3 API call was removed.

Callers: `main\_menu.gd:19`, `map\_select.gd:28`, `match\_setup.gd:173`, `skirmish.gd:935` and `:994`, `stat\_calculator.gd:227`, `parts\_menu.gd:39`.



`prototype/shaders/brushed\_aluminum\_panel.gdshader` — 48-line `canvas\_item` shader, procedural brushed streaks + two-octave grime, uniforms `faction\_tint`/`wear\_amount`/`tint\_strength`.



\### Every UI surface, exhaustively



\*\*Editor-built .tscn (only 3 of 10 scenes have real UI):\*\*

\- `prototype/scenes/UI\_StatBlock.tscn` + `prototype/scripts/stat\_calculator.gd` (1414 lines) — Design Lab right sidebar (300px anchored right) + floating module popup. Editor nodes: Panel → ScrollContainer/VBoxContainer with Title, BlueprintNameEdit (LineEdit), LibraryButton, MirrorCheckBox, HP/Weight/Cost/DPS labels, LocomotionTweaks (Size + Count HSliders), Delete/Save/Test buttons. At runtime `\_ready()` adds much more in code: armor-material OptionButton, faction OptionButton, armor-thickness/nose-taper HSliders, wheels-per-axle/blade-count/blade-pitch/helix-depth sliders, a "Ducted Shroud" CheckButton, ModuleTweaksContainer, Undo/Redo row, Main Menu button, and a floating `ModulePopup` PanelContainer (inline StyleBoxFlat: bg 0.1,0.1,0.12,0.9, 2px cyan border, corner radius 8, shadow size 12) that tracks the selected module's 3D→2D screen position every frame in `\_process`. `\_style\_action\_button()` at line 555 builds per-button StyleBoxFlat normal/hover/pressed — delete red, save green, test blue, library purple.

\- `prototype/scenes/UI\_PartsMenu.tscn` + `prototype/scripts/parts\_menu.gd` (187 lines) — Design Lab left Parts Catalog (300px anchored left): PanelContainer → VBox → "PARTS CATALOG" Label → TabContainer with Hulls/Modules/Locomotion ScrollContainers. In code it populates catalog buttons (`part\_button.gd` attached, per-button StyleBoxFlat colored from `ModuleCatalog`'s `color` field, `darkened(0.3)` 4px bottom border, `lightened(0.2)` hover) plus collapsible drawer groups (`\_make\_collapsible\_drawer`, gold-bordered header). Stat-preview `tooltip\_text` on every button.

\- `prototype/scenes/Battlefield.tscn` + `prototype/scripts/battlefield.gd` (241 lines) — Test Range: a Control + two default-gray Buttons with font\_size 18. Adds `PlayerHPLabel` in code (font 24, ASCII `■□` bar, modulate lerped green→red) and instantiates DebugTuningPanel.

\- `prototype/scenes/MainLab.tscn` — hosts UI\_StatBlock + UI\_PartsMenu instances, a DragDropOverlay Control (`drag\_drop\_manager.gd`), a DragHintLabel with inline font/shadow overrides.



\*\*Stub scenes — one root Control + a script, all content built in code:\*\*

\- `prototype/scripts/main\_menu.gd` (70 lines) — full-rect ColorRect bg with brushed shader, CenterContainer/VBox, "BUILD-A-BOMBER" Label font 64 `modulate(1.0,0.75,0.25)`, subtitle 16, 4 emoji buttons (340x54, font 22) each with a 12pt hint Label below. Buttons are DEFAULT GODOT GRAY — no styleboxes at all.

\- `prototype/scripts/map\_select.gd` (91 lines) — bg ColorRect, "SELECT MAP" 40pt gold, ScrollContainer of 420x50 map buttons + wrapped description labels, Back button. No styleboxes.

\- `prototype/scripts/match\_setup.gd` (233 lines) — "MATCH SETTINGS" 34pt gold, 2-col GridContainer of 4 OptionButtons (faction/enemy/difficulty/resources), blueprint checkbox list in a ScrollContainer, color-coded selection counter, Back / "Start Match ▶". `\_refresh\_theme` re-tints bg\_rect live on faction change.

\- `prototype/scripts/skirmish.gd` (1466 lines) — `\_build\_ui()` at \*\*line 921\*\*, all in a code-created CanvasLayer: top-bar PanelContainer (68px, brushed shader tint 0.4), `resource\_label` (font 22, metal/crystal/Base Power), `status\_label` (15, flashes gold via `\_flash\_status`), `intel\_label` (right-aligned 15, \*\*hardcoded `position = Vector2(700,14)`, `size = Vector2(460,40)`, unanchored\*\*), a "Menu" Button at \*\*hardcoded `Vector2(1180,14)`\*\* with its own radius-5 StyleBoxFlat, bottom build bar PanelContainer (96px) → ScrollContainer → HBoxContainer of 120x80 buttons, and the drag-select Panel with a translucent green StyleBoxFlat. `\_add\_build\_button(text, color, callback)` at line 1050 makes a per-button StyleBoxFlat + `lightened(0.2)` hover, corner radius 6. `\_on\_hq\_died` at line 1399 builds the victory/defeat overlay: ColorRect dim + PanelContainer card with gold/red border, 64pt 🏆/💀 title, subtitle, styled "Return to Menu" button.

\- `prototype/scripts/blueprint\_library\_panel.gd` (221 lines) — modal overlay: 55%-black backdrop ColorRect, centered 520x480 PanelContainer, MarginContainer, header + Close, scrolling rows with Load/Rename/Duplicate/Delete. Uses native ConfirmationDialog/AcceptDialog. \*\*No styleboxes at all\*\* — default panel + modulate tints.

\- `prototype/scripts/debug\_tuning\_panel.gd` (130 lines) — F1 overlay in Test Range: PanelContainer + 4 label/HSlider pairs + respawn button. Default panel, modulate only.

\- `prototype/scripts/part\_button.gd` (16 lines) — `extends Button`; `\_get\_drag\_data()` builds a bare unstyled Label inside a Control as the drag preview.



\*\*Diegetic in-world "UI" (Label3D, no Control nodes) — replace these too:\*\*

\- `battle\_unit.gd:601-621` `\_create\_hp\_bar`/`\_update\_hp\_bar` — billboard Label3D, font 22, outline 5, text is an 8-cell `■□` bar + `⛏` cargo glyph, modulate green/orange-red lerped to red.

\- `building.gd:255-262, 310-323` — billboard Label3D (font 24, outline 5) showing KIND + 10-cell `■□` bar + `⚙ NN%` production progress; refreshed \*\*every physics frame\*\* while a job is active.

\- `resource\_node.gd:49-60` — Label3D (font 20, outline 4) "METAL: n"/"CRYSTAL: n".

\- `target\_dummy.gd:44` — Label3D font 28, outline 6, `■□` bar.

\- Selection rings: `TorusMesh` + unshaded emissive green `Color(0.3,1.0,0.4)` at `battle\_unit.gd:584` and `building.gd:264-278`, `visible=false` until `set\_selected()`.



\### Two real defects to fold into the fix

1\. \*\*15 invalid theme property paths\*\* — both Design Lab .tscn files use a nonexistent `theme\_overrides/…` prefix instead of Godot 4's `theme\_override\_styles/`, `theme\_override\_colors/`, `theme\_override\_constants/`. So `PanelStyle\_Parts`, `PanelStyle\_Stats`, `TabStyle\_Selected`, `TabStyle\_Unselected` and every tab font color and separation constant \*\*never apply\*\*. Locations: `UI\_PartsMenu.tscn:52,56,69,70,71,72,73,82,92,102` and `UI\_StatBlock.tscn:37,55,116,127,146`. Note `theme\_overrides/separations/separation` isn't valid under any prefix — the real path is `theme\_override\_constants/separation`.

2\. \*\*Hardcoded absolute HUD positions in a stretch `expand` project\*\* — `skirmish.gd:958` and `:968` (see above). With `aspect="expand"` a wider viewport grows horizontally, so these drift off the right edge while the anchored bars around them stretch.



\### Existing verification machinery to extend

\- `prototype/scripts/ui\_audit.gd` (66 lines, `class\_name UIAudit`) — `find\_overflowing\_panels()`, `find\_offscreen\_controls()`, headless-safe.

\- `prototype/run\_tests.gd` — 113 `test\_` functions, 364KB. Relevant: `test\_ui\_no\_overflow\_or\_offscreen()` line 2807, `test\_ui\_audit\_has\_real\_teeth()` 2848, `test\_brushed\_aluminum\_ui\_theme()` 3314, `test\_hull\_modding\_parts\_menu\_two\_buckets()` 6348. Run: `cd prototype \&\& ./Godot\_v4.3-stable\_win64\_console.exe --headless --script run\_tests.gd --path .` expecting exit 0 + "ALL AUTOMATED TESTS PASSED SUCCESSFULLY!".

\- `prototype/visual\_regression/` — `run\_visual\_regression.gd`, `VisualRegression.tscn`, checked-in `baselines/`, gitignored `captures/`.

\- `prototype/scratch/capture\_\*.gd` — \~50 non-headless screenshot scripts (`capture\_ui\_theme.gd`, `capture\_skirmish\_hud.gd`, `capture\_mainlab\_ui.gd`, `capture\_ui\_sidebars.gd`, `capture\_drawer\_ui.gd`, `capture\_library\_panel\_fixes.gd`) that `img.save\_png()` into `progress\_captures/`.

\- `prototype/scripts/faction\_catalog.gd` — `FACTIONS` dict, 10 factions, each with base\_color/accent\_color/detail\_color/wear/grime/emissive + `get\_visual()`, `get\_visual\_color()`, `get\_visual\_wear\_color()`, `get\_visual\_wear\_amount()`, `get\_passive()`. `DEFAULT\_FACTION` const.



\## Locked-in decisions from the user (design to these, don't re-litigate)



1\. \*\*UI register: dark substrate + industrial trim.\*\* Near-black panels (\~88% opaque) as the legibility substrate. Industrial trim ON TOP: riveted corner plates, a 2px hazard-stripe accent rule, a stenciled/condensed display font, brushed metal reserved for header bars and card frames only. \*\*Faction color becomes an ACCENT only\*\* — borders, active/hover states, key numerals — never the panel fill. Rationale: VISUAL\_ART\_DIRECTION.md §1.1 and §4 establish a saturation hierarchy where units are the saturated objects and everything else is the muted stage; a faction-tinted panel fill violates that and hurts small-text legibility.

2\. \*\*Assets: SIL OFL fonts vendored + hand-authored SVG icons in-repo.\*\* 2-3 OFL fonts under `assets/fonts/` (a condensed industrial display face, a legible UI sans WITH TABULAR FIGURES for resource counters that must not jitter, optionally a mono). New `LICENSES/` directory + `CREDITS.md` at repo root — the repo currently has zero third-party assets and no attribution file, so this is new infrastructure. \~35 icons as hand-written SVG committed under `assets/icons/` (Godot 4 imports SVG natively; set `svg/scale` in the .import).

3\. \*\*Sequencing: foundation first, then a parallel track.\*\* The foundation slice must land before anything else because RTS\_CORE\_ROADMAP.md's own B9 (minimap) and D2 (queue HUD + categorised build bar) land into this chrome and would otherwise be built twice.



\## What I need from you



A concrete implementation design for the 2D layer, chunked the way this repo works (one chunk = one commit + one PROGRESS.md entry). Cover:



\*\*A. The Theme resource.\*\* Exact file path and structure for `bomber\_theme.tres`. Which Control types to define (Button, Panel, PanelContainer, Label, OptionButton, HSlider, CheckBox, CheckButton, TabContainer, ScrollContainer, LineEdit, VScrollBar, PopupMenu, Tooltip…) and which \*\*theme type variations\*\* to declare (e.g. `TitleLabel`, `SectionLabel`, `HUDValue`, `BuildButton`, `DangerButton`, `PrimaryButton`, `CardPanel`, `HeaderPanel`, `ChipLabel`). Whether to hand-author the .tres or generate it from a committed GDScript builder (consider: this repo generates all its art from scripts; a `tools/build\_ui\_theme.gd` that emits the .tres is arguably more on-brand and far more diffable/reviewable than a 600-line hand-edited .tres — give me a recommendation with reasoning). How `gui/theme/custom` in project.godot interacts with the remaining per-node overrides, and the migration order so the game never looks broken mid-chunk.



\*\*B. Fonts.\*\* Name 2-3 specific SIL OFL families that fit "diecast toy / pulpy industrial / RA2-adjacent" and say what each is for. Confirm the tabular-figures requirement is actually met by your picks (this matters — check which families ship `tnum` or are naturally monospaced-digit). Godot 4.3 specifics: FontFile import settings, `multichannel\_signed\_distance\_field` on/off for this use, `subpixel\_positioning`, whether to use FontVariation for the condensed/weight axes, and how to set fallbacks so the box-drawing/emoji glyphs currently in use don't render as tofu during migration.



\*\*C. Icon set.\*\* The concrete list of icons needed (derive it from the emoji inventory above plus what the HUD, build bar, order feedback, and Design Lab actually need). Naming convention, canonical viewBox/grid, stroke-vs-filled decision, how to keep 35 hand-written SVGs visually consistent, and the Godot import settings. Where they get referenced and how (a central `icons.gd` const map vs direct paths).



\*\*D. Mouse cursor.\*\* Design a `cursor\_manager.gd` — autoload or not, the cursor set (default, pointer/hand, move-order, attack-order, harvest, invalid, place-building, pan/grab, resize), image format and hotspot handling, how skirmish context drives swaps (what it raycasts and when), and how it interacts with `Control.mouse\_default\_cursor\_shape`. Note `Input.set\_custom\_mouse\_cursor` needs `Texture2D` and a hotspot `Vector2`; cover the headless-safe path so tests don't break.



\*\*E. Screen-by-screen redesign.\*\* For MainMenu, MapSelect, MatchSetup, Skirmish HUD, Design Lab (both sidebars + the floating module popup), Blueprint Library, Test Range, and the victory/defeat overlay: what the new layout is, which existing code changes, what's newly added. Be specific about the Skirmish HUD since it's the most-seen screen and currently has \*\*no unit selection/info panel at all\*\* — design the full region layout (resource cluster, status/toast area, minimap slot for B9, selection panel, command card, categorised build bar with tier strips and queue slots for D2) and make it explicit which regions are slots that B9/D2 fill later.



\*\*F. In-world UI replacement.\*\* Replace the `Label3D` + `■□` ASCII health bars and `TorusMesh` selection rings with something modern: shader-driven segmented health bars, animated selection decal rings, team-color chevrons, floating damage numbers, building production rings. Say whether these are `Sprite3D`/`QuadMesh`+shader/`MeshInstance3D`, how they billboard, how they fade in/out, and how they stay legible at the 10-240m camera height range in `rts\_camera.gd`.



\*\*G. Custom tooltips and UI motion.\*\* Godot's default tooltip is a plain PopupPanel — design `\_make\_custom\_tooltip()` on a shared base returning a styled card (icon + title + stat rows + flavor line), and where it hooks into the existing `tooltip\_text` usage in `parts\_menu.gd`/`stat\_calculator.gd`. Then a small `ui\_anim.gd` motion library: panel slide-in, button press feedback, resource counter roll-up (tween\_method), status toast slide+fade, scene-transition fade. Name the standard durations/easings so it reads as one system.



\*\*H. Render/project settings.\*\* Exact project.godot keys to add: MSAA 2D and 3D, viewport size decision (1280x720 → 1920x1080? justify against `canvas\_items`/`expand` and the hardcoded-position fix), `gui/theme/custom`, `gui/theme/default\_font\_\*`, window title, `config/icon`. Also the app icon replacement and `application/icon\_path` in all three export presets.



\*\*I. Verification.\*\* How to extend `ui\_audit.gd` and add headless tests that actually have teeth (theme resource defines every expected type/variation; no residual `add\_theme\_font\_size\_override` outside the theme builder; no unanchored absolute Control positions; every icon path resolves; every cursor texture loads; contrast ratio floor on theme color pairs). Plus which new `scratch/capture\_\*.gd` scripts and `visual\_regression` baselines to add, and specifically how to catch the stretch-mode drift class of bug (multi-resolution capture).



\*\*J. Chunk sequencing.\*\* Order the work into commit-sized chunks with dependencies, marking which are the mandatory foundation (must land before roadmap B9/D2) versus the parallel track. Flag anything that will break existing tests and what the fix is. Note that `prototype/scripts/production\_queue.gd` is currently untracked and `skirmish.gd`/`building.gd`/`enemy\_ai.gd`/`run\_tests.gd` are modified in the working tree (roadmap chunk A1 mid-flight) — say how that affects sequencing.



Be concrete and opinionated. Give recommendations, not option surveys.

