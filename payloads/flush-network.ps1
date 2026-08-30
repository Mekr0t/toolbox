foreach ($step in @(
    @{ File = 'ipconfig.exe'; Args = '/flushdns' },
    @{ File = 'ipconfig.exe'; Args = '/registerdns' },
    @{ File = 'netsh.exe';    Args = 'winsock reset' },
    @{ File = 'netsh.exe';    Args = 'int ip reset' }
)) {
    Write-Log "  $($step.File) $($step.Args)" 'dim'
    Invoke-Cli -FilePath $step.File -Arguments $step.Args -Quiet | Out-Null
}
Write-Log '  network stack reset - reboot to finish' 'warn'
