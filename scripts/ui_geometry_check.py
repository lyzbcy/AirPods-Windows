"""Offline Chromium geometry + hit checks for the two real case states."""
from pathlib import Path
from playwright.sync_api import sync_playwright
import os
root=Path(__file__).resolve().parents[1]
edge=Path(os.environ.get("ProgramFiles(x86)",r"C:\Program Files (x86)"))/"Microsoft/Edge/Application/msedge.exe"
with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path=str(edge),headless=True,args=["--disable-gpu"])
    try:
        page=browser.new_page(viewport={"width":560,"height":580})
        page.goto((root/"webui/index_built.html").as_uri())
        page.evaluate("""()=>{devices=[{id:'A',name:'AirPods Pro',connected:false,audioState:'disconnected',apple:true,progress:null},{id:'B',name:'AirPods Max',connected:false,audioState:'disconnected',apple:true,progress:null}];selectedDeviceId='A';render()}""")
        page.wait_for_timeout(1000)
        closed=page.evaluate("""()=>{const shell=document.querySelector('#caseShell'),main=document.querySelector('.case-main'),orb=document.querySelector('#orb'),b=orb.getBoundingClientRect(),m=main.getBoundingClientRect();return {closed:shell.dataset.case==='closed',onlyActionAndBrand:[...main.children].filter(e=>getComputedStyle(e).display!=='none').every(e=>e===orb||e.tagName==='HEADER'),logo:main.querySelector('.appicon').getBoundingClientRect().height>=70,hiddenTitle:getComputedStyle(main.querySelector('.title')).display==='none',iconControls:[...document.querySelectorAll('.rail-label')].every(e=>getComputedStyle(e).display==='none'),noScroll:main.scrollHeight<=main.clientHeight+1,buttonFit:b.top>=m.top&&b.bottom<=m.bottom&&b.left>=m.left&&b.right<=m.right,centered:Math.abs((b.left+b.right-m.left-m.right)/2)<2,hit:document.elementFromPoint((b.left+b.right)/2,(b.top+b.bottom)/2)?.closest('button')===orb,devices:document.querySelectorAll('#devices [data-select]').length===2}}""")
        assert all(closed.values()),closed
        print("PASS closed_case_brand_and_primary_action_no_scroll",closed)
        page.evaluate("""()=>{window.gestureCalls=[];rpc=async(cmd)=>{gestureCalls.push(cmd);return true}}""")
        page.locator('.case-lid-wrap').dispatch_event('mousedown',{'button':0})
        page.locator('#resizeGrip').dispatch_event('mousedown',{'button':0})
        page.locator('#topbar button').first.dispatch_event('mousedown',{'button':0})
        assert page.evaluate("gestureCalls") == ['windrag','winresize']
        print("PASS drag_and_resize_bridges_exclude_window_buttons")
        for state in ["closed","open"]:
            page.evaluate("""s=>{const shell=document.querySelector('#caseShell');shell.dataset.case=s;shell.classList.remove('case-opening','case-closing')}""",state)
            page.wait_for_timeout(1000)
            result=page.evaluate("""s=>{
              const bounds=e=>{const r=e.getBoundingClientRect();return [r.left,r.top,r.right,r.bottom]};
              const checks=[...document.querySelectorAll('#topbar button')].map(e=>{
                const r=e.getBoundingClientRect();const samples=[[.5,.5],[.25,.5],[.75,.5],[.5,.25],[.5,.75]];
                return {size:r.width>=36&&r.height>=36,inside:r.left>=8&&r.right<=552&&r.top>=(s==='closed'?120:0)&&r.bottom<=574,
                  hit:samples.every(([x,y])=>document.elementFromPoint(r.left+x*r.width,r.top+y*r.height)?.closest('button')===e)};
              });
              const lid=bounds(document.querySelector('.case-lid')),base=bounds(document.querySelector('.case-base'));
              return {checks,lid,base,fit:[lid,base].every(r=> r[0]>=8&&r[2]<=552&&r[1]>=(s==='closed'?120:0)&&r[3]<=574)};
            }""",state)
            print(state,result)
            assert result['fit'] and all(all(c.values()) for c in result['checks']),result
            print("PASS "+state+"_case_geometry_and_button_hit_targets")
        page.evaluate("""()=>{devices=[{id:'A',name:'测试设备 VeryLongHeadsetNameWithNoSpaces012345678901234567890',connected:true,audioState:'ready',apple:true,progress:null}];selectedDeviceId='A';render();let p=document.querySelector('#progressPanel');p.hidden=false;document.querySelector('#progressTitle').textContent='连接检查完成 · 请试听 · 超长设备名称ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';document.querySelector('#progressWhy').textContent='已核实的技术状态需要完整展示，长文本不能碰到圆角或者溢出容器。'.repeat(4)}""")
        page.wait_for_timeout(1000)
        assert page.locator('#caseSummary').is_visible()
        assert page.locator('#caseAdvanced').is_visible()
        text_check=page.evaluate("""()=>{const main=document.querySelector('.case-main'),panel=document.querySelector('#progressPanel');const safe=[...document.querySelectorAll('.case-summary .detail-row strong,#progressTitle,#progressWhy')].every(e=>e.scrollWidth<=e.clientWidth+1);return {safe,scrollable:main.scrollHeight>main.clientHeight,padding:parseFloat(getComputedStyle(panel).paddingLeft)>=14}}""")
        assert all(text_check.values()),text_check
        print("PASS long_text_wraps_and_scroll_is_available",text_check)
    finally:
        browser.close()
