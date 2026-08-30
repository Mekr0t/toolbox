# =============================================================================
#  Toolbox :: shared state + logging
# =============================================================================
# $Sync is shared between the UI thread and the background worker runspace.
# The worker never touches WPF objects -- it only enqueues log lines and
# updates plain values that a DispatcherTimer on the UI thread polls.

$Sync = [hashtable]::Synchronized(@{
    LogQueue = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]')
    Busy     = $false
    Cancel   = $false
    Progress = 0
    Total    = 0
    Done     = 0
    Failed   = 0
    Status   = 'Idle'
    LogFile  = $Toolbox.LogFile
})

function Write-Log {
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('info', 'ok', 'warn', 'err', 'step', 'dim')][string] $Level = 'info'
    )
    $stamp = Get-Date -Format 'HH:mm:ss'
    $Sync.LogQueue.Enqueue("$Level|[$stamp] $Message")
    try { Add-Content -LiteralPath $Sync.LogFile -Value "[$stamp][$Level] $Message" -Encoding UTF8 } catch { }
}

function Set-Status {
    param([string] $Text)
    $Sync.Status = $Text
}
