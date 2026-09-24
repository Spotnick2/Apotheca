<#
    run.ps1 - Syntax-check the shipping Lua and run every unit test.

    The tests are plain Lua 5.1 scripts that load the addon against
    tests/wow_stubs.lua. WoW uses Lua 5.1, so the tests do too, not whatever
    newer Lua may be first on PATH.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Lua)) {
    Write-Error "Lua 5.1 interpreter not found at: $Lua  (pass -Lua <path>)"
    exit 1
}
$Luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"

# Run from the repo root so tests can dofile("tests/...") and read the TOC.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    $shipping = Get-Content "Apotheca.toc" |
        Where-Object { $_ -and -not $_.StartsWith("#") } | ForEach-Object { $_.Trim() }
    & $Luac -p @shipping "Tools\ApothecaProbe\ApothecaProbe.lua"
    if ($LASTEXITCODE -ne 0) { Write-Error "luac -p failed"; exit 1 }
    Write-Host "luac -p: $($shipping.Count) shipped files + the dev probe OK"

    $failed = 0
    foreach ($t in Get-ChildItem "tests\test_*.lua" | Sort-Object Name) {
        & $Lua $t.FullName
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }
    if ($failed -gt 0) { Write-Error "$failed test file(s) failed"; exit 1 }
    Write-Host "All tests passed" -ForegroundColor Green
} finally {
    Pop-Location
}
