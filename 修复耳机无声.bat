@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix_headphone_no_sound.ps1" %*
exit /b %errorlevel%
