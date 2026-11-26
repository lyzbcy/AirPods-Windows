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
    finally:
        browser.close()
