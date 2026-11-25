; Independent, local-only companion. No device, filesystem or network commands.
agentGui := 0
agentWvc := 0
agentWv := 0
agentReady := false
agentCreating := false
agentWanted := false
agentPromptText := ""

AgentQueue(prompt, show := false) {
    global agentPromptText, agentWanted
    agentPromptText := prompt
    if show {
        agentWanted := true
        ; Never await another controller inside a WebMessage callback.
        SetTimer(AgentOpen, -1)
    } else
        AgentPublish()
}

AgentHide(*) {
    global agentGui, agentWanted, agentPromptText
    agentWanted := false
    agentPromptText := ""
    if IsObject(agentGui)
        agentGui.Hide()
    AgentPublish()
}

AgentPublish() {
    global agentWv, agentReady, agentPromptText
    if agentReady && IsObject(agentWv)
        try agentWv.ExecuteScriptAsync('window.setPrompt(' JsonStr(agentPromptText) ')')
}

AgentOnMessage(core, args) {
    global agentReady, agentGui
    if args.Source != "https://app.airpods.local/agent_built.html" || core.Source != "https://app.airpods.local/agent_built.html"
        return
    try {
        message := args.TryGetWebMessageAsString()
        if message = "agentready" {
            agentReady := true
            AgentPublish()
        } else if message = "agentclose"
            AgentHide()
        else if message = "agentdrag" {
            DllCall("ReleaseCapture")
            PostMessage(0xA1, 2,,, agentGui.Hwnd)
        }
    }
}

AgentResize(*) {
    global agentWvc
    if IsObject(agentWvc) {
        agentWvc.Fill()
        agentWvc.IsVisible := true
    }
}

AgentOpen() {
    global agentGui, agentWvc, agentWv, agentReady, agentCreating, agentWanted
    global myGui, wv, appRoot, wv2Fallback, wvDll
    if !agentWanted || agentCreating
        return
    agentCreating := true
    try {
        if !IsObject(agentWvc) {
            agentGui := Gui("-DPIScale -Caption +Resize +MinSize300x380 +Owner" myGui.Hwnd, "Agent 排障 · AirPods 小助手")
            agentGui.MarginX := 0, agentGui.MarginY := 0
            agentGui.BackColor := "FFFDF7"
            agentGui.Show("w420 h600 Hide")
            agentWvc := WebView2.create(agentGui.Hwnd,, wv.Environment, EnvGet("LOCALAPPDATA") "\AirPodsBuddy_webview", wv2Fallback, 0, wvDll)
            agentWv := agentWvc.CoreWebView2
            agentWv.Settings.AreDevToolsEnabled := false
            agentWv.Settings.AreDefaultContextMenusEnabled := false
            agentWv.add_NavigationStarting((core, args) => (args.Cancel := args.Uri != "https://app.airpods.local/agent_built.html"))
            agentWv.add_NewWindowRequested((core, args) => (args.Handled := true))
            agentWv.add_WebMessageReceived(AgentOnMessage)
            agentWv.SetVirtualHostNameToFolderMapping("app.airpods.local", A_IsCompiled ? appRoot : A_ScriptDir "\webui", 0)
            agentWv.Navigate("https://app.airpods.local/agent_built.html")
            agentGui.OnEvent("Close", AgentHide)
            agentGui.OnEvent("Escape", AgentHide)
            agentGui.OnEvent("Size", AgentResize)
        }
        if !agentWanted
            return
        myGui.GetPos(&mx, &my, &mw, &mh)
        monitor := MonitorGetPrimary()
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
            if mx + mw/2 >= ml && mx + mw/2 < mr && my + mh/2 >= mt && my + mh/2 < mb {
                monitor := A_Index
                break
            }
        }
        MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
        aw := Min(420, Max(300, right-left-mw-16))
        ah := Min(640, bottom-top)
        pairWidth := mw + 16 + aw
        px := Max(left, left + (right-left-pairWidth)//2)
        py := Max(top, Min(my, bottom-Max(mh,ah)))
        if pairWidth <= right-left {
            WinMove(px, py,,, myGui.Hwnd)
            ax := px + mw + 16
        } else
            ax := Max(left, right-aw)
        agentGui.Show("x" ax " y" py " w" aw " h" ah " NoActivate")
        AgentResize()
        AgentPublish()
        LogMsg("agent companion shown")
    } catch as e {
        LogMsg("agent companion failed: " e.Message, "WARN")
        try agentGui.Destroy()
        agentGui := 0, agentWvc := 0, agentWv := 0, agentReady := false
        PushEvent("toast", JsonStr("Agent 排障窗口暂未打开，请点「打开 Agent 排障」重试"))
    } finally agentCreating := false
}
