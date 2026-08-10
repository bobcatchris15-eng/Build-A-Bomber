# Third-Party Assets & Attribution

## Fonts
- **Source Sans Pro** (UI Font)
  - License: SIL Open Font License, Version 1.1 (`LICENSES/OFL.txt`)
  - Author: Paul D. Hunt (Adobe Systems Incorporated)
- **Source Code Pro** (Monospace / Technical Data Font)
  - License: SIL Open Font License, Version 1.1 (`LICENSES/OFL.txt`)
  - Author: Paul D. Hunt (Adobe Systems Incorporated)
- **Special Elite** (Stencil Font - stamped-materiel/model-instruction-booklet
  look: monospace, slab serifs, worn/uneven ink baked into the glyph shapes)
  - License: SIL Open Font License, Version 1.1 (`LICENSES/OFL.txt`)
  - Author: Astigmatic (astigmatic.com)

## Vector Icons
- Custom hand-authored SVG icons by Kitbash Command project contributors (`prototype/assets/icons/`).

## Audio
**Sound effects, comms and ambience are original and fully procedural. There are
no third-party samples, sample libraries, loops, soundfonts or impulse responses
in that layer, and no attribution is owed to anyone for it. The music is
different — see below — and its provenance is NOT yet confirmed as clear for
release.**

Every file under `prototype/assets/audio/sfx/`, `voice/` and `ambience/` — 66
sound banks across ~213 WAVs — is generated from source by
`prototype/tools/generate_audio.py`, which drives the synthesis package in
`prototype/tools/audio/`. Nothing is recorded and nothing is hand-edited in a
DAW; the Python source is the sole source of truth, and re-running the tool
reproduces the committed files byte for byte. That includes the two categories
most likely to be assumed licensed:

- **The soundtrack.** Six states (menu, lab, skirmish, operations, victory,
  defeat) written as tracker patterns in `tools/audio/tracks/` and rendered
  through synthesised instruments in `tools/audio/instruments.py` — oscillators,
  filters, drum synthesis, modal metal, tape emulation. No samples, no
  soundfont, no VST.
- **The ordnance vocalisations.** The "ka-POW" / "pyoo" weapon sounds are *not*
  voice recordings. They are formant synthesis — a Rosenberg glottal source
  through a cascade of moving resonators, in `tools/audio/voice.py`. No human
  was recorded, so there is no performer credit and no release to obtain.

### Music — externally generated, provenance TBD
The six music states ship as 13 finished tracks copied in from `Tracks/` at the
repo root by `prototype/tools/audio/curated_music.py`, **not** the procedural
soundtrack engine in `tools/audio/tracks/` (that engine still exists and still
renders a complete alternative soundtrack — run
`generate_audio.py --procedural-music` to use it instead). Five states play one
fixed track; skirmish rotates through a pool of eight so a match longer than
any single track doesn't just loop:

| State | Track(s) |
|---|---|
| menu | Saturday's Prototype (Main Menu) |
| lab | Concrete Swamp Logic |
| operations | The Midnight Brief |
| victory | Iron Fanfare (Victory) |
| defeat | Concrete Gravity (Defeat) |
| skirmish | Hostile Perimeter Breach, Grinding Steel Mandate, Iron Under Noon, Iron Undergrowth, Midnight Treads, Panic at the Perimeter, Silo Protocol, Winter in the Bunker — rotated, never repeating back to back |

**⚠ Before any public release or distribution:** confirm which tool generated
these tracks and its terms for commercial use, redistribution and (if
applicable) whether the underlying training data licensing is a concern for
this project. The track titles (`iron_fanfare_victory`, `saturday_s_prototype_main_menu`,
etc.) and file characteristics (192 kbps MP3 masters, no stems) are consistent
with an AI music generation service, but the specific service was not recorded
and has not been verified here. Until that is confirmed, treat this row of the
credits as **incomplete**, not as "no attribution owed."

### Third-party build-time dependencies (not shipped)
The generator imports these; they are developer tooling and none of their code
or data ends up in the game:

| Package | License | Used for |
|---|---|---|
| `numpy` | BSD-3-Clause | All DSP array maths |
| `scipy` | BSD-3-Clause | `signal.sosfilt` / `lfilter` filter implementations |
| `soundfile` (libsndfile) | BSD-3-Clause (LGPL-2.1 for libsndfile) | WAV and Ogg Vorbis encoding |

libsndfile is LGPL and is used as an unmodified dynamic library at authoring
time only. It is not linked into, redistributed with, or required by the game.
