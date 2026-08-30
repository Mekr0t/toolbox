# =============================================================================
#  Toolbox :: tweaks (registry / services / scheduled tasks / scripts)
# =============================================================================
# Every tweak that touches the registry or a service writes the previous state
# to %ProgramData%\Toolbox\backups\<id>.json first, so "Undo" works even for
# tweaks that never declared an explicit undo value.

function Get-TweakBackupPath {
    param([string] $Id)
    Join-Path $Toolbox.BackupDir ("$Id.json")
}

function Save-TweakBackup {
    param([string] $Id, [object[]] $Entries)
    if (-not $Entries) { return }
    $file = Get-TweakBackupPath $Id
    if (Test-Path $file) { return }   # keep the ORIGINAL state, not the last one
    $Entries | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding UTF8
}

function Get-TweakBackup {
    <#  Reads the recorded pre-tweak state.
        NB: do NOT wrap this in @(). ConvertTo-Hashtable returns an array that
        is itself array-wrapped, so @() leaves the whole list sitting in element
        zero -- every entry then reads as a non-hashtable and Get-ItemProp hands
        back defaults, which is an empty registry path. Single-entry backups
        survive that by accident, which is how it reached a real machine. #>
    param([string] $Id)
    $file = Get-TweakBackupPath $Id
    if (-not (Test-Path $file)) { return @() }
    ConvertTo-Hashtable ((Get-Content -LiteralPath $file -Raw) | ConvertFrom-Json)
}

function Set-RegValue {
    param([string] $Path, [string] $Name, [string] $Type = 'DWord', $Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
}

function Get-RegSnapshot {
    param([string] $Path, [string] $Name)
    $snap = @{ kind = 'registry'; path = $Path; name = $Name; existed = $false; value = $null; type = 'DWord' }
    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        $snap.existed = $true
        $snap.value   = $item.$Name
        $key = Get-Item -Path $Path
        $snap.type = ('' + $key.GetValueKind($Name))
    } catch { }
    $snap
}

function Set-CatalogTweak {
    param([hashtable] $Tweak)
    $id   = Get-ItemProp $Tweak 'id' '?'
    $name = Get-ItemProp $Tweak 'name' $id
    Write-Log "Applying tweak: $name" 'step'
    $backup = @()

    foreach ($reg in @(Get-ItemProp $Tweak 'registry' @())) {
        $path = Get-ItemProp $reg 'path' ''
        $key  = Get-ItemProp $reg 'name' ''
        $backup += Get-RegSnapshot -Path $path -Name $key
        Set-RegValue -Path $path -Name $key -Type (Get-ItemProp $reg 'type' 'DWord') -Value (Get-ItemProp $reg 'value' 0)
        Write-Log "  reg: $path\$key = $(Get-ItemProp $reg 'value' 0)" 'dim'
    }

    foreach ($svc in @(Get-ItemProp $Tweak 'services' @())) {
        $svcName = Get-ItemProp $svc 'name' ''
        $target  = Get-ItemProp $svc 'startup' 'Disabled'
        $current = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if (-not $current) { Write-Log "  service $svcName not present, skipped" 'dim'; continue }
        $backup += @{ kind = 'service'; name = $svcName; startup = ('' + $current.StartType) }
        if ($target -eq 'Disabled') { Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue }
        Set-Service -Name $svcName -StartupType $target -ErrorAction SilentlyContinue
        Write-Log "  service: $svcName -> $target" 'dim'
    }

    foreach ($task in @(Get-ItemProp $Tweak 'tasks' @())) {
        try {
            $backup += @{ kind = 'task'; name = $task }
            Disable-ScheduledTask -TaskPath ([IO.Path]::GetDirectoryName($task) + '\') `
                                  -TaskName ([IO.Path]::GetFileName($task)) -ErrorAction Stop | Out-Null
            Write-Log "  task disabled: $task" 'dim'
        } catch { Write-Log "  task $task not found" 'dim' }
    }

    Save-TweakBackup -Id $id -Entries $backup

    $apply = Get-ItemProp $Tweak 'apply' $null
    if ($apply) { Invoke-Payload -Path $apply | Out-Null }

    Write-Log "$name applied" 'ok'
    $true
}

function Undo-CatalogTweak {
    param([hashtable] $Tweak)
    $id   = Get-ItemProp $Tweak 'id' '?'
    $name = Get-ItemProp $Tweak 'name' $id
    Write-Log "Reverting tweak: $name" 'step'

    $file     = Get-TweakBackupPath $id
    $restored = 0

    if (Test-Path $file) {
        foreach ($entry in (Get-TweakBackup $id)) {
            switch (Get-ItemProp $entry 'kind' 'registry') {
                'registry' {
                    $path = Get-ItemProp $entry 'path' ''
                    $key  = Get-ItemProp $entry 'name' ''
                    if (Get-ItemProp $entry 'existed' $false) {
                        Set-RegValue -Path $path -Name $key -Type (Get-ItemProp $entry 'type' 'DWord') -Value (Get-ItemProp $entry 'value' 0)
                        Write-Log "  restored $path\$key" 'dim'
                    } else {
                        Remove-ItemProperty -Path $path -Name $key -Force -ErrorAction SilentlyContinue
                        Write-Log "  removed $path\$key" 'dim'
                    }
                    $restored++
                }
                'service' {
                    $svc = Get-ItemProp $entry 'name' ''
                    Set-Service -Name $svc -StartupType (Get-ItemProp $entry 'startup' 'Manual') -ErrorAction SilentlyContinue
                    Write-Log "  restored service $svc" 'dim'
                    $restored++
                }
                'task' {
                    $t = Get-ItemProp $entry 'name' ''
                    try {
                        Enable-ScheduledTask -TaskPath ([IO.Path]::GetDirectoryName($t) + '\') `
                                             -TaskName ([IO.Path]::GetFileName($t)) -ErrorAction Stop | Out-Null
                        Write-Log "  re-enabled task $t" 'dim'
                        $restored++
                    } catch { }
                }
            }
        }
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }

    # The payload runs LAST, mirroring apply (declarative changes first, payload
    # after), so a refresh-style payload -- restarting Explorer, say -- sees the
    # values that were just restored rather than the ones being reverted. It also
    # has to run for payload-only tweaks, which never write a backup file at all.
    $undo = Get-ItemProp $Tweak 'undo' $null
    if ($undo) { Invoke-Payload -Path $undo | Out-Null }

    if (-not $restored -and -not $undo) {
        # Never applied, or already reverted. A no-op, not a failure.
        Write-Log "$name : no backup recorded, nothing to restore" 'warn'
        return $true
    }

    Write-Log "$name reverted ($restored item(s))" 'ok'
    $true
}

function Invoke-CatalogScript {
    param([hashtable] $Script)
    $name = Get-ItemProp $Script 'name' (Get-ItemProp $Script 'id' '?')
    Write-Log "Running: $name" 'step'
    Invoke-Payload -Path (Get-ItemProp $Script 'run' '') | Out-Null
    Write-Log "$name finished" 'ok'
    $true
}
