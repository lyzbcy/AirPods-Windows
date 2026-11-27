; Independent WPods 0.4.4 endpoint interoperability, no driver or installer operations.
; Exact USB ancestry binds this capture endpoint to the current Bluetooth address.
; Never store or log the address, USB serial, or endpoint ID.
WPodsStereoCapture(address, rows, ancestorMatches) {
    if !RegExMatch(address, "i)^[0-9a-f]{12}$") || address = "000000000000"
        return ""
    usbInstance := "USB\VID_1209&PID_0001\WPODS" StrUpper(address)
    found := ""
    for row in rows {
        if !RegExMatch(row.id, "i)^\{0\.0\.1\.00000000\}\.\{[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\}$")
            continue
        if row.state != 1 || !RegExMatch(row.name, "i)[(（]\s*A2DP\s*[,，]")
            continue
        if !ancestorMatches.Call(row.id, usbInstance)
            continue
        if found != "" ; multiple exact candidates: do not guess
            return ""
        found := row.id
    }
    return found
}

WPodsEndpointHasAncestor(endpointId, expected) {
    dev := 0
    if DllCall("CfgMgr32\CM_Locate_DevNodeW", "UInt*", &dev, "Str", "SWD\MMDEVAPI\" endpointId, "UInt", 0, "UInt") != 0
        return false
    identity := Buffer(400, 0)
    loop 8 {
        if DllCall("CfgMgr32\CM_Get_Device_IDW", "UInt", dev, "Ptr", identity, "UInt", 200, "UInt", 0, "UInt") != 0
            return false
        if StrUpper(StrGet(identity, "UTF-16")) = StrUpper(expected)
            return true
        parent := 0
        if DllCall("CfgMgr32\CM_Get_Parent", "UInt*", &parent, "UInt", dev, "UInt", 0, "UInt") != 0
            return false
        dev := parent
    }
    return false
}

; Native service manager query only. No executable discovery, launch, install, or restart.
WPodsStereoServiceState() {
    scm := DllCall("Advapi32\OpenSCManagerW", "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr")
    if !scm
        return "unknown"
    try {
        service := DllCall("Advapi32\OpenServiceW", "Ptr", scm, "Str", "WPodsService", "UInt", 4, "Ptr")
        if !service
            return A_LastError = 1060 ? "absent" : "unknown"
        try {
            status := Buffer(28, 0)
            if !DllCall("Advapi32\QueryServiceStatus", "Ptr", service, "Ptr", status, "Int")
                return "unknown"
            return NumGet(status, 4, "UInt") = 4 ? "running" : "inactive"
        } finally DllCall("Advapi32\CloseServiceHandle", "Ptr", service)
    } finally DllCall("Advapi32\CloseServiceHandle", "Ptr", scm)
}


ResolveWPodsStereoCapture(address, backend?, serviceReader?, ancestryReader?) {
    if !IsSet(serviceReader) && VerCompare(A_OSVersion, "10.0.22000") < 0
        return ""
    try {
        serviceState := IsSet(serviceReader) ? serviceReader.Call() : WPodsStereoServiceState()
        if serviceState != "running"
            return ""
        api := IsSet(backend) ? backend : CoreAudioBackend()
        check := IsSet(ancestryReader) ? ancestryReader : WPodsEndpointHasAncestor
        return WPodsStereoCapture(address, api.Endpoints(1, 1), check)
    } catch {
        return ""
    }
}

; User-facing readiness is deliberately limited to OS and service presence.
; A running service does not prove the selected AirPods can provide an A2DP mic.
WPodsGuideStatus(osVersion?, serviceReader?) {
    if !IsSet(osVersion)
        osVersion := A_OSVersion
    if VerCompare(osVersion, "10.0.22000") < 0
        return "unsupported"
    try {
        state := IsSet(serviceReader) ? serviceReader.Call() : WPodsStereoServiceState()
        return (state = "running" || state = "inactive" || state = "absent") ? state : "unknown"
    } catch {
        return "unknown"
    }
}
