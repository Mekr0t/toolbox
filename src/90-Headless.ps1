# =============================================================================
#  Toolbox :: headless mode (no window)
# =============================================================================
# The GUI is only a renderer over $Sync -- the worker pushes log lines into a
# queue and mutates counters, and a DispatcherTimer draws them. Headless swaps
# that timer for a console loop. Manifest, providers, worker, backups and undo
# are the exact same code paths the window uses.

$ConsoleColour = @{
    info = 'Gray'; ok   = 'Green'; warn = 'Yellow'
    err  = 'Red';  step = 'Cyan';  dim  = 'DarkGray'
}

function Write-Console {
    param([string] $Level, [string] $Text)
    $colour = $ConsoleColour[$Level]
    if (-not $colour) { $colour = 'Gray' }
    Write-Host $Text -ForegroundColor $colour
}

function Split-IdList {
    param([string] $Value)
    if (-not $Value) { return @() }
    , @($Value -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-CatalogItem {
    param([string] $Kind, [string] $Id)
    @($Toolbox.Manifest[$Kind]) |
        Where-Object { (Get-ItemProp $_ 'id' '') -eq $Id } |
        Select-Object -First 1
}

function Resolve-HeadlessPlan {
    # -> @{ Plan = <action list>; Unknown = <ids that matched nothing> }
    $wanted  = @{ apps = @(); tweaks = @(); scripts = @() }
    $unknown = @()

    foreach ($name in (Split-IdList $Toolbox.Preset)) {
        $preset = @($Toolbox.Manifest.presets) | Where-Object {
            (Get-ItemProp $_ 'id' '') -eq $name -or (Get-ItemProp $_ 'name' '') -eq $name
        } | Select-Object -First 1

        if (-not $preset) { $unknown += "preset:$name"; continue }
        Write-Console 'step' ('preset: {0}' -f (Get-ItemProp $preset 'name' $name))
        foreach ($kind in 'apps', 'tweaks', 'scripts') {
            $wanted[$kind] += @(Get-ItemProp $preset $kind @())
        }
    }

    $wanted.apps    += Split-IdList $Toolbox.AppIds
    $wanted.tweaks  += Split-IdList $Toolbox.TweakIds
    $wanted.scripts += Split-IdList $Toolbox.ScriptIds

    $reverse     = ($Toolbox.Action -eq 'uninstall')
    $appAction   = if ($reverse) { 'uninstall' } else { 'install' }
    $tweakAction = if ($reverse) { 'untweak' }   else { 'tweak' }

    if ($reverse -and @($wanted.scripts).Count) {
        Write-Console 'warn' 'TOOLBOX_ACTION=uninstall: scripts have no inverse, skipping them.'
        $wanted.scripts = @()
    }

    # Apps, then tweaks, then scripts: a personal script usually wants the thing
    # it configures to exist already.
    $order = @(
        @{ K = 'apps';    A = $appAction },
        @{ K = 'tweaks';  A = $tweakAction },
        @{ K = 'scripts'; A = 'script' }
    )
    $plan = @()
    foreach ($pair in $order) {
        foreach ($id in (@($wanted[$pair.K]) | Select-Object -Unique)) {
            $item = Get-CatalogItem $pair.K $id
            if ($item) { $plan += @{ Kind = $pair.A; Item = $item } }
            else       { $unknown += "$($pair.K):$id" }
        }
    }

    @{ Plan = $plan; Unknown = $unknown }
}

function Write-WrappedList {
    <#  "Category    Name, Name, Name" wrapped to the console width. #>
    param([string] $Label, [string[]] $Items, [int] $LabelWidth = 15)

    $width = 100
    try { $width = [Math]::Max(60, $Host.UI.RawUI.WindowSize.Width - 2) } catch { }
    $room   = $width - $LabelWidth - 3
    $indent = ' ' * ($LabelWidth + 3)

    $lines = @()
    $line  = ''
    foreach ($item in $Items) {
        $candidate = if ($line) { "$line, $item" } else { "$item" }
        if ($line -and $candidate.Length -gt $room) { $lines += $line; $line = "$item" }
        else { $line = $candidate }
    }
    if ($line) { $lines += $line }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq 0) { Write-Host ('  ' + $Label.PadRight($LabelWidth) + ' ') -ForegroundColor DarkGray -NoNewline }
        else          { Write-Host $indent -NoNewline }
        Write-Host $lines[$i]
    }
}

function Show-ToolboxCatalogShort {
    # Deliberately skips Update-InstalledState -- this mode exists to be instant.
    $Toolbox.Manifest = Get-ToolboxManifest

    foreach ($kind in 'apps', 'tweaks', 'scripts') {
        $items = @($Toolbox.Manifest[$kind])
        Write-Console 'step' ("`n{0}  ({1})" -f $kind.ToUpper(), $items.Count)
        foreach ($group in (Group-ByCategory $items)) {
            Write-WrappedList -Label $group.Name -Items @($group.Items | ForEach-Object { Get-ItemProp $_ 'name' '' })
        }
    }

    $presets = @($Toolbox.Manifest.presets)
    Write-Console 'step' ("`nPRESETS  ({0})" -f $presets.Count)
    Write-WrappedList -Label '' -Items @($presets | ForEach-Object { Get-ItemProp $_ 'name' '' })

    Write-Console 'dim' "`nIds and install state:  `$env:TOOLBOX_LIST='1'"
    0
}

function Show-ToolboxCatalog {
    # $env:TOOLBOX_LIST='1' -- prints every id so you know what to put in the
    # other variables. Needs no elevation, since it changes nothing.
    if ($Toolbox.ListStyle -eq 'short') { return (Show-ToolboxCatalogShort) }

    $Toolbox.Manifest = Get-ToolboxManifest
    $found = Update-InstalledState

    foreach ($kind in 'apps', 'tweaks', 'scripts') {
        Write-Console 'step' ("`n{0}  ({1})" -f $kind.ToUpper(), @($Toolbox.Manifest[$kind]).Count)
        foreach ($group in (Group-ByCategory @($Toolbox.Manifest[$kind]))) {
            Write-Console 'dim' ("  {0}" -f $group.Name)
            foreach ($item in $group.Items) {
                $mark = if (Get-ItemProp $item 'installed' $false) { '*' } else { ' ' }
                Write-Host ("  {0} {1,-26} {2}" -f $mark, (Get-ItemProp $item 'id' ''), (Get-ItemProp $item 'name' ''))
            }
        }
    }

    Write-Console 'step' "`nPRESETS"
    foreach ($preset in @($Toolbox.Manifest.presets)) {
        $counts = '{0} apps, {1} tweaks, {2} scripts' -f
            @(Get-ItemProp $preset 'apps' @()).Count,
            @(Get-ItemProp $preset 'tweaks' @()).Count,
            @(Get-ItemProp $preset 'scripts' @()).Count
        Write-Host ("    {0,-26} {1}" -f (Get-ItemProp $preset 'id' ''), (Get-ItemProp $preset 'name' ''))
        Write-Console 'dim' ("    {0,-26} {1}" -f '', $counts)
    }

    Write-Console 'dim' ("`n* = already installed ({0} of {1} apps, {2} ms)" -f $found.Installed, $found.Total, $found.Ms)
    Write-Console 'dim' "Run a preset:   `$env:TOOLBOX_PRESET='dev'; irm $($Toolbox.BaseUrl) | iex"
    Write-Console 'dim' "Pick by id:     `$env:TOOLBOX_APPS='vscode,git'; irm $($Toolbox.BaseUrl) | iex"
    0
}

function Invoke-ToolboxHeadless {
    $Toolbox.Manifest = Get-ToolboxManifest
    $resolved = Resolve-HeadlessPlan
    $plan     = @($resolved.Plan)

    foreach ($miss in $resolved.Unknown) { Write-Console 'err' "unknown id: $miss" }

    if (-not $plan) {
        Write-Console 'err' 'Nothing to do - no id resolved to a catalog entry.'
        Write-Console 'dim' "Set `$env:TOOLBOX_LIST='1' to print every id."
        return 2
    }

    $banner = 'Toolbox v{0} headless - {1} task(s){2}' -f
        $Toolbox.Version, $plan.Count, $(if ($Toolbox.DryRun) { '   [DRY RUN - nothing will change]' } else { '' })
    Write-Console 'step' $banner
    foreach ($action in $plan) {
        Write-Console 'dim' ('  {0,-10} {1}' -f $action.Kind, (Get-ItemProp $action.Item 'name' ''))
    }
    Write-Host ''

    if (-not (Start-ToolboxPlan -Plan $plan)) { return 1 }

    # Same drain the DispatcherTimer does, minus the window. The queue is
    # checked as well as Busy, so the last lines are not lost on the way out.
    $line = ''
    while ($Sync.Busy -or $Sync.LogQueue.Count -gt 0) {
        while ($Sync.LogQueue.TryDequeue([ref]$line)) {
            $split = $line.IndexOf('|')
            Write-Console $line.Substring(0, $split) $line.Substring($split + 1)
        }
        Start-Sleep -Milliseconds 100
    }
    if ($Sync.Shell) { $Sync.Shell.Dispose(); $Sync.Shell = $null }

    $failed = [int]$Sync.Failed
    Write-Host ''
    if ($failed -gt 0) {
        Write-Console 'warn' ("{0} of {1} task(s) failed - full log: {2}" -f $failed, $plan.Count, $Toolbox.LogFile)
    } else {
        Write-Console 'ok' ("All {0} task(s) completed." -f $plan.Count)
    }
    if ($resolved.Unknown) {
        Write-Console 'warn' ("{0} id(s) matched nothing and were skipped." -f @($resolved.Unknown).Count)
    }

    if ($failed -gt 0)     { return 1 }
    if ($resolved.Unknown) { return 2 }
    0
}
