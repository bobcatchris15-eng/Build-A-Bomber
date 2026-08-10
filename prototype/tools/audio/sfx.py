"""Every non-music sound, and the manifest the engine loads them by.

THE SINCERE/ABSURD SPLIT IS ENFORCED BY FILE LAYOUT, not by convention.
CORE_DESIGN_LANGUAGE.md 6.2 draws the line between ordnance (vocalised, absurd)
and everything else (real, sincere), and it is easy to let that drift one asset
at a time. So:

    the ordnance banks come from voice.ORDNANCE and nothing else
    every sound authored IN THIS FILE is on the sincere side, without exception

If a sound in this module ever wants to be funny, it is in the wrong module.
That includes the interface: UX_REDESIGN_PLAN.md is explicit - "interface audio
is on the sincere side. No comedy on a button."

VARIANT BANKS. Every key renders 3-8 numbered files (`sfx_cannon_01.wav` ...)
rather than one, because audio_manager.gd now picks round-robin with no
immediate repeat. UI_STYLE_GUIDE.md:359 already required this of pitch
("never let a UI click repeat identically") and pitch variation alone stops
working once you have heard a sound a few hundred times, which for a click is
the first ten minutes.
"""

from __future__ import annotations

import numpy as np

from . import dsp as d
from . import voice as V


# --- Helpers -----------------------------------------------------------------

def _modal(freqs, decays, dur, seed, amps=None, strike=0.35, strike_hz=3000.0):
    """A struck object: inharmonic partials, each with its own decay rate.

    Every mechanical UI sound here is one of these. A switch, a latch, a dial
    detent and a relay differ in exactly the three things this takes - which
    frequencies ring, how fast each dies, and how hard the contact is.
    """
    g = d.rng(seed)
    out = d.silence(dur)
    amps = amps or [1.0 / (1.0 + i) for i in range(len(freqs))]
    for f, rate, a in zip(freqs, decays, amps):
        f = f * (1.0 + g.uniform(-0.012, 0.012))
        out += d.sine(f, dur) * d.decay_env(dur, rate, 0.0003) * a
    if strike > 0.0:
        contact = d.filt(g.uniform(-1.0, 1.0, len(out)), "bp", strike_hz, 0.8)
        out += contact * d.decay_env(dur, 900.0, 0.0001) * strike
    return d.normalize(d.fade(out, 0.0004, min(0.01, dur * 0.2)), 0.85)


def _seamless(x: np.ndarray, fade: float = 0.35) -> np.ndarray:
    """Make a buffer loop without a seam, by crossfading its tail over its head.

    Returns a buffer SHORTER than the input by `fade` seconds. The result's last
    sample runs continuously into its first, which is the only way a sustained
    engine or wind bed can loop without a click or a swell once a second.
    """
    f = d.n_samples(fade)
    if len(x) <= f * 2:
        return x
    length = len(x) - f
    out = np.array(x[:length])
    ramp = np.linspace(0.0, 1.0, f)
    out[:f] = x[:f] * ramp + x[length:length + f] * (1.0 - ramp)
    return out


def _variants(fn, count: int, *args):
    return [fn(i, *args) for i in range(count)]


# --- Interface (14 roles) ----------------------------------------------------
#
# Named for the MECHANISM, not the widget, which is what ui_feedback.gd's role
# table already assumes. Eight of these keys - toggle_on/off, dial, tick,
# drawer, plate, latch, mode - are referenced by ui_feedback.gd:52-68 and did
# not exist in audio_manager.gd's SFX_PATHS, so every control mapped to them
# has been silently playing nothing.

def ui_hover(i):
    """The lightest sound in the game. A readiness cue, never state."""
    return _modal([2400, 3900], [180, 260], 0.045, f"hover{i}",
                  amps=[1.0, 0.35], strike=0.10, strike_hz=5200.0) * 0.30


def ui_click(i):
    """Detent click - an ordinary press."""
    return _modal([1250, 2600, 4400], [190, 300, 420], 0.065, f"click{i}",
                  amps=[1.0, 0.5, 0.22], strike=0.4, strike_hz=3600.0) * 0.7


def ui_select(i):
    """Picking from a set. A tick with a small upward inflection."""
    base = _modal([900, 1850, 3100], [130, 200, 300], 0.09, f"sel{i}",
                  amps=[1.0, 0.55, 0.25], strike=0.3)
    lift = d.sine(d.breakpoints(0.09, [(0.0, 1400.0), (1.0, 2100.0)]), 0.09)
    return (base + lift * d.decay_env(0.09, 45.0, 0.001) * 0.3) * 0.65


def ui_place(i):
    """Seating something into the world or a slot. Has mass and stops dead."""
    g = d.rng(f"place{i}")
    thud = d.sine(d.breakpoints(0.18, [(0.0, 150.0), (0.1, 78.0), (1.0, 62.0)]),
                  0.18) * d.decay_env(0.18, 30.0, 0.0008)
    body = _modal([420, 780, 1360], [50, 80, 140], 0.18, f"place_m{i}",
                  amps=[1.0, 0.5, 0.25], strike=0.5, strike_hz=2200.0)
    grit = d.filt(g.uniform(-1.0, 1.0, d.n_samples(0.18)), "bp", 1100.0, 0.7)
    return d.normalize(thud * 0.9 + body * 0.7
                       + grit * d.decay_env(0.18, 160.0, 0.0004) * 0.3, 0.85)


def ui_error(i):
    """A refused input. A dead buzz - no pitch movement, nothing musical."""
    n = d.n_samples(0.16)
    g = d.rng(f"err{i}")
    buzz = d.square(d.breakpoints(0.16, [(0.0, 132.0), (1.0, 126.0)]), 0.16)
    buzz = d.filt(buzz, "lp", 1500.0, 0.9)
    buzz *= 0.55 + 0.45 * (np.abs(d.sine(58.0, 0.16)) > 0.35)
    buzz *= d.adsr(0.16, 0.002, 0.02, 0.85, 0.05, curve=1.2)
    grit = d.filt(g.uniform(-1.0, 1.0, n), "bp", 700.0, 1.2) * 0.12
    return d.normalize(buzz * 0.8 + grit, 0.75)


def ui_toggle_on(i):
    """A switch throwing one way. Harder detent than the return."""
    return _modal([1600, 3000, 5200], [260, 380, 520], 0.055, f"togon{i}",
                  amps=[1.0, 0.55, 0.3], strike=0.65, strike_hz=4200.0) * 0.7


def ui_toggle_off(i):
    """The same switch coming back. Lower, softer, unmistakably the other way.

    A real switch does NOT sound the same in both directions, and reversing one
    sample is audibly a reversed sample. Two distinct sounds is the only way the
    player knows which way a toggle went without looking at it.
    """
    return _modal([1050, 2100, 3600], [300, 420, 600], 0.048, f"togoff{i}",
                  amps=[1.0, 0.45, 0.2], strike=0.45, strike_hz=3200.0) * 0.6


def ui_dial(i):
    """A rotary selector dropping into its next notch."""
    return _modal([1900, 3400], [420, 560], 0.038, f"dial{i}",
                  amps=[1.0, 0.4], strike=0.7, strike_hz=4800.0) * 0.6


def ui_tick(i):
    """A continuous value passing a step. The quietest sound in the set - it
    fires repeatedly while a slider is dragged."""
    return _modal([3200], [600], 0.022, f"tick{i}", strike=0.5,
                  strike_hz=6000.0) * 0.25


def ui_drawer(i):
    """A dock or toolbox tier sliding open: rail friction, then a soft stop."""
    dur = 0.34
    g = d.rng(f"drawer{i}")
    rail = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 1500.0, 0.5)
    # Friction swells as the drawer accelerates, then stops.
    rail *= d.breakpoints(dur, [(0.0, 0.0), (0.15, 0.9), (0.72, 0.75),
                                (0.85, 0.0), (1.0, 0.0)])
    rail = d.sweep_filter(rail, "bp",
                          d.breakpoints(dur, [(0.0, 900.0), (0.8, 2100.0)]), 0.8)
    stop = _modal([320, 640, 1150], [45, 70, 110], 0.14, f"drawerstop{i}",
                  amps=[1.0, 0.5, 0.25], strike=0.45, strike_hz=2000.0)
    out = d.silence(dur)
    d.place(out, rail * 0.5, 0.0)
    d.place(out, stop * 0.8, 0.83 * dur)
    return d.normalize(out, 0.75)


def ui_plate(i):
    """A panel arriving and seating against its mount. Metal, with mass."""
    return _modal([260, 520, 980, 1700], [28, 45, 75, 120], 0.42, f"plate{i}",
                  amps=[1.0, 0.6, 0.3, 0.15], strike=0.5, strike_hz=2600.0) * 0.8


def ui_latch(i):
    """A quarter-turn fastener locking. Two-stage: turn, then seat."""
    dur = 0.22
    turn = _modal([1400, 2500], [340, 460], 0.05, f"latchturn{i}",
                  amps=[1.0, 0.4], strike=0.5, strike_hz=3800.0)
    seat = _modal([380, 700, 1250], [40, 65, 100], 0.17, f"latchseat{i}",
                  amps=[1.0, 0.55, 0.28], strike=0.75, strike_hz=2400.0)
    out = d.silence(dur)
    d.place(out, turn * 0.55, 0.0)
    d.place(out, seat * 0.95, 0.048)
    return d.normalize(out, 0.85)


def ui_mode(i):
    """A relay throwing. The heaviest non-destructive sound available."""
    dur = 0.30
    coil = d.sine(d.breakpoints(dur, [(0.0, 92.0), (0.25, 74.0), (1.0, 68.0)]),
                  dur) * d.decay_env(dur, 26.0, 0.0009)
    contact = _modal([540, 1020, 1850, 3100], [30, 55, 95, 160], dur,
                     f"mode{i}", amps=[1.0, 0.6, 0.32, 0.15],
                     strike=0.7, strike_hz=2800.0)
    return d.normalize(coil * 0.75 + contact * 0.9, 0.88)


def ui_menu_open(i):
    """The system/pause menu arriving. A heavy panel sliding in and seating.

    Distinct from `ui_drawer` on purpose: a drawer is a dock tier moving within
    a screen, this is the whole interface being interrupted, so it is lower,
    slower and has more mass behind it.
    """
    dur = 0.42
    g = d.rng(f"menuopen{i}")
    slide = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 700.0, 0.5)
    slide *= d.breakpoints(dur, [(0.0, 0.0), (0.12, 0.85), (0.62, 0.6),
                                 (0.78, 0.0), (1.0, 0.0)])
    seat = _modal([190, 380, 720, 1300], [26, 42, 72, 120], 0.28,
                  f"menuopenseat{i}", amps=[1.0, 0.6, 0.32, 0.16],
                  strike=0.5, strike_hz=2200.0)
    out = d.silence(dur)
    d.place(out, slide * 0.45, 0.0)
    d.place(out, seat * 0.9, 0.72 * dur)
    return d.normalize(out, 0.82)


def ui_menu_close(i):
    """The same panel leaving. Shorter, and it releases rather than seats."""
    dur = 0.30
    g = d.rng(f"menuclose{i}")
    unlatch = _modal([420, 800, 1500], [90, 130, 200], 0.09, f"menuclosel{i}",
                     amps=[1.0, 0.5, 0.25], strike=0.6, strike_hz=3000.0)
    slide = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 620.0, 0.5)
    slide *= d.breakpoints(dur, [(0.0, 0.0), (0.2, 0.7), (0.85, 0.0), (1.0, 0.0)])
    out = d.silence(dur)
    d.place(out, unlatch * 0.8, 0.0)
    d.place(out, slide * 0.4, 0.06)
    return d.normalize(out, 0.72)


def ui_warning(i):
    """Destructive action, and the alert banner. Mechanical, not musical."""
    dur = 0.5
    g = d.rng(f"warn{i}")
    # Two close tones beating against each other - a real warning horn, not a
    # synth interval.
    horn = (d.saw(196.0, dur) + d.saw(203.0, dur) * 0.9)
    horn = d.filt(horn, "lp", 1900.0, 0.8)
    horn = d.filt(horn, "hp", 150.0, 0.707)
    horn *= d.adsr(dur, 0.012, 0.06, 0.8, 0.16, curve=1.4)
    grit = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 900.0, 1.0) * 0.1
    return d.normalize(d.drive(horn * 0.5 + grit, 2.0), 0.8)


# --- Mechanical loops (sincere) ----------------------------------------------

def engine_loop(i, kind="diesel"):
    """A running powerplant. Seamless, pitch-shifted at runtime by unit speed.

    Built from a firing-order pulse train rather than a drone: an engine is a
    series of discrete combustion events, and that periodicity is what the ear
    identifies. Filtered noise alone gives a vacuum cleaner.
    """
    dur = 2.4
    g = d.rng(f"eng{kind}{i}")
    profiles = {
        "diesel": (26.0, 220.0, 1.6, 0.55),    # firing Hz, body Hz, drive, grit
        "turbine": (150.0, 900.0, 1.1, 0.30),
        "electric": (95.0, 1400.0, 1.0, 0.10),
        "heavy": (17.0, 150.0, 2.1, 0.65),
    }
    fire, body_hz, drv, grit_amt = profiles.get(kind, profiles["diesel"])

    # Slight wander so the loop does not read as a perfect machine.
    wander = 1.0 + d.filt(g.normal(0, 1, d.n_samples(dur)), "lp", 1.5, 0.707) * 0.012
    pulses = d.pulse(fire * wander, dur, width=0.18)
    pulses = d.sweep_resonator(pulses, body_hz, body_hz * 0.5)
    pulses = d.drive(pulses, drv)

    grit = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", body_hz * 3.0, 0.7)
    grit *= (0.6 + 0.4 * np.abs(d.pulse(fire * wander, dur, width=0.3)))

    out = pulses * 0.8 + grit * grit_amt
    out = d.filt(out, "lp", 4200.0, 0.707)
    out = d.filt(out, "hp", 45.0, 0.707)
    return d.normalize(_seamless(out, 0.4), 0.7)


def tread_loop(i):
    """Track clatter: irregular metallic impacts over a low roll."""
    dur = 2.0
    g = d.rng(f"tread{i}")
    out = d.silence(dur)
    t = 0.0
    while t < dur:
        hit = _modal([380, 720, 1400, 2600], [90, 130, 190, 280], 0.09,
                     f"tread{i}:{t:.3f}", amps=[1.0, 0.6, 0.35, 0.18],
                     strike=0.55, strike_hz=2800.0)
        d.place(out, hit * g.uniform(0.5, 1.0) * 0.5, t)
        t += g.uniform(0.055, 0.085)
    roll = d.filt(d.brown(dur, f"treadroll{i}"), "lp", 320.0, 0.707) * 0.5
    return d.normalize(_seamless(out + roll, 0.35), 0.7)


def wheel_loop(i):
    """Tyre roll. Broadband, smoother than treads, no discrete impacts."""
    dur = 2.0
    base = d.filt(d.pink(dur, f"wheel{i}"), "bp", 420.0, 0.7)
    hum = d.sine(78.0, dur) * 0.25 + d.sine(117.0, dur) * 0.12
    return d.normalize(_seamless(base * 0.7 + hum, 0.35), 0.55)


def servo_loop(i):
    """Turret/joint servo whine. A pitched electric motor."""
    dur = 1.6
    g = d.rng(f"servo{i}")
    whine = (d.saw(420.0, dur) * 0.6 + d.saw(631.0, dur) * 0.3)
    whine = d.filt(whine, "bp", 1500.0, 1.4)
    whine *= 1.0 + d.filt(g.normal(0, 1, d.n_samples(dur)), "lp", 6.0, 0.707) * 0.06
    brush = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "hp", 3000.0, 0.707) * 0.09
    return d.normalize(_seamless(whine * 0.5 + brush, 0.3), 0.5)


def hydraulic_loop(i):
    """Hydraulic hiss under load."""
    dur = 1.6
    g = d.rng(f"hyd{i}")
    hiss = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 2600.0, 0.6)
    hiss *= 0.75 + 0.25 * d.sine(3.2, dur)
    pump = d.sine(46.0, dur) * 0.2
    return d.normalize(_seamless(hiss * 0.6 + pump, 0.3), 0.45)


def rotor_loop(i):
    """Rotor wash: blade-passing tone plus downwash."""
    dur = 2.0
    g = d.rng(f"rotor{i}")
    blade = d.pulse(22.0, dur, width=0.12)
    blade = d.sweep_resonator(blade, 260.0, 180.0)
    wash = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "lp", 1400.0, 0.707)
    wash *= 0.6 + 0.4 * np.abs(d.sine(22.0, dur))
    return d.normalize(_seamless(blade * 0.8 + wash * 0.5, 0.35), 0.65)


def screw_loop(i):
    """Screw-drive churn: auger in mud. Wet, low, irregular."""
    dur = 2.2
    g = d.rng(f"screw{i}")
    churn = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "lp", 900.0, 0.707)
    churn *= 0.5 + 0.5 * np.abs(d.sine(9.0, dur))
    thump = d.sine(58.0, dur) * (0.5 + 0.5 * d.sine(4.5, dur)) * 0.4
    return d.normalize(_seamless(churn * 0.7 + thump, 0.35), 0.6)


def turret_start(i):
    return _modal([180, 340, 700], [40, 60, 95], 0.13, f"trvstart{i}",
                  amps=[1.0, 0.5, 0.25], strike=0.5, strike_hz=1800.0) * 0.6


def turret_stop(i):
    return _modal([220, 430, 820], [55, 80, 120], 0.16, f"trvstop{i}",
                  amps=[1.0, 0.45, 0.2], strike=0.6, strike_hz=2100.0) * 0.65


# --- Impacts: readable by outcome --------------------------------------------
#
# damage_resolver.gd already distinguishes chip damage, a normal reduced hit, a
# brute-force hit and a module strip. Those branches are invisible to the player
# right now because every one of them plays the same "hit". These give each a
# distinct sound, so a player can hear that their shots are BOUNCING - which is
# the single most useful piece of combat feedback an armour system can give.

def impact_chip(i):
    """Below threshold: a bounce. Bright, short, no low end - nothing got in."""
    return _modal([2100, 3800, 6200], [130, 190, 280], 0.13, f"chip{i}",
                  amps=[1.0, 0.55, 0.28], strike=0.75, strike_hz=5200.0) * 0.6


def impact_penetrate(i):
    """Armour defeated. Low, with a tearing component that chip has none of."""
    dur = 0.30
    g = d.rng(f"pen{i}")
    tear = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 700.0, 0.5)
    tear *= d.decay_env(dur, 22.0, 0.0004)
    thud = d.sine(d.breakpoints(dur, [(0.0, 210.0), (0.15, 88.0), (1.0, 70.0)]),
                  dur) * d.decay_env(dur, 18.0, 0.0006)
    return d.normalize(d.drive(thud * 0.9 + tear * 0.7, 1.8), 0.85)


def impact_module_lost(i):
    """A subsystem stripped. Something structural came off."""
    dur = 0.45
    g = d.rng(f"mod{i}")
    snap = _modal([520, 980, 1900, 3400], [35, 60, 100, 170], dur, f"modm{i}",
                  amps=[1.0, 0.6, 0.35, 0.18], strike=0.8, strike_hz=3000.0)
    debris = d.silence(dur)
    for k in range(5):
        t = g.uniform(0.08, 0.40)
        d.place(debris, _modal([900 + k * 400], [220], 0.08, f"deb{i}{k}",
                               strike=0.6) * g.uniform(0.2, 0.5), t)
    return d.normalize(snap * 0.9 + debris * 0.6, 0.85)


def impact_immobilised(i):
    """All locomotion gone. A grinding halt - the machine stops moving."""
    dur = 0.6
    g = d.rng(f"immob{i}")
    grind = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 480.0, 0.6)
    grind *= d.breakpoints(dur, [(0.0, 1.0), (0.5, 0.6), (1.0, 0.0)])
    drop = d.sine(d.breakpoints(dur, [(0.0, 120.0), (1.0, 48.0)]), dur)
    drop *= d.decay_env(dur, 7.0, 0.001)
    return d.normalize(d.drive(grind * 0.6 + drop * 0.9, 1.6), 0.8)


def impact_catastrophic(i):
    """A kill. The one impact allowed to be big - it is the end of a unit."""
    dur = 0.9
    g = d.rng(f"cat{i}")
    blast = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "lp", 2200.0, 0.707)
    blast *= d.decay_env(dur, 6.5, 0.0006)
    sub = d.sine(d.breakpoints(dur, [(0.0, 90.0), (0.3, 45.0), (1.0, 34.0)]), dur)
    sub *= d.decay_env(dur, 5.0, 0.001)
    debris = d.silence(dur)
    for k in range(9):
        d.place(debris, _modal([700 + k * 350], [180], 0.1, f"catd{i}{k}",
                               strike=0.7) * g.uniform(0.15, 0.45),
                g.uniform(0.10, 0.75))
    return d.normalize(d.drive(blast * 0.85 + sub * 0.9 + debris * 0.5, 1.5), 0.92)


# --- Construction and economy ------------------------------------------------

def construct_start(i):
    """A foundation being set."""
    return d.normalize(_modal([180, 350, 700, 1300], [22, 38, 65, 110], 0.55,
                              f"found{i}", amps=[1.0, 0.6, 0.32, 0.16],
                              strike=0.6, strike_hz=1900.0), 0.85)


def construct_loop(i):
    """Building in progress. Rhythmic, machine-like, seamless."""
    dur = 1.8
    g = d.rng(f"cons{i}")
    out = d.silence(dur)
    t = 0.0
    while t < dur:
        d.place(out, _modal([420, 810, 1500], [95, 140, 210], 0.11,
                            f"cons{i}:{t:.2f}", amps=[1.0, 0.5, 0.25],
                            strike=0.5, strike_hz=2400.0) * 0.55, t)
        t += 0.30
    motor = d.filt(d.pink(dur, f"consm{i}"), "bp", 380.0, 0.8) * 0.3
    return d.normalize(_seamless(out + motor, 0.3), 0.6)


def construct_done(i):
    """Complete. A latch plus a short rising confirmation - mechanical."""
    dur = 0.4
    seat = _modal([300, 590, 1100], [30, 50, 85], dur, f"done{i}",
                  amps=[1.0, 0.55, 0.28], strike=0.7, strike_hz=2200.0)
    conf = d.sine(d.breakpoints(dur, [(0.0, 620.0), (0.35, 930.0), (1.0, 930.0)]),
                  dur) * d.decay_env(dur, 9.0, 0.004) * 0.28
    return d.normalize(seat * 0.9 + conf, 0.85)


def unit_rollout(i):
    """A finished unit leaving the factory: door, then drive-away."""
    dur = 0.7
    g = d.rng(f"roll{i}")
    door = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 800.0, 0.6)
    door *= d.breakpoints(dur, [(0.0, 0.9), (0.35, 0.4), (0.5, 0.0), (1.0, 0.0)])
    clunk = _modal([260, 500, 950], [35, 55, 90], 0.3, f"rolld{i}",
                   amps=[1.0, 0.5, 0.25], strike=0.6, strike_hz=2000.0)
    out = d.silence(dur)
    d.place(out, door * 0.4, 0.0)
    d.place(out, clunk * 0.85, 0.36)
    return d.normalize(out, 0.8)


def harvester_dock(i):
    return d.normalize(_modal([210, 400, 760, 1400], [28, 45, 78, 130], 0.5,
                              f"dock{i}", amps=[1.0, 0.6, 0.3, 0.15],
                              strike=0.55, strike_hz=2100.0), 0.8)


def harvester_full(i):
    """Load complete. Two rising mechanical notes - a signal, not a jingle."""
    dur = 0.36
    a = _modal([880], [30], dur, f"hfa{i}", strike=0.3, strike_hz=3000.0)
    b = _modal([1320], [30], dur, f"hfb{i}", strike=0.3, strike_hz=3400.0)
    out = d.silence(dur)
    d.place(out, a * 0.7, 0.0)
    d.place(out, b * 0.8, 0.12)
    return d.normalize(out, 0.7)


def repair_loop(i):
    """Repair arm working. A welder: arc buzz plus spatter."""
    dur = 1.5
    g = d.rng(f"rep{i}")
    arc = d.filt(g.uniform(-1.0, 1.0, d.n_samples(dur)), "bp", 1800.0, 0.5)
    arc *= 0.5 + 0.5 * (g.uniform(0, 1, d.n_samples(dur)) > 0.35)
    arc = d.filt(arc, "lp", 5000.0, 0.707)
    hum = d.saw(120.0, dur) * 0.1
    return d.normalize(_seamless(arc * 0.5 + hum, 0.3), 0.5)


# --- Ambience ----------------------------------------------------------------
#
# One bed per surface type in terrain_builder.gd's SURFACE_PALETTE (line 415),
# plus wind and a Lab room tone. All long and seamless: these play continuously
# under everything else, so a seam would be heard every few seconds.

def _wind(dur, intensity, seed):
    g = d.rng(seed)
    base = d.pink(dur, seed + ":p")
    # Gusts: slow amplitude and cutoff movement together. Constant-level wind
    # reads as noise; wind is identified by its MOVEMENT.
    gust = d.filt(g.normal(0, 1, d.n_samples(dur)), "lp", 0.28, 0.707)
    gust = 0.55 + 0.45 * (gust / (np.max(np.abs(gust)) + 1e-9))
    cutoff = 380.0 + 1500.0 * intensity * gust
    out = d.sweep_filter(base, "lp", cutoff, q=0.7)
    return out * gust * (0.35 + 0.65 * intensity)


def ambience(i, surface="rocky"):
    """A surface's bed. 8 seconds, seamless."""
    dur = 8.0
    g = d.rng(f"amb{surface}{i}")
    wind_level = {
        "marsh": 0.30, "rocky": 0.55, "snow_mud": 0.45, "sand": 0.70,
        "gravel": 0.50, "forest": 0.40, "ice": 0.65,
    }.get(surface, 0.5)
    out = _wind(dur, wind_level, f"amb{surface}{i}")

    if surface == "marsh":
        # Water movement and the odd bubble.
        out += d.filt(d.pink(dur, f"marshw{i}"), "bp", 700.0, 0.6) * 0.18
        for k in range(14):
            t = g.uniform(0, dur - 0.3)
            blip = d.sine(d.breakpoints(0.12, [(0.0, 380.0), (1.0, 820.0)]), 0.12)
            d.place(out, blip * d.decay_env(0.12, 26.0, 0.002) * g.uniform(0.03, 0.10), t)
    elif surface == "forest":
        # Leaf rustle and distant birds.
        out += d.filt(d.pink(dur, f"leaf{i}"), "hp", 2600.0, 0.707) * 0.12
        for k in range(7):
            t = g.uniform(0, dur - 0.5)
            f0 = g.uniform(1900, 3400)
            call = d.sine(d.breakpoints(0.16, [(0.0, f0), (0.5, f0 * 1.25),
                                               (1.0, f0 * 0.95)]), 0.16)
            d.place(out, call * d.decay_env(0.16, 14.0, 0.01) * g.uniform(0.02, 0.06), t)
    elif surface == "ice":
        # Creaks and the occasional deep crack.
        for k in range(6):
            t = g.uniform(0, dur - 0.8)
            creak = d.sweep_filter(d.pink(0.6, f"ice{i}{k}"), "bp",
                                   d.breakpoints(0.6, [(0.0, 320.0), (1.0, 190.0)]), 3.0)
            d.place(out, creak * d.adsr(0.6, 0.1, 0.2, 0.5, 0.3) * g.uniform(0.05, 0.14), t)
    elif surface == "sand":
        out += d.filt(d.pink(dur, f"grit{i}"), "hp", 3800.0, 0.707) * 0.14
    elif surface in ("gravel", "rocky"):
        out += d.filt(d.brown(dur, f"rock{i}"), "lp", 180.0, 0.707) * 0.22
    elif surface == "snow_mud":
        out = d.filt(out, "lp", 2200.0, 0.707)   # snow deadens the top end

    return d.normalize(_seamless(out, 1.0), 0.42)


def ambience_lab(i):
    """Design Lab room tone. A workshop with the machines idling."""
    dur = 8.0
    g = d.rng(f"lab{i}")
    room = d.filt(d.brown(dur, f"labroom{i}"), "lp", 260.0, 0.707) * 0.5
    fluoro = d.sine(100.0, dur) * 0.035 + d.sine(150.0, dur) * 0.018
    vent = d.filt(d.pink(dur, f"labvent{i}"), "bp", 520.0, 0.5) * 0.16
    out = room + fluoro + vent
    for k in range(5):
        d.place(out, _modal([1400, 2600], [200, 300], 0.07, f"labtick{i}{k}",
                            strike=0.4) * g.uniform(0.02, 0.05),
                g.uniform(0, dur - 0.2))
    return d.normalize(_seamless(out, 1.0), 0.35)


def distant_artillery(i):
    """A war happening somewhere else. Sincere, and the strongest single cue
    that the environment takes the conflict seriously."""
    dur = 8.0
    g = d.rng(f"arty{i}")
    out = d.silence(dur)
    for k in range(5):
        t = g.uniform(0, dur - 1.2)
        boom = d.filt(d.brown(1.0, f"arty{i}{k}"), "lp", g.uniform(90, 190), 0.707)
        boom *= d.decay_env(1.0, g.uniform(2.5, 5.0), 0.03)
        d.place(out, boom * g.uniform(0.25, 0.7), t)
    return d.normalize(_seamless(out, 1.0), 0.30)


# --- The manifest ------------------------------------------------------------
#
# key -> (generator, variant count, subdirectory). audio_manager.gd's SFX_PATHS
# is generated FROM this by the CLI, so the two cannot drift: a key added here
# appears in the engine, and a key removed here disappears from it.

SURFACES = ["marsh", "rocky", "snow_mud", "sand", "gravel", "forest", "ice"]
ENGINE_KINDS = ["diesel", "turbine", "electric", "heavy"]
COMMS_PHRASES = ["ack", "affirm", "negative", "engaging", "structure_lost",
                 "low_power", "ready", "unit_lost"]


def manifest() -> dict:
    """Every sound the game can play, as {key: [(name, callable), ...]}."""
    out: dict = {}

    def add(key, fn, count, folder="sfx"):
        out[key] = {"folder": folder,
                    "variants": [(f"{key}_{n + 1:02d}", lambda i=n: fn(i))
                                 for n in range(count)]}

    # Interface - the fourteen roles ui_feedback.gd expects.
    add("hover", ui_hover, 3)
    add("click", ui_click, 5)
    add("select", ui_select, 4)
    add("place", ui_place, 4)
    add("error", ui_error, 3)
    add("ui_toggle_on", ui_toggle_on, 3)
    add("ui_toggle_off", ui_toggle_off, 3)
    add("ui_dial", ui_dial, 4)
    add("ui_tick", ui_tick, 4)
    add("ui_drawer", ui_drawer, 3)
    add("ui_plate", ui_plate, 3)
    add("ui_latch", ui_latch, 3)
    add("ui_mode", ui_mode, 3)
    # Used by ui/system_layer.gd for the pause/system menu.
    add("ui_menu_open", ui_menu_open, 2)
    add("ui_menu_close", ui_menu_close, 2)
    add("warning_banner", ui_warning, 3)

    # Ordnance - VOCALISED. The only absurd entries in this table.
    for key, fn in V.ORDNANCE.items():
        add(key, fn, 7)

    # Comms - sincere, and the only thing on the Voice bus.
    for phrase in COMMS_PHRASES:
        tone = "alert" if phrase in ("structure_lost", "low_power", "unit_lost") \
            else "calm"
        add(f"radio_{phrase}",
            lambda i, p=phrase, t=tone: V.comms(p, i, t), 4, folder="voice")
    add("radio_static", lambda i: V.comms("ack", i + 40, "calm"), 2, folder="voice")
    # order_ping stays a tone rather than speech: it acknowledges the PLAYER's
    # click, so it belongs with the interface, not with the unit talking back.
    add("order_ping", ui_dial, 3)

    # Mechanical loops.
    for kind in ENGINE_KINDS:
        add(f"engine_{kind}", lambda i, k=kind: engine_loop(i, k), 2)
    add("tread_loop", tread_loop, 2)
    add("wheel_loop", wheel_loop, 2)
    add("servo_loop", servo_loop, 2)
    add("hydraulic_loop", hydraulic_loop, 2)
    add("rotor_loop", rotor_loop, 2)
    add("screw_loop", screw_loop, 2)
    add("turret_start", turret_start, 3)
    add("turret_stop", turret_stop, 3)

    # Impacts, by outcome.
    add("impact_chip", impact_chip, 5)
    add("impact_penetrate", impact_penetrate, 5)
    add("impact_module_lost", impact_module_lost, 4)
    add("impact_immobilised", impact_immobilised, 3)
    add("impact_catastrophic", impact_catastrophic, 4)

    # Construction and economy.
    add("construct", construct_start, 3)
    add("construct_loop", construct_loop, 2)
    add("construct_done", construct_done, 3)
    add("unit_rollout", unit_rollout, 3)
    add("harvester_dock", harvester_dock, 3)
    add("harvester_full", harvester_full, 3)
    add("repair_loop", repair_loop, 2)

    # Ambience.
    for surface in SURFACES:
        add(f"ambience_{surface}", lambda i, s=surface: ambience(i, s), 1,
            folder="ambience")
    add("ambience_lab", ambience_lab, 1, folder="ambience")
    add("ambience_artillery", distant_artillery, 1, folder="ambience")

    return out
