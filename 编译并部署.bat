@echo off
title AirPods小助手 - 编译并部署
cd /d %~dp0
taskkill /F /IM AirPodsBuddy.exe >nul 2>&1
timeout /t 1 /nobreak >nul
del /F dist\APB_new.exe >nul 2>&1
tools\ahk2exe_stable\Ahk2Exe.exe /silent /compress 0 /in airpods_buddy.ahk /out dist\APB_new.exe /base tools\ahk2exe_stable\AutoHotkey64.exe /icon assets\star_pudding.ico
if not exist dist\APB_new.exe (
  echo [X] 编译失败
  pause
  exit /b 1
)
move /Y dist\APB_new.exe dist\AirPodsBuddy.exe >nul
copy /Y dist\AirPodsBuddy.exe "C:\Users\24676\Desktop\AirPodsBuddy\AirPodsBuddy.exe" >nul
start "" "C:\Users\24676\Desktop\AirPodsBuddy\AirPodsBuddy.exe"
echo [OK] 编译并部署完成
timeout /t 4 >nul
