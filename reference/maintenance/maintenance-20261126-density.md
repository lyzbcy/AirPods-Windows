# 2026-11-26 · 1.9.46 & beta.3

现状：主程序及独立实验室均已本机安装，未公开 ｜ 负责人：项目维护者 ｜ 最后更新时间：2026-11-26

用户指出正文贴圆角、状态密度不足、美化菜单无效、实验室样式与能力边界不清。根因：统一大半径没有相应内缩，状态行纯左右平铺；旧第二 WebView 返回 0x80070057；Beta 是独立协议实验工具而非真机实现。

1.9.46 使用同心曲率、正文安全内距与换行、图标/微标题/真实状态三层卡片，原生主题托盘替换第二 WebView。31 套 625 项通过，长文字浏览器几何和滚动检查通过，实际日志记录三次 native popup shown。已安装哈希 2709C3579AE758F68B2C362BEDECAFE296E3D4FD9DE8F5574D5BBCDA63BCAB00。未主动操作连接。

Beta.3 双栏、主题选择器/按钮/滑杆/开关与首屏驱动限制，协议和会话代码未改。3115 项离线、已安装隐藏窗口 UI smoke：layoutContained=true，hardwareOpened=false，interfaces=0，modeButtonsEnabled=0。EXE SHA256 B30526B806436BE4A73BBB7367CBD290FB040F788A2ADBCA193D0429BE8E5EE9，原 beta.2 EXE 备份哈希匹配；五个伴随 DLL 与安装版一致。没有安装驱动、降低系统防护或开启控制通道。见 [Beta 合成截图](../design/beta-3-fixture.png)、[状态卡片合成截图](../design/status-card-1946-fixture.png)。

实际用户对整套视觉最终验收仍待确认。
