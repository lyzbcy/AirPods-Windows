"""Offline checks for the AirPodsBuddy v1.9.20 public page sync."""

from __future__ import annotations

import argparse
from html.parser import HTMLParser
from pathlib import Path


ASSET = "https://github.com/lyzbcy/AirPods-Windows/releases/download/v1.9.20/AirPodsBuddy-Windows.zip"
PAGE_URL = "https://lyzbcy.github.io/airpods-buddy.html"


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "a":
            self.links.extend(value for key, value in attrs if key == "href" and value)


def verify(mode: str, page_path: Path, skill_path: Path) -> None:
    page = page_path.read_text(encoding="utf-8")
    skill = skill_path.read_text(encoding="utf-8")
    parser = PageParser()
    parser.feed(page)
    if mode == "baseline":
        checks = {
            "old_home_version": "v<b>1.8.4</b>" in page,
            "old_page_version": 'const PAGE_VER="2.2.4"' in page,
            "missing_skill_release_gate": PAGE_URL not in skill,
        }
    else:
        checks = {
            "home_version": "v<b>1.9.20</b>" in page,
            "page_version": 'const PAGE_VER="2.2.6"' in page,
            "download_links": parser.links.count(ASSET) == 2,
            "release_notes_link": "https://github.com/lyzbcy/AirPods-Windows/releases/tag/v1.9.20" in parser.links,
            "known_issue": "少数 Windows 蓝牙环境可能显示已连接但没有耳机播放端点" in page,
            "airpods5_caveat": "AirPods 5 的部分已配对名称识别已改进，但该型号尚未完成真机验证" in page,
            "controlled_feedback": "只有你确认附日志并提交反馈时才会发送" in page,
            "no_stale_claims": all(claim not in page for claim in ("单文件 3.4MB", "v<b>1.8.4</b>", "不上传任何数据，唯一网络行为")),
            "refresh_key_per_version": "const key='ab_autorefreshed_'+m[1]" in page,
            "skill_release_gate": PAGE_URL in skill and "每次正式 GitHub Release 发布后" in skill and "公网页面" in skill,
        }
    for name, ok in checks.items():
        print(f"{name}={'PASS' if ok else 'FAIL'}")
    print(f"{mode.upper()}_RESULT={'PASS' if all(checks.values()) else 'FAIL'} checks={len(checks)}")
    if not all(checks.values()):
        raise SystemExit(1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=("baseline", "modified"))
    ap.add_argument("page", type=Path)
    ap.add_argument("skill", type=Path)
    args = ap.parse_args()
    verify(args.mode, args.page, args.skill)
