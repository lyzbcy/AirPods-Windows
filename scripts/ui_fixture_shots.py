"""Render the built UI pages with headless Edge and synthetic devices.

Use it after any markup or CSS change: the offline tests check logic, not layout.
It loads webui/index_built.html (so run webui/build_ui.ps1 first), appends a small fixture
script with fake devices, and writes PNGs. No app process, no Bluetooth, no network.

Usage: python scripts/ui_fixture_shots.py --output <private folder> [--poster]
--poster also exports the "why noise control is blocked" flow as one tall shareable PNG.
"""
from pathlib import Path
import argparse, os, re, subprocess, tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True, help='folder for the PNGs; keep it outside the repo')
parser.add_argument('--poster', action='store_true', help='also export the noise-control explainer as one tall PNG')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
edge = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Microsoft/Edge/Application/msedge.exe'
if not edge.exists():
    raise SystemExit('Edge not found; set ProgramFiles(x86) or install Edge')
BASE = [str(edge), '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--virtual-time-budget=4000']
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


def bottom():
    return later("openAdvanced();setTimeout(()=>{const b=document.querySelector('#mAdvanced .dlg-body');if(b)b.scrollTop=b.scrollHeight},500)")


FIXTURES = [
    ('webui/index_built.html', later(TWO + 'render();'), '560,580', 'closed'),
    ('webui/index_built.html', failed('link_failed'), '560,580', 'link-failed'),
    ('webui/index_built.html', failed('link_failed', True), '560,580', 'link-failed-expanded'),
    ('webui/index_built.html', failed('audio_failed'), '560,580', 'audio-failed'),
    ('webui/index_built.html', later(TWO + "render();openModal('mSet');"), '560,700', 'settings'),
    ('webui/index_built.html', later('openAdvanced()'), '560,580', 'advanced'),
    ('webui/index_built.html', bottom(), '560,580', 'advanced-bottom'),
    # Headless Chromium lays out at about 500px minimum, so capture wider than the real popup.
    ('webui/tray_built.html', '', '500,440', 'tray'),
]

# Poster mode reuses the in-app markup unchanged: the app window is hidden, the modal loses
# its size cap and footer, and a brand line is added. Content is the single source of truth.
POSTER = """<style>
html,body{height:auto!important;overflow:visible!important}
body{border-radius:0!important;background:linear-gradient(180deg,#FFE9A6 0%,#FFFCF0 14%,#FFFCF0 86%,#FFE7A0 100%)!important}
.app,#toast,.mask:not(#mAdvanced){display:none!important}
#mAdvanced{position:static!important;display:block!important;opacity:1!important;background:transparent!important;backdrop-filter:none!important;-webkit-backdrop-filter:none!important;padding:30px 26px 28px!important}
#mAdvanced .dlg{width:min(508px,100%)!important;max-height:none!important;overflow:visible!important;transform:none!important;box-shadow:none!important;border:none!important;background:transparent!important;padding:0!important;backdrop-filter:none!important}
#mAdvanced .row,#mAdvanced .adv-status{display:none!important}
#mAdvanced .dlg-body{overflow:visible!important;padding-right:0!important}
/* Nothing sits behind the cards in poster mode; blur only leaves faint tiles in headless rendering. */
#mAdvanced .flow-card{backdrop-filter:none!important;-webkit-backdrop-filter:none!important}
#mAdvanced h3{font-size:21px;line-height:1.35;gap:10px}
#mAdvanced h3 img{width:42px;height:42px;border-radius:12px}
.flow-lede{font-size:14px;margin-top:10px}
.poster-foot{margin-top:18px;display:flex;align-items:center;justify-content:space-between;font-size:12.5px;color:#8A7A5C}
.poster-foot b{color:#3D3222;font-size:13.5px}
</style><script>
setTimeout(()=>{try{
  const dlg=document.querySelector('#mAdvanced .dlg'),h=dlg.querySelector('h3');
  h.insertBefore(document.querySelector('.appicon').cloneNode(),h.firstChild);
  const foot=document.createElement('div');foot.className='poster-foot';
  foot.innerHTML='<b>AirPods 小助手</b><span>免驱动 · 零管理员 · 点一下就连</span>';
  dlg.querySelector('ol.flow').after(foot);
  openModal('mAdvanced');
}catch(e){document.title='ERR '+e.message}},300);
setTimeout(()=>{const d=document.querySelector('#mAdvanced .dlg').getBoundingClientRect();document.documentElement.setAttribute('data-h',String(Math.ceil(d.bottom)+30))},1500);
</script>"""


def poster(profile, png):
    page = out / 'noise-control-poster.html'
    page.write_text((root / 'webui/index_built.html').read_text(encoding='utf-8-sig').replace('</body>', POSTER + '</body>'), encoding='utf-8')
    try:
        base = BASE + ['--user-data-dir=' + profile]
        # Two passes: measure the content height, then capture exactly that.
        dom = subprocess.run(base + ['--dump-dom', page.as_uri()], capture_output=True, timeout=120).stdout.decode('utf-8', 'replace')
        found = re.search(r'data-h="(\d+)"', dom)
        png.unlink(missing_ok=True)
        subprocess.run(base + ['--window-size=560,' + (found.group(1) if found else '2400'), '--force-device-scale-factor=2.6',
                              '--screenshot=' + str(png), page.as_uri()], capture_output=True, timeout=180)
    finally:
        page.unlink(missing_ok=True)
    print('noise-control-poster', 'ok' if png.exists() else 'MISSING', png)


with tempfile.TemporaryDirectory(prefix='apb-edge-') as profile:
    for source, script, size, name in FIXTURES:
        html = (root / source).read_text(encoding='utf-8-sig')
        page = out / (name + '.html')
        page.write_text(html.replace('</body>', STYLE + '<script>' + script + '</script></body>'), encoding='utf-8')
        png = out / (name + '.png')
        try:
            subprocess.run(BASE + ['--window-size=' + size, '--user-data-dir=' + profile,
                                  '--screenshot=' + str(png), page.as_uri()], capture_output=True, timeout=120)
        finally:
            page.unlink(missing_ok=True)
        print(name, 'ok' if png.exists() else 'MISSING', png)
    if args.poster:
        poster(profile, out / 'noise-control-poster.png')
