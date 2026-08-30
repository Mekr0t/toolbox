# =============================================================================
#  Toolbox :: background worker
# =============================================================================
# All installing happens in a separate STA runspace so the window keeps
# repainting. The worker touches no WPF object -- it writes to $Sync only.

$WorkerFunctions = @(
    'Write-Log', 'Set-Status', 'Test-Cmd', 'Get-RemoteText', 'Invoke-Cli',
    'ConvertTo-Hashtable', 'Get-ItemProp', 'Remove-Bom',
    'Get-WingetPath', 'Initialize-Winget', 'Install-ViaWinget', 'Uninstall-ViaWinget',
    'Initialize-Choco', 'Install-ViaChoco', 'Uninstall-ViaChoco',
    'Get-ScoopShim', 'Initialize-Scoop', 'Install-ViaScoop', 'Uninstall-ViaScoop',
    'Install-ViaDownload', 'Uninstall-ViaAppx', 'Invoke-InstallStep', 'Invoke-UninstallStep', 'Invoke-Payload',
    'Install-CatalogApp', 'Uninstall-CatalogApp',
    'Get-TweakBackupPath', 'Get-TweakBackup', 'Save-TweakBackup', 'Set-RegValue', 'Get-RegSnapshot',
    'Set-CatalogTweak', 'Undo-CatalogTweak', 'Invoke-CatalogScript'
)

function Get-WorkerPrelude {
    ($WorkerFunctions | ForEach-Object {
        "function $_ {`n$((Get-Command $_ -CommandType Function).Definition)`n}"
    }) -join "`n"
}

$WorkerBody = {
    $ErrorActionPreference = 'Continue'
    $ProgressPreference    = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $total = @($Plan).Count
    $index = 0
    $failed = 0
    Write-Log "--- starting $total task(s) ---" 'step'

    foreach ($action in $Plan) {
        if ($Sync.Cancel) { Write-Log 'Cancelled by user.' 'warn'; break }
        $index++
        $Sync.Done     = $index
        $Sync.Progress = [int]((($index - 1) / [Math]::Max($total, 1)) * 100)
        $label = if ($action.Item -is [hashtable]) { $action.Item['name'] } else { '' }
        $Sync.Status = "[$index/$total] $label"

        if ($Toolbox.DryRun) {
            Write-Log ('[dry run] would {0}: {1}' -f $action.Kind, $label) 'warn'
            continue
        }

        try {
            $ok = switch ($action.Kind) {
                'install'   { Install-CatalogApp    $action.Item }
                'uninstall' { Uninstall-CatalogApp  $action.Item }
                'tweak'     { Set-CatalogTweak      $action.Item }
                'untweak'   { Undo-CatalogTweak     $action.Item }
                'script'    { Invoke-CatalogScript  $action.Item }
                default     { Write-Log "unknown action '$($action.Kind)'" 'err'; $false }
            }
            if (-not $ok) { $failed++; $Sync.Failed = $failed }
        } catch {
            $failed++
            $Sync.Failed = $failed
            Write-Log "$label : $($_.Exception.Message)" 'err'
        }
    }

    $Sync.Progress = 100
    $Sync.Status   = 'Done'
    $Sync.Failed   = $failed
    if ($failed -gt 0) { Write-Log "--- finished, $failed of $total failed ---" 'warn' }
    else               { Write-Log "--- finished, all $total succeeded ---" 'ok' }
    $Sync.Busy = $false
}

function Start-ToolboxPlan {
    param([object[]] $Plan)
    if (-not $Plan -or $Plan.Count -eq 0) { Write-Log 'Nothing selected.' 'warn'; return $false }
    if ($Sync.Busy) { Write-Log 'Already running.' 'warn'; return $false }

    $Sync.Busy = $true; $Sync.Cancel = $false; $Sync.Progress = 0
    $Sync.Total = $Plan.Count; $Sync.Done = 0; $Sync.Failed = 0

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync',     $Sync)
    $rs.SessionStateProxy.SetVariable('Toolbox',  $Toolbox)
    $rs.SessionStateProxy.SetVariable('Plan',     $Plan)
    $rs.SessionStateProxy.SetVariable('WingetOk', $WingetOk)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript((Get-WorkerPrelude) + "`n" + $WorkerBody.ToString())

    $Sync.Shell  = $ps
    $Sync.Handle = $ps.BeginInvoke()
    $true
}

function Stop-ToolboxPlan {
    $Sync.Cancel = $true
    Write-Log 'Cancel requested - finishing the current task first...' 'warn'
}
