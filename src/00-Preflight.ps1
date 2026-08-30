# =============================================================================
#  Toolbox :: preflight  (run mode, elevation, apartment state, globals)
# =============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Toolbox = @{
    Name       = 'Toolbox'
    Version    = '{{VERSION}}'
    BuildDate  = '{{BUILD_DATE}}'
    BaseUrl    = '{{BASE_URL}}'.TrimEnd('/')
    DataDir    = (Join-Path $env:ProgramData 'Toolbox')
    Manifest   = $null
}

# Local development override:  $env:TOOLBOX_BASE = 'http://localhost:8080'
if ($env:TOOLBOX_BASE) { $Toolbox.BaseUrl = $env:TOOLBOX_BASE.TrimEnd('/') }

$Toolbox.BackupDir = Join-Path $Toolbox.DataDir 'backups'
$Toolbox.LogFile   = Join-Path $Toolbox.DataDir ('toolbox-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))

# --- run mode ----------------------------------------------------------------
# iex cannot take parameters, so the one-liner is configured with environment
# variables instead:
#
#   $env:TOOLBOX_PRESET='dev'; irm https://host | iex     install a preset, no GUI
#   $env:TOOLBOX_APPS='vscode,git'; irm https://host | iex
#   $env:TOOLBOX_LIST='1'; irm https://host | iex         print every id and stop
#   $env:TOOLBOX_LIST='short'                             just the names, grouped
#   $env:TOOLBOX_DRYRUN='1'                               log actions, change nothing
#   $env:TOOLBOX_ACTION='uninstall'                       reverse instead of apply

$Toolbox.Preset   = $env:TOOLBOX_PRESET
$Toolbox.AppIds   = $env:TOOLBOX_APPS
$Toolbox.TweakIds = $env:TOOLBOX_TWEAKS
$Toolbox.ScriptIds= $env:TOOLBOX_SCRIPTS
$Toolbox.Action   = if ($env:TOOLBOX_ACTION) { $env:TOOLBOX_ACTION.ToLower() } else { 'install' }
$Toolbox.DryRun   = ($env:TOOLBOX_DRYRUN -eq '1')
$Toolbox.KeepOpen = ($env:TOOLBOX_KEEPOPEN -eq '1')

# '1' or 'full' = ids, categories and install state; 'short' = names only.
$Toolbox.ListStyle = if ($env:TOOLBOX_LIST) { $env:TOOLBOX_LIST.ToLower() } else { '' }

$Toolbox.Mode =
    if     ($Toolbox.ListStyle -and $Toolbox.ListStyle -ne '0') { 'list' }
    elseif ($Toolbox.Preset -or $Toolbox.AppIds -or $Toolbox.TweakIds -or $Toolbox.ScriptIds) { 'headless' }
    else   { 'gui' }

function Test-ToolboxAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-OneShotHost {
    # True when this host was started to run one command and quit
    # (powershell -Command / -File), false at an interactive prompt. Calling
    # exit in an interactive session would close the user's terminal.
    [Environment]::CommandLine -match '\s-(?:c|f|e|ec|Command|File|EncodedCommand)\b'
}

function Exit-Toolbox {
    param([int] $Code = 0)
    $global:LASTEXITCODE = $Code
    if (Test-OneShotHost) { exit $Code }
}

function Get-EnvCarryOver {
    # Start-Process -Verb RunAs goes through ShellExecute, and the elevated
    # child gets a FRESH environment block -- nothing set in the calling shell
    # survives. So every TOOLBOX_* variable is re-emitted into the command the
    # elevated process runs.
    $seen  = @{}
    $lines = @("`$env:TOOLBOX_BASE='$($Toolbox.BaseUrl)'")
    $seen['TOOLBOX_BASE'] = $true

    foreach ($item in Get-ChildItem Env: | Where-Object { $_.Name -like 'TOOLBOX_*' }) {
        if ($seen[$item.Name]) { continue }
        $value = ('' + $item.Value).Replace("'", "''")
        $lines += "`$env:$($item.Name)='$value'"
        $seen[$item.Name] = $true
    }
    # A relaunched headless run owns its console window, so hold it open at the
    # end -- otherwise the window closes and takes the output with it.
    if ($Toolbox.Mode -ne 'gui' -and -not $seen['TOOLBOX_KEEPOPEN']) {
        $lines += "`$env:TOOLBOX_KEEPOPEN='1'"
    }
    $lines -join '; '
}

function Restart-ToolboxElevated {
    # Re-launch the same entry point in an elevated PowerShell 5.1 host.
    $prefix = Get-EnvCarryOver
    if ($PSCommandPath) {
        $inner = "$prefix; & '$PSCommandPath'"
    } else {
        $inner = "$prefix; irm '$($Toolbox.BaseUrl)' | iex"
    }
    $exe  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $sta  = if ($Toolbox.Mode -eq 'gui') { ' -STA' } else { '' }
    $argl = "-NoProfile -ExecutionPolicy Bypass$sta -NoLogo -Command `"$($inner.Replace('"', '\"'))`""

    try {
        if ($Toolbox.Mode -eq 'gui') {
            Start-Process -FilePath $exe -ArgumentList $argl -Verb RunAs | Out-Null
            return 0
        }
        # Headless: wait, so the caller gets a real exit code back.
        $proc = Start-Process -FilePath $exe -ArgumentList $argl -Verb RunAs -PassThru -Wait
        return $proc.ExitCode
    } catch {
        Write-Host 'Elevation was cancelled. Toolbox needs Administrator to install software.' -ForegroundColor Yellow
        return 1
    }
}

if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    Write-Host 'Toolbox only runs on Windows.' -ForegroundColor Red
    return
}

# Listing the catalog changes nothing, and a dry run does not either, so
# neither needs Administrator. Only the GUI needs an STA thread.
$needsElevation = ($Toolbox.Mode -ne 'list') -and (-not $Toolbox.DryRun) -and (-not (Test-ToolboxAdmin))
$needsSta       = ($Toolbox.Mode -eq 'gui') -and
                  ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA')

if ($needsElevation -or $needsSta) {
    $why = @()
    if ($needsElevation) { $why += 'Administrator' }
    if ($needsSta)       { $why += 'STA thread (WPF)' }
    Write-Host ("Relaunching Toolbox: needs {0}..." -f ($why -join ' + ')) -ForegroundColor Cyan
    $code = Restart-ToolboxElevated
    Exit-Toolbox $code
    return
}

New-Item -ItemType Directory -Path $Toolbox.DataDir   -Force | Out-Null
New-Item -ItemType Directory -Path $Toolbox.BackupDir -Force | Out-Null
