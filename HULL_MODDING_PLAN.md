# Hull Modding Plan (design doc, 2026-07-17)

**Status: planning only, not implemented.** Chris wants to review this before any code changes land. This doc grounds every claim in the actual current codebase (file:line references throughout) rather than guessing at what the catalog/loader/save system do today.

**Goal:** replace `module_catalog.gd`'s hardcoded hull dictionary entries with a directory scan that discovers `<name>.glb` + `<name>.yaml`/`.json` sidecar pairs at runtime, so a new hull can be added by dropping two files in a folder — no code changes, no recompiling GDScript.

---

## 1. What metadata the sidecar file needs to carry

Every field an existing hull entry in `module_catalog.gd` actually uses today (verified by reading every hull entry, `light_hull` through `fortress_wall_foundation`, plus every getter that reads a hull-specific field):

| Field | Type | Required? | Default if absent | Source |
|---|---|---|---|---|
| `name` | string | yes | — | display name, e.g. "Light Hull" |
| `category` | string | **no — always `"hull"`, not authorable** | forced to `"hull"` by the loader | see §4, this field currently doubles as the discriminator between hulls/weapons/locomotion/etc. in one shared catalog dict |
| `hp` | float | yes | — | |
| `weight` | float | yes | — | also drives `get_hull_size_tier()`'s light/medium/heavy manufactory bucket ([module_catalog.gd:1483](prototype/scripts/module_catalog.gd:1483)) — **fully weight-threshold-driven already, no per-hull-type hardcoding to migrate** |
| `metal` | int | yes | — | build cost |
| `crystal` | int | yes | — | build cost |
| `dps` | float | no | `0.0` | every existing hull entry sets this to `0.0` explicitly; hulls don't deal damage themselves |
| `size` | Vector3 (x, y, z) | yes | — | **the single most load-bearing field** — drives collision box, mount-zone facet classification, greeble/decal placement, manufactory placement, everything (see the mesh-swap research from earlier this session) |
| `color` | Color | yes | — | fallback tint used when no authored mesh exists ([module_placer.gd:428-433](prototype/scripts/module_placer.gd:428)); also the box-primitive fallback color if the `.glb` fails to load |
| `is_foundation` | bool | no | `false` | static defense (pillbox/tower/fortress_wall) vs. mobile hull — gates manufactory-queue eligibility ([module_catalog.gd:1131](prototype/scripts/module_catalog.gd:1131)) and several placement-flow branches |
| `base_energy` | float | no | `0.0` | starting max_energy before generators ([module_catalog.gd:1139](prototype/scripts/module_catalog.gd:1139)) |
| `base_vision` | float | no | `20.0` | starting sight radius before sensor_suite ([module_catalog.gd:1146](prototype/scripts/module_catalog.gd:1146)) |
| `draught` | float | no | `0.5` (`HULL_DRAUGHT_DEFAULT`) | naval-only; gates deep-water-only navigation past `SHALLOW_WATER_DRAUGHT_THRESHOLD = 1.0` ([module_catalog.gd:1463-1466](prototype/scripts/module_catalog.gd:1463)) |
| `underside_y_bias` | float | no | `0.0` | corrects underside-mount (wheels/legs/hover) placement when the mesh's visual bottom doesn't sit exactly at the collision box's `-halfHeight` (naval/airship hulls whose true silhouette doesn't fill the box) ([module_catalog.gd:1502](prototype/scripts/module_catalog.gd:1502)) |
| `turreted_capable` | bool | no | `true` | whether weapons on this hull get independent traverse vs. everything mounts `frame_built` (whole-vehicle-aims) ([module_catalog.gd:1248](prototype/scripts/module_catalog.gd:1248)) — no existing hull sets this to `false`, but the getter already supports it |

**Fields intentionally left out of the sidecar schema, and why:**
- `traits` (seen on locomotion entries, e.g. `["ground_contact", "amphibious"]`) — never used on any hull entry today, locomotion-only.
- `base_weight_capacity` / `thrust_coefficient` — locomotion-only fields, never on a hull.

**New field this plan needs to add, not present in the current schema:** a `domain` field (`"Ground"` / `"Naval"` / `"Air"` / `"Static Defense"`) — today this grouping lives entirely OUTSIDE `module_catalog.gd`, hardcoded in `parts_menu.gd`'s `HULL_DOMAINS` dict purely for UI sidebar organization (see §4). For a modded hull to sort into the right Parts Catalog section without a code change, the sidecar file has to declare its own domain rather than relying on a table the loader doesn't control.

---

## 2. Directory structure and naming convention

Mirror the existing asset convention exactly (`res://assets/models/hulls/<type_id>.glb`) rather than inventing a new layout:

```
prototype/assets/models/hulls/
    light_hull.glb
    light_hull.yaml
    medium_hull.glb
    medium_hull.yaml
    ...
    heavy_tank.glb          <- a modder's new hull, same folder
    heavy_tank.yaml
```

- **`type_id` is derived from the filename stem** (`heavy_tank.glb` + `heavy_tank.yaml` → `type_id = "heavy_tank"`), same identifier space already used everywhere (`hull.set_meta("type_id", ...)`, blueprint `"hull_type"` field, `MeshAssetLoader.get_hull_mesh(hull_type_id)`'s path lookup). No separate id field needed inside the YAML — the filename **is** the id, which also means a modder can't accidentally create a naming collision between the mesh and its own metadata declaring a different id.
- Both files **must share the same directory and stem** — no separate "hulls I'm adding" folder, so the existing `res://assets/models/hulls/%s.glb` lookup path in `mesh_asset_loader.gd` keeps working completely unmodified for both built-in and modded hulls alike. This is deliberate: it means the mesh-loading half of the pipeline needs **zero changes** for modding to work — only the metadata/catalog half changes.
- `type_id` should be restricted to `[a-z0-9_]+` (lowercase snake_case, matching every existing id) — the loader should reject/skip a file whose stem doesn't match, rather than silently accepting `"Heavy Tank.yaml"` and producing an id with spaces/capitals that would break blueprint save/load round-tripping.

---

## 3. Loader mechanics

**When it scans:** once, lazily, on first access — not on every `get_catalog()` call. This is a hard requirement, not a style preference: `get_catalog()` is a `static func` that **rebuilds and returns a brand-new dictionary literal on every single call** ([module_catalog.gd:4](prototype/scripts/module_catalog.gd:4)), and `get_module_data()` — the single most-called function in the whole catalog system, hit on nearly every stat calculation, mount decision, and AI tick — calls `get_catalog()` internally on every invocation ([module_catalog.gd:1567-1571](prototype/scripts/module_catalog.gd:1567)). A directory scan + N file reads + N parses executing on every one of those calls would be a real, immediate performance regression. The scan result has to be cached in a `static var`, populated once (either lazily on first `get_catalog()` call, or explicitly at project boot), and merged into the dict `get_catalog()` builds every time cheaply (a dictionary merge, not a re-scan).

**What gets scanned:** every `*.glb` file in `res://assets/models/hulls/` that has a same-stem `.yaml`/`.json` sidecar. A `.glb` with no sidecar is skipped with a warning (not a crash) — this is what lets the *existing* procedurally-generated hulls keep working exactly as they do today during a transition period (see §4) without needing all 15 to get a sidecar file on day one.

**Parsing:** Godot's built-in `JSON` class (`JSON.new()` / `JSON.parse_string()`) is already used by this project for blueprint save files ([blueprint_manager.gd:153,216,229,277](prototype/scripts/blueprint_manager.gd:153)) — no new dependency, no plugin. See §5 for the JSON-vs-YAML call.

**Validation and defaults — must not crash on a bad third-party file:**
1. Parse failure (malformed JSON/YAML syntax) → log a warning naming the file, skip that hull entirely. The game must still boot with N-1 hulls, not refuse to start over one broken mod file.
2. Missing required field (`name`/`hp`/`weight`/`metal`/`crystal`/`size`) → same treatment: warn and skip. Don't guess a fake `size` — a hull with a wrong bounding box silently corrupts collision/mount-zone/greeble placement in ways that are hard to debug later (see the mesh-swap research: `size` is load-bearing for far more than just the label reads).
3. Wrong type (e.g. `"size": "big"` instead of a 3-number array) → same: warn and skip that single hull, not the whole scan.
4. Optional fields missing → apply the exact same defaults the current GDScript getters already use (`draught` → `0.5`, `base_vision` → `20.0`, `underside_y_bias` → `0.0`, `turreted_capable` → `true`, `is_foundation` → `false`, `dps` → `0.0`) — reuse those getters unchanged; they already handle a dict that's missing keys via `.get(key, default)`, so a sparse modded sidecar (an author who only fills in `name`/`hp`/`weight`/`metal`/`crystal`/`size`/`color`/`domain`) works today's code path already supports.
5. `type_id` collision (a modded file using the same stem as a built-in hull, e.g. someone's `medium_hull.yaml` in a mod folder) — **out of scope for a single-directory scan** (the naming convention in §2 makes this a filesystem-level conflict, first-writer-wins or last-scanned-wins depending on directory walk order) — flag as an open question in §5 rather than solving speculatively before there's a real mods-vs-built-in-assets directory split to design against.

**Runtime merge:** the scanned hull dicts get merged into the same unified structure `get_catalog()` already returns (see §4 for why it's the *same* structure and not a separate one) — each entry gets `"category": "hull"` force-set by the loader (never trusted from the sidecar file, since nothing about a hull mod should be able to make itself register as a weapon or locomotion module and corrupt those subsystems).

---

## 4. Migration path — what else touches hull `type_id`s today

Searched every script referencing any current hull id string. Three genuinely different situations, not one:

**(a) Already fully data-driven — no migration needed, works on a modded hull automatically:**
- `get_hull_size_tier()` (manufactory light/medium/heavy queue bucket) — pure `weight` threshold math, no per-type_id list ([module_catalog.gd:1483](prototype/scripts/module_catalog.gd:1483)).
- `is_foundation()`, `get_base_energy()`, `get_base_vision()`, `get_hull_draught()`, `get_underside_y_bias()`, `is_turreted_capable()` — all generic `.get(key, default)` lookups against whatever dict `get_module_data()` hands back, indifferent to where that dict came from.
- The mount-zone system (`classify_facet()`, `get_mount_style_for_normal()`) and collision shape — confirmed in the earlier mesh-swap research to operate purely on the `size` field and a raycast against a `BoxShape3D`, never on hardcoded per-hull-type logic.
- `skirmish.gd`'s roster/manufactory-queue/deep-draught checks — all route through the generic getters above, not hardcoded id lists.

**(b) Hardcoded fallback default `"medium_hull"` — a real, necessary special case, not a bug to remove:**
Seven call sites (`battle_unit.gd:136,152`, `battlefield.gd:67,86,134`, `blueprint_manager.gd:34,190,294`, `module_placer.gd:109,380,867,1048`, `stat_calculator.gd:419,588`, `enemy_ai.gd:98,119`, `skirmish.gd:398,416,812,849`) all use `"medium_hull"` as the fallback when a hull's `type_id` metadata is missing or a blueprint's `hull_type` key is absent. **This means `medium_hull` must always exist and always be loadable**, whether it stays a hardcoded built-in entry or becomes a shipped sidecar pair — a moddable system cannot let `medium_hull` be deletable/overridable into something broken, since half the codebase silently falls back to it as *the* safe default hull. Worth treating as a "protected" id, not just another mod-replaceable entry.

**(c) Genuinely hardcoded, per-type_id, and would NOT generalize to a new modded hull without further work:**
- **`parts_menu.gd`'s `HULL_DOMAINS` dict** ([parts_menu.gd:18-25](prototype/scripts/parts_menu.gd:18)) — a separate hardcoded `type_id → "Ground"/"Naval"/"Air"/"Static Defense"` table used only for Parts Catalog sidebar grouping. A modded hull with no entry here would need a fallback (probably `"Ground"`) or — the cleaner fix, and why §1 adds a `domain` field to the sidecar schema — this table gets replaced entirely by reading `domain` off each hull's own catalog entry instead of a separate hardcoded map. This is a real, necessary code change alongside the loader, not optional.
- **`interceptor_hull` nose-taper deform**, special-cased by literal string equality in three places (`blueprint_manager.gd:339`, `module_placer.gd:1065`, `stat_calculator.gd:420`) — explicitly documented in this codebase's own comments as "proof-of-concept for interceptor_hull only." A modded hull cannot opt into this feature at all without a code change (there's no data field gating it, just `if type_id == "interceptor_hull"`). Out of scope to generalize as part of the modding loader itself — flagging so Chris knows this one feature stays built-in-hull-only unless a future pass turns it into a real data-driven flag (e.g. `"supports_nose_taper": true`).

**Blueprint save/load compatibility — already fine, verified directly:**
`blueprint_manager.gd` stores `"hull_type": hull.get_meta("type_id")` as a **plain string** in the saved JSON blueprint ([blueprint_manager.gd:34](prototype/scripts/blueprint_manager.gd:34)) — not an enum, not an index into a fixed array. A blueprint built with a modded hull round-trips through save/load exactly like a built-in one, no format change needed. The one real risk: **loading a blueprint whose `hull_type` no longer exists** (the mod was uninstalled since the save was made). Traced this directly: `get_module_data()`'s fallback for an unknown `type_id` is `cat["basic_cannon"]` ([module_catalog.gd:1571](prototype/scripts/module_catalog.gd:1571)) — **a weapon's data, not a hull's**, an existing latent bug that's currently borderline-theoretical (every built-in `type_id` always exists) but becomes a real, easy-to-hit scenario the moment hulls are moddable. Flagged as an open question in §5, not solved here.

---

## 5. Open questions / risks for Chris to weigh in on

1. **Trust/security of loading third-party mesh files.** A `.glb` is a binary format; Godot's glTF importer is the attack surface, not this project's own code. This plan doesn't change that exposure meaningfully versus today (the project already loads whatever `.glb` sits in `assets/models/hulls/`), but a *modding* feature invites players to download and install mesh files from strangers in a way "the dev team's own asset pipeline" doesn't — worth deciding whether mod hulls need any kind of sandboxing/warning, or whether "same trust model as installing any other Godot game mod" is an acceptable answer.
2. **JSON vs. YAML — recommend JSON**, for concrete reasons, not just convention: Godot has a **native, built-in `JSON` class** with zero dependencies, already used by this exact project for blueprint saves. YAML has **no built-in Godot support** — it would require a third-party GDExtension/addon, a new dependency this project doesn't currently have, purely for hull metadata files. The stated motivation for sidecar files over glTF `extras` was explicitly "simpler, tool-agnostic, human-editable, no import internals involved" — JSON satisfies all four of those exactly as well as YAML would (arguably better on "tool-agnostic," since JSON parsers are truly universal) without adding a dependency. If human-editability/comments are the real reason YAML felt appealing, that's worth surfacing explicitly since JSON has no comment syntax — but adding a YAML parser dependency for that alone is a real tradeoff to weigh, not a foregone conclusion.
3. **Schema versioning.** This project already has a working precedent: `blueprint_manager.gd`'s `CURRENT_BLUEPRINT_VERSION` constant + a "save version newer than the game understands → warn, then attempt load anyway" policy ([blueprint_manager.gd:10,251-252](prototype/scripts/blueprint_manager.gd:10)). Recommend the identical pattern for the hull sidecar schema (a `"schema_version"` field, warn-not-block on mismatch) rather than inventing a new versioning policy — but worth Chris explicitly signing off on reusing that exact precedent versus wanting something stricter for third-party mod content specifically (e.g. hard-reject an incompatible schema version instead of best-effort loading it, since a mod file is less trustworthy than the game's own save format).
4. **Unknown/removed `hull_type` on blueprint load** (see §4c) — recommend fixing the fallback to be hull-shaped (fall back to `medium_hull`'s data, not `basic_cannon`'s) as a small, low-risk bug fix bundled with this work, plus a real user-facing warning ("this design used a hull that's no longer installed") reusing the existing toast-notification pattern this project already has for other load-time warnings. Flagging as a decision because it's a scope question (bundle the fix now vs. track separately) more than a design question.
5. **`type_id` collision** between a mod file and a built-in hull, or between two installed mods (see §3, validation point 5) — no directory-structure separation between "built-in" and "modded" hulls is proposed here (§2 puts them in the same folder, matching the existing convention). If Chris wants mods physically separated from shipped assets (e.g. a `user://mods/hulls/` directory scanned in addition to `res://assets/models/hulls/`), that's a bigger structural decision this plan didn't assume — flagging rather than guessing, since it also changes the collision-handling story (a `user://` mod overriding a `res://` built-in becomes a deliberate, nameable feature instead of an accident).
6. **Stretch-slider/mount-zone/collision interaction** — already answered in full during this session's mesh-swap research (see prior conversation turn): these systems are keyed entirely off the catalog's declared `size` field and a `BoxShape3D`, never the mesh's real topology, so they need **zero changes** to support modded hulls — this is inherited for free as long as the loader correctly populates `size` from the sidecar. Restating here only so it's not lost as a separate "risk" — it's actually the one part of this whole plan that's already solved by how the existing system happens to be built.
