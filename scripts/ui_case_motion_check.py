"""Headless frame-by-frame review of the production case transition, without hardware."""
from pathlib import Path
import os
from playwright.sync_api import sync_playwright
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.environ['TEMP'])/'airpods-1.9.55-motion'
OUT.mkdir(exist_ok=True)
EDGE=Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Microsoft/Edge/Application/msedge.exe'

with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path=str(EDGE),headless=True,args=['--disable-gpu'])
    try:
        page=browser.new_page(viewport={'width':560,'height':580})
        page.goto((ROOT/'webui/index_built.html').as_uri())
        page.evaluate("""()=>{window.shapeCalls=[];rpc=async(cmd,arg)=>{if(cmd==='windowshape')shapeCalls.push(arg);return cmd==='list'?JSON.stringify(devices):true};window.setFixture=connected=>{devices=[{id:'A',name:'AirPods Pro',connected,audioState:connected?'ready':'disconnected',apple:true,progress:null},{id:'B',name:'AirPods Max',connected:false,audioState:'disconnected',apple:true,progress:null}];selectedDeviceId='A';localAction=null;lastActiveProgress=null;progressOutcome=null;render()};setFixture(false)}""")
        page.wait_for_timeout(1100)
        def monitor():
            page.evaluate("""()=>{window.motionSamples=[];const start=performance.now();function sample(now){const shell=document.querySelector('#caseShell'),lid=shell.querySelector('.case-lid').getBoundingClientRect(),base=shell.querySelector('.case-base').getBoundingClientRect();motionSamples.push({left:Math.min(lid.left,base.left),right:Math.max(lid.right,base.right),top:Math.min(lid.top,base.top),bottom:Math.max(lid.bottom,base.bottom)});if(now-start<900)requestAnimationFrame(sample)}requestAnimationFrame(sample)}""")
        def check_bounds():
            samples=page.evaluate('motionSamples')
            assert len(samples)>=10,len(samples)
            assert all(x['left']>=8 and x['right']<=552 and x['top']>=0 and x['bottom']<=574 for x in samples),samples
        def pose():
            return page.evaluate("""()=>{const base=document.querySelector('#caseShell .case-base'),lid=document.querySelector('#caseShell .case-lid');return {height:base.getBoundingClientRect().height,top:lid.getBoundingClientRect().top,inner:Number(getComputedStyle(document.querySelector('#caseShell .lid-inner')).opacity),transform:getComputedStyle(lid).transform,overlay:document.querySelectorAll('.case-exit-preview').length}}""")
        def snap(name):
            page.screenshot(path=str(OUT/(name+'.png')))
            return pose()
        closed=snap('00-closed')
        page.evaluate('setFixture(true)');monitor()
        page.wait_for_timeout(105);early=snap('01-opening')
        page.wait_for_timeout(180);mid=snap('02-opening')
        page.wait_for_timeout(820);opened=snap('03-open')
        assert closed['height']<early['height']<opened['height'],(closed,early,opened)
        assert closed['inner']<mid['inner']<=opened['inner'],(closed,mid,opened)
        assert opened['overlay']==0
        check_bounds()
        assert page.evaluate("shapeCalls.at(-1)")=='open'
        page.evaluate('setFixture(false)');monitor()
        page.wait_for_timeout(100);closing=snap('04-closing')
        assert closed['height']<closing['height']<opened['height'],closing
        assert page.evaluate("shapeCalls.at(-1)")=='open','native clip before closing settles'
        page.wait_for_timeout(170);snap('05-closing')
        page.wait_for_timeout(850);settled=snap('06-closed')
        assert abs(settled['height']-closed['height'])<1 and settled['overlay']==0
        assert page.evaluate("shapeCalls.at(-1)")=='closed'
        check_bounds()
        print('PASS open_and_close_pose_progress_and_native_clip')
        page.evaluate('setFixture(true)');page.wait_for_timeout(90)
        before=pose();page.evaluate('setFixture(false)');after=pose()
        assert abs(after['height']-before['height'])<20,(before,after)
        assert abs(after['top']-before['top'])<25,(before,after)
        page.wait_for_timeout(100);snap('07-reversing')
        page.evaluate('setFixture(true)');page.wait_for_timeout(1100);reopened=snap('08-reopened')
        assert abs(reopened['height']-opened['height'])<1 and reopened['overlay']==0
        assert page.evaluate("shapeCalls.at(-1)")=='open'
        print('PASS rapid_reversal_continuity_no_stale_clip_or_overlay')
        page.emulate_media(reduced_motion='reduce')
        page.evaluate('setFixture(false)');page.wait_for_timeout(80);reduced=pose()
        assert abs(reduced['height']-closed['height'])<1 and reduced['overlay']==0
        assert page.evaluate("shapeCalls.at(-1)")=='closed'
        print('PASS reduced_motion_immediate_pose_and_clip')
    finally:
        browser.close()
frames=sorted(OUT.glob('0*.png'))
board=Image.new('RGB',(3*560,3*610),'#fff7e8');draw=ImageDraw.Draw(board)
for i,frame in enumerate(frames):
    x=(i%3)*560;y=(i//3)*610;board.paste(Image.open(frame).convert('RGB'),(x,y));draw.text((x+20,y+585),frame.stem,fill='#795b31')
board.save(OUT/'motion-board.png')
print('MOTION_BOARD',OUT/'motion-board.png')
