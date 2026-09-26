; Core Audio adapter. No WMI/PnP IDs and no endpoint visibility mutation.
; IID F8679F50: slot 13 = SetDefaultEndpoint(PCWSTR, ERole), NOT slot 14.
class CoreAudioBackend {
    __New() {
        this.enumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
    }
    DeviceId(device) {
        p := 0
        ComCall(5, device, "ptr*", &p)
        try return StrGet(p, "UTF-16")
        finally DllCall("ole32\CoTaskMemFree", "ptr", p)
    }
    DefaultId(flow, role) {
        p := 0
        ComCall(4, this.enumerator, "int", flow, "int", role, "ptr*", &p)
        return this.DeviceId(ComValue(13, p, 1))
    }
    SetDefault(id, role) {
        pc := ComObject("{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}", "{F8679F50-850A-41CF-9C72-430F290290C8}")
        return ComCall(13, pc, "wstr", id, "int", role, "int")
    }
    Endpoints(flow, states := 1) {
        p := 0
        ComCall(3, this.enumerator, "int", flow, "uint", states, "ptr*", &p) ; default DEVICE_STATE_ACTIVE
        collection := ComValue(13, p, 1)
        count := 0
        ComCall(3, collection, "uint*", &count)
        rows := []
        loop count {
            try {
            p := 0
            ComCall(4, collection, "uint", A_Index - 1, "ptr*", &p)
            device := ComValue(13, p, 1)
            state := 0
            ComCall(6, device, "uint*", &state)
            p := 0
            ComCall(4, device, "uint", 0, "ptr*", &p) ; STGM_READ
            properties := ComValue(13, p, 1)
            key := Buffer(20, 0)
            DllCall("ole32\CLSIDFromString", "wstr", "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", "ptr", key)
            NumPut("uint", 14, key, 16) ; PKEY_Device_FriendlyName
            value := Buffer(24, 0)
            try {
                ComCall(5, properties, "ptr", key, "ptr", value)
                if (NumGet(value, 0, "ushort") = 31)
                    rows.Push({id: this.DeviceId(device), name: StrGet(NumGet(value, 8, "ptr"), "UTF-16"), state: state})
            } finally DllCall("ole32\PropVariantClear", "ptr", value)
            } catch as e {
                ; Disconnected/removed devices may disappear during enumeration.
                ; A stale property store must not hide the remaining endpoints.
                LogMsg("audio endpoint skipped during enumeration: " e.Message, "WARN")
            }
        }
        return rows
    }
}

; Literal matching only. Ambiguous matches fail closed instead of routing to a
; different headset. Persistent Bluetooth-address/container identity is separate.
SelectAudioEndpoint(rows, name, flow) {
    if (Trim(name) = "")
        return ""
    preferred := [], fallback := []
    for row in rows {
        if !(StrLower(row.name) = StrLower(name) || InStr(StrLower(row.name), "(" StrLower(name) ")") || InStr(StrLower(row.name), "（" StrLower(name) "）"))
            continue
        fallback.Push(row.id)
        if (flow != 0 || !RegExMatch(row.name, "i)hands.?free|headset|免提|头戴式耳麦"))
            preferred.Push(row.id)
    }
    ; Never call an HFP-only render endpoint a verified music output.
    candidates := flow = 0 ? preferred : fallback
    return candidates.Length = 1 ? candidates[1] : ""
}

FindAudioEndpointId(name, prefix, backend?) {
    flow := prefix = "0.0.0" ? 0 : 1
    try {
        api := IsSet(backend) ? backend : CoreAudioBackend()
        return SelectAudioEndpoint(api.Endpoints(flow), name, flow)
    } catch as e {
        LogMsg("audio enumerate failed: " e.Message, "WARN")
        return ""
    }
}

; Production routing uses the worker's exact MMDevice ID, never a display name.
AudioEndpointIdActive(id, flow, backend?) {
    if (id = "" || InStr(id, "SWD\"))
        return false
    try {
        api := IsSet(backend) ? backend : CoreAudioBackend()
        for row in api.Endpoints(flow, 1)
            if (StrLower(row.id) = StrLower(id) && row.state = 1)
                return true
    } catch as e {
        LogMsg("audio endpoint state unavailable: " e.Message, "WARN")
    }
    return false
}

RenderSwitchToId(id, backend?) {
    try {
        api := IsSet(backend) ? backend : CoreAudioBackend()
        return AudioEndpointIdActive(id, 0, api) && SetAudioDefault(id, 0, api, true)
    } catch as e {
        LogMsg("render route unavailable: " e.Message, "WARN")
        return false
    }
}

CaptureSwitchToId(id, backend?) {
    try {
        api := IsSet(backend) ? backend : CoreAudioBackend()
        return AudioEndpointIdActive(id, 1, api) && SetAudioDefault(id, 1, api, true)
    } catch as e {
        LogMsg("capture route unavailable: " e.Message, "WARN")
        return false
    }
}

AudioRouteMatchesId(id, backend?) {
    try {
        api := IsSet(backend) ? backend : CoreAudioBackend()
        if !AudioEndpointIdActive(id, 0, api)
            return false
        loop 3
            if StrLower(api.DefaultId(0, A_Index - 1)) != StrLower(id)
                return false
        return AudioEndpointIdActive(id, 0, api)
    } catch {
        return false
    }
}

; Success requires three S_OK results AND three matching readbacks. Restore
; pre-operation defaults on partial failure, never change visibility/state.
SetAudioDefault(id, flow, backend?, requireActive := false) {
    if (id = "" || InStr(id, "SWD\"))
        return false
    previous := [], attempted := [], success := false
    try {
        api := IsSet(backend) ? backend : CoreAudioBackend()
        loop 3
            previous.Push(api.DefaultId(flow, A_Index - 1))
        loop 3 {
            attempted.Push(A_Index - 1)
            hr := api.SetDefault(id, A_Index - 1)
            if (hr != 0)
                throw Error("role " (A_Index - 1) " HRESULT=" Format("{:08X}", hr & 0xFFFFFFFF))
        }
        loop 3 {
            if (StrLower(api.DefaultId(flow, A_Index - 1)) != StrLower(id))
                throw Error("default readback mismatch, role " (A_Index - 1))
        }
        ; Exact-ID routing must still be ACTIVE after all three role readbacks.
        ; Keep this check inside the transaction so a stale endpoint triggers
        ; the same conditional rollback as a failed role/readback.
        if requireActive && !AudioEndpointIdActive(id, flow, api)
            throw Error("endpoint became inactive during route verification")
        success := true
        return true
    } catch as e {
        LogMsg("audio route not verified: " e.Message, "WARN")
        return false
    } finally {
        if !success {
            loop attempted.Length {
                role := attempted[attempted.Length - A_Index + 1]
                oldId := previous[role + 1]
                try {
                    ; Do not overwrite another application's newer choice or
                    ; rewrite a role which this transaction never changed.
                    current := api.DefaultId(flow, role)
                    if (StrLower(current) != StrLower(id) || StrLower(current) = StrLower(oldId))
                        continue
                    hr := api.SetDefault(oldId, role)
                    if (hr != 0 || StrLower(api.DefaultId(flow, role)) != StrLower(oldId))
                        LogMsg("audio route rollback not verified, role " role, "ERROR")
                } catch as e {
                    LogMsg("audio route rollback failed: " e.Message, "ERROR")
                }
            }
        }
    }
}

AudioRouteMatches(name, backend?) {
    try {
        api := IsSet(backend) ? backend : CoreAudioBackend()
        id := FindAudioEndpointId(name, "0.0.0", api)
        if id = ""
            return false
        loop 3 {
            if StrLower(api.DefaultId(0, A_Index - 1)) != StrLower(id)
                return false
        }
        return true
    } catch {
        return false
    }
}

AudioEndpointAlive(name) {
    return FindAudioEndpointId(name, "0.0.0") != ""
}

RenderSwitchTo(name) {
    return SetAudioDefault(FindAudioEndpointId(name, "0.0.0"), 0)
}

FindCaptureEndpointId(name) {
    return FindAudioEndpointId(name, "0.0.1")
}
