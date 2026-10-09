#!/usr/bin/env python3
"""Collect public Release asset counts and render an honest snapshot chart."""

import argparse
from datetime import date, datetime, timedelta, timezone
from html import escape
import json
import math
import os
from pathlib import Path
import tempfile
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'lyzbcy/AirPods-Windows'
METRIC = 'release_asset_download_count'


def fetch_releases(repository):
    """Fetch every page; any API failure aborts without rewriting history."""
    headers = {'Accept': 'application/vnd.github+json',
               'User-Agent': 'AirPodsBuddy-release-download-chart',
               'X-GitHub-Api-Version': '2022-11-28'}
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization'] = f'Bearer {token}'
    releases = []
    page = 1
    while True:
        request = Request(
            f'https://api.github.com/repos/{repository}/releases?per_page=100&page={page}',
            headers=headers)
        with urlopen(request, timeout=30) as response:
            batch = json.load(response)
        if not isinstance(batch, list):
            raise ValueError('GitHub releases response must be an array')
        releases.extend(batch)
        if len(batch) < 100:
            return releases
        page += 1


def snapshot(releases, day):
    date.fromisoformat(day)
    public = [release for release in releases if not release.get('draft', False)]
    assets = []
    seen = set()
    for release in public:
        for asset in release['assets']:
            asset_id = asset['id']
            count = asset['download_count']
            if type(asset_id) is not int or asset_id in seen:
                raise ValueError('Missing, duplicate or invalid Release asset ID')
            if type(count) is not int or count < 0:
                raise ValueError('Invalid Release asset download count')
            seen.add(asset_id)
            assets.append({'id': asset_id, 'release': release['tag_name'],
                           'name': asset['name'], 'downloads': count})
    # A repository with no releases may be legitimate, but this repository has
    # existing downloads. Fail closed if a transient empty result would erase it.
    if not assets:
        raise ValueError('No public Release assets; retain previous snapshot')
    return {'date': day, 'total_downloads': sum(a['downloads'] for a in assets),
            'release_count': len(public), 'assets': sorted(assets, key=lambda a: a['id']),
            'source': f'https://api.github.com/repos/{REPOSITORY}/releases',
            'observed_at': datetime.now(timezone.utc).isoformat()}


def validate_history(history):
    if history.get('schema_version') != 1 or history.get('repository') != REPOSITORY:
        raise ValueError('Unexpected history schema or repository')
    if history.get('metric') != METRIC:
        raise ValueError('Unexpected metric')
    seen = set()
    for row in history['snapshots']:
        day = row['date']
        date.fromisoformat(day)
        if day in seen or type(row['total_downloads']) is not int or row['total_downloads'] < 0:
            raise ValueError('Duplicate date or invalid historical total')
        seen.add(day)
        if sum(a['downloads'] for a in row['assets']) != row['total_downloads']:
            raise ValueError('Historical total disagrees with asset counts')


def merge_snapshot(history, current):
    validate_history(history)
    rows = {row['date']: row for row in history['snapshots']}
    if rows and current['date'] < max(rows):
        raise ValueError('Refusing to insert a live count into a historical date')
    # Re-running today refreshes that point, rather than inventing a second day.
    rows[current['date']] = current
    result = {**history, 'snapshots': [rows[day] for day in sorted(rows)]}
    validate_history(result)
    return result


def render_svg(history):
    validate_history(history)
    rows = sorted(history['snapshots'], key=lambda row: row['date'])
    if not rows:
        raise ValueError('Cannot chart an empty history')
    latest = rows[-1]
    first_day = date.fromisoformat(rows[0]['date'])
    last_day = date.fromisoformat(latest['date'])
    span = max(1, (last_day - first_day).days)
    maximum = max(row['total_downloads'] for row in rows)
    unit = 10 ** max(0, math.floor(math.log10(max(1, maximum))))
    ceiling = max(4, math.ceil(maximum / unit) * unit)
    left, right, top, bottom = 76, 888, 156, 330
    def point(row):
        x = left + (date.fromisoformat(row['date']) - first_day).days / span * (right-left)
        if len(rows) == 1:
            x = (left+right)/2
        y = bottom-row['total_downloads']/ceiling*(bottom-top)
        return x, y
    svg = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="960" height="440" viewBox="0 0 960 440" role="img" aria-labelledby="title description">',
        '<title id="title">AirPodsBuddy Release 下载趋势</title>',
        f'<desc id="description">截至 {escape(latest["date"])}，公开 Release 附件累计 {latest["total_downloads"]} 次下载。仅绘制真实快照；包含更新和重复下载，不代表独立用户。</desc>',
        '<rect x="1" y="1" width="958" height="438" rx="22" fill="#fffdf7" stroke="#e8e1d3"/>',
        '<g font-family="Segoe UI, Microsoft YaHei, PingFang SC, sans-serif">',
        '<text x="40" y="47" fill="#262722" font-size="24" font-weight="700">Release 下载趋势</text>',
        '<text x="40" y="74" fill="#6b7063" font-size="14">AirPodsBuddy · GitHub 公开附件累计下载次数</text>',
        f'<text x="918" y="62" text-anchor="end" fill="#587844" font-size="40" font-weight="700">{latest["total_downloads"]:,}</text>',
        f'<text x="918" y="86" text-anchor="end" fill="#6b7063" font-size="13">截至 {escape(latest["date"])} · 上海日期</text>',
        '<path d="M40 110H920" stroke="#e8e1d3"/>',
        '<text x="76" y="135" fill="#72786a" font-size="12">累计下载次数</text>',
    ]
    for index in range(5):
        value = ceiling*index/4
        y = bottom-value/ceiling*(bottom-top)
        svg.extend([
            f'<path d="M{left} {y:.2f}H{right}" stroke="#e8e9df"/>',
            f'<text x="62" y="{y+4:.2f}" text-anchor="end" fill="#72786a" font-size="12">{value:g}</text>',
        ])
    for before, after in zip(rows, rows[1:]):
        x1, y1 = point(before)
        x2, y2 = point(after)
        gap = (date.fromisoformat(after['date'])-date.fromisoformat(before['date'])).days
        dash = ' stroke-dasharray="6 5"' if gap > 1 else ''
        svg.append(f'<path d="M{x1:.2f} {y1:.2f}L{x2:.2f} {y2:.2f}" stroke="#729858" stroke-width="3" fill="none"{dash}/>')
    for row in rows:
        x, y = point(row)
        svg.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="3.5" fill="#729858" stroke="#fffdf7" stroke-width="1.5"/>')
    # Label endpoints only; daily data remains readable as the history grows.
    for row in (rows if len(rows) == 1 else [rows[0], rows[-1]]):
        x, y = point(row)
        svg.append(f'<text x="{x:.2f}" y="{y-12:.2f}" text-anchor="middle" fill="#446334" font-size="13" font-weight="700">{row["total_downloads"]:,}</text>')
    tick_days = sorted({round(span*i/4) for i in range(5)}) if len(rows)>1 else [0]
    for day_offset in tick_days:
        x = left+day_offset/span*(right-left) if len(rows)>1 else (left+right)/2
        label = (first_day+timedelta(days=day_offset)).strftime('%m-%d')
        svg.append(f'<text x="{x:.2f}" y="355" text-anchor="middle" fill="#72786a" font-size="12">{label}</text>')
    svg.extend([
        '<text x="40" y="394" fill="#6b7063" font-size="13">● 实际采集快照　虚线连接缺少逐日记录的区间，未补造历史数据</text>',
        '<text x="40" y="418" fill="#6b7063" font-size="13">包含版本更新与重复下载；不代表独立用户数。资产删除或替换可能使总数下降。</text>',
        '</g></svg>\n',
    ])
    return '\n'.join(svg)


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', newline='\n',
                                     dir=path.parent, delete=False) as temporary:
        temporary.write(text)
        name = temporary.name
    try:
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--history', type=Path, default=ROOT/'assets/release-downloads.json')
    parser.add_argument('--svg', type=Path, default=ROOT/'assets/release-downloads.svg')
    parser.add_argument('--date', default=datetime.now(timezone(timedelta(hours=8))).date().isoformat())
    parser.add_argument('--render-only', action='store_true')
    args = parser.parse_args()
    history = json.loads(args.history.read_text(encoding='utf-8'))
    if not args.render_only:
        history = merge_snapshot(history, snapshot(fetch_releases(REPOSITORY), args.date))
    # Validate/render before touching either output; API/schema failures preserve
    # both prior files. Git publishes JSON and SVG together in one commit.
    chart = render_svg(history)
    if not args.render_only:
        atomic_write(args.history, json.dumps(history, ensure_ascii=False, indent=2)+'\n')
    atomic_write(args.svg, chart)
    latest = history['snapshots'][-1]
    print(f'{latest["date"]}: {latest["total_downloads"]} downloads; {len(history["snapshots"])} snapshots')


if __name__ == '__main__':
    main()
