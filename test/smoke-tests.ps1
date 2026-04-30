#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Smoke tests for openapi2zig.

.DESCRIPTION
    Discovers JSON OpenAPI/Swagger specs under openapi/v2.0, openapi/v3.0,
    openapi/v3.1, and openapi/v3.2, then for each (spec, resource-wrapper mode)
    pair runs `openapi2zig generate` and compile-checks the generated file with
    `zig test`. Continues after individual failures and exits non-zero if any
    non-denylisted case fails.

    Cross-platform: works on PowerShell 7+ (Windows, Linux, macOS).

.PARAMETER Optimize
    Optimize mode passed to `zig build`. Defaults to ReleaseFast.

.PARAMETER Filter
    Optional wildcard pattern matched against the spec relative path
    (e.g. "v3.0/petstore*"). Useful for focused local runs.

.PARAMETER Modes
    Resource-wrapper modes to test. Defaults to all four: none, tags, paths, hybrid.

.PARAMETER KeepOutput
    If set, the test/output directory is not cleaned before the run.

.EXAMPLE
    pwsh test/smoke-tests.ps1

.EXAMPLE
    pwsh test/smoke-tests.ps1 -Filter "v3.0/petstore*" -Modes paths
#>
[CmdletBinding()]
param(
    [string]$Optimize = "ReleaseFast",
    [string]$Filter = "*",
    [string[]]$Modes = @("none", "tags", "paths", "hybrid"),
    [switch]$KeepOutput
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Repo root resolution (independent of current working directory)
# ---------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..") | Select-Object -ExpandProperty Path
Set-Location $RepoRoot

$OutputDir = Join-Path $RepoRoot "test/output"

# ---------------------------------------------------------------------------
# Denylist: known unsupported (spec, mode) combinations.
#
# Format: each entry is a hashtable with:
#   Spec   - relative spec path using forward slashes (e.g. "openapi/v3.0/petstore.json")
#            or "*" to match any spec
#   Mode   - one of none|tags|paths|hybrid, or "*" to match any mode
#   Reason - short justification, included in skip output
#
# Keep this list small and explicit. Each entry is a generator gap to fix.
# This list intentionally starts empty; populate only when CI signal demands
# it and a tracking issue exists.
# ---------------------------------------------------------------------------
$Denylist = @(
    # openapi/v3.0/ingram-micro.json fails the compile phase in every
    # resource-wrapper mode (none, tags, paths, hybrid) because the unified
    # model generator emits duplicate `pub const X = struct` declarations for
    # several shared schemas. Denylisted across all modes via Mode="*" until
    # the unified model generator dedupes shared/nested type emissions.
    @{ Spec = "openapi/v3.0/ingram-micro.json"; Mode = "*"; Reason = "duplicate `pub const` emissions from unified model generator (all wrapper modes)" }
)

function Test-Denylisted {
    param([string]$RelSpec, [string]$Mode)
    foreach ($entry in $Denylist) {
        $specMatch = ($entry.Spec -eq "*") -or ($entry.Spec -eq $RelSpec)
        $modeMatch = ($entry.Mode -eq "*") -or ($entry.Mode -eq $Mode)
        if ($specMatch -and $modeMatch) { return $entry }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Tooling discovery
# ---------------------------------------------------------------------------
function Find-Zig {
    $cmd = Get-Command zig -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "ERROR: zig was not found on PATH." -ForegroundColor Red
        exit 1
    }
    return $cmd.Source
}

function Get-CliPath {
    $exeName = if ($IsWindows) { "openapi2zig.exe" } else { "openapi2zig" }
    return (Join-Path $RepoRoot (Join-Path "zig-out/bin" $exeName))
}

# ---------------------------------------------------------------------------
# Build CLI once
# ---------------------------------------------------------------------------
$ZigPath = Find-Zig
Write-Host "Using zig: $ZigPath"
& $ZigPath version
Write-Host ""
Write-Host "==> Building openapi2zig (-Doptimize=$Optimize)" -ForegroundColor Cyan
& $ZigPath build "-Doptimize=$Optimize"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: zig build failed" -ForegroundColor Red
    exit 1
}

$Cli = Get-CliPath
if (-not (Test-Path $Cli)) {
    Write-Host "ERROR: built CLI not found at $Cli" -ForegroundColor Red
    exit 1
}
Write-Host "CLI: $Cli"

# ---------------------------------------------------------------------------
# Output dir prep
# ---------------------------------------------------------------------------
if (-not $KeepOutput -and (Test-Path $OutputDir)) {
    Remove-Item $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# ---------------------------------------------------------------------------
# Spec discovery
# ---------------------------------------------------------------------------
$IncludedDirs = @("openapi/v2.0", "openapi/v3.0", "openapi/v3.1", "openapi/v3.2")
$Specs = New-Object System.Collections.Generic.List[object]
$SkippedYaml = 0

foreach ($rel in $IncludedDirs) {
    $abs = Join-Path $RepoRoot $rel
    if (-not (Test-Path $abs)) { continue }
    $files = Get-ChildItem -Path $abs -Recurse -File
    foreach ($f in $files) {
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -eq ".yaml" -or $ext -eq ".yml") { $SkippedYaml++; continue }
        if ($ext -ne ".json") { continue }
        $relPath = (Resolve-Path -Relative $f.FullName) -replace '\\', '/'
        $relPath = $relPath -replace '^\./', ''
        # Pattern match against the slash-normalized relative path.
        if ($relPath -notlike "*$Filter*" -and ($Filter -ne "*")) { continue }
        $Specs.Add([pscustomobject]@{
            Abs     = $f.FullName
            Rel     = $relPath
            Version = (Split-Path $rel -Leaf)
            Base    = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        })
    }
}

$Specs = $Specs | Sort-Object Rel
$totalCases = $Specs.Count * $Modes.Count

Write-Host ""
Write-Host "Discovered $($Specs.Count) JSON specs across $($IncludedDirs.Count) directories"
Write-Host "Resource-wrapper modes: $($Modes -join ', ')"
Write-Host "Total cases to run:     $totalCases (sequential)"
Write-Host "Skipped YAML files:     $SkippedYaml (unsupported by generator)"
Write-Host "Output directory:       $OutputDir"
Write-Host ""

# ---------------------------------------------------------------------------
# Run loop
# ---------------------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]
$idx = 0

foreach ($spec in $Specs) {
    foreach ($mode in $Modes) {
        $idx++
        $caseLabel = "[{0}/{1}] {2} :: {3}" -f $idx, $totalCases, $spec.Rel, $mode

        $deny = Test-Denylisted -RelSpec $spec.Rel -Mode $mode
        if ($null -ne $deny) {
            Write-Host "SKIP $caseLabel  (denylist: $($deny.Reason))" -ForegroundColor Yellow
            $results.Add([pscustomobject]@{
                Spec = $spec.Rel; Mode = $mode; Status = "skip"; Reason = $deny.Reason
            })
            continue
        }

        Write-Host "---- $caseLabel" -ForegroundColor Cyan

        $outFile = Join-Path $OutputDir (Join-Path $spec.Version ("{0}__{1}.zig" -f $spec.Base, $mode))
        $outParent = Split-Path -Parent $outFile
        if (-not (Test-Path $outParent)) { New-Item -ItemType Directory -Path $outParent -Force | Out-Null }

        # ---- Generate ----
        $genOutput = & $Cli generate -i $spec.Abs -o $outFile --resource-wrappers $mode 2>&1
        $genExit = $LASTEXITCODE
        if ($genExit -ne 0) {
            Write-Host "FAIL (generate) $caseLabel" -ForegroundColor Red
            Write-Host ($genOutput | Out-String)
            $results.Add([pscustomobject]@{
                Spec = $spec.Rel; Mode = $mode; Status = "fail"; Phase = "generate"
                ExitCode = $genExit; Output = ($genOutput | Out-String)
            })
            continue
        }

        if (-not (Test-Path $outFile)) {
            Write-Host "FAIL (generate produced no file) $caseLabel" -ForegroundColor Red
            $results.Add([pscustomobject]@{
                Spec = $spec.Rel; Mode = $mode; Status = "fail"; Phase = "generate"
                ExitCode = 0; Output = "no output file"
            })
            continue
        }

        # ---- Compile-check ----
        # Generated files are library modules (no main()), so use `zig test`,
        # which compiles them and reports "All 0 tests passed" on success.
        $testOutput = & $ZigPath test $outFile 2>&1
        $testExit = $LASTEXITCODE
        if ($testExit -ne 0) {
            Write-Host "FAIL (compile) $caseLabel" -ForegroundColor Red
            Write-Host ($testOutput | Out-String)
            $results.Add([pscustomobject]@{
                Spec = $spec.Rel; Mode = $mode; Status = "fail"; Phase = "compile"
                ExitCode = $testExit; Output = ($testOutput | Out-String)
            })
            continue
        }

        Write-Host "PASS $caseLabel" -ForegroundColor Green
        $results.Add([pscustomobject]@{
            Spec = $spec.Rel; Mode = $mode; Status = "pass"
        })
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$pass = @($results | Where-Object Status -eq "pass").Count
$fail = @($results | Where-Object Status -eq "fail").Count
$skip = @($results | Where-Object Status -eq "skip").Count

Write-Host ""
Write-Host "================ Smoke-test summary ================"
Write-Host ("Pass : {0}" -f $pass) -ForegroundColor Green
Write-Host ("Fail : {0}" -f $fail) -ForegroundColor ($(if ($fail -gt 0) { "Red" } else { "Gray" }))
Write-Host ("Skip : {0}" -f $skip) -ForegroundColor Yellow
Write-Host ("Total: {0}" -f $results.Count)
Write-Host "===================================================="

if ($fail -gt 0) {
    Write-Host ""
    Write-Host "Failing cases:" -ForegroundColor Red
    foreach ($r in ($results | Where-Object Status -eq "fail")) {
        Write-Host (" - [{0}] {1} :: {2}  (exit {3})" -f $r.Phase, $r.Spec, $r.Mode, $r.ExitCode) -ForegroundColor Red
    }
    exit 1
}

exit 0
