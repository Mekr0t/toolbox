Invoke-Cli -FilePath 'powercfg.exe' -Arguments '/hibernate off' | Out-Null
Write-Log '  hibernation disabled (hiberfil.sys freed)' 'dim'
