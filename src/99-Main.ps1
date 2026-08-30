# =============================================================================
#  Toolbox :: entry point
# =============================================================================
$exitCode = 0

try {
    switch ($Toolbox.Mode) {
        'list'     { $exitCode = Show-ToolboxCatalog }
        'headless' { $exitCode = Invoke-ToolboxHeadless }
        default    { Show-Toolbox }
    }
} catch {
    Write-Host ''
    Write-Host "Toolbox failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Check that the catalog URL is reachable:' -ForegroundColor Yellow
    Write-Host "  $($Toolbox.BaseUrl)/manifest.json" -ForegroundColor Yellow
    $exitCode = 1
    $Toolbox.KeepOpen = $true
}

# A relaunched run owns its console window; without this it closes on exit and
# takes the output with it.
if ($Toolbox.KeepOpen) {
    Write-Host ''
    [void](Read-Host 'Press Enter to close')
}

Exit-Toolbox $exitCode
