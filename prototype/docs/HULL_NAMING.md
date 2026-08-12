# Vehicle hull catalogue

81 vehicle hulls from 8 fictional manufacturers, across 6 classes. Built by
[`tools/blender/build_vehicle_hulls.py`](../tools/blender/build_vehicle_hulls.py)
on the geometry core in
[`tools/blender/hull_forge.py`](../tools/blender/hull_forge.py).

```bash
cd prototype
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python tools/blender/build_vehicle_hulls.py
```

Then reimport so Godot writes the `.import` sidecars:

```bash
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import
```

Useful flags after a `--` separator: `--list` (print the lineup and exit),
`--only <id>[,<id>]` (rebuild a subset), `--out <dir>` (write elsewhere).

## Naming

    <manufacturer>_<class>_<variant>

Three segments, lowercase snake_case (`HullLoader` rejects anything else).
`brenntal_medium_a` is the Brenntal Schwerbau, Medium class, variant A hull.

## Manufacturers (8)

The manufacturer owns the **body structure**. This is the primary axis of
difference, and it is structural rather than decorative: two hulls from
different houses share no body builder, no cross-section vocabulary and no
silhouette. There is no "same hull in a different livery" anywhere here.

| Slug | House | Body structure | Cue at distance |
|---|---|---|---|
| `halvorsen` | Halvorsen Yard | Hard-chine boat section: wide flat deck, near-vertical topsides, one hard horizontal chine crease, steep deadrise panels down to a narrow flat keel | A raked stem and a continuous raised bulwark rim around the deck. A boat dragged ashore. |
| `kestrel` | Kestrel Aeroworks | Faceted eight-sided fuselage tube with a flat cargo floor, stepping down in one jump to a narrower tail boom | Vertical tail fin, angular canopy riding high at the nose, thick wing-root stubs where the spar used to carry through |
| `brenntal` | Brenntal Schwerbau | Stacked orthogonal blocks with no taper anywhere: wide low plinth, narrower casemate offset rearward | One enormous frontal glacis plate, plus full-length sponson shoulders that set the vehicle's width |
| `tallow` | Tallow & Vance | Open spaceframe. Barely a body at all - a chassis rail, four thick corner posts, open deck | Cab jammed against the front bumper, rear two-thirds left as flatbed framed by rails and thick transverse beams |
| `orrin` | Orrin Collective | Bilaterally symmetric tumblehome hull. Cross-section is wider at the bottom (flat underside) and narrower at the top (naval-architecture end-on silhouette) | Symmetric front-to-rear, with a centered dorsal ridge or tall sensor mast integrated as a cross-section peak |
| `rackham` | Rackham Forge | Industrial crawler. Stout octagonal body, exposed boiler barrel on top, deep front radiator grille, full-length side rails at deck level | The boiler + smokestack silhouette, plus the tall front grille |
| `calder` | Calder Mobility | Fast-attack wedge. Body cross-section widens and shortens as z moves aft, narrow nose to full-width tail | Side sponsons bulge out of the mid-z range; small rear wing on top |
| `pillar` | Pillar Ironworks | Modular boxy. Body is a stack of chamfered rectangular cells (one cell = 1.0 hull-height cubed) | Combat variants are solid stacks with a visible cell seam; transport variants are two parallel cell walls with an open flatbed well between them |

Colours in the `.glb` are Blender-preview only - `hull_material_builder.gd`'s
`apply_hull_materials()` replaces both material slots at runtime.

## Classes (6)

The class owns the **proportions** and the large role element bolted onto the
manufacturer's body. It is written into every sidecar as `hull_class`.

| Class | Envelope band (W x H x L) | Role read |
|---|---|---|
| `scout` | 2.2-2.7 x 0.95-1.4 x 3.9-4.9 | Low and short, often a tall sensor mast |
| `light` | 2.8-3.2 x 0.95-1.3 x 4.8-5.9 | Compact, minimal superstructure |
| `medium` | 3.3-3.8 x 1.15-1.85 x 5.7-6.5 | Balanced; barbette or stepped bridge |
| `heavy` | 4.0-5.1 x 1.4-2.2 x 7.1-8.3 | Widest, extra glacis, armour shoulders |
| `transport` | 3.7-4.3 x 1.25-2.1 x 7.7-9.1 | Flatbed, cargo well, or trunk deck |
| `oddball` | wild | The house's weirdest structural idea |

## The lineup is deliberately unbalanced

Manufacturers are not required to cover every class evenly, and none does.
A house that focuses on heavies has fewer scouts; a house that does
transports at every size has those instead.

| | scout | light | medium | heavy | transport | oddball | total |
|---|---|---|---|---|---|---|---|
| `halvorsen` | 1 | 2 | 2 | 3 | 3 | 2 | **13** |
| `kestrel` | 3 | 3 | 2 | 1 | 1 | 2 | **12** |
| `brenntal` | 1 | 1 | 3 | 4 | 2 | 2 | **13** |
| `tallow` | 1 | 2 | 2 | 2 | 4 | 1 | **12** |
| `orrin` | 2 | 1 | 1 | 1 | 1 | 2 | **8** |
| `rackham` | 1 | 2 | 2 | 2 | 1 | 0 | **8** |
| `calder` | 2 | 3 | 2 | 1 | 0 | 0 | **8** |
| `pillar` | 0 | 0 | 2 | 2 | 3 | 0 | **7** |
| | 11 | 14 | 16 | 16 | 15 | 9 | **81** |

Brenntal and Halvorsen carry the heavy end. Tallow owns transports at
every weight class. Kestrel skews small and fast. Calder is light/medium
attack. Rackham is industrial mid-tier. Pillar is modular transport/heavy.
Orrin is mostly oddballs.

Four hulls are `domain: "Naval"` - `halvorsen_light_b`,
`halvorsen_transport_b`, `halvorsen_oddball_a` and `kestrel_oddball_b` -
covering the range the retired `skiff_*` family used to.

## Single-mesh build

Every body function builds ONE bmesh and exports it as one GLB. The
structural features (cabs, casemates, sponsons, outriggers, wheel arches,
glacis plates) are part of the cross-section's evolution as z progresses,
not bolted-on chamfered boxes glued to the main body.

**The cross-section has a fixed vertex count at every z** (so the loft
between sections is well-defined). Features that are only present in
some z range have their vertices positioned at the "inactive" location
outside the range, and at the "active" location inside, with smooth
transitions in between. As z sweeps along the hull, the cross-section
shape naturally morphs and the features grow out of the body.

**The bottom of the cross-section is always at `y = -h/2`** (the hull's
underside). Locomotion mounts at the underside therefore work on every
hull uniformly, regardless of body shape - the locomotion layout is
AABB-anchored, and the AABB bottom is the underside line.

**The front of the hull rises out of the flat underside as a sloped
face** (a glacis), not as a dropping keel. Nose drops are small, kept
under 0.3*h, so a Halvorsen or Brenntal bow never reaches below the
underside plane.

**Non-convex cross-sections are supported.** A non-convex outline
happens when a hull's cross-section is a single closed polygon that
includes all the structural features as part of the outline (e.g. the
T-shape of a Brenntal plinth + casemate, where the wider plinth
shoulders and the narrower casemate are both part of the outline).
`hull_forge.add_solid()` triangulates quads that fail to create, so a
T-shape with real plinth shoulders produces a closed, single-mesh
surface.

**Role elements** (masts, fins, ridges, flatbeds, wells, trunks) stay as
separate `add_chamfered_box()` / `add_ridge()` in the same bmesh for
most manufacturers. They are small thin features on top of the body,
and treating them as part of the cross-section would force the outline
to carry a tall vertical spike for a small mast, distorting the rest of
the silhouette.

The **prominent greebles** (masts, dorsal spines, barbettes) are now
**integrated into the hull as cross-section peaks** for the houses where
they read as part of the body — Orrin (spine + mast), Kestrel (spine),
Rackham (mast), Calder (barbette), Pillar (barbette). Each peak is a
4-vertex mesa bump on top of the chassis, active only in a small z
range, with the peak vertices held in the outline at every z (collapsed
to a flat segment on the deck when not active) so the cross-section
point count stays constant for the loft. This kills the "floating
detail" look — the peak grows out of the body rather than being a
separate `add_chamfered_box()` sitting on top.

The Orrin house is **bilaterally symmetric AND tumblehome**. The
cross-section is a trapezoid: wider at the bottom (flat underside, full
width), narrower at the top (`mass_w * tumblehome_frac`, default 0.80).
The tumblehome slope from bottom to top is part of the outline, not a
post-process. The hull's AABB is still centered on X, so locomotion
mounts on either side hit the same surface.

## Art direction constraints

Enforced by construction in `hull_forge.py`, not by review:

- **Blocky, chamfered, angled flat facets, no curves.** Every solid is a loft
  through explicit polygonal cross-sections. Chamfers come from the outlines
  themselves plus an auto-inserted inset section at each cap, so all edges
  are chamfered without a single `bmesh.ops.bevel` call - no clamp-overlap
  surprises and a predictable facet count. The module has no circle, sphere
  or cylinder primitive to reach for.
- **Flat shading**, deliberately. Every surface is a genuine planar facet
  meeting its neighbours at a hard angle, and smooth shading averages exactly
  those normals away - a chamfered octagonal prism shades as a cylinder. Note
  for anyone reaching for `mesh.use_auto_smooth` to limit it: that property
  was **removed in Blender 4.1**. Assigning it raises, and if the raise is
  swallowed by a `try`/`except` the hull exports fully smoothed and the whole
  catalogue renders as rounded blobs.
- **No small greebling.** No rivets, no panel lines, no bolt rings. Role is
  read from whole structures at hull scale - spinal ridges, outriggers,
  flatbeds, barbettes, gantries, bow ramps, corner buttresses.

## Orientation and winding

**Forward is local -Z.** That is Godot's own convention and the engine relies
on it: `unit.gd:706` steers along `-transform.basis.z`, `auto_weapon.gd:571`
fires along it, and `classify_facet()` classifies armour facets against it. A
hull's nose is authored at negative Godot Z and lands there in game.

The Blender-to-Godot axis chain was **measured, not assumed** - see
`scratch/hull_probe/`, which exports markers on all six raw-Blender half-axes
and reads the `.glb` back through Godot's own `GLTFDocument`:

| raw Blender | Godot |
|---|---|
| +X | +X (right) |
| +Y | **-Z (forward / nose)** |
| +Z | +Y (up) |

So `Blender = (Gx, -Gz, Gy)`, which is `hull_forge.BV()`. Its determinant is
**+1** - a rotation, so winding survives it untouched. Do not "simplify" it to
a bare axis swap like `(x, z, y)`: that is a reflection and it inverts face
winding.

That is not hypothetical. The catalogue this replaces authored through exactly
such a swap and then applied a *second* determinant -1 matrix to correct the
orientation, with `recalc_face_normals` running between the two. Two
reflections cancel for vertex positions but not for winding, so every
procedurally-built hull shipped **inside out** - near faces invisible, far
interior visible. `build_meshes.py`'s `generate_hulls()` is retired and now
raises rather than regenerate them.

Two checks guard this, both runnable:

```bash
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --headless --path . --script ../scratch/hull_probe/verify_winding.gd -- <glb> [<glb> ...]
```

```bash
cd prototype && ./Godot_v4.7.1-stable_win64_console.exe --path . --script tools/render_hull_sheet.gd -- sheet.png --cols 6 --cell 340x255
```

The first is numeric, the second visual - an inside-out hull renders as a
hollow shell and there is no mistaking it. `render_hull_sheet.gd` needs a real
rendering device, so it must run **without** `--headless`.

`verify_winding.gd` is calibrated rather than theorised: it does not assume
which sign means "outward". Run it over an asset that renders correctly and one
that renders inside out, and the two disagree. New hulls must match the
known-good sign.

| Asset | top.y | bottom.y | nose.z |
|---|---|---|---|
| `aa_barrel` (renders correctly) | -1.000 | +1.000 | +1.000 |
| `pod_heavy_osterholm` (was inside out) | +0.979 | -0.979 | -1.000 |
| all 81 current hulls | negative | positive | positive |

## Sizes, stats and the envelope

The sidecar's `size` is **exact**. `autofit()` solves for the working size
whose natural AABB lands on the declared envelope - masts, fins, gantries and
bulwarks all reach past the body they sit on - and `HF.normalize()` finishes
the job with a positive-determinant scale. Every hull in the lineup normalizes
at exactly 1.000 on all three axes.

This matters because `write_sidecar()` derives `hp`, `weight`, `metal` and
`crystal` from volume using `bake_custom_hull.py`'s formula, so the class bands
have to mean something. Letting a tall sensor mast inflate a scout's envelope
by 60% would hand it a heavy's stat line. Resulting spread: scouts ~280-440 hp,
light ~390-500, medium ~580-960, heavy and transport ~1000-1840.

`visual_yaw_offset_deg` / `visual_pitch_offset_deg` /
`visual_roll_offset_deg` are written explicitly as `0`. That makes
`ModuleCatalog.has_explicit_hull_orientation()` true and **skips the
aspect-ratio orientation search entirely**. That search exists to rescue hulls
whose `.glb` was authored along the wrong axis; these are authored correctly
and verified in Godot, so letting a heuristic guess at them could only make
things worse.

### Adding a hull

1. Add a row to `LINEUP` in `build_vehicle_hulls.py`.
2. Keep every element's **vertical extent a function of `h` alone**. Deriving
   it from `w` makes the `autofit()` solve non-convergent, and `HF.normalize()`
   raises with the offending axis and factor rather than quietly squashing the
   hull. Both `el_barbette` and `el_gantry` had this bug.
3. Rebuild, reimport, then run both checks above.

## Default hull

`brenntal_medium_a` - the plainest two-tier casemate in the catalogue, which is
what a fallback should be. 7+ scripts hardcode it as their safe fallback hull,
and `PROTECTED_DEFAULT_HULL_FALLBACK` in
[`scripts/hull_loader.gd`](../scripts/hull_loader.gd) carries an embedded copy
of its sidecar for the case where that file goes missing or fails validation.
**Keep those numbers in sync by hand** if the hull's design envelope changes.

`kestrel_scout_a` is the corresponding scout-tier default.

## Production tier

`ModuleCatalog.get_hull_size_tier()` derives the manufactory production tier
from the declared `hull_class`, falling back to weight breakpoints only for mod
hulls that declare no class:

| Classes | Tier |
|---|---|
| `scout`, `light` | `light` |
| `medium` | `medium` |
| `heavy`, `transport`, `oddball` | `heavy` |

It used to be weight-only, with breakpoints picked to split a 12-mobile-hull
catalogue into even thirds. That catalogue is long gone and the breakpoints did
not survive it: every hull here outweighs the old 150 "light" ceiling, so
nothing would have been light and almost everything would have been heavy. The
concrete symptom was `brenntal_medium_a` - the baseline medium - tiering as
HEAVY and handing every default harvester a 1.5x hopper.

## Foundations are a separate taxonomy

The 13 static defenses (`bunker_*`, `tower_*`, `rampart_*`, `battery_*`) are
`is_foundation: true`, are named `<family>_main_<manufacturer>`, and still come
from `build_meshes.py`'s `generate_foundations()`. They were never built through
the retired `generate_hulls()` path and this catalogue does not touch them.

## What was retired

All 30 shipped hulls of the `<family>_<tonnage>_<manufacturer>` catalogue - the
6 families (`block`, `wedge`, `plate`, `pod`, `carrier`, `skiff`) x 3 tonnages
(`scout`, `main`, `heavy`) x 3 manufacturers (`meridian`, `osterholm`,
`tidemark`) matrix. Plus 10 of the 12 single-house `<house>_<class>_<variant>`
Orrin hulls (kept the 8 that fit the new symmetric vocabulary, dropped
`orrin_oddball_c` and `orrin_oddball_d` whose asymmetric outrigger-on-strut
silhouette was the structural feature that broke locomotion mounts).

The 60-hull catalogue was replaced rather than repaired for two reasons. The
mesh problem: every procedurally-built hull in it was inside out. The design
problem: the three houses read as the same vehicle in different paint, because
the *family* axis rather than the manufacturer owned the silhouette, and a
single `convex_hull` call over body-plus-signature erased whatever structure
the signature added.

Reference migration: `block_main_meridian` -> `brenntal_medium_a`, and
`block_scout_meridian` -> `kestrel_scout_a`.
