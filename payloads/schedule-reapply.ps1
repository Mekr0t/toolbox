# ---------------------------------------------------------------------------
#  Registers a scheduled task that re-applies a preset every four weeks.
#
#  Windows updates quietly re-enable telemetry and reset shell settings. This
#  re-asserts your config without you remembering to. Only possible because the
#  toolbox has a headless mode.
# ---------------------------------------------------------------------------

# ---- EDIT ME --------------------------------------------------------------
$Preset   = 'fresh-install'
$TaskName = 'Toolbox re-apply'
$RunAt    = '15:00'
# ---------------------------------------------------------------------------

$command = "`$env:TOOLBOX_PRESET='$Preset'; irm '$($Toolbox.BaseUrl)' | iex"
$argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "{0}"' -f $command

try {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument

    $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Sunday -At $RunAt

    # Runs as YOU, elevated. Not SYSTEM: half the tweaks live in HKCU, and SYSTEM
    # would faithfully apply them to the wrong profile.
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                                            -LogonType Interactive -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
                                             -DontStopOnIdleEnd `
                                             -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
                           -Principal $principal -Settings $settings -Force | Out-Null

    Write-Log "  '$TaskName' will re-apply the '$Preset' preset every 4 weeks at $RunAt" 'ok'
    Write-Log '  it runs hidden - check the log if you want to see what it did' 'dim'
    Write-Log "  remove it with: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" 'dim'
} catch {
    Write-Log "  could not register the task: $($_.Exception.Message)" 'err'
}
