Write-Log '  running DISM /RestoreHealth (this takes a few minutes)' 'dim'
Invoke-Cli -FilePath 'dism.exe' -Arguments '/Online /Cleanup-Image /RestoreHealth' | Out-Null
Write-Log '  running SFC /scannow' 'dim'
Invoke-Cli -FilePath 'sfc.exe' -Arguments '/scannow' | Out-Null
