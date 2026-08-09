# Kitbash Command: Visual & UX Polish Plan (3D fidelity + interaction gaps)

> **Update 2026-08-09: Completed.** (All tasks in this plan have been fully implemented to satisfaction. This document is retained for historical context.)

**Status (2026-07-25): planning only.** Written alongside `PERFORMANCE_PLAN.md`
in response to Chris comparing the game's polish bar against `E:\OpenRA`
(source available locally) and `E:\Red Alert 2`. Every chunk is tagged
**[Claude]** or **[Qwen]** â€” see `PERFORMANCE_PLAN.md`'s delegation section
for how that split works in practice; the same rules apply here.

## Non-scope â€” read this before adding anything below

This project already has two other planning documents that cover most of
"make the game look/feel better." **Do not re-plan these here** â€” finish
them instead:

- **`VISUAL_IMPROVEMENT_PLAN.md`** â€” the 2D UI chrome overhaul brief (theme,
  fonts, icons, cursor, tooltips/motion, per-screen redesign). Chunks A
  (theme resource), C (icon registry), and D (cursor manager) appear to
  already be built â€” `resources/bomber_theme.tres`, `scripts/ui_icons.gd`,
  and `scripts/cursor_manager.gd` all exist and match that brief's spec.
  Chunk **F** (replace `Label3D` ASCII health bars / `TorusMesh` selection
  rings with real in-world UI) and chunk **G** (custom tooltip cards +
  `ui_anim.gd` motion library) are still unbuilt â€” see this doc's Part A for
  a couple of things worth doing alongside F, but F/G's actual specs live in
  `VISUAL_IMPROVEMENT_PLAN.md`, not here.
- **`RTS_CORE_ROADMAP.md`** â€” minimap (**B9**), the categorised build bar +
  queue HUD (**D2**), real power states (**E1**), and tech-tree greying
  (**E3**) are all fully specced there, unbuilt, with explicit OpenRA
  `file:line` citations into the `E:\OpenRA` checkout Chris already has.
- **`FABLE_REVIEW.md`** â€” flags that the project's real "build diversity"
  problem is combat-balance math (rapid-fire weapons deal zero damage to
  armored hulls â€” a threshold/per-shot-damage mismatch), not the visuals or
  editor. Out of scope for this document, but genuinely the highest-leverage
  fix in the repo if Chris wants to prioritize it at some point.

**Calibration note on the OpenRA/RA2 comparison:** both are sprite-based
2.5D isometric engines (RA2's units are pre-rendered 3D sprites; OpenRA
renders 2D sprite sheets), not real-time 3D. Their literal rendering
techniques (sprite lighting, isometric projection) don't transfer to this
project's true-3D, orbit-camera pipeline. What genuinely *does* transfer is
their **UX/readability convention** â€” legible health bars, clear selection
feedback, a minimap, control groups, order markers â€” which is Part C below
and already partly covered by B9/D2. For raising 3D rendering fidelity
itself (Part A), the more useful bar is modern real-time 3D presentation
generally, not OpenRA/RA2's specific sprite techniques.

## Part A â€” 3D rendering fidelity

- **A1. Environment/post-processing pass** â€” *afternoon* [Qwen once Claude
  sets exact parameter values]. No `WorldEnvironment` tuning found anywhere
  in the project. Add: glow/bloom (existing emissive parts â€” energy shields
  via `shield_mode`, engine glow, muzzle flashes â€” have emission data
  plumbed through `hull_faction_material.gdshader` already but nothing
  makes it bloom), SSAO (parts mounted flush against hull surfaces currently
  read as pasted-on with no contact shadow), and a filmic/ACES tonemap
  instead of Godot's default linear response. This is the single highest
  visual-return-for-effort item â€” it's one `WorldEnvironment` node with a
  handful of tuned values, not new geometry or systems.
- **A2. Replace ad-hoc VFX with `GPUParticles3D`** â€” *one session*
  [Qwen once Claude designs the process materials]. Muzzle flashes
  (`auto_weapon.gd:886-902`) and hit/death effects
  (`battle_unit.gd:1450-1470`) currently spawn a fresh `MeshInstance3D` +
  `StandardMaterial3D` + `Tween`, animate it by hand, and `queue_free()` it
  per shot/hit. Replace with `GPUParticles3D` (one-shot, `emitting = true`
  then auto-cleanup via `finished` signal or a lifetime timer) â€” visually
  richer (real particle spread/falloff instead of a single scaling mesh),
  cheaper per-shot (no per-shot resource allocation/Tween churn), and this
  is a genuine performance win too, not just polish.
- **A3. Activate the decal system** â€” *multi-session* [Claude]. The
  `decal_tint` uniform in `hull_faction_material.gdshader` (line 46) is
  wired but deliberately left inert per that shader's own comment ("needs
  actual authored texture content"), and `VISUAL_ART_DIRECTION.md` logs
  this as a deliberate deferral. Build the actual decal atlas (hazard
  stripes, faction insignia, battle-damage scorch marks) â€” this is real art
  production, not a code task, so budget it like `RTS_CORE_ROADMAP.md`'s B8
  (its own arc, not a quick chunk).
- **A4. Finish `VISUAL_IMPROVEMENT_PLAN.md` chunk F** â€” *one session*
  [Claude]. In-world health bars are still `Label3D` text rendering an
  `â– â–¡` ASCII bar (`battle_unit.gd:601-621`, `building.gd:255-262`,
  `target_dummy.gd:44` â€” three independent duplicated implementations of
  the same placeholder). Selection rings are an unshaded flat
  `TorusMesh`. Chunk F already specs the replacement (shader-driven
  segmented health bars, animated selection decal rings, floating damage
  numbers) â€” this is pure execution against an existing spec, no new
  design needed here.

## Part B â€” Camera & input feel

- **B1. RTS camera polish** â€” *afternoon* [Qwen once Claude picks the
  easing curves/constants]. `rts_camera.gd` has WASD pan and scroll-zoom
  with only zoom height lerped (`:38`) â€” pan itself is un-eased, there's no
  edge-of-screen scrolling, and zoom only changes camera height without
  recentering under the cursor (scrolling in doesn't pull the view toward
  what you're pointing at, a core RTS camera expectation both OpenRA and
  RA2 satisfy). Add edge-scroll (activate pan when the mouse nears the
  viewport edge) and zoom-to-cursor (raycast to ground under the mouse,
  lerp the camera target toward that point as height decreases).
- **B2. Design Lab orbit camera smoothing** â€” *small* [Qwen once Claude
  picks constants]. `designer_camera.gd:40-46` applies zoom/orbit as direct
  `_distance -=` / `position.z =` snaps â€” no lerp at all, unlike the RTS
  camera's already-smoothed height. Bring it in line (same lerp idiom
  `rts_camera.gd:38` already uses). Also remove the dead `_input(event):
  pass` stub at `designer_camera.gd:24-25` while touching this file.

## Part C â€” UX gaps not tracked in any other doc

- **C1. Shift-click add-to-selection + control groups** â€” *one session*
  [Claude â€” input-handling correctness, not mechanical]. `skirmish.gd`'s
  `_set_selection()` (line 1566) always replaces the selection wholesale;
  there's no shift/ctrl modifier handling anywhere in the file's input
  code. Add standard RTS semantics: shift-click/shift-drag adds to
  selection, Ctrl+1-9 assigns a control group, 1-9 recalls it (double-tap
  recenters camera on it, matching both OpenRA and RA2 convention).
- **C2. Stop debug tooling from shipping live** â€” *small* [Qwen once
  Claude specifies the exact gate]. `skirmish.gd:1235-1296` places an
  ungated Debug button directly in the live HUD next to Menu (checkboxes
  for infinite resources / reveal fog / instant build), and
  `debug_settings.gd:19` defaults `infinite_player_resources = true` with a
  comment explicitly asking not to flip that default because active
  development depends on it. Gate the HUD button behind
  `OS.is_debug_build()` (or an explicit `DebugSettings` flag Chris can
  still flip locally) so a build handed to anyone else doesn't ship
  unlimited resources by default; `battlefield.gd:28-34`'s always-on debug
  tuning panel in the Test Range gets the same treatment.
- **C3. Wire up `CursorManager`** â€” *afternoon* [Qwen once Claude specifies
  the exact hover/order call sites]. `cursor_manager.gd` is a fully built
  autoload (Default/Move/Attack/Harvest/Invalid/Build states, real cursor
  assets under `assets/cursors/`) that is **never called** from
  `skirmish.gd`, `battlefield.gd`, or `battle_unit.gd` â€” grep confirms the
  only other reference is an asset-existence audit script. The order
  resolution logic that would drive it already exists at
  `skirmish.gd:1595-1631` (`_issue_order`, which already determines
  move/attack/harvest by raycast target) â€” this is "call an existing
  function from another existing function," not new design.
- **C4. Fix the drawer's fake animation** â€” *trivial* [Qwen, this session's
  delegation trial â€” see below]. `parts_menu.gd:159-178`'s
  `_toggle_drawer()` has a comment claiming "content slides down with
  smooth animation," but the function body only sets
  `content.visible = true/false` â€” an instant flip, no tween. Add the
  tween the comment already promises (a `Tween` animating the container's
  `custom_minimum_size.y` or a `size_flags`-driven collapse, matching
  whatever easing/duration convention chunk G's motion library ends up
  using if it lands first â€” otherwise a plain `Tween.tween_property` over
  ~0.15-0.2s is enough on its own).

## Delegation & qwen trial

Same rules as `PERFORMANCE_PLAN.md`: Claude specifies the exact pattern for
any `[Qwen]`-tagged chunk before handoff; every qwen diff is reviewed and
the headless suite (`run_tests.gd`) runs before it's considered done.

**This session's trial run is C4** (the drawer-tween fix) â€” it's small,
purely additive, zero gameplay risk, and self-evidently verifiable (either
the drawer now animates or it doesn't), making it the right choice to
validate the invoke â†’ review â†’ test workflow before handing qwen anything
bigger like `PERFORMANCE_PLAN.md`'s P4c (106-site refactor) or this doc's
A1/A2/B1/B2.

## Sequencing

| # | Chunk | Size | Depends on | Delegation | Status |
|---|---|---|---|---|---|
| 1 | A1 environment/post-processing | afternoon | â€” | Qwen (Claude-specified) | â€” |
| 2 | A2 GPUParticles3D VFX | one session | â€” | Qwen (Claude-specified) | â€” |
| 3 | A3 decal system | multi-session | â€” | Claude (art production arc) | â€” |
| 4 | A4 finish chrome-plan chunk F | one session | â€” | Claude | â€” |
| 5 | B1 RTS camera edge-scroll/zoom-to-cursor | afternoon | â€” | Qwen (Claude-specified) | â€” |
| 6 | B2 Design Lab camera smoothing | small | â€” | Qwen (Claude-specified) | â€” |
| 7 | C1 shift-select + control groups | one session | â€” | Claude | â€” |
| 8 | C2 gate debug tooling | small | â€” | Qwen (Claude-specified) | â€” |
| 9 | C3 wire up CursorManager | afternoon | â€” | Qwen (Claude-specified) | â€” |
| 10 | C4 drawer tween fix | trivial | â€” | **Qwen â€” this session's trial** | â€” |

No hard dependencies between these chunks â€” they're independent enough to
pull in any order Chris prefers. C4 goes first only because it's this
session's delegation trial, not because anything depends on it.

## Verification

- Headless suite: `cd prototype && ./Godot_v4.3-stable_win64_console.exe
  --headless --script run_tests.gd --path .`, expecting "ALL AUTOMATED
  TESTS PASSED SUCCESSFULLY!".
- Visual chunks: `prototype/visual_regression/` baseline diff, plus a
  manual look in-editor since bloom/SSAO/tonemap changes are exactly the
  kind of thing a headless pixel diff won't meaningfully judge.
- UX chunks (C1-C4): manual play-test â€” these are exactly the class of bug
  `RTS_CORE_ROADMAP.md`'s D2 chunk already warns is invisible to the
  headless suite ("the wheels rebuild learned that the hard way").

