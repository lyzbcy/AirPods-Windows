from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
STAGE = __import__('sys').argv[1]

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, executable_path=r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
    page = browser.new_page(viewport={'width': 460, 'height': 600}, device_scale_factor=1)
    html = 'index_built.html' if STAGE == 'modified' else 'index.html'
    page.goto((ROOT / 'webui' / html).as_uri(), wait_until='domcontentloaded')
    if STAGE == 'modified':
        page.evaluate('devices=[];render()')
    page.wait_for_timeout(450)
    page.screenshot(path=str(OUT / f'{STAGE}-main.png'))
    if STAGE == 'modified':
        page.evaluate("devices=[{id:'AABBCCDDEEFF',name:'AirPods Pro',connected:false,audioState:'disconnected',apple:true}];render()")
        assert page.locator('#devices .empty').count() == 0
        page.wait_for_timeout(400)
        page.screenshot(path=str(OUT / 'modified-device.png'))
    if STAGE == 'modified':
        page.locator('button.issue-link').click()
    else:
        page.evaluate('openIssue()')
    page.wait_for_timeout(450)
    page.screenshot(path=str(OUT / f'{STAGE}-issue.png'))
    if STAGE == 'modified':
        assert page.locator('#issFile').is_visible()
        assert page.locator('#issFile').is_checked()
        page.locator('.iss-recovery summary').click()
        page.wait_for_timeout(200)
        page.screenshot(path=str(OUT / 'modified-recovery.png'))
        page.locator('#mIssue .dlg-body').evaluate('(e)=>e.scrollTop=e.scrollHeight')
        page.screenshot(path=str(OUT / 'modified-issue-scroll.png'))
    page.evaluate("closeModal('mIssue'); openAbout()")
    page.wait_for_timeout(450)
    page.screenshot(path=str(OUT / f'{STAGE}-about.png'))
    if STAGE == 'modified':
        page.evaluate("closeModal('mAbout');openModal('mHelp')")
        page.wait_for_timeout(450)
        page.screenshot(path=str(OUT / 'modified-help.png'))
        page.evaluate("closeModal('mHelp');openModal('mSet')")
        page.wait_for_timeout(450)
        page.screenshot(path=str(OUT / 'modified-settings.png'))
        page.locator('.set-more summary').click()
        page.screenshot(path=str(OUT / 'modified-settings-details.png'))
        page.evaluate("closeModal('mSet');openIssue()")
        page.locator('#issChips .tchip').first.click()
        page.locator('#issFile').uncheck()
        page.evaluate("rpc=async()=> 'ok';issueSend()")
        page.wait_for_timeout(100)
        assert '未附日志' in page.locator('#issDone').inner_text()
        page.screenshot(path=str(OUT / 'modified-no-log-receipt.png'))
    print(f'viewport=460x600 stage={STAGE} main={OUT / (STAGE + "-main.png")} issue={OUT / (STAGE + "-issue.png")} about={OUT / (STAGE + "-about.png")}')
    browser.close()
