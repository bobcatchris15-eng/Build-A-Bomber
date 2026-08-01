# The Design Lab: UI/UX & Placement Mechanics

The Design Lab is an out-of-match experience (accessed between Operations or from the main menu), meaning players have zero time pressure. The interface heavily draws from *Spore* and *Kerbal Space Program*, ensuring it is intuitive, tactile, and highly visual.

## 🖥️ Screen Layout & Flow

1. **Center Stage (The 3D Canvas):** 
   - The majority of the screen is a 3D viewport where the unit sits. Players can freely rotate, pan, and zoom the camera around the construct. 
2. **Left Panel (The Parts Bin):**
   - A scrollable, categorized list of modules. Selecting a category expands it to show the Base Archetypes (accordion: one drawer open at a time per tab).
   - **Grouping is by ROLE, not by mechanical category.** `category` (weapon/armor/generator/structural/module) is what the placer and stat calculator run on; it is far too coarse to browse by, since 25 of the catalog's entries are `category: "weapon"` and landed in one undifferentiated wall of buttons. Modules group on `role` (Direct-Fire Guns / Energy & Electromagnetic / Indirect Fire / Missiles / Point Defense / Deployables / Armor / Power / Support / Structural), hulls on `is_foundation` plus weight class, locomotion on its own `traits` array.
   - Every group's contents are sorted **light to heavy**. Weight is the sort key because it is the one stat every part in the catalog has and it is the number the player is budgeting against; each row shows its weight inline, right-aligned, so the ordering is legible without hovering every entry one at a time.
   - Group keys are always derived from data the catalog already owns, never from a table of type_ids in the UI script - the same rule HULL_MODDING_PLAN.md §4c sets for hulls. See `ModuleCatalog.MODULE_ROLES`. A part that declares no role still lands in a visible drawer via a category fallback rather than vanishing.
   - **Search bar at the top of the bin.** Grouping helps *browsing*; only search helps *retrieval*, and they are different tasks. This is the single most consistent complaint about parts palettes in this genre - KSP2's VAB, Trailmakers, Besiege all attract "the categories are fine but finding a specific part takes forever," and in each case the community answer was an external parts-list tool or a filter mod. Typing filters across all three tabs at once, force-opens the surviving drawers (making you click a header to see the thing you just searched for would defeat the point), hides empty groups, and fully restores the accordion on clear.
   - Collapsed drawer headers carry a **count badge**, so a closed accordion doesn't make "which drawer do I look in" a coin flip.
   - The bin states **"Drag a part onto the hull to place it"** in-panel. Discoverability is the other recurring failure mode in this genre: these are drag sources that look exactly like ordinary buttons, and controls documented only in an external guide are controls most players never find.
3. **Right Panel (The Stat Block):**
   - The overarching stats of the entire construct. As parts are added or tweaked, these numbers flash and update dynamically.
   - *Key Stats:* Total HP, Resource Cost, Top Speed, Overall DPS, Damage Thresholds (Kinetic/Thermal/Energy), and Weight.
4. **Top Bar (Admin Tools):**
   - Blueprint Name input field, Save/Load buttons, Undo/Redo, and the **Symmetry Toggle**.
   - *Symmetry Toggle:* An absolute necessity. Players can turn on bilateral symmetry so placing a missile pod on the starboard side automatically places an identical, mirrored pod on the port side. This can be toggled off for asymmetrical designs.

## 🛠️ The Tweaking Interface (Grab Handles)
When the player clicks on a module that has already been placed on the hull:
- **The Spec Popup:** A small contextual window appears near the module showing its specific, isolated stats (e.g., just the DPS and turn-rate of that one Gatling Gun).
- **Grab Handles:** 3D manipulation gizmos (arrows and rings) appear directly on the part. Clicking and dragging an arrow (e.g., on the barrel) physically stretches the mesh in real-time, while the Spec Popup dynamically updates to show the changing range and weight penalties.

---

## 📐 Solving the Freeform Placement Problem (Firing Arcs)

*Spore* allows you to stick a leg inside an eyeball and the game doesn't care. In an RTS, physical placement dictates functionality. If you place a Gatling Gun directly behind a massive smokestack, it physically shouldn't be able to shoot forward. 

To give players maximum freedom *without* them accidentally designing broken, useless units, the game relies on fully **freeform placement** (raycast against the hull surface, position and orientation unconstrained) paired with **Arc Visualization** and **Collision/Clipping Checks** to make the consequences of a bad placement immediately visible, rather than restricting placement itself:

### 1. Freeform Placement (No Snap-Grid)
Placement is fully continuous - a module can sit anywhere a raycast hits the hull surface, at any position and rotation, not locked to a grid of discrete points. This is deliberate: where exactly a weapon sits is itself a differentiation axis (it changes the module's firing arc and exposure), and a snap-grid would flatten that into a handful of interchangeable slots, working against the game's own Spore-style continuous-tweaking philosophy (see DESIGN_VISION.md). An earlier draft of this doc described a hex/square surface grid; that direction was superseded before it was built - freeform is the final, permanent placement model.
- Placement itself never blocks an overlap - you CAN drop a weapon on top of another weapon or the hull's own volume. What actually prevents "broken" designs from shipping is downstream: any overlapping parts are highlighted solid red in real time (see Collision/Clipping Checks, below), and Save/Test in Arena are both blocked outright while any clipping exists, forcing you to resolve it before the design leaves the Lab - not a placement-time restriction, not a grid.

### 2. Dynamic Firing Arc Visualization (The "Radar Sweep")
To ensure players understand their firing arcs without reading spreadsheets, the UI relies on immediate visual feedback.
- When you select a placed weapon, a **translucent cone of light** emanates from the barrel, representing its maximum traverse (turning) limit and elevation.
- **Line-of-Sight Blockers:** If the weapon's cone intersects with the hull, a tall sensor mast, or another weapon, that section of the cone turns **Red**, visually indicating a blind spot. 
- *The Result:* If a player builds a heavy tank and places a low-profile laser behind a massive armor plate, they will instantly see a red cone blocking the front. They instinctively know they need to either move the laser, scale the laser's elevation mount higher (so it shoots over the armor), or shrink the armor plate.

### 3. Collision / Clipping Checks
If a player uses a grab handle to stretch a gun barrel so long that it clips through another module on their own construct, the weapon turns Red and the blueprint cannot be saved until the clipping is resolved.

The red highlight is applied by **swapping** each mesh's `material_override` to one shared red material and restoring the part's own on clear - never by writing colour onto the material in place. Two reasons, both load-bearing: part materials are shared per role+tint (see below), so mutating one would repaint every other part in the scene using that role; and the old "restore" branch flattened every mesh in a module to its catalog colour on every pass, which runs on every placement, drag, rotation and tweak - so per-part colours never actually survived long enough to be seen.

---

## 🧱 Structural Pieces: Parametric Body + Fixed-Size Hardware

The six structural pieces (block, dome, slab, wedge, girder, I-beam) are the **only** modules the player can scale freely on all three axes at once, and they are meant to be stretched hard. That rules out the approach every other part family uses, where the whole part is one authored `.glb` that gets scaled - a bolt head scaled 4x along one axis is a smear.

- The **body** stays procedural: a box, wedge, hemisphere or truss that re-tessellates at its new size.
- The **detail** is authored hardware (`tools/blender/build_structural.py`) - corner brackets, bolt pads, stiffener ribs, gussets, splice collars, end caps, a dome hatch, vision blocks, tie-downs, step cleats - instanced at its **true authored size with no scaling**. Stretch a girder and you get *more* splice collars, not longer ones. Uniform scaling is the one allowance, for the handful of crew-scale references (the dome hatch) where a fastener-sized object reads wrong.
- **Scale isolation:** the resize is carried as a `struct_scale` meta and the body is rebuilt at the new size, exactly as the hull does - `node.scale` stays at ONE. This is what makes them behave like hull-builder primitives. Both the layer-2 click target and the layer-16 mounting surface are driven by hand to match, and the value persists through blueprint save/load via the same on-disk `scale` field.
- Hardware is **exempt from the faction hull-shader repaint** (it's named with `VisualBuilder.HARDWARE_PREFIX`), so faction-liveried plate reads as painted structure with bare steel fasteners rather than one flat shader.

---

## 🎨 Part Materials: Roles, Not Just Paint

Every bolt-on module part used to reach the screen through a `StandardMaterial3D` with exactly one property set - `albedo_color`. Everything else stayed at Godot's defaults, which are metallic 0.0 / roughness 1.0: the PBR description of matte plastic. A gun barrel, an ammo drum, a lens and a rubber tyre had identical surface response and differed only in how dark their paint was. The geometry was detailed; the surfaces were vinyl.

`scripts/part_materials.gd` replaces that with material **roles** - `steel`, `painted`, `gunmetal`, `scorched`, `brass`, `optics`, `rubber`, `ceramic`, `energized` - each with its own metallic/roughness/base colour, plus a `tint` weight controlling how much of the caller's colour survives. A painted housing takes the faction colour in full; a barrel stays gunmetal on a red gun and on a green gun alike.

- Roles are resolved from the authored **filename** (`ROLE_HINTS`), which is how ~190 existing parts pick one up without editing their call sites: the parts are already named after what they are. Anything unmatched degrades to the default role, which is still a properly finished metal.
- **Texture is procedural and triplanar.** The authored parts are built in bmesh from primitives and have no meaningful UV layout; triplanar projection needs none. Two runtime-generated `FastNoiseLite` frequencies do different jobs - a fine one on roughness so a flat face stops reading as a decal, a coarse one on the detail-albedo layer so paint reads as sprayed onto metal.
- **Materials are shared** per role+tint and must never be mutated in place (same rule as `munition_pool.gd`). `bake_module_visual()` merges a battle module's meshes grouped by material *identity*, so a fresh-but-identical material per part would silently defeat the merge and ship one draw call per bolt.
