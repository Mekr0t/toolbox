$winget = Get-WingetPath
if (-not $winget) { Write-Log '  winget unavailable' 'err'; return }
Invoke-Cli -FilePath $winget `
           -Arguments 'upgrade --all --silent --accept-source-agreements --accept-package-agreements --disable-interactivity' `
           -SuccessCodes $WingetOk | Out-Null
