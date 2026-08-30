<#
    Prints what the toolbox offers, straight from your local dist\ - no server,
    no elevation, no network.

        .\tools\catalog.ps1          names only, grouped
        .\tools\catalog.ps1 -Full    ids, categories and install state
#>
param([switch] $Full)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dist = Join-Path $root 'dist'
if (-not (Test-Path (Join-Path $dist 'toolbox.ps1'))) {
    Write-Host 'Nothing built yet - run .\build.ps1 first.' -ForegroundColor Yellow
    exit 1
}

$env:TOOLBOX_BASE = $dist
$env:TOOLBOX_LIST = if ($Full) { '1' } else { 'short' }
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dist 'toolbox.ps1')
} finally {
    Remove-Item Env:TOOLBOX_BASE, Env:TOOLBOX_LIST -ErrorAction SilentlyContinue
}
