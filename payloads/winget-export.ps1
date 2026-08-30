# Snapshots everything winget knows is installed, so you can diff it against
# the catalog later and see what is missing.
$winget = Get-WingetPath
if (-not $winget) { Write-Log '  winget unavailable' 'err'; return }

$dest = Join-Path $env:USERPROFILE ('winget-{0}-{1}.json' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd'))
Invoke-Cli -FilePath $winget -Arguments "export -o `"$dest`" --accept-source-agreements --disable-interactivity" | Out-Null

if (Test-Path $dest) {
    $n = @((Get-Content $dest -Raw | ConvertFrom-Json).Sources.Packages).Count
    Write-Log "  $n packages written to $dest" 'ok'
} else {
    Write-Log '  export produced no file' 'err'
}
