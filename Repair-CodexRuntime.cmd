@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Repair-CodexRuntime.ps1" -Apply
echo.
pause
