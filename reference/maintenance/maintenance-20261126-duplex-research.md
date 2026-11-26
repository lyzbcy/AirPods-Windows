# 2026-11-26 · 高音质耳麦第一阶段

所有者确认重点攻关，范围独立于暂缓的降噪自研签名路线。实际系统 Win10 19045，微软原生 LE Audio 不支持。WPods 0.4.4 发布源码固定 usbip-win2 0.9.8.1 x64，固定 SHA256 与上游资产公开摘要一致；上游认证报告及 BSD-2-Clause 声明存在，WPods 为 GPL-3.0。未下载或执行任何安装器，不将摘要比对冒充实际驱动签名核验。

新增独立只读观察工具测试精确端点、会话活动前后及 mix format，无音频流初始化或操作。离线整套 33/656 通过，实机只读输出 2ch/44100Hz 与 1ch/8000Hz，两个会话均不活动；返回 insufficient_observation，不是立体声通话验收。公开资料和发布版本链接见 docs/14。主程序仍 1.9.50，未改变构建、安装、蓝牙或配对。

下一阶段依赖可控 Win11 试验环境或备用适配器、目标耳机及用户真机验收；不在现有日常 Windows 10 上冒险安装竞品或驱动。


后续只读复核：当前唯一在场 USB 蓝牙节点为 Generic Bluetooth Adapter（VID/PID 10D7:B012，Microsoft BTHUSB），不等于历史 Realtek 硬件。竞品公开 issue 和更新记录已纳入验收矩阵。官方固定资产直接下载超时，API 路线部分完成、续传未完成；认证报告链接同样超时，实际签名验证仍未完成。旧研究提交后已成功同步远端。未运行或安装任何第三方程序。


完整资产后续取得：官方固定版本经已配置公共镜像传输，26,083,632 字节与已知 SHA256 一致；Authenticode 验证状态 Valid、GlobalSign EV 签名链、时间戳存在。仅证明安装器签名；Inno Setup 7.0.0.3 内部驱动未提取，认证链接返回 HTML，CAT/SYS 与实机兼容性待验。未执行安装器。此前部分下载以非可执行后缀保存。


签名证据补齐：从维护者公开仓库按 Git blob ID 读取支持 Inno 7 的 Innounp 2.71.4；提取器无 Authenticode 签名，独立临时运行，仅提取六个指定文件，没有执行 USB/IP 安装器。usbip2_filter.cat/.sys 与 usbip2_ude.cat/.sys 真实四项 Authenticode Valid，签名者均 Microsoft Windows Hardware Compatibility Publisher，哈希见 docs/14。未安装、未加载驱动，未验证目录成员绑定、商业分发许可或硬件实测。无需再以“没有已签名驱动”解释停滞；需要有条件的实机通话验收。
