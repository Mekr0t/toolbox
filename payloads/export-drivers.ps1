# Dumps every third-party driver on this machine to a folder you can keep.
# Run it BEFORE a reinstall and you never hunt for that one NIC driver again.
$dest = Join-Path $env:USERPROFILE ('Drivers-{0}-{1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd'))
New-Item -ItemType Directory -Path $dest -Force | Out-Null

Write-Log "  exporting to $dest" 'dim'
$r = Invoke-Cli -FilePath 'pnputil.exe' -Arguments "/export-driver * `"$dest`""

$count = @(Get-ChildItem $dest -Directory -ErrorAction SilentlyContinue).Count
if ($count -gt 0) {
    $size = (Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Log ('  {0} driver packages, {1:N0} MB' -f $count, ($size / 1MB)) 'ok'
    Write-Log '  copy this folder somewhere off the machine before you wipe it' 'warn'
} else {
    Write-Log '  nothing exported - pnputil may need a different Windows edition' 'err'
}
