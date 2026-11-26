# 2026-11-26 · 软件中心受管安装关联恢复复核

权威软件中心 0.10.30 工程的 production main.cjs::scanInstalled 在 Windows 分支先遍历 storage().appRoots（含 legacyAppsRoot），调用 scanDirectory(root,3)、selectInstalled(managed,state.installs)，再将 recovered.installed 传给 detectInstalled，最终由 status() 的 resolveInstalled 返回安装列表。单独调用 detectInstalled({},[]) 不覆盖这些目录，不能据此推断生产入口缺失恢复能力。

在本机受管 legacy appsRoot 上执行两次只读函数链：第一次仅从内存克隆移除 AirPods install path，第二次同时移除该目标的 path、source 和 package receipt；两次准确恢复实际安装路径。实际 EXE SHA256 与 1.9.50 构建清单一致，真实 state.json 前后字节相同，未写状态、下载、启动或改软件中心。第二次来源标签为「手动添加」，返回的 installedVersions/installedHashes 不会伪造发布回执；正常保留原来源时为「启动器管理」。本次证明实际受管路径可重新发现，不证明所有受管候选冲突场景、更不替代真实 GUI 重启验收。

老田式复核：把证据与实际调用链匹配，纠正片面底层接口判断；无需为该问题修改中心源码。本机仍 1.9.50、公开 AirPods 1.9.24，正式发行后仍须同步目录与页面。
