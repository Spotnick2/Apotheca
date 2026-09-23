<#
    deploy.ps1 - Deploy Apotheca into the WoW: Forever AddOns folder.

    The repo keeps `## Version: @project-version@` because the CurseForge
    packager substitutes it at release time. The client would show that
    literal token, so the deployed copy gets `## Version: dev`. The repo
    copy is never modified.

    The file list comes from the TOC, so a new file is deployed the day it
    is added there. Files in the install that the repo does not ship are
    reported, not deleted: local edits have been made directly in the
    AddOns folder before and existed nowhere in git.

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$TocPath  = Join-Path $RepoRoot "Apotheca.toc"

if (-not (Test-Path $AddOnsPath)) {
    Write-Error "AddOns path not found: $AddOnsPath"
    exit 1
}

# Lua files, in TOC order: every non-comment, non-blank line.
$luaFiles = Get-Content $TocPath |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    ForEach-Object { $_.Trim() }

foreach ($f in $luaFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $f))) {
        Write-Error "The TOC lists $f, which does not exist in the repo."
        exit 1
    }
}

$dest = Join-Path $AddOnsPath "Apotheca"
New-Item -ItemType Directory -Force $dest | Out-Null

# Anything installed that this deploy would not write is worth a look
# before it is shadowed or forgotten.
$shipped = @("Apotheca.toc") + $luaFiles
Get-ChildItem $dest -File | Where-Object { $shipped -notcontains $_.Name } | ForEach-Object {
    Write-Warning "Installed file not in the repo's TOC: $($_.Name) (left in place)"
}

foreach ($f in $luaFiles) {
    Copy-Item (Join-Path $RepoRoot $f) (Join-Path $dest $f) -Force
}

$toc = (Get-Content $TocPath -Raw) -replace '@project-version@', 'dev'
Set-Content -Path (Join-Path $dest "Apotheca.toc") -Value $toc -NoNewline

Write-Host "Deployed Apotheca ($($luaFiles.Count) Lua files) to $dest"
