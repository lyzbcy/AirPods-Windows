@echo off
title AirPods小助手
cd /d %~dp0
if not exist "tools\ahk2exe_stable\AutoHotkey64.exe" (
  echo [X] 缺少 tools\ahk2exe_stable\AutoHotkey64.exe
  pause
  exit /b 1
)
taskkill /F /IM AutoHotkey64.exe >nul 2>&1
taskkill /F /IM AirPodsBuddy.exe >nul 2>&1
start "" "%~dp0tools\ahk2exe_stable\AutoHotkey64.exe" airpods_buddy.ahk
echo [OK] AirPods小助手 已启动（此窗口几秒后自动关闭）
timeout /t 3 >nul
