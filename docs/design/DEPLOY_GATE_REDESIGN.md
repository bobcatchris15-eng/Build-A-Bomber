# Deploy Gate Redesign — Scratch Notes

**Status:** scratch. Working notes for the conversation, not a polished spec.
**Anchors:** every claim below points at the file:line that owns the current behaviour.
**Decisions:** all four open questions resolved (see §9). Ready to cut the PR.

---

## 1. The hitch — what it actually is

`scene_router.gd:194-248` is the current transition path:

```
fade_out  →  change_scene_to_file(Loading.tscn)
fade_in   →  run_load:
               for each warm-list script: load + yield a frame
               change_scene_to_packed(Battle.tscn)
               await 2 frames
               await _await_world_ready  (polled, 30s ceiling)
               await _deploy_gate
               fade_in
```

The "loading screen disappears → deploy button visible" window is the part
where the player is staring at the half-built Battle scene. In that window
the scene's `_ready` is running through:

- `match_director.gd:323-340`  services (Order, FlowField, Economy, Production)
- `:346-347`                   spawn resource nodes + bases
- `:349`                       `await _setup_terrain()` — 4 navmesh bakes,
                               ~4s on `lake_crossing`, async-yielding
- `:353-362`                   FlowFields, Selection, Alerts, Vision
- `:364-366`                   load roster, spawn starting units, build HUD
- `:385-387`                   AI commander
- `:389-390`                   `world_is_ready = true; world_ready.emit()`

The bakes are async-yielding so the main thread *technically* ticks, but
the per-frame cost is high enough that Windows' Not Responding watchdog
greys the title bar. The player sees: black fade-in lifts → grey title
bar + dim world slowly filling in → DEPLOY button finally appears.

**The hitch is the absence of a visual during the build.** The fade has
cleared, the loading screen is gone, and the player is staring at a
half-built world with no acknowledgement that anything is happening.

---

## 2. What the deploy gate needs to be

Three jobs the current gate does poorly:

1. **It appears after the hitch**, not during it. Job should be: own
   the hitch, not arrive after it.
2. **The DEPLOY button is a plain `Button` with text "DEPLOY"** —
   `scene_router.gd:326-328`. The whole game uses `StampedButton` for
   commit actions (match_setup, operations_setup, operations_draft,
   blueprint_library, livery). The deploy button is the only commit
   point in the game that looks like a web form input.
3. **The "ALL SYSTEMS READY" label is a `HintLabel`** at
   `scene_router.gd:320-323`. A hint, not a status. The screen it
   appears on is the most modal thing in the game.

---

## 3. The redesign

A diffuse-glass layer between the camera and the world, up **the moment
the scene swaps in**, with three states:

### State A: building (default on swap)
- Glass overlay up. World is mid-build behind it. The world is dimmed
  but visible (a translucent dark tint + subtle frosted texture, so the
  player sees something is happening rather than grey title bar + black).
- Status: `TitleLabel` reading **"PREPARING DEPLOYMENT"**.
- Step text: `StatLabel` reading the current step (e.g. "Surveying
  terrain" / "Raising command deck" / "Briefing opposition") — same
  vocabulary as `scene_router.STEP_LABELS` at `:386-415`. No DEPLOY
  button yet.
- **Progress bar** + **segment lamps** in the chrome (see §3.1). The
  bar moves with real progress, the lamps sweep continuously.
- The HQ zone wireframe and HQ ghost (`match_director.gd:2098-2141`)
  sit **on top of the glass** as bright UI elements — they need to be
  readable for the pre-game HQ phase. The player can drop the HQ
  through the glass (it's translucent, not opaque).
- Tree is **not paused** during this state — the AI commander is
  still being instantiated and would race a pause.

### State B: ready (when `world_ready` fires)
- Glass stays. World is now built; dim transitions to **blur** (see §4).
- Status flips to **"ALL SYSTEMS READY"** with a `SIGNAL_GO` accent
  (or **"ENGAGEMENT N OF M — ALL SYSTEMS READY"** when
  `MatchRuleSet.mode == OPERATIONS`; see §7).
- DEPLOY button **disabled → enabled** transition (one
  `Tokens.DURATION_NORMAL` ease). The player has visual confirmation
  that something changed.
- Bezel framing transitions with it — see §3.2. The frame's
  border colour shifts from `BASE_500` to `SIGNAL_GO`, the
  bezel status lamps all light green. The state change is
  readable even before the player reads the label.
- Tree is paused (`get_tree().paused = true`, `scene_router.gd:340`).
  Same reasoning as today — the AI would take its first decision
  before the player reads the map.

### State C: dismissing (on DEPLOY)
- Glass fades from translucent to clear (`Tokens.DURATION_NORMAL`,
  symmetric with the fade_in). The world sharpens underneath.
- DEPLOY button dims out, then `queue_free()`s.
- Tree unpauses. Match is live.

### Why this fixes the hitch
The hitch is the absence of a visual during the build. Putting the
glass up on swap means the player has a continuous visual presence
from fade-in (from the loading screen) → glass covering build → glass
showing the built map → glass dissolving. **The window of "no visual
acknowledgement" disappears.** The build itself is the same speed; the
frame budget is the same; only the perceived responsiveness changes.

### 3.1 Progress bar + segment lamps

Two indicators doing different jobs, same pattern as the loading
screen's existing pair (`loading_screen.gd:6-13`):

- **Segment lamps** — continuous visual proof of life. 24 rectangular
  lamps with a lit band sweeping across them at 1.5 sweeps/sec.
  The exact routine is `loading_screen.gd:130-147`
  (`_draw_lamps`, the LAMP_COUNT / LAMP_SWEEP_SPEED / draw_rect
  pattern). Sweep is driven by `_process` so it ticks even when
  progress is at 0; a bar that doesn't move is indistinguishable
  from the freeze this exists to replace.
- **Progress bar** — real progress. A `ProgressBar` driven by an
  extended `load_progress(fraction, label)` signal that the
  router subscribes to across the WHOLE sequence (warm-list +
  world build, ending at the world_is_ready moment). Same
  `_on_progress` shape as `loading_screen.gd:107-110`; the gate
  becomes a second subscriber.

**Lamps as a shared component.** The lamp draw routine is small
(20 lines) and identical in both places, but having two copies
means a tweak to the sweep speed or the colour ramp has to land
in two files. Lift `_draw_lamps` + the LAMP_COUNT / SWEEP_SPEED
constants into `scripts/ui_lamps.gd` as a `Control` subclass with
a `set_phase(t)` / `set_color(sweep_colour)` API. Both the
loading screen and the deploy gate instance it. Trivial,
preventive.

**The bar's source of truth.** The current `load_progress` is
`scene_router.gd:33`, `:204`, `:211`, `:216`:

| Emit site | Fraction | When |
|---|---|---|
| `:204` | `i / total` | per warm-list script (load + yield) |
| `:211` | `warm.size() / total` | end of warm-list, before swap |
| `:216` | `1.0` | after `change_scene_to_packed`, BEFORE world_is_ready |

The `:216` emission is the bug. The bar is at 100% during the
world build, then the button enables. The fraction needs to
represent the *whole* sequence. Two changes:

1. **`:216` moves.** Drop the `1.0` emission at `:216`; the
   match director now owns the final stretch.
2. **Match director emits.** New `MatchDirector.progress(fraction,
   label)` signal. Emission sites (a draft — needs verification
   against the actual order in `_ready`):

   | Site (in `match_director.gd`) | Fraction | Label |
   |---|---|---|
   | after `_spawn_resource_nodes()` | 0.05 | "Locating resource deposits" |
   | after `_spawn_bases()` | 0.10 | "Surveying build sites" |
   | per navmesh tile baked | 0.10 → 0.55 | "Surveying terrain" |
   | after `_setup_terrain()` resolves | 0.60 | "Plotting movement lanes" |
   | after `_load_roster()` | 0.70 | "Indexing designs" |
   | after `_spawn_starting_units()` | 0.80 | "Preparing vehicle systems" |
   | after `_build_hud()` | 0.90 | "Raising command deck" |
   | after AI commander setup | 0.95 | "Briefing opposition" |
   | `world_is_ready = true; emit 1.0` | 1.00 | "Ready" |

   The router subscribes to the new signal and re-emits
   `load_progress` so the loading screen and the gate get the
   same stream.

3. **Total rebalance.** The warm-list still owns 0.0 → 0.05 (the
   fraction that becomes 0.10 in the table above once the world
   build's first emission fires). With the warm-list at 13
   scripts and the build at ~9 steps, the bar is mostly
   non-linear in wall-time (the warm-list is script
   compilation, fast; the terrain bake is the slow part). The
   fractions above deliberately under-weight the build's early
   steps so the bar doesn't sit at 10% for 3 seconds before
   the bake starts. **Approved to ship as the first-pass
   table**; a stopwatch calibration pass on `lake_crossing`
   is a follow-up commit after the gate is actually running.

**Why the bar, not just the lamps.** Lamps say "yes, ticking".
The bar says "how much of this is left". Both belong: the lamps
are the heartbeat, the bar is the countdown. Same pairing the
loading screen already uses.

### 3.2 Bezel framing

A stamped-metal frame wraps the central column (status + step +
bar + lamps + DEPLOY button), so the deploy gate reads as
"industrial control panel" rather than "modal dialog with a
button on it". The bezel is a 2D `Panel` with a `StyleBoxFlat`
border, the same `UITheme.apply_material(bg_rect, "steel", ...)`
treatment `match_setup.gd:85-91` already uses for its backdrop
(the same material palette the StampedButton mesh lives in).

**Anatomy:**
- A `Panel` outer frame, ~12px border, `border_color` follows
  state: `BASE_500` while building, `SIGNAL_GO` when ready.
  One `Tokens.DURATION_NORMAL` ease on the border colour at
  the same moment the button enables.
- 6 small status lamps integrated into the bezel — 3 on each
  side of the DEPLOY button. Dim (`BASE_700`) while building,
  `SIGNAL_GO` when ready. **Different job from the segment
  lamps**: the segment lamps are continuous proof-of-life;
  the bezel lamps are state indicators that flip on together
  at the mark-ready moment. Two visual languages for two
  visual jobs.
- The DEPLOY button sits inside the bezel, centered, at its
  existing 260x56 dimensions. The StampedButton mesh's
  chamfered dish catches the bezel's `SIGNAL_GO` rim light
  when ready — a small detail that ties the button to the
  frame.
- Outer padding follows the existing `UIShell.screen_frame`
  convention (`loading_screen.gd:46` uses the same pattern)
  so the bezel sits at the same inset as the loading screen's
  frame. The deploy gate and the loading screen are
  contiguous surfaces; the inset is part of the visual
  contract.

**Implementation:**
- 2D, not 3D. The StampedButton's 3D-mesh-in-SubViewport
  approach is justified because the button is the only 3D
  object on its screen; the bezel is part of the chrome,
  not a featured object. A 2D `Panel` with a stamped
  material reads as "metal" without the render cost of a
  second SubViewport.
- The bezel is the gate's outermost Control; status, step,
  bar, lamps, and button are children of a `VBoxContainer`
  that's a child of the bezel Panel. Hit-test geometry is
  just the bezel + button; everything inside the bezel is
  `MOUSE_FILTER_IGNORE` so the bezel swallows clicks during
  the pause (the gate is up while the match is paused and
  the player should not be able to issue orders through it).

**Why this is approved.** The bezel makes the state
transition (build → ready) legible at a glance: the border
shifts, the lamps flip, the button enables, all in concert.
A modal with just a button is "did the game freeze?". A
modal with a bezel + lamps + button is "I can see the
system is online, the button is the last step". The latter
is the deploy gate's whole reason for existing.

---

## 4. The blur — what it actually is

The glass is dim+translucent during build (State A) and **transitions
to a real blur** when the world is ready (State B). Three approaches,
ranked by fidelity vs. cost:

### Option 1 — `CompositorEffect` with a separable Gaussian (recommended)
- `CompositorEffect` was added in 4.3, refined through 4.4+. We are
  on 4.7.1.
- Compute shader: read the back buffer at lower mip, two passes
  (horizontal then vertical) for a separable 9-tap Gaussian, output to
  a screen-sized target. The `ShaderMaterial` on the glass overlay
  samples the blurred mip.
- Cost: two compute dispatches per frame at 1/4 res, ~negligible on
  the maps we ship (`open_plains` 840 half-extent, `lake_crossing`
  similar).
- Fidelity: real blur. The map reads as "behind frosted glass",
  not as "dim map with a tint over it".
- Touches: new `shaders/deploy_blur.gdshader` (compute), new
  `scripts/deploy_blur_effect.gd` (the `CompositorEffect` wrapper),
  hook into `WorldEnvironment` in Battle.tscn or applied per-scene
  by the router.

### Option 2 — `SubViewport` re-render of the world
- The router already owns a `CanvasLayer` (the fade layer at
  `scene_router.gd:59`). Add a `SubViewport` underneath the glass
  that re-renders the Battle scene with a `post_process` material.
- Cost: doubles the scene's render cost for the duration of the
  gate (a few seconds, fine).
- Fidelity: real blur, but at half-rate (SubViewport `UPDATE_WHEN_VISIBLE`
  throttles). Reads correctly but feels "off" if the player notices
  the rate.
- Touches: new `SubViewport` child of the router, capture of the
  current camera, post-process material.

### Option 3 — no real blur, just dim + noise (fallback)
- Glass stays translucent dark. A small noise pattern over the
  world reads as "frosted" without sampling the back buffer.
- Cost: zero. A fragment shader on the overlay.
- Fidelity: "frosted" by convention, not literally. The map is
  visible but dimmed.
- Touches: one shader, no engine-side integration.

**Locked: Option 1.** The hookup is the same as the screen-space
SSAO already in Battle.tscn's `WorldEnvironment`, and the
`CompositorEffect` plumbing is documented for 4.7. Option 3 is
documented as the fallback if the compute shader path turns out
to fight the existing SSAO pipeline, but Option 1 is what
ships.

---

## 5. The button

Replace `scene_router.gd:326-329`:

```gdscript
var button := Button.new()
button.text = "DEPLOY"
button.custom_minimum_size = Vector2(260, 56)
```

with a `StampedButton` (PRIMARY variant), same dimensions. The
`StampedButton` header at `ui_stamped_button.gd:1-63` is the
rationale: every commit point in the game already uses it. The
DEPLOY button is the only commit point in the game that doesn't.

```gdscript
var button := StampedButtonScript.new()
button.legend = "DEPLOY"
button.variant = StampedButtonScript.Variant.PRIMARY
button.custom_minimum_size = Vector2(260, 56)
button.disabled = true  # lifted when world_is_ready
UIFeedbackScript.wire(button, "confirm")
```

Same `UIFeedbackScript.wire(..., "confirm")` as every other commit
point. Same dimensions as the current `Button` (260x56, slightly
taller than StampedButton's 132x44 minimum so the mesh has room).

---

## 6. The status label

`scene_router.gd:320-323`:

```gdscript
ready_label.text = "ALL SYSTEMS READY"
ready_label.theme_type_variation = "HintLabel"
ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
```

This is the most modal screen in the game and the status is a
`HintLabel`. Promote it to `TitleLabel` (24px stencil, `TEXT_PRIMARY`)
to match the loading screen's `_status_label` at `loading_screen.gd:60`.
The loading screen and the deploy gate should be readable as the
same kind of surface — the deploy gate is the loading screen's last
frame, not a separate thing.

---

## 7. What about Operations between stages?

The deploy gate appears on every Battle scene load, including
operations between stages. The current gate is the same "ALL SYSTEMS
READY" + plain `Button` for every stage. **Locked in:** the gate's
status label reads the current stage from
`OperationsManager.current_stage + 1` / `total_stages` when the
scene's `MatchRuleSet.mode == OPERATIONS`. So:

- **Skirmish**: `"ALL SYSTEMS READY"`
- **Operations engagement 3 of 5**: `"ENGAGEMENT 3 OF 5 — ALL SYSTEMS READY"`

This adds the stage context to the one-beat pause between
debrief and deploy without re-reading it from the AAR. The
debrief screen is still the primary place the player sees the
stage number; the gate is the last frame before the match
starts and a stage-anchored label there is the right amount
of redundant.

Operations between stages skip the HQ placement phase
(`_enter_hq_placement` early-returns when a live HQ exists, since
the structure.gd `died.connect` would have fired otherwise). The
glass overlay's State A still applies (build phase has its own
work to do: rebuild HUD with the new stage's selection, load
the new harvester, etc.), so no special case needed.

---

## 8. Implementation outline (file:line)

Order of changes, smallest first so each commit is independently
runnable:

1. **`scene_router.gd:303-343` — extract `_deploy_gate()` into
   `scripts/deploy_gate.gd` as a self-contained scene that the
   router composes.** This is the same shape as the loading screen
   (a self-contained scene + a coroutine the router drives), and
   it gets the new overlay its own file where the shaders, button,
   lamps, progress bar, and step-text wiring can live without
   bloating the router.

2. **New `scenes/DeployGate.tscn` + `scripts/deploy_gate.gd`.**
   Hosts the glass overlay, the status label, the step label, the
   **progress bar** + **segment lamps**, the StampedButton. Exposes:
   - `start()` — enter State A (building)
   - `set_progress(fraction, label)` — push fraction + step label
     (driven from the router's re-emission of the match director's
     progress signal)
   - `mark_ready()` — enter State B (button enabled, label flips)
   - `await deploy_pressed` — a signal the router awaits
   - `dismiss()` — State C, fade + free

3. **`scripts/ui_lamps.gd` — extract the segment-lamp routine
   from `loading_screen.gd:130-147` (plus LAMP_COUNT / SWEEP_SPEED
   at `:31-32`) into a `Control` subclass.** API: `set_phase(t)`,
   `set_sweep_colour(colour)`. Both the loading screen and the
   deploy gate instance it. Trivial lift, prevents two copies
   drifting on a sweep-speed tweak.

4. **`MatchDirector.progress(fraction, label)` signal + emissions**
   at the table sites in §3.1. Router subscribes and re-emits
   `load_progress` so the existing `_on_progress` handlers
   (loading screen, gate) get the unified stream. The `:216` 1.0
   emission in `scene_router.gd` is **removed** — the
   `world_is_ready` emission from the match director is now the
   single source of "1.0".

5. **Wire the existing `load_progress` signal
   (`scene_router.gd:33, :204, :211`) to the gate's
   `set_progress()`.** The bar moves through the warm-list (router
   emissions) and continues through the world build (match director
   emissions) without a discontinuity.

6. **Glass overlay shader.** New
   `shaders/deploy_glass.gdshader`. Fragment shader on a
   full-screen `ColorRect` with a `backdrop` uniform. The
   `backdrop` is filled by either the `CompositorEffect` (Option 1)
   or a literal `ScreenTexture` for the no-blur fallback.

7. **`CompositorEffect` for the blur (Option 1) or skip
   (Option 3 fallback).** New
   `scripts/deploy_blur_effect.gd` + a `.glsl` compute shader.
   Activated by the gate's `_ready`, removed on `dismiss()` so
   it doesn't run during the live match.

8. **Pause timing.** Move `get_tree().paused = true` from the
   router's gate function (`scene_router.gd:340`) into the gate's
   `mark_ready()` so the tree is only paused when the button is
   actually pressable. Today the pause and the gate appear
   together, but with the new "disabled → enabled" button
   transition they should be tied to the same moment.

9. **Operations stage label** in the gate's `mark_ready()` —
   one if/else on the rule set's `mode`, two text strings
   (Skirmish: `"ALL SYSTEMS READY"`; Operations: `"ENGAGEMENT N
   OF M — ALL SYSTEMS READY"`).

10. **Bezel framing** (new, see §3.2). The gate's central column
    is wrapped in a 2D `Panel` with a stamped-steel `StyleBoxFlat`
    border + 6 status lamps. Border colour eases from `BASE_500`
    to `SIGNAL_GO` on `mark_ready()`; lamps flip on in the same
    beat. The bezel + lamps + button are the three legs of the
    state-transition legibility story.

---

## 9. Decisions (closed)

All four open questions resolved:

- **Blur: Option 1** (`CompositorEffect` + separable Gaussian).
  Real blur, ~negligible cost, matches the SSAO plumbing already
  in `WorldEnvironment`. The compute shader lives in
  `shaders/deploy_blur.gdshader`, the `CompositorEffect` wrapper
  in `scripts/deploy_blur_effect.gd`. Activated on the gate's
  `mark_ready()`, removed on `dismiss()` so the live match
  doesn't pay for it.
- **Bezel framing: approved** (see §3.2). Stamped-metal frame
  around the central column, 6 status lamps on the bezel itself,
  `SIGNAL_GO` border + lamps at the mark-ready moment.
- **Operations label: "ENGAGEMENT N OF M — ALL SYSTEMS READY"**
  when `MatchRuleSet.mode == OPERATIONS` (see §7). Skirmish
  stays as plain "ALL SYSTEMS READY".
- **Progress bar calibration: ship the first-pass fractions,
  rebalance in a follow-up.** The wall-clock is dominated by
  the terrain bake; the under-weighting of the early build
  steps in §3.1's table is a deliberate "non-embarrassing
  first pass" and a stopwatch pass on `lake_crossing` will
  tighten it. Calibration commit goes in after the main
  PR lands and the gate is actually running.

---

## 10. What this does NOT do

- It does not change the warm-list (that's the actual time sink;
  the glass makes the time sink tolerable).
- It does not change the HQ placement flow. The player still drops
  the HQ during the terrain bake; the glass just covers the
  un-built ground beneath the wireframe + ghost.
- It does not change `_setup_terrain`. The bake is still ~4s on
  `lake_crossing`; the glass just gives the player a visual
  during it.
- It does not change the post-DEPLOY experience. Same fade, same
  match, same RTS camera. Only the arrival is redesigned.
