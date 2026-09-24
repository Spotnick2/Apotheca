<#
    deploy.ps1 - Deploy Apotheca into the WoW: Forever AddOns folder.

    The repo keeps `## Version: @project-version@` because the CurseForge
    packager substitutes it at release time. The client would show that
    literal token, so the deployed copy gets `## Version: dev`. The repo
    copy is never modified.

    The file list comes from the TOC, so a new file is deployed the day it
    is added there.

    Local edits have been made directly in the AddOns folder before and
    existed nowhere in git. So every deploy records a hash of each file it
    wrote (.apotheca-deploy.txt in the install), and the next deploy refuses
    to overwrite a file whose content no longer matches that record. An
    install with no record, from before this script, is compared against the
    repo instead. -Force overwrites anyway.

    -Probe also installs the development-only probe addon (Tools/ApothecaProbe:
    /apo probe, /apo scan, /apo scan2) as its own AddOns folder. It is never
    packaged for players.

    A file this script installed earlier that the TOC no longer lists (the
    probe used to live inside Apotheca) is removed, but only if it is
    unchanged since it was deployed.

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -Probe
        pwsh Tools/deploy.ps1 -Force
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns",
    [switch]$Force,
    [switch]$Probe
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$TocPath  = Join-Path $RepoRoot "Apotheca.toc"

if (-not (Test-Path $AddOnsPath)) {
    Write-Error "AddOns path not found: $AddOnsPath"
    exit 1
}

# Lua files, in TOC order: every non-comment, non-blank line.
$luaFiles = @(Get-Content $TocPath |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    ForEach-Object { $_.Trim() })

foreach ($f in $luaFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $f))) {
        Write-Error "The TOC lists $f, which does not exist in the repo."
        exit 1
    }
}

$dest     = Join-Path $AddOnsPath "Apotheca"
$manifest = Join-Path $dest ".apotheca-deploy.txt"
New-Item -ItemType Directory -Force $dest | Out-Null

function Get-Hash([string]$path) { (Get-FileHash -Algorithm SHA256 $path).Hash }

# What the last deploy wrote: name -> hash.
$recorded = @{}
if (Test-Path $manifest) {
    foreach ($line in Get-Content $manifest) {
        $name, $hash = $line -split "\s+", 2
        if ($name -and $hash) { $recorded[$name] = $hash }
    }
}

$tocText = (Get-Content $TocPath -Raw) -replace '@project-version@', 'dev'
$shipped = @("Apotheca.toc") + $luaFiles

# Refuse to clobber anything edited in place since the last deploy.
$changed = @()
foreach ($name in $shipped) {
    $installed = Join-Path $dest $name
    if (-not (Test-Path $installed)) { continue }
    $now = Get-Hash $installed
    if ($recorded.ContainsKey($name)) {
        if ($now -ne $recorded[$name]) { $changed += $name }
    } elseif ($name -ne "Apotheca.toc") {
        # No record yet: an install from before this script. Compare with the repo.
        if ($now -ne (Get-Hash (Join-Path $RepoRoot $name))) { $changed += $name }
    }
}
if ($changed.Count -gt 0 -and -not $Force) {
    Write-Error ("These installed files were changed since the last deploy and would be " +
        "overwritten: $($changed -join ', '). Diff them against the repo and bring any " +
        "local edits into git, or rerun with -Force.")
    exit 1
}

Get-ChildItem $dest -File | Where-Object {
    $shipped -notcontains $_.Name -and $_.Name -ne ".apotheca-deploy.txt"
} | ForEach-Object {
    # Ours and untouched: a file an earlier deploy wrote that is no longer shipped.
    if ($recorded.ContainsKey($_.Name) -and (Get-Hash $_.FullName) -eq $recorded[$_.Name]) {
        Remove-Item $_.FullName
        Write-Host "Removed $($_.Name): no longer in the TOC, unchanged since it was deployed"
    } else {
        Write-Warning "Installed file not in the repo's TOC: $($_.Name) (left in place)"
    }
}

foreach ($f in $luaFiles) {
    Copy-Item (Join-Path $RepoRoot $f) (Join-Path $dest $f) -Force
}
Set-Content -Path (Join-Path $dest "Apotheca.toc") -Value $tocText -NoNewline

$shipped | ForEach-Object { "$_ $(Get-Hash (Join-Path $dest $_))" } | Set-Content $manifest

Write-Host "Deployed Apotheca ($($luaFiles.Count) Lua files) to $dest"

if ($Probe) {
    $probeSrc  = Join-Path $RepoRoot "Tools\ApothecaProbe"
    $probeDest = Join-Path $AddOnsPath "ApothecaProbe"
    New-Item -ItemType Directory -Force $probeDest | Out-Null
    Copy-Item (Join-Path $probeSrc "*") $probeDest -Force
    Write-Host "Deployed the dev-only ApothecaProbe addon to $probeDest"
}
