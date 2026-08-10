"""Victory and defeat. Short, one-shot, never looped.

These replace sfx_victory.wav and sfx_defeat.wav, which were a C major triad
and an A minor triad respectively - four sine waves each, held for 1.5 seconds
under an exponential decay. That is a chord, not a cue.

BOTH STAY IN THE SHARED KEY AND PALETTE. A victory fanfare in a brighter key
with different instruments would sound like it came from another game, and the
moment it plays is the moment the player is most attentive. Victory earns its
lift by moving from A phrygian to A major - the one time the flat second is
abandoned - rather than by changing register.

Neither loops. audio_manager.gd plays these once and returns to the bed.
"""

from __future__ import annotations

from .. import instruments as I
from .. import sequencer as S
from . import build

CLOCK = S.Clock(bpm=96.0, steps_per_beat=4, beats_per_bar=4)
BAR = CLOCK.steps_per_bar


def victory() -> dict:
    seed = "victory"
    bars = 6

    horns = S.Track("brass", I.brass, gain=0.95, pan=-0.1, stem="bed")
    strings = S.Track("strings", I.low_strings, gain=0.7, pan=0.12, stem="bed")
    drums = S.Track("snare", I.snare, gain=0.7, stem="bed")
    kick = S.Track("kick", I.kick, gain=0.9, stem="bed")
    anvils = S.Track("anvil", I.anvil, gain=0.5, pan=0.3, stem="bed")

    # Rising: Am -> F -> G -> A MAJOR. The picardy third at the end is the
    # whole gesture - phrygian all game, and then it resolves bright.
    horns.add(S.chord(0 * BAR, ("a2", "c3", "e3"), steps=10, vel=0.85))
    horns.add(S.chord(0 * BAR + 12, ("f2", "a2", "c3"), steps=8, vel=0.85))
    horns.add(S.chord(1 * BAR + 4, ("g2", "b2", "d3"), steps=10, vel=0.9))
    horns.add(S.chord(2 * BAR, ("a2", "c#3", "e3", "a3"), steps=BAR * 3, vel=1.0))

    strings.add(S.chord(0, ("a1", "e2"), steps=BAR * 2, vel=0.6))
    strings.add(S.chord(2 * BAR, ("a1", "e2", "a2"), steps=BAR * 3, vel=0.7))

    drums.add(S.hits("o o x . o o x . x . x . X . . ."))
    drums.add(S.shift(S.hits("o o x o o o x o X . . . . . . ."), 1 * BAR))
    kick.add(S.hits("x . . . x . . . x . . . x . . ."))
    kick.add(S.shift(S.hits("x . . . x . . . x . x . x . . ."), 1 * BAR))
    kick.add(S.shift(S.hits("x . . . . . . . . . . . . . . ."), 2 * BAR))
    anvils.add(S.shift(S.hits("x . . . . . . . . . . . . . . ."), 2 * BAR))

    return build([horns, strings, drums, kick, anvils], CLOCK, bars, seed,
                 tail=3.0, loudness=0.84)


def defeat() -> dict:
    seed = "defeat"
    bars = 6

    horns = S.Track("brass", I.brass, gain=0.75, pan=-0.1, stem="bed")
    strings = S.Track("strings", I.low_strings, gain=0.95, pan=0.1, stem="bed")
    pipes = S.Track("pipe", I.pipe, gain=0.55, pan=0.25, stem="bed")

    # Sinking: Am -> F -> Bb -> A, each entry lower and quieter. No drums at
    # all - the machine has stopped, which is the point.
    horns.add(S.chord(0, ("a2", "c3", "e3"), steps=BAR, vel=0.7))
    horns.add(S.chord(1 * BAR, ("f2", "a2", "c3"), steps=BAR, vel=0.55))
    horns.add(S.chord(2 * BAR, ("bb1", "d2", "f2"), steps=BAR, vel=0.45))
    horns.add(S.chord(3 * BAR, ("a1", "c2", "e2"), steps=BAR * 3, vel=0.4))

    strings.add(S.chord(0, ("a1", "e2"), steps=BAR * 2, vel=0.65))
    strings.add(S.chord(2 * BAR, ("bb0", "f1"), steps=BAR * 2, vel=0.6))
    strings.add(S.chord(3 * BAR, ("a0", "a1"), steps=BAR * 3, vel=0.7))

    # A single struck pipe at the top, and one more as it dies away.
    pipes.add(S.hits("x . . . . . . . . . . . . . . ."))
    pipes.add(S.shift(S.hits("x . . . . . . . . . . . . . . ."), 3 * BAR))

    return build([horns, strings, pipes], CLOCK, bars, seed,
                 tail=3.5, loudness=0.70)
