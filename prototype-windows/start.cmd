@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

rem UIPI guard: Explorer(Medium) -> WPF target must not be High.
rem If this script was launched from an elevated shell, relaunch it through Explorer.
whoami /groups | findstr /C:"S-1-16-12288" >nul 2>&1
if not errorlevel 1 (
  explorer.exe "%~f0"
  exit /b 0
)

where pwsh >nul 2>&1
if errorlevel 1 (
  echo.
  echo PowerShell 7이 필요합니다.
  echo Windows Terminal에서 다음 명령어로 설치할 수 있습니다:
  echo     winget install Microsoft.PowerShell
  echo.
  timeout /t 8 >nul
  exit /b 1
)

if exist "%~dp0app\core.ps1" (
  set "CORE=%~dp0app\core.ps1"
) else (
  set "CORE=%~dp0core.ps1"
)

pwsh -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File "%CORE%"
exit /b %errorlevel%
