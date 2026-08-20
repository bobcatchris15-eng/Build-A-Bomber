$tmp_out = "$env:TEMP\test_out.txt"
$tmp_err = "$env:TEMP\test_err.txt"
$proc = Start-Process -FilePath "E:\Kitbash-Command\prototype\Godot_v4.7.1-stable_win64_console.exe" -ArgumentList "--headless","--quit","--script run_tests.gd" -WorkingDirectory "E:\Kitbash-Command\prototype" -NoNewWindow -RedirectStandardOutput $tmp_out -RedirectStandardError $tmp_err -PassThru
$null = $proc.WaitForExit()
Write-Host "Exit code: $($proc.ExitCode)"
Write-Host "OUT size: $((Get-Item $tmp_out).Length)"
Write-Host "ERR size: $((Get-Item $tmp_err).Length)"
if ((Get-Item $tmp_err).Length -gt 0) {
    Write-Host "=== STDERR ==="
    Get-Content $tmp_err | Select-Object -First 20
}
Write-Host "=== LAST 20 OUT ==="
Get-Content $tmp_out | Select-Object -Last 20
