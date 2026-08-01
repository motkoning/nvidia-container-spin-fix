@echo off
rem NVIDIA Container CPU Fix - double-click launcher
rem https://github.com/motkoning/nvidia-container-spin-fix
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0NvidiaFixTool.ps1"
