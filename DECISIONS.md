# Active Decisions & Pending Implementation Plans

> **Update 2026-08-09:** All of the plans listed below have actually been completed, but their original markdown files were never updated to reflect this. The next step is to update the documentation and `PROGRESS.md` to record their completion.

## 1. Speed & Naval Rebalance (`docs/archive/SPEED_AND_NAVAL_REBALANCE_PLAN.md`)
**Status:** Completed (Needs Documentation Update)

## 2. Hull Builder Expansion (`docs/archive/HULL_BUILDER_PLAN.md`)
**Status:** Completed (Needs Documentation Update)

## 3. Hull Modding System (`docs/archive/HULL_MODDING_PLAN.md`)
**Status:** Completed (Needs Documentation Update)

## 4. Locomotion Expansion (`docs/archive/LOCOMOTION_EXPANSION_PLAN.md`)
**Status:** Completed (Needs Documentation Update)

## 5. Performance Improvements (`docs/archive/PERFORMANCE_PLAN.md`)
**Status:** Completed (Needs Documentation Update)

## 6. Visual & UX Polish (`docs/archive/VISUAL_AND_UX_POLISH_PLAN.md`)
**Status:** Completed (Needs Documentation Update)

---

## 7. Battle System Unification — 2026-08-10 (Phases 1-5 complete; Phases 6+ pending)

Test Range, Skirmish, and Operations now route through one
`match_director.gd` + `Battle.tscn` runtime with a per-mode
`MatchRuleSet` gating what each mode is allowed to do. Five phases
landed in one session, all on Godot 4.7.1.

**Decisions made and why (the load-bearing ones):**

- **Cluster scatter, not just a count trim.** The user asked for
  "patches, denser" and we needed the per-iteration cost down
  anyway. Cluster scatter answers both: ~1190 nodes for ~810 trees
  + ~380 ore, vs the pre-cluster ~1650 (~0.72× the original).
  Visual reads as groves, not thickets. Reverting to random scatter
  is a search-and-replace against the pre-cluster constants
  (kept commented in `terrain_builder.gd`).
- **Nuke tests that depended on legacy scripts.** The user's call:
  "my call, just nuke those tests entirely. We can build ones to
  replace them if needed." The battle layer is now covered by
  `tests/battle/test_match_rule_set_integration.gd` (4 suites,
  Phase 2) plus `test_match_rule_set.gd` (9 suites, Phase 1) and
  the `test_terrain_and_maps.gd` smoke tests (which already
  exercise the new runtime through `Battle.tscn`).
- **DOF removed entirely, not gated.** A one-line re-enable
  recipe is documented in the `rts_camera.gd` file header. Gating
  it on a config flag would have been a feature for a feature
  nobody asked for, and the cost is on the always-on per-frame
  path.
- **`MatchConfig` shim retired.** Six legacy fields
  (`player_faction`, `enemy_faction`, `selected_blueprint_paths`,
  `ai_difficulty`, `starting_credits`, `scene`) were write-only
  shadows of rule-set fields. `match_director.gd` now reads
  strictly from the rule set. `MatchConfig` carries only
  `rule_set` and `selected_map_id` (the latter is display-only).
  `starting_credits` is set on the rule set post-construction
  with a `-1` sentinel that preserves the rule set's own default.
- **`_write_match_config` signature change.** Old:
  `(stage, ops_node)`. New: `(stage, operation_id, stage_index)`.
  The helper no longer reaches through an ops_node for
  `operation_id` / `stage_index`; those are passed in directly.
- **`TestRangeLauncher` is a Node, not a static helper.** Lets
  `SceneRouter` route through it the same way every other
  launcher routes, and lets the Main Menu's PROVING GROUND card
  and the Design Lab's "Test in Arena" button share one
  function (no per-caller drift on map / dummies / rule set).
- **Production HUD layout gate, not a refactor.** The fix
  wasn't a redesign — it was adding a `moved` flag, gating
  `_layout_toolboxes()` on it, and `call_deferred` after every
  state change that alters combined minimum size (panel toggle,
  `open_queue`, `_add_item_button`). The deferred call covers
  the VBoxContainer race the original author already documented
  ("list landed at y=1053, off-screen, when the conditional
  was `if moved`").
- **Chase camera, world-space mount.** Parented to the focused
  unit would have inherited the unit's yaw, which spins
  unpredictably during combat. World-space mount is stable.
- **MatchRuleSet as `RefCounted`.** Cheap copies via
  `factory().duplicate()`, and a future `to_dict()` / `from_dict()`
  save path is a one-liner away (the round-trip is already
  tested in `test_match_rule_set.gd`).

**What's pending.**

- Operations save/load: `MatchRuleSet.to_dict()` / `from_dict()`
  is in place; the Operations UI doesn't call it yet. This is
  the next big system that touches the rule set.
- Two pre-existing parse errors (not from this work):
  `LiveryScript` in `battle/buildings/structure.gd:95`,
  `detection_mult` in `battle/vision/vision_service.gd:316`.
  These will start gating tests once the focused editor flags
  them. They need to be fixed before the test wrapper can run
  cold-cache without the workaround.
- Two dead DOF tests in `test_ui_and_camera.gd` (DOF band
  monotonicity, DOF blur ceiling) — helpers are gone, tests
  target them. Delete in the next housekeeping pass.
- `user://blueprint.json` legacy slot path is gone from
  `blueprint_manager.gd`; any user with a save in that slot
  will fall through to the scratch slot on next launch. The
  scratch save is the only save that runs in the new flow.

**Files changed (cumulative).** See `PROGRESS.md` 2026-08-10
entries for the full list per phase. The unified runtime now
sits in `prototype/scripts/battle/` (match_director.gd,
match_rule_set.gd, units/, buildings/, economy/, hud/,
vision/, navigation/) and the per-mode launchers are
`scripts/match_setup.gd`, `scripts/operations_draft.gd`,
`scripts/test_range_launcher.gd`.

