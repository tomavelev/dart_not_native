# Maestro CLI Installation Script for Windows
# Uses local Maestro installation from C:\Users\progr\dev\maestro\maestro\bin\maestro.bat

param(
    [string]$MaestroPath = "C:\Users\progr\dev\maestro\maestro\bin",
    [switch]$Force = $false
)

function Write-Header {
    param([string]$Message)
    Write-Host "`n$('='*60)" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "$('='*60)`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

Write-Header "Maestro CLI Configuration for Windows"

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error-Custom "This script requires administrator privileges."
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Success "Running with administrator privileges"

# Verify local installation exists
Write-Header "Verifying Local Installation"

if (-not (Test-Path "$MaestroPath\maestro.bat")) {
    Write-Error-Custom "Maestro not found at: $MaestroPath"
    Write-Host "Expected: $MaestroPath\maestro.bat" -ForegroundColor Yellow
    Write-Host "Please ensure Maestro is installed at: C:\Users\progr\dev\maestro\maestro\bin" -ForegroundColor Yellow
    exit 1
}

Write-Success "Found Maestro installation at: $MaestroPath"

# List what we found
$maestroFiles = Get-ChildItem -Path $MaestroPath -File | Select-Object -First 5
Write-Host "Files found:" -ForegroundColor Cyan
$maestroFiles | ForEach-Object { Write-Host "  - $($_.Name)" }

# Update PATH
Write-Header "Updating Environment PATH"

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

if ($currentPath -like "*$MaestroPath*") {
    Write-Success "PATH already contains Maestro bin directory"
}
else {
    Write-Host "Adding $MaestroPath to PATH..." -ForegroundColor Cyan
    try {
        $newPath = "$currentPath;$MaestroPath"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
        Write-Success "PATH updated successfully"
        Write-Host "You will need to restart your terminal for changes to take effect" -ForegroundColor Yellow
    }
    catch {
        Write-Error-Custom "Failed to update PATH: $_"
        exit 1
    }
}

# Verify installation
Write-Header "Verifying Installation"

# Update current session PATH
$env:PATH = "$env:PATH;$binPath"

try {
    $version = & maestro --version 2>&1
    Write-Success "Maestro installed successfully!"
    Write-Host "Version: $version" -ForegroundColor Green

    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1. Start your Flutter app (web or mobile)"
    Write-Host "2. Run Maestro flows:" -ForegroundColor Cyan
    Write-Host "   maestro web flows maestro/web/flows/" -ForegroundColor Yellow
    Write-Host "   maestro test maestro/mobile/flows/" -ForegroundColor Yellow
}
catch {
    Write-Error-Custom "Verification failed. Maestro may not be in PATH yet."
    Write-Host "Please restart PowerShell and run: maestro --version" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n" -ForegroundColor Green
Write-Success "Installation Complete! 🎉"
