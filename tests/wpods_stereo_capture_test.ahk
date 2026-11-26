#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\AudioRouting.ahk
#Include ..\lib\WPodsStereoCapture.ahk
OnError((e, mode) => (FileAppend('ERROR ' e.Message ' line=' e.Line Chr(10), '*'), ExitApp(2)))
failures := 0
Check(label, pass) {
    global failures
    FileAppend((pass ? "PASS " : "FAIL ") label Chr(10), "*", "UTF-8")
    if !pass
        failures += 1
}
address := "112233AABBCC"
root := "USB\VID_1209&PID_0001\WPODS112233AABBCC"
cap := "{0.0.1.00000000}.{11111111-1111-1111-1111-111111111111}"
second := "{0.0.1.00000000}.{22222222-2222-2222-2222-222222222222}"
render := "{0.0.0.00000000}.{33333333-3333-3333-3333-333333333333}"
row := {id: cap, name:"Headset (A2DP, Synthetic AirPods)", state:1}
accept := (id, expected) => expected = root
Check("exact_pair", WPodsStereoCapture(address,[row],accept) = cap)
Check("address_case_normalized", WPodsStereoCapture(StrLower(address),[row],accept) = cap)
Check("invalid_address_is_not_queried", WPodsStereoCapture("112233",[row],(*) => 1/0) = "")
Check("zero_address_is_not_queried", WPodsStereoCapture("000000000000",[row],(*) => 1/0) = "")
Check("friendly_name_is_not_identity", WPodsStereoCapture(address,[row],(*) => false) = "")
Check("reject_other_pair", WPodsStereoCapture(address,[row],(id, expected) => expected = root "DD") = "")
Check("exclude_hd_voice", WPodsStereoCapture(address,[{id:cap,name:"Headset (HD, Synthetic AirPods)",state:1}],accept) = "")
Check("exclude_unplugged", WPodsStereoCapture(address,[{id:cap,name:row.name,state:8}],accept) = "")
Check("exclude_render", WPodsStereoCapture(address,[{id:render,name:row.name,state:1}],accept) = "")
Check("exclude_malformed_guid", WPodsStereoCapture(address,[{id:"bad",name:row.name,state:1}],accept) = "")
Check("fail_closed_if_multiple_exact_candidates", WPodsStereoCapture(address,[row,{id:second,name:row.name,state:1}],accept) = "")
Check("allow_unique_exact_target_with_another_a2dp", WPodsStereoCapture(address,[row,{id:second,name:row.name,state:1}],(id, expected) => id = cap && expected = root) = cap)
Check("normalization_of_localized_parentheses", WPodsStereoCapture(address,[{id:cap,name:"耳麦（A2DP，测试）",state:1}],accept) = cap)
Check("absent_pnp_instance_does_not_match", !WPodsEndpointHasAncestor(cap,root))
serviceState := WPodsStereoServiceState()
Check("service_query_has_fixed_enum", serviceState = "absent" || serviceState = "inactive" || serviceState = "running" || serviceState = "unknown")
fake := StereoTestBackend([row])
Check("resolver_requires_running_service", ResolveWPodsStereoCapture(address, fake, () => "inactive", accept) = "" && fake.queries = 0)
Check("resolver_uses_only_active_capture", ResolveWPodsStereoCapture(address, fake, () => "running", accept) = cap && fake.queries = 1)
fake.broken := true
Check("resolver_error_never_routes", ResolveWPodsStereoCapture(address, fake, () => "running", accept) = "")
FileAppend("RESULT failures=" failures Chr(10),"*","UTF-8")
ExitApp(failures ? 1 : 0)

class StereoTestBackend {
    __New(rows) {
        this.rows := rows
        this.queries := 0
        this.broken := false
    }
    Endpoints(flow, states) {
        this.queries++
        if (flow != 1 || states != 1 || this.broken)
            throw Error("test query failed")
        return this.rows
    }
}

LogMsg(*) {
}
