<#
    Builds and pushes dist\ to the Linux server over SSH.

        .\deploy.ps1                 # host/path from toolbox.config.json
        .\deploy.ps1 -Host me@box -RemotePath /srv/toolbox
#>
param(
    [string] $HostName,
    [string] $RemotePath,
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $root 'toolbox.config.json'
if (-not (Test-Path $configPath)) {
    Write-Host 'No toolbox.config.json yet - copy toolbox.config.example.json first.' -ForegroundColor Yellow
    exit 1
}
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $HostName)   { $HostName   = $config.deploy.host }
if (-not $RemotePath) { $RemotePath = $config.deploy.path }

if ($HostName -match 'your-server' -or $RemotePath -like '*your-server*') {
    Write-Host "deploy.host is still the placeholder - set it in toolbox.config.json." -ForegroundColor Yellow
    exit 1
}

if (-not $SkipBuild) { & (Join-Path $root 'build.ps1') }

Write-Host "Uploading to ${HostName}:${RemotePath}" -ForegroundColor Cyan
ssh $HostName "mkdir -p '$RemotePath'"
scp -r (Join-Path $root 'dist\*') "${HostName}:${RemotePath}/"
if ($LASTEXITCODE -ne 0) { throw "scp failed with exit code $LASTEXITCODE" }

Write-Host 'Deployed.' -ForegroundColor Green
Write-Host "  irm $($config.baseUrl) | iex" -ForegroundColor Cyan
