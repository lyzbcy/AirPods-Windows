; Privacy-first diagnostics. No discovery inquiry, connection, pairing or routing writes.
; Persistent device identifiers are used only as in-memory keys, never emitted.
DiagnosticSession() {
    static value := "s" Format("{:08X}", Random(0, 0xFFFFFFFF))
    return value
}

DiagnosticAlias(kind, value) {
    static aliases := Map(), next := Map()
    if value = ""
        return "none"
    normalized := StrLower(kind = "device" ? RegExReplace(value, "[:-]", "") : value)
    key := kind "|" normalized
    if !aliases.Has(key) {
        if aliases.Count >= 512
            return kind "#overflow"
        serial := next.Get(kind, 0) + 1
        next[kind] := serial
        aliases[key] := kind "#" serial
    }
    return aliases[key]
}

DiagnosticPrivateNames(value := "") {
    static names := Map()
    if (StrLen(value) >= 2 && names.Count < 128)
        names[value] := true
    return names
}

DiagnosticReplacePattern(text, pattern, kind) {
    start := 1
    while RegExMatch(text, pattern, &match, start) {
        replacement := DiagnosticAlias(kind, match[0])
        text := SubStr(text, 1, match.Pos - 1) replacement SubStr(text, match.Pos + match.Len)
        start := match.Pos + StrLen(replacement)
    }
    return text
}

DiagnosticSanitize(text) {
    ; Drop legacy arbitrary RPC/JS payloads and custom device-label lists first.
    text := RegExReplace(text, "im)(rpc:\s*(?:setprio|sendfeedback|sendissue))[^\r\n]*", "$1 details=[redacted]")
    text := RegExReplace(text, "im)\[JS-ERROR\][^\r\n]*", "[JS-ERROR] details=[redacted]")
    text := RegExReplace(text, "im)priority updated:[^\r\n]*", "priority updated: names=[redacted]")
    text := RegExReplace(text, "im)noise mode [^\r\n]*->[^\r\n]*", "noise mode target=[redacted]")
    text := RegExReplace(text, "i)Bearer\s+[A-Za-z0-9._+/=-]+", "Bearer [redacted]")
    text := RegExReplace(text, "\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", "[token]")
    text := RegExReplace(text, 'i)((?:key|token|secret|password|authorization)\s*[=:]\s*)[^&\s"<>]+', "$1[redacted]")
    ; Conservatively redact paths including spaces. Keep explicit numeric status fields.
    text := RegExReplace(text, 'im)(?:[a-z]:\\|\\\\)[^\r\n"<>]*?(?=\s+(?:status|hr|error|reason|state|code|HRESULT)=|[\r\n"<>]|$)', "[path]")
    text := RegExReplace(text, 'i)\b(?:BTHENUM|BTHLEDEVICE|SWD|USB)\\[^\s"<>]+', "[pnp-id]")
    text := DiagnosticReplacePattern(text, "i)\{0\.0\.[01]\.[0-9a-f]{8}\}\.\{[0-9a-f-]{36}\}", "endpoint")
    text := DiagnosticReplacePattern(text, "i)\{?[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\}?", "object")
    text := DiagnosticReplacePattern(text, "i)(?<![0-9a-f])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![0-9a-f])", "device")
    text := DiagnosticReplacePattern(text, "i)(?<![0-9a-f])[0-9a-f]{12}(?![0-9a-f])", "device")
    text := RegExReplace(text, "i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "[email]")
    text := RegExReplace(text, "(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)", "[phone]")
    text := RegExReplace(text, "\b(?:\d{1,3}\.){3}\d{1,3}\b", "[ip]")
    text := RegExReplace(text, "i)\bS-\d-(?:\d+-)+\d+\b", "[sid]")
    for name in DiagnosticPrivateNames()
        text := StrReplace(text, name, "[device-name]", true)
    return RegExReplace(text, "[\x00-\x08\x0B\x0C\x0E-\x1F]", " ")
}

DiagnosticNameHint(name) {
    n := StrLower(name)
    if InStr(n, "airpods")
        return InStr(n, "pro") ? "airpods-pro" : (InStr(n, "max") ? "airpods-max" : "airpods")
    return InStr(n, "beats") ? "beats" : (n = "" ? "empty" : "other")
}

DiagnosticNewStats(mode) {
    return {mode: mode, status: "ok", raw: 0, accepted: 0, rejected: 0,
        unknownClass: 0, nonAudio: 0, connected: 0, remembered: 0, authenticated: 0,
        refreshErrors: 0, refreshError: 0, error: 0, nextError: 0, elapsedMs: 0, capped: false}
}

DiagnosticTrackRow(stats, rows, info, refreshCode := 0) {
    name := StrGet(info.Ptr + 64, "UTF-16")
    cod := NumGet(info, 16, "uint")
    connected := NumGet(info, 20, "uint") != 0
    remembered := NumGet(info, 24, "uint") != 0
    authenticated := NumGet(info, 28, "uint") != 0
    accepted := IsAudioCandidate(cod, name)
    DiagnosticPrivateNames(name)
    stats.raw++, stats.connected += connected, stats.remembered += remembered
    stats.authenticated += authenticated, stats.refreshErrors += refreshCode != 0
    if refreshCode != 0
        stats.refreshError := refreshCode
    if accepted {
        stats.accepted++
        if rows.Length < 16
            rows.Push({alias: DiagnosticAlias("device", Format("{:012X}", NumGet(info, 8, "uint64"))),
                nameHint: DiagnosticNameHint(name), cod: cod, connected: connected,
                remembered: remembered, authenticated: authenticated})
    } else {
        stats.rejected++
        if cod = 0
            stats.unknownClass++
        else
            stats.nonAudio++
    }
}

DiagnosticDiscoveryText(stats, rows) {
    text := ("discovery mode=" stats.mode " status=" stats.status " raw=" stats.raw
        " accepted=" stats.accepted " rejected=" stats.rejected " filteredUnknownClass=" stats.unknownClass
        " filteredNonAudio=" stats.nonAudio " connected=" stats.connected " remembered=" stats.remembered
        " authenticated=" stats.authenticated " refreshErrors=" stats.refreshErrors " refreshError=" stats.refreshError " error=" stats.error
        " nextError=" stats.nextError " capped=" stats.capped " inquiry=off coverage=classic-only")
    detail := ""
    for row in rows
        detail .= ("`n  " row.alias " nameHint=" row.nameHint " cod=" Format("0x{:06X}", row.cod)
            " authenticated=" row.authenticated " remembered=" row.remembered " connected=" row.connected)
    return text Sort(detail) (stats.accepted > rows.Length ? "`n  details=bounded" : "")
}

DiagnosticObservationState() {
    static state := {signature: "", text: "", tick: 0}
    return state
}

DiagnosticObserveDiscovery(stats, rows, tick?) {
    state := DiagnosticObservationState()
    signature := DiagnosticDiscoveryText(stats, rows)
    now := IsSet(tick) ? tick : A_TickCount
    state.text := signature
    ; Only a state/result change or five-minute heartbeat produces a log line.
    if signature = state.signature && now - state.tick < 300000
        return false
    state.signature := signature, state.tick := now
    LogMsg("diagnostic schema=1 session=" DiagnosticSession() " " signature " elapsedMs=" stats.elapsedMs)
    return true
}

DiagnosticReadClassic(mode := "cached") {
    stats := DiagnosticNewStats(mode), rows := [], started := A_TickCount
    params := Buffer(40, 0), info := Buffer(560, 0)
    NumPut("uint", 40, params, 0), NumPut("uint", 1, params, 4)
    if mode = "cached" {
        NumPut("uint", 1, params, 8), NumPut("uint", 1, params, 16)
    }
    NumPut("uint", 560, info, 0)
    DllCall("SetLastError", "uint", 0)
    handle := DllCall("Bthprops.cpl\BluetoothFindFirstDevice", "ptr", params, "ptr", info, "ptr")
    if !handle {
        stats.error := A_LastError
        stats.status := stats.error = 259 ? "no_match" : "api_error"
    } else {
        try {
            loop {
                DiagnosticTrackRow(stats, rows, info)
                if stats.raw >= 128 {
                    stats.status := "partial", stats.capped := true
                    break
                }
                DllCall("SetLastError", "uint", 0)
                if !DllCall("Bthprops.cpl\BluetoothFindNextDevice", "ptr", handle, "ptr", info) {
                    stats.nextError := A_LastError
                    if stats.nextError != 259
                        stats.status := "partial"
                    break
                }
            }
        } finally DllCall("Bthprops.cpl\BluetoothFindDeviceClose", "ptr", handle)
    }
    stats.elapsedMs := A_TickCount - started
    return {stats: stats, rows: rows}
}

DiagnosticRadioSummary() {
    params := Buffer(4, 0), radio := 0, count := 0
    NumPut("uint", 4, params)
    DllCall("SetLastError", "uint", 0)
    handle := DllCall("Bthprops.cpl\BluetoothFindFirstRadio", "ptr", params, "ptr*", &radio, "ptr")
    errorCode := handle ? 0 : A_LastError
    if handle {
        try {
            loop {
                count++
                DllCall("CloseHandle", "ptr", radio)
                if count >= 8
                    break
                if !DllCall("Bthprops.cpl\BluetoothFindNextRadio", "ptr", handle, "ptr*", &radio)
                    break
            }
        } finally DllCall("Bthprops.cpl\BluetoothFindRadioClose", "ptr", handle)
    }
    ; Presence is not radio power. Do not infer that Bluetooth is switched on/off.
    return "radios visible=" count " error=" errorCode " power=unverified"
}

DiagnosticAudioSummary() {
    api := CoreAudioBackend(), text := ""
    loop 2 {
        flow := A_Index - 1, counts := Map(1, 0, 2, 0, 4, 0, 8, 0), hints := 0
        for row in api.Endpoints(flow, 15) {
            DiagnosticPrivateNames(row.name)
            counts[row.state] := counts.Get(row.state, 0) + 1
            if DiagnosticNameHint(row.name) != "other" && DiagnosticNameHint(row.name) != "empty"
                hints++
        }
        text .= ("`n  audio flow=" (flow = 0 ? "render" : "capture") " active=" counts[1]
            " disabled=" counts[2] " absent=" counts[4] " unplugged=" counts[8] " appleNameHints=" hints)
        loop 3 {
            role := A_Index - 1
            try id := DiagnosticAlias("endpoint", api.DefaultId(flow, role))
            catch
                id := "unavailable"
            text .= " role" role "=" id
        }
    }
    return text
}

class DiagnosticReadOnlyBackend {
    Classic(mode) => DiagnosticReadClassic(mode)
    Radios() => DiagnosticRadioSummary()
    Audio() => DiagnosticAudioSummary()
}

DiagnosticCollectFeedback(backend?) {
    global APP_VERSION
    started := A_TickCount
    try {
        api := IsSet(backend) ? backend : DiagnosticReadOnlyBackend()
        auth := api.Classic("authenticated"), cached := api.Classic("cached")
        text := ("=== Privacy diagnostic schema=1 session=" DiagnosticSession() " app=" APP_VERSION
            " os=" A_OSVersion " arch=" (A_PtrSize = 8 ? "x64" : "x86") " ==="
            "`n" DiagnosticDiscoveryText(auth.stats, auth.rows)
            "`n" DiagnosticDiscoveryText(cached.stats, cached.rows)
            "`n" api.Radios())
        try text .= api.Audio()
        catch as e
            text .= "`n  audio status=unavailable code=" (e.HasOwnProp("Number") ? e.Number : "unknown")
        hint := "candidates_present"
        if auth.stats.status = "api_error" || cached.stats.status = "api_error"
            hint := "classic_api_error"
        else if auth.stats.status = "partial" || cached.stats.status = "partial"
            hint := "classic_partial_result"
        else if auth.stats.accepted = 0 && cached.stats.accepted > 0
            hint := "authenticated_filter_gap"
        else if cached.stats.raw > 0 && cached.stats.accepted = 0
            hint := "candidate_filter_empty"
        else if cached.stats.accepted = 0
            hint := "no_cached_classic_candidate"
        text .= ("`n  observation=" hint " notRootCause=true elapsedMs=" (A_TickCount - started)
            "`n  identifiers=session-local names=category-only inquiry=off writes=none")
        return DiagnosticSanitize(text)
    } catch as e {
        return "=== Privacy diagnostic schema=1 status=unavailable code=" (e.HasOwnProp("Number") ? e.Number : "unknown") " ==="
    }
}
