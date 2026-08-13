"""
One-shot sweep: remove emoji and decorative glyphs from user-facing UI strings.

WHY THIS EXISTS AS A SCRIPT rather than fifty hand edits: the sites are spread
across nine files and the replacements are mechanical, so a reviewable table of
exact old -> new pairs is easier to check than a diff of fifty separate edits.
It is idempotent and it fails loudly if a pattern it expects is missing, so it
can be re-run after a merge to confirm nothing crept back.

THE RULE (stated in full at scripts/blueprint_namer.gd:6-13): the interface
plays it completely straight. The battle system is cartoonishly ridiculous and
the chrome's entire job is to refuse to acknowledge that. Emoji are the joke
written out loud - they collapse the deadpan, and they are also a
consumer-software tell that fights the steel/moulded/powdercoat material
direction. Arrows and dingbats go for the same reason: where a direction cue is
genuinely needed, scripts/ui_icons.gd already registers a real icon set
(chevron_left, chevron_right, undo, redo, play) that renders as line art
instead of as a font fallback square.

Several strings are also re-registered while we are in here - "TELEMETRY",
"TACTICAL ANALYSIS & ADVICE" and "VICTORY!" are the interface getting excited
about itself. Equipment documentation does not get excited.

DELIBERATELY KEPT: em dash, bullet, degree sign, and the box-drawing used in
the hull builder's keyboard hints. Those are typography, not decoration.

Run once from prototype/:  python tools/strip_ui_glyphs.py
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "scripts"

# (filename, exact old substring, new substring)
# Exact substrings rather than regex so that a near-miss is a loud failure
# instead of a silent partial match.
REPLACEMENTS = [
    # --- after_action_report.gd -------------------------------------------
    ("after_action_report.gd", '"⭐ MVP DESIGN"', '"BEST PERFORMING DESIGN"'),
    ("after_action_report.gd", '"\U0001f4a1 TACTICAL ANALYSIS & ADVICE"', '"ASSESSMENT"'),
    ("after_action_report.gd", '"\U0001f527 Iterate in Design Lab"', '"Iterate in Design Lab"'),
    ("after_action_report.gd", '"⚔️ Next Operation Stage >"', '"Next Operation Stage"'),
    ("after_action_report.gd", '"\U0001f3e0 Main Menu"', '"Main Menu"'),

    # --- battle_unit.gd ----------------------------------------------------
    # A cargo indicator on a unit. The glyph was a pickaxe; a filled block
    # reads as "carrying" at 10px far better and is not a picture of a joke.
    ("battle_unit.gd", '"⛏"', '"CARGO"'),

    # --- battlefield.gd ----------------------------------------------------
    ("battlefield.gd", '"❮ RETURN TO KITBASH LAB"', '"RETURN TO DESIGN LAB"'),
    ("battlefield.gd", '"\U0001f504 RESET TARGET DUMMIES"', '"RESET TARGET DUMMIES"'),

    # --- fleet_comparison_panel.gd -----------------------------------------
    ("fleet_comparison_panel.gd", '"⚡ FLEET BLUEPRINT TELEMETRY COMPARISON"', '"BLUEPRINT COMPARISON"'),
    ("fleet_comparison_panel.gd", '"✖ Close"', '"Close"'),

    # --- hull_builder.gd ---------------------------------------------------
    ("hull_builder.gd", '" \U0001f6e0️ 1. FRAME BUILDER "', '"1. FRAME"'),
    ("hull_builder.gd", '" \U0001f3a8 2. HULL FINISHING & PLATING "', '"2. FINISHING & PLATING"'),
    ("hull_builder.gd", '"[↔] Mirror Across X"', '"Mirror Across X"'),
    ("hull_builder.gd", '"\U0001f504 High-Res Preview"', '"High-Res Preview"'),
    ("hull_builder.gd", '"\U0001f4be Save & Finalize Hull"', '"Save & Finalize Hull"'),

    # --- match_setup.gd ----------------------------------------------------
    ("match_setup.gd", '"◀ Back"', '"Back"'),
    ("match_setup.gd", '"Start Match ▶"', '"Start Match"'),

    # --- skirmish.gd -------------------------------------------------------
    ("skirmish.gd", '"\U0001f441 No enemies sighted"', '"No enemies sighted"'),
    ("skirmish.gd", '"\U0001f441 Enemy sighted: %d%s"', '"Enemy sighted: %d%s"'),
    ("skirmish.gd", '"⚡ Normal"', '"Normal"'),
    ("skirmish.gd", '"\U0001f527 Repair"', '"Repair"'),
    ("skirmish.gd", '"\U0001f4b0 Sell"', '"Sell"'),
    ("skirmish.gd", '"\U0001f4b0 Metal: %d   \U0001f48e Crystal: %d"', '"Metal: %d    Crystal: %d"'),
    ("skirmish.gd", '"⚡ Base Power: %s"', '"Base Power: %s"'),
    ("skirmish.gd", '"⚡ SUBSYSTEM TELEMETRY"', '"SUBSYSTEM STATUS"'),
    ("skirmish.gd", '"⚡ DIAGNOSTICS: %s"', '"SUBSYSTEM STATUS: %s"'),
    # Deadpan: the outcome is stated, not celebrated. An exclamation mark is
    # the interface having a feeling about the player's tractor full of guns.
    ("skirmish.gd", '"\U0001f3c6 VICTORY!" if victory else "\U0001f480 DEFEAT"',
                    '"VICTORY" if victory else "DEFEAT"'),

    # --- stat_calculator.gd ------------------------------------------------
    ("stat_calculator.gd", '"★ SAVE BLUEPRINT"', '"SAVE BLUEPRINT"'),
    ("stat_calculator.gd", '"⚡ TEST IN ARENA"', '"TEST IN ARENA"'),
    ("stat_calculator.gd", '"\U0001f4c1 FLEET LIBRARY"', '"BLUEPRINT LIBRARY"'),
    ("stat_calculator.gd", '"✂ DISCARD PART"', '"DISCARD PART"'),
    ("stat_calculator.gd", '"\U0001f504 Rotate 90° [R]"', '"Rotate 90° [R]"'),
    ("stat_calculator.gd", '"↶ Undo"', '"Undo"'),
    ("stat_calculator.gd", '"↷ Redo"', '"Redo"'),
    ("stat_calculator.gd", '"◀ Main Menu"', '"Main Menu"'),
    ("stat_calculator.gd", '"\U0001f6e0️ " + data.module_name.to_upper()',
                           'data.module_name.to_upper()'),

    # --- ui_stamp.gd -------------------------------------------------------
    ("ui_stamp.gd", '"★ " + stamp_text.to_upper() + " ★"', 'stamp_text.to_upper()'),
]


def main() -> int:
    missing = []
    edits = 0
    by_file = {}
    for filename, old, new in REPLACEMENTS:
        by_file.setdefault(filename, []).append((old, new))

    for filename, pairs in by_file.items():
        path = ROOT / filename
        if not path.exists():
            missing.append(f"{filename}: file not found")
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        for old, new in pairs:
            if old in text:
                text = text.replace(old, new)
                edits += 1
            elif new not in text:
                # Neither the old form nor the already-applied new form is
                # present - the pattern is wrong or the code moved.
                missing.append(f"{filename}: {old!r}")
        if text != original:
            path.write_text(text, encoding="utf-8")
            print(f"  updated {filename}")

    print(f"\n{edits} replacement(s) applied.")
    if missing:
        print("\nUNMATCHED - check these by hand:")
        for m in missing:
            print(f"  {m}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
