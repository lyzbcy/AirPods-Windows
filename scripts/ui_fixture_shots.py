"""Render the built UI pages with headless Edge and synthetic devices.

Use it after any markup or CSS change: the offline tests check logic, not layout.
It loads webui/index_built.html (so run webui/build_ui.ps1 first), appends a small fixture
script with fake devices, and writes PNGs. No app process, no Bluetooth, no network.

Usage: python scripts/ui_fixture_shots.py --output <private folder>
"""
from pathlib import Path
import argparse, os, subprocess, tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True, help='folder for the PNGs; keep it outside the repo')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
edge = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Microsoft/Edge/Application/msedge.exe'
if not edge.exists():
    raise SystemExit('Edge not found; set ProgramFiles(x86) or install Edge')
# The real window is transparent; a plain tint shows the case silhouette.
STYLE = '<style>html{background:#e4e9ee}</style>'
TWO = ("devices=[{id:'A',name:'AirPods Pro',connected:false,audioState:'disconnected',apple:true,progress:null},"
       "{id:'B',name:'AirPods Max',connected:false,audioState:'disconnected',apple:true,progress:null}];"
       "selectedDeviceId='A';")
ONE = "devices=[{id:'A',name:'AirPods Pro',connected:false,audioState:'%s',apple:true,progress:null}];selectedDeviceId='A';"


def later(code):
    return "setTimeout(()=>{try{" + code + "}catch(e){document.title='ERR '+e.message}},400);"


def failed(state, expand=False):
    extra = "document.getElementById('progressSelfhelp').open=true;" if expand else ''
    return later((ONE % state) + "lastActiveProgress={id:'A',action:'connect'};render();renderProgress();" + extra)


FIXTURES = [
    ('webui/index_built.html', later(TWO + 'render();'), '560,580', 'closed'),
    ('webui/index_built.html', failed('link_failed'), '560,580', 'link-failed'),
    ('webui/index_built.html', failed('link_failed', True), '560,580', 'link-failed-expanded'),
    ('webui/index_built.html', failed('audio_failed'), '560,580', 'audio-failed'),
    ('webui/index_built.html', later(TWO + "render();openModal('mSet');"), '560,700', 'settings'),
    # Headless Chromium lays out at about 500px minimum, so capture wider than the real popup.
    ('webui/tray_built.html', '', '500,440', 'tray'),
]

with tempfile.TemporaryDirectory(prefix='apb-edge-') as profile:
    for source, script, size, name in FIXTURES:
        html = (root / source).read_text(encoding='utf-8-sig')
        page = out / (name + '.html')
        page.write_text(html.replace('</body>', STYLE + '<script>' + script + '</script></body>'), encoding='utf-8')
        png = out / (name + '.png')
        try:
            subprocess.run([str(edge), '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
                            '--window-size=' + size, '--virtual-time-budget=4000', '--user-data-dir=' + profile,
                            '--screenshot=' + str(png), page.as_uri()], capture_output=True, timeout=90)
        finally:
            page.unlink(missing_ok=True)
        print(name, 'ok' if png.exists() else 'MISSING', png)
