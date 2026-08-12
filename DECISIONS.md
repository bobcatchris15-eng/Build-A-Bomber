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



---

## 8. Hull Collider / Fitted AABB Refactor — 2026-08-11

Design Lab construction was reading the catalog `size` field as the
hull's collider and `base_hull_size` meta, while the visual mesh was
fitted to that catalog box by `get_hull_mesh_fit()`. For hulls whose
actual silhouette disagrees with their sidecar box (every SDF /
marching-cubes-baked hull, the spire / catamaran / pillbox /
interceptor / airship-envelope families, the tapered ship keels), the
collider was larger than the visible mesh, and every dimension
consumer that read it (locomotion station positions, armor auto-fit,
running-gear placement, hull.position.y, unit.gd's separation /
selection / cargo radii) silently disagreed with what the player
could see. Modules dropped onto the hull snapped to the bounding
shell and floated off the silhouette.

**Decision: the fitted AABB is now the source of truth for the
collider and the meta.** The catalog `size` stays as reference
metadata (weight tiers via `get_hull_size_tier`, the locomotion
`catalog_size` module-reference, `REFERENCE_HULL_SIZE` for
fallback / scale-anchor roles) but is no longer used for placement
geometry. Two new helpers in `module_catalog.gd`:

- `get_fitted_aabb_from_fit(mesh, fit_dict)` - given a fit dict
  already produced by `get_hull_mesh_fit()`, returns the
  hull-local AABB the visual mesh actually occupies.
- `get_hull_fitted_aabb(hull_type_id, mesh, extra_scale)` -
  convenience wrapper that runs one orientation search and
  returns the AABB.

**Four sites converted, all in one pass:**

- `module_placer.gd:_place_hull_from_ui` - the fresh-hull path
  the player exercises. Computes the fitted AABB after
  `get_hull_mesh_fit`, sets `BoxShape3D.size` and
  `base_hull_size` to the fitted size, positions the hull at
  `fitted_size.y / 2.0` so it sits on the ground.
- `module_placer.gd:update_hull_appearance` - the re-fit path
  on hull swap / armor change / scale rebuild. Same logic,
  reused via a `current_size` local, so the collider and the
  meta track every visual change.
- `blueprint_manager.gd:reconstruct_vehicle` - the load path
  for saved blueprints. Same treatment, so a loaded design
  mounts its wheels and armor to the same dimensions as a
  freshly built one.
- `gizmo_3d.gd:_apply_scale_to_node` - the scale-drag path.
  Updates the collider, the `base_hull_size` meta, and
  `hull.position.y` together. Adds a `HullSurfaceScript.rebuild`
  call in `_on_drag_ended` so the precise trimesh module
  placement raycasts against tracks the new scale (a separate
  pre-existing bug, fixed in the same pass).

**Three site-safety fallbacks updated.** Every "no hull loaded"
fallback that previously hard-coded `Vector3(4.0, 1.0, 6.0)` now
reads `ModuleCatalog.REFERENCE_HULL_SIZE` - the same value, but
named for what it is. module_placer.gd, blueprint_manager.gd,
gizmo_3d.gd, unit_assembly.gd.

**What stays the same.**

- `get_hull_mesh_fit()` is unchanged. The orientation-finder
  and per-axis scaling still do their job; we just take its
  output more seriously downstream.
- `HullSurfaceScript.rebuild()` is unchanged. The precise
  trimesh was already the snap surface; now the box fallback
  it falls back to is the same AABB.
- `HullSurface` collider layer 5 (16) unchanged. Same
  `surface_raycast()` precision-first behaviour.

**Why one pass, not behind a feature flag.** This is a correctness
fix to a long-standing visual bug. The catalog `size` field is
not going away (weight tiers, the locomotion module-reference
`catalog_size`, `REFERENCE_HULL_SIZE` for legacy fallbacks), so
no data migration is needed. Every hull in the roster, every
saved design, every loaded blueprint benefits on the next
place / load / scale drag.

**Verification.**

- `test_hull_collider_matches_visual_aabb` in
  `prototype/tests/test_designer_lab.gd` - drives
  `_place_hull_from_ui` for `medium_hull`, `pillbox_foundation`,
  `the_cube`, `the_rod`, asserts the `BoxShape3D.size` and the
  `base_hull_size` meta agree with
  `ModuleCatalog.get_hull_fitted_aabb()` to within 0.05m, and
  that `hull.position.y` keeps the hull on the ground.
- `test_hull_collider_rebuilt_on_scale` - drives
  `gizmo_3d.gd:_apply_scale_to_node` at 1.4x on a fresh hull,
  asserts the collider, the meta, and `hull.position.y` all
  scale together. Then exercises
  `HullSurfaceScript.rebuild()` and confirms a fresh trimesh
  Shape3D was produced.
- `GOLDEN_LOCOMOTION_LAYOUT` in `suite_base.gd` is unchanged
  - the locomotion refit happens at the gizmo's drag end, not
  per frame, so the golden fixture's pre-scale stations are
  still the right values. A scale-drag-then-check leg
  exists in the test plan as a follow-up.

**Files changed.** module_catalog.gd (helpers), module_placer.gd
(two sites + three fallback literals), blueprint_manager.gd
(three sites + one fallback literal), gizmo_3d.gd (one site +
trimesh-on-drag-end + one fallback literal),
battle/units/unit_assembly.gd (one fallback literal),
tests/test_designer_lab.gd (two suites), run_tests.gd
(manifest).
