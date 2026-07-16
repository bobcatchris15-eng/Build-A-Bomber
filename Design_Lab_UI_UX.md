# The Design Lab: UI/UX & Placement Mechanics

The Design Lab is an out-of-match experience (accessed between Operations or from the main menu), meaning players have zero time pressure. The interface heavily draws from *Spore* and *Kerbal Space Program*, ensuring it is intuitive, tactile, and highly visual.

## 🖥️ Screen Layout & Flow

1. **Center Stage (The 3D Canvas):** 
   - The majority of the screen is a 3D viewport where the unit sits. Players can freely rotate, pan, and zoom the camera around the construct. 
2. **Left Panel (The Parts Bin):**
   - A scrollable, categorized list of modules (Weapons, Support, Armor Materials). Selecting a category expands it to show the Base Archetypes. 
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
