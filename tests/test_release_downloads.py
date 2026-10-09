import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from xml.etree import ElementTree

SPEC = importlib.util.spec_from_file_location(
    'release_downloads', Path(__file__).resolve().parents[1]/'scripts/release_downloads.py')
chart = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(chart)


def release(identifier, count, draft=False):
    return {'draft': draft, 'tag_name': 'v1', 'assets': [
        {'id': identifier, 'name': 'app.zip', 'download_count': count}]}


def history(*rows):
    return {'schema_version': 1, 'repository': chart.REPOSITORY,
            'metric': chart.METRIC, 'snapshots': list(rows)}


class ReleaseDownloadsTests(unittest.TestCase):
    def test_fetches_later_pages(self):
        first = [release(index, 1) for index in range(100)]
        with patch.object(chart, 'urlopen', side_effect=[
                io.BytesIO(json.dumps(first).encode()),
                io.BytesIO(json.dumps([release(101, 3)]).encode())]) as fetch:
            rows = chart.fetch_releases(chart.REPOSITORY)
        self.assertEqual(len(rows), 101)
        self.assertIn('page=2', fetch.call_args[0][0].full_url)

    def test_ignores_authenticated_drafts(self):
        row = chart.snapshot([release(1, 7), release(2, 999, draft=True)], '2026-10-09')
        self.assertEqual(row['total_downloads'], 7)
        self.assertEqual(row['release_count'], 1)

    def test_same_day_refresh_and_actual_decrease(self):
        old = chart.snapshot([release(1, 8)], '2026-10-09')
        current = chart.snapshot([release(2, 3)], '2026-10-09')
        merged = chart.merge_snapshot(history(old), current)
        self.assertEqual(len(merged['snapshots']), 1)
        self.assertEqual(merged['snapshots'][0]['total_downloads'], 3)

    def test_no_invented_daily_points_and_sparse_dash(self):
        rows = [chart.snapshot([release(1, 386)], '2026-09-23'),
                chart.snapshot([release(1, 552)], '2026-10-09')]
        rendered = chart.render_svg(history(*rows))
        xml = ElementTree.fromstring(rendered)
        self.assertEqual(len(xml.findall('.//{*}circle')), 2)
        self.assertIn('stroke-dasharray="6 5"', rendered)
        self.assertIn('不代表独立用户', rendered)

    def test_one_zero_point_is_valid_svg(self):
        rendered = chart.render_svg(history(chart.snapshot([release(1, 0)], '2026-10-09')))
        ElementTree.fromstring(rendered)
        self.assertNotIn('nan', rendered)

    def test_bad_counts_and_empty_response_fail(self):
        for rows in ([], [release(1, -1)], [release(1, 2), release(1, 2)]):
            with self.assertRaises(ValueError):
                chart.snapshot(rows, '2026-10-09')

    def test_old_date_does_not_rewrite_history(self):
        with self.assertRaises(ValueError):
            chart.merge_snapshot(history(chart.snapshot([release(1, 10)], '2026-10-09')),
                                 chart.snapshot([release(1, 20)], '2026-09-23'))

    def test_api_failure_keeps_both_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data, image = root/'history.json', root/'chart.svg'
            data.write_text(json.dumps(history(chart.snapshot([release(1, 10)], '2026-10-09'))), encoding='utf-8')
            image.write_text('previous chart', encoding='utf-8')
            before = data.read_bytes(), image.read_bytes()
            with patch('sys.argv', ['chart', '--history', str(data), '--svg', str(image), '--date', '2026-10-09']), \
                    patch.object(chart, 'fetch_releases', side_effect=OSError('API unavailable')):
                with self.assertRaises(OSError):
                    chart.main()
            self.assertEqual((data.read_bytes(), image.read_bytes()), before)


if __name__ == '__main__':
    unittest.main()
