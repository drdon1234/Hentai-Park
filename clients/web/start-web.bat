@echo off
setlocal
start "HentaiPark Web" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-web-windows.ps1"
exit /b %errorlevel%
