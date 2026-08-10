"""Front desk. The first thing anyone hears, and the tone-setter.

Same key and same riff DNA as the skirmish track, held back. The main menu is
not a battle, so the full kit would be writing a cheque the screen does not
cash - but it has to promise the battle, or the transition into a skirmish
feels like a different game.

Restraint here is concrete: no snare until halfway, the guitar plays half as
many notes, and the brass states the hook once and then leaves.
"""

from __future__ import annotations

from .. import instruments as I
from .. import sequencer as S
from . import build

BPM = 120.0
BARS = 24
CLOCK = S.Clock(bpm=BPM, steps_per_beat=4, beats_per_bar=4)
BAR = CLOCK.steps_per_bar

RIFF = "a1 .  a1 .  a1 .  .  a1 .  .  bb1 -  .  .  g1 - "
KICK = "x . . . . . . . x . . . . . . ."
KICK_FULL = "x . . . . . x . x . . . . . . ."
SNARE = ". . . . . . . . x . . . . . . ."
PIPE = "x . . . . . . . . . . . x . . ."


def render() -> dict:
    seed = "menu"

    strings = S.Track("strings", I.low_strings, gain=0.9, pan=-0.18, stem="bed")
    PROGRESSION = ["a1", "a1", "f1", "g1"]
    for i in range(BARS):
        held = " ".join([PROGRESSION[i % 4]] + ["-"] * (BAR - 1))
        strings.add(S.shift(S.riff(held, vel=0.6), i * BAR))

    pipes = S.Track("pipe", I.pipe, gain=0.45, pan=0.28, stem="bed")
    pipes.add(S.repeat(S.hits(PIPE), BARS, BAR))

    kick = S.Track("kick", I.kick, gain=0.85, stem="bed")
    snare = S.Track("snare", I.snare, gain=0.6, pan=0.06, stem="bed")
    gtr = S.Track("gtr", I.guitar_chug, gain=0.68, pan=0.30, stem="bed")
    bass = S.Track("bass", I.power_bass, gain=0.75, stem="bed")
    horns = S.Track("brass", I.brass, gain=0.62, pan=-0.12, stem="bed")

    for i in range(BARS):
        # The riff enters at bar 4, the kick at 2, the snare not until 12.
        if i >= 2:
            kick.add(S.shift(S.hits(KICK_FULL if i >= 12 else KICK), i * BAR))
        if i >= 12:
            snare.add(S.shift(S.hits(SNARE), i * BAR))
        if i >= 4:
            gtr.add(S.shift(S.riff(RIFF, vel=0.75), i * BAR))
            bass.add(S.shift(S.riff(RIFF, vel=0.8, octave_shift=-1), i * BAR))

    # One statement of the hook, bars 16-19, then it gets out of the way.
    for k, notes in enumerate([("a2", "c3", "e3"), ("bb2", "d3", "f3"),
                               ("g2", "bb2", "d3"), ("a2", "c3", "e3")]):
        horns.add(S.chord((16 + k) * BAR, notes, steps=14, vel=0.7))

    return build([strings, pipes, kick, snare, gtr, bass, horns],
                 CLOCK, BARS, seed, loudness=0.76)
