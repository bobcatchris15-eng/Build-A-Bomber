"""Vectorised DSP primitives. Knows nothing about music or about the game.

EVERYTHING HERE IS FLOAT64 MONO UNLESS A DOCSTRING SAYS OTHERWISE. Stereo is a
(n, 2) array and only appears at the very end of a chain, in `pan` / `widen` /
`to_stereo`. Keeping the bulk of the graph mono is not just tidiness: the music
renderer runs hundreds of note events through these functions and doubling the
sample count for material that is mono anyway (bass, kick, the whole low end)
costs real render time for no audible gain.

WHY NOT PER-SAMPLE PYTHON LOOPS. The generator this replaces was written as

    for i in range(int(SAMPLE_RATE * duration)):
        t = i / SAMPLE_RATE
        ...

which is ~200k interpreted iterations per second of audio. A three-minute track
with a dozen simultaneous voices is on the order of 10^9 iterations. Every
function below is either a numpy expression over a whole buffer or a scipy
`lfilter`/`sosfilt` call, both of which run in C. The one genuinely recursive
operation that scipy cannot express - a filter whose cutoff moves per sample -
is handled by `sweep_filter` with block-wise coefficient interpolation, which is
the standard trick and is documented at that function.
"""

from __future__ import annotations

import numpy as np
from scipy import signal

from . import SAMPLE_RATE

SR = SAMPLE_RATE
TWO_PI = 2.0 * np.pi


# --- Seeding -----------------------------------------------------------------
#
# One entry point for every random draw in the package. Callers pass a string
# label rather than an integer so that seeds are stable under reordering: adding
# a new sound in the middle of sfx.py must not reshuffle the noise in every
# sound after it, which is exactly what an incrementing counter would do and
# exactly the kind of spurious binary churn __init__.py warns about.

def rng(label: str) -> np.random.Generator:
    """A deterministic generator keyed by a human-readable label."""
    # SeedSequence over the label's bytes: stable across runs, across platforms
    # and across Python versions, unlike hash(), which is salted per process.
    entropy = int.from_bytes(label.encode("utf-8"), "little") or 1
    return np.random.default_rng(np.random.SeedSequence(entropy))


# --- Time and buffers --------------------------------------------------------

def n_samples(duration: float) -> int:
    return max(1, int(round(SR * duration)))


def t_axis(duration: float) -> np.ndarray:
    """Sample times in seconds, [0, duration)."""
    return np.arange(n_samples(duration), dtype=np.float64) / SR


def silence(duration: float) -> np.ndarray:
    return np.zeros(n_samples(duration), dtype=np.float64)


def as_array(value, n: int) -> np.ndarray:
    """Broadcast a scalar-or-array parameter to length n.

    Lets every generator below accept either a constant or a per-sample
    modulation curve for the same argument, which is what makes envelopes and
    LFOs composable without a separate 'modulated' variant of each function.
    """
    arr = np.asarray(value, dtype=np.float64)
    if arr.ndim == 0:
        return np.full(n, float(arr))
    if len(arr) == n:
        return arr
    # Resample by linear interpolation rather than erroring. Envelopes are often
    # authored at a coarser resolution than the audio they shape.
    return np.interp(np.linspace(0.0, 1.0, n), np.linspace(0.0, 1.0, len(arr)), arr)


def phase_of(freq, duration: float, phase0: float = 0.0) -> np.ndarray:
    """Normalised phase in [0, 1) for a possibly-swept frequency.

    Integrating frequency rather than evaluating `freq * t` is what makes a
    pitch sweep continuous. The old generator did the latter -

        freq = f_start + (f_end - f_start) * progress
        phase += 2*pi*freq / SAMPLE_RATE

    - and while that loop happened to integrate correctly, `sin(2*pi*f(t)*t)`
    (which the same file used elsewhere) does not: it sweeps at twice the
    intended rate and lands on the wrong final pitch.
    """
    n = n_samples(duration)
    f = as_array(freq, n)
    return (phase0 + np.cumsum(f) / SR) % 1.0


# --- Oscillators -------------------------------------------------------------
#
# Saw and pulse are PolyBLEP-corrected. Naive versions of both alias badly, and
# aliasing is the single most recognisable "this was made by a script" artifact
# in synthesised music - it turns a bass riff's upper harmonics into an inhar-
# monic shimmer that no amount of filtering afterwards removes.

def _polyblep(phase: np.ndarray, dt: np.ndarray) -> np.ndarray:
    """Correction term for a discontinuity at phase 0."""
    out = np.zeros_like(phase)

    # Just after the step.
    m = phase < dt
    t = np.zeros_like(phase)
    t[m] = phase[m] / dt[m]
    out[m] = t[m] + t[m] - t[m] * t[m] - 1.0

    # Just before the step.
    m = phase > 1.0 - dt
    t[:] = 0.0
    t[m] = (phase[m] - 1.0) / dt[m]
    out[m] = t[m] * t[m] + t[m] + t[m] + 1.0

    return out


def sine(freq, duration: float, phase0: float = 0.0) -> np.ndarray:
    return np.sin(TWO_PI * phase_of(freq, duration, phase0))


def saw(freq, duration: float, phase0: float = 0.0) -> np.ndarray:
    n = n_samples(duration)
    ph = phase_of(freq, duration, phase0)
    dt = np.clip(as_array(freq, n) / SR, 1e-9, 0.5)
    return (2.0 * ph - 1.0) - _polyblep(ph, dt)


def pulse(freq, duration: float, width=0.5, phase0: float = 0.0) -> np.ndarray:
    n = n_samples(duration)
    ph = phase_of(freq, duration, phase0)
    dt = np.clip(as_array(freq, n) / SR, 1e-9, 0.5)
    w = np.clip(as_array(width, n), 0.02, 0.98)

    out = np.where(ph < w, 1.0, -1.0)
    out += _polyblep(ph, dt)
    out -= _polyblep((ph - w) % 1.0, dt)
    return out


def square(freq, duration: float, phase0: float = 0.0) -> np.ndarray:
    return pulse(freq, duration, 0.5, phase0)


def triangle(freq, duration: float, phase0: float = 0.0) -> np.ndarray:
    """Integrated square: naturally band-limited, no BLEP needed.

    The leaky integrator (0.999) keeps DC from accumulating over long notes.
    """
    sq = square(freq, duration, phase0)
    n = len(sq)
    f0 = float(np.mean(as_array(freq, n)))
    out = signal.lfilter([1.0], [1.0, -0.999], sq)
    return out * (4.0 * f0 / SR)


def supersaw(freq, duration: float, voices: int = 7, detune: float = 0.012,
             seed: str = "supersaw") -> np.ndarray:
    """Detuned saw stack. The backbone of both the bass and the brass patches."""
    g = rng(seed)
    n = n_samples(duration)
    base = as_array(freq, n)
    out = np.zeros(n)
    for i in range(voices):
        # Symmetric spread around the centre so the perceived pitch does not
        # drift with voice count.
        offset = (i - (voices - 1) / 2.0) / max(1.0, (voices - 1) / 2.0)
        ratio = 2.0 ** (offset * detune)
        out += saw(base * ratio, duration, phase0=g.random())
    return out / voices


# --- Noise -------------------------------------------------------------------

def white(duration: float, seed: str = "white") -> np.ndarray:
    return rng(seed).uniform(-1.0, 1.0, n_samples(duration))


def pink(duration: float, seed: str = "pink") -> np.ndarray:
    """-3 dB/octave noise via the standard 3-pole pinking filter.

    Pink rather than white is the correct base for wind, rumble and most
    mechanical beds; white noise reads as hiss because its energy piles up in
    the top octave where the ear is most sensitive to it.
    """
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1.0, -2.494956002, 2.017265875, -0.522189400]
    out = signal.lfilter(b, a, white(duration, seed))
    return out / (np.max(np.abs(out)) + 1e-12)


def brown(duration: float, seed: str = "brown") -> np.ndarray:
    """-6 dB/octave. Distant artillery, deep rumble."""
    out = signal.lfilter([1.0], [1.0, -0.99], white(duration, seed))
    out -= np.mean(out)
    return out / (np.max(np.abs(out)) + 1e-12)


# --- Envelopes ---------------------------------------------------------------

def adsr(duration: float, attack: float = 0.005, decay: float = 0.1,
         sustain: float = 0.7, release: float = 0.1, curve: float = 2.0) -> np.ndarray:
    """Standard four-stage envelope, exponential in the decay/release stages.

    `curve` shapes decay and release: 1.0 is linear, higher is more percussive.
    Real instruments decay roughly exponentially, and a linear decay is another
    of the tells that gives synthesised percussion its cheap sound.
    """
    n = n_samples(duration)
    env = np.zeros(n)

    a = min(n, n_samples(attack))
    d = min(n - a, n_samples(decay))
    r = min(n - a - d, n_samples(release))
    s = max(0, n - a - d - r)

    i = 0
    if a:
        env[i:i + a] = np.linspace(0.0, 1.0, a)
        i += a
    if d:
        env[i:i + d] = sustain + (1.0 - sustain) * (1.0 - np.linspace(0.0, 1.0, d)) ** curve
        i += d
    if s:
        env[i:i + s] = sustain
        i += s
    if r:
        env[i:i + r] = sustain * (1.0 - np.linspace(0.0, 1.0, r)) ** curve
    return env


def decay_env(duration: float, rate: float, attack: float = 0.001) -> np.ndarray:
    """Exponential decay with a short click-free attack.

    `rate` is in nepers per second, matching the `exp(-k*t)` shape the old
    generator used, so existing sound descriptions port over directly.
    """
    t = t_axis(duration)
    env = np.exp(-rate * t)
    a = n_samples(attack)
    if a > 1:
        env[:a] *= np.linspace(0.0, 1.0, a)
    return env


def breakpoints(duration: float, points) -> np.ndarray:
    """Arbitrary envelope from (time_fraction, value) pairs, linearly joined.

    This is what pitch contours are written with - the falling contour on a
    "ka-POW" is four breakpoints, not an equation.
    """
    pts = sorted(points)
    xs = np.array([p[0] for p in pts], dtype=np.float64)
    ys = np.array([p[1] for p in pts], dtype=np.float64)
    return np.interp(np.linspace(0.0, 1.0, n_samples(duration)), xs, ys)


# --- Filters -----------------------------------------------------------------

def _biquad(mode: str, cutoff: float, q: float) -> np.ndarray:
    """One second-order section, as scipy 'sos'."""
    f = float(np.clip(cutoff, 20.0, SR * 0.49))
    q = max(0.05, float(q))
    w0 = TWO_PI * f / SR
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2.0 * q)

    if mode == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
    elif mode == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    elif mode == "bp":
        b = [alpha, 0.0, -alpha]
    elif mode == "notch":
        b = [1.0, -2 * cw, 1.0]
    else:
        raise ValueError(f"unknown filter mode {mode!r}")

    a = [1 + alpha, -2 * cw, 1 - alpha]
    return np.array([[b[0] / a[0], b[1] / a[0], b[2] / a[0],
                      1.0, a[1] / a[0], a[2] / a[0]]])


def filt(x: np.ndarray, mode: str, cutoff: float, q: float = 0.707,
         poles: int = 2) -> np.ndarray:
    """Static filter. `poles` cascades identical sections for a steeper slope."""
    sos = np.vstack([_biquad(mode, cutoff, q)] * max(1, poles // 2))
    return signal.sosfilt(sos, x)


# BLOCK SIZE FOR SWEPT FILTERS. scipy has no time-varying filter, and a true
# per-sample recursion in Python is ~100x too slow to be usable here. The
# standard answer is to hold coefficients constant over a short block and carry
# the filter state across block boundaries. 64 samples is 1.45 ms at 44.1 kHz -
# far below the ~20 ms at which the ear resolves a coefficient step as a zipper
# artifact, and small enough that even a fast filter envelope stays smooth.
_SWEEP_BLOCK = 64


def sweep_filter(x: np.ndarray, mode: str, cutoff, q=0.707) -> np.ndarray:
    """Filter whose cutoff (and optionally Q) moves over time.

    This is the workhorse behind filter-envelope basses, the laser whine, and
    the formant glides in voice.py - anything where the point of the sound IS
    the movement of the filter.
    """
    n = len(x)
    fc = as_array(cutoff, n)
    qq = as_array(q, n)
    out = np.empty(n)
    zi = np.zeros((1, 2))

    for start in range(0, n, _SWEEP_BLOCK):
        stop = min(start + _SWEEP_BLOCK, n)
        # Mean over the block rather than the value at its start: with a fast
        # envelope the difference is audible as a slight lag otherwise.
        sos = _biquad(mode, float(np.mean(fc[start:stop])),
                      float(np.mean(qq[start:stop])))
        out[start:stop], zi = signal.sosfilt(sos, x[start:stop], zi=zi)
    return out


def resonator(x: np.ndarray, freq: float, q: float, gain: float = 1.0) -> np.ndarray:
    """A single sharp band-pass. The building block of modal hits."""
    return filt(x, "bp", freq, q) * gain


def _klatt_coeffs(freq: float, bandwidth: float):
    """Two-pole resonator in Klatt's formulation.

    y[n] = A x[n] + B y[n-1] + C y[n-2], with A chosen so the DC gain is 1.

    NOT the same thing as a band-pass. A band-pass has zeros at DC and Nyquist,
    so cascading four of them scoops out everything between the formants and
    leaves a thin, whistling result. This has no zeros: it is a pure resonance
    on a flat background, which is what lets a CASCADE of them reproduce a
    vocal tract transfer function with the correct relative formant amplitudes
    falling out automatically.
    """
    f = float(np.clip(freq, 60.0, SR * 0.48))
    bw = float(np.clip(bandwidth, 20.0, 1500.0))
    c = -np.exp(-TWO_PI * bw / SR)
    b = 2.0 * np.exp(-np.pi * bw / SR) * np.cos(TWO_PI * f / SR)
    a = 1.0 - b - c
    return [a], [1.0, -b, -c]


def sweep_resonator(x: np.ndarray, freq, bandwidth) -> np.ndarray:
    """A Klatt resonator whose centre frequency moves. Block-wise, like
    `sweep_filter` - see the block-size note there."""
    n = len(x)
    fc = as_array(freq, n)
    bw = as_array(bandwidth, n)
    out = np.empty(n)
    zi = np.zeros(2)

    for start in range(0, n, _SWEEP_BLOCK):
        stop = min(start + _SWEEP_BLOCK, n)
        b, a = _klatt_coeffs(float(np.mean(fc[start:stop])),
                             float(np.mean(bw[start:stop])))
        out[start:stop], zi = signal.lfilter(b, a, x[start:stop], zi=zi)
    return out


# --- Saturation and distortion -----------------------------------------------

def drive(x: np.ndarray, amount: float = 3.0) -> np.ndarray:
    """Symmetric soft clip. Adds odd harmonics - the guitar/bass crunch."""
    return np.tanh(x * amount) / np.tanh(amount)


def asym_drive(x: np.ndarray, amount: float = 3.0, bias: float = 0.25) -> np.ndarray:
    """Asymmetric clip. Adds EVEN harmonics too, which is what makes a valve
    stage sound warm rather than merely loud."""
    out = np.tanh((x + bias) * amount)
    return (out - np.tanh(bias * amount)) / np.tanh(amount)


def fold(x: np.ndarray, amount: float = 2.0) -> np.ndarray:
    """Wavefolding. Harsh and metallic - reserved for industrial percussion."""
    return np.sin(x * amount * np.pi * 0.5)


def bitcrush(x: np.ndarray, bits: int = 8, downsample: int = 1) -> np.ndarray:
    levels = float(2 ** max(1, bits))
    out = np.round(x * levels) / levels
    if downsample > 1:
        idx = (np.arange(len(out)) // downsample) * downsample
        out = out[idx]
    return out


# --- Time-domain effects -----------------------------------------------------

def delay(x: np.ndarray, time: float, feedback: float = 0.35,
          mix: float = 0.3) -> np.ndarray:
    d = max(1, n_samples(time))
    # A feedback delay IS an IIR filter with a d-sample denominator, so lfilter
    # runs the whole recursion in C rather than in a Python loop.
    a = np.zeros(d + 1)
    a[0] = 1.0
    a[d] = -np.clip(feedback, 0.0, 0.95)
    wet = signal.lfilter([1.0], a, x)
    return x * (1.0 - mix) + wet * mix


def _fractional_delay(x: np.ndarray, delay_samples: np.ndarray) -> np.ndarray:
    """Read x at a moving, non-integer offset. Linear interpolation.

    Used by chorus, flanger and tape wow/flutter, which are all the same
    operation with different modulation depths and rates.
    """
    n = len(x)
    idx = np.arange(n) - delay_samples
    idx = np.clip(idx, 0.0, n - 1.0)
    lo = np.floor(idx).astype(np.int64)
    hi = np.minimum(lo + 1, n - 1)
    frac = idx - lo
    return x[lo] * (1.0 - frac) + x[hi] * frac


def chorus(x: np.ndarray, rate: float = 0.6, depth_ms: float = 6.0,
           mix: float = 0.4, voices: int = 3, seed: str = "chorus") -> np.ndarray:
    g = rng(seed)
    n = len(x)
    t = np.arange(n) / SR
    base = 0.020 * SR
    wet = np.zeros(n)
    for i in range(voices):
        lfo = np.sin(TWO_PI * rate * (1.0 + 0.17 * i) * t + g.random() * TWO_PI)
        wet += _fractional_delay(x, base + lfo * depth_ms * 0.001 * SR)
    wet /= voices
    return x * (1.0 - mix) + wet * mix


def reverb(x: np.ndarray, room: float = 0.72, damp: float = 0.35,
           mix: float = 0.25) -> np.ndarray:
    """Freeverb-style: 8 parallel damped combs into 4 series allpasses.

    NOTE ON WHERE THIS IS ALLOWED. CORE_DESIGN_LANGUAGE.md 6.1 explicitly
    forbids reverb on the ordnance vocalisations - "a vocalisation with reverb
    and bass layered under it to make it feel weighty" is named as a way the
    joke dies. So this is for percussion, ambience and music only, and voice.py
    never imports it.
    """
    comb_delays = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    allpass_delays = [556, 441, 341, 225]

    fb = np.clip(room, 0.0, 0.95)
    wet = np.zeros_like(x)
    for d in comb_delays:
        a = np.zeros(d + 1)
        a[0] = 1.0
        a[d] = -fb
        c = signal.lfilter([1.0], a, x)
        # Damping: a one-pole lowpass inside the tail, so high frequencies die
        # first the way they do in a real room.
        c = signal.lfilter([1.0 - damp], [1.0, -damp], c)
        wet += c
    wet /= len(comb_delays)

    for d in allpass_delays:
        b = np.zeros(d + 1)
        b[0] = -0.5
        b[d] = 1.0
        a = np.zeros(d + 1)
        a[0] = 1.0
        a[d] = -0.5
        wet = signal.lfilter(b, a, wet)

    return x * (1.0 - mix) + wet * mix


# --- Dynamics ----------------------------------------------------------------

def _envelope_follower(x: np.ndarray, attack: float, release: float) -> np.ndarray:
    """Peak follower with separate attack and release time constants."""
    rect = np.abs(x)
    ca = np.exp(-1.0 / max(1.0, attack * SR))
    cr = np.exp(-1.0 / max(1.0, release * SR))
    # Attack and release differ, so this cannot be a single lfilter. Two passes
    # plus a max() is a close and fully vectorised approximation: the fast pass
    # tracks transients, the slow pass holds the tail.
    fast = signal.lfilter([1.0 - ca], [1.0, -ca], rect)
    slow = signal.lfilter([1.0 - cr], [1.0, -cr], rect)
    return np.maximum(fast, slow)


def compress(x: np.ndarray, threshold_db: float = -18.0, ratio: float = 4.0,
             attack: float = 0.005, release: float = 0.12,
             makeup_db: float = 0.0) -> np.ndarray:
    env = _envelope_follower(x, attack, release)
    env_db = 20.0 * np.log10(env + 1e-9)
    over = np.maximum(0.0, env_db - threshold_db)
    gain_db = -over * (1.0 - 1.0 / max(1.0, ratio)) + makeup_db
    return x * (10.0 ** (gain_db / 20.0))


def duck(x: np.ndarray, key: np.ndarray, amount_db: float = -9.0,
         attack: float = 0.004, release: float = 0.18) -> np.ndarray:
    """Sidechain: pull `x` down whenever `key` is loud.

    In the music this is the kick ducking the bass, which is most of what gives
    an industrial track its pump. At runtime the same idea is done in GDScript,
    where the music ducks under comms and stingers.
    """
    n = min(len(x), len(key))
    env = _envelope_follower(key[:n], attack, release)
    env /= (np.max(env) + 1e-12)
    gain_db = env * amount_db
    out = np.array(x, dtype=np.float64)
    out[:n] *= 10.0 ** (gain_db / 20.0)
    return out


# --- Tape --------------------------------------------------------------------

def tape(x: np.ndarray, wow: float = 0.4, flutter: float = 0.25,
         saturation: float = 1.6, hf_rolloff: float = 12000.0,
         seed: str = "tape") -> np.ndarray:
    """Wow, flutter, soft saturation and a high-frequency rolloff.

    BOTH design docs ask for this. CORE_DESIGN_LANGUAGE.md's cold-war register
    and UX_REDESIGN_PLAN.md's "tape-saturated" are the same instruction, and it
    is also the single most effective treatment for stopping a fully synthetic
    mix sounding sterile: real tape is never perfectly pitch-stable, and that
    tiny instability is most of what the ear reads as "recorded".
    """
    g = rng(seed)
    n = len(x)
    t = np.arange(n) / SR

    # Wow is slow (< 2 Hz) pitch drift; flutter is fast (~8 Hz) and shallower.
    wow_lfo = (np.sin(TWO_PI * 0.7 * t + g.random() * TWO_PI) * 0.6
               + np.sin(TWO_PI * 1.3 * t + g.random() * TWO_PI) * 0.4)
    flut_lfo = np.sin(TWO_PI * 8.5 * t + g.random() * TWO_PI)

    base = 0.004 * SR
    offset = base + wow_lfo * wow * 0.0009 * SR + flut_lfo * flutter * 0.00012 * SR
    out = _fractional_delay(x, offset)

    out = asym_drive(out, saturation, bias=0.08)
    out = filt(out, "lp", hf_rolloff, 0.707)
    return out


# --- Mixing helpers ----------------------------------------------------------

def db(gain_db: float) -> float:
    return 10.0 ** (gain_db / 20.0)


def normalize(x: np.ndarray, peak: float = 0.95) -> np.ndarray:
    m = float(np.max(np.abs(x)))
    return x if m < 1e-12 else x * (peak / m)


def match_loudness(x: np.ndarray, target_rms_db: float,
                   peak: float = 0.95) -> np.ndarray:
    """Gain so the buffer's RMS lands on `target_rms_db` dBFS.

    WHY NOT JUST normalize(). Peak normalisation says nothing about how loud a
    sound IS - measured across this library, a peak-normalised square-wave buzz
    came out at -7 dB RMS while an equally peak-normalised ping sat at -29, a
    22 dB loudness gap between two interface sounds. Perceived level tracks
    energy, so banks that must sit together in a mix are gain-set by RMS here.
    The peak ceiling is still enforced (a hard scale-down, not a limiter -
    render._prepare owns limiting); a sound whose crest factor would push it
    over at the target RMS simply ends up a little quieter than requested,
    which is the correct trade.
    """
    rms = float(np.sqrt(np.mean(np.asarray(x, dtype=np.float64) ** 2)))
    if rms < 1e-12:
        return np.zeros_like(x)
    out = x * (db(target_rms_db) / rms)
    m = float(np.max(np.abs(out)))
    return out * (peak / m) if m > peak else out


def fade(x: np.ndarray, in_time: float = 0.002, out_time: float = 0.01) -> np.ndarray:
    """Click guard. Any buffer that starts or ends mid-waveform needs this."""
    out = np.array(x, dtype=np.float64)
    a, b = n_samples(in_time), n_samples(out_time)
    if a > 1 and a < len(out):
        out[:a] *= np.linspace(0.0, 1.0, a)
    if b > 1 and b < len(out):
        out[-b:] *= np.linspace(1.0, 0.0, b)
    return out


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*layers) -> np.ndarray:
    """Sum buffers of differing lengths, zero-padding to the longest.

    Accepts bare arrays or (array, gain) pairs.
    """
    parts = []
    for layer in layers:
        if isinstance(layer, tuple):
            arr, gain = layer
            parts.append(np.asarray(arr, dtype=np.float64) * gain)
        else:
            parts.append(np.asarray(layer, dtype=np.float64))
    if not parts:
        return np.zeros(0)
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def place(canvas: np.ndarray, part: np.ndarray, at: float) -> np.ndarray:
    """Add `part` into `canvas` starting at `at` seconds. In-place, returns canvas.

    The sequencer's inner loop. Clips rather than growing the canvas, because a
    note that runs past the end of a loop must be truncated at the loop point,
    not extend the bar.
    """
    start = n_samples(at) if at > 0 else 0
    if start >= len(canvas):
        return canvas
    stop = min(len(canvas), start + len(part))
    canvas[start:stop] += part[:stop - start]
    return canvas


# --- Stereo ------------------------------------------------------------------

def to_stereo(x: np.ndarray) -> np.ndarray:
    return np.column_stack([x, x])


def pan(x: np.ndarray, position: float = 0.0) -> np.ndarray:
    """Equal-power pan. -1 hard left, +1 hard right."""
    p = (np.clip(position, -1.0, 1.0) + 1.0) * 0.25 * np.pi
    return np.column_stack([x * np.cos(p), x * np.sin(p)])


def widen(stereo: np.ndarray, amount: float = 1.4,
          bass_mono_below: float = 180.0) -> np.ndarray:
    """Mid/side widening, with the low end forced back to mono.

    Wide bass is the classic mixing error in synthesised material: it sounds
    impressive on headphones and collapses to a thin, phasey mess on anything
    with a shared woofer or in mono. Keeping everything below ~180 Hz centred
    costs nothing perceptually and fixes it.
    """
    left, right = stereo[:, 0], stereo[:, 1]
    mid = (left + right) * 0.5
    side = (left - right) * 0.5 * amount
    side = filt(side, "hp", bass_mono_below, 0.707)
    return np.column_stack([mid + side, mid - side])
