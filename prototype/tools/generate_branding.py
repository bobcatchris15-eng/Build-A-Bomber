"""
Brand assets: the Kitbash Command mark and its wordmark plate.

WHY THESE ARE NOT IN assets/icons/. Two reasons, and the first is enforced by a
test:

  1. test_ui_icons_share_one_stroke_colour() scans EVERY .svg in assets/icons and
     requires a single neutral stroke (#ADA9A0). That rule is correct for chrome
     glyphs - colour belongs to a control's state, not to the glyph - and a logo
     is exactly the thing that must be exempt from it. Putting the mark there
     would either fail the suite or force the brand to be grey.
  2. A mark is not an icon. Icons are interchangeable at 24px on a grid; this is
     a fixed piece of identity.

WHY THE WORDMARK CARRIES NO LETTERS. Godot imports SVG through ThorVG, which
does not render <text> - a wordmark authored with text elements imports blank,
and the failure is silent. Hand-drawing "KITBASH COMMAND" as bezier paths would
be a lot of work for letterforms that would look worse than the real stencil
face the game already ships.

So the split is: this file authors the PLATE (chamfer, punched corners, the
part-number rule), and scripts/ui/wordmark.gd lays the stencil font over it as a
real Label. That is also the honest version of the L3 placard layer - an engraved
rating plate IS a metal blank with type struck into it.

Run:  python tools/generate_branding.py
Then: Godot_v4.7.1-stable_win64_console.exe --headless --editor --import
"""

import os

OUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "assets", "branding"
)
OUT_DIR = os.path.normpath(OUT_DIR)
os.makedirs(OUT_DIR, exist_ok=True)

# ui_tokens.gd, duplicated as literals under the same stated-not-hidden rule
# generate_ui_plates.py uses - this is a build script and cannot import GDScript.
BASE_900 = "#13130F"
BASE_700 = "#252420"
BASE_500 = "#4A473E"
BASE_400 = "#676358"
TEXT_PRIMARY = "#EFE9E5"
HAZARD = "#E0AA2E"


# ---------------------------------------------------------------------------
# THE MARK
# ---------------------------------------------------------------------------
# A sprue gate feeding into a chevron.
#
# The idea it has to carry: this is a war game made of model kit parts. A
# military chevron alone is a hundred other games; a sprue runner alone is a
# hobby shop. The join is the whole concept - a part still attached to its
# runner, about to be clipped off and glued to something.
#
# CONSTRAINT THAT DROVE THE FORM: it has to survive 32px. That rules out the
# obvious version (a detailed sprue frame with several parts on it) and forces
# exactly three shapes - runner bar, gate stub, chevron. Anything more becomes
# mud at taskbar size.
MARK = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <!-- Runner: the sprue bar the part is still attached to. Deliberately plain
       and slightly off-centre, because a runner is stock material, not design. -->
  <rect x="6" y="8" width="52" height="7" rx="1.5" fill="{BASE_500}"/>
  <!-- Gate: the thin neck you cut. Narrow enough to read as "about to break". -->
  <rect x="29" y="15" width="6" height="7" fill="{BASE_400}"/>
  <!-- Chevron: the part itself. Hazard amber so the mark has one saturated
       accent and the rest stays equipment-grey.
       ONE CHEVRON, NOT TWO. The first version stacked a smaller grey chevron
       beneath this for a rank-insignia cadence. Rasterised at 32px it vanished
       into the dark ground and left a smear under the amber - the mark got
       busier and less legible at exactly the size that matters most. The sprue
       plus one part IS the concept; the second chevron was decoration. -->
  <path d="M32 24 L58 58 L45 58 L32 41 L19 58 L6 58 Z" fill="{HAZARD}"/>
</svg>"""


# ---------------------------------------------------------------------------
# THE WORDMARK PLATE
# ---------------------------------------------------------------------------
# An engraved aluminium rating plate: chamfered edge, four punched mounting
# holes, a hairline rule where the part number goes. The game's own name is
# struck into it at runtime by wordmark.gd.
#
# Two lockups, because a title screen and a corner watermark want different
# aspect ratios and scaling one into the other's slot is how a wordmark ends up
# with 6px type or an acre of dead metal.
def plate(width, height, hole_inset=14, rule=True):
    r = 3
    chamfer = 4
    rule_y = height - 18
    holes = ""
    for hx in (hole_inset, width - hole_inset):
        for hy in (hole_inset - 4, height - hole_inset + 4):
            holes += (
                f'  <circle cx="{hx}" cy="{hy}" r="3.2" fill="{BASE_900}"/>\n'
                f'  <circle cx="{hx}" cy="{hy}" r="3.2" fill="none" '
                f'stroke="{BASE_400}" stroke-width="0.8"/>\n'
            )
    rule_el = ""
    if rule:
        rule_el = (
            f'  <path d="M{hole_inset + 10} {rule_y} H{width - hole_inset - 10}" '
            f'stroke="{BASE_400}" stroke-width="1" opacity="0.6"/>\n'
        )
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">
  <!-- Plate body. Two stacked rects rather than one with a stroke: the lighter
       upper edge and darker lower edge are the chamfer catching a light from
       above, which is the same top-left lighting convention every 9-slice plate
       in assets/textures/ui is baked with. A shadow that disagrees with those
       reads as texture noise. -->
  <rect x="1" y="1" width="{width - 2}" height="{height - 2}" rx="{r}" fill="{BASE_700}"/>
  <path d="M{1 + chamfer} 1 H{width - 1 - chamfer} L{width - 1} {1 + chamfer} V{height - 1 - chamfer}
           L{width - 1 - chamfer} {height - 1} H{1 + chamfer} L1 {height - 1 - chamfer}
           V{1 + chamfer} Z"
        fill="none" stroke="{BASE_400}" stroke-width="1.2" opacity="0.75"/>
  <path d="M{1 + chamfer} 2.4 H{width - 1 - chamfer}" stroke="{TEXT_PRIMARY}"
        stroke-width="1" opacity="0.18"/>
{holes}{rule_el}</svg>"""


ASSETS = {
    "mark.svg": MARK,
    # Horizontal: title screen and the Front Desk header.
    "wordmark_plate_horizontal.svg": plate(420, 96),
    # Stacked: narrow contexts - the loading screen, a corner watermark.
    "wordmark_plate_stacked.svg": plate(240, 140),
}


def main():
    for name, content in ASSETS.items():
        path = os.path.join(OUT_DIR, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"  {name}")
    print(f"\n{len(ASSETS)} brand asset(s) written to {OUT_DIR}")


if __name__ == "__main__":
    main()
