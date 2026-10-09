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
Check("render_and_capture_separate", FindAudioEndpointId("Test Pods", "0.0.0", api) = "{target}" && FindCaptureForTest(api) = "{capture}")
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
api := MockAudio()
Check("exact_render_active_routes_three_roles", RenderSwitchToId("{target}", api) && api.setCalls = 3 && AudioRouteMatchesId("{target}", api))
api := MockAudio()
Check("wrong_render_id_never_routes", !RenderSwitchToId("{other}", api) && api.setCalls = 0)
api := MockAudio()
api.renderState := 8
Check("inactive_render_never_routes", !RenderSwitchToId("{target}", api) && api.setCalls = 0)
api := MockAudio()
Check("exact_capture_routes", CaptureSwitchToId("{capture}", api) && api.setCalls = 3)
api := MockAudio("render_drops_after_set")
Check("render_drop_after_roles_is_not_success", !RenderSwitchToId("{target}", api) && api.endpointChecks = 2 && api.lastEndpointReadCount = 6)
Check("render_drop_restores_prior_defaults", api.defaults[1] = "old0" && api.defaults[2] = "old1" && api.defaults[3] = "old2")
api := MockAudio("capture_drops_after_set")
Check("capture_drop_after_roles_is_not_success", !CaptureSwitchToId("{capture}", api) && api.endpointChecks = 2 && api.lastEndpointReadCount = 6)
Check("capture_drop_restores_prior_defaults", api.defaults[1] = "old0" && api.defaults[2] = "old1" && api.defaults[3] = "old2")
api := MockAudio("render_drops_after_readback")
api.defaults := ["{target}", "{target}", "{target}"]
Check("route_watch_rechecks_active_after_readback", !AudioRouteMatchesId("{target}", api) && api.endpointChecks = 2 && api.lastEndpointReadCount = 3)
captureExact := "{0.0.1.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
Check("capture_active_is_not_playback_success", AudioCaptureUse(captureExact, CaptureFake(1)) = 1)
Check("capture_idle_is_distinct", AudioCaptureUse(captureExact, CaptureFake(0)) = 0)
Check("capture_query_failure_is_unknown", AudioCaptureUse(captureExact, CaptureFake(-1)) = -1)
Check("render_id_not_used_as_capture", AudioCaptureUse("{0.0.0.00000000}.{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}", CaptureFake(1)) = -1)
Check("shared_hresult_s_ok_supported", AudioSharedFormatStatus(0) = "supported")
Check("shared_hresult_unsupported", AudioSharedFormatStatus(0x88890008) = "unsupported")
Check("shared_hresult_s_false_unknown", AudioSharedFormatStatus(1) = "unknown")
api := MockAudio()
Check("silent_probe_exact_render_supported", AudioRenderProbe("{target}", api).status = "supported" && api.probeCalls = 1)
Check("silent_probe_wrong_id_not_opened", AudioRenderProbe("{other}", api).status = "unknown" && api.probeCalls = 1)
api := MockAudio("probe_unsupported")
Check("silent_probe_unsupported_not_ready", AudioRenderProbe("{target}", api).status = "unsupported")
if AudioRenderProbe("{target}", api).status = "supported"
    RenderSwitchToId("{target}", api)
Check("negative_probe_keeps_other_defaults", api.setCalls = 0 && api.defaults[1] = "old0" && api.defaults[2] = "old1" && api.defaults[3] = "old2")
api := MockAudio("probe_s_false")
Check("silent_probe_s_false_unverified", AudioRenderProbe("{target}", api).status = "unknown")
api := MockAudio("probe_throw")
Check("silent_probe_exception_unverified", AudioRenderProbe("{target}", api).status = "unknown")
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
        this.renderState := 1, this.captureState := 1
        this.endpointChecks := 0, this.lastEndpointReadCount := -1, this.probeCalls := 0
    }
    Endpoints(flow, states := 1) {
        this.endpointChecks++, this.lastEndpointReadCount := this.readCalls
        return flow = 0 ? [{id: "{target}", name: "Speakers (Test Pods)", state: this.renderState}] : [{id: "{capture}", name: "Microphone (Test Pods)", state: this.captureState}]
    }
    DefaultId(flow, role) {
        this.readCalls++
        if (this.mode = "render_drops_after_readback" && this.readCalls = 3)
            this.renderState := 8
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
        if (id = "{target}" && role = 2 && this.mode = "render_drops_after_set")
            this.renderState := 8
        if (id = "{capture}" && role = 2 && this.mode = "capture_drops_after_set")
            this.captureState := 8
        return 0
    }
    ProbeRender(id) {
        this.probeCalls++
        if this.mode = "probe_throw"
            throw Error("injected COM failure")
        if this.mode = "probe_unsupported"
            return {status: AudioSharedFormatStatus(0x88890008), reason: "IsFormatSupported(shared) HRESULT=88890008"}
        if this.mode = "probe_s_false"
            return {status: AudioSharedFormatStatus(1), reason: "IsFormatSupported(shared) HRESULT=00000001"}
        return {status: AudioSharedFormatStatus(0), reason: "shared stream initialized; playback not listened to"}
    }
}

class CaptureFake {
    __New(state) {
        this.state := state
    }
    CaptureUse(id) {
        return this.state
    }
}
