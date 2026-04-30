param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Debug", "ReleaseFast", "ReleaseSafe", "ReleaseSmall")]
    [string]
    $Optimize = "ReleaseFast"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Format-CommandLine {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Command,

        [Parameter(Mandatory = $false)]
        [string[]]
        $Arguments = @()
    )

    $parts = @($Command)
    foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            $parts += '"' + $argument.Replace('"', '\"') + '"'
        } else {
            $parts += $argument
        }
    }

    return ($parts -join " ")
}

function Invoke-NativeCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Command,

        [Parameter(Mandatory = $false)]
        [string[]]
        $Arguments = @(),

        [Parameter(Mandatory = $true)]
        [string]
        $FailureMessage
    )

    Write-Host (Format-CommandLine -Command $Command -Arguments $Arguments)
    & $Command @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$FailureMessage (exit code $exitCode)"
    }
}

function Resolve-ZigCommand {
    $zig = Get-Command "zig" -ErrorAction SilentlyContinue
    if ($zig) {
        return $zig.Source
    }

    if ($IsWindows) {
        $candidates = @(
            "$env:USERPROFILE\scoop\shims\zig.exe",
            "$env:USERPROFILE\scoop\apps\zig\current\zig.exe",
            "C:\Program Files\Zig\zig.exe",
            "C:\tools\zig\zig.exe"
        )

        $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe"
        if (Test-Path -LiteralPath $wingetRoot) {
            $wingetZig = Get-ChildItem -Path $wingetRoot -Recurse -File -Filter "zig.exe" |
                Sort-Object -Property FullName -Descending |
                Select-Object -First 1
            if ($wingetZig) {
                $candidates += $wingetZig.FullName
            }
        }

        foreach ($candidate in $candidates) {
            if ($candidate -and (Test-Path -LiteralPath $candidate)) {
                return $candidate
            }
        }
    }

    throw "Could not locate the Zig executable. Install Zig 0.16.0+ or ensure 'zig' is available on PATH."
}

function Get-SmokeSpecFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $OpenApiRoot
    )

    return Get-ChildItem -Path $OpenApiRoot -Recurse -File -Filter "*.json" |
        Where-Object { $_.FullName -notmatch '[\\/]+json-schema[\\/]+' } |
        Sort-Object -Property FullName
}

function New-CompileHarness {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $HarnessPath
    )

    $content = @'
const std = @import("std");
const generated = @import("generated.zig");

test "generated code compiles" {
    std.testing.refAllDecls(generated);
}
'@

    Set-Content -LiteralPath $HarnessPath -Value $content -Encoding utf8NoBOM
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))
$openApiRoot = Join-Path $repoRoot "openapi"
$generatedRoot = Join-Path (Join-Path $repoRoot "generated") "smoke"
$zig = Resolve-ZigCommand
$binaryName = if ($IsWindows) { "openapi2zig.exe" } else { "openapi2zig" }
$openApi2Zig = Join-Path (Join-Path (Join-Path $repoRoot "zig-out") "bin") $binaryName

$specFiles = @(Get-SmokeSpecFiles -OpenApiRoot $openApiRoot)
if ($specFiles.Count -eq 0) {
    throw "No supported JSON OpenAPI/Swagger smoke-test inputs were found under '$openApiRoot'."
}

Push-Location $repoRoot
try {
    Write-Host "Discovered $($specFiles.Count) JSON OpenAPI/Swagger smoke-test inputs."
    Write-Host "Excluded: YAML examples and openapi/json-schema fixtures."
    Write-Host ""

    Invoke-NativeCommand -Command $zig -Arguments @("version") -FailureMessage "Unable to query Zig version"
    Invoke-NativeCommand -Command $zig -Arguments @("build", "-Doptimize=$Optimize") -FailureMessage "Failed to build openapi2zig"

    if (-not (Test-Path -LiteralPath $openApi2Zig)) {
        throw "Expected generated CLI at '$openApi2Zig' after build, but it was not found."
    }

    if (Test-Path -LiteralPath $generatedRoot) {
        Remove-Item -LiteralPath $generatedRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null

    $passedCount = 0
    $failures = [System.Collections.Generic.List[object]]::new()

    for ($index = 0; $index -lt $specFiles.Count; $index++) {
        $spec = $specFiles[$index]
        $relativeSpecPath = [System.IO.Path]::GetRelativePath($repoRoot, $spec.FullName)
        $relativeOutputPath = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetRelativePath($openApiRoot, $spec.FullName), $null)
        $outputDirectory = Join-Path $generatedRoot $relativeOutputPath
        $generatedFile = Join-Path $outputDirectory "generated.zig"
        $compileHarness = Join-Path $outputDirectory "compile.zig"

        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

        Write-Host "[$($index + 1)/$($specFiles.Count)] $relativeSpecPath" -ForegroundColor Cyan

        try {
            Invoke-NativeCommand `
                -Command $openApi2Zig `
                -Arguments @("generate", "-i", $spec.FullName, "-o", $generatedFile) `
                -FailureMessage "Generation failed for '$relativeSpecPath'"

            New-CompileHarness -HarnessPath $compileHarness

            Invoke-NativeCommand `
                -Command $zig `
                -Arguments @("test", $compileHarness) `
                -FailureMessage "Compilation failed for '$relativeSpecPath'"

            Write-Host "PASS  $relativeSpecPath" -ForegroundColor Green
            $passedCount += 1
        } catch {
            Write-Host "FAIL  $relativeSpecPath" -ForegroundColor Red
            $failures.Add([pscustomobject]@{
                Spec = $relativeSpecPath
                Message = $_.Exception.Message
            })
        }

        Write-Host ""
    }

    Write-Host "Smoke tests completed: $passedCount passed, $($failures.Count) failed."
    if ($failures.Count -gt 0) {
        Write-Host ""
        Write-Host "Failing specifications:" -ForegroundColor Red
        foreach ($failure in $failures) {
            Write-Host "- $($failure.Spec): $($failure.Message)" -ForegroundColor Red
        }

        throw "Smoke tests failed for $($failures.Count) specification(s)."
    }
} finally {
    Pop-Location
}
