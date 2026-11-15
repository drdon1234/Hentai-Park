@echo off
setlocal
cd /d "%~dp0"
node scripts/check-env.mjs
if errorlevel 1 exit /b 1
node scripts/ensure-build.mjs
if errorlevel 1 exit /b 1
node scripts/source-index.mjs
exit /b %errorlevel%
