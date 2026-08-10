"""The songs, plus the mastering chain and the key they all share.

MUSICAL BRIEF, and how the two design docs were reconciled.
UX_REDESIGN_PLAN.md asked for "cold-war register - brass, low strings,
tape-saturated, no synthwave". The stated direction for this pass is Frank
Klepacki. Those look like they collide and do not: *Hell March* is an industrial
rhythm section with cold-war brass over the top, and both descriptions agree on
tape saturation and on rejecting synthwave. The resolution adopted here, and
written back into UX_REDESIGN_PLAN.md so the doc stops disagreeing with the
shipped assets:

    Industrial rock rhythm section, cold-war brass and low strings carrying
    the hook, tape-saturated.

EVERYTHING IS IN A PHRYGIAN. A, Bb, C, D, E, F, G - a natural minor with a
flattened second. That flat second is the entire harmonic signature of the
style: it is what makes the root-to-flat-two move sound martial and faintly
Eastern rather than merely sad, and it is why these tracks read as a family
even though they differ in tempo and instrumentation.

STEMS, NOT SEPARATE COMBAT AND TENSION SONGS. The skirmish track renders as
three layers - bed / rhythm / lead - which audio_manager.gd plays on three
synchronised players and mixes by combat intensity. Crossfading between two
different pieces of music every time a skirmish heats up would be far more
noticeable than raising a layer, and it also cannot ramp continuously.
"""

from __future__ import annotations

import numpy as np

from .. import dsp as d
from .. import sequencer as S

# The shared key, recorded here as the single fact every track module has to
# agree on. The riffs themselves are written with note names rather than degrees
# because "a1 a1 . a1 bb1" reads as music in a way "0 0 . 0 1" does not.
ROOT = "a"
PHRYGIAN = [0, 1, 3, 5, 7, 8, 10]     # semitones from the root - the flat 2 is the signature


def master(stereo: np.ndarray, seed: str, *, loudness: float = 0.82,
           tape_amount: float = 1.0, width: float = 1.25) -> np.ndarray:
    """The shared mastering chain. Applied per stem.

    APPLIED PER STEM RATHER THAN TO THE SUM, because the stems are summed at
    runtime by the engine and never exist as one file. That is a real
    constraint on the chain: anything with strong programme-dependent gain
    (a slow limiter, multiband compression) would pump differently depending
    on which layers happened to be audible, so this is deliberately restricted
    to per-stem-stable processing - saturation, a gentle bus compressor, and
    width.
    """
    left = d.compress(stereo[:, 0], threshold_db=-20.0, ratio=2.6,
                      attack=0.012, release=0.20)
    right = d.compress(stereo[:, 1], threshold_db=-20.0, ratio=2.6,
                       attack=0.012, release=0.20)

    out = np.column_stack([
        d.tape(left, wow=0.35 * tape_amount, flutter=0.22 * tape_amount,
               saturation=1.5, hf_rolloff=13500.0, seed=seed + ":tapeL"),
        d.tape(right, wow=0.35 * tape_amount, flutter=0.22 * tape_amount,
               saturation=1.5, hf_rolloff=13500.0, seed=seed + ":tapeR"),
    ])
    out = d.widen(out, amount=width, bass_mono_below=170.0)
    return d.normalize(out, loudness)


def build(tracks, clock: S.Clock, bars: int, seed: str,
          *, tail: float = 2.4, **master_kw) -> dict:
    """Render, fold the loop tail back, and master each stem."""
    stems = S.render(tracks, clock, bars, seed, tail=tail)
    out = {}
    for name, buf in stems.items():
        looped = S.loop_seam(buf, clock, bars)
        out[name] = master(looped, f"{seed}:{name}", **master_kw)
    return out


from . import lab, menu, operations, skirmish, stingers  # noqa: E402

# name -> zero-argument callable returning {stem_name: stereo array}.
# sfx.py walks this to render everything, and the GDScript music state machine
# names these same keys.
REGISTRY = {
    "menu": menu.render,
    "lab": lab.render,
    "skirmish": skirmish.render,
    "operations": operations.render,
    "victory": stingers.victory,
    "defeat": stingers.defeat,
}

# Tracks that loop. The stingers do not - a victory fanfare that repeats is a
# distinctly amateur touch, and audio_manager.gd returns to the bed after one.
LOOPING = {"menu", "lab", "skirmish", "operations"}
