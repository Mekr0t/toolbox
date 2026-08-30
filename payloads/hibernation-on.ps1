Invoke-Cli -FilePath 'powercfg.exe' -Arguments '/hibernate on' | Out-Null
Write-Log '  hibernation re-enabled' 'dim'
