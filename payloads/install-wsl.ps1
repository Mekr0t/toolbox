# Installs WSL and Ubuntu. Needs a reboot to finish.
if (-not (Test-Cmd 'wsl')) {
    Write-Log '  wsl.exe not present on this edition of Windows' 'err'
    return
}
$existing = (wsl --list --quiet 2>$null) -join ' '
if ($existing -match '\w') {
    Write-Log "  a distro is already installed: $($existing.Trim())" 'warn'
    return
}
Write-Log '  installing WSL + Ubuntu (this pulls a few hundred MB)' 'dim'
Invoke-Cli -FilePath 'wsl.exe' -Arguments '--install -d Ubuntu --no-launch' | Out-Null
Write-Log '  reboot, then run "wsl" to set your username and password' 'warn'
