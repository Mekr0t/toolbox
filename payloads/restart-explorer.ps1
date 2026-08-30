# Restarts Explorer so shell settings take effect immediately.
Write-Log '  restarting explorer.exe' 'dim'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 800
if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
