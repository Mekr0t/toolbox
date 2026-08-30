# =============================================================================
#  Toolbox :: package-manager providers
# =============================================================================
# Each provider exposes Install/Uninstall plus a bootstrap that installs the
# manager itself on first use. To add a provider: write the two functions and
# register the type name in Invoke-InstallStep (50-Actions.ps1).

# --- winget ------------------------------------------------------------------

# winget returns HRESULT-style codes; these all mean "nothing to do, that's ok".
$WingetOk = @(0, -1978335189, -1978335153, -1978335212, -1978334967, -1978335135)

function Get-WingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # Elevated sessions sometimes lose the WindowsApps alias from PATH.
    $hit = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter winget.exe -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    $null
}

function Initialize-Winget {
    if (Get-WingetPath) { return $true }
    Write-Log 'winget not found - installing App Installer...' 'warn'
    try {
        $tmp = Join-Path $env:TEMP 'toolbox-winget'
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $urls = @(
            'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx',
            'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        )
        foreach ($u in $urls) {
            $dest = Join-Path $tmp ([IO.Path]::GetFileName(([Uri]$u).LocalPath))
            Invoke-WebRequest -Uri $u -OutFile $dest -UseBasicParsing
            Add-AppxPackage -Path $dest -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
        if (Get-WingetPath) { Write-Log 'winget installed.' 'ok'; return $true }
    } catch {
        Write-Log "winget bootstrap failed: $($_.Exception.Message)" 'err'
    }
    $false
}

function Install-ViaWinget {
    param([string] $Id, [string] $ExtraArgs = '')
    if (-not (Initialize-Winget)) { return $false }
    $argl = "install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity $ExtraArgs"
    $r = Invoke-Cli -FilePath (Get-WingetPath) -Arguments $argl -SuccessCodes $WingetOk
    if (-not $r.Success -and $r.Output -match 'already installed|No newer package') { return $true }
    $r.Success
}

function Uninstall-ViaWinget {
    param([string] $Id, [string] $ExtraArgs = '')
    $winget = Get-WingetPath
    if (-not $winget) { return $false }
    $argl = "uninstall --id $Id --exact --silent --accept-source-agreements --disable-interactivity $ExtraArgs"
    (Invoke-Cli -FilePath $winget -Arguments $argl -SuccessCodes $WingetOk).Success
}

# --- chocolatey --------------------------------------------------------------

function Initialize-Choco {
    if (Test-Cmd 'choco') { return $true }
    Write-Log 'Chocolatey not found - installing...' 'warn'
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path', 'User')
        if (Test-Cmd 'choco') { Write-Log 'Chocolatey installed.' 'ok'; return $true }
    } catch {
        Write-Log "Chocolatey bootstrap failed: $($_.Exception.Message)" 'err'
    }
    $false
}

function Install-ViaChoco {
    param([string] $Id, [string] $ExtraArgs = '')
    if (-not (Initialize-Choco)) { return $false }
    (Invoke-Cli -FilePath 'choco' -Arguments "install $Id -y --no-progress --limit-output $ExtraArgs" -SuccessCodes @(0, 1641, 3010)).Success
}

function Uninstall-ViaChoco {
    param([string] $Id, [string] $ExtraArgs = '')
    if (-not (Test-Cmd 'choco')) { return $false }
    (Invoke-Cli -FilePath 'choco' -Arguments "uninstall $Id -y --no-progress --limit-output $ExtraArgs" -SuccessCodes @(0, 1641, 3010)).Success
}

# --- scoop -------------------------------------------------------------------
# Scoop is a per-user manager and refuses to run elevated unless told to.

function Get-ScoopShim {
    $shim = Join-Path $env:USERPROFILE 'scoop\shims\scoop.cmd'
    if (Test-Path $shim) { return $shim }
    if (Test-Cmd 'scoop') { return (Get-Command scoop).Source }
    $null
}

function Initialize-Scoop {
    if (Get-ScoopShim) { return $true }
    Write-Log 'Scoop not found - installing (admin mode)...' 'warn'
    try {
        $installer = Invoke-RestMethod 'https://get.scoop.sh'
        Invoke-Expression "& { $installer } -RunAsAdmin"
        if (Get-ScoopShim) { Write-Log 'Scoop installed.' 'ok'; return $true }
    } catch {
        Write-Log "Scoop bootstrap failed: $($_.Exception.Message)" 'err'
    }
    $false
}

function Install-ViaScoop {
    param([string] $Id, [string] $ExtraArgs = '')
    if (-not (Initialize-Scoop)) { return $false }
    (Invoke-Cli -FilePath (Get-ScoopShim) -Arguments "install $Id $ExtraArgs").Success
}

function Uninstall-ViaScoop {
    param([string] $Id, [string] $ExtraArgs = '')
    $shim = Get-ScoopShim
    if (-not $shim) { return $false }
    (Invoke-Cli -FilePath $shim -Arguments "uninstall $Id $ExtraArgs").Success
}

# --- direct download (msi / exe / msix / appx) -------------------------------

function Install-ViaDownload {
    param([string] $Url, [string] $ExtraArgs = '', [string] $FileName)
    if (-not $FileName) { $FileName = [IO.Path]::GetFileName(([Uri]$Url).LocalPath) }
    if (-not $FileName) { $FileName = 'toolbox-download.exe' }
    $dest = Join-Path $env:TEMP $FileName
    Write-Log "  downloading $Url" 'dim'
    Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
    switch ([IO.Path]::GetExtension($dest).ToLower()) {
        '.msi'  { return (Invoke-Cli -FilePath 'msiexec.exe' -Arguments "/i `"$dest`" /qn /norestart $ExtraArgs" -SuccessCodes @(0, 1641, 3010)).Success }
        '.msix' { Add-AppxPackage -Path $dest; return $true }
        '.appx' { Add-AppxPackage -Path $dest; return $true }
        '.zip'  {
            $target = if ($ExtraArgs) { $ExtraArgs } else { Join-Path $env:LOCALAPPDATA ('Toolbox\' + [IO.Path]::GetFileNameWithoutExtension($dest)) }
            Expand-Archive -LiteralPath $dest -DestinationPath $target -Force
            Write-Log "  extracted to $target" 'dim'
            return $true
        }
        default {
            # NSIS/Inno silent switch is the most common default for bare .exe installers.
            if (-not $ExtraArgs) { $ExtraArgs = '/S' }
            return (Invoke-Cli -FilePath $dest -Arguments $ExtraArgs -SuccessCodes @(0, 1641, 3010)).Success
        }
    }
}

# --- appx / msix -------------------------------------------------------------
# Removal only. Preinstalled Store apps never appear in Add/Remove Programs, so
# this is the only way to shift them; reinstalling means the Store.

function Uninstall-ViaAppx {
    param([string] $Id, [string] $ExtraArgs = '')
    $removed = 0

    foreach ($pkg in @(Get-AppxPackage -Name $Id -AllUsers -ErrorAction SilentlyContinue)) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log "  removed $($pkg.Name)" 'dim'
            $removed++
        } catch {
            Write-Log "  could not remove $($pkg.Name): $($_.Exception.Message)" 'warn'
        }
    }

    # Drop the provisioned copy too, or the next new user profile gets it back.
    foreach ($prov in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -like $Id })) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
            Write-Log "  deprovisioned $($prov.DisplayName)" 'dim'
            $removed++
        } catch { }
    }

    if ($removed -eq 0) { Write-Log '  nothing matched - already gone' 'dim' }
    $true
}
