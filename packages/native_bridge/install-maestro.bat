@echo off
REM Maestro CLI Configuration Script for Windows (Batch version)
REM Uses local Maestro installation from C:\Users\progr\dev\maestro\maestro\bin

setlocal enabledelayedexpansion

echo.
echo ============================================================
echo Maestro CLI Configuration for Windows
echo ============================================================
echo.

REM Check if running as admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: This script requires administrator privileges.
    echo Please run as Administrator and try again.
    pause
    exit /b 1
)

echo [OK] Running with administrator privileges
echo.

REM Configuration
set MAESTRO_PATH=C:\Users\progr\dev\maestro\maestro\bin

echo Maestro location: %MAESTRO_PATH%
echo.

REM Verify installation exists
echo ============================================================
echo Verifying Local Installation
echo ============================================================
echo.

if not exist "%MAESTRO_PATH%\maestro.bat" (
    echo Error: Maestro not found at: %MAESTRO_PATH%
    echo Please ensure Maestro is installed at: C:\Users\progr\dev\maestro\maestro\bin
    pause
    exit /b 1
)

echo [OK] Found Maestro installation
echo     %MAESTRO_PATH%\maestro.bat
echo.

REM Update PATH
echo ============================================================
echo Updating Environment PATH
echo ============================================================
echo.

echo Adding %MAESTRO_PATH% to PATH...
setx PATH "%PATH%;%MAESTRO_PATH%"

if errorlevel 1 (
    echo Warning: Failed to update PATH. Please add manually:
    echo %MAESTRO_PATH%
) else (
    echo [OK] PATH updated successfully
    echo Note: Restart your terminal for changes to take effect
)

echo.
echo ============================================================
echo Configuration Complete!
echo ============================================================
echo.
echo Next steps:
echo 1. Close and restart PowerShell/Command Prompt
echo 2. Run: maestro --version
echo 3. Run your tests:
echo    maestro web flows maestro/web/flows/
echo    maestro test maestro/mobile/flows/
echo.

pause
