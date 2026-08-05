# Reimports assets (regenerates the gitignored .godot import cache, which
# goes stale whenever a new autoload/class_name script or asset lands and
# breaks the test run with a misleading "Identifier ... not declared" error)
# then runs the full headless test suite. This is the command to run, not
# the raw `--headless --script run_tests.gd` invocation in README.md's
# "Tests" section history - that one only works on an already-warm cache.
#
# Usage: cd prototype; ./run_tests.ps1

$ErrorActionPreference = "Continue"
$godot = Join-Path $PSScriptRoot "Godot_v4.7.1-stable_win64_console.exe"

Write-Host "Reimporting assets (regenerating .godot import cache)..."
& $godot --headless --editor --import --quit --path $PSScriptRoot 2>&1 | Out-Null
$ErrorActionPreference = "Stop"

Write-Host "Running headless test suite..."
& $godot --headless --script run_tests.gd --path $PSScriptRoot
exit $LASTEXITCODE
