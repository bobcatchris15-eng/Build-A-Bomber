#!/usr/bin/env python3
"""Write the battle HUD icon set as editable SVG files.

Each icon is a 64x64 viewBox, pure white, no fill-rule tricks and no groups, so
opening one in Inkscape gives you the bare shapes on a single layer. They are
tinted at runtime by CanvasItem.modulate, which is why they are white and why
none of them carry colour of their own.

This script is a one-off convenience for laying the set down; the SVG files are
the asset. Editing a glyph means editing the SVG, not re-running this.
"""
import pathlib

OUT = pathlib.Path(__file__).resolve().parents[0]

HEADER = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" '
    'viewBox="0 0 64 64">\n'
    '  <title>{title}</title>\n'
)
FOOTER = '</svg>\n'

W = '#ffffff'

# Shared stroke recipe. Heavier than a typical UI icon because these are read at
# 18-22 px on a moving battlefield, where a 2 px stroke disappears.
S = 'fill="none" stroke="%s" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"' % W
SF = 'fill="%s" stroke="none"' % W

ICONS = {
    # --- Resources ---------------------------------------------------------
    # Ingot, seen slightly from above. Reads as "raw stock".
    "metal": '  <path %s d="M14 40 L20 24 L44 24 L50 40 Z"/>\n'
             '  <path %s d="M20 24 L26 18 L38 18 L44 24"/>\n' % (SF, S),

    # Cut gem: crown facets over a pavilion. Angular, so it never reads as a
    # droplet at small sizes.
    "crystal": '  <path %s d="M32 8 L52 26 L32 56 L12 26 Z"/>\n'
               '  <path %s d="M12 26 L52 26 M32 8 L32 56 M22 17 L32 26 L42 17"/>\n'
               % (SF, 'fill="none" stroke="#0E1116" stroke-width="3"'),

    # Bolt. The one icon allowed to be a cliche - anything else reads as
    # "settings" or "flash".
    "power": '  <path %s d="M36 4 L16 34 L29 34 L26 60 L48 28 L34 28 Z"/>\n' % SF,

    # Income: a rising step line with an arrowhead, not a bare arrow, so it
    # reads as "rate" rather than "up".
    "income": '  <path %s d="M10 48 L24 34 L34 42 L52 20"/>\n'
              '  <path %s d="M40 20 L54 20 L54 34"/>\n' % (S, S),

    # --- Production queue tiers -------------------------------------------
    # One / two / three chevrons. A tier ladder has to be countable at a
    # glance; distinct silhouettes per tier would make LIGHT<MEDIUM<HEAVY an
    # act of memory instead of arithmetic.
    "tier_light": '  <path %s d="M14 40 L32 22 L50 40"/>\n' % S,
    "tier_medium": '  <path %s d="M14 32 L32 14 L50 32 M14 50 L32 32 L50 50"/>\n' % S,
    "tier_heavy": '  <path %s d="M14 24 L32 8 L50 24 M14 40 L32 24 L50 40 '
                  'M14 56 L32 40 L50 56"/>\n' % S,

    # Structures: a plant, not a house. Silo plus shed roof plus a stack.
    "structures": '  <path %s d="M10 54 L10 30 L30 20 L30 54 Z"/>\n'
                  '  <path %s d="M38 54 L38 14 L50 14 L50 54"/>\n'
                  '  <path %s d="M10 54 L56 54"/>\n' % (S, S, S),

    # Defence: shield. Kept simple - it carries a state tint often.
    "defence": '  <path %s d="M32 6 L54 14 V32 C54 46 44 54 32 58 '
               'C20 54 10 46 10 32 V14 Z"/>\n' % S,

    # --- Orders -----------------------------------------------------------
    # Move: waypoint pin with a travel line into it.
    "move": '  <path %s d="M8 54 L26 36"/>\n'
            '  <circle cx="42" cy="20" r="9" %s/>\n'
            '  <path %s d="M42 29 L42 46"/>\n' % (S, S, S),

    # Attack: crosshair with a gap at the centre so the target under it is
    # still visible when this is drawn over the world.
    "attack": '  <circle cx="32" cy="32" r="17" %s/>\n'
              '  <path %s d="M32 4 L32 16 M32 48 L32 60 M4 32 L16 32 '
              'M48 32 L60 32"/>\n' % (S, S),

    # Stop: filled square. Unambiguous, and the only fully solid glyph in the
    # order row, which is what makes it findable without reading.
    "stop": '  <rect x="16" y="16" width="32" height="32" rx="3" %s/>\n' % SF,

    # Hold position: a mark pinned between two brackets.
    "hold": '  <path %s d="M14 12 L14 52 M50 12 L50 52"/>\n'
            '  <rect x="26" y="26" width="12" height="12" rx="2" %s/>\n' % (S, SF),

    # Patrol: a closed circuit with direction. Two arcs and two heads.
    "patrol": '  <path %s d="M16 22 A20 20 0 0 1 48 22"/>\n'
              '  <path %s d="M48 42 A20 20 0 0 1 16 42"/>\n'
              '  <path %s d="M42 14 L50 22 L42 30 M22 50 L14 42 L22 34"/>\n'
              % (S, S, S),

    # --- Stances ----------------------------------------------------------
    # The three stances share the shield silhouette so they read as one family,
    # and differ only in what is inside it: nothing moves (bar), it answers
    # (chevron), it hunts (spearhead).
    "stance_hold": '  <path %s d="M32 6 L54 14 V32 C54 46 44 54 32 58 '
                   'C20 54 10 46 10 32 V14 Z"/>\n'
                   '  <path %s d="M20 32 L44 32"/>\n' % (S, S),
    "stance_return": '  <path %s d="M32 6 L54 14 V32 C54 46 44 54 32 58 '
                     'C20 54 10 46 10 32 V14 Z"/>\n'
                     '  <path %s d="M21 36 L32 25 L43 36"/>\n' % (S, S),
    "stance_aggressive": '  <path %s d="M32 6 L54 14 V32 C54 46 44 54 32 58 '
                         'C20 54 10 46 10 32 V14 Z"/>\n'
                         '  <path %s d="M32 18 L43 40 L32 34 L21 40 Z"/>\n' % (S, SF),

    # --- Queue chips ------------------------------------------------------
    "cancel": '  <path %s d="M16 16 L48 48 M48 16 L16 48"/>\n' % S,
    "pause": '  <rect x="18" y="14" width="9" height="36" rx="2" %s/>\n'
             '  <rect x="37" y="14" width="9" height="36" rx="2" %s/>\n' % (SF, SF),
    "resume": '  <path %s d="M20 12 L50 32 L20 52 Z"/>\n' % SF,

    # --- Intel ------------------------------------------------------------
    # Alert: bare triangle plus bar and dot. No rounded "warning sign" chrome -
    # this is stamped over the world and needs a hard edge.
    "alert": '  <path %s d="M32 8 L58 54 L6 54 Z"/>\n'
             '  <path %s d="M32 24 L32 38"/>\n'
             '  <circle cx="32" cy="46" r="3" %s/>\n' % (S, S, SF),

    # Contact: a return on a scope. Expanding arcs off a point.
    "contact": '  <circle cx="20" cy="44" r="4" %s/>\n'
               '  <path %s d="M28 44 A12 12 0 0 0 20 32"/>\n'
               '  <path %s d="M40 44 A24 24 0 0 0 20 20"/>\n'
               '  <path %s d="M52 44 A36 36 0 0 0 20 8"/>\n' % (SF, S, S, S),

    # Structure complete / ready.
    "ready": '  <path %s d="M12 34 L26 48 L52 18"/>\n' % S,
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, body in sorted(ICONS.items()):
        text = HEADER.format(title=name.replace("_", " ")) + body + FOOTER
        (OUT / ("%s.svg" % name)).write_text(text, encoding="utf-8")
        print("wrote %s.svg" % name)
    print("%d icons" % len(ICONS))


if __name__ == "__main__":
    main()
