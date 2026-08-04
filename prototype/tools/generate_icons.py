import os
import re

# ---------------------------------------------------------------------------
# ONE STROKE COLOUR FOR EVERY ICON
# ---------------------------------------------------------------------------
# = ui_tokens.gd TEXT_SECONDARY (0.678, 0.663, 0.627).
#
# THE RULE: icons are monochrome chrome. Colour is carried by the CONTROL's
# state, not by the glyph - a Button's icon dims with its disabled plate, a
# DangerButton's icon reads as alert because the button does. This is the same
# rule ui_tokens.gd states for fills ("signal colour is for STATE, not for
# decorating actions"), applied to the icon set.
#
# WHAT IT REPLACES. The 35 icons authored before ui_tokens.gd existed carried
# SEVENTEEN different stroke colours between them - #38BDF8, #4ADE80, #EF4444,
# #A855F7, #F43F5E, #94A3B8 and a dozen more. Every one was a cool-toned web
# palette value that appears nowhere in the token set, and they were the reason
# the build bar rendered its factory and hull icons in sky blue against warm
# powdercoat. Seventeen accent colours is not a design system with an icon set;
# it is a design system with a sticker collection.
#
# Enforced by rewrite rather than by editing 35 literals, so a hand-added icon
# that arrives with its own colour is normalised instead of quietly drifting.
# test_ui_icons_share_one_stroke_colour guards it from the other end.
ICON_STROKE = "#ADA9A0"

# Derived from this file's own location, not hardcoded. The previous value was
# an absolute path into a checkout that no longer exists
# (a since-removed e:\ checkout), so running this script silently wrote 35
# icons to a
# directory nobody reads and reported success.
ICON_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "icons")
)
os.makedirs(ICON_DIR, exist_ok=True)

icons = {
    "icon_metal.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#D0D5DD" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M4 8l8-4 8 4v8l-8 4-8-4V8z"/>
  <path d="M4 8l8 4 8-4"/>
  <path d="M12 12v8"/>
</svg>''',

    "icon_crystal.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#38BDF8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polygon points="12 2 19 9 12 22 5 9"/>
  <line x1="5" y1="9" x2="19" y2="9"/>
  <line x1="12" y1="2" x2="12" y2="22"/>
</svg>''',

    "icon_power.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#FACC15" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polygon points="13 2 4 14 11 14 11 22 20 10 13 10"/>
</svg>''',

    "icon_credits.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#4ADE80" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="9"/>
  <path d="M12 6v12M15 9.5a2.5 2.5 0 0 0-5 0c0 3 5 1.5 5 4.5a2.5 2.5 0 0 1-5 0"/>
</svg>''',

    "icon_attack.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#EF4444" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M14.5 17.5L3 6V3h3l11.5 11.5"/>
  <path d="M13 19l6-6"/>
  <path d="M16 16l4 4"/>
  <path d="M19 13l2 2"/>
  <path d="M9.5 17.5L21 6V3h-3L6.5 14.5"/>
</svg>''',

    "icon_defense.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#60A5FA" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
</svg>''',

    "icon_repair.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#34D399" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>
</svg>''',

    "icon_salvage.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#F97316" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/>
  <path d="m3.3 7 8.7 5 8.7-5"/>
  <path d="M12 22V12"/>
</svg>''',

    "icon_target.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#F43F5E" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="10"/>
  <circle cx="12" cy="12" r="6"/>
  <circle cx="12" cy="12" r="2"/>
</svg>''',

    "icon_skull.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#94A3B8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M12 2a8 8 0 0 0-8 8c0 3.5 2 6.5 5 7.5V20h6v-2.5c3-1 5-4 5-7.5a8 8 0 0 0-8-8z"/>
  <circle cx="9" cy="10" r="1.5"/>
  <circle cx="15" cy="10" r="1.5"/>
  <path d="M10 17v3M14 17v3"/>
</svg>''',

    "icon_trophy.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#F59E0B" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/>
  <path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/>
  <path d="M4 22h16"/>
  <path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/>
  <path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/>
  <path d="M18 2H6v7a6 6 0 0 0 12 0V2z"/>
</svg>''',

    "icon_factory.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#CBD5E1" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M2 20h20"/>
  <path d="M20 20V9l-5 3V9l-5 3V4H2v16"/>
  <rect x="5" y="8" width="3" height="3"/>
  <rect x="5" y="14" width="3" height="3"/>
</svg>''',

    "icon_powerplant.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#EAB308" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M4 20h16L17 4H7L4 20z"/>
  <path d="M7 12h10"/>
  <path d="M12 4v16"/>
</svg>''',

    "icon_extractor.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#A855F7" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M12 2v20"/>
  <path d="M17 5H7l-3 7h16l-3-7z"/>
  <path d="M4 20h16"/>
</svg>''',

    "icon_hq.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#3B82F6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M3 21h18"/>
  <path d="M5 21V7l7-4 7 4v14"/>
  <polygon points="12 9 13.5 12 17 12.5 14.5 15 15 18.5 12 17 9 18.5 9.5 15 7 12.5 10.5 12"/>
</svg>''',

    "icon_turret.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#F43F5E" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="14" r="6"/>
  <path d="M12 8V2M9 5h6"/>
  <path d="M4 20h16"/>
</svg>''',

    "icon_gear.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#94A3B8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="3"/>
  <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/>
</svg>''',

    "icon_wrench.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#64748B" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>
</svg>''',

    "icon_menu.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#F8FAFC" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <line x1="3" y1="12" x2="21" y2="12"/>
  <line x1="3" y1="6" x2="21" y2="6"/>
  <line x1="3" y1="18" x2="21" y2="18"/>
</svg>''',

    "icon_back.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#F8FAFC" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <line x1="19" y1="12" x2="5" y2="12"/>
  <polyline points="12 19 5 12 12 5"/>
</svg>''',

    "icon_close.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#EF4444" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <line x1="18" y1="6" x2="6" y2="18"/>
  <line x1="6" y1="6" x2="18" y2="18"/>
</svg>''',

    "icon_chevron_left.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#F8FAFC" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polyline points="15 18 9 12 15 6"/>
</svg>''',

    "icon_chevron_right.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#F8FAFC" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polyline points="9 18 15 12 9 6"/>
</svg>''',

    "icon_rotate_left.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#38BDF8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polyline points="1 4 1 10 7 10"/>
  <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>
</svg>''',

    "icon_rotate_right.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#38BDF8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polyline points="23 4 23 10 17 10"/>
  <path d="M20.49 15a9 9 0 1 1-2.13-9.36L23 10"/>
</svg>''',

    "icon_play.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#4ADE80" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polygon points="5 3 19 12 5 21 5 3"/>
</svg>''',

    "icon_pause.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#FACC15" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <rect x="6" y="4" width="4" height="16"/>
  <rect x="14" y="4" width="4" height="16"/>
</svg>''',

    "icon_undo.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#94A3B8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M3 7v6h6"/>
  <path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/>
</svg>''',

    "icon_redo.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#94A3B8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M21 7v6h-6"/>
  <path d="M3 17a9 9 0 0 1 9-9 9 9 0 0 1 6 2.3l3 2.7"/>
</svg>''',

    "icon_check.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#4ADE80" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polyline points="20 6 9 17 4 12"/>
</svg>''',

    "icon_hull.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#60A5FA" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M2 12l3-6h14l3 6-3 6H5l-3-6z"/>
  <line x1="8" y1="6" x2="8" y2="18"/>
  <line x1="16" y1="6" x2="16" y2="18"/>
</svg>''',

    "icon_weapon.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#EF4444" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <rect x="3" y="9" width="10" height="6" rx="1"/>
  <path d="M13 11h8v2h-8z"/>
  <line x1="6" y1="15" x2="6" y2="19"/>
</svg>''',

    "icon_engine.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#F59E0B" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="8"/>
  <path d="M12 4v16M4 12h16M6.34 6.34l11.32 11.32M6.34 17.66L17.66 6.34"/>
</svg>''',

    "icon_armor.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#94A3B8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <rect x="4" y="4" width="16" height="16" rx="2"/>
  <line x1="4" y1="12" x2="20" y2="12"/>
  <line x1="12" y1="4" x2="12" y2="20"/>
</svg>''',

    "icon_info.svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#38BDF8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="10"/>
  <line x1="12" y1="16" x2="12" y2="12"/>
  <line x1="12" y1="8" x2="12.01" y2="8"/>
</svg>'''
}

# ---------------------------------------------------------------------------
# HULL BUILDER PRIMITIVE ICONS
# ---------------------------------------------------------------------------
# VISUAL/UI plan item 0. The Hull Builder's primitive picker (hull_builder.gd's
# PRIMITIVES table) used 19 Unicode geometry glyphs as its button faces - ⬢ for
# Box, ⏢ for Frustum, ⬡ for Hex Prism and so on. They were the most defensible
# glyphs in the codebase, because each one genuinely depicted its primitive
# rather than decorating it, but they still had two real problems: the available
# Unicode shapes only approximate the primitives (there is no "chamfer box" or
# "fender" character, so those were approximated by whatever was closest), and
# they rendered in the UI font, so their weight and size drifted from every other
# icon in the interface.
#
# ONE VISUAL LANGUAGE, so the picker reads as a set rather than 19 unrelated
# marks:
#   * Warm neutral stroke (#ADA9A0 = ui_tokens.gd TEXT_SECONDARY) rather than the
#     per-icon saturated colours the older icons above use. These sit on bakelite
#     buttons in a dense grid; 19 saturated marks would be noise.
#   * Solids that need a 3D read get a light isometric treatment with the top
#     face drawn. Sections and profiles (I-Beam, L-Beam, Slope, Frustum) are
#     drawn flat, because the profile IS the information.
#   * 2px stroke, 24x24 box, ~4px margin, matching the icons above.
def _prim(body):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" '
        'height="24" fill="none" stroke="%s" stroke-width="2" '
        'stroke-linecap="round" stroke-linejoin="round">\n%s\n</svg>'
        % (ICON_STROKE, body)
    )


primitives = {
    # Isometric cube: front face, side face, top face.
    "icon_prim_box.svg": _prim(
        '  <path d="M4 8l8-4 8 4v8l-8 4-8-4V8z"/>\n'
        '  <path d="M4 8l8 4 8-4M12 12v8"/>'
    ),
    # A globe: outline, equator, and one meridian. The meridian is what stops it
    # reading as a lens - an outline plus a single flat ellipse is exactly the
    # shape of an eye, which is how the first version came out.
    "icon_prim_sphere.svg": _prim(
        '  <circle cx="12" cy="12" r="8"/>\n'
        '  <ellipse cx="12" cy="12" rx="8" ry="3.2"/>\n'
        '  <ellipse cx="12" cy="12" rx="3.2" ry="8"/>'
    ),
    # Tube: elliptical top, straight walls, curved bottom.
    "icon_prim_cylinder.svg": _prim(
        '  <ellipse cx="12" cy="6" rx="7" ry="2.5"/>\n'
        '  <path d="M5 6v12M19 6v12"/>\n'
        '  <path d="M5 18a7 2.5 0 0 0 14 0"/>'
    ),
    # Triangular prism, seen at an angle: the sloped face plus depth.
    "icon_prim_wedge.svg": _prim(
        '  <path d="M4 19V9l8-4v10z"/>\n'
        '  <path d="M4 19l8-4 6 3-6 3z"/>\n'
        '  <path d="M12 5l6 3v10l-6-3"/>'
    ),
    "icon_prim_cone.svg": _prim(
        '  <path d="M12 4l7 13"/>\n'
        '  <path d="M12 4L5 17"/>\n'
        '  <ellipse cx="12" cy="17" rx="7" ry="2.5"/>'
    ),
    # A doughnut in perspective. The outer ellipse is drawn as two arcs with a
    # visible tube thickness at the sides, because two concentric ellipses alone
    # read as an EYE at 24px - which is how the first version came out, and it sat
    # three rows from a sphere that had the same problem.
    "icon_prim_torus.svg": _prim(
        '  <ellipse cx="12" cy="12" rx="9.5" ry="5.5"/>\n'
        '  <ellipse cx="12" cy="12" rx="4.5" ry="1.6"/>\n'
        '  <path d="M2.5 12a9.5 5.5 0 0 0 19 0"/>'
    ),
    # Side profile: box with the top-front edge cut away. The Lego-slope read.
    "icon_prim_slope.svg": _prim('  <path d="M4 19V11l14-6v14z"/>\n  <path d="M4 11h14"/>'),
    # Flat trapezoid - a box tapered to a smaller top footprint.
    "icon_prim_frustum.svg": _prim('  <path d="M3 19L7 5h10l4 14z"/>\n  <path d="M7 5h10"/>'),
    # Box with every edge bevelled: an octagon, with the four corner cuts drawn as
    # short chords so the bevel reads as a CUT rather than a rounded corner. The
    # first version added interior iso edges on top of the octagon, which at 24px
    # just filled the shape with lines.
    "icon_prim_chamfer_box.svg": _prim(
        '  <path d="M8.5 4h7l4.5 4.5v7L15.5 20h-7L4 15.5v-7z"/>\n'
        '  <path d="M8.5 4l1.5 1.5M15.5 4l-1.5 1.5M20 8.5l-1.5 1.5M20 15.5l-1.5-1.5"/>'
    ),
    # Flat-bottomed half-round trough seen end-on.
    "icon_prim_half_cylinder.svg": _prim(
        '  <path d="M4 16a8 8 0 0 1 16 0"/>\n'
        '  <path d="M4 16h16"/>\n'
        '  <path d="M4 16v2h16v-2"/>'
    ),
    # Dome on a flat base.
    "icon_prim_hemisphere.svg": _prim(
        '  <path d="M4 15a8 8 0 0 1 16 0"/>\n'
        '  <ellipse cx="12" cy="15" rx="8" ry="2.5"/>'
    ),
    # Stadium shape: rounded-end cylinder, drawn lying down like a fuselage pod.
    "icon_prim_capsule.svg": _prim('  <rect x="3" y="8" width="18" height="8" rx="4"/>'),
    "icon_prim_i_beam.svg": _prim(
        '  <path d="M5 4h14M5 20h14"/>\n  <path d="M12 4v16"/>\n'
        '  <path d="M9 4v2h6V4M9 20v-2h6v2"/>'
    ),
    "icon_prim_l_beam.svg": _prim('  <path d="M6 4v16h14"/>\n  <path d="M6 4h4v12h10v4"/>'),
    "icon_prim_hex_prism.svg": _prim(
        '  <path d="M8 4h8l4 8-4 8H8l-4-8z"/>\n  <path d="M8 4l4 8 4-8M12 12v8"/>'
    ),
    "icon_prim_pyramid.svg": _prim(
        '  <path d="M12 4L4 18h16z"/>\n  <path d="M12 4v14"/>\n  <path d="M4 18l8-3 8 3"/>'
    ),
    # Open arch - a half-torus, i.e. two concentric arcs with open ends.
    "icon_prim_fender.svg": _prim(
        '  <path d="M3 18a9 9 0 0 1 18 0"/>\n'
        '  <path d="M7 18a5 5 0 0 1 10 0"/>\n'
        '  <path d="M3 18h4M17 18h4"/>'
    ),
    # A dome stretched along one axis: wide and low, the cockpit-bubble read.
    "icon_prim_canopy.svg": _prim(
        '  <path d="M2 16c0-6 4.5-9 10-9s10 3 10 9"/>\n'
        '  <path d="M2 16h20"/>'
    ),
    # Flat annulus, seen face-on: concentric circles, no perspective, which is
    # what separates it from Torus above.
    "icon_prim_ring.svg": _prim(
        '  <circle cx="12" cy="12" r="9"/>\n  <circle cx="12" cy="12" r="5"/>'
    ),
}

icons.update(primitives)

# Normalise every stroke to ICON_STROKE. The primitives above are already
# authored that way; this is what brings the 35 older icons onto the same
# palette without rewriting each of their literals. `fill` is left alone - the
# icons are stroke-only, and any fill they carry is "none".
_STROKE_RE = re.compile(r'stroke="#[0-9A-Fa-f]{3,8}"')
recoloured = 0
for name, svg in list(icons.items()):
    fixed, n = _STROKE_RE.subn('stroke="%s"' % ICON_STROKE, svg)
    if n and fixed != svg:
        recoloured += 1
    icons[name] = fixed

for filename, content in icons.items():
    filepath = os.path.join(ICON_DIR, filename)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)

print(
    "Successfully generated %d SVG icons (%d Hull Builder primitives, "
    "%d recoloured to %s) in %s"
    % (len(icons), len(primitives), recoloured, ICON_STROKE, ICON_DIR)
)
