# Exports release builds for Windows, Linux and macOS with the version and
# build date stamped into each filename.
#
#   ./build_release.ps1                 # all three platforms
#   ./build_release.ps1 -Only Linux     # just one
#
# The version comes from project.godot's application/config/version, which is a
# real ProjectSettings key - the game can read it at runtime via
# ProjectSettings.get_setting("application/config/version"), so the number in
# the filename and the number the build reports about itself cannot drift.
#
# The filenames are built HERE and passed to Godot as the export path argument
# rather than being written into export_presets.cfg. That file's export_path is
# a static string with no variable interpolation, so stamping a date into it
# would mean editing the preset before every build and committing a churny diff
# each time. The CLI argument overrides the preset, which keeps the presets
# stable and the naming automatic.

param(
    [string]$Only = ""
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- version ---------------------------------------------------------------
$projectFile = Join-Path $PSScriptRoot "project.godot"
$versionLine = Select-String -Path $projectFile -Pattern '^config/version="([^"]+)"' | Select-Object -First 1
if (-not $versionLine) {
    Write-Error "No config/version found in project.godot - add it under [application]."
}
$version = $versionLine.Matches[0].Groups[1].Value
$stamp = Get-Date -Format "yyyyMMdd"
$base = "BuildABomber-v$version-$stamp"

# Short commit so a build can always be traced back to a tree state, even one
# built from uncommitted work.
$commit = (& git rev-parse --short HEAD 2>$null)
$dirty = if ((& git status --porcelain 2>$null)) { " (dirty tree)" } else { "" }

Write-Output "Build-A-Bomber release export"
Write-Output "  version : $version"
Write-Output "  date    : $stamp"
Write-Output "  commit  : $commit$dirty"
Write-Output "  basename: $base"
Write-Output ""

# --- godot binary ----------------------------------------------------------
$godot = Join-Path $PSScriptRoot "Godot_v4.3-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    $godot = Join-Path $PSScriptRoot "godot.exe"
}
if (-not (Test-Path $godot)) {
    Write-Error "No Godot binary found next to this script."
}

# Export needs a populated .godot import cache; a fresh clone or a newly
# regenerated asset set has none, and Godot will happily export a build with
# missing meshes rather than fail.
Write-Output "Reimporting assets..."
& $godot --headless --editor --import --quit 2>&1 | Out-Null

# --- targets ---------------------------------------------------------------
# Each entry: preset name exactly as it appears in export_presets.cfg, the
# output subdirectory, and the platform's expected extension. macOS exports as
# a .zip rather than a .dmg when built off-platform - .dmg creation needs macOS
# tooling, and the zip is what Godot produces on Windows.
$targets = @(
    @{ Preset = "Windows Desktop"; Dir = "windows"; Ext = ".exe" },
    @{ Preset = "Linux";           Dir = "linux";   Ext = ".x86_64" },
    @{ Preset = "macOS";           Dir = "macos";   Ext = ".zip" }
)

$results = @()
foreach ($t in $targets) {
    if ($Only -and $t.Preset -notlike "*$Only*") { continue }

    $outDir = Join-Path $PSScriptRoot "../builds/$($t.Dir)"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $outFile = Join-Path $outDir ($base + $t.Ext)

    Write-Output "Exporting $($t.Preset) -> $($base + $t.Ext)"
    & $godot --headless --export-release $t.Preset $outFile 2>&1 | ForEach-Object {
        if ($_ -match "ERROR|error:|Failed") { Write-Output "    $_" }
    }

    if (Test-Path $outFile) {
        $sizeMb = [math]::Round((Get-Item $outFile).Length / 1MB, 1)
        Write-Output "    OK  $sizeMb MB"
        $results += [pscustomobject]@{ Platform = $t.Preset; File = $outFile; SizeMB = $sizeMb }
    } else {
        Write-Output "    FAILED - no output produced"
        $results += [pscustomobject]@{ Platform = $t.Preset; File = "(none)"; SizeMB = 0 }
    }
}

Write-Output ""
Write-Output "=== build summary ==="
$results | Format-Table -AutoSize
