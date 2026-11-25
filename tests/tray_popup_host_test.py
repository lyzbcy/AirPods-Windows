from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'lib/TrayPopup.ahk').read_text(encoding='utf-8-sig')
def extract(name):
    a=source.index('\n'+name+'(')+1
    return source[a:source.index('\n}',a)+2]+'\n'
body=r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
trayPopupLastNotify := A_TickCount-1000, trayHoverPending := false, trayHoverVisible := false, trayPopupVisible := false
rightCalls := 0, hoverCalls := 0, hideCalls := 0, fails := 0
Check("other_window_not_intercepted", TrayNotify(0,0x205,0x404,0) = "")
Check("right_click_intercepted", TrayNotify(0,0x205,0x404,A_ScriptHwnd) = 0)
Check("duplicate_right_click_suppressed", TrayNotify(0,0x205,0x404,A_ScriptHwnd) = 0)
Sleep 100
Check("right_popup_once", rightCalls = 1)
Check("left_click_not_intercepted", TrayNotify(0,0x201,0x404,A_ScriptHwnd) = "")
Sleep 100
Check("left_click_hides_hover", hideCalls = 1)
TrayNotify(0,0x200,0x404,A_ScriptHwnd)
TrayNotify(0,0x200,0x404,A_ScriptHwnd)
Check("hover_debounced", trayHoverPending)
Sleep 650
Check("hover_once", hoverCalls = 1)
r:={left:10,top:20,right:30,bottom:40}
Check("tray_rect_sensible", TrayPointIn(r,{x:10,y:20}) && !TrayPointIn(r,{x:30,y:20}) && !TrayPointIn(0,{x:10,y:20}))
ExitApp(fails ? 1 : 0)
Check(name,ok) {
 global fails
 if !ok
  fails++
 FileAppend((ok?"PASS ":"FAIL ") name "`n","*")
}
TrayPopupShow(*) {
 global rightCalls
 rightCalls++
}
TrayHoverShow(*) {
 global hoverCalls
 hoverCalls++
}
TrayHoverHide(*) {
 global hideCalls
 hideCalls++
}
'''
body+=extract('TrayNotify')+extract('TrayPointIn')
with tempfile.TemporaryDirectory(prefix='apb-tray-test-') as d:
    file=Path(d)/'test.ahk';file.write_text(body,encoding='utf-8-sig')
    r=subprocess.run([str(root/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(file)],capture_output=True,timeout=10)
    print((r.stdout+r.stderr).decode('utf-8-sig',errors='replace'),end='')
    raise SystemExit(r.returncode)
