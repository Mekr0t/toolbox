# Unhide and activate the Ultimate Performance power scheme.
$guid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
Invoke-Cli -FilePath 'powercfg.exe' -Arguments "-duplicatescheme $guid" | Out-Null
$scheme = (powercfg -list | Select-String 'Ultimate Performance' | Select-Object -First 1)
if ($scheme -match '([0-9a-fA-F-]{36})') {
    Invoke-Cli -FilePath 'powercfg.exe' -Arguments "-setactive $($Matches[1])" | Out-Null
    Write-Log '  Ultimate Performance plan active' 'dim'
} else {
    Write-Log '  could not find the Ultimate Performance plan' 'warn'
}
