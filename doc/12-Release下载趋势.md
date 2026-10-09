# Release 下载趋势

README 的图由 `scripts/release_downloads.py` 生成，数据保存在 `assets/release-downloads.json`，图片为 `assets/release-downloads.svg`。只读取 GitHub 公开 Release 附件计数，不调用软件、获取用户信息或修改发布资产。

## 指标口径

- 每个快照合计该时刻所有公开 Release 的附件 `download_count`；包含预发布附件，排除草稿。
- 累计下载次数包含同一个人的更新和重复下载，不是独立用户数、粉丝数或活跃用户数。
- GitHub 的 Release API 提供当前计数，不能回查任意日期的下载曲线。起始数据为此前保存的 2026-09-23（386）与首次启用采集器时的 2026-10-09（555）真实快照；同日数值可继续刷新。日期间未补造逐日数据，图中虚线表示采集间隔大于一天。
- 同一天重新采集更新当天的点；日期按 Asia/Shanghai。删除或替换 Release 附件可能让总数下降，脚本保留真实下降，不人为补成单调增长。
- 旧快照的逐附件记录和来源保留在 JSON 中。9月23日来自当时简历统计文件，10月9日来自当日 GitHub API。

## 更新

GitHub Actions 工作流 `Release download trend` 每天计划在上海时间 09:23 执行，GitHub 调度可能延迟；可从 Actions 页面手动运行。使用 Python 标准库及仓库内置 `GITHUB_TOKEN`，没有额外服务、付费接口或自定义密钥。

```sh
python -m unittest discover -s tests -p 'test_release_downloads.py' -v
python scripts/release_downloads.py
python scripts/release_downloads.py --render-only
```

接口、分页或数据校验失败时保留上一份历史与图片，工作流报错，不把失败采集算成零下载。JSON 和 SVG 在同一个 Git 提交里公开；并发更新冲突也报错，避免覆盖其他提交。README 图片通过 GitHub 自身图片缓存展示，可能晚于提交刷新。

本次仅增加公开下载统计和 README 展示，应用源码版本仍为 v1.9.23 候选，公开软件 Release 仍为 v1.9.21。
