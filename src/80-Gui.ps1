# =============================================================================
#  Toolbox :: GUI
# =============================================================================
# NOTE: WPF event handlers cannot see a function's local variables, so all UI
# state lives in these script-level containers and is only ever mutated.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$Ui   = @{}
$Rows = @{ apps = @(); tweaks = @(); scripts = @() }

$LogBrush = @{
    info = '#C7CDD9'; ok = '#5BD68A'; warn = '#E8B04B'
    err  = '#F0736A'; step = '#4C8DFF'; dim = '#6F7787'
}

function Add-LogLine {
    param([string] $Level, [string] $Text)
    $run = New-Object Windows.Documents.Run($Text)
    $hex = $LogBrush[$Level]
    if (-not $hex) { $hex = $LogBrush['info'] }
    $run.Foreground = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString($hex))
    if ($Level -eq 'step') { $run.FontWeight = 'Bold' }
    $para = $Ui.LogBox.Document.Blocks.LastBlock
    $para.Inlines.Add($run)
    $para.Inlines.Add((New-Object Windows.Documents.LineBreak))
    $Ui.LogBox.ScrollToEnd()
}

function New-ItemRow {
    <#  One catalog entry -> a CheckBox with a name line and a muted description. #>
    param([hashtable] $Item, [string] $Kind)

    $cb = New-Object Windows.Controls.CheckBox
    $cb.Tag = $Item
    $cb.IsChecked = [bool](Get-ItemProp $Item 'default' $false)

    $stack = New-Object Windows.Controls.StackPanel

    $titleRow = New-Object Windows.Controls.StackPanel
    $titleRow.Orientation = 'Horizontal'
    $title = New-Object Windows.Controls.TextBlock
    $title.Text = ('' + (Get-ItemProp $Item 'name' (Get-ItemProp $Item 'id' '?')))
    $title.FontSize = 13
    [void]$titleRow.Children.Add($title)

    # Filled in by Set-RowMarker once detection has run.
    $marker = New-Object Windows.Controls.TextBlock
    $marker.FontSize = 11
    $marker.Margin = '8,1,0,0'
    $marker.VerticalAlignment = 'Center'
    $marker.Visibility = 'Collapsed'
    $marker.Foreground = New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.ColorConverter]::ConvertFromString('#5BD68A'))
    [void]$titleRow.Children.Add($marker)
    [void]$stack.Children.Add($titleRow)

    $desc = Get-ItemProp $Item 'description' ''
    if ($desc) {
        $sub = New-Object Windows.Controls.TextBlock
        $sub.Text = $desc
        $sub.FontSize = 11
        $sub.TextWrapping = 'Wrap'
        $sub.Foreground = New-Object Windows.Media.SolidColorBrush(
            [Windows.Media.ColorConverter]::ConvertFromString('#8B93A5'))
        [void]$stack.Children.Add($sub)
    }
    $cb.Content = $stack

    $tip = @(Get-ItemProp $Item 'id' ''; Get-ItemProp $Item 'link' '') | Where-Object { $_ }
    if ($tip) { $cb.ToolTip = ($tip -join '  ') }

    $cb.Add_Checked({   Update-Counts }) | Out-Null
    $cb.Add_Unchecked({ Update-Counts }) | Out-Null

    @{ Cb = $cb; Marker = $marker }
}

function Set-RowMarker {
    param($Row)
    $item = $Row.Cb.Tag
    if (Get-ItemProp $item 'installed' $false) {
        $version = '' + (Get-ItemProp $item 'installedVersion' '')
        $Row.Marker.Text = if ($version) { "installed $version" } else { 'installed' }
        $Row.Marker.Visibility = 'Visible'
    } else {
        $Row.Marker.Visibility = 'Collapsed'
    }
}

function Sync-InstalledMarkers {
    <#  Rescans Add/Remove Programs and repaints the markers. Called once after
        the window is up (so startup stays instant) and again after every plan,
        because installing something is exactly what makes the markers stale. #>
    $summary = Update-InstalledState
    foreach ($row in $Rows['apps']) { Set-RowMarker $row }
    Update-Filter
    $summary
}

function Build-Panel {
    <#  Fills one tab: category expanders, each holding its item checkboxes. #>
    # NB: the local must not share a name with the script-level Rows table --
    # PowerShell is case-insensitive, so it would shadow it.
    param([string] $Kind, [object[]] $Items, $Panel)
    $built = @()
    $Panel.Children.Clear()
    foreach ($group in (Group-ByCategory $Items)) {
        $exp = New-Object Windows.Controls.Expander
        $exp.Header = ('{0}  ({1})' -f $group.Name, @($group.Items).Count)
        $inner = New-Object Windows.Controls.StackPanel
        $inner.Margin = '18,6,0,6'
        foreach ($item in $group.Items) {
            $row = New-ItemRow -Item $item -Kind $Kind
            [void]$inner.Children.Add($row.Cb)
            $built += @{
                Cb       = $row.Cb
                Marker   = $row.Marker
                Expander = $exp
                Haystack = (('{0} {1} {2} {3}' -f (Get-ItemProp $item 'name' ''),
                                                  (Get-ItemProp $item 'id' ''),
                                                  (Get-ItemProp $item 'description' ''),
                                                  (Get-ItemProp $item 'category' '')).ToLower())
            }
        }
        $exp.Content = $inner
        [void]$Panel.Children.Add($exp)
    }
    $Rows[$Kind] = $built
}

function Get-Checked {
    param([string] $Kind)
    @($Rows[$Kind] | Where-Object { $_.Cb.IsChecked } | ForEach-Object { $_.Cb.Tag })
}

function Clear-Checked {
    param([string] $Kind)
    foreach ($row in $Rows[$Kind]) { $row.Cb.IsChecked = $false }
}

function Update-Counts {
    foreach ($kind in 'apps', 'tweaks', 'scripts') {
        $n   = @(Get-Checked $kind).Count
        $key = ($kind.Substring(0,1).ToUpper() + $kind.Substring(1) + 'Count')
        if ($Ui[$key]) { $Ui[$key].Text = if ($n) { "   $n selected" } else { '' } }
    }
}

function Update-Filter {
    $needle = ('' + $Ui.SearchBox.Text).Trim().ToLower()
    $Ui.SearchHint.Visibility = if ($needle) { 'Collapsed' } else { 'Visible' }
    $hideInstalled = [bool]($Ui.HideInstalled -and $Ui.HideInstalled.IsChecked)
    foreach ($kind in 'apps', 'tweaks', 'scripts') {
        $seen = @{}
        foreach ($row in $Rows[$kind]) {
            $hit = (-not $needle) -or $row.Haystack.Contains($needle)
            if ($hit -and $hideInstalled -and $kind -eq 'apps' -and
                (Get-ItemProp $row.Cb.Tag 'installed' $false)) { $hit = $false }
            $row.Cb.Visibility = if ($hit) { 'Visible' } else { 'Collapsed' }
            if ($hit) { $seen[$row.Expander] = $true }
        }
        foreach ($row in $Rows[$kind]) {
            $row.Expander.Visibility = if ($seen[$row.Expander]) { 'Visible' } else { 'Collapsed' }
            if ($needle -and $seen[$row.Expander]) { $row.Expander.IsExpanded = $true }
        }
    }
}

function Set-Busy {
    param([bool] $Busy)
    $Ui.Running = $Busy
    foreach ($name in 'BtnInstall', 'BtnUninstall', 'BtnTweakApply', 'BtnTweakUndo', 'BtnRunScripts', 'BtnApplyPreset') {
        $Ui[$name].IsEnabled = -not $Busy
    }
    $Ui.BtnCancel.IsEnabled = $Busy
    if (-not $Busy) { $Ui.StatusText.Text = 'Ready' }
}

function Start-Selection {
    <#  Turns the checked boxes of one tab into a plan and hands it to the worker. #>
    param([string] $Kind, [string] $Action)
    $items = Get-Checked $Kind
    if (-not $items) { Add-LogLine 'warn' 'Nothing selected.'; return }
    $plan = @($items | ForEach-Object { @{ Kind = $Action; Item = $_ } })
    if (Start-ToolboxPlan -Plan $plan) { Set-Busy $true }
}

function Show-Toolbox {
    $Toolbox.Manifest = Get-ToolboxManifest

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $Ui['Window'] = $window

    foreach ($name in @(
        'SubTitle', 'PresetCombo', 'BtnApplyPreset', 'SearchBox', 'SearchHint', 'Tabs',
        'AppsPanel', 'TweaksPanel', 'ScriptsPanel',
        'BtnInstall', 'BtnUninstall', 'BtnAppsNone', 'AppsCount',
        'BtnTweakApply', 'BtnTweakUndo', 'BtnTweaksNone', 'TweaksCount',
        'BtnRunScripts', 'BtnScriptsNone', 'ScriptsCount',
        'LogBox', 'BtnClearLog', 'StatusText', 'Bar', 'BtnCancel', 'BtnClose', 'HideInstalled')) {
        $Ui[$name] = $window.FindName($name)
    }

    $Ui.LogBox.Document.Blocks.Clear()
    $Ui.LogBox.Document.Blocks.Add((New-Object Windows.Documents.Paragraph))

    $Ui.SubTitle.Text = '{0}   |   v{1}   |   {2} apps  {3} tweaks  {4} scripts' -f
        $Toolbox.BaseUrl, $Toolbox.Version,
        @($Toolbox.Manifest.apps).Count, @($Toolbox.Manifest.tweaks).Count, @($Toolbox.Manifest.scripts).Count

    Build-Panel -Kind 'apps'    -Items @($Toolbox.Manifest.apps)    -Panel $Ui.AppsPanel
    Build-Panel -Kind 'tweaks'  -Items @($Toolbox.Manifest.tweaks)  -Panel $Ui.TweaksPanel
    Build-Panel -Kind 'scripts' -Items @($Toolbox.Manifest.scripts) -Panel $Ui.ScriptsPanel

    foreach ($preset in @($Toolbox.Manifest.presets)) {
        [void]$Ui.PresetCombo.Items.Add((Get-ItemProp $preset 'name' (Get-ItemProp $preset 'id' '?')))
    }
    if ($Ui.PresetCombo.Items.Count) { $Ui.PresetCombo.SelectedIndex = 0 }

    # --- events ---------------------------------------------------------------
    $Ui.SearchBox.Add_TextChanged({ Update-Filter })
    $Ui.HideInstalled.Add_Click({ Update-Filter })
    $Ui.BtnInstall.Add_Click({      Start-Selection 'apps'    'install'   })
    $Ui.BtnUninstall.Add_Click({    Start-Selection 'apps'    'uninstall' })
    $Ui.BtnTweakApply.Add_Click({   Start-Selection 'tweaks'  'tweak'     })
    $Ui.BtnTweakUndo.Add_Click({    Start-Selection 'tweaks'  'untweak'   })
    $Ui.BtnRunScripts.Add_Click({   Start-Selection 'scripts' 'script'    })
    $Ui.BtnAppsNone.Add_Click({     Clear-Checked 'apps';    Update-Counts })
    $Ui.BtnTweaksNone.Add_Click({   Clear-Checked 'tweaks';  Update-Counts })
    $Ui.BtnScriptsNone.Add_Click({  Clear-Checked 'scripts'; Update-Counts })
    $Ui.BtnCancel.Add_Click({       Stop-ToolboxPlan })
    $Ui.BtnClose.Add_Click({        $Ui.Window.Close() })
    $Ui.BtnClearLog.Add_Click({
        $Ui.LogBox.Document.Blocks.Clear()
        $Ui.LogBox.Document.Blocks.Add((New-Object Windows.Documents.Paragraph))
    })

    $Ui.BtnApplyPreset.Add_Click({
        $wanted = '' + $Ui.PresetCombo.SelectedItem
        $preset = @($Toolbox.Manifest.presets) |
                    Where-Object { (Get-ItemProp $_ 'name' (Get-ItemProp $_ 'id' '')) -eq $wanted } |
                    Select-Object -First 1
        if (-not $preset) { return }
        foreach ($kind in 'apps', 'tweaks', 'scripts') {
            $ids = @(Get-ItemProp $preset $kind @())
            foreach ($row in $Rows[$kind]) {
                if ($ids -contains (Get-ItemProp $row.Cb.Tag 'id' '')) { $row.Cb.IsChecked = $true }
            }
        }
        Update-Counts
        Add-LogLine 'info' "Preset '$wanted' selected."
    })

    # --- UI heartbeat: drains the worker's log queue and mirrors its progress ---
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        $line = ''
        while ($Sync.LogQueue.TryDequeue([ref]$line)) {
            $split = $line.IndexOf('|')
            Add-LogLine $line.Substring(0, $split) $line.Substring($split + 1)
        }
        if ($Ui.NeedsScan) {
            $Ui.NeedsScan = $false
            $found = Sync-InstalledMarkers
            Add-LogLine 'dim' ("Scanned {0} installed programs: {1} of {2} catalog apps already present ({3} ms)" -f
                $found.Entries, $found.Installed, $found.Total, $found.Ms)
        }

        if ($Ui.Running) {
            $Ui.Bar.Value       = $Sync.Progress
            $Ui.StatusText.Text = $Sync.Status
            if (-not $Sync.Busy) {
                Set-Busy $false
                if ($Sync.Shell) { $Sync.Shell.Dispose(); $Sync.Shell = $null }
                $Ui.NeedsScan = $true      # installing is what makes markers stale
            }
        }
    })
    $timer.Start()

    Set-Busy $false
    Update-Counts
    $Ui.NeedsScan = $true
    Add-LogLine 'step' "Toolbox v$($Toolbox.Version) ready. Catalog: $($Toolbox.BaseUrl)"
    Add-LogLine 'dim'  "Log file: $($Toolbox.LogFile)"

    [void]$window.ShowDialog()
    $timer.Stop()
}
