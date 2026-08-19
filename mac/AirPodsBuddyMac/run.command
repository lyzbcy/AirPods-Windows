#!/bin/bash
# AirPodsBuddyMac 开发/测试专用启动器（双击本文件即可）
# 流程：自动编译（如有源码变动）→ 后台启动菜单栏 app → 自动关掉终端窗口
# 日志：~/Library/Logs/AirPodsBuddyMac.log（出错看这里，不会弹窗打扰）

cd "$(dirname "$0")" || exit 1

echo "[1/2] 编译（增量，几秒）..."
swift build -c release
if [ $? -ne 0 ]; then
    echo ""
    echo "❌ 编译失败，错误信息在上面。把这段截图发给 AI 修。"
    echo "窗口保留，按任意键关闭..."
    read -n 1 -s
    exit 1
fi

echo "[2/2] 启动 AirPodsBuddyMac（菜单栏找 🎧/💤 图标）..."
nohup .build/release/AirPodsBuddyMac >/dev/null 2>&1 &

# 稍等确认进程活着
sleep 1
if pgrep -f "AirPodsBuddyMac$" >/dev/null; then
    echo "✅ 已启动。日志在 ~/Library/Logs/AirPodsBuddyMac.log"
else
    echo "⚠️ 进程没起来，看日志：tail -20 ~/Library/Logs/AirPodsBuddyMac.log"
    echo "窗口保留，按任意键关闭..."
    read -n 1 -s
    exit 1
fi
exit 0
