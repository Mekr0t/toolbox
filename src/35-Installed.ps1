# =============================================================================
#  Toolbox :: installed-app detection
# =============================================================================
# One pass over Add/Remove Programs, then every catalog app is matched against
# it. An app can override the match with a "detect" block:
#
#   "detect": { "name": "^Node" }                    regex over the ARP name
#   "detect": { "command": "wt" }                    anything on PATH
#   "detect": { "path": "%ProgramFiles%/Foo/foo.exe" }
#   "detect": { "appx": "Microsoft.WindowsTerminal" } MSIX/Store, absent from ARP
#
# Without one, the app's own name is matched as a WHOLE WORD, so "Git" does not
# report itself installed because "GitHub Desktop" is present.

function Get-InstalledIndex {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $found = New-Object Collections.ArrayList
    foreach ($key in $keys) {
        foreach ($entry in (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)) {
            if (-not $entry.DisplayName) { continue }
            if ($entry.SystemComponent -eq 1) { continue }   # updates, redists, plumbing
            [void]$found.Add([pscustomobject]@{
                Name    = ('' + $entry.DisplayName)
                Version = ('' + $entry.DisplayVersion)
            })
        }
    }
    , $found
}

function Get-AppxIndex {
    <#  One call for the whole Appx list. Querying per package costs ~150 ms
        each, which the debloat entries turn into seconds. #>
    , @(Get-AppxPackage -ErrorAction SilentlyContinue)
}

function Test-AppInstalled {
    param([hashtable] $App, $Index, $AppxIndex)

    $detect = Get-ItemProp $App 'detect' $null

    $cmd = Get-ItemProp $detect 'command' $null
    if ($cmd -and (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        return @{ Installed = $true; Version = '' }
    }

    $file = Get-ItemProp $detect 'path' $null
    if ($file -and (Test-Path ([Environment]::ExpandEnvironmentVariables($file)) -ErrorAction SilentlyContinue)) {
        return @{ Installed = $true; Version = '' }
    }

    # Only pay for the Appx list when an entry actually asks for it, and only once.
    $appx = Get-ItemProp $detect 'appx' $null
    if ($appx) {
        if ($null -eq $AppxIndex) { $AppxIndex = Get-AppxIndex }
        $pkg = $AppxIndex | Where-Object { $_.Name -like $appx } | Select-Object -First 1
        if ($pkg) { return @{ Installed = $true; Version = ('' + $pkg.Version) } }
    }

    $pattern = Get-ItemProp $detect 'name' $null
    if (-not $pattern) {
        $name = '' + (Get-ItemProp $App 'name' '')
        if (-not $name) { return @{ Installed = $false; Version = '' } }
        $pattern = '\b' + [regex]::Escape($name) + '\b'
    }

    $hit = $Index | Where-Object { $_.Name -match $pattern } | Select-Object -First 1
    if ($hit) { return @{ Installed = $true; Version = $hit.Version } }
    @{ Installed = $false; Version = '' }
}

function Update-InstalledState {
    <#  Annotates every app in the manifest with 'installed' and
        'installedVersion'. Returns a small summary for the caller to log. #>
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $index = Get-InstalledIndex
    $apps  = @($Toolbox.Manifest.apps)
    $count = 0

    $appxIndex = $null
    if (@($apps | Where-Object { Get-ItemProp (Get-ItemProp $_ 'detect' $null) 'appx' $null }).Count) {
        $appxIndex = Get-AppxIndex
    }

    foreach ($app in $apps) {
        $state = Test-AppInstalled -App $app -Index $index -AppxIndex $appxIndex
        $app['installed']        = $state.Installed
        $app['installedVersion'] = $state.Version
        if ($state.Installed) { $count++ }
    }

    $watch.Stop()
    @{ Installed = $count; Total = $apps.Count; Ms = $watch.ElapsedMilliseconds; Entries = @($index).Count }
}
