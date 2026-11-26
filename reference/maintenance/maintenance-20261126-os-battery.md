# 2026-11-26 · 标准系统电量属性独立实验

官方属性及缓存语义见 docs/14。只读取原有授权验收目标的系统存储属性，不发送 BLE/GATT 请求，不改配对、音频或路由；一次独立探针最终输出：

`{"status":"absent","node":"absent","container":"absent","percent":null,"scope":"device_only","freshness":"unverified"}`

目标 PnP 节点唯一；PnP 属性返回 Empty，WinRT DeviceInformation 容器查询成功但 BatteryLife 缺失。没有确认目标实时电量，不能据此断言连接中或其他型号均不支持。八项离线注入检查涵盖唯一性、有效 0、非法数据、冲突、异常脱敏及缺失值。整套 32/647 通过。源码/运行版本仍 1.9.49，候选 EXE 与 ZIP 不变；工具不嵌入生产运行、不启动自动扫描。评审重点：明确结果是系统电量路径的有限负证据，不声称电量功能完成。
