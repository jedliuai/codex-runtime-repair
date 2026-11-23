@echo off
rem Codex repair toolbox (GUI). Asks for administrator rights so the login fix can pause / resume WinNAT.
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0scripts\CodexRepairToolbox.ps1"
