# Hull Massing Spec (from design research, 2026-07-16)

**Audience:** whoever implements the next hull-geometry pass directly in `prototype/tools/blender/build_meshes.py`.

**Problem this addresses:** Chris looked at the current hulls — even with the bold new faction textures — and they still read as "a beveled box with detail applied on top," not an assembled machine. The Tier 1/2/3 work (tiered bevel, eased taper, waist-inset, deck-line step, panel grooves, the few Tier-3 bespoke cuts) is real, but it is all *refinement of one convex-hull-derived silhouette*. Every hull class is fundamentally `taper_profile()` loft → `convex_hull` → `bevel_sharp_edges` → greebles. The base massing is the same shape everywhere; only the parameters differ.

## The core structural insight

A `bmesh.ops.convex_hull()` over a single point cloud **can never produce a re-entrant (concave) silhouette**. Any point placed "inside" the hull of its neighbours is silently discarded (this is already documented in `add_waist_inset`'s comment). That is the mathematical reason every hull reads as one convex blob: the primary massing operation *cannot* express "a lower hull tub AND a separate, narrower upper glacis with a real step between them." Bevel/taper tuning cannot fix a limitation that lives in the choice of construction primitive.

There are exactly **two proven, no-boolean ways** in this codebase to get genuine multi-volume massing, and we should lean on both:

1. **Multiple interpenetrating convex hulls / fused primitives in one `bm`.** `build_tower_hull()` already does this today: it calls `bmesh.ops.convex_hull()` **once per tier** into the same `bm`, producing several independent closed shells that visually overlap but are never boolean-unioned. Each shell is independently manifold, so there is zero non-manifold risk — the interpenetration is invisible because we only ever see these opaque meshes from outside. `build_sponson_hull()` likewise fuses `add_box` blisters onto a core hull. **This is the single most important technique to generalize.** A "tank" is a lower tub hull (one convex hull) + an upper glacis/casemate volume (a second convex hull, narrower and set back) + fender/sponson shelves (fused boxes) — three volumes, not one loft.

2. **`bisect_plane` + selective vertex shift** for concave *notches and pockets* on an existing shell (waist-inset, deck-line step, panel groove, speed-line chamfer all already do this). Good for recesses (louver pockets, embrasures, shot-traps) but **not** for adding a whole second protruding volume — use technique #1 for that.

**Booleans remain ruled out project-wide** (see `add_waist_inset`'s comment and DECISIONS_NEEDED 2026-07-13: new machinery, non-manifold/perf risk). Everything below is expressible with convex hulls, fused primitives, and bisect+shift.

## Stretch-safety ground rules (unchanged, apply to everything below)

- The Design Lab applies **independent, sometimes extreme, per-axis `hull_scale`** at runtime. Meshes are authored once at build time; there is no runtime rebuild.
- **Anything keyed to a fraction of a half-dimension (`hx`, `hy`, `hz`) stretches correctly with its axis for free** — this is why the existing loft works at all. A split at `0.55*size_y` stays at 55% height under any Y stretch.
- **Detail-scale sizes (bevel width, groove depth, shelf overhang, rivet size) must stay keyed to `R = hull_reference_dim(size_x, size_y) = min(width, height)` and MUST exclude length (`size_z`)** — length is the most-stretched axis and must never dilate a detail feature. This is the whole reason `R` excludes length.
- **Two real bugs to not repeat** (both in DECISIONS_NEEDED): a *fixed* elevation offset added at a tapering tip spikes wildly when local width → 0 (the `flare` bug on `heavy_cruiser_hull`); and an `R`-based bevel width can self-intersect near a pointed tip where local edges are far shorter than `R` (already mitigated inside `bevel_sharp_edges` by clamping to `min_edge_len * 0.4` — any new bevel call inherits this, any *hand-rolled* offset does not).
- **Always run `scratch/reimport_assets.sh` before trusting a screenshot** (stale Godot import cache bug). Verify visually, not just in code — the decal-occlusion and machicolation off-by-one bugs both passed code review and only showed up on screen.

---

# GROUND HULLS (highest priority — most iconic, most used)

The unifying move for **all** ground hulls: replace the single top-deck loft with a **two-volume lower-tub + upper-structure construction**, plus **fender/sponson shelves at the tub/upper junction over the track run**. This is the change that converts "beveled wedge" into "assembled AFV." I recommend a new shared builder rather than more parameters on `build_wedge_hull()` (see "Sequencing" per hull), but the two can coexist — `build_wedge_hull()` stays for anything we don't convert.

## Proposed new shared construction helper: `build_afv_hull(...)`

A sibling to `build_wedge_hull()`, same call-site ergonomics (Godot-space, `GV()/GS()` internally), producing three fused volume families:

**Volume A — lower hull tub.** A convex hull of a point cloud that is *near-vertical-sided and full-width* — a slab, not a wedge. Belly at `-hy` (unchanged flat full-width rectangle, preserves the flat bottom the belly/inverted-pintle mount needs). Its top ("hull roof line") sits at a fraction of height, `tub_top_y = -hy + 2*hy*tub_frac` (e.g. `tub_frac≈0.55`). Sides run full `±hx` and stay close to vertical (light taper only). This is the volume the tracks/wheels live against and the sponsons bolt to.

**Volume B — upper structure (glacis + casemate/fighting compartment).** A **second, separate** convex hull merged into the same `bm` (technique #1). Its point cloud is narrower in width (`±hx*upper_w`, e.g. 0.7–0.85) and starts at `tub_top_y`, rising to the deck at `hy`. The **front-top row of points is pulled forward and kept low** to create a genuine sloped glacis plate as a real facet, and the **rear is kept vertical/slab** for the engine compartment. Because B is convex-hulled separately and left interpenetrating A (exactly as tower tiers interpenetrate), the join between them reads as a real hull-roof line / shot-trap step — the thing that currently does not exist.

**Volume C — fender/sponson shelves.** Two fused `add_box` volumes (technique #1, identical to `build_sponson_hull`'s blisters) running along the length at `y ≈ tub_top_y`, protruding to `±hx` (or slightly past), **flat-topped**. These read as the fenders/sponsons over the track run and are the sponson-embed side-mount real estate. Protrusion width keyed to `R`, length keyed to `hz` (full length is correct here — fenders run the length of the track).

Construction order (must match the existing mount-zone-aware ordering — silhouette first, bevel, then greebles):
```
bm = bmesh.new()
tub_verts   = convex_hull(tub_point_cloud)        # Volume A
upper_verts = convex_hull(upper_point_cloud)       # Volume B  (separate call, interpenetrating)
add_box(...) x2                                    # Volume C fenders
# optional concave detail on the upper deck BEFORE bevel:
add_panel_line_groove(...) / louver pocket          # bisect+shift
bevel_sharp_edges(bm, list(bm.verts), R, tier=1)   # smooths A/B/C's own real edges + any cuts
greebles(bm, hx, hy, hz)
```
Note the bevel runs on `list(bm.verts)` (the *current* set) and selects by dihedral angle, so it correctly finds the new tub-roof edge, glacis crease, and fender edges without hand-picking — the same reason it already works on every convex-hull hull.

**Do NOT weld A/B/C together with `remove_doubles`.** Leave them interpenetrating like tower tiers. Welding coincident-but-not-aligned shells is where non-manifold geometry and bevel spikes come from. (Contrast: `build_fuselage_hull` *does* weld its nose/body/tail cones — that's correct there because they're coaxial rings meant to be one continuous tube. A/B/C are deliberately distinct blocks.)

### Mount-zone impact of the two-volume scheme (applies to all ground hulls)

- **Top:** pintle sits on the upper structure's deck (Volume B roof) — flat, good. The AABB `top` facet is now the deck at `hy`; fine.
- **Bottom:** unchanged flat full-width belly (Volume A). Inverted-pintle / helicopter-rotor mount unaffected — **safe, verify once.**
- **Left/right:** the AABB side plane is at `±hx` = the fender/sponson (Volume C) outer face, which is flat and vertical — **better** side-mount real estate than today. Sponson-embed muzzles emerge from the fender, exactly where real AFV sponson guns sit.
- **Front/back:** the AABB `front` plane is at `-hz`. A sponson-embed front muzzle projects along `-Z` through that plane; visually it now emerges from a **sloped glacis** rather than a vertical face. Per MOUNTING_AND_ARMOR_SPEC the muzzle just projects through the facet plane regardless of the true slope (facets are the AABB, not the mesh), so this is **cosmetically acceptable but should be eyeballed** — a very steep glacis could make a front muzzle look like it clips the slope. Mitigation if it reads wrong: keep the lowest ~30% of the glacis (the "bow" band around belly height) closer to vertical so front muzzles exit a near-vertical strip. **This is the one facet interaction to re-verify per hull.**
- The single AABB collision box (`module_placer.gd`) is unchanged — it already ignores the true silhouette, so multi-volume massing costs nothing on the collision/facet side. **No placement code needs touching**; this is purely an asset change. Flag only the front-glacis cosmetic above.

---

## light_hull — scout / light recon
`size (3.0, 1.0, 4.0)`, hp 200, weight 100. Fast, cheap, low-value expendable scout.

**Real-world reference:** wheeled scout car / light reconnaissance vehicle (Ferret, BRDM, Panhard). The class convention is *low, minimal frontal area, wedge-nosed, sloped all around* — survivability by not being hit, not by armour. It should read lower and slimmer than everything else.

**Concrete massing moves:**
- Use `build_afv_hull` with a **low `tub_frac ≈ 0.45`** and a **modest, well-faired upper structure** (`upper_w ≈ 0.8`) — the glacis and hull nearly merge into one continuous slope, which is exactly the scout-car read (little distinction between hull and superstructure). Keep the aggressive nose taper it has today (`nose_frac≈0.6`, `nose_region≈0.28`).
- **Skip Volume C heavy fenders** — a scout reads clean; use thin, shallow fender lips (small `R`-keyed boxes) rather than deep sponson blisters. This keeps it visually distinct from the heavier hulls, which get chunky sponsons.
- Keep the existing subtle bevel (`bevel_pct≈0.06`) — light reads sharp-edged and thin, not chunky.

**Stretch-safety:** all fractions of `hx/hy/hz`; fender lip depth keyed to `R`. Safe. The low `tub_frac` means under extreme Y-stretch it stays proportionally low — desirable.

**Mount-zone:** top pintle on the faired deck (flat enough); minimal fenders still give a valid `±hx` side face. Nothing new to verify beyond the shared front-glacis note.

**Sequencing:** moderate. Once `build_afv_hull` exists, light_hull is a light-parameter call. It's the *safest* first conversion to prove the new builder because it's the smallest/simplest and its failure cost is lowest.

## medium_hull — main workhorse ⭐ (flagship conversion — do this first)
`size (4.0, 1.0, 6.0)`, hp 400, weight 250. The default main-battle chassis, the one every player uses and stares at most.

**Real-world reference:** classic medium/main-battle tank (T-34, Sherman, Leopard 1). The canonical silhouette: a **distinct boxy lower hull tub, a well-sloped glacis plate as a clearly separate frontal facet, flat sponson tops over the tracks, a raised engine deck at the rear, and a flat turret-ring platform** on top. This is the exact anatomy the two-volume scheme is designed to hit, so medium_hull is the reference implementation.

**Concrete massing moves:**
- `build_afv_hull`, `tub_frac ≈ 0.55`, `upper_w ≈ 0.78`. Pull the upper structure's front-top points forward+down for a pronounced glacis; keep the rear third of Volume B a vertical slab = engine compartment.
- **Volume C fenders full** — flat-topped sponson shelves to `±hx`, this is the defining "over the tracks" read and the sponson-embed mount surface.
- **Turret ring:** keep/standardize the raised `add_cyl_y` collar (assault_hull already does this at `y≈hy*1.1`). Place it on the glacis/roof junction — this is the "hull-to-turret-ring relationship" Chris asked for, and it visually anchors a top-pintle weapon.
- **Engine deck louvers as real geometry** (new, see helper below) recessed into the rear deck instead of the current proud `greeble_vent` box.
- Keep the existing `panel_line_fracs`/deck detail on the upper structure.

**New helper needed — `greeble_louver_panel(bm, center, size, slats, recess_frac)`:** a *recessed* vent pocket, not a proud box. Two pairs of `bisect_plane` cuts bounding a rectangle on the deck (2 planes normal to length, 2 normal to width — same bisect technique as `add_panel_line_groove` but crossed in both axes), then push the interior verts **down** by `R*recess_frac` to form the pocket, then lay angled slat `add_box`es across it (reuse `greeble_vent`'s slat loop). This is a moderate new function — the 2D pocket (intersection of two bisect bands) is the only genuinely new bit; everything else is existing vocabulary. Keyed to `R`, deck-relative. Reusable by heavy/assault/sponson.

**Stretch-safety:** everything fraction- or `R`-keyed. The one thing to watch: the louver pocket's rectangular extent is a fraction of deck width (`hx`) and a *fraction of length* — but since it's a fixed *fraction* of `hz` (not a fixed world size), it scales fine; just don't give it a fixed world length. Safe.

**Mount-zone:** top pintle on turret-ring platform (ideal); sponson sides flat; re-verify the shared front-glacis muzzle note here since medium is the most-used and most-scrutinized.

**Sequencing:** this is the big lift — it's the one that *needs* `build_afv_hull` and `greeble_louver_panel`. Build both against medium_hull first (mirrors the Tier-1 "validate on medium ground hull first" precedent), verify on screen, then the other ground hulls are parameter variations.

## heavy_hull — heavy assault tank
`size (6.0, 1.5, 8.0)`, hp 1000, weight 800. Slow, maximally armoured, tallest/widest ground chassis.

**Real-world reference:** heavy/breakthrough tank (Tiger, IS-3, Maus register). Convention: **slab-sided and tall, thick near-vertical glacis, minimal graceful taper, heavy chunky edges.** Where light reads as "sloped to deflect," heavy reads as "thick enough not to care."

**Concrete massing moves:**
- `build_afv_hull`, **high `tub_frac ≈ 0.6` and near-full `upper_w ≈ 0.9`** — the upper structure barely narrows, giving the slab-sided read. Glacis is *thick and steep but blunt* (front-top points forward but the whole frontal plate stays tall), not the sharp thin wedge of light.
- Keep the chunky bevel it has today (`bevel_pct=0.09, bevel_segments=3`) — heavy is the wide/chunky end of the tier-1 band and should stay there; the extra segments read as thick cast armour.
- **Volume C fenders deep and boxy**; add a commander cupola (`add_cyl_y`) as today.
- **Bolt-on look:** the existing rivet rows + corner gussets already sell "assembled." Consider a second, lower belt of rivets along the tub/fender seam (a `greeble_rivet_row` at `y≈tub_top_y`) to emphasize the two-volume join.

**Stretch-safety:** the higher `size_y` (1.5) means `R = min(6.0, 1.5) = 1.5` is genuinely height-limited here — bevel/detail scale off height, correct. All fractional. Safe.

**Mount-zone:** blunt tall glacis is *better* for a front sponson-embed muzzle than a steep thin one (the shared front-glacis caveat is least severe here). Top/sides flat and generous. Safe.

**Sequencing:** parameter variation on `build_afv_hull` once it exists. Moderate.

## interceptor_hull — fast strike / recon (already partly bespoke)
`size (2.4, 0.8, 3.2)`, hp 130, weight 65. Fastest, best base vision, lowest HP. Already has `height_taper=0.45` and the Tier-3 `add_speed_line_chamfer`.

**Real-world reference:** Chris's own note points two ways — a fast light recon vehicle (Wiesel, CV90-scout) *or* an attack-helicopter canopy+skid vocabulary. I recommend **leaning into a low, dart-like recon-vehicle body with a distinct raised canopy/cockpit volume**, because the helicopter read is better delivered by the *rotor mount* (bottom inverted-pintle, per MOUNTING_AND_ARMOR_SPEC #3) than by the hull silhouette — let the hull stay a fast ground/strike wedge and let locomotion+weapon modules push it toward "helicopter" when the player wants that.

**Concrete massing moves:**
- **Do NOT convert to the full two-volume tub/glacis** — interceptor's identity is the *single sharp dart*, and the shared bevel + `height_taper` + speed-line chamfer already differentiate it. Forcing a slab tub on it would erase what makes it distinct.
- Instead, add **one** genuinely-separate volume: a small **faired canopy/cockpit** as a second convex hull (technique #1) or squashed dome (reuse `build_dome`'s uvsphere+scale), set slightly forward of centre, *faired* (low, blended) rather than the current proud `add_box` bump. This is the "real cockpit volume not just a bump" upgrade at ground-hull scale.
- Keep `speed_line_chamfer`, keep the sharp narrow bevel (`bevel_pct=0.05`).

**Stretch-safety:** the canopy dome must be keyed to `hx/hz` for footprint and `hy` for height; a dome scaled by `GS(...)` inherits stretch. **Watch:** under extreme independent Y-stretch a squashed dome can invert its squash ratio and look like a bubble — clamp the canopy height to a fraction of `hy` and let width follow `hx`, same as the airship gondola. Flag but low-risk.

**Mount-zone:** bottom inverted-pintle (rotor) must stay clear — keep the canopy on top only, belly flat. Top pintle sits behind the canopy. Verify the canopy doesn't intrude on the top facet's usable centre.

**Sequencing:** small. It's a targeted addition, not a rebuild. Lower priority than medium/heavy since it's already the most-differentiated ground hull.

## assault_hull — breakthrough / heavy assault
`size (5.0, 1.3, 7.0)`, hp 650, weight 500. Between medium and heavy; the "kicks the door in" chassis. Already has applique armour plates, turret ring, and a front dozer plate greeble.

**Real-world reference:** assault gun / breakthrough vehicle / engineering-tank (StuG casemate, AVRE, a dozer-tank). Convention: **a heavy blunt front with a prominent dozer/glacis plate, appliqué armour, low casemate rather than tall turret.**

**Concrete massing moves:**
- `build_afv_hull`, `tub_frac ≈ 0.55`, `upper_w ≈ 0.82`, but shape Volume B as a **low casemate** (front-top slab, less rising to a turret deck) rather than medium's turret platform — assault reads as "gun built into a boxy superstructure."
- **Promote the existing dozer plate into real massing:** today it's a single rotated `add_box` at the nose. Keep it, but tie it to the glacis so the front reads as one thick layered frontal assembly (dozer plate + glacis + appliqué). The existing appliqué plates (tier-2 bevel + rivet lines) are exactly right — keep them; they're the best "assembled, up-armoured" detail in the roster already.
- Keep chunky bevel (`bevel_pct=0.085, bevel_segments=3`).

**Stretch-safety:** the dozer plate is `add_box` at `-hz*1.0` with width `hx*1.3` — width already scales with `hx`; its *thickness* (0.15) is a small fixed world value — acceptable for a thin plate but consider keying to `R` so it doesn't look like paper under a big Z-stretch. Minor.

**Mount-zone:** casemate + dozer means the front facet is busy; a front sponson-embed muzzle should exit *above* the dozer plate — verify the muzzle Z-exit height clears the dozer. This is a specific check for assault. Top/sides fine.

**Sequencing:** parameter variation + tie-in of existing greebles. Moderate.

## sponson_hull — heavy multi-sponson platform (already multi-volume)
`size (6.5, 1.6, 7.5)`, hp 800, weight 650. Widest hull; `build_sponson_hull` already bakes side blisters into the silhouette.

**Real-world reference:** WWI-style rhomboid/multi-sponson landship, or a heavy self-propelled-gun carrier. Convention: **a broad slab core with pronounced box sponsons mid-flank** — it already has the right idea, it's the closest thing in the roster to "assembled."

**Concrete massing moves:**
- **This hull already uses technique #1** (core convex hull + fused `add_box` sponsons). The upgrade is to **also split the core into tub + upper structure** so it's not a flat slab under the sponsons — reuse `build_afv_hull`'s tub/upper for the core and keep the existing side blisters as Volume C but *bigger and more distinct* (they're the whole point of this hull).
- Give each sponson a **flat top and a distinct front face** (they already do) — these are premium sponson-embed mount zones on multiple facets, which is this hull's mechanical identity (lots of side-mount real estate).

**Stretch-safety:** already-proven builder. The blister protrusion (`sp_reach`) is derived from `hx*sponson_bulge - core_x` — a fraction of width, safe. Keep it that way.

**Mount-zone:** best side-mount real estate in the game — flat tall vertical sponson faces at `±hx`. Nothing to fix; verify the new tub/upper split doesn't reduce the flat sponson face height.

**Sequencing:** low-moderate. Either fold `build_sponson_hull` into `build_afv_hull` (share the tub/upper, keep the blister param) or leave it standalone and just add a tub/upper split. Lower priority — it already reads as assembled.

---

# NAVAL HULLS

Current state (`build_ship_hull`): a genuinely good per-station V-deadrise loft with sheer and optional flare — the *hull* anatomy is already the best in the roster. The weakness Chris names is **"a bridge box glued onto a uniform hull loft"**: the superstructure is one `add_box` (plus per-ship greebles). Fix the superstructure, not the hull.

## naval_hull — mid-size warship
`size (3.5, 1.6, 9.0)`, hp 550, weight 380. Already got a Tier-3 raked funnel + foremast.

**Real-world reference:** WWII destroyer / frigate. The mast–bridge–funnel silhouette is the identity (already partly there via greebles).

**Concrete massing moves:**
- **Promote the superstructure to a stepped stack of separate volumes** (technique #1): replace the single bridge `add_box` with 2–3 fused boxes of decreasing footprint stacked upward (foredeck house → bridge → open bridge), each with its own tier-2 bevel. `heavy_cruiser_hull`'s greebles already prototype this layering — generalize it into `build_ship_hull` as a `superstructure_tiers` param so every ship gets real layered massing, not one box.
- Keep the funnel/foremast. Add a **bulwark line** (the deck edge rising slightly) via the existing `sheer` — already present.
- **Forecastle break:** a raised foredeck as a short fused box forward, giving the classic freeboard step — cheap and reads instantly as "ship."

**Stretch-safety:** superstructure boxes keyed to `hx/hy/hz` fractions (as the current bridge box already is). The **funnel/mast heights are fixed multiples of `hy`** — good, but watch the `heavy_cruiser` flare bug lesson: don't add any fixed-elevation feature at the pointed bow. Safe if kept to fractions.

**Mount-zone:** ship decks are wide and flat — excellent top-pintle real estate. The stepped superstructure occupies the mid/rear top; ensure the fore and aft deck stay clear for turret pintles (real warships mount main guns fore and aft of the superstructure — this actually *reinforces* correct mount placement). Verify superstructure footprint leaves fore/aft deck open.

**Sequencing:** moderate extension of `build_ship_hull` (add layered superstructure param). No new construction function — reuses fused boxes.

## small_boat_hull — fast patrol boat
`size (2.0, 1.0, 5.0)`, hp 220. Sharpest bow, highest deadrise, sparse gear.

**Reference:** PT boat / patrol craft. **Planing hull, low freeboard, minimal superstructure — a small pilothouse, not a warship stack.**

**Concrete massing moves:** keep the sharp bow (`bow_frac=0.5, deadrise=0.55`). Give it **one** small pilothouse box (a single superstructure tier, not the stack) forward-of-centre. That's it — its identity is *sparseness*. Do not over-build.

**Stretch-safety:** already fine. **Mount-zone:** small flat deck; one top pintle amidships. Keep pilothouse small so it doesn't eat the deck. **Sequencing:** trivial once `superstructure_tiers` exists (set it to 1).

## heavy_cruiser_hull — capital warship
`size (4.4, 1.9, 10.5)`, hp 900. Biggest naval hull; already has the busiest greebles (twin funnels, layered bridge, portholes, foredeck turret housing).

**Reference:** heavy cruiser / small battleship. **Tall layered superstructure, multiple gun-deck levels, pronounced flare (already `flare=0.35`).**

**Concrete massing moves:** it already has most of this in greebles — the win is **moving that layering from greeble-scale into base massing** via the same `superstructure_tiers` param (3–4 tiers). Keep twin funnels, foredeck turret housing, flare. Add a **stern quarterdeck step** (a lower rear deck) for the layered-deck read.

**Stretch-safety:** the flare-at-bow bug is *already* correctly gated here (`beam_scale > 0.5`) — preserve that guard exactly if you touch the loft. **Mount-zone:** large multi-level deck — the fore/aft turret positions and the flanks are all valid; this hull can carry the most weapons and the massing should keep those zones flat. **Sequencing:** moderate; mostly promoting existing greebles into base massing.

---

# AIR HULLS

Current state is already reasonably differentiated (`flying_wing` is a real blended-wing-body, `fuselage` is a real tube+wing, `airship` is a faceted rigid envelope). The gaps Chris names are **construction detail**: spars/ribs as panel breaks, wing-root fairing, cockpit as a real volume.

## flying_wing_hull — fast blended-wing airframe
`size (5.0, 0.7, 3.6)`, hp 230, weight 140.

**Reference:** flying wing / lifting body (B-2, Horten). Already the right planform.

**Concrete massing moves:** the wing thickness taper is already implicit (dorsal shoulders short of the wingtips). Add **spanwise panel-line grooves** (reuse `add_panel_line_groove` logic but oriented along span, i.e. bisect planes normal to X instead of Z) to imply spars/ribs. Upgrade the canopy from a proud `add_box` to a **faired blister** (small second convex hull blended into the dorsal ridge). Keep the wide max-segment bevel at the wing-root/body junction — it's already tuned for that.

**Stretch-safety:** panel grooves keyed to `R`; a wing stretched in span shows more spanwise panels (correct, matches VISUAL_ART_DIRECTION's stretch philosophy). Safe. **Mount-zone:** thin flat top/bottom — top and bottom pintles fine; sides are wing edges (thin) so side sponson-embed will look odd on a wing — this is inherent to the airframe, not a regression. **Sequencing:** small; a groove-orientation variant + faired canopy.

## fuselage_hull — bomber/cargo airframe
`size (4.2, 1.2, 6.2)`, hp 300, weight 210.

**Reference:** conventional multi-engine aircraft. Already tube + separate wing + tail surfaces (genuinely good).

**Concrete massing moves:**
- **Wing-to-fuselage fairing:** today the wing slab crosses the tube with a hard intersection. Add a small **fillet fairing** — a fused, stretched, low box or a short lofted `add_cyl_axis` at the wing root where wing meets body — so the join reads as engineered, not two shapes clipping. Cheap.
- **Ribs/formers:** add circumferential panel rings (the `airship` greebles already do exactly this with `add_cyl_axis` thin rings — reuse that on the fuselage tube).
- **Canopy as real volume:** upgrade the cockpit bump (`_fuselage_hull_greebles`' `add_box`) to a faired canopy (squashed dome / small convex hull) proud of the tube top-forward.

**Stretch-safety:** the fuselage is welded coaxial cones (`remove_doubles`) — correct, keep it. Fairing and rings keyed to `body_r`/`R`. Safe. **Mount-zone:** tube top is curved — top pintle needs the pintle base to sit on the curve (the pintle already snaps to facet angle per spec). Verify a top pintle on a round fuselage doesn't float; may want a small flat hardpoint pad (`add_box`) at the mount anchor. **Sequencing:** moderate; several small additions, no new core function.

## airship_hull — rigid dirigible (already Tier-3 faceted)
`size (4.0, 3.0, 9.5)`, hp 480. Already faceted envelope (u_segments=8), gondola on struts, tail-fin cross, ring seams.

**Rigid vs blimp decision — pick RIGID, and here's the justification:** the envelope is *already* faceted (45° dihedral panels, deliberately past the auto-smooth threshold), the gondola hangs on rigid struts, and VISUAL_ART_DIRECTION's flat/low-metallic finish reads as a doped-fabric-over-frame Zeppelin. A blimp (smooth pressure envelope, gondola faired directly to the bag) would mean *undoing* the committed Tier-3 faceting. Rigid is already the established direction — keep it and lean in.

**Concrete massing moves:** add **longitudinal keel girders** — 2–4 thin fused `add_box` battens running the length along the belly of the envelope — and keep the existing ring seams; together the long battens + rings read as the rigid frame grid. This is the single move that upgrades "faceted balloon" to "girder ship." Cheap (fused thin boxes, `R`-keyed thickness).

**Stretch-safety:** the envelope tail taper is already fraction-based. Keel battens run the length — key their thickness to `R`, length to `hz`. The gondola is already correctly clamped (biased toward nose, fractions of `hy`). Safe. **Mount-zone:** bottom is the gondola (inverted-pintle mounts hang off it — thematically perfect); top of envelope is curved (same round-top note as fuselage). **Sequencing:** small.

---

# STATIC DEFENSES (mostly already addressed by Tier-3 — lowest priority)

These already received the most bespoke Tier-3 attention (split merlons, machicolation, faceting) and already use battered-wall taper. Remaining gaps are embrasures-as-real-geometry.

## pillbox_foundation — bunker
`size (3.0, 1.2, 3.0)`, hp 800. `build_bunker_hull`: octagonal battered frustum + dome + sandbag corner fillets + a proud `greeble_vent` embrasure.

**Reference:** concrete pillbox / casemate. Battered walls already present (the frustum taper *is* the batter — good). **The one real gap: firing embrasures.**

**Concrete massing moves:** replace the proud `greeble_vent` embrasure with a **real recessed, splayed embrasure** — a bisect-recessed pocket in the sloped wall (reuse the `greeble_louver_panel` pocket technique, but a horizontal slit) with the opening splayed wider on the outside (casemate logic: the firing slit narrows inward). This is the same bisect+shift vocabulary. Optionally add a shallow **casemate hood** (a small fused box lintel above the slit).

**Stretch-safety:** embrasure pocket keyed to `R` and wall-relative fractions. Safe. **Mount-zone:** foundations mount weapons on top/embrasure; the recessed slit gives a natural front sponson-embed exit. Verify the front-facet muzzle exits through the embrasure. **Sequencing:** small; one embrasure helper (shared with louver pocket).

## tower_foundation — watchtower
`size (3.0, 4.0, 3.0)`, hp 1400. `build_tower_hull`: stepped tiers + skirt + machicolation ring + railings. **Already the most-developed static hull.** No massing change recommended — it already reads as constructed. (If anything, add real embrasures to the tier faces using the pillbox embrasure helper.) **Sequencing:** none / trivial.

## fortress_wall_foundation — rampart
`size (6.0, 2.2, 1.3)`, hp 1100. `build_wall_hull`: battered wall + split-merlon crenellations + arrow-slit greebles. Already good, and critically it uses `preserve_axis=0` so wall segments **tile edge-to-edge** — any new feature must preserve that.

**Concrete massing moves:** promote the arrow-slit greebles (currently proud dark `add_box`es) to **recessed** slits (embrasure helper). **Hard constraint:** keep everything off the ±X end-cap faces — those must stay flat for tiling (the `preserve_axis=0` guard on the bevel exists for exactly this). Put embrasures only on the ±Z (front/back) faces. **Stretch-safety:** wall tiling depends on end caps staying identical — do not add length-keyed features. Safe if end caps untouched. **Sequencing:** small.

---

# Prioritized punch-list

Ordered by **(payoff × how much it moves the "reads as a real machine" needle) weighed against (technical risk/cost)**. The implementation pass should go top-down.

| # | Hull(s) | Payoff | Risk/Cost | Rationale |
|---|---------|--------|-----------|-----------|
| 1 | **medium_hull** | Very high | Moderate | Most-used, most-scrutinized. It's the vehicle for building & proving `build_afv_hull` + `greeble_louver_panel`. Mirrors the Tier-1 "validate on medium first" precedent. Everything else keys off this. |
| 2 | **heavy_hull** | Very high | Low* | Pure parameter variation on `build_afv_hull` once it exists (*low incremental). Slab-sided read is a dramatic before/after. |
| 3 | **light_hull** | High | Low* | Parameter variation; also the safest smallest test of the new builder. Low, wedgy scout read. |
| 4 | **assault_hull** | High | Moderate | Parameter variation + tie the existing dozer/appliqué greebles into real frontal massing. One mount-zone check (front muzzle over dozer). |
| 5 | **sponson_hull** | Medium-high | Low | Already multi-volume; just add the tub/upper core split. Best side-mount hull, worth polishing. |
| 6 | **naval_hull** | High | Moderate | `superstructure_tiers` param — turns the glued-on bridge box into layered massing. Reused by all 3 ships. |
| 7 | **heavy_cruiser_hull** | Medium-high | Low* | Promotes existing greeble layering into base massing via #6's param. Preserve the flare-at-bow guard. |
| 8 | **interceptor_hull** | Medium | Low | Targeted: faired canopy volume only. Already the most-differentiated ground hull; don't over-touch. |
| 9 | **fuselage_hull** | Medium | Moderate | Wing-root fairing + ribs + real canopy. Several small additions; round-top mount check. |
| 10 | **small_boat_hull** | Low-medium | Trivial | One pilothouse tier via #6. Identity is sparseness. |
| 11 | **flying_wing_hull** | Low-medium | Low | Spanwise panel grooves + faired canopy. Already a good planform. |
| 12 | **airship_hull** | Low-medium | Low | Longitudinal keel battens to complete the rigid-frame read. Already Tier-3 faceted. |
| 13 | **pillbox_foundation** | Low | Low | Real recessed splayed embrasure (new shared embrasure helper). |
| 14 | **fortress_wall_foundation** | Low | Low | Recessed arrow slits — but MUST preserve ±X end-cap tiling. |
| 15 | **tower_foundation** | Very low | None | Already the most-developed static hull. Optional embrasures only; otherwise leave it. |

**New helpers this work introduces** (all buildable from existing primitives, no booleans):
- `build_afv_hull(...)` — two-volume tub + upper-structure + fender shelves (interpenetrating convex hulls + fused boxes, per the tower/sponson precedent). *The keystone.* Items 1–5.
- `greeble_louver_panel(...)` — recessed 2D vent pocket (crossed bisect bands + downward vertex shift + slats). Items 1, 2, 4, 5.
- `superstructure_tiers` param on `build_ship_hull(...)` — layered fused-box stack (no new function, just generalize the existing bridge box). Items 6, 7, 10.
- A shared **recessed embrasure** helper (a horizontal-slit variant of the louver pocket, splayed). Items 13, 14, and optionally 8/15.

**Everything above is asset-only.** The single AABB collision box and the `classify_facet` mount system are untouched — the only thing to re-verify per hull is the cosmetic "does a front sponson-embed muzzle exit the sloped glacis / dozer / embrasure cleanly," since facets are the AABB and not the true sloped mesh.
