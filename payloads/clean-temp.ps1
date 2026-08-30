$targets = @(
    $env:TEMP,
    (Join-Path $env:SystemRoot 'Temp'),
    (Join-Path $env:SystemRoot 'SoftwareDistribution\Download'),
    (Join-Path $env:SystemRoot 'Prefetch')
)
$freed = 0
foreach ($dir in $targets) {
    if (-not (Test-Path $dir)) { continue }
    $before = (Get-ChildItem $dir -Recurse -Force -ErrorAction SilentlyContinue |
               Measure-Object -Property Length -Sum).Sum
    Get-ChildItem $dir -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $after = (Get-ChildItem $dir -Recurse -Force -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    $freed += [Math]::Max(0, ($before - $after))
    Write-Log "  cleaned $dir" 'dim'
}
Write-Log ('  freed {0:N0} MB' -f ($freed / 1MB)) 'ok'
