<#
    Idempotent JSON escape fixer for catalog\**\*.json.

    Registry and scheduled-task paths need doubled backslashes in JSON. It is
    easy to save a file with single ones by hand (or via an editor that helpfully
    "cleans" them), which makes ConvertFrom-Json fail with "Unrecognized escape
    sequence". This collapses every backslash run to one, then doubles it, so
    running it twice changes nothing.

        .\tools\normalize-catalog.ps1
#>
param([string] $Path = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'catalog'))

$ErrorActionPreference = 'Stop'
$bs      = [string][char]92
$changed = 0

foreach ($file in Get-ChildItem $Path -Recurse -Filter *.json) {
    $text = Get-Content $file.FullName -Raw
    $fixed = $text
    while ($fixed.Contains($bs + $bs)) { $fixed = $fixed.Replace($bs + $bs, $bs) }
    $fixed = $fixed.Replace($bs, $bs + $bs)

    if ($fixed -ne $text) {
        # No BOM: Get-Content tolerates one, but jq in build.sh does not.
        [IO.File]::WriteAllText($file.FullName, $fixed, (New-Object Text.UTF8Encoding($false)))
        Write-Host "  fixed  $($file.Name)" -ForegroundColor Yellow
        $changed++
    }
    try {
        [void](ConvertFrom-Json $fixed)
    } catch {
        Write-Host "  BROKEN $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host "$changed file(s) normalized." -ForegroundColor Green
