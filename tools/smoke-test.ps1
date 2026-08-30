<#
    Builds the whole UI against the local dist\manifest.json without showing a
    window and without touching the machine. Run this after editing src\ or the
    catalog:

        powershell -NoProfile -STA -File .\tools\smoke-test.ps1

    Checks: every module loads, the XAML parses, every catalog entry renders,
    presets resolve, referenced payloads exist, and the worker prelude builds.
#>
$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dist  = Join-Path $root 'dist'
$fails = @()

function Check {
    param([string] $Name, [scriptblock] $Test)
    try {
        $result = & $Test
        if ($result -eq $false) { throw 'returned false' }
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL  $Name -> $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "        $($_.ScriptStackTrace -replace '
?
', '  |  ')" -ForegroundColor DarkGray
        $script:fails += $Name
    }
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host 'Re-run with -STA (WPF needs it).' -ForegroundColor Red
    exit 1
}
if (-not (Test-Path (Join-Path $dist 'manifest.json'))) {
    Write-Host 'No dist\manifest.json - run .\build.ps1 first.' -ForegroundColor Red
    exit 1
}

# Stand in for what 00-Preflight would have set up, then load every other module.
$Toolbox = @{
    Name = 'Toolbox'; Version = 'test'; BuildDate = 'test'
    BaseUrl = $dist; DataDir = (Join-Path $env:TEMP 'toolbox-test')
    BackupDir = (Join-Path $env:TEMP 'toolbox-test\backups')
    LogFile = (Join-Path $env:TEMP 'toolbox-test\test.log')
    Manifest = $null
}
New-Item -ItemType Directory -Path $Toolbox.BackupDir -Force | Out-Null

foreach ($module in Get-ChildItem (Join-Path $root 'src') -Filter *.ps1 | Sort-Object Name) {
    if ($module.Name -in '00-Preflight.ps1', '99-Main.ps1') { continue }
    . $module.FullName
}

# BaseUrl is a folder, so the real Get-RemoteText reads it off disk -- no
# override, and no divergence between what is tested and what ships.

Write-Host 'Toolbox smoke test' -ForegroundColor Cyan

Check 'manifest loads' {
    $Toolbox.Manifest = Get-ToolboxManifest
    @($Toolbox.Manifest.apps).Count -gt 0
}

Check 'XAML parses' {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
    $script:window = [Windows.Markup.XamlReader]::Load($reader)
    $null -ne $script:window
}

Check 'every named element exists' {
    $missing = @()
    foreach ($name in @('SubTitle','PresetCombo','BtnApplyPreset','SearchBox','SearchHint','Tabs',
                        'AppsPanel','TweaksPanel','ScriptsPanel','BtnInstall','BtnUninstall','BtnAppsNone',
                        'AppsCount','BtnTweakApply','BtnTweakUndo','BtnTweaksNone','TweaksCount',
                        'BtnRunScripts','BtnScriptsNone','ScriptsCount','LogBox','BtnClearLog',
                        'StatusText','Bar','BtnCancel','BtnClose')) {
        if (-not $script:window.FindName($name)) { $missing += $name }
    }
    if ($missing) { throw "missing: $($missing -join ', ')" }
    $true
}

Check 'panels render every entry' {
    $Ui['LogBox'] = $script:window.FindName('LogBox')
    foreach ($pair in @(@{K='apps';P='AppsPanel'}, @{K='tweaks';P='TweaksPanel'}, @{K='scripts';P='ScriptsPanel'})) {
        $items = @($Toolbox.Manifest[$pair.K])
        Build-Panel -Kind $pair.K -Items $items -Panel $script:window.FindName($pair.P)
        if (@($Rows[$pair.K]).Count -ne $items.Count) {
            throw "$($pair.K): rendered $(@($Rows[$pair.K]).Count) of $($items.Count)"
        }
    }
    $true
}

Check 'search filter runs' {
    $Ui['SearchBox']  = $script:window.FindName('SearchBox')
    $Ui['SearchHint'] = $script:window.FindName('SearchHint')
    $Ui['AppsCount']  = $script:window.FindName('AppsCount')
    $Ui.SearchBox.Text = 'firefox'
    Update-Filter
    $visible = @($Rows['apps'] | Where-Object { $_.Cb.Visibility -eq 'Visible' })
    $Ui.SearchBox.Text = ''
    Update-Filter
    if ($visible.Count -lt 1) { throw "search for 'firefox' matched nothing" }
    $true
}

Check 'presets resolve to real ids' {
    $bad = @()
    foreach ($preset in @($Toolbox.Manifest.presets)) {
        foreach ($kind in 'apps', 'tweaks', 'scripts') {
            foreach ($id in @($preset[$kind])) {
                $known = @($Toolbox.Manifest[$kind] | ForEach-Object { $_['id'] })
                if ($id -and $known -notcontains $id) { $bad += "$($preset['name'])/$kind/$id" }
            }
        }
    }
    if ($bad) { throw ($bad -join ', ') }
    $true
}

Check 'referenced payloads exist' {
    $missing = @()
    $refs = @()
    foreach ($item in @($Toolbox.Manifest.tweaks) + @($Toolbox.Manifest.scripts) + @($Toolbox.Manifest.apps)) {
        foreach ($key in 'apply', 'undo', 'run') { if ($item[$key]) { $refs += $item[$key] } }
        foreach ($step in @($item['install']) + @($item['uninstall'])) {
            if ($step -and $step['type'] -eq 'script' -and $step['path']) { $refs += $step['path'] }
        }
    }
    foreach ($ref in ($refs | Select-Object -Unique)) {
        if (-not (Test-Path (Join-Path $dist ($ref -replace '/', '\')))) { $missing += $ref }
    }
    if ($missing) { throw "missing payloads: $($missing -join ', ')" }
    Write-Host "        ($($refs.Count) payload references checked)" -ForegroundColor DarkGray
    $true
}

Check 'every app can be installed or removed' {
    # Debloat entries are removal-only: preinstalled Store apps have no sane
    # install step, so they carry only an uninstall chain.
    $bad = @($Toolbox.Manifest.apps |
        Where-Object { -not @($_['install']).Count -and -not @($_['uninstall']).Count } |
        ForEach-Object { $_['id'] })
    if ($bad) { throw "neither install nor uninstall steps: $($bad -join ', ')" }
    $true
}

Check 'worker prelude builds' {
    $prelude = Get-WorkerPrelude
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($prelude, [ref]$null, [ref]$errors)
    if ($errors) { throw "prelude does not parse: $($errors[0])" }
    $prelude.Length -gt 1000
}

Check 'payload scripts parse' {
    $bad = @()
    foreach ($file in Get-ChildItem (Join-Path $dist 'payloads') -Filter *.ps1) {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
        if ($errors) { $bad += $file.Name }
    }
    if ($bad) { throw ($bad -join ', ') }
    $true
}

Check 'worker runs a plan end to end' {
    # A throwaway payload proves the whole chain: runspace -> injected functions
    # -> Invoke-CatalogScript -> Invoke-Payload -> log queue.
    $probe = Join-Path $dist 'payloads\_selftest.ps1'
    Set-Content $probe -Value "Write-Log '  selftest payload ran' 'ok'" -Encoding UTF8
    try {
        $plan = @(@{ Kind = 'script'; Item = @{ id = '_selftest'; name = 'Self test'; run = 'payloads/_selftest.ps1' } })
        if (-not (Start-ToolboxPlan -Plan $plan)) { throw 'Start-ToolboxPlan refused the plan' }

        $deadline = (Get-Date).AddSeconds(30)
        while ($Sync.Busy -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
        if ($Sync.Busy) { throw 'worker never finished' }

        $lines = @()
        $line = ''
        while ($Sync.LogQueue.TryDequeue([ref]$line)) { $lines += $line }
        if ($Sync.Shell) { $Sync.Shell.Dispose(); $Sync.Shell = $null }

        if (-not ($lines -match 'selftest payload ran')) { throw "payload never ran. log: $($lines -join ' / ')" }
        if (-not ($lines -match 'all 1 succeeded'))      { throw "plan did not report success. log: $($lines -join ' / ')" }
        Write-Host "        (worker emitted $($lines.Count) log lines)" -ForegroundColor DarkGray
    } finally {
        Remove-Item $probe -Force -ErrorAction SilentlyContinue
    }
    $true
}

# --- headless mode: run the real built artifact in a child process -----------
# This is the only way to exercise 00-Preflight (mode detection, the paths that
# skip elevation) without triggering a UAC prompt.

function Invoke-BuiltScript {
    param([hashtable] $Vars)
    $Vars['TOOLBOX_BASE'] = $dist
    foreach ($key in $Vars.Keys) { Set-Item "env:$key" $Vars[$key] }
    try {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dist 'toolbox.ps1') 2>&1 | Out-String
        [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
    } finally {
        foreach ($key in $Vars.Keys) { Remove-Item "env:$key" -ErrorAction SilentlyContinue }
    }
}

Check 'headless: list mode needs no elevation' {
    $r = Invoke-BuiltScript @{ TOOLBOX_LIST = '1' }
    if ($r.ExitCode -ne 0) { throw "exit $($r.ExitCode): $($r.Output)" }
    if ($r.Output -notmatch 'PRESETS')  { throw 'presets missing from listing' }
    if ($r.Output -notmatch 'vscode')   { throw 'app ids missing from listing' }
    $true
}

Check 'headless: preset resolves and runs in order' {
    $r = Invoke-BuiltScript @{ TOOLBOX_PRESET = 'minimal'; TOOLBOX_DRYRUN = '1' }
    if ($r.ExitCode -ne 0) { throw "exit $($r.ExitCode): $($r.Output)" }
    if ($r.Output -notmatch 'DRY RUN')            { throw 'dry-run banner missing' }
    if ($r.Output -notmatch 'would install')      { throw 'no install actions planned' }
    if ($r.Output -notmatch 'would tweak')        { throw 'no tweak actions planned' }
    # apps must be planned before tweaks
    if ($r.Output.IndexOf('would install') -gt $r.Output.IndexOf('would tweak')) {
        throw 'tweaks were ordered before apps'
    }
    $true
}

Check 'headless: unknown id warns and exits 2' {
    $r = Invoke-BuiltScript @{ TOOLBOX_APPS = 'vscode,definitely-not-real'; TOOLBOX_DRYRUN = '1' }
    if ($r.ExitCode -ne 2)                  { throw "expected exit 2, got $($r.ExitCode)" }
    if ($r.Output -notmatch 'unknown id')   { throw 'no warning for the bad id' }
    if ($r.Output -notmatch 'would install'){ throw 'the valid id was dropped too' }
    $true
}

Check 'headless: uninstall reverses apps and tweaks' {
    $r = Invoke-BuiltScript @{ TOOLBOX_PRESET = 'minimal'; TOOLBOX_ACTION = 'uninstall'; TOOLBOX_DRYRUN = '1' }
    if ($r.ExitCode -ne 0) { throw "exit $($r.ExitCode): $($r.Output)" }
    if ($r.Output -notmatch 'would uninstall') { throw 'apps were not reversed' }
    if ($r.Output -notmatch 'would untweak')   { throw 'tweaks were not reversed' }
    $true
}

Check 'built files carry no BOM' {
    # Get-Content strips a BOM, Invoke-RestMethod does not -- so this only ever
    # breaks against the real server. Guard it here rather than in production.
    $bad = @()
    foreach ($name in 'toolbox.ps1', 'manifest.json') {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $dist $name))
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bad += $name
        }
    }
    if ($bad) { throw "UTF-8 BOM found in: $($bad -join ', ')" }
    $true
}

Check 'tweak backups round-trip with several entries' {
    # A one-entry backup survives a bad round-trip by accident, so this has to
    # use several: that is exactly how the empty-registry-path bug shipped.
    $id  = '_backuptest'
    $file = Get-TweakBackupPath $id
    $written = @(
        @{ kind = 'registry'; path = 'HKCU:\Software\ToolboxTest'; name = 'A'; existed = $true;  value = 1; type = 'DWord' },
        @{ kind = 'registry'; path = 'HKCU:\Software\ToolboxTest'; name = 'B'; existed = $false; value = $null; type = 'DWord' },
        @{ kind = 'service';  name = 'FakeSvc'; startup = 'Automatic' },
        @{ kind = 'task';     name = '\Microsoft\Windows\Fake\Task' }
    )
    try {
        $written | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding UTF8
        $read = Get-TweakBackup $id

        if (@($read).Count -ne $written.Count) { throw "read $(@($read).Count) entries, wrote $($written.Count)" }
        foreach ($entry in $read) {
            if ($entry -isnot [hashtable]) { throw "entry came back as $($entry.GetType().Name), not a hashtable" }
        }
        $kinds = @($read | ForEach-Object { Get-ItemProp $_ 'kind' 'registry' })
        if (($kinds -join ',') -ne 'registry,registry,service,task') { throw "kinds mangled: $($kinds -join ',')" }
        $paths = @($read | Where-Object { (Get-ItemProp $_ 'kind' '') -eq 'registry' } |
                           ForEach-Object { Get-ItemProp $_ 'path' '' })
        if ($paths -contains '') { throw 'a registry entry lost its path' }
    } finally {
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
    $true
}

Check 'tweak applies, undoes, and runs its payload last' {
    # Real registry round-trip against a throwaway HKCU key (no elevation
    # needed). The undo payload records the value it SEES, which is what proves
    # it ran after the restore rather than before it.
    $key   = 'HKCU:\Software\ToolboxTest'
    $probe = Join-Path $dist 'payloads\_ordertest.ps1'
    $payload = @'
$v = (Get-ItemProperty -Path 'HKCU:\Software\ToolboxTest' -Name 'Val' -ErrorAction SilentlyContinue).Val
if ($null -ne $v) {
    New-ItemProperty -Path 'HKCU:\Software\ToolboxTest' -Name 'SawValue' -PropertyType DWord -Value $v -Force | Out-Null
}
'@
    try {
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'Val' -PropertyType DWord -Value 111 -Force | Out-Null
        Set-Content -LiteralPath $probe -Value $payload -Encoding UTF8

        $tweak = @{
            id = '_ordertest'; name = 'Order test'
            registry = @(@{ path = $key; name = 'Val'; type = 'DWord'; value = 222 })
            undo = 'payloads/_ordertest.ps1'
        }

        Set-CatalogTweak $tweak | Out-Null
        $applied = (Get-ItemProperty -Path $key -Name 'Val').Val
        if ($applied -ne 222) { throw "apply did not take: Val=$applied" }
        if (-not (Test-Path (Get-TweakBackupPath '_ordertest'))) { throw 'no backup was written' }

        Undo-CatalogTweak $tweak | Out-Null
        $after = (Get-ItemProperty -Path $key -Name 'Val').Val
        if ($after -ne 111) { throw "undo did not restore: Val=$after" }

        $saw = (Get-ItemProperty -Path $key -Name 'SawValue' -ErrorAction SilentlyContinue).SawValue
        if ($null -eq $saw) { throw 'the undo payload never ran' }
        if ($saw -ne 111)   { throw "undo payload ran BEFORE the restore (it saw $saw, expected 111)" }

        if (Test-Path (Get-TweakBackupPath '_ordertest')) { throw 'backup file was not cleaned up' }
    } finally {
        Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $probe -Force -ErrorAction SilentlyContinue
        Remove-Item (Get-TweakBackupPath '_ordertest') -Force -ErrorAction SilentlyContinue
    }
    $true
}

Check 'installed detection matches whole words only' {
    $index = @(
        [pscustomobject]@{ Name = 'GitHub Desktop';              Version = '3.4.0' },
        [pscustomobject]@{ Name = 'Mozilla Firefox (x64 en-US)'; Version = '154.0' },
        [pscustomobject]@{ Name = 'Node.js';                     Version = '20.1.0' }
    )

    # the whole point of the word boundary: "Git" must not match "GitHub Desktop"
    if ((Test-AppInstalled -App @{ id='git'; name='Git' } -Index $index).Installed) {
        throw 'Git falsely matched GitHub Desktop'
    }

    # a name in the middle of a longer display name still matches, with version
    $ff = Test-AppInstalled -App @{ id='firefox'; name='Firefox' } -Index $index
    if (-not $ff.Installed)     { throw 'Firefox was not matched' }
    if ($ff.Version -ne '154.0'){ throw "version not captured: '$($ff.Version)'" }

    # a catalog name longer than the ARP name needs an override, and gets one
    if ((Test-AppInstalled -App @{ id='n'; name='Node.js LTS' } -Index $index).Installed) {
        throw 'Node.js LTS should not match Node.js unaided'
    }
    if (-not (Test-AppInstalled -App @{ id='n'; name='Node.js LTS'; detect=@{ name='^Node' } } -Index $index).Installed) {
        throw 'detect.name override did not match'
    }

    # detect.command, for things that never reach Add/Remove Programs
    if (-not (Test-AppInstalled -App @{ id='p'; name='Nope'; detect=@{ command='powershell' } } -Index $index).Installed) {
        throw 'detect.command did not resolve a command that exists'
    }
    if ((Test-AppInstalled -App @{ id='p'; name='Nope'; detect=@{ command='definitely-not-a-real-exe' } } -Index $index).Installed) {
        throw 'detect.command matched a command that does not exist'
    }
    $true
}

Check 'installed detection annotates every app' {
    $found = Update-InstalledState
    if ($found.Total -ne @($Toolbox.Manifest.apps).Count) { throw 'not every app was visited' }
    if ($found.Entries -lt 1) { throw 'no installed programs found at all - the registry scan is broken' }
    foreach ($app in @($Toolbox.Manifest.apps)) {
        if (-not $app.ContainsKey('installed')) { throw "$($app['id']) was not annotated" }
    }
    Write-Host "        ($($found.Installed) of $($found.Total) detected from $($found.Entries) programs, $($found.Ms) ms)" -ForegroundColor DarkGray
    $true
}

Check 'headless: short listing is names only' {
    $short = Invoke-BuiltScript @{ TOOLBOX_LIST = 'short' }
    if ($short.ExitCode -ne 0)                          { throw "exit $($short.ExitCode)" }
    if ($short.Output -notmatch 'Visual Studio Code')   { throw 'app names missing' }
    if ($short.Output -notmatch 'PRESETS')              { throw 'presets missing' }
    if ($short.Output -match '\bvscode\b')              { throw 'short mode leaked ids' }

    $full  = Invoke-BuiltScript @{ TOOLBOX_LIST = '1' }
    $sLines = @($short.Output -split "`r?`n").Count
    $fLines = @($full.Output  -split "`r?`n").Count
    if ($sLines -ge $fLines) { throw "short is $sLines lines, full is $fLines - not actually shorter" }
    Write-Host "        ($sLines lines vs $fLines for the full listing)" -ForegroundColor DarkGray
    $true
}

Write-Host ''
if ($fails) {
    Write-Host "$($fails.Count) check(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed.' -ForegroundColor Green
