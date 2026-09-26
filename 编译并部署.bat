@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scriptsuild-deploy.ps1" -Deploy
exit /b %errorlevel%
