#Requires -Version 5.1

<#
.SYNOPSIS
    openapi2zig - Installation Script for Windows

.DESCRIPTION
    This script downloads and installs the latest release of openapi2zig for Windows.

.PARAMETER InstallDir
    The directory to install openapi2zig to. Defaults to a directory in the user's PATH.

.PARAMETER AddToPath
    Whether to add the installation directory to the user's PATH. Default is $true.

.PARAMETER Force
    Force installation even if openapi2zig is already installed.

.EXAMPLE
    # Install using default settings
    irm https://christianhelle.com/openapi2zig/install.ps1 | iex

.EXAMPLE
    # Install to a specific directory
    irm https://christianhelle.com/openapi2zig/install.ps1 | iex -InstallDir "C:\Tools"

.EXAMPLE
    # Install without adding to PATH
    irm https://christianhelle.com/openapi2zig/install.ps1 | iex -AddToPath $false
#>

param(
  [string]$InstallDir = "",
  [bool]$AddToPath = $true,
  [switch]$Force,
  [switch]$Help
)

# Configuration
$GitHubRepo = "christianhelle/openapi2zig"
$BinaryName = "openapi2zig.exe"
$ArchiveName = "openapi2zig-windows-x86_64.zip"

# Function to write colored output
function Write-ColorOutput
{
  param(
    [string]$Message,
    [string]$Color = "White",
    [string]$Emoji = ""
  )
    
  if ($Emoji)
  {
    Write-Host "$Emoji " -NoNewline
  }
  Write-Host $Message -ForegroundColor $Color
}

function Write-Info
{
  param([string]$Message)
  Write-ColorOutput -Message $Message -Color "Cyan" -Emoji "ℹ️"
}

function Write-Success
{
  param([string]$Message)
  Write-ColorOutput -Message $Message -Color "Green" -Emoji "✅"
}

function Write-Warning
{
  param([string]$Message)
  Write-ColorOutput -Message $Message -Color "Yellow" -Emoji "⚠️"
}

function Write-Error
{
  param([string]$Message)
  Write-ColorOutput -Message $Message -Color "Red" -Emoji "❌"
}

function Show-Usage
{
  Write-Host ""
  Write-Host "openapi2zig installation script for windows" -ForegroundColor "Blue"
  Write-Host ""
  Write-Host "Usage:" -ForegroundColor "Yellow"
  Write-Host "  irm https://christianhelle.com/openapi2zig/install.ps1 | iex" -ForegroundColor "White"
  Write-Host ""
  Write-Host "Parameters:" -ForegroundColor "Yellow"
  Write-Host "  -InstallDir <path>   Installation directory" -ForegroundColor "White"
  Write-Host "  -AddToPath <bool>    Add to PATH (default: true)" -ForegroundColor "White"
  Write-Host "  -Force              Force installation" -ForegroundColor "White"
  Write-Host "  -Help               Show this help" -ForegroundColor "White"
  Write-Host ""
  Write-Host "Examples:" -ForegroundColor "Yellow"
  Write-Host "  # Default installation" -ForegroundColor "Gray"
  Write-Host "  irm https://christianhelle.com/openapi2zig/install.ps1 | iex" -ForegroundColor "White"
  Write-Host ""
  Write-Host "  # Custom directory" -ForegroundColor "Gray"
  Write-Host "  irm https://christianhelle.com/openapi2zig/install.ps1 | iex -InstallDir 'C:\Tools'" -ForegroundColor "White"
  Write-Host ""
}

function Get-DefaultInstallDir
{
  # Try to find a good default installation directory
  $candidates = @(
    "$env:LOCALAPPDATA\Programs\openapi2zig",
    "$env:USERPROFILE\.local\bin",
    "$env:USERPROFILE\bin"
  )
    
  foreach ($candidate in $candidates)
  {
    if (Test-Path $candidate -PathType Container)
    {
      return $candidate
    }
  }
    
  # Default to LOCALAPPDATA\Programs\openapi2zig
  return "$env:LOCALAPPDATA\Programs\openapi2zig"
}

function Test-IsInPath
{
  param([string]$Directory)
    
  $pathDirs = $env:PATH -split ';' | ForEach-Object { $_.Trim('"').TrimEnd('\') }
  $targetDir = $Directory.TrimEnd('\')
    
  return $pathDirs -contains $targetDir
}

function Add-ToUserPath
{
  param([string]$Directory)
    
  if (Test-IsInPath -Directory $Directory)
  {
    Write-Info "Directory already in PATH: $Directory"
    return
  }
    
  try
  {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $userPath.EndsWith(';'))
    {
      $userPath += ';'
    }
    $newPath = $userPath + $Directory
        
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        
    # Update current session PATH
    $env:PATH += ";$Directory"
        
    Write-Success "Added to user PATH: $Directory"
    Write-Warning "Restart your terminal for PATH changes to take effect"
  } catch
  {
    Write-Error "Failed to add directory to PATH: $($_.Exception.Message)"
    Write-Info "You can manually add '$Directory' to your PATH"
  }
}

function Get-LatestRelease
{
  Write-Info "Fetching latest release information..."
    
  try
  {
    $apiUrl = "https://api.github.com/repos/$GitHubRepo/releases/latest"
    $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
    return $response.tag_name
  } catch
  {
    Write-Error "Failed to fetch release information: $($_.Exception.Message)"
    throw
  }
}

function Test-openapi2zigInstalled
{
  try
  {
    $version = & openapi2zig --version 2>$null
    if ($LASTEXITCODE -eq 0)
    {
      return $version
    }
  } catch
  {
    # Command not found or error
  }
  return $null
}

function Install-openapi2zig
{
  param(
    [string]$Version,
    [string]$TargetDir
  )
    
  $downloadUrl = "https://github.com/$GitHubRepo/releases/download/$Version/$ArchiveName"
  $tempDir = Join-Path $env:TEMP "openapi2zig-install-$(Get-Random)"
  $archivePath = Join-Path $tempDir $ArchiveName
    
  try
  {
    # Create temporary directory
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
    Write-Info "Downloading openapi2zig $Version..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -ErrorAction Stop
        
    Write-Info "Extracting archive..."
    Expand-Archive -Path $archivePath -DestinationPath $tempDir -Force
        
    # Create target directory if it doesn't exist
    if (-not (Test-Path $TargetDir))
    {
      Write-Info "Creating installation directory: $TargetDir"
      New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }
        
    Write-Info "Installing to $TargetDir..."
    $sourceBinary = Join-Path $tempDir $BinaryName
    $targetBinary = Join-Path $TargetDir $BinaryName
        
    if (-not (Test-Path $sourceBinary))
    {
      throw "Binary not found in archive: $BinaryName"
    }
        
    Copy-Item -Path $sourceBinary -Destination $targetBinary -Force
        
    Write-Success "openapi2zig $Version installed successfully!"
        
    return $targetBinary
  } catch
  {
    Write-Error "Installation failed: $($_.Exception.Message)"
    throw
  } finally
  {
    # Cleanup
    if (Test-Path $tempDir)
    {
      Remove-Item -Path $tempDir -Recurse -Force
    }
  }
}

function Test-Installation
{
  param([string]$BinaryPath)
    
  try
  {
    $version = & $BinaryPath --version 2>$null
    if ($LASTEXITCODE -eq 0)
    {
      Write-Success "Installation verified: $version"
      Write-Info "You can now run: openapi2zig --help"
      return $true
    }
  } catch
  {
    # Ignore
  }
    
  Write-Warning "Could not verify installation"
  return $false
}

function Main
{
  if ($Help)
  {
    Show-Usage
    return
  }
    
  Write-Info "Starting openapi2zig installation for Windows..."
    
  # Check if already installed
  if (-not $Force)
  {
    $existingVersion = Test-openapi2zigInstalled
    if ($existingVersion)
    {
      Write-Warning "openapi2zig is already installed: $existingVersion"
      Write-Info "Use -Force to reinstall"
      return
    }
  }
    
  # Determine installation directory
  if (-not $InstallDir)
  {
    $InstallDir = Get-DefaultInstallDir
  }
    
  Write-Info "Target directory: $InstallDir"
    
  try
  {
    # Get latest release
    $version = Get-LatestRelease
    Write-Info "Latest version: $version"
        
    # Install
    $binaryPath = Install-openapi2zig -Version $version -TargetDir $InstallDir
        
    # Add to PATH if requested
    if ($AddToPath)
    {
      Add-ToUserPath -Directory $InstallDir
    }
        
    # Verify installation
    Test-Installation -BinaryPath $binaryPath
        
    Write-Host ""
    Write-Success "🎉 Installation complete!"
    Write-Info "Get started with: openapi2zig --help"
    Write-Info "Documentation: https://christianhelle.com/openapi2zig/"
        
    if ($AddToPath)
    {
      Write-Host ""
      Write-Warning "Note: You may need to restart your terminal for PATH changes to take effect"
    }
  } catch
  {
    Write-Error "Installation failed: $($_.Exception.Message)"
    exit 1
  }
}

# Run main function
Main
