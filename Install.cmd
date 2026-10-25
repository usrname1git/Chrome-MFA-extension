@echo off
setlocal
title Autom8ed Vault installer
cd /d "%~dp0"
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Autom8edVault.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Autom8edVault.ps1" %*
)
set "INSTALL_EXIT=%ERRORLEVEL%"
echo.
if not "%INSTALL_EXIT%"=="0" echo Setup did not complete. Review the error above.
pause
exit /b %INSTALL_EXIT%
