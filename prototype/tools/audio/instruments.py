"""Patches. Knows about timbre, nothing about songs.

Every instrument has the same signature so the sequencer can treat them
interchangeably:

    instrument(freq, dur, vel, seed) -> mono np.ndarray

`freq` is 0.0 for unpitched percussion. `seed` is per-note, which is what stops
a repeated hi-hat being bit-identical sixteen times a bar - the difference
between "a sample triggered repeatedly" and "someone playing" is almost entirely
that micro-variation.

THE PALETTE IS CHOSEN, NOT GENERIC. The brief is Frank Klepacki's C&C-era
scoring, which is a specific and quite narrow set of sounds:

  * a distorted, palm-muted ostinato riff carrying the whole track, usually on
    the root and flat-second/flat-fifth of a minor or phrygian scale
  * a rhythm section that is half rock kit and half industrial noise - anvils,
    pipes, struck metal alongside the kick and snare
  * brass stabs and low strings for the hook, which is the "cold-war" half that
    UX_REDESIGN_PLAN.md asks for and the reason this does not come out sounding
    like synthwave
  * everything glued together with tape saturation

So there is a guitar patch and a brass patch and a modal-metal patch, and there
is deliberately no pad, no supersaw lead, and no side-chained arpeggio.
"""

from __future__ import annotations

import numpy as np

from . import dsp as d


# --- Bass and guitar ---------------------------------------------------------

def power_bass(freq, dur, vel=1.0, seed="bass"):
    """Distorted saw bass with a filter envelope. Carries the riff.

    Two octaves stacked: the sub is a clean sine (so the low end stays defined
    after distortion, which otherwise smears it) and the body is a driven saw.
    """
    dur = max(dur, 0.05)
    sub = d.sine(freq, dur) * 0.9
    body = d.supersaw(freq, dur, voices=3, detune=0.006, seed=seed)

    # Filter envelope: opens fast, closes to a growl. This movement is what
    # makes a repeated root note sound played rather than held.
    cutoff = d.breakpoints(dur, [(0.0, freq * 14.0), (0.06, freq * 7.0),
                                 (1.0, freq * 3.0)])
    body = d.sweep_filter(body, "lp", np.clip(cutoff, 120.0, 9000.0), q=1.9)
    body = d.drive(body, 5.0)

    env = d.adsr(dur, attack=0.004, decay=0.09, sustain=0.72,
                 release=min(0.09, dur * 0.4), curve=1.6)
    return (sub * 0.60 + body * 0.85) * env * vel


def guitar_chug(freq, dur, vel=1.0, seed="gtr"):
    """Palm-muted distorted guitar. The single most identifying sound here.

    'Palm muted' means a very fast decay and a strong low-mid honk - the string
    is damped, so what survives is the pick attack and the amplifier. The cab
    simulation is a band-pass plus two resonant peaks, which is a crude but
    effective stand-in for a real impulse response and needs no IR file.
    """
    dur = max(dur, 0.04)
    g = d.rng(seed)

    # Slight detune between two saws: one guitar double-tracked, which is how
    # this part would actually be recorded. The sub-octave square is what gives
    # the riff its floor - a drop-tuned guitar's lowest string is the point.
    osc = (d.saw(freq * (1.0 + g.uniform(-0.003, 0.003)), dur)
           + d.saw(freq * 2.0 * (1.0 + g.uniform(-0.004, 0.004)), dur) * 0.45
           + d.square(freq, dur) * 0.35
           + d.square(freq * 0.5, dur) * 0.30)

    # Pick attack: a noise transient before the note settles.
    pick = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 2600.0, 0.8)
    osc += pick * d.decay_env(dur, 190.0, 0.0004) * 0.75

    # Muted envelope. The 55/s decay is the mute; without it this is a lead.
    osc *= d.decay_env(dur, 52.0, 0.0018) * 0.75 + 0.25 * d.adsr(
        dur, 0.002, 0.04, 0.32, min(0.05, dur * 0.5), curve=2.0)

    # TWO GAIN STAGES WITH A FILTER BETWEEN THEM, not one big clip. A single
    # tanh at high drive just squares the wave off and turns to fizz; cascading
    # a preamp, a tone stack and a power stage is how a real amp builds gain,
    # and it is the difference between "distorted" and "heavy".
    osc = d.drive(osc, 5.5)
    osc = d.filt(osc, "hp", 110.0, 0.707)
    osc = d.filt(osc, "lp", 5200.0, 0.9)
    osc = d.asym_drive(osc, 4.2, bias=0.16)

    cab = (d.resonator(osc, 130.0, 1.0, 0.9)      # low string thump
           + d.resonator(osc, 240.0, 1.1, 1.0)    # body
           + d.resonator(osc, 900.0, 1.3, 0.55)   # lower honk - more scooped
           + d.resonator(osc, 2400.0, 1.6, 0.75)  # bite
           + d.resonator(osc, 3900.0, 2.0, 0.30)) # presence
    cab = d.filt(cab, "lp", 6800.0, 0.707, poles=4)
    cab = d.filt(cab, "hp", 80.0, 0.707)
    return cab * vel * 0.85


def lead_synth(freq, dur, vel=1.0, seed="lead"):
    """Detuned saw lead, octave-doubled. Sparse melodic statements only."""
    dur = max(dur, 0.08)
    osc = d.supersaw(freq, dur, voices=5, detune=0.014, seed=seed)
    osc += d.supersaw(freq * 2.0, dur, voices=3, detune=0.010,
                      seed=seed + "8va") * 0.35

    cutoff = d.breakpoints(dur, [(0.0, freq * 4.0), (0.15, freq * 9.0),
                                 (1.0, freq * 5.0)])
    osc = d.sweep_filter(osc, "lp", np.clip(cutoff, 300.0, 11000.0), q=1.3)
    osc = d.drive(osc, 1.9)

    env = d.adsr(dur, attack=0.012, decay=0.12, sustain=0.78,
                 release=min(0.16, dur * 0.45), curve=1.8)
    return osc * env * vel * 0.7


# --- The cold-war half -------------------------------------------------------

def brass(freq, dur, vel=1.0, seed="brass"):
    """Brass ensemble stab. Carries the hook.

    A brass instrument's spectrum brightens with loudness, so the filter tracks
    velocity rather than sitting still - a quiet stab is genuinely duller, not
    just quieter. The slow-ish 25 ms attack and the pitch scoop into the note
    are the other two cues that read as 'brass' rather than 'saw with an EQ'.
    """
    dur = max(dur, 0.1)

    # Scoop: brass players arrive slightly under the note and settle onto it.
    bend = d.breakpoints(dur, [(0.0, 0.972), (0.05, 0.997), (0.14, 1.0), (1.0, 1.0)])
    osc = d.supersaw(freq * bend, dur, voices=6, detune=0.009, seed=seed)
    osc += d.pulse(freq * bend, dur, width=0.32) * 0.35

    bright = 2200.0 + 5200.0 * (vel ** 1.5)
    cutoff = d.breakpoints(dur, [(0.0, 420.0), (0.09, bright),
                                 (0.45, bright * 0.62), (1.0, bright * 0.42)])
    osc = d.sweep_filter(osc, "lp", cutoff, q=1.1)

    # Formant peaks of a brass bore. This is what stops it reading as a synth.
    osc = osc + d.resonator(osc, 1150.0, 2.2, 0.5) + d.resonator(osc, 2400.0, 2.6, 0.3)
    osc = d.asym_drive(osc, 2.2, bias=0.12)

    env = d.adsr(dur, attack=0.025, decay=0.18, sustain=0.68,
                 release=min(0.22, dur * 0.5), curve=1.5)
    return osc * env * vel * 0.55


def low_strings(freq, dur, vel=1.0, seed="strings"):
    """Sustained low string bed. Slow, dark, never the focus."""
    dur = max(dur, 0.2)
    osc = d.supersaw(freq, dur, voices=7, detune=0.016, seed=seed)
    osc = d.filt(osc, "lp", 1400.0 + 900.0 * vel, 0.707, poles=4)
    osc = d.chorus(osc, rate=0.35, depth_ms=9.0, mix=0.45, seed=seed + "ch")

    env = d.adsr(dur, attack=0.16, decay=0.3, sustain=0.85,
                 release=min(0.45, dur * 0.5), curve=1.2)
    return osc * env * vel * 0.4


# --- Drum kit ----------------------------------------------------------------

def kick(freq, dur, vel=1.0, seed="kick"):
    """Pitch-swept sine with a click. Tight and forward, not a club kick."""
    dur = max(min(dur, 0.45), 0.12)
    pitch = d.breakpoints(dur, [(0.0, 210.0), (0.018, 82.0), (0.08, 51.0), (1.0, 43.0)])
    body = d.sine(pitch, dur) * d.decay_env(dur, 19.0, 0.0005)

    g = d.rng(seed)
    # Beater click, hard. On a driving sixteenth-note pattern the click is what
    # keeps the kick audible THROUGH the guitars - the low end alone just
    # disappears into the riff.
    click = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "hp", 2200.0, 0.707)
    click *= d.decay_env(dur, 380.0, 0.0002) * 0.62
    click += d.resonator(g.uniform(-1.0, 1.0, d.n_samples(dur)), 4200.0, 1.2)         * d.decay_env(dur, 500.0, 0.0002) * 0.3

    out = d.drive(body * 1.3 + click, 2.4)
    return d.filt(out, "hp", 32.0, 0.707) * vel


def snare(freq, dur, vel=1.0, seed="snare"):
    """Two tuned shell modes plus the snare wires. Marching-band forward.

    The rudimental snare is one of the most identifiable parts of this style, so
    this is deliberately a crisp, high-tuned, short-decay drum rather than the
    big gated snare the era is otherwise known for.
    """
    dur = max(min(dur, 0.4), 0.09)
    g = d.rng(seed)

    shell = (d.sine(196.0, dur) * 0.6 + d.sine(292.0, dur) * 0.4)
    shell *= d.decay_env(dur, 36.0, 0.0005)

    wires = g.uniform(-1.0, 1.0, d.n_samples(dur))
    wires = d.filt(wires, "hp", 1400.0, 0.707)
    wires = d.filt(wires, "lp", 9500.0, 0.707)
    wires *= d.decay_env(dur, 24.0, 0.0003)

    # The crack: a short, very bright transient on top of the wires. This is
    # the part that cuts through a wall of distorted guitar.
    crack = d.resonator(g.uniform(-1.0, 1.0, d.n_samples(dur)), 3400.0, 0.9)
    crack *= d.decay_env(dur, 220.0, 0.0002) * 0.7

    out = shell * 0.55 + wires * 0.9 + crack
    out = d.drive(out, 2.2)
    return d.filt(out, "hp", 140.0, 0.707) * vel


def hat(freq, dur, vel=1.0, seed="hat"):
    """Closed hi-hat: band-passed noise with a very fast decay."""
    dur = max(min(dur, 0.14), 0.02)
    g = d.rng(seed)
    n = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "hp", 6500.0, 0.707, poles=4)
    n = d.resonator(n, 9200.0, 1.2, 1.0) + n * 0.6
    return n * d.decay_env(dur, 130.0, 0.0003) * vel * 0.5


def open_hat(freq, dur, vel=1.0, seed="ohat"):
    dur = max(min(dur, 0.5), 0.12)
    g = d.rng(seed)
    n = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "hp", 5800.0, 0.707, poles=4)
    return n * d.decay_env(dur, 13.0, 0.0004) * vel * 0.4


def tom(freq, dur, vel=1.0, seed="tom"):
    """Tuned tom. Fills and the tribal floor pattern."""
    dur = max(min(dur, 0.6), 0.12)
    f = freq if freq > 0 else 120.0
    pitch = d.breakpoints(dur, [(0.0, f * 1.5), (0.08, f), (1.0, f * 0.86)])
    body = (d.sine(pitch, dur) + d.sine(pitch * 1.58, dur) * 0.3)
    body *= d.decay_env(dur, 11.0, 0.0008)

    g = d.rng(seed)
    skin = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 900.0, 0.9)
    skin *= d.decay_env(dur, 90.0, 0.0003) * 0.25
    return d.drive(body + skin, 1.4) * vel * 0.8


# --- Industrial percussion ---------------------------------------------------

def metal_hit(freq, dur, vel=1.0, seed="metal"):
    """Struck metal by modal synthesis: a sum of INHARMONIC decaying partials.

    This is the industrial layer - anvils, pipes, sheet steel - and it is the
    one thing that cannot be faked with filtered noise. What makes metal sound
    like metal is that its partials are not integer multiples of a fundamental
    and each one decays at its own rate, with the high ones dying first. A
    filtered noise burst has neither property and always reads as 'noise'.
    """
    dur = max(min(dur, 2.2), 0.15)
    g = d.rng(seed)
    f0 = freq if freq > 0 else 420.0

    # Ratios from a struck bar/plate, roughened per note so no two hits ring
    # identically.
    ratios = [1.0, 2.76, 5.40, 8.93, 13.34, 18.64]
    out = np.zeros(d.n_samples(dur))
    for i, r in enumerate(ratios):
        partial_f = f0 * r * (1.0 + g.uniform(-0.02, 0.02))
        if partial_f > 18000.0:
            continue
        # Higher partials decay faster - the physical reason a struck plate
        # goes from a clang to a hum.
        rate = 3.0 + i * 2.6
        amp = 1.0 / (1.0 + i * 0.85)
        out += d.sine(partial_f, dur) * d.decay_env(dur, rate, 0.0004) * amp

    # Strike noise at the contact instant.
    strike = d.filt(g.uniform(-1.0, 1.0, len(out)), "bp", f0 * 3.0, 0.7)
    out += strike * d.decay_env(dur, 300.0, 0.0002) * 0.4

    return d.normalize(out, 0.9) * vel * 0.65


def anvil(freq, dur, vel=1.0, seed="anvil"):
    """A high, bright, long-ringing metal hit. The signature accent."""
    return metal_hit(freq if freq > 0 else 1150.0, max(dur, 0.9), vel,
                     seed + ":anvil") * 0.8


def pipe(freq, dur, vel=1.0, seed="pipe"):
    """Low, dull struck pipe. Sits under the kick."""
    out = metal_hit(freq if freq > 0 else 165.0, max(dur, 0.6), vel, seed + ":pipe")
    return d.filt(out, "lp", 2200.0, 0.707) * 0.9


def noise_sweep(freq, dur, vel=1.0, seed="sweep"):
    """Riser/faller into a section change. Used sparingly - it is a cliche."""
    dur = max(dur, 0.3)
    src = d.pink(dur, seed)
    cutoff = d.breakpoints(dur, [(0.0, 300.0), (0.85, 9000.0), (1.0, 2000.0)])
    out = d.sweep_filter(src, "bp", cutoff, q=1.6)
    return out * d.adsr(dur, dur * 0.6, dur * 0.1, 0.8, dur * 0.25) * vel * 0.5
