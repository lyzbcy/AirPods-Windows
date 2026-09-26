#Requires AutoHotkey v2.0
#SingleInstance Off
FileEncoding("UTF-8-RAW")
#Include ..\lib\AudioRouting.ahk
OnError((e, mode) => (FileAppend("ERROR " e.Message " line=" e.Line "`n", "*"), ExitApp(2)))
failures := 0
if (A_Args.Length && A_Args[1] = "/live") {
    api := CoreAudioBackend()
    loop 2 {
        flow := A_Index - 1
        rows := api.Endpoints(flow)
        FileAppend("FLOW " flow " ACTIVE " rows.Length "`n", "*")
        for row in rows
            FileAppend("ENDPOINT " row.id " | " row.name "`n", "*")
        loop 3 {
            try FileAppend("DEFAULT " flow "/" (A_Index - 1) " " api.DefaultId(flow, A_Index - 1) "`n", "*")
            catch as e
                FileAppend("DEFAULT_UNAVAILABLE " flow "/" (A_Index - 1) " " e.Message "`n", "*")
        }
    }
    FileAppend("LIVE_READ_ONLY_COMPLETE (no routing, radio, or playback changes)`n", "*")
    ExitApp(0)
}
stereo := {id: "{render}", name: "Headphones (Test Pods)"}
hfp := {id: "{handsfree}", name: "Headset (Test Pods)"}
Check("stereo_preferred_over_hfp", SelectAudioEndpoint([hfp, stereo], "Test Pods", 0) = "{render}")
Check("hfp_only_render_rejected", SelectAudioEndpoint([hfp], "Test Pods", 0) = "")
Check("ambiguous_stereo_rejected", SelectAudioEndpoint([stereo, {id: "other", name: "Speaker (Test Pods)"}], "Test Pods", 0) = "")
Check("partial_name_rejected", SelectAudioEndpoint([stereo], "Test", 0) = "")
Check("empty_name_rejected", SelectAudioEndpoint([stereo], "", 0) = "")
Check("wildcards_are_literal", SelectAudioEndpoint([stereo], "%", 0) = "")
api := MockAudio()
Check("render_and_capture_separate", FindAudioEndpointId("Test Pods", "0.0.0", api) = "" && FindCaptureForTest(api) = "{capture}")
Check("pnp_id_rejected", !SetAudioDefault("SWD\MMDEVAPI\{capture}", 1, api) && api.setCalls = 0)
api := MockAudio()
Check("all_roles_and_readback_succeed", SetAudioDefault("{target}", 0, api) && api.setCalls = 3 && api.readCalls = 6)
api := MockAudio("fail")
Check("one_failed_role_is_failure", !SetAudioDefault("{target}", 0, api))
Check("partial_change_rolled_back", api.defaults[1] = "old0" && api.defaults[2] = "old1" && api.defaults[3] = "old2")
Check("untouched_roles_not_rewritten", api.setCalls = 3)
api := MockAudio("external")
Check("external_default_not_overwritten", !SetAudioDefault("{target}", 0, api) && api.defaults[1] = "external" && api.setCalls = 2)
api := MockAudio("throw")
Check("exception_is_retryable_failure", !SetAudioDefault("{target}", 0, api) && api.defaults[1] = "old0")
api := MockAudio("mismatch")
Check("s_ok_without_readback_rejected", !SetAudioDefault("{target}", 0, api))
api := MockAudio("missing")
Check("missing_prior_default_no_mutation", !SetAudioDefault("{target}", 0, api) && api.setCalls = 0)
FileAppend("RESULT failures=" failures "`n", "*")
ExitApp(failures ? 1 : 0)

FindCaptureForTest(api) {
    return FindAudioEndpointId("Test Pods", "0.0.1", api)
}
Check(name, ok) {
    global failures
    if !ok
        failures++
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*")
}
LogMsg(*) {
}
class MockAudio {
    __New(mode := "success") {
        this.mode := mode, this.defaults := ["old0", "old1", "old2"]
        this.setCalls := 0, this.readCalls := 0
    }
    Endpoints(flow) {
        return flow = 0 ? [] : [{id: "{capture}", name: "Microphone (Test Pods)"}]
    }
    DefaultId(flow, role) {
        this.readCalls++
        if this.mode = "missing"
            throw Error("no prior default")
        return this.defaults[role + 1]
    }
    SetDefault(id, role) {
        this.setCalls++
        if (id = "{target}" && role = 1 && this.mode = "external") {
            this.defaults[1] := "external"
            return -2147024809
        }
        if (id = "{target}" && role = 1 && this.mode = "throw")
            throw Error("HRESULT exception")
        if (id = "{target}" && role = 1 && this.mode = "fail")
            return -2147024809
        if this.mode != "mismatch"
            this.defaults[role + 1] := id
        return 0
    }
}
