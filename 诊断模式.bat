@echo off
title AirPods小助手 - 诊断模式
cd /d %~dp0
set LOG=%~dp0diag_result.txt
echo === %date% %time% === > %LOG%
echo [1] cd=%CD% >> %LOG%
if exist "tools\ahk2exe_stable\AutoHotkey64.exe" (echo [2] AHK解释器 OK>>%LOG%) else echo [2] AHK解释器 缺失>>%LOG%
if exist "airpods_buddy.ahk" (echo [3] 脚本 OK>>%LOG%) else echo [3] 脚本 缺失>>%LOG%
taskkill /F /IM AutoHotkey64.exe >nul 2>&1
taskkill /F /IM AirPodsBuddy.exe >nul 2>&1
echo [4] 前台启动解释器（应用窗口应出现；此控制台会一直开着=应用在跑）>> %LOG%
echo [4] 正在启动，请看应用窗口是否出现...（应用运行期间本窗口保持打开属正常）
"tools\ahk2exe_stable\AutoHotkey64.exe" /ErrorStdOut "airpods_buddy.ahk" >> "%LOG%" 2>&1
echo [5] 解释器已退出 code=%ERRORLEVEL% >> %LOG%
echo.
echo === 诊断完成，结果已写入 diag_result.txt ===
echo 完整启动日志见 logs 文件夹最新一份
pause
