<#
    Serves dist\ exactly the way the Linux box will, so you can test the real
    one-liner before deploying:

        .\tools\serve.ps1
        irm http://localhost:8080 | iex

    HttpListener needs an elevated prompt (or a netsh urlacl reservation).
#>
param(
    [int]    $Port = 8080,
    [string] $Root = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'dist')
)

$ErrorActionPreference = 'Stop'
$prefix   = "http://localhost:$Port/"
$listener = New-Object Net.HttpListener
$listener.Prefixes.Add($prefix)

try { $listener.Start() } catch {
    Write-Host "Could not bind $prefix - run this in an elevated PowerShell." -ForegroundColor Red
    return
}

Write-Host "Serving $Root at $prefix" -ForegroundColor Green
Write-Host "Test with:  irm http://localhost:$Port | iex" -ForegroundColor Cyan
Write-Host 'Ctrl+C to stop.' -ForegroundColor DarkGray

$types = @{ '.ps1' = 'text/plain; charset=utf-8'; '.json' = 'application/json; charset=utf-8' }

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
    if (-not $rel) { $rel = 'toolbox.ps1' }          # same rewrite Caddy does
    $file = Join-Path $Root ($rel -replace '/', '\')

    if (Test-Path $file -PathType Leaf) {
        $bytes = [IO.File]::ReadAllBytes($file)
        $ext   = [IO.Path]::GetExtension($file).ToLower()
        $ctx.Response.ContentType = if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' }
        $ctx.Response.Headers.Add('Cache-Control', 'no-store')
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        Write-Host ("  200  {0}" -f $rel) -ForegroundColor DarkGray
    } else {
        $ctx.Response.StatusCode = 404
        Write-Host ("  404  {0}" -f $rel) -ForegroundColor Yellow
    }
    $ctx.Response.Close()
}
