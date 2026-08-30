# ---------------------------------------------------------------------------
#  Personal bootstrap - TEMPLATE.
#
#  Edit the block below, then rebuild and redeploy. This runs inside the Toolbox
#  worker, so Write-Log, Invoke-Cli and Get-WingetPath are all available.
# ---------------------------------------------------------------------------

# ---- EDIT ME --------------------------------------------------------------
$GitUserName  = 'Your Name'
$GitUserEmail = 'you@example.com'
$Folders      = @("$env:USERPROFILE\projects", "$env:USERPROFILE\tools")
$MakeSshKey   = $true
# ---------------------------------------------------------------------------

# 1. Folders you always want
foreach ($dir in $Folders) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Log "  created $dir" 'dim'
    }
}

# 2. Git identity -- skipped while the template values are still in place, so a
#    fresh clone cannot quietly commit as "Your Name".
if ($GitUserEmail -eq 'you@example.com') {
    Write-Log '  git identity is still the template default - edit payloads/my-dev-setup.ps1' 'warn'
} elseif (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global user.name  $GitUserName
    git config --global user.email $GitUserEmail
    git config --global init.defaultBranch main
    git config --global pull.rebase true
    Write-Log "  git configured as $GitUserName <$GitUserEmail>" 'dim'
} else {
    Write-Log '  git is not installed yet - install it first, then re-run this' 'warn'
}

# 3. SSH key, only if there is not one already
$sshKey = "$env:USERPROFILE\.ssh\id_ed25519"
if ($MakeSshKey -and -not (Test-Path $sshKey)) {
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh" -Force | Out-Null
    ssh-keygen -t ed25519 -f $sshKey -N '""' -C "$env:COMPUTERNAME" | Out-Null
    Write-Log "  new ssh key: $sshKey.pub" 'ok'
    Write-Log ('  ' + (Get-Content "$sshKey.pub" -Raw).Trim()) 'info'
}

Write-Log '  dev bootstrap done' 'ok'
