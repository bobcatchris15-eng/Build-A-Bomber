"""Procedural audio authoring for Kitbash Command.

WHY THIS PACKAGE EXISTS. Every other asset class in this repo is authored by a
script - hulls and parts by tools/blender/build_meshes.py, icons by
generate_icons.py, terrain and faction textures by GDScript bakers. Audio was the
exception: tools/generate_audio.py synthesised 20 files from `random()` noise
multiplied by `exp()` decay, in per-sample Python loops, and that was the whole
soundscape. It got sound into the game, which was the right call at the time, and
it was also the ceiling.

This package is that generator rebuilt as a real synthesis toolkit. It stays
procedural rather than moving to recorded samples for the same reasons the mesh
pipeline is procedural: the source of truth is a diffable text file, a tweak is a
one-line edit and a re-render rather than a studio session, and there is no
third-party licensing surface anywhere in the shipped audio.

LAYERING. Modules depend strictly downward, so there are no cycles:

    dsp          numpy/scipy primitives. Knows nothing about music or the game.
    instruments  patches built from dsp. Knows about timbre, not about songs.
    sequencer    pattern/tracker timing. Knows about bars, not about timbre.
    voice        formant synthesis. Depends on dsp only.
    tracks/      one module per song. Depends on instruments + sequencer.
    sfx          every non-music sound. Depends on dsp + voice.
    render       file output and Godot .import sidecars. Depends on nothing above.

DETERMINISM IS A HARD REQUIREMENT, NOT A NICETY. Every generator takes an explicit
seed and every random draw goes through it. Re-running the tool must produce
byte-identical output, because these are binary files under version control - a
generator that drifts between runs turns every unrelated regeneration into a
multi-megabyte diff, and that is how a procedural pipeline stops being rerunnable
in practice. tools/blender/build_meshes.py is the cautionary tale already
documented in CLAUDE.md.
"""

SAMPLE_RATE = 44100
