"""Tracker-style timing. Knows about bars and notes, nothing about timbre.

WHY TRACKER NOTATION AND NOT A LIST OF DICTS. These patterns are source code
under version control and their whole value is that a riff can be READ and
edited in place:

    kick    = "x . . . x . . . x . . . x . . ."
    riff    = "a1 - . a1 . c2 - . a1 . . . g1 - . ."

That is legible as rhythm at a glance, and a one-note change is a one-character
diff. The same material as `[{"step": 0, "pitch": "a1", "len": 2}, ...]` is
neither. Trackers settled on this notation in the 1980s for exactly these
reasons and nothing since has improved on it for this job.

TIMING IS COMPUTED IN SAMPLES, NOT ACCUMULATED IN SECONDS. Every event's start
is `round(step * samples_per_step)` from the origin of the song, so rounding
error cannot accumulate over a three-minute track. This matters more than usual
here: the skirmish track renders as three separate stems that MUST stay sample
locked, because audio_manager.gd plays them on three synchronised players and
any drift between them would phase.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from . import SAMPLE_RATE
from . import dsp as d

SR = SAMPLE_RATE

_SEMITONES = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


def note_hz(name) -> float:
    """'a1', 'c#2', 'eb3' -> Hz. Octave 4 contains A4 = 440 Hz.

    Accepts a number too, treated as a MIDI note, so a caller computing an
    interval arithmetically does not have to render it back to a string.
    """
    if isinstance(name, (int, float)):
        return 440.0 * 2.0 ** ((float(name) - 69.0) / 12.0)

    s = str(name).strip().lower()
    semi = _SEMITONES[s[0]]
    i = 1
    while i < len(s) and s[i] in "#b":
        semi += 1 if s[i] == "#" else -1
        i += 1
    octave = int(s[i:]) if s[i:] else 4
    midi = 12 * (octave + 1) + semi
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


@dataclass
class Event:
    """One scheduled note. `step` is absolute from the start of the song."""
    step: float
    freq: float           # 0.0 for unpitched percussion
    steps: float          # length in steps
    vel: float = 1.0


def hits(pattern: str, accent: float = 1.25, ghost: float = 0.45) -> list:
    """Percussion row. 'x' hit, 'X' accent, 'o' ghost note, '.' rest.

    Whitespace is ignored, so a row can be grouped by beat for readability:
    "x... ..x. x... ..x." is the same as "x....x.x.....x..".
    """
    out = []
    step = 0
    for ch in pattern:
        if ch.isspace() or ch == "|":
            continue
        if ch == "x":
            out.append(Event(step, 0.0, 1.0, 1.0))
        elif ch == "X":
            out.append(Event(step, 0.0, 1.0, accent))
        elif ch == "o":
            out.append(Event(step, 0.0, 1.0, ghost))
        step += 1
    return out


def riff(pattern: str, vel: float = 1.0, octave_shift: int = 0) -> list:
    """Pitched row. Tokens separated by whitespace, one token per step.

    '.'  rest
    '-'  tie: extend the previous note by one step
    'a1' a note, held until the next token that is not a tie

    A trailing tie at the end of a bar carries into the next bar's first token
    only if that token is also a tie, which is what makes a note sustain across
    a bar line read naturally.
    """
    out = []
    step = 0
    for tok in pattern.replace("|", " ").split():
        if tok == "-":
            if out:
                out[-1].steps += 1.0
        elif tok != ".":
            out.append(Event(step, note_hz(tok) * (2.0 ** octave_shift), 1.0, vel))
        step += 1
    return out


def chord(step: float, notes, steps: float = 4.0, vel: float = 1.0) -> list:
    """All of `notes` struck together. Brass stabs and string pads."""
    return [Event(step, note_hz(n), steps, vel) for n in notes]


def shift(events, by_steps: float) -> list:
    """Move a row later in the song. How bars are assembled into a structure."""
    return [Event(e.step + by_steps, e.freq, e.steps, e.vel) for e in events]


def repeat(events, times: int, every: float) -> list:
    out = []
    for i in range(times):
        out.extend(shift(events, i * every))
    return out


def transpose(events, semitones: float) -> list:
    ratio = 2.0 ** (semitones / 12.0)
    return [Event(e.step, e.freq * ratio, e.steps, e.vel) for e in events]


def velocity(events, scale: float) -> list:
    return [Event(e.step, e.freq, e.steps, e.vel * scale) for e in events]


@dataclass
class Clock:
    """Converts steps to samples. One instance per song."""
    bpm: float = 128.0
    steps_per_beat: int = 4
    beats_per_bar: int = 4
    swing: float = 0.0        # 0 straight; 0.2 is a light shuffle

    @property
    def samples_per_step(self) -> float:
        return SR * 60.0 / (self.bpm * self.steps_per_beat)

    @property
    def steps_per_bar(self) -> int:
        return self.steps_per_beat * self.beats_per_bar

    def sample_at(self, step: float) -> int:
        s = step
        # Swing delays every second sixteenth. Klepacki's material is straight,
        # so this defaults off, but the lab and operations beds use a touch.
        if self.swing and int(step) % 2 == 1:
            s += self.swing * 0.5
        return int(round(s * self.samples_per_step))

    def duration_of(self, steps: float) -> float:
        return steps * self.samples_per_step / SR

    def bars(self, n: int) -> float:
        return n * self.steps_per_bar


@dataclass
class Track:
    """One instrument plus the events it plays, and where it sits in the mix."""
    name: str
    instrument: object              # (freq, dur, vel, seed) -> np.ndarray
    events: list = field(default_factory=list)
    gain: float = 1.0
    pan: float = 0.0
    stem: str = "bed"               # which stem this track belongs to

    def add(self, events) -> "Track":
        self.events.extend(events)
        return self


def render_track(track: Track, clock: Clock, total_samples: int,
                 seed: str) -> np.ndarray:
    """Render one track to a mono buffer."""
    out = np.zeros(total_samples)
    for i, ev in enumerate(track.events):
        start = clock.sample_at(ev.step)
        if start >= total_samples:
            continue
        dur = clock.duration_of(ev.steps)
        # Per-note seed so two identical notes are not bit-identical: real
        # players do not repeat exactly, and on percussion especially the
        # difference between "sampled once" and "played" is this.
        note = track.instrument(ev.freq, dur, ev.vel, f"{seed}:{track.name}:{i}")
        stop = min(total_samples, start + len(note))
        out[start:stop] += note[:stop - start]
    return out * track.gain


def render(tracks, clock: Clock, bars: int, seed: str,
           tail: float = 2.0) -> dict:
    """Render every track, grouped into stems.

    Returns {stem_name: stereo array}. All stems are exactly the same length -
    the skirmish track depends on that for its synchronised layer playback, and
    `test_audio_system` asserts it.
    """
    total = int(round(clock.bars(bars) * clock.samples_per_step))
    # The tail lets reverb and long releases decay past the last bar. It is
    # included in every stem equally so lengths still match.
    total += d.n_samples(tail)

    stems: dict = {}
    for track in tracks:
        mono = render_track(track, clock, total, seed)
        stereo = d.pan(mono, track.pan)
        if track.stem not in stems:
            stems[track.stem] = np.zeros((total, 2))
        stems[track.stem] += stereo
    return stems


def loop_seam(x: np.ndarray, clock: Clock, bars: int) -> np.ndarray:
    """Fold the decay tail back over the start so the track loops seamlessly.

    A loop that just cuts at the last bar line kills every cymbal, reverb and
    release tail dead, which is audible as a hole once per cycle - the single
    most common reason a looping game track sounds like a loop.

    NO CROSSFADE RAMP IS APPLIED, and that is deliberate rather than an
    omission. The tail is by construction the samples immediately following the
    body, so `tail[0]` already continues `body[-1]` smoothly; adding it at
    offset 0 is a continuous overlap-add. Ramping it in would attenuate the
    loudest, most audible part of the decay - precisely the material this
    function exists to preserve.
    """
    body = int(round(clock.bars(bars) * clock.samples_per_step))
    if len(x) <= body:
        return x[:body] if x.ndim == 2 else d.pad_to(x, body)

    out = np.array(x[:body])
    tail = x[body:]
    n = min(len(tail), body)
    out[:n] += tail[:n]
    return out
