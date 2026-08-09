# Damage Model & Armoring System

## 🛡️ The Armoring Problem (Avoiding the Tedium)
Placing individual armor plates manually is tedious, often results in visually messy designs, and slows down the player. To solve this, base armoring is handled at the **Hull level** rather than as individual placeable modules.

### The Solution: Hull Materials & Thickness Sliders
When a player selects their Hull block, they are presented with an "Armor Material" dropdown and a "Thickness" parametric slider.
- **Armor Material:** Defines the *type* of protection (e.g., Reactive, Ablative, Hardened Steel, Energy Shielding). This visually changes the texture and style of the hull without requiring manual placement.
- **Thickness Slider:** A parametric slider that scales the sheer volume of the chosen armor. Increasing thickness visibly bulks out the hull model, increasing its **Damage Thresholds** and base HP, while drastically adding to weight and resource cost. 

*(Note: Defensive modules, like Point-Defense lasers or Shield Emitters, are still placed as physical modules. But base protection is handled via the Hull).*

---

## ⚔️ The Damage Model: Thresholds & Multipliers
Combat relies on a granular, simulation-style mathematical model. Armor provides damage mitigation based on **Damage Classes** and **Damage Thresholds**. 

### 1. Damage Classes
Weapons deal specific classes of damage:
- **Kinetic:** Relies on mass and velocity (e.g., Railguns, Autocannons).
- **Thermal / Energy:** Relies on heat transfer (e.g., Lasers, Plasma).
- **Explosive:** Relies on blast wave and shrapnel (e.g., Howitzers, Missiles).

### 2. Negative Multipliers & Thresholds
Armor types apply a **negative multiplier** (damage reduction) to specific damage classes, and possess a **Damage Threshold**.
- **The Threshold Rule:** If an incoming attack's damage-per-hit is *below* the armor's threshold for that class, the attack is negated (deals 0 damage to the main hull). 
- **The Brute Force Rule:** If the incoming damage is overwhelmingly high, it punches straight through the mitigation multipliers (e.g. a massive 16" shell detonating near a shield still transfers kinetic shockwave damage to the hull).

---

## ⚖️ Countering the "Heavy Meta" (Why Small Still Matters)
The threshold mechanic inherently favors heavier weapons with massive damage-per-hit. To prevent the game from devolving into *only* building super-heavy dreadnoughts, the simulation incorporates mechanics that ensure variety. If a Zerg Rush of light drones encounters a Super-Heavy Tank they cannot penetrate, they win through the following mechanics:

### 1. Action Economy & Overkill
A massive 16-inch cannon might do 10,000 damage, but a light drone only has 100 HP. Firing that cannon at a single drone wastes 9,900 damage and triggers a 15-second reload. A swarm of cheap drones will overrun a slow-firing super-heavy because the heavy simply cannot kill them fast enough.
* **The Counter:** The heavy player should have designed CIWS (Close-In Weapon System) drones or Flame-Tanks to escort their super-heavy.

### 2. Evasion & Traverse Speeds (The "Death Spiral")
Scaling a weapon up makes it incredibly heavy. A massive railgun on a heavy turret turns extremely slowly. Fast hover-drones with light lasers can simply drive circles around the heavy unit; the turret physically cannot rotate fast enough to acquire a lock. The drones can then attack the weaker rear armor (directional thresholds) or ignore the tank entirely to destroy the enemy's resource harvesters.

### 3. Sub-System Targeting (Stripping)
Even if a swarm's light autocannons cannot penetrate the heavy tank's main hull threshold, they *can* destroy exposed modules. A swarm can target the heavy unit's radar dishes, exposed cooling fins, or treads. Stripping a heavy unit of its mobility and sensors renders it a useless pillbox, allowing the swarm to leave it stranded.

### 4. Economy & Map Control
A super-heavy unit costs 10x the resources and takes 10x longer to build. A player doing a Zerg Rush can field dozens of units and capture the entire map's resource nodes before the super-heavy even leaves the factory. 

### Summary of Strategic Counters
- **Zerg Swarm (Fast/Fragile)** > defeats > **Super-Heavy Specialists (Slow/Overkill)**
- **Super-Heavy Artillery** > defeats > **Turtling Bases (Static Defenses)**
- **Turtling Bases (CIWS/Flak/AOE)** > defeats > **Zerg Swarm (Low HP)**
- **Balanced Force** > defeats > **Specialists caught out of position**
