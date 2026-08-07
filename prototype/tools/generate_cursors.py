"""Generates the in-game cursor set.

WHY THIS WAS REWRITTEN. The first version drew 32x32 aliased shapes in flat
neon (Tailwind-ish cyan/red/green) with no outline. Three problems, all visible
in play:

  * NO ANTI-ALIASING. Every diagonal was a hard stair-step at cursor size.
  * NO CONTRAST HALO. A thin cyan reticle over pale sand and the same reticle
    over dark water are two different levels of "can you see it", and over the
    sand it effectively vanished.
  * OFF-PALETTE. The colours belonged to no part of the game; ui_tokens.gd
    already defines the signal palette every other piece of UI reads from.

This version supersamples 4x and downsamples with LANCZOS for real
anti-aliasing, draws every shape twice - once fat in near-black as a halo, then
in its signal colour on top - so a cursor holds up on any terrain, and takes its
colours from the project palette.

Run:  python tools/generate_cursors.py
Then reimport in Godot so the .import sidecars pick up the new files.
"""

import os
from PIL import Image, ImageDraw

CURSOR_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "cursors")
)
os.makedirs(CURSOR_DIR, exist_ok=True)

SIZE = 32
# Everything is drawn at SIZE*SS and shrunk. 4x is enough that a 2 px stroke
# lands on a clean edge, without the file taking meaningful time to produce.
SS = 4

# From scripts/ui_tokens.gd. Kept as literals rather than parsed out of the
# GDScript so this script needs no import machinery, but the values and names
# match, so a palette change is a two-file edit rather than a hunt.
SIGNAL_HAZARD = (224, 170, 46)    # attention, selection, warning
SIGNAL_ALERT = (200, 68, 50)      # damage, failure, destructive
SIGNAL_GO = (102, 156, 74)        # ready, affordable, confirmed
SIGNAL_INFO = (96, 146, 169)      # informational only, never an action
BONE = (239, 236, 229)            # the neutral light the UI text uses

# The halo. Near-black rather than pure, and not fully opaque, so it reads as a
# shadow under the shape instead of a second outline competing with it.
HALO = (10, 12, 14, 215)
HALO_GROW = 1


def _paint(halo, color, width):
    """Colour and stroke width for this pass."""
    if halo:
        return HALO, (width + HALO_GROW * 2) * SS
    return color + (255,), width * SS


def _p(x, y):
    return (x * SS, y * SS)


def line(d, halo, a, b, color, width):
    col, w = _paint(halo, color, width)
    d.line([_p(*a), _p(*b)], fill=col, width=int(w))


def ellipse(d, halo, box, color, width):
    col, w = _paint(halo, color, width)
    d.ellipse([_p(box[0], box[1]), _p(box[2], box[3])], outline=col, width=int(w))


def polygon(d, halo, seq, color, width=2, solid=False):
    """`solid` fills the body dark. Only for the big pointer shapes.

    The arrowheads on the move cursor are ~6 px across at final size; filling
    those dark turns each one into an indistinct blob and the four of them read
    as a smudge rather than as a four-way arrow. They get a flat signal-coloured
    fill instead, which is legible at that size.
    """
    col, w = _paint(halo, color, width)
    path = [_p(x, y) for x, y in seq]
    if halo:
        # A polygon outline does not grow outward usefully, so the halo is a
        # thick closed path around the same points.
        d.line(path + [path[0]], fill=col, width=int(w), joint="curve")
        return
    d.polygon(path, fill=((18, 21, 24, 245) if solid else col))
    d.line(path + [path[0]], fill=col, width=int(w), joint="curve")


def create_cursor(name, draw_fn):
    big = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    draw_fn(d, True)    # halo pass
    draw_fn(d, False)   # shape pass
    big.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(CURSOR_DIR, f"{name}.png"))


# --- The set -----------------------------------------------------------------
#
# Hotspots are declared in cursor_manager.gd and these shapes are drawn to match
# them: the arrow points at its own (0,0); everything else is centred on (16,16).

def draw_default(d, halo):
    # A plain arrow, slimmer than the original - which was wide enough to hide
    # whatever it was pointing at.
    polygon(d, halo, [(1, 1), (1, 21), (6, 16), (10, 25), (14, 23), (10, 15), (17, 15)],
            BONE, 2, True)


def draw_pointer(d, halo):
    # Pointer for interactive UI. Hazard-coloured because "this is interactive"
    # is exactly what SIGNAL_HAZARD is for.
    polygon(d, halo, [(8, 2), (12, 2), (12, 14), (17, 14), (21, 18), (19, 27), (9, 27)],
            SIGNAL_HAZARD, 2, True)


def draw_move(d, halo):
    # Four-way arrow with an OPEN centre - a solid middle hides the exact spot
    # the order will land on.
    for a, b in [((16, 4), (16, 12)), ((16, 20), (16, 28)),
                 ((4, 16), (12, 16)), ((20, 16), (28, 16))]:
        line(d, halo, a, b, SIGNAL_GO, 2)
    for tip, l, r in [((16, 2), (12, 8), (20, 8)), ((16, 30), (12, 24), (20, 24)),
                      ((2, 16), (8, 12), (8, 20)), ((30, 16), (24, 12), (24, 20))]:
        polygon(d, halo, [tip, l, r], SIGNAL_GO, 1)


def draw_attack(d, halo):
    # Targeting reticle: a ring with external tick marks rather than a ring plus
    # a full crosshair. Keeping the middle clear is what lets you see the target
    # you are about to click.
    ellipse(d, halo, (7, 7, 25, 25), SIGNAL_ALERT, 2)
    for a, b in [((16, 1), (16, 6)), ((16, 26), (16, 31)),
                 ((1, 16), (6, 16)), ((26, 16), (31, 16))]:
        line(d, halo, a, b, SIGNAL_ALERT, 2)


def draw_harvest(d, halo):
    # A pick. Reads as a tool at 32 px, which the original two crossed lines
    # did not.
    line(d, halo, (9, 25), (21, 11), SIGNAL_HAZARD, 3)
    line(d, halo, (14, 6), (25, 15), SIGNAL_HAZARD, 2)
    line(d, halo, (14, 6), (11, 16), SIGNAL_HAZARD, 2)


def draw_invalid(d, halo):
    # Forbidden. The slash stays inside the ring rather than running past it.
    ellipse(d, halo, (5, 5, 27, 27), SIGNAL_ALERT, 3)
    line(d, halo, (10, 10), (22, 22), SIGNAL_ALERT, 3)


def draw_build(d, halo):
    # A plot plan: four corner stakes around a centre mark. The original was a
    # plain square with a cross in it, which read as a selection box.
    ellipse(d, halo, (14, 14, 18, 18), SIGNAL_INFO, 2)
    for a, b in [((6, 6), (13, 6)), ((6, 6), (6, 13)),
                 ((26, 6), (19, 6)), ((26, 6), (26, 13)),
                 ((6, 26), (13, 26)), ((6, 26), (6, 19)),
                 ((26, 26), (19, 26)), ((26, 26), (26, 19))]:
        line(d, halo, a, b, SIGNAL_INFO, 2)


CURSORS = {
    "cursor_default": draw_default,
    "cursor_pointer": draw_pointer,
    "cursor_move": draw_move,
    "cursor_attack": draw_attack,
    "cursor_harvest": draw_harvest,
    "cursor_invalid": draw_invalid,
    "cursor_build": draw_build,
}


if __name__ == "__main__":
    for cursor_name, fn in CURSORS.items():
        create_cursor(cursor_name, fn)
        print(f"  wrote {cursor_name}.png")
    print(f"{len(CURSORS)} cursors -> {CURSOR_DIR}")
