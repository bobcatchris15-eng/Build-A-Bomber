# Decisions Needed / Judgment Calls Log

Newest entries first. Each entry: the question, the default I'm proceeding with, and why. Anything marked **BLOCKING** means I stopped that thread entirely and need Chris's input before continuing it — everything else is "proceeding on best judgment, flagging for review."

---

## 2026-07-12 — Armor "mass distribution" example in DESIGN_VISION.md conflicts with an existing, deliberate design decision

**Not blocking — proceeding on the documented default, flagging for confirmation.**

`DESIGN_VISION.md` (from this week's conversation) uses "how armor mass is distributed" as an example of the kind of continuous tweak that should let two players' builds diverge. But [Damage_And_Armor_Model.md](Damage_And_Armor_Model.md) — an existing repo doc, presumably from an earlier deliberate design pass — explicitly rejects individual/spatial armor plate placement: *"Placing individual armor plates manually is tedious, often results in visually messy designs, and slows down the player. To solve this, base armoring is handled at the Hull level rather than as individual placeable modules."*

**Default I'm proceeding with:** I am NOT building a spatial/per-zone armor placement system this week. The existing hull-level Armor Material (4-choice dropdown) × Armor Thickness (continuous 0.5–3.0x slider) already gives two real axes of differentiation, just not a spatial one. I'm treating that as "good enough" for the differentiation test rather than overriding a considered prior decision on a guess.

**Why flagged rather than just decided:** this is a genuine values conflict between two of Chris's own docs, not an implementation detail — worth 30 seconds of his confirmation when he's back rather than me picking a side permanently.

---

## 2026-07-12 — Directional/facing armor thresholds are documented but not implemented (deprioritized this week)

**Not blocking — deferred, not forgotten.**

Damage_And_Armor_Model.md's counter-play section explicitly describes weaker rear armor as a real mechanic: *"drive circles around the heavy unit... attack the weaker rear armor (directional thresholds)."* Grepping `battle_unit.gd`'s damage/threshold code found only a single uniform threshold per damage class — no facing/hit-angle logic exists.

**Default I'm proceeding with:** not implementing this. It's a combat-simulation feature, not a Design Lab mechanic, and Chris's instructions this week are explicitly Design-Lab-mechanics-first ("ahead of pure visual/mesh polish" — this is arguably behind even that). Logging it so it isn't lost, not touching it.

---

## 2026-07-12 — Firing arc visualization (Design_Lab_UI_UX.md) is unimplemented; deferring behind tweak-depth work

**Not blocking.**

Design_Lab_UI_UX.md calls the firing-arc cone visualization ("Radar Sweep") "an absolute necessity," but it doesn't exist in the current build — placement is freeform (raycast onto hull surface) with a clipping/collision check (which *does* work and blocks saving), but no arc-of-fire feedback. This is a UX-legibility gap, not a differentiation-mechanics gap.

**Default I'm proceeding with:** treating this as a stretch goal for later in the week (Wed/Thu) if the higher-priority tweak-depth and mesh-gap work leaves runway, per Chris's explicit "highest-leverage gap first" instruction. Not skipping it forever — just sequencing it after the things DESIGN_VISION.md actually asked to be audited for.

---

## 2026-07-12 — Keeping freeform module placement (not adding grid-snap)

**Not blocking.**

Design_Lab_UI_UX.md also specifies a hex/square surface grid that constrains placement to snap points. The current implementation is fully freeform (raycast-based placement anywhere on the hull surface, constrained only by collision/clipping checks). Adding grid-snap would be a regression relative to DESIGN_VISION.md's Spore-style continuous-placement spirit and the differentiation test (freeform position is itself a differentiation axis — where exactly a weapon sits affects its arc/exposure).

**Default I'm proceeding with:** leaving placement freeform, not adding grid-snap. Flagging the doc tension (Design_Lab_UI_UX.md predates DESIGN_VISION.md) rather than silently ignoring the older doc.
