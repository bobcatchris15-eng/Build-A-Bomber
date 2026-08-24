"""File output. Knows about paths and encoders, nothing about sound.

WHY NO .import SIDECARS ARE WRITTEN HERE. Godot owns those - it generates the
`uid://` and the cache hash on import, and a hand-authored sidecar with a made-up
UID is worse than no sidecar at all (CLAUDE.md already records what happens when
UIDs get out of step with the project). So this module writes only the source
media, and `--headless --editor --import` produces the sidecars. It DOES delete
orphaned sidecars, because a .import whose source file no longer exists is a
persistent import error in the editor.
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

import numpy as np
import soundfile as sf

from . import SAMPLE_RATE

AUDIO_DIR = Path(__file__).resolve().parents[2] / "assets" / "audio"
SFX_DIR = AUDIO_DIR / "sfx"
MUSIC_DIR = AUDIO_DIR / "music"
VOICE_DIR = AUDIO_DIR / "voice"
AMBIENCE_DIR = AUDIO_DIR / "ambience"

ALL_DIRS = [SFX_DIR, MUSIC_DIR, VOICE_DIR, AMBIENCE_DIR]

# Frames per write into the Vorbis encoder. See the note in `write_ogg`.
_OGG_CHUNK = 65536

# Every file this run produced, so `prune` can tell an orphan from a survivor.
_written: set[Path] = set()
_bytes_written = 0


def ensure_dirs() -> None:
    for d in ALL_DIRS:
        d.mkdir(parents=True, exist_ok=True)


def _prepare(samples: np.ndarray, peak: float = 0.95) -> np.ndarray:
    """Shape, limit and DC-correct a buffer on its way to disk.

    THE LIMITER IS NOT OPTIONAL. Several layers here (drive, fold, reverb tails
    summing) can exceed unity on a loud transient, and 16-bit PCM wraps rather
    than clips on overflow - a wrap is a full-scale discontinuity, which is a
    loud crack, not a soft distortion.

    BUT IT MUST ONLY ENGAGE NEAR THE CEILING. The first version ran every buffer
    through `tanh` unconditionally, which saturated even material peaking at
    -10 dBFS: measured, a 0.5 input came out 0.45 and a full-scale peak landed
    at 0.716 (-2.9 dBFS), so the whole tree shipped with one always-on
    odd-harmonic stage colouring it - mud on complex beds, harshness on pure
    tones. What is wanted is wrap PROTECTION, not saturation, so this is now a
    soft-knee limiter: identity below the knee (0.7 * peak), tanh continuation
    above it. The curve joins with matched slope at the knee and tops out
    exactly at `peak`, so overflow still turns into gentle rounding.
    """
    x = np.asarray(samples, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]

    # Remove DC per channel. Asymmetric drive and wavefolding both introduce an
    # offset, and DC eats headroom while being completely inaudible on its own.
    x = x - np.mean(x, axis=0, keepdims=True)

    ceil = max(float(peak), 1e-6)
    knee = 0.7 * ceil
    mag = np.abs(x)
    over = mag - knee
    limited = np.sign(x) * np.where(
        over > 0.0,
        knee + (ceil - knee) * np.tanh(over / (ceil - knee)),
        mag,
    )
    return limited


def _record(path: Path) -> None:
    global _bytes_written
    _written.add(path.resolve())
    _bytes_written += path.stat().st_size


def write_wav(path, samples, peak: float = 0.95) -> Path:
    """16-bit PCM. Used for every SFX: they are short, and PCM decodes with no
    per-play cost, which matters when a dozen can fire in the same frame."""
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(p), _prepare(samples, peak), SAMPLE_RATE, subtype="PCM_16")
    _record(p)
    return p


def write_ogg(path, samples, peak: float = 0.95, quality: float = 0.6) -> Path:
    """Ogg Vorbis. Music only.

    A three-minute stereo track is ~30 MB as PCM and ~2.5 MB here. With .git
    already near a gigabyte that difference is the whole reason `soundfile` is a
    dependency. Quality 0.6 is transparent for this material - it is synthetic,
    band-limited and heavily saturated, which is the easy case for a perceptual
    codec.
    """
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    data = _prepare(samples, peak)

    with sf.SoundFile(str(p), "w", samplerate=SAMPLE_RATE,
                      channels=data.shape[1], format="OGG",
                      subtype="VORBIS") as f:
        # WRITTEN IN CHUNKS BECAUSE A SINGLE LARGE WRITE CRASHES THE ENCODER.
        # libsndfile's Vorbis path overflows the stack on a one-shot write of a
        # multi-million-frame buffer - a 5-second buffer is fine, a 51-second
        # track kills the interpreter outright with a Windows fatal exception
        # and no Python traceback. Chunking is the documented way to stream
        # into a SoundFile and costs nothing.
        for start in range(0, len(data), _OGG_CHUNK):
            f.write(data[start:start + _OGG_CHUNK])
    _record(p)
    return p


def copy_file(src, dest) -> Path:
    """Copy an already-encoded file into the asset tree and track it.

    For sources that did not come from this package's synthesis - curated_music
    copies externally-produced tracks this way, rather than through write_wav /
    write_ogg, since there is no sample buffer to encode.
    """
    p = Path(dest)
    p.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(src), p)
    _record(p)
    return p


def prune(directories=None) -> list[Path]:
    """Delete audio files (and their .import sidecars) this run did not write.

    Renaming a sound would otherwise leave the old file behind forever, still
    loaded by nobody and still counted by the tests as an asset.
    """
    removed = []
    for d in (directories or ALL_DIRS):
        if not d.exists():
            continue
        # The listing is a SNAPSHOT, and deleting a media file also deletes its
        # sidecar - so by the time the loop reaches that sidecar's own entry it
        # is already gone. missing_ok covers that, and covers a sidecar removed
        # by hand between runs.
        for f in sorted(d.iterdir()):
            if f.suffix in (".wav", ".ogg") and f.resolve() not in _written:
                f.with_suffix(f.suffix + ".import").unlink(missing_ok=True)
                f.unlink(missing_ok=True)
                removed.append(f)
            elif f.suffix == ".import" and not f.with_suffix("").exists():
                # An orphaned sidecar whose source is gone. Left behind, this
                # is a permanent import error in the editor.
                f.unlink(missing_ok=True)
                removed.append(f)
    return removed


def summary() -> str:
    mb = _bytes_written / (1024 * 1024)
    return f"{len(_written)} files, {mb:.1f} MB total"


def preview(samples, name: str = "preview", peak: float = 0.95) -> Path:
    """Drop a buffer somewhere audible without touching the asset tree.

    For iterating on a single sound - especially the cannon vocalisation, which
    both design docs say to playtest on its own before committing the set.
    """
    out = Path(__file__).resolve().parents[2] / "user_audio_preview"
    out.mkdir(exist_ok=True)
    p = out / f"{name}.wav"
    sf.write(str(p), _prepare(samples, peak), SAMPLE_RATE, subtype="PCM_16")
    return p


def clear_preview() -> None:
    out = Path(__file__).resolve().parents[2] / "user_audio_preview"
    if out.exists():
        shutil.rmtree(out)
