# Win11: restore the full right-click menu by blanking the new shell extension.
$key = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name '(Default)' -Value '' -Force
Write-Log '  classic context menu enabled' 'dim'
Invoke-Payload -Path 'payloads/restart-explorer.ps1' | Out-Null
