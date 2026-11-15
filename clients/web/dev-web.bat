@echo off
setlocal
cd /d "%~dp0"
node scripts/check-env.mjs
if errorlevel 1 exit /b 1
call pnpm build
if errorlevel 1 exit /b 1
node --env-file-if-exists=.env scripts/dev-web.mjs
exit /b %errorlevel%
