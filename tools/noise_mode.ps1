# AirPods noise-control mode switch (Windows native, one-shot CLI)
# CLI (unchanged, called by AHK via RunWait):
#   powershell -NoProfile -ExecutionPolicy Bypass -File noise_mode.ps1 -Mac "XX:XX:XX:XX:XX:XX" -Mode off|anc|trans|adapt
#   exit 0 = success, exit 1 = failure.
# Every step is appended (crash-proof, incrementally) to
#   %LOCALAPPDATA%\BluetoothDeviceConnector\logs\noise_debug.log
#
# Transport facts (from librepods reverse-engineering docs, GPLv3; protocol facts only,
# implementation independently written - attribution in README):
#   * AAP runs on Classic Bluetooth L2CAP with fixed PSM 0x1001 (docs/AAP Definitions.md)
#     -> we connect directly; SDP lookup is only a fallback/diagnostic.
#   * Handshake packet 00 00 04 00 01 00 02 00 00 00 00 00 00 00 00 00 must be sent
#     right after connect, "or else the AirPods will not respond to any packets".
#   * Control command = 04 00 04 00 09 00 <id> <d1> <d2> <d3> <d4>  (12 bytes total).
#     ListeningMode id 0x0D: 1=off 2=ANC 3=transparency 4=adaptive.
#
# Fix history (live attempt records in noise_debug.log):
#   * AHK DevAddrString() passes the MAC byte-reversed (LSB-first formatting of the
#     raw BTH_ADDR uint64). This script normalizes the address by matching both byte
#     orders against the locally paired-device list (read-only Bthprops enumeration).
#   * Old payload was 11 bytes (protocol is 12: identifier + data1..data4).
#   * Old WSADATA struct was misdeclared (fixed arrays as single chars -> ~40 bytes
#     instead of ~400) causing a buffer overrun inside WSAStartup.
#   * Old SDP-first flow failed 10108 on the reversed (nonexistent) address.
#
# PLATFORM LIMITATION discovered 2026-08-19 (see log, probes 1-3):
#   On Windows, the Winsock BTHPROTO_L2CAP socket provider is non-functional for
#   user-mode apps: even a purely LOCAL bind() on an L2CAP socket fails instantly
#   with WSAENETDOWN 10050, while the RFCOMM provider passes address validation.
#   connect() to ANY PSM (incl. invalid 0x1000 and stack-owned 0x0001) of the
#   connected AirPods returns the same instant 10050 - the request never goes
#   on-air. This is why MagicPods (the commercial Windows AirPods app) ships an
#   unsigned KERNEL driver ("MagicAAP", needs Windows test mode) for noise control,
#   and why Qt's QBluetoothSocket does not support L2CAP on Windows. The AAP
#   control channel exists on the AirPods (SDP shows service "AAP Server"), but a
#   plain PowerShell process cannot reach it. This script keeps the full connect
#   strategy so it starts working on systems where user-mode L2CAP is available,
#   and it fails fast with an explicit diagnosis otherwise.
param(
    [Parameter(Mandatory=$true)][string]$Mac,
    [Parameter(Mandatory=$true)][ValidateSet("off","anc","trans","adapt")][string]$Mode
)
$ErrorActionPreference = "Stop"

$logDir = Join-Path $env:LOCALAPPDATA "BluetoothDeviceConnector\logs"
$logFile = Join-Path $logDir "noise_debug.log"
try { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } catch {}
function Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    try { Add-Content -Path $logFile -Value $line -Encoding UTF8 } catch {}
    Write-Output $line
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public class AirPodsL2Cap {
    // ---- constants ----
    const int AF_BTH = 32;
    const int SOCK_STREAM = 1;
    const int BTHPROTO_L2CAP = 0x0100;
    const int NS_BTH = 16;
    const int LUP_RETURN_NAME = 0x0010;
    const int LUP_RETURN_ADDR = 0x0100;
    const int SOL_SOCKET = 0xFFFF;
    const int SO_RCVTIMEO = 0x1006;
    const int FIXED_PSM = 0x1001;   // Apple AAP L2CAP PSM per librepods docs

    public static string LogPath = "";
    public static List<string> Trace = new List<string>();
    static void T(string s) {
        Trace.Add(s);
        try {
            if (LogPath.Length > 0)
                File.AppendAllText(LogPath,
                    "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + "] " + s + "\r\n",
                    Encoding.UTF8);
        } catch {}
    }
    static string Hex(byte[] b, int n) {
        var sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.Append(b[i].ToString("X2")).Append(" ");
        return sb.ToString().Trim();
    }

    [DllImport("ws2_32.dll")] static extern int WSAStartup(short v, byte[] data);
    [DllImport("ws2_32.dll")] static extern int WSACleanup();
    [DllImport("ws2_32.dll")] static extern int WSAGetLastError();
    [DllImport("ws2_32.dll")] static extern UIntPtr socket(int af, int type, int proto);
    [DllImport("ws2_32.dll")] static extern int connect(UIntPtr s, byte[] name, int namelen);
    [DllImport("ws2_32.dll")] static extern int send(UIntPtr s, byte[] buf, int len, int flags);
    [DllImport("ws2_32.dll")] static extern int recv(UIntPtr s, byte[] buf, int len, int flags);
    [DllImport("ws2_32.dll")] static extern int shutdown(UIntPtr s, int how);
    [DllImport("ws2_32.dll")] static extern int closesocket(UIntPtr s);
    [DllImport("ws2_32.dll")] static extern int setsockopt(UIntPtr s, int level, int optname, ref int val, int len);
    [DllImport("ws2_32.dll")] static extern int bind(UIntPtr s, byte[] name, int namelen);
    static bool Invalid(UIntPtr s) { return s == (UIntPtr)~(ulong)0 || s == UIntPtr.Zero; }

    // Local-only health probe of the Winsock L2CAP provider: bind() to port 0 never
    // touches any remote device. 10050 here (RFCOMM gives 10049 instead) means the
    // provider is dead in user mode and no connect strategy can succeed.
    public static string L2CapProviderCheck() {
        UIntPtr s = socket(AF_BTH, SOCK_STREAM, BTHPROTO_L2CAP);
        if (Invalid(s)) return "socket err=" + WSAGetLastError();
        byte[] la = new byte[40];
        BitConverter.GetBytes((short)AF_BTH).CopyTo(la, 0);
        BitConverter.GetBytes((int)0).CopyTo(la, 32);
        int rc = bind(s, la, la.Length);
        int err = rc == 0 ? 0 : WSAGetLastError();
        closesocket(s);
        if (rc == 0) return "alive";
        return "bind err=" + err + (err == 10050 ? " (WSAENETDOWN: user-mode L2CAP provider not functional on this system)" : "");
    }

    // ---- Bluetooth device enumeration (read-only, cached; no radio inquiry) ----
    [StructLayout(LayoutKind.Sequential)]
    struct BLUETOOTH_DEVICE_SEARCH_PARAMS {
        public int dwSize;
        public bool fReturnAuthenticated;
        public bool fReturnRemembered;
        public bool fReturnUnknown;
        public bool fReturnUnconnected;
        public bool fIssueInquiry;
        public byte cTimeoutMultiplier;
        public IntPtr hRadio;
    }
    [DllImport("irprops.cpl", CharSet = CharSet.Unicode)]
    static extern IntPtr BluetoothFindFirstDevice(ref BLUETOOTH_DEVICE_SEARCH_PARAMS p, byte[] di);
    [DllImport("irprops.cpl", CharSet = CharSet.Unicode)]
    static extern bool BluetoothFindNextDevice(IntPtr h, byte[] di);
    [DllImport("irprops.cpl")]
    static extern bool BluetoothFindDeviceClose(IntPtr h);
    [DllImport("irprops.cpl", CharSet = CharSet.Unicode)]
    static extern uint BluetoothGetDeviceInfo(IntPtr hRadio, byte[] di);
    const int BDI_SIZE = 560; // sizeof(BLUETOOTH_DEVICE_INFO) on x64

    public class BtDev { public ulong Addr; public int ConnFlag; public string Name; }

    public static List<BtDev> EnumDevices() {
        var list = new List<BtDev>();
        var p = new BLUETOOTH_DEVICE_SEARCH_PARAMS();
        p.dwSize = Marshal.SizeOf(typeof(BLUETOOTH_DEVICE_SEARCH_PARAMS));
        p.fReturnAuthenticated = true;
        p.fReturnRemembered = true;
        p.fReturnUnknown = false;
        p.fReturnUnconnected = true;
        p.fIssueInquiry = false;
        p.cTimeoutMultiplier = 1;
        p.hRadio = IntPtr.Zero;
        byte[] di = new byte[BDI_SIZE];
        BitConverter.GetBytes(BDI_SIZE).CopyTo(di, 0);
        IntPtr h = BluetoothFindFirstDevice(ref p, di);
        if (h == IntPtr.Zero) { T("enum: BluetoothFindFirstDevice failed err=" + Marshal.GetLastWin32Error()); return list; }
        try {
            do {
                var d = new BtDev();
                d.Addr = BitConverter.ToUInt64(di, 8);          // BTH_ADDR @8
                d.ConnFlag = BitConverter.ToInt32(di, 20);      // flags @20, nonzero = connected
                d.Name = Marshal.PtrToStringUni(Marshal.UnsafeAddrOfPinnedArrayElement(di, 64));
                list.Add(d);
            } while (BluetoothFindNextDevice(h, di));
        } finally { BluetoothFindDeviceClose(h); }
        T("enum: " + list.Count + " remembered devices");
        return list;
    }

    // live refresh of the fConnected flag for one address (0 = ERROR_SUCCESS)
    public static int RefreshConnected(ulong addr) {
        byte[] di = new byte[BDI_SIZE];
        BitConverter.GetBytes(BDI_SIZE).CopyTo(di, 0);
        BitConverter.GetBytes(addr).CopyTo(di, 8);
        uint err = BluetoothGetDeviceInfo(IntPtr.Zero, di);
        if (err != 0) return (int)err;
        return BitConverter.ToInt32(di, 20);
    }

    static string AddrToStr(ulong a) {
        byte[] b = BitConverter.GetBytes(a);
        return string.Format("{0:X2}:{1:X2}:{2:X2}:{3:X2}:{4:X2}:{5:X2}", b[5], b[4], b[3], b[2], b[1], b[0]);
    }

    static ulong ParseMsb(string mac) {   // first pair = most significant byte
        ulong v = 0;
        foreach (string part in mac.Split(':', '-'))
            v = (v << 8) | ulong.Parse(part, System.Globalization.NumberStyles.HexNumber);
        return v;
    }
    static string ReverseMac(string mac) {
        var p = mac.Split(':', '-');
        Array.Reverse(p);
        return string.Join(":", p);
    }

    // Resolve the real BTH_ADDR numeric from a MAC string that may be byte-reversed
    // (AHK DevAddrString formats LSB-first). Both orders are checked against the
    // locally remembered device list; a connected match wins.
    public static ulong ResolveAddr(string mac) {
        ulong msbFirst = ParseMsb(mac);             // correct if caller passed true MAC
        ulong lsbFirst = ParseMsb(ReverseMac(mac)); // correct if caller passed reversed MAC
        T("resolve: input=" + mac + " msbFirst=" + AddrToStr(msbFirst) + " lsbFirst=" + AddrToStr(lsbFirst));
        List<BtDev> devs = EnumDevices();
        BtDev hitM = null, hitL = null;
        foreach (BtDev d in devs) {
            if (d.Addr == msbFirst && hitM == null) hitM = d;
            if (d.Addr == lsbFirst && hitL == null) hitL = d;
        }
        if (hitM != null && hitL != null) {
            var pick = (hitM.ConnFlag != 0) ? hitM : hitL;
            T("resolve: both orders known devices, picked connected one " + AddrToStr(pick.Addr));
            return pick.Addr;
        }
        if (hitM != null) { T("resolve: msbFirst matches device '" + hitM.Name + "' conn=" + hitM.ConnFlag); return hitM.Addr; }
        if (hitL != null) { T("resolve: lsbFirst matches device '" + hitL.Name + "' conn=" + hitL.ConnFlag); return hitL.Addr; }
        T("resolve: no remembered device matched either order; assuming input was reversed (AHK style)");
        return lsbFirst;
    }

    // ---- SDP fallback (only used when fixed-PSM connect fails) ----
    // Raw-pointer reads are range-checked against the result buffer: never dereference
    // anything the NS provider may have left outside it (a previous version crashed
    // the whole powershell process with AccessViolationException here).
    [DllImport("ws2_32.dll", CharSet = CharSet.Unicode)]
    static extern int WSALookupServiceBeginW(ref WSAQUERYSETW q, int flags, out IntPtr h);
    [DllImport("ws2_32.dll", CharSet = CharSet.Unicode)]
    static extern int WSALookupServiceNextW(IntPtr h, int flags, ref int len, IntPtr buf);
    [DllImport("ws2_32.dll")]
    static extern int WSALookupServiceEnd(IntPtr h);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WSAQUERYSETW {
        public int dwSize; public string lpszServiceInstanceName; public IntPtr lpServiceClassId;
        public IntPtr lpVersion; public string lpszComment; public int dwNameSpace;
        public IntPtr lpNSProviderId; public string lpszContext; public int dwNumberOfProtocols;
        public IntPtr lpafpProtocols; public string lpszQueryString; public int dwNumberOfCsAddrs;
        public IntPtr lpcsaBuffer; public int dwOutputFlags; public IntPtr lpBlob;
    }
    const int SDP_BUF = 8192;

    // returns PSM (>0) or -1; logs every service it sees when browse=true
    static int SdpQuery(ulong addr, bool browse, Guid svc) {
        IntPtr pGuid = IntPtr.Zero;
        IntPtr h;
        var q = new WSAQUERYSETW();
        q.dwSize = Marshal.SizeOf(typeof(WSAQUERYSETW));
        if (!browse) {
            pGuid = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Guid)));
            Marshal.StructureToPtr(svc, pGuid, false);
            q.lpServiceClassId = pGuid;
        }
        q.dwNameSpace = NS_BTH;
        q.lpszContext = "(" + AddrToStr(addr) + ")";   // MSDN: BT address string, parens form
        int flags = LUP_RETURN_NAME | LUP_RETURN_ADDR;
        int rc = WSALookupServiceBeginW(ref q, flags, out h);
        if (pGuid != IntPtr.Zero) Marshal.FreeHGlobal(pGuid);
        if (rc != 0) { T("sdp: begin(" + (browse ? "browse" : "uuid") + ") failed err=" + WSAGetLastError()); return -1; }
        int found = -1;
        IntPtr buf = Marshal.AllocHGlobal(SDP_BUF);
        try {
            int n = 0;
            while (n < 8) {
                int len = SDP_BUF;
                Marshal.WriteInt32(buf, Marshal.SizeOf(typeof(WSAQUERYSETW)));
                rc = WSALookupServiceNextW(h, flags, ref len, buf);
                if (rc != 0) {
                    int e = WSAGetLastError();
                    if (e != 10110 && e != 10108) T("sdp: next err=" + e);  // 10110=WSA_E_NO_MORE is the normal end
                    break;
                }
                string name = SafeReadString(buf, 8, len);
                int port = ReadPortFromResult(buf, len, addr);
                T("sdp: service name='" + (name ?? "?") + "' psm=" + port);
                if (found < 0 && port > 0) found = port;
                n++;
                if (!browse) break;   // UUID query: first result is enough
            }
        } finally {
            Marshal.FreeHGlobal(buf);
            WSALookupServiceEnd(h);
        }
        return found;
    }

    static string SafeReadString(IntPtr buf, int off, int bufLen) {
        try {
            IntPtr p = Marshal.ReadIntPtr(buf, off);
            if (p == IntPtr.Zero) return null;
            long lo = buf.ToInt64(), hi = buf.ToInt64() + bufLen - 4;
            if (p.ToInt64() < lo || p.ToInt64() > hi) { T("sdp: string ptr 0x" + p.ToString("X") + " outside buffer"); return null; }
            return Marshal.PtrToStringUni(p);
        } catch { return null; }
    }

    // WSAQUERYSETW raw x64 layout: dwNumberOfCsAddrs@88, lpcsaBuffer@96.
    // CSADDR_INFO: Local@0, Remote@8. SOCKADDR_BTH: family@0(2), btAddr@8, guid@16, port@32.
    // If pointer chasing fails (provider layout surprises), fall back to scanning the
    // raw buffer for the device's btAddr byte pattern; port sits 24 bytes after it.
    static int ReadPortFromResult(IntPtr buf, int bufLen, ulong wantAddr) {
        int nAddrs = Marshal.ReadInt32(buf, 88);
        IntPtr pCsa = Marshal.ReadIntPtr(buf, 96);
        long lo = buf.ToInt64(), hi = buf.ToInt64() + bufLen - 40;
        if (nAddrs >= 1 && pCsa != IntPtr.Zero && pCsa.ToInt64() >= lo && pCsa.ToInt64() <= hi) {
            IntPtr remote = Marshal.ReadIntPtr(pCsa, 8);
            if (remote != IntPtr.Zero && remote.ToInt64() >= lo && remote.ToInt64() <= hi) {
                int family = Marshal.ReadInt16(remote, 0);
                int port = Marshal.ReadInt32(remote, 32);
                if (family == AF_BTH) return port;
                T("sdp: sockaddr family=" + family + " (not AF_BTH)");
            } else if (remote != IntPtr.Zero) {
                T("sdp: remote 0x" + remote.ToString("X") + " outside buffer");
            }
        } else if (pCsa != IntPtr.Zero) {
            T("sdp: lpcsa 0x" + pCsa.ToString("X") + " outside buffer (nAddrs=" + nAddrs + ")");
        }
        // scan: find btAddr little-endian bytes inside buffer
        byte[] raw = new byte[bufLen];
        Marshal.Copy(buf, raw, 0, bufLen);
        byte[] addr = BitConverter.GetBytes(wantAddr);
        for (int i = 8; i + 32 <= bufLen; i++) {
            bool m = true;
            for (int j = 0; j < 6; j++) if (raw[i + j] != addr[j]) { m = false; break; }
            if (m && BitConverter.ToInt16(raw, i - 8) == AF_BTH) {
                int p = BitConverter.ToInt32(raw, i + 24);
                T("sdp: scan found SOCKADDR_BTH at +" + (i - 8) + " port=" + p);
                return p;
            }
        }
        T("sdp: no SOCKADDR_BTH in result buffer");
        return -1;
    }

    static byte[] BuildSockAddrBth(ulong addr, int psm, Guid guid) {
        byte[] sa = new byte[40];                       // sizeof(SOCKADDR_BTH)
        BitConverter.GetBytes((short)AF_BTH).CopyTo(sa, 0);
        BitConverter.GetBytes(addr).CopyTo(sa, 8);      // BTH_ADDR numeric, LE bytes
        if (psm == 0) {                                 // port 0 + serviceClassId = stack-side SDP resolve
            byte[] g = guid.ToByteArray();
            Array.Copy(g, 0, sa, 16, 16);
        }
        BitConverter.GetBytes(psm).CopyTo(sa, 32);
        return sa;
    }

    public static string SendCommand(string mac, byte[] handshake, byte[] payload) {
        byte[] wsadata = new byte[512];                 // proper WSADATA sink (sizeof=408)
        if (WSAStartup(0x0202, wsadata) != 0) throw new Exception("WSAStartup failed err=" + WSAGetLastError());
        try {
            string prov = L2CapProviderCheck();
            T("l2cap provider check: " + prov);
            if (prov != "alive")
                throw new Exception("Winsock L2CAP provider not available in user mode (" + prov + "); " +
                    "Windows needs a kernel driver (e.g. MagicPods' MagicAAP) for AirPods noise control - " +
                    "see noise_debug.log probes");

            ulong addr = ResolveAddr(mac);
            T("resolved btAddr=0x" + addr.ToString("X12") + " (" + AddrToStr(addr) + ")");
            int live = RefreshConnected(addr);
            T("live fConnected flag=" + live);

            Guid svc = new Guid("74ec2172-0bad-4d01-8f77-997b2be0722a");
            // connect strategies, first success wins:
            //   A) port=0 + serviceClassId -> the stack resolves the PSM via SDP itself
            //      (this is what QBluetoothSocket::connectToService does on Linux/Qt)
            //   B) fixed PSM 0x1001 (documented Apple AAP PSM)
            //   C) manual SDP query for the AAP Server record, then connect to its PSM
            UIntPtr sock = UIntPtr.Zero;
            int usedPsm = 0;
            string how = "";
            int lastErr = 0;
            int[,] tries = new int[,] { { 0, 0 }, { FIXED_PSM, 1 } };
            for (int t = 0; t < 2 && Invalid(sock); t++) {
                int psm = tries[t, 0];
                UIntPtr s = socket(AF_BTH, SOCK_STREAM, BTHPROTO_L2CAP);
                if (Invalid(s)) { lastErr = WSAGetLastError(); T("socket() failed err=" + lastErr); continue; }
                byte[] sa = BuildSockAddrBth(addr, psm, svc);
                if (connect(s, sa, sa.Length) != 0) {
                    lastErr = WSAGetLastError();
                    T("connect " + (psm == 0 ? "by-serviceClassId" : "psm 0x" + psm.ToString("X")) + " failed err=" + lastErr);
                    closesocket(s);
                    continue;
                }
                sock = s;
                usedPsm = psm;
                how = (psm == 0) ? "serviceClassId(stack-resolved)" : "psm-0x" + psm.ToString("X");
                T("connect " + how + " OK");
            }
            if (Invalid(sock)) {
                // C) manual SDP
                int psm = SdpQuery(addr, false, svc);
                if (psm > 0) {
                    UIntPtr s = socket(AF_BTH, SOCK_STREAM, BTHPROTO_L2CAP);
                    if (!Invalid(s)) {
                        byte[] sa = BuildSockAddrBth(addr, psm, svc);
                        if (connect(s, sa, sa.Length) == 0) {
                            sock = s; usedPsm = psm; how = "sdp-psm-" + psm;
                            T("connect " + how + " OK");
                        } else {
                            lastErr = WSAGetLastError();
                            T("connect sdp psm " + psm + " failed err=" + lastErr);
                            closesocket(s);
                        }
                    }
                }
            }
            if (Invalid(sock)) throw new Exception("L2CAP connect failed (last err=" + lastErr + ")");

            try {
                int rcvto = 600;
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, ref rcvto, 4);

                // handshake is mandatory: without it AirPods ignore everything
                SendAll(sock, handshake, "handshake");
                byte[] rbuf = new byte[256];
                int n = recv(sock, rbuf, rbuf.Length, 0);
                T("recv after handshake: n=" + n + (n > 0 ? " data=" + Hex(rbuf, Math.Min(n, 48)) : " err=" + WSAGetLastError()));

                // the actual control command (12 bytes)
                SendAll(sock, payload, "command");
                n = recv(sock, rbuf, rbuf.Length, 0);
                T("recv after command: n=" + n + (n > 0 ? " data=" + Hex(rbuf, Math.Min(n, 48)) : " err=" + WSAGetLastError()));

                shutdown(sock, 1);
                return "OK addr=" + AddrToStr(addr) + " via=" + how + " sent=" + payload.Length + "B";
            } finally {
                closesocket(sock);
            }
        } finally {
            WSACleanup();
        }
    }

    static void SendAll(UIntPtr s, byte[] data, string tag) {
        int off = 0;
        while (off < data.Length) {
            byte[] chunk = new byte[data.Length - off];
            Array.Copy(data, off, chunk, 0, chunk.Length);
            int n = send(s, chunk, chunk.Length, 0);
            if (n < 0) throw new Exception("send(" + tag + ") failed err=" + WSAGetLastError());
            off += n;
        }
        T("sent " + tag + " (" + data.Length + "B): " + Hex(data, data.Length));
    }
}
'@

# Handshake: mandatory per AAP docs ("or else the AirPods will not respond to any packets")
$handshake = [byte[]](0x00,0x00,0x04,0x00,0x01,0x00,0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)

# Control command: 04 00 04 00 09 00 <id> <mode> 00 00 00 00  (12 bytes)
$modeByte = @{ "off" = 1; "anc" = 2; "trans" = 3; "adapt" = 4 }[$Mode]
$payload  = [byte[]](0x04,0x00,0x04,0x00,0x09,0x00,0x0D,$modeByte,0x00,0x00,0x00,0x00)

Log ("run start mac=" + $Mac + " mode=" + $Mode + " payload=" + (($payload | ForEach-Object { $_.ToString("X2") }) -join " "))
[AirPodsL2Cap]::LogPath = $logFile
try {
    $r = [AirPodsL2Cap]::SendCommand($Mac, $handshake, $payload)
    foreach ($line in [AirPodsL2Cap]::Trace) { Write-Output $line }
    Log ("RESULT " + $r)
    exit 0
} catch {
    foreach ($line in [AirPodsL2Cap]::Trace) { Write-Output $line }
    Log ("RESULT FAIL: " + $_.Exception.Message)
    exit 1
}
