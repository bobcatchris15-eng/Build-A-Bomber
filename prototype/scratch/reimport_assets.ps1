$REAL = "E:\Build-A-Bomber\prototype"
$DST = "$REAL\scratch\.reimport_root\reimport_copy"

Write-Host "=== Syncing assets/ into isolated copy ==="
# robocopy returns exit codes that aren't 0 even on success, so we ignore errors/exit codes
robocopy "$REAL\assets" "$DST\assets" /E /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null

# First run: copy the rest of the project if project.godot isn't present
if (-not (Test-Path "$DST\project.godot")) {
    Write-Host "=== First run: copying full project ==="
    robocopy "$REAL" "$DST" /E /XD "$REAL\UPBGE-0.30-windows-x86_64" "$REAL\progress_captures" "$REAL\.godot" "$REAL\.git" "$REAL\scratch" /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
}

Write-Host "=== Running isolated reimport ==="
# Run Godot headless editor to force import
$process = Start-Process -FilePath "$REAL\Godot_v4.3-stable_win64_console.exe" -ArgumentList "--path", """$DST""", "--headless", "--editor", "--import" -NoNewWindow -PassThru -Wait
if ($process.ExitCode -ne 0) {
    Write-Warning "Godot editor import exited with non-zero code: $($process.ExitCode)"
}

Write-Host "=== Copying import artifacts back ==="
if (-not (Test-Path "$REAL\.godot\imported")) {
    New-Item -ItemType Directory -Path "$REAL\.godot\imported" -Force | Out-Null
}
Copy-Item -Path "$DST\.godot\imported\*" -Destination "$REAL\.godot\imported\" -Recurse -Force
Copy-Item -Path "$DST\.godot\uid_cache.bin" -Destination "$REAL\.godot\uid_cache.bin" -Force

Write-Host "=== Copying .import sidecar files back ==="
Get-ChildItem -Path "$DST" -Filter "*.import" -Recurse | ForEach-Object {
    $relativePath = $_.FullName.Substring($DST.Length + 1)
    $destinationPath = Join-Path $REAL $relativePath
    $parentDir = Split-Path $destinationPath
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    Copy-Item -Path $_.FullName -Destination $destinationPath -Force
}

Write-Host "=== Reimport complete ==="
