# Godot 4.7 Pitfalls & Anti-Patterns

> A reference list of bugs, footguns, and engine-level landmines the project
> has either hit, is at risk of hitting, or that the engine's own release notes
> flag as live. Each entry has a stable anchor (`#anchor-id`) for cross-references
> from `CLAUDE.md`, `minimax.md`, `llm_directives.md`, and any future doc.
>
> **Audience:** anyone writing or reviewing GDScript in this repo. The
> pitfalls are ordered by likelihood × impact, not by category.
>
> **Engine pin:** Godot **4.7.1** (per `project.godot:20` and the bundled
> `Godot_v4.7.1-stable_win64.exe`). The 4.6 → 4.7 jump is officially "relatively
> safe" but shipped four behaviour changes that bite real projects; they are
> flagged under [#jolt-softbody3d-default-mass] and [#input-device-ids].

---

## How to use this doc

- **Writing new code?** Read [#lambda-capture-by-value], [#gdscript-strict-mode],
  and [#performance-the-four-gdscript-patterns] first.
- **Debugging a hitch?** Read [#hitches-first-frame-first-shot-first-spawn] and
  [#navigation-agent-perf-cliff].
- **Tests are flakey?** Read [#class-name-uid-cache-staleness] and
  [#godot-import-cache-when-it-lies].
- **Touching navmesh?** Read [#navigation-server-async-sync],
  [#navigation-agent-avoidance-correct-flow], and
  [#navigation-server-edge-connection-margin-tax].
- **Upgrading the engine pin past 4.7.1?** Re-read the whole file; the
  project-specific risk register at the bottom is where new entries land.

---

## 1. NavigationServer3D queries before first sync (since 4.4)  <a id="navigation-server-async-sync"></a>

Godot 4.4+ moved `NavigationServer3D` map iteration to a **threaded async**
build. A query against a freshly created `NavigationMap` that runs **before the
first sync completes** returns an error: `NavigationServer navigation map query
failed because it was made before first map synchronization`. `map_force_update()`
no longer synchronously synchronises the map; the sync runs on its own schedule.

**Symptoms**

- `map_get_closest_point()` / `map_get_closest_point_normal()` / `map_get_path()`
  returning `Vector3.ZERO` or empty arrays for the first few frames after a bake
- `NavigationAgent3D.is_target_reachable()` falsely returning `false` on a
  reachable target
- A unit drives into water / off a cliff on its first order, then behaves
  correctly from frame ~5 onwards

**Fix**

- `await` a `world_ready`-style signal before allowing AI or units to issue
  path queries. This codebase already does it: `match_director.gd:118-119`
  declares both `signal world_ready` and `var world_is_ready: bool`, and the
  comment at `match_director.gd:107-117` explains the race the flag exists to
  defuse ("a signal already emitted is a signal that never arrives").
- For test code that builds a `NavigationMap` directly, call
  `NavigationServer3D.map_force_update(...)` and then poll
  `NavigationServer3D.map_get_iteration_id(rid) != 0` before issuing queries.

**References:** [godotengine#104671](https://github.com/godotengine/godot/issues/104671), [Godot 4.7 docs `NavigationServer3D`](https://docs.godotengine.org/en/4.7/classes/class_navigationserver3d.html) ("Most NavigationServer3D changes take effect after the next physics frame").

---

## 2. GDScript strict mode: Variant inference warnings as errors  <a id="gdscript-strict-mode"></a>

When `gdscript/warnings/untyped_declaration` (and friends) is set to `error`,
several common GDScript patterns that were warnings under lax rules become
**hard parse errors**. The most common in this codebase:

| Trap | Pattern | Fix |
|---|---|---|
| **Variant inference from a Variant-returning function** | `var x := weakref(obj)` — `weakref()` returns `Variant` | `var x: WeakRef = weakref(obj) as WeakRef` |
| **Ternary with `null`** | `var v := x if cond else null` — the `null` side widens the type to `Variant` | rewrite as an `if/else` block, or `var v: Variant = x if cond else null` |
| **`clamp()` is Variant** | `clamp(x, 0, 1)` returns `Variant` in strict mode | use `clampf()` / `clampi()` for typed clamps |
| **`const` `PackedStringArray` from a function** | `const ARR = some_func()` where `some_func` returns `PackedStringArray` | `static var ARR: Array[String] = ...` (typed) |
| **Module / autoload init that fails** | An autoload script that fails to compile silently breaks every other script that preloads it | boot the project in `--headless --quit-after 30` to surface the chain |

**Verify with the CLI** (per the Japanese `zenn.dev/iori_001` writeup):

```bash
godot --headless --quit-after 30 --path . 2>&1 | grep -E "Parse Error|Compile Error"
```

**This codebase's setting:** `llm_directives.md:39-43` already mandates static
typing. The `Battle.tscn` / `Battlefield.tscn` scenes are not currently run
under strict mode (Project Settings → GDScript → `untyped_declaration` =
`warn` not `error`), so these are latent. If you ever flip that switch, run
the full test wrapper to surface the chain.

**Reference:** [zenn.dev/iori_001 — GDScript 4 strict mode 7 traps](https://zenn.dev/iori_001/articles/gdscript4-strict-mode-7-traps).

---

## 3. Lambda capture by value (CONFUSABLE_CAPTURE_REASSIGNMENT)  <a id="lambda-capture-by-value"></a>

GDScript lambdas (`func (): ...`) capture outer local variables **by value**.
This is the trap that has historically broken this codebase the most — there
is a "GDScript captures local primitives by value" note in
`llm_directives.md:131-134` because the team has been bitten by it.

**The failure mode**

```gdscript
var got_finished := false
signal.connect(func(): got_finished = true)
# Signal fires, but got_finished is still false outside the lambda.
```

A lambda that reads `x` reads the captured value. A lambda that **reassigns**
`x` is shadowing — the outer `x` is unchanged. A warning
`CONFUSABLE_CAPTURE_REASSIGNMENT: Reassigning lambda capture does not modify
the outer local variable` is emitted if warning level is `warn` or higher.

**Symptoms**

- DOT timers that never tick (`var damage := 0.0; timer.timeout.connect(func(): damage += 1.0)`)
- A counter that reads 0 after the loop that was supposed to increment it
- A "done" flag that never flips, leading to a 30-second hang on a
  `while not done` loop in tests
- Homing projectiles that fly straight instead of tracking

**Fixes, in order of preference**

1. **Use a reference type.** Wrap the value in a single-element `Array` or
   use a `Dictionary`. Both are reference types and survive capture:
   `var state := {"hp": 100}; signal.connect(func(): state["hp"] -= 10)`.
2. **Make it a member variable.** `var _done := false` on the owning class.
3. **Use `Callable.bind(value)`** for read-only values that the lambda needs
   to know the specific value of (e.g. the loop index `i` in `for i in range(n)`).
4. **Extract into a real method** that takes the value as a parameter; the
   function scope gives you a fresh binding per call.

**Project context:** the doctrine is to never do this; `llm_directives.md:5.6`
calls it out. If a `CONFUSABLE_CAPTURE_REASSIGNMENT` warning shows up in a
PR, treat it as the bug it is — `zenn.dev/iori_001` says DOT/homing/pierce
behaviour that "always worked in the editor" tends to have this exact bug.

**References:** [godotengine#69014](https://github.com/godotengine/godot/issues/69014) (closed as "by design"), [GDScript reference — Lambda functions](https://docs.godotengine.org/en/latest/tutorials/scripting/gdscript/gdscript_basics.html).

---

## 4. NavigationAgent3D avoidance: feed desired in, apply safe out  <a id="navigation-agent-avoidance-correct-flow"></a>

`NavigationAgent3D` ships with RVO-based local avoidance that **will** cause
your crowd to jitter if you use the obvious "set my velocity to what the
agent suggests" pattern. The correct flow:

```gdscript
func _physics_process(delta):
    var next = nav_agent.get_next_path_position()
    var desired = (next - global_position).normalized() * speed
    nav_agent.velocity = desired  # FEED desired into the avoidance system
    # do NOT move the body here

func _on_velocity_computed(safe_velocity: Vector3):
    velocity = safe_velocity  # apply ONLY the safe velocity, never both
    move_and_slide()
```

**Two specific failure modes in this codebase if you ever re-enable avoidance:**

1. Applying `desired` directly to `velocity` **and** using the
   `velocity_computed` signal — the body gets the sum, the agent does its own
   RVO with a phantom extra, and the crowd fights itself into vibration.
2. Calling `get_next_path_position()` more often than necessary — every call
   that re-targets a different position triggers an A* path query, which is
   the documented perf killer (see [#navigation-agent-perf-cliff]).

**Tuning knobs**

- `time_horizon` (default 1.0) — raise to 2–3 for smoother but slower reactions.
- `max_neighbors` (default 10) — lower to 5–8 in dense crowds to cut jitter.
- `neighbor_distance` — match it to the actual spacing of your units.
- `radius` — the agent's own footprint; too high causes constant avoidance.
- `avoidance_priority` — important units push through, decoration yields.

**This codebase's stance:** `unit_assembly.gd:367-368` explicitly sets
`agent.avoidance_enabled = false`, with the comment
"Local avoidance is OFF. Separation is handled in steering.gd, where it can
be reconciled with formation slots - NavigationAgent3D's built-in avoidance
fights a formation." That is the correct call at RTS scale; do not flip it
on casually. The `_physics_process` separation in `steering.gd` is what keeps
groups from collapsing into each other today.

**References:** [bugnet.io — Fix Godot NavigationAgent Avoidance Jitter](https://bugnet.io/blog/fix-godot-navigation-agent-avoidance-jitter), [godot-proposals#1966 — Improve Navigation with multiple agents](https://github.com/godotengine/godot-proposals/issues/1966).

---

## 5. NavigationServer3D perf cliff (300+ agents)  <a id="navigation-agent-perf-cliff"></a>

The public perf cliff: more than ~300 `NavigationAgent3D` instances in the
same scene on the same `NavigationMap` start to cause noticeable frame stalls
when targets are unreachable. The cause is the A* search that each agent
runs on path query — if the target can't be reached, A* has to search
**every** polygon on the map before giving up, and a tight cluster of 300
agents can issue thousands of these in one frame.

**Symptoms**

- A move order near a wall or off-mesh edge causes a 50–200ms hitch
- Whole-army move commands lag, then snap-correct
- Profiler shows `NavigationServer3D::_query_path` dominating the frame

**Mitigations the codebase already has**

- **One cell-spaced neighbour grid in `match_director.gd`** (`NEIGHBOUR_CELL := 8.0`,
  `_neighbour_grid` rebuilt every physics tick) — separation does the local
  avoidance work, leaving the navmesh query free of agent-agent work
- **Flow-field pathfinding via `flow_field_service.gd`** — one path query
  per destination per team, not one per unit
- **Throttle `get_next_path_position()`** — `unit_assembly.gd:354-380` only
  sets the navigation map once at construction, not per-frame

**What NOT to do**

- Don't add per-frame `get_next_path_position()` calls on agents that
  already have a valid path. If position and path are unchanged, skip the
  call (the official guidance from `godotengine/godot#64567`).
- Don't issue 12 different path queries for 12 units in the same squad to
  the same destination. Use a flow field (already done) or a single
  leader-follower with the followers steering into formation slots.

**Reference:** [godot forum — Terrible performance on NavigationAgent3D](https://forum.godotengine.org/t/godot-terrible-performance-on-navigationagent3d/64567).

---

## 6. `class_name` / ResourceUID cache staleness ("Identifier X not declared")  <a id="class-name-uid-cache-staleness"></a>

The single most-asked question about Godot 4. Adding a new `class_name` (or
autoload) and then running headless tests gives
`Identifier "X" not declared in the current scope` — even though `X` is
plainly there.

**Why**

- The `.godot/global_script_class_cache.cfg` file is built by the editor.
  Headless runs that bypass the editor (or that follow an `.uid` change
  without a re-scan) read a stale cache and report class_names that exist
  as undeclared.
- Since 4.4, every `.gd` / `.tscn` / `.gdshader` ships a sidecar `.uid`
  file. Renaming a file *externally* (not via the editor) breaks the
  sidecar pairing, and the next headless run sees the old path with the
  new UID and panics.

**This codebase's fix:** the test wrapper reimports. `run_tests.ps1` /
`run_tests.sh` (per `CLAUDE.md:51-65`) regenerate the import cache before
running. Running `Godot_v4.7.1-stable_win64_console.exe --headless --script run_tests.gd`
directly is documented as broken — `CLAUDE.md:54` calls out the
misleading "Identifier X not declared" symptom specifically.

**If the cache lies to you anyway**

1. Close the editor.
2. Delete `.godot/` (it is a cache; not a project artifact).
3. Open the project once in the editor to regenerate the cache.
4. Run tests.

`CLAUDE.md:217` already calls this out as the second-line of defense. The
`run_tests.ps1` wrapper covers the common case.

**The `.uid` sidecar discipline (since 4.4)**

- **Commit `.uid` files.** They are part of the project state, not generated
  output. `git mv foo.gd bar/foo.gd` MUST be paired with
  `git mv foo.gd.uid bar/foo.gd.uid`.
- Do not put `*.uid` in `.gitignore`.
- If you see `Invalid UID` warnings after an export, find the asset in the
  inspector and resave (it regenerates the sidecar's binding).

**References:** [godotengine#76380 — Class names stop working after a while](https://github.com/godotengine/godot/issues/76380), [godot forum — "Identifier not declared in current scope"](https://forum.godotengine.org/t/identifier-not-declared-in-current-scope/46367), [dev.to/ziva — Godot 4.4 Added .uid Files Everywhere](https://dev.to/ziva/godot-44-added-uid-files-everywhere-heres-what-they-actually-do-4e56).

---

## 7. Performance: the four GDScript patterns that account for most damage  <a id="performance-the-four-gdscript-patterns"></a>

From `dev.to/ziva` and confirmed by the engine's own CPU optimisation doc.
These four cover the majority of GDScript perf complaints in shipped
projects:

### 7a. Untyped variables and arrays  <a id="untyped-variables"></a>

`var hp = 100` is untyped. `var hp: int = 100` is typed. The typed version
skips the runtime type-resolve step on every read/write. Same for arrays:
`var arr: Array[int] = []` is meaningfully faster than `var arr = []`. The
project's `llm_directives.md:39-43` already mandates static typing; the
hot paths in `unit.gd:62-180` and `match_director.gd` are typed throughout.

### 7b. `get_node()` / `get_tree()` / `get_nodes_in_group()` in hot loops  <a id="scene-tree-lookups"></a>

Every call walks the scene tree. Cache via `@onready var foo = $X` and use
the field. Group lookups in `_process` are the most common offender; the
project is clean here because `@onready` is used everywhere it matters.

### 7c. String operations in `_process` / `_physics_process`  <a id="string-operations-in-hot-loops"></a>

`str(x) + " " + str(y)` allocates two strings per frame. Use
`"%d %d" % [x, y]` or move the string work behind `if OS.is_debug_build()`
gating. There is one measurable instance in this codebase:
`battlefield.gd:381-386` builds a 15-character ASCII HP bar by `+=` every
physics tick. Fine for Test Range's 1 player unit; would be a problem if
the function were ever reused at scale.

### 7d. Signal connection duplication  <a id="signal-duplication"></a>

`Object.connect()` does not deduplicate. Connecting the same signal in
both `_enter_tree()` and `_ready()` causes the slot to fire twice per
emit. Either gate with `is_connected()` or only connect in one lifecycle
hook. The codebase connects mostly in `_ready()`; the recent AAR wiring in
`match_director.gd:316-318` is a place to re-check when adding new
handlers.

**Reference:** [dev.to/ziva — How to Profile GDScript Performance in Godot 4: A 2026 Guide](https://dev.to/ziva/how-to-profile-gdscript-performance-in-godot-4-a-2026-guide-16jn).

---

## 8. Jolt SoftBody3D default mass 1 kg (4.6 → 4.7 breaking change)  <a id="jolt-softbody3d-default-mass"></a>

Under Jolt Physics, `SoftBody3D` no longer defaults mass to 0 (which
previously auto-calculated 1 kg per point, producing very high total mass).
It now defaults to **1 kg for the whole body**, matching Godot Physics.
`linear_stiffness` also applies differently. Pre-existing `SoftBody3D`
instances will look and behave differently after the upgrade.

**This codebase's exposure:** zero — there are no `SoftBody3D` nodes in
the project. Listed for completeness in case a future feature (cloth
flags, deformable terrain) adds one without the dev realising the default
changed.

**Reference:** [Godot 4.7 Beta 1 changelog — Jolt Physics: Make SoftBody3D default mass 1 kg](https://godotengine.org/article/dev-snapshot-godot-4-7-beta-1/) (GH-116041).

---

## 9. Keyboard / mouse device ID scheme change (4.6 → 4.7)  <a id="input-device-ids"></a>

Mouse and keyboard device IDs changed scheme in 4.7. Code that hardcoded
device IDs (e.g. "the player's mouse is device 0") will break.

**This codebase's exposure:** low. `scripts/core/input_service.gd` is the
keybinding table and uses action names (the abstract layer), not device
IDs. If anything in the project bypasses the input service to read
`InputEvent.device` directly, it should be re-tested.

**Reference:** [Godot 4.7 Beta 1 changelog — Input: Add device IDs to keyboard and mouse input events](https://godotengine.org/article/dev-snapshot-godot-4-7-beta-1/) (GH-116274).

---

## 10. NavigationServer3D edge connection margin performance tax  <a id="navigation-server-edge-connection-margin-tax"></a>

The "edge connection margin" feature exists to help beginners merge
sloppily-created, misaligned navigation meshes. It is a per-tile
performance cost that does not scale to large maps.

**This codebase's exposure:** worth checking. `terrain_builder.gd` builds
multi-region navmeshes (`match_director.gd:84-93`: "one region PER NAVMESH
TILE, not one region for the whole ground/amphibious surface"). If the
project setting `navigation/world/map_use_edge_connections` is on (or
per-region equivalent), the per-tile cost compounds.

**Recommendation:** disable it explicitly in `terrain_builder.gd` for the
shipped maps and add a comment, since the maps are authored rather than
user-generated.

**Reference:** [godotengine#96483 — NavigationServer3D::sync could be optimized](https://github.com/godotengine/godot/issues/96483).

---

## 11. HDR output / AreaLight3D (4.7)  <a id="hdr-arealight3d"></a>

Godot 4.7 ships real-time HDR output to displays on Windows, macOS, Linux
(Wayland), iOS, visionOS. The `AreaLight3D` node is a rectangular
real-time light source with correct soft shadowing and distance falloff.
iOS and Web (WebGL 2.0) are **not** in the HDR support list; wasm64
exports are.

**Implications for this codebase**

- The `WorldEnvironment` in `Battle.tscn:13-21` and `Battlefield.tscn:5-21`
  currently sets `tonemap_mode = 3` (Filmic). If HDR output is enabled in
  the user's display settings, existing materials and post-processing may
  render slightly differently — the doc string says HDR/SDR is one of the
  predictable 4.6 → 4.7 break zones.
- The new `AreaLight3D` is a candidate for replacing clustered point-light
  rigs in the Design Lab preview (window lights, overhead panels) — note
  it for the visual polish backlog, not for the battle unification work.

**Reference:** [godotengine.org/4.7 — Lights, Camera, Action!](https://godotengine.org/releases/4.7/).

---

## 12. NavigationAgent3D pause/resume re-registration bug (4.7.1 fix)  <a id="navigation-agent-pause-resume"></a>

4.7.1 RC 1 / RC 2 fixed: navigation agents were unconditionally being
added back to the avoidance simulation after a `pause → resume` cycle,
which could thrash the avoidance system on matches that are paused and
unpaused repeatedly.

**This codebase's exposure:** any pause flow (the pause overlay, the
loading screen, the after-action report). `match_director.gd` does not
appear to use `get_tree().paused`, but if a future feature adds a real
pause, this is the bug it will hit.

**Reference:** [Godot 4.7.1 maintenance release notes](https://godotengine.org/article/maintenance-release-godot-4-7-1/) (GH-120249).

---

## 13. NavigationServer3D `map_get_closest_point_normal` returning unnormalized value (4.7 beta 3)  <a id="map-get-closest-point-normal"></a>

In 4.7 beta 2, `map_get_closest_point_normal` could return an
**unnormalized** normal vector (magnitude not 1.0). Fixed in 4.7 beta 3
(GH-119022). If you are on 4.7.1, this is patched, but the codebase's
vision/flow-field code that consumes normals should not assume magnitude
1.0 — it should `normalised()` defensively.

**This codebase's exposure:** `vision_service.gd` and `flow_field_service.gd`
both work with surface normals; check the call sites for `normalised()`
post-read.

**Reference:** [Godot 4.7 beta 3 changelog](https://godotengine.org/article/dev-snapshot-godot-4-7-beta-3/) (GH-119022).

---

## 14. Hitches: first frame, first shot, first spawn  <a id="hitches-first-frame-first-shot-first-spawn"></a>

The codebase has dedicated probe scripts for these because the team has
already mapped them:

- `tools/probe_first_shot_hitch.gd` — first shot of a match
- `tools/probe_death_hitch.gd` — first unit death (triggers vfx, audio, AAR record)
- `tools/probe_engagement_hitch.gd` — first contact between opposing armies
- `tools/probe_unit_stutter.gd` — per-frame cost when N units are in play
- `tools/probe_unit_tick_breakdown.gd` — which per-frame call is the culprit

**Known cause, documented in code:** `unit_assembly.gd:42-51`:

> "MEASURED: reconstruct_vehicle() is the entire cost of spawning a unit -
> spawn_unit totalled 1069.94ms mean per call, of which spawn.assemble was
> 1046.90ms, against 2.94ms for weapons and 0.07ms for the nav agent."

That is the SDF/Marching-Cubes hull rebuild doing its full bake per spawn.
The mitigation already in place is a static `_hull_cache` keyed on the
blueprint's full content + faction (`unit_assembly.gd:69-79`); the cache
serves a `.duplicate()` of the cached template, which is cheap.

**When you add a new "I think there's a hitch" probe** to `tools/`, follow
the convention: name `probe_<thing>_hitch.gd`, write it to stdout, ship
in the same commit as the change being measured. The cache for the
comment "this is just scratch" is already violated — there are 58 such
probes in `tools/`. See the "documentation drift" issue in the
top-of-tree doc sprawl; the probe discipline is good, the *placement*
in the repo is the smell.

**Other first-frame hitch sources to know**

- The shader compile of any new material the first time it is rendered —
  including `StandardMaterial3D` instances built at runtime
- `NavigationServer3D` first sync (see [#navigation-server-async-sync])
- The first `_ready` of any node whose script does significant work in
  `_ready` rather than lazily in first use
- The first call into `AudioStreamPlayer.play()` for any stream loaded
  via `load()` rather than preloaded at scene-build time

---

## 15. Draw call discipline (the "1000 MeshInstance3D problem")  <a id="draw-call-discipline"></a>

For a 3D RTS, draw call count is the more common render bottleneck than
per-pixel cost. The `unit_assembly.gd:60-64` comment captures the
project's own take:

> "MATERIALS ARE SHARED between duplicates, deliberately. battle_finish.gd
> states absolute targets (a floor and a ceiling) rather than applying a
> delta, so applying it repeatedly to the same shared material is
> idempotent - and sharing gives the renderer fewer distinct materials,
> which is the direction the ~31 draw calls per unit needs to move
> anyway."

The hierarchy to follow, in order of impact:

1. **`MultiMeshInstance3D` for any repeated prop.** Grass, rocks, trees,
   fence posts — one MultiMesh with 10,000 instances is one draw call;
   10,000 `MeshInstance3D` is 10,000 draw calls + 10,000 scene-tree
   objects with per-node overhead. The terrain layer (`terrain_builder.gd`)
   is the obvious place to convert.
2. **Fewer materials, fewer surfaces.** Each distinct material is a draw
   call. Atlas textures, merge materials, merge small static meshes.
3. **Shadow multiplication.** Every shadow-casting light re-renders
   casters into its shadow map. `match_director.gd:415-419` is already
   aware of this (it sets `directional_shadow_max_distance` based on
   `WorldScale`).
4. **Visibility range / LOD** for clutter; the project does not yet use
   either, but the `LOD` is a clear future task.

**Reference:** [strayspark.studio — Godot 3D Optimization Guide 2026](https://www.strayspark.studio/blog/godot-3d-optimization-guide-2026).

---

## 16. The `.godot/` import cache: when it lies, when to nuke it  <a id="godot-import-cache-when-it-lies"></a>

The `.godot/` directory is engine-cached, project-portable state. It is
gitignored. It regenerates on first open. It is also the source of
multiple classes of "I just changed X and Godot doesn't see it" bugs.

**Symptoms it has lied**

- "Identifier X not declared" after adding a new autoload or `class_name`
  → see [#class-name-uid-cache-staleness]
- A scene that was just changed reverts visually to its old layout
- A script edit doesn't take effect until a restart
- A `default_roster/*.json` edit isn't picked up by the rosters shown
  in the Blueprint Library

**When to nuke it (close the editor first)**

- After a Godot version upgrade (the cache may be incompatible)
- After moving a script or scene *externally* (not via the editor)
- After adding the first `class_name` to a script that previously had none
- After adding or removing an autoload in `project.godot`
- When the test wrapper (`run_tests.ps1`) is failing with the misleading
  "Identifier not declared" class of error
- When the project shows "Invalid UID" warnings on export

The repo's `run_tests.ps1` already calls the import step before the
script step (per `CLAUDE.md:58-65`). Manual nuke: delete `.godot/` while
the editor is closed, reopen.

---

## 17. Things to never do in `_init()`  <a id="_init-pitfalls"></a>

### 17a. `_init()` with required parameters

`PackedScene.instantiate()` calls the no-arg constructor. Any `class_name`
script with a required-parameter `_init()` will **silently fail** to
instantiate from a scene if its `_init` is not the only way it's created.
Symptoms: a scene loads with the script attached but the script's
fields are at default; no error, no warning, just a half-built object.

The fix: put parameterless setup in `_init` and treat any constructor args
as optional with defaults. The codebase does this correctly — `_init`
appears only as a parameterless constructor for autoloads and probes
(`match_director.gd`, `probe_*.gd`).

### 17b. Reading `@export` values in `_init`

`@export` properties are deserialised **after** `_init` runs. Reading
them in `_init` gives the default value (the script's own literal
default), not the value the editor / scene file set. Use `_ready` for
any read of `@export` state.

The codebase is clean here.

---

## 18. Async, threading, and where it isn't safe  <a id="async-threading-safety"></a>

### 18a. `NavigationServer3D` is not safe to call from arbitrary threads

NavigationServer3D queries are mostly safe from threads since 4.4, but
the threaded async map iteration is the only place it has been hardened
to be. Don't issue `get_closest_point` etc. from a `Thread` you spawned
yourself for a HUD lookup — the answer can be a frame stale at best,
undefined at worst.

### 18b. Audio stream playback from threads

`AudioStreamPlayer.play()` is not safe to call from a worker thread. The
codebase routes all SFX through `AudioManager` (autoload), which is
thread-safe by being on the main thread.

### 18c. The 4.7.1 `WorkerThreadPool` deadlock (GH-120250)

A deadlock in `WorkerThreadPool` was introduced then reverted in 4.7.1
RC 3. If you are on 4.7.1 stable you are fine; the warning is that
**if you upgrade past 4.7.1, check the WorkerThreadPool PR list for
re-applies** before running the heavy async terrain bake.

**Reference:** [Godot 4.7.1 RC 3 changelog](https://godotengine.org/article/release-candidate-godot-4-7-1-rc-3/) (GH-120250).

---

## 19. `Image.blend_rect` / `blit_rect` fail on a format mismatch — by doing nothing  <a id="image-blend-rect-format-mismatch"></a>

`Image.blend_rect()` and `blit_rect()` do **not** convert between pixel
formats. They assert that source and destination match:

```cpp
// core/io/image.cpp
ERR_FAIL_COND(format != p_src->format);
```

The trap is the failure mode, not the restriction. `ERR_FAIL_COND`
pushes an error and **returns** — it does not crash, and it does not
partially draw. The call silently becomes a no-op, so a feature built on
it renders exactly as it did before and looks like it was never wired
up rather than like it failed.

Hit while compositing fog onto the minimap (`battle_hud.gd`): the
minimap baked at `FORMAT_RGB8`, the fog source was `FORMAT_RGBA8`
(it needs the alpha channel to blend at all), and the composite did
nothing. The minimap is now `FORMAT_RGBA8` throughout — the alpha is
unused by the terrain bake itself, it exists purely so the formats
agree.

Two follow-on notes:

- `ImageTexture.update()` requires the image to keep the **same format
  and size** it was created with, so changing an image's format means
  changing it everywhere in that pipeline, including `_static_image`
  and the initial `create_from_image()`.
- `Image.resize()` preserves format, so a duplicate-resize-blend chain
  is safe once the formats agree.

**Verify a compositing path with a pixel readback, not a clean log.** An
`Image` op that no-ops leaves no visible trace in a passing test run.

## 20. Headless never compiles shaders, so a broken shader passes the whole test suite  <a id="headless-does-not-compile-shaders"></a>

`--headless` selects the **dummy rasterizer**. It creates no rendering
device and compiles no shader. A `Shader` whose GLSL does not compile is
therefore completely invisible to `run_tests.ps1` — the resource loads,
the `ShaderMaterial` is assigned, every suite passes, and the failure
first appears as untextured or missing geometry in a playtest.

This bites hardest for shaders built as string constants in GDScript
(`vision_service.gd`'s `SHROUD_SHADER`), because there is no `.gdshader`
file for the editor to have validated either.

The check is to render on a real driver, briefly, and assert on pixels:

```bash
# NOT --headless - that is the whole point
./Godot_v4.7.1-stable_win64_console.exe --path . \
    --script tools/probe_shroud_shader_compiles.gd
```

Two things that make such a probe trustworthy:

- **Assert pixels, not absence of errors.** A shader that compiles can
  still draw nothing (frustum-culled, wrong render priority, a depth
  guard that rejects every fragment). `probe_shroud_shader_compiles.gd`
  samples the framebuffer with the effect toggled off and on.
- **`get_texture().get_image()` reads back sRGB-encoded**, while shader
  uniforms are linear. `sRGB(0.015)` is about `0.14`, not `0.015`, so an
  absolute threshold picked against the linear value will look like a
  failure when the shader is perfectly correct. Compare against a
  converted expectation, or A/B the same pixel.

Related: `Camera3D.unproject_position()` returns `(0, 0)` before the
root viewport has a size, which in a `--script` probe is most of setup.
Locate a sample point by searching the rendered frame for a distinctly
coloured marker object instead of computing it.

---

## Project-specific risk register

Tracks the current state of which pitfalls the project has already hit,
which it is exposed to, and which apply to the active work
(battle-system unification). When you fix or trigger one, update the
matching row.

| Subsystem | Live risk | Anchor | Notes |
|---|---|---|---|
| **Battle unification (Test Range → Battle.tscn)** | async navmesh sync, lambda capture, `.uid` cache | [#navigation-server-async-sync], [#lambda-capture-by-value], [#class-name-uid-cache-staleness] | The unification moves Test Range onto the new `match_director` pipeline. Any new wiring that calls `get_next_path_position()` before `world_ready` will hit [#1]. |
| **Design Lab (SDF hull baking)** | 1069ms first-spawn hitch already mitigated by `_hull_cache` | [#hitches-first-frame-first-shot-first-spawn] | Cache works; do not break the "metadata must survive duplication" invariant at `unit_assembly.gd:53-58`. |
| **Skirmish / Operations (RTS scale, 200+ units planned)** | NavigationServer3D perf cliff, avoidance jitter | [#navigation-agent-perf-cliff], [#navigation-agent-avoidance-correct-flow] | Flow field + steering separation is the correct architecture; do not enable RVO without a measured reason. |
| **UI (HUD shells, Design Lab chrome)** | Control offset transforms (4.7 new), HDR-aware material selection | (4.7 feature, not a pitfall) | Control offset transforms in 4.7 are a deliberate improvement over hand-rolled `Vector2` offsets. Track in the UI polish backlog. |
| **Test suite (211 suites, 10 area files)** | `.godot` cache staleness, NavServer3D first-sync timing in headless, **shaders never compiled** | [#class-name-uid-cache-staleness], [#navigation-server-async-sync], [#headless-does-not-compile-shaders] | The `run_tests.ps1` reimport covers (a); the explicit `await world_ready` pattern covers (b). (c) is not coverable headlessly at all — any shader work needs a windowed probe alongside the suite. |
| **Fog of war (world shroud + minimap)** | Shader is a GDScript string constant, so neither the editor nor the suite validates it; minimap fog is an `Image` composite | [#headless-does-not-compile-shaders], [#image-blend-rect-format-mismatch] | Covered by `tools/probe_shroud_shader_compiles.gd` (windowed, pixel-asserting) and `tools/probe_minimap_fog.gd`. Run both after touching `vision_service.gd`'s `SHROUD_SHADER` or the minimap image pipeline. |
| **Hull loader (`user://mods/hulls/`)** | Same `.uid` discipline as the rest of the project | [#class-name-uid-cache-staleness] | Mods that ship without `.uid` sidecars will fail to load under 4.4+; document this for the modding API. |
| **Audio (procedural + curated)** | Curated music licensing — see `CREDITS.md` | not a Godot pitfall | Procedural alternative is `--procedural-music` flag. Cross-link to the CREDITS.md warning. |
| **Curated vs procedural music fork** | Two parallel pipelines with one shipping | (process, not engine) | Listed in the top-of-tree doc drift; resolve before any release. |

---

## 4.7 known-issue tracker (live engine issues affecting this project)

Pulled from the Godot 4.7 release notes and 4.7.1 maintenance release.
These are the issues the engine team has acknowledged; expect patches
to arrive in 4.7.2 or 4.8.

| GH issue | Title | Status | Project impact |
|---|---|---|---|
| GH-120249 | NavigationAgent3D unconditionally added to avoidance after pause/resume | Fixed in 4.7.1 | low (we don't pause matches) |
| GH-119022 | `NavigationServer3D.map_get_closest_point_normal` returns unnormalized | Fixed in 4.7 beta 3 | low (defensive `normalised()` is the right answer anyway) |
| GH-119551 | CSG performance regression from auto smoothing | Fixed in 4.7 beta 3 | low (CSG is not the active hull path; SDF is) |
| GH-120299 | Adreno 660 + Vulkan: geometry errors with `LightmapGI` | Open | low (no Android, no LightmapGI) |
| GH-120272 | Editor UI container layout breaks when Editor Scale < 1.0 | Open | low (editor-only) |
| GH-120279 | Programmatically updating gravity vector currently fails | Open | low (we use `ProjectSettings` for gravity) |
| GH-120250 | Deadlock in `WorkerThreadPool` (reverted in RC 3) | Reverted in 4.7.1 | monitor on next upgrade |

The upstream tracker:
[godotengine/godot 4.7 milestone](https://github.com/godotengine/godot/issues?q=is%3Aissue+milestone%3A4.7).

---

## See also

- `CLAUDE.md` § "Important Notes" — engine version pin, test wrapper
  workflow, the rules the project follows
- `llm_directives.md` §3.5, §4.2, §5.6 — project rules around
  no-emoji, no-script-reorder, lambda capture (this file is the
  long-form reference; `llm_directives.md` is the short rules)
- `minimax.md` §2.6 — "no silent fallbacks" + the lambda-capture
  warning, recapped in [#lambda-capture-by-value]
- `DECISIONS.md` — code-and-document drift; some of the entries in
  the "plan tracker" overlap with this file (HULL_BUILDER_PLAN,
  PERFORMANCE_PLAN, etc.) and the unification work should update
  both
- [Godot 4.7 release notes](https://godotengine.org/releases/4.7/)
- [Godot 4.7.1 maintenance release notes](https://godotengine.org/article/maintenance-release-godot-4-7-1/)
- [dev.to/ziva — GDScript 4 strict mode 7 traps](https://zenn.dev/iori_001/articles/gdscript4-strict-mode-7-traps) (Japanese; English summary in §2 above)
- [bugnet.io — Fix Godot NavigationAgent Avoidance Jitter](https://bugnet.io/blog/fix-godot-navigation-agent-avoidance-jitter)
- [strayspark.studio — Godot 3D Optimization Guide 2026](https://www.strayspark.studio/blog/godot-3d-optimization-guide-2026)
- [dev.to/ziva — Godot 4.4 Added .uid Files Everywhere](https://dev.to/ziva/godot-44-added-uid-files-everywhere-heres-what-they-actually-do-4e56)
- [dev.to/ziva — How to Profile GDScript Performance in Godot 4: A 2026 Guide](https://dev.to/ziva/how-to-profile-gdscript-performance-in-godot-4-a-2026-guide-16jn)
