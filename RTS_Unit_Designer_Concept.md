# RTS Unit & Structure Designer: Core Concept

## 🎯 The Vision
### 1. 4X Lite-Lite Pacing
A "4X Lite-Lite" RTS (evoking the pacing of *Command & Conquer* skirmishes, *Sins of a Solar Empire*, and *Ashes of the Singularity*) where your ability to prototype, adapt, and counter enemy designs is the primary driver of victory. The designer isn't just a menu; it's a creative and highly tactile sandbox.

### 2. The Vibe: Pulpy & Overdone
The overall tone of the game actively avoids taking itself too seriously. Instead of gritty, ultra-realistic hardline sci-fi or grimdark dieselpunk, the aesthetic is **Pulpy and Slightly Overdone**. 
- It’s a touch too colorful, a bit too gung-ho, and a shade too silly-looking. 
- Massive cannons recoil with cartoonish force, laser beams are bright and obnoxious, and exploding vehicles go up in spectacular, over-dramatized fireballs. The combat simulation math is deep, but the presentation is pure popcorn entertainment.

## 🛠️ The Player Experience (The "Spore" Approach)

### 1. The Hull & Locomotion (Foundation)
Inspired by *Spore's* vehicle creators, the blueprint canvas is a fully 3D environment designed for speed and creativity.
- **Hull Selection & Scaling:** Players begin by selecting a largely cosmetic hull shape from a specific Size Class (Light, Medium, Heavy, etc.). The player can scale this hull in at least two axes (length and width). The size class dictates the upper and lower bounds of this scaling. A larger hull offers more surface area for weapons, but increases the target profile and base weight.
- **Auto-Scaled Locomotion:** To keep mid-match adaptation fast, players don't manually place individual wheels. They simply select a **Locomotion Archetype**, and the designer automatically scales and places the parts beneath the hull based on its size and weight. Available archetypes include:
  - **Treads:** High weight capacity, slow speed, ignores mild terrain.
  - **Wheels:** Fast on open roads, poor weight capacity, bogs down in rough terrain.
  - **Legs:** Can traverse extreme verticality (cliffs), moderate weight capacity, high target profile.
  - **Hovercraft:** Skims over water and flat land rapidly, struggles with steep inclines.
  - **Anti-Grav:** True hovering, ignores terrain completely, but draws massive amounts of energy.
  - **Multirotor Array:** Flight-capable, bypasses ground obstacles, but highly vulnerable to flak and cannot capture ground nodes.

### 2. Tweakable & Scalable Parts
Parts aren't just static items; they are malleable.
- **Physical Manipulation:** Players snap weapons and utility modules onto their custom hull and can stretch, squash, and scale individual parts (e.g., pulling a gun barrel to make it longer).
- **Dynamic Stat Scaling:** Tweaking a part physically alters its in-game stats in real-time.
  - *Example:* Scaling up an artillery cannon increases its damage radius and range, but exponentially increases its resource cost, weight, and turret turn-speed.
  - *Example:* Shrinking an engine makes it cheaper and easier to fit on a small chassis, but significantly reduces top speed.

### 3. Structural Design (Defenses & Buildings)
The designer isn't limited to mobile units. **Defensive buildings are also custom-designed.**
- Players can design bespoke defensive structures by starting with a "Foundation" core instead of a vehicle hull.
- Create towering artillery batteries, sprawling wall segments with built-in repair nodes, or cheap, spammy laser pylons. 
- This ensures base-building has just as much strategic depth and expression as unit creation.

## 🔍 Designer Depth: Nested Design vs. Parametric Tweaking

How deep does the player go when creating a unit? There are two main philosophies to consider for the workflow:

### Option A: Nested Design (Design the Weapon -> Design the Unit)
In this approach, the player acts as a true defense contractor. They first design sub-assemblies (like a custom turret) from raw parts, save it to their armory, and then attach that custom turret to a chassis.
- **Pros:** Unmatched depth. You could design a specific "Shield-Breaker Flak Turret" and stick it on both your heavy tanks and your defensive walls.
- **Cons:** High cognitive load and slower pacing. Mid-match adaptation becomes a two-step process (update the weapon, then update the unit), which might conflict with the faster "4X Lite-Lite" pacing. 

### Option B: Parametric Tweaking (Place Base Weapon -> Tweak on Chassis)
This is closer to the true *Spore* experience. The player selects a "Base Kinetic Cannon" from the menu, snaps it onto the chassis, and then uses sliders/gizmos to stretch the barrel, widen the ammo drum, or flatten the armor casing directly on the unit.
- **Pros:** Fast, punchy, and highly visual. You get the depth of custom stats without leaving the unit canvas. It keeps mid-match adaptation snappy.
- **Cons:** Slightly less granular than building a gun from scratch, as the base functionality (e.g., "this is a kinetic weapon") is locked to the base part.

*Conclusion:* Option B (Parametric Tweaking) perfectly serves the RTS format for out-of-combat/in-base adjustments, offering massive depth through physical scaling and a WIDE pool of base archetypes.

## 🔬 Factions & The World

### 1. Faction Asymmetry
The overarching theme is loose, allowing maps to be diverse, arbitrary patches of terrain. Factions are made distinct through their specific component pools and visual "vibes."
- **Faction A:** Might rely on sleek, high-tech hovering components and energy weapons.
- **Faction B:** Might use gritty, industrial treads, thick armor plates, and kinetic cannons.
- **Faction C:** Could utilize bio-engineered organic parts, bone-plating, and acid spitters.

## 🧠 Gameplay Integration & Match Flow

### 1. Meta-Structure: Operations & The Blueprint Deck
To enforce the importance of the designer without bogging down live gameplay, the game is structured around multi-stage **Operations** rather than single one-off skirmishes.
- **The Operation:** A single "match" is an Operation consisting of three separate skirmishes played across different maps. 
- **Skirmish Pacing:** Each individual skirmish lasts roughly 15-20 minutes. 
  - *Minutes 0-5:* Establishing basic economy and producing mainline units.
  - *Minutes 9-11:* Economy peaks, allowing production of end-game or super-heavy units (if brought in the loadout).
- **The Loadout (Deck Building):** Players cannot build every design they own during a skirmish. They must select a limited "Loadout" of roughly 12 to 15 designs to bring into the match. This limit includes non-combat units (harvesters, builders, repair drones). 
  - *Exploiting Utility:* While most players might use a generic cheap harvester to save a slot, advanced players might design heavily armored harvesters or stealth builders to exploit this loadout limit and gain a unique economic edge.
- **Between Skirmishes (Reinforcements):** Between the 3 skirmishes of an Operation, players have a "Reinforcement Phase." Here, they can swap designs out of their active 12-15 unit Loadout and bring in different blueprints from their master library to adapt to the enemy's strategy.
- **Between Operations (The Design Lab):** The actual Unit Designer (where you tweak and build new blueprints from scratch) is accessed exclusively **between Operations**. 
  - *The Intelligence Loop:* Scanning enemy wreckage during Skirmish 1 gives you vital intel. You might realize you don't have a good counter in your active loadout. You swap in the closest counter you have from your library for Skirmish 2. Then, once the Operation is completely over, you return to the Design Lab to perfectly engineer a direct counter to that enemy's favorite dreadnought.

### 2. Progression & Unlocks
- **Starting Arsenal:** Players start matches with a massive portion of the arsenal already unlocked. The limitation isn't arbitrary tech gating; it's cost, weight, and resource management. 
- **Exotics:** Exotic or highly specialized parts could be unlocked via specific Operation objectives or out-of-game achievements.

### 3. Economy & Resource Management (The Framework)
The economy serves as the structural sandbox for the designer.
- **Streamlined System:** 2-3 resources maximum.
- **Varied Generation:** Resources can be gathered through securing map nodes, building trade/tax networks, or salvaging wreckage.
- **Cheap Units:** Overall, units are relatively cheap to produce (similar to *Ashes of the Singularity*, though with slightly less intense swarms). This encourages continuous prototyping and combat rather than hoarding.
- **Component Cost Ties:** Scaling parts directly impacts their cost. A massive chassis covered in thick armor drains basic materials, while oversized plasma lances bottleneck advanced tech resources.
