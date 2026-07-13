# Build-A-Bomber — Faction & Terrain Visual Design Document

## 0. Design Premise
Every hull/module uses one shared mesh per part, faction-agnostic. Faction identity is carried 100% by material parameters: paint color, wear, trim, surface finish — no bespoke geometry, no hand-painted unique textures per faction. Entire faction-identity system lives in a shared shader with a small number of exposed per-faction parameters, plus shared masks (wear masks, panel-line masks, trim masks) every faction's parameters multiply against.

## 1. Tone/Mood Translation
**1.1 Color temperature & saturation:** Base metal = warm-neutral silver (hue 40-55°, luminance 0.55-0.70), never cold blue-steel by default. Faction accents: HSV saturation 55-85%, value 70-95% (diecast-model-paint register, not military-drab, not pastel). Terrain saturation must sit lower than faction saturation — units are the saturated "toy" objects, world is the muted stage. Lifted blacks (shadow floor ~0.08), capped whites (specular cap ~0.92).

**1.2 Where goofy lives:** Detail-scale only, never silhouette/color-blocking. Safe: oversized bolt-heads at module seams, small stenciled serial numbers/nicknames in rounded stencil font, tiny per-faction mascot decal (~5% of hull silhouette max) at fixed anchor points, personality emerging from extreme Design Lab slider combos (systemic, not textural — material system must not fight it), warm cartoon-bright hazard stripes at panel edges. Never: primary silhouette color-blocking staying "toy tractor" not cartoon, no googly-eyes/face-like grilles, weapon barrels/muzzles stay subdued/functional, faction color must never reduce unit-vs-terrain/unit-vs-unit legibility.

**1.3 Brushed anodized aluminum surface language:** Brush direction follows dominant long axis per part-type (nose-to-tail hulls, spanwise wings, radial wheels/turret rings). Anisotropic highlight perpendicular to brush grain — use Godot's `anisotropy_enabled`/`anisotropy`/`anisotropy_flowmap` on StandardMaterial3D/spatial shader; reads as a static bright stripe per unit facing at fixed RTS camera angle. Anodized tint = translucent tint multiplied over brushed-metal albedo+anisotropy (not opaque paint layer) — this is both the correct metaphor and cheapest shader implementation, letting factions share one brush/anisotropy pass and differ only by tint. Edge wear: high-curvature edges (panel corners, bolt heads, tread lugs, wingtips) expose brighter/warmer bare metal as wear_amount rises, driven by baked curvature/AO mask (shared across factions, depends only on mesh). Panel lines/rivets: consistent kit-of-parts grammar across ALL factions regardless of paint — recessed seams w/ darkened AO line, rivet rows, large structural bolts at attachment points — reinforces "same engineering, different livery." Roughness: bake subtle roughness-noise stretched along brush direction into shared base texture even for pristine factions.

**1.4 Shared decal/stencil library:** hazard chevrons, serial stencils, mascot icon, warning glyphs — one decal atlas, re-tinted per faction accent/detail color.

**1.5 Wear as continuous 0-1 dial**, not binary.

**1.6 Team-color problem (important, flag explicitly):** Since faction paint IS the primary identity channel, two players picking the same faction have no material signal left to distinguish "mine" vs "enemy's." Recommend a small, separate, low-saturation team marker independent of faction shader — thin colored piping/edge-light at a fixed decal anchor (corner pennant, cockpit glow, LED strip) driven by its own `team_color` parameter layered ON TOP of faction material, not replacing any faction parameter. Keeps "who owns this" and "what faction" orthogonal.

## 2. Shader Parameter Model
Proposed as a Godot ShaderMaterial, packaged as a custom Resource (e.g. FactionMaterialProfile.tres) so each faction is one data asset:

| Parameter | Type | Purpose |
|---|---|---|
| base_color | Color | Primary hull paint (large flat panels) |
| accent_color | Color | Secondary trim/stripe/panel-edge tint |
| detail_color | Color | Tertiary stencil/decal/insignia tint, small-area only |
| metallic | float 0-1 | Base metallic response under paint |
| roughness | float 0-1 | Base roughness of paint layer |
| anisotropy | float 0-1 | Strength of brushed-metal highlight streak |
| brush_scale | float | Tiling frequency of brush-grain detail (see stretch handling below) |
| wear_amount | float 0-1 | Master weathering dial — blends base paint → exposed metal/rust, driven by shared curvature/edge mask |
| wear_color | Color | What gets exposed as wear increases — bare steel most factions, rust-orange Industrialists, grime-black Salvagers, frost-white Glacier Syndicate, brass Aerodrome Cartel, etc. |
| grime_amount | float 0-1 | Separate from edge wear — soot/dirt in RECESSED areas (AO-driven, opposite mask logic from wear_amount) |
| edge_highlight_strength | float 0-1 | How bright/hot exposed-edge highlight reads |
| emissive_color / emissive_strength | Color/float | Optional status lights/cockpit glow/tech accents — zero most factions, nonzero e.g. Technocrats |
| decal_tint | Color | Tint for shared stencil/hazard/mascot decal atlas |

13 exposed values total — small enough to hand-author per faction.

**Shared mask set (baked ONCE per mesh/module, not per faction):** Mask R = base/panel mask (where base_color applies). Mask G = trim mask (accent_color — edge stripes, sponson trim, turret ring). Mask B = curvature/edge-wear mask (baked from mesh curvature or runtime fresnel/curvature approx — drives wear_amount exposure, high on edges/corners/bolts, near-zero on flat panel interiors). Mask A = cavity/AO mask (drives grime_amount, opposite spatial logic from wear mask — grime collects in crevices). Separate greyscale decal-alpha atlas for the shared stencil library, tinted by decal_tint at fixed anchor points.

**Handling continuous stretch/scale (IMPORTANT, game-specific risk):** Since Design Lab lets players continuously stretch/scale hulls, naive per-object UVs will distort/re-tile brush grain and panel lines unpredictably. Fix: drive brush_scale and panel/rivet detail through world-space or object-local triplanar sampling (or UVs normalized to real-world unit length, not 0-1 per mesh) so a stretched hull shows MORE repetitions of the same brush grain, not one smeared stroke — correct real-world behavior too. Rivets/bolts should stay fixed-size in world units, tiling to match part length, rather than scaling with the slider. Solve this ONCE in the shared shader, not per faction — it's a mesh/UV problem, not a faction-identity problem.

## 3. The Ten Factions

1. **Heavy Industrialists** (existing) — Steel-belt magnates, brute-force manufacturing. Gunmetal grey / hazard yellow / rust-orange wear. Lived-in: moderate wear+grime, low-mid roughness ("well-oiled," not derelict). Bonus: armor-weight tolerance.

2. **Technocrats** (existing) — Clean futurists, precision over brute force. Pearlescent white / electric cyan / chrome. Pristine: near-zero wear/grime, high anisotropy, nonzero emissive on sensors/cockpit. Bonus: vision + speed.

3. **Expansionists** (existing) — Colonial frontier land-grabbers. Olive drab / burnt sienna / aged brass. Dusty/weathered: mud-spatter grime concentrated low (terrain-contact), sunbaked mid-high roughness. Bonus: resource-drain exemption for structures/units far from base.

4. **The Salvage Union** — Junkyard mercenaries, nothing original equipment. Primer grey base w/ mismatched randomized-per-unit patch panels (secondary patch mask) + duct-tape/raw-aluminum trim. Scavenged/battle-worn: highest wear+grime in roster, dull edge highlight, patched bullet-hole decals. Bonus: cheaper repair / reduced module costs.

5. **The Crimson Concordat** — Zealous militant order, banners and kill-marks as doctrine. Deep crimson / gold-brass / black. Ceremonial-pristine chassis, heavy decal density (kill-mark stencils, banner motifs) rather than physical wear. Bonus: combat bonus scaling up as unit nears critical health.

6. **The Glacier Syndicate** — Cold-climate industrial cartel, methodical. Arctic white / ice-blue / gunmetal. Pristine-but-frosted: unique wear_color (pale frost-crystal white, not rust), low-mid roughness. Bonus: reduced terrain-speed penalty across the board.

7. **The Dune Runners** — Desert nomad convoy, economy first. Sandstone tan / faded turquoise / worn-leather-brown. Sun-bleached/sandblasted: matte, LOW-anisotropy finish (sand scours off the mirror-brush highlight rather than exposing bright metal), wear_color desaturates rather than brightens. Bonus: harvesting/economy bonus (faster gathering / higher harvester capacity).

8. **The Ledger Combine** — Corporate-military conglomerate, war-as-product-line. Corporate blue / white / neon-green logo detail. Showroom-pristine, notably higher gloss than any other faction, branded decal (wordmark/logo) at mascot anchor rather than sensor-tech emissive. Bonus: cheaper unit/production costs.

9. **The Bayou Irregulars** — Swamp guerrilla insurgency, hit-and-fade. Swamp green / mud brown / faded olive, MOTTLED camo-pattern mask blending base/accent (two greens mottled, not flat color) — trim mask reads as camo netting, not a racing stripe. Scavenged, moss/algae-tinted grime (wear_color shifted green-black, not rust) concentrated low on hull. Bonus: reduced detection range against this faction (camouflage).

10. **The Aerodrome Cartel** — Barnstorming aviation enthusiasts turned arms dealers, art-deco glamour over serious airframes. Cream/ivory / polished brass-copper / deep aviation-blue stripe. Polished-brass-pristine trim (wear_color is brass, not raw aluminum), lived-in leather-toned grime around cockpits/nacelles only. Bonus: air-unit (flying-wing/fuselage/airship) cost or speed specialization.

Note: wear-level spans full spectrum (2 showroom-pristine, 2 pristine-with-a-twist, 2 lived-in/weathered, 2 scavenged/battle-worn, 2 with genuinely unique wear chromatics — frost-white and brass-gold, not just "more rust") so the roster doesn't converge on "everyone just gets rustier." Bonus-flavor spans economy/combat/utility-vision/unit-class-specialization so no two factions reward the same playstyle.

## 4. Map/Terrain Texture Direction
Governing rule: terrain saturation/brightness sits below unit paint; instant tactical legibility beats prettiness. Keep natural terrain roughness high/matte (glossy dirt reads as plastic/toy — the wrong kind of goofy). Reserve the brushed-metal anisotropic language for MAN-MADE terrain only (bridges, urban structures, resource-node machinery) — organic terrain = matte painterly, manufactured terrain = brushed metal family, doubling as a passive "capturable/interactable" cue. Maintain strong value (not just hue) separation between adjacent terrain types for readability at fast pan/small-icon scale. Avoid pure saturated primaries anywhere in terrain.

- **Open ground:** warm desaturated ochre-green, matte, two-scale noise (large mottling + fine grain for tread-track readability). The neutral baseline.
- **Marsh/swamp:** darker/cooler/murkier green-brown, sheen ONLY in standing-water pockets not the mud itself. Bayou Irregulars' camo palette intentionally sits close to this hue family (their camo bonus made visible) but terrain should stay a notch darker/duller than even their paint so non-Irregular units don't also vanish.
- **Rocky terrain:** cooler grey-brown, higher-frequency chunky normal/roughness detail, harder value-contrast between faces and crevices — reads "hard and blocky" at a glance.
- **Snow vs. mud (split, not one look):** Snow = bright warm-white (not blue-white, ties to warm-aluminum temperature target), blue-shadow only in recesses/tracks. Mud = dark saturated brown, GLOSSY — the one deliberate exception to matte-terrain rule, since wet mud is genuinely reflective and the gloss itself is the "this will slow you down" readability cue.
- **Soft sand:** warm light tan, matte, soft low-frequency dune-shaped normal (not chunky like rock) — silhouette alone should read "soft and slow."
- **Shallow/deep water:** shallow = lighter, more saturated teal-blue, visible terrain-bed detail underneath (communicates crossable/amphibious-passable); deep = darker, desaturated, opaque (naval-only, ground units stop here). Treat the shallow/deep boundary as a soft-edged but clearly-valued transition line, not an ambiguous gradient — it's a hard gameplay boundary.
- **Elevated plateaus:** same base terrain coloring as what's below (open ground on a plateau still reads as open ground) but warm rim-light/cliff-face treatment on vertical faces w/ slightly metallic/brushed rock-strata normal (restrained nod to brushed language, still mostly natural) so elevation reads as silhouette break even before shadow sells it.
- **Urban/city structures:** brushed-metal-family shader (rusted/worn concrete-and-metal, panel lines, rivets) but STRICTLY NEUTRAL, no-faction-tint palette (weathered concrete grey, oxidized rebar-rust, faded neutral signage) — reads as "the world," not belonging to any faction.
- **Bridges:** full brushed-aluminum treatment, unambiguously manufactured — hazard-stripe edge markings from the shared decal library, NEUTRAL-tinted (not faction-tinted), since bridges are a chokepoint/hazard players need to spot instantly.
- **Resource nodes:** recommend their own fixed neutral high-saturation industrial yellow/orange (hazard-adjacent, not faction-adjacent, not terrain-adjacent) purely for at-a-glance economy-target legibility, like traffic-cone orange.

## 5. Suggested Implementation Priority
1. Build shared shader + mask-bake pipeline against ONE hull and ONE module first, validate the stretch/scale handling (section 2.4) before touching faction data at all — this is the one piece of real technical risk in the whole system.
2. Author the 3 existing factions as data rows against that shader to prove the parameter set covers the intended range.
3. Add remaining 7 factions purely as data once the shader is proven — should require zero new shader logic.
4. Terrain shader work can proceed in parallel, reconnecting only at the urban/bridges brushed-metal touchpoint.
