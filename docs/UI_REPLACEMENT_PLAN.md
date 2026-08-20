# Kitbash Command — Battle UI Replacement: Detailed Implementation Plan
## Plan 1: Minimal Diegetic Command Console (No Grease Pencil)

**Target**: Replace `battle_hud.gd`, `right_rail.gd`, `selection_panel.gd`, `production_hud.gd` with a unified diegetic command console  
**Constraint**: Battlefield retains 100% vertical visibility; bottom ~120px persistent chrome  
**Theme**: Buried bunker command desk — bakelite, brushed aluminum, amber/green CRT, folded paper drawers  
**Coordination**: Performance session (P1-P4 complete) has reduced per-unit node count via `bake_module_visual()`; UI must not regress draw calls

---

## 1. Architecture Overview

### 1.1 File Structure (New + Modified)

```
prototype/scripts/battle/hud/
├── command_console.gd          ← NEW: Root HUD orchestrator (replaces battle_hud.gd responsibilities)
├── desk_instrument_bar.gd      ← NEW: Bottom 48px persistent bar (resources, power, clock, alerts)
├── production_tab_bar.gd       ← NEW: 5 tabs above desk bar (LIGHT/MEDIUM/HEAVY/STRUCTURES/DEFENSES)
├── context_drawer.gd           ← NEW: Slides up on selection (tabbed: STATUS/WEAPONS/TARGETING/MOVE/SPECIAL)
├── production_drawer.gd        ← NEW: Slides up from tab click (accordion queue lists)
├── intel_feed.gd               ← NEW: Top-left collapsible teletype log
├── minimap_overlay.gd          ← REFACTOR: Extracted from battle_hud.gd (toggleable, phosphor radar)
└── tactical_feed.gd            ← DELETED (functionality merged into context_drawer)

prototype/scripts/ui/
├── crt_readout.gd              ← NEW: Reusable amber/green CRT mono-font widget
├── bakelite_panel.gd           ← NEW: Theme variation + shader params for desk surfaces
├── folded_paper_panel.gd       ← NEW: Drawer panel material (canvas + vignette)
├── aluminum_trim.gd            ← NEW: Tab edges, slider tracks
└── teletype_log.gd             ← NEW: Scrolling paper-tape log (shared by intel_feed + orders)

prototype/scripts/battle/hud/   (DELETED)
├── right_rail.gd
├── selection_panel.gd
└── production_hud.gd

prototype/scripts/battle_hud.gd  ← SLIM: Minimap + director wiring only (delegates to command_console)

prototype/scripts/build_ui_theme.gd  ← MODIFIED: Add new theme variations
prototype/shaders/
├── phosphor_display.gdshader   ← EXISTING: Reuse for CRT readouts + minimap
└── crt_warmup.gdshader         ← NEW: Panel expand animation (scanline bloom-in)
```

### 1.2 Scene Hierarchy (Runtime)

```
BattleHUD (CanvasLayer)
├── CommandConsole (Control, PRESET_TOP_LEFT, full viewport)
│   ├── DeskInstrumentBar (Control, PRESET_BOTTOM_WIDE, height=48)
│   │   ├── ResourcesCRT (CRTReadout)          ← "1,240 cr  +32/s"
│   │   ├── PowerCRT (CRTReadout + ProgressBar) ← bar + "LOW POWER" text
│   │   ├── MissionClock (CRTReadout)           ← "14:32 / 45:00"
│   │   └── AlertStack (HBoxContainer)          ← 4 icons: contact/ready/power/intel
│   ├── ProductionTabBar (Control, PRESET_BOTTOM_WIDE, y=-48, height=36)
│   │   ├── TabButton[LIGHT]    (badge: queue depth)
│   │   ├── TabButton[MEDIUM]   (badge: queue depth)
│   │   ├── TabButton[HEAVY]    (badge: queue depth)
│   │   ├── TabButton[STRUCTURES] (badge: queue depth)
│   │   └── TabButton[DEFENSES] (badge: queue depth)
│   ├── ContextDrawer (PanelContainer, PRESET_BOTTOM_WIDE, hidden, max_h=0.4*vh)
│   │   ├── TabBar (HBoxContainer)              ← STATUS | WEAPONS | TARGETING | MOVE | SPECIAL
│   │   └── StackContainer (5 pages)            ← one per tab
│   ├── ProductionDrawer (PanelContainer, PRESET_BOTTOM_WIDE, hidden, max_h=0.5*vh)
│   │   ├── AccordionList (VBoxContainer)       ← 5 sections, one open at a time
│   └── MinimapOverlay (TextureRect, PRESET_TOP_RIGHT, 180x180, toggleable)
│
├── IntelFeed (PanelContainer, PRESET_TOP_LEFT, 320x200, collapsible)
│   └── TeletypeLog (ScrollContainer)           ← time-stamped entries
│
└── (SelectionDock removed — SelectionPanel merged into ContextDrawer)
```

### 1.3 Data Flow

```
MatchDirector
├── .economy → DeskInstrumentBar._refresh_resources()          (5 Hz throttle)
├── .production → ProductionTabBar._refresh_badges() + ProductionDrawer._rebuild()
├── .selection → ContextDrawer.update_selection()              (event-driven)
├── .vision → MinimapOverlay._composite_fog() + IntelFeed.add_entry()
└── .signals (structure_built, structure_lost, unit_spawned) → relevant refresh
```

---

## 2. Component Specifications

### 2.1 DeskInstrumentBar (`desk_instrument_bar.gd`)

**Visual**: Bakelite panel, 48px tall, full width, `preSET_BOTTOM_WIDE`  
**Material**: `bakelite` shader params (`wear: 0.15, grime: 0.25, vignette: 0.35, brightness: 0.75`)  
**Layout**: HBoxContainer, `SPACE_LG` separation, centered group + right-aligned alerts

| Element | Spec |
|---------|------|
| **ResourcesCRT** | Amber CRT, mono font 14pt, text: `"{credits} cr  +{income}/s"`, right-aligned |
| **PowerCRT** | Amber CRT label "POWER" + horizontal ProgressBar (160px), fill: amber→red at 80%, text "LOW POWER" blinks (0.5s) when `economy.is_low_power()` |
| **MissionClock** | Green CRT, mono 14pt, `"{elapsed} / {limit}"` |
| **AlertStack** | 4 icon buttons (24x24), `SIGNAL_HAZARD` tint when active: `contact` (radar), `ready` (hammer), `power` (bolt), `intel` (paper). Click → `IntelFeed.expand_to_entry(category)` |

**Signals**: `alert_clicked(category: String)`

**Update cadence**: 5 Hz (same as ProductionHUD `_refresh_acc`)

---

### 2.2 ProductionTabBar (`production_tab_bar.gd`)

**Visual**: Brushed aluminum tab bar, 36px tall, sits directly above DeskInstrumentBar  
**Material**: `aluminum` shader params (`wear: 0.08, grime: 0.12, scale: 0.9, vignette: 0.15`)  
**Tabs**: 5 equal-width buttons, `TOOLBOX_WIDTH = 264px` logic → each tab = `viewport_width / 5`

| Tab | Queue Key | Badge | Tooltip |
|-----|-----------|-------|---------|
| LIGHT | `"light"` | queue depth | "Light vehicles — {contributors} factory(s)" |
| MEDIUM | `"medium"` | queue depth | "Medium armor — {contributors} factory(s)" |
| HEAVY | `"heavy"` | queue depth | "Heavy armor — {contributors} factory(s)" |
| STRUCTURES | `"building"` | queue depth | "Base structures — {contributors} constructor(s)" |
| DEFENSES | `"defense"` | queue depth | "Static defenses — {contributors} constructor(s)" |

**Interaction**:
- Hover → highlight (aluminum `BASE_600` background)
- Click → toggle `ProductionDrawer` for that tier (accordion: close others)
- Badge: amber numeral, `FONT_MICRO`, top-right of tab
- Active tab: `SIGNAL_HAZARD` bottom border (2px, standard highlight — no grease pencil)

**Signals**: `tab_toggled(queue_name: String, open: bool)`

---

### 2.3 ContextDrawer (`context_drawer.gd`)

**Visual**: Folded paper panel, slides up from desk, max 40% viewport height  
**Material**: `folded_paper` (`canvas` shader: `wear: 0.06, grime: 0.30, scale: 0.7, vignette: 0.12, brightness: 0.85`)  
**Animation**: `crt_warmup` shader (0.22s `DURATION_NORMAL`, scanline bloom-in from bottom)  
**Tabs**: 5 buttons in HBoxContainer, `SPACE_MD` separation, `FONT_HEADING` (17pt)

#### Tab 1: STATUS (default)
```
┌─────────────────────────────────────────────────────────────┐
│  IRON HOG M60 ×4                    ████████░░ 78%          │
│  ORDER: ATTACK-MOVE → SECTOR D4      STANCE: HOLD FIRE      │
│  ─────────────────────────────────────────────────────────  │
│  [WEAPONS]  [TARGETING]  [MOVEMENT]  [SPECIAL]  [DISMISS]   │  ← quick-jump pills
└─────────────────────────────────────────────────────────────┘
```
- Aggregate health bar (sum current/max across selection)
- Current order + target (from `unit.current_order_name` + target position → sector)
- Stance dropdown (HOLD / RETURN FIRE / FIRE AT WILL)
- Quick-jump pills: click → switches to that tab

#### Tab 2: WEAPONS
- Per-weapon-group rows (from `unit.get_weapon_groups()`):
  - Icon + name (e.g., "105mm HE Cannon")
  - Ammo: `ProgressBar` (current/max) + text "12/48"
  - Range: `Label` "420m" + range ring toggle (checkbox → `unit.show_range_ring`)
  - Arc: `Label` "FRONT 120°" / "360°"
  - Status: `READY` / `RELOADING 3.2s` / `JAMMED` (red)

#### Tab 3: TARGETING
- Priority list (drag-reorder): `TargetPriority` resource per design
- ROE buttons (radio): HOLD / RETURN FIRE / FIRE AT WILL
- Engagement ranges: sliders per weapon group (min/max)
- "TARGET PRIORITY" preset buttons: ARMOR FIRST / AIR FIRST / NEAREST / WEAKENED

#### Tab 4: MOVEMENT
- Speed readout: `Label` "42 km/h (85% max)"
- Formation: radio buttons (LINE / WEDGE / COLUMN / BOX / ECHELON)
- Path preview toggle (checkbox → shows ghost path on map)
- "FORMATION SPEED: SLOWEST / AVERAGE / FASTEST" radio

#### Tab 5: SPECIAL
- Per-ability buttons (from `unit.get_abilities()`):
  - Icon + name + cooldown ProgressBar
  - Click → issues ability order (if off cooldown)
- Deploy/undeploy toggle (for siege, sensor, shield modules)
- Overload toggle (for engines, reactors) — shows heat bar
- Repair priority slider (for logistics units)

**Input**:
- `Tab` / `Shift+Tab` → cycle tabs
- `Esc` → dismiss drawer (slide down)
- `Space` → pin open (stays open on deselect)
- Double-click unit group in drawer → select all of type (from `SelectionPanel` logic)

---

### 2.4 ProductionDrawer (`production_drawer.gd`)

**Visual**: Folded paper panel, slides up from ProductionTabBar, max 50% viewport height  
**Material**: Same `folded_paper` as ContextDrawer  
**Structure**: Accordion — one tier open at a time (mirrors `ProductionHUD` toolbox behavior)

#### Tier Section (per queue)
```
▼ LIGHT VEHICLES (2 factories, 3 queued)     ████████░░ 65%  x3
  ┌────────────────────────────────────────────────────────┐
  │ SCOUT CAR M3          180 cr  12s  [QUEUE] [×5]        │
  │ FAST ATTACK M12       420 cr  28s  [QUEUE] [×5]  🔒  →  │
  │   Requires: TECH LAB                                         │
  │ LIGHT TANK M24        680 cr  45s  [QUEUE] [×5]        │
  └────────────────────────────────────────────────────────┘
```
- Section header: tier name + contributor count + head-job progress bar + depth
- Items: `Button` (height 40px, `HIT_TARGET_MIN`), text: `"{name}  {cost} cr  {time}s"`
- Tech gate: disabled + lock icon + tooltip "Requires: {building list}"
- Right side: `[QUEUE]` button (primary), `[×5]` button (shift-click queues 5)
- Empty tier: "NOTHING AVAILABLE" (centered, `HintLabel` style)

**Interaction**:
- Click `[QUEUE]` → `director.production.enqueue_unit/structure()`
- Click `[×5]` → queues 5× (or max affordable)
- Double-click item → queues 1×
- `Esc` → close drawer
- Click another tab → switches tier (accordion)

**Reuse**: Ports `_items_for()`, `_enqueue()`, `_re_evaluate_gates()` from `ProductionHUD` with minimal changes

---

### 2.5 IntelFeed (`intel_feed.gd`)

**Visual**: Folded paper panel, top-left, 320×200 default, collapses to 3-line summary  
**Material**: `folded_paper` + `teletype_print` shader for new entries  
**Content**: Scrolling log, newest at bottom, auto-scroll, timestamp + icon + message

| Category | Icon | Color | Example |
|----------|------|-------|---------|
| Contact | Radar | `SIGNAL_HAZARD` | "14:32:15  ENEMY CONTACT  SECTOR D4  T-72 ×3" |
| Structure Ready | Hammer | `SIGNAL_GO` | "14:33:02  REFINERY ONLINE  SECTOR B2  +28/s" |
| Low Power | Bolt | `SIGNAL_ALERT` | "14:33:45  LOW POWER  BUILD MORE REACTORS" |
| Research | Flask | `SIGNAL_INFO` | "14:34:10  RESEARCH COMPLETE  COMPOSITE ARMOR" |
| Player Order | Chevron | `TEXT_SECONDARY` | "14:35:00  GROUP 1  ATTACK-MOVE → SECTOR F6" |

**Behavior**:
- New entry → `teletype_print` animation (character-by-character, 0.02s/char)
- After 5s no hover → collapse to 3 most recent lines
- Hover → expand full, pause auto-collapse
- Click entry with sector → camera pan to sector center
- `I` key toggles collapse/expand

---

### 2.6 MinimapOverlay (`minimap_overlay.gd`)

**Refactor**: Extract from `battle_hud.gd` lines 205-266, 414-636  
**Changes**:
- Add `visible` property + `toggle()` method (bound to `M` key)
- Default `visible = true`
- Keep phosphor radar shader, view indicator, fog re-shade logic
- Remove `RightRail` anchoring dependency

---

### 2.7 CRTReadout (`crt_readout.gd`)

**Reusable widget** for all mono-font phosphor displays

```gdscript
class_name CRTReadout
extends PanelContainer

@export var tube_color: String = "amber"  # "amber" | "green"
@export var font_size: int = 14
@export var show_scanlines: bool = true
@export var show_vignette: bool = true

var _label: Label
var _shader: ShaderMaterial

func _init() -> void:
    theme_type_variation = "HUDPanel"
    mouse_filter = MOUSE_FILTER_IGNORE
    _build()

func _build() -> void:
    _label = Label.new()
    _label.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
    _label.add_theme_font_size_override("font_size", font_size)
    _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    add_child(_label)
    _apply_phosphor_shader()

func set_text(text: String) -> void:
    _label.text = text

func _apply_phosphor_shader() -> void:
    var pair = UITokens.phosphor_pair(tube_color)
    _shader = ShaderMaterial.new()
    _shader.shader = preload("res://shaders/phosphor_display.gdshader")
    _shader.set_shader_parameter("lit_color", pair["lit"])
    _shader.set_shader_parameter("unlit_color", pair["unlit"])
    _shader.set_shader_parameter("glass_color", pair["glass"])
    _shader.set_shader_parameter("scanline_pitch", UITokens.SCANLINE_PITCH)
    _shader.set_shader_parameter("persistence_decay", UITokens.PERSISTENCE_DECAY)
    _shader.set_shader_parameter("enable_scanlines", show_scanlines)
    _shader.set_shader_parameter("enable_vignette", show_vignette)
    material = _shader
    _bind_panel_size()
```

---

### 2.8 BakelitePanel / FoldedPaperPanel / AluminumTrim (`bakelite_panel.gd`, etc.)

**Pattern**: `RefCounted` helpers that apply material + elevation to a node

```gdscript
# bakelite_panel.gd
class_name BakelitePanel
extends RefCounted

static func apply(node: Control, overrides: Dictionary = {}) -> void:
    UITheme.apply_material(node, "bakelite", {
        "wear": 0.15, "grime": 0.25, "vignette": 0.35, "brightness": 0.75
    } + overrides)
    UITheme.apply_elevation(node.material as ShaderMaterial, "flush")  # desk surface
```

```gdscript
# folded_paper_panel.gd
class_name FoldedPaperPanel
extends RefCounted

static func apply(node: Control, overrides: Dictionary = {}) -> void:
    UITheme.apply_material(node, "canvas", {
        "wear": 0.06, "grime": 0.30, "scale": 0.7, "vignette": 0.12, "brightness": 0.85
    } + overrides)
    UITheme.apply_elevation(node.material as ShaderMaterial, "raised")
```

---

### 2.9 TeletypeLog (`teletype_log.gd`)

**Shared component** for IntelFeed + order confirmation lines in ContextDrawer

```gdscript
class_name TeletypeLog
extends ScrollContainer

var _vbox: VBoxContainer
var _print_timer: Timer
var _pending_chars: Array[String] = []
var _current_line: Label = null

func add_entry(timestamp: String, icon: String, message: String, color: Color) -> void:
    var line = Label.new()
    line.add_theme_font_override("font", preload("res://assets/fonts/MonoFont-Regular.ttf"))
    line.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
    line.add_theme_color_override("font_color", color)
    line.text = ""  # will be filled by teletype
    _vbox.add_child(line)
    _pending_chars.append("[{0}] {1} {2}".format(timestamp, icon, message).chars())
    _current_line = line
    _start_print()

func _start_print() -> void:
    if _print_timer == null:
        _print_timer = Timer.new()
        _print_timer.wait_time = 0.02
        _print_timer.one_shot = true
        _print_timer.timeout.connect(_print_next_char)
        add_child(_print_timer)
    _print_timer.start()

func _print_next_char() -> void:
    if _pending_chars.is_empty():
        _current_line = null
        return
    var chars := _pending_chars[0]
    if chars.size() > 0:
        _current_line.text += chars.pop_front()
        _print_timer.start()
    else:
        _pending_chars.pop_front()
        if not _pending_chars.is_empty():
            _start_print()
        else:
            _current_line = null
    _vbox.get_parent().get_parent().scroll_vertical = int.max  # auto-scroll
```

---

## 3. Theme Additions (`build_ui_theme.gd`)

Add to `KNOWN_VARIATIONS` and create StyleBoxFlat/StyleBoxTexture entries:

| Variation | Base | StyleBox | Font | Colors |
|-----------|------|----------|------|--------|
| `BakelitePanel` | PanelContainer | `bakelite` shader | — | — |
| `FoldedPaperPanel` | PanelContainer | `canvas` shader | — | — |
| `AluminumTab` | Button | `aluminum` shader | `FONT_HEADING` | `TEXT_PRIMARY` / `SIGNAL_HAZARD` (active) |
| `CRTReadout` | PanelContainer | `phosphor_display` shader | `MonoFont` 14pt | `PHOSPHOR_AMBER` / `PHOSPHOR_GREEN` |
| `DrawerTab` | Button | `canvas` shader | `FONT_HEADING` | `TEXT_SECONDARY` / `TEXT_PRIMARY` (hover) / `SIGNAL_HAZARD` (active) |
| `QueueItemButton` | Button | `canvas` shader | `FONT_BODY` | `TEXT_PRIMARY` / `TEXT_DISABLED` (gated) |
| `TeletypeLabel` | Label | — | `MonoFont` 13pt | Per-category |
| `QuickJumpPill` | Button | `canvas` shader | `FONT_SMALL` | `BASE_600` bg / `TEXT_PRIMARY` |

---

## 4. Shaders

### 4.1 `crt_warmup.gdshader` (Panel Expand Animation)

```glsl
shader_type canvas_item;
render_mode blend_mix;

uniform float progress : hint_range(0.0, 1.0) = 0.0;  // 0=collapsed, 1=expanded
uniform float scanline_pitch = 3.0;
uniform vec3 warm_color = vec3(1.0, 0.69, 0.0);  // amber
uniform float bloom_intensity = 0.3;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float scan = sin(UV.y * SCREEN_PIXEL_SIZE.y * scanline_pitch * 100.0) * 0.05;
    float vignette = 1.0 - length(UV - 0.5) * 0.5;
    float bloom = smoothstep(0.0, 1.0, progress) * bloom_intensity * (1.0 - UV.y);  // bottom-up
    COLOR = vec4(tex.rgb + warm_color * bloom + scan, tex.a * progress * vignette);
}
```

**Usage**: On `ContextDrawer` / `ProductionDrawer` panel. Animate `progress` 0→1 on open, 1→0 on close via `Tween`.

---

## 5. Integration Points & Migration

### 5.1 `battle_hud.gd` → Slim Down

**Keep**:
- `setup(director, local_team, current_map)`
- `fit_to_viewport()`
- `minimap_rect` + `_bake_minimap()` + `_refresh_minimap()` + `_composite_fog()`
- `_on_minimap_input()`
- `minimap_image()` (for tests)

**Remove** (delegate to `CommandConsole`):
- `_build_top_strip()` → `DeskInstrumentBar`
- `_build_right_rail()` + `_build_selection_panel()` + `_build_selection_dock()` + `_build_command_card()` → `ContextDrawer`
- `_refresh_resources()` → `DeskInstrumentBar`
- `_refresh_placard()` → `ContextDrawer` (STATUS tab)
- `selection_dock`, `right_rail`, `selection_panel`, `command_card`, `placard`, `edge_marker`

**New**:
```gdscript
@onready var command_console: CommandConsole = %CommandConsole

func setup(director, local_team, current_map) -> void:
    # ... existing minimap setup ...
    command_console.setup(director, local_team, current_map)
```

### 5.2 `match_director.gd` / `skirmish.gd` Wiring

```gdscript
# In match_director.gd _ready() or setup_battle():
var hud = battle_hud  # BattleHUD instance
hud.setup(self, PLAYER_TEAM, current_map)

# Signal connections (existing, keep):
production.queue_changed.connect(hud.command_console.on_queue_changed)
selection.selection_changed.connect(hud.command_console.on_selection_changed)
vision.shroud_version_changed.connect(hud.command_console.on_vision_changed)
structure_built.connect(hud.command_console.on_structure_built)
structure_lost.connect(hud.command_console.on_structure_lost)
```

### 5.3 `CommandConsole` Signal Interface

```gdscript
# command_console.gd
signal alert_clicked(category: String)

func setup(director: Node, local_team: int, current_map: Dictionary) -> void:
    _director = director
    _local_team = local_team
    desk_bar.setup(director, local_team)
    tab_bar.setup(director)
    context_drawer.setup(director)
    production_drawer.setup(director)
    intel_feed.setup(director)
    minimap.setup(current_map)
    # Wire signals
    director.economy.changed.connect(desk_bar._refresh_resources)
    director.production.queue_changed.connect(_on_queue_changed)
    director.selection.selection_changed.connect(context_drawer.update_selection)
    director.vision.shroud_version_changed.connect(minimap._composite_fog)
    # ... etc

func _on_queue_changed(team: int, queue: String) -> void:
    if team == _local_team:
        tab_bar.refresh_badge(queue)
        if production_drawer.visible and production_drawer.current_tier == queue:
            production_drawer.rebuild_tier(queue)

func on_selection_changed(units: Array) -> void:
    context_drawer.update_selection(units)
    if not units.is_empty():
        context_drawer.expand()
```

---

## 6. Input Bindings (Add to `project.godot` / InputMap)

| Action | Key | Handling |
|--------|-----|----------|
| `ui_toggle_minimap` | `M` | `minimap.toggle()` |
| `ui_toggle_intel` | `I` | `intel_feed.toggle_collapse()` |
| `ui_open_production` | `B` | `tab_bar.toggle_tab(last_hovered)` |
| `ui_context_tab_next` | `Tab` | `context_drawer.cycle_tab(1)` |
| `ui_context_tab_prev` | `Shift+Tab` | `context_drawer.cycle_tab(-1)` |
| `ui_context_pin` | `Space` | `context_drawer.toggle_pin()` |
| `ui_context_dismiss` | `Escape` | `context_drawer.collapse()` |
| `ui_select_all_type` | Double-click | `context_drawer.select_all_of_type()` (in drawer) |

---

## 7. Performance Considerations (Coordination with Performance Session)

### 7.1 Draw Call Budget
- **Current**: `ProductionHUD` creates ~50-80 buttons + CRT readouts + toolbox plates
- **Target**: `CommandConsole` ≤ 40 persistent nodes + drawer contents (lazy-instantiated)
- **Rules**:
  - Drawer contents instantiated on-demand, freed on collapse (`queue_free()`)
  - ProductionDrawer tier lists built once per tier, cached, filtered on refresh
  - CRTReadout shader reused — single `ShaderMaterial` instance shared across all readouts
  - Minimap: single `ImageTexture` + phosphor shader (unchanged)

### 7.2 Update Throttling
| Component | Cadence | Mechanism |
|-----------|---------|-----------|
| DeskInstrumentBar (resources/power) | 5 Hz (0.2s) | `_refresh_acc` accumulator (port from `ProductionHUD`) |
| ProductionTabBar badges | Event-driven | `queue_changed` signal |
| ContextDrawer | Event-driven | `selection_changed` signal |
| Minimap fog | Vision tick | `shroud_version_changed` signal (existing) |
| IntelFeed | Event-driven | `add_entry()` called by vision/service |

### 7.3 Memory
- TeletypeLog: cap at 200 entries (oldest removed)
- Thumbnail cache: `SelectionPanel._thumbnail_cache` reused (static, per-match)
- ProductionDrawer item buttons: cached in `_item_buttons` (port from `ProductionHUD`)

### 7.4 Visual Regression (P4 Alignment)
- `bake_module_visual()` merges module meshes at spawn → fewer `MeshInstance3D` per unit
- UI must not create per-unit 3D nodes — all 2D CanvasItems
- Test: `run_tests.gd` suites `test_ui_and_camera`, `test_sim_and_stats` must pass

---

## 8. Implementation Sequence (6-Week Sprint)

### Week 1: Foundation & Desk Instrument Bar
- [ ] Create `command_console.gd` (orchestrator, layout only)
- [ ] Create `desk_instrument_bar.gd` + `crt_readout.gd`
- [ ] Add `BakelitePanel`, `AluminumTrim` helpers
- [ ] Add `BakelitePanel`, `CRTReadout` theme variations
- [ ] Wire `battle_hud.gd` → delegate to `command_console`
- [ ] Verify: resources/power/clock/alerts display, 5 Hz update, no layout errors

### Week 2: Production Tab Bar + Minimap Extraction
- [ ] Create `production_tab_bar.gd` with 5 tabs + badges
- [ ] Extract `minimap_overlay.gd` from `battle_hud.gd`
- [ ] Add `M` key binding for minimap toggle
- [ ] Verify: tabs clickable, badges update on queue change, minimap works standalone

### Week 3: Context Drawer (Core Tabs)
- [ ] Create `context_drawer.gd` with slide animation + tab bar
- [ ] Implement STATUS tab (port from `SelectionPanel` + `SpecPlacard` + `CommandCard`)
- [ ] Implement WEAPONS tab (port weapon group data from `unit.gd`)
- [ ] Add `FoldedPaperPanel` helper + `crt_warmup` shader
- [ ] Verify: selection → drawer slides up, tabs switch, data accurate

### Week 4: Context Drawer (Remaining Tabs) + Input
- [ ] Implement TARGETING, MOVEMENT, SPECIAL tabs
- [ ] Add `TeletypeLog` component
- [ ] Wire input bindings (`Tab`, `Esc`, `Space`, double-click)
- [ ] Port `SelectionPanel` sub-group grammar (Ctrl/Shift clicks)
- [ ] Verify: all tabs functional, keyboard nav works, multi-select correct

### Week 5: Production Drawer + Intel Feed
- [ ] Create `production_drawer.gd` (accordion, port from `ProductionHUD`)
- [ ] Port `_items_for()`, `_enqueue()`, `_re_evaluate_gates()`, tech gates
- [ ] Create `intel_feed.gd` + `teletype_log.gd` (shared)
- [ ] Wire vision/service events → intel entries
- [ ] Verify: production flow works, intel log animates, no duplicate resource readouts

### Week 6: Polish, Accessibility, Tests
- [ ] Theme consistency pass (all panels use helpers, no inline StyleBox)
- [ ] Colorblind mode: CRT readouts use shape + text, not color-only
- [ ] UI scale slider (0.8x–1.5x) → multiplies `TOKEN` spacings + font sizes
- [ ] Focus order / gamepad nav: `ui_up/down/left/right` moves between tabs/buttons
- [ ] Run full test suite: `./run_tests.sh` → ALL PASS
- [ ] Visual regression: `prototype/visual_regression/` baseline diff clean
- [ ] Stress test: 30v30 skirmish, physics frame time ≤ baseline

---

## 9. Testing Checklist

### Unit Tests (Add to `test_ui_and_camera.gd`)
- [ ] `test_command_console_layout()` — all regions anchor correctly at 1280×720, 1920×1080, 3440×1440
- [ ] `test_desk_bar_updates()` — economy signals → CRT readouts update within 1 frame
- [ ] `test_production_tab_badges()` — queue depth badges match `production.status()`
- [ ] `test_context_drawer_selection()` — select units → drawer shows correct aggregate data
- [ ] `test_context_drawer_tabs()` — Tab/Shift+Tab cycles, Esc dismisses, Space pins
- [ ] `test_production_drawer_enqueue()` — click QUEUE → `production.enqueue_unit()` called
- [ ] `test_production_drawer_tech_gate()` — missing building → button disabled + tooltip
- [ ] `test_intel_feed_entries()` — vision contact → entry appears with correct category
- [ ] `test_minimap_toggle()` — `M` key hides/shows, view indicator persists
- [ ] `test_no_duplicate_resource_readouts()` — only DeskInstrumentBar shows credits/power

### Integration Tests
- [ ] Full skirmish: 20 min match, no UI errors in log, HUD responsive throughout
- [ ] Test Range: scratch design → Test in Arena → ContextDrawer shows design stats
- [ ] Multiplayer (if applicable): spectator HUD shows correct team data

---

## 10. Rollback Plan

If regression detected:
1. `git revert` last 3 commits (each week is 1-2 commits)
2. `battle_hud.gd` still contains minimap logic — can run standalone
3. `ProductionHUD`, `SelectionPanel`, `RightRail` preserved in git history
4. Feature flag: `global_config.gd` → `use_new_command_console = false` falls back to old HUD

---

## 11. Definition of Done

- [ ] All 4 legacy HUD files deleted (`right_rail.gd`, `selection_panel.gd`, `production_hud.gd`, old `battle_hud.gd` top-strip/right-rail code)
- [ ] `command_console.gd` + 6 component files pass all tests
- [ ] Battlefield vertical visibility = 100% (no persistent left/right/top chrome)
- [ ] Persistent chrome height ≤ 120px (desk bar 48 + tab bar 36 + drawer peek 0-36)
- [ ] Cold war visual language consistent (bakelite, aluminum, CRT, folded paper)
- [ ] No grease pencil animations — standard highlights only
- [ ] Performance: 30v30 skirmish physics frame time ≤ pre-replacement baseline
- [ ] Accessibility: colorblind safe, UI scale 0.8–1.5, gamepad navigable
- [ ] Documentation: `UI_STYLE_GUIDE.md` updated with new variations

---

## 12. Coordination Notes (Performance Session)

| Area | Performance Session Impact | UI Session Action |
|------|---------------------------|-------------------|
| `bake_module_visual()` | Fewer MeshInstance3D per unit | UI: no 3D nodes created; all CanvasItem |
| `auto_weapon` throttling | 5-10x unit count viable | UI: ContextDrawer weapon tab reads `unit.get_weapon_groups()` — must be O(1) cached |
| Spatial grid (`_damageable_grid`) | Reacquisition bounded | UI: Minimap fog uses same `vision.shroud_image()` — no new queries |
| Material pooling | Subsumed by mesh merge | UI: CRTReadout shares single ShaderMaterial instance |
| Visual regression baseline | Updated for P4 | UI: Must not change unit appearance; only HUD chrome |

**Sync point**: After Week 2 (minimap extracted), verify `minimap_overlay.gd` still passes `test_ui_and_camera::test_minimap_fog_and_blips` with P1c spatial grid active.

---

*Generated 2026-08-19 | Aligns with PERFORMANCE_PLAN.md P1-P4 complete | No grease pencil per user request*