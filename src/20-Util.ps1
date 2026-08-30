# =============================================================================
#  Toolbox :: small utilities (used by both UI and worker)
# =============================================================================

function Test-Cmd {
    param([Parameter(Mandatory)][string] $Name)
    [bool](Get-Command $Name -CommandType Application, Cmdlet, Function -ErrorAction SilentlyContinue)
}

function Remove-Bom {
    <#  A UTF-8 BOM reaches us one of two ways: as U+FEFF when the server
        declared a utf-8 charset, or as the three characters its raw bytes
        decode to under latin-1 when it did not. Either one breaks
        ConvertFrom-Json and iex, so strip both. #>
    param([string] $Text)
    if (-not $Text) { return $Text }
    if ($Text[0] -eq [char]0xFEFF) { return $Text.Substring(1) }
    if ($Text.Length -ge 3 -and
        [int][char]$Text[0] -eq 239 -and [int][char]$Text[1] -eq 187 -and [int][char]$Text[2] -eq 191) {
        return $Text.Substring(3)
    }
    $Text
}

function Get-RemoteText {
    <#  Fetches a text resource relative to the Toolbox base URL (or absolute).
        A BaseUrl that is not http(s) is treated as a directory and read off
        disk, so the catalog can be served from a folder -- dist\ during
        development, or a folder mapped into a VM -- with no web server. #>
    param([Parameter(Mandatory)][string] $Path)

    if ($Toolbox.BaseUrl -notmatch '^https?://' -and $Path -notmatch '^https?://') {
        return (Remove-Bom (Get-Content -LiteralPath (Join-Path $Toolbox.BaseUrl ($Path -replace '/', '\')) -Raw))
    }

    $url = if ($Path -match '^https?://') { $Path } else { '{0}/{1}' -f $Toolbox.BaseUrl, $Path.TrimStart('/') }
    $url = '{0}{1}cb={2}' -f $url, $(if ($url.Contains('?')) { '&' } else { '?' }), [DateTime]::UtcNow.Ticks
    Remove-Bom (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60).Content
}

function Invoke-Cli {
    <#  Runs a console tool, streams its output into the log, returns the exit code.
        Output is redirected to temp files so large output can never deadlock us. #>
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [string] $Arguments = '',
        [int[]]  $SuccessCodes = @(0),
        [switch] $Quiet
    )
    $out = [IO.Path]::GetTempFileName()
    $err = [IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru `
                           -RedirectStandardOutput $out -RedirectStandardError $err
        $code = $p.ExitCode
        if (-not $Quiet) {
            foreach ($file in @($out, $err)) {
                Get-Content -LiteralPath $file -ErrorAction SilentlyContinue |
                    Where-Object { $_ -and $_.Trim() } |
                    Select-Object -Last 12 |
                    ForEach-Object { Write-Log "  $_" 'dim' }
            }
        }
        return [pscustomobject]@{
            ExitCode = $code
            Success  = ($SuccessCodes -contains $code)
            Output   = ((Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) + "`n" +
                        (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue))
        }
    } finally {
        Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-Hashtable {
    # PS 5.1 has no -AsHashtable on ConvertFrom-Json.
    # NOTE: -is [psobject] is true for strings and numbers too, so the object
    # test has to be an exact type-name match or every string in the catalog
    # gets turned into a hashtable of its properties.
    param($InputObject)
    if ($null -eq $InputObject) { return $null }

    if ($InputObject.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
        $ht = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $ht[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $ht
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        # the leading comma stops a one-element list collapsing into a scalar
        return , @($InputObject | ForEach-Object { ConvertTo-Hashtable $_ })
    }

    $InputObject
}

function Get-ItemProp {
    <#  Safe property read off a hashtable-backed catalog item. #>
    param($Item, [string] $Name, $Default = $null)
    if ($Item -is [hashtable] -and $Item.ContainsKey($Name) -and $null -ne $Item[$Name]) { return $Item[$Name] }
    return $Default
}
