# Arsenal: Base Weapons & Support Modules

Since we are utilizing the "Spore" parametric approach, each item acts as a base archetype. To ensure deep strategic variety, the arsenal pool is incredibly **WIDE**. While each weapon may only have 3-4 sliding-scale adjustments, the sheer number of base weapon types allows for endless combat combinations.

*(Note: All units are autonomous drones/constructs. There are no infantry or dedicated melee weapons, mimicking modern vehicle combat.)*

---

## 💥 Kinetic & Ballistic (Direct Fire)
Physical projectiles relying on velocity and mass. Excellent against raw armor.

### 1. Main Cannon (Tank / Naval Gun)
- **Role:** High-damage, armor-piercing direct fire. Covers 120mm tank guns up to 16-inch battleship cannons.
- **Tweakable Features:**
  - **Caliber / Barrel Width:** Increases damage and penetration, but dramatically increases recoil and reload time.
  - **Barrel Length:** Increases projectile velocity and accuracy, but slows down turret traverse.

### 2. Heavy Machine Gun / Chaingun (e.g., Bushmaster, Oerlikon)
- **Role:** High rate of fire, shredding light armor and suppressing swarms. 
- **Tweakable Features:**
  - **Multi-Barrel (Action Addition):** Adding a second barrel doubles ROF and damage, but doubles weight and ammo footprint.
  - **Ammo Drum Size:** Increases sustained burst duration before reloading.

### 2b. Autocannon (modelled on the M230 chain gun, AH-64 chin turret)
- **Role:** The mid-tier between the machine gun and the main cannon. Rapid enough to matter against light armor, with real per-shot weight behind it.
- **Silhouette:** The barrel *is* the silhouette — very long, very slim, projecting a long way clear of everything else, so the gun reads as reach rather than volume of fire. A **ribbed muzzle sleeve and flared bell** at the tip, unmistakable at a distance and nothing like the plain crowned pipe a machine gun carries. **Exposed helical recoil springs** you can see daylight through, **welded tubular framing** triangulated into an A-frame, and hydraulic hoses and cable runs draped throughout. The chain drive housing bulges off the left flank (flat oval cover, sprocket bosses proud of it) — the asymmetry that makes it an M230 specifically — but it no longer dominates, because the structure and the barrel do.
- **Tweakable Features:**
  - **Caliber / Barrel Length:** The usual damage-vs-handling trade.
  - **Ammo Drum Size:** Sustained burst duration. Scales the magazine only — never the receiver it feeds.

### 2ba. Anti-Materiel Rifle (Bushmaster III derived)
- **Role:** The roster's only **precision** weapon — everything else is DPS or splash. One very large round every 4.5 seconds: **351 per shot, the largest direct-fire number in the game**, which matters because per-shot damage (`dps × fire_rate`) is exactly what `damage_resolver`'s armor thresholds gate on. It punches straight through every armor threshold in the table, and is comprehensively wasted on a scout it can only hit once every four and a half seconds. An ambush and overwatch piece: slow-traversing, expensive in crystal, and defenceless once something closes.
- **Silhouette:** A long greebled breech running back **through** the trunnions rather than hanging off them, so the gun reads as balanced about its middle, with an oversized recoil buffer tube and twin hydraulic rams projecting well past the rear — something has to absorb a shot this size, and it should look like it barely can. Very long slim tube with a multi-baffle muzzle brake. Where another weapon would carry ammunition it carries an unmanned sensor head: a rotating **LIDAR drum**, a **camera** with its lens standing proud under a sunshade, and heat-sink fins. Deliberately not a scope — see VISUAL_ART_DIRECTION.md on why optics are the easiest place to accidentally imply a gunner.
- **Ammunition:** `AP` first and by default — this is the round the weapon is *for*. No flechette and no smoke: a precision rifle firing a cloud of darts or a screening round is fighting its own premise.
- **Tweakable Features:**
  - **Calibre / Barrel Length:** Damage and reach, at the usual handling cost. Barrel Length moves the muzzle brake rather than stretching it.
  - **Optic Power:** Buys **reach and nothing else** — explicitly *not* damage, or it would stop being a trade and become a strictly-better slider. Paid for in crystal (×1.6 per point) rather than in metal or mass: a better sight is not more steel. This makes the rifle the most crystal-hungry non-energy weapon in the roster.
  - **Deploy Bipod:** The roster's only tweak that buys a stat with a **capability** instead of with weight or cost. Deployed, the rifle reaches 45% further; deployed, it **cannot fire while its vehicle is moving**. That turns the slider into a real question about how you intend to use the vehicle — a dug-in overwatch platform, or something that shoots on the advance — rather than a number you drag to the right. The bipod is visible on the model when down, so a deployed rifle is readable at a glance.

### 2c. Recoilless Rifle
- **Role:** Enormous per-shot HEAT damage from a light, cheap mount, paid for with a brutal reload — and a **backblast danger zone behind the weapon** that damages *anything* in it, friend, foe, or the firing vehicle itself. The first weapon where *where you mount it* has a mechanical consequence, not just an arc consequence.
- **Tweakable Features:**
  - **Bore Caliber:** Warhead size.
  - **Tube Length:** Range and accuracy. (Does not move the venturi — the backblast always vents from the breech.)

### 2d. Ballista
- **Role:** A torsion-spring bolt thrower, bolted to a machine that also mounts railguns. Enormous per-shot kinetic damage — enough to clear armor thresholds outright rather than chip at them — at almost no crystal cost, paid for with the slowest cycle in the roster. The cheap answer to heavy armor for a design that can't afford a railgun.
- **Tweakable Features:**
  - **Bolt Thickness:** Per-shot damage.
  - **Draw Length:** Range, at the cost of an even slower cycle.

### 3. Rotary Cannon (Gatling Gun)
- **Role:** Extreme ROF. Covers everything from tri-barreled .50 cals up to massive 30mm GAU-8 Avengers.
- **Tweakable Features:**
  - **Barrel Count:** Adding more barrels increases maximum ROF and cooling, but increases the spin-up time before firing starts.
  - **Motor Size:** A larger electric motor decreases spin-up time, but draws significantly more power from the chassis.

### 3b. Coil Gun
- **Role:** The sane sibling to the railgun — genuinely turreted rather than frame-built, less per-shot punch, roughly twice the cycle rate, far cheaper on crystal. Lets a mid-tier design reach hitscan kinetic without committing a whole hull to a fixed rail.
- **Tweakable Features:**
  - **Accelerator Stage Count:** More coils means more muzzle velocity and range — and visibly more coils on a longer rail.
  - **Slug Caliber:** Per-shot damage.

### 4. Gauss / Railgun
- **Role:** Extreme velocity, line-piercing, anti-heavy armor.
- **Tweakable Features:**
  - **Rail Length:** Increases penetration (damaging modules *behind* the armor), but exponentially increases energy draw.

---

## ☄️ Indirect Fire & Demolition
Arcing fire used to bombard static positions or hit units behind cover.

### 5. Heavy Howitzer
- **Role:** Long-range, heavy splash damage.
- **Tweakable Features:**
  - **Elevation Mount:** Increases maximum firing arc to shoot over taller obstacles, but creates a massive blind spot at close range.

### 6. Mortar Array
- **Role:** Medium-range, high-arcing, rapid-burst indirect fire.
- **Tweakable Features:**
  - **Tube Array Size:** Adding more tubes allows for a massive "alpha strike," but drastically increases reload time.

### 6b. MK19 Grenade Launcher
- **Role:** Belt-fed rapid-fire grenades. Fills the gap between the mortar (slow, heavy, high arc) and the machine gun (fast, flat, no splash) — a small blast per round, but a great many rounds, on a low direct-lay arc.
- **Tweakable Features:**
  - **Grenade Caliber / Barrel Length:** Blast size and reach.
  - **Belt Box Size:** Sustained fire before reloading.

### 6c. Napalm Mortar
- **Role:** Area denial by fire rather than fragments. Modest impact damage, but leaves a large, long-lived burning pool that makes ground genuinely expensive to stand on.
- **Tweakable Features:**
  - **Canister Caliber:** Pool size and burn damage.
  - **Mortar Tube Length:** Range.

### 7. Spigot Mortar
- **Role:** Fires an oversized, disproportionately massive explosive from a very small launcher (e.g., Petard mortar). Very short range, devastating anti-structure damage.
- **Tweakable Features:**
  - **Spigot Rod Thickness:** Allows for a heavier, more damaging warhead, but reduces the already short firing range due to the extreme weight.

---

## 🚀 Missiles, Rockets, & Drones
Self-propelled tracking munitions and deployables.

### 8. Guided Missile Launcher (TOW / Hellfire)
- **Role:** Direct-fire or lock-on tracking munitions. Highly accurate anti-armor.
- **Tweakable Features:**
  - **Seeker Head Size:** Increases lock-on speed and tracking angle, but raises the resource cost of each missile.
  - **Engine Length:** Increases top speed to evade point-defenses, but widens the turning radius (less nimble).

### 9. Dual-Stage Platform (Top-Attack / Javelin style)
- **Role:** Missiles that launch upward and arc down to strike the weakly armored top of enemy constructs.
- **Tweakable Features:**
  - **Ascent Thruster:** Increases the launch height to clear massive obstacles, but severely increases the minimum arming distance.
  - **Payload Size:** Increases top-armor penetration at the cost of overall missile speed.

### 10. Swarm Missile Pod
- **Role:** Fires erratic, fast-moving mini-missiles designed to overwhelm point-defenses.
- **Tweakable Features:**
  - **Pod Grid Size:** Increases missiles per volley, scaling up resource cost and reload time.

### 11. Drone Carrier Bay
- **Role:** Launches autonomous mini-drones (interceptors or bombers).
- **Tweakable Features:**
  - **Hangar Size:** Increases active drone count but takes up massive chassis real estate.
  - **Launch Catapult:** Decreases launch time for a full wing.

---

## ☢️ Area-of-Effect & Area Denial
Weapons designed to control space and punish clustering.

### 12. Cluster Munitions Dispenser
- **Role:** Blankets a wide area in submunitions. Devastating against swarms or lightly armored resource lines.
- **Tweakable Features:**
  - **Dispersion Matrix:** Widening the matrix increases the blast footprint, but lowers the density/damage of submunitions in that area.

### 13. Area-Denial Emitter (Flamethrower / Microwave)
- **Role:** Projects a cone of continuous hazard (fire, heat, radiation).
- **Tweakable Features:**
  - **Nozzle / Emitter Width:** Widens the damage cone, but reduces the maximum projection range.
  - **Pressure Valve:** Increases damage tick-rate, but burns through fuel/energy reserves exponentially faster.

---

## ⚡ Energy & Directed Weapons
Bypasses physical armor, but highly susceptible to energy shielding.

### 14. Continuous Beam Laser
- **Role:** Instant-hit, perfect accuracy, sustained single-target melting.
- **Tweakable Features:**
  - **Lens Aperture:** Widening the lens increases raw damage output, but reduces maximum focused range.

### 15. Plasma Lobber
- **Role:** Slow projectiles dealing massive localized damage and lingering burn.
- **Tweakable Features:**
  - **Containment Chamber:** Increases splash radius, but lowers projectile speed.

---

### 13a. Mine Layer
- **Role:** The only weapon in the arsenal that **holds ground**. Everything else must keep firing to keep denying space; mines persist without the layer, survive its destruction, and punish a chokepoint indefinitely. They arm shortly after landing, blink visibly once armed (spotting and avoiding them is the counterplay), and ignore aircraft entirely — giving air a real reason to exist against a mined approach.
- **Tweakable Features:**
  - **Mines Per Volley:** More mines laid per cycle, visibly loaded on the rack.
  - **Mine Charge Size:** Blast damage per mine.

### 13b. Smoke Discharger
- **Role:** Dedicated obscurant launcher. Deals no damage whatsoever — it lays a persistent cloud that blocks weapon line-of-sight, blocks fog-of-war scouting, and breaks guided-missile lock. The complement to smoke *ammunition* (below): a gun loaded with smoke gives up its turn to shoot, while a discharger frees your real weapons to keep firing.
- **Tweakable Features:**
  - **Discharger Tube Count:** More tubes lay a wider screen per volley, at the cost of a longer reload.

---

## 🎯 Ammunition Types (Cross-Cutting)
Any weapon that fires a discrete **shell or payload** can be loaded with a specialist round, chosen per-module in the Design Lab and locked in for the match. Continuous-fire weapons (beams, flamethrowers, tesla/arc/ion discharges, plasma bolts) have nothing to swap and get no selection.

This is the arsenal's main **counter-pick** layer. Each round resolves against a different row of the armor threshold table, so the same cannon answers different enemies depending on what it's fed.

| Round | Damage Class | Profile | Beats | Loses To |
|---|---|---|---|---|
| **Standard** | *native* | Balanced, no specialisation | — | — |
| **Armor-Piercing** | Kinetic | +25% damage, **no splash**, ×0.4 vs light | All armor, esp. Ablative | Drones, aircraft, swarms |
| **High-Explosive** | Explosive | −15% damage, +60% blast | Hardened Steel, light targets | Reactive Armor |
| **Incendiary** | Thermal | −30% damage, leaves a burning pool | Hardened Steel | Ablative Ceramic |
| **Flechette Canister** | Kinetic | −45% damage, wide spread, ×3.5 vs light | Drones, swarms, aircraft | Anything armored |
| **EMP Shell** | Energy | −50% damage, drains target capacitor | Steel, Reactive | Energy Shielding |
| **Smoke** | — | **No damage.** Blocks sightlines and missile lock | Positioning | Anything, offensively |
| **Illumination** | — | **No damage.** Burns off fog of war where it lands | Scouting | Anything, offensively |

Resolved per-shot damage from a standard Main Cannon (72 base), against each armor material and against a light target:

| | Steel | Reactive | Ablative | Shielding | **Light** |
|---|---|---|---|---|---|
| Standard | 53.6 | 66.2 | 70.2 | 64.8 | 72.0 |
| **AP** | **73.1** | **85.5** | **87.8** | **84.4** | 36.0 |
| **HE** | 53.8 | *24.5* | 50.1 | 30.6 | 79.6 |
| **Incendiary** | 49.1 | 42.3 | *15.1* | 25.2 | 60.5 |
| **EMP** | 31.1 | 31.1 | 21.6 | *10.8* | 36.0 |
| **Flechette** | *27.7* | 31.7 | 36.3 | 29.7 | **138.6** |

Every round has both a clear best target and a clear worst — Standard is the only one that is never either, which is what makes it the honest default rather than a wasted slot. AP is deliberately the anti-armor answer, but pays for it by over-penetrating thin-skinned targets, making it the exact mirror of Flechette.

Ammunition carries real stowage **weight** and per-round **cost** — EMP shells are the crystal sink of the set, obscurants the cheapest. Loading a specialist round is a genuine commitment, not a free re-tune.

---

## 🛡️ Point Defense (Anti-Munition)
Dedicated systems for shooting down incoming missiles and artillery.

### 16. CIWS (Close-In Weapon System)
- **Role:** Extreme ROF ballistic tracking to physically shred incoming missiles.
- **Tweakable Features:**
  - **Tracking Radar Dish:** Increases engagement range but draws significantly more power.

### 17. Point-Defense Laser
- **Role:** Instantaneous beam that pops incoming artillery shells or slow torpedoes.
- **Tweakable Features:**
  - **Cooling Jacket:** Enlarges cooling fins to allow continuous firing without overheating.

### 18. Flak Cannon
- **Role:** Fires shells that detonate at a set range, creating a wall of shrapnel.
- **Tweakable Features:**
  - **Proximity Fuse Setter:** Alters blast radius versus shell velocity.

---

## 🔧 Support & Utility Modules (Non-Combat)
Essential systems for economy, logistics, and intelligence.

### 19. Resource Harvester
- **Role:** Extracts raw materials from map nodes or salvages wreckage.
- **Tweakable Features:**
  - **Extractor Arm Size:** Increases harvest rate but makes the unit incredibly heavy.

### 20. Construction / Repair Array
- **Role:** Builds base structures or repairs friendly units.
- **Tweakable Features:**
  - **Nanite/Welder Count:** Adding more arms speeds up construction exponentially.

### 21. Sensor Suites (Radar / Lidar)
- **Role:** Pushes back fog of war, provides targeting data to artillery, detects stealth.
- **Tweakable Features:**
  - **Mast Height:** Drastically increases line-of-sight, but makes the unit a highly visible target.

### 22. Logistics (Fuel Tanks / Power Banks)
- **Role:** Resupplies energy or fuel to frontline units.
- **Tweakable Features:**
  - **Tank Capacity:** Holds more reserves, but creates a massive explosive hazard if destroyed.
