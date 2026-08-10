"""Operations map. Between missions: planning, not fighting.

Sits deliberately between the menu and the skirmish in intensity. There is a
pulse and there is harmonic movement, but the guitar never enters and the brass
is muted and low - the register of a briefing room rather than an engagement.

The marching snare is the one element that carries forward from the battle
track, because on a strategic map it reads as anticipation.
"""

from __future__ import annotations

from .. import instruments as I
from .. import sequencer as S
from . import build

BPM = 100.0
BARS = 24
CLOCK = S.Clock(bpm=BPM, steps_per_beat=4, beats_per_bar=4)
BAR = CLOCK.steps_per_bar

KICK = "x . . . . . . . x . . . . . . ."
MARCH = ". . o . x . o o . . o . x . o ."
PIPE = "x . . . . . . . . . . . . . . ."


def render() -> dict:
    seed = "operations"

    strings = S.Track("strings", I.low_strings, gain=0.9, pan=-0.16, stem="bed")
    PROGRESSION = ["a1", "a1", "bb1", "bb1", "f1", "f1", "g1", "g1"]
    for i in range(BARS):
        held = " ".join([PROGRESSION[i % 8]] + ["-"] * (BAR - 1))
        strings.add(S.shift(S.riff(held, vel=0.55), i * BAR))

    kick = S.Track("kick", I.kick, gain=0.7, stem="bed")
    snare = S.Track("snare", I.snare, gain=0.5, pan=0.1, stem="bed")
    pipes = S.Track("pipe", I.pipe, gain=0.4, pan=0.3, stem="bed")
    horns = S.Track("brass", I.brass, gain=0.5, pan=-0.14, stem="bed")
    bass = S.Track("bass", I.power_bass, gain=0.6, stem="bed")

    for i in range(BARS):
        kick.add(S.shift(S.hits(KICK), i * BAR))
        pipes.add(S.shift(S.hits(PIPE), i * BAR))
        if i >= 4:
            snare.add(S.shift(S.hits(MARCH), i * BAR))
        bass.add(S.shift(S.riff(
            " ".join([PROGRESSION[i % 8].replace("1", "0")] + ["-"] * 7
                     + ["."] * 8), vel=0.6), i * BAR))

    # Low, held brass - a signal flare, not a fanfare.
    for k, notes in enumerate([("a2", "e3"), ("bb2", "f3"), ("f2", "c3"),
                               ("g2", "d3")]):
        horns.add(S.chord((8 + k * 2) * BAR, notes, steps=28, vel=0.55))
        horns.add(S.chord((16 + k * 2) * BAR, notes, steps=28, vel=0.48))

    return build([strings, kick, snare, pipes, horns, bass], CLOCK, BARS, seed,
                 loudness=0.74)
