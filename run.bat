@echo off
rem AirPodsBuddy 开发/测试专用启动器（双击本文件即可）
rem 从仓库根目录分离启动已编译的 exe（直接 bash/cmd 调 Ahk2Exe 会静默失败，
rem 同理启动也用 Start-Process 分离，见 doc/05 坑 B1）
rem 重新编译请用 compile_autohotkey.ps1（在 Windows 上跑）

if not exist "%~dp0dist\AirPodsBuddy.exe" (
    echo [X] dist\AirPodsBuddy.exe 不存在，先在 Windows 上运行 compile_autohotkey.ps1 编译
    pause
    exit /b 1
)

start "" "%~dp0dist\AirPodsBuddy.exe"
echo [OK] 已启动，托盘找布丁图标。日志在 logs\ 目录。
timeout /t 2 >nul
