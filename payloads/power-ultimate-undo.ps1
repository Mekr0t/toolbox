# Back to Balanced.
Invoke-Cli -FilePath 'powercfg.exe' -Arguments '-setactive 381b4222-f694-41f0-9685-ff5bb260df2e' | Out-Null
Write-Log '  Balanced power plan active' 'dim'
