"""The battle track. The one the player hears for forty minutes at a stretch.

55 seconds, 32 bars at 140 BPM, A phrygian, rendered as three synchronised
stems that audio_manager.gd mixes by combat intensity:

    bed     low strings, struck pipe, a sparse root pulse.
            ALWAYS AUDIBLE. This is what a quiet base-building stretch sounds
            like, so it has to be listenable on its own for a long time - which
            is why it has no drums and no hook, and why it moves slowly.
    rhythm  kick, snare, hats, the guitar ostinato and the bass.
            Fades in as soon as anything is shooting. This is the Klepacki
            engine: relentless sixteenths on the root.
    lead    brass hook, anvil accents, the melodic statement.
            Only at real engagement intensity. Kept SPARSE on purpose - a hook
            that plays constantly is the fastest way to make a looping track
            unbearable, so it sits out roughly half the form.

WHY 32 BARS AND NOT 8. A short loop is cheaper to render and much worse to
live with; the ear locks onto the period and then hears nothing else. 60
seconds with an internal A/B/break/A' structure means the repeat is far enough
apart to stay background.
"""

from __future__ import annotations

from .. import instruments as I
from .. import sequencer as S
from . import build

BPM = 140.0
BARS = 32
CLOCK = S.Clock(bpm=BPM, steps_per_beat=4, beats_per_bar=4)
BAR = CLOCK.steps_per_bar          # 16 steps


# --- The riff ----------------------------------------------------------------
#
# Root-heavy sixteenths with the flat second (bb) and flat seventh (g) as the
# only moves. That restraint is the point: the riff is a rhythm part that
# happens to have pitch, and every note that is not the root is an event.

RIFF_A = "a1 a1 . a1 a1 . a1 a1 . a1 bb1 . a1 . g1 ."
RIFF_B = "a1 a1 . a1 a1 . a1 a1 . c2 bb1 . a1 -  -  - "
RIFF_C = "a1 a1 . a1 g1 -  . f1 f1 . g1 .  a1 -  -  - "   # the turnaround

# Drums. Kick pushes the "and" of 3, which is what gives the pattern its
# forward lean rather than sitting square on the beat.
KICK = "x . x . x . . x x . x . x . . x"
KICK_FILL = "x . x . x . . x x . x x x . x x"
SNARE = ". . . . x . . . . . . . x . . ."
SNARE_MARCH = ". . . . x . o o . . o . x . o o"
HAT = "x . x . x . x . x . x . x . x ."
HAT_DRIVE = "x o x o x o x o x o x o x o x o"
ANVIL = ". . . . . . . . . . . . . . x ."
PIPE = "x . . . . . . . x . . . . . . ."


def render() -> dict:
    seed = "skirmish"

    # --- bed ----------------------------------------------------------------
    strings = S.Track("strings", I.low_strings, gain=0.85, pan=-0.15, stem="bed")
    # Slow root/flat-six/flat-seven movement under everything, one chord per
    # bar, so it reads as harmony rather than as a part.
    PROGRESSION = ["a1", "a1", "f1", "f1", "a1", "a1", "g1", "g1"]
    for i in range(BARS):
        held = " ".join([PROGRESSION[i % len(PROGRESSION)]] + ["-"] * (BAR - 1))
        strings.add(S.shift(S.riff(held, vel=0.55), i * BAR))

    pipes = S.Track("pipe", I.pipe, gain=0.5, pan=0.25, stem="bed")
    pipes.add(S.repeat(S.hits(PIPE), BARS, BAR))

    sub = S.Track("sub", I.power_bass, gain=0.35, pan=0.0, stem="bed")
    for i in range(BARS):
        sub.add(S.shift(S.riff("a0 - - - - - - - . . . . . . . .", vel=0.5),
                        i * BAR))

    # THE BED NEEDS SOMETHING ABOVE 6 kHz. Measured on the first render, the
    # bed was 45 dB darker than the rhythm stem in the top band, because low
    # strings, a struck pipe and a sub have essentially no air between them.
    # That is not a mixing nicety: the bed is what plays ALONE during a quiet
    # base-building stretch, so its spectrum is the spectrum of the game most
    # of the time, and on its own it sounded like the music was playing through
    # a wall. Sparse high struck metal, panned wide and pitched well above the
    # harmony, fixes it without adding a part the ear has to track.
    ticks = S.Track("tick", I.metal_hit, gain=0.13, pan=0.5, stem="bed")
    ticks_l = S.Track("tick_l", I.metal_hit, gain=0.10, pan=-0.55, stem="bed")
    TICK = ". . . . . . . . . . . x . . . ."
    for i in range(0, BARS, 2):
        ticks.add(S.shift(S.hits(TICK), i * BAR))
    # Offset by an odd number of bars so the two sides never coincide inside
    # the loop - the pattern stays unpredictable without ever being busy.
    for i in range(3, BARS, 5):
        ticks_l.add(S.shift(S.hits(TICK), i * BAR + 4))

    # --- rhythm -------------------------------------------------------------
    kick = S.Track("kick", I.kick, gain=1.15, pan=0.0, stem="rhythm")
    snare = S.Track("snare", I.snare, gain=0.92, pan=0.08, stem="rhythm")
    hats = S.Track("hat", I.hat, gain=0.42, pan=-0.22, stem="rhythm")
    gtr = S.Track("gtr", I.guitar_chug, gain=0.82, pan=0.38, stem="rhythm")
    gtr2 = S.Track("gtr2", I.guitar_chug, gain=0.82, pan=-0.38, stem="rhythm")
    bass = S.Track("bass", I.power_bass, gain=0.95, pan=0.0, stem="rhythm")

    # THE FORM. Bars 0-3 intro (bed only), 4-11 riff A, 12-19 riff B with the
    # hook, 20-23 break, 24-31 riff A' full.
    riff_bars = list(range(4, 20)) + list(range(24, 32))
    for i in riff_bars:
        pattern = RIFF_A if (i % 8) < 6 else (RIFF_C if i % 8 == 7 else RIFF_B)
        if 12 <= i < 20:
            pattern = RIFF_B if (i % 4) < 3 else RIFF_C
        gtr.add(S.shift(S.riff(pattern, vel=0.9), i * BAR))
        gtr2.add(S.shift(S.riff(pattern, vel=0.82), i * BAR))
        bass.add(S.shift(S.riff(pattern, vel=0.85, octave_shift=-1), i * BAR))

        is_fill = (i % 8) == 7
        kick.add(S.shift(S.hits(KICK_FILL if is_fill else KICK), i * BAR))
        snare.add(S.shift(S.hits(SNARE_MARCH if 12 <= i < 20 else SNARE), i * BAR))
        hats.add(S.shift(S.hits(HAT_DRIVE if i >= 24 else HAT), i * BAR))

    # The break (bars 20-23): drums out, guitar out, so the bed is exposed and
    # the return at bar 24 lands. A track with no hole in it has no dynamics.
    for i in range(20, 24):
        snare.add(S.shift(S.hits(SNARE_MARCH), i * BAR))

    # --- lead ---------------------------------------------------------------
    horns = S.Track("brass", I.brass, gain=0.7, pan=-0.10, stem="lead")
    anvils = S.Track("anvil", I.anvil, gain=0.35, pan=0.35, stem="lead")
    lead = S.Track("lead", I.lead_synth, gain=0.45, pan=0.12, stem="lead")

    # Brass hook over bars 12-19: Am - Bb - G - Am, stabbed rather than held.
    hook_chords = [
        ("a2", "c3", "e3"),      # Am
        ("bb2", "d3", "f3"),     # Bb  - the phrygian flat two
        ("g2", "bb2", "d3"),     # G
        ("a2", "c3", "e3"),      # Am
    ]
    for k, notes in enumerate(hook_chords):
        base = (12 + k * 2) * BAR
        horns.add(S.chord(base + 0, notes, steps=3, vel=0.95))
        horns.add(S.chord(base + 6, notes, steps=2, vel=0.75))
        horns.add(S.chord(base + 10, notes, steps=6, vel=0.85))

    # A' section: the same harmony, played longer and with the melody on top.
    for k, notes in enumerate(hook_chords):
        base = (24 + k * 2) * BAR
        horns.add(S.chord(base, notes, steps=12, vel=0.8))

    melody = "a3 -  -  bb3 - a3 -  g3 -  -  f3 -  -  -  -  - "
    melody2 = "e3 -  f3 -  -  g3 -  -  a3 -  -  -  -  -  -  - "
    for k, line in enumerate([melody, melody2, melody, melody2]):
        lead.add(S.shift(S.riff(line, vel=0.8), (24 + k * 2) * BAR))

    for i in list(range(12, 20)) + list(range(24, 32)):
        anvils.add(S.shift(S.hits(ANVIL), i * BAR))

    tracks = [strings, pipes, sub, ticks, ticks_l, kick, snare, hats,
              gtr, gtr2, bass, horns, anvils, lead]
    return build(tracks, CLOCK, BARS, seed, loudness=0.80)
