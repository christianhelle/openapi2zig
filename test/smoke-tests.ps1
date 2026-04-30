param (
    [Parameter(Mandatory=$false)]
    [switch]
    $UseInstalled = $false,

    [Parameter(Mandatory=$false)]
    [switch]
    $IncludeYaml = $false,

    [Parameter(Mandatory=$false)]
    [string]
    $OutputRoot = "./.zig-cache/smoke-tests"
)

$ErrorActionPreference = "Stop"

function Invoke-NativeCommand {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $FilePath,

        [Parameter(Mandatory=$false)]
        [string[]]
        $Arguments = @(),

        [Parameter(Mandatory=$false)]
        [string]
        $FailureMessage = "Native command failed"
    )

    if (-not (Get-Command $FilePath -ErrorAction SilentlyContinue)) {
        throw "$FailureMessage. Command not found: $FilePath"
    }

    Write-Host "> $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code: $LASTEXITCODE)"
    }
}

function Test-IsOpenApiExampleSpec {
    param (
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]
        $File,

        [Parameter(Mandatory=$true)]
        [string[]]
        $Extensions
    )

    # The json-schema folder contains reference schemas, not API examples that openapi2zig can generate clients from.
    $normalizedPath = $File.FullName.Replace('\', '/')
    return $Extensions -contains $File.Extension.ToLowerInvariant() -and
        $normalizedPath -notlike "*/json-schema/*"
}

function Get-OpenApiSpecs {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $OpenApiRoot,

        [Parameter(Mandatory=$true)]
        [bool]
        $IncludeYamlSpecs
    )

    $extensions = @(".json")
    if ($IncludeYamlSpecs) {
        $extensions += @(".yaml", ".yml")
    }

    Get-ChildItem -Path $OpenApiRoot -Recurse -File |
        Where-Object { Test-IsOpenApiExampleSpec -File $_ -Extensions $extensions } |
        Sort-Object FullName
}

function Get-SafeName {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Value
    )

    return ($Value -replace '[^A-Za-z0-9_]', '_')
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$openApiRoot = Join-Path $repoRoot "openapi"
$outputRootPath = Join-Path $repoRoot $OutputRoot

if (-not (Test-Path -Path $openApiRoot -PathType Container)) {
    throw "OpenAPI examples directory not found: $openApiRoot"
}

Push-Location $repoRoot
try {
    Invoke-NativeCommand -FilePath "zig" -Arguments @("version") -FailureMessage "Zig is required to run smoke tests"

    $openapi2zig = "openapi2zig"
    if (-not $UseInstalled) {
        Write-Host "`n=== Building openapi2zig ===`n"
        Write-Host "Initial Zig builds can take 2-5 minutes, and generated code compilation across all specs can take several more minutes; do not cancel these steps."
        Invoke-NativeCommand -FilePath "zig" -Arguments @("build", "-Doptimize=Debug") -FailureMessage "Failed to build openapi2zig"

        $isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
        $binaryName = if ($isWindowsPlatform) { "openapi2zig.exe" } else { "openapi2zig" }
        $openapi2zig = Join-Path $repoRoot (Join-Path "zig-out/bin" $binaryName)
        if (-not (Test-Path -Path $openapi2zig -PathType Leaf)) {
            throw "Built openapi2zig binary not found: $openapi2zig"
        }
    }

    if (Test-Path -Path $outputRootPath) {
        Remove-Item -Path $outputRootPath -Recurse -Force
    }
    New-Item -Path $outputRootPath -ItemType Directory -Force | Out-Null

    $allSpecs = @(Get-OpenApiSpecs -OpenApiRoot $openApiRoot -IncludeYamlSpecs $true)
    $specs = if ($IncludeYaml) {
        $allSpecs
    } else {
        @($allSpecs | Where-Object { $_.Extension.ToLowerInvariant() -eq ".json" })
    }
    if ($specs.Count -eq 0) {
        throw "No OpenAPI specification examples found under $openApiRoot"
    }

    if (-not $IncludeYaml) {
        $yamlCount = @($allSpecs | Where-Object { $_.Extension.ToLowerInvariant() -in @(".yaml", ".yml") }).Count
        if ($yamlCount -gt 0) {
            Write-Host "Skipping $yamlCount YAML specs because YAML input has not been implemented by openapi2zig yet. Use -IncludeYaml to verify YAML support when it is available."
        }
    }

    Write-Host "`n=== Smoke testing $($specs.Count) OpenAPI specification examples ===`n"
    Write-Host "Generated code compilation runs once per specification and can take several minutes across the full suite; CI allows up to 15 minutes for this job."

    for ($i = 0; $i -lt $specs.Count; $i++) {
        $spec = $specs[$i]
        $relativeSpec = [System.IO.Path]::GetRelativePath($repoRoot, $spec.FullName)
        $safeName = Get-SafeName -Value ([System.IO.Path]::ChangeExtension($relativeSpec, $null))
        $caseOutputRoot = Join-Path $outputRootPath $safeName
        $generatedFile = Join-Path $caseOutputRoot "client.zig"
        $compileFile = Join-Path $caseOutputRoot "compile.zig"

        New-Item -Path $caseOutputRoot -ItemType Directory -Force | Out-Null

        Write-Host "`n[$($i + 1)/$($specs.Count)] Generating $relativeSpec"
        Invoke-NativeCommand `
            -FilePath $openapi2zig `
            -Arguments @("generate", "-i", $spec.FullName, "-o", $generatedFile) `
            -FailureMessage "Generation failed for $relativeSpec"

        @'
const std = @import("std");
const generated = @import("client.zig");

test "generated client compiles" {
    std.testing.refAllDecls(generated);
}
'@ | Set-Content -Path $compileFile -Encoding utf8NoBOM

        Write-Host "[$($i + 1)/$($specs.Count)] Compiling generated Zig for $relativeSpec"
        Invoke-NativeCommand `
            -FilePath "zig" `
            -Arguments @("test", $compileFile) `
            -FailureMessage "Generated Zig failed to compile for $relativeSpec"
    }

    Write-Host "`nSmoke tests passed for $($specs.Count) OpenAPI specification examples."
}
finally {
    Pop-Location
}
