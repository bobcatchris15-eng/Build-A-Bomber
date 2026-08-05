#!/usr/bin/env bash
# Reimports assets (regenerates the gitignored .godot import cache, which
# goes stale whenever a new autoload/class_name script or asset lands and
# breaks the test run with a misleading "Identifier ... not declared" error)
# then runs the full headless test suite. This is the command to run, not
# the raw `--headless --script run_tests.gd` invocation in README.md's
# "Tests" section history - that one only works on an already-warm cache.
#
# Usage: cd prototype && ./run_tests.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

GODOT="./Godot_v4.7.1-stable_win64_console.exe"

echo "Reimporting assets (regenerating .godot import cache)..."
"$GODOT" --headless --editor --import --quit --path . > /dev/null 2>&1

echo "Running headless test suite..."
"$GODOT" --headless --script run_tests.gd --path .
