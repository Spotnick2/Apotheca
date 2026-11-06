<#
    run.ps1 - Syntax-check the shipping Lua and the dev probe, and run every
    tests\test_*.lua under Lua 5.1, through WowTestKit at the commit
    tests\kit.pin names (its scripts\run.ps1). WoW uses Lua 5.1, so the tests
    do too, not whatever newer Lua may be first on PATH.

    The probe's tests (test_probe, test_applytest, test_profprobe) load
    ForeverProbe from ..\ForeverProbe, or $env:FOREVERPROBE. It is private: CI
    sets FOREVERPROBE_OPTIONAL=1 and they say SKIPPED there.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev      # the ..\WowTestKit working copy, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "Apotheca.toc" `
    -Extra @("Tools\ApothecaProbe\ApothecaProbe.lua") -Lua $Lua
exit $LASTEXITCODE
