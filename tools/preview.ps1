<#
    Opens the real window against your local dist\ catalog, without elevating
    and without deploying anything. Use it to eyeball layout while editing.

        powershell -NoProfile -STA -File .\tools\preview.ps1
        powershell -NoProfile -STA -File .\tools\preview.ps1 -AutoCloseSeconds 3

    Buttons are live, so do not click Install unless you mean it (and without
    elevation most installs will fail anyway).
#>
param([int] $AutoCloseSeconds = 0)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dist = Join-Path $root 'dist'

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host 'Re-run with -STA.' -ForegroundColor Red; exit 1
}
if (-not (Test-Path (Join-Path $dist 'manifest.json'))) {
    Write-Host 'No dist\manifest.json - run .\build.ps1 first.' -ForegroundColor Red; exit 1
}

$Toolbox = @{
    Name = 'Toolbox'; Version = 'preview'; BuildDate = (Get-Date -Format 'yyyy-MM-dd')
    BaseUrl = $dist
    DataDir = (Join-Path $env:TEMP 'toolbox-preview')
    BackupDir = (Join-Path $env:TEMP 'toolbox-preview\backups')
    LogFile = (Join-Path $env:TEMP 'toolbox-preview\preview.log')
    Manifest = $null
}
New-Item -ItemType Directory -Path $Toolbox.BackupDir -Force | Out-Null

foreach ($module in Get-ChildItem (Join-Path $root 'src') -Filter *.ps1 | Sort-Object Name) {
    if ($module.Name -in '00-Preflight.ps1', '99-Main.ps1') { continue }
    . $module.FullName
}

function Get-RemoteText {
    param([string] $Path)
    Get-Content (Join-Path $Toolbox.BaseUrl ($Path -replace '/', '\')) -Raw
}

if ($AutoCloseSeconds -gt 0) {
    # Runs on this dispatcher, so it ticks inside Show-Toolbox's modal loop.
    $closer = New-Object Windows.Threading.DispatcherTimer
    $closer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:elapsed = 0
    $closer.Add_Tick({
        $script:elapsed += 0.5
        if ($Ui.Window -and $script:elapsed -ge $AutoCloseSeconds) {
            Write-Host "Window rendered for ${AutoCloseSeconds}s with no errors - closing." -ForegroundColor Green
            $Ui.Window.Close()
        }
    })
    $closer.Start()
}

Show-Toolbox
Write-Host 'Preview closed.' -ForegroundColor DarkGray
