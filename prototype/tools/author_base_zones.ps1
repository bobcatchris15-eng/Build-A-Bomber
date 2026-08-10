# One-shot authoring script: adds `base_zones` to every bundled map's JSON
# so the new pre-game HQ-placement phase has somewhere to constrain the
# player to. The data is derived from each map's existing `spawns[].hq`
# positions (the maps were already authored around the assumption that
# HQ pads sit on flat ground) plus a map-scale-appropriate size.
#
# Idempotent: skips maps that already have a `base_zones` field. Run
# this again after the schema changes and the new field stays.
#
# Run from prototype/:
#   powershell -ExecutionPolicy Bypass -File tools/author_base_zones.ps1
$ErrorActionPreference = "Stop"
$mapsDir = Join-Path $PSScriptRoot "..\data\maps"
Get-ChildItem -Path $mapsDir -Filter "*.json" | Where-Object { $_.BaseName -notlike "*surface*" -and $_.BaseName -notlike "*height*" } | ForEach-Object {
    $path = $_.FullName
    $name = $_.BaseName
    $raw = Get-Content $path -Raw
    $json = $raw | ConvertFrom-Json

    if ($json.PSObject.Properties.Name -contains "base_zones") {
        Write-Output "[skip] $name already has base_zones"
        return
    }

    $half = [double]$json.map_half_extents
    if ($half -le 150) { $zoneHalf = 12.5 }
    elseif ($half -le 220) { $zoneHalf = 15.0 }
    elseif ($half -le 250) { $zoneHalf = 17.5 }
    elseif ($half -le 320) { $zoneHalf = 20.0 }
    else { $zoneHalf = 25.0 }

    # Find the HQ positions and assign zone ids by the order they appear
    # (player/enemy convention - first spawn is "player", so the first
    # HQ in the file is the "north" base; the second is "south"). The id
    # naming matches what assign_base_zones()'s test fixture uses, so
    # anyone reading the file in isolation can map names to cardinal
    # directions at a glance.
    $hqs = $json.spawns | ForEach-Object { $_.hq }
    $zones = @()
    $i = 0
    foreach ($hq in $hqs) {
        $id = if ($i -eq 0) { "north" } else { "south" }
        $zones += [PSCustomObject]@{
            id = $id
            center = @([double]$hq[0], 0, [double]$hq[2])
            half_extents = @($zoneHalf, $zoneHalf)
        }
        $i++
    }

    # Insert base_zones as a top-level field. We do this with a regex
    # pass rather than re-serialising the whole JSON, because the
    # existing files use 2-space indentation and a strict key order
    # that the round-trip would silently change.
    $zonesJson = ($zones | ConvertTo-Json -Depth 5 -Compress) -replace '^', '  ' -replace '(?m)^', '  ' | Out-String
    $zonesBlock = "  `"base_zones`": $($zones | ConvertTo-Json -Depth 5 -Compress),"
    $newRaw = $raw -replace '("spawns":\s*\[)', ($zonesBlock + "`n$1")
    Set-Content -Path $path -Value $newRaw -NoNewline
    Write-Output "[done] $name -> $zoneHalf x $zoneHalf zones at $($hqs[0][2]) and $(-($hqs[1][2]))"
}
Write-Output "All maps processed."
