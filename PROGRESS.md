# Progress Log

Dated entries, newest first. Written after every major chunk of work as a checkpoint for anyone (Chris, or a fresh session) picking this up cold.

---

## 2026-07-12 (Tue) — Mesh/part kit audit: coverage is actually complete; fixed real quality bugs instead

**Audit finding (another pleasant surprise): there are no missing part meshes.** Cross-referenced every `_part("...")` call in `visual_builder.gd` against the authored `.glb` files in `assets/models/parts/` and `assets/models/hulls/` — every weapon/module type that requests an authored mesh has one, and all 7 hull/foundation catalog entries have a matching hull mesh. The planned "gap-fill" premise didn't hold up, so today's work shifted to quality/consistency issues found via a visual QA sweep instead of new mesh authoring.

**Shipped:**
1. **`armor_plating` removed from the placeable parts menu.** It's a leftover catalog entry (category "armor") that was still clickable in the Modules tab despite Damage_And_Armor_Model.md's explicit, deliberate decision to keep armor hull-level-only (logged in [DECISIONS_NEEDED.md](DECISIONS_NEEDED.md) yesterday). It had no tweaks and no dedicated visual — exposing it just contradicted the documented design and confused the parts bin. No bundled loadout referenced it, so this was safe to hide with zero save-compat risk.
2. **Sensor mast dish was absurdly disproportionate** — a fixed 0.7-radius disc (1.4 diameter) mounted on a module with a 0.5-wide footprint, nearly 3x oversized. Screenshotted during the hull-variety QA pass (`progress_captures/2026-07-12/hull_variety_qa/`) and was obviously wrong at a glance. Now scales with the module's own footprint.
3. **The "Radar Mast Height" slider was mislabeled** — it scaled the *dish's* thickness (`children[1]`), not the *mast's* height (`children[0]`). The slider visibly did something (the flat dish got very slightly thicker) so it wasn't obviously broken, but it didn't do what its label said, and didn't move the dish to match. This is exactly the kind of "looks tweakable but isn't" bug the DESIGN_VISION.md differentiation test is meant to catch. Fixed to scale the mast and reposition the dish to ride its top.

**Verified:**
- New test `test_sensor_mast_tweak_and_proportions()`: checks dish radius stays proportional to module footprint, and that `mast_height` scales the mast (not the dish) with the dish correctly repositioned. Caught a real scope bug of my own while writing it — `_apply_tweak_deformations()` didn't have `base_size` in scope, a straight compile error, fixed by threading it through as a parameter.
- Extended `scratch/VisualVerify.tscn` to cover all 7 hull types (previously 5) for a full-coverage visual sweep, screenshots in `progress_captures/2026-07-12/hull_variety_qa/`.
- Full suite: **15/15 green.**

**Commit checkpoint:** see git log.

---

## 2026-07-12 (Mon) — Undo/Redo implemented (was entirely missing)

Design_Lab_UI_UX.md's Top Bar spec explicitly lists "Undo/Redo" as part of the Admin Tools row, but there was zero implementation of it — no history stack, no keybinding, no button.

**Shipped:** full snapshot-based undo/redo.
- `blueprint_manager.gd`: extracted the dict-building half of `save_blueprint()` into a new `serialize_hull(hull)` function (no file I/O, no clipping-gate) so it can be reused for both saving and in-memory undo snapshots.
- `module_placer.gd` (the MainLab root controller): `push_undo_snapshot()` / `undo()` / `redo()` / `can_undo()` / `can_redo()`. Undo tears down the current hull and reconstructs it from the previous snapshot via the existing `reconstruct_vehicle()` path (same code used for loading saved blueprints — reused, not reinvented). History capped at 50 entries.
- Snapshot is pushed at the *start* of a mutation (module placement, deletion, rotation, drag-move, gizmo tweak-drag, hull-scale drag, armor material/thickness, faction change) so one undo = one user-visible action, not one-per-frame. Slider-based tweaks hook `drag_started` (not `value_changed`) for the same reason.
- Bound to Ctrl+Z / Ctrl+Y (and Ctrl+Shift+Z), plus Undo/Redo buttons added to the stat panel UI.

**Verified:**
- New test `test_undo_redo()` in `run_tests.gd`: place → undo → redo, asserting module count at each step.
- Real-scene integration smoke test (not just synthetic test scaffolding) via `scratch/MainLabSmoke.tscn`: placed a railgun pair + wheels on a real hull, called `undo()`/`redo()` on the actual running MainLab scene, screenshotted all three states. Confirms the real UI buttons render and the absolute `/root/MainLab` node-path lookups used by `gizmo_3d.gd` actually resolve outside of synthetic tests. See `progress_captures/2026-07-12/undo_redo_integration/` — wheels visibly present → gone after undo → back after redo, with HP/weight/DPS stat panel numbers updating correctly at each step (640/448/220 → 240/288/220 → back).
- Full suite: **13/13 green.**

**Also shipped today:** Design Lab camera was orbit+zoom only — Design_Lab_UI_UX.md explicitly specs "rotate, pan, and zoom" but pan didn't exist, so there was no way to recenter on a large hull without zooming out. Added middle-drag pan (matches the Skirmish camera's documented convention), distance-scaled. Pan math pulled into a pure `_compute_pan_delta()` function and unit tested directly — headless Godot can't simulate held mouse-button state via `Input.parse_input_event` (confirmed empirically: `is_mouse_button_pressed` stayed false after a parsed press event), so a real end-to-end input test wasn't possible; the math itself is fully covered instead. Suite now **14/14 green.**

**Commit checkpoint:** see git log.

---

## 2026-07-12 (Sun) — Design Lab audit vs DESIGN_VISION.md + first fixes

**Audit finding (the headline surprise): the Design Lab is much closer to the Spore/KSP vision than the "Forged Battalion trap" worry assumed.** Most weapons already have real continuous tweak parameters (caliber, barrel length, drum size, etc. — see `stat_calculator.gd`'s `TWEAK_SPECS`), wired to both a 3D gizmo-drag interface (`gizmo_3d.gd`) *and* a slider popup, with live stat feedback (HP/weight/cost/DPS recompute per-frame) and working bilateral symmetry (`mirrored_counterpart` propagates tweak changes to the mirror twin, confirmed at both tweak-time and placement-time in `module_placer.gd`). This is not a discrete-swap-only system.

**Real gaps found and fixed today:**
1. **Three locomotion types had non-functional or missing tweak sliders.** `legs` and `anti_grav` had a "size" slider in the UI that updated internal settings but `update_locomotion()` never read the value — moving the slider did nothing. `hover_engine` had no tweak UI at all. Only `wheels`/`tracked_treads`/`helicopter_rotors` (3 of 6 locomotion archetypes) actually responded to their sliders. This directly failed the DESIGN_VISION.md differentiation test: two players could not have diverged on leg length, anti-grav ring size, or hover pad size no matter what they did. **Fixed** — all three now scale correctly and feed into `ModuleData.scale_multiplier` (so weight/HP/cost respond too), verified visually (see `progress_captures/2026-07-12/locomotion_tweak_fix/`) and with a new automated test.
2. **Three weapons (`mortar_array`, `cluster_dispenser`, `missile_pod`) had slider-based tweaks but no 3D gizmo-drag mapping** — tweakable via the popup, but not via the tactile "grab the part and pull" interaction the vision doc calls out as core to the Spore feel. **Fixed** — added axis mappings in `gizmo_handle.gd`'s `get_tweak_for_axis`.

**Gaps found and explicitly NOT fixed this week (see [DECISIONS_NEEDED.md](DECISIONS_NEEDED.md) for full reasoning):**
- Armor "mass distribution" (DESIGN_VISION.md's own example) conflicts with an existing, deliberate anti-tedium design decision in Damage_And_Armor_Model.md that rejects spatial armor placement. Kept the existing hull-level material×thickness system; flagged the doc conflict rather than picking a side.
- Directional/facing armor thresholds are documented as intended but unimplemented — deferred as a combat-model (not Design Lab) concern.
- Firing-arc cone visualization from Design_Lab_UI_UX.md is unimplemented — deferred as a stretch goal behind tweak-depth work.
- Grid-snap placement from Design_Lab_UI_UX.md was never built; current freeform placement is being kept deliberately since it better serves DESIGN_VISION.md's differentiation goal.

**New test added:** `test_locomotion_tweak_parity()` in `run_tests.gd` — regression-guards the legs/anti_grav/hover_engine fix and the three new gizmo axis mappings.

**Verified:**
- Full suite: **12/12 green** (was 11 suites; added 1). Combat-sim HP numbers shifted slightly (1720→1650 vs baseline 1720→1656) — expected, since the locomotion fix changes computed stats for any roster/loadout unit using legs/anti_grav/hover with non-default size settings.
- Visual: `progress_captures/2026-07-12/locomotion_tweak_fix/` — 6 screenshots (3 types × size 1.0/2.0) confirm the fix visually.

**Commit checkpoint:** see git log.

---

## 2026-07-12 (Sat) — Day 0: Setup

**Shipped:**
- Initialized git repo at `E:\Build-A-Bomber` (was not previously under version control). `.gitignore` excludes bundled engine binaries (Godot exe/zip, UPBGE ~777MB) and the `.godot/` cache — these are large, static, and regenerable, so keeping them out of git keeps checkpoints fast.
- Baseline commit `c6f472f` captures the entire prototype as it stood before this session's changes — the revert target if anything goes sideways.
- Created `PROGRESS.md` (this file) and `DECISIONS_NEEDED.md` for judgment-call tracking.
- `DESIGN_VISION.md` already existed from prior conversation (Chris's Spore/KSP reference points + the Forged-Battalion-trap differentiation test) — this now drives the Sunday audit.

**Verified:**
- Full headless test suite (`run_tests.gd`, 11 suites) — **all green** at baseline. This is the reference point for "did I break anything."

**Next:** Sunday Design Lab audit against `DESIGN_VISION.md` — specifically checking discrete-swap-only vs. continuous tweakables, and whether symmetry-aware editing is real.
