"""Design Lab. A workshop, not a battlefield.

THE HARD CONSTRAINT HERE IS DURATION OF EXPOSURE. The Lab is where a player
spends the longest single uninterrupted stretch, concentrating on a fiddly
spatial task. Anything with a strong hook, a fast pulse or a clear melodic
period becomes actively hostile after fifteen minutes - the player starts
hearing the loop instead of thinking about their design.

So this is a bed rather than a song: no drum kit, no melody, no brass. What it
does keep is the key and the struck-metal palette, so it belongs to the same
world as the battle music. The pulse is a workshop pulse - a slow, soft
machine-room thump rather than a kick.

`UI_STYLE_GUIDE.md`'s framing of the interface as "an instrument housing" is
the right reference for this track too.
"""

from __future__ import annotations

from .. import instruments as I
from .. import sequencer as S
from . import build

BPM = 84.0
BARS = 24
CLOCK = S.Clock(bpm=BPM, steps_per_beat=4, beats_per_bar=4, swing=0.06)
BAR = CLOCK.steps_per_bar

PULSE = "x . . . . . . . . . . . x . . ."
TICK = ". . . . x . . . . . . . . . x ."


def render() -> dict:
    seed = "lab"

    strings = S.Track("strings", I.low_strings, gain=0.95, pan=-0.2, stem="bed")
    # Four-bar harmonic cycle, deliberately ambiguous - it never resolves, so
    # there is no cadence for the ear to latch onto and start anticipating.
    PROGRESSION = ["a1", "f1", "g1", "f1", "a1", "c2", "g1", "f1"]
    for i in range(BARS):
        held = " ".join([PROGRESSION[i % 8]] + ["-"] * (BAR - 1))
        strings.add(S.shift(S.riff(held, vel=0.5), i * BAR))

    pulse = S.Track("pulse", I.pipe, gain=0.35, pan=0.15, stem="bed")
    pulse.add(S.repeat(S.hits(PULSE), BARS, BAR))

    # Sparse struck metal, panned wide, at a period that does not divide the
    # bar evenly - so it never lines up the same way twice within the loop.
    ticks = S.Track("tick", I.metal_hit, gain=0.16, pan=0.45, stem="bed")
    for i in range(0, BARS, 3):
        ticks.add(S.shift(S.hits(TICK), i * BAR))

    ticks_l = S.Track("tick_l", I.metal_hit, gain=0.12, pan=-0.5, stem="bed")
    for i in range(2, BARS, 5):
        ticks_l.add(S.shift(S.hits(TICK), i * BAR + 6))

    sub = S.Track("sub", I.power_bass, gain=0.3, stem="bed")
    for i in range(0, BARS, 2):
        sub.add(S.shift(S.riff("a0 - - - - - - - - - - - - - - .", vel=0.42),
                        i * BAR))

    return build([strings, pulse, ticks, ticks_l, sub], CLOCK, BARS, seed,
                 loudness=0.62, tape_amount=1.2, width=1.4)
