"""Authors the running-gear service stencils as SVG, then rasterises them with
Inkscape.

Hull decals are drawn procedurally in hull_decals.gd, pixel by pixel. That is
fine for a roundel or a stripe, but it is a bad way to draw LETTERFORMS and
precise linework, and the running gear wants exactly that: the small stencilled
plates real vehicles carry around their suspension and final drives - load
ratings, lift and jack points, grease intervals, tow shackles, hazard chevrons.

Authoring them as vector art and rasterising once is both better looking and
easier to revise than a wall of set_pixel calls. Inkscape does the rasterising;
the SVG sources stay in assets/textures/decals/src so they remain editable.

Usage:  python tools/build_locomotion_decals.py
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "textures", "decals", "src")
OUT = os.path.join(ROOT, "assets", "textures", "decals")
INKSCAPE = r"C:\Program Files\Inkscape\bin\inkscape.exe"
SIZE = 256

os.makedirs(SRC, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

# White-on-transparent throughout: hull_decals.gd tints decals per faction at
# runtime (get_visual_decal_tint), so baking a colour here would fight it.
INK = "#FFFFFF"

HEADER = (
    '<svg xmlns="http://www.w3.org/2000/svg" width="{s}" height="{s}" '
    'viewBox="0 0 256 256">'
)


def stencil_text(lines, size=34, weight="bold"):
    """Stencilled text block, centred. The font stack falls back through the
    condensed grotesques Windows actually ships, so this renders the same on a
    clean machine as it does here."""
    out = []
    n = len(lines)
    total = n * size * 1.18
    y0 = 128 - total / 2 + size * 0.92
    for i, line in enumerate(lines):
        out.append(
            '<text x="128" y="{y:.1f}" font-family="Bahnschrift Condensed,'
            'Arial Narrow,DIN Condensed,Impact,sans-serif" font-size="{s}" '
            'font-weight="{w}" letter-spacing="2" fill="{ink}" '
            'text-anchor="middle">{t}</text>'.format(
                y=y0 + i * size * 1.18, s=size, w=weight, ink=INK, t=line
            )
        )
    return "".join(out)


def frame(stroke=7, inset=14, radius=8):
    return (
        '<rect x="{i}" y="{i}" width="{w}" height="{w}" rx="{r}" '
        'fill="none" stroke="{ink}" stroke-width="{s}"/>'
    ).format(i=inset, w=256 - inset * 2, r=radius, ink=INK, s=stroke)


DECALS = {
    # Load rating plate - goes on suspension anchors and hub carriers.
    "loco_load_rating": frame() + stencil_text(["MAX LOAD", "4 500 kg"], size=38),
    # Jacking / lift point - the triangle-on-bar symbol used on real chassis.
    "loco_lift_point": (
        '<path d="M128 44 L196 156 L60 156 Z" fill="none" stroke="{ink}" '
        'stroke-width="10" stroke-linejoin="round"/>'
        '<rect x="52" y="170" width="152" height="20" rx="4" fill="{ink}"/>'
        + stencil_text(["LIFT"], size=30)
    ).format(ink=INK),
    # Grease interval - stencilled next to bearing stations.
    "loco_grease_point": (
        '<circle cx="128" cy="106" r="46" fill="none" stroke="{ink}" '
        'stroke-width="10"/>'
        '<circle cx="128" cy="106" r="15" fill="{ink}"/>'
        '<rect x="120" y="30" width="16" height="34" fill="{ink}"/>'
        + stencil_text(["GREASE 50h"], size=27)
    ).format(ink=INK),
    # Hazard chevrons - final drives and anything that rotates.
    "loco_hazard_chevron": "".join(
        '<path d="M{x} 40 L{x2} 128 L{x} 216" fill="none" stroke="{ink}" '
        'stroke-width="22" stroke-linecap="butt"/>'.format(
            x=10 + i * 58, x2=68 + i * 58, ink=INK
        )
        for i in range(4)
    ),
    # Tow / recovery shackle marker.
    "loco_tow_point": (
        '<path d="M84 150 A46 46 0 1 1 172 150" fill="none" stroke="{ink}" '
        'stroke-width="16"/>'
        '<rect x="74" y="146" width="108" height="18" rx="6" fill="{ink}"/>'
        + stencil_text(["TOW"], size=30)
    ).format(ink=INK),
    # Track / drive tension index plate.
    "loco_tension_plate": (
        frame(stroke=6, inset=20)
        + '<rect x="44" y="112" width="168" height="10" fill="{ink}"/>'.format(ink=INK)
        + "".join(
            '<rect x="{x}" y="{y}" width="8" height="26" fill="{ink}"/>'.format(
                x=48 + i * 32, y=86 if i % 2 == 0 else 96, ink=INK
            )
            for i in range(6)
        )
        + stencil_text(["TENSION"], size=26)
    ),
}


def main():
    if not os.path.isfile(INKSCAPE):
        print("Inkscape not found at", INKSCAPE)
        return 1
    for name, body in DECALS.items():
        svg_path = os.path.join(SRC, name + ".svg")
        with open(svg_path, "w", encoding="utf-8") as fh:
            fh.write(HEADER.format(s=SIZE) + body + "</svg>")
        png_path = os.path.join(OUT, name + ".png")
        subprocess.run(
            [
                INKSCAPE,
                svg_path,
                "--export-type=png",
                "--export-filename=" + png_path,
                "--export-width=%d" % SIZE,
                "--export-height=%d" % SIZE,
                "--export-background-opacity=0",
            ],
            check=True,
            capture_output=True,
        )
        print("Rasterised:", png_path)
    print("LOCOMOTION_DECALS_DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
