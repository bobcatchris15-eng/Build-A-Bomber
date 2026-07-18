#!/bin/bash
# Reusable helper: forces Godot to properly reimport changed .glb assets.
#
# Godot in --script/console run mode NEVER reimports on its own - it only
# reads whatever is cached in .godot/imported/. Rebuilding a .glb in Blender
# and then immediately running a capture/test script silently renders the
# OLD cached mesh with no error (a real bug this session hit and had to
# diagnose the hard way - see DECISIONS_NEEDED.md 2026-07-13 cont'd 9).
# Running --headless --editor --import DIRECTLY on the real project also
# doesn't reliably trigger it in this environment. The one procedure
# confirmed to work (documented in project memory from an earlier session):
# import into an ISOLATED COPY via --path, then copy back .godot/imported/,
# .godot/uid_cache.bin, and every *.import sidecar next to its asset.
#
# Run this after ANY tools/blender/build_meshes.py rebuild, BEFORE trusting
# a screenshot or test result.
#
# Usage: ./scratch/reimport_assets.sh   (run from the prototype/ directory)

set -e
REAL="$(pwd)"
SCRATCH_ROOT="C:/Users/Chris/AppData/Local/Temp/claude/E--Build-A-Bomber/515c4c38-bcb4-4d28-839d-866d46eefd44/scratchpad"
DST="$SCRATCH_ROOT/reimport_copy"

mkdir -p "$DST"

echo "=== Syncing assets/ into isolated copy ==="
powershell.exe -NoProfile -Command "robocopy '$(cygpath -w "$REAL/assets")' '$(cygpath -w "$DST/assets")' /E /MIR /NFL /NDL /NJH /NJS /NP; exit 0"

# First run: the isolated copy needs project.godot + scripts/scenes/etc too,
# not just assets - only copy the rest if this is the isolated copy's first use.
if [ ! -f "$DST/project.godot" ]; then
	echo "=== First run: copying full project (excluding UPBGE/progress_captures/.godot) ==="
	powershell.exe -NoProfile -Command "robocopy '$(cygpath -w "$REAL")' '$(cygpath -w "$DST")' /E /XD '$(cygpath -w "$REAL/UPBGE-0.30-windows-x86_64")' '$(cygpath -w "$REAL/progress_captures")' '$(cygpath -w "$REAL/.godot")' /NFL /NDL /NJH /NJS /NP; exit 0"
fi

echo "=== Running isolated reimport ==="
timeout 200 ./Godot_v4.3-stable_win64_console.exe --path "$DST" --headless --editor --import 2>&1 | tail -5

echo "=== Copying import artifacts back ==="
cp -rf "$DST/.godot/imported/." "$REAL/.godot/imported/"
cp -f "$DST/.godot/uid_cache.bin" "$REAL/.godot/uid_cache.bin"
cd "$DST"
find . -iname "*.import" | while read -r f; do
	mkdir -p "$REAL/$(dirname "$f")"
	cp -f "$f" "$REAL/$f"
done
cd "$REAL"

echo "=== Reimport complete ==="
