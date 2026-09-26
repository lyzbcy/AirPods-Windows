# 09 · Windows 优先：蓝牙连接方案选型

现状：KS 后端已接入 v1.9.20 候选并真机执行；连续重连尚未通过，原始失败证据保留。
负责人：当前维护 Agent。
最后更新：2026-09-26。

## 结论

第一优先级是 Windows 用户稳定、可预期、少打扰的体验，而非自研代码量或测试次数。复用已有方案必须看源码、API 语义和已知问题。**v1.9.20 已采用音频驱动 KS 单次连接/断开请求，替代日常路径中反复启停蓝牙服务；硬件稳定性按下方真实结果单独验收。**

当前 1.9.19 保留已通过的默认设备读回、后台截止、回滚、界面刷新等修复。当前重连不稳定仍为 P0；不把单次有声、96 项回归或 GitHub 项目自述当作连续重连通过。

## 1. 关键事实：现在操作的不是单纯连接开关

微软明确说明 `BluetoothSetServiceState` 启用服务会安装对应驱动，禁用服务会移除对应驱动；`E_INVALIDARG` 可以表示目标服务已经处于请求状态，而 `ERROR_INVALID_PARAMETER` 表示标志参数无效，两者文档语义不同。

旧 v1.9.19 `scripts/background-worker.ps1` 70–95 行的通用重试把两种错误放在同一分支，并通过相反状态再重试；连接前还先关闭 HFP/A2DP。上游 AHK 也沿用服务切换。这能解释该路线为什么涉及比“连接”更多的系统状态变化，**但不是本机掉线根因已被证明**。

来源：[Microsoft BluetoothSetServiceState](https://learn.microsoft.com/en-us/windows/win32/api/bluetoothapis/nf-bluetoothapis-bluetoothsetservicestate)。

## 2. 已核对的开源实现

| 项目 / 固定提交 | 源码位置及做法 | 采纳与保留意见 |
|---|---|---|
| ToothTray / `0d1a7eef82b4c9e69ed6b931ec07e6c760703434` | `BluetoothAudioDevices.cpp` 22–29、39、77–124、136–147：ContainerId 分组；枚举音频端点；沿 DeviceTopology 找 IKsControl；发 KS 请求 | 主要参考连接机制和物理设备分组；该版本只枚举 eRender，不能原样当完整断开方案 |
| BTAudioSysTrayTool / `5d423cfb16c3a59011f52c2ad7b3833c1708e622` | `BluetoothManager.cs` 71–96、117–148、160–208：BASICSUPPORT 探测；端点拓扑；单次 KS 请求 | 参考能力探测和COM资源释放；其62行按清理后的名字合并设备，不适合直接用于同名多耳机 |
| BluetoothDeviceConnector / `907d0ac428600a30f3e450a1fa3c1b78ae048030` | `bluetooth_device_connector.ahk` 159 行依然调用 BluetoothSetServiceState；`audio_endpoint_router.cpp` 使用 ACTIVE 端点与默认输出切换 | 已有默认输出能力继续复用；仅升级这个上游不会自动获得不同的连接机制 |

固定源码链接：
- [ToothTray C++](https://github.com/m2jean/ToothTray/blob/0d1a7eef82b4c9e69ed6b931ec07e6c760703434/ToothTray/BluetoothAudioDevices.cpp)
- [BTAudioSysTrayTool C#](https://github.com/jeremyleff/BTAudioSysTrayTool/blob/5d423cfb16c3a59011f52c2ad7b3833c1708e622/BluetoothManager.cs)
- [上游 AHK](https://github.com/ChromuSx/BluetoothDeviceConnector/blob/907d0ac428600a30f3e450a1fa3c1b78ae048030/bluetooth_device_connector.ahk)

ToothTray 的 [issue #10](https://github.com/m2jean/ToothTray/issues/10) 报告过断开播放后麦克风仍连接。它提示实现必须覆盖同一物理设备的播放/录音端点，而非只照抄单个 render 的处理。BTAudio 项目作者记录过服务切换/RFCOMM 路线失败，这是作者环境观察，不是所有 Windows 驱动的结论。

许可证元数据：ToothTray BSD-2-Clause；BTAudioSysTrayTool、上游 BluetoothDeviceConnector MIT。若后续复制代码，随代码保留原始版权和许可文件；v1.9.20 的 C# 互操作改编保留 MIT 原文与版权，随 THIRD_PARTY_NOTICES.md 内嵌分发；未打包第三方二进制。

## 3. 选定的候选机制及边界

`IMMDevice → IDeviceTopology → 对端连接器/IPart → 驱动拓扑设备 → IKsControl`。

- 先以 `KSPROPERTY_TYPE_BASICSUPPORT` 查询支持情况；实际单次请求为 `KSPROPERTY_TYPE_GET`，值缓冲区为空。
- 连接使用 `KSPROPERTY_ONESHOT_RECONNECT`；断开使用 `KSPROPERTY_ONESHOT_DISCONNECT`。
- 微软同时明确：请求成功仅表示驱动尝试了操作，不等于连接/断开成功。因此现有异步真实状态核实仍应保留。
- 此路径不调用服务安装/移除接口；仍然属于驱动操作，兼容性和实际影响需由隔离候选验证，不能承诺所有 Windows 机器都正常。

官方依据：[连接请求](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/ksproperty-oneshot-reconnect)、[断开请求](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/ksproperty-oneshot-disconnect)。

## 4. 按 Windows 体验排序的落地步骤

1. **只读探测先行**：绑定 Bluetooth 地址与 ContainerId，枚举 ACTIVE/UNPLUGGED 的目标端点与拓扑；输出能力报告。名称仅显示，不作为唯一身份；不要启用用户手动禁用的端点。
2. **独立候选后端**：沿用现有后台任务/超时架构，接口收地址、动作和明确偏好；每目标只提交有界请求。能力不足或端点缺失时如实给出原因，不偷偷启停服务、无线电、PnP节点或删除配对。
3. **分开处理三件事**：连接目标设备、确认可播放、按用户偏好切默认输出。只有目标 ACTIVE 后才设默认并逐角色读回；设备已就绪时复用现有连接，避免无谓断开重连。
4. **断开完整但不扩大影响**：仅覆盖目标 ContainerId 的实际关联端点，含需要断开的录音端点；不操作其他耳机、蓝牙键鼠或全局服务。保留用户当前麦克风偏好，迁移语义前明确说明。
5. **先离线回归，再集中一次真机验收**：失败/超时/同名设备/不支持KS/半连接/用户变更默认输出先故障注入。然后约定一批真实测试，不在每个猜测后反复要求用户摘戴、关手机蓝牙。
6. **通过再替换、最后才发布**：候选和现安装版分离；记录构建输入与原始备份；通过后才切换。Release 仍走既有用户确认流程。

## 5. 验收门槛

- 正常操作不调用 BluetoothSetServiceState、radio reset、PnP禁用或删配对；不增加管理员弹窗。
- 同名设备、其他耳机、蓝牙键鼠、未授权更改的麦克风/默认角色保持不变。
- 一轮请求结束后 busy 正确释放；界面保持响应并反映真实状态，失效状态及时更新。
- 操作前后记录目标 ContainerId、render/capture端点、请求HRESULT、ACTIVE变化、三角色默认读回、耗时；不上传无关信息。
- 连续5轮连接/断开与应用重启后复连通过；至少一次默认路径听音由用户确认。API成功、CI成功都不单独作为通过标准。
- 候选失败保留原程序和诊断；不为了让单次测试通过而升级到影响整个Windows的恢复动作。

## 6. v1.9.20 实现与实测

已完成：精确地址→ContainerId→端点绑定、能力预检、filter 去重、同目标 render/capture 断开、禁用状态保护、ACTIVE 事务尾部复核、后台任务接入、打包与版权。离线 10 套回归 165 项通过（最终数量以 VERIFICATION.txt 为准）。

真实过程不合并成虚构的通过结果：
- 首次 KS 连接成功：link=1、目标 ACTIVE、三个默认输出角色读回一致。
- 第一批连续测试第 2 轮断开失败：UNPLUGGED 被当作已经断开，requested=0 但 link=1。已修为仍向该目标 filter 发一次断开，修后真实结果 requested=1、link=0。
- 修后重新开始：第 1 轮连接/断开均通过，第 2 轮连接请求已接受，但到核实截止 link=0；停止该批，保留 `five-cycles-verified.json`（文件名不是通过断言）。稍后只读复查仍未连接。
- 同一个 render ID 在本轮测试保持不变；麦克风默认角色与非目标耳机状态保持不变。没有整机重置、PnP 禁用或删除配对。

因此 KS 方案消除了旧服务卸装路径，但五轮稳定性和本候选最终听音尚未闭环。不能用离线通过覆盖硬件失败。证据入口：`verification/2026-09-26-ks/VERIFICATION.txt`。

## 7. 最终候选验收（本段优先于过程记录）

链路/音频共用一次15秒延迟重试、可取消状态和进行中取消后真实断开排队均已实现。最新严格测试第1轮含7秒后复查通过，第2轮在一次音频重试后仍 audio_failed（link=1），exit5。早前15秒间隔的5轮只证明10次瞬时采样通过，其中第3轮开始前已发现上一轮路由失活。

165项离线回归、编译与隔离源副本回滚通过。当前已打包候选，**未替换常驻v1.9.19、未发布Release**。最后只读时端点已恢复ACTIVE和三角色默认值，不据此改写失败或推断根因。后续应对同一时间轴的原生Windows状态/驱动事件/应用状态取证，先解释迟到就绪与失活，不增加全局恢复动作。

## 8. 其他设备蓝牙关闭后的对照

用户确认测试期间暂时关闭附近已配对手机/Mac蓝牙。严格方案要求每轮连接后7秒重新核实链路/ACTIVE/三个默认播放角色，另隔15秒再次只读核实；断开后亦隔15秒核实 link=0 与目标端点UNPLUGGED。第1轮全过，第2轮断开全过，重连经唯一一次延迟KS请求后仍 `link_failed link=0`、exit5，后续轮次停止。由此“只要关闭其他设备蓝牙就稳定”没有成立。本轮没有全局无线电重置、配对删除或驱动卸装。公开发版条件仍不满足。

## 9. 同一时钟的 P0 取证（2026-09-26）

旧严格复测只保存请求次数和最终链路/端点状态，没有每条请求的原始 HRESULT、时间或失败前后连续状态，不能判断是哪一层先变化。候选 `KsBluetooth.cs` 的 `KsTrace` 现在记录 `beforeUtcFiletime,afterUtcFiletime,property,endpointId,HRESULT`（分号分隔多次请求），经 worker 结果进入应用日志；请求异常同样记录 HRESULT 并停止该事务。单次请求策略未变。`python tests/p0_timeline.py --address <12位地址> --seconds 90` 只读采样，同一个 Windows FILETIME 时钟记录链路位、精确播放端点状态、三个默认输出角色，结束时快照目标 PnP 状态和现有 System 蓝牙/音频事件；不存在的事件记0，不启用禁用的通道。显式 `--action connect` 触发一次源码连接；`--action cycle` 执行最多一轮断开→连接，第一步失败则停止。首次3秒只读试跑目标是 link=1、端点 ACTIVE、三个角色一致、目标 PnP OK、System 匹配事件0。紧接的单轮对照在断开步已复现旧窗口假失败：KS 请求 `0x00000000` 于14:56:19.761 UTC返回，端点在14:56:29.098变UNPLUGGED且默认角色回到非耳机，链路在14:56:43.895才down（KS返回后约24.1秒）。旧核实约9秒即报失败；这轮没有执行重连。候选把断开核实延至约30秒，只等待真实链路而不增加请求。连续五轮/听音、麦克风偏好迁移和安装版验收仍是独立的发版前条件。

注意采样盲区：旧窗口复现时两个样本间有17.60秒空窗，因此14:56:29.098只是首次看见UNPLUGGED，不是精确变化时刻。新26次窗口已做一轮真机对照：源码断开和重连均过，重连7秒后路由保持，末态 link=1/目标ACTIVE/三角色目标；但该轮采样存在51.27秒空窗，不能当连续时序证明。候选补了链路未知态及目标端点非ACTIVE核实，采样器补每个读取耗时/最大空窗并传递子操作失败码。181项/12套离线通过，仅一轮真机，不满足五轮、普通听音与micOff迁移门槛。
