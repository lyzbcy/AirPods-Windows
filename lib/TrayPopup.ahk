; Lazy shared-environment tray popup. Only the actual tray callback is intercepted.
trayPopupGui := 0, trayPopupWvc := 0, trayPopupWv := 0, trayPopupVisible := false
trayPopupCreating := false, trayPopupReady := false, trayPopupOpenedAt := 0, trayPopupLastNotify := 0, trayPopupHadFocus := false
trayHoverGui := 0, trayHoverPending := false, trayHoverVisible := false, trayHoverOriginalTip := ""

TrayIconRect() {
    ni := Buffer(A_PtrSize = 8 ? 40 : 28, 0), rect := Buffer(16, 0)
    NumPut("uint", ni.Size, ni, 0)
    NumPut("ptr", A_ScriptHwnd, ni, A_PtrSize = 8 ? 8 : 4)
    NumPut("uint", 0x404, ni, A_PtrSize = 8 ? 16 : 8)
    try {
        if DllCall("shell32\Shell_NotifyIconGetRect", "ptr", ni, "ptr", rect, "int") = 0
            return {left:NumGet(rect,0,"int"),top:NumGet(rect,4,"int"),right:NumGet(rect,8,"int"),bottom:NumGet(rect,12,"int")}
    }
    return 0
}

TrayMouse() {
    old := A_CoordModeMouse
    CoordMode("Mouse", "Screen")
    MouseGetPos(&x, &y)
    CoordMode("Mouse", old)
    return {x:x,y:y}
}

TrayPointIn(rect, p) {
    return IsObject(rect) && p.x >= rect.left && p.x < rect.right && p.y >= rect.top && p.y < rect.bottom
}

TrayPopupPosition(w, h) {
    p := TrayMouse(), r := TrayIconRect()
    if IsObject(r)
        p := {x:(r.left+r.right)//2, y:r.top}
    idx := MonitorGetPrimary()
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &rr, &b)
        if p.x >= l && p.x < rr && p.y >= t && p.y < b {
            idx := A_Index
            break
        }
    }
    MonitorGetWorkArea(idx, &l, &t, &rr, &b)
    return {x:Max(l+4,Min(p.x-w//2,rr-w-4)),y:Max(t+4,Min(p.y-h-8,b-h-4))}
}

TrayNotify(wParam, lParam, msg, hwnd) {
    global trayPopupLastNotify, trayHoverPending, trayHoverVisible, trayPopupVisible, trayHoverOriginalTip
    if hwnd != A_ScriptHwnd
        return
    event := lParam & 0xFFFF
    if event = 0x205 || event = 0x7B {
        if A_TickCount - trayPopupLastNotify > 250 {
            trayPopupLastNotify := A_TickCount
            SetTimer(TrayPopupShow, -1)
        }
        return 0
    }
    if event = 0x200 && !trayPopupVisible && !trayHoverPending && !trayHoverVisible {
        trayHoverPending := true
        trayHoverOriginalTip := A_IconTip
        A_IconTip := " "
        SetTimer(TrayHoverShow, -600)
    } else if event = 0x201 || event = 0x203 {
        ; Do not intercept left-click quick connection.
        SetTimer(TrayHoverHide, -1)
    }
}

TrayHoverShow() {
    global trayHoverGui, trayHoverPending, trayHoverVisible, trayHoverOriginalTip, trayPopupVisible
    global busy, appRoot
    trayHoverPending := false
    if trayPopupVisible || !TrayPointIn(TrayIconRect(), TrayMouse()) {
        TrayHoverHide()
        return
    }
    try {
        trayHoverGui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000", "AirPods 快捷提示")
        trayHoverGui.BackColor := "FFF9EE"
        on := AnyConnected()
        icon := TrayIconDir() (on ? "\brand-tray-on.ico" : "\brand-tray-off.ico")
        if FileExist(icon)
            trayHoverGui.AddPicture("x12 y15 w39 h39", icon)
        trayHoverGui.SetFont("s10 c604720 bold", "Microsoft YaHei UI")
        trayHoverGui.AddText("x61 y10 w185", "AirPods 小助手")
        trayHoverGui.SetFont("s9 " (on ? "c5B976A" : "cB28A40") " norm", "Microsoft YaHei UI")
        trayHoverGui.AddText("x61 y33 w190", (busy ? "● 正在处理连接…" : on ? "● 蓝牙已连接 · 左键断开" : "● 未连接 · 左键连接"))
        trayHoverGui.SetFont("s8 cA58C60", "Microsoft YaHei UI")
        trayHoverGui.AddText("x61 y55 w190", "右键打开快捷菜单")
        trayHoverGui.Show("w260 h83 Hide")
        ; GUI dimensions may be DPI-scaled logical units; the region and
        ; screen placement need the actual physical HWND rectangle.
        rect := Buffer(16,0)
        if !DllCall("user32\GetWindowRect","ptr",trayHoverGui.Hwnd,"ptr",rect,"int")
            throw Error("hover window rectangle unavailable")
        w := NumGet(rect,8,"int")-NumGet(rect,0,"int"), h := NumGet(rect,12,"int")-NumGet(rect,4,"int")
        pos := TrayPopupPosition(w,h)
        try WinSetRegion("0-0 W" w " H" h " R22-22", trayHoverGui.Hwnd)
        try DllCall("dwmapi\DwmSetWindowAttribute","ptr",trayHoverGui.Hwnd,"int",33,"int*",2,"int",4)
        trayHoverVisible := true
        trayHoverGui.Show("x" pos.x " y" pos.y " NoActivate")
        SetTimer(TrayHoverWatch, 100)
    } catch as e {
        TrayHoverHide()
        LogMsg("tray hover fallback code=" (e.HasOwnProp("Number") ? e.Number : "unknown"),"WARN")
    }
}
TrayHoverWatch() {
    if !TrayPointIn(TrayIconRect(), TrayMouse())
        TrayHoverHide()
}
TrayHoverHide(*) {
    global trayHoverGui, trayHoverPending, trayHoverVisible, trayHoverOriginalTip
    SetTimer(TrayHoverShow, 0), SetTimer(TrayHoverWatch, 0)
    trayHoverPending := false, trayHoverVisible := false
    if A_IconTip = " " && trayHoverOriginalTip != ""
        A_IconTip := trayHoverOriginalTip
    trayHoverOriginalTip := ""
    if IsObject(trayHoverGui)
        try trayHoverGui.Destroy()
    trayHoverGui := 0
}

TrayPopupPublish() {
    global trayPopupWv, trayPopupReady, busy, LOG_VERBOSE
    if trayPopupReady && IsObject(trayPopupWv)
        try trayPopupWv.ExecuteScriptAsync('window.setTrayState(' (AnyConnected() ? "true" : "false") ',' (busy ? "true" : "false") ',' (LOG_VERBOSE ? "true" : "false") ')')
}

TrayPopupMessage(core,args) {
    global trayPopupReady
    if args.Source != "https://app.airpods.local/tray_built.html" || core.Source != "https://app.airpods.local/tray_built.html"
        return
    try {
        message := args.TryGetWebMessageAsString()
        if message = "tray:ready" {
            trayPopupReady := true
            TrayPopupPublish()
            return
        }
        actions := Map("tray:open", "open", "tray:connect", "connect", "tray:disconnect", "disconnect", "tray:advanced", "advanced", "tray:logs", "logs", "tray:update", "update", "tray:quit", "quit", "tray:close", "close")
        if actions.Has(message) {
            action := actions[message]
            TrayPopupHide()
            SetTimer(() => TrayPopupAction(action), -1)
        }
    }
}

TrayPopupAction(action) {
    global myGui
    switch action {
        case "open": myGui.Show(), SyncWebView()
        case "connect": TrayQuickAction("connect")
        case "disconnect": TrayQuickAction("disconnect")
        case "advanced": OpenAdvancedControl()
        case "logs": ToggleDiagnosticLogging()
        case "update": CheckUpdate(true)
        case "quit": ExitApp()
    }
}

TrayPopupShow(*) {
    global trayPopupGui, trayPopupWvc, trayPopupWv, trayPopupVisible, trayPopupCreating, trayPopupReady, trayPopupOpenedAt, trayPopupHadFocus
    global wv, appRoot, wv2Fallback, wvDll
    TrayHoverHide()
    if trayPopupCreating
        return
    if trayPopupVisible {
        TrayPopupHide()
        return
    }
    SetTimer(TrayPopupDestroy,0)
    trayPopupCreating := true
    try {
        scale := A_ScreenDPI / 96
        w := Round(300*scale), h := Round(382*scale)
        if !IsObject(trayPopupWvc) {
            EnsureResources()
            trayPopupGui := Gui("-DPIScale -Caption +AlwaysOnTop +ToolWindow", "AirPods 小助手 · 快捷菜单")
            trayPopupGui.MarginX := 0, trayPopupGui.MarginY := 0, trayPopupGui.BackColor := "FDEEFF"
            trayPopupGui.Show("w" w " h" h " Hide")
            trayPopupWvc := WebView2.create(trayPopupGui.Hwnd,, wv.Environment, EnvGet("LOCALAPPDATA") "\AirPodsBuddy_webview", wv2Fallback, 0, wvDll)
            trayPopupWv := trayPopupWvc.CoreWebView2
            trayPopupWvc.DefaultBackgroundColor := 0x00000000
            WinSetTransColor("FDEEFF", trayPopupGui)
            trayPopupWv.Settings.AreDevToolsEnabled := false
            trayPopupWv.Settings.AreDefaultContextMenusEnabled := false
            trayPopupWv.add_NavigationStarting((core,args) => (args.Cancel := args.Uri != "https://app.airpods.local/tray_built.html"))
            trayPopupWv.add_NewWindowRequested((core,args) => (args.Handled := true))
            trayPopupWv.add_WebMessageReceived(TrayPopupMessage)
            trayPopupWv.SetVirtualHostNameToFolderMapping("app.airpods.local", A_IsCompiled ? appRoot : A_ScriptDir "\webui", 0)
            trayPopupWv.Navigate("https://app.airpods.local/tray_built.html")
            trayPopupGui.OnEvent("Close", TrayPopupHide)
            trayPopupGui.OnEvent("Escape", TrayPopupHide)
        }
        pos := TrayPopupPosition(w,h)
        trayPopupGui.Show("x" pos.x " y" pos.y " w" w " h" h)
        trayPopupWvc.Fill(), trayPopupWvc.IsVisible := true
        try WinActivate("ahk_id " trayPopupGui.Hwnd)
        trayPopupHadFocus := !!WinActive("ahk_id " trayPopupGui.Hwnd)
        trayPopupVisible := true, trayPopupOpenedAt := A_TickCount
        TrayPopupPublish()
        SetTimer(TrayPopupWatch, 120)
        LogMsg("custom tray popup shown")
    } catch as e {
        trayPopupVisible := false
        TrayPopupDestroy()
        LogMsg("custom tray popup failed; native fallback code=" (e.HasOwnProp("Number") ? e.Number : "unknown"),"WARN")
        A_TrayMenu.Show()
    } finally trayPopupCreating := false
}

TrayPopupWatch() {
    global trayPopupVisible, trayPopupGui, trayPopupOpenedAt, trayPopupHadFocus
    if !trayPopupVisible || A_TickCount - trayPopupOpenedAt <= 500
        return
    active := !!WinActive("ahk_id " trayPopupGui.Hwnd)
    if active
        trayPopupHadFocus := true
    ; Foreground activation can be denied by Windows. Do not dismiss a
    ; freshly shown popup solely because it never became active.
    if trayPopupHadFocus && !active {
        TrayPopupHide()
        return
    }
    if GetKeyState("LButton","P") || GetKeyState("RButton","P") {
        trayPopupGui.GetPos(&x,&y,&w,&h)
        if !TrayPointIn({left:x,top:y,right:x+w,bottom:y+h},TrayMouse())
            TrayPopupHide()
    }
}
TrayPopupHide(*) {
    global trayPopupVisible, trayPopupGui, trayPopupWvc
    trayPopupVisible := false
    SetTimer(TrayPopupWatch,0)
    if IsObject(trayPopupWvc)
        try trayPopupWvc.IsVisible := false
    if IsObject(trayPopupGui)
        try trayPopupGui.Hide()
    SetTimer(TrayPopupDestroy,-200)
}
TrayPopupDestroy(*) {
    global trayPopupVisible, trayPopupGui, trayPopupWv, trayPopupWvc, trayPopupReady
    if trayPopupVisible
        return
    SetTimer(TrayPopupWatch,0)
    if IsObject(trayPopupWvc)
        try trayPopupWvc.Close()
    if IsObject(trayPopupGui)
        try trayPopupGui.Destroy()
    trayPopupGui := 0, trayPopupWv := 0, trayPopupWvc := 0, trayPopupReady := false
}
