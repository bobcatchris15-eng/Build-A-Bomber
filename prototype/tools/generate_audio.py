"""Regenerate every sound and every music track in the game.

    cd prototype && python tools/generate_audio.py
    cd prototype && python tools/generate_audio.py --only cannon,click
    cd prototype && python tools/generate_audio.py --music-only

Then reimport so Godot picks up the new media and writes its .import sidecars:

    ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import

WHAT THIS REPLACES. The previous version of this file was ~200 lines of
per-sample Python loops producing 20 mono WAVs from sine, noise and linear
pitch sweeps - `sfx_laser` was a 1400->300 Hz sweep, `sfx_explosion` was
`random()` times `exp(-5t)`, and the "12-second ambient industrial music track"
was four sine waves. It is now a thin driver over tools/audio/, which is a real
synthesis toolkit. See tools/audio/__init__.py for the layering.

THE MANIFEST IS THE CONTRACT. This writes assets/audio/audio_manifest.json,
which audio_manager.gd loads at boot to build its variant banks. That means
adding a sound is a one-line edit to sfx.py's `manifest()` and a re-run - no
GDScript change - and it makes it impossible for the engine's idea of what
exists to drift from what is on disk, which is exactly how eight UI roles ended
up mapped to files that were never created.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tools.audio import curated_music as CURATED  # noqa: E402
from tools.audio import render as R          # noqa: E402
from tools.audio import sfx as SFX           # noqa: E402
from tools.audio import tracks as TRACKS     # noqa: E402


def _rel(path: Path) -> str:
    """Absolute path -> a res:// path Godot can load."""
    return "res://" + str(path.relative_to(R.AUDIO_DIR.parents[1])).replace("\\", "/")


def generate_sfx(only=None) -> dict:
    entries = SFX.manifest()
    manifest: dict = {}
    total = sum(len(e["variants"]) for e in entries.values())
    done = 0

    for key, entry in entries.items():
        if only and key not in only:
            continue
        folder = {"sfx": R.SFX_DIR, "voice": R.VOICE_DIR,
                  "ambience": R.AMBIENCE_DIR}[entry["folder"]]
        files = []
        for name, fn in entry["variants"]:
            path = R.write_wav(folder / f"{name}.wav", fn())
            files.append(_rel(path))
            done += 1
            print(f"\r  sfx {done}/{total}  {name:<28}", end="", flush=True)
        manifest[key] = {"bus": "Voice" if entry["folder"] == "voice" else "SFX",
                         "files": files}
    print()
    return manifest


def generate_music(only=None, procedural: bool = False) -> dict:
    # CURATED IS THE DEFAULT SHIPPED SOUNDTRACK. tools/audio/tracks/ is a
    # complete from-scratch synthesis engine and still works - pass
    # --procedural-music to render it instead - but Chris generated a separate
    # set of finished tracks with an external tool and asked for those to ship.
    # See tools/audio/curated_music.py for the state->file mapping and the
    # provenance caveat (licensing on the external tool is unconfirmed).
    if not procedural:
        return CURATED.build(only)

    manifest: dict = {}
    for name, fn in TRACKS.REGISTRY.items():
        if only and name not in only:
            continue
        t0 = time.time()
        stems = fn()
        entry = {"loop": name in TRACKS.LOOPING, "stems": {}}
        for stem, buf in stems.items():
            path = R.write_ogg(R.MUSIC_DIR / f"music_{name}_{stem}.ogg", buf)
            entry["stems"][stem] = _rel(path)
        seconds = len(next(iter(stems.values()))) / 44100.0
        manifest[name] = entry
        print(f"  music {name:<11} {seconds:5.1f}s  "
              f"{len(stems)} stem(s)  rendered in {time.time() - t0:.1f}s")
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", help="comma-separated keys/track names")
    ap.add_argument("--music-only", action="store_true")
    ap.add_argument("--sfx-only", action="store_true")
    ap.add_argument("--procedural-music", action="store_true",
                    help="render the from-scratch synth soundtrack instead of "
                         "copying the curated Tracks/ set")
    ap.add_argument("--no-prune", action="store_true",
                    help="keep files this run did not write")
    args = ap.parse_args()

    only = set(args.only.split(",")) if args.only else None
    R.ensure_dirs()
    t0 = time.time()

    manifest_path = R.AUDIO_DIR / "audio_manifest.json"
    previous = {}
    if manifest_path.exists():
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))

    sfx_manifest = {} if args.music_only else generate_sfx(only)
    music_manifest = {} if args.sfx_only else generate_music(only, args.procedural_music)

    # A partial run must not truncate the manifest to only what it regenerated.
    if args.music_only or only:
        sfx_manifest = {**previous.get("sfx", {}), **sfx_manifest}
    if args.sfx_only or only:
        music_manifest = {**previous.get("music", {}), **music_manifest}

    manifest_path.write_text(json.dumps(
        {"sfx": sfx_manifest, "music": music_manifest}, indent=2) + "\n",
        encoding="utf-8")

    # Pruning is only safe on a full run - a partial run legitimately did not
    # write most of the tree.
    if not args.no_prune and not (only or args.music_only or args.sfx_only):
        removed = R.prune()
        if removed:
            print(f"  pruned {len(removed)} orphaned file(s)")

    print(f"\n{R.summary()} in {time.time() - t0:.1f}s")
    print(f"manifest: {manifest_path}")
    print("\nNow reimport so Godot writes the .import sidecars:")
    print("  ./Godot_v4.7.1-stable_win64_console.exe --headless --editor --import")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
