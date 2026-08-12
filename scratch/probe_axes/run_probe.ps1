# Axis-probe bake runner.
#
# What this does:
#   1. Bakes scratch/probe_axes/axis_probe_input.json through the
#      project's existing bake_custom_hull.py using the installed
#      Blender 5.2 binary at C:\Program Files\Blender Foundation\Blender 5.2\blender.exe
#   2. Re-imports the resulting GLB through Blender's own glTF importer
#      (the same importer Godot uses, modulo the .gltf file format wrapper)
#      and writes back the per-color marker bounding boxes.
#   3. Asserts the markers land in the expected Godot-space axes:
#        red+  -> +X   (right in Godot)
#        red-  -> -X
#        grn+  -> +Y   (up in Godot)
#        grn-  -> -Y
#        blu+  -> +Z   (forward in Godot)
#        blu-  -> -Z
#
# The JSON input is authored in Godot-space (X right, Y up, Z forward).
# If the bake pipeline's coordinate swap is correct, the resulting
# GLB — read back in Blender's glTF-Y-up space — will show the markers
# in the same (X right, Y up, Z forward) layout, because the swap
# + export_yup=True in bake_custom_hull.py is exactly what re-expresses
# Godot-space in glTF-Y-up.
#
# Pass criterion:
#   Each color class' vertices land entirely in the expected Godot-axis
#   half-space (e.g. all red+ verts have x>0, all red- verts have x<0,
#   no verts cross the wrong axis).
#
# Output: scratch/probe_axes/axis_probe_report.md

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$root        = 'E:\Kitbash-Command'
$probeDir    = Join-Path $root 'scratch\probe_axes'
$blender     = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
$bakeScript  = Join-Path $root 'prototype\tools\blender\bake_custom_hull.py'
$inputJson   = Join-Path $probeDir 'axis_probe_input.json'
$outputGlb   = Join-Path $probeDir 'axis_probe.glb'
$outputJson  = Join-Path $probeDir 'axis_probe.json'
$reportMd    = Join-Path $probeDir 'axis_probe_report.md'
$reimportPy  = Join-Path $probeDir 'reimport_and_report.py'

if (-not (Test-Path $blender)) { throw "Blender not found: $blender" }
if (-not (Test-Path $bakeScript)) { throw "Bake script not found: $bakeScript" }
if (-not (Test-Path $inputJson)) { throw "Input JSON not found: $inputJson" }

# Stage 1: bake ----------------------------------------------------------
Write-Host '[1/2] Baking axis probe via bake_custom_hull.py ...' -ForegroundColor Cyan
& $blender --background --python $bakeScript -- $inputJson $outputGlb $outputJson Ground
if ($LASTEXITCODE -ne 0) { throw "Blender bake exited $LASTEXITCODE" }
if (-not (Test-Path $outputGlb)) { throw "Bake did not produce $outputGlb" }

# Stage 2: re-import and report -----------------------------------------
Write-Host '[2/2] Re-importing GLB and reporting per-marker bounds ...' -ForegroundColor Cyan
& $blender --background --python $reimportPy -- $outputGlb $reportMd
if ($LASTEXITCODE -ne 0) { throw "Re-import exited $LASTEXITCODE" }

Write-Host ''
Write-Host 'Report:' -ForegroundColor Green
Write-Host "  $reportMd" -ForegroundColor Green
if (Test-Path $reportMd) {
    Get-Content $reportMd | ForEach-Object { Write-Host "  $_" }
}
