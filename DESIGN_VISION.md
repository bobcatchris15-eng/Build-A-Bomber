# Design Vision (from Chris, 2026-07-11)

This document exists so the reference points below survive across sessions/context resets. Read it before touching the Design Lab.

## Reference points

- **Spore's Creature/Vehicle Creator** — continuous stretch/deform.
- **KSP's Vehicle Assembly Building (VAB)** — symmetry modes + Advanced Tweakables.
- **Forged Battalion got close to the vibe but felt shallow.** Reviews confirm why: locked to 4 unit types per factory (16 total), weapons barely differentiated (same range/armor multipliers across the board), and beyond picking a weapon/propulsion/armor from a short list there's no way to tweak anything — no visual customization beyond color. **This is the failure mode to design away from.**

## Concrete mechanics to borrow

### From Spore
- Continuous stretch/deform on body and limbs (metaballs), **not discrete part swaps** — dragging a limb longer/fatter reshapes it smoothly and live-updates stat bars (health/power/speed).
- Hand-authored "rigblocks" (weapons, mouths, etc.) snap onto the body but still carry their own scale/stretch degrees of freedom.
- Editing is symmetric by default (mirrors across the center axis).

### From KSP's VAB
- Symmetry mode (radial up to 8x, or mirror, toggle key) — placing one part places its mirrored siblings too.
- "Advanced Tweakables" — right-click any part for a mini-panel of sliders/toggles (thrust limiter %, gimbal range, staging/deploy angle, fuel priority) that adjust continuous values without leaving the editor and immediately affect stats.
- Precise placement tools (angle snap, free offset, free rotation) for fine control beyond snap points.

## The actual design goal — this is the test for whether the Design Lab is working

> **Two players independently building "a heavily armored frontline anti-air unit" should land on functionally distinct units** — not because they picked different discrete parts, but because they set continuous tweaks differently (barrel length vs. traverse speed vs. magazine size vs. how armor mass is distributed, etc.).

If two "same concept" builds converge to be nearly identical, or if the only differentiation comes from swapping a part off a short list, **that's the Forged Battalion trap.**

## How this factors into current work

- Fold into the Sunday [Design_Lab_UI_UX.md](Design_Lab_UI_UX.md) gap audit specifically: check whether weapons/armor/modules currently support only discrete swaps vs. **continuous tweakable parameters with live stat feedback**, and whether **symmetry-aware editing** exists end-to-end (not just a toggle that's a no-op).
- This is probably the highest-leverage gap to close this week — ahead of pure visual/mesh polish.
- Any gap-audit finding or implementation decision should be checked against the differentiation test above before being marked done: can two players building "the same concept" diverge meaningfully through tweaks alone?
