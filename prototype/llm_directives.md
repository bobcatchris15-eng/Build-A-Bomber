# LLM Directives & Coding Standards

This document defines the architectural guidelines, GDScript style guides, testing practices, and deprecated/superseded patterns for **Kitbash Command** prototype (a Godot 4.7 RTS project).

All future code changes and feature additions must adhere strictly to the rules laid out in this file.

---

## 1. Engine & Environment Configuration
- **Godot Version**: `4.7.1-stable` (Win64 binaries are bundled in the `prototype/` directory).
- **Primary Directories**:
  - `res://scripts/`: Production game logic and controllers.
  - `res://scenes/`: Game scenes (`.tscn`).
  - `res://tests/`: Headless automated test suites (extend `suite_base.gd`).
  - `res://tools/`: Development, baking, and validation utility scripts.
  - `res://assets/blueprints/default_roster/`: Read-only pre-made player and enemy design files.

---

## 2. GDScript Style Guide & Conventions
Follow Godotâ€™s official GDScript guidelines with the following additions:

### 2.1 Formatting & Indentation
- **Indentation**: Use **tabs** for indentation (Godot editor default). Do not use spaces.
- **Line Length**: Keep lines under **100 characters** (soft limit of 80 characters for simple statements).
- **Spacing**:
  - Surround operators with single spaces: `a + b`, not `a+b`.
  - Put a space after commas in arrays/dictionaries/arguments: `[a, b, c]`.
  - Put a space after colons in type definitions: `var speed: float = 10.0`.
- **Blank Lines**: Keep a single blank line between functions. Use blank lines inside functions to group logical blocks.

### 2.2 Naming Conventions
- **Files & Folders**: `snake_case` (e.g., `blueprint_manager.gd`, `main_menu.gd`).
- **Class Names**: `PascalCase` (e.g., `class_name MyClassName`).
- **Variable & Function Names**: `snake_case` (e.g., `func get_hull_volume_factor()`).
- **Constants**: `UPPER_SNAKE_CASE` (e.g., `const HULL_SCALE_MIN = 0.5`).
- **Private/Internal Members**: Prefix with a leading underscore (e.g., `var _loading: bool`, `func _build_ui()`).

### 2.3 Type Safety
- **Static Typing**: Strongly type everything. Do not write dynamic types unless absolutely required.
  - Variable declarations: `var height: float = 26.0` or `var vehicle: CharacterBody3D = null`.
  - Function parameters & returns: `func rename_blueprint(id: String, new_name: String) -> bool:`.
- **Inferred Types**: Avoid un-typed assignments. Use `:=` for type inference only when the type is obvious and explicit (e.g., `var dir := DirAccess.open(path)`).

### 2.4 Script Member Order
Organize script contents in this order:
1. `extends` statement.
2. `class_name` definition.
3. `signal` declarations.
4. `const` definitions.
5. `enum` definitions.
6. `@export` variables.
7. Public variables (unprefixed).
8. Private/Internal variables (prefixed with `_`).
9. `@onready` variables.
10. Engine lifecycle functions (`_init`, `_ready`, `_process`, `_physics_process`, `_input`, etc.).
11. Public methods.
12. Private/Internal methods (prefixed with `_`).

---

## 3. High-Level Systems & Architectural Rules

### 3.1 Asynchronous Scene Transitions (`SceneRouter`)
- **GDScript Compilation Delay**: Loading large scenes (`Skirmish.tscn`, `MainLab.tscn`) stalls the main thread due to recursive script compilation of `preload()` graphs.
- **Rule**: Never load heavy scenes synchronously using `get_tree().change_scene_to_file()`.
- **Instruction**: Use the `SceneRouter` autoload: `SceneRouter.change_scene_async(target_scene_path)`. The router parses script preloads and compiles them progressively frame-by-frame, keeping the throbber responsive.

### 3.2 Blueprint Serialization & Pathing
- **Roster vs. Scratch splits**:
  - Explicit user "Save" writes permanently to `user://blueprints/<id>.json`.
  - "Test in Arena" writes to a temporary scratch file `user://lab_scratch.json` (do not pollute the blueprint library folder).
- **Built-in Blueprints**: Preload or read-only blueprints are fetched from `res://assets/blueprints/default_roster/`. User blueprints are fetched from `user://blueprints/`.
- **Rule**: `blueprint_manager.gd` is the single source of truth for loading, serialization, and reconstruction of designs. Always use its helper functions.

### 3.3 Combat, Damage, & Custom Mounts
- **Threshold Model**: Resolves in `damage_resolver.gd`. Hits below an armor threshold deal chip damage (15% of reduced damage). Hits $\ge 4\times$ threshold bypass armor reduction.
- **Subsystem Stripping**: 35% of damage impacts module attachments directly, potentially stripping weapons or disabling locomotion.
- **Sponsons (Vertical Mounting)**: Sponsons align direct-fire weapons outboard on near-vertical walls via `Basis.looking_at(outboard, Vector3.UP)`.
  - Sponson-capable weapons use a low-profile faceted housing blister (`sponson_blister.glb`).
  - Sponson embed depth is automatically calculated via visual bounds measuring (`min(wanted, reach - 0.30)`).
  - Mortars, artillery, and launchers cannot wall-mount; placement is rejected on vertical glacis (`!is_sponson_capable()`).

### 3.4 Procedural Structural Modules
- **Scale Isolation**: Girders, wedges, blocks, and plates must not be scaled using standard `Node3D.scale` properties, as this stretches textures and hardware details (screws, collars).
- **Rule**: Send structural scales to the `struct_scale` metadata/property, keep `Node3D.scale` at `(1.0, 1.0, 1.0)`, and trigger a mesh re-bake. The body re-tessellates procedurally, and structural details are instanced at a $1:1$ ratio.



### 3.6 Hull Data Flow (catalog size vs. fitted AABB)
- **The catalog size field is REFERENCE metadata, not placement geometry.** It is used by weight tiers (get_hull_size_tier), the locomotion module-reference (catalog_size in layout ctx), REFERENCE_HULL_SIZE for legacy fallbacks, and a few stat-anchor roles. It is NOT used for the hull's collider, the ase_hull_size meta, or the visual mesh placement.
- **The fitted AABB is the source of truth for placement.** Compute it via ModuleCatalog.get_hull_fitted_aabb(hull_type_id, mesh) (or get_fitted_aabb_from_fit(mesh, fit_dict) when the fit dict is already on hand). This is the AABB the visible mesh occupies in hull-local space, after get_hull_mesh_fit()'s orientation correction and per-axis scaling.
- **Where the fitted AABB must flow:**
  - BoxShape3D.size on the hull's CollisionShape3D
  - hull.set_meta("base_hull_size", fitted_size) - every dimension consumer reads this
  - hull.position.y = fitted_size.y / 2.0 - keep the hull on the ground
- **Where the catalog size is still the right value:**
  - Vector3(ModuleCatalog.REFERENCE_HULL_SIZE) for the "no hull loaded" safety-net default (was hard-coded Vector3(4, 1, 6))
  - get_running_gear_size(hull_size) reads base_hull_size, not catalog
  - Any new code that needs a hull dimension should ask hull.get_meta("base_hull_size") first; fall back to the catalog only if the meta is missing (which means the hull was constructed without going through _place_hull_from_ui or econstruct_vehicle)
- **When refitting a hull (armor change, scale, hull swap), every consumer has to refit together.** The collider's BoxShape3D.size, the ase_hull_size meta, hull.position.y, and the HullSurface trimesh MUST be updated in the same call. update_hull_appearance() is the one place that handles visual + collider + meta together; the gizmo's _apply_scale_to_node is the one place that handles scale + trimesh-rebuild together. New code paths that change the hull's visual must go through one of these or follow the same pattern.

 & Practices

### 4.1 Running Tests
- **Wrapper Scripts**: Always run tests using `./run_tests.ps1` (Windows) or `./run_tests.sh` (Linux/Mac/Git Bash).
- **Why**: Running raw `run_tests.gd` headless bypasses the resource import phase. A stale `.godot` cache causes confusing script compilation errors when script autoloads or class names change.
- **Compile Verification**: After editing, run compile validation:
  ```bash
  ./Godot_v4.7.1-stable_win64_console.exe --headless --script tools/compile_check_all.gd
  ```

### 4.2 Test Order & Manifest
- **Execution Order Flakes**: Several navigation mesh and Recast-bake suites flake due to shared-process memory leak or nondeterminism.
- **Rule**: Pinned execution order is required. Do not sort or randomize the `SUITE_ORDER` list in `run_tests.gd`.
- **Adding a Test**: Add your suite function to the correct category in `prototype/tests/` (e.g., `test_weapons_and_damage.gd`), then register the file category and function name under `SUITE_ORDER` in `run_tests.gd`.
- **Quarantine Retries**: The test driver allows up to 2 attempts per suite to shield against navmesh flakes. Treat only consecutive failures as real breaks.

### 4.3 Golden Locomotion Layouts
- **Layout Parity**: Metrics for locomotion mount coordinates across three hull sizes are frozen under `GOLDEN_LOCOMOTION_LAYOUT` in `res://tests/suite_base.gd`.
- **Rule**: Refactoring module placement must not alter the layout layout coordinates. Any intentional coordinate change must update the golden fixture in its own commit, with a clear explanation of the visual improvement.

---

## 5. Deprecated & Superseded Systems (DO NOT USE)

Be aware of superseded files and patterns. Do not use, revive, or replicate them:

1. **`res://scripts/battle_unit.gd` (DELETED, 2026-08-10)**:
   - **Production Status**: Retired in the battle-system unification's Phase 4. New combat work goes in `res://scripts/battle/units/unit.gd` + `damage_model.gd` + `unit_assembly.gd` + `boost_controller.gd`.
   - **Test Exception**: The damage-model test suites that used `BattleUnitScript` as a full unit fixture were retired in the same pass per Chris's "nuke those tests entirely" call. The replacement coverage is the `tests/battle/` suite (battle_movement, battle_combat, battle_ai, etc.), which exercises the same surface through the new runtime.
2. **`res://scripts/player_vehicle.gd` (DELETED, 2026-08-10)**:
   - **Production Status**: Retired with `battle_unit.gd` and the rest of the pre-unification Test Range. The "minimal CharacterBody3D damage target" pattern it served is gone with the suites that used it.
3. **`res://scripts/target_dummy.gd` and `res://scenes/TargetDummy.tscn` (DELETED, 2026-08-10)**:
   - **Production Status**: Retired with the pre-unification Test Range. The Test Range now uses the 3 bundled default dummies on `Battle.tscn` via `TestRangeLauncher` (the launcher's `DUMMY_BLUEPRINT_PATHS` constant).
4. **`res://scripts/battlefield.gd` and `res://scenes/Battlefield.tscn` (DELETED, 2026-08-10)**:
   - **Production Status**: The pre-unification Test Range scene and its controller script. The Test Range now boots on `Battle.tscn` via `TestRangeLauncher` with a `MatchRuleSet.test_range(...)` rule set.
5. **`prototype/test_cargo_capacity.gd` and `prototype/test_cargo_capacity_2.gd` (DELETED, 2026-08-10)**:
   - **Production Status**: Throwaway one-off probes that depended on `battle_unit.gd`. Gone with their dep.
6. **`MatchConfig`'s seven legacy pre-match fields (RETIRED, 2026-08-10)**:
   - `selected_map_id` (as a rule-set input; still on MatchConfig as a display field), `player_faction`, `enemy_faction`, `selected_blueprint_paths`, `ai_difficulty`, `starting_credits`.
   - **Replacement**: `MatchConfig.rule_set` (a `MatchRuleSet` written by `match_setup.gd` / `operations_draft.gd` / `operations_setup.gd` / `test_range_launcher.gd`). `match_director.gd` reads only the rule set now.
7. **`blueprint_manager.gd`'s `LEGACY_SLOT_PATH = "user://blueprint.json"` (DELETED, 2026-08-10)**:
   - The Test Range now reads `SCRATCH_PATH = "user://lab_scratch.json"` (which is also what the Design Lab writes) via `TestRangeLauncher`. No second write, no second file.
8. **`res://scripts/blueprint_library_panel.gd` (DELETED earlier)**:
   - **Replacement**: Entirely replaced by `res://scripts/blueprint_library_screen.gd` and the associated scene `res://scenes/BlueprintLibrary.tscn`.
9. **Local Panel Styleboxes**:
   - **Replacement**: Setting custom stylebox overrides directly in Panel nodes is deprecated. All panels must inherit theme classes via `bomber_theme.tres` or style through `ui_theme.gd`/`ui_tokens.gd`.
10. **Hardcoded Map Lists**:
    - **Replacement**: Do not write hardcoded map properties. Maps are JSON files stored under `data/maps/` and automatically discovered via directory scanning in `MapCatalog`.
11. **Procedural Mount Columns**:
    - **Replacement**: The old procedural mounting columns and base plates on weapons were deleted. Do not double-mount or add procedural cylinders under weapon meshes.
12. **Lambda Closure Primitive Captures**:
    - **Pitfall**: GDScript captures local primitives (like `float`, `int`, `bool`) **by value** in closures. If a lambda needs to mutate a captured variable and have it reflect outside, wrap it inside a reference type such as a single-element `Array`.

