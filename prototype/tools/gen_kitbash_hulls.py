#!/usr/bin/env python3
"""Authors the kitbashed hull assembly sources in data/hull_assemblies/.

These eight hulls exist to break the roster out of a single silhouette family.
The original eight all borrow their outline from "military vehicle", which is
why they read as variations rather than as a kitbash. Each hull here steals its
silhouette from a domain that is obviously NOT a tank - a capital ship, a
submarine, a sports car, a helicopter, a steam locomotive, a landing craft, a
water tower, a delivery truck - and relies on the player bolting tracks or
rotors to it via the locomotion module, which module_catalog.gd already allows
on any hull ("A player can put treads on a naval hull if...").

Run from the prototype/ directory:

    python tools/gen_kitbash_hulls.py

then bake with:

    ./godot.exe --headless --script res://tools/bake_hull_roster.gd -- <ids>

PRIMITIVE FACTS, measured empirically against csg_mesh_baker.gd rather than
assumed (a wedge pointing the wrong way is invisible in an AABB check, so these
were verified by slicing baked unit primitives):

  * `scale` is FULL extents; the baker halves it internally.
  * `rotation` is RADIANS, fed straight to Basis.from_euler (Godot's YXZ order).
  * -Z is forward, matching every existing hull.
  * WEDGE   full height at -Z, tapering to zero at +Z. A bow-forward wedge
            therefore needs rotation [0, pi, 0].
  * SLOPE   full height at +Z, cut down toward -Z. Correct for a glacis, a
            car hood, or a bow ramp with NO rotation.
  * FRUSTUM tapers along Y, wide at -Y. rotation [pi, 0, 0] inverts it for a
            narrow-bottomed hopper.
  * HALF_CYLINDER  axis Z, flat bottom, domed top. rotation [0, pi/2, 0] turns
            the axis to X, which is what makes a wheel arch.
  * CANOPY / HEMISPHERE  dome sitting on its own floor, apex at the ceiling.
  * RING    square-section washer in XZ, inner radius 0.6 * outer, thickness
            taken from scale.y.
  * CYLINDER  axis Y. rotation [pi/2, 0, 0] lays it along Z.
  * HEX_PRISM axis Z.
  * FENDER is deliberately unused: a 2x2x2 request bakes to (2.6, 0.6, 1.3) -
            a flat half-washer lying in XZ, not the vertical wheel arch the
            name suggests. HALF_CYLINDER does that job predictably.
"""

import json
import math
import os

PI = math.pi
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(HERE), "data", "hull_assemblies")


def prim(ptype, pos, scale, color, note, rot=(0.0, 0.0, 0.0)):
    return {
        "_note": note,
        "type": ptype,
        "position": [round(v, 4) for v in pos],
        "rotation": [round(v, 6) for v in rot],
        "scale": [round(v, 4) for v in scale],
        "color": list(color) + [1],
    }


# Per-hull edge treatment. Part of selling "kitbash": a factory-sharp capital
# ship next to a rounded industrial tank reads as parts from different kits,
# where a roster at a uniform 5.0 reads as one coherent product line.
HULLS = {}


# ---------------------------------------------------------------- 1. WEDGE ---
HULLS["dreadnought_wedge_hull"] = dict(
    role=(
        "Capital-ship wedge (Star Destroyer register). The single most useful "
        "hull shape in the roster mechanically, not just visually: a wedge is "
        "all flat dorsal deck, which is exactly what module mounting and decal "
        "projection both want. Bow tapers to a point, stern carries the full "
        "height and the superstructure."
    ),
    size=[5.0, 1.85, 9.0],
    chamfer=2.0,       # factory-sharp - this thing was built in a shipyard
    resolution=36,
    stats=dict(hp=900, weight=700, metal=230, crystal=55, base_energy=125, base_vision=22),
    color=[0.60, 0.62, 0.66],
    prims=[
        prim("WEDGE", (0, -0.15, 0), (5.0, 1.5, 9.0), (0.60, 0.62, 0.66),
             "Main hull. Rotated pi about Y so the full height sits at the STERN and "
             "the bow tapers to a point - an unrotated WEDGE is tall at -Z, i.e. "
             "backwards for a ship. Note the consequence: the top surface runs from "
             "y=+0.6 at the stern down to y=-0.9 at the bow, so anything mounted on "
             "the 'deck' at a constant height only touches the hull aft of where the "
             "slope reaches it. A flat plate at y=+0.35 floated free of the entire "
             "hull for exactly this reason.", rot=(0, PI, 0)),
        prim("BOX", (0, -0.3, 0.5), (4.2, 0.8, 6.0), (0.57, 0.59, 0.63),
             "Midships hull block. Rides low enough to stay inside the wedge's sloping "
             "top over its whole length, which is what ties the superstructure to the "
             "hull instead of leaving it hovering."),
        prim("BOX", (0, 0.1, 2.1), (3.0, 0.6, 4.8), (0.52, 0.54, 0.59),
             "Aft superstructure. Its flat top is the module real estate - the wedge "
             "itself cannot provide one, since its deck is a slope."),
        prim("CHAMFER_BOX", (0, 0.6, 3.4), (1.4, 0.6, 1.6), (0.46, 0.48, 0.54),
             "Bridge tower, the silhouette's signature."),
        prim("BOX", (-1.4, -0.78, 1.6), (0.5, 0.3, 5.4), (0.44, 0.45, 0.5),
             "Port ventral rail. Kept aft: the wedge collapses to a knife edge at "
             "y=-0.9 near the bow, so a rail carried forward would stick out below it."),
        prim("BOX", (1.4, -0.78, 1.6), (0.5, 0.3, 5.4), (0.44, 0.45, 0.5),
             "Starboard ventral rail."),
    ],
)


# ------------------------------------------------------------ 2. SUBMARINE ---
HULLS["pressure_hull"] = dict(
    role=(
        "Submarine pressure hull, run on land because nothing here is "
        "underwater. The dorsal casing is not decoration: a bare cylinder has "
        "almost no flat area for module mounts, and a real submarine's flat "
        "walking casing solves the realism and the mounting problem with the "
        "same part."
    ),
    size=[2.8, 3.3, 11.55],
    chamfer=6.0,
    resolution=60,     # rounded body needs the facet count
    stats=dict(hp=700, weight=520, metal=180, crystal=40, base_energy=110, base_vision=20),
    color=[0.30, 0.33, 0.36],
    prims=[
        prim("CAPSULE", (0, -0.3, 0), (2.6, 2.6, 11.0), (0.30, 0.33, 0.36),
             "Pressure hull proper - one long tapered cigar."),
        prim("BOX", (0, 0.9, -0.5), (1.5, 0.5, 8.4), (0.26, 0.28, 0.31),
             "Flat dorsal casing / walking deck. The mounting surface."),
        prim("CHAMFER_BOX", (0, 1.3, 1.4), (1.2, 0.7, 2.2), (0.22, 0.24, 0.27),
             "Conning tower / sail."),
        prim("RING", (0, -0.3, -2.2), (2.8, 0.3, 2.8), (0.38, 0.4, 0.42),
             "Forward hull band."),
        prim("RING", (0, -0.3, 2.6), (2.8, 0.3, 2.8), (0.38, 0.4, 0.42),
             "Aft hull band."),
        prim("CYLINDER", (0, -0.3, 5.2), (0.5, 1.4, 0.5), (0.5, 0.44, 0.3),
             "Propeller shaft fairing. Rotated pi/2 about X so CYLINDER's Y axis "
             "runs fore-aft along Z.", rot=(PI / 2, 0, 0)),
    ],
)


# -------------------------------------------------------------- 3. ROADSTER ---
HULLS["roadster_hull"] = dict(
    role=(
        "Sports car. Fast, fragile, and deliberately too low to carry a "
        "sensible weapon - anything mounted on it will read as comically "
        "oversized, which is the joke. Scout-tier stats to match."
    ),
    size=[2.5, 1.05, 4.85],
    chamfer=12.0,      # soft, pressed-panel bodywork
    resolution=48,
    stats=dict(hp=150, weight=70, metal=38, crystal=12, base_energy=40, base_vision=28),
    color=[0.62, 0.16, 0.14],
    prims=[
        prim("CHAMFER_BOX", (0, -0.25, 0.1), (2.3, 0.7, 4.6), (0.62, 0.16, 0.14),
             "Lower body tub."),
        prim("SLOPE", (0, 0.05, -1.5), (2.1, 0.5, 1.7), (0.66, 0.2, 0.16),
             "Long hood. SLOPE cuts down toward -Z unrotated, which is exactly a "
             "forward-raking bonnet."),
        prim("CANOPY", (0, 0.1, 0.5), (1.7, 0.55, 2.0), (0.2, 0.22, 0.26),
             "Greenhouse, dark so it reads as glass rather than body colour."),
        prim("HALF_CYLINDER", (0, 0.0, 1.7), (1.9, 0.5, 1.6), (0.58, 0.14, 0.12),
             "Fastback rear deck."),
        prim("HALF_CYLINDER", (-1.0, -0.35, -1.5), (0.8, 0.55, 0.5), (0.18, 0.18, 0.2),
             "Front left wheel arch. Rotated pi/2 about Y to swing HALF_CYLINDER's "
             "Z axis across the car.", rot=(0, PI / 2, 0)),
        prim("HALF_CYLINDER", (1.0, -0.35, -1.5), (0.8, 0.55, 0.5), (0.18, 0.18, 0.2),
             "Front right wheel arch.", rot=(0, PI / 2, 0)),
        prim("HALF_CYLINDER", (-1.0, -0.35, 1.5), (0.9, 0.6, 0.5), (0.18, 0.18, 0.2),
             "Rear left wheel arch, deliberately larger than the front.", rot=(0, PI / 2, 0)),
        prim("HALF_CYLINDER", (1.0, -0.35, 1.5), (0.9, 0.6, 0.5), (0.18, 0.18, 0.2),
             "Rear right wheel arch.", rot=(0, PI / 2, 0)),
    ],
)


# ------------------------------------------------------------ 4. HELICOPTER ---
HULLS["rotor_fuselage_hull"] = dict(
    role=(
        "Helicopter fuselage. Pair it with helicopter_rotors and it stops "
        "being a gag and becomes coherent. Caveat by design: the tail boom "
        "pushes the bounding box far aft while contributing almost no "
        "mountable or projectable surface, so treat the boom as decoration "
        "and the cabin as the real estate."
    ),
    size=[2.2, 2.55, 9.45],
    chamfer=8.0,
    resolution=48,
    stats=dict(hp=380, weight=210, metal=90, crystal=35, base_energy=100, base_vision=27),
    color=[0.28, 0.34, 0.28],
    prims=[
        prim("CHAMFER_BOX", (0, 0, -1.6), (2.2, 1.8, 3.6), (0.28, 0.34, 0.28),
             "Cabin - the only part of this hull with real mounting area."),
        prim("CANOPY", (0, -0.2, -3.5), (2.0, 1.4, 1.8), (0.2, 0.24, 0.28),
             "Bubble nose glazing."),
        prim("BOX", (0, 0.85, -0.4), (1.4, 0.5, 2.4), (0.24, 0.29, 0.24),
             "Engine deck."),
        prim("CYLINDER", (0, 1.2, -1.4), (0.45, 0.7, 0.45), (0.4, 0.4, 0.42),
             "Rotor mast."),
        prim("BOX", (0, 0.35, 2.2), (0.55, 0.55, 5.2), (0.26, 0.31, 0.26),
             "Tail boom."),
        prim("FRUSTUM", (0, 0.95, 4.3), (0.35, 1.2, 1.4), (0.24, 0.29, 0.24),
             "Vertical stabiliser. FRUSTUM is wide at -Y, so unrotated it tapers "
             "upward like a fin."),
        prim("BOX", (-0.85, -0.82, -1.6), (0.22, 0.34, 3.0), (0.35, 0.35, 0.37),
             "Port landing skid. Raised and deepened: at y=-1.0 x 0.18 thick its top "
             "sat at -0.91 against a cabin floor of -0.90, a 0.01 gap, so both skids "
             "baked as free-floating components."),
        prim("BOX", (0.85, -0.82, -1.6), (0.22, 0.34, 3.0), (0.35, 0.35, 0.37),
             "Starboard landing skid."),
    ],
)


# ------------------------------------------------------------ 5. LOCOMOTIVE ---
HULLS["locomotive_hull"] = dict(
    role=(
        "Steam locomotive. The strongest instant read of anything in the "
        "roster and almost trivially simple to author - a boiler, a cab, and a "
        "stack is all the silhouette needs."
    ),
    size=[2.8, 3.45, 8.9],
    chamfer=4.0,
    resolution=48,
    stats=dict(hp=820, weight=760, metal=240, crystal=30, base_energy=120, base_vision=17),
    color=[0.18, 0.18, 0.2],
    prims=[
        prim("CYLINDER", (0, 0.1, -1.2), (2.2, 6.2, 2.2), (0.18, 0.18, 0.2),
             "Boiler. Rotated pi/2 about X so the cylinder axis runs fore-aft.",
             rot=(PI / 2, 0, 0)),
        prim("BOX", (0, 0.6, 2.9), (2.6, 2.9, 2.8), (0.3, 0.14, 0.12),
             "Cab, in oxide red so it reads as a separate donor part. Deepened so it "
             "overlaps the running board by a real margin - at the original height the "
             "two met with a 0.05 sliver and the cab baked as its own component."),
        prim("HALF_CYLINDER", (0, 1.9, 2.9), (2.7, 0.6, 2.7), (0.24, 0.11, 0.1),
             "Arched cab roof."),
        prim("CYLINDER", (0, 1.4, -3.2), (0.7, 1.6, 0.7), (0.14, 0.14, 0.15),
             "Smokestack."),
        prim("CYLINDER", (0, 1.15, -0.4), (0.9, 0.7, 0.9), (0.45, 0.4, 0.2),
             "Steam dome, brass."),
        prim("BOX", (0, -0.9, -0.4), (2.8, 0.3, 7.6), (0.22, 0.22, 0.24),
             "Running board / footplate."),
        prim("SLOPE", (0, -0.75, -4.0), (2.4, 0.9, 1.2), (0.26, 0.26, 0.28),
             "Pilot / cowcatcher."),
    ],
)


# --------------------------------------------------------- 6. LANDING CRAFT ---
HULLS["landing_craft_hull"] = dict(
    role=(
        "Landing craft. The utility counterpart to the dreadnought wedge - an "
        "enormous open deck between two gunwales, so it carries more modules "
        "than anything else its weight."
    ),
    size=[4.3, 2.4, 8.7],
    chamfer=3.0,
    resolution=36,
    stats=dict(hp=520, weight=400, metal=150, crystal=25, base_energy=95, base_vision=19),
    color=[0.38, 0.4, 0.34],
    prims=[
        prim("BOX", (0, -0.4, 0.4), (4.2, 1.2, 7.4), (0.38, 0.4, 0.34),
             "Hull tub."),
        prim("SLOPE", (0, -0.35, -3.7), (3.8, 1.3, 1.6), (0.42, 0.44, 0.38),
             "Bow ramp."),
        prim("BOX", (0, 0.05, 0.2), (3.6, 0.4, 6.4), (0.34, 0.35, 0.3),
             "Open deck floor - the mounting surface. Thickened and dropped so it "
             "genuinely interpenetrates the tub rather than resting on it."),
        prim("BOX", (-1.95, 0.3, 0.4), (0.4, 1.0, 7.0), (0.32, 0.33, 0.28),
             "Port gunwale. Widened to 0.4 so its outer face is NOT coplanar with the "
             "tub's - two exactly-coincident face planes are what split this hull into "
             "three disconnected shells on the first bake."),
        prim("BOX", (1.95, 0.3, 0.4), (0.4, 1.0, 7.0), (0.32, 0.33, 0.28),
             "Starboard gunwale."),
        prim("CHAMFER_BOX", (0, 0.7, 3.4), (1.6, 1.4, 1.4), (0.28, 0.3, 0.26),
             "Aft wheelhouse."),
        prim("BOX", (0, 0.1, 3.9), (3.0, 0.7, 0.6), (0.3, 0.26, 0.22),
             "Stern engine box."),
    ],
)


# ----------------------------------------------------------- 7. WATER TOWER ---
HULLS["water_tower_hull"] = dict(
    role=(
        "Water tower / grain silo on a chassis. Vertical, which nothing else "
        "in the roster is, and absurd in exactly the right way. Tall and "
        "top-heavy on purpose."
    ),
    size=[3.2, 4.35, 4.2],
    chamfer=14.0,      # rolled and welded industrial plate, not machined
    resolution=48,
    stats=dict(hp=600, weight=480, metal=170, crystal=20, base_energy=85, base_vision=16),
    color=[0.52, 0.5, 0.44],
    prims=[
        prim("CYLINDER", (0, 0.6, 0), (3.0, 3.0, 3.0), (0.52, 0.5, 0.44),
             "Main tank."),
        prim("CANOPY", (0, 2.1, 0), (3.0, 0.9, 3.0), (0.46, 0.44, 0.39),
             "Domed lid."),
        prim("FRUSTUM", (0, -0.6, 0), (3.0, 1.0, 3.0), (0.48, 0.46, 0.41),
             "Conical hopper bottom. Rotated pi about X to invert FRUSTUM's default "
             "wide-at-the-bottom taper into a narrow-bottomed funnel.", rot=(PI, 0, 0)),
        prim("BOX", (0, -1.4, 0), (3.2, 0.8, 4.2), (0.3, 0.3, 0.32),
             "Chassis skid the whole thing is bolted to."),
        prim("RING", (0, 1.6, 0), (3.2, 0.25, 3.2), (0.36, 0.35, 0.32),
             "Upper reinforcing hoop."),
        prim("BOX", (1.4, 0.6, -1.5), (0.25, 3.0, 0.25), (0.34, 0.33, 0.3),
             "External ladder / standpipe."),
        prim("HEX_PRISM", (0, 0.9, -1.6), (0.9, 0.9, 0.6), (0.4, 0.38, 0.34),
             "Access hatch. HEX_PRISM extrudes along Z, so unrotated it faces "
             "forward like a bolted-on plate."),
    ],
)


# --------------------------------------------------------- 8. CABOVER TRUCK ---
HULLS["cabover_truck_hull"] = dict(
    role=(
        "Cab-over delivery truck. Reads as a civilian vehicle pressed into "
        "service, a different flavour of kitbash from the sci-fi donors - flat "
        "nose, tall cab, open cargo bed behind."
    ),
    size=[2.8, 2.8, 7.8],
    chamfer=5.0,
    resolution=36,
    stats=dict(hp=340, weight=240, metal=100, crystal=18, base_energy=75, base_vision=21),
    color=[0.2, 0.34, 0.46],
    prims=[
        prim("CHAMFER_BOX", (0, 0.35, -2.5), (2.7, 2.2, 2.4), (0.2, 0.34, 0.46),
             "Flat-nosed cab sitting over the front axle - the cab-over signature."),
        prim("HALF_CYLINDER", (0, 1.4, -2.5), (2.5, 0.5, 2.2), (0.17, 0.29, 0.4),
             "Roof fairing."),
        prim("BOX", (0, -0.85, 0.2), (2.4, 0.5, 7.2), (0.24, 0.24, 0.26),
             "Chassis frame rails."),
        prim("BOX", (0, -0.5, 1.8), (2.7, 0.25, 4.2), (0.4, 0.34, 0.24),
             "Cargo bed floor, timber-toned against the painted cab."),
        prim("BOX", (-1.3, -0.05, 1.8), (0.2, 0.9, 4.2), (0.36, 0.31, 0.22),
             "Left bed side."),
        prim("BOX", (1.3, -0.05, 1.8), (0.2, 0.9, 4.2), (0.36, 0.31, 0.22),
             "Right bed side."),
        prim("BOX", (0, -0.05, -0.25), (2.7, 0.9, 0.2), (0.36, 0.31, 0.22),
             "Headboard behind the cab."),
        prim("BOX", (0, -0.7, -3.75), (2.8, 0.4, 0.3), (0.3, 0.3, 0.32),
             "Front bumper."),
    ],
)


def pretty_name(hull_id):
    return " ".join(w.capitalize() for w in hull_id.replace("_hull", "").split("_")) + " Hull"


NAME_OVERRIDES = {
    "pressure_hull": "Pressure Hull",
    "dreadnought_wedge_hull": "Dreadnought Wedge",
    "roadster_hull": "Roadster Hull",
    "rotor_fuselage_hull": "Rotor Fuselage",
    "locomotive_hull": "Locomotive Hull",
    "landing_craft_hull": "Landing Craft Hull",
    "water_tower_hull": "Water Tower Hull",
    "cabover_truck_hull": "Cabover Truck Hull",
}


def build(hull_id, spec):
    sidecar = {"name": NAME_OVERRIDES.get(hull_id, pretty_name(hull_id))}
    sidecar.update(spec["stats"])
    sidecar["size"] = spec["size"]
    sidecar["color"] = list(spec["color"]) + [1]
    return {
        "schema_version": 1,
        "hull_name": hull_id,
        "_role": spec["role"],
        "bake": {
            "smoothness": 0.0,
            "resolution": spec["resolution"],
            "method": "csg",
            "fit_percent": 95,
            "facet_angle": 15,
            "crystallinity": 0.0,
            "chamfer_edge_pct": spec["chamfer"],
            "mirror_x": False,
        },
        "sidecar": sidecar,
        "primitives": spec["prims"],
    }


def main():
    for hull_id, spec in HULLS.items():
        path = os.path.join(OUT_DIR, hull_id + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(build(hull_id, spec), f, indent="\t")
            f.write("\n")
        print("wrote %s (%d primitives)" % (path, len(spec["prims"])))


if __name__ == "__main__":
    main()
