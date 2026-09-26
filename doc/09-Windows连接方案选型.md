# 09 · Windows 优先：蓝牙连接方案选型

现状：源码调研完成；KS 候选尚未接入或真机执行，现用程序未替换。
负责人：当前维护 Agent。
最后更新：2026-09-26。

## 结论

第一优先级是 Windows 用户稳定、可预期、少打扰的体验，而非自研代码量或测试次数。复用已有方案必须看源码、API 语义和已知问题。**下一候选采用音频驱动的 KS 单次连接/断开请求，替代日常路径中反复启停蓝牙服务；本轮只完成选型，不宣称稳定性问题已解决。**

当前 1.9.19 保留已通过的默认设备读回、后台截止、回滚、界面刷新等修复。当前重连不稳定仍为 P0；不把单次有声、96 项回归或 GitHub 项目自述当作连续重连通过。

## 1. 关键事实：现在操作的不是单纯连接开关

微软明确说明 `BluetoothSetServiceState` 启用服务会安装对应驱动，禁用服务会移除对应驱动；`E_INVALIDARG` 可以表示目标服务已经处于请求状态，而 `ERROR_INVALID_PARAMETER` 表示标志参数无效，两者文档语义不同。

本地 `scripts/background-worker.ps1` 70–95 行的通用重试把两种错误放在同一分支，并通过相反状态再重试；连接前还先关闭 HFP/A2DP。上游 AHK 也沿用服务切换。这能解释该路线为什么涉及比“连接”更多的系统状态变化，**但不是本机掉线根因已被证明**。

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

许可证元数据：ToothTray BSD-2-Clause；BTAudioSysTrayTool、上游 BluetoothDeviceConnector MIT。若后续复制代码，随代码保留原始版权和许可文件；本轮保存的源码仅用于本地核对，没有把第三方实现打包部署。

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

## 6. 本轮实际完成 / 未执行

完成：核对三项目固定提交的6份源码，保存原始字节SHA256与来源；对照官方API和一个相关issue；把Windows用户体验优先写入项目入口。

未执行：KS连接/断开、蓝牙服务切换、默认输出修改、安装版替换、Release。应用版本仍为1.9.19。本报告是技术选型证据，不是修复已完成的声明。
