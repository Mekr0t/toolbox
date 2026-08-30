# =============================================================================
#  Toolbox :: catalog actions (apps / tweaks / scripts)
# =============================================================================

function Invoke-InstallStep {
    param([hashtable] $Step)
    $type  = ('' + (Get-ItemProp $Step 'type' 'winget')).ToLower()
    $id    = Get-ItemProp $Step 'id'   ''
    $args  = Get-ItemProp $Step 'args' ''
    switch ($type) {
        'winget'   { return Install-ViaWinget   -Id $id -ExtraArgs $args }
        'choco'    { return Install-ViaChoco    -Id $id -ExtraArgs $args }
        'scoop'    { return Install-ViaScoop    -Id $id -ExtraArgs $args }
        'download' { return Install-ViaDownload -Url (Get-ItemProp $Step 'url' '') -ExtraArgs $args -FileName (Get-ItemProp $Step 'file' $null) }
        'script'   { return Invoke-Payload      -Path (Get-ItemProp $Step 'path' '') }
        'appx'     { Write-Log '  appx entries are removal-only - reinstall from the Microsoft Store' 'warn'; return $false }
        default    { Write-Log "unknown install type '$type'" 'err'; return $false }
    }
}

function Invoke-UninstallStep {
    param([hashtable] $Step)
    $type = ('' + (Get-ItemProp $Step 'type' 'winget')).ToLower()
    $id   = Get-ItemProp $Step 'id'   ''
    $args = Get-ItemProp $Step 'args' ''
    switch ($type) {
        'winget' { return Uninstall-ViaWinget -Id $id -ExtraArgs $args }
        'choco'  { return Uninstall-ViaChoco  -Id $id -ExtraArgs $args }
        'scoop'  { return Uninstall-ViaScoop  -Id $id -ExtraArgs $args }
        'appx'   { return Uninstall-ViaAppx   -Id $id -ExtraArgs $args }
        'script' { return Invoke-Payload      -Path (Get-ItemProp $Step 'path' '') }
        default  { Write-Log "cannot uninstall via '$type'" 'warn'; return $false }
    }
}

function Invoke-Payload {
    # Runs a .ps1 hosted next to the catalog on your server.
    param([Parameter(Mandatory)][string] $Path)
    Write-Log "  running payload $Path" 'dim'
    $code = Get-RemoteText $Path
    $sb   = [scriptblock]::Create($code)
    & $sb
    $true
}

function Install-CatalogApp {
    param([hashtable] $App)
    $name  = Get-ItemProp $App 'name' (Get-ItemProp $App 'id' '?')
    $steps = @(Get-ItemProp $App 'install' @())
    if (-not $steps) { Write-Log "$name has no install steps" 'err'; return $false }
    Write-Log "Installing $name" 'step'
    foreach ($step in $steps) {
        $type = Get-ItemProp $step 'type' 'winget'
        try {
            if (Invoke-InstallStep $step) { Write-Log "$name installed (via $type)" 'ok'; return $true }
            Write-Log "$name : $type failed, trying next source" 'warn'
        } catch {
            Write-Log "$name : $type errored - $($_.Exception.Message)" 'warn'
        }
    }
    Write-Log "$name FAILED - every source exhausted" 'err'
    $false
}

function Uninstall-CatalogApp {
    param([hashtable] $App)
    $name  = Get-ItemProp $App 'name' (Get-ItemProp $App 'id' '?')
    # Fall back to the install steps: winget/choco/scoop uninstall by the same id.
    $steps = @(Get-ItemProp $App 'uninstall' (Get-ItemProp $App 'install' @()))
    Write-Log "Removing $name" 'step'
    foreach ($step in $steps) {
        try {
            if (Invoke-UninstallStep $step) { Write-Log "$name removed" 'ok'; return $true }
        } catch {
            Write-Log "$name : $($_.Exception.Message)" 'warn'
        }
    }
    Write-Log "$name could not be removed automatically" 'err'
    $false
}
