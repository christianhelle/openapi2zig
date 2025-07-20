
# Generate version information for openapi2zig
$gitTag = "unknown"
$gitCommit = "unknown"

try {
    $gitTag = git describe --tags --abbrev=0 2>$null
    if ($LASTEXITCODE -ne 0) { $gitTag = "unknown" }
} catch {
    $gitTag = "unknown"
}

try {
    $gitCommit = git rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { $gitCommit = "unknown" }
} catch {
    $gitCommit = "unknown"
}

$Version = ($gitTag).Replace('v', '')
$buildDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"

# Generate version_info.zig
$versionContent = @"
// This file is auto-generated at build time
pub const VERSION = "$Version";
pub const GIT_TAG = "$gitTag";
pub const GIT_COMMIT = "$gitCommit";
pub const BUILD_DATE = "$buildDate";
"@

$versionContent | Out-File -FilePath "src\version_info.zig" -Encoding UTF8

Write-Host "Generated version info:"
Write-Host "  Version: $Version"
Write-Host "  Git Tag: $gitTag"
Write-Host "  Git Commit: $gitCommit"
Write-Host "  Build Date: $buildDate"

# Generate Windows resource file for version information
if ($IsWindows -or $env:OS -match "Windows") {
    $versionParts = $Version.Split('.')
    $major = if ($versionParts.Length -gt 0) { $versionParts[0] } else { "1" }
    $minor = if ($versionParts.Length -gt 1) { $versionParts[1] } else { "0" }
    $patch = if ($versionParts.Length -gt 2) { $versionParts[2] } else { "0" }
    $build = "0"

    $rcContent = @"
#include <windows.h>

VS_VERSION_INFO VERSIONINFO
FILEVERSION $major,$minor,$patch,$build
PRODUCTVERSION $major,$minor,$patch,$build
FILEFLAGSMASK VS_FFI_FILEFLAGSMASK
FILEFLAGS 0x0L
FILEOS VOS__WINDOWS32
FILETYPE VFT_APP
FILESUBTYPE VFT2_UNKNOWN
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904b0"
        BEGIN
            VALUE "CompanyName", "Christian Helle"
            VALUE "FileDescription", "openapi2zig - OpenAPI to Zig code generator"
            VALUE "FileVersion", "$Version ($gitTag)"
            VALUE "InternalName", "openapi2zig"
            VALUE "OriginalFilename", "openapi2zig.exe"
            VALUE "ProductName", "openapi2zig"
            VALUE "ProductVersion", "$Version"
            VALUE "LegalCopyright", "Copyright (C) Christian Helle 2025"
        END
    END
    BLOCK "VarFileInfo"
    BEGIN
        VALUE "Translation", 0x409, 1200
    END
END
"@

    $rcContent | Out-File -FilePath "src\openapi2zig.rc" -Encoding UTF8
    Write-Host "Generated Windows resource file"
}
