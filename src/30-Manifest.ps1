# =============================================================================
#  Toolbox :: manifest loading
# =============================================================================

function Get-ToolboxManifest {
    Write-Host ("Fetching catalog from {0} ..." -f $Toolbox.BaseUrl) -ForegroundColor DarkGray
    $raw  = Get-RemoteText 'manifest.json'
    $data = ConvertTo-Hashtable ($raw | ConvertFrom-Json)

    foreach ($key in 'apps', 'tweaks', 'scripts', 'presets') {
        if (-not $data.ContainsKey($key) -or $null -eq $data[$key]) { $data[$key] = @() }
        $data[$key] = @($data[$key])
    }
    $data
}

function Group-ByCategory {
    # Returns an ordered list of @{ Name; Items }, categories A-Z with 'Other'
    # last. Deliberately NOT an [ordered]@{}: PowerShell resolves a string index
    # on OrderedDictionary against its int overload and throws.
    param([object[]] $Items)

    $names   = @($Items | ForEach-Object { Get-ItemProp $_ 'category' 'Other' } | Select-Object -Unique | Sort-Object)
    $ordered = @($names | Where-Object { $_ -ne 'Other' }) + @($names | Where-Object { $_ -eq 'Other' })

    $groups = @()
    foreach ($name in $ordered) {
        $groups += @{
            Name  = $name
            Items = @($Items |
                Where-Object { (Get-ItemProp $_ 'category' 'Other') -eq $name } |
                Sort-Object { Get-ItemProp $_ 'name' '' })
        }
    }
    , $groups
}
