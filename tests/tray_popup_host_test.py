from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'lib/TrayPopup.ahk').read_text(encoding='utf-8-sig')
def extract(name):
    a=source.index('\n'+name+'(')+1
    return source[a:source.index('\n}',a)+2]+'\n'
main=(root/'airpods_buddy.ahk').read_text(encoding='utf-8-sig')
for name,ok in {
    'main_interactive_surface_opaque': 'WinSetTransColor("FDEEFF", myGui)' not in main and 'wvc.DefaultBackgroundColor := 0xFFFFF7E8' in main,
    'custom_popup_interactive_surface_opaque': 'WinSetTransColor("FDEEFF", trayPopupGui)' not in source and 'trayPopupGui.BackColor := "FFF7E8"' in source,
    'tray_advanced_opens_explanation_before_external_lab': 'case "advanced": ShowAdvancedExplanation()' in source and 'A_TrayMenu.Add("🎧 降噪/通透实验室", (*) => ShowAdvancedExplanation())' in main,
    'custom_popup_no_second_webview': 'WebView2.create' not in extract('TrayPopupShow') and 'TrayPopupPick.Bind(row[2])' in source,
}.items():
    print(('PASS ' if ok else 'FAIL ')+name)
    if not ok:raise SystemExit(1)
body=r'''
#Requires AutoHotkey v2.0
#SingleInstance Off
OnError((*) => ExitApp(1), -1)
trayPopupLastNotify := A_TickCount-1000, trayHoverPending := false, trayHoverVisible := false, trayPopupVisible := false
rightCalls := 0, hoverCalls := 0, hideCalls := 0, fails := 0, pendingAction := ""
Check("other_window_not_intercepted", TrayNotify(0,0x205,0x404,0) = "")
Check("right_click_native_unintercepted", TrayNotify(0,0x205,0x404,A_ScriptHwnd) = "")
Check("right_context_native_unintercepted", TrayNotify(0,0x7B,0x404,A_ScriptHwnd) = "")
Sleep 100
Check("right_does_not_create_webview", rightCalls = 0)
Check("left_click_not_intercepted", TrayNotify(0,0x201,0x404,A_ScriptHwnd) = "")
Sleep 100
Check("left_click_hides_hover", hideCalls = 2)
TrayNotify(0,0x200,0x404,A_ScriptHwnd)
TrayNotify(0,0x200,0x404,A_ScriptHwnd)
Check("hover_debounced", trayHoverPending)
Sleep 650
Check("hover_once", hoverCalls = 1)
r:={left:10,top:20,right:30,bottom:40}
Check("tray_rect_sensible", TrayPointIn(r,{x:10,y:20}) && !TrayPointIn(r,{x:30,y:20}) && !TrayPointIn(0,{x:10,y:20}))
TrayPopupMessage({Source:"https://app.airpods.local/tray_built.html"},{Source:"https://app.airpods.local/tray_built.html",TryGetWebMessageAsString:(*) => "tray:feedback"})
Sleep 60
Check("tray_feedback_whitelisted_and_hides_popup", pendingAction = "feedback" && hideCalls = 3)
TrayPopupMessage({Source:"https://app.airpods.local/tray_built.html"},{Source:"https://app.airpods.local/tray_built.html",TryGetWebMessageAsString:(*) => "tray:reset"})
Sleep 60
Check("unknown_tray_action_ignored", pendingAction = "feedback" && hideCalls = 3)
TrayPopupMessage({Source:"https://evil.example/x"},{Source:"https://app.airpods.local/tray_built.html",TryGetWebMessageAsString:(*) => "tray:quit"})
Sleep 60
Check("foreign_tray_source_ignored", pendingAction = "feedback" && hideCalls = 3)
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
TrayPopupHide(*) {
 global hideCalls
 hideCalls++
}
; Every function referenced by an extracted function must exist, or AHK stalls at load
; with an error dialog instead of failing the test.
TrayPopupPublish() {
}
'''
body+=extract('TrayNotify')+extract('TrayPointIn')+extract('TrayPopupMessage')
body+='''
TrayPopupAction(action) {
 global pendingAction
 pendingAction := action
}
'''
with tempfile.TemporaryDirectory(prefix='apb-tray-test-') as d:
    file=Path(d)/'test.ahk';file.write_text(body,encoding='utf-8-sig')
    r=subprocess.run([str(root/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(file)],capture_output=True,timeout=10)
    print((r.stdout+r.stderr).decode('utf-8-sig',errors='replace'),end='')
    if r.returncode:raise SystemExit(r.returncode)

# Real native controls, hidden: no WebView/browser startup, no desktop popup.
native=extract('TrayPopupShow').replace('trayPopupGui.Show("x" pos.x " y" pos.y " w" w " h" h)','trayPopupGui.Show("w" w " h" h " Hide")').replace('try WinActivate("ahk_id " trayPopupGui.Hwnd)','').replace('A_TrayMenu.Show()','throw Error("native tray fallback")')
native_body=r"""
#Requires AutoHotkey v2.0
#SingleInstance Off
OnError((e,*) => (FileAppend("FAIL native gui " e.Message "`n","*"),ExitApp(1)))
trayPopupGui:=0,trayPopupVisible:=false,trayPopupCreating:=false,trayPopupOpenedAt:=0,trayPopupHadFocus:=false,busy:=false,LOG_VERBOSE:=false
TrayPopupShow()
if !trayPopupVisible || !IsObject(trayPopupGui)
    ExitApp(1)
count:=0
for _,ctrl in trayPopupGui
    count++
FileAppend((count>=10?"PASS ":"FAIL ") "hidden_native_tray_creates_all_controls count=" count "`n","*")
TrayPopupDestroy()
ExitApp(count>=10?0:1)
TrayHoverHide(*) {
}
TrayPopupDestroy(*) {
    global trayPopupGui,trayPopupVisible
    if IsObject(trayPopupGui)
        trayPopupGui.Destroy()
    trayPopupGui:=0,trayPopupVisible:=false
}
TrayPopupHide(*) {
}
TrayPopupWatch(*) {
}
TrayPopupPick(*) {
}
TrayPopupPosition(*) {
    return {x:0,y:0}
}
AnyConnected() {
    return false
}
LogMsg(*) {
}
TrayIconDir() {
    return "ASSET_DIR"
}
""".replace("ASSET_DIR",str(root/"assets").replace('"','""'))
with tempfile.TemporaryDirectory(prefix='apb-native-tray-test-') as d:
    file=Path(d)/'native.ahk';file.write_text(native_body+native,encoding='utf-8-sig')
    r=subprocess.run([str(root/'tools/ahk_v2_portable/AutoHotkey64.exe'),'/ErrorStdOut=UTF-8',str(file)],capture_output=True,timeout=12)
    print((r.stdout+r.stderr).decode('utf-8-sig',errors='replace'),end='')
    raise SystemExit(r.returncode)
