# Vehicle Hull & Building Catalogue Refresh

_Concept plan. Author: mavis. Audience: Chris, with the goal of sequencing this into a PR roadmap._

---

## 0. Why this doc exists

The current vehicle-hull catalogue is the largest single source of "this looks
chunky / this looks like every other hull" in the build. The 2026-07-16
[HULL_MASSING_SPEC](../specs/HULL_MASSING_SPEC.md) already identified the root
cause — every ground hull was a single convex-hull loft with greebles, so all
seven ground hulls share one underlying massing primitive. That spec proposed
the two-volume tub/upper construction and the `build_afv_hull` helper; this doc
takes the next step and restructures the **catalogue** so the massing fix has a
coherent design language to work against, instead of being applied to a
haphazardly-named, mid-refresh pile of meshes.

Concretely: we are doing the **complete hull refresh** Chris asked for. The
existing families (`scout / light / medium / heavy / transport / heavy_transport /
open_transport / assault` + `mk2` + `mod_4a*` variants) are retired. They are
replaced by a manufacturer-organised catalogue of 6 silhouette families with
12+ hulls per family, a unified base architecture for buildings, and a
parallel expansion of the 3 foundation hulls (`pillbox / tower / fortress_wall`)
to 12+ variants — Chris explicitly approved foundation expansion as
in-scope on 2026-08-11, after the foundation hulls had been carved out of
the original draft.

This doc is a **design-level** plan. It commits to the catalogue shape and the
manufacturer roster, but the per-hull Blender authoring work, the per-PR GLB
exports, and the in-code `build_*` helpers are sequenced separately in §9.
**Both authoring paths are in scope** — hulls can be assembled from
primitives via `bake_custom_hull.py`'s JSON-composition path (the
"outer-skin treatment of the GLB that the baker produces"), OR
hand-authored in Blender using the `build_*.py` family of scripts (the
path that produces the existing hand-authored assets under
`prototype/assets/models/`). Triangle counts must stay low in both
cases; see §6.6 for the per-family budget.

### 0.1 The bake pipeline is the gold standard (2026-08-11 update)

Empirical axis-test results, run against Blender 5.2 LTS:

- The bake pipeline's coordinate swap is **now correct** end-to-end —
  a Godot input at `(X, Y, Z)` round-trips to a glTF at the same
  `(X, Y, Z)`. See `scratch/probe_axes/NOTES.md` for the full
  derivation and the two bugs that were found and fixed in the bake
  script during this audit (Z-axis inversion and a per-primitive
  transform loss in Blender 5.2's `export_apply`).
- Hand-authored hulls via the `build_*.py` path are unaffected by
  the bake fix; they were already producing glTF files in the right
  Godot-space coordinate system.
- Both paths produce the same glTF coordinate system, so any new
  hull can be authored via either path and the rest of the engine
  pipeline treats it identically.

---

## 1. Audit: what we have today

### 1.1 File-system reality (`prototype/assets/models/hulls/`)

**Two parallel naming systems are in flight.** This is the heart of the problem.

| Legacy (tier 1/2, "military-typology" names) | Modern (tier 3, "abstract" names) | WIP (in `NEW_HULLS/` at repo root) |
|---|---|---|
| `scout_hull` + `mk2` + `mod_4a2` | `capsule_hull` + light/heavy | `hull_01_scout` |
| `light_hull` + `mk2` + `mod_4a3` | `carapace_hull` + light/heavy | `hull_02_light_tank` |
| `medium_hull` + `mk2` + `mod_4a4` | `catamaran_hull` + light/heavy | `hull_03_medium_tank` |
| `heavy_hull` + `mk2` + `mod_4a5` | `crawler_hull` + light/heavy | `hull_04_heavy_tank` |
| `transport_hull` + `mk2` + `mod_4a6` | `delta_plate_hull` + light/heavy | `hull_05_medium_transport` |
| `heavy_transport_hull_mod_4a7` | `flatbed_hull` + light/heavy | `hull_06_heavy_transport` |
| `open_transport_hull_mod_4a8` | `gantry_hull` + light/flatbed | `hull_07_open_topped_transport` |
| `assault_hull_mod_4a9` | `hex_pod_hull` + light/heavy | `hull_08_assault_vehicle` |
| | `octaplate_hull` + light/broad | |
| | `spire_hull` + light/heavy | |
| | `tandem_hull` + light/heavy | |
| | `tank_drum_hull` + light/heavy | |

**12 modern base families, 8 legacy names, 8 WIP files. Three naming systems,
none complete.** A `module_catalog.gd` consumer today has to know which names
ship and which are dead-on-arrival.

### 1.2 File-size evidence of the "chunky" problem

GLB sizes for the heaviest hulls (largest 10):

| Hull | Size | Note |
|---|---|---|
| `heavy_hull_mk2.glb` | 112,192 B | Massing duplicated as 4+ welded convex hulls. |
| `light_hull_mk2.glb` | 100,120 B | Same construction, same chunk. |
| `medium_hull_mk2.glb` | 28,996 B | Notice the 4× drop vs. the other two `mk2`s. |
| `pillbox_foundation.glb` | 28,116 B | One of the better ones. |
| `transport_hull_mk2.glb` | 23,428 B | |
| `capsule_hull_heavy.glb` | 20,020 B | |
| `tank_drum_hull*.glb` | ~20,000 B | Three near-identical files for "tank" / "light" / "heavy". |
| `scout_hull_mk2.glb` | 18,364 B | |
| `fortress_wall_foundation.glb` | 18,012 B | |

The WIP `NEW_HULLS/` set is **3,900 – 8,600 B** — between 4× and 30× smaller
than the legacy set. That is the right ballpark for "low-poly kitbash parts"
(most contemporary model-kit parts sit between 1 KB and 15 KB per piece), but
the WIP set is so under-detailed that it reads as placeholder, not as finished
art. The new catalogue needs to land between the two: chunky enough to be
detailed and recognisable, lean enough to render 60+ units on screen at once.

**The chunkiness isn't a triangle count problem. It's a topology problem.**
A 100 KB `light_hull_mk2.glb` is heavy because it's a stacked pile of convex
hulls welded together to fake multi-volume massing, every one of them
re-bevel-re-greebled in isolation. The visual reading is "blob with a blob
grafted on." The WIP set went the other way and lost the "assembled" read
entirely. Both ends of this are what the catalogue refresh has to escape.

### 1.3 Buildings (`prototype/assets/models/buildings/`)

Nine distinct meshes, none of them related to each other by construction:

| Building | Size | Function in-game |
|---|---|---|
| `hq.glb` | 39,172 B | C&C pre-fab HQ |
| `refinery.glb` | 54,012 B | Resource processing |
| `light_manufactory.glb` | 45,524 B | Light factory |
| `medium_manufactory.glb` | 53,132 B | Medium factory |
| `heavy_manufactory.glb` | 61,580 B | Heavy factory |
| `power_plant.glb` | 34,268 B | Power generation |
| `tech_lab.glb` | 33,252 B | Tech unlock |
| `physics_lab.glb` | 36,100 B | Tech unlock |
| `exotics_lab.glb` | 52,240 B | Tech unlock |

These are the **C&C pre-fab infrastructure** layer. The player's *defenses* are
the kitbash-designed bunkers in `prototype/assets/models/hulls/`
(`pillbox_foundation`, `tower_foundation`, `fortress_wall_foundation`); the
buildings are the "this is your base" dressing. As Chris noted, they currently
read as a grab-bag — every one is a different artist, a different construction,
a different scale. The kitbash philosophy demands that they all read as one
industrial complex.

### 1.4 Three foundations (defenses-as-hulls)

`pillbox_foundation`, `tower_foundation`, `fortress_wall_foundation` are
already done well per the HULL_MASSING_SPEC Tier-3 notes (split merlons,
machicolation, faceting, `preserve_axis=0` tiling on the wall). **These
survive the refresh unchanged.** They are the player's kitbash canvas, not
pre-fab infrastructure, and they benefit from being visually distinct from
both the buildings and the vehicle hulls.

---

## 2. Refresh goals (restated as commit-ready targets)

1. **One naming system**, manufacturer-organised. No more `mk2` / `mod_4a*` /
   `*_light` / `*_heavy` suffixes on family names. Variant suffix is reserved
   for in-family variants.
2. **6 silhouette families** (down from 12), each with **12+ variants**
   distributed across 3–4 manufacturers. 72+ hulls minimum total.
3. **3–4 fictional manufacturers**, each with a distinct design language
   signature that survives at silhouette scale.
4. **Geometry constraints enforced project-wide**: regular convex polygons,
   plenty of flat facets, limited curves. Documented in §6 and enforceable in
   `build_meshes.py` via a small audit pass.
5. **One building base, greeble-differentiated.** The 9 C&C pre-fab buildings
   reduce to 1 base mesh + 9 greeble sets.
6. **Foundations unchanged.** `pillbox_foundation`, `tower_foundation`,
   `fortress_wall_foundation` are already Tier-3 done.

---

## 3. The new catalogue structure

### 3.1 Six silhouette families

The families are **silhouette archetypes**, not weight classes. A hull is
classified first by silhouette family (what shape it is), then by tonnage (how
big), then by manufacturer (who made it).

| # | Family | Slug | Silhouette philosophy | Reference vocabulary |
|---|---|---|---|---|
| 1 | **Block** | `block` | Boxy, conventional, sloped glacis. The "tank" baseline. | T-34, M4 Sherman, Leopard 1 |
| 2 | **Wedge** | `wedge` | Streamlined, dart-like, single taper. The "fighter." | Wiesel, CV90, Stryker Dragoon |
| 3 | **Plate** | `plate` | Heavy plate-armour, faceted, fortress-on-wheels. The "dreadnought." | Maus, IS-3, Object 279 |
| 4 | **Pod** | `pod` | Spherical / multi-axis sensor vehicle. The "eye." | Ho-Ri, Strv 103, modern C2 vehicle |
| 5 | **Carrier** | `carrier` | Cab-forward, open platform, modular. The "truck." | M939, M1078 LMTV, RCB |
| 6 | **Skiff** | `skiff` | Planing-hull, boat-on-land, low-slung. The "hovercraft." | BTR-80, LAV-25, AAV-7 |

The WIP set already maps to four of these (Block / Wedge / Carrier / Skiff)
under different names. The new slug scheme lets us retire the typo-prone
"tank_drum" / "delta_plate" / "spire" naming while keeping what worked.

### 3.2 Why six, not five and not seven

**Five** is too few to give each family the catalogue mass that makes
manufacturer identity legible. With 12 hulls per family and 3–4 manufacturers,
5 families × 12 hulls = 60 hulls, but each manufacturer ends up making
15–20 hulls, which is too much — designers can't keep a coherent look across
that many pieces without it drifting.

**Seven** is one too many to differentiate. The "dreadnought" plate-on-wheels
is genuinely distinct from the conventional "block" tank, but a "command
vehicle" would be a pod with extra greebles, not its own family. Six is the
right shape: it spans conventional / streamlined / heavy / sensor / utility /
amphibious without forcing artificial distinctions.

### 3.3 Tonnage bands within a family

Each family has three tonnage bands. These are *not* new families — they are
parameter variants of the same silhouette archetype:

| Tonnage | Typical footprint | Typical role |
|---|---|---|
| **Scout** (S) | 0.6× width, 0.5× height | Recon, cheap expendable |
| **Main** (M) | 1.0× width, 1.0× height | Workhorse |
| **Heavy** (H) | 1.4× width, 1.4× height | Assault, breakthrough |

That gives 6 families × 3 tonnages = 18 **archetypes**. Each archetype
needs at least 4 manufacturer-specific variants to hit 12 hulls per family
(4 × 3 tonnages = 12). With 4 manufacturers and 6 families, each
manufacturer is responsible for 18 hulls — a tractable single-author scope
over the refresh window.

### 3.4 Per-family hull count

| Family | Scout | Main | Heavy | **Total** |
|---|---|---|---|---|
| Block | 4 | 4 | 4 | **12** |
| Wedge | 4 | 4 | 4 | **12** |
| Plate | 4 | 4 | 4 | **12** |
| Pod | 4 | 4 | 4 | **12** |
| Carrier | 4 | 4 | 4 | **12** |
| Skiff | 4 | 4 | 4 | **12** |
| **Total** | **24** | **24** | **24** | **72** |

The 12-per-family minimum is the floor. Plate family in particular should run
to 14–16 (it has the most to differentiate: dozer / siege / mobile-artillery /
assault-gun sub-variants all live here, not in Block).

### 3.5 Total authoring work

- **72 vehicle hulls** (12 per family × 6 families), down from 12+8+8 = ~28
  finished, ~12 WIP. The refresh is ~3× the current count.
- **12+ foundation hulls** (expanded from the 3 existing) — see §5.7
  "Foundations/defenses expansion" for the family and variant breakdown.
- **1 building base** + **9 greeble sets** (down from 9 distinct buildings).
- **3 foundations** (the original `pillbox` / `tower` / `fortress_wall`)
  ship as the first 3 of the 12+ foundation expansion; the rest are
  new per §5.7.

**Total new vehicle + foundation hulls:** 72 + 12 = **84 hulls**, plus
1 building base and 9 greeble sets, plus the existing 3 foundations
(retired in name only — they survive as the first entries of the
expanded foundation catalogue).

---

## 4. Manufacturers (3 of them, the 4th is optional)

Three committed, one reserve. The roster is intentionally small — each
manufacturer is a recognisable silhouette signature that has to survive at
RTS zoom, so the player can pick out a Meridian hull at 80 m the same way
they'd pick out a Leopard 2 silhouette from a Cold War photo.

### 4.1 MERIDIAN ARMORY (conventional / slab)

> _"It has worked for fifty years. It will work for fifty more."_

The **default / mainline** manufacturer. Conservative engineering, lots of
bolts, plate seams, exposed rivets. The silhouette is the one that has
existed since 1945 and will exist in 2090: a near-vertical frontal plate,
sloped upper glacis, a single rotating mass on top.

- **Visual signature:** chamfered box with a wide beltline and visible bolt
  rows along every panel seam. Sloped glacis is *blunt* — angled but not
  dart-thin. The deck always has a raised turret ring or pintle collar.
- **Cues players read at distance:** a slight overhang of the upper
  superstructure past the lower tub (the "Marine Crocodile" silhouette),
  a flat front face, a barrel of the same width as the turret.
- **Makes families:** Block (primary), Plate (secondary), Carrier
  (military-truck variants).
- **Distinctive greebles:** exposed rib-and-bolt plate seams, a chimney or
  louver on the rear deck, "MERIDIAN" wordmark in the stencil library.
- **Coat:** dull steel-grey primer with a uniform finish — the "could be
  any faction, paint goes over the top" hull.

### 4.2 OSTERHOLM WERKE (precision / modular)

> _"Form follows function, but function follows measurement."_

The **Bauhaus / industrial-design** manufacturer. Right angles, flat
surfaces, geometric simplicity. The hulls are the kind of thing you'd see
in a Dieter Rams catalogue if Dieter Rams made tanks. Every panel is
square. Every bolt is on a grid. Nothing is decorative.

- **Visual signature:** clean orthogonal boxes, no superfluous bevels, no
  rivets on the broad faces (only at structural joints). Thin panel lines
  on a 1-unit grid. Hard 90° corners with a *very small* chamfer.
- **Cues players read at distance:** flat top deck with no turret ring (the
  pintle sits on an integrated pad), perfectly square front face, a
  one-piece lower tub with no fenders.
- **Makes families:** Pod (primary), Carrier (precision variants),
  Wedge (stealth / recon variants).
- **Distinctive greebles:** datum-line etchings on the side (a single
  shallow horizontal panel groove at exactly 1/3 height), a small roundel
  housing instead of a rivet row, gridded sensor apertures.
- **Coat:** a powder-coat matte finish, very low gloss — the "showroom
  floor" hull.

### 4.3 TIDEMARK DYNAMICS (maritime-origin)

> _"Engines run better when they can see the water."_

The **boat-builders**, repurposed for ground. Maritime engineering applied
to AFVs: low-slung, long, lots of horizontal paneling, a slight sheer-line
in the side profile, deck-edge bulwarks on the heavier pieces. Founded by
shipwrights who pivoted to ground vehicles when the polar ice receded and
the new coastlines opened up.

- **Visual signature:** a low freeboard, a long horizontal sweep, a
  distinctive "stem-to-stern" paneling rhythm (3–4 long horizontal grooves
  on each side). The superstructure is *one tier* — no bridge-box-on-bridge-
  box, just a single raised pilothouse forward.
- **Cues players read at distance:** a sheer line in side profile (the
  deck is higher at the ends than amidships), a small pilothouse offset
  forward, a long flat cargo or mounting deck aft. The planing-hull
  underside shows as a faceted V at the bow.
- **Makes families:** Skiff (primary), Wedge (naval-influenced fast attack),
  Block (light variants with maritime character).
- **Distinctive greebles:** cleats and bollards on the deck (the
  universal shipwright sign), a small anchor stowed on the bow, the
  "TIDEMARK" wordmark above the waterline, an ensign staff on the
  pilothouse.
- **Coat:** a marine-paint scheme — even the bare metal has a
  slightly different alloy tint, and the wear edges are *teal-green*
  (anti-fouling paint underneath), not rust.

### 4.4 (RESERVE) VANE-FORST HEAVY INDUSTRIES

> _"Build it tall, build it heavy, build it twice."_

The reserve slot. **Don't author Vane-Forst hulls yet.** The 72-hull count
above is achieved with the three committed manufacturers. Vane-Forst
becomes the home for "the smart tank that hasn't been invented yet" — the
faceted/stealth/active-armour work that is currently speculative. If a
fourth manufacturer is needed to hit 12 hulls in a particular family
because a tonnage band has 5 viable variants, Vane-Forst can take the 5th.
For the refresh PR sequence this stays a documented slot but ships
empty.

**Why hold the slot:** committing a fourth manufacturer now forces us to
write a fourth design language before we've validated that the first three
work. If one of the first three turns out to be a one-trick pony (e.g.
Tidemark can only really do Skiff and one Block variant), the catalogue
gets a fourth manufacturer almost for free. The slot costs nothing and
keeps the door open.

---

## 5. Family profiles (what each silhouette must have)

Every family has a one-paragraph design brief and a hard list of
mount-zone implications. Mount-zone implications are the **load-bearing
constraints** of the family — they are what determines whether a hull can
carry the sponson-embed weapons, the top pintle, the inverted bottom
pintle, etc. Read MOUNTING_AND_ARMOR_SPEC §3 and §5 first; the per-family
notes below are the per-hull consequences.

### 5.1 Block

> The conventional tank. Sloped glacis, near-vertical sides, a turret
> ring or pintle on top. Reads at distance as "main-battle."

- **Front facet:** a *single* sloped face, 30°–45° off vertical, with a
  30% vertical strip at the bottom that stays near-vertical so front-
  sponson-embed muzzles don't clip the slope (the HULL_MASSING_SPEC §4
  "front-glacis cosmetic" caveat lives here).
- **Side facets:** flat, full-tall vertical surfaces — premium sponson
  real estate.
- **Top facet:** must host a raised turret ring or pintle collar (the
  standard).
- **Bottom facet:** flat, full-width belly. The inverted-pintle (rotor)
  mount fits.
- **Mandatory greebles:** a rear engine deck with louvers, a turret ring,
  side-skirt fenders over the track run.
- **Per-manufacturer cue:** Meridian = exposed rib-and-bolt; Osterholm =
  clean orthogonal with no turret ring (integrated pad); Tidemark =
  maritime "deck" with cleats and a sheer line.

### 5.2 Wedge

> The streamlined fighter. Long, low, single taper. The interceptor
> class.

- **Front facet:** *sharp* — a near-45° wedge nose, NOT a blunt plate.
  The 30% near-vertical bottom strip from Block is *not* present; the
  wedge has to read as a wedge, and front sponson-embed weapons are
  deliberately rare on this family (the muzzle would clip the slope).
- **Side facets:** sloping inward (the wedge side is *not* vertical; it's
  a chamfered slope toward the deck).
- **Top facet:** narrow, often faceted. The pintle sits behind a faired
  canopy.
- **Bottom facet:** flat, often with a small inverted-pintle hardpoint for
  rotor mounts.
- **Mandatory greebles:** a small faired canopy or cockpit volume, a
  speed-line chamfer along the flanks.
- **Per-manufacturer cue:** Meridian = military Wiesel-style (square
  edges, exposed rivets on the canopy); Osterholm = stealth angularity,
  hard 30° chamfer; Tidemark = maritime "torpedo" read, planing-bow
  underside.

### 5.3 Plate

> The dreadnought. Heavy plate-armour, faceted, fortress-on-wheels.
> Maximum surface area for armor modules.

- **Front facet:** *thick* and *tall* — a near-vertical frontal plate,
  60–80% of `hy` of vertical surface, with only a *gentle* 20° slope at
  the top (vs. Block's 30–45°). The vertical strip at the bottom is
  maximal — this hull *invites* front-sponson-embed weapons, the
  opposite of the Wedge.
- **Side facets:** tall and vertical, with optional appliqué plate
  shelves.
- **Top facet:** often a *casemate* (a low forward-fixed fighting
  compartment) rather than a turret. Optional second tier.
- **Bottom facet:** flat, deep.
- **Mandatory greebles:** appliqué armour plates, rivet rows along every
  plate seam, a forward dozer or blade for the Heavy variant.
- **Per-manufacturer cue:** Meridian = the most "rivet-heavy" silhouette
  in the catalogue, the canonical dreadnought; Osterholm = unarmoured
  bare-bones chassis (Pod and Carrier families are also Osterholm, so
  Plate-Osterholm is rare and reads as a factory mistake — skip it);
  Tidemark = naval-influenced casemate with a tiered superstructure
  (read: a "battery" on a barge).

### 5.4 Pod

> The sensor vehicle. Spherical, multi-axis, the "eye on legs."

- **Front facet:** *not* a flat plate — this family is the one allowed
  the most non-orthogonal geometry. A faceted dome or rounded box
  forward, never a single sloped plate. A faceted sphere is *convex*
  (per the spec) but is *not* a flat plate.
- **Side facets:** curved or faceted-curved (octagonal cross-section
  reads as "pod" without violating the convex constraint).
- **Top facet:** a *small* flat sensor pad, the rest of the roof is
  faceted dome.
- **Bottom facet:** flat, full-width.
- **Mandatory greebles:** multiple sensor apertures (radar dome, optical
  cluster, comm array), a turret ring or sensor-pod pintle on top.
- **Per-manufacturer cue:** Meridian = boxy and conventional (a "Pod
  pretending to be a Block"); Osterholm = the canonical spherical
  pod, sensor-heavy; Tidemark = rarely builds Pods (skip Tidemark-Pod
  unless 12-hull count forces it).

### 5.5 Carrier

> The truck / hauler / modular platform. Cab-forward, open or
> configurable deck aft.

- **Front facet:** *vertical*, near-flat. The cab face. NO glacis slope
  on this family — that is the whole point; a Carrier is a flat-face
  vehicle.
- **Side facets:** flat, full-tall vertical surfaces — same as Block,
  equally good for sponson real estate.
- **Top facet:** *split* — a small flat cab roof forward, a large flat
  cargo or mounting deck aft. This is the most sponson-friendly top
  facet in the catalogue (a full cargo deck).
- **Bottom facet:** flat, full-width.
- **Mandatory greebles:** a distinct cab volume forward, a deck surface
  aft (flatbed, cargo bay, open-top, container).
- **Per-manufacturer cue:** Meridian = military truck (canvas-back,
  bench seats visible through cab windows); Osterholm = precision
  carrier (clean lines, no canvas, integrated equipment bays);
  Tidemark = marine-deck carrier (cleats, bollards, deck-edge
  bulwarks).

### 5.6 Skiff

> The hovercraft / amphibious. Planing-hull underside, low freeboard,
  the boat-on-land.

- **Front facet:** a *V* — the planing-hull bow, two faceted panels
  meeting at a centreline. NOT a single plate.
- **Side facets:** near-vertical but *shorter* than Block's sides (the
  hull is low-slung). Often with a sheer line (the deck edge rises
  slightly toward bow and stern).
- **Top facet:** wide and flat — the deck is the most generous in the
  catalogue because the hull is low and wide.
- **Bottom facet:** the *planing-hull* V — a faceted V from bow to
  stern, NOT a flat belly. This is the one family whose bottom is
  *not* a flat surface, and the inverted-pintle mount must be
  treated specially: the rotor sits on a small flat pad integrated
  into the V.
- **Mandatory greebles:** a small pilothouse forward (single tier, no
  superstructure stack), cleats on the deck, an anchor or bow
  fitting, a waterline stripe (decals).
- **Per-manufacturer cue:** Meridian = boxy AFV with boat-like
  underside; Osterholm = precision hovercraft (no cleats, clean
  lines); Tidemark = the canonical Skiff manufacturer, all three
  tonnages.

### 5.7 Foundations / defenses expansion (12+ variants)

The 3 existing foundation hulls (`pillbox_foundation`,
`tower_foundation`, `fortress_wall_foundation`) are the player-designed
defense kitbash; they were carved out of the original draft but Chris
explicitly approved expansion on 2026-08-11. **In-scope.** The existing
three ship as the first three entries of the new foundation catalogue;
the rest are new.

Foundations are not families in the same sense as vehicles — they are
*roles*, each of which has its own silhouette archetype and its own
mount-zone rules. The expansion is organised as 4 foundation
*families* × 3–4 manufacturer variants, with the 12+ floor on the
catalogue as a whole.

#### Foundation families

| # | Foundation | Slug | Silhouette philosophy | Reference vocabulary |
|---|---|---|---|---|
| 1 | **Bunker** | `bunker` | Compact, low, single fighting compartment. The baseline. | M8 pillbox, WWII Atlantic-wall casemate |
| 2 | **Tower** | `tower` | Tall, vertical, observation / over-watch. | WWII fire-control tower, watchtower |
| 3 | **Rampart** | `rampart` | Long, low, tileable wall + crenellation. The "defensive line." | Sectional fortification, merlon-and-embrasure curtain wall |
| 4 | **Battery** | `battery` | Open-platform, multi-weapon mount. The "static fire-base." | Coast-artillery casemate, missile launch pad |

The existing `pillbox_foundation` becomes `bunker_main_*`, the existing
`tower_foundation` becomes `tower_main_*`, and the existing
`fortress_wall_foundation` becomes `rampart_main_*`. New variants
expand each family to 3+ manufacturer-specific shapes and add the
`battery` family.

#### Per-family count

| Foundation | Manufacturer variants | Total |
|---|---|---|
| Bunker | 4 (Meridian / Osterholm / Tidemark / reserve) | **4** |
| Tower | 3 (Meridian / Osterholm / Tidemark) | **3** |
| Rampart | 3 (Meridian / Osterholm / Tidemark) | **3** |
| Battery | 3 (Meridian / Osterholm / Tidemark) | **3** |
| **Total** | | **13** |

The "12 hulls per category minimum" floor from the catalogue goal
translates to "12+ foundations in the catalogue" rather than "12+
variants per foundation family"; the bunker family in particular can
hold 5–6 variants (Meridian pillbox, Osterholm reinforced
bunker, Tidemark buried casemate, an AA-bunker variant, a
command-bunker variant) without crossing into "same thing with
different greebles" territory.

#### Mount-zone implications (foundations)

Foundations are static, so they have different mount-zone rules from
vehicles:

- **Top:** the foundation's *entire top surface* is a mount pad
  (per `MOUNTING_AND_ARMOR_SPEC §3`, the top facet is a full
  sponson-less pintle site). One or more weapons mount directly
  to the top. The turret ring convention does *not* apply — the
  foundation's top is one continuous platform.
- **Sides / front / back:** all side facets are flat vertical
  sponson-embed real estate. A foundation's side sponson capacity
  is *the entire perimeter* (vs. a vehicle's selective sponson
  surfaces), which is what makes defensive kitbashes
  disproportionately strong in the player economy (per
  `Factions_and_Buildings.md §1.2`).
- **Bottom:** flat. No locomotion, no inverted-pintle rotor. The
  bottom is purely the placement / collision plane.
- **Per-foundation rule:**
  - **Bunker** has the smallest top pad (1–2 weapons) and the
    most side-real-estate (perimeter-sponson everywhere). Reads
    as "tight, low, defensive."
  - **Tower** has the largest top pad (3–4 weapons stacked) and
    the least side real-estate (because the silhouette is tall
    and narrow). Reads as "over-watch."
  - **Rampart** has *no* top pad (the top is the crenellation
    — too small for a weapon mount) and the most side real-estate
    per linear meter. Tiles end-to-end. Reads as "defensive line."
  - **Battery** has a large flat top pad (multiple weapons) and
    minimal side sponson real-estate (the open-platform look).
    Reads as "fire-base."

#### Per-manufacturer cue on foundations

- **Meridian** — heavy rivets, exposed plate seams, the "dug-in
  bunker" read. The classic pillbox look.
- **Osterholm** — clean orthogonal lines, no rivets on broad
  faces, the "prefab concrete" read. Smooth walls, sharp
  crenellations.
- **Tidemark** — maritime-influenced, slight sheer line, anchor
  fittings on the corners, a waterline stripe. The "coastal
  defence" read. Tidemark-bunker is the most distinct of the
  manufacturer variants; it's a half-buried concrete
  casemate with marine fittings.

#### The "if I had to pick one" foundation

The **Tidemark Bunker** is the single most distinctive new
foundation in the catalogue. It carries the kitbash philosophy
forward (a buried concrete casemate with marine fittings is
genuinely "same engineering, different purpose" — the same
industrial complex as the buildings, but dug in and armoured)
and it costs roughly the same to author as a Meridian Bunker
because the silhouette and the manufacturing are the same. If
the foundation expansion has to be cut for time, the *one*
foundation that should not be cut is Tidemark Bunker; everything
else can ship later.

---

## 6. Geometric constraints (the "convex, faceted, no curves" rule)

### 6.1 The rule, in one sentence

Every hull silhouette is a **single convex polyhedron** (or a few
**interpenetrating** convex polyhedra) whose every face is a **flat
polygon with straight edges and no curvature**; the only permitted
curvature is the **post-bevel smoothing of edges** between flat faces,
and the radius of that smoothing must be small relative to the edge
length.

### 6.2 What this means for the Blender authoring pass

| Geometry element | Permitted | Forbidden |
|---|---|---|
| Top-level shape | Convex hull of a point cloud, or 2–3 interpenetrating convex hulls | A lofted NURBS surface, a subdivided mesh with smooth shading on a non-faceted normal |
| Faces | Triangles or quads with **planar vertices** | Triangles or quads with non-planar vertices (forcing triangulation) |
| Edges | Straight; the bevel chamfer between adjacent flat faces | A `bmesh.ops.bevel` so wide the chamfer fills the face and you can't tell where the face ends |
| Curves | Cylinder cross-sections (allowed in the per-axis hull primitives library), but only as **8-sided or fewer faceted cylinders** | `bpy.ops.mesh.primitive_*_add` with `segments > 8` and `cap_fill` |
| Greebles | Flat `add_box` and faceted `add_cyl_y` with ≤ 8 segments; flat `add_plane` decals; orthogonal `add_box` extrusions | Subdivided `add_cube` modifiers, `subdivision_surface` modifiers on hull geometry |
| Boolean ops | None (per HULL_MASSING_SPEC §3) | `bmesh.ops.difference` / `union` / `intersect` |

### 6.3 The convex-hull baseline (from HULL_MASSING_SPEC)

The current `build_meshes.py` already uses `bmesh.ops.convex_hull()` per
volume. This is **the right primitive** for the new catalogue, and the
two-volume interpenetrating-convex-hull technique (`build_afv_hull` in
HULL_MASSING_SPEC §4) generalises to the whole roster: every family
is a "Volume A primary + Volume B secondary, fused, then greebled."

### 6.4 The "small number of curves" allowance

The strict reading of "no curves" would ban cylinders, but the
mounting kit (`prototype/assets/models/parts/`) already uses
`add_cyl_y` for barrels, turrets, and antennae, and the player
expects a barrel to be round. The compromise:

- **Hull silhouettes:** faceted only. Cylinder segments ≤ 6.
- **Mounting hardware (turrets, pintles, barrels, sensor heads):** can
  be cylindrical, with segments ≤ 16.
- **Greebles (vents, hatches, antennae):** ≤ 6 segments.
- **Buildings:** can use a few curved silhouettes for the smokestack
  and dome, but the building base is straight-edged.

### 6.5 The enforcement mechanism

A small audit pass added to `build_meshes.py`:

```python
def audit_hull_geometry(obj, hx, hy, hz):
    """Reject hulls whose geometry violates the no-curves rule.
    Called once per export, after bevel, before GLB write."""
    # Rule 1: every face must have a planar vertex set
    # Rule 2: no face normal may have curvature > threshold
    # Rule 3: total triangle count < budget (proportional to hx*hy*hz)
    ...
```

This is a CI-style guard, not a runtime check. A hull that fails the
audit is logged with the file name, the rule it failed, and the vertex
IDs of the offending face. The fix is in the Blender file, not in
the audit script.

### 6.6 Triangle count budget (the "low triangle counts" rule)

Chris called out "low triangle counts" as an explicit goal on
2026-08-11, alongside the convex/flat-facets rule. The two rules
are coupled: **low triangle counts are achieved by large flat
facets**, and large flat facets are what the mounting system
needs. The audit pass in §6.5 enforces both at once.

The triangle budget is set per-hull-size, not per-hull:

| Hull tonnage | Footprint (typical) | Triangle budget (max) | Why |
|---|---|---|---|
| Scout (S) | (2.4, 0.8, 3.2) | **150 triangles** | Cheap expendable; the player expects a low-detail silhouette here |
| Main (M) | (4.0, 1.0, 6.0) | **400 triangles** | The workhorse. This is the median — every Block-Main, Wedge-Main etc. lands here |
| Heavy (H) | (6.0, 1.5, 8.0) | **700 triangles** | The dreadnought. The extra budget is for appliqué plates, more greebles, the dozer |
| Foundation | varies | **500 triangles** | The mid-budget ceiling; most foundations are Main-sized silhouettes |

**Why these numbers:**

- The current `heavy_hull_mk2.glb` is 112 KB and "looks chunky" per
  the audit. Pulling its triangle count puts it at ~3,700
  triangles — roughly 5× the Heavy budget above. The budget is
  the *why* the current hulls are chunky: they're 5× over budget
  in a catalogue that's supposed to render 60+ units on screen
  at once.
- The WIP set in `NEW_HULLS/` is 4–8 KB and reads as
  under-detailed. Those land at ~50–150 triangles — too low
  to read as a kitbash at RTS zoom. The Scout budget (150) is
  roughly the right floor for "looks finished, not placeholder."
- The Main budget (400) is the median; the per-hull
  silhouette budget is the same for every family at the same
  tonnage, so a Block-Main has the same triangle budget as a
  Wedge-Main or a Pod-Main. The *visual* difference between
  families comes from *how* the budget is spent, not from
  getting more or fewer triangles.

**How the budget is spent:**

- A convex-hull of a 12-point cloud (the block-hull primary
  volume) costs ~20 triangles after triangulation.
- A bevel with 2 segments on a 12-edge convex hull adds ~80
  triangles.
- A `greeble_louver_panel` (recessed vent pocket) costs
  ~30 triangles.
- A `greeble_rivet_row` (5 rivets) costs ~40 triangles.
- A turret ring (`add_cyl_y` at 16 segments) costs ~64
  triangles.
- A manufacturer's signature greebles (e.g. Meridian's
  rib-and-bolt plate seams) cost 40–80 triangles total.

A Main hull with two interpenetrating convex hulls + bevel +
turret ring + louver panel + rivet row + manufacturer signature
lands at ~280–400 triangles. Right in budget.

**The relationship to "large flat facets":**

A 400-triangle Main hull with 60 vertices and 12 facets per
volume has an average facet area of `(4×1×6) / 12 = 2.0 square
units`. The mount zones (`module_placer.gd`'s AABB) have a
typical facet area of `(4×1) / 2 = 2.0 square units` for the
sides, `(1×6) / 2 = 3.0` for top/bottom. The hull's facets are
*at least* as large as the mount-zone AABB facets they back,
which is what makes the sponson-embed look right (the muzzle
exits a flat plate that is the actual hull face, not a tiny
greeble that the player can't see at RTS zoom).

**The audit pass enforces the budget** as rule 3 in
`audit_hull_geometry()` above. A hull that exceeds the budget
is rejected before export, with a per-hull triangle count and
the budget for that tonnage.

---

## 7. Building unification

### 7.1 The new rule

> All C&C pre-fab buildings share one base mesh. The buildings are
> differentiated by the greeble set mounted on that base, exactly the
> way the kitbash philosophy says "same engineering, different
> purpose."

The 9 current building GLBs reduce to:

- **1 base building mesh** — `building_base.glb`. A multi-tier
  industrial complex shell, ~6×4×6 units in Godot space, with a
  flat roof and three distinct "anchor points" on the roof for
  greeble attachment.
- **9 greeble sets** — `building_addon_<name>.glb`, one per building
  function. Each is a single greeble assembly (chimney + cooling fins
  for the power plant; tanks + pipes for the refinery; a comm dish +
  flag for the HQ; etc.) that mounts to the roof anchor.
- **3 foundation meshes** unchanged.

### 7.2 The base mesh design

- **Tier 1 (lower)**: a 6×4 box, flat roof at `y = 2.0`, full width
  6×6 footprint. Chamfered edges, panel-line grooves on each face.
- **Tier 2 (mid)**: a 4×2 box, footprint 4×4, on top of Tier 1
  centred, roof at `y = 4.0`.
- **Tier 3 (upper)**: a 2×1.5 box, footprint 2×2, on top of Tier 2
  centred, roof at `y = 5.5`.
- **Anchors**: three roof plates on Tier 3, at offsets `(0, 0, 0)`,
  `(0, 0, ±0.6)`. Each anchor is a 0.6×0.05×0.6 flat plate that the
  greeble hardpoints mount to.
- **Loading doors**: four large rectangular doors, one per side, on
  Tier 1 (the manufactories need them; the labs hide them with
  decals; the HQ has a single grand entrance instead — same door
  frame, different door).
- **No fixed function** in the base mesh. No chimney, no comm dish,
  no laboratory glass, no refinery tanks. All of that is in the
  greeble set.

### 7.3 The greeble set roster

| Function | Greeble assembly | Roof anchor |
|---|---|---|
| HQ | Comm dish + flag pole + mast | centre + back |
| Refinery | Storage tanks (3×) + pipe rack | centre |
| Light Manufactory | Small crane + loading door | centre |
| Medium Manufactory | Medium crane + smokestack | centre + back |
| Heavy Manufactory | Large crane + heavy smokestack + cooling fins | centre + back + side |
| Power Plant | Tall smokestack + cooling fins (4×) | centre + back |
| Tech Lab | Glass-dome sensor head | centre |
| Physics Lab | Cylinder coil + magnet array | centre + back |
| Exotics Lab | Crystalline cluster (3× faceted cones) | centre |

The **manufactories** get progressively more greebles as the tonnage
goes up — that's the visible differentiator. The **labs** are
distinguished by their *roof feature* alone (a dome, a coil, a
crystal cluster), since the lab body is the same in all three.
The **power plant** is the most visually distinct, because it has
the tallest feature (the smokestack) and the most "horizontal"
greebles (the cooling fins).

### 7.4 The mount logic

The building is a single scene in Godot: `building_base.glb` is the
parent, `building_addon_<name>.glb` is instanced as a child of the
roof anchor. The greeble set is selected at instantiation time from
the building's `function` enum. The instanced child has its own
collision shape; the base mesh has the main collision shape.

This means **adding a new building function** is a one-file change
(new greeble GLB + one enum value) — the building catalogue
becomes an extensible data table.

---

## 8. Retirement plan (what gets deleted, what gets archived)

### 8.1 Vehicle hulls: full retirement

| Path | Disposition | Reason |
|---|---|---|
| `prototype/assets/models/hulls/scout_hull*` | **Delete** | Replaced by `block_scout_*` |
| `prototype/assets/models/hulls/light_hull*` | **Delete** | Replaced by `block_main_*` and `wedge_scout_*` |
| `prototype/assets/models/hulls/medium_hull*` | **Delete** | Replaced by `block_main_*` |
| `prototype/assets/models/hulls/heavy_hull*` | **Delete** | Replaced by `block_heavy_*` and `plate_heavy_*` |
| `prototype/assets/models/hulls/transport_hull*` | **Delete** | Replaced by `carrier_main_*` |
| `prototype/assets/models/hulls/heavy_transport_hull_mod_4a7` | **Delete** | Replaced by `carrier_heavy_*` |
| `prototype/assets/models/hulls/open_transport_hull_mod_4a8` | **Delete** | Replaced by `carrier_open_*` |
| `prototype/assets/models/hulls/assault_hull_mod_4a9` | **Delete** | Replaced by `plate_assault_*` |
| `prototype/assets/models/hulls/capsule_hull*` | **Delete** | Replaced by `pod_main_*` |
| `prototype/assets/models/hulls/carapace_hull*` | **Delete** | Replaced by `plate_main_*` |
| `prototype/assets/models/hulls/catamaran_hull*` | **Delete** | Replaced by `skiff_main_*` |
| `prototype/assets/models/hulls/crawler_hull*` | **Delete** | Replaced by `skiff_scout_*` |
| `prototype/assets/models/hulls/delta_plate_hull*` | **Delete** | Replaced by `wedge_main_*` |
| `prototype/assets/models/hulls/flatbed_hull*` | **Delete** | Replaced by `carrier_main_*` |
| `prototype/assets/models/hulls/gantry_hull*` | **Delete** | Replaced by `carrier_heavy_*` |
| `prototype/assets/models/hulls/hex_pod_hull*` | **Delete** | Replaced by `pod_heavy_*` |
| `prototype/assets/models/hulls/octaplate_hull*` | **Delete** | Replaced by `block_main_*` (Osterholm) and `plate_main_*` (Meridian) |
| `prototype/assets/models/hulls/spire_hull*` | **Delete** | Replaced by `plate_main_*` and `plate_heavy_*` |
| `prototype/assets/models/hulls/tandem_hull*` | **Delete** | Replaced by `wedge_heavy_*` |
| `prototype/assets/models/hulls/tank_drum_hull*` | **Delete** | Replaced by `block_main_*` and `plate_heavy_*` |
| `NEW_HULLS/hull_*` (all 8) | **Move to `docs/archive/new_hulls_wip/`** | Incomplete WIP, kept for reference but not shipped |

### 8.2 Buildings

| Path | Disposition |
|---|---|
| `prototype/assets/models/buildings/hq.glb` | **Replace with `building_base.glb` + `building_addon_hq.glb`** |
| `prototype/assets/models/buildings/refinery.glb` | Same — `building_addon_refinery.glb` |
| `prototype/assets/models/buildings/light_manufactory.glb` | `building_addon_light_manufactory.glb` |
| `prototype/assets/models/buildings/medium_manufactory.glb` | `building_addon_medium_manufactory.glb` |
| `prototype/assets/models/buildings/heavy_manufactory.glb` | `building_addon_heavy_manufactory.glb` |
| `prototype/assets/models/buildings/power_plant.glb` | `building_addon_power_plant.glb` |
| `prototype/assets/models/buildings/tech_lab.glb` | `building_addon_tech_lab.glb` |
| `prototype/assets/models/buildings/physics_lab.glb` | `building_addon_physics_lab.glb` |
| `prototype/assets/models/buildings/exotics_lab.glb` | `building_addon_exotics_lab.glb` |

The old `*_manufactory.glb` files are deleted once the greeble
replacement is in `building_catalog.gd` (the building spawner).

### 8.3 Foundations (unchanged)

`pillbox_foundation.glb`, `tower_foundation.glb`,
`fortress_wall_foundation.glb` survive the refresh untouched. They
are the player-designed defense kitbash, not the pre-fab
infrastructure, and they already pass the HULL_MASSING_SPEC audit.

### 8.4 What about the `.json` and `.glb.import` files?

The `.json` sidecars carry the catalog metadata (size, hp, weight,
mount zones). When the new hulls are authored, each new `.glb` gets
a matching `.json` rewritten. The old `.json` files are deleted
alongside their `.glb`s. The `.glb.import` files are
auto-regenerated by Godot's import pipeline on the first
`reimport_assets.sh` run after the file move — no manual handling.

### 8.5 The `module_catalog.gd` follow-up

Every retired hull entry in `module_catalog.gd` gets deleted in the
same PR as the asset retirement. New entries are added for the
72-hull catalogue. The WIP entries
(`scout_hull_mod_4a2`, `light_hull_mod_4a3`, etc.) are
*already* removed from the catalog — verify before retiring the
files.

---

## 9. PR sequencing

The refresh is one logical change but it ships in **8 PRs**, ordered
so each PR is independently reviewable and the build stays green
between them. Each PR closes one or more issues on
`docs/specs/HULL_MASSING_SPEC.md` and reuses the
`build_afv_hull` helper from that spec as the foundational
construction primitive.

The order below is the **logical** order (foundational first,
families in sequence, buildings and foundations last). The
**recommended execution order** is the swap called out in §13:
ship the building unification (PR 7 here) first, then return to
the hull PRs. Either way, **PR 0 must be the first PR shipped**,
because the bake pipeline fix it carries is the prerequisite for
every hull PR after it.

### PR 0 — `hull: bake pipeline axis-test fixes (prerequisite for everything)`

**Scope:** the two bugs found in the 2026-08-11 axis-test audit
(see `scratch/probe_axes/NOTES.md` and §10.6). The fixes are
already applied in the working tree; this PR makes them official.

1. `prototype/tools/blender/bake_custom_hull.py`:
   - `pos_b = (position[0], -position[2], position[1])` (was
     `(X, Z, Y)` — the original swap put Godot +Z at glTF -Z)
   - `rot_b = (rotation[0], -rotation[2], rotation[1])` (same fix)
   - `scale_b = (scale[0], -scale[2], scale[1])` (same fix)
   - Added `bpy.ops.object.transform_apply(location=True,
     scale=True, rotation=True)` after the `bpy.ops.object.join()`
     step (Blender 5.2's `export_apply=True` was silently dropping
     per-primitive location/scale)
   - Updated the docstring to document the derivation
2. `scratch/probe_axes/` — the new regression-test directory:
   - `axis_probe_input.json` — the 7-primitive axis-probe input
   - `axis_probe.glb` + `axis_probe.json` — the bake output
   - `axis_probe_report.md` — the per-marker AABB report (PASS)
   - `run_probe.ps1` — the runner (one command, no Godot needed)
   - `reimport_and_report.py` — the pure-Python GLB reader
   - `dump_primitives.py`, `dump_vertices.py`,
     `check_existing_asset.py` — diagnostic utilities
   - `NOTES.md` — the full audit writeup
3. `scratch/.gitignore` — exclude the `.glb` outputs from VCS
   (they're regenerated by `run_probe.ps1`); keep the JSON
   inputs and the report checked in.

**Validation:** `.\scratch\probe_axes\run_probe.ps1` reports
**PASS** for all 6 axis markers. The report is checked in as
`axis_probe_report.md` and is the artifact a reviewer looks
at. No Godot runtime needed.

**Risk:** low. The fixes are surgical (one negation in three
lines, one explicit `transform_apply` call) and they're verified
by a 6/6 PASS regression test.

**Why this is PR 0 and not PR 1:** every subsequent hull PR that
uses `bake_custom_hull.py` (i.e., every hull PR using Path A
from §10.5) ships baked hulls that depend on this fix. Without
this PR, the catalog of 72+ new hulls would ship with the
Z-inversion bug and the transforms-dropped bug, and the player
would see every new tank facing backward and at the wrong
scale. Cheap to merge, blocking for everything else.

### PR 1 — `hull: rename and retire the legacy tier-1/2 catalogue`

**Scope:** rename and retire. No new meshes.

1. Move all `*_hull_mk2` and `*_hull_mod_4a*` and legacy
   `scout/light/medium/heavy/transport_*_hull` files to
   `docs/archive/legacy_hulls/`.
2. Move the `NEW_HULLS/` WIP files at repo root to
   `docs/archive/new_hulls_wip/` (they are reference-only;
   not shippable, but not deleted).
3. Update `module_catalog.gd` to remove their entries (verify
   already-done per §8.5).
4. Update `hull_loader.gd`'s "hull missing" error message to point
   at the new naming scheme.
5. Add a `HULL_NAMING.md` (one-pager) into
   `prototype/docs/` documenting the new slug scheme and the
   manufacturer roster.

**Validation:** run the test suite — it should pass with the
smaller catalogue.

**Risk:** low. This is a renaming PR with the test suite as
the safety net. If a hull entry is referenced anywhere else
(visual_builder.gd, greebles, etc.) the test suite catches it.

### PR 2 — `hull: introduce build_afv_hull() and Meridian block family`

**Scope:** the keystone helper, plus the first 12-hull family
(Block-Meridian, all three tonnages × four variants).

1. Add `build_afv_hull(...)` to `build_meshes.py` per
   HULL_MASSING_SPEC §4.
2. Add `greeble_louver_panel(...)` (the recessed vent pocket
   helper) — also per HULL_MASSING_SPEC §4.
3. Add `audit_hull_geometry(obj, hx, hy, hz, tonnage)` per
   §6.5 (the no-curves + low-triangle + planar-faces audit).
4. Author the **Block-Meridian** family: 12 hulls
   (`block_scout_meridian_a/b/c/d`,
   `block_main_meridian_a/b/c/d`,
   `block_heavy_meridian_a/b/c/d`). Mix of Path A (JSON
   composition) and Path B (hand-authored) per §10.5 — the
   stock family shells are baked from JSON, the manufacturer
   signature greebles are added by hand.
5. Add the corresponding `.json` sidecars.
6. Update `module_catalog.gd` with the 12 new entries.

**Validation:** the Block family is the most-tested family
(because it is the conventional tank and the player will use it
the most). Run the full test suite and visually inspect all 12
in the Design Lab. Confirm every hull passes `audit_hull_geometry`
(triangle count within the per-tonnage budget from §6.6).

**Risk:** moderate. The `build_afv_hull` helper is the foundational
piece; if it has a bug, it propagates to every other family.
**Mitigation:** ship only Block-Meridian in this PR, then
validate the helper against it before extending.

### PR 3 — `hull: Osterholm and Tidemark Block variants`

**Scope:** the remaining 12 Block hulls (8 from Osterholm, 4 from
Tidemark).

1. Author `block_*_osterholm_*` × 8.
2. Author `block_*_tidemark_*` × 4.
3. Update `module_catalog.gd`.

**Validation:** the visual side-by-side test: Meridian / Osterholm
/ Tidemark variants of the same tonnage should be recognisably
different at a glance (the manufacturer signature) but still
recognisably the same family (the silhouette archetype). The
triangle-count audit should still PASS for every hull.

**Risk:** low. The helper is proven in PR 2.

### PR 4 — `hull: Wedge and Plate families (24 hulls)`

**Scope:** the two "advanced" families. 12 Wedge, 12 Plate.

1. Author Wedge-Meridian, Wedge-Osterholm, Wedge-Tidemark
   (4 + 4 + 4 = 12).
2. Author Plate-Meridian, Plate-Osterholm (8 — Osterholm
   Plate is "rare per §5.3", so we ship 4 instead of 4),
   Plate-Tidemark (4).
3. Add `block` and `plate` family mount-zone overrides to
   `module_placer.gd` if needed (the front-glacis cosmetic
   from HULL_MASSING_SPEC §4 lives in PR 2 verification — re-
   verify per hull here).

**Risk:** moderate. Plate is the most mount-sensitive family
(it's the "front-sponson-embed" family by design), so the
mount-zone check has to be visual-and-by-eye, not just
code-review. Schedule an in-editor pass.

### PR 5 — `hull: Pod, Carrier, Skiff families (36 hulls)`

**Scope:** the remaining three families. 12 + 12 + 12 = 36.

1. Author Pod-Meridian, Pod-Osterholm (Tidemark-Pod is rare
   per §5.4, ship 8 here).
2. Author Carrier-Meridian, Carrier-Osterholm, Carrier-Tidemark
   (4 + 4 + 4 = 12).
3. Author Skiff-Meridian, Skiff-Osterholm, Skiff-Tidemark
   (4 + 4 + 4 = 12).
4. Update `module_catalog.gd`.

**Risk:** low-moderate. Skiff is the one family with a
non-flat bottom (the planing V), so the inverted-pintle mount
needs the new "V-bottom pad" treatment. This is a small
addition to `module_placer.gd` (~20 lines).

### PR 6 — `hull: foundation expansion (13 hulls across 4 families)`

**Scope:** the foundation catalogue expansion per §5.7.
The 3 existing foundation GLBs are renamed (not retired); the
rest are new.

1. Rename `pillbox_foundation.glb` →
   `bunker_main_meridian.glb` (the existing Tier-3 bunker
   already follows the Meridian rib-and-bolt signature; it's
   the canonical Meridian Bunker Main).
2. Rename `tower_foundation.glb` →
   `tower_main_meridian.glb`.
3. Rename `fortress_wall_foundation.glb` →
   `rampart_main_meridian.glb`.
4. Author the **Osterholm Bunker** and **Tidemark Bunker**
   (the §5.7 "if I had to pick one" Tidemark Bunker is the
   marquee piece here).
5. Author **Osterholm Tower** and **Tidemark Tower**.
6. Author **Osterholm Rampart** and **Tidemark Rampart**.
7. Author the new **Battery** family (3 variants —
   Meridian / Osterholm / Tidemark).
8. Update `module_catalog.gd` with the 13 entries
   (3 renames + 10 new).
9. Update the foundation-spawner in `prototype/scripts/` to
   read the new entries (same code, new IDs — the rename is
   the bulk of the work).

**Validation:** every foundation variant passes
`audit_hull_geometry()`. The Tile-Edges-Identical rule on
`rampart_*` is preserved (the existing
`fortress_wall_foundation` `preserve_axis=0` guard is kept).

**Risk:** moderate. The Tidemark Bunker is the most novel
silhouette in this PR (a half-buried concrete casemate with
marine fittings) and needs an in-editor pass.

### PR 7 — `buildings: unify to base + greeble sets`

**Scope:** the building refresh.

1. Author `building_base.glb` and the 9 greeble sets
   (`building_addon_*.glb`).
2. Add `BuildingCatalog.gd` — the data table that maps
   function name to greeble set.
3. Update the building spawner to instantiate the base +
   greeble rather than a single per-function GLB.
4. Delete the old 9 building GLBs (per §8.2).
5. Update `prototype/docs/UI_STYLE_GUIDE.md` and
   `docs/design/CORE_DESIGN_LANGUAGE.md` with the new building
   architecture.

**Risk:** low-moderate. The spawner is the only piece of code
that has to change; the rest of the building system reads
`building_base` + the active greeble and doesn't care.

### PR 8 — `hull: doc + test baseline update`

**Scope:** final documentation and visual-regression baseline.

1. Add a `HULL_REFRESH_CHANGELOG.md` (single-line per PR)
   pointing to this doc for the rationale.
2. Update the visual regression baselines in
   `prototype/tests/visual/` for the new hulls (this
   is the bulk of the diff).
3. Add a `HULL_REFRESH_NOTES.md` to the project root
   summarising the catalogue shape, the manufacturer roster,
   the family taxonomy, and the bake-pipeline fix.

**Risk:** low.

---

## 10. Tooling & pipeline

### 10.1 The `build_meshes.py` extension

This plan adds to the existing file, doesn't replace it. The
new helpers are appended after the existing
`build_wedge_hull()` family.

```python
# New section in build_meshes.py
# 1. build_afv_hull(...)              # HULL_MASSING_SPEC §4
# 2. greeble_louver_panel(...)        # HULL_MASSING_SPEC §4
# 3. superstructure_tiers param       # HULL_MASSING_SPEC §6
# 4. greeble_recessed_embrasure(...)  # HULL_MASSING_SPEC §13
# 5. hull_geometry_audit(obj, ...)    # §6.5
# 6. family builders:
#      build_block_hull(...)
#      build_wedge_hull(...)  # already exists; new param
#      build_plate_hull(...)
#      build_pod_hull(...)
#      build_carrier_hull(...)
#      build_skiff_hull(...)
# 7. manufacturer dispatchers:
#      meridian_signature(bm, hx, hy, hz, tonnage)
#      osterholm_signature(bm, hx, hy, hz, tonnage)
#      tidemark_signature(bm, hx, hy, hz, tonnage)
```

The **manufacturer signature** is a function that adds the
manufacturer-specific greebles to a built family hull. This is
the cleanest way to enforce manufacturer identity without
inlining the signature into every family builder.

### 10.2 Reimport pipeline

Per the GODOT_4_7_PITFALLS doc: always run
`scratch/reimport_assets.sh` before trusting a screenshot.
The refresh doesn't change the reimport script; it does mean
the reimport script gets run *a lot* during the PR sequence.
Each PR's manual verification is a reimport + a Design Lab
walkthrough.

### 10.3 The .json sidecar

The `.json` sidecar format is unchanged. Each new hull
gets the same fields the existing hulls use (size, hp,
weight, mount zones, etc.). The `manufacturer` and
`family` fields are new — add them to the schema.

```json
{
  "id": "block_main_meridian_a",
  "display_name": "Block Main / Meridian A",
  "family": "block",
  "tonnage": "main",
  "manufacturer": "meridian",
  "size": [4.0, 1.0, 6.0],
  "hp": 400,
  "weight": 250,
  "mount_zones": { ... }
}
```

### 10.4 The test order

The current `run_tests.gd` `SUITE_ORDER` is preserved per the
project rule (navmesh/Recast flake depending on prior
suites). The hull refresh doesn't add a new test suite, but
the existing visual regression tests in
`prototype/tests/visual/` will need a baseline update when
the first 12 hulls are replaced. Document the baseline
update in the PR 2 description.

### 10.5 The bake pipeline — both authoring paths

The refresh supports two authoring paths. Either is fine; the
end result is the same `.glb` + `.json` pair, and either path
is fed into the rest of the engine the same way (via
`mesh_asset_loader.gd`).

**Path A — JSON composition via `bake_custom_hull.py`.**

The Design Lab's Hull Builder UI is a *player-facing* tool, but
it is also the canonical way to compose a hull from the
project's primitive vocabulary. A hull authored in the Hull
Builder exports a JSON like `axis_probe_input.json` (see
`scratch/probe_axes/`) with the primitive list; running that
JSON through `bake_custom_hull.py` produces the GLB.

This path is the right choice for:
- Stock family shells (the 18 archetypes: 6 families × 3 tonnages).
- Hulls that are mostly the family shell plus manufacturer signature.
- Fast iteration — JSON composition is data-driven, not freeform Blender.
- Re-authoring an existing hull with new parameters (e.g. scale, greeble count).

**Path B — hand-authored via the `build_*.py` scripts.**

The `build_*.py` family (`build_37mm_m3.py`, `build_artillery.py`,
`build_hull_primitives.py`, `build_meshes.py`, etc.) is the path
that produced the existing hand-authored assets in
`prototype/assets/models/`. The author runs the script in headless
Blender (`blender.exe --background --python build_<thing>.py`)
and the script writes the GLB.

This path is the right choice for:
- Hulls that need a non-trivial custom silhouette (e.g. the
  multi-tier tower foundation, the interpenetrating-convex-hull
  AFV body).
- Hulls whose manufacturer signature is geometry-heavy (e.g.
  Tidemark's maritime cleats and bulwarks).
- Hulls whose greebles are too complex to express as a primitive
  list (e.g. a recessed embrasure, a faceted canopy).

**Path C — the `NEW_HULLS/` WIP files (8 files, 3.9–8.6 KB each).**

These are the unfinished hand-authored hulls Chris started
before the refresh kicked off. They are moved to
`docs/archive/new_hulls_wip/` and used as a *reference*, not as
shippable assets. The new catalogue draws on the same family
shells (Block / Wedge / Carrier / Skiff) but with the
manufacturer-specific signatures that the WIP files don't have.

**The output equivalence rule (the "outer skin treatment" guarantee).**

Both paths produce a GLB that:
- is in the same Godot-space coordinate system (verified
  empirically, see §10.6 below);
- has the same per-primitive material setup (the bake path
  uses a single `PrimitiveMaterial` per primitive; the
  `build_*.py` path uses one `StandardMaterial3D` per part,
  but the import side (`mesh_asset_loader.gd`) doesn't
  distinguish);
- carries the same `.json` sidecar schema (size, hp, weight,
  domain, family, tonnage, manufacturer, mount zones);
- renders identically in the Design Lab and in
  `Match.tscn` after a Godot reimport.

The `audit_hull_geometry()` pass in §6.5 runs on the GLB
output regardless of which path produced it, so the
no-curves + low-triangle + planar-faces rules apply
uniformly.

### 10.6 Bake pipeline: status after the 2026-08-11 axis-test audit

The bake pipeline was audited end-to-end on 2026-08-11
against the actual installed Blender 5.2 LTS
(`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`).
The audit found two bugs in the original `bake_custom_hull.py`,
both now fixed in place. Full notes are in
`scratch/probe_axes/NOTES.md`; the summary:

| Bug | Symptom | Cause | Fix | Where |
|---|---|---|---|---|
| **Per-primitive transforms dropped** | A test marker at Godot (1.5, 0, 0) collapsed to glTF (0, 0, 0) | Blender 5.2's `export_apply=True` does not reliably bake per-object location/scale into vertex positions; the bake script did not call `transform_apply` explicitly | Added `bpy.ops.object.transform_apply(location=True, scale=True, rotation=True)` after the join step | `bake_custom_hull.py` join block |
| **Z axis inverted** | A test marker at Godot (0, 0, 1.5) landed at glTF (0, 0, -1.5) | The glTF exporter's `export_yup=True` applies a **-90° rotation about X** (i.e., glTF (X, Y, Z) = Blender (X, Z, -Y)), not the pure swap the original code assumed. The original `pos_b = (X, Z, Y)` puts Godot +Z at glTF -Z. | Changed `pos_b = (X, -Z, Y)`, `rot_b = (Rx, -Rz, Ry)`, `scale_b = (Sx, -Sz, Sy)` | `bake_custom_hull.py:54-56` (now lines 38-69 in the post-fix file) |

**Post-fix test result: 6/6 PASS.** A Godot-space input at
(X, Y, Z) round-trips to a glTF at the same (X, Y, Z). The
round-trip matches the convention used by the existing
hand-authored assets (where the `heavy_hull_mk2.glb` turret-top
vertices sit at glTF -Z, confirming "forward = -Z" is the
project convention).

**Why the existing hand-authored assets were unaffected:**

The existing assets under `prototype/assets/models/` come from
the `build_*.py` path, not from `bake_custom_hull.py`. The
`build_*.py` path authors directly in Blender Z-up (where
+Y is "forward" in this codebase) and exports with the same
`export_yup=True` flag; the resulting glTF has "forward" at
glTF -Z, which matches the Godot convention. The bake path
was the only broken path, and it had not been used to ship
any production asset yet.

**The `scratch/probe_axes/` directory** is the canonical
regression test for the bake pipeline. It bakes a 7-primitive
test (a 2×2×2 core cube + 6 colour-coded axis markers), reads
the resulting GLB directly from the glTF JSON chunk, and
asserts each marker landed in the expected Godot-axis
half-space. Run from PowerShell:

```powershell
.\scratch\probe_axes\run_probe.ps1
```

This is the test the future agent runs if a Blender upgrade
or a Godot glTF-importer change threatens the convention.
It is a one-command CI gate; it does not require a Godot
runtime.

---

## 11. Verification checklist (per hull)

For every new hull authored, the following has to be verified
before the PR is mergeable:

### 11.1 The construction checklist

- [ ] **Family is correct.** A `block_main_meridian_a` looks
  like a Block, not a Wedge.
- [ ] **Manufacturer is correct.** The Meridian rib-and-bolt
  greebles are present. The Osterholm cleanliness is present.
  The Tidemark maritime cues are present.
- [ ] **Size matches the catalog.** `(4.0, 1.0, 6.0)` is
  `(4.0, 1.0, 6.0)` in Godot space.
- [ ] **No NURBS, no subdivision, no boolean ops.** Run
  `audit_hull_geometry()` (§6.5).
- [ ] **Bevel is applied.** The chamfer is at the dihedral
  angle threshold, not a free-form offset.
- [ ] **All greebles are mounted with the bevel done first.**
  (Per HULL_MASSING_SPEC §4: silhouette first, bevel,
  then greebles.)

### 11.2 The mount-zone checklist

- [ ] **Top facet hosts a pintle or turret ring.** The top
  center of the AABB at `(0, hy, 0)` is reachable from a
  click on the top facet.
- [ ] **Side facets are flat and vertical** (Block, Plate,
  Carrier) or "flat-and-vertical-with-acceptable-slope"
  (Wedge, Skiff, Pod — see family profiles).
- [ ] **Bottom facet is flat and full-width** (Block, Wedge,
  Plate, Pod, Carrier) or a flat pad integrated into the V
  (Skiff).
- [ ] **Front-sponson-embed muzzles exit cleanly** on Block
  (with the 30% bottom-strip near-vertical band), Plate
  (whole frontal is near-vertical, easy), and Pod (faceted
  dome, may need the faceted-dome to have a flat-front
  strip). Wedge and Skiff avoid front-sponson-embed as a
  design choice.
- [ ] **The convex-hull audit passes.** The mesh is
  manifold, no degenerate faces, no zero-area triangles.

### 11.3 The at-distance checklist

- [ ] **The silhouette reads at RTS zoom.** A player looking
  at a unit at 80 m should be able to name the family
  (Block, Wedge, etc.) from the silhouette alone, and the
  manufacturer (Meridian, Osterholm, Tidemark) with a
  second's look.
- [ ] **The faction colour reads.** Even with the heaviest
  Meridian wear setting, the brand silhouette is still
  visible.
- [ ] **The mounting real estate is visible.** Side
  sponson-embed sites look like sites, not like random
  surface bumps. Top pintle sites look like pads, not
  like noise.

### 11.4 The parity checklist (one per family)

For each family, **one variant per tonnage** has to be
screenshot-compared across all three manufacturers. The
three-way comparison is the test that the manufacturer
identity is doing real work.

---

## 12. What's NOT in this plan

These are scope decisions, not omissions — they're listed
so they don't get re-asked.

- **No new factions.** Faction identity is colour-only per
  `CORE_DESIGN_LANGUAGE.md §4.2` and stays that way. The
  manufacturer is a separate abstraction (in-fiction factory
  of origin), not a faction.
- **No change to the mounting system.** The
  `module_placer.gd` flush-mount + sponson-blister + facet
  classification pipeline stays untouched. The hull refresh
  feeds it; the pipeline doesn't change.
- **No change to the locomotion system.** Treads / wheels /
  hover / legs stay as they are. The hull silhouette
  doesn't dictate locomotion.
- **No change to the weapon modules.** Weapons are
  kitbash-mounted on whatever hull the player picks. The
  hull refresh doesn't add or remove weapon modules.
- **The fourth manufacturer is held in reserve.** Vane-Forst
  is named but not authored. If the 72-hull count is hit
  with three, Vane-Forst stays a slot. If the count is
  short, Vane-Forst takes the remaining variants.
- **The damage / wear system is not in scope.** The hull
  refresh is the catalogue shape; the wear shader
  (VISUAL_ART_DIRECTION §1.3) is unchanged. A worn
  Meridian hull still reads as a worn Meridian hull.
- **The bake pipeline bug fixes are in scope** (PR 0). They
  are required for any hull baked via the JSON-composition
  path; they are documented in `scratch/probe_axes/NOTES.md`
  and are surgical (one negation in three lines, one explicit
  `transform_apply` call).
- **The foundation / defenses expansion is in scope** (PR 6,
  per §5.7). The 3 existing foundations survive as the first
  3 entries of the new 13-hull catalogue; 10 more are new.
  Chris explicitly approved this on 2026-08-11.
- **Both authoring paths are in scope** (§10.5). The hull
  refresh supports both Path A (JSON composition via
  `bake_custom_hull.py`) and Path B (hand-authored via the
  `build_*.py` family). Either path's output is the same
  `.glb` + `.json` pair and is fed into the rest of the
  engine the same way.
- **Low triangle counts are in scope** (§6.6). Every hull
  must hit the per-tonnage triangle budget (Scout 150,
  Main 400, Heavy 700, Foundation 500). The
  `audit_hull_geometry()` pass enforces this at export time.

---

## 13. The "if I had to pick one" line

> **Ship PR 0 (the bake fix) and PR 7 (the building
> unification) back-to-back, in that order, before any
> new hull is authored.** That's the lowest-risk, highest-
> signal path through the refresh.

Specifically:

1. **PR 0** — bake pipeline fix + axis-test regression test.
   Surgical, 6/6 PASS, no Godot runtime needed. The
   prerequisite for every hull baked via Path A.
2. **PR 7** — building base + 9 greeble sets + BuildingCatalog.
   Lowest-risk architecture change; validates the "kit-of-parts
   grammar" pattern (CORE_DESIGN_LANGUAGE §4.1) end-to-end
   before committing 72 vehicle hulls to the same pattern.

After PR 0 and PR 7, the foundation is solid: the bake
pipeline is verified, the building kit-of-parts pattern is
proven, and the `audit_hull_geometry()` pass is in place.
From there, PRs 1 → 2 → 3 → 4 → 5 → 6 → 8 ship the
vehicle and foundation catalogue against a known-good
toolchain.

**Why not start with the Block family (PR 2) instead?** Two
reasons. First, the bake fix in PR 0 *must* land before any
Path A hull, because the bug it fixes (Z inversion) would put
every new tank facing backward in-game. Second, the building
unification in PR 7 is the *least*-coupled change in the
whole refresh — it touches one file (`building.gd`'s spawner)
and one new file (`BuildingCatalog.gd`) — and it teaches the
team the kit-of-parts-grammar pattern that the hull PRs will
need to follow. Doing it first means doing the cheap one
twice if the team needs to iterate, not doing the expensive
one twice.

**The if-I-had-to-pick-one Tidemark Bunker is the single
foundation that should not be cut for time** (per §5.7).
Everything else can ship later; that one carries the
kitbash philosophy forward most clearly.
