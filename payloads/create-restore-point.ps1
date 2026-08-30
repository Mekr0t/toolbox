try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    # Windows rate-limits restore points to one per 24h unless this is relaxed.
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
                     -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value 0 -Force | Out-Null
    Checkpoint-Computer -Description ('Toolbox {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) `
                        -RestorePointType 'MODIFY_SETTINGS'
    Write-Log '  restore point created' 'ok'
} catch {
    Write-Log "  restore point failed: $($_.Exception.Message)" 'err'
}
