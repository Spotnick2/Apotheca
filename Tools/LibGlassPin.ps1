<#
    LibGlassPin.ps1 - The one PowerShell reader of the LibGlass pin, dot-sourced
    by Tools/deploy.ps1 and tests/run.ps1 (review of #30: they each had a copy).

    The pin is read the way the packager and tests/fetch_external.sh read it:
    only the Libs/LibGlass-1.0 entry of the externals block, and the whole rest
    of the commit:/tag: line as the value (the packager's YAML reader keeps an
    inline "# comment" in the value, so one shows up here as a pin that doesn't
    resolve, not as no pin at all).
#>

function Get-LibGlassPin([string]$RepoRoot, [string]$Lib = "Libs/LibGlass-1.0") {
    $inExt = $false; $inLib = $false
    foreach ($line in Get-Content -LiteralPath (Join-Path $RepoRoot ".pkgmeta")) {
        $line = $line.TrimEnd("`r")
        if ($line -match '^externals:') { $inExt = $true; continue }
        if ($inExt -and $line -match '^[^ #]') { $inExt = $false }
        if ($inExt -and $line -match ('^  ' + [regex]::Escape($Lib) + ':\s*(#.*)?$')) { $inLib = $true; continue }
        if ($inLib -and $line -match '^  [^ ]') { $inLib = $false }
        if ($inExt -and $inLib -and $line -match '^\s+(commit|tag):\s*(.*\S)\s*$') { return $Matches[2] }
    }
    return $null
}

# Prints where the checkout stands against the pin. Off the pin is a warning,
# not a failure: trying a library change before a pin bump is legitimate, but
# it isn't a check of what ships.
function Write-LibGlassPinStatus([string]$RepoRoot, [string]$LibGlass, [string]$What, [string]$Lib = "Libs/LibGlass-1.0") {
    $pin = Get-LibGlassPin $RepoRoot $Lib
    $name = ($Lib -split '/')[-1]
    if (-not $pin) {
        Write-Host "WARNING: no $name pin found in .pkgmeta's externals" -ForegroundColor Yellow
        return
    }
    $want = $null; $head = $null; $dirty = $null
    try {
        $want = (git -C $LibGlass rev-parse --verify --quiet "$pin^{commit}" 2>$null)
        $head = (git -C $LibGlass rev-parse HEAD 2>$null)
        $dirty = (git -C $LibGlass status --porcelain 2>$null)
    } catch { }
    if (-not $want -or $want -ne $head -or $dirty) {
        Write-Host "WARNING: $name at $LibGlass is not the .pkgmeta pin ($pin)$(if ($dirty) { ', or has uncommitted changes' }): $What" -ForegroundColor Yellow
    } else {
        Write-Host "${name}: $LibGlass at the pin ($pin)" -ForegroundColor DarkGray
    }
}
